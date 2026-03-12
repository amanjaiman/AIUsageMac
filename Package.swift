// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CursorUsageMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "CursorUsageMenuBar",
            path: "CursorUsageMenuBar",
            exclude: ["Info.plist", "CursorUsageMenuBar.entitlements", "Assets.xcassets"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
