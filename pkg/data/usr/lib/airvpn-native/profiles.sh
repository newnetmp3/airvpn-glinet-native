#!/bin/sh
# AirVPN native plugin module — sourced by /usr/bin/airvpn-native.

confval() {
	sec="$1"; key="$2"; f="$3"
	awk -v sec="$sec" -v key="$key" '
		function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
		{
			line=$0
			gsub(/\r/,"",line)
			if (line ~ /^[ \t]*\[[^]]+\][ \t]*$/) {
				h=line
				gsub(/^[ \t]*\[/,"",h); gsub(/\][ \t]*$/,"",h)
				insec=(tolower(h)==tolower(sec))
				next
			}
			if (insec && index(line,"=")>0) {
				k=line; sub(/=.*/,"",k); k=trim(k)
				if (tolower(k)==tolower(key)) {
					v=line; sub(/^[^=]*=/,"",v); print trim(v); exit
				}
			}
		}' "$f"
}

ensure_group() {
	mkdir -p "$STATE"; chmod 700 "$STATE"
	group_name="$(get group_name)"; [ -n "$group_name" ] || group_name=AirVPN
	gid="$(cat "$GROUPID_FILE" 2>/dev/null || true)"
	if [ -n "$gid" ] && [ "$(uci -q get wireguard.group_$gid 2>/dev/null || true)" = groups ]; then echo "$gid"; return 0; fi
	for s in $(uci -q show wireguard 2>/dev/null | sed -n 's/^wireguard\.\([^.=]*\)=groups$/\1/p'); do
		[ "$(uci -q get wireguard.$s.group_name 2>/dev/null || true)" = "$group_name" ] || continue
		case "$s" in group_*) gid="${s#group_}";; *) continue;; esac
		printf '%s\n' "$gid" >"$GROUPID_FILE"; echo "$gid"; return 0
	done
	escaped="$(json_string_escape "$group_name")"
	out="$(glinet_wg_client_call add_group "{\"group_name\":\"$escaped\"}" 20)" || { rc=$?; echo "Native wg-client.add_group failed (rc=$rc)." >&2; return "$rc"; }
	if glinet_rpc_failed "$out"; then echo "Native wg-client.add_group rejected the request:" >&2; echo "$out" >&2; return 5; fi
	# Firmware commits the new group synchronously. Resolve the generated id.
	for s in $(uci -q show wireguard 2>/dev/null | sed -n 's/^wireguard\.\([^.=]*\)=groups$/\1/p'); do
		[ "$(uci -q get wireguard.$s.group_name 2>/dev/null || true)" = "$group_name" ] || continue
		case "$s" in group_*) gid="${s#group_}";; *) continue;; esac
	done
	case "$gid" in ''|*[!0-9]*) echo "Native add_group succeeded but generated group_id could not be resolved." >&2; return 6;; esac
	printf '%s\n' "$gid" >"$GROUPID_FILE"; echo "$gid"
}

remove_managed() {
	failed=0
	kept="$STATE/managed-peers.keep.$$"
	: >"$kept"
	for peer in $(managed_peer_ids); do
		gid="$(uci -q get wireguard.$peer.group_id 2>/dev/null || true)"; pid="${peer#peer_}"
		case "$gid" in ''|*[!0-9]*) echo "Warning: cannot natively remove $peer because group_id is invalid: $gid" >&2; failed=1; echo "$peer" >>"$kept"; continue;; esac
		case "$pid" in ''|*[!0-9]*) echo "Warning: cannot natively remove $peer because peer_id is invalid: $pid" >&2; failed=1; echo "$peer" >>"$kept"; continue;; esac
		rc=0
		out="$(glinet_wg_client_call clear_config_list "{\"group_id\":$gid,\"peer_id\":$pid,\"clear_all\":false}" 20)" || rc=$?
		if [ "$rc" -ne 0 ] || glinet_rpc_failed "$out"; then
			echo "Warning: native wg-client.clear_config_list failed for $peer; leaving it registered as managed." >&2
			failed=1
			echo "$peer" >>"$kept"
			continue
		fi
	done
	mkdir -p "$STATE"
	mv -f "$kept" "$MANAGED"; chmod 600 "$MANAGED" 2>/dev/null || true
	if [ "$failed" -eq 0 ]; then
		rm -rf "$PROFILE_SOURCE_DIR"
	else
		echo "One or more native WireGuard configs could not be removed." >&2
		return 4
	fi
}

