#!/bin/sh
# AirVPN native plugin module — sourced by /usr/bin/airvpn-native.

native_reload_491() {
	[ "$(get native_reload)" = 1 ] || return 0
	log "Running explicit GL.iNet VPN recovery reload; normal profile/tunnel operations use native RPC and do not call this path."
	ubus call service event '{"type":"config.change","data":{"package":"wireguard"}}' >/dev/null 2>&1 || true
	ubus call service event '{"type":"config.change","data":{"package":"route_policy"}}' >/dev/null 2>&1 || true
	[ -x /etc/init.d/vpn-client ] && /etc/init.d/vpn-client restart >/dev/null 2>&1 || true
}

managed_peer_ids() {
	seen=" "
	if [ -f "$MANAGED" ]; then
		while IFS= read -r p; do
			[ -n "$p" ] || continue
			[ "$(uci -q get "wireguard.$p" 2>/dev/null || true)" = "peers" ] || continue
			case "$seen" in *" $p "*) continue;; esac
			echo "$p"; seen="$seen$p "
		done <"$MANAGED"
	fi
	# Recover profiles annotated by this plugin if the state file was lost.
	for p in $(uci -q show wireguard 2>/dev/null | sed -n 's/^wireguard\.\([^.=]*\)\.airvpn_managed=.1.$/\1/p'); do
		[ "$(uci -q get "wireguard.$p" 2>/dev/null || true)" = "peers" ] || continue
		case "$seen" in *" $p "*) continue;; esac
		echo "$p"; seen="$seen$p "
	done
}

managed_peer_count() { managed_peer_ids | wc -l | tr -d ' '; }

route_policy_sections() {
	# Return UCI-resolvable anonymous rule references exactly as the native
	# Dashboard sees them: @rule[0], @rule[1], ...
	i=0
	while uci -q get "route_policy.@rule[$i]" >/dev/null 2>&1; do
		echo "@rule[$i]"
		i=$((i+1))
	done
}

find_managed_dashboard_tunnel() {
	# The tunnel id persisted by the plugin is only a locator. GL.iNet owns the
	# actual route_policy/profile objects and is never marked or rewritten here.
	tid="$(cat "$DASHBOARD_TUNNEL_ID_FILE" 2>/dev/null || true)"
	case "$tid" in
		''|*[!0-9]*) ;;
		*) s="$(find_rule_by_tunnel_id "$tid" 2>/dev/null || true)"; [ -n "$s" ] && { echo "$s"; return 0; };;
	esac
	gid="$(cat "$GROUPID_FILE" 2>/dev/null || true)"
	for s in $(route_policy_sections); do
		[ "$(uci -q get route_policy.$s.via_type 2>/dev/null || true)" = "wireguard" ] || continue
		[ "$(uci -q get route_policy.$s.group_id 2>/dev/null || true)" = "$gid" ] || continue
		prof="$(uci -q get route_policy.$s.profiles 2>/dev/null || true)"
		for p in $(managed_peer_ids); do
			pid="${p#peer_}"
			if [ "$(uci -q get route_policy.$s.peer_id 2>/dev/null || true)" = "$pid" ] || { [ -s "$prof" ] && grep -Fxq "${gid}_${pid}" "$prof" 2>/dev/null; }; then
				tid="$(uci -q get route_policy.$s.tunnel_id 2>/dev/null || true)"
				case "$tid" in ''|*[!0-9]*) ;; *) printf '%s\n' "$tid" >"$DASHBOARD_TUNNEL_ID_FILE";; esac
				echo "$s"; return 0
			fi
		done
	done
	return 1
}

find_rule_by_tunnel_id() {
	want="$1"
	[ -n "$want" ] || return 1
	for s in $(route_policy_sections); do
		[ "$(uci -q get route_policy.$s.tunnel_id 2>/dev/null || true)" = "$want" ] || continue
		echo "$s"
		return 0
	done
	return 1
}

native_add_dashboard_tunnel() {
	peer="$1"
	gid="$(uci -q get wireguard.$peer.group_id 2>/dev/null || true)"; pid="${peer#peer_}"
	case "$gid" in ''|*[!0-9]*) echo "Invalid native WireGuard group_id for $peer: $gid" >&2; return 4;; esac
	case "$pid" in ''|*[!0-9]*) echo "Invalid native WireGuard peer_id for $peer: $pid" >&2; return 4;; esac
	params="{\"name\":\"AirVPN\",\"from\":{\"type\":\"default\"},\"to\":{\"type\":\"default\"},\"via\":{\"type\":\"wireguard\",\"configs\":[{\"group_id\":$gid,\"id_list\":[$pid]}]},\"enabled\":false}"
	out="$(glinet_vpn_client_call add_tunnel "$params" 20)" || { rc=$?; echo "Native vpn-client.add_tunnel failed (rc=$rc)." >&2; return "$rc"; }
	if glinet_rpc_failed "$out"; then echo "Native vpn-client.add_tunnel rejected the request:" >&2; echo "$out" >&2; return 5; fi
	tid="$(printf '%s' "$out" | jsonfilter -e '@.result.tunnel_id' 2>/dev/null || true)"
	case "$tid" in ''|*[!0-9]*) echo "Native add_tunnel did not return a tunnel_id." >&2; echo "$out" >&2; return 6;; esac
	printf '%s\n' "$tid" >"$DASHBOARD_TUNNEL_ID_FILE"
	s="$(find_rule_by_tunnel_id "$tid" 2>/dev/null || true)"
	native_dashboard_tunnel_visible "$tid" || return 8
	# Apply options through the dedicated firmware API rather than embedding
	# option data in add_tunnel.
	if ! native_set_tunnel_options "$tid"; then echo "Warning: tunnel created, but native vpn-client.set_options did not accept the requested AirVPN options." >&2; fi
	echo "Native GL.iNet vpn-client.add_tunnel created AirVPN tunnel_id=$tid." >&2
	[ -n "$s" ] && echo "$s" || echo "$tid"
}

