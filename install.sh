#!/usr/bin/env bash
# claudeshot — install script
# Copies scripts and skill into ~/.claude/ and wires up the UserPromptSubmit hook.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"

# ── Copy files ────────────────────────────────────────────────────────────────
mkdir -p "$HOME/.claude/scripts"
mkdir -p "$HOME/.claude/skills/cshot"

cp "$SCRIPT_DIR/scripts/screenshot.sh"      "$HOME/.claude/scripts/screenshot.sh"
cp "$SCRIPT_DIR/scripts/screenshot-hook.sh" "$HOME/.claude/scripts/screenshot-hook.sh"
chmod +x "$HOME/.claude/scripts/screenshot.sh"
chmod +x "$HOME/.claude/scripts/screenshot-hook.sh"

cp "$SCRIPT_DIR/skills/cshot/SKILL.md" "$HOME/.claude/skills/cshot/SKILL.md"

# ── Patch settings.json ───────────────────────────────────────────────────────
if [[ ! -f "$SETTINGS" ]]; then
    cat > "$SETTINGS" << 'EOF'
{
  "permissions": {
    "allow": []
  },
  "hooks": {}
}
EOF
fi

# Use Python to merge — avoids overwriting existing settings
python3 - "$SETTINGS" << 'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

# Permissions
cfg.setdefault("permissions", {})
cfg["permissions"].setdefault("allow", [])
for rule in [
    "Bash(bash $HOME/.claude/scripts/screenshot.sh*)",
    "Bash(bash $HOME/.claude/scripts/screenshot-hook.sh*)"
]:
    if rule not in cfg["permissions"]["allow"]:
        cfg["permissions"]["allow"].append(rule)

# Hook
cfg.setdefault("hooks", {})
cfg["hooks"].setdefault("UserPromptSubmit", [])
hook_cmd = "bash $HOME/.claude/scripts/screenshot-hook.sh"
already = any(
    any(h.get("command") == hook_cmd for h in entry.get("hooks", []))
    for entry in cfg["hooks"]["UserPromptSubmit"]
)
if not already:
    cfg["hooks"]["UserPromptSubmit"].append({
        "hooks": [{"type": "command", "command": hook_cmd}]
    })

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")

print("settings.json updated.")
PYEOF

echo ""
echo "claudeshot installed successfully."
echo ""
echo "  /cshot              → full screen (2s delay)"
echo "  /cshot region       → interactive region selector"
echo "  /cshot monitor      → list monitors"
echo "  /cshot monitor 2    → capture monitor 2"
echo "  /cshot full 5       → full screen with 5s delay"
echo ""
echo "Restart Claude Code (or open /hooks) to activate the hook."