import_conf() {
	f="$1"; selector="$2"; gid="$3"; index="$4"
	addr="$(confval Interface Address "$f")"; priv="$(confval Interface PrivateKey "$f")"; dns="$(confval Interface DNS "$f")"; mtu_conf="$(confval Interface MTU "$f")"
	pub="$(confval Peer PublicKey "$f")"; psk="$(confval Peer PresharedKey "$f")"; endpoint="$(confval Peer Endpoint "$f")"; allowed="$(confval Peer AllowedIPs "$f")"; keep_conf="$(confval Peer PersistentKeepalive "$f")"
	[ -n "$addr" ] && [ -n "$priv" ] && [ -n "$pub" ] && [ -n "$endpoint" ] || { echo "Invalid WireGuard configuration for $selector." >&2; return 1; }
	mtu="$(get mtu)"; [ -n "$mtu" ] || mtu="$mtu_conf"; keep="$(get keepalive)"; [ -n "$keep" ] || keep="$keep_conf"
	prefix="$(get prefix)"; [ -n "$prefix" ] || prefix=AirVPN; name="$(sanitize "$prefix-$selector")"; [ -n "$name" ] || name="AirVPN-$index"
	a4=""; a6=""
	oldIFS="$IFS"; IFS=','; for a in $addr; do a="$(printf '%s' "$a" | xargs)"; case "$a" in *:*) [ -n "$a6" ] || a6="$a";; *.*) [ -n "$a4" ] || a4="$a";; esac; done; IFS="$oldIFS"
	jname="$(json_string_escape "$name")"; jpriv="$(json_string_escape "$priv")"; jpub="$(json_string_escape "$pub")"; jendpoint="$(json_string_escape "$endpoint")"; jallowed="$(json_string_escape "${allowed:-0.0.0.0/0}")"; ja4="$(json_string_escape "$a4")"; ja6="$(json_string_escape "$a6")"; jdns="$(json_string_escape "$dns")"; jpsk="$(json_string_escape "$psk")"
	params="{\"group_id\":$gid,\"name\":\"$jname\",\"address_v4\":\"$ja4\",\"address_v6\":\"$ja6\",\"private_key\":\"$jpriv\",\"public_key\":\"$jpub\",\"allowed_ips\":\"$jallowed\",\"end_point\":\"$jendpoint\""
	[ -n "$dns" ] && params="$params,\"dns\":\"$jdns\""
	case "$mtu" in ''|*[!0-9]*) ;; *) params="$params,\"mtu\":$mtu";; esac
	case "$keep" in ''|*[!0-9]*) ;; *) params="$params,\"persistent_keepalive\":$keep";; esac
	if [ -n "$psk" ]; then params="$params,\"presharedkey_enable\":true,\"preshared_key\":\"$jpsk\""; else params="$params,\"presharedkey_enable\":false"; fi
	params="$params}"
	out="$(glinet_wg_client_call add_config "$params" 30)" || { rc=$?; echo "Native wg-client.add_config failed for $selector (rc=$rc)." >&2; return "$rc"; }
	if glinet_rpc_failed "$out"; then echo "Native wg-client.add_config rejected $selector:" >&2; echo "$out" >&2; return 5; fi
	# Resolve the firmware-generated peer id by immutable key + group.
	peer=""
	for p in $(uci -q show wireguard 2>/dev/null | sed -n 's/^wireguard\.\([^.=]*\)=peers$/\1/p'); do
		[ "$(uci -q get wireguard.$p.group_id 2>/dev/null || true)" = "$gid" ] || continue
		[ "$(uci -q get wireguard.$p.public_key 2>/dev/null || true)" = "$pub" ] || continue
		peer="$p"; break
	done
	[ -n "$peer" ] || { echo "Native add_config succeeded but its peer could not be resolved." >&2; return 6; }
	# Plugin-only metadata. Core VPN fields remain firmware-owned.
	uci set "wireguard.$peer.airvpn_managed=1"; uci set "wireguard.$peer.airvpn_selector=$selector"
	if [ -r "$f.effective" ]; then
		for key in protocol layer resolve; do val="$(sed -n "s/^$key=//p" "$f.effective" | head -n1)"; [ -n "$val" ] || continue; case "$key" in protocol) uk=airvpn_protocol;; layer) uk=airvpn_ip_layer;; resolve) uk=airvpn_resolve;; esac; uci set "wireguard.$peer.$uk=$val"; done
	fi
	uci commit wireguard
	mkdir -p "$PROFILE_SOURCE_DIR"; chmod 700 "$PROFILE_SOURCE_DIR"; cp "$f" "$PROFILE_SOURCE_DIR/$peer.conf"; chmod 600 "$PROFILE_SOURCE_DIR/$peer.conf"
	[ -f "$MANAGED" ] || : >"$MANAGED"; grep -qxF "$peer" "$MANAGED" 2>/dev/null || echo "$peer" >>"$MANAGED"
	printf '%s\t%s\t%s\n' "$peer" "$name" "$endpoint"
}

