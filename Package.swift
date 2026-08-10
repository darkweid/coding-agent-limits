// swift-tools-version: 6.0
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "QuotaOrbits",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuotaOrbitsCore", targets: ["QuotaOrbitsCore"]),
        .library(name: "QuotaOrbitsUI", targets: ["QuotaOrbitsUI"]),
        .executable(name: "QuotaOrbits", targets: ["QuotaOrbits"]),
    ],
    targets: [
        .target(name: "QuotaOrbitsCore", swiftSettings: swift6),
        .target(
            name: "QuotaOrbitsUI",
            dependencies: ["QuotaOrbitsCore"],
            resources: [.process("Resources")],
            swiftSettings: swift6
        ),
        .executableTarget(
            name: "QuotaOrbits",
            dependencies: ["QuotaOrbitsCore", "QuotaOrbitsUI"],
            swiftSettings: swift6
        ),
        .executableTarget(
            name: "QuotaOrbitsCoreTestRunner",
            dependencies: ["QuotaOrbitsCore"],
            path: "Tests/QuotaOrbitsCoreTestRunner",
            resources: [.copy("Fixtures")],
            swiftSettings: swift6
        ),
        .executableTarget(
            name: "QuotaOrbitsUITestRunner",
            dependencies: ["QuotaOrbitsUI", "QuotaOrbitsCore"],
            path: "Tests/QuotaOrbitsUITestRunner",
            swiftSettings: swift6
        ),
    ]
)
