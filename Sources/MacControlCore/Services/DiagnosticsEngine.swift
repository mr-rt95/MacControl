//
//  DiagnosticsEngine.swift
//  MacControlCore
//

import Foundation

/// Facts the rules reason about. Built by `DiagnosticsService`; constructed directly in tests.
public struct DiagnosticsInput {
    public var snapshot: SystemSnapshot
    public var throttle: ThrottleInfo
    public var diskHealth: DiskHealth
    public var battery: BatteryHealth?
    public var modelIdentifier: String
    public var thresholds: DiagnosticsThresholds
    public var cpuCulprit: Culprit?
    public var memoryCulprit: Culprit?
    public var highCPUSeconds: TimeInterval
    public var memoryPressureSeconds: TimeInterval
    public var coolingSuspicionSeconds: TimeInterval
    /// Typical CPU temperature of this Mac at the current load.
    public var temperatureBaseline: (celsius: Double, observations: Int)?
    /// CPU use of WindowServer (window drawing) and how long it has stayed high.
    public var graphicsCPUPercent: Double
    public var graphicsBusySeconds: TimeInterval
    /// CPU use of `kernel_task`. When macOS throttles a hot CPU it burns cycles in kernel_task on purpose.
    public var kernelTaskCPUPercent: Double

    public init(snapshot: SystemSnapshot, throttle: ThrottleInfo = .none, diskHealth: DiskHealth = .unknown,
                battery: BatteryHealth? = nil, modelIdentifier: String = "",
                thresholds: DiagnosticsThresholds = DiagnosticsThresholds(),
                cpuCulprit: Culprit? = nil, memoryCulprit: Culprit? = nil,
                highCPUSeconds: TimeInterval = 0, memoryPressureSeconds: TimeInterval = 0,
                coolingSuspicionSeconds: TimeInterval = 0,
                temperatureBaseline: (celsius: Double, observations: Int)? = nil,
                graphicsCPUPercent: Double = 0, graphicsBusySeconds: TimeInterval = 0,
                kernelTaskCPUPercent: Double = 0) {
        self.kernelTaskCPUPercent = kernelTaskCPUPercent
        self.graphicsCPUPercent = graphicsCPUPercent
        self.graphicsBusySeconds = graphicsBusySeconds
        self.snapshot = snapshot
        self.throttle = throttle
        self.diskHealth = diskHealth
        self.battery = battery
        self.modelIdentifier = modelIdentifier
        self.thresholds = thresholds
        self.cpuCulprit = cpuCulprit
        self.memoryCulprit = memoryCulprit
        self.highCPUSeconds = highCPUSeconds
        self.memoryPressureSeconds = memoryPressureSeconds
        self.coolingSuspicionSeconds = coolingSuspicionSeconds
        self.temperatureBaseline = temperatureBaseline
    }
}

/// Heuristic rules that turn measurements into findings.
///
/// These are heuristics, not an absolute diagnosis: every finding carries the evidence it is based on.
public enum DiagnosticsEngine {

    /// Seconds a suspicious condition must last before it is reported (avoids flicker).
    public static let cpuOverloadDefaultSeconds: TimeInterval = 60
    static let memoryWarningSeconds: TimeInterval = 60
    static let memoryInsufficientSeconds: TimeInterval = 300
    public static let coolingSeconds: TimeInterval = 120
    /// WindowServer above this percentage of one core, for this long, is reported.
    static let graphicsThreshold = 25.0
    /// kernel_task above this percentage of one core is treated as thermal throttling.
    static let kernelTaskThreshold = 30.0
    static let graphicsSeconds: TimeInterval = 60
    static let batteryWarningWear = 0.20
    static let batterySeriousWear = 0.50

    /// Evaluates every rule; the result is sorted with the most serious finding first.
    public static func evaluate(_ input: DiagnosticsInput) -> [Finding] {
        let findings = [
            heat(input), cpuOverload(input), graphics(input), memory(input), disk(input),
            cooling(input), ssd(input), ssdWear(input), battery(input)
        ].compactMap { $0 }

        return findings.sorted {
            $0.severity != $1.severity ? $0.severity > $1.severity : $0.kind.priority < $1.kind.priority
        }
    }

