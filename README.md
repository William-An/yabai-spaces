# Yabai Multi-Monitor Space Management

Maintain consistent desktop space assignments across different monitor setups (home/office).

Supports 3 displays: **laptop (built-in) + left external + right external**

## Files

| File | Purpose |
|------|---------|
| `install.sh` | Installer: copies scripts to ~/.config/yabai, installs launchd timer |
| `displays.conf` | Configuration: UUIDs and space assignments |
| `restore-spaces.sh` | Main script: moves spaces and windows to correct displays |
| `save-window-mapping.sh` | Saves window-to-space assignments (runs via launchd timer) |
| `com.user.yabai-save-windows.plist` | launchd timer: runs save-window-mapping.sh every 60s |
| `init-spaces.sh` | Initialize and label spaces (run once) |
| `add-space.sh` | Helper: create new space on laptop/left/right |
| `get-uuids.sh` | Interactive: detects displays, prompts for left/right |
| `yabairc-snippet.sh` | Code to add to your yabairc |

---

## Installation

### Step 1: Partially disable SIP (required for space management)

Moving spaces between displays requires yabai's scripting addition, which needs SIP partially disabled.

1. **Reboot into Recovery Mode:**
   - Apple Silicon: Hold power button → "Options" → Continue
   - Intel: Hold `Cmd + R` during boot

2. **Open Terminal** (Utilities → Terminal) and run:
   ```bash
   csrutil enable --without fs --without debug --without nvram
   ```

3. **Reboot** back to macOS

4. **Verify** SIP status:
   ```bash
   csrutil status
   # Should show: "enabled" with some exceptions
   ```

> ⚠️ This partially disables SIP. Understand the security implications before proceeding.

### Step 2: Install yabai

```bash
brew install koekeishiya/formulae/yabai
```

Configure sudoers for scripting addition (no password prompt):
```bash
echo "$(whoami) ALL=(root) NOPASSWD: sha256:$(shasum -a 256 $(which yabai) | cut -d " " -f 1) $(which yabai) --load-sa" | sudo tee /private/etc/sudoers.d/yabai
```

### Step 3: Run installer

```bash
./install.sh
```

Or manually:
```bash
mkdir -p ~/.config/yabai
cp *.sh *.conf ~/.config/yabai/
chmod +x ~/.config/yabai/*.sh
```

### Step 4: Start yabai

```bash
yabai --start-service
```

### Step 5: Get display UUIDs

**At home:**
```bash
~/.config/yabai/get-uuids.sh home
```

**At office:**
```bash
~/.config/yabai/get-uuids.sh office
```

The script will:
1. Auto-detect your laptop's built-in display
2. List external monitors and ask you to identify which is LEFT
3. Auto-assign the remaining external as RIGHT
4. Output config lines to copy into `displays.conf`

Example interaction:
```
=== Identify External Monitors ===
Which external monitor is your LEFT monitor?

  1) Index=2, 2560x1440, x=-2560, Spaces: 4, 5, 6
  2) Index=3, 2560x1440, x=1512, Spaces: 7, 8, 9

Enter number [1-2]: 1

Assigned:
  Left:  Index=2, 2560x1440, x=-2560, Spaces: 4, 5, 6
  Right: Index=3, 2560x1440, x=1512, Spaces: 7, 8, 9 (auto-assigned)
```

### Step 6: Configure yabairc

Add the contents of `yabairc-snippet.sh` to your `~/.yabairc`:

```bash
cat ~/.config/yabai/yabairc-snippet.sh >> ~/.yabairc
```

Then restart yabai:
```bash
yabai --restart-service
```

---

## Usage

### Manual restore
```bash
~/.config/yabai/restore-spaces.sh
```

### Add new space
```bash
~/.config/yabai/add-space.sh laptop  # Add space to laptop screen
~/.config/yabai/add-space.sh left    # Add space to left external
~/.config/yabai/add-space.sh right   # Add space to right external
```

After adding, update the corresponding array in `displays.conf`.

---

## Configuration Reference

### Why use labels instead of indices?

macOS renumbers space indices when displays connect/disconnect. Space 11 can become Space 15 after reconnection. **Labels persist** regardless of index changes.

### Initialize space labels (run once)

```bash
~/.config/yabai/init-spaces.sh
```

This creates and labels spaces according to `displays.conf`.

### In `displays.conf`:

```bash
# Use labels (recommended) - persist across index changes
LAPTOP_SPACES=(laptop1 laptop2 laptop3)
LEFT_SPACES=(left1 left2 left3)
RIGHT_SPACES=(right1 right2 right3)

# Or use indices (fragile - may break on display changes)
# LAPTOP_SPACES=(1 2 3)
# LEFT_SPACES=(4 5 6)
# RIGHT_SPACES=(7 8 9)
```

### Manual labeling

```bash
yabai -m space 1 --label laptop1
yabai -m space 4 --label left1
yabai -m space 7 --label right1
# ... etc
```

The restore script will:
1. Detect connected monitors by UUID
2. Identify laptop by common MacBook resolutions as fallback
3. Fall back to position (leftmost = left) if UUID unknown
4. Move spaces (by label or index) to their assigned displays

---

## Troubleshooting

**Spaces not moving:**
- Verify SIP is partially disabled: `csrutil status`
- Ensure scripting addition loads: add `yabai -m signal --add event=dock_did_restart action="sudo yabai --load-sa"` and `sudo yabai --load-sa` to your yabairc
- Check System Settings > Privacy & Security > Accessibility for yabai

**"operation not permitted" errors:**
- SIP not properly configured - redo Step 1
- Sudoers entry invalid - re-run the sudoers command from Step 2

**UUIDs not recognized:**
- Re-run `get-uuids.sh` and update `displays.conf`
- The fallback uses physical position (x-coordinate)

**New location:**
- Run `get-uuids.sh <location_name>` and add the UUIDs to `displays.conf`

**View logs:**
```bash
tail -f ~/.config/yabai/restore-spaces.log
tail -f ~/.config/yabai/save-window-mapping.log
```

---

## How It Works

### Window Mapping Timer

Window-to-space mappings are saved every 60 seconds via a launchd timer (not yabai signals). This avoids race conditions from rapid signal-based triggers.

- Only saves when **3 displays are connected** (prevents overwriting with laptop-only state)
- Uses file locking to prevent concurrent writes
- Logs to `~/.config/yabai/save-window-mapping.log`

**Timer management:**
```bash
# Check status
launchctl list | grep yabai-save

# Stop timer
launchctl unload ~/Library/LaunchAgents/com.user.yabai-save-windows.plist

# Start timer
launchctl load ~/Library/LaunchAgents/com.user.yabai-save-windows.plist
```

### Space Restoration

Triggered automatically by yabai signals on `display_added` and `display_resized`.

- Relabels spaces from saved UUID→label mapping
- Moves spaces to correct displays by UUID (falls back to position)
- Restores windows using app+title matching
- Uses file locking to prevent concurrent runs
- Logs to `~/.config/yabai/restore-spaces.log`
