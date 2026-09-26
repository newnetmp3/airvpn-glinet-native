#!/bin/sh
# AirVPN native plugin module — sourced by /usr/bin/airvpn-native.

add_profile_selected_inner() {
	selector="${1:-}"
	[ -n "$selector" ] || { echo "server selector required" >&2; return 2; }
	# Router-side serialization is handled by add_profile_selected().
	add_progress 8 target-check "Checking router/firmware target"
	target_check || return $?
	add_progress 15 credential-device "Loading validated AirVPN credential/device"
	profile_preflight || return 3
	mkdir -p "$STATE/tmp" "$PROFILE_SOURCE_DIR"; chmod 700 "$STATE" "$PROFILE_SOURCE_DIR"
	add_progress 22 profile-lookup "Checking whether this server already exists"

	# If already present, still verify that the native Dashboard profile list
	# actually contains it.  A profile existing in UCI is not sufficient proof.
	p="$(find_peer_for_selector "$selector" 2>/dev/null || true)"
	if [ -n "$p" ]; then
		echo "AirVPN Client Profile already contains $selector ($p)."
		add_progress 64 dashboard-ensure "Ensuring existing profile is present in native VPN Dashboard"
		verify_line="$(ensure_dashboard_profile_visible "$p" "$selector")" || {
			rc=$?
			echo "ADD_PROFILE_STATUS=FAIL selector=$selector peer=$p reason=dashboard_verification rc=$rc" >&2
			return 6
		}
		echo "$verify_line"
		echo "ADD_PROFILE_STATUS=SUCCESS selector=$selector peer=$p"
		echo "SUCCESS: $selector is present in VPN Client Profile and verified in the native VPN Dashboard."
		return 0
	fi

	gid="$(ensure_group)"
	f="$STATE/tmp/add-profile.$$.conf"
	add_progress 32 generator "Generating fresh AirVPN WireGuard profile (Generator Diagnostic fast path; adaptive fallback)"
	echo "Generating AirVPN profile: $selector"
	if ! generate_one "$selector" "$f"; then
		rm -f "$f" "$f.effective"
		echo "ADD_PROFILE_STATUS=FAIL selector=$selector reason=generation" >&2
		echo "Failed to generate profile for selector: $selector" >&2
		return 4
	fi

	add_progress 58 import-wireguard "Importing WireGuard peer into GL.iNet profile database"
	out="$(import_conf "$f" "$selector" "$gid" 1)" || {
		rm -f "$f" "$f.effective"
		echo "ADD_PROFILE_STATUS=FAIL selector=$selector reason=import" >&2
		echo "Failed to import generated profile for selector: $selector" >&2
		return 5
	}
	peer="$(printf '%s\n' "$out" | tail -n1 | cut -f1)"
	rm -f "$f" "$f.effective"
	[ -n "$peer" ] || { echo "ADD_PROFILE_STATUS=FAIL selector=$selector reason=missing_peer" >&2; return 5; }

	# A successful add means more than a UCI peer exists: force the native
	# Dashboard profile list to include this exact peer and verify it through
	# vpn-client.get_tunnel before returning success to the browser.
	add_progress 64 dashboard-ensure "Ensuring server is present in native VPN Dashboard"
	verify_line="$(ensure_dashboard_profile_visible "$peer" "$selector")" || {
		rc=$?
		echo "ADD_PROFILE_STATUS=FAIL selector=$selector peer=$peer reason=dashboard_verification rc=$rc" >&2
		echo "The WireGuard profile was imported, but '$selector' could not be verified in the native VPN Dashboard." >&2
		return 6
	}

	[ -n "$(get active_selector)" ] || { uci set "$CFG.active_selector=$selector"; uci commit airvpn_native; }
	echo "$out"
	echo "$verify_line"
	echo "ADD_PROFILE_STATUS=SUCCESS selector=$selector peer=$peer"
	echo "SUCCESS: Added $selector to VPN Client Profile and verified it in the native VPN Dashboard."
}

