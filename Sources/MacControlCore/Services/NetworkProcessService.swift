//
//  NetworkProcessService.swift
//  MacControlCore
//

import Foundation
import Combine

/// Repeatedly measures per-process network traffic while a screen needs it.
///
/// Call `start()` when the Network screen appears and `stop()` when it disappears,
/// so `nettop` is never running in the background.
public final class NetworkProcessService: ObservableObject {

    @Published public private(set) var usage: [ProcessNetworkUsage] = []
    /// `false` until the first measurement completes.
    @Published public private(set) var hasMeasurement = false

    private let monitor = NetworkProcessMonitor()
    private let queue = DispatchQueue(label: "com.maccontrol.nettop", qos: .utility)
    private var generation = 0   // invalidates in-flight loops after stop()

    public init() {}

    public func start() {
        generation += 1
        let current = generation
        queue.async { [weak self] in self?.loop(generation: current) }
    }

    public func stop() {
        generation += 1
    }

    private func loop(generation current: Int) {
        while true {
            let isCurrent = DispatchQueue.main.sync { current == generation }
            guard isCurrent else { return }

            let result = monitor.measure(seconds: 2)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, current == self.generation else { return }
                self.usage = result
                self.hasMeasurement = true
            }
        }
    }
}
