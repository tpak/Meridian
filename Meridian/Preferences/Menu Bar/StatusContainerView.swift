// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreModelKit

func compactWidth(for timezone: TimezoneData, with store: DataStoring) -> Int {
    var totalWidth = MenubarLayoutConstants.baseWidth
    // Menu-bar-only geometry — width follows the menu-bar format (12/24 from
    // Appearance, seconds from the Menu Bar pane's Seconds toggle).
    let timeFormat = timezone.timezoneFormat(store.menubarTimezoneFormat())

    if store.shouldShowDayInMenubar() {
        totalWidth += MenubarLayoutConstants.dayBuffer
    }

    if timeFormat == DateFormat.twelveHour
        || timeFormat == DateFormat.twelveHourWithSeconds
        || timeFormat == DateFormat.twelveHourWithZero
        || timeFormat == DateFormat.twelveHourWithSeconds {
        totalWidth += MenubarLayoutConstants.twelveHourBuffer
    } else if timeFormat == DateFormat.twentyFourHour
        || timeFormat == DateFormat.twentyFourHourWithSeconds {
        totalWidth += 0
    }

    if timezone.shouldShowSeconds(store.menubarTimezoneFormat()) {
        // Slight buffer needed when the Menubar supplementary text was Mon 9:27:58 AM
        totalWidth += MenubarLayoutConstants.secondsBuffer
    }

    if store.shouldShowDateInMenubar() {
        totalWidth += MenubarLayoutConstants.dateBuffer
    }

    return totalWidth
}

// Test with Sat 12:46 AM
let bufferWidth: CGFloat = 9.5

/// Height of the status-item content — always the live menu-bar thickness so the item fills the bar
/// exactly (measured: 22pt on this hardware). A taller item overflows the bar and shoves the
/// two-line stacked content down onto the bottom edge; matching the bar keeps both the single line
/// and the stacked pair vertically centred (#142 UAT).
var menubarItemHeight: CGFloat { NSStatusBar.system.thickness }

/// Renders the compact menu-bar strip (every favourited city) into a single image (#191).
///
/// The strip used to be a live NSView hierarchy added as a subview of the status item's button.
/// AppKit only mirrors plain image/title buttons onto additional displays' menu bars natively;
/// custom subviews force the replicant *snapshot* path, which flips `setAppearance:` on the live
/// view for every snapshot so it renders under the target screen's appearance. On Macs whose menu
/// bars resolve different appearances per display, each flip re-dirtied the views (AppKit's own
/// `_viewDidChangeAppearance:` → `setNeedsDisplay`) and scheduled the next snapshot — an infinite
/// loop pinning a core whenever 2+ displays were active. An image in the button replicates
/// natively, so the snapshot machinery (and with it the loop) never runs.
enum MenubarImageRenderer {
    /// Everything needed to draw one city, captured eagerly: the image's drawing handler runs on
    /// later AppKit draw passes (including replicant draws for other displays) and must not touch
    /// DataStore or recompute times.
    struct CityStrip {
        /// Stacked mode: the city-name line. Single-line mode: nil.
        let title: String?
        /// The time line (stacked) or the whole "NAME TIME" line (single-line).
        let line: String
        /// Leading "●" color; nil when color dots are off or in stacked mode.
        let dotColor: NSColor?
        let width: CGFloat
    }

    // Semibold (not bold) for the stacked name line — matches the cleaner Settings preview
    // chip; full bold read heavier/chunkier in the menu bar (issue #142 UAT).
    private static let titleFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private static let dotFont = NSFont.systemFont(ofSize: 9)

