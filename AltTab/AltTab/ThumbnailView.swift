//
//  ThumbnailView.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  A single window cell in the switcher strip. Displays the window thumbnail
//  (or app icon fallback), window title, and application name. Highlights the
//  selected cell with an accent-colored border and subtle background tint.
//  Supports mouse hover and click interaction for direct window selection.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.3.0
//  Date:    2026-07-02
//  License: MIT
//

import Cocoa

final class ThumbnailView: NSView {

    var onClicked: (() -> Void)?

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    /// Secondary tone for the app name that stays dynamic across appearance
    /// changes — withAlphaComponent() on a catalog color resolves and freezes
    /// it at call time, which would pin the wrong theme's color (cells are
    /// constructed before joining the panel's forced-appearance hierarchy).
    private static let appNameColor = NSColor(name: nil) { appearance in
        var color = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.withAlphaComponent(0.78)
        }
        return color
    }

    private let imageView: NSImageView
    private let titleLabel: NSTextField
    private let appLabel: NSTextField
    private let selectionBorder: NSView
    private let labelBackdrop: NSBox
    private let thumbnailHeight: CGFloat

    init(windowInfo: WindowInfo, width: CGFloat, height: CGFloat) {
        self.thumbnailHeight = height - 50 // Reserve space for labels

        imageView = NSImageView()
        titleLabel = NSTextField(labelWithString: "")
        appLabel = NSTextField(labelWithString: "")
        selectionBorder = NSView()
        labelBackdrop = NSBox()

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        setupViews(width: width, height: height)
        configure(with: windowInfo)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Setup

    private func setupViews(width: CGFloat, height: CGFloat) {
        wantsLayer = true

        // Selection border
        selectionBorder.wantsLayer = true
        selectionBorder.layer?.borderWidth = 3
        selectionBorder.layer?.cornerRadius = 8
        selectionBorder.layer?.borderColor = NSColor.clear.cgColor
        selectionBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectionBorder)

        // Solid theme-paired backing so label contrast never depends on the
        // wallpaper showing through the translucent panel (WCAG AA, spec
        // 2026-07-02). The opaque windowBackgroundColor box is painted
        // directly behind the sibling labels, so any residual vibrant
        // blending composites against exactly the background the unit tests
        // assert against.
        labelBackdrop.boxType = .custom
        labelBackdrop.titlePosition = .noTitle
        labelBackdrop.fillColor = .windowBackgroundColor
        labelBackdrop.borderWidth = 0
        labelBackdrop.cornerRadius = 6
        labelBackdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelBackdrop)

        // Thumbnail image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        // Window title
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // App name
        appLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        appLabel.textColor = Self.appNameColor
        appLabel.alignment = .center
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.maximumNumberOfLines = 1
        appLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appLabel)

        // Constraints
        NSLayoutConstraint.activate([
            // Selection border fills entire view
            selectionBorder.topAnchor.constraint(equalTo: topAnchor),
            selectionBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            selectionBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectionBorder.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Image at top
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: width - 16),
            imageView.heightAnchor.constraint(equalToConstant: thumbnailHeight),

            // Title below image
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

            // App name below title
            appLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

            // Fixed size
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: height),

            // Label backing strip wraps both labels with small padding
            labelBackdrop.topAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -3),
            labelBackdrop.bottomAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 3),
            labelBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            labelBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
        ])
    }

    private func configure(with windowInfo: WindowInfo) {
        titleLabel.stringValue = windowInfo.windowTitle.isEmpty ? windowInfo.ownerName : windowInfo.windowTitle
        appLabel.stringValue = windowInfo.ownerName

        if let thumbnail = windowInfo.thumbnail {
            imageView.image = thumbnail
        } else {
            // Fallback: app icon
            let icon = windowInfo.appIcon
            imageView.image = icon
            if windowInfo.isMinimized {
                imageView.alphaValue = 0.7
            }
        }

        #if DEBUG
        // Regression tripwire for the WCAG AA guarantee (spec 2026-07-02).
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let bg = NSColor.windowBackgroundColor.usingColorSpace(.sRGB),
               let fg = NSColor.labelColor.usingColorSpace(.sRGB) {
                let ratio = WCAGContrast.contrastRatio(
                    text: SRGB(r: fg.redComponent, g: fg.greenComponent,
                               b: fg.blueComponent, a: fg.alphaComponent),
                    background: SRGB(r: bg.redComponent, g: bg.greenComponent,
                                     b: bg.blueComponent, a: bg.alphaComponent))
                assert(ratio >= 4.5, "Switcher label contrast fell below WCAG AA: \(ratio)")
            }
        }
        #endif
    }

    /// Replaces the app-icon placeholder with a captured window preview.
    func setThumbnail(_ image: NSImage) {
        imageView.image = image
        imageView.alphaValue = 1.0
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isSelected {
                selectionBorder.layer?.borderColor = NSColor.controlAccentColor.cgColor
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            } else {
                selectionBorder.layer?.borderColor = NSColor.clear.cgColor
                layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
