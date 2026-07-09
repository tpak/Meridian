// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import CoreModelKit
import XCTest

@testable import Meridian

/// The compact menu-bar strip is drawn into an image instead of hosted as live NSViews
/// inside the status item's button (#191) — these tests exercise the renderer headlessly.
class MenubarImageRendererTests: XCTestCase {
    private var mockStore: MockDataStore!

    override func setUp() {
        super.setUp()
        mockStore = MockDataStore()
    }

    private func fixtures() -> [TimezoneData] {
        let sanFrancisco = TimezoneData(with: TestTimezones.sanFrancisco)
        let newYork = TimezoneData(with: TestTimezones.newYork)
        return [sanFrancisco, newYork]
    }

    func testContentsProducesOneStripPerCity() {
        let strips = MenubarImageRenderer.contents(for: fixtures(), store: mockStore)

        XCTAssertEqual(strips.count, 2)
        for strip in strips {
            XCTAssertFalse(strip.line.isEmpty)
            XCTAssertGreaterThan(strip.width, 0)
        }
    }

    func testImageSizeMatchesStripGeometry() {
        let strips = MenubarImageRenderer.contents(for: fixtures(), store: mockStore)
        let image = MenubarImageRenderer.image(for: strips)

        let expectedWidth = strips.reduce(0) { $0 + $1.width }
        XCTAssertEqual(image.size.width, expectedWidth, accuracy: 0.5)
        XCTAssertEqual(image.size.height, menubarItemHeight, accuracy: 0.5)
        XCTAssertFalse(image.isTemplate)
    }

    func testImageActuallyDrawsContent() throws {
        let strips = MenubarImageRenderer.contents(for: fixtures(), store: mockStore)
        let image = MenubarImageRenderer.image(for: strips)

        // Rasterize through the drawing handler and confirm at least some pixels landed —
        // an empty bitmap would mean the handler drew nothing (wrong coordinates, empty
        // strings, or a fully-transparent color).
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: Int(image.size.width),
                                                 pixelsHigh: Int(image.size.height),
                                                 bitsPerSample: 8,
                                                 samplesPerPixel: 4,
                                                 hasAlpha: true,
                                                 isPlanar: false,
                                                 colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0,
                                                 bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        var opaquePixels = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                    opaquePixels += 1
                }
            }
        }
        XCTAssertGreaterThan(opaquePixels, 10, "rendered strip should contain visible text pixels")
    }

    func testSignatureIsStableForSameContent() {
        let strips = MenubarImageRenderer.contents(for: fixtures(), store: mockStore)
        let again = MenubarImageRenderer.contents(for: fixtures(), store: mockStore)

        // Same minute, same cities → identical signature, so refresh ticks skip the rebuild.
        XCTAssertEqual(MenubarImageRenderer.signature(of: strips),
                       MenubarImageRenderer.signature(of: again))
    }

    func testSignatureDiffersAcrossCityLists() {
        let both = MenubarImageRenderer.contents(for: fixtures(), store: mockStore)
        let one = MenubarImageRenderer.contents(for: [fixtures()[0]], store: mockStore)

        XCTAssertNotEqual(MenubarImageRenderer.signature(of: both),
                          MenubarImageRenderer.signature(of: one))
    }

    func testAccessibilityTextContainsEveryCityLine() {
        let strips = MenubarImageRenderer.contents(for: fixtures(), store: mockStore)
        let text = MenubarImageRenderer.accessibilityText(of: strips)

        for strip in strips {
            XCTAssertTrue(text.contains(strip.line))
        }
    }
}
