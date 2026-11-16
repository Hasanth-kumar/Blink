// swift-tools-version:5.9
import PackageDescription

// Lets Blink be built with only the Xcode Command Line Tools (see build.sh).
// The same sources are also used by Blink.xcodeproj.
let package = Package(
    name: "Blink",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Blink",
            path: "Blink",
            exclude: [
                "Info.plist",
                "Blink.entitlements",
                "Resources"
            ]
        )
    ]
)
