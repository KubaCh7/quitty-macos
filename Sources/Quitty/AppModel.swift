import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

/// An app shown in the "Never quit" list.
struct AppEntry: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
}

/// State behind the menu bar panel, plus the long-lived pieces of the app.
@MainActor
final class AppModel: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { settings.isEnabled = isEnabled }
    }
    @Published var autoCheckForUpdates: Bool {
        didSet { settings.autoCheckForUpdates = autoCheckForUpdates }
    }
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var excluded: Set<String>
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    let updater = Updater()

    private let settings = Settings.shared
    private let controller = QuitController()
    private var workspaceObservers: [NSObjectProtocol] = []
    private lazy var updateWindow = UpdateWindowController(updater: updater)

    private static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    var isActive: Bool { isEnabled && isTrusted }

    var statusText: String {
        if !isTrusted { return "Needs Accessibility access" }
        if !isEnabled { return "Paused" }
        return "Quits apps when you close their last window"
    }

    init() {
        _isEnabled = Published(initialValue: Settings.shared.isEnabled)
        _autoCheckForUpdates = Published(initialValue: Settings.shared.autoCheckForUpdates)
        _excluded = Published(initialValue: Settings.shared.excludedBundleIDs)
    }

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if isTrusted {
            controller.start()
        } else {
            waitForAccessibilityPermission()
        }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshApps() }
            })
        }
        refreshApps()

        updater.onUpdateFound = { [weak self] _ in self?.showUpdateWindow() }
        updater.startAutomaticChecks()
    }

    func stop() {
        controller.stop()
    }

    /// Re-reads state that can change outside Quitty while the panel is closed.
    func refresh() {
        isTrusted = AXIsProcessTrusted()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshApps()
    }

    /// Polls until the user grants Accessibility access in System Settings.
    private func waitForAccessibilityPermission() {
        Task {
            while !AXIsProcessTrusted() {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            isTrusted = true
            controller.start()
        }
    }

    // MARK: - Exclusions

    func isExcluded(_ bundleID: String) -> Bool {
        excluded.contains(bundleID)
    }

    func setExcluded(_ bundleID: String, _ isExcluded: Bool) {
        settings.setExcluded(bundleID, isExcluded)
        excluded = settings.excludedBundleIDs
        refreshApps()
    }

    func addExclusionFromFinder() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps Quitty should never quit"
        panel.prompt = "Never Quit"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier {
                settings.setExcluded(id, true)
            }
        }
        excluded = settings.excludedBundleIDs
        refreshApps()
    }

    /// Running apps plus anything already excluded, excluded ones first.
    private func refreshApps() {
        let workspace = NSWorkspace.shared
        let ownBundleID = Bundle.main.bundleIdentifier
        var entries: [String: AppEntry] = [:]

        for app in workspace.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != ownBundleID,
                  !Settings.alwaysExcluded.contains(id) else { continue }
            entries[id] = AppEntry(id: id, name: app.localizedName ?? id,
                                   icon: app.icon ?? workspace.icon(for: .application))
        }
        for id in excluded where entries[id] == nil {
            if let url = workspace.urlForApplication(withBundleIdentifier: id) {
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                entries[id] = AppEntry(id: id, name: name, icon: workspace.icon(forFile: url.path))
            } else {
                entries[id] = AppEntry(id: id, name: id, icon: workspace.icon(for: .application))
            }
        }

        apps = entries.values.sorted { lhs, rhs in
            let lhsExcluded = excluded.contains(lhs.id)
            if lhsExcluded != excluded.contains(rhs.id) {
                return lhsExcluded
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Settings

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        launchAtLogin = service.status == .enabled
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(Self.accessibilitySettingsURL)
    }

    /// Clears a stale Accessibility entry (left behind by an older build) and
    /// asks for access again.
    func resetAccessibilityPermission() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", bundleID]
        try? reset.run()
        reset.waitUntilExit()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    // MARK: - Updates

    func checkForUpdates() {
        Task { await updater.check(userInitiated: true) }
    }

    func showUpdateWindow() {
        updateWindow.show()
    }
}
