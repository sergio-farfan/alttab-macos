<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_13%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/swift-5.9%2B-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/github/license/sergio-farfan/alttab-macos?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/github/v/release/sergio-farfan/alttab-macos?style=flat-square&label=version" alt="Version">
  <img src="https://img.shields.io/github/downloads/sergio-farfan/alttab-macos/total?style=flat-square&label=downloads" alt="Downloads">
  <img src="https://img.shields.io/github/stars/sergio-farfan/alttab-macos?style=flat-square" alt="Stars">
</p>

# AltTab

**Windows-style window switcher for macOS.**

<!--
  DEMO GIF: record a ~5s screen capture of Option-Tab cycling through window
  thumbnails, save it as Screenshots/demo.gif, then replace the <img> below with:
    <img src="Screenshots/demo.gif" alt="AltTab in action" width="640">
-->
<p align="center">
  <img src="Screenshots/switcher.jpg" alt="AltTab switcher in action — Option-Tab cycling through every open window" width="900">
</p>
<p align="center">
  <em>One Option-Tab: every open window, most-recent first, on the screen where your mouse is.</em>
</p>
<p align="center">
  <img src="Screenshots/menu.png" alt="AltTab menu bar menu" width="320">
</p>

macOS Cmd-Tab switches between *applications*. AltTab switches between *windows* — just like Alt-Tab on Windows. Hold Option, tap Tab to see every open window as a thumbnail, cycle through them, and release to switch. Prefer it on the system shortcut? Set **Switcher Key → Command** in the menu and Cmd-Tab becomes a window switcher.

## Download

