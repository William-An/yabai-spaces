#!/bin/bash
# =============================================================================
# yabairc-snippet.sh - Add this to your ~/.yabairc
# =============================================================================

# Load scripting addition (required for space management)
# Re-load when Dock restarts (e.g., after macOS updates)
yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"
sudo yabai --load-sa

# Paths to scripts
YABAI_SCRIPTS="$HOME/.config/yabai"
RESTORE_SCRIPT="$YABAI_SCRIPTS/restore-spaces.sh"

# -----------------------------------------------------------------------------
# Window-Space Mapping: Saved periodically via launchd timer
# -----------------------------------------------------------------------------
# The save-window-mapping.sh script runs every 60 seconds via launchd.
# Install with: launchctl load ~/Library/LaunchAgents/com.user.yabai-save-windows.plist
# This approach avoids race conditions from rapid signal-based triggers.

# -----------------------------------------------------------------------------
# Display Events: Restore spaces and windows on connect/disconnect
# -----------------------------------------------------------------------------

# Restore spaces and windows when displays are added or resized
yabai -m signal --add event=display_added action="$RESTORE_SCRIPT"
yabai -m signal --add event=display_resized action="$RESTORE_SCRIPT"

# -----------------------------------------------------------------------------
# Initial setup on yabai start
# -----------------------------------------------------------------------------
$RESTORE_SCRIPT  # Restore spaces/windows on yabai start

# =============================================================================
# Optional: App rules (uncomment and modify as needed)
# =============================================================================
# These rules automatically move apps to specific spaces when they launch
# yabai -m rule --add app="Code" space=left1
# yabai -m rule --add app="Terminal" space=left2
# yabai -m rule --add app="Slack" space=right1
# yabai -m rule --add app="Safari" space=laptop1
# yabai -m rule --add app="Mail" space=laptop2
