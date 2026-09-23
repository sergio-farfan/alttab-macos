//
//  PreferencesMenu.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Status bar dropdown menu with "Launch at Login" toggle (via SMAppService
//  on macOS 13+), "Switcher Key" submenu (Option / Command — Command
//  replaces the system app switcher), "Appearance" submenu (System / Light / Dark switcher
//  theme override), "Background" submenu (Solid / Transparent / Liquid
//  Glass on macOS 26+), "Show Window Previews" toggle (ScreenCaptureKit
//  previews, macOS 14+, requires Screen Recording), About dialog, and Quit.
//  Attached to the NSStatusItem created by AppDelegate.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.3.3
//  Date:    2026-09-19
//  License: MIT
//

import Cocoa
import ServiceManagement

final class PreferencesMenu {

    let menu: NSMenu

    /// The "Glass Strength" submenu's parent item — greyed out unless the
    /// Background is Liquid Glass, which is the only style it affects.
    private var glassStrengthItem: NSMenuItem?

    /// Called on the main thread when the user picks a different Switcher
    /// Key; AppDelegate forwards it to HotkeyManager so it applies at once.
    var onModifierChanged: ((SwitcherModifier) -> Void)?

    init() {
        menu = NSMenu()
        // Manual enablement so the Glass Strength parent can be greyed out;
        // every other top-level item keeps its default enabled state.
        menu.autoenablesItems = false

        let launchItem = NSMenuItem(title: "Launch at Login",
                                    action: #selector(toggleLaunchAtLogin(_:)),
                                    keyEquivalent: "")
        launchItem.target = self
        launchItem.state = Self.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        let modifierItem = NSMenuItem(title: "Switcher Key", action: nil, keyEquivalent: "")
        let modifierMenu = NSMenu()
        for modifier in SwitcherModifier.allCases {
            let item = NSMenuItem(title: modifier.title,
                                  action: #selector(selectModifier(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = modifier.rawValue
            if modifier == .command {
                item.toolTip = "Replaces the system Cmd-Tab app switcher while AltTab is running."
            }
            modifierMenu.addItem(item)
        }
        modifierItem.submenu = modifierMenu
        menu.addItem(modifierItem)
        refreshModifierChecks(in: modifierMenu)

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for (title, value) in [("System", "system"), ("Light", "light"), ("Dark", "dark")] {
            let item = NSMenuItem(title: title,
                                  action: #selector(selectAppearance(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = value
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)
        refreshAppearanceChecks(in: appearanceMenu)

        let backgroundItem = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        let backgroundMenu = NSMenu()
        var backgroundChoices = [("Solid", "solid"), ("Transparent", "transparent")]
        if #available(macOS 26.0, *) {
            backgroundChoices.append(("Liquid Glass", "glass"))
        }
        for (title, value) in backgroundChoices {
            let item = NSMenuItem(title: title,
                                  action: #selector(selectBackground(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = value
            backgroundMenu.addItem(item)
        }
        backgroundItem.submenu = backgroundMenu
        menu.addItem(backgroundItem)
        refreshBackgroundChecks(in: backgroundMenu)

        if #available(macOS 26.0, *) {
            let strengthItem = NSMenuItem(title: "Glass Strength", action: nil, keyEquivalent: "")
            let strengthMenu = NSMenu()
            for level in GlassStrength.allCases {
                let item = NSMenuItem(title: level.title,
                                      action: #selector(selectGlassStrength(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = level.rawValue
                strengthMenu.addItem(item)
            }
            strengthItem.submenu = strengthMenu
            menu.addItem(strengthItem)
            glassStrengthItem = strengthItem
            refreshGlassStrengthChecks(in: strengthMenu)
            updateGlassStrengthEnabled()
        }

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

    // MARK: - Switcher Key

    /// The stored choice; absent means the default (Option).
    static var currentModifier: SwitcherModifier {
        SwitcherModifier.resolve(UserDefaults.standard.string(forKey: SwitcherModifier.defaultsKey))
    }

    @objc private func selectModifier(_ sender: NSMenuItem) {
        let modifier = SwitcherModifier.resolve(sender.representedObject as? String)
        if modifier == SwitcherModifier.defaultModifier {
            UserDefaults.standard.removeObject(forKey: SwitcherModifier.defaultsKey)
        } else {
            UserDefaults.standard.set(modifier.rawValue, forKey: SwitcherModifier.defaultsKey)
        }
        if let menu = sender.menu {
            refreshModifierChecks(in: menu)
        }
        onModifierChanged?(modifier)
    }

    private func refreshModifierChecks(in menu: NSMenu) {
        let current = Self.currentModifier
        for item in menu.items {
            item.state = ((item.representedObject as? String) == current.rawValue) ? .on : .off
        }
    }

    // MARK: - Appearance

    @objc private func selectAppearance(_ sender: NSMenuItem) {
        let value = sender.representedObject as? String ?? "system"
        if value == "system" {
            UserDefaults.standard.removeObject(forKey: SwitcherPanel.appearanceDefaultsKey)
        } else {
            UserDefaults.standard.set(value, forKey: SwitcherPanel.appearanceDefaultsKey)
        }
        if let menu = sender.menu {
            refreshAppearanceChecks(in: menu)
        }
    }

    private func refreshAppearanceChecks(in menu: NSMenu) {
        let current = UserDefaults.standard.string(forKey: SwitcherPanel.appearanceDefaultsKey) ?? "system"
        for item in menu.items {
            item.state = ((item.representedObject as? String) == current) ? .on : .off
        }
    }

    // MARK: - Background

    @objc private func selectBackground(_ sender: NSMenuItem) {
        let value = sender.representedObject as? String ?? "solid"
        if value == "solid" {
            UserDefaults.standard.removeObject(forKey: SwitcherPanel.backgroundDefaultsKey)
        } else {
            UserDefaults.standard.set(value, forKey: SwitcherPanel.backgroundDefaultsKey)
        }
        if let menu = sender.menu {
            refreshBackgroundChecks(in: menu)
        }
        updateGlassStrengthEnabled()
    }

    private func refreshBackgroundChecks(in menu: NSMenu) {
        let current = UserDefaults.standard.string(forKey: SwitcherPanel.backgroundDefaultsKey) ?? "solid"
        for item in menu.items {
            item.state = ((item.representedObject as? String) == current) ? .on : .off
        }
    }

    // MARK: - Glass Strength

    @objc private func selectGlassStrength(_ sender: NSMenuItem) {
        let level = GlassStrength.resolve(sender.representedObject as? String)
        if level == GlassStrength.defaultLevel {
            UserDefaults.standard.removeObject(forKey: SwitcherPanel.glassStrengthDefaultsKey)
        } else {
            UserDefaults.standard.set(level.rawValue, forKey: SwitcherPanel.glassStrengthDefaultsKey)
        }
        if let menu = sender.menu {
            refreshGlassStrengthChecks(in: menu)
        }
    }

    private func refreshGlassStrengthChecks(in menu: NSMenu) {
        let current = GlassStrength.resolve(UserDefaults.standard.string(forKey: SwitcherPanel.glassStrengthDefaultsKey))
        for item in menu.items {
            item.state = ((item.representedObject as? String) == current.rawValue) ? .on : .off
        }
    }

    /// Strength only applies to the Liquid Glass background.
    private func updateGlassStrengthEnabled() {
        glassStrengthItem?.isEnabled =
            UserDefaults.standard.string(forKey: SwitcherPanel.backgroundDefaultsKey) == "glass"
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
