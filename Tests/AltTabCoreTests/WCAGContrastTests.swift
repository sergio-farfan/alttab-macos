//
//  WCAGContrastTests.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Tests for the WCAG 2.x relative-luminance / contrast-ratio math and for
//  the concrete semantic color pairs the switcher UI uses.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  License: MIT
//

import XCTest
import AppKit
@testable import AltTabCore

final class WCAGContrastTests: XCTestCase {

    func testBlackOnWhiteIsMaxContrast() {
        let white = SRGB(r: 1, g: 1, b: 1)
        let black = SRGB(r: 0, g: 0, b: 0)
        XCTAssertEqual(WCAGContrast.contrastRatio(white, black), 21.0, accuracy: 0.01)
    }

    func testIdenticalColorsAreMinContrast() {
        let gray = SRGB(r: 0.5, g: 0.5, b: 0.5)
        XCTAssertEqual(WCAGContrast.contrastRatio(gray, gray), 1.0, accuracy: 0.0001)
    }

    func testRatioIsSymmetric() {
        let a = SRGB(r: 0.2, g: 0.4, b: 0.6)
        let b = SRGB(r: 0.9, g: 0.9, b: 0.9)
        XCTAssertEqual(WCAGContrast.contrastRatio(a, b),
                       WCAGContrast.contrastRatio(b, a), accuracy: 0.0001)
    }

    func testKnownAABoundaryValue() {
        // #767676 on white is the canonical ~4.54:1 AA boundary example.
        let gray = SRGB(r: 0x76 / 255.0, g: 0x76 / 255.0, b: 0x76 / 255.0)
        let white = SRGB(r: 1, g: 1, b: 1)
        XCTAssertEqual(WCAGContrast.contrastRatio(gray, white), 4.54, accuracy: 0.01)
    }

    func testLuminanceOfWhiteIsOneAndBlackIsZero() {
        XCTAssertEqual(WCAGContrast.relativeLuminance(SRGB(r: 1, g: 1, b: 1)), 1.0, accuracy: 0.0001)
        XCTAssertEqual(WCAGContrast.relativeLuminance(SRGB(r: 0, g: 0, b: 0)), 0.0, accuracy: 0.0001)
    }

    func testCompositeHalfAlphaWhiteOverBlack() {
        let fg = SRGB(r: 1, g: 1, b: 1, a: 0.5)
        let bg = SRGB(r: 0, g: 0, b: 0)
        let out = WCAGContrast.composite(fg, over: bg)
        XCTAssertEqual(out.r, 0.5, accuracy: 0.0001)
        XCTAssertEqual(out.g, 0.5, accuracy: 0.0001)
        XCTAssertEqual(out.b, 0.5, accuracy: 0.0001)
        XCTAssertEqual(out.a, 1.0, accuracy: 0.0001)
    }

    func testTextRatioCompositesAlphaFirst() {
        // 50%-alpha white text on black background == solid 0.5 gray vs black.
        let text = SRGB(r: 1, g: 1, b: 1, a: 0.5)
        let bg = SRGB(r: 0, g: 0, b: 0)
        let expected = WCAGContrast.contrastRatio(SRGB(r: 0.5, g: 0.5, b: 0.5), bg)
        XCTAssertEqual(WCAGContrast.contrastRatio(text: text, background: bg),
                       expected, accuracy: 0.0001)
    }

    // MARK: - Semantic pairs used by ThumbnailView on the solid default
    // background (spec: WCAG AA >= 4.5:1)

    private func resolved(_ color: NSColor, under appearanceName: NSAppearance.Name) -> SRGB {
        var result = SRGB(r: 0, g: 0, b: 0)
        NSAppearance(named: appearanceName)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            result = SRGB(r: Double(c.redComponent),
                          g: Double(c.greenComponent),
                          b: Double(c.blueComponent),
                          a: Double(c.alphaComponent))
        }
        return result
    }

    func testTitleLabelMeetsAAOnBackingInBothAppearances() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let bg = resolved(.windowBackgroundColor, under: name)
            let text = resolved(.labelColor, under: name)
            let ratio = WCAGContrast.contrastRatio(text: text, background: bg)
            XCTAssertGreaterThanOrEqual(ratio, 4.5,
                "labelColor on windowBackgroundColor is \(ratio) in \(name.rawValue)")
        }
    }

    func testAppNameLabelMeetsAAOnBackingInBothAppearances() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let bg = resolved(.windowBackgroundColor, under: name)
            // Derive INSIDE the appearance context: withAlphaComponent() on a
            // dynamic catalog color resolves and freezes it at call time, so
            // deriving outside would test the wrong appearance's color.
            var text = SRGB(r: 0, g: 0, b: 0)
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                let c = NSColor.labelColor.withAlphaComponent(0.78).usingColorSpace(.sRGB)!
                text = SRGB(r: c.redComponent, g: c.greenComponent,
                            b: c.blueComponent, a: c.alphaComponent)
            }
            let ratio = WCAGContrast.contrastRatio(text: text, background: bg)
            XCTAssertGreaterThanOrEqual(ratio, 4.5,
                "labelColor@0.78 on windowBackgroundColor is \(ratio) in \(name.rawValue)")
        }
    }
}
