#!/bin/bash
# preflight.sh — Verify macOS prerequisites for wrapper-bot.
# Run once before first use. CC0.
#
# Usage: ./wrapper-bot/preflight.sh [--gmail]
#   --gmail   Also check Gmail tab prerequisites
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAB_SH="$SCRIPT_DIR/tab.sh"

CHECK_GMAIL=false
for arg in "$@"; do
    case "$arg" in
        --gmail) CHECK_GMAIL=true ;;
    esac
done

PASS=0
FAIL=0

check() {
    local label="$1"
    local result="$2"
    if [[ "$result" == "ok" ]]; then
        echo "  [OK] $label"
        PASS=$((PASS + 1))
    else
        echo "  [!!] $label"
        echo "       $result"
        FAIL=$((FAIL + 1))
    fi
}

echo "wrapper-bot preflight check"
echo "==========================="

# 1. Safari running
if pgrep -xq "Safari"; then
    check "Safari is running" "ok"
else
    check "Safari is running" "FIX: Open Safari"
fi

# 2. osascript can read Safari URL
URL=$(osascript -e 'tell application "Safari" to return URL of front document' 2>/dev/null || echo "FAIL")
if [[ "$URL" != "FAIL" && -n "$URL" ]]; then
    check "osascript can read Safari" "ok"
else
    check "osascript can read Safari" "FIX: System Settings → Privacy & Security → Automation → allow Terminal to control Safari"
fi

# 3. JavaScript execution
JS_TEST=$(osascript -e 'tell application "Safari" to do JavaScript "1+1" in front document' 2>/dev/null || echo "FAIL")
if [[ "$JS_TEST" == "2" || "$JS_TEST" == "2.0" ]]; then
    check "JavaScript from Apple Events" "ok"
else
    check "JavaScript from Apple Events" "FIX: Safari → Develop → Allow JavaScript from Apple Events"
fi

# 4. tab.sh exists and works
if [[ -x "$TAB_SH" ]]; then
    TAB_LIST=$("$TAB_SH" list 2>/dev/null || echo "FAIL")
    if [[ "$TAB_LIST" != "FAIL" && -n "$TAB_LIST" ]]; then
        check "tab.sh utility works" "ok"
    else
        check "tab.sh utility works" "FIX: Ensure Safari has at least one tab open"
    fi
else
    check "tab.sh utility works" "FIX: tab.sh not found or not executable at $TAB_SH"
fi

# 5. Claude tab discoverable by URL
CLAUDE_TAB=$("$TAB_SH" find "claude.ai" 2>/dev/null || echo "")
if [[ -n "$CLAUDE_TAB" ]]; then
    CLAUDE_URL=$("$TAB_SH" url "$CLAUDE_TAB" 2>/dev/null || echo "")
    check "Claude tab found (tab $CLAUDE_TAB)" "ok"
else
    check "Claude tab found" "FIX: Open claude.ai in a Safari tab and log in"
fi

# 6. JS execution in Claude tab (by index, not front document)
if [[ -n "$CLAUDE_TAB" ]]; then
    JS_TAB_TEST=$("$TAB_SH" js "$CLAUDE_TAB" "1+1" 2>/dev/null || echo "FAIL")
    if [[ "$JS_TAB_TEST" == "2" || "$JS_TAB_TEST" == "2.0" ]]; then
        check "JS execution in Claude tab $CLAUDE_TAB" "ok"
    else
        check "JS execution in Claude tab $CLAUDE_TAB" "FIX: Safari → Develop → Allow JavaScript from Apple Events"
    fi
fi

# --- Gmail checks (optional) ---
if $CHECK_GMAIL; then
    echo ""
    echo "Gmail checks"
    echo "----------------------------"

    GMAIL_TAB=$("$TAB_SH" find "mail.google.com" 2>/dev/null || echo "")
    if [[ -n "$GMAIL_TAB" ]]; then
        GMAIL_URL=$("$TAB_SH" url "$GMAIL_TAB" 2>/dev/null || echo "")
        check "Gmail tab found (tab $GMAIL_TAB)" "ok"
    else
        check "Gmail tab found" "FIX: Open mail.google.com in a Safari tab and log in"
    fi

    if [[ -n "$GMAIL_TAB" ]]; then
        # JS execution in Gmail tab
        GMAIL_JS=$("$TAB_SH" js "$GMAIL_TAB" "1+1" 2>/dev/null || echo "FAIL")
        if [[ "$GMAIL_JS" == "2" || "$GMAIL_JS" == "2.0" ]]; then
            check "JS execution in Gmail tab $GMAIL_TAB" "ok"
        else
            check "JS execution in Gmail tab $GMAIL_TAB" "FIX: Safari → Develop → Allow JavaScript from Apple Events"
        fi

        # Compose button selector resolves
        COMPOSE_CHECK=$(osascript -e "tell application \"Safari\" to do JavaScript \"(function(){var b=document.querySelector('.T-I.T-I-KE.L3');if(b)return 'FOUND';var a=document.querySelectorAll('div[role=\\\"button\\\"]');for(var i=0;i<a.length;i++){if(a[i].textContent.trim()==='Compose')return 'FOUND'}return 'NOT_FOUND'})()\" in tab $GMAIL_TAB of window 1" 2>/dev/null || echo "FAIL")
        if [[ "$COMPOSE_CHECK" == "FOUND" ]]; then
            check "Gmail Compose button selector" "ok"
        else
            check "Gmail Compose button selector" "FIX: Ensure Gmail inbox is fully loaded (not in loading state)"
        fi

        # gmail-compose.sh uses a pointer event chain to click Send.
        # No extra permissions needed beyond "Allow JavaScript from Apple Events."
    fi
fi

echo ""
echo "Result: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Fix the above issues, then run this again."
    exit 1
else
    echo "All checks passed."
    if $CHECK_GMAIL; then
        echo "Ready for: scrape.sh, post.sh, watch.sh, gmail-compose.sh"
    else
        echo "Ready for: scrape.sh, post.sh, watch.sh"
        echo "Run with --gmail to also check Gmail prerequisites."
    fi
    exit 0
fi
