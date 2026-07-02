//
//  WCAGContrast.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  WCAG 2.x relative-luminance and contrast-ratio math
//  (https://www.w3.org/WAI/standards-guidelines/wcag/ — SC 1.4.3), used to
//  verify that the switcher's label colors meet AA (>= 4.5:1) against their
//  backing in both light and dark appearances. Pure Swift, no AppKit, so it
//  compiles into both the app target and the SPM AltTabCore module.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  License: MIT
//

import Foundation

/// A color in sRGB space, components 0...1.
struct SRGB {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

enum WCAGContrast {

    /// WCAG relative luminance of an (assumed opaque) sRGB color.
    static func relativeLuminance(_ color: SRGB) -> Double {
        func linearize(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(color.r)
             + 0.7152 * linearize(color.g)
             + 0.0722 * linearize(color.b)
    }

    /// Alpha-composites a foreground color over an opaque background.
    static func composite(_ fg: SRGB, over bg: SRGB) -> SRGB {
        let a = fg.a
        return SRGB(r: fg.r * a + bg.r * (1 - a),
                    g: fg.g * a + bg.g * (1 - a),
                    b: fg.b * a + bg.b * (1 - a),
                    a: 1.0)
    }

    /// WCAG contrast ratio between two opaque colors (1...21).
    static func contrastRatio(_ c1: SRGB, _ c2: SRGB) -> Double {
        let l1 = relativeLuminance(c1)
        let l2 = relativeLuminance(c2)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Contrast ratio of (possibly translucent) text over an opaque
    /// background: the text is composited first, per WCAG practice.
    static func contrastRatio(text: SRGB, background: SRGB) -> Double {
        contrastRatio(composite(text, over: background), background)
    }
}
