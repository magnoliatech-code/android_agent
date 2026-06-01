---
name: android-verify
description: Verify Android app changes on an emulator. Spawns the android-tester subagent to install APKs, interact with the UI, take screenshots, and check logs.
---

# Android Verify

Verify Android app changes on an emulator. This skill spawns a dedicated
`android-tester` subagent that does the actual work — you relay between
the user and the subagent.

## When to Load

- The user invokes `/android-verify` or `/verify-android`
- The user asks to "test on emulator", "verify this change on Android",
  "install the APK", "check the app", "run on Android", "take a screenshot
  of the emulator", or similar

## How to Handle Requests

### Pre-flight Check

Before spawning the subagent, quickly verify:
- The `scripts/` directory exists in the project root
- `adb` is on PATH (run `which adb`)

If either is missing, tell the user what to install and point them to
the project README.

### One-shot Verification

When the user asks to verify an app or runs `/verify-android`:

1. **Find the APK** — ask the user for the path, or check common locations
   (`app/build/outputs/apk/debug/`, `build/`). If the user wants to build
   first, run their build command (e.g., `./gradlew assembleDebug`).

2. **Spawn the subagent** — use the Agent tool:
   ```
   Subagent: android-tester
   Prompt: "Verify the APK at <apk_path>. Check the emulator is running or
   start one. Install the APK, launch the app, take a screenshot, check
   logs for errors. Report back what you find."
   ```

3. **Present results** — relay the subagent's findings to the user. If a
   screenshot was taken, Read and display it.

### Interactive Mode

When the user continues the conversation with follow-up commands
("tap X", "scroll down", "check the logs", "what's on screen"):

1. **Keep using the same subagent** — use `SendMessage` with the subagent's
   name or ID to relay the user's request. This preserves the subagent's
   context (device serial, package name, current screen).

2. **Relay the response** — present the subagent's findings to the user.

3. **If context was lost** (new conversation, subagent expired) — spawn a
   fresh android-tester subagent with a summary of the current state.

### Example

```
User: /verify-android
You: [Spawn android-tester("Verify app-debug.apk")]
Subagent: Emulator ready. APK installed. LoginScreen shown. No crashes.
You: App launched on LoginScreen. No crashes. [screenshot]

User: Tap "Sign Up"
You: [SendMessage to android-tester: "Tap the 'Sign Up' button"]
Subagent: Tapped Sign Up. Registration form visible.
You: Registration screen is showing. Fields: Name, Email, Password.

User: Fill in name as "Test User"
You: [SendMessage to android-tester: "Type 'Test User' into the Name field"]
Subagent: Focused Name field and typed "Test User". Done.
You: Name field filled with "Test User".

User: Scroll down
You: [SendMessage to android-tester: "Scroll down"]
Subagent: Scrolled. New elements: Submit button, Terms link.
You: Scrolled down. "Submit" button is now visible.
```
