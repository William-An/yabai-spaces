#!/bin/bash
# =============================================================================
# get-uuids.sh - Display UUIDs and positions of connected monitors
# =============================================================================
# Run this at home and office to get the UUIDs for displays.conf

echo "=== Connected Displays ==="
echo ""

DISPLAYS=$(yabai -m query --displays 2>/dev/null)

if [[ -z "$DISPLAYS" ]]; then
    echo "Error: Cannot query displays. Is yabai running?"
    echo ""
    echo "Start yabai with: yabai --start-service"
    exit 1
fi

NUM_DISPLAYS=$(echo "$DISPLAYS" | jq 'length')

# Detect laptop and external displays
LAPTOP_UUID=""
LAPTOP_INFO=""
EXT_UUIDS=()
EXT_INFOS=()

while IFS= read -r line; do
    uuid=$(echo "$line" | jq -r '.uuid')
    index=$(echo "$line" | jq -r '.index')
    # Convert floats to integers using jq floor
    w=$(echo "$line" | jq -r '.frame.w | floor')
    h=$(echo "$line" | jq -r '.frame.h | floor')
    x=$(echo "$line" | jq -r '.frame.x | floor')
    spaces=$(echo "$line" | jq -r '.spaces | join(", ")')

    # Common MacBook scaled resolutions (as integers)
    is_laptop=false
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
        is_laptop=true
    fi

    if $is_laptop && [[ -z "$LAPTOP_UUID" ]]; then
        LAPTOP_UUID="$uuid"
        LAPTOP_INFO="Index=$index, ${w}x${h}, x=$x, Spaces: $spaces"
        echo "[LAPTOP (built-in)]"
        echo "  Index: $index"
        echo "  UUID:  $uuid"
        echo "  Frame: ${w}x${h} at x=$x"
        echo "  Spaces: $spaces"
        echo ""
    else
        EXT_UUIDS+=("$uuid")
        EXT_INFOS+=("Index=$index, ${w}x${h}, x=$x, Spaces: $spaces")
        echo "[EXTERNAL ${#EXT_UUIDS[@]}]"
        echo "  Index: $index"
        echo "  UUID:  $uuid"
        echo "  Frame: ${w}x${h} at x=$x"
        echo "  Spaces: $spaces"
        echo ""
    fi
done < <(echo "$DISPLAYS" | jq -c 'sort_by(.frame.x) | .[]')

# Get location
LOCATION=${1:-""}
if [[ -z "$LOCATION" ]]; then
    echo "=== Location ==="
    read -p "Enter location [home/office]: " LOCATION
fi
LOCATION_UPPER=$(echo "$LOCATION" | tr '[:lower:]' '[:upper:]')

# If we have external monitors, ask user to identify left/right
LEFT_UUID=""
RIGHT_UUID=""

if [[ ${#EXT_UUIDS[@]} -ge 2 ]]; then
    echo ""
    echo "=== Identify External Monitors ==="
    echo "Which external monitor is your LEFT monitor?"
    echo ""
    for i in "${!EXT_UUIDS[@]}"; do
        echo "  $((i+1))) ${EXT_INFOS[$i]}"
    done
    echo ""
    read -p "Enter number [1-${#EXT_UUIDS[@]}]: " LEFT_CHOICE

    LEFT_IDX=$((LEFT_CHOICE - 1))
    if [[ $LEFT_IDX -ge 0 && $LEFT_IDX -lt ${#EXT_UUIDS[@]} ]]; then
        LEFT_UUID="${EXT_UUIDS[$LEFT_IDX]}"
        # Right is the remaining one
        for i in "${!EXT_UUIDS[@]}"; do
            if [[ $i -ne $LEFT_IDX ]]; then
                RIGHT_UUID="${EXT_UUIDS[$i]}"
                echo ""
                echo "Assigned:"
                echo "  Left:  ${EXT_INFOS[$LEFT_IDX]}"
                echo "  Right: ${EXT_INFOS[$i]} (auto-assigned)"
                break
            fi
        done
    else
        echo "Invalid choice. Using position-based assignment."
        LEFT_UUID="${EXT_UUIDS[0]}"
        RIGHT_UUID="${EXT_UUIDS[1]}"
    fi
elif [[ ${#EXT_UUIDS[@]} -eq 1 ]]; then
    echo ""
    echo "=== Single External Monitor ==="
    read -p "Is this monitor on the LEFT or RIGHT? [l/r]: " SIDE
    if [[ "$SIDE" =~ ^[Ll] ]]; then
        LEFT_UUID="${EXT_UUIDS[0]}"
    else
        RIGHT_UUID="${EXT_UUIDS[0]}"
    fi
fi

# Output config
echo ""
echo "=== Add to displays.conf ==="
echo ""
[[ -n "$LAPTOP_UUID" ]] && echo "LAPTOP_UUID=\"$LAPTOP_UUID\""
[[ -n "$LEFT_UUID" ]] && echo "${LOCATION_UPPER}_LEFT_UUID=\"$LEFT_UUID\""
[[ -n "$RIGHT_UUID" ]] && echo "${LOCATION_UPPER}_RIGHT_UUID=\"$RIGHT_UUID\""