native_set_tunnel_options() {
	tid="$1"; mtu="$(get mtu)"; local="$(get local_access)"; masq="$(get masquerade)"
	case "$mtu" in ''|*[!0-9]*) mtu=0;; esac
	[ "$local" = 1 ] && jlocal=true || jlocal=false
	[ "$masq" = 0 ] && jmasq=false || jmasq=true
	params="{\"tunnel_id\":$tid,\"mtu\":$mtu,\"local_access\":$jlocal,\"masq\":$jmasq,\"service_policy\":false,\"killswitch\":true}"
	out="$(glinet_vpn_client_call set_options "$params" 20)" || return $?
	glinet_rpc_failed "$out" && return 1
	return 0
}

verify_dashboard_tunnel() {
	input="$1"; [ -n "$input" ] || return 1
	case "$input" in @rule\[*\]) tid="$(uci -q get route_policy.$input.tunnel_id 2>/dev/null || true)";; *) tid="$input";; esac
	case "$tid" in ''|*[!0-9]*) tid="$(cat "$DASHBOARD_TUNNEL_ID_FILE" 2>/dev/null || true)";; esac
	case "$tid" in ''|*[!0-9]*) echo "verify: tunnel_id missing/invalid" >&2; return 1;; esac
	native_dashboard_tunnel_visible "$tid" || return 1
	s="$(find_rule_by_tunnel_id "$tid" 2>/dev/null || true)"
	[ -n "$s" ] || { echo "verify: native tunnel $tid is visible but route_policy locator is unavailable"; return 0; }
	printf 'Dashboard tunnel verified through native vpn-client.get_tunnel: tunnel_id=%s section=%s enabled=%s\n' "$tid" "$s" "$(uci -q get route_policy.$s.enabled 2>/dev/null || echo unknown)"
}

ensure_dashboard_tunnel() {
	peer="$1"; [ -n "$peer" ] || { echo "peer required" >&2; return 2; }
	[ "$(uci -q get wireguard.$peer 2>/dev/null || true)" = "peers" ] || { echo "WireGuard peer $peer does not exist." >&2; return 3; }
	s="$(find_managed_dashboard_tunnel 2>/dev/null || true)"
	if [ -z "$s" ]; then
		s="$(native_add_dashboard_tunnel "$peer")" || return $?
	else
		native_update_dashboard_profiles "$s" "$peer" || return $?
	fi
	# Resolve tunnel id from either native-created route_policy or persisted locator.
	case "$s" in @rule\[*\]) tid="$(uci -q get route_policy.$s.tunnel_id 2>/dev/null || true)";; *) tid="$(cat "$DASHBOARD_TUNNEL_ID_FILE" 2>/dev/null || true)";; esac
	case "$tid" in ''|*[!0-9]*) echo "Native Dashboard tunnel id could not be resolved." >&2; return 6;; esac
	printf '%s\n' "$tid" >"$DASHBOARD_TUNNEL_ID_FILE"
	native_dashboard_tunnel_visible "$tid" || return 8
	return 0
}

native_remove_dashboard_tunnel() {
	tid="$1"
	case "$tid" in ''|*[!0-9]*) echo "Native remove_tunnel: invalid tunnel_id '$tid'" >&2; return 2;; esac
	rc=0
	out="$(glinet_vpn_client_call remove_tunnel "{\"tunnel_id\":$tid}")" || rc=$?
	if [ "$rc" -ne 0 ]; then
		echo "Native vpn-client.remove_tunnel call failed (rc=$rc)." >&2
		[ -n "$out" ] && echo "$out" >&2
		return "$rc"
	fi
	if printf '%s' "$out" | grep -Eq '"code"[[:space:]]*:[[:space:]]*-[0-9]+|"err_code"[[:space:]]*:[[:space:]]*[1-9][0-9]*'; then
		echo "Native vpn-client.remove_tunnel returned an error:" >&2
		echo "$out" >&2
		return 3
	fi
	return 0
}

# Prove that a specific AirVPN peer is represented by the native VPN Dashboard.
# Verification requires both layers used by GL.iNet: the tunnel must be visible
# through vpn-client.get_tunnel, and the tunnel's native profile file must contain
# the exact group_id/peer_id token for the newly added server.

