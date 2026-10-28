// swift-tools-version: 5.9

// The FreeCol app for iOS and iPadOS (Phase 5 of doc/swift-port-plan.md):
// the screens, in SwiftUI, over the engine and map planning of
// FreeColKit.  It is a Swift Playgrounds style app package, which Xcode
// opens and xcodebuild builds as it is.
//
// Its resources are the game's data folder and the test saved games,
// each a symlink to its folder in the repository (Xcode copies a linked
// folder's contents, but not links inside a folder).
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "FreeColApp",
    platforms: [
        .iOS("17.0"),
    ],
    products: [
        .iOSApplication(
            name: "FreeCol",
            targets: ["FreeColApp"],
            bundleIdentifier: "net.sf.freecol.ios",
            displayVersion: "0.1",
            bundleVersion: "1",
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [.portrait, .landscapeLeft, .landscapeRight, .portraitUpsideDown(.when(deviceFamilies: [.pad]))]
        ),
    ],
    dependencies: [
        .package(path: "../FreeColKit"),
    ],
    targets: [
        .executableTarget(
            name: "FreeColApp",
            dependencies: [.product(name: "FreeColKit", package: "FreeColKit")],
            path: "Sources",
            exclude: [],
            resources: [.copy("Resources/data"), .copy("Resources/games")]
        ),
    ]
)
