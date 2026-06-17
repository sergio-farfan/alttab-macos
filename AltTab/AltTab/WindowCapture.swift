//
//  WindowCapture.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Window thumbnail/icon provider. Currently returns app icons for all windows
//  to avoid triggering the macOS 15 "Screen & System Audio Recording" prompt.
//  The former CGWindowListCreateImage path was removed once that API became
//  unavailable in the macOS 15 SDK; use ScreenCaptureKit if thumbnails return.
//  Window titles are sourced from AXUIElement (Accessibility API) in WindowModel.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.1.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa

final class WindowCapture {

    /// Captures thumbnails for all windows asynchronously.
    /// Calls completion on main thread with updated WindowInfo array.
    ///
    /// On macOS 15+, both CGWindowListCopyWindowInfo (for window names) and
    /// CGWindowListCreateImage trigger a "Screen & System Audio Recording" prompt
    /// whenever the binary's code signature changes. Since there is no non-prompting
    /// way to check or use these APIs, thumbnail capture is disabled. The switcher
    /// uses app icons instead, which work without any Screen Recording permission.
    func captureThumbnails(for windows: [WindowInfo], completion: @escaping ([WindowInfo]) -> Void) {
        completion(windows)
    }
}
