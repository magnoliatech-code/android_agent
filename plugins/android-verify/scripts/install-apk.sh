#!/usr/bin/env bash
set -euo pipefail

# install-apk.sh — Install an APK to a connected Android device/emulator
# Usage: install-apk.sh <apk_path> [-s serial] [-r] [-g] [--no-verify]

SERIAL="${ANDROID_SERIAL:-}"
REINSTALL=true
GRANT_PERMISSIONS=true
VERIFY_INSTALL=true
APK_PATH=""

usage() {
  cat <<EOF
Usage: install-apk.sh <apk_path> [-s serial] [-r] [-g] [--no-verify]

  apk_path    Path to the APK file to install
  -s serial   Target a specific device (default: first connected)
  -r          Do NOT reinstall if app already exists
  -g          Do NOT auto-grant permissions
  --no-verify Skip post-install verification
  -h          Show this help
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) SERIAL="$2"; shift 2 ;;
    -r) REINSTALL=false; shift ;;
    -g) GRANT_PERMISSIONS=false; shift ;;
    --no-verify) VERIFY_INSTALL=false; shift ;;
    -h) usage ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
    *)
      if [ -z "$APK_PATH" ]; then
        APK_PATH="$1"
        shift
      else
        echo "ERROR: Unexpected argument: $1" >&2
        usage
      fi
      ;;
  esac
done

if [ -z "$APK_PATH" ]; then
  echo "ERROR: APK path is required." >&2
  usage
fi

if [ ! -f "$APK_PATH" ]; then
  echo "ERROR: APK file not found: $APK_PATH" >&2
  exit 1
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
    echo "Launch an emulator first with: emulator-start.sh" >&2
    exit 1
  fi

  if [ -z "$SERIAL" ]; then
    SERIAL=$(echo "$devices" | head -1)
  fi
}

resolve_serial

# --- Get APK info ---
PACKAGE_NAME=""
if command -v aapt &>/dev/null; then
  PACKAGE_NAME=$(aapt dump badging "$APK_PATH" 2>/dev/null | grep "^package:" | sed "s/.*name='\([^']*\)'.*/\1/" || echo "")
elif command -v aapt2 &>/dev/null; then
  PACKAGE_NAME=$(aapt2 dump packagename "$APK_PATH" 2>/dev/null || echo "")
fi

if [ -z "$PACKAGE_NAME" ]; then
  # Try to get package name from the APK filename or skip
  PACKAGE_NAME="<unknown>"
fi

echo "APK:     $APK_PATH"
echo "Package: $PACKAGE_NAME"
echo "Device:  $SERIAL"

# --- Check if already installed ---
INSTALLED=false
if adb_cmd shell pm list packages "$PACKAGE_NAME" 2>/dev/null | grep -q "$PACKAGE_NAME"; then
  INSTALLED=true
fi

# --- Build install flags ---
INSTALL_FLAGS=""
if $REINSTALL && $INSTALLED; then
  INSTALL_FLAGS="$INSTALL_FLAGS -r"
fi
if $GRANT_PERMISSIONS; then
  INSTALL_FLAGS="$INSTALL_FLAGS -g"
fi

# For large APKs, push first then use pm install
APK_SIZE=$(stat -f%z "$APK_PATH" 2>/dev/null || stat -c%s "$APK_PATH" 2>/dev/null || echo "0")

if [ "$APK_SIZE" -gt 500000000 ] 2>/dev/null; then
  # Large APK: push then install via shell
  echo "Large APK detected (${APK_SIZE} bytes). Using push+pm method..."
  REMOTE_PATH="/data/local/tmp/$(basename "$APK_PATH")"
  adb_cmd push "$APK_PATH" "$REMOTE_PATH"

  if $INSTALLED && $REINSTALL; then
    OUTPUT=$(adb_cmd shell pm install $INSTALL_FLAGS "$REMOTE_PATH" 2>&1) || INSTALL_EXIT=$?
  else
    OUTPUT=$(adb_cmd shell pm install $INSTALL_FLAGS "$REMOTE_PATH" 2>&1) || INSTALL_EXIT=$?
  fi
  adb_cmd shell rm "$REMOTE_PATH" 2>/dev/null || true
else
  # Standard install
  OUTPUT=$(adb_cmd install $INSTALL_FLAGS "$APK_PATH" 2>&1) || INSTALL_EXIT=$?
fi

INSTALL_EXIT=${INSTALL_EXIT:-$?}

echo ""
echo "$OUTPUT"

# --- Check result ---
if [ "$INSTALL_EXIT" -ne 0 ]; then
  echo ""
  echo "Installation FAILED."

  # Diagnose common errors
  if echo "$OUTPUT" | grep -q "NO_MATCHING_ABIS"; then
    echo "CAUSE: APK architecture doesn't match the emulator."
    echo "FIX: Build the APK for x86_64 (emulator) or use an arm-compatible emulator image."
  elif echo "$OUTPUT" | grep -q "INSTALL_FAILED_INSUFFICIENT_STORAGE"; then
    echo "CAUSE: Not enough storage on the emulator."
    echo "FIX: Wipe emulator data or increase its storage partition size."
  elif echo "$OUTPUT" | grep -q "INSTALL_FAILED_UPDATE_INCOMPATIBLE"; then
    echo "CAUSE: Signature mismatch — a different-signed APK is already installed."
    echo "FIX: Uninstall the existing app first: adb uninstall $PACKAGE_NAME"
  elif echo "$OUTPUT" | grep -q "INSTALL_FAILED_USER_RESTRICTED"; then
    echo "CAUSE: User restriction on install."
    echo "FIX: Try: adb install -r -g --user 0 $APK_PATH"
  fi

  exit 1
fi

echo ""
echo "Installation SUCCEEDED."

# --- Verify ---
if $VERIFY_INSTALL && [ "$PACKAGE_NAME" != "<unknown>" ]; then
  if adb_cmd shell pm list packages "$PACKAGE_NAME" 2>/dev/null | grep -q "$PACKAGE_NAME"; then
    echo "Verified: package $PACKAGE_NAME is installed."
  else
    echo "WARNING: Package $PACKAGE_NAME not found in pm list. App may still work." >&2
  fi
fi
