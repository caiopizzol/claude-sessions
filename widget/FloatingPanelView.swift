import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var stateManager: StateManager
    @State private var isCloseHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Close button (custom traffic light style)
                Button(action: { NSApp.terminate(nil) }) {
                    Circle()
                        .fill(Color.red.opacity(0.9))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.black.opacity(isCloseHovering ? 0.8 : 0))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isCloseHovering = hovering
                    }
                }

                // Brand logo: mini app icon (squircle with dot)
                AppIconView(size: 16)

                Text("Claude Sessions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.4))

            // Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if stateManager.windowGroups.isEmpty {
                        EmptyStateView(isConnected: stateManager.isConnected)
                    } else {
                        ForEach(stateManager.windowGroups) { group in
                            if group.isMultiTab {
                                // Multi-tab window: show grouped card
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
                                // Single-tab window: show flat card
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

            // Footer
            HStack {
                let count = stateManager.sessions.count
                Text(count == 0 ? "No sessions" : "\(count) session\(count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))
        }
        .frame(width: 280)
        .frame(minHeight: 200, maxHeight: 600)
        .background(Color(white: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Window Group View

struct WindowGroupView: View {
    let group: WindowGroup
    let onSessionTap: (ClaudeSession) -> Void
    let onSessionRename: (String, String) -> Void
    let onWindowRename: (String) -> Void
    @State private var isHoveringHeader = false
    @State private var isEditingName = false
    @State private var editText = ""
    @State private var isCollapsed = false
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Window header
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))

                Image(systemName: "macwindow")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))

                if isEditingName {
                    TextField("Window name", text: $editText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            onWindowRename(editText)
                            isEditingName = false
                        }
                        .onExitCommand {
                            isEditingName = false
                        }
                } else {
                    Text(group.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                Text("\(group.sessions.count) tabs")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(isHoveringHeader ? 0.05 : 0))
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isEditingName else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCollapsed.toggle()
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHoveringHeader = hovering
                }
            }
            .contextMenu {
                Button("Rename Window...") {
                    editText = group.customName ?? ""
                    isEditingName = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
                }
                Button("Reset to Default") {
                    onWindowRename("")
                }
                .disabled(group.customName == nil)
            }

            if !isCollapsed {
                Divider()
                    .background(Color.white.opacity(0.05))

                // Sessions in this window
                VStack(spacing: 0) {
                    ForEach(group.sessions) { session in
                        GroupedSessionCardView(
                            session: session,
                            onTap: { onSessionTap(session) },
                            onRename: { newName in onSessionRename(session.session_id, newName) }
                        )

                        if session.id != group.sessions.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.03))
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Grouped Session Card (inside a window group)

struct GroupedSessionCardView: View {
    let session: ClaudeSession
    let onTap: () -> Void
    let onRename: (String) -> Void
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        Button(action: {
            guard !isEditing else { return }
            onTap()
        }) {
            HStack(spacing: 10) {
                // Status indicator
                ZStack {
                    Circle()
                        .fill(session.stateColor.opacity(0.15))
                        .frame(width: 28, height: 28)

                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    Circle()
                        .trim(from: 0, to: session.context_percentage ?? 0)
                        .stroke(session.contextRingColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 24, height: 24)
                        .rotationEffect(.degrees(-90))

                    Circle()
                        .fill(session.stateColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: session.stateColor.opacity(0.6), radius: 3)
                }

                VStack(alignment: .leading, spacing: 1) {
                    if isEditing {
                        TextField("Session name", text: $editText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                onRename(editText)
                                isEditing = false
                            }
                            .onExitCommand {
                                isEditing = false
                            }
                    } else {
                        Text(session.displayName.isEmpty ? "Unknown" : session.displayName)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Text(session.stateDescription)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                if isHovering {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(isHovering ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename...") {
                editText = session.displayName
                isEditing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFieldFocused = true
                }
            }
            Button("Reset to Default") {
                onRename("")
            }
            .disabled(session.customName == nil)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Session Card (flat, for single-tab windows)

struct SessionCardView: View {
    let session: ClaudeSession
    let onTap: () -> Void
    let onRename: (String) -> Void
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        Button(action: {
            guard !isEditing else { return }
            onTap()
        }) {
            HStack(spacing: 12) {
                // Status indicator with context ring
                ZStack {
                    // Background circle
                    Circle()
                        .fill(session.stateColor.opacity(0.15))
                        .frame(width: 32, height: 32)

                    // Context ring (track)
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 2.5)
                        .frame(width: 28, height: 28)

                    // Context ring (progress)
                    Circle()
                        .trim(from: 0, to: session.context_percentage ?? 0)
                        .stroke(
                            session.contextRingColor,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))

                    // Status dot (centered)
                    Circle()
                        .fill(session.stateColor)
                        .frame(width: 10, height: 10)
                        .shadow(color: session.stateColor.opacity(0.6), radius: 4)

                    // Pulsing animation for generating state
                    if session.state == "generating" {
                        Circle()
                            .stroke(session.stateColor.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                            .scaleEffect(isHovering ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isHovering)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    if isEditing {
                        TextField("Session name", text: $editText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                onRename(editText)
                                isEditing = false
                            }
                            .onExitCommand {
                                isEditing = false
                            }
                    } else {
                        HStack(spacing: 6) {
                            Text(session.displayName.isEmpty ? "Unknown Project" : session.displayName)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .help(session.displayName.isEmpty ? "Unknown Project" : session.displayName)

                            // Context percentage badge (appears on hover)
                            if isHovering, let pct = session.context_percentage {
                                Text("[\(Int(pct * 100))%]")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                    .transition(.opacity)
                            }
                        }
                    }

                    Text(session.stateDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(isHovering ? 0.8 : 0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(isHovering ? 0.4 : 0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(isHovering ? 0.2 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename...") {
                editText = session.displayName
                isEditing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isTextFieldFocused = true
                }
            }
            Button("Reset to Default") {
                onRename("")
            }
            .disabled(session.customName == nil)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onAppear {
            if session.state == "generating" {
                isHovering = true // Start animation
            }
        }
    }
}

struct EmptyStateView: View {
    let isConnected: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isConnected ? "terminal" : "wifi.slash")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.3))

            if isConnected {
                Text("No active sessions")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))

                Text("Start Claude Code in a terminal")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.3))
            } else {
                Text("Server not running")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))

                Text("Restart the app if this persists")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

struct AppIconView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Squircle background with gradient
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 224 / 255, green: 122 / 255, blue: 58 / 255),
                            Color(red: 196 / 255, green: 90 / 255, blue: 26 / 255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // White dot
            Circle()
                .fill(.white)
                .frame(width: size * 0.4, height: size * 0.4)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    FloatingPanelView(stateManager: StateManager())
}
