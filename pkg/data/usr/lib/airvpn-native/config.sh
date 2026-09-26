#!/bin/sh
# AirVPN native plugin module — sourced by /usr/bin/airvpn-native.

validate_uint_range() {
	value="$1" min="$2" max="$3" label="$4"
	case "$value" in ''|*[!0-9]*) echo "$label must be a whole number." >&2; return 1;; esac
	[ "$value" -ge "$min" ] 2>/dev/null && [ "$value" -le "$max" ] 2>/dev/null || {
		echo "$label must be between $min and $max." >&2; return 1;
	}
}

setcfg() {
	k="$1"; v="${2-}"
	case "$k" in
		device|selectors|active_selector|protocol|resolve|ip_layer|dns_mode|mtu|keepalive|local_access|masquerade|group_name|prefix|cleanup_managed|auto_sync|target_firmware|strict_target|native_reload|discovery_mode|country_aliases|health_only|min_score|max_load|include_server|exclude_server|country_filter|use_server_discovery|sort_column|sort_direction|favorites|server_exclusions|latency_candidates|refresh_min_seconds|cache_min_servers|smart_rank|column_order|hidden_columns|generator_strategy) ;;
		*) echo "Invalid key" >&2; return 2;;
	esac
	# Reject control characters in text values that would corrupt UCI or later
	# line-oriented state files. Spaces are valid in selector/country names.
	clean="$(printf '%s' "$v" | tr -d '\r\n')"
	[ "$clean" = "$v" ] || { echo "$k contains unsupported line breaks." >&2; return 2; }
	case "$k" in
		mtu) [ -z "$v" ] || validate_uint_range "$v" 576 9000 "MTU" || return 2;;
		keepalive) [ -z "$v" ] || validate_uint_range "$v" 0 3600 "Persistent keepalive" || return 2;;
		max_load) [ -z "$v" ] || validate_uint_range "$v" 0 100 "Maximum load" || return 2;;
		latency_candidates) validate_uint_range "$v" 1 1000 "Latency candidates" || return 2;;
		refresh_min_seconds) validate_uint_range "$v" 10 86400 "Refresh minimum seconds" || return 2;;
		cache_min_servers) validate_uint_range "$v" 1 5000 "Minimum cached servers" || return 2;;
		sort_direction)
			[ -n "$v" ] || v=desc
			case "$v" in asc|desc) ;; *) echo "Sort direction must be asc or desc." >&2; return 2;; esac;;
		sort_column)
			[ -n "$v" ] || v=smart_rank
			case "$v" in name|country|city|score|load|bandwidth|effective_bandwidth|max_bandwidth|available_bandwidth|latency|smart_rank|users|health|entry_ip) ;; *) echo "Unsupported sort column: $v" >&2; return 2;; esac;;
		ip_layer) case "$v" in ipv4|ipv6|ipv4_ipv6|ipv6_ipv4) ;; *) echo "Unsupported IP layer: $v" >&2; return 2;; esac;;
		resolve) case "$v" in on|off) ;; *) echo "Resolve must be on or off." >&2; return 2;; esac;;
		generator_strategy) case "$v" in adaptive|preferred) ;; *) echo "Generator strategy must be adaptive or preferred." >&2; return 2;; esac;;
	esac
	uci set "$CFG.$k=$v" || return 2
	uci commit airvpn_native || return 2
}

background_refresh_schedule() {
	seed="$STATE/background-refresh.schedule"
	if [ -s "$seed" ]; then
		. "$seed"
		minute="${MINUTE:-}"
		offset="${HOUR_OFFSET:-}"
		printf 'minute=%s\nhour_offset=%s\n' "$minute" "$offset"
		if [ -f /etc/crontabs/root ]; then
			grep 'airvpn-native-background-refresh' /etc/crontabs/root 2>/dev/null || true
		fi
	else
		echo "not configured"
	fi
}
