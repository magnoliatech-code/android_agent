#!/usr/bin/env bash
set -euo pipefail

# input-text.sh — Type text into the focused field on a connected Android device
# Usage: input-text.sh "text to type" [-s serial]
#
# Handles both ASCII and Unicode text (emoji, CJK characters, etc.)
# ASCII: uses fast `adb shell input text`
# Unicode: uses clipboard paste approach

SERIAL="${ANDROID_SERIAL:-}"
TEXT=""

usage() {
  cat <<EOF
Usage: input-text.sh <text> [-s serial]

  text       The text to type (supports Unicode/emoji)
  -s serial  Target a specific device (default: first connected)
  -h         Show this help
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) SERIAL="$2"; shift 2 ;;
    -h) usage ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
    *)
      if [ -z "$TEXT" ]; then
        TEXT="$1"
        shift
      else
        # Append remaining text with spaces (handle multi-word input)
        TEXT="$TEXT $1"
        shift
      fi
      ;;
  esac
done

if [ -z "$TEXT" ]; then
  echo "ERROR: Text to type is required." >&2
  usage
fi

adb_cmd() {
  if [ -n "$SERIAL" ]; then
    adb -s "$SERIAL" "$@"
  else
    adb "$@"
  fi
}

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

# --- Check if text is ASCII-only ---
is_ascii() {
  # ASCII printable: space (32) through tilde (126)
  # Also allow newline, tab
  ! echo "$1" | grep -qP '[^\x20-\x7E\x0A\x09]'
}

# --- Get Android API level ---
API_LEVEL=$(adb_cmd shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || echo "0")

echo "Typing: \"$TEXT\""

if is_ascii "$TEXT"; then
  # Fast path: ASCII-only, use input text directly
  # Escape special characters for `input text`
  # %s = space, but we need to handle other special chars too
  ESCAPED=$(echo "$TEXT" | sed 's/ /%s/g')
  adb_cmd shell input text "$ESCAPED"
  echo "Typed (ASCII fast path)."
else
  # Unicode path: use clipboard + paste
  echo "Unicode detected. Using clipboard method..."

  # Android 13+ (API 33): clipboard service supports setting text directly
  if [ "$API_LEVEL" -ge 33 ] 2>/dev/null; then
    # Escape the text for shell
    # Use base64 to safely pass any text through adb shell
    ENCODED=$(echo -n "$TEXT" | base64)
    adb_cmd shell "echo $ENCODED | base64 -d | cmd clipboard set" 2>/dev/null
  else
    # Older Android: use service call or am broadcast
    # Escape and push via broadcast
    ENCODED=$(echo -n "$TEXT" | base64)
    adb_cmd shell "echo $ENCODED | base64 -d | am broadcast -n com.android.shell/.ClipboardService 2>/dev/null" || {
      # Try alternative: write to a temp file and broadcast
      adb_cmd shell "echo $ENCODED | base64 -d > /sdcard/clip_tmp.txt"
      adb_cmd shell "cat /sdcard/clip_tmp.txt | am broadcast -a android.intent.action.SET_CLIPBOARD_TEXT" 2>/dev/null || true
      adb_cmd shell "rm /sdcard/clip_tmp.txt" 2>/dev/null || true
    }
  fi

  # Small delay for clipboard to take effect
  sleep 0.3

  # Send paste keyevent (KEYCODE_PASTE = 279)
  adb_cmd shell input keyevent 279

  echo "Typed (Unicode via clipboard paste)."
fi
