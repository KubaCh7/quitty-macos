import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item and the panel it opens.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Created at launch rather than in init: main.swift constructs the
    // delegate outside the main actor.
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hostingController: NSHostingController<MenuView>!
    private var iconUpdates: AnyCancellable?

    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMover.moveToApplicationsIfNeeded() {
            return
        }
        model = AppModel()
        popover = NSPopover()
        hostingController = NSHostingController(rootView: MenuView(model: model, updater: model.updater))
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = .preferredContentSize
        }
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))

        iconUpdates = model.$isEnabled.combineLatest(model.$isTrusted)
            .sink { [weak self] isEnabled, isTrusted in
                self?.updateIcon(isActive: isEnabled && isTrusted)
            }

        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    private func updateIcon(isActive: Bool) {
        let image = NSImage(systemSymbolName: isActive ? "xmark.circle.fill" : "xmark.circle",
                            accessibilityDescription: "Quitty")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        model.refresh()
        if #unavailable(macOS 13.0) {
            popover.contentSize = hostingController.view.fittingSize
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
