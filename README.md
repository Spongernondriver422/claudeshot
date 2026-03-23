# claudeshot

A Claude Code skill that lets you capture your screen and drop it straight into your next prompt — silently, with zero friction.

## The problem

Claude Code can read images via `@path` mentions, but getting a screenshot into context is awkward:

- **WSL2 / Windows**: you can't paste an image from clipboard directly into Claude Code's input box — it only accepts text
- **Any platform**: you'd normally need to take a screenshot, find the file, type the path, and prefix it with `@` — every single time

claudeshot eliminates all of that. Type `/cshot`, capture, and the `@path` is already in your next prompt waiting for you.

## How it works

1. You type `/cshot [mode]` and press Enter
2. A `UserPromptSubmit` hook intercepts the command **before Claude sees it** — no response is generated
3. The screenshot is captured and saved to `/tmp/claude-screenshots/`
4. The `@path` is copied to your clipboard **and** auto-pasted into the input box
5. Type your question and send — the image is already in context

## Install

```bash
git clone https://github.com/MarcoGarofalo94/claudeshot.git
cd claudeshot
bash install.sh
```

Then **restart Claude Code** (or open `/hooks`) to activate the hook.

## Usage

```
/cshot                  full screen, 2s delay (time to switch windows)
/cshot region           interactive selection — click and drag any region
/cshot monitor          list available monitors
/cshot monitor 2        capture monitor 2
/cshot full 5           full screen with 5s delay
```

## Platform support

| Platform | Full | Region | Monitor |
|---|---|---|---|
| **macOS** | `screencapture` | `screencapture -i` | `screencapture -D N` |
| **WSL2 / Windows** | PowerShell + WinForms | Native snipping tool (Win+Shift+S) | PowerShell + WinForms |
| **Linux X11** | `scrot` / `flameshot` / `gnome-screenshot` | `scrot -s` / `flameshot gui` | `scrot` + xrandr geometry |
| **Linux Wayland** | `grim` / `flameshot` | `grim` + `slurp` | `grim -o <output>` |

### Dependencies

**macOS** — no dependencies, `screencapture` is built-in.

**WSL2 / Windows** — no dependencies, uses built-in PowerShell.

**Linux X11** — install one of: `scrot`, `flameshot`, `imagemagick`, `gnome-screenshot`, `spectacle`

**Linux Wayland** — install `grim` (required) + `slurp` (for region mode) + `wlr-randr` or `swaymsg` (for monitor listing)

```bash
# Debian/Ubuntu
sudo apt install scrot        # X11
sudo apt install grim slurp   # Wayland

# Arch
sudo pacman -S scrot
sudo pacman -S grim slurp wlr-randr

# macOS / Homebrew — nothing needed
```

## How the hook works (technical)

claudeshot uses two Claude Code primitives:

**Skill** (`~/.claude/skills/cshot/SKILL.md`) — registers the `/cshot` command for autocomplete and argument hints. `disable-model-invocation: true` prevents Claude from generating a response when invoked normally.

**UserPromptSubmit hook** (`~/.claude/scripts/screenshot-hook.sh`) — fires on every prompt submission. If the message matches `/cshot`, it:
- Runs the screenshot script
- Fires a background process that simulates Ctrl+V after 400ms (once the input box is ready)
- Returns `{"continue": false}` to stop Claude from processing the message entirely

This means `/cshot` is completely silent — no text response, no tool calls, nothing in the transcript.

## Settings applied by install.sh

```json
{
  "permissions": {
    "allow": [
      "Bash(bash $HOME/.claude/scripts/screenshot.sh*)",
      "Bash(bash $HOME/.claude/scripts/screenshot-hook.sh*)"
    ]
  },
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "bash $HOME/.claude/scripts/screenshot-hook.sh"
      }]
    }]
  }
}
```

`install.sh` merges these into your existing `~/.claude/settings.json` without overwriting anything else.

## License

MIT
