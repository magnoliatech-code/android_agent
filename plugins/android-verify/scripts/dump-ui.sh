#!/usr/bin/env bash
set -euo pipefail

# dump-ui.sh — Dump the UI hierarchy from a connected Android device
# Usage: dump-ui.sh [-s serial] [--format text|json|compact]

SERIAL="${ANDROID_SERIAL:-}"
FORMAT="compact"

usage() {
  cat <<EOF
Usage: dump-ui.sh [-s serial] [--format text|json|compact]

  -s serial     Target a specific device (default: first connected)
  --format fmt  Output format:
                  compact  One line per interactive element (default, token-efficient)
                  text     Indented tree with element details
                  json     Structured JSON array of interactive elements
  -h            Show this help
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) SERIAL="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    -h) usage ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [[ ! "$FORMAT" =~ ^(compact|text|json)$ ]]; then
  echo "ERROR: Invalid format '$FORMAT'. Use compact, text, or json." >&2
  exit 1
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

# Dump UI hierarchy
DEVICE_XML="/sdcard/ui_dump_$$.xml"
LOCAL_XML="$(mktemp -t ui_dump.XXXXXX.xml)"

# Clean up on exit
cleanup() {
  adb_cmd shell rm "$DEVICE_XML" 2>/dev/null || true
  rm -f "$LOCAL_XML"
}
trap cleanup EXIT

adb_cmd shell uiautomator dump "$DEVICE_XML" 2>/dev/null
adb_cmd pull "$DEVICE_XML" "$LOCAL_XML" 2>/dev/null

if [ ! -s "$LOCAL_XML" ]; then
  echo "ERROR: Failed to dump UI hierarchy. The app may not have any accessible UI elements." >&2
  exit 1
fi

# --- Parse the XML ---
# We use python3 for reliable XML parsing (available on all modern macOS/Linux).
# Falls back to grep-based extraction if python3 is unavailable.

parse_with_python() {
  python3 -c "
import sys, json, xml.etree.ElementTree as ET

def extract(node, depth=0):
    elements = []
    tag = node.tag
    # Collect useful attributes
    attrs = {
        'text': node.get('text', '').strip(),
        'content-desc': node.get('content-desc', '').strip(),
        'resource-id': node.get('resource-id', ''),
        'class': node.get('class', ''),
        'clickable': node.get('clickable', 'false'),
        'scrollable': node.get('scrollable', 'false'),
        'focused': node.get('focused', 'false'),
        'enabled': node.get('enabled', 'true'),
        'checked': node.get('checked', 'false'),
        'selected': node.get('selected', 'false'),
        'bounds': node.get('bounds', ''),
        'index': node.get('index', ''),
    }
    elements.append({'depth': depth, **attrs})
    for child in node:
        elements.extend(extract(child, depth + 1))
    return elements

try:
    tree = ET.parse('$LOCAL_XML')
    root = tree.getroot()
    all_elements = extract(root)

    if '$FORMAT' == 'compact':
        # One line per interactive or labeled element
        for el in all_elements:
            is_interactive = (
                el['clickable'] == 'true' or
                el['scrollable'] == 'true' or
                el['focused'] == 'true' or
                bool(el['text']) or
                bool(el['content-desc']) or
                el['class'].endswith('EditText') or
                el['class'].endswith('Button') or
                el['class'].endswith('CheckBox') or
                el['class'].endswith('Switch') or
                el['class'].endswith('ImageView')
            )
            if not is_interactive:
                continue

            # Build compact description
            parts = []
            # Interactive flags
            flags = []
            if el['clickable'] == 'true': flags.append('clickable')
            if el['scrollable'] == 'true': flags.append('scrollable')
            if el['focused'] == 'true': flags.append('focused')
            if el['enabled'] == 'false': flags.append('disabled')
            if el['checked'] == 'true': flags.append('checked')
            if el['selected'] == 'true': flags.append('selected')
            flag_str = ','.join(flags) if flags else '-'

            # Label
            label = el['text'] or el['content-desc'] or ''
            if not label and el['resource-id']:
                label = el['resource-id'].split('/')[-1] if '/' in el['resource-id'] else el['resource-id']

            # Class short name
            cls = el['class'].split('.')[-1] if '.' in el['class'] else el['class']

            line = f\"[{flag_str}] {cls}: \\\"{label}\\\" \"
            if el['resource-id']:
                line += f\"id={el['resource-id']} \"
            if el['bounds']:
                line += f\"bounds={el['bounds']}\"

            print(line)

    elif '$FORMAT' == 'json':
        print(json.dumps(all_elements, indent=2))

    elif '$FORMAT' == 'text':
        for el in all_elements:
            indent = '  ' * el['depth']
            label = el['text'] or el['content-desc'] or '-'
            cls = el['class'].split('.')[-1] if '.' in el['class'] else el['class']
            flags = []
            if el['clickable'] == 'true': flags.append('C')
            if el['scrollable'] == 'true': flags.append('S')
            if el['focused'] == 'true': flags.append('F')
            flag_str = '[' + ''.join(flags) + ']' if flags else ''
            id_part = f' id={el[\"resource-id\"]}' if el['resource-id'] else ''
            bounds_part = f' {el[\"bounds\"]}' if el['bounds'] else ''
            print(f'{indent}{cls}{flag_str} \"{label}\"{id_part}{bounds_part}')

except Exception as e:
    print(f'ERROR parsing UI XML: {e}', file=sys.stderr)
    sys.exit(1)
"
}

parse_fallback() {
  # Grep-based fallback: extract clickable elements and those with text
  # Less reliable but works without python3
  echo "NOTE: Using grep-based parsing (install python3 for better results)" >&2
  grep -oP '<[^>]*(?:clickable="true"|text="[^"]+"|content-desc="[^"]+"|class="[^"]*(?:Button|EditText|CheckBox|Switch|ImageView)[^"]*")[^>]*>' "$LOCAL_XML" 2>/dev/null | \
    sed 's/<node//; s/\/>$//' | \
    while read -r line; do
      text=$(echo "$line" | grep -oP 'text="[^"]*"' | head -1 | sed 's/text="//;s/"$//')
      desc=$(echo "$line" | grep -oP 'content-desc="[^"]*"' | head -1 | sed 's/content-desc="//;s/"$//')
      rid=$(echo "$line" | grep -oP 'resource-id="[^"]*"' | head -1 | sed 's/resource-id="//;s/"$//')
      cls=$(echo "$line" | grep -oP 'class="[^"]*"' | head -1 | sed 's/class="//;s/"$//' | sed 's/.*\.//')
      bounds=$(echo "$line" | grep -oP 'bounds="[^"]*"' | head -1 | sed 's/bounds="//;s/"$//')
      clickable=$(echo "$line" | grep -oP 'clickable="[^"]*"' | head -1 | sed 's/clickable="//;s/"$//')
      scrollable=$(echo "$line" | grep -oP 'scrollable="[^"]*"' | head -1 | sed 's/scrollable="//;s/"$//')

      flags=""
      [ "$clickable" = "true" ] && flags="${flags}clickable,"
      [ "$scrollable" = "true" ] && flags="${flags}scrollable,"
      flags="${flags%,}"
      [ -z "$flags" ] && flags="-"

      label="${text:-${desc:-${rid:-}}}"
      [ -z "$label" ] && label="-"

      echo "[$flags] $cls: \"$label\" id=$rid bounds=$bounds"
    done || echo "(unable to parse UI hierarchy)"
}

if command -v python3 &>/dev/null; then
  parse_with_python
else
  parse_fallback
fi
