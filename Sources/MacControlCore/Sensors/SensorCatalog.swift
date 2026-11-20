//
//  SensorCatalog.swift
//  MacControlCore
//

import Foundation

/// Mac product family, derived from the `hw.model` identifier (e.g. `MacBookPro14,1`).
public enum ModelFamily: Equatable {
    case macBookPro
    case macBookAir
    case macBook
    case iMac
    case macMini
    case macPro
    case unknown

    public init(modelIdentifier: String) {
        // Order matters: "MacBookPro" and "MacBookAir" must be tested before "MacBook".
        if modelIdentifier.hasPrefix("MacBookPro") { self = .macBookPro }
        else if modelIdentifier.hasPrefix("MacBookAir") { self = .macBookAir }
        else if modelIdentifier.hasPrefix("MacBook") { self = .macBook }
        else if modelIdentifier.hasPrefix("iMac") { self = .iMac }
        else if modelIdentifier.hasPrefix("Macmini") { self = .macMini }
        else if modelIdentifier.hasPrefix("MacPro") { self = .macPro }
        else { self = .unknown }
    }

    /// Portable Macs have a battery, palm-rest sensors and a lid.
    public var isPortable: Bool {
        self == .macBookPro || self == .macBookAir || self == .macBook
    }
}

/// Table of SMC temperature sensors known for Intel Macs.
///
/// SMC key names vary between models, so the catalog lists candidates per family and
/// `SensorReader` keeps only those the machine actually exposes.
public enum SensorCatalog {

    /// Candidate temperature sensors for the given model identifier.
    public static func temperatureSensors(forModel model: String) -> [SensorDescriptor] {
        let family = ModelFamily(modelIdentifier: model)
        var sensors = cpu + gpu + storage + memory + common

        if family.isPortable {
            sensors += battery + portable
        } else {
            sensors += desktop
        }
        return sensors
    }

    // MARK: - Tables

    private static let cpu: [SensorDescriptor] = [
        .init(key: "TC0P", title: "CPU Proximity", category: .cpu),
        .init(key: "TC0D", title: "CPU Die", category: .cpu),
        .init(key: "TC0E", title: "CPU Die (E)", category: .cpu),
        .init(key: "TC0F", title: "CPU Die (F)", category: .cpu),
        .init(key: "TC0H", title: "CPU Heatsink", category: .cpu),
        .init(key: "TCXC", title: "CPU PECI", category: .cpu),
        .init(key: "TCSA", title: "CPU System Agent", category: .cpu),
        .init(key: "TPCD", title: "Platform Controller Hub", category: .cpu)
    ] + (1...8).map { SensorDescriptor(key: "TC\($0)C", title: "CPU Core \($0)", category: .cpu) }

    private static let gpu: [SensorDescriptor] = [
        .init(key: "TG0P", title: "GPU Proximity", category: .gpu),
        .init(key: "TG0D", title: "GPU Die", category: .gpu),
        .init(key: "TG0H", title: "GPU Heatsink", category: .gpu),
        .init(key: "TG1D", title: "GPU 2 Die", category: .gpu)
    ]

    private static let storage: [SensorDescriptor] = [
        .init(key: "TH0P", title: "Storage Proximity", category: .storage),
        .init(key: "TH0a", title: "Storage NAND A", category: .storage),
        .init(key: "TH0b", title: "Storage NAND B", category: .storage),
        .init(key: "TH0A", title: "Storage A", category: .storage),
        .init(key: "TH0B", title: "Storage B", category: .storage)
    ]

    private static let memory: [SensorDescriptor] = [
        .init(key: "TM0P", title: "Memory Proximity", category: .memory),
        .init(key: "TM0S", title: "Memory Module", category: .memory)
    ]

    private static let common: [SensorDescriptor] = [
        .init(key: "TA0P", title: "Ambient", category: .enclosure),
        .init(key: "TW0P", title: "Wi-Fi Module", category: .enclosure)
    ]

    private static let battery: [SensorDescriptor] = [
        .init(key: "TB0T", title: "Battery 1", category: .battery),
        .init(key: "TB1T", title: "Battery 2", category: .battery),
        .init(key: "TB2T", title: "Battery 3", category: .battery)
    ]

    private static let portable: [SensorDescriptor] = [
        .init(key: "Ts0P", title: "Palm Rest", category: .enclosure),
        .init(key: "Ts1P", title: "Palm Rest 2", category: .enclosure),
        .init(key: "Ts0S", title: "Enclosure Bottom", category: .enclosure),
        .init(key: "TaLP", title: "Airflow Left", category: .enclosure),
        .init(key: "TaRP", title: "Airflow Right", category: .enclosure)
    ]

    private static let desktop: [SensorDescriptor] = [
        .init(key: "TN0P", title: "Northbridge Proximity", category: .enclosure),
        .init(key: "Tp0P", title: "Power Supply Proximity", category: .enclosure)
    ]
}
