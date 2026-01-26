import AppKit
import Combine
import Foundation
import SwiftUI

struct ClaudeSession: Identifiable, Codable {
    var id: String { session_id }
    let session_id: String
    let state: String
    let tty: String
    let cwd: String
    let project: String
    var customName: String?
    var terminalTabName: String?
    var windowId: String? // Terminal window identifier
    let last_update: String
    let timestamp: Int
    let context_percentage: Double?
    let input_tokens: Int?
    var memoryMB: Int? // RSS memory in megabytes

    var displayName: String { customName ?? terminalTabName ?? project }

    var memoryDisplay: String? {
        guard let mb = memoryMB else { return nil }
        return "\(mb)MB"
    }

    var memoryColor: Color {
        guard let mb = memoryMB else { return Color.white.opacity(0.4) }
        switch mb {
        case 0 ..< 300: return Color.white.opacity(0.7)
        case 300 ..< 500: return .yellow
        default: return .red
        }
    }

    var stateEmoji: String {
        switch state {
        case "generating", "running": "🟢"
        case "asking", "permission": "🟡"
        case "idle": "🔴"
        case "ready": "⚪"
        default: "⚪"
        }
    }

    var stateDescription: String {
        switch state {
        case "generating": "Generating..."
        case "running": "Running..."
        case "ready": "Ready"
        case "asking": "Needs response"
        case "permission": "Needs permission"
        case "idle": "Idle"
        default: state.capitalized
        }
    }

    var stateColor: Color {
        switch state {
        case "generating", "running": .green
        case "asking", "permission": .yellow
        case "idle": .red
        case "ready": .white
        default: .gray
        }
    }

    var contextRingColor: Color {
        guard let pct = context_percentage else { return Color.white.opacity(0.2) }
        switch pct {
        case 0 ..< 0.6: return Color.white.opacity(0.4)
        case 0.6 ..< 0.8: return .yellow
        default: return .red
        }
    }
}

struct ServerResponse: Codable {
    let sessions: [ClaudeSession]
    let server_time: String
}

actor SessionNameStore {
    private let filePath = NSHomeDirectory() + "/.claude/widget/session-names.json"
    private var names: [String: String]

    init() {
        // Load synchronously at init since filePath is constant
        if let data = FileManager.default.contents(atPath: NSHomeDirectory() + "/.claude/widget/session-names.json"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            names = decoded
        } else {
            names = [:]
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(names) else { return }
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        try? data.write(to: URL(fileURLWithPath: filePath))
    }

    func getName(for sessionId: String) -> String? {
        names[sessionId]
    }

    func setName(_ name: String?, for sessionId: String) {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            names[sessionId] = name
        } else {
            names.removeValue(forKey: sessionId)
        }
        save()
    }

    func getAllNames() -> [String: String] {
        names
    }
}

// MARK: - Window Grouping

struct WindowGroup: Identifiable {
    let id: String // Window identifier from AppleScript
    var customName: String?
    var sessions: [ClaudeSession]

    var displayName: String {
        customName ?? "Window \(id)"
    }

    var isMultiTab: Bool {
        sessions.count > 1
    }
}

actor WindowNameStore {
    private let filePath = NSHomeDirectory() + "/.claude/widget/window-names.json"
    private var names: [String: String]

    init() {
        if let data = FileManager.default.contents(atPath: NSHomeDirectory() + "/.claude/widget/window-names.json"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            names = decoded
        } else {
            names = [:]
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(names) else { return }
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        try? data.write(to: URL(fileURLWithPath: filePath))
    }

    func getName(for windowId: String) -> String? {
        names[windowId]
    }

    func setName(_ name: String?, for windowId: String) {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            names[windowId] = name
        } else {
            names.removeValue(forKey: windowId)
        }
        save()
    }

    func getAllNames() -> [String: String] {
        names
    }
}

/// Terminal tab info returned by AppleScript
struct TerminalTabInfo {
    let tabName: String
    let windowId: String
}

@MainActor
class StateManager: ObservableObject {
    @Published var sessions: [ClaudeSession] = []
    @Published var windowGroups: [WindowGroup] = []
    @Published var isConnected = false
    @Published var lastError: String?

