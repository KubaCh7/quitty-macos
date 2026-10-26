import AppKit

@MainActor
enum Relauncher {
    /// Quits, then opens the app at `url` once this process has exited. When
    /// `volume` is set (Quitty was running from its disk image), that volume
    /// is ejected afterwards.
    static func relaunch(at url: URL, ejecting volume: String? = nil) {
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/bin/sh")
        script.arguments = [
            "-c",
            """
            while /bin/kill -0 "$0" 2>/dev/null; do /bin/sleep 0.2; done
            /usr/bin/open "$1"
            if [ -n "$2" ]; then /usr/bin/hdiutil detach -quiet "$2"; fi
            """,
            String(ProcessInfo.processInfo.processIdentifier),
            url.path,
            volume ?? "",
        ]
        try? script.run()
        NSApp.terminate(nil)
    }
}
