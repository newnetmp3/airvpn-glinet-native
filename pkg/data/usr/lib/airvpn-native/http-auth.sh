#!/bin/sh
# GL.iNet Admin Panel HTTP authentication helpers.
# Firmware 4.9.x carries the authenticated session in the same-origin
# Admin-Token cookie. Keep cookie parsing server-side: browser JavaScript does
# not need access to the session secret.

airvpn_admin_token_from_cookie() {
	cookie_header="${1:-}"
	[ -n "$cookie_header" ] || return 1

	# Cookie values cannot contain ';'. Split on cookie separators and select
	# only the exact GL.iNet Admin-Token key.
	token="$(printf '%s\n' "$cookie_header" \
		| tr ';' '\n' \
		| sed -n 's/^[[:space:]]*Admin-Token=\([^[:space:];]*\)[[:space:]]*$/\1/p' \
		| head -n 1)"
	[ -n "$token" ] || return 1
	[ "${#token}" -le 512 ] || return 1

	# Known 4.x SIDs/Admin-Tokens are opaque URL-safe identifiers. Reject
	# metacharacters before using the value in a JSON-RPC payload.
	case "$token" in *[!A-Za-z0-9_-]*) return 1;; esac
	printf '%s\n' "$token"
}