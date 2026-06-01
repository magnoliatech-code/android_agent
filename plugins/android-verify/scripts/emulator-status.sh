#!/usr/bin/env bash
set -euo pipefail

# emulator-status.sh — Report connected Android device/emulator state
# Usage: emulator-status.sh [-s serial] [-p package_filter] [-j]

SERIAL="${ANDROID_SERIAL:-}"
PACKAGE_FILTER=""
JSON_OUTPUT=false

usage() {
  cat <<EOF
Usage: emulator-status.sh [-s serial] [-p package_filter] [-j]

  -s serial         Target a specific device (default: first connected)
  -p package_filter Filter installed packages (e.g., "com.example")
  -j                Output as JSON
  -h                Show this help
EOF
  exit 0
}

while getopts "s:p:jh" opt; do
  case "$opt" in
    s) SERIAL="$OPTARG" ;;
    p) PACKAGE_FILTER="$OPTARG" ;;
    j) JSON_OUTPUT=true ;;
    h) usage ;;
    *) usage ;;
  esac
done

adb_cmd() {
  if [ -n "$SERIAL" ]; then
    adb -s "$SERIAL" "$@"
  else
    adb "$@"
  fi
}

# Resolve device serial if not specified
resolve_serial() {
  local devices
  devices=$(adb devices 2>/dev/null | tail -n +2 | grep -v '^$' | awk '{print $1}')
  local count
  count=$(echo "$devices" | grep -c . || true)

  if [ "$count" -eq 0 ]; then
    echo "ERROR: No devices/emulators connected." >&2
    echo "Run 'adb devices' to check, or launch an emulator with emulator-start.sh" >&2
    exit 1
  fi

  if [ -z "$SERIAL" ]; then
    SERIAL=$(echo "$devices" | head -1)
    if [ "$count" -gt 1 ]; then
      echo "NOTE: Multiple devices found. Using $SERIAL (override with -s)" >&2
    fi
  fi
}

resolve_serial

# Device identification
DEVICE_NAME=$(adb_cmd shell getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "unknown")
API_LEVEL=$(adb_cmd shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || echo "unknown")
BUILD_VERSION=$(adb_cmd shell getprop ro.build.version.release 2>/dev/null | tr -d '\r' || echo "unknown")
MANUFACTURER=$(adb_cmd shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r' || echo "unknown")
BOOT_COMPLETED=$(adb_cmd shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "0")
BOOT_ANIM=$(adb_cmd shell getprop init.svc.bootanim 2>/dev/null | tr -d '\r' || echo "unknown")

# Screen info
SCREEN_SIZE=$(adb_cmd shell wm size 2>/dev/null | head -1 | awk '{print $NF}' || echo "unknown")
SCREEN_DENSITY=$(adb_cmd shell wm density 2>/dev/null | head -1 | awk '{print $NF}' || echo "unknown")

# Screen state
SCREEN_STATE=$(adb_cmd shell dumpsys power 2>/dev/null | grep -oP 'mWakefulness=\K\w+' || echo "unknown")

# Battery
BATTERY_LEVEL=$(adb_cmd shell dumpsys battery 2>/dev/null | grep 'level:' | awk '{print $NF}' || echo "unknown")

# Resolve boot status to human-readable
BOOT_STATUS="booting"
if [ "$BOOT_COMPLETED" = "1" ]; then
  BOOT_STATUS="ready"
elif [ "$BOOT_ANIM" = "stopped" ]; then
  BOOT_STATUS="ready"
fi

if $JSON_OUTPUT; then
  cat <<JSON
{
  "serial": "$SERIAL",
  "device_name": "$DEVICE_NAME",
  "manufacturer": "$MANUFACTURER",
  "api_level": $API_LEVEL,
  "build_version": "$BUILD_VERSION",
  "boot_status": "$BOOT_STATUS",
  "screen_size": "$SCREEN_SIZE",
  "screen_density": $SCREEN_DENSITY,
  "screen_state": "$SCREEN_STATE",
  "battery_level": $BATTERY_LEVEL
}
JSON
else
  echo "Device:     $DEVICE_NAME ($MANUFACTURER)"
  echo "Serial:     $SERIAL"
  echo "Android:    $BUILD_VERSION (API $API_LEVEL)"
  echo "Boot:       $BOOT_STATUS"
  echo "Screen:     $SCREEN_SIZE @ ${SCREEN_DENSITY}dpi ($SCREEN_STATE)"
  echo "Battery:    ${BATTERY_LEVEL}%"
fi

# Packages
if [ -n "$PACKAGE_FILTER" ]; then
  echo ""
  echo "Installed packages matching '$PACKAGE_FILTER':"
  adb_cmd shell pm list packages "$PACKAGE_FILTER" 2>/dev/null | sed 's/^package://' | sort || echo "  (none found)"
fi
