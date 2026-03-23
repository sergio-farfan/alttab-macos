//
//  SwitcherPanel.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  The overlay UI that displays window thumbnails in a horizontal strip.
//  Built as an NSPanel with .nonactivatingPanel style mask so it floats
//  above all windows without stealing focus — critical for the Option-release
//  activation flow. Uses NSVisualEffectView with .hudWindow material for
//  the semi-transparent backdrop, and an NSScrollView wrapping a horizontal
//  NSStackView of ThumbnailView cells.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.1.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa

final class SwitcherPanel: NSPanel {

    private let itemWidth: CGFloat = 180
    private let itemHeight: CGFloat = 160
    private let itemSpacing: CGFloat = 12
    private let panelPadding: CGFloat = 20

    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var thumbnailViews: [ThumbnailView] = []
    private var selectedIndex: Int = 0

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        self.level = .floating
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = false

        setupUI()
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
    }

    // MARK: - UI Setup

    private func setupUI() {
        let backdrop = NSVisualEffectView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 16
        backdrop.layer?.masksToBounds = true

        contentView = backdrop

        scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        backdrop.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: panelPadding),
            scrollView.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -panelPadding),
            scrollView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: panelPadding),
            scrollView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -panelPadding),
        ])

        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = itemSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stackView
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.heightAnchor.constraint(equalToConstant: itemHeight),
        ])
    }

    // MARK: - Public API

    func show(windows: [WindowInfo], selectedIndex: Int) {
        self.selectedIndex = selectedIndex

        // Clear old
        thumbnailViews.forEach { $0.removeFromSuperview() }
        thumbnailViews.removeAll()

        // Build new
        for (index, windowInfo) in windows.enumerated() {
            let view = ThumbnailView(windowInfo: windowInfo, width: itemWidth, height: itemHeight)
            view.isSelected = (index == selectedIndex)
            view.onClicked = { [weak self] in
                self?.handleClick(index: index)
            }
            stackView.addArrangedSubview(view)
            thumbnailViews.append(view)
        }

        // Size and position the panel
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let maxPanelWidth = screen.frame.width * 0.85
        let contentWidth = CGFloat(windows.count) * itemWidth + CGFloat(max(0, windows.count - 1)) * itemSpacing
        let panelWidth = min(maxPanelWidth, contentWidth + panelPadding * 2)
        let panelHeight = itemHeight + panelPadding * 2

        let panelX = screen.frame.midX - panelWidth / 2
        let panelY = screen.frame.midY - panelHeight / 2

        setFrame(NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight), display: true)

        orderFrontRegardless()
        scrollToSelected()
    }

    func updateSelection(index: Int) {
        guard index >= 0, index < thumbnailViews.count else { return }
        thumbnailViews[selectedIndex].isSelected = false
        selectedIndex = index
        thumbnailViews[selectedIndex].isSelected = true
        scrollToSelected()
    }

    func dismiss() {
        orderOut(nil)
        thumbnailViews.forEach { $0.removeFromSuperview() }
        thumbnailViews.removeAll()
    }

    // MARK: - Private

    private func scrollToSelected() {
        guard selectedIndex < thumbnailViews.count else { return }
        let view = thumbnailViews[selectedIndex]
        scrollView.contentView.scrollToVisible(view.frame)
    }

    private func handleClick(index: Int) {
        updateSelection(index: index)
        // Notify delegate through responder chain — AppDelegate handles it
        NotificationCenter.default.post(name: .switcherClickedWindow, object: nil,
                                        userInfo: ["index": index])
    }

    // Allow mouse interaction even though we're non-activating
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension Notification.Name {
    static let switcherClickedWindow = Notification.Name("com.alttab.switcherClickedWindow")
}
