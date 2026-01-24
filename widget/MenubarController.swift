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

    override init() {
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.dotted", accessibilityDescription: "Claude Sessions")
            button.image?.isTemplate = true
            // Right-click for context menu
            button.sendAction(on: [.rightMouseUp])
            button.action = #selector(showContextMenu)
            button.target = self
        }
    }

    @objc private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Claude Sessions", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
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
        statusItem = nil
    }
}
