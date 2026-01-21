// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeSessions",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeSessions",
            path: ".",
            exclude: ["AppIcon.icns"],
            sources: [
                "ClaudeSessionsApp.swift",
                "MenubarController.swift",
                "StateManager.swift",
                "FloatingPanelView.swift",
                "StateServer.swift",
                "SetupManager.swift",
                "SetupWizardView.swift"
            ]
        )
    ]
)
