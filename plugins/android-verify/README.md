# Android Emulator Testing Plugin for Claude Code

Test and verify Android apps directly from Claude Code. Install APKs to an
emulator, inspect the UI, tap and swipe, type text, capture screenshots,
and read logs — without leaving your editor.

```
/android-verify          (canonical)
/verify-android          (alias, also works)
```

> No external MCP servers or libraries. Just the Android SDK and Python 3.

## Quick Start

```bash
# 1. Install the plugin in Claude Code
/plugin marketplace add magnoliatech-code/android_agent
/plugin install android-verify@magnoliatech-android-tools
```

```bash
# 2. Make sure you have an Android emulator (AVD)
emulator -list-avds
# If empty, create one:
avdmanager create avd -n Pixel8 -k "system-images;android-35;google_apis;x86_64" -d pixel_8
```

```bash
# 3. Run the command
/verify-android
```

Claude will check the emulator, install your APK, launch the app, take a
screenshot, and report any crashes from logcat.

## What It Can Do

| Capability | How |
|---|---|
| Install APKs | `scripts/install-apk.sh <apk>` with auto-diagnosis |
| Take screenshots | `scripts/screenshot.sh` — Claude sees exactly what's on screen |
| Read logs | `scripts/get-logs.sh` — filtered logcat by package, level, tag |
| Inspect UI | `scripts/dump-ui.sh` — all interactive elements with labels and bounds |
| Tap buttons | `scripts/tap.sh --text "Login"` — tap by text, ID, or coordinates |
| Scroll & swipe | `scripts/swipe.sh --direction up` — scroll in any direction |
| Type text | `scripts/input-text.sh "hello"` — supports Unicode and emoji |
| System keys | `scripts/key-event.sh back` — back, home, enter, volume, etc. |

## Interactive Example

First, you ask Claude to verify the app. Then you explore interactively.

```
Step 1: Quick verify

  You:  /android-verify
  Claude: Emulator ready. Installed APK. Launched app.
          LoginScreen is showing. No crashes in logcat.
          Screenshot saved.

Step 2: Explore interactively — just keep talking

  You:  Tap the "Sign Up" button
  Claude: Tapped. Now on Registration screen.
          Fields visible: Name, Email, Password, Confirm.

  You:  Type "Test User" into the Name field
  Claude: Focused the Name field and typed "Test User".

  You:  Scroll down
  Claude: Scrolled. "Submit" button is now visible.

  You:  Tap Submit
  Claude: Tapped Submit.
          New screen: "Welcome, Test User!" — No errors.
```

## Prerequisites

- **Android SDK** — `adb`, `emulator`, and `avdmanager` on `PATH`
- **Python 3** — for parsing UI hierarchy (installed by default on macOS/Linux)
- **An AVD** — at least one Android Virtual Device created

### Installing the Android SDK

```bash
# macOS
brew install android-commandlinetools

# Or download from developer.android.com/studio#command-line-tools
```

Add to your shell config (`~/.zshrc` or `~/.bashrc`):

```bash
export ANDROID_SDK_ROOT=$HOME/Library/Android/sdk
export PATH=$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/platform-tools:$PATH
```

## Workflows

### One-shot verification

Type `/verify-android`. Claude spawns the `android-tester` subagent which:
1. Checks the emulator is running (or launches one)
2. Installs the APK
3. Launches the app
4. Captures a screenshot
5. Checks logcat for errors
6. Reports the result

### Interactive debugging

After verifying, continue the conversation naturally. Claude relays your
commands to the subagent, which keeps context across messages:

- `"Tap the Settings button"`
- `"What's on the screen?"`
- `"Scroll down"`
- `"Type 'search query' into the search bar"`
- `"Check for crashes"`

### Trigger phrases

The skill activates on any of these:
- `/verify-android` or `/android-verify`
- "test on emulator", "verify this change on Android"
- "install the APK", "check the app", "run on Android"
- "take a screenshot of the emulator"

## Script Reference

All scripts live in `scripts/` and accept `-s <serial>` to target a
specific device. Run any with `-h` for full usage.

### Emulator

| Script | Purpose |
|---|---|
| `emulator-start.sh [-n avd]` | Launch emulator, wait for boot |
| `emulator-status.sh [-p filter] [-j]` | Device info, boot state, installed packages |

### App

| Script | Purpose |
|---|---|
| `install-apk.sh <apk> [-r] [-g]` | Install APK with error diagnosis |

### Observe

| Script | Purpose |
|---|---|
| `screenshot.sh [path]` | Capture screenshot, output the file path |
| `get-logs.sh [-p pkg] [-l level] [-n N] [-f]` | Filtered logcat with package/level/tag control |

### Inspect

| Script | Purpose |
|---|---|
| `dump-ui.sh [--format compact\|json\|text]` | Dump UI hierarchy of interactive elements |
| `find-element.sh (--text\|--id\|--desc) <value>` | Locate element by property, return tap coordinates |

### Interact

| Script | Purpose |
|---|---|
| `tap.sh <x> <y>` | Tap at screen coordinates |
| `tap.sh --text "Login"` | Tap element by text label |
| `tap.sh --id "com.ex:id/btn"` | Tap element by resource ID |
| `tap.sh --desc "Search"` | Tap element by content description |
| `swipe.sh <x1> <y1> <x2> <y2> [ms]` | Swipe between coordinates |
| `swipe.sh --direction up\|down\|left\|right` | Swipe from screen center |
| `input-text.sh <text>` | Type text (ASCII + Unicode/emoji) |
| `key-event.sh <event>` | Send key: back, home, enter, paste, etc. |
| `key-event.sh --list` | List all available key events |

## Project Structure

```
android_agent/
├── .claude-plugin/
│   ├── marketplace.json             # Marketplace listing
│   └── plugin.json                  # Plugin manifest
├── .claude/
│   ├── agents/
│   │   └── android-tester.md        # Subagent: the testing expert
│   └── skills/
│       └── android-verify/
│           └── SKILL.md             # Skill: dispatcher entry point
├── scripts/
│   ├── emulator-start.sh            # Launch emulator
│   ├── emulator-status.sh           # Device info
│   ├── install-apk.sh               # APK installation
│   ├── screenshot.sh                # Screen capture
│   ├── get-logs.sh                  # Logcat filtering
│   ├── dump-ui.sh                   # UI hierarchy parser
│   ├── find-element.sh              # Element locator
│   ├── tap.sh                       # Tap interaction
│   ├── swipe.sh                     # Swipe/scroll
│   ├── input-text.sh                # Text input
│   └── key-event.sh                 # Key events
└── README.md
```

## Troubleshooting

**"No devices/emulators connected"**
```bash
emulator -avd <name> &
adb devices
adb kill-server && adb start-server  # if stuck
```

**"emulator: command not found"**
Ensure `$ANDROID_SDK_ROOT/emulator` is on your `PATH`.

**Screenshot is blank or black**
The emulator may still be booting. The launcher waits for boot but very
large system images can take 60–90 seconds. Try `-gpu swiftshader_indirect`.

**INSTALL_FAILED_NO_MATCHING_ABIS**
Your APK was built for ARM but the emulator is x86_64. Build an x86_64
APK or use an ARM-compatible system image.

**Unicode text not appearing**
The clipboard paste method requires Android 13+ (API 33). On older images,
only ASCII text is supported via `adb shell input text`.

## License

MIT
