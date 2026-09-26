#!/bin/sh
# AirVPN native plugin module — sourced by /usr/bin/airvpn-native.

validate_status_json() {
	f="$1"; [ -s "$f" ] || { echo "empty response"; return 1; }
	first="$(jsonfilter -i "$f" -e '@.servers[0].public_name' 2>/dev/null || true)"
	[ -n "$first" ] || first="$(jsonfilter -i "$f" -e '@.servers[0].name' 2>/dev/null || true)"
	[ -n "$first" ] || { echo "missing servers[]"; return 1; }
	new_count="$(safe_json_count_servers "$f")"; case "$new_count" in ''|*[!0-9]*) new_count=0;; esac
	min="$(get cache_min_servers)"; [ -n "$min" ] || min=20
	[ "$new_count" -ge "$min" ] || { echo "suspiciously small server list: $new_count"; return 1; }
	if [ -s "$raw_status_cache_file" ]; then
		old_count="$(safe_json_count_servers "$raw_status_cache_file")"; case "$old_count" in ''|*[!0-9]*) old_count=0;; esac
		if [ "$old_count" -ge "$min" ] && [ "$new_count" -lt $((old_count/4)) ]; then echo "server count collapsed from $old_count to $new_count"; return 1; fi
	fi
}

record_refresh_result() {
	ok="$1"; msg="$2"; now="$(date +%s 2>/dev/null || echo 0)"; umask 077
	{ echo "ok=$ok"; echo "time=$now"; printf 'message=%s\n' "$(printf '%s' "$msg" | tr '\n\r' '  ')"; } >"${REFRESH_STATUS}.tmp"
	mv "${REFRESH_STATUS}.tmp" "$REFRESH_STATUS"
}

need_key() {
	API_KEY="$(get api_key)"
	# Read the legacy credential file only as a migration fallback.
	if [ -z "$API_KEY" ] && [ -r "$API_KEY_FILE" ]; then
		API_KEY="$(cat "$API_KEY_FILE" 2>/dev/null || true)"
	fi
	[ -n "$API_KEY" ] || { echo "AirVPN API key not configured" >&2; exit 2; }
}

api() {
	need_key
	# Match AirVPN's current API clients: authenticate with the API-KEY header.
	curl -fsS --connect-timeout 10 --max-time 45 -H "API-KEY: $API_KEY" "$@"
}

auth_response_rejected() {
	f="$1"
	[ -s "$f" ] || return 1
	grep -Eqi '"error"[[:space:]]*:[[:space:]]*"?Not authorized|Not authorized|unauthori[sz]ed' "$f" 2>/dev/null
}

api_userinfo_request() {
	out="$1"
	key="$2"
	err="$out.error"
	rm -f "$out" "$err"
	umask 077
	# AirVPN's current API clients authenticate with API-KEY in the request
	# header. Do not also send key= in the query string: generator and account
	# endpoints may interpret that independently and return misleading
	# "Not authorized" responses even though userinfo accepted the header.
	code="$(curl -sS --connect-timeout 10 --max-time 45 \
		-H "API-KEY: $key" \
		-o "$out" -w '%{http_code}' -G "$API/userinfo/" \
		--data-urlencode 'format=json' 2>"$err" || true)"
	[ "$code" = 200 ] || return 3
	auth_response_rejected "$out" && return 2
	result="$(jsonfilter -i "$out" -e '@.result' 2>/dev/null || true)"
	[ "$result" = ok ] || return 3
	# Member-only userinfo must contain a user object/login when authorized.
	login="$(jsonfilter -i "$out" -e '@.user.login' 2>/dev/null || true)"
	[ -n "$login" ] || grep -Eqi '"user"[[:space:]]*:|"login"[[:space:]]*:' "$out" 2>/dev/null || return 3
	return 0
}

validate_api_key_value() {
	key="$1"
	tmp="$STATE/api-key-check.$$"
	mkdir -p "$STATE"
	chmod 700 "$STATE" 2>/dev/null || true
	if api_userinfo_request "$tmp" "$key"; then
		rm -f "$tmp" "$tmp.error"
		return 0
	else
		rc=$?
	fi
	if [ "$rc" -eq 2 ]; then
		echo "AirVPN rejected this API key as not authorized." >&2
	elif [ -s "$tmp.error" ]; then
		echo "Could not verify AirVPN API key because the API request failed:" >&2
		sed -n '1,4p' "$tmp.error" >&2
	else
		echo "Could not verify AirVPN API key: unexpected AirVPN userinfo response." >&2
		[ -s "$tmp" ] && sed -n '1,6p' "$tmp" >&2
	fi
	rm -f "$tmp" "$tmp.error"
	return "$rc"
}