dashboard_profile_token_contains_peer() {
	peer="$1"
	selector="${2:-}"
	[ -n "$peer" ] || { echo "Dashboard verification: peer is empty." >&2; return 2; }
	[ "$(uci -q get wireguard.$peer 2>/dev/null || true)" = "peers" ] || { echo "Dashboard verification: $peer is not a WireGuard peer." >&2; return 2; }
	gid="$(uci -q get wireguard.$peer.group_id 2>/dev/null || true)"
	pid="${peer#peer_}"
	case "$gid" in ''|*[!0-9]*) echo "Dashboard verification: invalid group_id '$gid' for $peer." >&2; return 2;; esac
	case "$pid" in ''|*[!0-9]*) echo "Dashboard verification: invalid peer_id '$pid' for $peer." >&2; return 2;; esac

	s="$(find_managed_dashboard_tunnel 2>/dev/null || true)"
	[ -n "$s" ] || { echo "Dashboard verification: no AirVPN tunnel exists in VPN Dashboard." >&2; return 3; }
	tid="$(uci -q get route_policy.$s.tunnel_id 2>/dev/null || true)"
	prof="$(uci -q get route_policy.$s.profiles 2>/dev/null || true)"
	case "$tid" in ''|*[!0-9]*) echo "Dashboard verification: tunnel_id '$tid' is invalid." >&2; return 3;; esac
	[ -n "$prof" ] && [ -s "$prof" ] || { echo "Dashboard verification: native profile file '$prof' is missing/empty." >&2; return 4; }
	expected="${gid}_${pid}"
	if ! tr -d '\r' <"$prof" 2>/dev/null | grep -Fxq "$expected"; then
		echo "Dashboard verification: $selector ($peer) token '$expected' is not present in '$prof'." >&2
		echo "Dashboard currently contains: $(tr '\n' ' ' <"$prof" 2>/dev/null || true)" >&2
		return 4
	fi
	name="$(uci -q get wireguard.$peer.name 2>/dev/null || true)"
	[ -n "$selector" ] || selector="$(uci -q get wireguard.$peer.airvpn_selector 2>/dev/null || true)"
	printf 'DASHBOARD_TOKEN_VERIFIED selector=%s name=%s peer=%s tunnel_id=%s group_id=%s peer_id=%s profile=%s token=%s\n' \
		"$selector" "$name" "$peer" "$tid" "$gid" "$pid" "$prof" "$expected"
}

native_dashboard_tunnel_visible() {
	tid="$1"
	case "$tid" in ''|*[!0-9]*) echo "Dashboard native verification: invalid tunnel_id '$tid'." >&2; return 2;; esac
	rc=0
	native_list="$(glinet_vpn_client_call get_tunnel '{}' 6)" || rc=$?
	if [ "$rc" -ne 0 ] || [ -z "$native_list" ]; then
		echo "Dashboard native verification: vpn-client.get_tunnel failed/returned no data (rc=$rc, timeout=6s)." >&2
		[ -n "$native_list" ] && echo "Native response: $native_list" >&2
		return 5
	fi
	native_ids="$(printf '%s' "$native_list" | jsonfilter -e '@.result.tunnels[*].tunnel_id' 2>/dev/null || true)"
	if ! printf '%s\n' "$native_ids" | grep -Fxq "$tid"; then
		echo "Dashboard native verification: tunnel_id $tid is not visible through vpn-client.get_tunnel." >&2
		echo "Native response: $native_list" >&2
		return 5
	fi
	return 0
}

# Update the existing native Dashboard tunnel in place using GL.iNet's own
# vpn-client.set_tunnel schema. Firmware 4.9.1 accepts via.configs with a
# wireguard group_id/id_list and internally rewrites /etc/vpn_profiles.d.
# This is deliberately one-shot: no tunnel removal, no service restart, and no
# rebuild retry loop. A failed native update is reported instead of escalated.

