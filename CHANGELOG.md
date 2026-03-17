# Changelog

All notable changes to AltTab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/sergio-farfan/alttab-macos/releases/tag/v1.0.0
