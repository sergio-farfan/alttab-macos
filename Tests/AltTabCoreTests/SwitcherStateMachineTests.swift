//
//  SwitcherStateMachineTests.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Unit tests for the modifier-Tab session state machine used by HotkeyManager,
//  and for the SwitcherModifier setting that picks Option vs Command.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  License: MIT
//

import XCTest
import Carbon.HIToolbox
@testable import AltTabCore

final class SwitcherStateMachineTests: XCTestCase {

    // MARK: - Activation

    func testModifierTabActivatesAndSwallows() {
        var machine = SwitcherStateMachine()
        let result = machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.activate)
        XCTAssertTrue(result.swallow)
        XCTAssertTrue(machine.isActive)
    }

    func testModifierShiftTabActivatesBackwardAndSwallows() {
        var machine = SwitcherStateMachine()
        let result = machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: true, shiftDown: true)
        XCTAssertEqual(result.action, SwitcherAction.activateBackward)
        XCTAssertTrue(result.swallow)
        XCTAssertTrue(machine.isActive)
        // The backward session behaves like any other: modifier release confirms.
        XCTAssertEqual(machine.handleFlagsChanged(modifierDown: false), SwitcherAction.confirm)
        XCTAssertFalse(machine.isActive)
    }

    func testShiftAloneDoesNotChangeActivationKey() {
        var machine = SwitcherStateMachine()
        let result = machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: false, shiftDown: true)
        XCTAssertEqual(result.action, SwitcherAction.none)
        XCTAssertFalse(result.swallow)
        XCTAssertFalse(machine.isActive)
    }

    func testTabWithoutModifierPassesThroughWhenIdle() {
        var machine = SwitcherStateMachine()
        let result = machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: false, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.none)
        XCTAssertFalse(result.swallow)
        XCTAssertFalse(machine.isActive)
    }

    func testOtherKeysPassThroughWhenIdle() {
        var machine = SwitcherStateMachine()
        let result = machine.handleKeyDown(keyCode: kVK_ANSI_A, modifierDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.none)
        XCTAssertFalse(result.swallow)
    }

    /// Q/H are only meaningful inside a session — Cmd+Q / Cmd+H in an
    /// ordinary app must keep working when the switcher is idle.
    func testQuitAndHideKeysPassThroughWhenIdle() {
        var machine = SwitcherStateMachine()
        for key in [kVK_ANSI_Q, kVK_ANSI_H] {
            let result = machine.handleKeyDown(keyCode: key, modifierDown: true, shiftDown: false)
            XCTAssertEqual(result.action, SwitcherAction.none)
            XCTAssertFalse(result.swallow)
        }
        XCTAssertFalse(machine.isActive)
    }

    // MARK: - Cycling

    func testCyclingWhileActive() {
        var machine = activated()
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: true, shiftDown: false).action, SwitcherAction.cycleNext)
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: true, shiftDown: true).action, SwitcherAction.cyclePrevious)
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_RightArrow, modifierDown: true, shiftDown: false).action, SwitcherAction.cycleNext)
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_LeftArrow, modifierDown: true, shiftDown: false).action, SwitcherAction.cyclePrevious)
        XCTAssertTrue(machine.isActive)
    }

    func testCyclingSwallowsEvents() {
        var machine = activated()
        XCTAssertTrue(machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: true, shiftDown: false).swallow)
        XCTAssertTrue(machine.handleKeyDown(keyCode: kVK_LeftArrow, modifierDown: true, shiftDown: false).swallow)
    }

    /// While the switcher is up the modifier is still held, so any key that
    /// leaked would land on the frontmost app as a chord (Cmd+W, Cmd+A …).
    /// Unhandled keys are swallowed, do nothing, and keep the session alive.
    func testUnhandledKeyWhileActiveIsSwallowed() {
        var machine = activated()
        for key in [kVK_ANSI_A, kVK_ANSI_W, kVK_Space, kVK_Delete] {
            let result = machine.handleKeyDown(keyCode: key, modifierDown: true, shiftDown: false)
            XCTAssertEqual(result.action, SwitcherAction.none)
            XCTAssertTrue(result.swallow, "key \(key) leaked to the frontmost app")
            XCTAssertTrue(machine.isActive)
        }
    }

    // MARK: - Quit / Hide selected app

    func testQuitKeyWhileActiveQuitsSelectedAndKeepsSession() {
        var machine = activated()
        let result = machine.handleKeyDown(keyCode: kVK_ANSI_Q, modifierDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.quitSelected)
        XCTAssertTrue(result.swallow)
        XCTAssertTrue(machine.isActive)
        // Still switching: Tab keeps cycling, release still confirms.
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: true, shiftDown: false).action, SwitcherAction.cycleNext)
        XCTAssertEqual(machine.handleFlagsChanged(modifierDown: false), SwitcherAction.confirm)
    }

    func testHideKeyWhileActiveHidesSelectedAndKeepsSession() {
        var machine = activated()
        let result = machine.handleKeyDown(keyCode: kVK_ANSI_H, modifierDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.hideSelected)
        XCTAssertTrue(result.swallow)
        XCTAssertTrue(machine.isActive)
    }

    // MARK: - Confirm / Cancel

    func testEscapeCancelsAndEndsSession() {
        var machine = activated()
        let result = machine.handleKeyDown(keyCode: kVK_Escape, modifierDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.cancel)
        XCTAssertTrue(result.swallow)
        XCTAssertFalse(machine.isActive)
    }

    func testReturnConfirmsAndEndsSession() {
        var machine = activated()
        let result = machine.handleKeyDown(keyCode: kVK_Return, modifierDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.confirm)
        XCTAssertTrue(result.swallow)
        XCTAssertFalse(machine.isActive)
    }

    func testModifierReleaseConfirmsWhileActive() {
        var machine = activated()
        XCTAssertEqual(machine.handleFlagsChanged(modifierDown: false), SwitcherAction.confirm)
        XCTAssertFalse(machine.isActive)
    }

    func testModifierReleaseIsNoOpWhenIdle() {
        var machine = SwitcherStateMachine()
        XCTAssertEqual(machine.handleFlagsChanged(modifierDown: false), SwitcherAction.none)
    }

    func testModifierStillDownIsNoOpWhileActive() {
        var machine = activated()
        XCTAssertEqual(machine.handleFlagsChanged(modifierDown: true), SwitcherAction.none)
        XCTAssertTrue(machine.isActive)
    }

    // MARK: - Tap disabled / cancelSession

    func testTapDisabledCancelsActiveSession() {
        var machine = activated()
        XCTAssertEqual(machine.handleTapDisabled(), SwitcherAction.cancel)
        XCTAssertFalse(machine.isActive)
        XCTAssertEqual(machine.handleTapDisabled(), SwitcherAction.none)
    }

    func testCancelSessionEndsSessionSilently() {
        var machine = activated()
        machine.cancelSession()
        XCTAssertFalse(machine.isActive)
        // Modifier release after a click-confirm must not re-confirm...
        XCTAssertEqual(machine.handleFlagsChanged(modifierDown: false), SwitcherAction.none)
        // ...and Modifier-Tab can start a fresh session immediately.
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: true, shiftDown: false).action, SwitcherAction.activate)
    }

    func testEscapeThenTabWhileModifierHeldReactivates() {
        var machine = activated()
        _ = machine.handleKeyDown(keyCode: kVK_Escape, modifierDown: true, shiftDown: false)
        let result = machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.activate)
        XCTAssertTrue(machine.isActive)
    }

    // MARK: - SwitcherModifier setting

    func testModifierDefaultIsOption() {
        XCTAssertEqual(SwitcherModifier.defaultModifier, SwitcherModifier.option)
        XCTAssertEqual(SwitcherModifier.resolve(nil), SwitcherModifier.option)
        XCTAssertEqual(SwitcherModifier.resolve("garbage"), SwitcherModifier.option)
    }

    func testModifierResolvesStoredValues() {
        XCTAssertEqual(SwitcherModifier.resolve("option"), SwitcherModifier.option)
        XCTAssertEqual(SwitcherModifier.resolve("command"), SwitcherModifier.command)
    }

    /// The flag is the ONLY thing HotkeyManager tests against CGEventFlags, so
    /// a wrong bit would silently bind the switcher to the wrong key.
    func testModifierFlagsMapToTheRightModifierBits() {
        XCTAssertEqual(SwitcherModifier.option.flag, CGEventFlags.maskAlternate)
        XCTAssertEqual(SwitcherModifier.command.flag, CGEventFlags.maskCommand)
        XCTAssertFalse(CGEventFlags.maskAlternate.contains(SwitcherModifier.command.flag))
        XCTAssertFalse(CGEventFlags.maskCommand.contains(SwitcherModifier.option.flag))
    }

    func testModifierRawValuesRoundTripThroughDefaultsStrings() {
        for modifier in SwitcherModifier.allCases {
            XCTAssertEqual(SwitcherModifier.resolve(modifier.rawValue), modifier)
        }
    }

    // MARK: - Helpers

    private func activated() -> SwitcherStateMachine {
        var machine = SwitcherStateMachine()
        _ = machine.handleKeyDown(keyCode: kVK_Tab, modifierDown: true, shiftDown: false)
        return machine
    }
}