native_update_dashboard_profiles() {
	s="$1"; requested_peer="$2"
	case "$s" in @rule\[*\]) tid="$(uci -q get route_policy.$s.tunnel_id 2>/dev/null || true)";; *) tid="$s";; esac
	case "$tid" in ''|*[!0-9]*) echo "Dashboard update: invalid tunnel_id '$tid'." >&2; return 2;; esac
	gid="$(uci -q get wireguard.$requested_peer.group_id 2>/dev/null || true)"; requested_pid="${requested_peer#peer_}"
	case "$gid" in ''|*[!0-9]*) echo "Dashboard update: invalid group_id '$gid'." >&2; return 2;; esac
	case "$requested_pid" in ''|*[!0-9]*) echo "Dashboard update: invalid peer_id '$requested_pid'." >&2; return 2;; esac
	ids="$requested_pid"; count=1
	for candidate in $(managed_peer_ids); do
		[ "$(uci -q get wireguard.$candidate.group_id 2>/dev/null || true)" = "$gid" ] || continue
		cpid="${candidate#peer_}"; case "$cpid" in ''|*[!0-9]*) continue;; esac
		case ",$ids," in *",$cpid,"*) continue;; esac
		count=$((count+1)); [ "$count" -le 32 ] || { echo "More than 32 AirVPN peers in one native tunnel is not supported by this plugin." >&2; return 10; }
		ids="$ids,$cpid"
	done
	# Preserve current enabled state while changing the via mapping. This matches
	# the 4.9.1 VPN Client UI contract for set_tunnel.
	enabled="$(uci -q get route_policy.$s.enabled 2>/dev/null || echo 0)"
	[ "$enabled" = 1 ] && jenabled=true || jenabled=false
	params="{\"enabled\":$jenabled,\"tunnel_id\":$tid,\"via\":{\"type\":\"wireguard\",\"configs\":[{\"group_id\":$gid,\"id_list\":[$ids]}]}}"
	add_progress 78 native-set-tunnel "Updating native VPN Dashboard profile list"
	out="$(glinet_vpn_client_call set_tunnel "$params" 20)" || { rc=$?; echo "Native vpn-client.set_tunnel failed (rc=$rc)." >&2; return "$rc"; }
	if glinet_rpc_failed "$out"; then echo "Native vpn-client.set_tunnel rejected the profile update:" >&2; echo "$out" >&2; return 6; fi
	printf '%s\n' "$tid" >"$DASHBOARD_TUNNEL_ID_FILE"
	return 0
}

ensure_dashboard_profile_visible() {
	peer="$1"
	selector="${2:-}"

	# Cheap local token check first. Do not issue native get_tunnel repeatedly: on
	# firmware 4.9.1 a slow get_tunnel can consume its full ubus timeout, and the
	# old verifier called it up to four times (~80s by itself).
	add_progress 66 dashboard-local-check "Checking native Dashboard profile token"
	local_line="$(dashboard_profile_token_contains_peer "$peer" "$selector" 2>/dev/null || true)"
	if [ -n "$local_line" ]; then
		tid="$(printf '%s\n' "$local_line" | sed -n 's/.* tunnel_id=\([^ ]*\).*/\1/p')"
		add_progress 92 dashboard-native-verify "Verifying tunnel through GL.iNet VPN Dashboard API (6s maximum)"
		if native_dashboard_tunnel_visible "$tid"; then
			printf '%s\n' "$local_line" | sed 's/^DASHBOARD_TOKEN_VERIFIED /DASHBOARD_VERIFIED /'
			return 0
		fi
		# A stale local token should continue into one native update rather than
		# repeatedly polling get_tunnel.
	fi

	s="$(find_managed_dashboard_tunnel 2>/dev/null || true)"
	created_native=0
	if [ -z "$s" ]; then
		add_progress 74 native-add-tunnel "Creating native VPN Dashboard tunnel"
		echo "No AirVPN Dashboard tunnel exists; creating one native tunnel for '$selector' ($peer)." >&2
		s="$(native_add_dashboard_tunnel "$peer")" || return $?
		created_native=1
	else
		native_update_dashboard_profiles "$s" "$peer" || return $?
	fi

	add_progress 86 dashboard-token-verify "Waiting for Dashboard profile token"
	local_line="$(dashboard_profile_token_contains_peer "$peer" "$selector" 2>/dev/null || true)"
	if [ -z "$local_line" ]; then
		sleep 1
		local_line="$(dashboard_profile_token_contains_peer "$peer" "$selector" 2>/dev/null || true)"
	fi
	if [ -z "$local_line" ]; then
		echo "Dashboard verification failed: '$selector' ($peer) was imported but its token is not present after one bounded native update." >&2
		dashboard_profile_token_contains_peer "$peer" "$selector" >&2 || true
		return 9
	fi

	tid="$(printf '%s\n' "$local_line" | sed -n 's/.* tunnel_id=\([^ ]*\).*/\1/p')"
	if [ "$created_native" -eq 1 ]; then
		# native_add_dashboard_tunnel already performed the one native API verification.
		printf '%s\n' "$local_line" | sed 's/^DASHBOARD_TOKEN_VERIFIED /DASHBOARD_VERIFIED /'
		return 0
	fi
	add_progress 92 dashboard-native-verify "Verifying tunnel through GL.iNet VPN Dashboard API (6s maximum)"
	if ! native_dashboard_tunnel_visible "$tid"; then
		echo "Dashboard profile token is present, but the native Dashboard API did not confirm tunnel_id=$tid." >&2
		return 9
	fi
	printf '%s\n' "$local_line" | sed 's/^DASHBOARD_TOKEN_VERIFIED /DASHBOARD_VERIFIED /'
	return 0
}

purge_dashboard_tunnel() {
	# Firmware owns route_policy and /etc/vpn_profiles.d. Removal is native-only;
	# if the firmware rejects it we report the damage instead of deleting pieces
	# behind vpn-client's back.
	n=0
	while [ "$n" -lt 32 ]; do
		s="$(find_managed_dashboard_tunnel 2>/dev/null || true)"
		[ -n "$s" ] || break
		tid="$(uci -q get route_policy.$s.tunnel_id 2>/dev/null || true)"
		case "$tid" in ''|*[!0-9]*) echo "Cannot resolve native AirVPN tunnel id for removal." >&2; return 3;; esac
		if ! native_remove_dashboard_tunnel "$tid"; then
			echo "Native remove_tunnel failed for $tid; no direct route_policy/profile-file deletion was attempted." >&2
			return 4
		fi
		n=$((n+1))
	done
	rm -f "$DASHBOARD_TUNNEL_ID_FILE"
}

