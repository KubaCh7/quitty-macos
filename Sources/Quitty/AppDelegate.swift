import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = QuitController()
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!

    private static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            controller.start()
        } else {
            waitForAccessibilityPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    /// Polls until the user grants Accessibility access in System Settings.
    private func waitForAccessibilityPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            if AXIsProcessTrusted() {
                self.controller.start()
                self.updateIcon()
            } else {
                self.waitForAccessibilityPermission()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Quitty")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !settings.isEnabled || !AXIsProcessTrusted()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "⚠️ Quitty potrzebuje dostępu (Dostępność)", action: nil, keyEquivalent: "")
            menu.addItem(item("Otwórz Ustawienia systemowe…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let enabled = item("Zamykaj aplikacje po zamknięciu ostatniego okna", #selector(toggleEnabled))
        enabled.state = settings.isEnabled ? .on : .off
        menu.addItem(enabled)

        let exclusions = NSMenuItem(title: "Wyjątki (nie zamykaj)", action: nil, keyEquivalent: "")
        exclusions.submenu = exclusionsMenu()
        menu.addItem(exclusions)

        let login = item("Uruchamiaj przy logowaniu", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Zakończ Quitty", #selector(quit), key: "q"))
    }

    private func exclusionsMenu() -> NSMenu {
        let menu = NSMenu()
        let ownBundleID = Bundle.main.bundleIdentifier

        // Running apps plus anything already excluded, keyed by bundle ID.
        var names: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != ownBundleID,
                  !Settings.alwaysExcluded.contains(id) else { continue }
            names[id] = app.localizedName ?? id
        }
        for id in settings.excludedBundleIDs where names[id] == nil {
            names[id] = Self.displayName(forBundleID: id)
        }

        let sorted = names.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        for (id, name) in sorted {
            let entry = item(name, #selector(toggleExclusion(_:)))
            entry.representedObject = id
            entry.state = settings.excludedBundleIDs.contains(id) ? .on : .off
            menu.addItem(entry)
        }
        if !sorted.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(item("Dodaj aplikację…", #selector(addExclusion)))

        let finder = NSMenuItem(title: "Finder jest zawsze pomijany", action: nil, keyEquivalent: "")
        finder.isEnabled = false
        menu.addItem(finder)
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private static func displayName(forBundleID id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        updateIcon()
    }

    @objc private func toggleExclusion(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.setExcluded(id, !settings.excludedBundleIDs.contains(id))
    }

    @objc private func addExclusion() {
        let panel = NSOpenPanel()
        panel.title = "Wybierz aplikacje, których Quitty ma nie zamykać"
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
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Nie udało się zmienić uruchamiania przy logowaniu"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(Self.accessibilitySettingsURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
