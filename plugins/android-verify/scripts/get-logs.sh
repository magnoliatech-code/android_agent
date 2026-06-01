#!/usr/bin/env bash
set -euo pipefail

# get-logs.sh — Capture filtered logcat output from a connected Android device
# Usage: get-logs.sh [-s serial] [-p package] [-l level] [-t tag] [-n lines] [-f]

SERIAL="${ANDROID_SERIAL:-}"
PACKAGE=""
LOG_LEVEL="I"    # Default: Info and above
TAG_FILTER=""
NUM_LINES=200
FOLLOW=false
CLEAR_FIRST=true

usage() {
  cat <<EOF
Usage: get-logs.sh [-s serial] [-p package] [-l level] [-t tag] [-n lines] [-f]

  -s serial   Target a specific device (default: first connected)
  -p package  Filter logs by package name (resolves to PID automatically)
  -l level    Minimum log level: V(erbose), D(ebug), I(nfo), W(arning), E(rror), F(atal)
              Default: I
  -t tag      Filter by log tag (e.g., "ActivityManager")
  -n lines    Show last N lines (default: 200; ignored with -f)
  -f          Follow/tail mode — stream logs until interrupted
  --no-clear  Don't clear the log buffer before capturing
  -h          Show this help
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) SERIAL="$2"; shift 2 ;;
    -p) PACKAGE="$2"; shift 2 ;;
    -l) LOG_LEVEL="$2"; shift 2 ;;
    -t) TAG_FILTER="$2"; shift 2 ;;
    -n) NUM_LINES="$2"; shift 2 ;;
    -f) FOLLOW=true; shift ;;
    --no-clear) CLEAR_FIRST=false; shift ;;
    -h) usage ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
  esac
done

# Validate log level
case "$LOG_LEVEL" in
  V|v) LOG_LEVEL="V" ;;
  D|d) LOG_LEVEL="D" ;;
  I|i) LOG_LEVEL="I" ;;
  W|w) LOG_LEVEL="W" ;;
  E|e) LOG_LEVEL="E" ;;
  F|f) LOG_LEVEL="F" ;;
  *)
    echo "ERROR: Invalid log level '$LOG_LEVEL'. Use V, D, I, W, E, or F." >&2
    exit 1
    ;;
esac

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

# Resolve package to PID
PID=""
if [ -n "$PACKAGE" ]; then
  PID=$(adb_cmd shell pidof "$PACKAGE" 2>/dev/null | tr -d '\r' | awk '{print $1}' || echo "")
  if [ -z "$PID" ]; then
    # Package not currently running — still try to filter by PID if it starts
    echo "NOTE: Package '$PACKAGE' is not currently running. Logs will show if it starts." >&2
  else
    echo "Package: $PACKAGE (PID: $PID)" >&2
  fi
fi

# Clear buffer
if $CLEAR_FIRST && ! $FOLLOW; then
  adb_cmd logcat -c 2>/dev/null || true
fi

# Build logcat command
LOGCAT_ARGS=("-v" "time")

if [ -n "$PID" ]; then
  LOGCAT_ARGS+=("--pid=$PID")
fi

if $FOLLOW; then
  # Continuous tail mode
  echo "Streaming logs (Ctrl+C to stop)..." >&2
  if $CLEAR_FIRST; then
    adb_cmd logcat -c 2>/dev/null || true
  fi
  exec adb_cmd logcat "${LOGCAT_ARGS[@]}" "*:$LOG_LEVEL"
else
  # Dump mode
  OUTPUT=$(adb_cmd logcat -d "${LOGCAT_ARGS[@]}" "*:$LOG_LEVEL" 2>/dev/null)

  LINES_TOTAL=$(echo "$OUTPUT" | grep -c . || echo "0")

  # Apply tag filter if specified
  if [ -n "$TAG_FILTER" ]; then
    OUTPUT=$(echo "$OUTPUT" | grep -i "$TAG_FILTER" || echo "")
  fi

  # Limit to last N lines
  OUTPUT=$(echo "$OUTPUT" | tail -n "$NUM_LINES" || echo "")

  LINES_SHOWN=$(echo "$OUTPUT" | grep -c . || echo "0")

  if [ "$LINES_SHOWN" -eq 0 ] && [ "$LINES_TOTAL" -eq 0 ]; then
    echo "(no log entries at level $LOG_LEVEL or above)"
  elif [ "$LINES_SHOWN" -eq 0 ]; then
    echo "(no matching log entries)"
  else
    echo "$OUTPUT"
    echo ""
    echo "--- Showing $LINES_SHOWN of $LINES_TOTAL entries (level: >=$LOG_LEVEL) ---"
  fi
fi
