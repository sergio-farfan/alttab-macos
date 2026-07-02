//
//  WindowActivator.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Handles the actual window switching: unminimizes if needed, activates the
//  owning application, and raises the specific window via AXUIElement. Window
//  matching uses CGWindowID first (via _AXUIElementGetWindow), falling back
//  to title matching, then first-window-of-app as a last resort.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.1.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa
import ApplicationServices

enum WindowActivator {

    /// Serial queue for the synchronous Accessibility IPC involved in raising a window.
    /// Kept off the main thread so a slow/busy target app can't freeze the switcher on
    /// confirm — profiled via `sample` as ~75% of main-thread activation cost, dominated
    /// by AXUIElementCopyAttributeValue(kAXWindows) blocking in mach_msg. Client-side AX
    /// queries against other apps are safe off-main; each call is additionally bounded by
    /// a messaging timeout (see below).
    private static let axQueue = DispatchQueue(label: "com.alttab.window-activator", qos: .userInitiated)

    /// Upper bound (seconds) on a single AX message. Long enough for a legitimately busy
    /// app to answer, short enough that a wedged app can't tie up the queue indefinitely.
    private static let axMessagingTimeout: Float = 1.0

    /// Activates the given window: brings the owning app forward on the main thread, then
    /// unminimizes (if needed) and raises the specific window via AXUIElement off the main
    /// thread so confirm returns immediately and the UI never blocks.
    static func activate(window: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else { return }

        // Bring the owning app forward on the main thread — this is an AppKit call and is
        // cheap (~1% of activation cost); AppKit is not safe to touch off the main thread.
        // activateIgnoringOtherApps is deprecated on macOS 14+, where plain activate()
        // has the same effect for a user-initiated switch.
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        // The expensive part — synchronous AX IPC to fetch the app's window list and raise
        // the target — runs off the main thread.
        axQueue.async {
            if window.isMinimized {
                unminimize(window: window)
            }
            raiseWindow(window: window)
        }
    }

    // MARK: - Unminimize

    private static func unminimize(window: WindowInfo) {
        let axApp = AXUIElementCreateApplication(window.ownerPID)
        AXUIElementSetMessagingTimeout(axApp, axMessagingTimeout)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        for axWindow in axWindows {
            var windowID: CGWindowID = 0
            _ = _AXUIElementGetWindow(axWindow, &windowID)

            if windowID == window.windowID {
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
                break
            }
        }
    }

    // MARK: - Raise Window

    private static func raiseWindow(window: WindowInfo) {
        let axApp = AXUIElementCreateApplication(window.ownerPID)
        AXUIElementSetMessagingTimeout(axApp, axMessagingTimeout)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        // Try to match by CGWindowID first
        for axWindow in axWindows {
            var windowID: CGWindowID = 0
            _ = _AXUIElementGetWindow(axWindow, &windowID)

            if windowID == window.windowID {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                return
            }
        }

        // Fallback: match by title + approximate bounds
        for axWindow in axWindows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            let title = titleRef as? String ?? ""

            if title == window.windowTitle && !title.isEmpty {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                return
            }
        }

        // Last resort: raise the first window
        if let firstWindow = axWindows.first {
            AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(firstWindow, kAXMainAttribute as CFString, true as CFTypeRef)
        }
    }
}
