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
//  Version: 1.0.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa
import ApplicationServices

enum WindowActivator {

    /// Activates the given window: unminimizes if needed, brings app to front, raises window.
    static func activate(window: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else { return }

        // 1. Unminimize if needed
        if window.isMinimized {
            unminimize(window: window)
        }

        // 2. Activate the owning application
        app.activate(options: [.activateIgnoringOtherApps])

        // 3. Raise the specific window via AXUIElement
        raiseWindow(window: window)
    }

    // MARK: - Unminimize

    private static func unminimize(window: WindowInfo) {
        let axApp = AXUIElementCreateApplication(window.ownerPID)
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
