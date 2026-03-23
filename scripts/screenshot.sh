#!/usr/bin/env bash
# Claude Code Screenshot Tool — Cross-platform
# Supports: macOS, Linux X11, Linux Wayland, WSL2, Windows (Git Bash/MSYS2)
# Usage: screenshot.sh [full|region|monitor [N]] [delay_seconds]
#   full            → full screen (all monitors combined), 2s delay
#   region          → interactive click-and-drag selection
#   monitor         → list available monitors
#   monitor N       → capture monitor N (1-based index)
#   full 5          → full screen with custom delay

MODE="${1:-full}"
MONITOR_NUM=""
DELAY="2"

case "$MODE" in
    region)  ;;
    monitor) MONITOR_NUM="${2:-}"; DELAY="${3:-0}" ;;
    full)    DELAY="${2:-2}" ;;
    *)       DELAY="${2:-2}" ;;
esac

mkdir -p /tmp/claude-screenshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILE="/tmp/claude-screenshots/screenshot_${TIMESTAMP}.png"

# ── OS Detection ──────────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "${OS:-}" == "Windows_NT" ]]; then
        echo "windows"
    elif [[ "$OSTYPE" == "linux"* ]]; then
        [[ -n "${WAYLAND_DISPLAY:-}" ]] && echo "linux-wayland" || echo "linux-x11"
    else
        echo "unknown"
    fi
}

# ── macOS ─────────────────────────────────────────────────────────────────────
screenshot_macos() {
    case "$MODE" in
        region)
            echo "Draw a selection on screen. Press Space to select a window, Esc to cancel." >&2
            screencapture -i -t png "$FILE"
            ;;
        monitor)
            if [[ -z "$MONITOR_NUM" ]]; then
                echo "Available displays (use /screenshot monitor N):" >&2
                system_profiler SPDisplaysDataType 2>/dev/null \
                    | awk '/Resolution:/{res=$0} /Display Type:|^\s{4}[A-Z]/{name=$0} res && name{
                        gsub(/^[[:space:]]+|:[[:space:]]*$/,"",name)
                        gsub(/.*Resolution: /,"",res)
                        print ++n". "name" — "res; res=""; name=""
                    }' >&2 \
                    || echo "  (Could not list displays — try /screenshot monitor 1, 2, ...)" >&2
                exit 0
            fi
            echo "Capturing monitor ${MONITOR_NUM} in ${DELAY}s..." >&2
            sleep "$DELAY"
            screencapture -D "$MONITOR_NUM" -x -t png "$FILE"
            ;;
        *)  # full
            echo "Taking screenshot in ${DELAY}s... Switch to the window you want to capture." >&2
            sleep "$DELAY"
            screencapture -x -t png "$FILE"
            ;;
    esac
}

# ── Linux X11 ─────────────────────────────────────────────────────────────────
list_monitors_x11() {
    echo "Available monitors (use /screenshot monitor N):" >&2
    xrandr --query 2>/dev/null | awk '/ connected /{
        match($0, /[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/)
        if (RSTART) print ++n". "$1" — "substr($0,RSTART,RLENGTH)
    }' >&2 || echo "  (xrandr not available)" >&2
    exit 0
}

