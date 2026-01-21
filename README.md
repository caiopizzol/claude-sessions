<img width="400" height="60" alt="logo" src="https://github.com/user-attachments/assets/9de72ea7-a466-4fb5-a8f4-1ed5e078ae21" />

[![GitHub release](https://img.shields.io/github/v/release/caiopizzol/claude-sessions)](https://github.com/caiopizzol/claude-sessions/releases)

A macOS utility that monitors all your Claude Code terminal sessions.

## Features

- **Real-time status** — See which sessions are generating, waiting, or idle
- **Instant switching** — Click any session to focus its terminal
- **Context tracking** — Monitor token usage with visual progress rings
- **Lightweight** — Native macOS app, no Electron, no dependencies
- **Open source** — MIT licensed

## Installation

### Download

Download the latest `.dmg` from [Releases](https://github.com/caiopizzol/claude-sessions/releases).

### Build from source

```sh
git clone https://github.com/caiopizzol/claude-sessions.git
cd claude-sessions
./scripts/build-app.sh
open "build/Claude Sessions.app"
```

Requires macOS 13+, Xcode Command Line Tools.

## Setup

On first launch, the app guides you through:

1. **Install jq** — Required for hook scripts (`brew install jq`)
2. **Install hooks** — Enables session tracking in Claude Code
3. **Accessibility permission** — Optional, enables window focusing

## Usage

1. Start Claude Code in one or more terminal windows
2. Click the menubar icon to see your sessions
3. Click a session to focus its terminal

The menubar icon changes to indicate session status (idle, generating, needs attention).

## How it works

Claude Sessions uses Claude Code's hook system to track session state. When you start Claude Code, hook scripts send status updates to the app via a local socket. The app displays this data in real time.

No data leaves your machine.

## Troubleshooting

**App won't open (security warning)**
Right-click the app and select "Open", or allow it in System Settings > Privacy & Security.

**Window focus not working**
Grant Accessibility permission in System Settings > Privacy & Security > Accessibility.

**Sessions not appearing**
Reinstall hooks via the setup wizard. Check that jq is installed (`which jq`).

## Contributing

Issues and pull requests welcome.

```sh
# Development build
cd widget && swift build

# Run tests
swift test
```

## License

MIT
