#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/airvpn-adaptive-test.$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
STATE="$TMP/state"
CACHE_DIR="$STATE/cache"
mkdir -p "$CACHE_DIR"
CFG='airvpn_native.main'

# Only the cache/performance helpers and generator orchestrator are exercised.
. "$ROOT/pkg/data/usr/lib/airvpn-native/catalog.sh"
. "$ROOT/pkg/data/usr/lib/airvpn-native/generator.sh"

record_generator_performance 'wg_a|ipv4|off' success 1500
record_generator_performance 'wg_b|ipv4|off' success 700
best="$(fastest_generator_attempt | cut -f1)"
[ "$best" = 'wg_b|ipv4|off' ] || { echo "FAIL fastest expected wg_b, got $best" >&2; exit 1; }

# Normal Add-server timeouts are derived from learned successful timings: fast
# methods get a 6s floor, unknown methods get the 8s default, and historically
# slower successful methods are capped at 15s rather than the old 30s.
[ "$(generator_timeout_for_attempt 'wg_b|ipv4|off')" = '6' ] || { echo 'FAIL fast adaptive timeout was not 6s' >&2; exit 1; }
[ "$(generator_timeout_for_attempt 'wg_unknown|ipv4|off')" = '8' ] || { echo 'FAIL unknown adaptive timeout was not 8s' >&2; exit 1; }
record_generator_performance 'wg_long|ipv4|off' success 6000
[ "$(generator_timeout_for_attempt 'wg_long|ipv4|off')" = '15' ] || { echo 'FAIL adaptive timeout did not cap at 15s' >&2; exit 1; }

# A latest failure demotes the formerly-fastest method immediately.
record_generator_performance 'wg_b|ipv4|off' failure 125
best="$(fastest_generator_attempt | cut -f1)"
[ "$best" = 'wg_a|ipv4|off' ] || { echo "FAIL failed fastest was not demoted: $best" >&2; exit 1; }

# A later successful observation makes the method eligible again.
record_generator_performance 'wg_b|ipv4|off' success 600
best="$(fastest_generator_attempt | cut -f1)"
[ "$best" = 'wg_b|ipv4|off' ] || { echo "FAIL recovered fastest not selected: $best" >&2; exit 1; }

# Old per-selector success files bootstrap adaptive mode when timing data is absent.
rm -f "$(generator_performance_file)"
save_cached_attempt Alpha wg_old ipv4 off
save_cached_attempt Bravo wg_common ipv4 off
save_cached_attempt Charlie wg_common ipv4 off
boot="$(most_common_cached_attempt)"
[ "$boot" = 'wg_common|ipv4|off' ] || { echo "FAIL legacy bootstrap expected wg_common, got $boot" >&2; exit 1; }

# Verify generate_one actually tries the globally learned fastest method first,
# then learns the successful fallback when that method fails.
rm -rf "$CACHE_DIR"; mkdir -p "$CACHE_DIR"
record_generator_performance 'wg_fast|ipv4|off' success 100
record_generator_performance 'wg_slow|ipv4|off' success 300
RESOLVED_DEVICE_ID='device-test'
STRATEGY='adaptive'
REQUEST_LOG="$TMP/requests"
: >"$REQUEST_LOG"
get() {
  case "$1" in
    protocol) echo wg_slow ;;
    device) echo default ;;
    resolve) echo off ;;
    ip_layer) echo ipv4 ;;
    generator_strategy) echo "$STRATEGY" ;;
    *) echo '' ;;
  esac
}
discover_selector() { echo "$1"; }
resolve_airvpn_device() { RESOLVED_DEVICE_ID='device-test'; return 0; }
generator_request() {
  # args: selector out protocol device resolve layer
  combo="$3|$6|$5"
  echo "$combo" >>"$REQUEST_LOG"
  if [ "$3" = wg_fast ]; then return 10; fi
  : >"$2"
  return 0
}
show_generator_error() { :; }

if ! generate_one Delta "$TMP/delta.conf" >/dev/null 2>&1; then
  echo 'FAIL adaptive generate_one did not fall back successfully' >&2; exit 1
fi
first="$(sed -n '1p' "$REQUEST_LOG")"
second="$(sed -n '2p' "$REQUEST_LOG")"
[ "$first" = 'wg_fast|ipv4|off' ] || { echo "FAIL adaptive fastest not first: $first" >&2; exit 1; }
[ "$second" = 'wg_slow|ipv4|off' ] || { echo "FAIL configured fallback not second: $second" >&2; exit 1; }
newbest="$(fastest_generator_attempt | cut -f1)"
[ "$newbest" = 'wg_slow|ipv4|off' ] || { echo "FAIL successful fallback was not promoted: $newbest" >&2; exit 1; }

# Explicit preferred strategy preserves manual ordering even when adaptive history exists.
rm -f "$(cache_file_for_selector Echo)"
STRATEGY='preferred'
: >"$REQUEST_LOG"
generator_request() { echo "$3|$6|$5" >>"$REQUEST_LOG"; : >"$2"; return 0; }
if ! generate_one Echo "$TMP/echo.conf" >/dev/null 2>&1; then
  echo 'FAIL preferred generate_one failed' >&2; exit 1
fi
first="$(sed -n '1p' "$REQUEST_LOG")"
[ "$first" = 'wg_slow|ipv4|off' ] || { echo "FAIL preferred strategy did not honor configured method first: $first" >&2; exit 1; }

# A transport timeout must fail fast instead of trying every configuration
# against the same unavailable/slow generator endpoint.
rm -rf "$CACHE_DIR"; mkdir -p "$CACHE_DIR"
record_generator_performance 'wg_timeout|ipv4|off' success 100
STRATEGY='adaptive'
: >"$REQUEST_LOG"
generator_request() { echo "$3|$6|$5|timeout=$7" >>"$REQUEST_LOG"; return 14; }
if generate_one Foxtrot "$TMP/foxtrot.conf" >/dev/null 2>&1; then
  echo 'FAIL transport timeout unexpectedly succeeded' >&2; exit 1
else
  rc=$?
fi
[ "$rc" -eq 14 ] || { echo "FAIL transport timeout returned $rc instead of 14" >&2; exit 1; }
[ "$(wc -l <"$REQUEST_LOG" | tr -d ' ')" = '1' ] || { echo 'FAIL transport timeout continued into fallback attempts' >&2; cat "$REQUEST_LOG" >&2; exit 1; }
[ "$(cut -d'|' -f4 "$REQUEST_LOG")" = 'timeout=6' ] || { echo 'FAIL learned fast method did not receive 6s ceiling' >&2; cat "$REQUEST_LOG" >&2; exit 1; }

echo 'PASS adaptive generator performance contract'