capture_monitor_x11() {
    local N="$1"
    local GEOMETRY
    GEOMETRY=$(xrandr --query 2>/dev/null | awk '/ connected /{
        match($0, /[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/)
        if (RSTART) print ++n" "substr($0,RSTART,RLENGTH)
    }' | awk -v n="$N" '$1==n{print $2}')

    if [[ -z "$GEOMETRY" ]]; then
        echo "ERROR: Monitor $N not found. Run /screenshot monitor to list available monitors." >&2
        exit 1
    fi

    local W H X Y
    W=$(echo "$GEOMETRY" | sed 's/x.*//')
    H=$(echo "$GEOMETRY" | sed 's/.*x//;s/+.*//')
    X=$(echo "$GEOMETRY" | cut -d+ -f2)
    Y=$(echo "$GEOMETRY" | cut -d+ -f3)

    echo "Capturing monitor $N (${W}x${H}+${X}+${Y}) in ${DELAY}s..." >&2
    sleep "$DELAY"

    if command -v scrot &>/dev/null; then
        scrot -a "${X},${Y},${W},${H}" "$FILE"
    elif command -v import &>/dev/null; then
        import -window root -crop "${W}x${H}+${X}+${Y}" "$FILE"
    else
        echo "ERROR: Install scrot or imagemagick for monitor capture" >&2
        exit 1
    fi
}

screenshot_linux_x11() {
    case "$MODE" in
        region)
            echo "Click and drag to select a region..." >&2
            if command -v flameshot &>/dev/null; then
                flameshot gui -p "$FILE"
            elif command -v scrot &>/dev/null; then
                scrot -s "$FILE" 2>/dev/null
            elif command -v import &>/dev/null; then
                import "$FILE" 2>/dev/null
            elif command -v gnome-screenshot &>/dev/null; then
                gnome-screenshot -a -f "$FILE"
            elif command -v spectacle &>/dev/null; then
                spectacle -r -b -n -o "$FILE"
            else
                echo "ERROR: Install flameshot, scrot, imagemagick, gnome-screenshot, or spectacle" >&2
                exit 1
            fi
            ;;
        monitor)
            [[ -z "$MONITOR_NUM" ]] && list_monitors_x11
            capture_monitor_x11 "$MONITOR_NUM"
            ;;
        *)  # full
            echo "Taking screenshot in ${DELAY}s... Switch to the window you want to capture." >&2
            sleep "$DELAY"
            if command -v scrot &>/dev/null; then
                scrot "$FILE"
            elif command -v flameshot &>/dev/null; then
                flameshot full -p "$FILE"
            elif command -v import &>/dev/null; then
                import -window root "$FILE"
            elif command -v gnome-screenshot &>/dev/null; then
                gnome-screenshot -f "$FILE"
            elif command -v spectacle &>/dev/null; then
                spectacle -f -b -n -o "$FILE"
            else
                echo "ERROR: Install scrot, flameshot, imagemagick, gnome-screenshot, or spectacle" >&2
                exit 1
            fi
            ;;
    esac
}

# ── Linux Wayland ─────────────────────────────────────────────────────────────
list_monitors_wayland() {
    echo "Available outputs (use /screenshot monitor NAME or N):" >&2
    if command -v wlr-randr &>/dev/null; then
        wlr-randr 2>/dev/null | awk '/^[A-Z]/{print ++n". "$1}' >&2
    elif command -v swaymsg &>/dev/null; then
        swaymsg -t get_outputs 2>/dev/null \
            | python3 -c "import sys,json; [print(f'{i+1}. {o[\"name\"]} — {o.get(\"current_mode\",{}).get(\"width\",\"?\")}x{o.get(\"current_mode\",{}).get(\"height\",\"?\")}') for i,o in enumerate(json.load(sys.stdin))]" 2>/dev/null \
            || echo "  (could not parse outputs)" >&2
    elif command -v hyprctl &>/dev/null; then
        hyprctl monitors 2>/dev/null | grep "^Monitor" | awk '{print ++n". "$2}' >&2
    elif command -v grim &>/dev/null; then
        echo "  (install wlr-randr to list outputs; grim uses output names like eDP-1, HDMI-1)" >&2
    else
        echo "  (install grim + wlr-randr for Wayland monitor capture)" >&2
    fi
    exit 0
}

get_wayland_output_name() {
    local N="$1"
    if command -v wlr-randr &>/dev/null; then
        wlr-randr 2>/dev/null | awk '/^[A-Z]/{++n; if(n=='"$N"') print $1}'
    elif command -v swaymsg &>/dev/null; then
        swaymsg -t get_outputs 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[$N-1]['name'])" 2>/dev/null
    elif command -v hyprctl &>/dev/null; then
        hyprctl monitors 2>/dev/null | grep "^Monitor" | awk "NR==$N{print \$2}"
    else
        echo "$N"  # fallback: treat as raw output name
    fi
}

screenshot_linux_wayland() {
    case "$MODE" in
        region)
            echo "Click and drag to select a region..." >&2
            if command -v grim &>/dev/null && command -v slurp &>/dev/null; then
                grim -g "$(slurp)" "$FILE"
            elif command -v flameshot &>/dev/null; then
                flameshot gui -p "$FILE"
            elif command -v gnome-screenshot &>/dev/null; then
                gnome-screenshot -a -f "$FILE"
            elif command -v spectacle &>/dev/null; then
                spectacle -r -b -n -o "$FILE"
            else
                echo "ERROR: Install grim+slurp (recommended for Wayland) or flameshot" >&2
                exit 1
            fi
            ;;
        monitor)
            [[ -z "$MONITOR_NUM" ]] && list_monitors_wayland
            local OUTPUT_NAME
            # If numeric, resolve to output name; if already a name, use directly
            if [[ "$MONITOR_NUM" =~ ^[0-9]+$ ]]; then
                OUTPUT_NAME=$(get_wayland_output_name "$MONITOR_NUM")
            else
                OUTPUT_NAME="$MONITOR_NUM"
            fi
            if [[ -z "$OUTPUT_NAME" ]]; then
                echo "ERROR: Monitor $MONITOR_NUM not found." >&2
                exit 1
            fi
            echo "Capturing output '${OUTPUT_NAME}' in ${DELAY}s..." >&2
            sleep "$DELAY"
            if command -v grim &>/dev/null; then
                grim -o "$OUTPUT_NAME" "$FILE"
            else
                echo "ERROR: Install grim for Wayland monitor capture" >&2
                exit 1
            fi
            ;;
        *)  # full
            echo "Taking screenshot in ${DELAY}s..." >&2
            sleep "$DELAY"
            if command -v grim &>/dev/null; then
                grim "$FILE"
            elif command -v flameshot &>/dev/null; then
                flameshot full -p "$FILE"
            elif command -v gnome-screenshot &>/dev/null; then
                gnome-screenshot -f "$FILE"
            elif command -v spectacle &>/dev/null; then
                spectacle -f -b -n -o "$FILE"
            else
                echo "ERROR: Install grim for Wayland screenshots" >&2
                exit 1
            fi
            ;;
    esac
}

