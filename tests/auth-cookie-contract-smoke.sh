#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/pkg/data/usr/lib/airvpn-native/http-auth.sh"

expect() {
	cookie="$1" expected="$2"
	got="$(airvpn_admin_token_from_cookie "$cookie")"
	[ "$got" = "$expected" ] || { echo "FAIL cookie parse: $got != $expected" >&2; exit 1; }
}
expect 'Admin-Token=abc123_XY-9' 'abc123_XY-9'
expect 'QSESSIONID=deadbeef; Admin-Token=A1b2C3d4; theme=dark' 'A1b2C3d4'
expect 'foo=1;Admin-Token=0123456789abcdef0123456789abcdef' '0123456789abcdef0123456789abcdef'

if airvpn_admin_token_from_cookie 'foo=1; theme=dark' >/dev/null 2>&1; then
	echo 'FAIL missing token accepted' >&2; exit 1
fi
if airvpn_admin_token_from_cookie 'Admin-Token=bad%inject' >/dev/null 2>&1; then
	echo 'FAIL malformed token accepted' >&2; exit 1
fi

UI="$ROOT/pkg/data/www/airvpn-native-ui.js"
CGI="$ROOT/pkg/data/www/cgi-bin/airvpn-native"
! grep -q "Admin-Token.*A.token\|findStored\|__av_fetch\|__av_xhr" "$UI" || { echo 'FAIL JS still harvests Admin-Token' >&2; exit 1; }
grep -q "credentials:'same-origin'" "$UI" || { echo 'FAIL same-origin credentials missing' >&2; exit 1; }
grep -q 'HTTP_COOKIE' "$CGI" || { echo 'FAIL CGI does not read native cookie' >&2; exit 1; }
grep -q '\\"params\\":\[\\"\$token\\",\\"system\\",\\"get_status\\"' "$CGI" || { echo 'FAIL verification does not use token as SID' >&2; exit 1; }

echo 'PASS auth-cookie native contract'