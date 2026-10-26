import AppKit

/// Keeps an `AppWatcher` for every running app and quits an app once its last
/// window is closed.
final class QuitController {
    private var watchers: [pid_t: AppWatcher] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var lastSpaceChange = Date.distantPast
    private(set) var isRunning = false

    /// Apps get this long after launch before they can be quit, so splash
    /// screens that close before the main window opens don't kill the app.
    private static let launchGracePeriod: TimeInterval = 3
    private static let attachRetryDelay: TimeInterval = 0.5
    private static let maxAttachAttempts = 20
    /// How often the frontmost app's windows are checked, in case it doesn't
    /// send the Accessibility notifications we rely on.
    private static let pollInterval: TimeInterval = 0.3

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.attach(app)
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.detach(app)
            },
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.lastSpaceChange = Date()
            },
        ]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            attach(app)
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.pollFrontmostApp()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        watchers.values.forEach { $0.stop() }
        watchers.removeAll()
    }

    private func attach(_ app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard isRunning, !app.isTerminated, watchers[pid] == nil,
              pid != ProcessInfo.processInfo.processIdentifier else { return }

        let watcher = AppWatcher(app: app)
        watcher.onLastWindowClosed = { [weak self] in self?.lastWindowClosed(in: $0) }
        watcher.lastSpaceChange = { [weak self] in self?.lastSpaceChange ?? .distantPast }
        if watcher.start() {
            watchers[pid] = watcher
        } else if attempt < Self.maxAttachAttempts {
            // Freshly launched apps often aren't ready for Accessibility yet.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.attachRetryDelay) { [weak self] in
                self?.attach(app, attempt: attempt + 1)
            }
        }
    }

    private func detach(_ app: NSRunningApplication) {
        watchers.removeValue(forKey: app.processIdentifier)?.stop()
    }

    /// The app you just closed a window in is almost always the frontmost one.
    private func pollFrontmostApp() {
        guard Settings.shared.isEnabled,
              let app = NSWorkspace.shared.frontmostApplication,
              app.activationPolicy == .regular else { return }
        if let watcher = watchers[app.processIdentifier] {
            watcher.poll()
        } else {
            attach(app, attempt: Self.maxAttachAttempts)
        }
    }

    private func lastWindowClosed(in watcher: AppWatcher) {
        let app = watcher.app
        guard Settings.shared.isEnabled,
              !app.isTerminated,
              !app.isHidden,
              app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier,
              !Settings.shared.isExcluded(bundleID) else { return }
        if let launchDate = app.launchDate, Date().timeIntervalSince(launchDate) < Self.launchGracePeriod {
            return
        }
        // Same as choosing Quit: the app can still ask to save unsaved work.
        app.terminate()
    }
}
