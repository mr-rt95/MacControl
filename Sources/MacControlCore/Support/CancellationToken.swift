//
//  CancellationToken.swift
//  MacControlCore
//

import Foundation

/// Thread-safe flag that lets the UI abandon a long scan running on a background queue.
public final class CancellationToken {

    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
