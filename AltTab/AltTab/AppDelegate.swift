//
//  AppDelegate.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Application lifecycle and orchestration. Sets up the menu bar status item,
//  manages permissions, and coordinates the hotkey manager, window model,
//  preview capture, and switcher panel. Implements HotkeyDelegate to respond
//  to modifier-Tab state machine transitions (Option by default, Command
//  when the Switcher Key setting replaces the system app switcher). Activation shows the cached
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
    /// Per-session selection state (initial anchor, cycling, reconcile policy)
    /// — pure logic in AltTabCore, unit-tested in SwitcherSelectionTests.
    private var selection = SwitcherSelection()
    /// Focus anchor captured once per session. reconcile() must re-anchor
    /// against the same reference point the session opened with — re-probing
    /// would expose the selection to focus drift (a sheet appearing, background
    /// churn) while the switcher is up.
    private var sessionFocusedID: CGWindowID?
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
            self.selection.select(index: index)
            // The modifier may still be held — end the tap session so its
            // release doesn't re-confirm and Tab can start a fresh session.
            self.hotkeyManager.cancelSession()
            self.hotkeyDidConfirm()
        }

        hotkeyManager = HotkeyManager()
        hotkeyManager.delegate = self
        hotkeyManager.modifier = PreferencesMenu.currentModifier
        preferencesMenu.onModifierChanged = { [weak self] modifier in
            self?.hotkeyManager.modifier = modifier
            NSLog("AltTab: Switcher Key set to %@", modifier.rawValue)
        }

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
                    // WindowModel was built pre-grant, so its AXObserver
                    // registrations failed — intra-app focus tracking would
                    // stay dead until relaunch without this.
                    self.windowModel.reinstallAXObservers()
                    self.hotkeyManager.start()
                } else {
                    NSLog("AltTab: Accessibility still not trusted, prompting user")
                    self.permissionManager.ensureAccessibility()
                    NotificationCenter.default.addObserver(
                        forName: .accessibilityGranted, object: nil, queue: .main
                    ) { [weak self] _ in
                        NSLog("AltTab: Accessibility granted, starting hotkey manager")
                        self?.windowModel.reinstallAXObservers()
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
                button.title = PreferencesMenu.currentModifier.symbol + "⇥"
            }
        }
        preferencesMenu = PreferencesMenu()
        statusItem.menu = preferencesMenu.menu
        NSLog("AltTab: Status item installed")
    }

    // MARK: - HotkeyDelegate

    func hotkeyDidActivate(reverse: Bool) {
        switchSession += 1
        let session = switchSession

        currentWindows = windowModel.windowsFromCache()
        guard !currentWindows.isEmpty else {
            // Nothing to show — end the tap session so Tab isn't swallowed
            // dead, and kick a gather so an immediate retry can succeed (a
            // cold launch with zero on-screen windows serves an empty list).
            // Coalescible: its completion drives nothing, so mashed retries
            // must not backlog the serial gather queue.
            hotkeyManager.cancelSession()
            windowModel.refreshWindows(coalescible: true) { _ in }
            return
        }
        // Anchor against the actual focused window: the cache can be stale
        // (a window opened since the last gather is missing from it), in which
        // case slot 0 already holds the previous window and the classic
        // slot-1 anchor would jump one slot too far.
        sessionFocusedID = windowModel.frontmostWindowID()
        selection.activate(windowIDs: currentWindows.map { $0.windowID },
                           focusedWindowID: sessionFocusedID,
                           reverse: reverse)
        switcherActive = true
        switcherPanel.show(windows: currentWindows, selectedIndex: selection.selectedIndex)

        // Reconcile against a fresh gather off the main thread.
        windowModel.refreshWindows { [weak self] fresh in
            guard let self = self, self.switcherActive, self.switchSession == session else { return }
            self.reconcile(with: fresh)
            self.startPreviewCapture(session: session)
        }
    }

    func hotkeyDidCycleNext() {
        guard switcherActive, !currentWindows.isEmpty else { return }
        selection.cycleNext()
        switcherPanel.updateSelection(index: selection.selectedIndex)
    }

    func hotkeyDidCyclePrevious() {
        guard switcherActive, !currentWindows.isEmpty else { return }
        selection.cyclePrevious()
        switcherPanel.updateSelection(index: selection.selectedIndex)
    }

    func hotkeyDidConfirm() {
        guard switcherActive, !currentWindows.isEmpty,
              selection.selectedIndex < currentWindows.count else {
            dismissSwitcher()
            return
        }
        // The cache can hold ghosts (windows closed since the last gather);
        // activating one would surface an arbitrary window. Fall through the
        // confirmation order to the first window that still exists — verified
        // with one batched WindowServer query.
        let byID = Dictionary(currentWindows.map { ($0.windowID, $0) },
                              uniquingKeysWith: { first, _ in first })
        let candidates = selection.confirmationOrder.compactMap { byID[$0] }
        let live = WindowActivator.liveWindowIDs(candidates.map { $0.windowID })
        dismissSwitcher()
        guard let window = candidates.first(where: { live.contains($0.windowID) }) else { return }
        WindowActivator.activate(window: window)
        windowModel.noteExplicitActivation(pid: window.ownerPID, windowID: window.windowID)
    }

    func hotkeyDidCancel() {
        dismissSwitcher()
    }

    // MARK: - Quit / Hide selected app (Q / H while the switcher is up)

    func hotkeyDidQuitSelected() {
        guard let app = selectedRunningApplication() else { return }
        NSLog("AltTab: quitting %@ (pid %d) from the switcher", app.localizedName ?? "?", app.processIdentifier)
        app.terminate()
        // Drop its windows from the session right away instead of waiting for
        // the termination notification → debounced re-gather. The session
        // stays open (native Cmd+Tab convention) unless nothing is left.
        let pid = app.processIdentifier
        let remaining = currentWindows.filter { $0.ownerPID != pid }
        guard !remaining.isEmpty else {
            hotkeyManager.cancelSession()
            dismissSwitcher()
            return
        }
        currentWindows = remaining
        // After a cycle the selection follows its window ID; that ID is gone,
        // so reconcile lands on the same slot — now the next window. Before a
        // cycle it re-anchors against the (possibly quit) focused window.
        selection.reconcile(windowIDs: remaining.map { $0.windowID },
                            focusedWindowID: sessionFocusedID)
        switcherPanel.show(windows: remaining, selectedIndex: selection.selectedIndex)
    }

    func hotkeyDidHideSelected() {
        guard let app = selectedRunningApplication() else { return }
        NSLog("AltTab: hiding %@ (pid %d) from the switcher", app.localizedName ?? "?", app.processIdentifier)
        app.hide()
        // Hidden apps stay listed (the switcher includes ⌘H-hidden windows),
        // so the panel needs no rebuild and the selection stays put.
    }

    /// The app owning the highlighted window, or nil when there is no live
    /// session / selection. Never AltTab itself.
    private func selectedRunningApplication() -> NSRunningApplication? {
        guard switcherActive, selection.selectedIndex < currentWindows.count else { return nil }
        let pid = currentWindows[selection.selectedIndex].ownerPID
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    // MARK: - Refresh & Previews

    /// Applies a freshly gathered window list to an active switcher: carries
    /// over captured previews and rebuilds the panel only if the window set or
    /// order actually changed. Selection policy lives in SwitcherSelection:
    /// re-anchor while the user hasn't cycled (so a stale initial default
    /// can't survive the corrected list), follow the selected window after a
    /// manual cycle or click.
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

        let idsChanged = updated.map { $0.windowID } != currentWindows.map { $0.windowID }
        let oldIndex = selection.selectedIndex
        currentWindows = updated
        selection.reconcile(windowIDs: updated.map { $0.windowID },
                            focusedWindowID: sessionFocusedID)

        if idsChanged {
            switcherPanel.show(windows: updated, selectedIndex: selection.selectedIndex)
        } else if selection.selectedIndex != oldIndex {
            switcherPanel.updateSelection(index: selection.selectedIndex)
        }
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
