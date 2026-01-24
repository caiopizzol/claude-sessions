import AppKit
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
    var floatingPanelController: FloatingPanelController?
    var setupWindow: NSWindow?
    var stateManager: StateManager?
    var setupManager: SetupManager?
    var stateServer: StateServer?
    private var serverTask: Task<Void, Never>?

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
            showFloatingPanel()
        } else {
            showSetupWizard()
        }
    }

    private func showSetupWizard() {
        let setupView = SetupWizardView(setupManager: setupManager!) { [weak self] in
            self?.setupWindow?.close()
            self?.setupWindow = nil
            self?.showFloatingPanel()
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

    private func showFloatingPanel() {
        guard let stateManager else { return }
        floatingPanelController = FloatingPanelController(stateManager: stateManager)
    }

    func windowWillClose(_: Notification) {
        // Setup window close does not terminate app (menubar still running)
    }

    func applicationWillTerminate(_: Notification) {
        serverTask?.cancel()
        floatingPanelController?.cleanup()
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
