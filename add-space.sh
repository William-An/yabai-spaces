#!/bin/bash
# =============================================================================
# add-space.sh - Create a new space on specified monitor
# =============================================================================
# Usage: ./add-space.sh [laptop|left|right]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/displays.conf"
source "$CONFIG_FILE"

TARGET=${1:-left}

# Get displays
DISPLAYS=$(yabai -m query --displays)
NUM_DISPLAYS=$(echo "$DISPLAYS" | jq 'length')

# Try to find displays by UUID first
LAPTOP_INDEX=""
LEFT_INDEX=""
RIGHT_INDEX=""

while IFS= read -r line; do
    uuid=$(echo "$line" | jq -r '.uuid')
    index=$(echo "$line" | jq -r '.index')

    [[ "$uuid" == "$LAPTOP_UUID" ]] && LAPTOP_INDEX="$index"
    [[ "$uuid" == "$HOME_LEFT_UUID" || "$uuid" == "$OFFICE_LEFT_UUID" ]] && LEFT_INDEX="$index"
    [[ "$uuid" == "$HOME_RIGHT_UUID" || "$uuid" == "$OFFICE_RIGHT_UUID" ]] && RIGHT_INDEX="$index"
done < <(echo "$DISPLAYS" | jq -c '.[]')

# Fallback to position-based
if [[ -z "$LEFT_INDEX" || -z "$RIGHT_INDEX" ]]; then
    SORTED=$(echo "$DISPLAYS" | jq -c 'sort_by(.frame.x) | .[].index')
    INDICES=($SORTED)

    if [[ ${#INDICES[@]} -ge 2 ]]; then
        LEFT_INDEX="${INDICES[0]}"
        RIGHT_INDEX="${INDICES[1]}"
    fi
    if [[ ${#INDICES[@]} -ge 3 ]]; then
        LEFT_INDEX="${INDICES[0]}"
        RIGHT_INDEX="${INDICES[2]}"
    fi
fi

case "$TARGET" in
    laptop|l)
        DISPLAY_INDEX="${LAPTOP_INDEX:-1}"
        MONITOR_NAME="laptop"
        LABEL_PREFIX="laptop"
        ARRAY_NAME="LAPTOP_SPACES"
        CURRENT_SPACES=("${LAPTOP_SPACES[@]}")
        ;;
    left|1)
        DISPLAY_INDEX="${LEFT_INDEX:-1}"
        MONITOR_NAME="left"
        LABEL_PREFIX="left"
        ARRAY_NAME="LEFT_SPACES"
        CURRENT_SPACES=("${LEFT_SPACES[@]}")
        ;;
    right|2)
        DISPLAY_INDEX="${RIGHT_INDEX:-2}"
        MONITOR_NAME="right"
        LABEL_PREFIX="right"
        ARRAY_NAME="RIGHT_SPACES"
        CURRENT_SPACES=("${RIGHT_SPACES[@]}")
        ;;
    *)
        echo "Usage: $0 [laptop|left|right]"
        echo "  laptop, l  - Add space to laptop screen"
        echo "  left, 1    - Add space to left external monitor"
        echo "  right, 2   - Add space to right external monitor"
        exit 1
        ;;
esac

# Calculate next label number
NEXT_NUM=$((${#CURRENT_SPACES[@]} + 1))
NEW_LABEL="${LABEL_PREFIX}${NEXT_NUM}"

# Create the space
yabai -m space --create

# Get the new space index (last space)
NEW_SPACE=$(yabai -m query --spaces | jq '.[-1].index')

# Label the new space
yabai -m space "$NEW_SPACE" --label "$NEW_LABEL"

# Move to correct display
yabai -m space "$NEW_LABEL" --display "$DISPLAY_INDEX"

echo "Created space $NEW_SPACE with label '$NEW_LABEL' on $MONITOR_NAME (display $DISPLAY_INDEX)"

# Build new array
NEW_SPACES=("${CURRENT_SPACES[@]}" "$NEW_LABEL")

echo ""
echo "=== Update displays.conf ==="
echo "${ARRAY_NAME}=(${NEW_SPACES[*]})"

# Optionally auto-update
echo ""
read -p "Auto-update displays.conf? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sed -i.bak "s/^${ARRAY_NAME}=.*/${ARRAY_NAME}=(${NEW_SPACES[*]})/" "$CONFIG_FILE"
    echo "Updated $CONFIG_FILE"
fi
