//
//  PermissionManager.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Manages macOS permission requirements. Checks and prompts for Accessibility
//  access (required for CGEvent taps and AXUIElement window management) with
//  a polling timer that posts a notification when granted. Screen Recording
//  (needed only for the opt-in window previews) is checked silently via
//  CGPreflightScreenCaptureAccess and requested via CGRequestScreenCaptureAccess.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.2.0
//  Date:    2026-07-01
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
        pollTimer?.tolerance = 0.5 // let the kernel coalesce wakeups
    }

    // MARK: - Screen Recording (window previews only)

    /// True when Screen Recording is already granted. Never prompts.
    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts for Screen Recording access if not yet granted (macOS shows at
    /// most one system prompt). Returns true when access is already granted.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

extension Notification.Name {
    static let accessibilityGranted = Notification.Name("com.alttab.accessibilityGranted")
}
