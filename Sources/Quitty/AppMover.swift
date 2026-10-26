import AppKit

/// Offers to copy Quitty into Applications when it runs from somewhere else,
/// such as its disk image or Downloads.
@MainActor
enum AppMover {
    private static let dontAskKey = "dontOfferMoveToApplications"

    /// Returns true when Quitty is being moved and is about to relaunch.
    static func moveToApplicationsIfNeeded() -> Bool {
        let source = Bundle.main.bundleURL
        guard !isInApplications(source),
              !UserDefaults.standard.bool(forKey: dontAskKey) else { return false }

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Move Quitty to your Applications folder?"
        alert.informativeText = "Quitty can install updates and keep its Accessibility permission only when it runs from Applications."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: dontAskKey)
        }
        guard response == .alertFirstButtonReturn else { return false }

        do {
            let destination = try copyToApplications(source)
            let volume = source.path.hasPrefix("/Volumes/") ? volumeRoot(of: source) : nil
            Relauncher.relaunch(at: destination, ejecting: volume)
            return true
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't move Quitty to Applications"
            failure.informativeText = "\(error.localizedDescription)\n\nDrag Quitty into the Applications folder in Finder instead."
            failure.runModal()
            return false
        }
    }

    private static func isInApplications(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    /// Copies into /Applications, or ~/Applications when that isn't writable.
    private static func copyToApplications(_ source: URL) throws -> URL {
        let fileManager = FileManager.default
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let user = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let folder = fileManager.isWritableFile(atPath: system.path) ? system : user
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let destination = folder.appendingPathComponent(source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)

        let unquarantine = Process()
        unquarantine.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        unquarantine.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try? unquarantine.run()
        unquarantine.waitUntilExit()
        return destination
    }

    /// "/Volumes/Quitty" for "/Volumes/Quitty/Quitty.app".
    private static func volumeRoot(of url: URL) -> String {
        let components = url.pathComponents
        return NSString.path(withComponents: Array(components.prefix(3)))
    }
}