add_profile_selected() {
	selector="${1:-}"
	started_op="$(date +%s 2>/dev/null || echo 0)"
	lock_acquire add-profile || return $?
	add_progress 3 lock-acquired "AirVPN profile mutation lock acquired"
	rc=0
	add_profile_selected_inner "$selector" || rc=$?
	now_op="$(date +%s 2>/dev/null || echo 0)"
	elapsed_op=0
	case "$started_op:$now_op" in *[!0-9:]* ) ;; *) [ "$now_op" -ge "$started_op" ] 2>/dev/null && elapsed_op=$((now_op-started_op));; esac
	if [ "$rc" -ne 0 ]; then
		echo "ADD_PROFILE_FAIL stage=${ADD_CURRENT_STAGE_CODE:-unknown} code=$rc elapsed=${elapsed_op}s selector=$selector" >&2
		add_finish failed 100 "${ADD_CURRENT_STAGE_CODE:-unknown}" "FAILED at ${ADD_CURRENT_STAGE_CODE:-unknown} (code=$rc, elapsed=${elapsed_op}s)"
	else
		add_progress 100 complete "Server is verified in native VPN Dashboard"
		add_finish complete 100 complete "SUCCESS — server verified in native VPN Dashboard"
	fi
	lock_release
	return "$rc"
}

add_profile_job_start() {
	selector="${1:-}"
	[ -n "$selector" ] || { echo "server selector required" >&2; return 2; }
	jobs="$STATE/addjobs"
	mkdir -p "$jobs" || return 1
	chmod 700 "$jobs" 2>/dev/null || true
	job="add-$(date +%s)-$$"
	dir="$jobs/$job"
	mkdir -p "$dir" || return 1
	chmod 700 "$dir" 2>/dev/null || true
	started="$(date +%s 2>/dev/null || echo 0)"
	cat >"$dir/status" <<EOF
state=starting
percent=1
started=$started
stage_code=queued
stage=Queued Add server to profile operation
EOF
	: >"$dir/output"
	chmod 600 "$dir/status" "$dir/output" 2>/dev/null || true
	if command -v nohup >/dev/null 2>&1; then
		ADD_STATUS_FILE="$dir/status" ADD_STARTED="$started" nohup "$0" add-profile-job-run "$selector" "$job" >"$dir/output" 2>&1 </dev/null &
	else
		(ADD_STATUS_FILE="$dir/status" ADD_STARTED="$started" "$0" add-profile-job-run "$selector" "$job" >"$dir/output" 2>&1 </dev/null) &
	fi
	echo $! >"$dir/pid"
	echo "$job"
}

add_profile_job_run() {
	selector="${1:-}"; job="${2:-}"
	case "$job" in add-[0-9]*-[0-9]*) ;; *) return 2;; esac
	dir="$STATE/addjobs/$job"
	[ -d "$dir" ] || return 2
	export ADD_STATUS_FILE="$dir/status"
	[ -n "${ADD_STARTED:-}" ] || ADD_STARTED="$(sed -n 's/^started=//p' "$dir/status" | head -n1)"
	export ADD_STARTED
	add_progress 2 starting "Starting Add server to profile"
	if add_profile_selected "$selector"; then
		add_finish complete 100 complete "SUCCESS — server verified in native VPN Dashboard"
		return 0
	else
		rc=$?
		# add_profile_selected already emits the stage-coded ADD_PROFILE_FAIL line.
		add_finish failed 100 "${ADD_CURRENT_STAGE_CODE:-unknown}" "FAILED at ${ADD_CURRENT_STAGE_CODE:-unknown} (code=$rc)"
		return "$rc"
	fi
}