api_devices_request() {
	out="$1"
	key="$2"
	err="$out.error"
	rm -f "$out" "$err"
	umask 077
	# The current AirVPN devices API uses an authenticated POST action=list.
	code="$(curl -sS --connect-timeout 10 --max-time 45 \
		-H "API-KEY: $key" \
		-H 'Content-Type: application/json' \
		-o "$out" -w '%{http_code}' -X POST "$API/devices/" \
		--data '{"action":"list"}' 2>"$err" || true)"
	[ "$code" = 200 ] || return 3
	auth_response_rejected "$out" && return 2
	# A valid list response always has devices[] (which may be empty).
	grep -Eq '"devices"[[:space:]]*:' "$out" 2>/dev/null || return 3
	return 0
}

resolve_device_id_from_json() {
	f="$1"
	want="$2"
	[ -s "$f" ] || return 1
	[ -n "$want" ] || want=default
	tmpbase="$STATE/device-resolve.$$"
	ids="$tmpbase.ids"; names="$tmpbase.names"
	rm -f "$ids" "$names"
	jsonfilter -i "$f" -e '@.devices[*].id' >"$ids" 2>/dev/null || true
	jsonfilter -i "$f" -e '@.devices[*].name' >"$names" 2>/dev/null || true
	want_lc="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')"
	match=""; first_id=""; first_name=""; count=0
	exec 3<"$names"
	while IFS= read -r id; do
		IFS= read -r name <&3 || name=""
		[ -n "$id" ] || continue
		count=$((count+1))
		[ -n "$first_id" ] || { first_id="$id"; first_name="$name"; }
		name_lc="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
		if [ "$id" = "$want" ] || [ "$name_lc" = "$want_lc" ]; then
			match="$id|$name"
			break
		fi
	done <"$ids"
	exec 3<&-
	rm -f "$ids" "$names"
	if [ -n "$match" ]; then
		printf '%s\n' "$match"
		return 0
	fi
	# A single account device is unambiguous even if the saved name is stale.
	if [ "$count" -eq 1 ] && [ -n "$first_id" ]; then
		printf '%s|%s\n' "$first_id" "$first_name"
		return 0
	fi
	return 1
}

resolve_airvpn_device() {
	configured="${1:-$(get device)}"
	[ -n "$configured" ] || configured=default
	mkdir -p "$STATE"; chmod 700 "$STATE" 2>/dev/null || true
	devjson="$STATE/devices.json"
	if api_devices_request "$devjson" "$API_KEY"; then
		:
	else
		rc=$?
		if [ "$rc" -eq 2 ]; then
			echo "AirVPN rejected the API key while listing account devices." >&2
		elif [ -s "$devjson.error" ]; then
			echo "Could not list AirVPN devices:" >&2
			sed -n '1,4p' "$devjson.error" >&2
		else
			echo "Could not read a valid AirVPN device list." >&2
		fi
		return 1
	fi
	resolved="$(resolve_device_id_from_json "$devjson" "$configured" 2>/dev/null || true)"
	if [ -z "$resolved" ]; then
		echo "AirVPN device '$configured' was not found for this API key." >&2
		echo "Available AirVPN devices:" >&2
		jsonfilter -i "$devjson" -e '@.devices[*].name' 2>/dev/null | sed 's/^/  - /' >&2 || true
		echo "Set 'AirVPN device name / ID' in Settings to one of the devices above." >&2
		return 1
	fi
	RESOLVED_DEVICE_ID="${resolved%%|*}"
	RESOLVED_DEVICE_NAME="${resolved#*|}"
	[ -n "$RESOLVED_DEVICE_NAME" ] || RESOLVED_DEVICE_NAME="$configured"
	configured_lc="$(printf '%s' "$configured" | tr '[:upper:]' '[:lower:]')"
	resolved_name_lc="$(printf '%s' "$RESOLVED_DEVICE_NAME" | tr '[:upper:]' '[:lower:]')"
	if [ "$configured" != "$RESOLVED_DEVICE_ID" ] && [ "$configured_lc" != "$resolved_name_lc" ]; then
		echo "Configured AirVPN device '$configured' is not present; the account exposes one device. Automatically using '$RESOLVED_DEVICE_NAME' (id=$RESOLVED_DEVICE_ID)."
		# Persist the resolved device name for later generator requests.
		uci set "$CFG.device=$RESOLVED_DEVICE_NAME" 2>/dev/null && uci commit airvpn_native 2>/dev/null || true
	fi
	printf '%s\n' "$RESOLVED_DEVICE_ID" >"$STATE/device-id"
	printf '%s\n' "$RESOLVED_DEVICE_NAME" >"$STATE/device-name"
	chmod 600 "$STATE/device-id" "$STATE/device-name" 2>/dev/null || true
	echo "Resolved AirVPN device: $RESOLVED_DEVICE_NAME (id=$RESOLVED_DEVICE_ID)"
	return 0
}

