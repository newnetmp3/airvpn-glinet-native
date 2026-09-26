#!/bin/sh
# AirVPN native plugin module — sourced by /usr/bin/airvpn-native.

backup_current_state() {
	rm -rf "$BACKUP_DIR.tmp"; mkdir -p "$BACKUP_DIR.tmp"
	if [ -f /etc/config/wireguard ]; then cp -p /etc/config/wireguard "$BACKUP_DIR.tmp/wireguard"; else : >"$BACKUP_DIR.tmp/no-wireguard"; fi
	if [ -f /etc/config/route_policy ]; then cp -p /etc/config/route_policy "$BACKUP_DIR.tmp/route_policy"; else : >"$BACKUP_DIR.tmp/no-route-policy"; fi
	# Native add_tunnel/setup_autovpn_instance can create or alter wgclient network
	# instances. Back up network as part of the same transaction.
	if [ -f /etc/config/network ]; then cp -p /etc/config/network "$BACKUP_DIR.tmp/network"; else : >"$BACKUP_DIR.tmp/no-network"; fi
	if [ -f "$MANAGED" ]; then cp -p "$MANAGED" "$BACKUP_DIR.tmp/managed-peers"; else : >"$BACKUP_DIR.tmp/no-managed-peers"; fi
	[ -f "$DASHBOARD_TUNNEL_ID_FILE" ] && cp -p "$DASHBOARD_TUNNEL_ID_FILE" "$BACKUP_DIR.tmp/dashboard-tunnel-id"
	[ -f "$GROUPID_FILE" ] && cp -p "$GROUPID_FILE" "$BACKUP_DIR.tmp/group-id"
	if [ -d "$PROFILE_SOURCE_DIR" ]; then mkdir -p "$BACKUP_DIR.tmp/profile-sources"; cp -a "$PROFILE_SOURCE_DIR/." "$BACKUP_DIR.tmp/profile-sources/" 2>/dev/null || true; fi
	if [ -d /etc/vpn_profiles.d ]; then mkdir -p "$BACKUP_DIR.tmp/vpn_profiles.d"; cp -a /etc/vpn_profiles.d/. "$BACKUP_DIR.tmp/vpn_profiles.d/" 2>/dev/null || true; else : >"$BACKUP_DIR.tmp/no-vpn-profiles-d"; fi
	if [ -d /etc/wireguard/profile ]; then mkdir -p "$BACKUP_DIR.tmp/wireguard-profile"; cp -a /etc/wireguard/profile/. "$BACKUP_DIR.tmp/wireguard-profile/" 2>/dev/null || true; else : >"$BACKUP_DIR.tmp/no-wireguard-profile"; fi
	rm -rf "$BACKUP_DIR"; mv "$BACKUP_DIR.tmp" "$BACKUP_DIR"; date +%s >"$BACKUP_DIR/timestamp"
	echo "Last-known-good VPN state backed up."
}

