# Changelog

All notable changes to AltTab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.2.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.2.0
[1.1.2]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.1.2
[1.1.1]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.1.1
[1.1.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.1.0
[1.0.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.0.0
