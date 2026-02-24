#!/bin/bash
# scrape.sh — Extract conversation text from claude.ai in Safari.
# Zero dependencies. macOS only. CC0.
#
# Usage: ./scrape.sh [--refresh] [--raw] [--tab N]
#   --refresh   Force page reload before scraping (fixes stale SPA state)
#   --raw       Output text only, no metadata header (for piping)
#   --tab N     Target tab N instead of front document (multi-tab mode)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Parse flags ---
DO_REFRESH=false
RAW_OUTPUT=false
TAB_INDEX=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --refresh) DO_REFRESH=true; shift ;;
        --raw)     RAW_OUTPUT=true; shift ;;
        --tab)     TAB_INDEX="${2:-}"; shift 2 ;;
        *)         shift ;;
    esac
done

# --- Build AppleScript target ---
# "front document" (legacy) or "tab N of window 1" (multi-tab)
if [[ -n "$TAB_INDEX" ]]; then
    AS_TARGET="tab $TAB_INDEX of window 1"
else
    AS_TARGET="front document"
fi

# --- Preflight checks ---

if ! pgrep -xq "Safari"; then
    echo "ERROR: Safari is not running." >&2
    exit 1
fi

URL=$(osascript -e "tell application \"Safari\" to return URL of $AS_TARGET" 2>/dev/null) || {
    echo "ERROR: Could not read Safari tab URL." >&2
    echo "FIX:  Safari → Settings → Advanced → Show features for web developers" >&2
    echo "      Safari → Develop → Allow JavaScript from Apple Events" >&2
    exit 2
}

if [[ -z "$URL" ]]; then
    echo "ERROR: Safari tab has no URL." >&2
    exit 1
fi

if [[ ! "$URL" =~ claude\.ai ]]; then
    echo "ERROR: Target Safari tab is not claude.ai" >&2
    echo "URL: $URL" >&2
    exit 1
fi

# --- Force refresh if requested (fixes stale SPA / phone-to-desktop sync) ---

if $DO_REFRESH; then
    osascript -e "tell application \"Safari\" to do JavaScript \"location.reload()\" in $AS_TARGET" 2>/dev/null || true
    sleep 5
    # Re-read URL after reload (page may redirect)
    URL=$(osascript -e "tell application \"Safari\" to return URL of $AS_TARGET" 2>/dev/null || echo "")
fi

# --- Auto-navigate to most recent conversation if on /new ---

if [[ "$URL" =~ claude\.ai/new ]] || [[ ! "$URL" =~ claude\.ai/chat/ ]]; then
    # Click the most recent conversation in the sidebar
    CLICK_RESULT=$(osascript -e "tell application \"Safari\" to do JavaScript \"
    (function() {
        var links = document.querySelectorAll('a');
        for (var i = 0; i < links.length; i++) {
            if (links[i].href && links[i].href.indexOf('/chat/') !== -1) {
                links[i].click();
                return 'NAVIGATED: ' + links[i].href;
            }
        }
        return 'NO_CHATS';
    })()
    \" in $AS_TARGET" 2>/dev/null || echo "FAIL")

    if [[ "$CLICK_RESULT" == "NO_CHATS" ]]; then
        echo "ERROR: No conversations found in claude.ai sidebar." >&2
        exit 1
    fi

    # Wait for navigation
    sleep 3

    # Re-read URL after navigation
    URL=$(osascript -e "tell application \"Safari\" to return URL of $AS_TARGET" 2>/dev/null || echo "")
fi

# --- Extract metadata ---

# Conversation UUID from URL (handles /chat/{uuid} and /chat/{uuid}?...)
CONV_ID=""
if [[ "$URL" =~ claude\.ai/chat/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) ]]; then
    CONV_ID="${BASH_REMATCH[1]}"
fi

TITLE=$(osascript -e "tell application \"Safari\" to return name of $AS_TARGET" 2>/dev/null || echo "untitled")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Extract conversation text ---

TEXT=$(osascript -e "tell application \"Safari\"
    do JavaScript \"
    (function() {
        var nav = document.querySelector('nav');
        if (!nav) {
            var main = document.querySelector('main') || document.querySelector('[role=\\\"main\\\"]');
            return main ? main.innerText : document.body.innerText;
        }
        var navParent = nav.parentElement;
        while (navParent && navParent.children.length < 2) {
            navParent = navParent.parentElement;
        }
        if (!navParent) return document.body.innerText;
        var navContainer = nav;
        while (navContainer.parentElement !== navParent) {
            navContainer = navContainer.parentElement;
        }
        var parts = [];
        for (var i = 0; i < navParent.children.length; i++) {
            if (navParent.children[i] !== navContainer) {
                var text = navParent.children[i].innerText.trim();
                if (text) parts.push(text);
            }
        }
        return parts.join('\\\\n');
    })()
    \" in $AS_TARGET
end tell" 2>/dev/null) || {
    echo "ERROR: JavaScript execution failed." >&2
    echo "FIX:  Safari → Develop → Allow JavaScript from Apple Events" >&2
    echo "      System Settings → Privacy & Security → Automation → allow Terminal to control Safari" >&2
    exit 2
}

if [[ -z "$TEXT" ]]; then
    echo "ERROR: No text extracted from page." >&2
    exit 1
fi

# --- Output ---

# If --raw flag, output text only (for piping)
if $RAW_OUTPUT; then
    echo "$TEXT"
    exit 0
fi

# Default: output with metadata header
cat <<EOF
# Conversation: $TITLE
# URL: $URL
# ID: $CONV_ID
# Scraped: $TIMESTAMP
# ---

$TEXT
EOF
