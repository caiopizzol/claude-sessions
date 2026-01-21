import SwiftUI

struct SetupWizardView: View {
    @ObservedObject var setupManager: SetupManager
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Brand logo: mini app icon (squircle with dot)
                AppIconView(size: 16)

                Text("Setup Required")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.4))

            ScrollView {
                VStack(spacing: 16) {
                    // Welcome message
                    VStack(spacing: 8) {
                        Text("Welcome to Claude Sessions")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)

                        Text("A few things need to be set up before you can use the app.")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Setup steps
                    VStack(spacing: 12) {
                        SetupStepRow(
                            title: "Install jq",
                            description: "Required for hook scripts",
                            isComplete: setupManager.jqInstalled,
                            action: setupManager.jqInstalled ? nil : {
                                setupManager.openHomebrewInstructions()
                            },
                            actionLabel: "Install via Homebrew"
                        )

                        if !setupManager.jqInstalled {
                            HStack {
                                Text("Run: brew install jq")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))

                                Spacer()

                                Button("Check") {
                                    setupManager.checkStatus()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 12)
                        }

                        SetupStepRow(
                            title: "Install Claude Code Hooks",
                            description: "Enables session tracking",
                            isComplete: setupManager.hooksInstalled,
                            action: setupManager.hooksInstalled ? nil : {
                                setupManager.installHooks()
                            },
                            actionLabel: "Install Hooks"
                        )

                        SetupStepRow(
                            title: "Accessibility Permission",
                            description: "Optional - enables window focusing",
                            isComplete: setupManager.accessibilityGranted,
                            action: setupManager.accessibilityGranted ? nil : {
                                setupManager.requestAccessibilityPermission()
                            },
                            actionLabel: "Grant Permission"
                        )

                        if !setupManager.accessibilityGranted {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("After rebuilds, toggle permission OFF then ON in System Settings")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 12)
                        }
                    }

                    if let error = setupManager.error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 16)
                }
                .padding(16)
            }

            // Footer
            HStack {
                Button("Skip for now") {
                    setupManager.skipSetup()
                    onComplete()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))

                Spacer()

                if setupManager.hooksInstalled, setupManager.jqInstalled {
                    Button("Continue") {
                        onComplete()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.3))
        }
        .frame(width: 320, height: 400)
        .background(
            ZStack {
                // Dark base layer for consistent appearance on any background
                Color.black.opacity(0.7)
                // Glass effect on top
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .opacity(0.6)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SetupStepRow: View {
    let title: String
    let description: String
    let isComplete: Bool
    let action: (() -> Void)?
    let actionLabel: String

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: isComplete ? "checkmark" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isComplete ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if let action {
                Button(actionLabel) {
                    action()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.blue)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
