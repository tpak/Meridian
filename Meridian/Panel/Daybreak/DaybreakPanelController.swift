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
    // Gap between the menu-bar bottom and the panel body so the popover sits clearly *below* the bar
    // (standard menu-bar-app behaviour) instead of flush against it. (#142 UAT — the menu-bar item
    // height fix moved the anchor button's bottom up to the bar, which pulled the panel flush.)
    private let bodyGapBelowBar: CGFloat = 8

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
        // Floating popovers reopen where the user left them; transient ones anchor under the item.
        if isFloating, let topLeft = restoredFloatingTopLeft(for: panel, near: button) {
            panel.setFrameTopLeftPoint(topLeft)
            panel.invalidateShadow()
        } else {
            position(panel, under: button)
        }
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
        // Floating popovers are draggable by their background (chrome); transient ones stay anchored
        // under the menu-bar item. Interactive surfaces (scrubber, buttons, rows, hero edit) consume
        // their own gestures, so only true background regions initiate a window drag.
        panel.isMovableByWindowBackground = isFloating
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
        // Align the body's top just under the menu-bar item, plus a small gap so the popover sits
        // clearly below the bar (the transparent top inset still overlaps the bar harmlessly).
        let topLeft = NSPoint(x: left, y: buttonRect.minY + bodyTopInset - bodyGapBelowBar)
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
        if isFloating {
            // Seed the floating position with where it currently sits (under the menu bar) so the
            // first reopen lands here until the user drags it elsewhere.
            saveFloatingTopLeft(panel)
        } else if let button = anchorButton {
            // Back to transient mode — re-anchor under the menu-bar item rather than leaving it
            // stranded wherever it was floating.
            position(panel, under: button)
        }
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

    func windowDidMove(_ notification: Notification) {
        // Remember where the user drags a floating popover so it reopens there. Programmatic moves
        // while floating (restore/resize) re-save the same point, which is harmless.
        guard isFloating, let panel = window as? DaybreakPanel, panel.isVisible else { return }
        saveFloatingTopLeft(panel)
    }

    // MARK: Floating position persistence

    private static let floatingTopLeftKey = "com.tpak.meridian.v4.daybreakFloatingTopLeft"

    private var savedFloatingTopLeft: NSPoint? {
        guard let pair = UserDefaults.standard.array(forKey: Self.floatingTopLeftKey) as? [Double],
              pair.count == 2 else { return nil }
        return NSPoint(x: pair[0], y: pair[1])
    }

    private func saveFloatingTopLeft(_ panel: NSPanel) {
        let topLeft = [Double(panel.frame.minX), Double(panel.frame.maxY)]
        UserDefaults.standard.set(topLeft, forKey: Self.floatingTopLeftKey)
    }

    /// The saved floating top-left, clamped onto the current screen so a stale position (e.g. from a
    /// disconnected display) can't strand the popover off-screen. `nil` when nothing is saved yet.
    private func restoredFloatingTopLeft(for panel: NSPanel, near button: NSStatusBarButton) -> NSPoint? {
        guard let saved = savedFloatingTopLeft else { return nil }
        let screen = button.window?.screen ?? panel.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return saved }
        let width = panel.frame.width
        let height = panel.frame.height
        let x = min(max(saved.x, visible.minX), max(visible.minX, visible.maxX - width))
        let y = max(min(saved.y, visible.maxY), min(visible.maxY, visible.minY + height))
        return NSPoint(x: x, y: y)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.stopTicking()
    }
}
