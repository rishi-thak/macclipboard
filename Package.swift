// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "clipboardopt",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Pure logic: history, classifiers, decision table, Jev request/response,
        // clipboard snapshot. Everything here is unit-tested.
        .target(
            name: "ClipOptCore",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        // The background app: hotkey, Accessibility field reading, paste, panel.
        .executableTarget(
            name: "clipboardopt",
            dependencies: ["ClipOptCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "ClipOptCoreTests",
            dependencies: ["ClipOptCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
