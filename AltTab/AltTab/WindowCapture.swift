//
//  WindowCapture.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Window preview provider built on ScreenCaptureKit's SCScreenshotManager
//  (macOS 14+). Previews are strictly opt-in ("Show Window Previews" in the
//  status menu) because they require the Screen Recording permission; with
//  the preference off — the default — no ScreenCaptureKit API is touched and
//  no permission prompt can ever appear, and the switcher shows app icons.
//  Captures run concurrently at reduced resolution and are delivered
//  incrementally on the main thread as they complete.
//
//  API validated against the installed macOS SDK headers: SCScreenshotManager
//  captureImage(contentFilter:configuration:) is macOS 14.0+;
//  SCContentFilter(desktopIndependentWindow:) captures a single window.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.2.0
//  Date:    2026-07-01
//  License: MIT
//

import Cocoa
import ScreenCaptureKit

final class WindowCapture {

    static let previewsDefaultsKey = "ShowWindowPreviews"

    /// Whether the user has opted into window previews (requires Screen Recording).
    static var previewsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: previewsDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: previewsDefaultsKey) }
    }

    /// Longest edge (pixels) of a captured preview — roughly 2x the cell's image
    /// area, keeping per-window captures cheap.
    private static let maxPreviewDimension: CGFloat = 400

    private var captureTask: Task<Void, Never>?

    /// Captures previews for the given windows, delivering each on the main
    /// thread as it arrives. Minimized windows are skipped (not capturable).
    /// No-op unless previews are enabled, Screen Recording is granted, and the
    /// OS is macOS 14+ (SCScreenshotManager availability).
    func capturePreviews(for windows: [WindowInfo], onPreview: @escaping (CGWindowID, NSImage) -> Void) {
        guard #available(macOS 14.0, *),
              Self.previewsEnabled,
              PermissionManager.hasScreenRecordingPermission else { return }

        let targetIDs = Set(windows.filter { !$0.isMinimized }.map { $0.windowID })
        guard !targetIDs.isEmpty else { return }

        captureTask?.cancel()
        captureTask = Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
            let scWindows = content.windows.filter { targetIDs.contains($0.windowID) }

            await withTaskGroup(of: Void.self) { group in
                for scWindow in scWindows {
                    group.addTask {
                        guard !Task.isCancelled else { return }
                        let frame = scWindow.frame
                        let scale = min(1, Self.maxPreviewDimension / max(frame.width, frame.height, 1))
                        let configuration = SCStreamConfiguration()
                        configuration.width = max(1, Int(frame.width * scale))
                        configuration.height = max(1, Int(frame.height * scale))
                        configuration.showsCursor = false
                        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                                        configuration: configuration) else { return }
                        let image = NSImage(cgImage: cgImage, size: NSSize(width: frame.width, height: frame.height))
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            onPreview(scWindow.windowID, image)
                        }
                    }
                }
            }
        }
    }

    /// Stops any in-flight capture (e.g. the switcher was dismissed).
    func cancel() {
        captureTask?.cancel()
        captureTask = nil
    }
}