purge_all_managed() {
	purge_dashboard_tunnel
	remove_managed
	echo "Removed AirVPN-managed Client Profile and VPN Dashboard objects through native GL.iNet RPCs."
}

find_tunnels_for_peer() {
	peer="${1:-}"
	[ -n "$peer" ] || return 0
	for s in $(route_policy_sections); do
		pid="$(uci -q get route_policy.$s.peer_id 2>/dev/null || true)"
		[ "$pid" = "${peer#peer_}" ] || continue
		echo "$s"
	done
}

tunnels() {
	found=0
	for peer in $(managed_peer_ids); do
		peer_num="${peer#peer_}"
		name="$(uci -q get wireguard.$peer.name 2>/dev/null || true)"
		endpoint="$(uci -q get wireguard.$peer.end_point 2>/dev/null || true)"
		for rs in $(find_tunnels_for_peer "$peer"); do
			found=1
			rname="$(uci -q get route_policy.$rs.name 2>/dev/null || true)"
			tid="$(uci -q get route_policy.$rs.tunnel_id 2>/dev/null || true)"
			enabled="$(uci -q get route_policy.$rs.enabled 2>/dev/null || echo 0)"
			ks="$(uci -q get route_policy.$rs.killswitch 2>/dev/null || echo 0)"
			group="$(uci -q get route_policy.$rs.group_id 2>/dev/null || true)"
			profiles="$(uci -q get route_policy.$rs.profiles 2>/dev/null || true)"
			from_mac="$(uci -q get route_policy.$rs.from_mac 2>/dev/null || true)"
			printf 'peer=%s\tname=%s\tendpoint=%s\ttunnel=%s\ttunnel_name=%s\tenabled=%s\tkillswitch=%s\tgroup=%s\tprofile=%s\tclient=%s\n' \
				"$peer" "$name" "$endpoint" "$tid" "$rname" "$enabled" "$ks" "$group" "$profiles" "$from_mac"
		done
	done
	[ "$found" -eq 1 ] || echo "No GL.iNet VPN Dashboard tunnel currently references an AirVPN-managed peer."
}

tunnel_status() {
	tunnels
}

native_profile() {
	found=0
	for peer in $(managed_peer_ids); do
		found=1
		echo "AirVPN native profile: $peer"
		echo "  Name: $(uci -q get wireguard.$peer.name 2>/dev/null || true)"
		echo "  Group ID: $(uci -q get wireguard.$peer.group_id 2>/dev/null || true)"
		echo "  Endpoint: $(uci -q get wireguard.$peer.end_point 2>/dev/null || true)"
		echo "  Address v4: $(uci -q get wireguard.$peer.address_v4 2>/dev/null || true)"
		echo "  Address v6: $(uci -q get wireguard.$peer.address_v6 2>/dev/null || true)"
		echo "  DNS: $(uci -q get wireguard.$peer.dns 2>/dev/null || true)"
		echo "  MTU: $(uci -q get wireguard.$peer.mtu 2>/dev/null || true)"
		echo "  Keepalive: $(uci -q get wireguard.$peer.persistent_keepalive 2>/dev/null || true)"
		echo "  AirVPN selector: $(uci -q get wireguard.$peer.airvpn_selector 2>/dev/null || true)"
		echo "  AirVPN protocol: $(uci -q get wireguard.$peer.airvpn_protocol 2>/dev/null || true)"
		echo "  AirVPN IP layer: $(uci -q get wireguard.$peer.airvpn_ip_layer 2>/dev/null || true)"
		echo "  AirVPN resolve: $(uci -q get wireguard.$peer.airvpn_resolve 2>/dev/null || true)"
		for rs in $(find_tunnels_for_peer "$peer"); do
			echo "  Dashboard tunnel:"
			echo "    Section: $rs"
			echo "    Name: $(uci -q get route_policy.$rs.name 2>/dev/null || true)"
			echo "    Tunnel ID: $(uci -q get route_policy.$rs.tunnel_id 2>/dev/null || true)"
			echo "    Enabled: $(uci -q get route_policy.$rs.enabled 2>/dev/null || echo 0)"
			echo "    Kill switch: $(uci -q get route_policy.$rs.killswitch 2>/dev/null || echo 0)"
			echo "    Policy profile: $(uci -q get route_policy.$rs.profiles 2>/dev/null || true)"
			echo "    Client MAC: $(uci -q get route_policy.$rs.from_mac 2>/dev/null || true)"
		done
		echo
	done
	[ "$found" -eq 1 ] || echo "No AirVPN-managed native profiles found."
}

