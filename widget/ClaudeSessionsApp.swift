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
    var floatingWindow: NSWindow?
    var setupWindow: NSWindow?
    var stateManager: StateManager?
    var setupManager: SetupManager?
    var stateServer: StateServer?
    private var serverTask: Task<Void, Never>?

    // Window size constraints (fixed width, flexible height)
    private let fixedWidth: CGFloat = 280
    private let minHeight: CGFloat = 200
    private let maxHeight: CGFloat = 600
    private let defaultHeight: CGFloat = 400

    // UserDefaults key for persistence (only height, width is fixed)
    private let windowHeightKey = "floatingWindowHeight"

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
            showMainPanel()
        } else {
            showSetupWizard()
        }
    }

    private func showSetupWizard() {
        let setupView = SetupWizardView(setupManager: setupManager!) { [weak self] in
            self?.setupWindow?.close()
            self?.setupWindow = nil
            self?.showMainPanel()
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

    private func showMainPanel() {
        let contentView = FloatingPanelView(stateManager: stateManager!)
        let hostingView = NSHostingView(rootView: contentView)

        // Load saved height or use default (width is fixed)
        let savedHeight = UserDefaults.standard.double(forKey: windowHeightKey)
        let height = savedHeight > 0 ? savedHeight : defaultHeight

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: fixedWidth, height: height),
            styleMask: [.nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Set size constraints (fixed width, flexible height)
        window.minSize = NSSize(width: fixedWidth, height: minHeight)
        window.maxSize = NSSize(width: fixedWidth, height: maxHeight)

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

        // Hide native traffic light buttons - we'll add our own close button
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Position in top-right corner
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = window.frame
            let x = screenRect.maxX - windowRect.width - 20
            let y = screenRect.maxY - windowRect.height - 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
        floatingWindow = window
    }

    // Handle window close button - only terminate if main panel is closed
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }

        // Only terminate if the main floating window is closed
        if closingWindow === floatingWindow {
            NSApp.terminate(nil)
        }
    }

    // Save window height when resized (width is fixed)
    func windowDidResize(_ notification: Notification) {
        guard let resizedWindow = notification.object as? NSWindow,
              resizedWindow === floatingWindow else { return }

        UserDefaults.standard.set(resizedWindow.frame.size.height, forKey: windowHeightKey)
    }

    func applicationWillTerminate(_: Notification) {
        // Stop the server when app quits
        serverTask?.cancel()
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
