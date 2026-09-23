# Changelog

All notable changes to AltTab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.4] - 2026-09-23

### Added

- **Switcher Key** (status menu): Option (default) or **Command**. Command makes Cmd-Tab open AltTab's window switcher in place of the system app switcher — the session-level event tap swallows the Cmd-Tab keyDown before the Dock sees it, so no Keyboard Shortcuts changes are needed. Applies to the next keypress, no relaunch. The choice lives in the pure `SwitcherModifier` type (unit-tested).
- **Q / H while the switcher is open** quit or hide the selected window's app and keep the switcher up (native Cmd-Tab convention; both modifier modes). A quit app's windows leave the list immediately.

### Changed

- **CI runs the unit tests**: `swift test` now gates the release workflow (before anything is built) and runs on every push and pull request via the new `tests.yml`. Until now the suite was only ever compiled, never executed in CI.
- While a switcher session is active, **every other keyDown is swallowed** (previously passed through). The modifier is still held, so a leaked key would reach the frontmost app as a chord — with Command as the modifier that was a fumbled Cmd-Q/Cmd-W on the wrong window.

## [1.3.3] - 2026-09-19

### Added

- **Glass Strength** (status menu, macOS 26+): Light / Medium / High / Max for the Liquid Glass background. `NSGlassEffectView` has no intensity API, so the levels are emulated: **High** is the previous look (regular glass), **Light** and **Medium** lay an appearance-adaptive translucent plate over the glass, and **Max** switches to the clear glass style. Applies on the next Option-Tab, no relaunch; the submenu is greyed out unless the Background is Liquid Glass.
- **Homebrew install**: `brew install --cask sergio-farfan/tap/alttab`, via the new [`sergio-farfan/homebrew-tap`](https://github.com/sergio-farfan/homebrew-tap). The release workflow notifies the tap so the cask follows each release automatically once the `TAP_DISPATCH_TOKEN` secret is configured.

### Changed

- First-launch guidance for the unsigned build follows Apple's current flow (System Settings → Privacy & Security → **Open Anyway**); right-click → Open no longer bypasses Gatekeeper on recent macOS.

## [1.3.2] - 2026-09-12

### Added

- **Option+Shift+Tab as the initial invoke** now opens the switcher cycling backward: the selection anchors on the least-recently-used window (Windows convention) instead of behaving like a forward invoke, and the mid-session reconcile keeps the backward anchor until the user cycles.

### Fixed

- **Stale switcher after idle**: the window cache was only re-gathered while the switcher was open, so the first invoke after a long pause served a list frozen at the previous session. Focus changes, app activations, launches, and terminations now schedule a debounced (1s) background refresh that keeps the cache warm, rate-limited to one background sweep per 8s under sustained switching (the trailing sweep is pushed back, never dropped), and superseded background sweeps are skipped so they can never delay the switcher's own refresh.
- **One wedged app erasing its windows' MRU ranks**: a single 0.25s Accessibility timeout during a gather dropped that app's minimized/other-Space windows from the list, pruning their MRU ranks; the next successful gather re-appended them at the tail (far from where the user last saw them). Windows owned by apps that failed the AX pass — including a wedge mid-enumeration after the window list was returned — are now carried over from the previous cache (`GatherMerge`), preserving both panel membership and ranks.

### Changed (performance)

- The per-app Accessibility pass in the window gather runs concurrently instead of sequentially — previously each wedged app stacked its 0.25s timeouts onto the total gather time — and visits apps in sorted-pid order so discovery order is deterministic.
- `WindowActivator` now sets the Accessibility messaging timeout on each *window* element (timeouts are per-element); previously the unminimize/raise/title calls against a wedged app waited on the ~6s AX default per call, serializing behind one another on the activation queue.
- The focused-window probe on app activation moved off the main thread (it is synchronous IPC bounded by a 0.25s timeout), so activating a busy app can no longer stall the run loop that services the event tap. A focus-epoch guard drops a late probe result once any newer focus signal has been recorded.
- The cold-cache path (first Option-Tab before the launch warm-up lands) serves on-screen windows from one WindowServer query instead of running the full synchronous AX gather on the event tap's run loop, which risked the tap being disabled by timeout. That first panel can briefly omit minimized/other-Space windows and titles until the async gather reconciles (~a second).
- App-icon prewarming resolves icons on a utility queue instead of the main run loop.

## [1.3.1] - 2026-09-10

### Fixed

- **First Option-Tab landing on the wrong window** after the switcher had been idle: the panel is served from a cached window list re-sorted by live MRU order, so a window opened (or closed) since the last gather shifted every slot by one and a single Tab jumped to the 2nd/3rd-most-recent window. The initial selection is now anchored against the window that actually has focus (cheap WindowServer probe, with a bounded Accessibility fallback only when the focused window is unknown to the cache), and the mid-session reconcile re-anchors against the fresh list unless the user has already cycled or clicked.
- **Background apps corrupting the MRU order**: `kAXFocusedWindowChanged` from non-frontmost apps (Electron/Chromium window churn, windows closed by finished jobs) promoted their windows to the front while the user worked elsewhere. Promotions are now accepted only from the frontmost app.
- **Confirming a stale (already-closed) entry raised an arbitrary window**: the raise-first-window fallback in `WindowActivator` is gone, and confirm now skips ghost windows via a single batched liveness query, falling through to the next live window in MRU order.
- **Intra-app focus tracking silently dead after every update**: `AXObserverAddNotification` failures (Accessibility not yet granted, app's AX server not up) were stored as if they had succeeded and never retried. Observers now register only on success, are reinstalled when Accessibility is granted after launch, retry once for just-launched apps, and self-heal on an app's first activation.
- Rapid Option-Tab toggling right after a switch no longer anchors on the window just switched to (the in-flight activation is treated as focus ground truth), and a pending activation is superseded when a different app or window takes focus.

### Changed

- Per-session selection logic (initial anchor, cycling, reconcile policy, confirmation order) extracted from `AppDelegate` into a pure `SwitcherSelection` type in `AltTabCore`, covered by unit tests.

## [1.3.0] - 2026-07-02

### Added

- Appearance setting (status menu): System / Light / Dark. Default follows the OS theme, including scheduled Auto switching.
- Background setting (status menu): **Solid** (default), **Transparent** (the classic translucent HUD), and **Liquid Glass** (native `NSGlassEffectView`, macOS 26+).

### Changed

- Switcher labels use semantic system colors that adapt to light/dark. On the default Solid background the label/background pair meets WCAG 2.x AA (contrast >= 4.5:1), verified by unit tests (`WCAGContrastTests`) that resolve the live system colors in both appearances. Transparent and Liquid Glass are aesthetic opt-ins where contrast depends on the wallpaper; labels there render with the system's vibrancy / glass legibility treatments.
- The Solid background is always opaque; the Transparent material auto-opaques when macOS "Reduce transparency" (Accessibility) is enabled.

## [1.2.1] - 2026-07-01

### Fixed

- Option-Tab dead after updating, with the Accessibility toggle in System Settings still showing ON. Unsigned distribution shipped an *unsealed* bundle (bare linker-signed arm64 slice, unsigned x86_64 slice, no `_CodeSignature`), so macOS fabricated unpredictable code identities and the TCC Accessibility grant never matched the running app. `package-dmg.sh` now applies a deterministic ad-hoc seal (`codesign --force --deep -s -`) when `SIGN_IDENTITY` is unset.
- Because ad-hoc identities still change per release, each update legitimately re-prompts for Accessibility once. Documented in the README (Troubleshooting) together with the `tccutil reset Accessibility com.alttab.app` recovery for grants stuck on an old build. A stable Developer ID signature (supported by the release workflow once certificate secrets are configured) removes the re-prompt entirely.

## [1.2.0] - 2026-07-01

### Added

- Optional window previews via ScreenCaptureKit (macOS 14+): "Show Window Previews" toggle in the status menu, **off by default**. Unless enabled, no ScreenCaptureKit API is touched and no Screen Recording prompt can appear. When enabled, previews are captured concurrently at reduced resolution and patched into the panel cells as they arrive.
- Windows of ⌘H-hidden apps and windows on other Spaces now appear in the switcher (standard windows only), discovered by the same Accessibility pass that finds minimized windows.
- Multi-monitor support: the switcher appears on the screen containing the mouse pointer.
- Unit tests for the extracted pure logic (`SwitcherStateMachine`, `MRUOrder`), runnable with `swift test`.

### Fixed

- Clicking a thumbnail now switches to that window. The click posted a notification nothing observed, and it desynced the panel's selection from the app's — releasing Option then activated the keyboard-selected window instead of the clicked one.
- Potential crash on every app activation: the `kAXFocusedWindow` result was force-cast without a type check.
- MRU race on confirm: the app-activation notification could read the target app's focused window before the asynchronous raise landed, demoting the just-selected window in MRU order. Explicit activations are now pinned for the next activation notification.
- Running another app named "AltTab" (e.g. lwouis/alt-tab-macos) no longer hides its windows from the switcher — the self-filter now uses the PID, not the app name.
- About dialog showed a hardcoded "Version 1.0"; it now reads the bundle version (single-sourced from `MARKETING_VERSION`).

### Changed

- Option-Tab opens from a cached window list instantly and reconciles against a fresh enumeration gathered off the main thread; the panel rebuilds only when the window set actually changed. Previously the panel was built twice per activation and enumeration ran synchronously on the main thread.
- Window enumeration makes a single Accessibility pass per app instead of re-fetching each app's full window list once per window plus once per app for minimized windows (≈65 → ≈25 IPC round-trips for 5 apps × 4 windows), and every Accessibility call is bounded by a 0.25s messaging timeout — a wedged app can no longer stall the switcher for up to ~6s per call.
- MRU sorting uses a rank dictionary with stable tiebreaking (O(n log n)) instead of `firstIndex(of:)` scans inside the comparator (O(n² log n)).
- The Option-Tab state machine was extracted from the event-tap plumbing into `SwitcherStateMachine` (pure, unit-tested); MRU ordering into `MRUOrder`.
- `NSRunningApplication.activate(options:)` deprecation gated: plain `activate()` on macOS 14+.
- Watchdog and permission-poll timers set a 0.5s tolerance so the kernel can coalesce wakeups.

## [1.1.2] - 2026-07-01

### Added

- Prebuilt universal (Apple Silicon + Intel) `.dmg`, published automatically on each tagged release — install without building from source.

### Changed

- README now leads with a direct download and adds a "Why another AltTab?" comparison.

## [1.1.1] - 2026-06-17

### Fixed

- Switcher latency and the grey panel shown before window icons appeared. Profiling with `sample` traced both to synchronous work on the main thread:
  - Window activation (`WindowActivator.raiseWindow`) blocked in `AXUIElementCopyAttributeValue(kAXWindows)` — a synchronous IPC round-trip to the target app for its full window list (~75% of main-thread activation cost; worst when switching into heavy apps like browsers or IDEs). It now runs on a background queue with a bounded `AXUIElementSetMessagingTimeout`, so confirming a selection no longer blocks the UI.
  - App icons (`NSRunningApplication.icon`) were resolved through a LaunchServices binding and disk read for every cell on every show, leaving the panel grey until icons loaded. Icons are now cached in memory — prewarmed on launch and on app-launch notifications, evicted when an app quits.

### Changed

- Removed the unused `CGWindowListCreateImage` thumbnail-capture code path, which became unavailable in the macOS 15 SDK and broke builds under Xcode 26.x.

## [1.1.0] - 2026-03-23

### Fixed

- Event tap failing silently after restart — added retry with exponential backoff so the hotkey recovers when the Accessibility subsystem isn't ready at login time
- Spurious Accessibility permission prompt on reboot — delays the check by 1.5s to let the TCC daemon initialize before prompting

### Changed

- Window titles now read via AXUIElement (Accessibility API) instead of CGWindowList (Screen Recording API), providing meaningful labels for all apps (VS Code project names, Teams chat titles, browser page titles, etc.) without requiring Screen Recording permission
- Removed ScreenCaptureKit dependency for thumbnail capture — avoids the repeated "Screen & System Audio Recording" prompt on macOS 15 (Sequoia); app icons are shown instead
- Screen Recording permission is no longer required or prompted
- Re-enable polling now also recovers from event taps that were never created (not just disabled)

## [1.0.0] - 2026-03-17

### Added

- Option-Tab global hotkey with 3-state machine (idle/active/idle)
- Window enumeration via CGWindowList + AXUIElement for minimized windows
- MRU ordering with per-app AXObserver intra-app focus tracking
- ScreenCaptureKit thumbnail capture (macOS 14+) with CGWindowList fallback (macOS 13)
- Non-activating NSPanel overlay with NSVisualEffectView backdrop
- AXUIElement window activation with unminimize support
- Accessibility permission check with polling until granted
- Screen Recording permission detection with graceful degradation to app icons
- Menu bar status item (no Dock icon)
- Launch at Login via SMAppService (macOS 13+)
- Build/install script with `--system` flag for /Applications
- Shift-Tab, Arrow keys, Escape, Enter, and mouse click navigation

[1.3.4]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.3.4
[1.3.3]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.3.3
[1.3.2]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.3.2
[1.3.1]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.3.1
[1.3.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.3.0
[1.2.1]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.2.1
[1.2.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.2.0
[1.1.2]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.1.2
[1.1.1]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.1.1
[1.1.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.1.0
[1.0.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.0.0
