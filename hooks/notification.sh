#!/bin/bash
# Hook: Notification - triggered when Claude sends notifications
# Detects permission_prompt to show "permission" state

INPUT=$(cat)
TTY_NAME=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
if [[ -n "$TTY_NAME" && "$TTY_NAME" != "??" ]]; then
    TTY="/dev/$TTY_NAME"
else
    TTY="unknown"
fi
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
NOTIFICATION_TYPE=$(echo "$INPUT" | jq -r '.notification_type // "unknown"')
SOCKET_PATH="$HOME/.claude/widget/state.sock"
LOG_FILE="$HOME/.claude/widget/hooks.log"

echo "[$(date)] Notification: session=$SESSION_ID type=$NOTIFICATION_TYPE" >> "$LOG_FILE"

# Only send state update for permission prompts
if [[ "$NOTIFICATION_TYPE" == "permission_prompt" ]]; then
    MSG=$(jq -n \
      --arg event "permission" \
      --arg tty "$TTY" \
      --arg session_id "$SESSION_ID" \
      --arg cwd "$CWD" \
      --arg timestamp "$(date +%s)" \
      '{event: $event, tty: $tty, session_id: $session_id, cwd: $cwd, timestamp: ($timestamp | tonumber)}')

    if [[ -S "$SOCKET_PATH" ]]; then
        echo "$MSG" | nc -U "$SOCKET_PATH" -w 1 2>>"$LOG_FILE" || \
        python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect('$SOCKET_PATH'); s.send(sys.stdin.read().encode())" <<< "$MSG" 2>>"$LOG_FILE" || true
    fi

    PROJECT=$(basename "$CWD")
    printf '\033]0;🟡 Claude: %s\007' "$PROJECT"
fi

exit 0
