#!/usr/bin/env bash
set -euo pipefail

# emulator-start.sh — Launch an Android emulator and wait for it to boot
# Usage: emulator-start.sh [-n avd_name] [-w] [-p port]

AVD_NAME=""
WAIT_FOR_BOOT=true
EMULATOR_PORT=5554
SERIAL=""

usage() {
  cat <<EOF
Usage: emulator-start.sh [-n avd_name] [-w] [-p port]

  -n avd_name  AVD to launch (default: first available)
  -w           Do NOT wait for boot (default: wait)
  -p port      Emulator port (default: 5554)
  -h           Show this help
EOF
  exit 0
}

while getopts "n:wp:h" opt; do
  case "$opt" in
    n) AVD_NAME="$OPTARG" ;;
    w) WAIT_FOR_BOOT=false ;;
    p) EMULATOR_PORT="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# --- Find emulator binary ---
EMULATOR_BIN=""
if command -v emulator &>/dev/null; then
  EMULATOR_BIN="emulator"
elif [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -x "$ANDROID_SDK_ROOT/emulator/emulator" ]; then
  EMULATOR_BIN="$ANDROID_SDK_ROOT/emulator/emulator"
elif [ -n "${ANDROID_HOME:-}" ] && [ -x "$ANDROID_HOME/emulator/emulator" ]; then
  EMULATOR_BIN="$ANDROID_HOME/emulator/emulator"
else
  echo "ERROR: 'emulator' binary not found on PATH." >&2
  echo "Set ANDROID_SDK_ROOT or ANDROID_HOME, or add \$ANDROID_SDK_ROOT/emulator to PATH." >&2
  exit 1
fi

# --- Resolve AVD ---
if [ -z "$AVD_NAME" ]; then
  AVDS=$("$EMULATOR_BIN" -list-avds 2>/dev/null)
  AVD_COUNT=$(echo "$AVDS" | grep -c . || true)

  if [ "$AVD_COUNT" -eq 0 ]; then
    echo "ERROR: No AVDs found." >&2
    echo "Create one with: avdmanager create avd -n <name> -k \"system-images;android-35;google_apis;x86_64\"" >&2
    exit 1
  fi

  AVD_NAME=$(echo "$AVDS" | head -1)
  if [ "$AVD_COUNT" -gt 1 ]; then
    echo "NOTE: Multiple AVDs found. Using '$AVD_NAME' (override with -n)" >&2
  fi
fi

# --- Check if emulator is already running ---
SERIAL="emulator-${EMULATOR_PORT}"
if adb devices 2>/dev/null | grep -q "^${SERIAL}"; then
  echo "Emulator $SERIAL already connected."
  BOOT_CHECK=$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "0")
  if [ "$BOOT_CHECK" = "1" ]; then
    echo "Emulator is ready."
    echo "$SERIAL"
    exit 0
  elif $WAIT_FOR_BOOT; then
    echo "Waiting for boot to complete..."
  else
    echo "$SERIAL"
    exit 0
  fi
else
  # --- Launch emulator ---
  echo "Launching AVD '$AVD_NAME' on port $EMULATOR_PORT..."
  "$EMULATOR_BIN" -avd "$AVD_NAME" \
    -port "$EMULATOR_PORT" \
    -no-window \
    -no-audio \
    -no-boot-anim \
    -gpu swiftshader_indirect \
    -accel auto \
    &

  EMULATOR_PID=$!
fi

# --- Wait for device to appear ---
echo "Waiting for device $SERIAL..."
adb -s "$SERIAL" wait-for-device 2>/dev/null

if ! $WAIT_FOR_BOOT; then
  echo "$SERIAL"
  exit 0
fi

# --- Wait for boot to complete ---
echo "Waiting for system boot (this may take 30-90s)..."

MAX_WAIT=180
ELAPSED=0
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  BOOT_STATUS=$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "0")
  BOOT_ANIM=$(adb -s "$SERIAL" shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r' || echo "running")

  if [ "$BOOT_STATUS" = "1" ] && [ "$BOOT_ANIM" = "stopped" ]; then
    echo "Emulator booted successfully in ${ELAPSED}s."
    break
  fi

  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
  echo "WARNING: Timed out waiting for boot after ${MAX_WAIT}s. Proceeding anyway." >&2
fi

# --- Unlock screen if needed ---
adb -s "$SERIAL" shell wm dismiss-keyguard 2>/dev/null || true

echo "$SERIAL"
