#!/usr/bin/env bash
set -euo pipefail

# tap.sh — Tap on the screen by coordinates or by element specification
# Usage: tap.sh <x> <y> [-s serial]
#        tap.sh --text "Login" [-s serial]
#        tap.sh --id "com.example:id/btn" [-s serial]
#        tap.sh --desc "Search" [-s serial]

SERIAL="${ANDROID_SERIAL:-}"
MODE="coords"
COORD_X=""
COORD_Y=""
SEARCH_TEXT=""
SEARCH_ID=""
SEARCH_DESC=""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage: tap.sh <x> <y> [-s serial]
       tap.sh --text <text> [-s serial]
       tap.sh --id <resource-id> [-s serial]
       tap.sh --desc <content-desc> [-s serial]

  x y           Tap at screen coordinates
  --text text   Find element by text and tap its center
  --id id       Find element by resource-id and tap its center
  --desc desc   Find element by content-description and tap its center
  -s serial     Target a specific device (default: first connected)
  -h            Show this help
EOF
  exit 0
}

# Parse args
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --text) MODE="element"; SEARCH_TEXT="$2"; shift 2 ;;
    --id) MODE="element"; SEARCH_ID="$2"; shift 2 ;;
    --desc) MODE="element"; SEARCH_DESC="$2"; shift 2 ;;
    -s) SERIAL="$2"; shift 2 ;;
    -h) usage ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

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

if [ "$MODE" = "coords" ]; then
  if [ ${#POSITIONAL[@]} -lt 2 ]; then
    echo "ERROR: Coordinates required (x y) or use --text/--id/--desc." >&2
    usage
  fi
  COORD_X="${POSITIONAL[0]}"
  COORD_Y="${POSITIONAL[1]}"
else
  # Element mode: find element first
  FIND_ARGS=()
  [ -n "$SERIAL" ] && FIND_ARGS+=(-s "$SERIAL")
  [ -n "$SEARCH_TEXT" ] && FIND_ARGS+=(--text "$SEARCH_TEXT")
  [ -n "$SEARCH_ID" ] && FIND_ARGS+=(--id "$SEARCH_ID")
  [ -n "$SEARCH_DESC" ] && FIND_ARGS+=(--desc "$SEARCH_DESC")

  FIND_OUTPUT=$("$SCRIPT_DIR/find-element.sh" "${FIND_ARGS[@]}" 2>&1)
  FIND_EXIT=$?

  if [ $FIND_EXIT -ne 0 ]; then
    echo "ERROR: Element not found." >&2
    echo "$FIND_OUTPUT" >&2
    exit 1
  fi

  # Extract center coordinates from find-element output
  # Last line format: "  → tap coordinates: <cx> <cy>"
  COORDS=$(echo "$FIND_OUTPUT" | grep 'tap coordinates:' | tail -1 | awk '{print $NF}' | tr -d '()')
  COORD_X=$(echo "$COORDS" | awk '{print $1}')
  COORD_Y=$(echo "$COORDS" | awk '{print $2}')

  if [ -z "$COORD_X" ] || [ -z "$COORD_Y" ]; then
    echo "ERROR: Could not determine tap coordinates from element." >&2
    echo "$FIND_OUTPUT" >&2
    exit 1
  fi

  # Show what we're tapping
  echo "$FIND_OUTPUT" | head -1
fi

# Perform the tap
echo "Tapping at ($COORD_X, $COORD_Y)..."
adb_cmd shell input tap "$COORD_X" "$COORD_Y"

echo "Tap complete."
