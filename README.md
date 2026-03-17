# AltTab — Windows-style Window Switcher for macOS

A lightweight macOS utility that replaces Cmd-Tab's app-level switching with **window-level switching**, just like Alt-Tab on Windows.

**Hold Option, tap Tab** to see all open windows as thumbnails. Keep tapping Tab to cycle. Release Option to switch.

## Features

- **Option-Tab** to activate, cycle with Tab, confirm on release
- **Shift-Tab** / Arrow keys to navigate in reverse
- **Escape** to cancel
- Live window thumbnails (with Screen Recording permission) or app icon fallback
- Includes minimized windows
- MRU (most recently used) ordering — tracks window focus across and within apps
- Menu bar utility — no Dock icon
- Launch at Login support
- macOS 13+ (Ventura)
- Zero dependencies, pure Swift + AppKit

## Install

Requires Xcode (not just Command Line Tools).

```bash
# Build and install to /Applications
./build.sh install

# Or just build
./build.sh build

# Build and launch immediately
./build.sh run
```

## Permissions

On first launch, grant these in **System Settings → Privacy & Security**:

| Permission | Required | Purpose |
|-----------|----------|---------|
| **Accessibility** | Yes | Hotkey detection (CGEvent tap) and window management (AXUIElement) |
| **Screen Recording** | Optional | Live window thumbnails. Falls back to app icons if denied. |

## Usage

| Shortcut | Action |
|----------|--------|
| **Option + Tab** | Open switcher, select next window |
| **Tab** (while holding Option) | Cycle forward |
| **Shift + Tab** | Cycle backward |
| **← →** Arrow keys | Navigate left/right |
| **Release Option** | Switch to selected window |
| **Escape** | Cancel, dismiss switcher |
| **Enter** | Confirm selection |
| **Click** thumbnail | Select and switch |

## Uninstall

```bash
./build.sh uninstall
```

Or manually delete `/Applications/AltTab.app` and remove from Login Items.

## Architecture

```
AltTab/AltTab/
├── main.swift              # App entry point, wires delegate
├── AppDelegate.swift       # Lifecycle, menu bar, orchestration
├── HotkeyManager.swift     # CGEvent tap + state machine
├── WindowModel.swift       # Window enumeration + MRU tracking + AXObservers
├── WindowCapture.swift     # ScreenCaptureKit / CGWindowList thumbnails
├── SwitcherPanel.swift     # Non-activating NSPanel overlay
├── ThumbnailView.swift     # Individual window thumbnail cell
├── WindowActivator.swift   # AXUIElement raise/focus/unminimize
├── PermissionManager.swift # Accessibility + Screen Recording checks
└── PreferencesMenu.swift   # Status bar menu (Login Item, Quit)
```

## License

MIT
