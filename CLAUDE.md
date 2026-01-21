# Claude Sessions

macOS utility app for monitoring Claude Code sessions. Built with SwiftUI + AppKit, no external dependencies.

## Build & Run

```sh
# Development (with hot reload)
swift run

# Release build
swift build -c release

# Build .app bundle
./scripts/build-app.sh

# Build distributable DMG
./scripts/build-dmg.sh
```

## Architecture

- **SwiftUI** for UI components
- **AppKit** for system integration (NSPanel, NSApplication)
- **Swift Concurrency** with actors for thread-safe state
- **Darwin sockets** for Unix domain socket IPC
- **AppleScript** for cross-terminal window management

### Key Patterns

- `actor` for shared mutable state (StateServer)
- `@Observable` / `@ObservableObject` for reactive UI state
- AppDelegate pattern for macOS lifecycle
- Single-file-per-responsibility organization

## Swift Guidelines

### Conciseness

```swift
// Prefer
let name = session.projectName

// Avoid
let name: String = session.projectName
```

```swift
// Prefer computed properties for simple derivations
var isActive: Bool { status != .idle }

// Avoid methods for simple getters
func isActive() -> Bool { status != .idle }
```

### Control Flow

```swift
// Prefer guard for early exits
guard let session = sessions[id] else { return }
// happy path continues unindented

// Avoid nested if-lets
if let session = sessions[id] {
    // deeply nested code
}
```

### Types

```swift
// Prefer structs for data
struct Session: Codable, Identifiable { ... }

// Use classes only when identity/inheritance needed
class AppDelegate: NSObject, NSApplicationDelegate { ... }

// Use actors for shared mutable state
actor StateServer { ... }
```

### Concurrency

```swift
// Prefer async/await
let state = try await fetchState()

// Avoid completion handlers
fetchState { result in ... }
```

### Extensions

```swift
// Organize by protocol conformance
extension Session: Codable {
    // Codable implementation
}

extension Session: Identifiable {
    var id: String { sessionId }
}
```

### Error Handling

```swift
// Prefer try? for recoverable failures
guard let data = try? encoder.encode(state) else { return }

// Use do-catch only when error details matter
do {
    try socket.bind()
} catch {
    print("Socket error: \(error)")
}
```

## Testing

```swift
import XCTest
@testable import ClaudeSessions

final class SessionTests: XCTestCase {
    func testSessionDecoding() throws {
        let json = """
        {"sessionId": "abc", "status": "generating"}
        """
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        XCTAssertEqual(session.sessionId, "abc")
    }
}
```

Run tests:
```sh
swift test
```

## Dependencies

None. Uses only Swift standard library, Foundation, AppKit, SwiftUI, and Network frameworks.
