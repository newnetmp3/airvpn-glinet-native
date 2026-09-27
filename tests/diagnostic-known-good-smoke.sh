#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/airvpn-known-good-test.$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
STATE="$TMP/state"
CACHE_DIR="$STATE/cache"
mkdir -p "$CACHE_DIR"
CFG='airvpn_native.main'
API_KEY='test-key'
RESOLVED_DEVICE_ID='device-id-123'
RESOLVED_DEVICE_NAME='GLinet'
REQUEST_LOG="$TMP/requests"
: >"$REQUEST_LOG"

. "$ROOT/pkg/data/usr/lib/airvpn-native/catalog.sh"
. "$ROOT/pkg/data/usr/lib/airvpn-native/generator.sh"

need_key() { API_KEY='test-key'; return 0; }
airvpn_key_fingerprint() { echo fingerprint-test; }
get() {
  case "$1" in
    protocol) echo wg_manual ;;
    device) echo GLinet ;;
    resolve) echo off ;;
    ip_layer) echo ipv4 ;;
    generator_strategy) echo adaptive ;;
    *) echo '' ;;
  esac
}
discover_selector() { echo "$1"; }
resolve_airvpn_device() { RESOLVED_DEVICE_ID='device-id-123'; RESOLVED_DEVICE_NAME='GLinet'; return 0; }
show_generator_error() { :; }

# Diagnostic winner selection prefers the fastest successful HEADER transport,
# even if a query-key variant happens to measure slightly faster.
CAND="$TMP/candidates.tsv"
printf 'query\tid\t40\nheader\tid\t310\nheader\tname\t120\nboth\tid\t60\n' >"$CAND"
sel="$(select_and_save_diagnostic_known_good "$CAND" wg_diag ipv4 off)"
[ "$sel" = 'header|name|120' ] || { echo "FAIL expected header/name diagnostic winner, got $sel" >&2; exit 1; }

# Add Server must try that exact recipe first and return after one request.
generator_request() {
  # selector|protocol|device|resolve|layer|max|connect|auth
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$1" "$3" "$4" "$5" "$6" "$7" "$8" "$9" >>"$REQUEST_LOG"
  printf '[Interface]\nPrivateKey=x\n[Peer]\nPublicKey=y\n' >"$2"
  return 0
}
if ! generate_one Vega "$TMP/vega.conf" >/dev/null 2>&1; then
  echo 'FAIL known-good generate_one failed' >&2; exit 1
fi
[ "$(wc -l <"$REQUEST_LOG" | tr -d ' ')" = 1 ] || { echo 'FAIL known-good path did not skip fallback matrix' >&2; cat "$REQUEST_LOG" >&2; exit 1; }
line="$(cat "$REQUEST_LOG")"
case "$line" in
  'Vega|wg_diag|GLinet|off|ipv4|'*'|header') ;;
  *) echo "FAIL Add Server did not use diagnostic recipe: $line" >&2; exit 1;;
esac

# Once verified by Add Server, the recipe remains persisted with refreshed timing.
kg="$(load_known_good_generator)"
case "$kg" in
  'header|name|wg_diag|ipv4|off|'*'|add-server-verified') ;;
  *) echo "FAIL refreshed known-good recipe unexpected: $kg" >&2; exit 1;;
esac

# If no header transport succeeds, the fastest diagnostic-proven fallback is
# allowed to be persisted rather than discarding a configuration that works.
rm -f "$(known_good_generator_file)"
printf 'query\tid\t150\nboth\tid\t220\n' >"$CAND"
sel="$(select_and_save_diagnostic_known_good "$CAND" wg_query ipv4 off)"
[ "$sel" = 'query|id|150' ] || { echo "FAIL query-only diagnostic fallback selection: $sel" >&2; exit 1; }

# Retained diagnostic output should bootstrap the known-good request path.
rm -f "$(known_good_generator_file)"
mkdir -p "$STATE/diagjobs/diag-100-1"
cat >"$STATE/diagjobs/diag-100-1/output" <<'EOF'
AirVPN Generator Diagnostic v0.11.4
API key fingerprint: fingerprint-test
Generator parameters: server='Rigel' protocol='wg_old' layer='ipv4' resolve='off'
Successful diagnostic variants: header-id,query-id,both-id,header-name
OVERALL RESULT: PASS
EOF
bootstrap_known_good_from_diagnostics >/dev/null
kg="$(load_known_good_generator)"
[ "$kg" = 'header|id|wg_old|ipv4|off|0|diagnostic-history' ] || { echo "FAIL 0.11.4 diagnostic bootstrap: $kg" >&2; exit 1; }

# Explicit cache clearing must not silently resurrect an old diagnostic job.
clear_cache >/dev/null
[ ! -e "$(known_good_generator_file)" ] || { echo 'FAIL clear_cache left known-good recipe behind' >&2; exit 1; }
if bootstrap_known_good_from_diagnostics >/dev/null 2>&1; then
  echo 'FAIL clear_cache allowed old diagnostic recipe to bootstrap again' >&2; exit 1
fi

echo 'PASS Generator Diagnostic known-good fast-path contract'