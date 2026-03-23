//
//  HotkeyManager.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Global hotkey detection via a CGEvent tap installed at the session level.
//  Implements a 3-state machine (idle → active → idle) that tracks Option
//  key hold state and Tab/Arrow/Escape keypresses. The CGEvent callback is
//  a C function pointer bridged to Swift via Unmanaged<HotkeyManager>.
//  Only keyDown events are swallowed; flagsChanged is always passed through
//  to avoid breaking system modifier state. Includes retry logic with
//  exponential backoff for event tap creation, handling the case where the
//  Accessibility subsystem isn't ready at login time.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.0.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa
import Carbon.HIToolbox

// MARK: - Delegate Protocol

protocol HotkeyDelegate: AnyObject {
    func hotkeyDidActivate()
    func hotkeyDidCycleNext()
    func hotkeyDidCyclePrevious()
    func hotkeyDidConfirm()
    func hotkeyDidCancel()
}

// MARK: - HotkeyManager

final class HotkeyManager {

    weak var delegate: HotkeyDelegate?

    private enum State {
        case idle
        case active
    }

    private var state: State = .idle
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var reEnableTimer: Timer?

    // MARK: - Lifecycle

    /// Maximum number of retries for event tap creation at startup.
    private static let maxTapRetries = 10
    /// Delay between retries, in seconds (doubles each attempt, capped at 4s).
    private static let baseTapRetryInterval: TimeInterval = 0.5
    private var tapRetryCount = 0

    func start() {
        if !installEventTap() {
            scheduleRetry()
        }
        startReEnablePolling()
    }

    /// Retry event tap creation with exponential back-off.
    /// At login the accessibility subsystem may not be ready yet.
    private func scheduleRetry() {
        guard tapRetryCount < Self.maxTapRetries else {
            NSLog("AltTab: Gave up creating event tap after \(Self.maxTapRetries) retries.")
            return
        }
        let delay = min(Self.baseTapRetryInterval * pow(2.0, Double(tapRetryCount)), 4.0)
        tapRetryCount += 1
        NSLog("AltTab: Will retry event tap in %.1fs (attempt %d/%d)", delay, tapRetryCount, Self.maxTapRetries)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.eventTap == nil else { return }
            if self.installEventTap() {
                NSLog("AltTab: Event tap created on retry %d", self.tapRetryCount)
            } else {
                self.scheduleRetry()
            }
        }
    }

    func stop() {
        reEnableTimer?.invalidate()
        reEnableTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    // MARK: - Event Tap

    @discardableResult
    private func installEventTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) |
                                (1 << CGEventType.keyDown.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: userInfo
        ) else {
            NSLog("AltTab: Failed to create event tap. Is Accessibility enabled?")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// The system can disable our tap if the callback takes too long. Poll to re-enable.
    /// If the tap was disabled while the switcher was active, we missed the Option release —
    /// force-cancel to prevent the panel from sticking.
    private func startReEnablePolling() {
        reEnableTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            // If the tap was never created (e.g. permissions weren't ready at launch),
            // keep trying — accessibility may have been granted in the meantime.
            guard let tap = self.eventTap else {
                if AXIsProcessTrusted() {
                    NSLog("AltTab: Accessibility now trusted, retrying event tap creation.")
                    self.installEventTap()
                }
                return
            }

            if !CGEvent.tapIsEnabled(tap: tap) {
                NSLog("AltTab: Event tap was disabled by system, re-enabling.")
                CGEvent.tapEnable(tap: tap, enable: true)
                // If we were active, we missed the Option release — force cancel
                if self.state == .active {
                    self.state = .idle
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyDidCancel()
                    }
                }
            }
        }
    }

    // MARK: - Event Handling

    fileprivate func handleEvent(_ proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If tap is disabled, re-enable and force-cancel any active switcher
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            if state == .active {
                state = .idle
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidCancel()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let optionDown = flags.contains(.maskAlternate)

        switch state {
        case .idle:
            if optionDown {
                // Don't activate yet — wait for Tab keyDown
            }
        case .active:
            if !optionDown {
                // Option released → confirm selection
                state = .idle
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidConfirm()
                }
            }
        }

        // NEVER swallow flagsChanged — always pass through
        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let optionDown = flags.contains(.maskAlternate)
        let shiftDown = flags.contains(.maskShift)

        switch state {
        case .idle:
            // Option + Tab → activate switcher
            if optionDown && keyCode == kVK_Tab {
                state = .active
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidActivate()
                }
                return nil // swallow the Tab
            }

        case .active:
            switch Int(keyCode) {
            case kVK_Tab:
                if shiftDown {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyDidCyclePrevious()
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyDidCycleNext()
                    }
                }
                return nil // swallow

            case kVK_LeftArrow:
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidCyclePrevious()
                }
                return nil

            case kVK_RightArrow:
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidCycleNext()
                }
                return nil

            case kVK_Escape:
                state = .idle
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidCancel()
                }
                return nil

            case kVK_Return:
                state = .idle
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidConfirm()
                }
                return nil

            default:
                break
            }
        }

        // Pass through all other keys
        return Unmanaged.passUnretained(event)
    }
}

// MARK: - C Callback Bridge

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(proxy, type: type, event: event)
}
