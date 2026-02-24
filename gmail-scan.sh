#!/bin/bash
# gmail-scan.sh — Read your Gmail inbox. One command. No arguments needed.
# Uses tab.sh to find the Gmail tab and extract email subjects.
# CC0. macOS only. Zero dependencies beyond tab.sh.
#
# Usage:
#   ./gmail-scan.sh              # Print inbox (up to 30 emails)
#   ./gmail-scan.sh --count      # Just print the count
#
# Output format (one email per line):
#   [UNREAD] sender | subject | date
#   [read]   sender | subject | date
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAB_SH="$SCRIPT_DIR/tab.sh"

COUNT_ONLY=false
[[ "${1:-}" == "--count" ]] && COUNT_ONLY=true

# --- Find Gmail tab ---
GMAIL_TAB=$("$TAB_SH" find "mail.google.com" 2>/dev/null || echo "")

if [[ -z "$GMAIL_TAB" ]]; then
    echo "Gmail is not open in Safari." >&2
    echo "" >&2
    echo "FIX: Open Safari and go to mail.google.com" >&2
    echo "     Log in if needed, then run this again." >&2
    exit 1
fi

if $COUNT_ONLY; then
    RESULT=$(osascript <<JSEOF
tell application "Safari"
    do JavaScript "
    (function() {
        var unread = document.querySelectorAll('tr.zE').length;
        var total = document.querySelectorAll('tr.zA, tr.zE').length;
        return unread + ' unread out of ' + total + ' visible';
    })()
    " in tab ${GMAIL_TAB} of window 1
end tell
JSEOF
    )
    echo "$RESULT"
    exit 0
fi

# --- Read inbox emails ---
RESULT=$(osascript <<JSEOF
tell application "Safari"
    do JavaScript "
    (function() {
        var rows = document.querySelectorAll('tr.zA, tr.zE');
        if (rows.length === 0) return 'NO_EMAILS_VISIBLE';
        var out = [];
        var limit = Math.min(rows.length, 30);
        for (var i = 0; i < limit; i++) {
            var row = rows[i];
            var unread = row.classList.contains('zE');
            var sender = '';
            var subject = '';
            var date = '';
            var senderEl = row.querySelector('.yX .yW');
            if (senderEl) sender = senderEl.textContent.trim();
            var subjEl = row.querySelector('.y6');
            if (subjEl) subject = subjEl.textContent.trim();
            if (!subject) {
                var bogEl = row.querySelector('.bog');
                if (bogEl) subject = bogEl.textContent.trim();
            }
            var dateEl = row.querySelector('.xW');
            if (dateEl) date = dateEl.textContent.trim();
            if (!date) {
                var brdEl = row.querySelector('.brd');
                if (brdEl) date = brdEl.textContent.trim();
            }
            var status = unread ? '[UNREAD]' : '[read]  ';
            out.push(status + ' ' + sender + ' | ' + subject + ' | ' + date);
        }
        return out.join('\\\\n');
    })()
    " in tab ${GMAIL_TAB} of window 1
end tell
JSEOF
)

if [[ "$RESULT" == "NO_EMAILS_VISIBLE" ]]; then
    echo "Gmail tab is open but no emails are visible." >&2
    echo "FIX: Make sure you're on the inbox view (not settings or compose)." >&2
    exit 1
fi

echo "$RESULT"
