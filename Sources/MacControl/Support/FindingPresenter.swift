//
//  FindingPresenter.swift
//  MacControl
//

import Foundation
import MacControlCore

/// Wording of one finding, in the user's language.
struct FindingText {
    let title: String
    let detail: String
    let advice: String
}

/// Turns structured findings into plain-language messages using localizable templates.
/// Adding a language only requires a new `Localizable.strings`.
enum FindingPresenter {

    static func text(for finding: Finding) -> FindingText {
        FindingText(title: title(for: finding), detail: detail(for: finding), advice: advice(for: finding))
    }

    /// Screen that shows the data behind a finding.
    static func screen(for finding: Finding) -> Screen {
        if case .quitApp = finding.action { return .processes }
        switch finding.kind {
        case .overheating, .throttling, .cpuOverload: return .processor
        case .memoryPressure: return .memory
        case .diskLow: return .cleanup
        case .cooling: return .sensors
        case .graphicsLoad: return .speedup
        case .ssdFailing, .ssdWear, .batteryWear: return .health
        }
    }

    /// Label of the button that opens that screen.
    static func buttonTitle(for finding: Finding) -> String {
        if case .quitApp(let name) = finding.action { return tr("Manage %@", name) }
        switch finding.kind {
        case .overheating, .throttling, .cpuOverload, .memoryPressure: return tr("Show top consumers")
        case .diskLow: return tr("Free up space")
        case .cooling: return tr("Show temperatures")
        case .graphicsLoad: return tr("Open Speed up")
        case .ssdFailing, .ssdWear, .batteryWear: return tr("Show health")
        }
    }

    // MARK: - Templates

    private static func title(for finding: Finding) -> String {
        switch finding.kind {
        case .overheating:
            return (finding.metrics["speedLimit"] != nil || finding.metrics["kernelTask"] != nil)
                ? tr("Your Mac is overheating and slowing itself down")
                : tr("Your Mac is overheating")
        case .throttling:     return tr("The processor is slowing itself down")
        case .cpuOverload:    return tr("The processor is overloaded")
        case .memoryPressure: return tr("Memory is running low")
        case .diskLow:        return tr("The disk is almost full")
        case .cooling:        return tr("Cooling may be impaired")
        case .graphicsLoad:   return tr("Drawing the screen uses a lot of processor time")
        case .ssdFailing:     return tr("The SSD reports a problem")
        case .ssdWear:        return tr("The SSD is wearing out")
        case .batteryWear:    return tr("The battery is worn out")
        }
    }

