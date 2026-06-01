#!/usr/bin/env bash
set -euo pipefail

# swipe.sh — Perform swipe/scroll gestures on a connected Android device
# Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms] [-s serial]
#        swipe.sh --direction up|down|left|right [--distance px] [-s serial]
#        swipe.sh --text "element" --direction up|down|left|right [-s serial]

SERIAL="${ANDROID_SERIAL:-}"
MODE="coords"
X1="" Y1="" X2="" Y2=""
DIRECTION=""
DISTANCE=500     # Default swipe distance in pixels
DURATION=300     # Default duration in ms
ELEMENT_TEXT=""

usage() {
  cat <<EOF
Usage: swipe.sh <x1> <y1> <x2> <y2> [duration_ms] [-s serial]
       swipe.sh --direction up|down|left|right [--distance px] [--duration ms] [-s serial]
       swipe.sh --text <element> --direction up|down|left|right [-s serial]

  x1 y1 x2 y2   Swipe from (x1,y1) to (x2,y2)
  --direction d  Swipe direction: up, down, left, right (from screen center)
  --distance px  Swipe distance in pixels (default: 500)
  --duration ms  Swipe duration in ms (default: 300; use ~1000 for slow scroll)
  --text text    Find element by text and swipe on it (for scrollable containers)
  -s serial      Target a specific device (default: first connected)
  -h             Show this help
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --direction) DIRECTION="$2"; shift 2 ;;
    --distance) DISTANCE="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --text) ELEMENT_TEXT="$2"; shift 2 ;;
    -s) SERIAL="$2"; shift 2 ;;
    -h) usage ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
    *)
      if [ "$MODE" = "coords" ] && [ -z "$X1" ]; then
        X1="$1"
      elif [ "$MODE" = "coords" ] && [ -z "$Y1" ]; then
        Y1="$1"
      elif [ "$MODE" = "coords" ] && [ -z "$X2" ]; then
        X2="$1"
      elif [ "$MODE" = "coords" ] && [ -z "$Y2" ]; then
        Y2="$1"
      elif [ "$MODE" = "coords" ] && [ -z "$DURATION" ]; then
        DURATION="$1"
      else
        echo "ERROR: Unexpected argument: $1" >&2
        usage
      fi
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

# --- Resolve swipe coordinates ---
if [ -n "$DIRECTION" ]; then
  # Get screen size
  SCREEN_SIZE=$(adb_cmd shell wm size 2>/dev/null | head -1 | awk '{print $NF}' || echo "1080x2400")
  SW=$(echo "$SCREEN_SIZE" | cut -d'x' -f1)
  SH=$(echo "$SCREEN_SIZE" | cut -d'x' -f2)

  # Default: swipe from center
  CX=$((SW / 2))
  CY=$((SH / 2))

  # If swiping on a specific element, get its center
  if [ -n "$ELEMENT_TEXT" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    FIND_OUTPUT=$("$SCRIPT_DIR/find-element.sh" --text "$ELEMENT_TEXT" ${SERIAL:+-s "$SERIAL"} 2>&1)
    COORDS=$(echo "$FIND_OUTPUT" | grep 'tap coordinates:' | tail -1 | grep -oP '\d+ \d+' || echo "")
    if [ -n "$COORDS" ]; then
      CX=$(echo "$COORDS" | awk '{print $1}')
      CY=$(echo "$COORDS" | awk '{print $2}')
    fi
  fi

  case "$DIRECTION" in
    up)
      X1=$CX; Y1=$((CY + DISTANCE / 2))
      X2=$CX; Y2=$((CY - DISTANCE / 2))
      ;;
    down)
      X1=$CX; Y1=$((CY - DISTANCE / 2))
      X2=$CX; Y2=$((CY + DISTANCE / 2))
      ;;
    left)
      X1=$((CX + DISTANCE / 2)); Y1=$CY
      X2=$((CX - DISTANCE / 2)); Y2=$CY
      ;;
    right)
      X1=$((CX - DISTANCE / 2)); Y1=$CY
      X2=$((CX + DISTANCE / 2)); Y2=$CY
      ;;
    *)
      echo "ERROR: Invalid direction '$DIRECTION'. Use up, down, left, or right." >&2
      exit 1
      ;;
  esac

  # Clamp to screen bounds
  [ "$X1" -lt 0 ] && X1=0; [ "$X1" -gt "$SW" ] && X1=$SW
  [ "$Y1" -lt 0 ] && Y1=0; [ "$Y1" -gt "$SH" ] && Y1=$SH
  [ "$X2" -lt 0 ] && X2=0; [ "$X2" -gt "$SW" ] && X2=$SW
  [ "$Y2" -lt 0 ] && Y2=0; [ "$Y2" -gt "$SH" ] && Y2=$SH
fi

if [ -z "$X1" ] || [ -z "$Y1" ] || [ -z "$X2" ] || [ -z "$Y2" ]; then
  echo "ERROR: Must specify either coordinates or --direction." >&2
  usage
fi

echo "Swiping from ($X1,$Y1) to ($X2,$Y2) over ${DURATION}ms..."
adb_cmd shell input swipe "$X1" "$Y1" "$X2" "$Y2" "$DURATION"
echo "Swipe complete."
