import AppKit
import ApplicationServices

/// Private but long-stable HIServices call that maps an Accessibility window
/// to its window server ID. Window managers like Rectangle and AltTab use it.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// C callback for every Accessibility notification; forwards to the owning `AppWatcher`.
private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<AppWatcher>.fromOpaque(refcon).takeUnretainedValue()
    watcher.handle(notification: notification as String, element: element)
}

/// Watches the windows of a single running app through the Accessibility API
/// and reports when the app's last window has been closed.
final class AppWatcher {
    let app: NSRunningApplication
    var onLastWindowClosed: ((AppWatcher) -> Void)?
    /// When the user last switched Spaces; entering full screen does that too.
    var lastSpaceChange: () -> Date = { .distantPast }

    private let appElement: AXUIElement
    private var observer: AXObserver?
    private var windows: [AXUIElement] = []
    private var pendingCheck: DispatchWorkItem?
    private var pendingCheckConfirms = false
    /// True once the app has shown a window, so apps that launch without one
    /// aren't quit straight away.
    private var hadWindows = false
    private var lastWindowGeometryChange = Date.distantPast

    /// Wait after a window disappears before reading the window list, which
    /// can still contain the closed window for a moment.
    private static let firstCheckDelay: TimeInterval = 0.1
    /// Wait before confirming that the app really has no windows left. Covers
    /// apps that briefly swap one window for another.
    private static let confirmDelay: TimeInterval = 0.2
    /// After a window moves, resizes or changes Space, give it this long to
    /// settle. Full screen and zoom animations briefly empty the window list.
    private static let settleTime: TimeInterval = 1.5
    private static let maxCheckRetries = 3

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]

    /// Windows that always keep an app open.
    private static let standardSubroles: Set<String> = [
        kAXStandardWindowSubrole,
        kAXDialogSubrole,
    ]

    /// Palettes and panels that never keep an app open on their own.
    private static let ignoredSubroles: Set<String> = [
        kAXFloatingWindowSubrole,
        kAXSystemFloatingWindowSubrole,
    ]

    init(app: NSRunningApplication) {
        self.app = app
        appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
    }

    deinit {
        stop()
    }

    /// Starts observing. Returns false when the app isn't ready to talk to
    /// Accessibility yet (e.g. it is still launching), so the caller can retry.
    func start() -> Bool {
        guard observer == nil else { return true }

        var created: AXObserver?
        guard AXObserverCreate(app.processIdentifier, axCallback, &created) == .success,
              let created else { return false }

        // Some apps don't support every notification; one is enough, and the
        // controller's polling covers the rest.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = 0
        for name in Self.appNotifications {
            let err = AXObserverAddNotification(created, appElement, name as CFString, refcon)
            if err == .success || err == .notificationAlreadyRegistered {
                registered += 1
            }
        }
        guard registered > 0 else { return false }

        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        syncWindows()
        return true
    }

    func stop() {
        pendingCheck?.cancel()
        pendingCheck = nil
        guard let observer else { return }
        for window in windows {
            for name in Self.windowNotifications {
                AXObserverRemoveNotification(observer, window, name as CFString)
            }
        }
        for name in Self.appNotifications {
            AXObserverRemoveNotification(observer, appElement, name as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        windows.removeAll()
        self.observer = nil
    }

    /// Checks the window list now, for apps whose notifications we may have missed.
    func poll() {
        scheduleCheck(after: 0, confirming: false)
    }

    fileprivate func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            lastWindowGeometryChange = Date()
            return
        case kAXUIElementDestroyedNotification:
            windows.removeAll { CFEqual($0, element) }
        default:
            syncWindows()
        }
        // Focus also moves when a window closes, so every notification is a
        // reason to look at the window list. A check never cancels one that
        // is already waiting to confirm.
        scheduleCheck(after: Self.firstCheckDelay, confirming: false)
    }

    /// Starts watching every window the app currently reports.
    private func syncWindows() {
        guard let current = copyWindows() else { return }
        current.forEach(watch)
        if hasOpenWindow(current) {
            hadWindows = true
        }
    }

    private func watch(_ window: AXUIElement) {
        guard let observer, !windows.contains(where: { CFEqual($0, window) }) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        guard err == .success || err == .notificationAlreadyRegistered else { return }
        windows.append(window)
        for name in [kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
    }

    private func scheduleCheck(after delay: TimeInterval, confirming: Bool, retry: Int = 0) {
        if pendingCheck != nil {
            guard confirming, !pendingCheckConfirms else { return }
            pendingCheck?.cancel()
        }
        let work = DispatchWorkItem { [weak self] in
            self?.check(confirming: confirming, retry: retry)
        }
        pendingCheck = work
        pendingCheckConfirms = confirming
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func check(confirming: Bool, retry: Int) {
        pendingCheck = nil
        pendingCheckConfirms = false
        guard !app.isTerminated else { return }
        guard let current = copyWindows() else {
            // The app didn't answer; ask again rather than guessing.
            if retry < Self.maxCheckRetries {
                scheduleCheck(after: Self.confirmDelay, confirming: confirming, retry: retry + 1)
            }
            return
        }
        current.forEach(watch)

        if hasOpenWindow(current) {
            hadWindows = true
            return
        }
        guard hadWindows else { return }

        let settling = remainingSettleTime()
        if confirming && settling == 0 {
            // Accessibility sometimes reports no windows for an app that is
            // busy. The window server is the second opinion: never quit an
            // app that still shows a window on screen.
            guard onScreenWindowIDs(visibleOnly: true).isEmpty else {
                hadWindows = true
                return
            }
            hadWindows = false
            onLastWindowClosed?(self)
        } else {
            scheduleCheck(after: max(Self.confirmDelay, settling), confirming: true)
        }
    }

    /// Seconds until recent window or Space changes have settled.
    private func remainingSettleTime() -> TimeInterval {
        let lastChange = max(lastWindowGeometryChange, lastSpaceChange())
        return max(0, Self.settleTime - Date().timeIntervalSince(lastChange))
    }

    private func hasOpenWindow(_ windows: [AXUIElement]) -> Bool {
        // Listing on-screen windows is comparatively slow, so only do it once
        // a window actually needs it.
        var onScreen: Set<CGWindowID>?
        return windows.contains { window in
            countsAsOpen(window) {
                if onScreen == nil {
                    onScreen = onScreenWindowIDs()
                }
                return onScreen!
            }
        }
    }

    /// Whether a window keeps the app open. Standard windows always do, even
    /// on another Space; minimized and full screen ones too. Floating palettes
    /// never do. Anything else (Steam's windows report an unknown subrole)
    /// counts only while it is actually visible.
    private func countsAsOpen(_ window: AXUIElement, onScreen: () -> Set<CGWindowID>) -> Bool {
        if boolAttribute(window, kAXMinimizedAttribute) == true || boolAttribute(window, "AXFullScreen") == true {
            return true
        }
        guard let subrole = stringAttribute(window, kAXSubroleAttribute) else { return true }
        if Self.standardSubroles.contains(subrole) {
            return true
        }
        if Self.ignoredSubroles.contains(subrole) {
            return false
        }
        var windowID: CGWindowID = 0
        if _AXUIElementGetWindow(window, &windowID) == .success, windowID != 0 {
            return onScreen().contains(windowID)
        }
        return !(stringAttribute(window, kAXTitleAttribute) ?? "").isEmpty
    }

    /// Window server IDs of this app's windows that are on screen right now.
    /// With `visibleOnly`, only normal-level windows that are opaque and big
    /// enough for someone to be looking at.
    private func onScreenWindowIDs(visibleOnly: Bool = false) -> Set<CGWindowID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var ids = Set<CGWindowID>()
        for info in list {
            guard info[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            if visibleOnly {
                let layer = info[kCGWindowLayer as String] as? Int ?? 0
                let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
                let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
                guard layer == 0, alpha > 0.01, bounds.width >= 50, bounds.height >= 50 else { continue }
            }
            ids.insert(id)
        }
        return ids
    }

    /// The app's windows (minimized and hidden ones included), or nil if the
    /// app couldn't be queried.
    private func copyWindows() -> [AXUIElement]? {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) {
        case .success:
            // An unexpected value means we don't know, not that there are no windows.
            return value as? [AXUIElement]
        case .noValue:
            return []
        default:
            return nil
        }
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
