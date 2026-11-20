//
//  HistoryStore.swift
//  MacControlCore
//

import Foundation

/// Three-tier load and temperature history kept in memory and saved to a compact JSON file.
///
/// | Tier | Resolution | Retention | Points |
/// |------|-----------|-----------|--------|
/// | hour | 5 s       | 1 hour    | 720    |
/// | day  | 1 min     | 24 hours  | 1440   |
/// | week | 10 min    | 7 days    | 1008   |
///
/// Thread-safe: the sampling queue writes, the UI reads.
public final class HistoryStore {

    // MARK: - Types

    /// Averages raw samples into fixed-width buckets.
    private struct Accumulator {
        let range: HistoryRange
        var bucketIndex: Int64 = -1
        var count = 0
        var cpu = 0.0, memory = 0.0, diskRead = 0.0, diskWrite = 0.0, netDown = 0.0, netUp = 0.0
        var temperatureSum = 0.0, temperatureCount = 0
        var processScores: [String: Double] = [:]

        init(range: HistoryRange) { self.range = range }

        mutating func reset(bucketIndex: Int64) {
            self = Accumulator(range: range)
            self.bucketIndex = bucketIndex
        }

        var point: HistoryPoint? {
            guard count > 0 else { return nil }
            let n = Double(count)
            let top = processScores.sorted { $0.value > $1.value }.prefix(3).map(\.key)
            return HistoryPoint(
                time: Double(bucketIndex) * range.bucket,
                cpu: cpu / n, memory: memory / n,
                diskRead: diskRead / n, diskWrite: diskWrite / n,
                networkDown: netDown / n, networkUp: netUp / n,
                cpuTemperature: temperatureCount > 0 ? temperatureSum / Double(temperatureCount) : nil,
                topProcesses: top
            )
        }
    }

    /// Average CPU temperature observed at a given load level; used to spot cooling degradation.
    struct BaselineBucket: Codable, Equatable {
        var temperatureSum = 0.0
        var count = 0
    }

    private struct Persisted: Codable {
        var hour: [HistoryPoint]
        var day: [HistoryPoint]
        var week: [HistoryPoint]
        var baseline: [BaselineBucket]
    }

    // MARK: - State

    private static let baselineBucketCount = 10
    private static let baselineCountLimit = 50_000

    private let lock = NSLock()
    private let fileURL: URL?
    private var tiers: [HistoryRange: RingBuffer<HistoryPoint>]
    private var accumulators: [HistoryRange: Accumulator]
    private var baseline = [BaselineBucket](repeating: BaselineBucket(), count: baselineBucketCount)

    /// - Parameter fileURL: where to persist; `nil` keeps the history in memory only (tests).
    public init(fileURL: URL? = HistoryStore.defaultFileURL, now: Date = Date()) {
        self.fileURL = fileURL
        tiers = Dictionary(uniqueKeysWithValues: HistoryRange.allCases.map {
            ($0, RingBuffer<HistoryPoint>(capacity: Int($0.span / $0.bucket)))
        })
        accumulators = Dictionary(uniqueKeysWithValues: HistoryRange.allCases.map { ($0, Accumulator(range: $0)) })
        load(now: now)
    }

    /// `~/Library/Application Support/MacControl/history.json`
    public static var defaultFileURL: URL? {
        AppSupport.directory?.appendingPathComponent("history.json")
    }

    // MARK: - Recording

    /// Adds a measurement to every tier.
    public func record(_ snapshot: SystemSnapshot) {
        lock.lock()
        defer { lock.unlock() }

        let time = snapshot.timestamp.timeIntervalSince1970
        let temperature = snapshot.cpuTemperature
        let topNames = snapshot.processGroups.map { ($0.name, $0.cpuPercent) }

        for range in HistoryRange.allCases {
            var accumulator = accumulators[range]!
            let index = Int64(time / range.bucket)

            if index != accumulator.bucketIndex {
                if let finished = accumulator.point {
                    tiers[range]?.append(finished)
                    if range == .hour { updateBaseline(with: finished) }
                }
                accumulator.reset(bucketIndex: index)
            }

            accumulator.count += 1
            accumulator.cpu += snapshot.cpu.total
            accumulator.memory += snapshot.memory.usedFraction
            accumulator.diskRead += snapshot.disk.readBytesPerSecond
            accumulator.diskWrite += snapshot.disk.writeBytesPerSecond
            accumulator.netDown += snapshot.network.downloadBytesPerSecond
            accumulator.netUp += snapshot.network.uploadBytesPerSecond
            if let temperature = temperature {
                accumulator.temperatureSum += temperature
                accumulator.temperatureCount += 1
            }
            for (name, cpu) in topNames where cpu > 0.5 {
                accumulator.processScores[name, default: 0] += cpu
            }
            accumulators[range] = accumulator
        }
    }

