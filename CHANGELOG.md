# Changelog

All notable changes to AltTab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.1.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.1.0
[1.0.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.0.0
