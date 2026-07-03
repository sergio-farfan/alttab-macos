# CLAUDE.md

Guidance for Claude Code sessions in this repo (AltTab — Windows-style window switcher for macOS, pure Swift/AppKit, zero dependencies).

## Build & Test

- `swift test` — unit tests for the pure-logic core (`MRUOrder`, `SwitcherStateMachine`) via the SPM harness in `Package.swift`; run plainly, no output-truncating pipes
- `xcodebuild -project AltTab/AltTab.xcodeproj -scheme AltTab -configuration Release build` — app build
- `./build.sh install` — build + install to `~/Applications` (dev installs live there, not `/Applications`)
- `scripts/package-dmg.sh <version>` — universal (arm64+x86_64) Release, ad-hoc seal, DMG + sha256 into `dist/` (gitignored; CI artifact is canonical)
- `swift scripts/generate-appicon.swift` — regenerates all AppIcon PNGs parametrically (pure AppKit, no design tools)

## Architecture Invariants

- `WindowModel` state (MRU order, cache, `pendingActivation`, observers) is **main-thread-confined**; only the stateless static `gatherWindows` runs on the background queue. Never mutate WindowModel state off-main.
- `AXUIElementSetMessagingTimeout` is **per-element** — set it on each AX *window* element too, not just the app element, or per-window fetches keep the ~6s default.
- `MRUOrder.swift` and `SwitcherStateMachine.swift` compile into BOTH the app target and the SPM `AltTabCore` module: keep them free of AppKit imports.
- New Swift files must be registered by hand in `project.pbxproj` (classic explicit refs — mirror the existing `A1…`/`A2…` PBXBuildFile/PBXFileReference/group/Sources pattern) AND added to the `exclude` list in `Package.swift` (unless they belong in AltTabCore).
- No ScreenCaptureKit API may execute unless the `ShowWindowPreviews` default is on — never prompting for Screen Recording by default is a core product promise (README, CHANGELOG 1.1.0).
- `NSGlassEffectView` (Liquid Glass background) exists only in the macOS 26 SDK — `#available` gates runtime, not compile time, so builds require Xcode 26+; `release.yml` runs on `macos-26` for this reason. Glass content must be embedded via its `contentView` property (header contract), and as of macOS 26.5 assigning it auto-pins edge-to-edge internally.
- Async completions in `AppDelegate` (refresh, previews) are guarded by `switchSession` epoch + `switcherActive`; preserve that pattern when adding async work.

## Signing & TCC (hard-won)

- Shipped bundles MUST be codesign-sealed. Building with `CODE_SIGNING_ALLOWED=NO` alone yields an unsealed bundle (linker-signed arm64 slice only) → macOS fabricates unpredictable code identities → the TCC Accessibility toggle shows ON while the binary is denied and no event tap is created. `package-dmg.sh` applies `codesign --force --deep -s - --identifier com.alttab.app` when `SIGN_IDENTITY` is unset.
- Ad-hoc identity changes every build → each release legitimately re-prompts Accessibility once. Stuck grant: `tccutil reset Accessibility com.alttab.app`, relaunch, re-grant.
- Debugging TCC: read `csreq` from `/Library/Application Support/com.apple.TCC/TCC.db` (sqlite3), decompile with `csreq -r <file> -t`, compare with `codesign -dvvv` cdhash; verify the tap exists with a `CGGetEventTapList` probe.
- Launching the app from a shell is an INVALID test of its own TCC state (the terminal becomes the responsible process and its grants leak in) — always test via `open` / LaunchServices.
- `log show --predicate 'process == "AltTab"'` returns nothing on this machine even for fresh NSLog output; don't rely on the unified log for the app's diagnostics.

## Release Process

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj` (Info.plist uses `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` substitution — single-sourced).
2. Add a `## [X.Y.Z]` CHANGELOG section plus the link reference at the bottom (Keep a Changelog format).
3. Commit to `main` (direct push bypasses the PR rule via admin — matches release precedent), annotated tag `vX.Y.Z`, push branch + tag.
4. `release.yml` triggers on `v*` tags → builds and publishes the DMG (~1 min). CI stamps `CFBundleVersion = major*10000+minor*100+patch.runN`. Developer ID signing/notarization is dormant until the certificate secrets are set.
