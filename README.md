<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_13%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/swift-5.9%2B-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/github/license/sergio-farfan/alttab-macos?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/github/v/release/sergio-farfan/alttab-macos?style=flat-square&label=version" alt="Version">
  <img src="https://img.shields.io/github/stars/sergio-farfan/alttab-macos?style=flat-square" alt="Stars">
</p>

# AltTab

**Windows-style window switcher for macOS.**

macOS Cmd-Tab switches between *applications*. AltTab switches between *windows* — just like Alt-Tab on Windows. Hold Option, tap Tab to see every open window as a thumbnail, cycle through them, and release to switch.

## Features

- **Option-Tab** to activate, cycle with Tab, confirm on release
- **Shift-Tab** / Arrow keys to navigate in reverse
- **Escape** to cancel without switching
- Live window thumbnails via ScreenCaptureKit (app icon fallback if permission denied)
- Includes minimized windows
- MRU (most recently used) ordering with intra-app focus tracking
- Menu bar utility — no Dock icon, no clutter
- Launch at Login support (macOS 13+ SMAppService)
- Zero dependencies — pure Swift + AppKit
- ~2,000 lines of code, single-purpose, auditable

## Quick Start

```bash
git clone https://github.com/sergio-farfan/alttab-macos.git
cd alttab-macos
./build.sh install
open ~/Applications/AltTab.app
```

Then grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility).

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **macOS** | 13.0+ (Ventura, Sonoma, Sequoia) |
| **Xcode** | Full install from App Store (not just Command Line Tools) |

<details>
<summary>First time with Xcode?</summary>

If you just installed Xcode, you may need to run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```
</details>

## Install

### User install (recommended)

Installs to `~/Applications` — no sudo required.

```bash
./build.sh install
```

### System-wide install

Installs to `/Applications` — requires sudo.

```bash
sudo ./build.sh install --system
```

### Build commands

| Command | Description |
|---------|-------------|
| `./build.sh build` | Build only (Release configuration) |
| `./build.sh install` | Build and install to `~/Applications` |
| `./build.sh install --system` | Build and install to `/Applications` (sudo) |
| `./build.sh run` | Build and launch from build directory |
| `./build.sh clean` | Remove build artifacts |
| `./build.sh uninstall` | Remove from `~/Applications` |
| `./build.sh uninstall --system` | Remove from `/Applications` (sudo) |

## Permissions

On first launch, AltTab will prompt for Accessibility access. Screen Recording is optional.

| Permission | Required | Why |
|-----------|----------|-----|
| **Accessibility** | Yes | CGEvent tap for global hotkey detection; AXUIElement for window management, focus tracking, and unminimize |
| **Screen Recording** | No | Live window thumbnail capture via ScreenCaptureKit. Without it, app icons are shown instead |

Grant in: **System Settings → Privacy & Security → [Accessibility / Screen Recording]**

## Usage

| Shortcut | Action |
|----------|--------|
| <kbd>Option</kbd> + <kbd>Tab</kbd> | Open switcher, select next window |
| <kbd>Tab</kbd> | Cycle forward (while holding Option) |
| <kbd>Shift</kbd> + <kbd>Tab</kbd> | Cycle backward |
| <kbd>←</kbd> <kbd>→</kbd> | Navigate left / right |
| Release <kbd>Option</kbd> | Switch to selected window |
| <kbd>Escape</kbd> | Cancel, dismiss switcher |
| <kbd>Enter</kbd> | Confirm selection |
| Click thumbnail | Select and switch |

## How It Works

AltTab installs a **CGEvent tap** at the session level to intercept keyboard events globally. A 3-state machine (idle → active → idle) tracks Option hold/release and Tab presses. Window enumeration combines `CGWindowListCopyWindowInfo` (on-screen windows) with `AXUIElement` queries (minimized windows). MRU order is maintained via `NSWorkspace` activation notifications and per-app `AXObserver` callbacks that track focused-window changes — including intra-app switches like Cmd-\`.

The switcher UI is a **non-activating NSPanel** (`.nonactivatingPanel` style mask) so it floats above all windows without stealing focus. Thumbnails are captured asynchronously via `SCScreenshotManager` (macOS 14+) or `CGWindowListCreateImage` (macOS 13), cached per-activation. Window activation uses `AXUIElement` to raise the specific window and unminimize if needed.

## Architecture

```
AltTab/AltTab/
├── main.swift              # App entry point — wires NSApp delegate manually
├── AppDelegate.swift       # Lifecycle, menu bar status item, orchestration
├── HotkeyManager.swift     # CGEvent tap + idle/active state machine
├── WindowModel.swift       # CGWindowList + AXUIElement enumeration, MRU tracking
├── WindowCapture.swift     # ScreenCaptureKit / CGWindowList thumbnail capture
├── SwitcherPanel.swift     # NSPanel overlay with NSVisualEffectView backdrop
├── ThumbnailView.swift     # Individual window cell (thumbnail + title + app name)
├── WindowActivator.swift   # AXUIElement window raise / unminimize / focus
├── PermissionManager.swift # Accessibility & Screen Recording permission checks
└── PreferencesMenu.swift   # Status bar menu (Launch at Login, Quit)
```

## Uninstall

```bash
./build.sh uninstall                # Remove from ~/Applications
sudo ./build.sh uninstall --system  # Remove from /Applications
```

Or manually delete `AltTab.app` and remove from Login Items in System Settings.

## Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test: `./build.sh run`
5. Commit and push
6. Open a Pull Request

## License

[MIT](LICENSE) — Sergio Farfan (sergio.farfan@gmail.com)
