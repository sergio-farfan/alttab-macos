//
//  PreferencesMenu.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Status bar dropdown menu with "Launch at Login" toggle (via SMAppService
//  on macOS 13+), "Show Window Previews" toggle (ScreenCaptureKit previews,
//  macOS 14+, requires Screen Recording), About dialog, and Quit. Attached
//  to the NSStatusItem created by AppDelegate.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.2.0
//  Date:    2026-07-01
//  License: MIT
//

import Cocoa
import ServiceManagement

final class PreferencesMenu {

    let menu: NSMenu

    init() {
        menu = NSMenu()

        let launchItem = NSMenuItem(title: "Launch at Login",
                                    action: #selector(toggleLaunchAtLogin(_:)),
                                    keyEquivalent: "")
        launchItem.target = self
        launchItem.state = Self.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        if #available(macOS 14.0, *) {
            let previewsItem = NSMenuItem(title: "Show Window Previews",
                                          action: #selector(toggleWindowPreviews(_:)),
                                          keyEquivalent: "")
            previewsItem.target = self
            previewsItem.state = WindowCapture.previewsEnabled ? .on : .off
            menu.addItem(previewsItem)
        }

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About AltTab",
                                   action: #selector(showAbout(_:)),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit AltTab",
                                  action: #selector(quitApp(_:)),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Launch at Login

    private static var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    sender.state = .off
                } else {
                    try SMAppService.mainApp.register()
                    sender.state = .on
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to update Login Item"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    // MARK: - Window Previews

    @objc private func toggleWindowPreviews(_ sender: NSMenuItem) {
        let enabling = sender.state == .off
        WindowCapture.previewsEnabled = enabling
        sender.state = enabling ? .on : .off

        if enabling && !PermissionManager.hasScreenRecordingPermission {
            PermissionManager.requestScreenRecordingPermission()
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "Window previews need Screen Recording access. "
                + "Grant it to AltTab in System Settings > Privacy & Security > "
                + "Screen & System Audio Recording, then relaunch AltTab. "
                + "Until then, the switcher keeps showing app icons."
            alert.runModal()
        }
    }

    // MARK: - About / Quit

    @objc private func showAbout(_ sender: NSMenuItem) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let alert = NSAlert()
        alert.messageText = "AltTab"
        alert.informativeText = "Windows-style window switcher for macOS.\nVersion \(version)"
        alert.runModal()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