profile_files() {
	echo "GL.iNet vpn_profiles.d entries referenced by AirVPN tunnels:"
	found=0
	for peer in $(managed_peer_ids); do
		for rs in $(find_tunnels_for_peer "$peer"); do
			p="$(uci -q get route_policy.$rs.profiles 2>/dev/null || true)"
			[ -n "$p" ] || continue
			found=1
			echo "  $p"
			if [ -e "$p" ]; then
				ls -l "$p" 2>/dev/null || true
				echo "  preview:"
				sed -n '1,40p' "$p" 2>/dev/null | sed \
					-e 's/^\([[:space:]]*PrivateKey[[:space:]]*=[[:space:]]*\).*/\1<redacted>/' \
					-e 's/^\([[:space:]]*PresharedKey[[:space:]]*=[[:space:]]*\).*/\1<redacted>/'
			else
				echo "  (referenced path does not currently exist)"
			fi
		done
	done
	[ "$found" -eq 1 ] || echo "  none"
}

dashboard_repair() {
	peer="${1:-}"; [ -n "$peer" ] || peer="$(managed_peer_ids | sed -n '1p')"
	[ -n "$peer" ] || { echo "No AirVPN-managed WireGuard Client Profile exists." >&2; return 2; }
	echo "Repairing AirVPN VPN Dashboard mapping through native GL.iNet RPC from $peer..."
	ensure_dashboard_tunnel "$peer" || return $?
	s="$(find_managed_dashboard_tunnel 2>/dev/null || true)"; verify_dashboard_tunnel "$s"
}

native_tunnel_test() {
	tid="${1:-}"
	state="${2:-}"
	[ -n "$tid" ] || { echo "Usage: airvpn-native native-tunnel-test TUNNEL_ID on|off" >&2; return 2; }
	case "$state" in on|1|true) want=1;; off|0|false) want=0;; *) echo "Expected on/off" >&2; return 2;; esac

	native_set_tunnel_state "$tid" "$want" || return $?
	wait_for_tunnel_state "$tid" "$want" 12 || {
		echo "Native call returned, but tunnel state did not become $want." >&2
		return 3
	}

	s="$(find_rule_by_tunnel_id "$tid" 2>/dev/null || true)"
	echo "section=$s"
	echo "enabled=$(uci -q get route_policy.$s.enabled 2>/dev/null || echo unknown)"
	glinet_vpn_client_call get_status '{}' 2>/dev/null || true
}

dashboard_diag() {
	echo "AirVPN VPN Dashboard diagnostics"
	echo "--------------------------------"
	echo "[route_policy]"
	uci -q show route_policy 2>/dev/null || true
	echo
	echo "[managed dashboard]"
	s="$(find_managed_dashboard_tunnel 2>/dev/null || true)"
	if [ -n "$s" ]; then
		if ! verify_dashboard_tunnel "$s"; then
			echo "managed rule present but verification failed (see verify: reason above)"
		fi
	else
		echo "no managed AirVPN Dashboard rule found"
	fi
	echo
	echo "[vpn-client ubus]"
	ubus -v list 2>/dev/null | grep -Ei 'vpn|route_policy' || true
}

native_diag() {
	echo "AirVPN GL.iNet native diagnostics"
	echo "--------------------------------"
	echo "Model: $(model_name)"
	echo "Firmware: $(fwver)"
	echo "Profile backend: $(profile_backend)"
	echo "vpn-client init: $([ -x /etc/init.d/vpn-client ] && echo present || echo missing)"
	echo "wireguard config: $([ -f /etc/config/wireguard ] && echo present || echo missing)"
	echo "route_policy config: $([ -f /etc/config/route_policy ] && echo present || echo missing)"
	echo "vpn_profiles.d: $([ -d /etc/vpn_profiles.d ] && echo present || echo missing)"
	echo "legacy profile dir: $([ -d /etc/wireguard/profile ] && echo present || echo missing)"
	echo
	echo "Relevant ubus objects:"
	ubus list 2>/dev/null | grep -Ei '(^|\.)(vpn|wg|wireguard|route)' | sort || true
	echo
	echo "AirVPN managed group/peers:"
	uci -q show wireguard 2>/dev/null | grep -E 'airvpn_managed|group_name=.AirVPN|airvpn_selector|airvpn_protocol|airvpn_ip_layer|airvpn_resolve' || true
	echo
	echo "AirVPN Dashboard tunnel mapping:"
	tunnels
	echo
	echo "Native vpn_profiles.d references (read-only diagnostics):"
	profile_files
	echo
	echo "Route policy:"
	uci -q show route_policy 2>/dev/null | sed -n '1,80p' || true
	echo
	echo "vpn-client service status:"
	/etc/init.d/vpn-client status 2>/dev/null || true
}

profile_backend() {
	if command -v ubus >/dev/null 2>&1 && [ -f /etc/config/wireguard ] && [ -f /etc/config/route_policy ]; then
		echo "glinet-4.9.1-native-rpc(wg-client+vpn-client)"
	else
		echo "unknown"
	fi
}

