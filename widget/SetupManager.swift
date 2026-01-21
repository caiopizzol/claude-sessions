import AppKit
import Foundation

/// Manages first-run setup: hook installation, dependency checks, and permissions
@MainActor
class SetupManager: ObservableObject {
    @Published var hooksInstalled = false
    @Published var jqInstalled = false
    @Published var accessibilityGranted = false
    @Published var setupComplete = false
    @Published var error: String?

    private let claudeSettingsPath = NSHomeDirectory() + "/.claude/settings.json"
    private let hooksDir = NSHomeDirectory() + "/.claude/hooks"
    private var permissionCheckTimer: Timer?

    init() {
        checkStatus()
        startPermissionPolling()
    }

    deinit {
        permissionCheckTimer?.invalidate()
    }

    /// Polls for accessibility permission changes every second
    private func startPermissionPolling() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAccessibilityStatus()
            }
        }
    }

    private func checkAccessibilityStatus() {
        accessibilityGranted = checkAccessibilityPermission()

        // Stop polling once granted
        if accessibilityGranted {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }

    func checkStatus() {
        hooksInstalled = checkHooksInstalled()
        jqInstalled = checkJqInstalled()
        accessibilityGranted = checkAccessibilityPermission()
        // Accessibility is optional - only hooks and jq are required
        setupComplete = hooksInstalled && jqInstalled
    }

    // MARK: - Hook Installation

    func checkHooksInstalled() -> Bool {
        guard FileManager.default.fileExists(atPath: claudeSettingsPath) else {
            return false
        }

        guard let data = FileManager.default.contents(atPath: claudeSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any]
        else {
            return false
        }

        // Check if our hooks are configured
        let requiredHooks = ["SessionStart", "SessionEnd", "PreToolUse", "PostToolUse", "Stop"]
        return requiredHooks.allSatisfy { hooks[$0] != nil }
    }

    func installHooks() {
        do {
            // Create hooks directory
            try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

            // Get hooks from app bundle
            guard let bundlePath = Bundle.main.resourcePath else {
                error = "Could not find app bundle resources"
                return
            }

            let bundleHooksPath = bundlePath + "/hooks"

            // Copy hooks from bundle to ~/.claude/hooks/
            let hookFiles = ["session-start.sh", "prompt-submit.sh", "stop.sh", "session-end.sh"]
            for hookFile in hookFiles {
                let source = bundleHooksPath + "/" + hookFile
                let dest = hooksDir + "/" + hookFile

                if FileManager.default.fileExists(atPath: source) {
                    if FileManager.default.fileExists(atPath: dest) {
                        try FileManager.default.removeItem(atPath: dest)
                    }
                    try FileManager.default.copyItem(atPath: source, toPath: dest)

                    // Make executable
                    var attributes = try FileManager.default.attributesOfItem(atPath: dest)
                    attributes[.posixPermissions] = 0o755
                    try FileManager.default.setAttributes(attributes, ofItemAtPath: dest)
                }
            }

            // Update settings.json
            try updateClaudeSettings()

            hooksInstalled = true
            error = nil
        } catch {
            self.error = "Failed to install hooks: \(error.localizedDescription)"
        }
    }

    private func updateClaudeSettings() throws {
        let settingsDir = (claudeSettingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)

        // Read existing settings or create new
        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: claudeSettingsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        // Create hooks configuration
        let hooks: [String: Any] = [
            "SessionStart": [
                [
                    "matcher": "",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(hooksDir)/session-start.sh"
                        ]
                    ]
                ]
            ],
            "SessionEnd": [
                [
                    "matcher": "",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(hooksDir)/session-end.sh"
                        ]
                    ]
                ]
            ],
            "PreToolUse": [
                [
                    "matcher": "Bash",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(hooksDir)/prompt-submit.sh"
                        ]
                    ]
                ]
            ],
            "PostToolUse": [
                [
                    "matcher": "Bash",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(hooksDir)/stop.sh"
                        ]
                    ]
                ]
            ],
            "Stop": [
                [
                    "matcher": "",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(hooksDir)/stop.sh"
                        ]
                    ]
                ]
            ]
        ]

        settings["hooks"] = hooks

        let jsonData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: URL(fileURLWithPath: claudeSettingsPath))
    }

    // MARK: - jq Dependency

    func checkJqInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["jq"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func openHomebrewInstructions() {
        if let url = URL(string: "https://brew.sh") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() -> Bool {
        // This triggers the permission prompt if not already granted
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptPrompt: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestAccessibilityPermission() {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptPrompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Open System Preferences directly
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // Restart polling if it was stopped
        if permissionCheckTimer == nil {
            startPermissionPolling()
        }
    }

    func skipSetup() {
        setupComplete = true
    }
}
