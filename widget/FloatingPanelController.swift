import AppKit
import Combine
import SwiftUI

@MainActor
class FloatingPanelController: NSObject, NSWindowDelegate, ObservableObject {
    private var panel: NSPanel?
    private let stateManager: StateManager
    private var stateObservation: AnyCancellable?
    private var keyMonitor: Any?

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

    // Keyboard navigation cursor (where arrow keys point)
    @Published var navigationIndex: Int?

    // Focused session (activated with Return)
    @Published var focusedSessionId: String?

    init(stateManager: StateManager) {
        self.stateManager = stateManager
        isCollapsed = UserDefaults.standard.bool(forKey: kPanelCollapsed)
        super.init()

        setupPanel()
        setupStateObservation()
        setupKeyboardMonitor()
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
            styleMask: [.titled, .fullSizeContentView],
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
        panel.becomesKeyOnlyIfNeeded = true

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
        // Observe session changes for attention count updates and selection adjustment
        stateObservation = stateManager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                guard let self else { return }
                // Trigger UI update for attention badge
                objectWillChange.send()

                // Adjust selection if sessions change
                if let index = navigationIndex {
                    if sessions.isEmpty {
                        navigationIndex = nil
                    } else if index >= sessions.count {
                        navigationIndex = sessions.count - 1
                    }
                } else if !sessions.isEmpty, !isCollapsed {
                    // Auto-select first session when expanded
                    navigationIndex = 0
                }
            }
    }

    // MARK: - Keyboard Navigation

    private func setupKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !isCollapsed else { return event }

            switch event.keyCode {
            case 125: // Down arrow
                selectNext()
                return nil
            case 126: // Up arrow
                selectPrevious()
                return nil
            case 38: // J key
                if !event.modifierFlags.contains(.command) {
                    selectNext()
                    return nil
                }
            case 40: // K key
                if !event.modifierFlags.contains(.command) {
                    selectPrevious()
                    return nil
                }
            case 36: // Return
                focusSelected()
                return nil
            case 53: // Escape
                handleEscape()
                return nil
            default:
                break
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func selectNext() {
        let sessions = stateManager.sessions
        guard !sessions.isEmpty else { return }

        if let current = navigationIndex {
            // Stop at edge (no wrap)
            if current < sessions.count - 1 {
                navigationIndex = current + 1
            }
        } else {
            navigationIndex = 0
        }
    }

    private func selectPrevious() {
        let sessions = stateManager.sessions
        guard !sessions.isEmpty else { return }

        if let current = navigationIndex {
            // Stop at edge (no wrap)
            if current > 0 {
                navigationIndex = current - 1
            }
        } else {
            navigationIndex = sessions.count - 1
        }
    }

    private func focusSelected() {
        guard let index = navigationIndex,
              index >= 0,
              index < stateManager.sessions.count else { return }
        let session = stateManager.sessions[index]
        focusedSessionId = session.session_id
        stateManager.focusSession(session)
    }

    private func handleEscape() {
        if navigationIndex != nil {
            navigationIndex = nil
        } else {
            toggleCollapsed()
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
        removeKeyboardMonitor()
        panel?.close()
        panel = nil
    }
}
