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
//  Version: 1.0.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa

final class ThumbnailView: NSView {

    var onClicked: (() -> Void)?

    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    private let imageView: NSImageView
    private let titleLabel: NSTextField
    private let appLabel: NSTextField
    private let selectionBorder: NSView
    private let thumbnailHeight: CGFloat

    init(windowInfo: WindowInfo, width: CGFloat, height: CGFloat) {
        self.thumbnailHeight = height - 50 // Reserve space for labels

        imageView = NSImageView()
        titleLabel = NSTextField(labelWithString: "")
        appLabel = NSTextField(labelWithString: "")
        selectionBorder = NSView()

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
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // App name
        appLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        appLabel.textColor = NSColor.white.withAlphaComponent(0.6)
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
    }

    private func updateAppearance() {
        if isSelected {
            selectionBorder.layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        } else {
            selectionBorder.layer?.borderColor = NSColor.clear.cgColor
            layer?.backgroundColor = NSColor.clear.cgColor
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
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}
