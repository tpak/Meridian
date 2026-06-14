// Copyright © 2026 Chris Tirpak
//
// DaybreakPanelController — owns the v4 popover window and its view model. Self-contained: it ports
// the positioning + show/hide + float-mode behavior from the legacy PanelController without touching
// it, so the old panel remains an instant fallback (toggle `AppDelegate.useDaybreakPanel`).

import AppKit
import Combine
import SwiftUI

final class DaybreakPanelController: NSWindowController, NSWindowDelegate {

    let viewModel = DaybreakViewModel()
    private var hosting: NSHostingView<DaybreakRootView>?
    private weak var anchorButton: NSStatusBarButton?
    private var cancellables = Set<AnyCancellable>()

    // Chrome insets baked into DaybreakRootView (transparent margin around the 378px body for the
    // shadow + notch). Used to align the body under the status item.
    private let bodyInsetX: CGFloat = 40
    private let bodyTopInset: CGFloat = 14
    private let bodyWidth: CGFloat = 378

    convenience init() {
        let panel = DaybreakPanel(
            contentRect: NSRect(x: 0, y: 0, width: 458, height: 520),
            styleMask: [.borderless],
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
        observeContentHeight()
    }

    /// While the popover is open the only thing that changes its height is the scrubber's "Back to
    /// now" link toggling in/out of travel. Re-fit the window when that happens, anchored at the TOP
    /// edge so the body grows DOWNWARD — the reset link pushes the footer down and the hero (pinned at
    /// the top) never reflows. README §F.
    private func observeContentHeight() {
        viewModel.$snapshot
            .map { $0.scrubber.traveling }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            // Defer one runloop pass so the hosting view has re-rendered the toggled reset link before
            // we measure `fittingSize` — otherwise we'd resize to the pre-toggle height.
            .sink { [weak self] _ in DispatchQueue.main.async { self?.resizeToFitContent() } }
            .store(in: &cancellables)
    }

    private func resizeToFitContent() {
        guard let panel = window as? DaybreakPanel, let host = hosting, panel.isVisible else { return }
        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let width = max(fitting.width, bodyWidth + bodyInsetX * 2)
        let frame = panel.frame
        guard abs(frame.height - fitting.height) > 0.5 || abs(frame.width - width) > 0.5 else { return }
        // AppKit frames are bottom-left anchored; hold the top edge (maxY) so growth extends downward.
        let newFrame = NSRect(x: frame.minX, y: frame.maxY - fitting.height, width: width, height: fitting.height)
        panel.setFrame(newFrame, display: true)
        panel.invalidateShadow()
    }

    var isFloating: Bool { DataStore.shared().floatOnTop }

    private func rebuildHosting() {
        let root = DaybreakRootView(
            viewModel: viewModel,
            isFloating: isFloating,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onTogglePin: { [weak self] in self?.togglePin() },
            onCopyAll: { [weak self] in self?.copyAllCitiesToClipboard() }
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
        anchorButton?.state = .off // keep the menu-bar highlight in sync on every dismiss path
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
            panel.center()
            return
        }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let width = panel.frame.width

        // Center the 378px body (inset by bodyInsetX) under the status item.
        var left = buttonRect.midX - (bodyInsetX + bodyWidth / 2)
        if let visible = screen?.visibleFrame {
            left = max(visible.minX + 4, min(left, visible.maxX - width - 4))
        }
        // Align the body's top to just under the menu-bar item (the transparent top inset overlaps
        // the bar harmlessly).
        let topLeft = NSPoint(x: left, y: buttonRect.minY + bodyTopInset)
        panel.setFrameTopLeftPoint(topLeft)
        panel.invalidateShadow()
    }

    // MARK: Footer / shortcut actions

    func openSettings() {
        hidePanel() // dismiss the popover so the Settings window takes focus cleanly
        (NSApp.delegate as? AppDelegate)?.openSettingsRouted()
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

    /// Copy every visible city's name + time as newline-separated text — the v4 equivalent of the
    /// legacy footer "copy all timezones" button. Current location (hero) first, then each tracked
    /// city, mirroring the popover's top-to-bottom order. Reflects the scrubber's traveled time.
    func copyAllCitiesToClipboard() {
        let snapshot = viewModel.snapshot
        var lines: [String] = []

        // Hero name is the eyebrow segment before " · " ("Denver · Current Location" → "Denver").
        let heroName = snapshot.hero.eyebrow.components(separatedBy: " · ").first ?? snapshot.hero.eyebrow
        lines.append(Self.copyLine(name: heroName, time: snapshot.hero.time, period: snapshot.hero.period))

        // The rows already exclude the current-location timezone, so there's no duplicate hero line.
        for city in snapshot.cities {
            lines.append(Self.copyLine(name: city.name, time: city.time, period: city.period))
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private static func copyLine(name: String, time: String, period: String) -> String {
        let timeString = period.isEmpty ? time : "\(time) \(period)"
        return "\(name) — \(timeString)"
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
