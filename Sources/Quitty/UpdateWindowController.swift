import AppKit
import SwiftUI

/// Shows `UpdateView` in a borderless-looking glass window.
@MainActor
final class UpdateWindowController {
    private let updater: Updater
    private var window: NSWindow?

    init(updater: Updater) {
        self.updater = updater
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingView(rootView: UpdateView(updater: updater) { [weak self] in self?.close() })
        let size = hosting.fittingSize

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Quitty Update"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = Self.glassBackground(around: hosting, window: window)
        window.setContentSize(size)
        return window
    }

    /// Liquid Glass on macOS 26, a translucent window material before that.
    private static func glassBackground(around content: NSView, window: NSWindow) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            window.isOpaque = false
            window.backgroundColor = .clear
            let glass = NSGlassEffectView()
            glass.cornerRadius = 26
            glass.contentView = content
            return glass
        }
        #endif
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }
}
