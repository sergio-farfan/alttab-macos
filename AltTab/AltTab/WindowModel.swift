//
//  WindowModel.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Window discovery and MRU (most recently used) tracking. Discovers on-screen
//  windows via CGWindowListCopyWindowInfo, then makes a single Accessibility
//  pass per application that fills in titles (kCGWindowName needs Screen
//  Recording; AX titles only need Accessibility) and finds windows the CG
//  list can't see: minimized, ⌘H-hidden apps, and other Spaces. Every AX call
//  is bounded by a messaging timeout so one wedged app can't stall the
//  switcher (the AX default is ~6 seconds per call).
//
//  Enumeration is split so the switcher opens instantly: windowsFromCache()
//  serves the last gathered list re-sorted by current MRU on the main thread,
//  while refreshWindows() gathers a fresh list off the main thread and
//  reconciles on completion. MRU order is maintained by NSWorkspace activation
//  notifications and per-app AXObservers that track intra-app focused-window
//  changes (e.g. Cmd-` between two Terminal windows). Uses the private
//  _AXUIElementGetWindow SPI to bridge AXUIElement to CGWindowID — the
//  standard approach for macOS window managers.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.2.0
//  Date:    2026-07-01
//  License: MIT
//

import Cocoa
import ApplicationServices

// MARK: - WindowInfo

struct WindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    var windowTitle: String
    let bounds: CGRect
    let isMinimized: Bool
    var thumbnail: NSImage?

    /// Returns the app icon for this window's owner process, served from an in-memory
    /// cache so the switcher never hits LaunchServices/disk while building the panel.
    var appIcon: NSImage {
        AppIconCache.shared.icon(forPID: ownerPID)
    }
}

// MARK: - AppIconCache

/// Caches application icons by PID. `NSRunningApplication.icon` resolves a LaunchServices
/// binding and reads the icon file from disk on every access; doing that per cell on every
/// activation is what made the panel render before its icons appeared (profiled via
/// `sample`: ~6% of main-thread work plus synchronous `open()` calls). NSCache is
/// thread-safe, so main-thread reads and prewarming coexist safely.
final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSNumber, NSImage>()
    private let fallback = NSImage(named: NSImage.applicationIconName)!

    /// Returns a cached icon, resolving and caching it on first request.
    func icon(forPID pid: pid_t) -> NSImage {
        let key = NSNumber(value: pid)
        if let hit = cache.object(forKey: key) { return hit }
        let resolved = NSRunningApplication(processIdentifier: pid)?.icon ?? fallback
        cache.setObject(resolved, forKey: key)
        return resolved
    }

    /// Resolve and cache an icon ahead of time so the first switch is already warm.
    func prewarm(pid: pid_t) {
        let key = NSNumber(value: pid)
        guard cache.object(forKey: key) == nil else { return }
        if let resolved = NSRunningApplication(processIdentifier: pid)?.icon {
            cache.setObject(resolved, forKey: key)
        }
    }

    /// Drop an icon when its app quits so a recycled PID can't surface a stale icon.
    func evict(pid: pid_t) {
        cache.removeObject(forKey: NSNumber(value: pid))
    }
}

// MARK: - WindowModel

/// All state (MRU order, cache, pending activation, observers) is confined to the
/// main thread; only the stateless gather step runs on the background queue.
final class WindowModel {

    private var mru = MRUOrder()
    private var cachedWindows: [WindowInfo] = []
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    /// Explicit activation in flight: the didActivateApplication notification for
    /// this PID must promote this window, not whatever kAXFocusedWindow returns
    /// while the off-main AX raise is still landing.
    private var pendingActivation: (pid: pid_t, windowID: CGWindowID, at: Date)?
    private static let pendingActivationWindow: TimeInterval = 2.0

    /// Upper bound (seconds) on a single AX message. Timeouts are per-element,
    /// so it must be applied to both app and window elements.
    private static let axMessagingTimeout: Float = 0.25

    private let gatherQueue = DispatchQueue(label: "com.alttab.window-gather", qos: .userInitiated)

    /// Per-PID AXObservers for intra-app window focus tracking.
    private var axObservers: [pid_t: AXObserver] = [:]

    init() {
        seedMRUFromStackingOrder()
        observeAppActivation()
        observeAppLifecycle()
        installAXObserversForRunningApps()
        prewarmIcons()
        refreshWindows { _ in } // warm the cache so the first Option-Tab is instant
    }

    deinit {
        removeAllAXObservers()
    }

    // MARK: - Enumeration API (main thread)