json_status() {
	group="$(get group_name)"; selectors="$(get selectors)"
	count="$(managed_peer_count)"
	printf '{"firmware":"%s","backend":"%s","group":"%s","selectors":"%s","managed_profiles":%s}\n' \
		"$(fwver | sed 's/"/\\"/g')" "$(profile_backend)" \
		"$(printf '%s' "$group" | sed 's/"/\\"/g')" \
		"$(printf '%s' "$selectors" | sed 's/"/\\"/g')" "$count"
}

active_airvpn_peer() {
	for peer in $(managed_peer_ids); do
		for rs in $(find_tunnels_for_peer "$peer"); do
			enabled="$(uci -q get route_policy.$rs.enabled 2>/dev/null || echo 0)"
			[ "$enabled" = 1 ] && { echo "$peer"; return 0; }
		done
	done
	return 1
}

glinet_vpn_client_call() {
	func="$1"; params_json="${2:-{}}"; timeout="${3:-20}"
	glinet_rpc_call "vpn-client" "$func" "$params_json" "$timeout"
}

glinet_wg_client_call() {
	func="$1"; params_json="${2:-{}}"; timeout="${3:-20}"
	glinet_rpc_call "wg-client" "$func" "$params_json" "$timeout"
}

glinet_rpc_call() {
	module="$1"; func="$2"; params_json="${3:-{}}"; timeout="${4:-20}"
	case "$timeout" in ''|*[!0-9]*) timeout=20;; esac
	command -v ubus >/dev/null 2>&1 || return 127
	ubus -t "$timeout" call gl-session call \
		"{\"module\":\"$module\",\"func\":\"$func\",\"params\":$params_json}" 2>/dev/null
}

glinet_rpc_failed() {
	printf '%s' "${1:-}" | grep -Eq '"code"[[:space:]]*:[[:space:]]*-[0-9]+|"err_code"[[:space:]]*:[[:space:]]*[1-9][0-9]*'
}

native_set_tunnel_state() {
	tid="$1"; want="$2"; peer="${3:-}"
	case "$tid" in ''|*[!0-9]*) echo "Native set_tunnel: invalid tunnel_id '$tid'" >&2; return 2;; esac
	case "$want" in 0|1) ;; *) echo "Native set_tunnel: enabled must be 0 or 1" >&2; return 2;; esac
	[ -n "$peer" ] || peer="$(preferred_airvpn_peer 2>/dev/null || true)"
	[ -n "$peer" ] || { echo "Native set_tunnel: no AirVPN peer is available." >&2; return 2; }
	gid="$(uci -q get wireguard.$peer.group_id 2>/dev/null || true)"; pid="${peer#peer_}"
	case "$gid" in ''|*[!0-9]*) echo "Native set_tunnel: invalid group_id '$gid' for $peer." >&2; return 2;; esac
	case "$pid" in ''|*[!0-9]*) echo "Native set_tunnel: invalid peer_id '$pid' for $peer." >&2; return 2;; esac
	ids="$pid"; count=1
	for candidate in $(managed_peer_ids); do
		[ "$(uci -q get wireguard.$candidate.group_id 2>/dev/null || true)" = "$gid" ] || continue
		cpid="${candidate#peer_}"; case "$cpid" in ''|*[!0-9]*) continue;; esac
		case ",$ids," in
			*",$cpid,"*) ;;
			*) count=$((count+1)); [ "$count" -le 32 ] || { echo "More than 32 AirVPN peers in one native tunnel is not supported by this plugin." >&2; return 10; }; ids="$ids,$cpid";;
		esac
	done
	[ "$want" = 1 ] && jenabled=true || jenabled=false
	params="{\"enabled\":$jenabled,\"tunnel_id\":$tid,\"via\":{\"type\":\"wireguard\",\"configs\":[{\"group_id\":$gid,\"id_list\":[$ids]}]}}"
	out="$(glinet_vpn_client_call set_tunnel "$params" 20)" || { rc=$?; echo "Native vpn-client.set_tunnel failed (rc=$rc)." >&2; return "$rc"; }
	if glinet_rpc_failed "$out"; then echo "Native vpn-client.set_tunnel returned an error:" >&2; echo "$out" >&2; return 3; fi
	return 0
}

wait_for_tunnel_state() {
	tid="$1"; want="$2"; timeout="${3:-12}"
	elapsed=0
	while [ "$elapsed" -lt "$timeout" ]; do
		s="$(find_rule_by_tunnel_id "$tid" 2>/dev/null || true)"
		if [ -n "$s" ]; then
			state="$(uci -q get route_policy.$s.enabled 2>/dev/null || echo 0)"
			[ "$state" = "$want" ] && return 0
		fi
		sleep 1
		elapsed=$((elapsed+1))
	done
	return 1
}

