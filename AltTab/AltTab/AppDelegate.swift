//
//  AppDelegate.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Application lifecycle and orchestration. Sets up the menu bar status item,
//  manages permissions, and coordinates the hotkey manager, window model,
//  thumbnail capture, and switcher panel. Implements HotkeyDelegate to
//  respond to Option-Tab state machine transitions.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.0.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, HotkeyDelegate {

    private var statusItem: NSStatusItem!
    private var preferencesMenu: PreferencesMenu!
    private var hotkeyManager: HotkeyManager!
    private var windowModel: WindowModel!
    private var windowCapture: WindowCapture!
    private var switcherPanel: SwitcherPanel!
    private var permissionManager: PermissionManager!

    private var currentWindows: [WindowInfo] = []
    private var selectedIndex: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("AltTab: applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        permissionManager = PermissionManager()

        windowModel = WindowModel()
        windowCapture = WindowCapture()
        switcherPanel = SwitcherPanel()

        hotkeyManager = HotkeyManager()
        hotkeyManager.delegate = self

        if AXIsProcessTrusted() {
            hotkeyManager.start()
            NSLog("AltTab: Accessibility already granted, hotkey active")
        } else {
            permissionManager.ensureAccessibility()
            NotificationCenter.default.addObserver(
                forName: .accessibilityGranted, object: nil, queue: .main
            ) { [weak self] _ in
                NSLog("AltTab: Accessibility granted, starting hotkey manager")
                self?.hotkeyManager.start()
            }
        }
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                  accessibilityDescription: "AltTab") {
                img.isTemplate = true
                button.image = img
            } else {
                // Fallback if SF Symbol unavailable
                button.title = "⌥⇥"
            }
        }
        preferencesMenu = PreferencesMenu()
        statusItem.menu = preferencesMenu.menu
        NSLog("AltTab: Status item installed")
    }

    // MARK: - HotkeyDelegate

    func hotkeyDidActivate() {
        currentWindows = windowModel.enumerateWindows()
        guard !currentWindows.isEmpty else { return }
        selectedIndex = min(1, currentWindows.count - 1) // start on second window (MRU)

        // Capture thumbnails asynchronously
        windowCapture.captureThumbnails(for: currentWindows) { [weak self] updatedWindows in
            guard let self = self else { return }
            self.currentWindows = updatedWindows
            DispatchQueue.main.async {
                self.switcherPanel.show(windows: self.currentWindows,
                                        selectedIndex: self.selectedIndex)
            }
        }

        // Show immediately with placeholder icons
        switcherPanel.show(windows: currentWindows, selectedIndex: selectedIndex)
    }

    func hotkeyDidCycleNext() {
        guard !currentWindows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % currentWindows.count
        switcherPanel.updateSelection(index: selectedIndex)
    }

    func hotkeyDidCyclePrevious() {
        guard !currentWindows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + currentWindows.count) % currentWindows.count
        switcherPanel.updateSelection(index: selectedIndex)
    }

    func hotkeyDidConfirm() {
        let window = currentWindows[selectedIndex]
        switcherPanel.dismiss()
        WindowActivator.activate(window: window)
        windowModel.promoteToFront(windowID: window.windowID)
    }

    func hotkeyDidCancel() {
        switcherPanel.dismiss()
    }
}
