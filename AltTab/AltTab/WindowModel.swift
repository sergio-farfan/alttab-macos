//
//  WindowModel.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Window enumeration and MRU (most recently used) tracking. Discovers all
//  user windows via CGWindowListCopyWindowInfo for on-screen windows and
//  AXUIElement queries for minimized windows. Maintains MRU order using
//  NSWorkspace activation notifications and per-app AXObservers that track
//  intra-app focused-window changes (e.g., Cmd-` between two Terminal windows).
//  Uses the private _AXUIElementGetWindow SPI to bridge between AXUIElement
//  and CGWindowID — the standard approach for macOS window managers.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.0.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa
import ApplicationServices

// MARK: - WindowInfo

struct WindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let windowTitle: String
    let bounds: CGRect
    let isMinimized: Bool
    var thumbnail: NSImage?

    /// Returns the app icon for this window's owner process.
    var appIcon: NSImage {
        NSRunningApplication(processIdentifier: ownerPID)?.icon ?? NSImage(named: NSImage.applicationIconName)!
    }
}

// MARK: - WindowModel

final class WindowModel {

    /// MRU-ordered list of window IDs. Front of array = most recently used.
    private var mruOrder: [CGWindowID] = []
    private let selfBundleID = Bundle.main.bundleIdentifier ?? ""

    /// Per-PID AXObservers for intra-app window focus tracking.
    private var axObservers: [pid_t: AXObserver] = [:]

    init() {
        seedMRUFromStackingOrder()
        observeAppActivation()
        observeAppLifecycle()
        installAXObserversForRunningApps()
    }

    deinit {
        removeAllAXObservers()
    }

    // MARK: - Enumerate

    /// Returns all user windows, ordered by MRU.
    func enumerateWindows() -> [WindowInfo] {
        var windows: [WindowInfo] = []
        var seenIDs = Set<CGWindowID>()

        // 1. On-screen windows from CGWindowList
        if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                      kCGNullWindowID) as? [[String: Any]] {
            for info in infoList {
                guard let window = parseWindowInfo(info, isMinimized: false) else { continue }
                if seenIDs.contains(window.windowID) { continue }
                seenIDs.insert(window.windowID)
                windows.append(window)
            }
        }

        // 2. Minimized windows via AXUIElement (not in CG list)
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
        for app in runningApps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let axWindows = windowsRef as? [AXUIElement] else { continue }

            for axWindow in axWindows {
                var minimizedRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
                      let isMin = minimizedRef as? Bool, isMin else { continue }

                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? ""

                // Get CGWindowID for this AXUIElement window
                var windowID: CGWindowID = 0
                _ = _AXUIElementGetWindow(axWindow, &windowID)
                guard windowID != 0, !seenIDs.contains(windowID) else { continue }
                seenIDs.insert(windowID)

                let windowInfo = WindowInfo(
                    windowID: windowID,
                    ownerPID: app.processIdentifier,
                    ownerName: app.localizedName ?? "Unknown",
                    windowTitle: title,
                    bounds: .zero,
                    isMinimized: true,
                    thumbnail: nil
                )
                windows.append(windowInfo)
            }
        }

        // 3. Remove our own windows
        windows.removeAll { $0.ownerName == "AltTab" || $0.ownerPID == ProcessInfo.processInfo.processIdentifier }

        // 4. Sort by MRU
        pruneMRU(validIDs: Set(windows.map { $0.windowID }))
        windows.sort { a, b in
            let idxA = mruOrder.firstIndex(of: a.windowID) ?? Int.max
            let idxB = mruOrder.firstIndex(of: b.windowID) ?? Int.max
            return idxA < idxB
        }

        return windows
    }

    // MARK: - MRU Management

    func promoteToFront(windowID: CGWindowID) {
        mruOrder.removeAll { $0 == windowID }
        mruOrder.insert(windowID, at: 0)
    }

    private func seedMRUFromStackingOrder() {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                        kCGNullWindowID) as? [[String: Any]] else { return }
        mruOrder = infoList.compactMap { info -> CGWindowID? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  w > 0 && h > 0 else { return nil }
            return id
        }
    }

    private func pruneMRU(validIDs: Set<CGWindowID>) {
        mruOrder.removeAll { !validIDs.contains($0) }
        // Add any new windows not yet in MRU at the end
        for id in validIDs where !mruOrder.contains(id) {
            mruOrder.append(id)
        }
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
        let axApp = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success else { return }
        let focusedWindow = focusedRef as! AXUIElement
        var windowID: CGWindowID = 0
        _ = _AXUIElementGetWindow(focusedWindow, &windowID)
        if windowID != 0 {
            promoteToFront(windowID: windowID)
        }
    }

    // MARK: - AXObserver (Intra-App Focus Tracking)

    /// Install AXObservers on all currently running regular apps.
    private func installAXObserversForRunningApps() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        for app in apps {
            installAXObserver(for: app.processIdentifier)
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
            promoteToFront(windowID: windowID)
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
        }

        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                           object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.removeAXObserver(for: app.processIdentifier)
        }
    }

    // MARK: - Helpers

    private func parseWindowInfo(_ info: [String: Any], isMinimized: Bool) -> WindowInfo? {
        guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
              let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
              let ownerName = info[kCGWindowOwnerName as String] as? String,
              let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"], let y = boundsDict["Y"],
              let w = boundsDict["Width"], let h = boundsDict["Height"],
              w > 0 && h > 0 else { return nil }

        let title = info[kCGWindowName as String] as? String ?? ""
        let bounds = CGRect(x: x, y: y, width: w, height: h)

        return WindowInfo(
            windowID: windowID,
            ownerPID: ownerPID,
            ownerName: ownerName,
            windowTitle: title,
            bounds: bounds,
            isMinimized: isMinimized,
            thumbnail: nil
        )
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