rollback_state() {
	[ -d "$BACKUP_DIR" ] || { echo "No last-known-good backup exists." >&2; return 1; }
	# Tear down the currently-created native AirVPN tunnel before restoring files,
	# so vpn-client does not retain a runtime instance that no longer exists in UCI.
	purge_dashboard_tunnel >/dev/null 2>&1 || true
	[ -f "$BACKUP_DIR/wireguard" ] && cp -p "$BACKUP_DIR/wireguard" /etc/config/wireguard
	[ -f "$BACKUP_DIR/no-wireguard" ] && rm -f /etc/config/wireguard 2>/dev/null || true
	[ -f "$BACKUP_DIR/route_policy" ] && cp -p "$BACKUP_DIR/route_policy" /etc/config/route_policy
	[ -f "$BACKUP_DIR/no-route-policy" ] && rm -f /etc/config/route_policy 2>/dev/null || true
	[ -f "$BACKUP_DIR/network" ] && cp -p "$BACKUP_DIR/network" /etc/config/network
	[ -f "$BACKUP_DIR/no-network" ] && rm -f /etc/config/network 2>/dev/null || true
	[ -f "$BACKUP_DIR/managed-peers" ] && cp -p "$BACKUP_DIR/managed-peers" "$MANAGED"
	[ -f "$BACKUP_DIR/no-managed-peers" ] && rm -f "$MANAGED" 2>/dev/null || true
	[ -f "$BACKUP_DIR/dashboard-tunnel-id" ] && cp -p "$BACKUP_DIR/dashboard-tunnel-id" "$DASHBOARD_TUNNEL_ID_FILE" || rm -f "$DASHBOARD_TUNNEL_ID_FILE" 2>/dev/null || true
	[ -f "$BACKUP_DIR/group-id" ] && cp -p "$BACKUP_DIR/group-id" "$GROUPID_FILE" || rm -f "$GROUPID_FILE" 2>/dev/null || true
	rm -rf "$PROFILE_SOURCE_DIR"; if [ -d "$BACKUP_DIR/profile-sources" ]; then mkdir -p "$PROFILE_SOURCE_DIR"; cp -a "$BACKUP_DIR/profile-sources/." "$PROFILE_SOURCE_DIR/" 2>/dev/null || true; chmod 700 "$PROFILE_SOURCE_DIR" 2>/dev/null || true; fi
	if [ -d "$BACKUP_DIR/vpn_profiles.d" ]; then rm -rf /etc/vpn_profiles.d; mkdir -p /etc/vpn_profiles.d; cp -a "$BACKUP_DIR/vpn_profiles.d/." /etc/vpn_profiles.d/ 2>/dev/null || true; fi
	[ -f "$BACKUP_DIR/no-vpn-profiles-d" ] && rm -rf /etc/vpn_profiles.d 2>/dev/null || true
	if [ -d "$BACKUP_DIR/wireguard-profile" ]; then rm -rf /etc/wireguard/profile; mkdir -p /etc/wireguard/profile; cp -a "$BACKUP_DIR/wireguard-profile/." /etc/wireguard/profile/ 2>/dev/null || true; fi
	[ -f "$BACKUP_DIR/no-wireguard-profile" ] && rm -rf /etc/wireguard/profile 2>/dev/null || true
	native_reload_491; echo "Restored last-known-good AirVPN/GL.iNet VPN state."
}

connection_validate() {
	echo "AirVPN connection validation"; echo "----------------------------"
	peer="$(active_airvpn_peer 2>/dev/null || true)"
	if [ -z "$peer" ]; then echo "status=not-connected"; echo "No enabled GL.iNet route_policy tunnel references an AirVPN-managed peer."; return 2; fi
	name="$(uci -q get wireguard.$peer.name 2>/dev/null || true)"
	endpoint="$(uci -q get wireguard.$peer.end_point 2>/dev/null || true)"
	dns="$(uci -q get wireguard.$peer.dns 2>/dev/null || true)"
	addr4="$(uci -q get wireguard.$peer.address_v4 2>/dev/null || true)"
	addr6="$(uci -q get wireguard.$peer.address_v6 2>/dev/null || true)"
	echo "peer=$peer"; echo "name=$name"; echo "endpoint=$endpoint"; echo "address_v4=$addr4"; echo "address_v6=$addr6"; echo "dns=${dns:-not-set}"
	for rs in $(find_tunnels_for_peer "$peer"); do
		echo "route_policy_section=$rs"
		echo "route_policy_enabled=$(uci -q get route_policy.$rs.enabled 2>/dev/null || echo 0)"
		echo "killswitch=$(uci -q get route_policy.$rs.killswitch 2>/dev/null || echo 0)"
	done
	handshake=0
	if command -v wg >/dev/null 2>&1; then
		handshake="$(wg show all latest-handshakes 2>/dev/null | awk 'BEGIN{m=0} $2>m{m=$2} END{print m+0}')"
		echo "wg_interfaces=$(wg show interfaces 2>/dev/null || true)"
	fi
	now="$(date +%s 2>/dev/null || echo 0)"; age=0; [ "$handshake" -gt 0 ] && age=$((now-handshake))
	echo "handshake_age_seconds=$age"
	route="$(ip route get 1.1.1.1 2>/dev/null | head -n1 || true)"
	[ -n "$route" ] && echo "default_route_probe=$route"
	if [ "$handshake" -gt 0 ] && [ "$age" -le 180 ]; then
		echo "status=healthy"; return 0
	fi
	echo "status=degraded"; echo "No recent WireGuard handshake detected."; return 3
}

