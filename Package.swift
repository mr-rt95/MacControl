// swift-tools-version:5.7
//
//  Package.swift
//  MacControl
//
//  Package layout:
//    - CLibProc        — C shim exposing libproc to Swift.
//    - CNVMe           — C shim reading NVMe SMART data (SSD wear) through IOKit.
//    - MacControlCore  — UI-independent system data collection (monitors, SMC, sampler).
//    - MacControl      — the SwiftUI/AppKit application (window + menu bar item).
//    - MacControlHelper — root daemon for administrator-only actions (see docs/HELPER.md).
//    - MacControlProbe — small CLI used to dump raw sensor data from a given Mac.
//

import PackageDescription

let package = Package(
    name: "MacControl",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "MacControl", targets: ["MacControl"]),
        .executable(name: "MacControlProbe", targets: ["MacControlProbe"]),
        .executable(name: "MacControlHelper", targets: ["MacControlHelper"]),
        .library(name: "MacControlCore", targets: ["MacControlCore"])
    ],
    targets: [
        .target(
            name: "CLibProc",
            path: "Sources/CLibProc"
        ),
        .target(
            name: "CNVMe",
            path: "Sources/CNVMe",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(
            name: "MacControlCore",
            dependencies: ["CLibProc", "CNVMe"],
            path: "Sources/MacControlCore"
        ),
        .executableTarget(
            name: "MacControl",
            dependencies: ["MacControlCore"],
            path: "Sources/MacControl"
        ),
        .executableTarget(
            name: "MacControlProbe",
            dependencies: ["MacControlCore"],
            path: "Sources/MacControlProbe"
        ),
        .executableTarget(
            name: "MacControlHelper",
            dependencies: ["MacControlCore"],
            path: "Sources/MacControlHelper",
            linkerSettings: [
                // Embeds the helper's Info.plist (it has no bundle), which carries the signing team ID.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", "Resources/HelperInfo.plist"])
            ]
        ),
        .testTarget(
            name: "MacControlCoreTests",
            dependencies: ["MacControlCore"],
            path: "Tests/MacControlCoreTests"
        )
    ]
)