preflight() {
	need_key
	echo "Checking AirVPN API key..."
	if validate_api_key_value "$API_KEY"; then
		echo "AirVPN API key authorized."
	else
		rc=$?
		if [ "$rc" -eq 2 ]; then
			echo "AirVPN API key check failed: the saved key is not authorized." >&2
			echo "Open AirVPN Client Area -> API, create/enable a current key, paste it in this plugin's Settings, Save, and retry." >&2
		else
			echo "AirVPN API key check could not be completed. Verify Internet/DNS access and retry." >&2
		fi
		return 1
	fi

	device="$(get device)"; [ -n "$device" ] || device=default
	# Resolve the user-facing device name to the account device ID before any
	# generator request. AirVPN's current generator API expects Device.id.
	if ! resolve_airvpn_device "$device"; then
		echo "AirVPN API key is valid, but the configured device could not be resolved." >&2
		return 2
	fi
	echo "Using AirVPN device/key: $RESOLVED_DEVICE_NAME (id=$RESOLVED_DEVICE_ID)"
}

# Interactive Add/Connect should not spend up to 90 seconds revalidating a key/device
# that Settings already validated. Use the persisted validated device when it still
# matches the configured name/ID; the generator itself remains the authoritative
# authorization check. Fall back to the full network preflight when cached identity
# is absent or no longer matches Settings.

profile_preflight() {
	need_key
	configured="$(get device)"; [ -n "$configured" ] || configured=default
	validated="$(get api_key_validated)"
	stored_id="$(cat "$STATE/device-id" 2>/dev/null || true)"
	stored_name="$(cat "$STATE/device-name" 2>/dev/null || true)"
	configured_lc="$(printf '%s' "$configured" | tr '[:upper:]' '[:lower:]')"
	stored_name_lc="$(printf '%s' "$stored_name" | tr '[:upper:]' '[:lower:]')"
	if [ "$validated" = 1 ] && [ -n "$stored_id" ] && { [ "$configured" = "$stored_id" ] || [ "$configured_lc" = "$stored_name_lc" ]; }; then
		RESOLVED_DEVICE_ID="$stored_id"
		RESOLVED_DEVICE_NAME="${stored_name:-$configured}"
		export RESOLVED_DEVICE_ID RESOLVED_DEVICE_NAME
		echo "Using previously validated AirVPN account/device: $RESOLVED_DEVICE_NAME (id=$RESOLVED_DEVICE_ID)."
		return 0
	fi
	preflight
}

sync_profiles() {
	mkdir -p "$STATE/tmp"; chmod 700 "$STATE"
	target_check || return $?
	preflight || return 3
	if [ "$(get cleanup_managed)" = 1 ]; then
		purge_dashboard_tunnel || return $?
		remove_managed || return $?
	fi
	gid="$(ensure_group)"
	selectors="$(get selectors)"
	[ -n "$selectors" ] || selectors=earth
	# Accept comma, semicolon, or newline-separated selectors. Spaces are preserved
	# within a selector until sent URL-encoded to AirVPN.
	oldIFS="$IFS"; IFS=';,
'
	i=0
	for selector in $selectors; do
		selector="$(printf '%s' "$selector" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		[ -n "$selector" ] || continue
		i=$((i+1))
		f="$STATE/tmp/$i.conf"
		echo "Generating AirVPN profile: $selector"
		if generate_one "$selector" "$f"; then
			if ! import_conf "$f" "$selector" "$gid" "$i"; then
				echo "Failed to import generated profile for selector: $selector" >&2
			fi
		else
			echo "Failed to generate profile for selector: $selector" >&2
		fi
	done
	IFS="$oldIFS"
	rm -rf "$STATE/tmp"
	count="$(managed_peer_count)"
	if [ "$count" -eq 0 ]; then
		echo "No AirVPN profiles were generated. Nothing was imported into GL.iNet." >&2
		echo "All AirVPN generator fallback combinations failed; review the AirVPN response lines above." >&2
		return 4
	fi
	first_peer="$(managed_peer_ids | sed -n '1p')"
	if [ -n "$first_peer" ]; then
		ensure_dashboard_tunnel "$first_peer" || {
			echo "AirVPN Client Profile was created, but VPN Dashboard tunnel creation failed." >&2
			return 6
		}
	fi
	echo "$count AirVPN profile(s) synchronized into the GL.iNet 4.9.1 native WireGuard profile database."
	echo "The managed AirVPN VPN Dashboard tunnel is linked to the synchronized profile."
}

list_profiles() {
	managed_peer_ids | while IFS= read -r p; do
		[ -n "$p" ] || continue
		printf '%s\t%s\t%s\n' "$p" \
			"$(uci -q get wireguard.$p.name 2>/dev/null || true)" \
			"$(uci -q get wireguard.$p.end_point 2>/dev/null || true)"
	done
}

find_peer_for_selector() {
	want="${1:-}"
	[ -n "$want" ] || return 1
	want_lc="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')"
	for p in $(managed_peer_ids); do
		sel="$(uci -q get wireguard.$p.airvpn_selector 2>/dev/null || true)"
		sel_lc="$(printf '%s' "$sel" | tr '[:upper:]' '[:lower:]')"
		[ "$sel_lc" = "$want_lc" ] && { echo "$p"; return 0; }
	done
	return 1
}
