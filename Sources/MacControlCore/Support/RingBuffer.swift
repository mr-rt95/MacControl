//
//  RingBuffer.swift
//  MacControlCore
//

import Foundation

/// A fixed-capacity FIFO buffer that overwrites its oldest element when full.
///
/// Used for short in-memory histories (sparklines) so memory use stays constant.
public struct RingBuffer<Element> {

    private var storage: [Element] = []
    private var head = 0

    /// Maximum number of elements kept.
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    /// Number of elements currently stored.
    public var count: Int { storage.count }

    public var isEmpty: Bool { storage.isEmpty }

    /// Appends an element, evicting the oldest one when the buffer is full.
    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Elements in chronological order (oldest first).
    public var elements: [Element] {
        guard storage.count == capacity, head != 0 else { return storage }
        return Array(storage[head...] + storage[..<head])
    }

    /// Removes every element.
    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }
}
