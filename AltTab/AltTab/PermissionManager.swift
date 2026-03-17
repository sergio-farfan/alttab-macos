//
//  PermissionManager.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Manages macOS permission requirements. Checks and prompts for Accessibility
//  access (required for CGEvent taps and AXUIElement window management) with
//  a polling timer that posts a notification when granted. Detects Screen
//  Recording permission by probing CGWindowListCopyWindowInfo for window names.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.0.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa
import ApplicationServices

final class PermissionManager {

    private var pollTimer: Timer?

    /// Checks Accessibility permission, prompting if needed, and polls until granted.
    func ensureAccessibility() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            promptForAccessibility()
            startPolling()
        }
    }

    /// Shows the system prompt for Accessibility permission.
    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Polls every 2 seconds until Accessibility is granted.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                self?.pollTimer = nil
                NotificationCenter.default.post(name: .accessibilityGranted, object: nil)
            }
        }
    }

    /// Returns true if Screen Recording permission appears to be granted.
    /// There's no direct API — we test by attempting a zero-size CGWindow capture.
    static var hasScreenRecordingPermission: Bool {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]]
        // If we can read window names, permission is granted
        guard let list = windowList, let first = list.first else { return false }
        return first[kCGWindowName] != nil
    }
}

extension Notification.Name {
    static let accessibilityGranted = Notification.Name("com.alttab.accessibilityGranted")
}
