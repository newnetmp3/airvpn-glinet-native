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
grep -Fq "ev.target===m||ev.target.closest('[data-server-close]')" "$UI"
grep -q "function updateSelectedServer" "$UI"
grep -q "tr.dataset.serverName=String(r\[0\]||'')" "$UI"
if sed -n '/function refreshVpnPower(){/,/^}/p' "$UI" | grep -q "makeServerTable"; then
  echo "FAIL VPN status polling still rebuilds the server table" >&2
  exit 1
fi
if grep -Fq "var cl=e.target.closest('[data-server-close]')" "$UI"; then
  echo "FAIL server Info close still depends on the panel click delegate" >&2
  exit 1
fi
node --check "$UI" >/dev/null

echo "PASS server action UI contract"