    private var timer: Timer?
    private let serverURL = URL(string: "http://127.0.0.1:19847/state")!
    private let sessionNameStore = SessionNameStore()
    private let windowNameStore = WindowNameStore()
    private var staleCounts: [String: Int] = [:]
    private let staleThreshold = 3 // Remove after 3 consecutive stale detections (~1.5s)

    init() {
        startPolling()
    }

    func startPolling() {
        Task { await fetchState() }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchState()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func fetchState() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: serverURL)
            let response = try JSONDecoder().decode(ServerResponse.self, from: data)

            // Merge with persisted custom names and terminal tab info
            let customNames = await sessionNameStore.getAllNames()
            let tabInfo = getTerminalTabInfo()
            var enrichedSessions = response.sessions
            for i in enrichedSessions.indices {
                enrichedSessions[i].customName = customNames[enrichedSessions[i].session_id]
                if let info = tabInfo?[enrichedSessions[i].tty] {
                    enrichedSessions[i].terminalTabName = info.tabName
                    enrichedSessions[i].windowId = info.windowId
                }
                enrichedSessions[i].memoryMB = getProcessMemory(for: enrichedSessions[i].tty)
            }

            // Detect and remove stale sessions (Terminal.app tabs that no longer exist)
            if let activeTTYs = tabInfo.map({ Set($0.keys) }) {
                for session in enrichedSessions {
                    let sessionId = session.session_id
                    if !session.tty.isEmpty, !activeTTYs.contains(session.tty) {
                        // TTY not found in Terminal.app - increment stale count
                        staleCounts[sessionId, default: 0] += 1
                        if staleCounts[sessionId]! >= staleThreshold {
                            await removeSession(sessionId)
                            staleCounts.removeValue(forKey: sessionId)
                        }
                    } else {
                        // TTY is active - reset stale count
                        staleCounts.removeValue(forKey: sessionId)
                    }
                }
            }

            // Preserve existing order: keep known sessions in place, append new ones at end
            let existingOrder = Dictionary(uniqueKeysWithValues: sessions.enumerated().map { ($1.session_id, $0) })
            sessions = enrichedSessions.sorted { a, b in
                let orderA = existingOrder[a.session_id]
                let orderB = existingOrder[b.session_id]
                switch (orderA, orderB) {
                case let (a?, b?): return a < b // Both known: preserve order
                case (_?, nil): return true // a known, b new: a comes first
                case (nil, _?): return false // a new, b known: b comes first
                case (nil, nil): return a.timestamp < b.timestamp // Both new: by timestamp
                }
            }

            // Build window groups (preserving order)
            let existingGroupOrder = Dictionary(uniqueKeysWithValues: windowGroups.enumerated().map { ($1.id, $0) })
            windowGroups = await buildWindowGroups(from: sessions, existingOrder: existingGroupOrder)

