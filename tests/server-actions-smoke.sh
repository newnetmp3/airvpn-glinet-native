#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
UI="$HERE/pkg/data/www/airvpn-native-ui.js"
CSS="$HERE/pkg/data/www/airvpn-native-ui.css"

grep -q "infoButton.textContent='Info'" "$UI"
grep -q "actionWrap.appendChild(makeSelectMenu" "$UI"
grep -q "var AV_ACTION_WIDTH=132" "$UI"
grep -q "left:132px!important" "$CSS"

for action in favorite exclude copy country; do
  if grep -q "data-server-action=\\\"$action\\\"" "$UI"; then
    echo "FAIL $action action button is still rendered" >&2
    exit 1
  fi
  if grep -q "action==='${action}'" "$UI"; then
    echo "FAIL dead $action click handler is still present" >&2
    exit 1
  fi
done

if grep -q 'class="avmodalactions".*data-server-action' "$UI"; then
  echo "FAIL server Info dialog still contains action buttons" >&2
  exit 1
fi

grep -q 'data-server-close' "$UI"
node --check "$UI" >/dev/null

echo "PASS server action UI contract"