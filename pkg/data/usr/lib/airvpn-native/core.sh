#!/bin/sh
# AirVPN native plugin module — sourced by /usr/bin/airvpn-native.

lock_max_age() {
	case "${1:-unknown}" in
		add-profile) echo 150;;
		sync-connect) echo 210;;
		vpn-power-set) echo 90;;
		*) echo 300;;
	esac
}

lock_cleanup_owned() {
	oldpid="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
	[ "$oldpid" = "$$" ] && rm -rf "$LOCKDIR" 2>/dev/null || true
}

lock_acquire() {
	op="${1:-unknown}"
	mkdir -p "$STATE"
	if ! mkdir "$LOCKDIR" 2>/dev/null; then
		oldpid="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
		oldop="$(cat "$LOCKDIR/owner" 2>/dev/null || echo unknown)"
		oldstage="$(cat "$LOCKDIR/stage_code" 2>/dev/null || echo unknown)"
		started="$(cat "$LOCKDIR/started" 2>/dev/null || echo 0)"
		# Re-entrant calls (Connect Now -> Add Profile) share the same lock.
		if [ "$oldpid" = "$$" ]; then
			LOCK_DEPTH=$((LOCK_DEPTH+1))
			return 0
		fi
		live=0; cmdline=""
		case "$oldpid" in
			''|*[!0-9]*) live=0;;
			*)
				if kill -0 "$oldpid" 2>/dev/null; then
					cmdline="$(tr '\000' ' ' <"/proc/$oldpid/cmdline" 2>/dev/null || true)"
					case "$cmdline" in *airvpn-native*) live=1;; esac
				fi;;
		esac
		now="$(date +%s 2>/dev/null || echo 0)"
		case "$started" in ''|*[!0-9]*) started=0;; esac
		age=0; [ "$started" -gt 0 ] 2>/dev/null && [ "$now" -ge "$started" ] 2>/dev/null && age=$((now-started))
		max="$(lock_max_age "$oldop")"
		if [ "$live" -eq 1 ] && [ "$started" -gt 0 ] 2>/dev/null && [ "$age" -gt "$max" ] 2>/dev/null; then
			echo "Clearing timed-out AirVPN operation: operation=$oldop pid=$oldpid age=${age}s limit=${max}s." >&2
			kill "$oldpid" 2>/dev/null || true
			sleep 1
			kill -0 "$oldpid" 2>/dev/null && kill -9 "$oldpid" 2>/dev/null || true
			live=0
		fi
		if [ "$live" -eq 1 ]; then
			echo "Another AirVPN operation is already running: operation=$oldop pid=$oldpid age=${age}s stage=$oldstage." >&2
			return 75
		fi
		# Dead owner, timed-out owner, or PID reuse: reclaim the stale lock.
		rm -rf "$LOCKDIR" 2>/dev/null || true
		mkdir "$LOCKDIR" 2>/dev/null || { echo "Another AirVPN operation is already starting." >&2; return 75; }
	fi
	now="$(date +%s 2>/dev/null || echo 0)"
	printf '%s\n' "$$" >"$LOCKDIR/pid"
	printf '%s\n' "$op" >"$LOCKDIR/owner"
	printf '%s\n' "$now" >"$LOCKDIR/started"
	printf '%s\n' "starting" >"$LOCKDIR/stage_code"
	LOCK_DEPTH=1
	trap 'lock_cleanup_owned' EXIT
	trap 'lock_cleanup_owned; exit 130' INT
	trap 'lock_cleanup_owned; exit 143' TERM
	return 0
}

lock_release() {
	case "${LOCK_DEPTH:-0}" in ''|*[!0-9]*) LOCK_DEPTH=1;; esac
	if [ "$LOCK_DEPTH" -gt 1 ]; then
		LOCK_DEPTH=$((LOCK_DEPTH-1))
		return 0
	fi
	lock_cleanup_owned
	LOCK_DEPTH=0
	trap - EXIT INT TERM
}

# Record the current mutation stage both for UI progress and for lock diagnostics.
ADD_CURRENT_STAGE_CODE=idle

add_progress() {
	percent="$1"; code="$2"; shift 2; label="$*"
	ADD_CURRENT_STAGE_CODE="$code"
	if [ -d "$LOCKDIR" ] && [ "$(cat "$LOCKDIR/pid" 2>/dev/null || true)" = "$$" ]; then
		printf '%s\n' "$code" >"$LOCKDIR/stage_code" 2>/dev/null || true
		printf '%s\n' "$label" >"$LOCKDIR/stage" 2>/dev/null || true
	fi
	status_file="${ADD_STATUS_FILE:-}"
	[ -n "$status_file" ] || return 0
	started="${ADD_STARTED:-$(date +%s 2>/dev/null || echo 0)}"
	tmp="$status_file.tmp.$$"
	{
		echo "state=running"
		echo "percent=$percent"
		echo "started=$started"
		echo "stage_code=$code"
		echo "stage=$label"
	} >"$tmp" && mv -f "$tmp" "$status_file"
}

add_finish() {
	state="$1"; percent="$2"; code="$3"; shift 3; label="$*"
	ADD_CURRENT_STAGE_CODE="$code"
	status_file="${ADD_STATUS_FILE:-}"
	[ -n "$status_file" ] || return 0
	started="${ADD_STARTED:-$(date +%s 2>/dev/null || echo 0)}"
	tmp="$status_file.tmp.$$"
	{
		echo "state=$state"
		echo "percent=$percent"
		echo "started=$started"
		echo "stage_code=$code"
		echo "stage=$label"
	} >"$tmp" && mv -f "$tmp" "$status_file"
}
safe_json_count_servers() { grep -ao '"public_name"[[:space:]]*:' "$1" 2>/dev/null | wc -l | tr -d ' '; }

sanitize() {
	printf '%s' "$1" | tr ' /,:()' '______' | tr -cd 'A-Za-z0-9_.-'
}

fwver() {
	if [ -r /etc/glversion ]; then cat /etc/glversion | head -n1
	else ubus call system board 2>/dev/null | jsonfilter -e '@.release.version' 2>/dev/null || echo unknown
	fi
}

model_name() {
	ubus call system board 2>/dev/null | jsonfilter -e '@.model' 2>/dev/null || echo unknown
}

target_check() {
	strict="$(get strict_target)"; [ -n "$strict" ] || strict=1
	[ "$strict" = 1 ] || return 0
	fw="$(fwver)"
	model="$(model_name)"
	case "$model" in
		*"GL-MT6000"*|*"Flint 2"*) ;;
		*)
			echo "This build targets GL-MT6000 (Flint 2); detected model: $model" >&2
			return 20;;
	esac
	case "$fw" in
		4.9.1*|*4.9.1*) return 0;;
		*)
			echo "This build targets GL.iNet firmware 4.9.1; detected firmware: $fw" >&2
			return 21;;
	esac
}
