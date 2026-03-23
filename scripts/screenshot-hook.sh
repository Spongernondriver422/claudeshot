#!/usr/bin/env bash
# UserPromptSubmit hook — intercepts /cshot commands before Claude sees them.
# Runs the screenshot script, auto-pastes the @path, and silences Claude's response.

INPUT=$(cat)
MSG=$(echo "$INPUT" | jq -r '.prompt // .message // ""' 2>/dev/null)

# Pass through anything that isn't a /cshot command
echo "$MSG" | grep -qE '^\s*/cshot(\s|$)' || exit 0

# Extract arguments (everything after /cshot)
ARGS=$(echo "$MSG" | sed 's|^\s*/cshot[[:space:]]*||')

# Run screenshot (handles screenshot + clipboard + sentinel file)
bash "$HOME/.claude/scripts/screenshot.sh" $ARGS >/dev/null 2>&1

# Auto-paste @path into the input box after it becomes available.
# Since continue:false skips Claude entirely, Stop hook won't fire — handle it here.
TMP=$(mktemp /tmp/cc_autopaste_XXXXXX.sh)
cat > "$TMP" << 'APEOF'
#!/usr/bin/env bash
if grep -qi microsoft /proc/version 2>/dev/null; then
    sleep 0.4
    powershell.exe -NoProfile -NonInteractive -Command \
        "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^v')" \
        2>/dev/null
elif [[ "$(uname)" == "Darwin" ]]; then
    sleep 1.0
    osascript -e 'tell application "System Events" to keystroke "v" using {command down}' 2>/dev/null
elif command -v xdotool &>/dev/null; then
    sleep 0.4
    xdotool key ctrl+v 2>/dev/null
fi
APEOF
chmod +x "$TMP"
nohup bash "$TMP" >/dev/null 2>&1 &

# Block Claude from processing this message — no response generated
echo '{"continue": false}'
