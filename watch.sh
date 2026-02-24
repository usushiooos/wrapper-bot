#!/bin/bash
# watch.sh — Continuously poll claude.ai in Safari, detect changes, save conversation log.
# Uses tab.sh for tab-by-URL targeting (never touches front document).
# Zero dependencies. macOS only. CC0.
#
# Usage: ./watch.sh [--no-refresh] [interval_seconds]
#   --no-refresh   Skip page reload on each poll (faster but may miss phone messages)
#   Default: refreshes page every poll to catch phone-to-desktop messages
#   Default interval: 15 seconds
# Output: chatsource/{conversation-uuid}.txt (one file per conversation, overwritten with full state)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/chatsource"
TAB_SH="$SCRIPT_DIR/tab.sh"

# --- Parse flags ---
DO_REFRESH=true
INTERVAL=15
for arg in "$@"; do
    case "$arg" in
        --no-refresh) DO_REFRESH=false ;;
        [0-9]*)       INTERVAL="$arg" ;;
    esac
done

LAST_HASH=""
LAST_CONV_ID=""
SNAPSHOT_COUNT=0
STALE_COUNT=0

REFRESH_LABEL="on"
if ! $DO_REFRESH; then REFRESH_LABEL="off"; fi

echo "=== wrapper-bot watch ==="
echo "Polling every ${INTERVAL}s (refresh: $REFRESH_LABEL)"
echo "Tab targeting: by URL (never touches front document)"
echo "Output: $OUTPUT_DIR/"
echo "Press Ctrl+C to stop"
echo "========================="
echo ""

mkdir -p "$OUTPUT_DIR"

while true; do
    # Check Safari is running
    if ! pgrep -xq "Safari"; then
        sleep "$INTERVAL"
        continue
    fi

    # Find Claude tab by URL pattern (never touches front document)
    CLAUDE_TAB=$("$TAB_SH" find "claude.ai/chat" 2>/dev/null || echo "")

    if [[ -z "$CLAUDE_TAB" ]]; then
        # No Claude tab open — skip silently
        sleep "$INTERVAL"
        continue
    fi

    # Get URL from the discovered tab
    URL=$("$TAB_SH" url "$CLAUDE_TAB" 2>/dev/null || echo "")

    # Skip if not claude.ai (shouldn't happen, but defensive)
    if [[ ! "$URL" =~ claude\.ai ]]; then
        sleep "$INTERVAL"
        continue
    fi

    # Force page reload to catch phone-to-desktop messages (SPA doesn't push-update)
    if $DO_REFRESH; then
        "$TAB_SH" reload "$CLAUDE_TAB" 2>/dev/null || true
        sleep 5
    fi

    # Scrape content using tab-targeted mode
    CONTENT=$("$SCRIPT_DIR/scrape.sh" --raw --tab "$CLAUDE_TAB" 2>/dev/null || echo "")

    if [[ -z "$CONTENT" ]]; then
        sleep "$INTERVAL"
        continue
    fi

    # Re-read URL after scrape (may have navigated)
    URL=$("$TAB_SH" url "$CLAUDE_TAB" 2>/dev/null || echo "")

    # Re-extract conversation ID after possible navigation
    CONV_ID=""
    if [[ "$URL" =~ claude\.ai/chat/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) ]]; then
        CONV_ID="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$CONV_ID" ]]; then
        sleep "$INTERVAL"
        continue
    fi

    # Detect conversation switch
    if [[ "$CONV_ID" != "$LAST_CONV_ID" && -n "$LAST_CONV_ID" ]]; then
        echo "[$(date +%H:%M:%S)] Conversation changed: $CONV_ID"
        LAST_HASH=""  # Force re-save on new conversation
    fi

    # Hash to detect changes
    CURRENT_HASH=$(echo "$CONTENT" | shasum -a 256 | cut -d' ' -f1)

    if [[ "$CURRENT_HASH" != "$LAST_HASH" ]]; then
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        TITLE=$("$TAB_SH" title "$CLAUDE_TAB" 2>/dev/null || echo "untitled")
        CONV_FILE="$OUTPUT_DIR/$CONV_ID.txt"

        # Write full conversation state (overwrite — the file IS the conversation)
        cat > "$CONV_FILE" <<SNAPSHOT
# Conversation: $TITLE
# URL: $URL
# ID: $CONV_ID
# Tab: $CLAUDE_TAB
# Last updated: $TIMESTAMP
# ---

$CONTENT
SNAPSHOT

        SNAPSHOT_COUNT=$((SNAPSHOT_COUNT + 1))
        STALE_COUNT=0
        SHORT_TITLE="${TITLE:0:50}"
        echo "[$(date +%H:%M:%S)] #$SNAPSHOT_COUNT updated → $CONV_ID.txt (tab $CLAUDE_TAB: $SHORT_TITLE)"

        LAST_HASH="$CURRENT_HASH"
    else
        STALE_COUNT=$((STALE_COUNT + 1))
    fi

    LAST_CONV_ID="$CONV_ID"
    sleep "$INTERVAL"
done
