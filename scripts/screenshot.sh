#!/usr/bin/env bash
set -euo pipefail

# screenshot.sh — Capture a screenshot from a connected Android device/emulator
# Usage: screenshot.sh [-s serial] [output_path]

SERIAL="${ANDROID_SERIAL:-}"
OUTPUT_PATH=""

usage() {
  cat <<EOF
Usage: screenshot.sh [-s serial] [output_path]

  output_path  Where to save the screenshot (default: /tmp/android-screenshot-<timestamp>.png)
  -s serial    Target a specific device (default: first connected)
  -h           Show this help
EOF
  exit 0
}

while getopts "s:h" opt; do
  case "$opt" in
    s) SERIAL="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

if [ -n "${1:-}" ]; then
  OUTPUT_PATH="$1"
fi

adb_cmd() {
  if [ -n "$SERIAL" ]; then
    adb -s "$SERIAL" "$@"
  else
    adb "$@"
  fi
}

# Resolve device serial
resolve_serial() {
  local devices
  devices=$(adb devices 2>/dev/null | tail -n +2 | grep -v '^$' | awk '{print $1}')
  local count
  count=$(echo "$devices" | grep -c . || true)

  if [ "$count" -eq 0 ]; then
    echo "ERROR: No devices/emulators connected." >&2
    exit 1
  fi

  if [ -z "$SERIAL" ]; then
    SERIAL=$(echo "$devices" | head -1)
  fi
}

resolve_serial

# Resolve output path
if [ -z "$OUTPUT_PATH" ]; then
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  OUTPUT_PATH="/tmp/android-screenshot-${TIMESTAMP}.png"
fi

# Ensure output directory exists
OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
mkdir -p "$OUTPUT_DIR"

# Capture screenshot
# Use exec-out for reliable piping — avoids file corruption issues with adb pull
if adb_cmd exec-out screencap -p > "$OUTPUT_PATH" 2>/dev/null; then
  if [ -s "$OUTPUT_PATH" ]; then
    echo "$OUTPUT_PATH"
    exit 0
  else
    echo "ERROR: Screenshot file is empty. The screen may be off or the device is not fully booted." >&2
    rm -f "$OUTPUT_PATH"
    exit 1
  fi
else
  # Fallback: save on device then pull
  echo "NOTE: exec-out failed, trying pull method..." >&2
  DEVICE_PATH="/sdcard/screenshot_tmp.png"
  adb_cmd shell screencap -p "$DEVICE_PATH" 2>/dev/null
  adb_cmd pull "$DEVICE_PATH" "$OUTPUT_PATH" 2>/dev/null
  adb_cmd shell rm "$DEVICE_PATH" 2>/dev/null || true

  if [ -s "$OUTPUT_PATH" ]; then
    echo "$OUTPUT_PATH"
  else
    echo "ERROR: Failed to capture screenshot." >&2
    rm -f "$OUTPUT_PATH"
    exit 1
  fi
fi
