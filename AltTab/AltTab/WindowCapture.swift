//
//  WindowCapture.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Asynchronous window thumbnail capture. Uses SCScreenshotManager (macOS 14+)
//  for high-quality single-frame captures, with CGWindowListCreateImage as a
//  fallback for macOS 13. Results are cached per-activation via NSCache keyed
//  by CGWindowID. Minimized windows and permission-denied scenarios gracefully
//  degrade to app icons.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.0.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa
import ScreenCaptureKit

final class WindowCapture {

    private let thumbnailMaxWidth: CGFloat = 320
    private let thumbnailMaxHeight: CGFloat = 200
    private let cache = NSCache<NSNumber, NSImage>()

    /// Captures thumbnails for all windows asynchronously.
    /// Calls completion on main thread with updated WindowInfo array.
    func captureThumbnails(for windows: [WindowInfo], completion: @escaping ([WindowInfo]) -> Void) {
        cache.removeAllObjects()

        guard PermissionManager.hasScreenRecordingPermission else {
            // No Screen Recording permission — use app icons as fallback
            completion(windows)
            return
        }

        if #available(macOS 14.0, *) {
            captureWithScreenCaptureKit(windows: windows, completion: completion)
        } else {
            captureWithCGWindowList(windows: windows, completion: completion)
        }
    }

    // MARK: - ScreenCaptureKit (macOS 14+ for SCScreenshotManager)

    @available(macOS 14.0, *)
    private func captureWithScreenCaptureKit(windows: [WindowInfo], completion: @escaping ([WindowInfo]) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self, let content = content else {
                DispatchQueue.main.async { completion(windows) }
                return
            }

            let group = DispatchGroup()
            var updatedWindows = windows

            for (index, windowInfo) in windows.enumerated() {
                // Skip minimized windows (no visual capture possible)
                if windowInfo.isMinimized { continue }

                // Check cache first
                if let cached = self.cache.object(forKey: NSNumber(value: windowInfo.windowID)) {
                    updatedWindows[index].thumbnail = cached
                    continue
                }

                // Find matching SC window
                guard let scWindow = content.windows.first(where: {
                    $0.windowID == windowInfo.windowID
                }) else { continue }

                group.enter()
                self.captureWindow(scWindow) { image in
                    if let image = image {
                        self.cache.setObject(image, forKey: NSNumber(value: windowInfo.windowID))
                        updatedWindows[index].thumbnail = image
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion(updatedWindows)
            }
        }
    }

    @available(macOS 14.0, *)
    private func captureWindow(_ scWindow: SCWindow, completion: @escaping (NSImage?) -> Void) {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        config.width = Int(thumbnailMaxWidth * 2) // Retina
        config.height = Int(thumbnailMaxHeight * 2)
        config.scalesToFit = true
        config.showsCursor = false

        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
            guard let cgImage = image else {
                completion(nil)
                return
            }
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(
                width: CGFloat(cgImage.width) / 2.0,
                height: CGFloat(cgImage.height) / 2.0
            ))
            completion(nsImage)
        }
    }

    // MARK: - CGWindowList Fallback

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
