// swift-tools-version:5.9
//
// SPM manifest used ONLY to unit-test the pure-logic core (MRUOrder,
// SwitcherStateMachine) with `swift test`. The app itself builds through
// AltTab/AltTab.xcodeproj; the same source files are compiled into both.
//
import PackageDescription

let package = Package(
    name: "AltTabCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "AltTabCore",
            path: "AltTab/AltTab",
            exclude: [
                "AppDelegate.swift",
                "HotkeyManager.swift",
                "WindowModel.swift",
                "WindowCapture.swift",
                "WindowActivator.swift",
                "SwitcherPanel.swift",
                "ThumbnailView.swift",
                "PermissionManager.swift",
                "PreferencesMenu.swift",
                "main.swift",
                "Assets.xcassets",
                "Info.plist",
                "AltTab.entitlements",
            ],
            sources: ["MRUOrder.swift", "SwitcherStateMachine.swift"]
        ),
        .testTarget(
            name: "AltTabCoreTests",
            dependencies: ["AltTabCore"],
            path: "Tests/AltTabCoreTests"
        ),
    ]
)
