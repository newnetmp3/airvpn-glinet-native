#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/airvpn-generator-timeout-test.$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP"
STATE="$TMP/state"; mkdir -p "$STATE"
API='https://example.invalid/api'
API_KEY='test-key'
CURL_LOG="$TMP/curl-args"

. "$ROOT/pkg/data/usr/lib/airvpn-native/generator.sh"
need_key() { API_KEY='test-key'; return 0; }
auth_response_rejected() { return 1; }
normalize_generator_output() { cp "$1" "$2"; return 0; }

curl() {
  printf '%s\n' "$*" >"$CURL_LOG"
  out=''; hdr=''; prev=''
  for arg in "$@"; do
    if [ "$prev" = '-o' ]; then out="$arg"; fi
    if [ "$prev" = '-D' ]; then hdr="$arg"; fi
    prev="$arg"
  done
  [ -n "$out" ] && printf '[Interface]\nPrivateKey=x\n[Peer]\nPublicKey=y\n' >"$out"
  [ -n "$hdr" ] && printf 'HTTP/1.1 200 OK\n' >"$hdr"
  printf '200'
  return 0
}

out="$TMP/profile"
generator_request Alpha "$out" wg device off ipv4 7 3
case "$(cat "$CURL_LOG")" in
  *'--connect-timeout 3 --max-time 7'*) ;;
  *) echo 'FAIL generator_request did not pass requested short curl ceilings' >&2; cat "$CURL_LOG" >&2; exit 1;;
esac

curl() { printf '%s\n' "$*" >"$CURL_LOG"; return 28; }
if generator_request Alpha "$out" wg device off ipv4 6 3; then
  echo 'FAIL curl timeout unexpectedly succeeded' >&2; exit 1
else
  rc=$?
fi
[ "$rc" -eq 14 ] || { echo "FAIL curl timeout mapped to $rc instead of 14" >&2; exit 1; }

echo 'PASS generator request timeout contract'