// Copyright © 2026 Chris Tirpak
//
// DaybreakPanelController — owns the v4 popover window and its view model. Self-contained: it ports
// the positioning + show/hide + float-mode behavior from the legacy PanelController without touching
// it, so the old panel remains an instant fallback (toggle `AppDelegate.useDaybreakPanel`).

import AppKit
import SwiftUI

final class DaybreakPanelController: NSWindowController, NSWindowDelegate {

    let viewModel = DaybreakViewModel()
    private var hosting: NSHostingView<DaybreakRootView>?
    private weak var anchorButton: NSStatusBarButton?

    // Chrome insets baked into DaybreakRootView (transparent margin around the 378px body for the
    // shadow + notch). Used to align the body under the status item.
    private let bodyInsetX: CGFloat = 40
    private let bodyTopInset: CGFloat = 14
    private let bodyWidth: CGFloat = 378

    convenience init() {
        let panel = DaybreakPanel(
            contentRect: NSRect(x: 0, y: 0, width: 458, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false            // the SwiftUI body draws its own shadow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false // controller persists across open/close
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.transient, .ignoresCycle]
        self.init(window: panel)
        panel.delegate = self
        rebuildHosting()
    }

    var isFloating: Bool { DataStore.shared().floatOnTop }

    private func rebuildHosting() {
        let root = DaybreakRootView(
            viewModel: viewModel,
            isFloating: isFloating,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onTogglePin: { [weak self] in self?.togglePin() }
        )
        let host = NSHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        window?.contentView = host
        hosting = host
    }

    // MARK: Show / hide

    func toggle(relativeTo button: NSStatusBarButton) {
        anchorButton = button
        if window?.isVisible == true {
            hidePanel()
        } else {
            showPanel(relativeTo: button)
        }
    }

    func showPanel(relativeTo button: NSStatusBarButton) {
        guard let panel = window as? DaybreakPanel, let host = hosting else { return }
        anchorButton = button
        rebuildHosting() // pick up any float/theme changes since last open
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        panel.setContentSize(NSSize(width: max(fitting.width, bodyWidth + bodyInsetX * 2),
                                    height: fitting.height))
        applyWindowMode(panel)
        position(panel, under: button)
        viewModel.startTicking()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hidePanel() {
        viewModel.stopTicking()
        window?.orderOut(nil)
    }

    private func applyWindowMode(_ panel: DaybreakPanel) {
        if isFloating {
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            panel.level = .popUpMenu
            panel.collectionBehavior = [.transient, .ignoresCycle]
        }
    }

    private func position(_ panel: NSPanel, under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            if let screen = NSScreen.main {
                panel.center()
                _ = screen
            }
            return
        }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let width = panel.frame.width

        // Center the 378px body (inset by bodyInsetX) under the status item.
        var left = buttonRect.midX - (bodyInsetX + bodyWidth / 2)
        if let visible = screen?.visibleFrame {
            left = max(visible.minX + 4, min(left, visible.maxX - width + 4))
        }
        // Align the body's top to just under the menu-bar item (the transparent top inset overlaps
        // the bar harmlessly).
        let topLeft = NSPoint(x: left, y: buttonRect.minY + bodyTopInset)
        panel.setFrameTopLeftPoint(topLeft)
        panel.invalidateShadow()
    }

    // MARK: Footer / shortcut actions

    func openSettings() {
        // Reuse the existing Preferences window until the v4 Settings ships (Phase 3).
        (NSApp.delegate as? AppDelegate)?.panelController.openPreferencesWindow()
    }

    func togglePin() {
        DataStore.shared().floatOnTop.toggle()
        guard let panel = window as? DaybreakPanel else { return }
        applyWindowMode(panel)
        rebuildHosting()
    }

    func copyCurrentLocationToClipboard() {
        let hero = viewModel.snapshot.hero
        let name = hero.eyebrow.components(separatedBy: " · ").first ?? hero.eyebrow
        let time = hero.period.isEmpty ? hero.time : "\(hero.time) \(hero.period)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(name) - \(time)", forType: .string)
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard !isFloating else { return }
        hidePanel()
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.stopTicking()
    }
}