activate_managed_tunnel_native() {
	peer="$1"; want="$2"; case "$want" in 0|1) ;; *) return 2;; esac
	s="$(find_managed_dashboard_tunnel 2>/dev/null || true)"
	[ -n "$s" ] || { echo "No mapped AirVPN Dashboard tunnel found for $peer." >&2; return 5; }
	tid="$(uci -q get route_policy.$s.tunnel_id 2>/dev/null || cat "$DASHBOARD_TUNNEL_ID_FILE" 2>/dev/null || true)"
	case "$tid" in ''|*[!0-9]*) echo "AirVPN Dashboard tunnel id is invalid." >&2; return 5;; esac
	echo "Calling native GL.iNet vpn-client.set_tunnel with full via mapping: tunnel_id=$tid enabled=$want"
	native_set_tunnel_state "$tid" "$want" "$peer" || return $?
	wait_for_tunnel_state "$tid" "$want" 12 || { echo "GL.iNet did not report enabled=$want for tunnel_id=$tid." >&2; return 5; }
	return 0
}

mapped_airvpn_peer() {
	rs="$(find_managed_dashboard_tunnel 2>/dev/null || true)"
	[ -n "$rs" ] || return 1
	pid="$(uci -q get route_policy.$rs.peer_id 2>/dev/null || true)"
	case "$pid" in ''|*[!0-9]*) return 1;; esac
	peer="peer_$pid"
	[ "$(uci -q get wireguard.$peer.airvpn_managed 2>/dev/null || true)" = "1" ] || return 1
	echo "$peer"
}

preferred_airvpn_peer() {
	# First honor the peer currently mapped by the native Dashboard tunnel.
	peer="$(mapped_airvpn_peer 2>/dev/null || true)"
	[ -n "$peer" ] && { echo "$peer"; return 0; }

	# If Connect Now selected a server previously, use that profile next.
	want="$(get active_selector)"
	if [ -n "$want" ]; then
		peer="$(find_peer_for_selector "$want" 2>/dev/null || true)"
		[ -n "$peer" ] && { echo "$peer"; return 0; }
	fi

	managed_peer_ids | sed -n '1p'
}

json_string_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/[[:cntrl:]]/ /g'
}

vpn_power_status() {
	enabled=0; mapped=0; profiles=0; selected_peer=""
	for peer in $(managed_peer_ids); do
		profiles=$((profiles+1))
		for rs in $(find_tunnels_for_peer "$peer"); do
			mapped=$((mapped+1))
			state="$(uci -q get route_policy.$rs.enabled 2>/dev/null || echo 0)"
			if [ "$state" = "1" ]; then enabled=$((enabled+1)); selected_peer="$peer"; fi
		done
	done
	[ -n "$selected_peer" ] || selected_peer="$(preferred_airvpn_peer 2>/dev/null || true)"
	selector=""
	[ -n "$selected_peer" ] && selector="$(uci -q get wireguard.$selected_peer.airvpn_selector 2>/dev/null || true)"
	selector="$(json_string_escape "$selector")"
	if [ "$enabled" -gt 0 ]; then on=true; else on=false; fi
	printf '{"profiles":%s,"mapped":%s,"enabled":%s,"on":%s,"selector":"%s"}\n' "$profiles" "$mapped" "$enabled" "$on" "$selector"
}

vpn_power_set() {
	want="$1"
	case "$want" in on|1|true) want=1;; off|0|false) want=0;; *) echo "Expected on/off" >&2; return 2;; esac
	lock_acquire vpn-power-set || return $?

	if [ "$want" -eq 0 ]; then
		peer="$(active_airvpn_peer 2>/dev/null || true)"
		[ -n "$peer" ] || peer="$(mapped_airvpn_peer 2>/dev/null || true)"
	else
		peer="$(preferred_airvpn_peer 2>/dev/null || true)"
	fi
	if [ -z "$peer" ]; then
		lock_release
		echo "No AirVPN Client Profile is available." >&2
		return 5
	fi

	if ! find_tunnels_for_peer "$peer" | grep -q .; then
		if ! ensure_dashboard_tunnel "$peer"; then
			lock_release
			echo "Could not create the AirVPN VPN Dashboard tunnel." >&2
			return 5
		fi
	fi

	if ! activate_managed_tunnel_native "$peer" "$want"; then
		lock_release
		echo "GL.iNet did not retain the requested AirVPN Dashboard state." >&2
		vpn_power_status
		return 6
	fi

	if [ "$want" -eq 1 ]; then
		sel="$(uci -q get wireguard.$peer.airvpn_selector 2>/dev/null || true)"
		[ -n "$sel" ] && { uci set "$CFG.active_selector=$sel"; uci commit airvpn_native; }
	fi
	lock_release
	if [ "$want" -eq 1 ]; then
		echo "AirVPN tunnel enabled through native GL.iNet vpn-client.set_tunnel."
	else
		echo "AirVPN tunnel disabled through native GL.iNet vpn-client.set_tunnel."
	fi
	vpn_power_status
}

select_profile() {
	p="${1:-}"; [ -n "$p" ] || { echo "peer id required" >&2; return 2; }
	[ "$(uci -q get wireguard.$p 2>/dev/null || true)" = peers ] || { echo "Unknown WireGuard peer: $p" >&2; return 3; }
	ensure_dashboard_tunnel "$p" || return $?
	activate_managed_tunnel_native "$p" 1 || return $?
	echo "Selected $p through native GL.iNet vpn-client.set_tunnel."
}