            isConnected = true
            lastError = nil
        } catch {
            isConnected = false
            lastError = error.localizedDescription
            sessions = []
            windowGroups = []
        }
    }

    private func buildWindowGroups(from sessions: [ClaudeSession], existingOrder: [String: Int]) async -> [WindowGroup] {
        let windowNames = await windowNameStore.getAllNames()

        // Group sessions by windowId (preserving session order within each group)
        var groupedByWindow: [String: [ClaudeSession]] = [:]
        var ungroupedSessions: [ClaudeSession] = []

        for session in sessions {
            if let windowId = session.windowId {
                groupedByWindow[windowId, default: []].append(session)
            } else {
                ungroupedSessions.append(session)
            }
        }

        var groups: [WindowGroup] = []

        // Create groups for multi-tab windows
        for (windowId, windowSessions) in groupedByWindow {
            if windowSessions.count > 1 {
                groups.append(WindowGroup(
                    id: windowId,
                    customName: windowNames[windowId],
                    sessions: windowSessions
                ))
            } else {
                ungroupedSessions.append(contentsOf: windowSessions)
            }
        }

        // Add ungrouped sessions as individual "groups"
        for session in ungroupedSessions {
            groups.append(WindowGroup(
                id: "single_\(session.session_id)",
                customName: nil,
                sessions: [session]
            ))
        }

        // Sort: preserve existing order, append new groups at end
        return groups.sorted { a, b in
            let orderA = existingOrder[a.id]
            let orderB = existingOrder[b.id]
            switch (orderA, orderB) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false // Both new: preserve current order
            }
        }
    }

    /// Strips Claude Code status prefixes from tab names
    private func cleanTabName(_ name: String) -> String {
        var cleaned = name.trimmingCharacters(in: .whitespaces)

        // Strip known Claude Code status prefixes (braille spinners, etc.)
        let prefixes = ["⠂", "⠐", "⠈", "⠁", "⠉", "⠘", "⠰", "⠠", "✳"]
        for prefix in prefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                break
            }
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    /// Returns Terminal.app tab info (name + window ID) keyed by TTY, or nil if Terminal.app is not running
    private func getTerminalTabInfo() -> [String: TerminalTabInfo]? {
        // Terminal.app treats each tab as a separate "window" object internally,
        // but tabs that are visually grouped share the same screen position (bounds).
        // We use bounds as the window identifier to correctly group tabs.
        let script = """
        tell application "System Events"
            if not (exists process "Terminal") then return "NOT_RUNNING"
        end tell
        tell application "Terminal"
            set output to ""
            repeat with w in windows
                set winBounds to bounds of w
                set boundsKey to (item 1 of winBounds as text) & "," & (item 2 of winBounds as text)
                repeat with t in tabs of w
                    set output to output & (tty of t) & "\\t" & (custom title of t) & "\\t" & boundsKey & "\\n"
                end repeat
            end repeat
        end tell
        return output
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script),
              let result = appleScript.executeAndReturnError(&error).stringValue
        else {
            return nil
        }

        if result == "NOT_RUNNING" {
            return nil
        }

        var tabInfo: [String: TerminalTabInfo] = [:]
        for line in result.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            if parts.count >= 3 {
                let tty = String(parts[0])
                let tabName = cleanTabName(String(parts[1]))
                let windowId = String(parts[2])
                tabInfo[tty] = TerminalTabInfo(tabName: tabName, windowId: windowId)
            }
        }
        return tabInfo
    }

    func renameSession(_ sessionId: String, to name: String) async {
        await sessionNameStore.setName(name.isEmpty ? nil : name, for: sessionId)

        // Update local state immediately
        if let index = sessions.firstIndex(where: { $0.session_id == sessionId }) {
            sessions[index].customName = name.isEmpty ? nil : name
        }
    }

    func renameWindow(_ windowId: String, to name: String) async {
        await windowNameStore.setName(name.isEmpty ? nil : name, for: windowId)

        // Update local state immediately
        if let index = windowGroups.firstIndex(where: { $0.id == windowId }) {
            windowGroups[index].customName = name.isEmpty ? nil : name
        }
    }

    private func removeSession(_ sessionId: String) async {
        guard let url = URL(string: "http://127.0.0.1:19847/sessions/\(sessionId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Returns RSS memory in MB for the claude process on the given TTY
    private func getProcessMemory(for tty: String) -> Int? {
        guard tty.hasPrefix("/dev/ttys") else { return nil }

        let ttyName = String(tty.dropFirst("/dev/".count))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-t", ttyName, "-o", "rss,comm"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            // Find line with "claude" and extract RSS (in KB)
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("claude") {
                    let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
                    if let rssKB = Int(parts.first ?? "") {
                        return rssKB / 1024 // Convert KB to MB
                    }
                }
            }
        } catch {
            // Silently fail - memory display is optional
        }

        return nil
    }

    func focusSession(_ session: ClaudeSession) {
        guard !session.tty.isEmpty, session.tty.hasPrefix("/dev/") else { return }

        let script = """
        tell application "Terminal"
            if not running then return "not running"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(session.tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        activate
                        return "focused"
                    end if
                end repeat
            end repeat
        end tell
        return "not found"
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if let error {
                print("Terminal.app error: \(error)")
            } else {
                print("Focus result: \(result.stringValue ?? "unknown")")
            }
        }
    }
}
