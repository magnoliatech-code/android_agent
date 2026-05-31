#!/usr/bin/env bash
set -euo pipefail

# find-element.sh — Find UI elements by text, resource-id, or content-description
# Usage: find-element.sh --text "Login" [--exact] [-s serial]
#        find-element.sh --id "com.example:id/btn" [-s serial]
#        find-element.sh --desc "Search" [-s serial]

SERIAL="${ANDROID_SERIAL:-}"
SEARCH_TEXT=""
SEARCH_ID=""
SEARCH_DESC=""
EXACT_MATCH=false
MULTI_MODE=false  # Return all matches, not just first

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage: find-element.sh (--text <text> | --id <id> | --desc <desc>) [-s serial] [--exact] [--all]

  --text <text>   Find element by text content (substring match)
  --id <id>       Find element by resource-id (exact match)
  --desc <desc>   Find element by content-description (substring match)
  -s serial       Target a specific device (default: first connected)
  --exact         Require exact match for text/desc
  --all           Return all matching elements (default: first match only)
  --json          Output as JSON
  -h              Show this help
EOF
  exit 0
}

JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text) SEARCH_TEXT="$2"; shift 2 ;;
    --id) SEARCH_ID="$2"; shift 2 ;;
    --desc) SEARCH_DESC="$2"; shift 2 ;;
    -s) SERIAL="$2"; shift 2 ;;
    --exact) EXACT_MATCH=true; shift ;;
    --all) MULTI_MODE=true; shift ;;
    --json) JSON_OUTPUT=true; shift ;;
    -h) usage ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [ -z "$SEARCH_TEXT" ] && [ -z "$SEARCH_ID" ] && [ -z "$SEARCH_DESC" ]; then
  echo "ERROR: Must specify one of --text, --id, or --desc." >&2
  usage
fi

# Determine search mode
SEARCH_MODE=""
SEARCH_VALUE=""
if [ -n "$SEARCH_ID" ]; then
  SEARCH_MODE="id"
  SEARCH_VALUE="$SEARCH_ID"
elif [ -n "$SEARCH_TEXT" ]; then
  SEARCH_MODE="text"
  SEARCH_VALUE="$SEARCH_TEXT"
else
  SEARCH_MODE="desc"
  SEARCH_VALUE="$SEARCH_DESC"
fi

# Build dump-ui args
DUMP_ARGS=(--format json)
if [ -n "$SERIAL" ]; then
  DUMP_ARGS+=(-s "$SERIAL")
fi

# Get UI hierarchy as JSON
UI_JSON=$("$SCRIPT_DIR/dump-ui.sh" "${DUMP_ARGS[@]}" 2>/dev/null)
DUMP_EXIT=$?

if [ $DUMP_EXIT -ne 0 ]; then
  echo "ERROR: Failed to dump UI hierarchy." >&2
  exit 1
fi

# Search for matches using python3 (or fallback grep on compact output)
if command -v python3 &>/dev/null; then
  python3 -c "
import json, sys

data = json.loads('''$UI_JSON''')
search_mode = '$SEARCH_MODE'
search_value = '''$SEARCH_VALUE'''
exact = '$EXACT_MATCH' == 'true'
multi = '$MULTI_MODE' == 'true'
json_out = '$JSON_OUTPUT' == 'true'

matches = []
for el in data:
    if search_mode == 'id':
        if el['resource-id'] == search_value:
            matches.append(el)
    elif search_mode == 'text':
        if exact:
            if el['text'] == search_value:
                matches.append(el)
        else:
            if search_value.lower() in el['text'].lower():
                matches.append(el)
    elif search_mode == 'desc':
        if exact:
            if el['content-desc'] == search_value:
                matches.append(el)
        else:
            if search_value.lower() in el['content-desc'].lower():
                matches.append(el)

if not matches:
    print(f'No element found matching {search_mode}=\"{search_value}\"')
    sys.exit(1)

if multi:
    results = matches
else:
    results = [matches[0]]

if json_out:
    print(json.dumps(results, indent=2))
else:
    for i, m in enumerate(results):
        text = m['text'] or '-'
        desc = m['content-desc'] or '-'
        rid = m['resource-id'] or '-'
        cls = m['class'].split('.')[-1] if '.' in m['class'] else m['class']
        bounds = m['bounds']

        # Parse bounds to compute center
        # bounds format: [x1,y1][x2,y2]
        import re
        coords = re.findall(r'\d+', bounds)
        if len(coords) == 4:
            cx = (int(coords[0]) + int(coords[2])) // 2
            cy = (int(coords[1]) + int(coords[3])) // 2
        else:
            cx, cy = 0, 0

        if len(results) > 1:
            print(f'[{i}] {cls}: text=\"{text}\" desc=\"{desc}\" id={rid} bounds={bounds} center=({cx},{cy})')
        else:
            print(f'{cls}: text=\"{text}\" desc=\"{desc}\" id={rid} bounds={bounds} center=({cx},{cy})')
        print(f'  → tap coordinates: {cx} {cy}')
"
else
  # Fallback: use compact format with grep
  DUMP_ARGS=(--format compact)
  if [ -n "$SERIAL" ]; then
    DUMP_ARGS+=(-s "$SERIAL")
  fi

  case "$SEARCH_MODE" in
    id)
      "$SCRIPT_DIR/dump-ui.sh" "${DUMP_ARGS[@]}" 2>/dev/null | grep -F "id=$SEARCH_VALUE" || {
        echo "No element found matching id=\"$SEARCH_VALUE\""
        exit 1
      }
      ;;
    text)
      if $EXACT_MATCH; then
        "$SCRIPT_DIR/dump-ui.sh" "${DUMP_ARGS[@]}" 2>/dev/null | grep -F "\"$SEARCH_VALUE\"" || {
          echo "No element found matching text=\"$SEARCH_VALUE\""
          exit 1
        }
      else
        "$SCRIPT_DIR/dump-ui.sh" "${DUMP_ARGS[@]}" 2>/dev/null | grep -i "$SEARCH_VALUE" || {
          echo "No element found matching text=\"$SEARCH_VALUE\""
          exit 1
        }
      fi
      ;;
    desc)
      "$SCRIPT_DIR/dump-ui.sh" "${DUMP_ARGS[@]}" 2>/dev/null | grep -i "$SEARCH_VALUE" || {
        echo "No element found matching desc=\"$SEARCH_VALUE\""
        exit 1
      }
      ;;
  esac
fi
