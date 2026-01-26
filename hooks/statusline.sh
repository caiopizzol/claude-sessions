#!/bin/bash
# StatusLine hook - receives pre-calculated context data from Claude Code
# This is more accurate than parsing transcripts because it uses Claude's own calculation

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
CWD=$(echo "$INPUT" | jq -r '.cwd // "unknown"')
TTY_NAME=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')
TTY=$([[ -n "$TTY_NAME" && "$TTY_NAME" != "??" ]] && echo "/dev/$TTY_NAME" || echo "unknown")
SOCKET_PATH="$HOME/.claude/widget/state.sock"
LOG_FILE="$HOME/.claude/widget/hooks.log"

# Pre-calculated by Claude Code - guaranteed accurate
CONTEXT_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty')
INPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // empty')

# Skip if no context data yet
[ -z "$CONTEXT_PCT" ] && exit 0

# Convert 0-100 to 0-1 for existing Swift code
CONTEXT_DECIMAL=$(echo "scale=4; $CONTEXT_PCT / 100" | bc 2>/dev/null || echo "0")

echo "[$(date)] StatusLine: session=$SESSION_ID context=${CONTEXT_PCT}% tokens=$INPUT_TOKENS" >> "$LOG_FILE"

MSG=$(jq -n \
  --arg event "status" \
  --arg tty "$TTY" \
  --arg session_id "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg timestamp "$(date +%s)" \
  --argjson context_percentage "$CONTEXT_DECIMAL" \
  --argjson input_tokens "${INPUT_TOKENS:-null}" \
  '{event: $event, tty: $tty, session_id: $session_id, cwd: $cwd, timestamp: ($timestamp | tonumber), context_percentage: $context_percentage, input_tokens: $input_tokens}')

if [[ -S "$SOCKET_PATH" ]]; then
    echo "$MSG" | nc -U "$SOCKET_PATH" -w 1 2>>"$LOG_FILE" || \
    python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect('$SOCKET_PATH'); s.send(sys.stdin.read().encode())" <<< "$MSG" 2>>"$LOG_FILE" || true
fi

exit 0