    // MARK: - Rules

    /// Overheating and/or throttling (reported as one finding because they are one story).
    static func heat(_ input: DiagnosticsInput) -> Finding? {
        let snapshot = input.snapshot
        let hottest = snapshot.hottest(in: .cpu)
        let overheated = (hottest ?? 0) >= input.thresholds.overheatingCelsius
        let kernelTaskThrottling = input.kernelTaskCPUPercent >= kernelTaskThreshold
        // A hot CPU with kernel_task busy means macOS is deliberately slowing it down, even when pmset reports 100 %.
        let throttled = input.throttle.isThrottling || (overheated && kernelTaskThrottling)
        guard overheated || throttled else { return nil }

        var metrics: [String: Double] = [:]
        var evidence: [Evidence] = []
        if let hottest = hottest {
            metrics["temperature"] = hottest
            evidence.append(Evidence(label: "CPU temperature", value: String(format: "%.0f °C", hottest)))
        }
        if let limit = input.throttle.speedLimitPercent, limit < 100 {
            metrics["speedLimit"] = Double(limit)
            evidence.append(Evidence(label: "CPU speed limit", value: "\(limit)%"))
        }
        if kernelTaskThrottling {
            metrics["kernelTask"] = input.kernelTaskCPUPercent
            evidence.append(Evidence(label: "kernel_task CPU (%)", value: String(format: "%.0f", input.kernelTaskCPUPercent)))
        }
        evidence.append(Evidence(label: "Thermal state", value: "\(input.throttle.thermalState)".lowercased()))
        evidence.append(Evidence(label: "CPU load", value: String(format: "%.0f%%", snapshot.cpu.total * 100)))
        if let fan = snapshot.fans.compactMap(\.currentRPM).max() {
            evidence.append(Evidence(label: "Fan speed (rpm)", value: String(format: "%.0f", fan)))
        }
        if let culprit = input.cpuCulprit {
            evidence.append(Evidence(label: "Main consumer (CPU %)",
                                     value: String(format: "%@, %.0f%%", culprit.name, culprit.cpuPercent)))
        }

        let kind: FindingKind = overheated ? .overheating : .throttling
        var severity: Severity = overheated ? .serious : .warning
        if throttled, (input.throttle.speedLimitPercent ?? 100) < 100 || kernelTaskThrottling { severity = max(severity, .serious) }
        if overheated && throttled { severity = .critical }

        let action: RecommendedAction = input.cpuCulprit.map { .quitApp(name: $0.name) } ?? .closeHeavyApps
        return Finding(kind: kind, severity: severity, culprit: input.cpuCulprit,
                       metrics: metrics, evidence: evidence, action: action)
    }

    static func cpuOverload(_ input: DiagnosticsInput) -> Finding? {
        let load = input.snapshot.cpu.total
        guard load >= input.thresholds.cpuOverloadFraction,
              input.highCPUSeconds >= input.thresholds.cpuOverloadSeconds else { return nil }

        var evidence = [
            Evidence(label: "CPU load", value: String(format: "%.0f%%", load * 100)),
            Evidence(label: "Duration (s)", value: String(format: "%.0f", input.highCPUSeconds))
        ]
        if let culprit = input.cpuCulprit {
            evidence.append(Evidence(label: "Main consumer (CPU %)",
                                     value: String(format: "%@, %.0f%%", culprit.name, culprit.cpuPercent)))
        }
        return Finding(kind: .cpuOverload, severity: .warning, culprit: input.cpuCulprit,
                       metrics: ["load": load, "duration": input.highCPUSeconds],
                       evidence: evidence,
                       action: input.cpuCulprit.map { .quitApp(name: $0.name) } ?? .closeHeavyApps)
    }

    /// Window drawing (WindowServer) using a lot of CPU: typical on older Macs with transparency and animations.
    static func graphics(_ input: DiagnosticsInput) -> Finding? {
        guard input.graphicsCPUPercent >= graphicsThreshold, input.graphicsBusySeconds >= graphicsSeconds else { return nil }
        return Finding(kind: .graphicsLoad, severity: .warning,
                       metrics: ["cpu": input.graphicsCPUPercent, "duration": input.graphicsBusySeconds],
                       evidence: [Evidence(label: "WindowServer CPU (%)", value: String(format: "%.0f", input.graphicsCPUPercent)),
                                  Evidence(label: "Duration (s)", value: String(format: "%.0f", input.graphicsBusySeconds))],
                       action: .reduceVisualEffects)
    }

