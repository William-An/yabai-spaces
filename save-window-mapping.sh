#!/bin/bash
# =============================================================================
# save-window-mapping.sh - Save window-to-space assignments
# =============================================================================
# Only saves when 3 displays are connected (laptop + left + right).
# This prevents overwriting the mapping when on laptop-only mode.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAPPING_FILE="$SCRIPT_DIR/window-space-mapping.json"
LOG_FILE="$SCRIPT_DIR/save-window-mapping.log"
MAX_LOG_LINES=200

# Logging function - writes to both stdout and log file
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$@"
    echo "[$timestamp] $@" >> "$LOG_FILE"
}

# Rotate log if too large
if [[ -f "$LOG_FILE" ]] && [[ $(wc -l < "$LOG_FILE") -gt $MAX_LOG_LINES ]]; then
    tail -n $((MAX_LOG_LINES / 2)) "$LOG_FILE" > "$LOG_FILE.tmp"
    mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# -----------------------------------------------------------------------------
# File locking to prevent race conditions
# -----------------------------------------------------------------------------
LOCK_DIR="$SCRIPT_DIR/.save-window-mapping.lock"
LOCK_TIMEOUT=10  # seconds

acquire_lock() {
    local start_time=$(date +%s)
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        # Check if lock is stale (older than timeout)
        if [[ -f "$LOCK_DIR/pid" ]]; then
            local lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
            local lock_time=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
            local now=$(date +%s)

            # If lock holder is dead or lock is stale, remove it
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -rf "$LOCK_DIR"
                continue
            elif [[ $((now - lock_time)) -gt $LOCK_TIMEOUT ]]; then
                rm -rf "$LOCK_DIR"
                continue
            fi
        fi

        # Check timeout
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -ge $LOCK_TIMEOUT ]]; then
            log "Failed to acquire lock after ${LOCK_TIMEOUT}s - skipping save"
            exit 0  # Exit gracefully, not an error
        fi

        sleep 0.1
    done

    # Write PID to lock dir
    echo $$ > "$LOCK_DIR/pid"
}

release_lock() {
    rm -rf "$LOCK_DIR"
}

# Acquire lock and ensure cleanup on exit
acquire_lock
trap release_lock EXIT

# Check number of displays
DISPLAYS=$(yabai -m query --displays 2>/dev/null)
if [[ -z "$DISPLAYS" ]]; then
    log "Error: Cannot query yabai displays. Is it running?"
    exit 1
fi

NUM_DISPLAYS=$(echo "$DISPLAYS" | jq 'length')

# Only save mapping when all 3 displays are connected
if [[ $NUM_DISPLAYS -lt 3 ]]; then
    # Don't log skip messages to avoid log spam (runs every 60s)
    exit 0
fi

# Get all windows with their space labels
WINDOWS=$(yabai -m query --windows 2>/dev/null)
SPACES=$(yabai -m query --spaces 2>/dev/null)

if [[ -z "$WINDOWS" || -z "$SPACES" ]]; then
    log "Error: Cannot query yabai. Is it running?"
    exit 1
fi

# Build space index -> label map using jq
SPACE_MAP=$(echo "$SPACES" | jq -r '[.[] | select(.label != null and .label != "") | {(.index | tostring): .label}] | add // {}')

# Build window mappings as JSON array
# Format: [{app, title, space_label}, ...]
MAPPINGS=$(echo "$WINDOWS" | jq --argjson space_map "$SPACE_MAP" '
    [.[] |
        select(.space != null) |
        {
            app: .app,
            title: (.title // ""),
            window_id: .id,
            space_label: ($space_map[.space | tostring] // null)
        } |
        select(.space_label != null)
    ]
')

# Save to file
echo "$MAPPINGS" > "$MAPPING_FILE"

COUNT=$(echo "$MAPPINGS" | jq 'length')
log "Saved $COUNT window mappings"
