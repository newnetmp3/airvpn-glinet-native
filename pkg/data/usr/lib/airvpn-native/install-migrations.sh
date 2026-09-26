#!/bin/sh
# Upgrade cleanup kept separate from runtime paths.
set -u
STATE=/etc/airvpn-native
LOCK="$STATE/lock"

stop_owned_pid() {
	pid="$1"; pattern="$2"
	case "$pid" in ''|*[!0-9]*) return 0;; esac
	kill -0 "$pid" 2>/dev/null || return 0
	cmdline="$(tr '\000' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
	case "$cmdline" in *"$pattern"*) kill "$pid" 2>/dev/null || true; sleep 1; kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true;; esac
}

# Clear stale locks only when they belong to an AirVPN mutation process.
if [ -d "$LOCK" ]; then
	pid="$(cat "$LOCK/pid" 2>/dev/null || true)"
	op="$(cat "$LOCK/owner" 2>/dev/null || true)"
	case "$op" in add-profile|sync-connect|vpn-power-set|'') stop_owned_pid "$pid" airvpn-native;; esac
	rm -rf "$LOCK" 2>/dev/null || true
fi

# Stop stale generator diagnostic workers before removing their state.
for pf in "$STATE"/diagjobs/diag-*/pid; do
	[ -f "$pf" ] || continue
	pid="$(cat "$pf" 2>/dev/null || true)"
	stop_owned_pid "$pid" generator-diagnostic-run
done

# Migrate the old dedicated API-key file into UCI once.
uci_key="$(uci -q get airvpn_native.main.api_key 2>/dev/null || true)"
file_key="$(cat "$STATE/api.key" 2>/dev/null || true)"
if [ -z "$uci_key" ] && [ -n "$file_key" ]; then
	uci set "airvpn_native.main.api_key=$file_key" 2>/dev/null || true
	uci set airvpn_native.main.api_key_validated='0' 2>/dev/null || true
	uci set airvpn_native.main.api_key_validation_time='0' 2>/dev/null || true
	uci commit airvpn_native 2>/dev/null || true
	[ "$(uci -q get airvpn_native.main.api_key 2>/dev/null || true)" = "$file_key" ] && rm -f "$STATE/api.key" 2>/dev/null || true
fi
exit 0