import AppKit
import ApplicationServices

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

    private let appElement: AXUIElement
    private var observer: AXObserver?
    private var windows: [AXUIElement] = []
    private var pendingCheck: DispatchWorkItem?
    private var pendingCheckConfirms = false
    /// True once the app has shown a window, so apps that launch without one
    /// aren't quit straight away.
    private var hadWindows = false

    /// Wait after a window disappears before reading the window list, which
    /// can still contain the closed window for a moment.
    private static let firstCheckDelay: TimeInterval = 0.1
    /// Wait before confirming that the app really has no windows left. Covers
    /// apps that briefly swap one window for another.
    private static let confirmDelay: TimeInterval = 0.2
    private static let maxCheckRetries = 3

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]

    /// Window subroles that don't keep an app open on their own (palettes,
    /// invisible helper windows).
    private static let ignoredSubroles: Set<String> = [
        kAXFloatingWindowSubrole,
        kAXSystemFloatingWindowSubrole,
        kAXUnknownSubrole,
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
            AXObserverRemoveNotification(observer, window, kAXUIElementDestroyedNotification as CFString)
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
        if notification == kAXUIElementDestroyedNotification {
            windows.removeAll { CFEqual($0, element) }
        } else {
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
        if current.contains(where: countsAsOpen) {
            hadWindows = true
        }
    }

    private func watch(_ window: AXUIElement) {
        guard let observer, !windows.contains(where: { CFEqual($0, window) }) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        if err == .success || err == .notificationAlreadyRegistered {
            windows.append(window)
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

        if current.contains(where: countsAsOpen) {
            hadWindows = true
        } else if hadWindows {
            if confirming {
                hadWindows = false
                onLastWindowClosed?(self)
            } else {
                scheduleCheck(after: Self.confirmDelay, confirming: true)
            }
        }
    }

    /// Whether a window keeps the app open. Minimized windows count; floating
    /// palettes and invisible helper windows don't.
    private func countsAsOpen(_ window: AXUIElement) -> Bool {
        if boolAttribute(window, kAXMinimizedAttribute) == true {
            return true
        }
        guard let subrole = stringAttribute(window, kAXSubroleAttribute) else { return true }
        return !Self.ignoredSubroles.contains(subrole)
    }

    /// The app's windows (minimized and hidden ones included), or nil if the
    /// app couldn't be queried.
    private func copyWindows() -> [AXUIElement]? {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) {
        case .success:
            return (value as? [AXUIElement]) ?? []
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
