//
//  MRUOrderTests.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Unit tests for the MRU ordering logic used by WindowModel.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  License: MIT
//

import XCTest
import CoreGraphics
@testable import AltTabCore

final class MRUOrderTests: XCTestCase {

    func testSeedReplacesOrder() {
        var mru = MRUOrder()
        mru.seed([3, 1, 2])
        XCTAssertEqual(mru.order, [3, 1, 2])
        mru.seed([5])
        XCTAssertEqual(mru.order, [5])
    }

    func testPromoteToFrontMovesExistingID() {
        var mru = MRUOrder()
        mru.seed([1, 2, 3])
        mru.promoteToFront(3)
        XCTAssertEqual(mru.order, [3, 1, 2])
    }

    func testPromoteToFrontInsertsUnknownID() {
        var mru = MRUOrder()
        mru.seed([1, 2])
        mru.promoteToFront(9)
        XCTAssertEqual(mru.order, [9, 1, 2])
    }

    func testPromoteToFrontIsIdempotentAtFront() {
        var mru = MRUOrder()
        mru.seed([1, 2])
        mru.promoteToFront(1)
        XCTAssertEqual(mru.order, [1, 2])
    }

    func testSyncPrunesStaleAndAppendsNewInInputOrder() {
        var mru = MRUOrder()
        mru.seed([1, 2, 3])
        mru.sync(with: [3, 1, 7, 5])
        XCTAssertEqual(mru.order, [1, 3, 7, 5])
    }

    func testSyncWithEmptyClearsOrder() {
        var mru = MRUOrder()
        mru.seed([1, 2])
        mru.sync(with: [])
        XCTAssertEqual(mru.order, [])
    }

    func testSortedOrdersByRankWithUnrankedLastPreservingInputOrder() {
        var mru = MRUOrder()
        mru.seed([20, 10])
        let items: [CGWindowID] = [10, 30, 20, 40]
        let sorted = mru.sorted(items) { $0 }
        XCTAssertEqual(sorted, [20, 10, 30, 40])
    }

    func testSortedEmptyOrderKeepsInputOrder() {
        let mru = MRUOrder()
        let items: [CGWindowID] = [4, 2, 9]
        XCTAssertEqual(mru.sorted(items) { $0 }, [4, 2, 9])
    }

    func testSortedAfterPromotionsReflectsRecency() {
        var mru = MRUOrder()
        mru.seed([1, 2, 3])
        mru.promoteToFront(2)
        mru.promoteToFront(3)
        let sorted = mru.sorted([1, 2, 3] as [CGWindowID]) { $0 }
        XCTAssertEqual(sorted, [3, 2, 1])
    }
}
