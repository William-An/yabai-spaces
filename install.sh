#!/bin/bash
# =============================================================================
# install.sh - Install yabai space management scripts
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YABAI_CONFIG="$HOME/.config/yabai"

echo "=== Yabai Space Management Installer ==="
echo ""

# Check if yabai is installed
if ! command -v yabai &> /dev/null; then
    echo "yabai not found. Install with:"
    echo "  brew install koekeishiya/formulae/yabai"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Create config directory
echo "Creating $YABAI_CONFIG..."
mkdir -p "$YABAI_CONFIG"

# Copy scripts
echo "Copying scripts..."
cp "$SCRIPT_DIR/displays.conf" "$YABAI_CONFIG/"
cp "$SCRIPT_DIR/restore-spaces.sh" "$YABAI_CONFIG/"
cp "$SCRIPT_DIR/init-spaces.sh" "$YABAI_CONFIG/"
cp "$SCRIPT_DIR/add-space.sh" "$YABAI_CONFIG/"
cp "$SCRIPT_DIR/get-uuids.sh" "$YABAI_CONFIG/"
cp "$SCRIPT_DIR/save-window-mapping.sh" "$YABAI_CONFIG/"
cp "$SCRIPT_DIR/yabairc-snippet.sh" "$YABAI_CONFIG/"

# Set permissions
echo "Setting executable permissions..."
chmod +x "$YABAI_CONFIG"/*.sh

# Check if yabairc exists
YABAIRC="$HOME/.yabairc"
if [[ -f "$YABAIRC" ]]; then
    echo ""
    echo "Existing ~/.yabairc found."
    read -p "Append space management config to it? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "" >> "$YABAIRC"
        echo "# === Space Management (added by installer) ===" >> "$YABAIRC"
        cat "$YABAI_CONFIG/yabairc-snippet.sh" >> "$YABAIRC"
        echo "Appended to ~/.yabairc"
    fi
else
    echo ""
    read -p "Create ~/.yabairc with space management config? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "#!/bin/bash" > "$YABAIRC"
        echo "" >> "$YABAIRC"
        cat "$YABAI_CONFIG/yabairc-snippet.sh" >> "$YABAIRC"
        chmod +x "$YABAIRC"
        echo "Created ~/.yabairc"
    fi
fi

# Install launchd plist for periodic window mapping saves
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_NAME="com.user.yabai-save-windows.plist"

echo ""
echo "Installing launchd timer for window mapping..."
mkdir -p "$LAUNCH_AGENTS"
cp "$SCRIPT_DIR/$PLIST_NAME" "$LAUNCH_AGENTS/"

# Update the plist to use the actual path (expand ~)
sed -i '' "s|~/.config/yabai|$YABAI_CONFIG|g" "$LAUNCH_AGENTS/$PLIST_NAME"

# Load the launch agent
if launchctl list | grep -q "com.user.yabai-save-windows"; then
    launchctl unload "$LAUNCH_AGENTS/$PLIST_NAME" 2>/dev/null
fi
launchctl load "$LAUNCH_AGENTS/$PLIST_NAME"
echo "  Loaded: $LAUNCH_AGENTS/$PLIST_NAME (runs every 60s)"

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run: $YABAI_CONFIG/get-uuids.sh home"
echo "  2. Copy UUIDs to: $YABAI_CONFIG/displays.conf"
echo "  3. Repeat at office: $YABAI_CONFIG/get-uuids.sh office"
echo "  4. Edit displays.conf - set space labels (e.g., laptop1, left1, right1)"
echo "  5. Run: $YABAI_CONFIG/init-spaces.sh (creates and labels spaces)"
echo "  6. Start/restart yabai: yabai --restart-service"
echo ""
echo "Window mappings are saved every 60s via launchd timer."
echo "  Check status: launchctl list | grep yabai-save"
echo "  View logs: tail -f $YABAI_CONFIG/save-window-mapping.log"
