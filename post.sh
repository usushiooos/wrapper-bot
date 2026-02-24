#!/bin/bash
# post.sh — Send a message to claude.ai via Safari.
# Zero dependencies. macOS only. CC0.
#
# Usage: ./post.sh [--tab N] "Your message here"
#        echo "Your message" | ./post.sh [--tab N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Parse flags and message ---

TAB_INDEX=""
MESSAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tab) TAB_INDEX="${2:-}"; shift 2 ;;
        *)     MESSAGE="${MESSAGE:+$MESSAGE }$1"; shift ;;
    esac
done

# Read from stdin if no message from args
if [[ -z "$MESSAGE" ]] && [[ ! -t 0 ]]; then
    MESSAGE=$(cat)
fi

if [[ -z "$MESSAGE" ]]; then
    echo "Usage: ./post.sh [--tab N] \"Your message here\"" >&2
    echo "       echo \"message\" | ./post.sh [--tab N]" >&2
    exit 1
fi

# --- Build AppleScript target ---
if [[ -n "$TAB_INDEX" ]]; then
    AS_TARGET="tab $TAB_INDEX of window 1"
else
    AS_TARGET="front document"
fi

# --- Preflight ---

if ! pgrep -xq "Safari"; then
    echo "ERROR: Safari is not running." >&2
    exit 1
fi

URL=$(osascript -e "tell application \"Safari\" to return URL of $AS_TARGET" 2>/dev/null || echo "")

if [[ ! "$URL" =~ claude\.ai ]]; then
    echo "ERROR: Target Safari tab is not claude.ai" >&2
    exit 1
fi

# --- Escape message for JavaScript string ---
ESCAPED_MESSAGE=$(printf '%s' "$MESSAGE" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g" | tr '\n' ' ')

# --- Inject text via ProseMirror composition events ---
# ProseMirror ignores synthetic InputEvents and direct DOM writes.
# It DOES respond to composition events (IME simulation):
# 1. compositionstart pauses the DOM observer
# 2. Mutate the DOM directly (set textContent)
# 3. compositionend triggers ProseMirror to read DOM and create a transaction

INJECT_RESULT=$(osascript <<EOF 2>&1
tell application "Safari"
    do JavaScript "
    (function() {
        var msg = '${ESCAPED_MESSAGE}';
        var editor = document.querySelector('.tiptap.ProseMirror');
        if (!editor) return 'ERROR: No ProseMirror editor found';

        editor.focus();

        // Start composition (pauses MutationObserver)
        editor.dispatchEvent(new CompositionEvent('compositionstart', { data: '', bubbles: true }));

        // Mutate DOM directly
        var p = editor.querySelector('p') || editor;
        p.textContent = msg;

        // End composition (ProseMirror reads DOM, creates transaction)
        editor.dispatchEvent(new CompositionEvent('compositionend', { data: msg, bubbles: true }));

        return 'INJECTED';
    })()
    " in $AS_TARGET
end tell
EOF
)

if [[ "$INJECT_RESULT" != "INJECTED" ]]; then
    echo "ERROR: Text injection failed: $INJECT_RESULT" >&2
    exit 1
fi

# --- Wait for ProseMirror to process, then send ---

sleep 1

SEND_RESULT=$(osascript -e "tell application \"Safari\"
    do JavaScript \"
    (function() {
        var sendBtn = document.querySelector('button[aria-label=\\\"Send message\\\"]');
        if (!sendBtn) return 'ERROR: No send button found';
        if (sendBtn.disabled) return 'ERROR: Send button still disabled after text injection';
        sendBtn.click();
        return 'SENT';
    })()
    \" in $AS_TARGET
end tell" 2>&1)

if [[ "$SEND_RESULT" != "SENT" ]]; then
    echo "$SEND_RESULT" >&2
    exit 1
fi

echo "SENT: ${MESSAGE:0:80}"