    static func memory(_ input: DiagnosticsInput) -> Finding? {
        let memory = input.snapshot.memory
        let sustained = memory.pressure >= .warning && input.memoryPressureSeconds >= memoryWarningSeconds
        guard memory.pressure == .critical || sustained else { return nil }

        // An app holding a third of used memory is the likely cause; otherwise suspect too little RAM.
        let culprit = input.memoryCulprit
        let dominant = culprit.map { memory.used > 0 && Double($0.memoryBytes) / Double(memory.used) >= 0.35 } ?? false
        let insufficient = !dominant && input.memoryPressureSeconds >= memoryInsufficientSeconds
        let upgradable = isMemoryUpgradable(model: input.modelIdentifier)

        var metrics: [String: Double] = [
            "pressure": Double(memory.pressure.rawValue),
            "swap": Double(memory.swapUsed),
            "insufficient": insufficient ? 1 : 0
        ]
        if let upgradable = upgradable { metrics["upgradable"] = upgradable ? 1 : 0 }

        var evidence = [
            Evidence(label: "Memory pressure", value: "\(memory.pressure)".lowercased()),
            Evidence(label: "Swap used", value: ByteCountFormatter.string(fromByteCount: Int64(memory.swapUsed), countStyle: .memory)),
            Evidence(label: "Memory used", value: ByteCountFormatter.string(fromByteCount: Int64(memory.used), countStyle: .memory))
        ]
        if let culprit = culprit {
            evidence.append(Evidence(label: "Largest app",
                                     value: "\(culprit.name) (\(ByteCountFormatter.string(fromByteCount: Int64(culprit.memoryBytes), countStyle: .memory)))"))
        }

        let action: RecommendedAction
        if dominant, let culprit = culprit { action = .quitApp(name: culprit.name) }
        else if insufficient && upgradable == true { action = .addMemory }
        else { action = .reduceMemoryUse }

        return Finding(kind: .memoryPressure,
                       severity: memory.pressure == .critical ? .serious : .warning,
                       culprit: dominant ? culprit : nil, metrics: metrics, evidence: evidence, action: action)
    }

    static func disk(_ input: DiagnosticsInput) -> Finding? {
        let disk = input.snapshot.disk
        guard disk.totalBytes > 0 else { return nil }
        let thresholds = input.thresholds

        let severity: Severity
        if disk.availableBytes < thresholds.diskCriticalFreeBytes { severity = .critical }
        else if disk.freeFraction < thresholds.diskSeriousFreeFraction { severity = .serious }
        else if disk.freeFraction < thresholds.diskWarningFreeFraction { severity = .warning }
        else { return nil }

        let free = ByteCountFormatter.string(fromByteCount: Int64(disk.availableBytes), countStyle: .file)
        return Finding(kind: .diskLow, severity: severity,
                       metrics: ["free": Double(disk.availableBytes), "freeFraction": disk.freeFraction],
                       evidence: [
                           Evidence(label: "Free space", value: String(format: "%@ (%.0f%%)", free, disk.freeFraction * 100)),
                           Evidence(label: "Disk capacity", value: ByteCountFormatter.string(fromByteCount: Int64(disk.totalBytes), countStyle: .file))
                       ],
                       action: .freeDiskSpace)
    }

