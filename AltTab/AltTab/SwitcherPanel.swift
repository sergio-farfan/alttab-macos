//
//  SwitcherPanel.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  The overlay UI that displays window thumbnails in a horizontal strip.
//  Built as an NSPanel with .nonactivatingPanel style mask so it floats
//  above all windows without stealing focus — critical for the Option-release
//  activation flow. The background is user-selectable (status menu →
//  Background): an opaque solid plate (default, WCAG AA-tested label
//  contrast), the classic translucent HUD material, or native Liquid Glass
//  on macOS 26+. Content lives in an NSScrollView wrapping a horizontal
//  NSStackView of ThumbnailView cells. Appears centered on the screen that
//  contains the mouse pointer. Thumbnail clicks are reported through the
//  onWindowClicked callback; previews arriving later are patched into cells
//  in place via updateThumbnail(windowID:image:).
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.3.0
//  Date:    2026-07-02
//  License: MIT
//

import Cocoa

final class SwitcherPanel: NSPanel {

    /// Called with the cell index when the user clicks a thumbnail.
    var onWindowClicked: ((Int) -> Void)?

    /// UserDefaults key for the appearance override: absent/"system", "light", or "dark".
    static let appearanceDefaultsKey = "AppearanceOverride"

    /// UserDefaults key for the panel background style: absent/"solid",
    /// "transparent", or "glass".
    static let backgroundDefaultsKey = "BackgroundStyle"

    private enum BackgroundStyle: String {
        case solid, transparent, glass

        /// Resolves the stored preference: unknown values map to solid, and
        /// "glass" falls back to solid on macOS < 26 where NSGlassEffectView
        /// does not exist.
        static func current() -> BackgroundStyle {
            let raw = UserDefaults.standard.string(forKey: SwitcherPanel.backgroundDefaultsKey) ?? "solid"
            let style = BackgroundStyle(rawValue: raw) ?? .solid
            if style == .glass {
                guard #available(macOS 26.0, *) else { return .solid }
            }
            return style
        }
    }

    private var installedStyle: BackgroundStyle?

    private let itemWidth: CGFloat = 180
    private let itemHeight: CGFloat = 160
    private let itemSpacing: CGFloat = 12
    private let panelPadding: CGFloat = 20

    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var thumbnailViews: [ThumbnailView] = []
    private var windowIDs: [CGWindowID] = []
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
        scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false

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

        installBackground(BackgroundStyle.current())
    }

    /// The opaque, appearance-adaptive plate whose label contrast the
    /// WCAGContrastTests guarantee (>= 4.5:1, WCAG AA). Also the fallback
    /// for unavailable styles.
    private static func makeSolidBackground() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.titlePosition = .noTitle
        box.fillColor = .windowBackgroundColor
        box.borderWidth = 0
        box.cornerRadius = 16
        box.contentViewMargins = .zero
        return box
    }

    /// Re-installs the background root only when the preference changed.
    private func installBackgroundIfNeeded() {
        let style = BackgroundStyle.current()
        if style != installedStyle {
            installBackground(style)
        }
    }

    /// Builds the root view for the style and re-parents the persistent
    /// scroll view into it with the standard panel padding.
    private func installBackground(_ style: BackgroundStyle) {
        scrollView.removeFromSuperview()

        let root: NSView
        let scrollHost: NSView

        switch style {
        case .solid:
            let box = Self.makeSolidBackground()
            root = box
            scrollHost = box

        case .transparent:
            // The classic translucent HUD (pre-1.2 look). Labels are
            // effect-view descendants, so they render with vibrancy; the
            // material is appearance-adaptive and auto-opaques when
            // "Reduce transparency" (Accessibility) is enabled.
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 16
            effect.layer?.masksToBounds = true
            root = effect
            scrollHost = effect

        case .glass:
            if #available(macOS 26.0, *) {
                // NSGlassEffectView only guarantees placement of content
                // assigned to contentView (SDK header contract), so the
                // scroll view lives in an embedded host view.
                let glass = NSGlassEffectView()
                glass.cornerRadius = 16
                glass.style = .regular
                let host = NSView()
                host.translatesAutoresizingMaskIntoConstraints = false
                glass.contentView = host
                NSLayoutConstraint.activate([
                    host.topAnchor.constraint(equalTo: glass.topAnchor),
                    host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
                    host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                    host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                ])
                root = glass
                scrollHost = host
            } else {
                // Unreachable: BackgroundStyle.current() never yields .glass
                // below macOS 26. Kept for exhaustiveness.
                let box = Self.makeSolidBackground()
                root = box
                scrollHost = box
            }
        }

        contentView = root
        scrollHost.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: scrollHost.topAnchor, constant: panelPadding),
            scrollView.bottomAnchor.constraint(equalTo: scrollHost.bottomAnchor, constant: -panelPadding),
            scrollView.leadingAnchor.constraint(equalTo: scrollHost.leadingAnchor, constant: panelPadding),
            scrollView.trailingAnchor.constraint(equalTo: scrollHost.trailingAnchor, constant: -panelPadding),
        ])
        installedStyle = style
    }

    // MARK: - Public API

    func show(windows: [WindowInfo], selectedIndex: Int) {
        applyAppearancePreference()
        installBackgroundIfNeeded()
        self.selectedIndex = selectedIndex

        // Clear old
        thumbnailViews.forEach { $0.removeFromSuperview() }
        thumbnailViews.removeAll()
        windowIDs = windows.map { $0.windowID }

        // Build new
        for (index, windowInfo) in windows.enumerated() {
            let view = ThumbnailView(windowInfo: windowInfo, width: itemWidth, height: itemHeight)
            view.onClicked = { [weak self] in
                self?.handleClick(index: index)
            }
            // Join the hierarchy before setting selection: isSelected resolves
            // and freezes CGColors via effectiveAppearance, which only reflects
            // the panel's forced appearance once the view is parented.
            stackView.addArrangedSubview(view)
            thumbnailViews.append(view)
            view.isSelected = (index == selectedIndex)
        }

        // Size and position the panel on the screen containing the mouse.
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
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
        if selectedIndex < thumbnailViews.count {
            thumbnailViews[selectedIndex].isSelected = false
        }
        selectedIndex = index
        thumbnailViews[selectedIndex].isSelected = true
        scrollToSelected()
    }

    /// Patches a captured preview into its cell without rebuilding the panel.
    func updateThumbnail(windowID: CGWindowID, image: NSImage) {
        guard let index = windowIDs.firstIndex(of: windowID),
              index < thumbnailViews.count else { return }
        thumbnailViews[index].setThumbnail(image)
    }

    func dismiss() {
        orderOut(nil)
        thumbnailViews.forEach { $0.removeFromSuperview() }
        thumbnailViews.removeAll()
        windowIDs.removeAll()
    }

    // MARK: - Private

    /// Applies the user's appearance preference; nil follows the OS theme.
    private func applyAppearancePreference() {
        switch UserDefaults.standard.string(forKey: Self.appearanceDefaultsKey) {
        case "light": appearance = NSAppearance(named: .aqua)
        case "dark": appearance = NSAppearance(named: .darkAqua)
        default: appearance = nil
        }
    }

    private func scrollToSelected() {
        guard selectedIndex < thumbnailViews.count else { return }
        let view = thumbnailViews[selectedIndex]
        scrollView.contentView.scrollToVisible(view.frame)
    }

    private func handleClick(index: Int) {
        updateSelection(index: index)
        onWindowClicked?(index)
    }

    // Allow mouse interaction even though we're non-activating
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
