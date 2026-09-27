#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
UI="$HERE/pkg/data/www/airvpn-native-ui.js"
PATCH="$HERE/pkg/data/usr/bin/airvpn-ui-patch"
CSS="$HERE/pkg/data/www/airvpn-native-ui.css"

grep -q "airvpn-sidebar-item" "$UI"
grep -q "airvpn-sidebar-view" "$UI"
grep -q "VPN Client Profile','VPN Dashboard','VPN Client" "$UI"
grep -q "showAirSidebar" "$UI"
grep -q "sidebarNavigationCapture" "$UI"
grep -q "menuContextScore" "$UI"
grep -q "syncSidebarRowPlacement" "$UI"
grep -q "primarySidebarContainer" "$UI"
grep -q "adminHeaderBounds" "$UI"
grep -q "airvpnPageBounds" "$UI"
grep -q "INTERNET','WIRELESS','CLIENTS','NETWORK','SYSTEM" "$UI"
grep -q "setInterval(tick,750)" "$UI"
grep -q "removeAttribute('href')" "$UI"
grep -q "z-index:2147482000" "$CSS"
grep -q "airvpn-native-ui.css?v=" "$UI"
grep -q "LOADER_VERSION=205" "$PATCH"
grep -q '/cgi-bin/airvpn-native-ui?v=${LOADER_VERSION}-' "$PATCH"
grep -Fq 's.dataset.airvpnLoader=\"${LOADER_VERSION}\"' "$PATCH"

if grep -q "r.left<=40" "$UI"; then
  echo "FAIL sidebar geometry still assumes a left-aligned app shell" >&2
  exit 1
fi
if grep -q "r.left>Math.min(420,vw\*.36)" "$UI"; then
  echo "FAIL sidebar discovery still rejects centered layouts" >&2
  exit 1
fi
if grep -q "if(!isVisible(e))continue" "$UI"; then
  echo "FAIL hidden VPN submenu rows cannot be discovered on cold load" >&2
  exit 1
fi
if grep -q 'airvpn-provider-tab' "$UI" || grep -q 'function cloneTab' "$UI" || grep -q 'function selector()' "$UI" || grep -q 'hideStock' "$UI"; then
  echo "FAIL legacy provider-tab integration is still present" >&2
  exit 1
fi

node --check "$UI" >/dev/null

echo "PASS dedicated VPN sidebar UI contract"