    // Half the vertical gap between the stacked lines; same ±6pt centerline offsets the
    // stacked NSView layout used (#142 UAT).
    private static let stackedHalfGap: CGFloat = 6

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        style.lineHeightMultiple = 1
        return style
    }()

    private static var measurementAttributes: [NSAttributedString.Key: AnyObject] {
        [NSAttributedString.Key.paragraphStyle: paragraphStyle]
    }

    /// Identity used to look up a city's color dot.
    private static func dotIdentity(for timezone: TimezoneData) -> String {
        if let pid = timezone.placeID, !pid.isEmpty { return pid }
        if let tid = timezone.timezoneID, !tid.isEmpty { return tid }
        return timezone.timezone()
    }

    /// Compute the drawable content and slot width for each city.
    static func contents(for timezones: [TimezoneData], store: DataStoring) -> [CityStrip] {
        timezones.map { timezone in
            let operations = TimezoneDataOperations(with: timezone, store: store)

            if kMenubarV4SingleLine {
                // Measure the actual single line ("● NAME TIME"); a generous width avoids
                // truncating the measurement itself.
                let line = operations.compactMenuOneLine()
                let lineSize = compactModeTimeFont.size(for: line, width: 1000, attributes: measurementAttributes)
                let dotColor = menubarColorDotsEnabled ? CityColorStore.nsColor(for: dotIdentity(for: timezone)) : nil
                let dotPad: CGFloat = dotColor != nil ? MenubarLayoutConstants.colorDotPadding : 0
                return CityStrip(title: nil, line: line, dotColor: dotColor,
                                 width: lineSize.width + dotPad + bufferWidth)
            }

            let title = operations.compactMenuTitle()
            let line = operations.compactMenuSubtitle()
            let widthBudget = Double(compactWidth(for: timezone, with: store))
            let lineSize = compactModeTimeFont.size(for: line, width: widthBudget, attributes: measurementAttributes)
            let titleSize = compactModeTimeFont.size(for: title, width: widthBudget, attributes: measurementAttributes)
            let showSeconds = timezone.shouldShowSeconds(store.menubarTimezoneFormat())
            let secondsBuffer: CGFloat = showSeconds ? MenubarLayoutConstants.measuredSecondsBuffer : 0
            return CityStrip(title: title, line: line, dotColor: nil,
                             width: max(lineSize.width, titleSize.width) + bufferWidth + secondsBuffer)
        }
    }

    /// Cheap change-detection key: rebuilding the image is skipped when this is unchanged, so a
    /// no-op refresh tick never touches the button (and never wakes the replicant machinery).
    static func signature(of strips: [CityStrip]) -> String {
        strips.map { "\($0.title ?? "")|\($0.line)|\($0.dotColor?.description ?? "-")|\($0.width)" }
            .joined(separator: "§")
    }

    /// Concatenated plain-text content, exposed to accessibility since the drawn image (unlike
    /// the old NSTextField hierarchy) has no text of its own for VoiceOver to read.
    static func accessibilityText(of strips: [CityStrip]) -> String {
        strips.map { [$0.title, $0.line].compactMap { $0 }.joined(separator: " ") }
            .joined(separator: ", ")
    }

    /// Render all cities side by side into one menu-bar-height image. Text color resolves via
    /// `menubarTextColor` inside the drawing handler, i.e. against the appearance active where
    /// the image is actually drawn — each display's menu bar gets the right variant.
    static func image(for strips: [CityStrip]) -> NSImage {
        let height = menubarItemHeight
        let totalWidth = max(strips.reduce(0) { $0 + $1.width }, 1)
        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for strip in strips {
                draw(strip, at: x, height: height)
                x += strip.width
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(_ strip: CityStrip, at x: CGFloat, height: CGFloat) {
        if let title = strip.title {
            let titleString = NSAttributedString(string: title, attributes: [
                .font: titleFont,
                .foregroundColor: menubarTextColor,
                .paragraphStyle: paragraphStyle
            ])
            let lineString = NSAttributedString(string: strip.line, attributes: [
                .font: compactModeTimeFont,
                .foregroundColor: menubarTextColor,
                .paragraphStyle: paragraphStyle
            ])
            drawCentered(titleString, x: x, width: strip.width, centerY: height / 2 + stackedHalfGap)
            drawCentered(lineString, x: x, width: strip.width, centerY: height / 2 - stackedHalfGap)
            return
        }

        let line = NSMutableAttributedString()
        if let dotColor = strip.dotColor {
            line.append(NSAttributedString(string: "\u{25CF} ", attributes: [
                .font: dotFont,
                .foregroundColor: dotColor,
                .paragraphStyle: paragraphStyle
            ]))
        }
        line.append(NSAttributedString(string: strip.line, attributes: [
            .font: compactModeTimeFont,
            .foregroundColor: menubarTextColor,
            .paragraphStyle: paragraphStyle
        ]))
        drawCentered(line, x: x, width: strip.width, centerY: height / 2)
    }

    private static func drawCentered(_ string: NSAttributedString, x: CGFloat, width: CGFloat, centerY: CGFloat) {
        let textHeight = string.size().height
        string.draw(in: NSRect(x: x, y: centerY - textHeight / 2, width: width, height: textHeight))
    }
}
