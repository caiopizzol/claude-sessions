import AppKit
import Combine
import SwiftUI

@main
struct ClaudeSessionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var menubarController: MenubarController?
    var setupWindow: NSWindow?
    var stateManager: StateManager?
    var setupManager: SetupManager?
    var stateServer: StateServer?
    private var serverTask: Task<Void, Never>?
    private var stateObservation: AnyCancellable?

    func applicationDidFinishLaunching(_: Notification) {
        // Hide from dock
        NSApp.setActivationPolicy(.accessory)

        // Start the embedded state server
        startStateServer()

        // Initialize managers
        stateManager = StateManager()
        setupManager = SetupManager()

        // Check if setup is needed
        if setupManager!.setupComplete {
            showMenubar()
        } else {
            showSetupWizard()
        }
    }

    private func showSetupWizard() {
        let setupView = SetupWizardView(setupManager: setupManager!) { [weak self] in
            self?.setupWindow?.close()
            self?.setupWindow = nil
            self?.showMenubar()
        }
        let hostingView = NSHostingView(rootView: setupView)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.delegate = self

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Center on screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = window.frame
            let x = screenRect.midX - windowRect.width / 2
            let y = screenRect.midY - windowRect.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
        setupWindow = window
    }

    private func showMenubar() {
        guard let stateManager else { return }

        menubarController = MenubarController(stateManager: stateManager)

        // Observe state changes to update menubar icon
        stateObservation = stateManager.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.updateMenubarIcon(for: sessions)
            }
    }

    private func updateMenubarIcon(for sessions: [ClaudeSession]) {
        let state =
            if sessions.isEmpty {
                SessionState.noSessions
            } else if sessions.contains(where: { $0.state == "asking" || $0.state == "permission" }) {
                SessionState.needsAttention
            } else if sessions.contains(where: { $0.state == "generating" || $0.state == "running" }) {
                SessionState.generating
            } else {
                SessionState.idle
            }

        menubarController?.updateStatusIcon(for: state)
    }

    func windowWillClose(_: Notification) {
        // Setup window close does not terminate app (menubar still running)
    }

    func applicationWillTerminate(_: Notification) {
        serverTask?.cancel()
        menubarController?.cleanup()
        Task {
            await stateServer?.stop()
        }
    }

    private func startStateServer() {
        stateServer = StateServer()
        serverTask = Task.detached { [weak self] in
            do {
                try await self?.stateServer?.start()
            } catch {
                print("Failed to start state server: \(error)")
            }
        }
    }
}