# ── Windows / WSL2 ────────────────────────────────────────────────────────────
# Uses native Windows screen clipping (ms-screenclip: = Win+Shift+S experience).
# No custom overlay: no flash, correct multi-monitor, native DPI handling.
read -r -d '' PS_REGION_SCRIPT << 'PSEOF'
param([string]$OutputPath)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# Clear clipboard so we can detect when the snip lands
try { [System.Windows.Forms.Clipboard]::Clear() } catch {}

# Launch the native Windows snipping UI (same as Win+Shift+S)
Start-Process "ms-screenclip:"

# Give ScreenClippingHost time to start
Start-Sleep -Milliseconds 600

# Wait for ScreenClippingHost to finish (user selects region or presses Esc)
$proc = Get-Process "ScreenClippingHost" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
    $proc.WaitForExit(60000)
} else {
    # Fallback: poll clipboard for up to 60 seconds
    $deadline = [DateTime]::Now.AddSeconds(60)
    while ([DateTime]::Now -lt $deadline) {
        Start-Sleep -Milliseconds 300
        if ([System.Windows.Forms.Clipboard]::ContainsImage()) { break }
    }
}

# Read image from clipboard and save
$img = $null
try { $img = Get-Clipboard -Format Image -ErrorAction SilentlyContinue } catch {}
if (-not $img) {
    try { $img = [System.Windows.Forms.Clipboard]::GetImage() } catch {}
}

if ($img) {
    $img.Save($OutputPath)
    try { $img.Dispose() } catch {}
    Write-Output "SUCCESS"
} else {
    Write-Output "CANCELLED"
}
PSEOF

_ps_run() {
    local OS_TYPE="$1" PS_CMD="$2"
    shift 2
    $PS_CMD "$@" 2>/dev/null
}

_ps_win_path() {
    local OS_TYPE="$1" LINUX_PATH="$2"
    if [[ "$OS_TYPE" == "wsl" ]]; then
        wslpath -w "$LINUX_PATH"
    else
        cygpath -w "$LINUX_PATH" 2>/dev/null || echo "$LINUX_PATH"
    fi
}