    private static func detail(for finding: Finding) -> String {
        let m = finding.metrics
        var sentences: [String] = []

        switch finding.kind {
        case .overheating:
            if let t = m["temperature"] { sentences.append(tr("CPU temperature is %@.", Formatters.temperature(t))) }
            if let limit = m["speedLimit"] { sentences.append(tr("Speed is limited to %@ of maximum.", "\(Int(limit))%")) }
            if let kernelTask = m["kernelTask"] {
                sentences.append(tr("kernel_task is using %@ of a core: macOS is deliberately slowing the processor to cool it down.",
                                    "\(Int(kernelTask))%"))
            }
            if let c = finding.culprit { sentences.append(tr("The main load comes from %@.", c.name)) }
        case .throttling:
            if let limit = m["speedLimit"] {
                sentences.append(tr("Speed is limited to %@ of maximum because of heat or power limits.", "\(Int(limit))%"))
            } else {
                sentences.append(tr("macOS reports a serious thermal state."))
            }
            if let c = finding.culprit { sentences.append(tr("The main load comes from %@.", c.name)) }
        case .cpuOverload:
            sentences.append(tr("Load has been %@ for %@.", Formatters.percent(m["load"] ?? 0), duration(m["duration"] ?? 0)))
            if let c = finding.culprit { sentences.append(tr("The main load comes from %@.", c.name)) }
        case .memoryPressure:
            let pressure = MemoryPressure(rawValue: Int(m["pressure"] ?? 1)) ?? .normal
            sentences.append(tr("Memory pressure is %@ and swap is %@.", pressureName(pressure), Formatters.bytes(UInt64(m["swap"] ?? 0))))
            if let c = finding.culprit {
                sentences.append(tr("%@ uses the most memory (%@).", c.name, Formatters.bytes(c.memoryBytes)))
            }
            if m["insufficient"] == 1 { sentences.append(tr("There is probably not enough RAM for your workload.")) }
        case .diskLow:
            sentences.append(tr("Only %@ left (%@). macOS needs free space for swap and temporary files.",
                                Formatters.bytes(UInt64(m["free"] ?? 0)), Formatters.percent(m["freeFraction"] ?? 0)))
        case .cooling:
            let temperature = Formatters.temperature(m["temperature"] ?? 0)
            let load = Formatters.percent(m["load"] ?? 0)
            if let fan = m["fan"], fan >= 0.75 {
                sentences.append(tr("Fans run at %@ of maximum while the CPU load is only %@, and the CPU is at %@.",
                                    Formatters.percent(fan), load, temperature))
            } else {
                sentences.append(tr("The CPU is at %@ with a load of only %@, hotter than usual for this Mac.", temperature, load))
            }
            sentences.append(tr("Dust or dried thermal paste are likely causes."))
        case .graphicsLoad:
            sentences.append(tr("WindowServer (window drawing) has used %@ of a processor core for %@. Transparency and animations are the usual cause on older Macs.",
                                "\(Int(m["cpu"] ?? 0))%", duration(m["duration"] ?? 0)))
        case .ssdFailing:
            sentences.append(tr("The drive's SMART self-assessment is failing."))
        case .ssdWear:
            sentences.append(tr("The drive reports %@ of its life used, %@ spare blocks left and %@ written in total.",
                                "\(Int(m["used"] ?? 0))%", "\(Int(m["spare"] ?? 0))%", Formatters.bytes(UInt64(m["written"] ?? 0))))
        case .batteryWear:
            sentences.append(tr("Capacity is %@ of the original, after %@ charge cycles.",
                                Formatters.percent(1 - (m["wear"] ?? 0)), "\(Int(m["cycles"] ?? 0))"))
        }
        return sentences.joined(separator: " ")
    }

    private static func advice(for finding: Finding) -> String {
        switch finding.action {
        case .quitApp(let name):   return tr("Close %@ or restart it.", name)
        case .closeHeavyApps:      return tr("Close apps you are not using.")
        case .freeDiskSpace:       return tr("Free up space: empty the Trash and remove large or unused files.")
        case .cleanCooling:
            return tr("Clean the fans and vents and avoid soft surfaces such as a bed or sofa. On Macs older than five years, new thermal paste may help.")
        case .reduceMemoryUse:
            let base = tr("Close apps and browser tabs you are not using.")
            return finding.metrics["upgradable"] == 0 ? base + " " + tr("Memory is soldered on this model and cannot be upgraded.") : base
        case .addMemory:           return tr("Adding more memory will help, and this model allows it.")
        case .replaceBattery:      return tr("Consider replacing the battery.")
        case .reduceVisualEffects: return tr("Turn off transparency and motion in Speed up.")
        case .planSSDReplacement:  return tr("Keep your backups current and plan to replace the drive before it reaches 100%.")
        case .backUpData:          return tr("Back up your data now and consider replacing the drive.")
        }
    }

    // MARK: - Helpers

    private static func pressureName(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal:   return tr("normal")
        case .warning:  return tr("warning")
        case .critical: return tr("critical")
        }
    }

    /// "5 min" / "40 s"
    static func duration(_ seconds: TimeInterval) -> String {
        seconds >= 90 ? tr("%@ min", "\(Int((seconds / 60).rounded()))") : tr("%@ s", "\(Int(seconds))")
    }
}
