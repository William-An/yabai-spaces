#!/bin/bash
# =============================================================================
# restore-spaces.sh - Restore spaces to correct displays based on UUID mapping
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/displays.conf"
LOG_FILE="$SCRIPT_DIR/restore-spaces.log"
MAX_LOG_LINES=500

# -----------------------------------------------------------------------------
# File locking to prevent race conditions
# -----------------------------------------------------------------------------
LOCK_DIR="$SCRIPT_DIR/.restore-spaces.lock"
LOCK_TIMEOUT=30  # seconds

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
            echo "Failed to acquire lock after ${LOCK_TIMEOUT}s - another instance may be stuck"
            exit 1
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

log "=========================================="
log "restore-spaces.sh triggered"

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "Error: $CONFIG_FILE not found"
    exit 1
fi
source "$CONFIG_FILE"

# -----------------------------------------------------------------------------
# Relabel spaces sequentially based on config arrays
# -----------------------------------------------------------------------------
# Labels spaces by index order: laptop spaces first, then left, then right.
# This ensures labels are always correct regardless of previous state.

relabel_spaces_sequential() {
    log ""
    log "Relabeling spaces sequentially..."

    # Build combined label array in order
    local all_labels=("${LAPTOP_SPACES[@]}" "${LEFT_SPACES[@]}" "${RIGHT_SPACES[@]}")
    local total_labels=${#all_labels[@]}

    if [[ $total_labels -eq 0 ]]; then
        log "  No space labels defined in config"
        return
    fi

    # Get current spaces sorted by index
    local current_spaces=$(yabai -m query --spaces 2>/dev/null)
    if [[ -z "$current_spaces" ]]; then
        log "  Error: Cannot query spaces"
        return
    fi

    local num_spaces=$(echo "$current_spaces" | jq 'length')
    local relabeled=0

    # Label each space by index (1-based)
    for ((i=0; i<total_labels && i<num_spaces; i++)); do
        local space_index=$((i + 1))
        local expected_label="${all_labels[$i]}"

        # Get current label for this index
        local current_label=$(echo "$current_spaces" | jq -r --argjson idx "$space_index" \
            '.[] | select(.index == $idx) | .label // ""')

        log "  Space $space_index: $current_label → $expected_label"
        if [[ "$current_label" != "$expected_label" ]]; then
            if yabai -m space "$space_index" --label "$expected_label" 2>/dev/null; then
                ((relabeled++))
                log "  Space $space_index: relabeled as $expected_label"
            else
                log "  Space $space_index: failed to label as $expected_label"
            fi
        fi
    done

    if [[ $relabeled -gt 0 ]]; then
        log "  Relabeled $relabeled space(s)"
    else
        log "  All spaces already labeled correctly"
    fi
}

# Relabel spaces before proceeding
relabel_spaces_sequential

# Get current displays
DISPLAYS=$(yabai -m query --displays 2>/dev/null)
if [[ -z "$DISPLAYS" ]]; then
    log "Error: Cannot query yabai displays. Is yabai running?"
    exit 1
fi

NUM_DISPLAYS=$(echo "$DISPLAYS" | jq 'length')
log "Detected $NUM_DISPLAYS display(s)"

# Function to reorder spaces on a display according to label order
# Usage: reorder_spaces DISPLAY1 SPACE1 SPACE2 SPACE3 ...
reorder_spaces() {
    local display_index=$1
    shift
    local desired_order=("$@")

    if [[ ${#desired_order[@]} -lt 2 ]]; then
        return  # Nothing to reorder
    fi

    log "  Reordering on display $display_index: ${desired_order[*]}"

    # Move first space to the first in display by calling move with prev
    # until the return status is not 0
    local first_label="${desired_order[0]}"
    while true; do
        echo "Moving $first_label to prev location"
        yabai -m space "$first_label" --move prev
        if [[ $? -ne 0 ]]; then
            break
        fi
    done

    # Now for rest of the label, just move to prev label location and swap with prev
    for ((i=1; i<${#desired_order[@]}; i++)); do
        local prev_label="${desired_order[$((i-1))]}"
        local curr_label="${desired_order[$i]}"
        echo "Moving $curr_label to prev location"
        yabai -m space "$curr_label" --move "$prev_label" 2>/dev/null
        echo "Swapping $curr_label with $prev_label"
        yabai -m space "$curr_label" --swap "$prev_label" 2>/dev/null
    done
}

# Handle single display case
if [[ $NUM_DISPLAYS -eq 1 ]]; then
    log ""
    log "Single display mode - all spaces will be on this display."
    SINGLE_INDEX=$(echo "$DISPLAYS" | jq -r '.[0].index')

    log ""
    log "Moving all spaces to display $SINGLE_INDEX..."

    ALL_SPACES=("${LAPTOP_SPACES[@]}" "${LEFT_SPACES[@]}" "${RIGHT_SPACES[@]}")
    for space in "${ALL_SPACES[@]}"; do
        yabai -m space "$space" --display "$SINGLE_INDEX" 2>/dev/null
    done

    # Reorder all spaces
    log ""
    log "Reordering spaces..."
    reorder_spaces "$SINGLE_INDEX" "${ALL_SPACES[@]}"

    log "Done."
    exit 0
fi

# Find display indices based on UUID matching
LAPTOP_INDEX=""
LEFT_INDEX=""
RIGHT_INDEX=""
MATCHED_COUNT=0

while IFS= read -r line; do
    uuid=$(echo "$line" | jq -r '.uuid')
    index=$(echo "$line" | jq -r '.index')

    # Check laptop
    if [[ "$uuid" == "$LAPTOP_UUID" ]]; then
        LAPTOP_INDEX="$index"
        log "  Laptop: display $index (UUID matched)"
        ((MATCHED_COUNT++))
    fi

    # Check left external (home or office)
    if [[ "$uuid" == "$HOME_LEFT_UUID" || "$uuid" == "$OFFICE_LEFT_UUID" ]]; then
        LEFT_INDEX="$index"
        log "  Left external: display $index (UUID matched)"
        ((MATCHED_COUNT++))
    fi

    # Check right external (home or office)
    if [[ "$uuid" == "$HOME_RIGHT_UUID" || "$uuid" == "$OFFICE_RIGHT_UUID" ]]; then
        RIGHT_INDEX="$index"
        log "  Right external: display $index (UUID matched)"
        ((MATCHED_COUNT++))
    fi
done < <(echo "$DISPLAYS" | jq -c '.[]')

# Fallback: position-based detection if UUIDs not recognized
USED_FALLBACK=false
if [[ $MATCHED_COUNT -eq 0 ]]; then
    log ""
    log ">>> Unknown monitor setup - no UUIDs matched <<<"
    log "Using position-based fallback (leftmost = left, etc.)"
    log "To add this location, run: $SCRIPT_DIR/get-uuids.sh <location_name>"
    log ""
    USED_FALLBACK=true
elif [[ $MATCHED_COUNT -lt 3 ]]; then
    # Some but not all matched - use fallback for missing ones
    log ">>> Some but not all monitors matched - using position-based fallback <<<"
    USED_FALLBACK=true
fi

if $USED_FALLBACK; then
    # Sort displays by x-coordinate
    SORTED=$(echo "$DISPLAYS" | jq -c 'sort_by(.frame.x)')

    # Detect built-in by common MacBook resolutions (if not already matched)
    if [[ -z "$LAPTOP_INDEX" ]]; then
        for i in $(seq 0 $((NUM_DISPLAYS - 1))); do
            # Convert floats to integers
            w=$(echo "$SORTED" | jq -r ".[$i].frame.w | floor")
            h=$(echo "$SORTED" | jq -r ".[$i].frame.h | floor")
            idx=$(echo "$SORTED" | jq -r ".[$i].index")

            # Common MacBook scaled resolutions
            if [[ ($w -le 1800 && $h -le 1200) ||
                  ($w -eq 1920 && $h -eq 1200) ||
                  ($w -eq 2560 && $h -eq 1600) ||
                  ($w -eq 1512 && $h -eq 982) ||
                  ($w -eq 1728 && $h -eq 1117) ||
                  ($w -eq 1800 && $h -eq 1169) ||
                  ($w -eq 1496 && $h -eq 967) ||
                  ($w -eq 1352 && $h -eq 878) ||
                  ($w -eq 1470 && $h -eq 956) ||
                  ($w -eq 1680 && $h -eq 1050) ||
                  ($w -eq 1440 && $h -eq 900) ]]; then
                LAPTOP_INDEX="$idx"
                log "  Laptop (detected by resolution): display $idx"
                break
            fi
        done
    fi

    # Collect external displays (non-laptop)
    EXT_DISPLAYS=()
    for i in $(seq 0 $((NUM_DISPLAYS - 1))); do
        idx=$(echo "$SORTED" | jq -r ".[$i].index")
        if [[ "$idx" != "$LAPTOP_INDEX" ]]; then
            EXT_DISPLAYS+=("$idx")
        fi
    done

    # Assign external displays by position (leftmost first)
    if [[ ${#EXT_DISPLAYS[@]} -eq 1 ]]; then
        # Only 1 external - assign based on what's missing
        if [[ -z "$LEFT_INDEX" && -z "$RIGHT_INDEX" ]]; then
            # Neither assigned - default to left
            LEFT_INDEX="${EXT_DISPLAYS[0]}"
            log "  Single external (assigned as left): display $LEFT_INDEX"
        elif [[ -z "$LEFT_INDEX" ]]; then
            LEFT_INDEX="${EXT_DISPLAYS[0]}"
            log "  Left external (by position): display $LEFT_INDEX"
        elif [[ -z "$RIGHT_INDEX" ]]; then
            RIGHT_INDEX="${EXT_DISPLAYS[0]}"
            log "  Right external (by position): display $RIGHT_INDEX"
        fi
    elif [[ ${#EXT_DISPLAYS[@]} -ge 2 ]]; then
        if [[ -z "$LEFT_INDEX" ]]; then
            LEFT_INDEX="${EXT_DISPLAYS[0]}"
            log "  Left external (by position): display $LEFT_INDEX"
        fi
        if [[ -z "$RIGHT_INDEX" ]]; then
            RIGHT_INDEX="${EXT_DISPLAYS[1]}"
            log "  Right external (by position): display $RIGHT_INDEX"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Restore windows to their saved spaces
# -----------------------------------------------------------------------------
restore_windows_from_mapping() {
    local mapping_file="$SCRIPT_DIR/window-space-mapping.json"

    if [[ ! -f "$mapping_file" ]]; then
        log "No window mapping file found - skipping window restoration"
        return
    fi

    log ""
    log "Restoring windows to saved spaces..."

    # Get current windows and spaces
    local current_windows=$(yabai -m query --windows 2>/dev/null)
    local current_spaces=$(yabai -m query --spaces 2>/dev/null)
    local saved_mappings=$(cat "$mapping_file" 2>/dev/null)

    if [[ -z "$current_windows" || -z "$current_spaces" || -z "$saved_mappings" ]]; then
        log "  Error: Cannot query windows/spaces or read mappings"
        return
    fi

    # Validate JSON
    if ! echo "$saved_mappings" | jq empty 2>/dev/null; then
        log "  Error: Invalid JSON in mapping file"
        return
    fi

    local moved=0
    local skipped=0

    # Track moved windows using a string (bash 3.x compatible)
    local moved_windows=","

    # Process each saved mapping
    local num_mappings=$(echo "$saved_mappings" | jq 'length')
    for ((i=0; i<num_mappings; i++)); do
        local saved_app=$(echo "$saved_mappings" | jq -r ".[$i].app // empty")
        local saved_title=$(echo "$saved_mappings" | jq -r ".[$i].title // empty")
        local saved_label=$(echo "$saved_mappings" | jq -r ".[$i].space_label // empty")

        [[ -z "$saved_app" || -z "$saved_label" ]] && continue

        local window_id=""

        # 1. Exact match: app + title
        window_id=$(echo "$current_windows" | jq -r --arg app "$saved_app" --arg title "$saved_title" \
            '[.[] | select(.app == $app and .title == $title)] | .[0].id // empty')

        # 2. Partial/substring match
        if [[ -z "$window_id" && -n "$saved_title" ]]; then
            window_id=$(echo "$current_windows" | jq -r --arg app "$saved_app" --arg title "$saved_title" \
                '[.[] | . as $win | select($win.app == $app and (($win.title | tostring | contains($title)) or ($title | contains($win.title | tostring))))] | .[0].id // empty')
        fi

        # 3. Prefix match (first 20 chars)
        if [[ -z "$window_id" && -n "$saved_title" && ${#saved_title} -ge 10 ]]; then
            local title_prefix="${saved_title:0:20}"
            window_id=$(echo "$current_windows" | jq -r --arg app "$saved_app" --arg prefix "$title_prefix" \
                '[.[] | select(.app == $app and (.title | tostring | startswith($prefix)))] | .[0].id // empty')
        fi

        # 4. Fallback: app-only match for windows not yet moved
        if [[ -z "$window_id" ]]; then
            local app_windows=$(echo "$current_windows" | jq -r --arg app "$saved_app" \
                '[.[] | select(.app == $app) | .id] | .[]')

            for wid in $app_windows; do
                # Check if window already moved (bash 3.x compatible)
                if [[ "$moved_windows" != *",$wid,"* ]]; then
                    window_id=$wid
                    break
                fi
            done
        fi

        [[ -z "$window_id" ]] && { ((skipped++)); continue; }

        # Skip if already moved
        [[ "$moved_windows" == *",$window_id,"* ]] && continue

        # Get current space of this window
        local current_space=$(echo "$current_windows" | jq -r --argjson id "$window_id" \
            '.[] | select(.id == $id) | .space')

        # Get target space index from label
        local target_space=$(echo "$current_spaces" | jq -r --arg label "$saved_label" \
            '.[] | select(.label == $label) | .index // empty')

        if [[ -n "$target_space" && "$current_space" != "$target_space" ]]; then
            if yabai -m window "$window_id" --space "$saved_label" 2>/dev/null; then
                local display_title="$saved_title"
                [[ ${#display_title} -gt 40 ]] && display_title="${display_title:0:37}..."
                log "  $saved_app ($display_title) → $saved_label"
                moved_windows="${moved_windows}${window_id},"
                ((moved++))
            else
                ((skipped++))
            fi
        else
            moved_windows="${moved_windows}${window_id},"  # Mark as processed
        fi
    done

    if [[ $moved -gt 0 ]]; then
        log "  Moved $moved window(s), skipped $skipped"
    else
        log "  No windows needed moving"
    fi
}

# Restore windows after space restoration
restore_windows_from_mapping

log ""
if $USED_FALLBACK; then
    log "Space restoration complete (used fallback for some displays)."
else
    log "Space restoration complete."
fi