screenshot_windows() {
    local OS_TYPE="$1"
    local PS_CMD WIN_FILE

    local PS_FLAGS="-NoProfile -NonInteractive -ExecutionPolicy Bypass"
    PS_CMD=$([[ "$OS_TYPE" == "wsl" ]] && echo "powershell.exe" || echo "powershell")
    WIN_FILE=$(_ps_win_path "$OS_TYPE" "$FILE")

    case "$MODE" in
        region)
            echo "Windows snipping tool opening — select a region on any monitor, then press Enter or click the checkmark." >&2

            local WIN_TEMP
            WIN_TEMP=$($PS_CMD $PS_FLAGS -Command "[System.IO.Path]::GetTempPath()" 2>/dev/null | tr -d '\r\n')
            local PS_WIN_PATH="${WIN_TEMP}claude_ss_region_${TIMESTAMP}.ps1"
            local PS_LINUX_PATH
            PS_LINUX_PATH=$([[ "$OS_TYPE" == "wsl" ]] && wslpath "$PS_WIN_PATH" || cygpath "$PS_WIN_PATH" 2>/dev/null || echo "$PS_WIN_PATH")

            printf '%s' "$PS_REGION_SCRIPT" > "$PS_LINUX_PATH"
            local RESULT
            RESULT=$($PS_CMD $PS_FLAGS -File "$PS_WIN_PATH" -OutputPath "$WIN_FILE" 2>/dev/null | tr -d '\r')
            rm -f "$PS_LINUX_PATH"

            if [[ "$RESULT" != "SUCCESS" ]]; then
                echo "Screenshot cancelled or failed." >&2
                exit 1
            fi
            ;;
        monitor)
            if [[ -z "$MONITOR_NUM" ]]; then
                echo "Available monitors (use /screenshot monitor N):" >&2
                $PS_CMD $PS_FLAGS -Command "
                    Add-Type -AssemblyName System.Windows.Forms
                    \$screens = [System.Windows.Forms.Screen]::AllScreens
                    for (\$i = 0; \$i -lt \$screens.Length; \$i++) {
                        \$s = \$screens[\$i]
                        \$primary = if (\$s.Primary) { ' (primary)' } else { '' }
                        Write-Host (\$i+1).ToString()'. '\$s.DeviceName' — '\$s.Bounds.Width'x'\$s.Bounds.Height'+'\$s.Bounds.X'+'\$s.Bounds.Y\$primary
                    }
                " 2>/dev/null | tr -d '\r' >&2
                exit 0
            fi
            [[ "$DELAY" -gt 0 ]] && sleep "$DELAY"
            $PS_CMD $PS_FLAGS -Command "
                Add-Type -AssemblyName System.Windows.Forms, System.Drawing
                \$screens = [System.Windows.Forms.Screen]::AllScreens
                \$idx = ${MONITOR_NUM} - 1
                if (\$idx -lt 0 -or \$idx -ge \$screens.Length) {
                    Write-Error 'Monitor ${MONITOR_NUM} not found (only '\$screens.Length' monitors)'
                    exit 1
                }
                \$b = \$screens[\$idx].Bounds
                \$bmp = New-Object System.Drawing.Bitmap \$b.Width, \$b.Height
                \$g = [System.Drawing.Graphics]::FromImage(\$bmp)
                \$g.CopyFromScreen(\$b.Location, [System.Drawing.Point]::Empty, \$b.Size)
                \$g.Dispose()
                \$bmp.Save('${WIN_FILE}')
                \$bmp.Dispose()
            " 2>/dev/null
            ;;
        *)  # full
            echo "Taking screenshot in ${DELAY}s... Switch to the window you want to capture." >&2
            sleep "$DELAY"
            $PS_CMD $PS_FLAGS -Command "
                Add-Type -AssemblyName System.Windows.Forms, System.Drawing
                \$vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
                \$b = [System.Drawing.Rectangle]::new(\$vs.Left, \$vs.Top, \$vs.Width, \$vs.Height)
                \$bmp = New-Object System.Drawing.Bitmap \$b.Width, \$b.Height
                \$g = [System.Drawing.Graphics]::FromImage(\$bmp)
                \$g.CopyFromScreen(\$b.Location, [System.Drawing.Point]::Empty, \$b.Size)
                \$g.Dispose()
                \$bmp.Save('${WIN_FILE}')
                \$bmp.Dispose()
            " 2>/dev/null
            ;;
    esac
}

# ── Main ──────────────────────────────────────────────────────────────────────
OS=$(detect_os)

case "$OS" in
    macos)         screenshot_macos ;;
    linux-x11)     screenshot_linux_x11 ;;
    linux-wayland) screenshot_linux_wayland ;;
    wsl|windows)   screenshot_windows "$OS" ;;
    *)
        echo "ERROR: Unsupported platform: $OS" >&2
        uname -a >&2
        exit 1
        ;;
esac

if [[ -f "$FILE" && -s "$FILE" ]]; then
    ATPATH="@${FILE}"

    # ── Copy @path to clipboard ──────────────────────────────────────────────
    case "$OS" in
        wsl|windows) echo -n "$ATPATH" | clip.exe 2>/dev/null ;;
        macos)       echo -n "$ATPATH" | pbcopy 2>/dev/null ;;
        linux-x11)
            if command -v xclip &>/dev/null; then
                echo -n "$ATPATH" | xclip -selection clipboard 2>/dev/null
            elif command -v xsel &>/dev/null; then
                echo -n "$ATPATH" | xsel --clipboard --input 2>/dev/null
            fi
            ;;
        linux-wayland)
            command -v wl-copy &>/dev/null && echo -n "$ATPATH" | wl-copy 2>/dev/null
            ;;
    esac

    # Leave sentinel so the Stop hook knows to auto-paste on next input ready
    echo "$ATPATH" > /tmp/claude-screenshot-autopaste

    echo "$ATPATH"
else
    echo "ERROR: Screenshot failed or file is empty." >&2
    exit 1
fi
