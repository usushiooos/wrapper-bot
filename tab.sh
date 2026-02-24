#!/bin/bash
# tab.sh — Safari tab discovery + targeting utility.
# Targets tabs by index (tab N of window 1) instead of front document.
# Zero dependencies. macOS only. CC0.
#
# Usage:
#   tab.sh list                     # Print all tabs: index|URL|title
#   tab.sh find "mail.google.com"   # Return index of first tab matching URL pattern
#   tab.sh url <index>              # Return URL of tab N
#   tab.sh title <index>            # Return title of tab N
#   tab.sh js <index> "code"        # Execute JavaScript in tab N
#   tab.sh reload <index>           # Reload tab N
set -euo pipefail

# --- Helpers ---

die() {
    echo "ERROR: $1" >&2
    exit "${2:-1}"
}

require_safari() {
    pgrep -xq "Safari" || die "Safari is not running."
}

require_index() {
    [[ -n "${1:-}" ]] || die "Tab index required."
    [[ "$1" =~ ^[0-9]+$ ]] || die "Tab index must be a number, got: $1"
}

# --- Commands ---

cmd_list() {
    require_safari
    osascript <<'EOF'
tell application "Safari"
    if (count of windows) = 0 then return ""
    set w to window 1
    set tabCount to count of tabs of w
    set output to ""
    repeat with i from 1 to tabCount
        set t to tab i of w
        set tabURL to URL of t
        set tabName to name of t
        if i > 1 then set output to output & linefeed
        set output to output & i & "|" & tabURL & "|" & tabName
    end repeat
    return output
end tell
EOF
}

cmd_find() {
    local pattern="${1:-}"
    [[ -n "$pattern" ]] || die "URL pattern required. Usage: tab.sh find \"pattern\""
    require_safari
    local result
    result=$(osascript -e "
tell application \"Safari\"
    if (count of windows) = 0 then return \"\"
    set w to window 1
    set tabCount to count of tabs of w
    repeat with i from 1 to tabCount
        set tabURL to URL of tab i of w
        if tabURL contains \"$pattern\" then return i
    end repeat
    return \"\"
end tell
" 2>/dev/null || echo "")
    if [[ -z "$result" ]]; then
        return 1
    fi
    echo "$result"
}

cmd_url() {
    require_index "${1:-}"
    require_safari
    osascript -e "tell application \"Safari\" to return URL of tab $1 of window 1" 2>/dev/null || die "Could not read URL of tab $1"
}

cmd_title() {
    require_index "${1:-}"
    require_safari
    osascript -e "tell application \"Safari\" to return name of tab $1 of window 1" 2>/dev/null || die "Could not read title of tab $1"
}

cmd_js() {
    require_index "${1:-}"
    local index="$1"
    local code="${2:-}"
    [[ -n "$code" ]] || die "JavaScript code required. Usage: tab.sh js <index> \"code\""
    require_safari
    osascript -e "tell application \"Safari\" to do JavaScript \"$code\" in tab $index of window 1" 2>/dev/null
}

cmd_reload() {
    require_index "${1:-}"
    require_safari
    osascript -e "tell application \"Safari\" to do JavaScript \"location.reload()\" in tab $1 of window 1" 2>/dev/null || true
}

# --- Dispatch ---

CMD="${1:-}"
shift || true

case "$CMD" in
    list)   cmd_list ;;
    find)   cmd_find "$@" ;;
    url)    cmd_url "$@" ;;
    title)  cmd_title "$@" ;;
    js)     cmd_js "$@" ;;
    reload) cmd_reload "$@" ;;
    "")
        echo "Usage: tab.sh <command> [args]" >&2
        echo "" >&2
        echo "Commands:" >&2
        echo "  list                  Print all tabs: index|URL|title" >&2
        echo "  find \"pattern\"        Return index of first tab matching URL pattern" >&2
        echo "  url <index>           Return URL of tab N" >&2
        echo "  title <index>         Return title of tab N" >&2
        echo "  js <index> \"code\"     Execute JavaScript in tab N" >&2
        echo "  reload <index>        Reload tab N" >&2
        exit 1
        ;;
    *)
        die "Unknown command: $CMD"
        ;;
esac
