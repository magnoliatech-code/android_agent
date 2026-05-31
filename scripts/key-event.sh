#!/usr/bin/env bash
set -euo pipefail

# key-event.sh — Send key events to a connected Android device
# Usage: key-event.sh <event> [-s serial]
#        key-event.sh --list  (show available keys)

SERIAL="${ANDROID_SERIAL:-}"
EVENT=""

usage() {
  cat <<EOF
Usage: key-event.sh <event> [-s serial]
       key-event.sh --list

  event     Human-readable key name (back, home, enter, volume_up, etc.)
  -s serial Target a specific device (default: first connected)
  --list    List all available key event names
  -h        Show this help
EOF
  exit 0
}

# Show key list
if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
  cat <<EOF
Common key events:
  back          Go back
  home          Go to home screen
  recent        App switcher / recent apps
  menu          Context menu
  search        Search
  enter         Enter / Return
  delete        Delete / Backspace
  tab           Tab
  escape        Escape
  space         Space bar
  dpad_up       D-pad up
  dpad_down     D-pad down
  dpad_left     D-pad left
  dpad_right    D-pad right
  dpad_center   D-pad center / select
  volume_up     Volume up
  volume_down   Volume down
  volume_mute   Mute
  power         Power button
  camera        Camera button
  call          Call button
  endcall       End call
  notification  Open notifications
  media_play    Media play
  media_pause   Media pause
  media_stop    Media stop
  media_next    Next track
  media_prev    Previous track
  media_rewind  Rewind
  media_fast_forward  Fast forward
  paste         Paste from clipboard
  cut           Cut
  copy          Copy
  select_all    Select all
  num_lock      Num lock
  caps_lock     Caps lock
  scroll_lock   Scroll lock
  sleep         Sleep / screen off
  wakeup        Wake up / screen on

Use --list-raw to see numeric keycodes too.
EOF
  exit 0
fi

if [ "${1:-}" = "--list-raw" ]; then
  # Show detailed numeric mapping
  cat <<EOF
Full key event mapping (name → keycode):
  home=3, back=4, call=5, endcall=6
  volume_up=24, volume_down=25, volume_mute=164
  power=26, camera=27, clear=28
  enter=66, delete=67, tab=61, escape=111, space=62
  dpad_up=19, dpad_down=20, dpad_left=21, dpad_right=22, dpad_center=23
  menu=82, search=84, notification=83, recent=187
  media_play=126, media_pause=127, media_stop=86
  media_next=87, media_prev=88, media_rewind=89, media_fast_forward=90
  paste=279, cut=277, copy=278, select_all=280
  sleep=223, wakeup=224
  num_lock=143, caps_lock=115, scroll_lock=116
  page_up=92, page_down=93
  move_home=122, move_end=123
  insert=124, forward_del=112
  num_0=7 through num_9=16
  a=29 through z=54
EOF
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) SERIAL="$2"; shift 2 ;;
    -h) usage ;;
    -*)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
    *)
      EVENT="$1"
      shift
      ;;
  esac
done

if [ -z "$EVENT" ]; then
  echo "ERROR: Key event name is required." >&2
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

# --- Map human name to Android keycode ---
map_keycode() {
  case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    # Navigation
    home)             echo 3 ;;
    back)             echo 4 ;;
    call)             echo 5 ;;
    endcall|end_call) echo 6 ;;
    menu)             echo 82 ;;
    search)           echo 84 ;;
    notification|notifications) echo 83 ;;
    recent|recents|app_switch|app-switch) echo 187 ;;

    # Directional
    dpad_up|up)       echo 19 ;;
    dpad_down|down)   echo 20 ;;
    dpad_left|left)   echo 21 ;;
    dpad_right|right) echo 22 ;;
    dpad_center|center|select) echo 23 ;;

    # Volume
    volume_up|vol_up)   echo 24 ;;
    volume_down|vol_down) echo 25 ;;
    volume_mute|mute)   echo 164 ;;

    # Power
    power)            echo 26 ;;
    camera)           echo 27 ;;
    sleep|screen_off) echo 223 ;;
    wakeup|wake|screen_on) echo 224 ;;

    # Text editing
    enter|return)     echo 66 ;;
    delete|backspace|del) echo 67 ;;
    tab)              echo 61 ;;
    escape|esc)       echo 111 ;;
    space)            echo 62 ;;
    paste)            echo 279 ;;
    cut)              echo 277 ;;
    copy)             echo 278 ;;
    select_all|selectall) echo 280 ;;
    insert)           echo 124 ;;
    forward_del|forward_delete) echo 112 ;;
    move_home)        echo 122 ;;
    move_end)         echo 123 ;;
    page_up)          echo 92 ;;
    page_down)        echo 93 ;;

    # Media
    media_play|play)            echo 126 ;;
    media_pause|pause)          echo 127 ;;
    media_stop|stop)            echo 86 ;;
    media_next|next)            echo 87 ;;
    media_prev|prev|previous)   echo 88 ;;
    media_rewind|rewind)        echo 89 ;;
    media_fast_forward|fast_forward|ff) echo 90 ;;

    # Lock keys
    caps_lock|capslock)   echo 115 ;;
    num_lock|numlock)     echo 143 ;;
    scroll_lock|scrolllock) echo 116 ;;

    # If the input is already a number, use it directly
    [0-9]*) echo "$1" ;;

    *)
      echo "ERROR: Unknown key event '$1'." >&2
      echo "Run 'key-event.sh --list' to see available keys." >&2
      exit 1
      ;;
  esac
}

KEYCODE=$(map_keycode "$EVENT")
echo "Sending key event: $EVENT (keycode $KEYCODE)"
adb_cmd shell input keyevent "$KEYCODE"
echo "Done."
