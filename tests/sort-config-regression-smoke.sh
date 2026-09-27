#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CFG='airvpn_native.main'
LAST_UCI=''
uci() {
  case "$1" in
    set) LAST_UCI="$2"; return 0 ;;
    commit) return 0 ;;
    *) return 0 ;;
  esac
}
. "$ROOT/pkg/data/usr/lib/airvpn-native/config.sh"

setcfg sort_column ''
[ "$LAST_UCI" = 'airvpn_native.main.sort_column=smart_rank' ] || {
  echo "FAIL blank sort column normalized to: $LAST_UCI" >&2; exit 1;
}
setcfg sort_direction ''
[ "$LAST_UCI" = 'airvpn_native.main.sort_direction=desc' ] || {
  echo "FAIL blank sort direction normalized to: $LAST_UCI" >&2; exit 1;
}
if setcfg sort_column definitely_not_a_sort >/dev/null 2>&1; then
  echo 'FAIL invalid non-empty sort column was accepted' >&2; exit 1
fi

JS="$ROOT/pkg/data/www/airvpn-native-ui.js"
grep -Fq "saveConfigOnly({selectors:ta.value})" "$JS" || { echo 'FAIL Add profile still saves full config' >&2; exit 1; }
grep -Fq "saveConfigOnly({sort_column:sc,sort_direction:sd})" "$JS" || { echo 'FAIL sort apply is not a partial persisted update' >&2; exit 1; }
grep -Fq "sort_column:v('avsort')||((A.catalogSort&&A.catalogSort.column)||'smart_rank')" "$JS" || { echo 'FAIL UI sort default is not defensive' >&2; exit 1; }
echo 'PASS sort/config regression contract'