//
//  AppDelegate.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Application lifecycle and orchestration. Sets up the menu bar status item,
//  manages permissions, and coordinates the hotkey manager, window model,
//  preview capture, and switcher panel. Implements HotkeyDelegate to respond
//  to Option-Tab state machine transitions. Activation shows the cached
//  window list instantly, then reconciles against a fresh gather off the
//  main thread; async completions are guarded by a session epoch so a stale
//  refresh or preview can never touch a newer switcher session.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.2.0
//  Date:    2026-07-01
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
    private var switcherActive: Bool = false
    /// Incremented on every activation; async completions (refresh, previews)
    /// belonging to an older session are dropped.
    private var switchSession: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("AltTab: applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        permissionManager = PermissionManager()

        windowModel = WindowModel()
        windowCapture = WindowCapture()
        switcherPanel = SwitcherPanel()
        switcherPanel.onWindowClicked = { [weak self] index in
            guard let self = self, self.switcherActive, index < self.currentWindows.count else { return }
            self.selectedIndex = index
            // Option may still be held — end the tap session so its release
            // doesn't re-confirm and Tab can start a fresh session.
            self.hotkeyManager.cancelSession()
            self.hotkeyDidConfirm()
        }

        hotkeyManager = HotkeyManager()
        hotkeyManager.delegate = self

        if AXIsProcessTrusted() {
            hotkeyManager.start()
            NSLog("AltTab: Accessibility already granted, hotkey active")
        } else {
            // At login the TCC daemon may not be ready yet, causing a false negative.
            // Wait briefly and recheck before prompting the user.
            NSLog("AltTab: Accessibility not yet trusted, will recheck before prompting")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self else { return }
                if AXIsProcessTrusted() {
                    NSLog("AltTab: Accessibility granted after brief wait, hotkey active")
                    self.hotkeyManager.start()
                } else {
                    NSLog("AltTab: Accessibility still not trusted, prompting user")
                    self.permissionManager.ensureAccessibility()
                    NotificationCenter.default.addObserver(
                        forName: .accessibilityGranted, object: nil, queue: .main
                    ) { [weak self] _ in
                        NSLog("AltTab: Accessibility granted, starting hotkey manager")
                        self?.hotkeyManager.start()
                    }
                }
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
        switchSession += 1
        let session = switchSession

        currentWindows = windowModel.windowsFromCache()
        guard !currentWindows.isEmpty else {
            // Nothing to show — end the tap session so Tab isn't swallowed dead.
            hotkeyManager.cancelSession()
            return
        }
        selectedIndex = min(1, currentWindows.count - 1) // start on second window (MRU)
        switcherActive = true
        switcherPanel.show(windows: currentWindows, selectedIndex: selectedIndex)

        // Reconcile against a fresh gather off the main thread.
        windowModel.refreshWindows { [weak self] fresh in
            guard let self = self, self.switcherActive, self.switchSession == session else { return }
            self.reconcile(with: fresh)
            self.startPreviewCapture(session: session)
        }
    }

    func hotkeyDidCycleNext() {
        guard switcherActive, !currentWindows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % currentWindows.count
        switcherPanel.updateSelection(index: selectedIndex)
    }

    func hotkeyDidCyclePrevious() {
        guard switcherActive, !currentWindows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + currentWindows.count) % currentWindows.count
        switcherPanel.updateSelection(index: selectedIndex)
    }

    func hotkeyDidConfirm() {
        guard switcherActive, !currentWindows.isEmpty,
              selectedIndex < currentWindows.count else {
            dismissSwitcher()
            return
        }
        let window = currentWindows[selectedIndex]
        dismissSwitcher()
        WindowActivator.activate(window: window)
        windowModel.noteExplicitActivation(pid: window.ownerPID, windowID: window.windowID)
    }

    func hotkeyDidCancel() {
        dismissSwitcher()
    }

    // MARK: - Refresh & Previews

    /// Applies a freshly gathered window list to an active switcher: carries
    /// over captured previews, keeps the selection on the same window, and
    /// rebuilds the panel only if the window set or order actually changed.
    private func reconcile(with fresh: [WindowInfo]) {
        guard !fresh.isEmpty else {
            hotkeyManager.cancelSession()
            dismissSwitcher()
            return
        }

        let thumbnails = Dictionary(currentWindows.compactMap { window in window.thumbnail.map { (window.windowID, $0) } },
                                    uniquingKeysWith: { first, _ in first })
        var updated = fresh
        for index in updated.indices {
            updated[index].thumbnail = thumbnails[updated[index].windowID]
        }

        let selectedID = currentWindows.indices.contains(selectedIndex) ? currentWindows[selectedIndex].windowID : nil
        let changed = updated.map { $0.windowID } != currentWindows.map { $0.windowID }
        currentWindows = updated
        guard changed else { return }

        if let id = selectedID, let index = updated.firstIndex(where: { $0.windowID == id }) {
            selectedIndex = index
        } else {
            selectedIndex = min(selectedIndex, updated.count - 1)
        }
        switcherPanel.show(windows: updated, selectedIndex: selectedIndex)
    }

    private func startPreviewCapture(session: Int) {
        windowCapture.capturePreviews(for: currentWindows) { [weak self] windowID, image in
            guard let self = self, self.switcherActive, self.switchSession == session else { return }
            if let index = self.currentWindows.firstIndex(where: { $0.windowID == windowID }) {
                self.currentWindows[index].thumbnail = image
            }
            self.switcherPanel.updateThumbnail(windowID: windowID, image: image)
        }
    }

    private func dismissSwitcher() {
        switcherActive = false
        windowCapture.cancel()
        switcherPanel.dismiss()
    }
}