**[Download the latest AltTab.dmg →](https://github.com/sergio-farfan/alttab-macos/releases/latest)**

Open the `.dmg`, drag **AltTab** to **Applications**, and launch it. Grant **Accessibility** when prompted (System Settings → Privacy & Security → Accessibility).

<!-- UNSIGNED-NOTE: remove this block once notarized builds ship. -->
> This build is not yet notarized. On first launch macOS blocks it: open **System Settings → Privacy & Security**, click **Open Anyway**, and launch again (or clear the quarantine flag with `xattr -dr com.apple.quarantine /Applications/AltTab.app`).

**Homebrew**:

```bash
brew install --cask sergio-farfan/tap/alttab
```

The fully qualified name trusts just this cask (Homebrew 6+ requires third-party taps to be trusted before their code runs). To use the short name instead, run `brew trust sergio-farfan/tap && brew tap sergio-farfan/tap` first, then `brew install --cask alttab`. Update later with `brew upgrade --cask alttab` — until releases are notarized, each upgrade of this ad-hoc-signed build needs the **Open Anyway** step once more (Homebrew only carries a Gatekeeper approval forward when the signing identity is stable).

Prefer to build it yourself? See [Build from source](#build-from-source).

## Why another AltTab?

[`lwouis/alttab`](https://github.com/lwouis/alttab) is the feature-rich, highly configurable incumbent. This project is the deliberately minimal alternative:

- **Tiny and auditable** — ~2,700 lines of pure Swift + AppKit, single purpose.
- **Zero dependencies** — no packages, no frameworks bundled.
- **No Screen Recording permission** — titles via the Accessibility API, app icons instead of live thumbnails (avoids the recurring macOS 15 recording prompt). Live window previews are available as a strictly opt-in toggle on macOS 14+.
- **Windows-style Option-Tab** semantics with menu-bar-only footprint (no Dock icon).

If you want extensive customization, use lwouis/alttab. If you want something small you can read end to end, use this.

## Features

- **Option-Tab** to activate, cycle with Tab, confirm on release
- **Switcher Key** setting: Option (default) or **Command** — Command takes over the system Cmd-Tab app switcher while AltTab runs, no system settings changes needed; while the switcher is open, **Q** quits and **H** hides the selected window's app (native Cmd-Tab convention, works in both modes)
- **Shift-Tab** / Arrow keys to navigate in reverse — and **Option-Shift-Tab** opens the switcher already cycling backward, anchored on the least-recently-used window (new in 1.3.2)
- **Escape** to cancel without switching
- **Instant response** — the window list is kept warm by a debounced background refresh between invocations, window-raise runs off the main thread, and app icons are cached, so the switcher appears immediately with fresh contents even after hours of idle (1.3.2)
- Window titles via Accessibility API — works for all apps without Screen Recording permission
- App icon display with graceful fallback (no Screen Recording prompt on macOS 15+)
- Includes minimized windows, ⌘H-hidden apps, and windows on other Spaces
- Optional live window previews (ScreenCaptureKit, macOS 14+, opt-in from the menu)
- Appearance override (System / Light / Dark) and background styles: Solid (default), Transparent, or native Liquid Glass (macOS 26+) with a **Glass Strength** setting — Light / Medium / High / Max
- Multi-monitor aware — the switcher opens on the screen with the mouse pointer
- MRU (most recently used) ordering with intra-app focus tracking — resilient to busy apps: a wedged app's Accessibility timeout can't drop its windows from the list or scramble their order (1.3.2)
- Menu bar utility — no Dock icon, no clutter
- Launch at Login support (macOS 13+ SMAppService)
- Zero dependencies — pure Swift + AppKit
- ~2,800 lines of code, single-purpose, auditable (97 unit tests on the pure-logic core, run in CI)

## Build from source

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
| **macOS** | 13.0+ (Ventura or newer) to run |
| **Xcode** | 26 or newer to build from source (the code references `NSGlassEffectView`, which only exists in the macOS 26 SDK); full install from App Store, not just Command Line Tools |

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
| **Accessibility** | Yes | CGEvent tap for global hotkey detection; AXUIElement for window titles, window management, focus tracking, and unminimize |
| **Screen Recording** | No (opt-in) | Only for the optional "Show Window Previews" feature (macOS 14+, ScreenCaptureKit) |

Grant in: **System Settings → Privacy & Security → Accessibility**

> **Note:** Screen Recording permission is **not required**. Window titles are read via the Accessibility API, and app icons are used instead of live thumbnails. This avoids the repeated "Screen & System Audio Recording" prompt on macOS 15 (Sequoia). Enabling **Show Window Previews** in the status menu is the only thing that requests Screen Recording; with the toggle off (the default) the API is never touched.

### Option-Tab stops working after an update

macOS pins each Accessibility grant to the code identity of one specific build. Ad-hoc-signed releases get a new identity every build, so after updating AltTab the toggle in System Settings still shows **ON** while the new binary is silently denied. Fix:

```bash
tccutil reset Accessibility com.alttab.app
open ~/Applications/AltTab.app   # or /Applications — grant again when prompted
```

(Equivalently: remove AltTab from the Accessibility list with the **−** button and re-add it.) This re-prompt-per-update goes away once releases are signed with a stable Developer ID certificate.

## Usage

| Shortcut | Action |
|----------|--------|
| <kbd>Option</kbd> + <kbd>Tab</kbd> | Open switcher, select next window (<kbd>Cmd</kbd> instead of <kbd>Option</kbd> when Switcher Key is Command) |
| <kbd>Option</kbd> + <kbd>Shift</kbd> + <kbd>Tab</kbd> | Open switcher cycling backward (least-recent window first) |
| <kbd>Tab</kbd> | Cycle forward (while holding Option) |
| <kbd>Q</kbd> | Quit the selected window's app, keep switching |
| <kbd>H</kbd> | Hide the selected window's app, keep switching |
| <kbd>Shift</kbd> + <kbd>Tab</kbd> | Cycle backward |
| <kbd>←</kbd> <kbd>→</kbd> | Navigate left / right |
| Release <kbd>Option</kbd> | Switch to selected window |
| <kbd>Escape</kbd> | Cancel, dismiss switcher |
| <kbd>Enter</kbd> | Confirm selection |
| Click thumbnail | Select and switch |

## How It Works

AltTab installs a **CGEvent tap** at the session level to intercept keyboard events globally. A 3-state machine (idle → active → idle) tracks modifier hold/release and Tab presses (the modifier is Option or Command per the Switcher Key setting; in Command mode the head-inserted session tap swallows the Cmd-Tab keyDown before the Dock's app switcher sees it). While the switcher is open every other keyDown is swallowed too, so a chord like Cmd-W can't leak to the frontmost app. The event tap includes retry logic with exponential backoff to handle the case where the Accessibility subsystem isn't ready at login time. Window enumeration combines `CGWindowListCopyWindowInfo` (on-screen windows) with `AXUIElement` queries (minimized windows). Window titles are read via `AXUIElement` (`kAXTitleAttribute`), which only requires Accessibility permission — no Screen Recording needed. MRU order is maintained via `NSWorkspace` activation notifications and per-app `AXObserver` callbacks that track focused-window changes — including intra-app switches like Cmd-\`. Between invocations, those same events schedule a debounced, rate-limited background re-gather, so the cached window list the switcher opens from is never stale — even on the first Option-Tab after hours of idle.

The switcher UI is a **non-activating NSPanel** (`.nonactivatingPanel` style mask) so it floats above all windows without stealing focus. App icons are displayed for each window, served from an in-memory cache (prewarmed at launch) so the panel paints immediately instead of resolving each icon through LaunchServices on the fly. Window activation uses `AXUIElement` to raise the specific window and unminimize if needed; that synchronous AX IPC runs on a background queue with a bounded messaging timeout, so a slow target app can't block the main thread (and stall the switcher).

## Architecture

```
AltTab/AltTab/
├── main.swift                  # App entry point — wires NSApp delegate manually
├── AppDelegate.swift           # Lifecycle, menu bar status item, orchestration, session epochs
├── HotkeyManager.swift         # CGEvent tap plumbing; decodes events for the state machine
├── SwitcherStateMachine.swift  # Pure modifier-Tab session state machine + SwitcherModifier setting (unit-tested)
├── SwitcherSelection.swift     # Pure per-session selection: initial anchor, cycling, reconcile (unit-tested)
├── WindowModel.swift           # CGWindowList + concurrent AX pass per app, warm cache + async refresh
├── MRUOrder.swift              # Pure MRU ordering (unit-tested)
├── GatherMerge.swift           # Pure carry-over policy for lossy AX gathers (unit-tested)
├── Debouncer.swift             # Trailing-edge debouncer for the background cache refresh (unit-tested)
├── WindowCapture.swift         # Opt-in ScreenCaptureKit window previews (macOS 14+)
├── SwitcherPanel.swift         # NSPanel overlay with selectable background (solid / HUD / Liquid Glass)
├── ThumbnailView.swift         # Individual window cell (preview/icon + title + app name)
├── WindowActivator.swift       # AXUIElement window raise / unminimize (off-main, bounded timeout)
├── PermissionManager.swift     # Accessibility polling; Screen Recording preflight/request
└── PreferencesMenu.swift       # Status bar menu (Launch at Login, Appearance, Background, Window Previews, Quit)
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
