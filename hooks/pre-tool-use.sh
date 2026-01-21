#!/bin/bash
# Hook: PreToolUse - triggered when Claude is about to use a tool
# Detects AskUserQuestion to show "asking" state

INPUT=$(cat)
TTY_NAME=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
if [[ -n "$TTY_NAME" && "$TTY_NAME" != "??" ]]; then
    TTY="/dev/$TTY_NAME"
else
    TTY="unknown"
fi
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
SOCKET_PATH="$HOME/.claude/widget/state.sock"
LOG_FILE="$HOME/.claude/widget/hooks.log"

echo "[$(date)] PreToolUse: session=$SESSION_ID tool=$TOOL_NAME" >> "$LOG_FILE"

# Determine event type based on tool
if [[ "$TOOL_NAME" == "AskUserQuestion" ]]; then
    EVENT="asking"
    EMOJI="🟡"
else
    EVENT="running"
    EMOJI="🟢"
fi

MSG=$(jq -n \
  --arg event "$EVENT" \
  --arg tty "$TTY" \
  --arg session_id "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg timestamp "$(date +%s)" \
  --arg tool_name "$TOOL_NAME" \
  '{event: $event, tty: $tty, session_id: $session_id, cwd: $cwd, timestamp: ($timestamp | tonumber), tool_name: $tool_name}')

if [[ -S "$SOCKET_PATH" ]]; then
    echo "$MSG" | nc -U "$SOCKET_PATH" -w 1 2>>"$LOG_FILE" || \
    python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect('$SOCKET_PATH'); s.send(sys.stdin.read().encode())" <<< "$MSG" 2>>"$LOG_FILE" || true
fi

PROJECT=$(basename "$CWD")
printf '\033]0;%s Claude: %s\007' "$EMOJI" "$PROJECT"

exit 0
