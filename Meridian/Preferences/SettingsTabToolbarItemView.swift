// Copyright © 2026 Christopher Tirpak

import Cocoa

/// Custom NSToolbarItem view used by OneWindowController to render the
/// Settings tab strip (Preferences / Appearance / About).
///
/// Why this exists:
/// On macOS Tahoe (26+) the auto-generated toolbar tab items used by
/// NSTabViewController(tabStyle: .toolbar) render the *selected* tab's
/// label in a color derived from `NSColor.controlAccentColor` over a
/// background pill that's *also* accent-tinted. With Meridian's team
/// accent swizzle (AccentColorSwizzler.install), both surfaces share
/// the team color — yielding orange-on-orange where the label disappears.
/// There's no public API to override the auto-rendered label color.
///
/// We bypass AppKit's drawing by setting each NSToolbarItem.view to an
/// instance of this class. AppKit then renders our view instead of its
/// own, so all colors are under our control: the label is always
/// `NSColor.labelColor` (high-contrast), the selection state is shown
/// as a subtle rounded fill that doesn't fight the team color, and the
/// icon keeps its team-color palette tint.
final class SettingsTabToolbarItemView: NSView {
    var isSelected: Bool = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
        }
    }

    /// Invoked when the user clicks the view. The owner translates this
    /// into a `selectedTabViewItemIndex` change on the tab controller.
    var onClick: (() -> Void)?

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(image: NSImage?, title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 90, height: 54))

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // Match the visual weight AppKit uses for tab toolbar icons.
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)

        label.stringValue = title
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = .labelColor
        label.alignment = .center
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(label)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),

            widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setImage(_ image: NSImage?) {
        imageView.image = image
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelected {
            // Neutral, alpha-tinted highlight that reads clearly on both
            // light and dark window backgrounds without pulling color
            // from the team accent (which AppKit's default tab pill does,
            // and which broke label contrast on Tahoe).
            let inset = bounds.insetBy(dx: 2, dy: 3)
            let path = NSBezierPath(roundedRect: inset, xRadius: 7, yRadius: 7)
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            path.fill()
        }
    }

    override func mouseDown(with _: NSEvent) {
        onClick?()
    }
}
