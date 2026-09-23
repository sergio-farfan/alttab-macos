//
//  SwitcherStateMachine.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Pure modifier-Tab session state machine, extracted from HotkeyManager so
//  the trickiest behavior — event-tap state transitions — is unit-testable
//  without CGEvent taps. HotkeyManager decodes CGEvents (resolving the
//  configured SwitcherModifier to a single "modifier held" Bool) and feeds
//  them in; the machine answers with the action to dispatch and whether the
//  event must be swallowed.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  License: MIT
//

import Carbon.HIToolbox
import CoreGraphics

// MARK: - SwitcherModifier

/// The modifier key that opens a switcher session (held + Tab) and confirms
/// it on release. Option is the historical default; Command replaces the
/// system app switcher, which works because the session-level event tap
/// swallows the Cmd+Tab keyDown before the Dock sees it.
enum SwitcherModifier: String, CaseIterable {
    case option
    case command

    static let defaultModifier: SwitcherModifier = .option
    /// UserDefaults key. Absent (or unknown) means `defaultModifier`.
    static let defaultsKey = "SwitcherModifier"

    /// Maps a stored defaults string to a level; nil or unknown → default.
    static func resolve(_ raw: String?) -> SwitcherModifier {
        raw.flatMap(SwitcherModifier.init(rawValue:)) ?? defaultModifier
    }

    /// The CGEventFlags bit HotkeyManager tests on every flagsChanged/keyDown.
    var flag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .command: return .maskCommand
        }
    }

    /// Menu title.
    var title: String {
        switch self {
        case .option: return "Option (⌥)"
        case .command: return "Command (⌘)"
        }
    }

    /// Short glyph for the status-item fallback title / docs.
    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .command: return "⌘"
        }
    }
}

// MARK: - SwitcherAction

/// Action the host should dispatch in response to an input event.
enum SwitcherAction: Equatable {
    case none
    case activate
    /// Session opened with Modifier+Shift+Tab — anchor at the list tail
    /// (Windows convention: reverse-cycle starts from the least recent).
    case activateBackward
    case cycleNext
    case cyclePrevious
    case confirm
    case cancel
    /// Q while active — quit the selected window's app; the session stays
    /// open so the user can keep switching (native Cmd+Tab convention).
    case quitSelected
    /// H while active — hide the selected window's app; session stays open.
    case hideSelected
}

// MARK: - SwitcherStateMachine

struct SwitcherStateMachine {

    private(set) var isActive = false

    /// Modifier flags changed. The caller must never swallow flagsChanged
    /// events regardless of the returned action.
    mutating func handleFlagsChanged(modifierDown: Bool) -> SwitcherAction {
        guard isActive, !modifierDown else { return .none }
        // Modifier released → confirm selection
        isActive = false
        return .confirm
    }

    /// keyDown event. Returns the action plus whether the event must be
    /// swallowed (kept from the target app). While a session is active EVERY
    /// keyDown is swallowed: the modifier is still held, so a key that leaked
    /// would reach the frontmost app as a chord (Cmd+Q, Cmd+W, Cmd+H …) — in
    /// Command mode that is a fumbled quit or close of the wrong window.
    mutating func handleKeyDown(keyCode: Int, modifierDown: Bool, shiftDown: Bool) -> (action: SwitcherAction, swallow: Bool) {
        if !isActive {
            // Modifier + Tab → activate switcher; Shift reverses the direction.
            if modifierDown && keyCode == kVK_Tab {
                isActive = true
                return (shiftDown ? .activateBackward : .activate, true)
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
        case kVK_ANSI_Q:
            return (.quitSelected, true)
        case kVK_ANSI_H:
            return (.hideSelected, true)
        default:
            // Swallow everything else — see the doc comment above.
            return (.none, true)
        }
    }

    /// The event tap was disabled (timeout or user input) — the modifier
    /// release may have been missed, so an active session must be cancelled.
    mutating func handleTapDisabled() -> SwitcherAction {
        guard isActive else { return .none }
        isActive = false
        return .cancel
    }

    /// Ends the session without an action, e.g. after a thumbnail click already
    /// confirmed the selection. The still-held modifier no longer confirms on
    /// release, and Modifier-Tab can start a fresh session immediately.
    mutating func cancelSession() {
        isActive = false
    }
}
