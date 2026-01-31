#!/bin/bash
# =============================================================================
# init-spaces.sh - Initialize and label spaces for consistent tracking
# =============================================================================
# Queries existing spaces and distributes them equally across displays.
# Labels persist across index changes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/displays.conf"

echo "=== Initializing Space Labels ==="
echo ""

# Get current spaces
SPACES=$(yabai -m query --spaces)
NUM_SPACES=$(echo "$SPACES" | jq 'length')

echo "Total spaces: $NUM_SPACES"

# Determine number of displays to distribute across
NUM_DISPLAYS=3  # laptop, left, right (can be overridden)

# Check actual connected displays
DISPLAYS=$(yabai -m query --displays 2>/dev/null)
if [[ -n "$DISPLAYS" ]]; then
    ACTUAL_DISPLAYS=$(echo "$DISPLAYS" | jq 'length')
    echo "Connected displays: $ACTUAL_DISPLAYS"
fi

# Calculate spaces per display
SPACES_PER_DISPLAY=$((NUM_SPACES / NUM_DISPLAYS))
REMAINDER=$((NUM_SPACES % NUM_DISPLAYS))

echo "Distribution: $SPACES_PER_DISPLAY spaces per display"
if [[ $REMAINDER -gt 0 ]]; then
    echo "  (extra $REMAINDER space(s) will go to laptop)"
fi
echo ""

# Calculate ranges
LAPTOP_COUNT=$((SPACES_PER_DISPLAY + REMAINDER))  # laptop gets remainder
LEFT_COUNT=$SPACES_PER_DISPLAY
RIGHT_COUNT=$SPACES_PER_DISPLAY

LAPTOP_START=1
LAPTOP_END=$LAPTOP_COUNT

LEFT_START=$((LAPTOP_END + 1))
LEFT_END=$((LEFT_START + LEFT_COUNT - 1))

RIGHT_START=$((LEFT_END + 1))
RIGHT_END=$((RIGHT_START + RIGHT_COUNT - 1))

echo "Laptop spaces: $LAPTOP_START-$LAPTOP_END ($LAPTOP_COUNT spaces)"
echo "Left spaces:   $LEFT_START-$LEFT_END ($LEFT_COUNT spaces)"
echo "Right spaces:  $RIGHT_START-$RIGHT_END ($RIGHT_COUNT spaces)"
echo ""

# Confirm before proceeding
read -p "Proceed with labeling? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Labeling spaces..."

# Build arrays for config
LAPTOP_LABELS=()
LEFT_LABELS=()
RIGHT_LABELS=()

# Label laptop spaces
for ((i=LAPTOP_START; i<=LAPTOP_END; i++)); do
    label="laptop$((i - LAPTOP_START + 1))"
    LAPTOP_LABELS+=("$label")
    yabai -m space "$i" --label "$label" 2>/dev/null && \
        echo "  Space $i → $label" || \
        echo "  Space $i: failed to label"
done

# Label left spaces
for ((i=LEFT_START; i<=LEFT_END; i++)); do
    label="left$((i - LEFT_START + 1))"
    LEFT_LABELS+=("$label")
    yabai -m space "$i" --label "$label" 2>/dev/null && \
        echo "  Space $i → $label" || \
        echo "  Space $i: failed to label"
done

# Label right spaces
for ((i=RIGHT_START; i<=RIGHT_END; i++)); do
    label="right$((i - RIGHT_START + 1))"
    RIGHT_LABELS+=("$label")
    yabai -m space "$i" --label "$label" 2>/dev/null && \
        echo "  Space $i → $label" || \
        echo "  Space $i: failed to label"
done

echo ""
echo "=== Update displays.conf with these values ==="
echo ""
echo "LAPTOP_SPACES=(${LAPTOP_LABELS[*]})"
echo "LEFT_SPACES=(${LEFT_LABELS[*]})"
echo "RIGHT_SPACES=(${RIGHT_LABELS[*]})"

# Optionally update config file
echo ""
read -p "Auto-update displays.conf? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Update the arrays in config file using sed
    sed -i.bak "s/^LAPTOP_SPACES=.*/LAPTOP_SPACES=(${LAPTOP_LABELS[*]})/" "$CONFIG_FILE"
    sed -i.bak "s/^LEFT_SPACES=.*/LEFT_SPACES=(${LEFT_LABELS[*]})/" "$CONFIG_FILE"
    sed -i.bak "s/^RIGHT_SPACES=.*/RIGHT_SPACES=(${RIGHT_LABELS[*]})/" "$CONFIG_FILE"

    echo "Updated $CONFIG_FILE"
    echo "(Backup saved as displays.conf.bak)"
fi

echo ""
echo "=== Current Space Labels ==="
yabai -m query --spaces | jq -r '.[] | "  Space \(.index): \(.label // "(unlabeled)")"'

echo ""
echo "Done. Run restore-spaces.sh to move spaces to correct displays."