add_profile_job_status() {
	job="${1:-}"
	case "$job" in add-[0-9]*-[0-9]*) ;; *) echo "Invalid add-profile job id"; return 2;; esac
	dir="$STATE/addjobs/$job"
	[ -d "$dir" ] || { echo "Add-profile job not found"; return 3; }
	cat "$dir/status" 2>/dev/null || true
	started="$(sed -n 's/^started=//p' "$dir/status" 2>/dev/null | head -n1)"
	now="$(date +%s 2>/dev/null || echo 0)"
	case "$started" in ''|*[!0-9]*) elapsed=0;; *) elapsed=$((now-started)); [ "$elapsed" -ge 0 ] || elapsed=0;; esac
	state_now="$(sed -n 's/^state=//p' "$dir/status" 2>/dev/null | head -n1)"
	stage_code="$(sed -n 's/^stage_code=//p' "$dir/status" 2>/dev/null | head -n1)"
	# Hard ceiling for interactive profile addition. This is a last-resort guard;
	# generator/ubus requests are independently bounded. Polling performs cleanup
	# and records a pasteable stage-coded failure instead of leaving a lock wedged.
	if [ "$elapsed" -gt 120 ] && { [ "$state_now" = running ] || [ "$state_now" = starting ]; }; then
		pid="$(cat "$dir/pid" 2>/dev/null || true)"
		case "$pid" in ''|*[!0-9]*) ;; *)
			if kill -0 "$pid" 2>/dev/null; then
				cmdline="$(tr '\000' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
				case "$cmdline" in *airvpn-native*add-profile-job-run*) kill "$pid" 2>/dev/null || true;; esac
			fi;;
		esac
		lockpid="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
		[ "$lockpid" = "$pid" ] && rm -rf "$LOCKDIR" 2>/dev/null || true
		echo "ADD_PROFILE_FAIL stage=${stage_code:-unknown} code=124 elapsed=${elapsed}s reason=overall_timeout" >>"$dir/output"
		add_status_tmp="$dir/status.tmp.$$"
		{ echo "state=failed"; echo "percent=100"; echo "started=$started"; echo "stage_code=${stage_code:-unknown}"; echo "stage=FAILED — overall 120s safety limit at ${stage_code:-unknown}"; } >"$add_status_tmp"
		mv -f "$add_status_tmp" "$dir/status"
	fi
	echo "elapsed=$elapsed"
	echo "---OUTPUT---"
	cat "$dir/output" 2>/dev/null || true
}

sync_connect_selected() {
	selector="${1:-}"; [ -n "$selector" ] || { echo "server selector required" >&2; return 2; }
	lock_acquire sync-connect || return $?
	backup_current_state

	# Connect Now must be additive, not a full profile synchronization.  The old
	# path temporarily replaced main.selectors and called sync_profiles(), which
	# can remove every other AirVPN profile when cleanup_managed=1.
	peer="$(find_peer_for_selector "$selector" 2>/dev/null || true)"
	if [ -z "$peer" ]; then
		if ! add_profile_selected "$selector"; then
			echo "Could not add the selected AirVPN profile; rolling back." >&2
			rollback_state >/dev/null 2>&1 || true
			lock_release
			return 4
		fi
		peer="$(find_peer_for_selector "$selector" 2>/dev/null || true)"
	fi

	if [ -z "$peer" ]; then
		echo "Selected AirVPN profile was not found after profile creation; rolling back." >&2
		rollback_state >/dev/null 2>&1 || true
		lock_release
		return 5
	fi

	if ! ensure_dashboard_tunnel "$peer"; then
		echo "Could not create/update the GL.iNet VPN Dashboard tunnel for $selector; rolling back." >&2
		rollback_state >/dev/null 2>&1 || true
		lock_release
		return 6
	fi
	activation_started="$(date +%s 2>/dev/null || echo 0)"
	if ! enable_managed_peer_tunnel "$peer"; then
		echo "The AirVPN Dashboard tunnel exists but GL.iNet did not enable it; rolling back." >&2
		rollback_state >/dev/null 2>&1 || true
		lock_release
		return 6
	fi

	for rs in $(find_tunnels_for_peer "$peer"); do
		state="$(uci -q get route_policy.$rs.enabled 2>/dev/null || echo 0)"
		[ "$state" = "1" ] || {
			echo "GL.iNet Dashboard rule did not remain enabled after native activation; rolling back." >&2
			rollback_state >/dev/null 2>&1 || true
			lock_release
			return 6
		}
	done

	echo "Connecting to $selector..."
	echo "Waiting for a fresh WireGuard handshake (up to 30 seconds)..."

	if wait_for_managed_peer_connection "$peer" 30 "$activation_started"; then
		tmp="/tmp/airvpn-validate.$$"
		if connection_validate >"$tmp" 2>&1; then
			cat "$tmp"
			rm -f "$tmp"
			echo "connected_server=$selector"
			echo "connect_result=connected"
			uci set "$CFG.active_selector=$selector"
			uci commit airvpn_native
			vpn_power_status
			lock_release
			return 0
		fi
		rm -f "$tmp"
	fi

	tmp="/tmp/airvpn-validate.$$"
	connection_validate >"$tmp" 2>&1 || true
	cat "$tmp" >&2
	rm -f "$tmp"
	echo "Connect Now did not establish a WireGuard handshake within 30 seconds; restoring last-known-good state." >&2
	rollback_state >/dev/null 2>&1 || true
	lock_release
	return 7
}