    /// Returns the last gathered window list re-sorted by current MRU. Gathers
    /// synchronously only when the cache is empty (first use before the warm-up
    /// completes). Follow with refreshWindows() to reconcile against reality.
    func windowsFromCache() -> [WindowInfo] {
        if cachedWindows.isEmpty {
            cachedWindows = Self.gatherWindows(regularApps: Self.regularAppsSnapshot(), selfPID: selfPID)
            mru.sync(with: cachedWindows.map { $0.windowID })
        }
        return mru.sorted(cachedWindows) { $0.windowID }
    }

    /// Gathers a fresh window list off the main thread, then caches, sorts, and
    /// completes on the main thread.
    func refreshWindows(completion: @escaping ([WindowInfo]) -> Void) {
        let apps = Self.regularAppsSnapshot() // NSWorkspace snapshot taken on main
        let selfPID = self.selfPID
        gatherQueue.async {
            let gathered = Self.gatherWindows(regularApps: apps, selfPID: selfPID)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.cachedWindows = gathered
                self.mru.sync(with: gathered.map { $0.windowID })
                completion(self.mru.sorted(gathered) { $0.windowID })
            }
        }
    }

    // MARK: - Gathering (stateless, any thread)

    private struct AppRef {
        let pid: pid_t
        let name: String
    }

    private static func regularAppsSnapshot() -> [AppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { AppRef(pid: $0.processIdentifier, name: $0.localizedName ?? "Unknown") }
    }

    private static func gatherWindows(regularApps: [AppRef], selfPID: pid_t) -> [WindowInfo] {
        var windows: [WindowInfo] = []
        var seenIDs = Set<CGWindowID>()
        var needsTitle: [CGWindowID: Int] = [:] // windowID → index into windows

        // 1. On-screen windows (any app, current Space) from CGWindowList.
        if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                      kCGNullWindowID) as? [[String: Any]] {
            for info in infoList {
                guard let window = parseWindowInfo(info) else { continue }
                guard window.ownerPID != selfPID, !seenIDs.contains(window.windowID) else { continue }
                seenIDs.insert(window.windowID)
                if window.windowTitle.isEmpty {
                    needsTitle[window.windowID] = windows.count
                }
                windows.append(window)
            }
        }

        // 2. One AX pass per app: titles for on-screen windows, plus discovery of
        //    minimized, hidden-app, and other-Space windows. Covers regular apps
        //    and any non-regular app that owns an on-screen window.
        let regularPIDs = Set(regularApps.map { $0.pid })
        var appNames = Dictionary(regularApps.map { ($0.pid, $0.name) },
                                  uniquingKeysWith: { first, _ in first })
        for window in windows where appNames[window.ownerPID] == nil {
            appNames[window.ownerPID] = window.ownerName
        }
        var axPIDs = regularPIDs.union(windows.map { $0.ownerPID })
        axPIDs.remove(selfPID)

        for pid in axPIDs {
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, axMessagingTimeout)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { continue }

            for axWindow in axWindows {
                AXUIElementSetMessagingTimeout(axWindow, axMessagingTimeout)
                var windowID: CGWindowID = 0
                _ = _AXUIElementGetWindow(axWindow, &windowID)
                guard windowID != 0 else { continue }

                if let index = needsTitle[windowID] {
                    let title = copyString(axWindow, kAXTitleAttribute)
                    if !title.isEmpty {
                        windows[index].windowTitle = title
                    }
                    needsTitle[windowID] = nil
                } else if !seenIDs.contains(windowID), regularPIDs.contains(pid) {
                    // Off-screen: minimized, ⌘H-hidden app, or another Space.
                    let isMinimized = copyBool(axWindow, kAXMinimizedAttribute) ?? false
                    if !isMinimized {
                        // Only standard windows — skips palettes, sheets, popovers.
                        guard copyString(axWindow, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { continue }
                    }
                    seenIDs.insert(windowID)
                    windows.append(WindowInfo(
                        windowID: windowID,
                        ownerPID: pid,
                        ownerName: appNames[pid] ?? "Unknown",
                        windowTitle: copyString(axWindow, kAXTitleAttribute),
                        bounds: .zero,
                        isMinimized: isMinimized,
                        thumbnail: nil
                    ))
                }
            }
        }

        return windows
    }

    private static func parseWindowInfo(_ info: [String: Any]) -> WindowInfo? {
        guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
              let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
              let ownerName = info[kCGWindowOwnerName as String] as? String,
              let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"], let y = boundsDict["Y"],
              let w = boundsDict["Width"], let h = boundsDict["Height"],
              w > 0 && h > 0 else { return nil }

        // kCGWindowName requires Screen Recording; empty titles are filled from
        // the AX pass, which only needs Accessibility.
        return WindowInfo(
            windowID: windowID,
            ownerPID: ownerPID,
            ownerName: ownerName,
            windowTitle: info[kCGWindowName as String] as? String ?? "",
            bounds: CGRect(x: x, y: y, width: w, height: h),
            isMinimized: false,
            thumbnail: nil
        )
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return "" }
        return ref as? String ?? ""
    }

    private static func copyBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? Bool
    }

    // MARK: - MRU Management (main thread)

    /// Records that the user explicitly switched to a window, so the upcoming
    /// app-activation notification can't demote it (the notification may read
    /// kAXFocusedWindow before the off-main AX raise lands).
    func noteExplicitActivation(pid: pid_t, windowID: CGWindowID) {
        mru.promoteToFront(windowID)
        pendingActivation = (pid: pid, windowID: windowID, at: Date())
    }

    private func seedMRUFromStackingOrder() {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                        kCGNullWindowID) as? [[String: Any]] else { return }
        mru.seed(infoList.compactMap { info -> CGWindowID? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 0 && h > 0 else { return nil }
            return id
        })
    }

    private func observeAppActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.promoteAppWindows(pid: app.processIdentifier)
        }
    }

    /// When an app is activated, promote its frontmost window in MRU.
    private func promoteAppWindows(pid: pid_t) {
        if let pending = pendingActivation, pending.pid == pid {
            pendingActivation = nil
            if Date().timeIntervalSince(pending.at) < Self.pendingActivationWindow {
                mru.promoteToFront(pending.windowID)
                return
            }
        }

        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, Self.axMessagingTimeout)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return }
        let focusedWindow = focused as! AXUIElement
        var windowID: CGWindowID = 0
        _ = _AXUIElementGetWindow(focusedWindow, &windowID)
        if windowID != 0 {
            mru.promoteToFront(windowID)
        }
    }

    // MARK: - AXObserver (Intra-App Focus Tracking)

    /// Install AXObservers on all currently running regular apps.
    private func installAXObserversForRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != selfPID
        }
        for app in apps {
            installAXObserver(for: app.processIdentifier)
        }
    }

    /// Warm the icon cache for currently-running apps shortly after launch. Deferred to the
    /// main run loop so it never blocks startup; subsequent launches are warmed via the
    /// didLaunch notification in observeAppLifecycle().
    private func prewarmIcons() {
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { $0.processIdentifier }
        DispatchQueue.main.async {
            for pid in pids { AppIconCache.shared.prewarm(pid: pid) }
        }
    }

    /// Creates an AXObserver for a single app and watches for focused-window changes.
    private func installAXObserver(for pid: pid_t) {
        guard axObservers[pid] == nil else { return }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, axObserverCallback, &observer)
        guard result == .success, let observer = observer else { return }

        let axApp = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, axApp, kAXFocusedWindowChangedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObservers[pid] = observer
    }

    /// Remove observer for a terminated app.
    private func removeAXObserver(for pid: pid_t) {
        guard let observer = axObservers.removeValue(forKey: pid) else { return }
        let axApp = AXUIElementCreateApplication(pid)
        AXObserverRemoveNotification(observer, axApp, kAXFocusedWindowChangedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func removeAllAXObservers() {
        for pid in axObservers.keys {
            removeAXObserver(for: pid)
        }
    }

    /// Called from the AXObserver C callback when any app's focused window changes.
    fileprivate func handleFocusedWindowChanged(_ element: AXUIElement) {
        var windowID: CGWindowID = 0
        _ = _AXUIElementGetWindow(element, &windowID)
        if windowID != 0 {
            mru.promoteToFront(windowID)
        }
    }

    /// Watch for app launches and terminations to manage observer lifecycle.
    private func observeAppLifecycle() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                           object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            self?.installAXObserver(for: app.processIdentifier)
            AppIconCache.shared.prewarm(pid: app.processIdentifier)
        }

        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                           object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.removeAXObserver(for: app.processIdentifier)
            AppIconCache.shared.evict(pid: app.processIdentifier)
        }
    }
}

// Private SPI to get CGWindowID from AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// C callback for AXObserver — bridges to WindowModel.handleFocusedWindowChanged
private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo else { return }
    let model = Unmanaged<WindowModel>.fromOpaque(userInfo).takeUnretainedValue()
    model.handleFocusedWindowChanged(element)
}
