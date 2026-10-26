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
        // Finish launching first: an alert shown from here blocks the launch,
        // and macOS then reports Quitty as not responding.
        Task { @MainActor in
            self.setUp()
        }
    }

    private func setUp() {
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

        // A menu bar app shows nothing when it opens, and the icon can hide
        // behind the notch. Open the panel when there is something to do.
        if !model.isTrusted {
            showPanel()
        }
    }

    /// Opening Quitty again (Finder, Spotlight, Launchpad) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
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
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let popover, !popover.isShown, let button = statusItem?.button else { return }
        model.refresh()
        if #unavailable(macOS 13.0) {
            popover.contentSize = hostingController.view.fittingSize
        }
        NSApp.bringToFront()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