enable_managed_peer_tunnel() {
	peer="$1"
	activate_managed_tunnel_native "$peer" 1
}

wait_for_managed_peer_connection() {
	peer="$1"
	timeout="${2:-30}"
	not_before="${3:-0}"
	elapsed=0

	while [ "$elapsed" -lt "$timeout" ]; do
		want_key="$(uci -q get wireguard.$peer.public_key 2>/dev/null || true)"
		hs=0
		if command -v wg >/dev/null 2>&1 && [ -n "$want_key" ]; then
			hs="$(wg show all latest-handshakes 2>/dev/null | awk -v k="$want_key" '$1==k || $2==k {print $NF; exit}')"
			case "$hs" in ''|*[!0-9]*) hs=0;; esac
		fi

		if [ "$hs" -gt 0 ] 2>/dev/null && [ "$hs" -ge "$not_before" ] 2>/dev/null; then
			return 0
		fi

		for rs in $(find_tunnels_for_peer "$peer"); do
			state="$(uci -q get route_policy.$rs.enabled 2>/dev/null || echo 0)"
			if [ "$state" != "1" ]; then
				echo "Dashboard tunnel became disabled while waiting for handshake." >&2
				return 2
			fi
		done

		sleep 2
		elapsed=$((elapsed+2))
	done
	return 1
}

latency_test() {
	# The UI submits at most 12 targets per call.  Run every target in the batch
	# concurrently on the router so browser connection limits cannot reduce the
	# requested 12-way latency parallelism.
	targets="${1:-}"; i=0; oldIFS="$IFS"; IFS=','
	tmpdir="/tmp/airvpn-latency.$$"
	rm -rf "$tmpdir" 2>/dev/null || true
	mkdir -p "$tmpdir" || { IFS="$oldIFS"; return 1; }
	for item in $targets; do
		[ "$i" -lt 12 ] || break
		name="${item%%|*}"; host="${item#*|}"; [ -n "$name" ] && [ -n "$host" ] || continue
		# Preserve raw IPv6 literals. Strip a port only from IPv4/hostnames or
		# from bracketed IPv6 forms such as [2001:db8::1]:443.
		case "$host" in
			\[*\]:*) host="${host#[}"; host="${host%%]*}";;
			\[*\]) host="${host#[}"; host="${host%]}";;
			*:*:*) : ;;
			*:*) host="${host%%:*}";;
		esac
		[ -n "$host" ] || continue
		idx="$i"; i=$((i+1))
		(
			out="$(ping -c 2 -W 1 "$host" 2>/dev/null || true)"
			avg="$(printf '%s\n' "$out" | awk -F'=' '/round-trip|rtt/ {gsub(/ ms/,"",$2); split($2,a,"/"); print a[2]}' | head -n1)"
			[ -n "$avg" ] || avg=9999
			printf '%s\t%s\t%s\n' "$name" "$host" "$avg" >"$tmpdir/$idx"
		) &
	done
	IFS="$oldIFS"
	wait
	j=0
	while [ "$j" -lt "$i" ]; do
		[ -f "$tmpdir/$j" ] && cat "$tmpdir/$j"
		j=$((j+1))
	done
	rm -rf "$tmpdir" 2>/dev/null || true
}

