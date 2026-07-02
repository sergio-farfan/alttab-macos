//
//  MRUOrder.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Pure MRU (most recently used) ordering of window IDs, extracted from
//  WindowModel so it is unit-testable without AppKit or Accessibility.
//  Front of the order = most recently used. Sorting builds a rank
//  dictionary once (O(n log n) total) instead of calling firstIndex(of:)
//  inside the comparator (O(n² log n)), and uses the input index as a
//  tiebreaker because Swift's sort is not guaranteed stable.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  License: MIT
//

import CoreGraphics

struct MRUOrder {

    /// MRU-ordered window IDs. Front of array = most recently used.
    private(set) var order: [CGWindowID] = []

    /// Replaces the order wholesale (seeding from the window stacking order).
    mutating func seed(_ ids: [CGWindowID]) {
        order = ids
    }

    /// Moves a window to the front (most recently used).
    mutating func promoteToFront(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    /// Drops IDs that no longer exist and appends newly discovered ones at the
    /// end, preserving their relative order.
    mutating func sync(with validIDs: [CGWindowID]) {
        let valid = Set(validIDs)
        order.removeAll { !valid.contains($0) }
        let known = Set(order)
        for id in validIDs where !known.contains(id) {
            order.append(id)
        }
    }

    /// Returns the items sorted by MRU rank. IDs not present in the order sort
    /// last, keeping their relative input order.
    func sorted<T>(_ items: [T], id: (T) -> CGWindowID) -> [T] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) },
                              uniquingKeysWith: { first, _ in first })
        return items.enumerated()
            .sorted { a, b in
                let rankA = rank[id(a.element)] ?? Int.max
                let rankB = rank[id(b.element)] ?? Int.max
                return rankA == rankB ? a.offset < b.offset : rankA < rankB
            }
            .map { $0.element }
    }
}
