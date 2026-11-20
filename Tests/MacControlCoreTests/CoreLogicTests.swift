//
//  CoreLogicTests.swift
//  MacControlCoreTests
//

import XCTest
@testable import MacControlCore

final class RingBufferTests: XCTestCase {

    func testKeepsChronologicalOrderAfterOverflow() {
        var buffer = RingBuffer<Int>(capacity: 3)
        (1...5).forEach { buffer.append($0) }
        XCTAssertEqual(buffer.elements, [3, 4, 5])
        XCTAssertEqual(buffer.count, 3)
    }

    func testRemoveAllResetsBuffer() {
        var buffer = RingBuffer<Int>(capacity: 2)
        buffer.append(1)
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
    }
}

final class SMCValueDecoderTests: XCTestCase {

    func testDecodesSignedFixedPointTemperature() {
        // 0x2D80 = 45.5 in sp78
        XCTAssertEqual(SMCValueDecoder.decode(type: "sp78", bytes: [0x2D, 0x80]), 45.5)
    }

    func testDecodesFanSpeed() {
        // 0x0FA0 = 4000 / 4 = 1000 rpm in fpe2
        XCTAssertEqual(SMCValueDecoder.decode(type: "fpe2", bytes: [0x0F, 0xA0]), 1000)
    }

    func testDecodesLittleEndianFloat() {
        let bits = Float(60).bitPattern
        let bytes = [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)]
        XCTAssertEqual(SMCValueDecoder.decode(type: "flt ", bytes: bytes), 60)
    }

    func testRejectsShortPayloadAndUnknownType() {
        XCTAssertNil(SMCValueDecoder.decode(type: "sp78", bytes: [0x01]))
        XCTAssertNil(SMCValueDecoder.decode(type: "zzzz", bytes: [0, 0, 0, 0]))
    }

    func testFourCCRoundTrip() {
        XCTAssertEqual(SMCValueDecoder.string(fromFourCC: SMCValueDecoder.fourCC("TC0P")), "TC0P")
    }

    /// The kernel expects exactly this layout (80 bytes).
    func testSMCParametersMatchKernelLayout() {
        XCTAssertEqual(MemoryLayout<SMCConnection.Parameters>.size, 80)
        XCTAssertEqual(MemoryLayout<SMCConnection.Parameters>.offset(of: \.keyInfo), 28)
        XCTAssertEqual(MemoryLayout<SMCConnection.Parameters>.offset(of: \.result), 40)
        XCTAssertEqual(MemoryLayout<SMCConnection.Parameters>.offset(of: \.bytes), 48)
    }
}

final class ModelAndThermalTests: XCTestCase {

    func testModelFamilyDetection() {
        XCTAssertEqual(ModelFamily(modelIdentifier: "MacBookPro14,1"), .macBookPro)
        XCTAssertEqual(ModelFamily(modelIdentifier: "MacBookAir7,2"), .macBookAir)
        XCTAssertEqual(ModelFamily(modelIdentifier: "MacBook9,1"), .macBook)
        XCTAssertEqual(ModelFamily(modelIdentifier: "iMac18,3"), .iMac)
        XCTAssertEqual(ModelFamily(modelIdentifier: "Foo1,1"), .unknown)
    }

    func testDesktopsHaveNoBatterySensors() {
        let keys = SensorCatalog.temperatureSensors(forModel: "iMac18,3").map(\.key)
        XCTAssertFalse(keys.contains("TB0T"))
        XCTAssertTrue(SensorCatalog.temperatureSensors(forModel: "MacBookPro14,1").map(\.key).contains("TB0T"))
    }

    func testThermalClassification() {
        XCTAssertEqual(ThermalLevel.classify(celsius: 50, category: .cpu), .normal)
        XCTAssertEqual(ThermalLevel.classify(celsius: 80, category: .cpu), .warm)
        XCTAssertEqual(ThermalLevel.classify(celsius: 95, category: .cpu), .hot)
    }

    func testFanSpeedFraction() {
        let fan = FanReading(index: 0, currentRPM: 4200, minimumRPM: 1200, maximumRPM: 7200)
        XCTAssertEqual(fan.speedFraction ?? -1, 0.5, accuracy: 0.001)
        XCTAssertNil(FanReading(index: 0, currentRPM: nil, minimumRPM: nil, maximumRPM: nil).speedFraction)
    }
}

final class ProcessGroupingTests: XCTestCase {

    func testAppBundleExtractionUsesOutermostApp() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/X/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        let bundle = ProcessMonitor.appBundle(fromExecutablePath: path)
        XCTAssertEqual(bundle?.name, "Google Chrome")
        XCTAssertEqual(bundle?.path, "/Applications/Google Chrome.app")
        XCTAssertNil(ProcessMonitor.appBundle(fromExecutablePath: "/usr/sbin/cfprefsd"))
    }

    func testGroupingSumsHelpersIntoParent() {
        func sample(_ pid: Int32, _ cpu: Double, _ mem: UInt64) -> ProcessSample {
            ProcessSample(pid: pid, name: "p\(pid)", groupKey: "/A.app", groupName: "A", uid: 501,
                          cpuPercent: cpu, memoryBytes: mem,
                          diskReadBytesPerSecond: 1, diskWriteBytesPerSecond: 2)
        }
        let groups = ProcessGroup.group([sample(10, 5, 100), sample(11, 7, 200)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].cpuPercent, 12)
        XCTAssertEqual(groups[0].memoryBytes, 300)
        XCTAssertEqual(groups[0].processCount, 2)
    }
}

final class NettopParsingTests: XCTestCase {

    func testUsesLastBlockAndDropsIdleProcesses() {
        let output = """
        ,bytes_in,bytes_out,
        old.1,999,999,
        ,bytes_in,bytes_out,
        Brave Browser H.809,100,50,
        idle.5,0,0,
        mDNSResponder.218,10,5,
        """
        let usage = NetworkProcessMonitor.parse(output)
        XCTAssertEqual(usage.map(\.pid), [809, 218])
        XCTAssertEqual(usage.first?.name, "Brave Browser H")
    }
}