userinfo() {
	need_key
	tmp="$STATE/userinfo.$$"
	if api_userinfo_request "$tmp" "$API_KEY"; then
		cat "$tmp"
		rm -f "$tmp" "$tmp.error"
		return 0
	else
		rc=$?
	fi
	cat "$tmp" 2>/dev/null || true
	rm -f "$tmp" "$tmp.error"
	return "$rc"
}

devices() {
	need_key
	tmp="$STATE/devices-command.$$"
	mkdir -p "$STATE"
	if api_devices_request "$tmp" "$API_KEY"; then
		cat "$tmp"
		rm -f "$tmp" "$tmp.error"
		return 0
	else
		rc=$?
	fi
	[ -s "$tmp" ] && cat "$tmp"
	[ -s "$tmp.error" ] && cat "$tmp.error" >&2
	rm -f "$tmp" "$tmp.error"
	return "$rc"
}

set_api_key() {
	key="${1-}"
	[ -n "$key" ] || { echo "API key may not be empty" >&2; exit 2; }
	clean="$(printf '%s' "$key" | tr -d '\r\n')"
	[ "$clean" = "$key" ] || { echo "API key contains unsupported line breaks." >&2; exit 2; }
	validation_note=""
	validated=0
	if validate_api_key_value "$key"; then
		validation_note="AirVPN API key validated and authorized."
		validated=1
	else
		rc=$?
		if [ "$rc" -eq 2 ]; then
			echo "API key was NOT saved because AirVPN explicitly rejected it as not authorized." >&2
			exit 3
		fi
		validation_note="Warning: API key could not be validated because AirVPN was unreachable or returned an unexpected response; key was saved for later retry."
	fi

	# Use OpenWrt's built-in persistent configuration store instead of a
	# parallel custom credential file. /etc/config/airvpn_native is a conffile
	# and is preserved by opkg upgrades.
	uci set "$CFG.api_key=$key" || { echo "Could not write API key to UCI." >&2; exit 4; }
	uci set "$CFG.api_key_validated=$validated" || true
	uci set "$CFG.api_key_validation_time=$(date +%s 2>/dev/null || echo 0)" || true
	uci commit airvpn_native || { echo "Could not commit API key to UCI." >&2; exit 4; }
	chmod 600 /etc/config/airvpn_native 2>/dev/null || true

	saved="$(get api_key)"
	if [ "$saved" != "$key" ]; then
		echo "API key UCI read-back verification failed; refusing to report success." >&2
		exit 5
	fi

	# Remove the obsolete custom-file copy only after UCI commit/read-back succeeds.
	rm -f "$API_KEY_FILE" 2>/dev/null || true
	echo "AirVPN API key saved in OpenWrt UCI and read back successfully."
	echo "$validation_note"
}

set_api_key_stdin() {
	key="$(cat)"
	set_api_key "$key"
}

api_key_status() {
	key="$(get api_key)"
	if [ -n "$key" ]; then
		validated="$(get api_key_validated)"; [ "$validated" = 1 ] || validated=0
		when="$(get api_key_validation_time)"; case "$when" in ''|*[!0-9]*) when=0;; esac
		printf '{"configured":true,"storage":"uci","validated":%s,"validation_time":%s}\n' \
			"$([ "$validated" = 1 ] && echo true || echo false)" "$when"
	elif [ -s "$API_KEY_FILE" ]; then
		printf '{"configured":true,"storage":"legacy-file","validated":false,"validation_time":0}\n'
	else
		printf '{"configured":false,"storage":"none","validated":false,"validation_time":0}\n'
	fi
}

clear_api_key() {
	rm -f "$API_KEY_FILE"
	uci -q delete "$CFG.api_key" 2>/dev/null || true
	uci -q delete "$CFG.api_key_validated" 2>/dev/null || true
	uci -q delete "$CFG.api_key_validation_time" 2>/dev/null || true
	uci commit airvpn_native 2>/dev/null || true
	echo "AirVPN API key removed."
}