    /// Hot CPU with busy fans but little work, or much hotter than this Mac used to be at the same load.
    static func cooling(_ input: DiagnosticsInput) -> Finding? {
        guard input.coolingSuspicionSeconds >= coolingSeconds else { return nil }
        let snapshot = input.snapshot
        let load = snapshot.cpu.total
        guard let temperature = snapshot.hottest(in: .cpu) else { return nil }

        var evidence = [
            Evidence(label: "CPU temperature", value: String(format: "%.0f °C", temperature)),
            Evidence(label: "CPU load", value: String(format: "%.0f%%", load * 100))
        ]
        var metrics = ["temperature": temperature, "load": load]
        if let fan = snapshot.fans.compactMap(\.speedFraction).max() {
            metrics["fan"] = fan
            evidence.append(Evidence(label: "Fan speed (% of maximum)", value: String(format: "%.0f%%", fan * 100)))
        }
        if let baseline = input.temperatureBaseline {
            metrics["baselineDelta"] = temperature - baseline.celsius
            evidence.append(Evidence(label: "Usual temperature at this load", value: String(format: "%.0f °C", baseline.celsius)))
        }
        return Finding(kind: .cooling, severity: .warning, metrics: metrics, evidence: evidence, action: .cleanCooling)
    }

    /// `true` when the suspicion conditions hold right now (the service times how long they last).
    public static func coolingSuspected(snapshot: SystemSnapshot,
                                        baseline: (celsius: Double, observations: Int)?) -> Bool {
        guard let temperature = snapshot.hottest(in: .cpu) else { return false }
        let load = snapshot.cpu.total
        let fanBusy = (snapshot.fans.compactMap(\.speedFraction).max() ?? 0) >= 0.75
        if fanBusy && temperature >= 75 && load <= 0.4 { return true }
        if let baseline = baseline, baseline.observations >= 200, load <= 0.6,
           temperature - baseline.celsius >= 10 { return true }
        return false
    }

    static func ssd(_ input: DiagnosticsInput) -> Finding? {
        guard input.diskHealth.smart == .failing else { return nil }
        return Finding(kind: .ssdFailing, severity: .critical,
                       evidence: [Evidence(label: "SMART status", value: "Failing")],
                       action: .backUpData)
    }

    /// Wear reported by the drive itself. A manufacturer estimate, so only high values or real warnings are reported.
    static func ssdWear(_ input: DiagnosticsInput) -> Finding? {
        guard let wear = input.diskHealth.wear else { return nil }
        let spareLow = wear.availableSpare < wear.spareThreshold
        let severity: Severity
        if wear.criticalWarning != 0 || spareLow { severity = .critical }
        else if wear.percentageUsed >= 90 { severity = .serious }
        else if wear.percentageUsed >= 70 { severity = .warning }
        else { return nil }

        return Finding(
            kind: .ssdWear, severity: severity,
            metrics: ["used": Double(wear.percentageUsed), "spare": Double(wear.availableSpare),
                      "written": Double(wear.bytesWritten)],
            evidence: [
                Evidence(label: "SSD life used", value: "\(wear.percentageUsed)%"),
                Evidence(label: "Spare blocks", value: "\(wear.availableSpare)%"),
                Evidence(label: "Data written", value: ByteCountFormatter.string(fromByteCount: Int64(clamping: wear.bytesWritten), countStyle: .decimal)),
                Evidence(label: "Media errors", value: "\(wear.mediaErrors)")
            ],
            action: .planSSDReplacement)
    }

    static func battery(_ input: DiagnosticsInput) -> Finding? {
        guard let battery = input.battery, battery.maximumCapacity > 0,
              battery.wearFraction >= batteryWarningWear else { return nil }
        return Finding(
            kind: .batteryWear,
            severity: battery.wearFraction >= batterySeriousWear ? .serious : .warning,
            metrics: ["wear": battery.wearFraction, "cycles": Double(battery.cycleCount)],
            evidence: [
                Evidence(label: "Battery capacity (% of design)", value: String(format: "%.0f%%", battery.healthFraction * 100)),
                Evidence(label: "Charge cycles", value: "\(battery.cycleCount)")
            ],
            action: .replaceBattery)
    }

    // MARK: - Model knowledge

    /// Whether RAM can be added to this model. `nil` when unknown.
    public static func isMemoryUpgradable(model: String) -> Bool? {
        let family = ModelFamily(modelIdentifier: model)
        let major = Int(model.drop { !$0.isNumber }.prefix { $0.isNumber }) ?? 0
        switch family {
        case .macBookAir, .macBook: return false
        case .macBookPro:           return major <= 9      // 2012 and earlier non-Retina models
        case .macMini:              return major != 7      // the 2014 Mac mini has soldered RAM
        case .iMac, .macPro, .unknown: return nil
        }
    }
}
