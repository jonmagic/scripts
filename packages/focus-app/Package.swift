// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WeeklyFocus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "weekly-focus-app", targets: ["WeeklyFocusApp"]),
        .library(name: "WeeklyFocusCore", targets: ["WeeklyFocusCore"])
    ],
    targets: [
        .target(name: "WeeklyFocusCore"),
        .executableTarget(
            name: "WeeklyFocusApp",
            dependencies: ["WeeklyFocusCore"]
        ),
        .testTarget(
            name: "WeeklyFocusCoreTests",
            dependencies: ["WeeklyFocusCore"]
        )
    ]
)