self_test() {
	fail=0; echo "AirVPN Native self-test v$PLUGIN_VERSION"; echo "===================================="
	for cmd in curl jsonfilter uci ubus; do if command -v "$cmd" >/dev/null 2>&1; then echo "PASS command:$cmd"; else echo "FAIL command:$cmd missing"; fail=$((fail+1)); fi; done
	if target_check >/dev/null 2>&1; then echo "PASS target firmware/model"; else echo "WARN target firmware/model: $(target_check 2>&1 || true)"; fi
	[ -n "$(get api_key)" ] && echo "PASS API key configured in UCI" || { [ -s "$API_KEY_FILE" ] && echo "WARN API key only in legacy file" || echo "WARN API key not configured"; }
	[ -s "$raw_status_cache_file" ] && echo "PASS server cache present ($(safe_json_count_servers "$raw_status_cache_file") servers)" || echo "WARN server cache absent"
	if [ -x /usr/bin/airvpn-ui-patch ] && /usr/bin/airvpn-ui-patch verify >/dev/null 2>&1; then echo "PASS native UI injection"; else echo "FAIL native UI injection"; fail=$((fail+1)); fi
	[ -x /usr/bin/airvpn-native-schedule ] && grep -q 'airvpn-native-background-refresh' /etc/crontabs/root 2>/dev/null && echo "PASS randomized background refresh scheduled" || echo "WARN background refresh schedule missing"
	ubus -v list airvpn_native >/dev/null 2>&1 && echo "PASS rpcd object airvpn_native" || { echo "FAIL rpcd object missing"; fail=$((fail+1)); }
	if [ ! -d "$LOCKDIR" ]; then
		echo "PASS operation lock clear"
	else
		echo "WARN operation lock exists: operation=$(cat "$LOCKDIR/owner" 2>/dev/null || echo unknown) pid=$(cat "$LOCKDIR/pid" 2>/dev/null || echo unknown) stage=$(cat "$LOCKDIR/stage_code" 2>/dev/null || echo unknown) started=$(cat "$LOCKDIR/started" 2>/dev/null || echo unknown)"
	fi
	echo "Failures=$fail"; [ "$fail" -eq 0 ]
}

diagnostics_export() {
	echo "AirVPN Native Diagnostics v$PLUGIN_VERSION"; echo "Generated: $(date 2>/dev/null || true)"
	echo "Model: $(model_name)"; echo "Firmware: $(fwver)"; echo "Backend: $(profile_backend)"
	echo "API key configured: $([ -n "$(get api_key)" ] && echo yes || { [ -s "$API_KEY_FILE" ] && echo legacy || echo no; })"
	echo; echo "[Cache]"; raw_status_meta
	echo; echo "[Refresh schedule]"; background_refresh_schedule
	echo; echo "[Connection]"; connection_validate 2>&1 || true
	echo; echo "[Managed profiles]"; list_profiles 2>&1 || true
	echo; echo "[Last Add Profile job]"
	latest_add="$(ls -1dt "$STATE"/addjobs/add-* 2>/dev/null | head -n1 || true)"
	if [ -n "$latest_add" ] && [ -d "$latest_add" ]; then
		echo "job=${latest_add##*/}"
		cat "$latest_add/status" 2>/dev/null || true
		echo "--- output (last 120 lines) ---"
		tail -n 120 "$latest_add/output" 2>/dev/null || true
	else
		echo "No asynchronous Add Profile job has run yet."
	fi
	echo; echo "[Self-test]"; self_test 2>&1 || true
	echo; echo "[Config - sanitized]"
	uci -q show airvpn_native 2>/dev/null | sed -E -e 's/(api_key=).*/\1<redacted>/' -e 's/(private_key=).*/\1<redacted>/' -e 's/(preshared_key=).*/\1<redacted>/' || true
}
