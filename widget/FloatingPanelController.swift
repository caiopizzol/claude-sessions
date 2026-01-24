import AppKit
import Combine
import SwiftUI

@MainActor
class FloatingPanelController: NSObject, NSWindowDelegate, ObservableObject {
    private var panel: NSPanel?
    private let stateManager: StateManager
    private var stateObservation: AnyCancellable?

    // Persistence keys
    private let kPanelPositionX = "floatingPanelPositionX"
    private let kPanelPositionY = "floatingPanelPositionY"
    private let kPanelCollapsed = "floatingPanelCollapsed"

    // Published state for the SwiftUI view
    @Published var isCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(isCollapsed, forKey: kPanelCollapsed)
            updatePanelSize(animated: true)
        }
    }

    init(stateManager: StateManager) {
        self.stateManager = stateManager
        isCollapsed = UserDefaults.standard.bool(forKey: kPanelCollapsed)
        super.init()

        setupPanel()
        setupStateObservation()
    }

    private func setupPanel() {
        let collapsedWidth: CGFloat = 180
        let expandedWidth: CGFloat = 300
        let collapsedHeight: CGFloat = 40
        let expandedHeight: CGFloat = 400

        let initialWidth = isCollapsed ? collapsedWidth : expandedWidth
        let initialHeight = isCollapsed ? collapsedHeight : expandedHeight

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        guard let panel else { return }

        // Window configuration
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false

        // Visible on all Spaces
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self

        // Hide standard window buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        // SwiftUI content
        let contentView = CollapsiblePanelView(
            stateManager: stateManager,
            controller: self
        )
        panel.contentView = NSHostingView(rootView: contentView)

        // Restore position or default to top-right
        restoreWindowPosition()

        panel.makeKeyAndOrderFront(nil)
    }

    private func setupStateObservation() {
        // Auto-expand when any session needs attention
        stateObservation = stateManager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                let needsAttention = sessions.contains {
                    $0.state == "asking" || $0.state == "permission"
                }
                if needsAttention, self?.isCollapsed == true {
                    self?.isCollapsed = false
                }
            }
    }

    // MARK: - Window Position Persistence

    private func restoreWindowPosition() {
        let x = UserDefaults.standard.double(forKey: kPanelPositionX)
        let y = UserDefaults.standard.double(forKey: kPanelPositionY)

        if x != 0 || y != 0 {
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            // Default: top-right corner
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let panelFrame = panel?.frame ?? .zero
                let defaultX = screenRect.maxX - panelFrame.width - 20
                let defaultY = screenRect.maxY - panelFrame.height - 20
                panel?.setFrameOrigin(NSPoint(x: defaultX, y: defaultY))
            }
        }
    }

    private func saveWindowPosition() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set(origin.x, forKey: kPanelPositionX)
        UserDefaults.standard.set(origin.y, forKey: kPanelPositionY)
    }

    func windowDidMove(_: Notification) {
        saveWindowPosition()
    }

    private func updatePanelSize(animated: Bool) {
        guard let panel else { return }

        let collapsedWidth: CGFloat = 180
        let expandedWidth: CGFloat = 300
        let collapsedHeight: CGFloat = 40
        let expandedHeight: CGFloat = 400

        let newWidth = isCollapsed ? collapsedWidth : expandedWidth
        let newHeight = isCollapsed ? collapsedHeight : expandedHeight

        var frame = panel.frame
        let heightDelta = newHeight - frame.height
        let widthDelta = newWidth - frame.width

        // Anchor to top-right
        frame.size.height = newHeight
        frame.size.width = newWidth
        frame.origin.y -= heightDelta
        frame.origin.x -= widthDelta

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    func toggleCollapsed() {
        isCollapsed.toggle()
    }

    var attentionCount: Int {
        stateManager.sessions.filter {
            $0.state == "asking" || $0.state == "permission"
        }.count
    }

    func cleanup() {
        panel?.close()
        panel = nil
    }
}
