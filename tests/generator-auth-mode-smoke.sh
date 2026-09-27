#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/airvpn-generator-authmode-test.$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
STATE="$TMP/state"; mkdir -p "$STATE"
CACHE_DIR="$STATE/cache"; mkdir -p "$CACHE_DIR"
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
    [ "$prev" = '-o' ] && out="$arg"
    [ "$prev" = '-D' ] && hdr="$arg"
    prev="$arg"
  done
  [ -n "$out" ] && printf '[Interface]\nPrivateKey=x\n[Peer]\nPublicKey=y\n' >"$out"
  [ -n "$hdr" ] && printf 'HTTP/1.1 200 OK\n' >"$hdr"
  printf '200'
}

out="$TMP/p"
generator_request Alpha "$out" wg device off ipv4 8 4 header
args="$(cat "$CURL_LOG")"
case "$args" in *'-H API-KEY: test-key'*) ;; *) echo 'FAIL header mode omitted API-KEY header' >&2; exit 1;; esac
case "$args" in *'key=test-key'*) echo 'FAIL header mode leaked API key into query' >&2; exit 1;; esac

generator_request Alpha "$out" wg device off ipv4 8 4 query
args="$(cat "$CURL_LOG")"
case "$args" in *'key=test-key'*) ;; *) echo 'FAIL query mode omitted key query parameter' >&2; exit 1;; esac
case "$args" in *'-H API-KEY: test-key'*) echo 'FAIL query mode unexpectedly sent API-KEY header' >&2; exit 1;; esac

generator_request Alpha "$out" wg device off ipv4 8 4 both
args="$(cat "$CURL_LOG")"
case "$args" in *'-H API-KEY: test-key'*'key=test-key'*) ;; *) echo 'FAIL both mode did not send both auth forms' >&2; exit 1;; esac

if generator_request Alpha "$out" wg device off ipv4 8 4 nope >/dev/null 2>&1; then
  echo 'FAIL invalid auth mode unexpectedly accepted' >&2; exit 1
else rc=$?; fi
[ "$rc" -eq 20 ] || { echo "FAIL invalid auth mode rc=$rc" >&2; exit 1; }

echo 'PASS generator auth-mode contract'