    // MARK: - Reading

    /// Points of a tier within its span, oldest first. The bucket still being filled is included.
    public func points(for range: HistoryRange, now: Date = Date()) -> [HistoryPoint] {
        lock.lock()
        defer { lock.unlock() }
        return pointsLocked(range: range, from: now.timeIntervalSince1970 - range.span, to: now.timeIntervalSince1970)
    }

    /// Points covering `from...to` using the finest tier that still reaches back to `from`.
    public func points(from: Date, to: Date, now: Date = Date()) -> [HistoryPoint] {
        lock.lock()
        defer { lock.unlock() }
        let age = now.timeIntervalSince(from)
        let range = HistoryRange.allCases.first { age <= $0.span } ?? .week
        return pointsLocked(range: range, from: from.timeIntervalSince1970, to: to.timeIntervalSince1970)
    }

    /// The point nearest to `date`, within one bucket, for hover read-outs.
    public static func nearest(to date: Date, in points: [HistoryPoint], tolerance: TimeInterval) -> HistoryPoint? {
        let t = date.timeIntervalSince1970
        guard let best = points.min(by: { abs($0.time - t) < abs($1.time - t) }),
              abs(best.time - t) <= tolerance else { return nil }
        return best
    }

    /// Removes all stored history, including the cooling baseline, and the file on disk.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        for range in HistoryRange.allCases {
            tiers[range]?.removeAll()
            accumulators[range] = Accumulator(range: range)
        }
        baseline = [BaselineBucket](repeating: BaselineBucket(), count: Self.baselineBucketCount)
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Cooling baseline

    /// Typical CPU temperature of this Mac at the given load, and how many observations it rests on.
    public func baselineTemperature(forLoad load: Double) -> (celsius: Double, observations: Int)? {
        lock.lock()
        defer { lock.unlock() }
        let bucket = baseline[Self.bucketIndex(forLoad: load)]
        guard bucket.count > 0 else { return nil }
        return (bucket.temperatureSum / Double(bucket.count), bucket.count)
    }

    private static func bucketIndex(forLoad load: Double) -> Int {
        min(baselineBucketCount - 1, max(0, Int(load * Double(baselineBucketCount))))
    }

    private func updateBaseline(with point: HistoryPoint) {
        guard let temperature = point.cpuTemperature else { return }
        let index = Self.bucketIndex(forLoad: point.cpu)
        baseline[index].temperatureSum += temperature
        baseline[index].count += 1
        if baseline[index].count > Self.baselineCountLimit {   // slowly forget the distant past
            baseline[index].temperatureSum /= 2
            baseline[index].count /= 2
        }
    }

    // MARK: - Persistence

    /// Writes the history to disk atomically.
    public func save() {
        guard let url = fileURL else { return }
        lock.lock()
        let persisted = Persisted(
            hour: tiers[.hour]?.elements ?? [],
            day: tiers[.day]?.elements ?? [],
            week: tiers[.week]?.elements ?? [],
            baseline: baseline
        )
        lock.unlock()

        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func load(now: Date) {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let persisted = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        let current = now.timeIntervalSince1970
        for (range, points) in [(HistoryRange.hour, persisted.hour), (.day, persisted.day), (.week, persisted.week)] {
            for point in points where point.time >= current - range.span {
                tiers[range]?.append(point)
            }
        }
        if persisted.baseline.count == Self.baselineBucketCount { baseline = persisted.baseline }
    }

    // MARK: - Private

    private func pointsLocked(range: HistoryRange, from: TimeInterval, to: TimeInterval) -> [HistoryPoint] {
        var result = (tiers[range]?.elements ?? []).filter { $0.time >= from && $0.time <= to }
        if let partial = accumulators[range]?.point, partial.time >= from, partial.time <= to,
           partial.time > (result.last?.time ?? -1) {
            result.append(partial)
        }
        return result
    }
}
