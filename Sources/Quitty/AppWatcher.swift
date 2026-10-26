import AppKit
import ApplicationServices

/// C callback for every Accessibility notification; forwards to the owning `AppWatcher`.
private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let watcher = Unmanaged<AppWatcher>.fromOpaque(refcon).takeUnretainedValue()
    watcher.handle(notification: notification as String, element: element)
}

/// Watches the windows of a single running app through the Accessibility API
/// and reports when the app has no windows left.
final class AppWatcher {
    let app: NSRunningApplication
    var onLastWindowClosed: ((AppWatcher) -> Void)?

    private let appElement: AXUIElement
    private var observer: AXObserver?
    private var windows: [AXUIElement] = []
    private var pendingCheck: DispatchWorkItem?

    /// Delay before checking the window list after a window disappears. Covers
    /// apps that briefly destroy and recreate windows (full screen, tab moves).
    private static let checkDelay: TimeInterval = 0.6
    private static let maxCheckRetries = 3

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
    ]

    init(app: NSRunningApplication) {
        self.app = app
        appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 1.0)
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

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            let err = AXObserverAddNotification(created, appElement, name as CFString, refcon)
            guard err == .success || err == .notificationAlreadyRegistered else {
                for name in Self.appNotifications {
                    AXObserverRemoveNotification(created, appElement, name as CFString)
                }
                return false
            }
        }

        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
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
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        windows.removeAll()
        self.observer = nil
    }

    fileprivate func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            windows.removeAll { CFEqual($0, element) }
            scheduleCheck()
        default:
            // A window appeared or got focus: make sure we track it, and don't
            // quit an app that just opened a new window.
            pendingCheck?.cancel()
            pendingCheck = nil
            syncWindows()
        }
    }

    /// Starts watching every window the app currently reports.
    private func syncWindows() {
        guard let current = copyWindows() else { return }
        for window in current {
            watch(window)
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

    private func scheduleCheck(retry: Int = 0) {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.checkForRemainingWindows(retry: retry)
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.checkDelay, execute: work)
    }

    private func checkForRemainingWindows(retry: Int) {
        pendingCheck = nil
        guard !app.isTerminated else { return }
        guard let current = copyWindows() else {
            // The app didn't answer; ask again rather than guessing.
            if retry < Self.maxCheckRetries {
                scheduleCheck(retry: retry + 1)
            }
            return
        }
        if current.isEmpty {
            onLastWindowClosed?(self)
        } else {
            current.forEach(watch)
        }
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
}
