#!/bin/bash
# gmail-compose.sh — Send an email via Gmail tab in Safari.
# Uses tab.sh for tab-by-URL targeting. Zero dependencies. macOS only. CC0.
#
# Usage: ./wrapper-bot/gmail-compose.sh --to "addr" --subject "subj" --body "msg"
#
# Prerequisites:
#   - Safari tab open to mail.google.com (logged in)
#   - JavaScript from Apple Events enabled
#
# How it works:
#   Steps 1-5 use JavaScript (fill fields in any tab, background OK).
#   Step 6 fires a full pointer event chain (pointerdown→mousedown→pointerup→mouseup→click)
#   on the Send button. Gmail ignores bare .click() but accepts the full event sequence.
#   Same "Allow JavaScript from Apple Events" permission as everything else.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAB_SH="$SCRIPT_DIR/tab.sh"

# --- Parse flags ---
TO=""
SUBJECT=""
BODY=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --to)      TO="${2:-}"; shift 2 ;;
        --subject) SUBJECT="${2:-}"; shift 2 ;;
        --body)    BODY="${2:-}"; shift 2 ;;
        *)         shift ;;
    esac
done

if [[ -z "$TO" || -z "$SUBJECT" || -z "$BODY" ]]; then
    echo "Usage: gmail-compose.sh --to \"addr\" --subject \"subj\" --body \"msg\"" >&2
    exit 1
fi

# --- Escape for JS ---
js_escape() {
    printf '%s' "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g; s/\"/\\\\\"/g" | tr '\n' ' '
}

ESCAPED_TO=$(js_escape "$TO")
ESCAPED_SUBJECT=$(js_escape "$SUBJECT")
ESCAPED_BODY=$(js_escape "$BODY")

# --- Find Gmail tab ---

GMAIL_TAB=$("$TAB_SH" find "mail.google.com" 2>/dev/null || echo "")

if [[ -z "$GMAIL_TAB" ]]; then
    echo "ERROR: No Gmail tab found in Safari." >&2
    echo "FIX:  Open mail.google.com in a Safari tab and log in." >&2
    exit 1
fi

GMAIL_URL=$("$TAB_SH" url "$GMAIL_TAB" 2>/dev/null || echo "")
echo "Found Gmail tab $GMAIL_TAB: $GMAIL_URL"

AS_TARGET="tab $GMAIL_TAB of window 1"

# --- Step 1: Check for existing compose window and close it ---
osascript -e "tell application \"Safari\" to do JavaScript \"
(function() {
    var existing = document.querySelector('div[aria-label=\\\"Message Body\\\"]');
    if (existing) {
        var discard = document.querySelector('img[aria-label=\\\"Discard draft\\\"]');
        if (!discard) discard = document.querySelector('img[aria-label=\\\"Save & close\\\"]');
        if (discard) discard.click();
    }
    return 'OK';
})()
\" in $AS_TARGET" 2>/dev/null || true
sleep 0.5

# --- Step 2: Click Compose button ---
COMPOSE_RESULT=$(osascript -e "tell application \"Safari\" to do JavaScript \"
(function() {
    var btn = document.querySelector('.T-I.T-I-KE.L3');
    if (!btn) btn = document.querySelector('div[gh=\\\"cm\\\"]');
    if (!btn) btn = document.querySelector('div[aria-label*=\\\"Compose\\\"]');
    if (!btn) {
        var all = document.querySelectorAll('div[role=\\\"button\\\"]');
        for (var i = 0; i < all.length; i++) {
            if (all[i].textContent.trim() === 'Compose') { btn = all[i]; break; }
        }
    }
    if (!btn) return 'ERROR: Compose button not found';
    btn.click();
    return 'COMPOSE_CLICKED';
})()
\" in $AS_TARGET" 2>/dev/null || echo "ERROR: AppleScript failed")

if [[ "$COMPOSE_RESULT" != "COMPOSE_CLICKED" ]]; then
    echo "ERROR: Could not click Compose: $COMPOSE_RESULT" >&2
    exit 1
fi

echo "Compose window opened..."
sleep 2

# --- Step 3: Fill To field ---
TO_RESULT=$(osascript -e "tell application \"Safari\" to do JavaScript \"
(function() {
    var toField = document.querySelector('input[aria-label=\\\"To recipients\\\"]');
    if (!toField) toField = document.querySelector('input[aria-label=\\\"To\\\"]');
    if (!toField) toField = document.querySelector('input[name=\\\"to\\\"]');
    if (!toField) return 'ERROR: To field not found';
    toField.focus();
    toField.value = '$ESCAPED_TO';
    toField.dispatchEvent(new Event('input', { bubbles: true }));
    toField.dispatchEvent(new Event('change', { bubbles: true }));
    // Blur to trigger recipient resolution
    toField.blur();
    return 'TO_FILLED';
})()
\" in $AS_TARGET" 2>/dev/null || echo "ERROR: AppleScript failed")

if [[ "$TO_RESULT" != "TO_FILLED" ]]; then
    echo "ERROR: Could not fill To field: $TO_RESULT" >&2
    exit 1
fi

echo "To: $TO"
sleep 0.5

