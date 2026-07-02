//
//  SwitcherStateMachineTests.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Unit tests for the Option-Tab session state machine used by HotkeyManager.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  License: MIT
//

import XCTest
import Carbon.HIToolbox
@testable import AltTabCore

final class SwitcherStateMachineTests: XCTestCase {

    // MARK: - Activation

    func testOptionTabActivatesAndSwallows() {
        var machine = SwitcherStateMachine()
        let result = machine.handleKeyDown(keyCode: kVK_Tab, optionDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.activate)
        XCTAssertTrue(result.swallow)
        XCTAssertTrue(machine.isActive)
    }

    func testTabWithoutOptionPassesThroughWhenIdle() {
        var machine = SwitcherStateMachine()
        let result = machine.handleKeyDown(keyCode: kVK_Tab, optionDown: false, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.none)
        XCTAssertFalse(result.swallow)
        XCTAssertFalse(machine.isActive)
    }

    func testOtherKeysPassThroughWhenIdle() {
        var machine = SwitcherStateMachine()
        let result = machine.handleKeyDown(keyCode: kVK_ANSI_A, optionDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.none)
        XCTAssertFalse(result.swallow)
    }

    // MARK: - Cycling

    func testCyclingWhileActive() {
        var machine = activated()
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_Tab, optionDown: true, shiftDown: false).action, SwitcherAction.cycleNext)
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_Tab, optionDown: true, shiftDown: true).action, SwitcherAction.cyclePrevious)
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_RightArrow, optionDown: true, shiftDown: false).action, SwitcherAction.cycleNext)
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_LeftArrow, optionDown: true, shiftDown: false).action, SwitcherAction.cyclePrevious)
        XCTAssertTrue(machine.isActive)
    }

    func testCyclingSwallowsEvents() {
        var machine = activated()
        XCTAssertTrue(machine.handleKeyDown(keyCode: kVK_Tab, optionDown: true, shiftDown: false).swallow)
        XCTAssertTrue(machine.handleKeyDown(keyCode: kVK_LeftArrow, optionDown: true, shiftDown: false).swallow)
    }

    func testUnhandledKeyWhileActivePassesThrough() {
        var machine = activated()
        let result = machine.handleKeyDown(keyCode: kVK_ANSI_A, optionDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.none)
        XCTAssertFalse(result.swallow)
        XCTAssertTrue(machine.isActive)
    }

    // MARK: - Confirm / Cancel

    func testEscapeCancelsAndEndsSession() {
        var machine = activated()
        let result = machine.handleKeyDown(keyCode: kVK_Escape, optionDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.cancel)
        XCTAssertTrue(result.swallow)
        XCTAssertFalse(machine.isActive)
    }

    func testReturnConfirmsAndEndsSession() {
        var machine = activated()
        let result = machine.handleKeyDown(keyCode: kVK_Return, optionDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.confirm)
        XCTAssertTrue(result.swallow)
        XCTAssertFalse(machine.isActive)
    }

    func testOptionReleaseConfirmsWhileActive() {
        var machine = activated()
        XCTAssertEqual(machine.handleFlagsChanged(optionDown: false), SwitcherAction.confirm)
        XCTAssertFalse(machine.isActive)
    }

    func testOptionReleaseIsNoOpWhenIdle() {
        var machine = SwitcherStateMachine()
        XCTAssertEqual(machine.handleFlagsChanged(optionDown: false), SwitcherAction.none)
    }

    func testOptionStillDownIsNoOpWhileActive() {
        var machine = activated()
        XCTAssertEqual(machine.handleFlagsChanged(optionDown: true), SwitcherAction.none)
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
        // Option release after a click-confirm must not re-confirm...
        XCTAssertEqual(machine.handleFlagsChanged(optionDown: false), SwitcherAction.none)
        // ...and Option-Tab can start a fresh session immediately.
        XCTAssertEqual(machine.handleKeyDown(keyCode: kVK_Tab, optionDown: true, shiftDown: false).action, SwitcherAction.activate)
    }

    func testEscapeThenTabWhileOptionHeldReactivates() {
        var machine = activated()
        _ = machine.handleKeyDown(keyCode: kVK_Escape, optionDown: true, shiftDown: false)
        let result = machine.handleKeyDown(keyCode: kVK_Tab, optionDown: true, shiftDown: false)
        XCTAssertEqual(result.action, SwitcherAction.activate)
        XCTAssertTrue(machine.isActive)
    }

    // MARK: - Helpers

    private func activated() -> SwitcherStateMachine {
        var machine = SwitcherStateMachine()
        _ = machine.handleKeyDown(keyCode: kVK_Tab, optionDown: true, shiftDown: false)
        return machine
    }
}
