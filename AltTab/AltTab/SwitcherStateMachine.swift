//
//  SwitcherStateMachine.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Pure Option-Tab session state machine, extracted from HotkeyManager so the
//  trickiest behavior — event-tap state transitions — is unit-testable without
//  CGEvent taps. HotkeyManager decodes CGEvents and feeds them in; the machine
//  answers with the action to dispatch and whether the event must be swallowed.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  License: MIT
//

import Carbon.HIToolbox

/// Action the host should dispatch in response to an input event.
enum SwitcherAction: Equatable {
    case none
    case activate
    case cycleNext
    case cyclePrevious
    case confirm
    case cancel
}

struct SwitcherStateMachine {

    private(set) var isActive = false

    /// Modifier flags changed. The caller must never swallow flagsChanged
    /// events regardless of the returned action.
    mutating func handleFlagsChanged(optionDown: Bool) -> SwitcherAction {
        guard isActive, !optionDown else { return .none }
        // Option released → confirm selection
        isActive = false
        return .confirm
    }

    /// keyDown event. Returns the action plus whether the event must be
    /// swallowed (kept from the target app).
    mutating func handleKeyDown(keyCode: Int, optionDown: Bool, shiftDown: Bool) -> (action: SwitcherAction, swallow: Bool) {
        if !isActive {
            // Option + Tab → activate switcher
            if optionDown && keyCode == kVK_Tab {
                isActive = true
                return (.activate, true)
            }
            return (.none, false)
        }

        switch keyCode {
        case kVK_Tab:
            return (shiftDown ? .cyclePrevious : .cycleNext, true)
        case kVK_LeftArrow:
            return (.cyclePrevious, true)
        case kVK_RightArrow:
            return (.cycleNext, true)
        case kVK_Escape:
            isActive = false
            return (.cancel, true)
        case kVK_Return:
            isActive = false
            return (.confirm, true)
        default:
            // Pass through all other keys
            return (.none, false)
        }
    }

    /// The event tap was disabled (timeout or user input) — the Option release
    /// may have been missed, so an active session must be cancelled.
    mutating func handleTapDisabled() -> SwitcherAction {
        guard isActive else { return .none }
        isActive = false
        return .cancel
    }

    /// Ends the session without an action, e.g. after a thumbnail click already
    /// confirmed the selection. The still-held Option no longer confirms on
    /// release, and Option-Tab can start a fresh session immediately.
    mutating func cancelSession() {
        isActive = false
    }
}