# --- Step 4: Fill Subject ---
SUBJECT_RESULT=$(osascript -e "tell application \"Safari\" to do JavaScript \"
(function() {
    var subj = document.querySelector('input[name=\\\"subjectbox\\\"]');
    if (!subj) subj = document.querySelector('input[aria-label=\\\"Subject\\\"]');
    if (!subj) return 'ERROR: Subject field not found';
    subj.focus();
    subj.value = '$ESCAPED_SUBJECT';
    subj.dispatchEvent(new Event('input', { bubbles: true }));
    subj.dispatchEvent(new Event('change', { bubbles: true }));
    return 'SUBJECT_FILLED';
})()
\" in $AS_TARGET" 2>/dev/null || echo "ERROR: AppleScript failed")

if [[ "$SUBJECT_RESULT" != "SUBJECT_FILLED" ]]; then
    echo "ERROR: Could not fill Subject: $SUBJECT_RESULT" >&2
    exit 1
fi

echo "Subject: $SUBJECT"
sleep 0.3

# --- Step 5: Fill Body ---
BODY_RESULT=$(osascript -e "tell application \"Safari\" to do JavaScript \"
(function() {
    var body = document.querySelector('div[aria-label=\\\"Message Body\\\"]');
    if (!body) body = document.querySelector('div[role=\\\"textbox\\\"][g_editable=\\\"true\\\"]');
    if (!body) return 'ERROR: Body field not found';
    body.focus();
    body.textContent = '$ESCAPED_BODY';
    body.dispatchEvent(new Event('input', { bubbles: true }));
    return 'BODY_FILLED';
})()
\" in $AS_TARGET" 2>/dev/null || echo "ERROR: AppleScript failed")

if [[ "$BODY_RESULT" != "BODY_FILLED" ]]; then
    echo "ERROR: Could not fill Body: $BODY_RESULT" >&2
    exit 1
fi

echo "Body filled."
sleep 0.5

# --- Step 6: Click Send via full pointer event chain ---
# Gmail ignores bare btn.click(). It requires the full pointer event sequence:
# pointerdown → mousedown → pointerup → mouseup → click
# with geometric properties set. This satisfies Gmail's event handler.

SEND_RESULT=$(osascript -e "tell application \"Safari\" to do JavaScript \"
(function() {
    var btn = document.querySelector('.T-I.J-J5-Ji.aoO.v7.T-I-atl.L3');
    if (!btn) {
        var all = document.querySelectorAll('[data-tooltip]');
        for (var i = 0; i < all.length; i++) {
            var tip = all[i].getAttribute('data-tooltip') || '';
            if (tip.indexOf('Send') === 0) { btn = all[i]; break; }
        }
    }
    if (!btn) return 'ERROR: Send button not found';
    var rect = btn.getBoundingClientRect();
    var x = rect.x + rect.width/2;
    var y = rect.y + rect.height/2;
    ['pointerdown','mousedown','pointerup','mouseup','click'].forEach(function(type) {
        var Cls = type.startsWith('pointer') ? PointerEvent : MouseEvent;
        btn.dispatchEvent(new Cls(type, {
            bubbles: true, cancelable: true, composed: true,
            view: window, detail: 1,
            screenX: x, screenY: y, clientX: x, clientY: y,
            button: 0, buttons: type.includes('down') ? 1 : 0,
            pointerId: 1, pointerType: 'mouse',
            isPrimary: true, width: 1, height: 1
        }));
    });
    return 'SEND_CLICKED';
})()
\" in $AS_TARGET" 2>/dev/null || echo "ERROR: AppleScript failed")

if [[ "$SEND_RESULT" != "SEND_CLICKED" ]]; then
    echo "ERROR: Could not click Send: $SEND_RESULT" >&2
    exit 1
fi

echo "Send clicked..."
sleep 3

# --- Step 7: Verify send ---
# Gmail's compose may linger in DOM briefly after send (transition animation).
# Check twice with a gap. If compose closes OR "Message sent" banner appears, success.
VERIFY_RESULT=$(osascript -e "tell application \"Safari\" to do JavaScript \"
(function() {
    var body = document.querySelector('div[aria-label=\\\"Message Body\\\"]');
    var banner = document.querySelector('span.bAq') || document.body.innerText.indexOf('Message sent') > -1;
    if (!body) return 'COMPOSE_CLOSED';
    if (banner) return 'SENT_BANNER';
    return 'COMPOSE_STILL_OPEN';
})()
\" in $AS_TARGET" 2>/dev/null || echo "UNKNOWN")

if [[ "$VERIFY_RESULT" == "COMPOSE_STILL_OPEN" ]]; then
    # Second check after additional delay
    sleep 2
    VERIFY_RESULT=$(osascript -e "tell application \"Safari\" to do JavaScript \"
(function() {
    var body = document.querySelector('div[aria-label=\\\"Message Body\\\"]');
    return body ? 'COMPOSE_STILL_OPEN' : 'COMPOSE_CLOSED';
})()
\" in $AS_TARGET" 2>/dev/null || echo "UNKNOWN")
fi

if [[ "$VERIFY_RESULT" == "COMPOSE_STILL_OPEN" ]]; then
    echo "WARNING: Compose window may still be open. Email might not have sent." >&2
    echo "SENT (unverified): to=$TO subject=$SUBJECT"
else
    echo "SENT: to=$TO subject=$SUBJECT"
fi
