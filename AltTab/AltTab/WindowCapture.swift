//
//  WindowCapture.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Window thumbnail/icon provider. Currently returns app icons for all windows
//  to avoid triggering the macOS 15 "Screen & System Audio Recording" prompt.
//  CGWindowList capture code is retained but disabled. Window titles are sourced
//  from AXUIElement (Accessibility API) in WindowModel, not from CGWindowList.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.1.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa

final class WindowCapture {

    private let thumbnailMaxWidth: CGFloat = 320
    private let thumbnailMaxHeight: CGFloat = 200
    private let cache = NSCache<NSNumber, NSImage>()

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

    // MARK: - Thumbnail Capture via CGWindowList

    private func captureWithCGWindowList(windows: [WindowInfo], completion: @escaping ([WindowInfo]) -> Void) {
        var updatedWindows = windows

        for (index, windowInfo) in windows.enumerated() {
            if windowInfo.isMinimized { continue }

            if let cgImage = CGWindowListCreateImage(
                windowInfo.bounds,
                .optionIncludingWindow,
                windowInfo.windowID,
                [.boundsIgnoreFraming, .nominalResolution]
            ) {
                let thumbnail = NSImage(cgImage: cgImage, size: NSSize(
                    width: min(thumbnailMaxWidth, CGFloat(cgImage.width)),
                    height: min(thumbnailMaxHeight, CGFloat(cgImage.height))
                ))
                self.cache.setObject(thumbnail, forKey: NSNumber(value: windowInfo.windowID))
                updatedWindows[index].thumbnail = thumbnail
            }
        }

        DispatchQueue.main.async {
            completion(updatedWindows)
        }
    }
}
