// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemindersCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RemindersCore", targets: ["RemindersCore"]),
        .executable(name: "RemindersCompanion", targets: ["RemindersCompanion"]),
    ],
    targets: [
        .target(name: "RemindersCore"),
        .executableTarget(name: "RemindersCompanion", dependencies: ["RemindersCore"]),
        .testTarget(name: "RemindersCoreTests", dependencies: ["RemindersCore"]),
    ]
)
