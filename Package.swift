// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RemindersCompanion",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "RemindersCore", targets: ["RemindersCore"]),
        // iOS + watchOS only: the WatchConnectivity bridge. Kept out of RemindersCore so
        // the Mac app never links WatchConnectivity, which it has no use for.
        .library(name: "RemindersShared", targets: ["RemindersShared"]),
        .executable(name: "RemindersCompanion", targets: ["RemindersCompanion"]),
    ],
    targets: [
        .target(name: "RemindersCore"),
        .target(name: "RemindersShared", dependencies: ["RemindersCore"]),
        .executableTarget(name: "RemindersCompanion", dependencies: ["RemindersCore"]),
        .testTarget(name: "RemindersCoreTests", dependencies: ["RemindersCore"]),
    ]
)
