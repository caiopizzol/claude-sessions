#!/bin/bash
# Hook: SessionStart - triggered when Claude Code session begins

INPUT=$(cat)
# Get TTY from parent process (stdin is piped, so `tty` won't work)
TTY_NAME=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
if [[ -n "$TTY_NAME" && "$TTY_NAME" != "??" ]]; then
    TTY="/dev/$TTY_NAME"
else
    TTY="unknown"
fi
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
SOCKET_PATH="$HOME/.claude/widget/state.sock"
LOG_FILE="$HOME/.claude/widget/hooks.log"

# Log for debugging
echo "[$(date)] SessionStart: session=$SESSION_ID cwd=$CWD" >> "$LOG_FILE"

# Build JSON properly using jq
MSG=$(jq -n \
  --arg event "start" \
  --arg tty "$TTY" \
  --arg session_id "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg timestamp "$(date +%s)" \
  '{event: $event, tty: $tty, session_id: $session_id, cwd: $cwd, timestamp: ($timestamp | tonumber)}')

# Send state to server if socket exists
if [[ -S "$SOCKET_PATH" ]]; then
    echo "$MSG" | nc -U "$SOCKET_PATH" -w 1 2>>"$LOG_FILE" || \
    python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect('$SOCKET_PATH'); s.send(sys.stdin.read().encode())" <<< "$MSG" 2>>"$LOG_FILE" || true
    echo "[$(date)] Sent: $MSG" >> "$LOG_FILE"
fi

# Update window title
PROJECT=$(basename "$CWD")
printf '\033]0;🟡 Claude: %s\007' "$PROJECT"

exit 0
