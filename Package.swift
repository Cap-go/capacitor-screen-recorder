// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapgoCapacitorScreenRecorder",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapgoCapacitorScreenRecorder",
            targets: ["ScreenRecorderPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.1.0")
    ],
    targets: [
        .target(
            name: "ScreenRecorderPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/ScreenRecorderPlugin"),
        .testTarget(
            name: "ScreenRecorderPluginTests",
            dependencies: ["ScreenRecorderPlugin"],
            path: "ios/Tests/ScreenRecorderPluginTests")
    ]
)
