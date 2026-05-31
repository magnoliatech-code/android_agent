# Android Agent

A Claude Code subagent for Android app development. It automates the manual
test-and-verify loop: install your APK to an emulator, interact with the UI,
capture screenshots, read logs, and report results — all from within Claude Code.

## How It Works

The subagent is a Claude Code skill (`/verify-android`) backed by small shell
scripts that wrap Android SDK CLI tools (`adb`, `emulator`). No external
libraries or MCP servers needed — just the Android SDK and Python 3.

```
You: /verify-android
Claude: [Launches emulator] → [Installs APK] → [Launches app]
        → [Screenshot] → [Checks logs] → Reports result.

You: Tap the "Settings" button
Claude: [Finds element] → [Taps it] → [Screenshot] → "Settings screen loaded."
```

## Prerequisites

### 1. Android SDK

Install the Android SDK command-line tools:

**macOS (Homebrew):**
```bash
brew install android-commandlinetools
```

**Manual install:**
Download from [developer.android.com/studio#command-line-tools](https://developer.android.com/studio#command-line-tools)
and add to PATH.

Ensure these are on your PATH:
```bash
which adb       # Android Debug Bridge
which emulator   # Emulator launcher
which avdmanager # AVD manager (optional, for creating emulators)
```

Set environment variables (add to `~/.zshrc` or `~/.bashrc`):
```bash
export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk
export PATH=$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH
```

### 2. Python 3

Required for UI hierarchy XML parsing. Most macOS/Linux systems have it.
```bash
which python3
```

### 3. Create an Android Virtual Device (AVD)

```bash
# List available system images
sdkmanager --list | grep system-images

# Install a system image (API 35, x86_64 recommended for performance)
sdkmanager "system-images;android-35;google_apis;x86_64"

# Create an AVD
avdmanager create avd -n Pixel8 -k "system-images;android-35;google_apis;x86_64" -d pixel_8

# Verify
emulator -list-avds
```

## Setup

1. Clone or copy this project to your Android app workspace.

2. The skill is automatically discovered by Claude Code when it's in
   `.claude/skills/android-verify.md` relative to your project root.

3. Make sure the scripts are executable:
   ```bash
   chmod +x scripts/*.sh
   ```

## Usage

### Quick Verification

```
/verify-android
```

Claude will check the emulator state, install the APK, launch the app,
capture a screenshot, and report any errors from logcat.

### Interactive Testing

After the quick verify, continue the conversation to explore interactively:

```
You: Scroll down and check if the footer is visible
You: Tap the "Profile" tab
You: Type "testuser" into the search field
You: What errors are in the logs?
```

Or start interactive mode directly:

```
You: Launch the emulator and install the debug APK so I can test it.
```

### Other Ways to Invoke

Any of these phrases will trigger the skill:
- "Test this change on the emulator"
- "Verify the app on Android"
- "Install the APK and check it"
- "Take a screenshot of the emulator"
- "Check for crashes in the app"

## Script Reference

All scripts live in `scripts/` and accept `-s <serial>` to target a specific
device. Run any script with `-h` for full usage.

### Emulator Management

| Script | Purpose |
|---|---|
| `emulator-start.sh [-n avd] [-p port]` | Launch emulator, wait for boot |
| `emulator-status.sh [-p filter] [-j]` | Device info, boot state, installed packages |

### App Management

| Script | Purpose |
|---|---|
| `install-apk.sh <apk> [-r] [-g]` | Install APK with auto-diagnosis |

### Observation

| Script | Purpose |
|---|---|
| `screenshot.sh [path]` | Capture screenshot, output file path |
| `get-logs.sh [-p pkg] [-l level] [-n N] [-f]` | Filtered logcat output |

### UI Inspection

| Script | Purpose |
|---|---|
| `dump-ui.sh [--format compact\|json\|text]` | Dump interactive UI elements |
| `find-element.sh (--text\|--id\|--desc) <value>` | Find element by property |

### Interaction

| Script | Purpose |
|---|---|
| `tap.sh <x> <y>` | Tap at coordinates |
| `tap.sh --text "Login"` | Tap element by text |
| `tap.sh --id "com.ex:id/btn"` | Tap element by resource ID |
| `tap.sh --desc "Search"` | Tap element by content description |
| `swipe.sh <x1> <y1> <x2> <y2> [ms]` | Swipe by coordinates |
| `swipe.sh --direction up\|down\|left\|right` | Swipe from screen center |
| `input-text.sh <text>` | Type text (ASCII + Unicode) |
| `key-event.sh <event>` | Send key (back, home, enter, paste, etc.) |
| `key-event.sh --list` | List available key events |

### Common Patterns

```bash
# Quick check: is the emulator running?
./scripts/emulator-status.sh

# Launch emulator and wait for boot (or use existing)
./scripts/emulator-start.sh

# Install and verify
./scripts/install-apk.sh app/build/outputs/apk/debug/app-debug.apk

# See what's on screen
./scripts/dump-ui.sh --format compact

# Find and tap a button
./scripts/tap.sh --text "Get Started"

# Scroll down
./scripts/swipe.sh --direction up

# Type text (works with emoji/Unicode too)
./scripts/input-text.sh "user@example.com"
./scripts/input-text.sh "你好世界"

# Check for crashes
./scripts/get-logs.sh -p com.example.app -l E -n 50

# Navigate back
./scripts/key-event.sh back

# Screenshot
./scripts/screenshot.sh ~/Desktop/screen.png
```

## Project Structure

```
android_agent/
├── .claude/
│   └── skills/
│       └── android-verify.md    # Skill definition
├── scripts/
│   ├── emulator-start.sh         # Launch emulator
│   ├── emulator-status.sh        # Device info
│   ├── install-apk.sh            # APK installation
│   ├── screenshot.sh             # Screen capture
│   ├── get-logs.sh               # Logcat filtering
│   ├── dump-ui.sh                # UI hierarchy parser
│   ├── find-element.sh           # Element locator
│   ├── tap.sh                    # Tap interaction
│   ├── swipe.sh                  # Swipe/scroll
│   ├── input-text.sh             # Text input
│   └── key-event.sh              # Key events
└── README.md                     # This file
```

## Troubleshooting

**"No devices/emulators connected"**
- Make sure the emulator is running: `emulator -avd <name> &`
- Check with `adb devices`
- Try `adb kill-server && adb start-server`

**"emulator: command not found"**
- Make sure `$ANDROID_SDK_ROOT/emulator` is on your PATH

**Screenshot is blank/black**
- The emulator may still be booting. Wait for `sys.boot_completed=1`
- Try `-gpu swiftshader_indirect` when launching the emulator

**"INSTALL_FAILED_NO_MATCHING_ABIS"**
- Your APK was built for ARM but the emulator is x86_64
- Build an x86_64 APK or use an ARM-compatible system image

**Unicode text not appearing**
- The clipboard paste method requires Android 13+. For older versions,
  only ASCII text is supported via `adb shell input text`.
