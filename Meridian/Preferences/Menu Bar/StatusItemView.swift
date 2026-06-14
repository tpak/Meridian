// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreModelKit

let defaultTimeParagraphStyle: NSMutableParagraphStyle = {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byTruncatingTail
    return paragraphStyle
}()

let defaultParagraphStyle: NSMutableParagraphStyle = {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    paragraphStyle.lineBreakMode = .byTruncatingTail
    // Better readability for p,q,y,g in the status bar.
    let userPreferredLanguage = Locale.preferredLanguages.first ?? "en-US"
    let lineHeight = userPreferredLanguage.contains("en") ? LayoutConstants.englishMenubarLineHeightMultiple : 1
    paragraphStyle.lineHeightMultiple = CGFloat(lineHeight)
    return paragraphStyle
}()

let compactModeTimeFont: NSFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

/// v4 menu bar: render each favourite as a single line "● NAME TIME" with a per-city color dot,
/// instead of the legacy two-line (place over time) item. Flip to false to restore the old layout.
let kMenubarV4SingleLine = true

/// Whether the leading color dot is shown (Settings → Menu Bar → Color dots; default on).
var menubarColorDotsEnabled: Bool {
    UserDefaults.standard.object(forKey: "com.tpak.meridian.v4.menubarColorDots") as? Bool ?? true
}

extension NSView {
    var hasDarkAppearance: Bool {
        switch effectiveAppearance.name {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
            return true
        default:
            return false
        }
    }
}

class StatusItemView: NSView {
    // MARK: Private variables

    private let locationView = NSTextField(labelWithString: "Hello")
    private let timeView = NSTextField(labelWithString: "Mon 19:14 PM")
    private var operationsObject: TimezoneDataOperations {
        return TimezoneDataOperations(with: dataObject, store: DataStore.shared())
    }
    private lazy var paragraphStyle: NSMutableParagraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        // The two-line item compresses line height for p,q,y,g readability across its stacked
        // lines. The single-line item is vertically centered, so it keeps the natural line height —
        // the compressed box would otherwise shift the glyphs up and clip descenders.
        if kMenubarV4SingleLine {
            paragraphStyle.lineHeightMultiple = 1
        } else {
            let userPreferredLanguage = Locale.preferredLanguages.first ?? "en-US"
            let lineHeight = userPreferredLanguage.contains("en") ? LayoutConstants.englishMenubarLineHeightMultiple : 1
            paragraphStyle.lineHeightMultiple = CGFloat(lineHeight)
        }
        return paragraphStyle
    }()

    // Cached per appearance mode; invalidated in viewDidChangeEffectiveAppearance.
    private var cachedTimeAttributes: [NSAttributedString.Key: AnyObject]?
    private var cachedTextFontAttributes: [NSAttributedString.Key: Any]?

    private var timeAttributes: [NSAttributedString.Key: AnyObject] {
        if let cached = cachedTimeAttributes { return cached }
        let textColor = hasDarkAppearance ? NSColor.white : NSColor.black
        let attributes: [NSAttributedString.Key: AnyObject] = [
            NSAttributedString.Key.font: compactModeTimeFont,
            NSAttributedString.Key.foregroundColor: textColor,
            NSAttributedString.Key.backgroundColor: NSColor.clear,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ]
        cachedTimeAttributes = attributes
        return attributes
    }

    private var textFontAttributes: [NSAttributedString.Key: Any] {
        if let cached = cachedTextFontAttributes { return cached }
        let textColor = hasDarkAppearance ? NSColor.white : NSColor.black
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 10),
            NSAttributedString.Key.foregroundColor: textColor,
            NSAttributedString.Key.backgroundColor: NSColor.clear,
            NSAttributedString.Key.paragraphStyle: paragraphStyle
        ]
        cachedTextFontAttributes = attributes
        return attributes
    }

    // MARK: Public

    var dataObject: TimezoneData! {
        didSet {
            initialSetup()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        [timeView, locationView].forEach {
            $0.wantsLayer = true
            $0.applyDefaultStyle()
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        timeView.disableWrapping()

        if kMenubarV4SingleLine {
            // One line, vertically centered. The location line is unused. Pinning top+bottom would
            // stretch the field and an NSTextField draws a single line at the *top* of a tall frame,
            // shoving the text against the menu bar's top edge — so centerY-anchor it instead and
            // let it keep its intrinsic (one-line) height.
            locationView.isHidden = true
            NSLayoutConstraint.activate([
                timeView.leadingAnchor.constraint(equalTo: leadingAnchor),
                timeView.trailingAnchor.constraint(equalTo: trailingAnchor),
                timeView.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            return
        }

        let topAnchorConstant: CGFloat = 0.0

        NSLayoutConstraint.activate([
            locationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            locationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            locationView.topAnchor.constraint(equalTo: topAnchor, constant: topAnchorConstant),
            locationView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.35)
        ])

        NSLayoutConstraint.activate([
            timeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            timeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
            timeView.topAnchor.constraint(equalTo: locationView.bottomAnchor),
            timeView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Identity used to look up this row's color dot.
    private var dotIdentity: String {
        if let pid = dataObject.placeID, !pid.isEmpty { return pid }
        if let tid = dataObject.timezoneID, !tid.isEmpty { return tid }
        return dataObject.timezone()
    }

    /// v4 single-line attributed string: optional color dot + "NAME [day] TIME [date]".
    private func oneLineAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        if menubarColorDotsEnabled {
            result.append(NSAttributedString(string: "\u{25CF} ", attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: CityColorStore.nsColor(for: dotIdentity),
                .paragraphStyle: paragraphStyle
            ]))
        }
        result.append(NSAttributedString(string: operationsObject.compactMenuOneLine(), attributes: timeAttributes))
        return result
    }

    /// Apply the current content to the views, honoring the single-line vs two-line mode.
    private func applyContent() {
        if kMenubarV4SingleLine {
            timeView.attributedStringValue = oneLineAttributedString()
            return
        }
        locationView.attributedStringValue = NSAttributedString(string: operationsObject.compactMenuTitle(), attributes: textFontAttributes)
        timeView.attributedStringValue = NSAttributedString(string: operationsObject.compactMenuSubtitle(), attributes: timeAttributes)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Invalidate appearance-dependent attribute caches so they are rebuilt for the new appearance.
        cachedTimeAttributes = nil
        cachedTextFontAttributes = nil
        statusItemViewSetNeedsDisplay()
    }

    private func initialSetup() {
        applyContent()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension StatusItemView: StatusItemViewConforming {
    func statusItemViewSetNeedsDisplay() {
        applyContent()
    }

    func statusItemViewIdentifier() -> String {
        return "location_view"
    }
}
