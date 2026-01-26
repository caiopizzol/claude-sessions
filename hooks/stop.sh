#!/bin/bash
# Hook: Stop - triggered when Claude finishes responding

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
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SOCKET_PATH="$HOME/.claude/widget/state.sock"
LOG_FILE="$HOME/.claude/widget/hooks.log"

echo "[$(date)] Stop: session=$SESSION_ID transcript=$TRANSCRIPT_PATH" >> "$LOG_FILE"

# Check if there are pending tool calls in the transcript
# If so, don't set "waiting" - the PreToolUse hook will handle the state
HAS_PENDING_TOOLS="false"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # Look for tool_use in the last assistant message that doesn't have a matching tool_result
    LAST_ASSISTANT=$(tail -50 "$TRANSCRIPT_PATH" 2>/dev/null | grep -E '"type":\s*"assistant"' | tail -1)
    if [ -n "$LAST_ASSISTANT" ]; then
        # Check if this message contains tool_use content
        if echo "$LAST_ASSISTANT" | grep -q '"type":\s*"tool_use"'; then
            HAS_PENDING_TOOLS="true"
            echo "[$(date)] Stop: Pending tool calls detected, not setting waiting" >> "$LOG_FILE"
        fi
    fi
fi

# If there are pending tools, exit early - PreToolUse will set the correct state
if [ "$HAS_PENDING_TOOLS" = "true" ]; then
    exit 0
fi

# Context data now comes from statusLine hook (more accurate)
MSG=$(jq -n \
  --arg event "ready" \
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
printf '\033]0;🟢 Claude: %s\007' "$PROJECT"

exit 0
