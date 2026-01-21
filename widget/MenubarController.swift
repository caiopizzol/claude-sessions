import AppKit
import SwiftUI

enum SessionState {
    case idle
    case generating
    case needsAttention
    case noSessions
}

@MainActor
class MenubarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let stateManager: StateManager
    private var eventMonitor: Any?

    init(stateManager: StateManager) {
        self.stateManager = stateManager
        super.init()
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Claude Sessions")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 400)
        popover?.behavior = .applicationDefined
        popover?.animates = true

        let contentView = PopoverContentView(stateManager: stateManager)
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupEventMonitor() {
        // No global monitor - popover stays open until user clicks menubar icon again
    }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hidePopover() {
        popover?.performClose(nil)
    }

    func updateStatusIcon(for state: SessionState) {
        guard let button = statusItem?.button else { return }

        let symbolName = switch state {
        case .noSessions: "circle.dotted"
        case .idle: "circle"
        case .generating: "circle.fill"
        case .needsAttention: "exclamationmark.circle.fill"
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Claude Sessions")
        button.image?.isTemplate = true
    }

    func cleanup() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        statusItem = nil
    }
}

struct PopoverContentView: View {
    @ObservedObject var stateManager: StateManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                AppIconView(size: 16)

                Text("Claude Sessions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Menu {
                    Button("Quit Claude Sessions") {
                        NSApp.terminate(nil)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if stateManager.windowGroups.isEmpty {
                        PopoverEmptyStateView(isConnected: stateManager.isConnected)
                    } else {
                        ForEach(stateManager.windowGroups) { group in
                            if group.isMultiTab {
                                WindowGroupView(
                                    group: group,
                                    onSessionTap: { session in stateManager.focusSession(session) },
                                    onSessionRename: { sessionId, newName in
                                        Task {
                                            await stateManager.renameSession(sessionId, to: newName)
                                        }
                                    },
                                    onWindowRename: { newName in
                                        Task {
                                            await stateManager.renameWindow(group.id, to: newName)
                                        }
                                    }
                                )
                            } else if let session = group.sessions.first {
                                SessionCardView(
                                    session: session,
                                    onTap: { stateManager.focusSession(session) },
                                    onRename: { newName in
                                        Task {
                                            await stateManager.renameSession(session.session_id, to: newName)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(12)
            }

            Divider()

            // Footer
            HStack {
                let count = stateManager.sessions.count
                Text(count == 0 ? "No sessions" : "\(count) session\(count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
        .frame(minHeight: 200, maxHeight: 500)
    }
}

struct PopoverEmptyStateView: View {
    let isConnected: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isConnected ? "terminal" : "wifi.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            if isConnected {
                Text("No active sessions")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                Text("Start Claude Code in a terminal")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            } else {
                Text("Server not running")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
