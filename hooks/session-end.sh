#!/bin/bash
# Hook: SessionEnd - triggered when session terminates

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

echo "[$(date)] SessionEnd: session=$SESSION_ID" >> "$LOG_FILE"

MSG=$(jq -n \
  --arg event "end" \
  --arg tty "$TTY" \
  --arg session_id "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg timestamp "$(date +%s)" \
  '{event: $event, tty: $tty, session_id: $session_id, cwd: $cwd, timestamp: ($timestamp | tonumber)}')

if [[ -S "$SOCKET_PATH" ]]; then
    echo "$MSG" | nc -U "$SOCKET_PATH" -w 1 2>>"$LOG_FILE" || \
    python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect('$SOCKET_PATH'); s.send(sys.stdin.read().encode())" <<< "$MSG" 2>>"$LOG_FILE" || true
fi

printf '\033]0;Terminal\007'

exit 0
