#!/bin/sh
# AirVPN native plugin module — sourced by /usr/bin/airvpn-native.

normalize_generator_output() {
	src="$1"
	dst="$2"
	rm -f "$dst"

	# 1) Plain WireGuard profile.
	if grep -a -q '^\[Interface\]' "$src" 2>/dev/null && grep -a -q '^\[Peer\]' "$src" 2>/dev/null; then
		# If it is genuinely text, copy it. Binary archives may also contain those
		# strings, so reject files containing NUL bytes before treating as text.
		if ! LC_ALL=C grep -a -q "$(printf '\000')" "$src" 2>/dev/null; then
			cp "$src" "$dst"
			return 0
		fi
	fi

	# Read magic bytes without relying on the optional `file` utility.
	magic="$(od -An -tx1 -N4 "$src" 2>/dev/null | tr -d ' \n')"

	# 2) ZIP package. BusyBox on GL.iNet normally provides unzip; the standalone
	# unzip package is also supported.
	case "$magic" in
		504b0304|504b0506|504b0708)
			if command -v unzip >/dev/null 2>&1; then
				member="$(unzip -Z1 "$src" 2>/dev/null | grep -Ei '\.(conf|wg)$' | head -n1 || true)"
				[ -n "$member" ] || member="$(unzip -Z1 "$src" 2>/dev/null | head -n1 || true)"
				if [ -n "$member" ]; then
					unzip -p "$src" "$member" >"$dst" 2>/dev/null || true
					grep -q '^\[Interface\]' "$dst" 2>/dev/null && grep -q '^\[Peer\]' "$dst" 2>/dev/null && return 0
				fi
			fi
			;;
	esac

	# 3) gzip/tar.gz package.
	case "$magic" in
		1f8b*)
			td="$STATE/extract.$$"
			mkdir -p "$td"
			if tar -xzf "$src" -C "$td" >/dev/null 2>&1; then
				member="$(find "$td" -type f \( -name '*.conf' -o -name '*.wg' \) | head -n1)"
				[ -n "$member" ] || member="$(find "$td" -type f | head -n1)"
				if [ -n "$member" ]; then
					cp "$member" "$dst"
					rm -rf "$td"
					grep -q '^\[Interface\]' "$dst" 2>/dev/null && grep -q '^\[Peer\]' "$dst" 2>/dev/null && return 0
				fi
			fi
			rm -rf "$td"
			;;
	esac

	# 4) JSON wrapped response. Decode common escaped newlines/quotes without
	# requiring jq. jsonfilter handles simple fields if AirVPN names one `config`,
	# `content`, or `file`.
	first="$(dd if="$src" bs=1 count=1 2>/dev/null || true)"
	if [ "$first" = "{" ] || [ "$first" = "[" ]; then
		for expr in '@.config' '@.content' '@.file' '@[0].config' '@[0].content' '@[0].file'; do
			val="$(jsonfilter -i "$src" -e "$expr" 2>/dev/null || true)"
			[ -n "$val" ] || continue
			printf '%b\n' "$val" >"$dst"
			grep -q '^\[Interface\]' "$dst" 2>/dev/null && grep -q '^\[Peer\]' "$dst" 2>/dev/null && return 0
		done

		# Last-resort extraction for a JSON string containing an escaped WG config.
		# This is intentionally conservative and only succeeds when both sections
		# become valid line starts after unescaping.
		sed 's/\\r//g; s/\\n/\n/g; s/\\"/"/g; s/\\\\/\\/g' "$src" \
			| sed -n '/\[Interface\]/,$p' >"$dst" 2>/dev/null || true
		grep -q '^\[Interface\]' "$dst" 2>/dev/null && grep -q '^\[Peer\]' "$dst" 2>/dev/null && return 0
	fi

	# 5) A text package may contain headers or explanatory text before the actual
	# WireGuard profile. Strip everything before [Interface].
	awk 'BEGIN{s=0} /^\[Interface\]/{s=1} s{print}' "$src" >"$dst" 2>/dev/null || true
	grep -q '^\[Interface\]' "$dst" 2>/dev/null && grep -q '^\[Peer\]' "$dst" 2>/dev/null && return 0

	rm -f "$dst"
	return 1
}

generator_request() {
	selector="$1"; out="$2"; protocol="$3"; device="$4"; resolve="$5"; layer="$6"
	max_time="${7:-8}"; connect_time="${8:-4}"; auth_mode="${9:-header}"
	case "$max_time" in ''|*[!0-9]*) max_time=8;; esac
	case "$connect_time" in ''|*[!0-9]*) connect_time=4;; esac
	case "$auth_mode" in header|query|both) ;; *) echo "Unsupported generator auth mode: $auth_mode" >&2; return 20;; esac
	[ "$max_time" -ge 3 ] 2>/dev/null || max_time=3
	[ "$connect_time" -ge 2 ] 2>/dev/null || connect_time=2
	[ "$connect_time" -le "$max_time" ] 2>/dev/null || connect_time="$max_time"
	need_key
	err="$out.error"
	hdr="$out.headers"
	rm -f "$out" "$err" "$hdr"
	umask 077

	# Add-server can now reuse the exact authentication transport proven by the
	# Generator Diagnostic. Header auth remains the normal/safer default; query
	# and both are accepted only when a diagnostic proved that shape succeeds.
	curl_rc=0
	case "$auth_mode" in
		header)
			code="$(curl -sS --connect-timeout "$connect_time" --max-time "$max_time" \
				-H "API-KEY: $API_KEY" \
				-D "$hdr" -o "$out" -w '%{http_code}' -G "$API/generator/" \
				--data-urlencode 'format=json' \
				--data-urlencode 'system=linux' \
				--data-urlencode 'download=auto' \
				--data-urlencode "protocols=$protocol" \
				--data-urlencode "servers=$selector" \
				--data-urlencode "device=$device" \
				--data-urlencode "resolve=$resolve" \
				--data-urlencode "iplayer_entry=$layer" 2>"$err")" || curl_rc=$?
			;;
		query)
			code="$(curl -sS --connect-timeout "$connect_time" --max-time "$max_time" \
				-D "$hdr" -o "$out" -w '%{http_code}' -G "$API/generator/" \
				--data-urlencode "key=$API_KEY" \
				--data-urlencode 'format=json' \
				--data-urlencode 'system=linux' \
				--data-urlencode 'download=auto' \
				--data-urlencode "protocols=$protocol" \
				--data-urlencode "servers=$selector" \
				--data-urlencode "device=$device" \
				--data-urlencode "resolve=$resolve" \
				--data-urlencode "iplayer_entry=$layer" 2>"$err")" || curl_rc=$?
			;;
		both)
			code="$(curl -sS --connect-timeout "$connect_time" --max-time "$max_time" \
				-H "API-KEY: $API_KEY" \
				-D "$hdr" -o "$out" -w '%{http_code}' -G "$API/generator/" \
				--data-urlencode "key=$API_KEY" \
				--data-urlencode 'format=json' \
				--data-urlencode 'system=linux' \
				--data-urlencode 'download=auto' \
				--data-urlencode "protocols=$protocol" \
				--data-urlencode "servers=$selector" \
				--data-urlencode "device=$device" \
				--data-urlencode "resolve=$resolve" \
				--data-urlencode "iplayer_entry=$layer" 2>"$err")" || curl_rc=$?
			;;
	esac

	[ "$curl_rc" -eq 0 ] || return 14
	[ "$code" = "200" ] || return 10
	# AirVPN may report authorization failures as JSON with HTTP 200.
	auth_response_rejected "$out" && return 12

	norm="$out.normalized"
	if normalize_generator_output "$out" "$norm"; then
		mv "$norm" "$out"
		return 0
	fi
	rm -f "$norm"
	return 11
}

generator_timeout_for_attempt() {
	combo="$1"
	default_s="${GENERATOR_DEFAULT_MAX_TIME:-8}"
	min_s="${GENERATOR_MIN_ADAPTIVE_TIME:-6}"
	max_s="${GENERATOR_MAX_ADAPTIVE_TIME:-15}"
	case "$default_s" in ''|*[!0-9]*) default_s=8;; esac
	case "$min_s" in ''|*[!0-9]*) min_s=6;; esac
	case "$max_s" in ''|*[!0-9]*) max_s=15;; esac
	[ "$min_s" -le "$max_s" ] 2>/dev/null || min_s="$max_s"
	[ "$default_s" -ge "$min_s" ] 2>/dev/null || default_s="$min_s"
	[ "$default_s" -le "$max_s" ] 2>/dev/null || default_s="$max_s"
	avg_ms="$(generator_attempt_avg_ms "$combo" 2>/dev/null || true)"
	case "$avg_ms" in ''|*[!0-9]*) echo "$default_s"; return 0;; esac
	# Three times the observed successful average absorbs ordinary jitter without
	# returning to the old 30-second stall. Clamp to 6..15 seconds by default.
	sec=$(( (avg_ms * 3 + 999) / 1000 ))
	[ "$sec" -ge "$min_s" ] 2>/dev/null || sec="$min_s"
	[ "$sec" -le "$max_s" ] 2>/dev/null || sec="$max_s"
	echo "$sec"
}

known_good_generator_file() {
	printf '%s/.generator-known-good' "$CACHE_DIR"
}

known_good_bootstrap_marker() {
	printf '%s/.known-good-bootstrap-v0115' "$STATE"
}

save_known_good_generator() {
	kg_auth="$1"; kg_device_mode="$2"; kg_protocol="$3"; kg_layer="$4"; kg_resolve="$5"
	kg_elapsed="${6:-0}"; kg_source="${7:-diagnostic}"
	case "$kg_auth" in header|query|both) ;; *) return 2;; esac
	case "$kg_device_mode" in id|name) ;; *) return 2;; esac
	[ -n "$kg_protocol" ] && [ -n "$kg_layer" ] && [ -n "$kg_resolve" ] || return 2
	case "$kg_elapsed" in ''|*[!0-9]*) kg_elapsed=0;; esac
	mkdir -p "$CACHE_DIR" || return 1
	chmod 700 "$CACHE_DIR" 2>/dev/null || true
	kg_file="$(known_good_generator_file)"
	kg_tmp="$kg_file.tmp.$$"
	kg_fp="$(airvpn_key_fingerprint 2>/dev/null || true)"
	umask 077
	{
		echo "auth_mode=$kg_auth"
		echo "device_mode=$kg_device_mode"
		echo "protocol=$kg_protocol"
		echo "layer=$kg_layer"
		echo "resolve=$kg_resolve"
		echo "elapsed_ms=$kg_elapsed"
		echo "key_fingerprint=$kg_fp"
		echo "source=$kg_source"
		echo "saved=$(date +%s 2>/dev/null || echo 0)"
	} >"$kg_tmp" || return 1
	chmod 600 "$kg_tmp" 2>/dev/null || true
	mv -f "$kg_tmp" "$kg_file"
}

invalidate_known_good_generator() {
	rm -f "$(known_good_generator_file)" 2>/dev/null || true
}

load_known_good_generator() {
	kg_file="$(known_good_generator_file)"
	[ -r "$kg_file" ] || return 1
	kg_auth="$(sed -n 's/^auth_mode=//p' "$kg_file" | head -n1)"
	kg_device_mode="$(sed -n 's/^device_mode=//p' "$kg_file" | head -n1)"
	kg_protocol="$(sed -n 's/^protocol=//p' "$kg_file" | head -n1)"
	kg_layer="$(sed -n 's/^layer=//p' "$kg_file" | head -n1)"
	kg_resolve="$(sed -n 's/^resolve=//p' "$kg_file" | head -n1)"
	kg_elapsed="$(sed -n 's/^elapsed_ms=//p' "$kg_file" | head -n1)"
	kg_source="$(sed -n 's/^source=//p' "$kg_file" | head -n1)"
	kg_stored_fp="$(sed -n 's/^key_fingerprint=//p' "$kg_file" | head -n1)"
	case "$kg_auth" in header|query|both) ;; *) return 1;; esac
	case "$kg_device_mode" in id|name) ;; *) return 1;; esac
	[ -n "$kg_protocol" ] && [ -n "$kg_layer" ] && [ -n "$kg_resolve" ] || return 1
	case "$kg_elapsed" in ''|*[!0-9]*) kg_elapsed=0;; esac
	if [ -n "$kg_stored_fp" ]; then
		kg_current_fp="$(airvpn_key_fingerprint 2>/dev/null || true)"
		[ -n "$kg_current_fp" ] && [ "$kg_current_fp" = "$kg_stored_fp" ] || return 1
	fi
	printf '%s|%s|%s|%s|%s|%s|%s\n' "$kg_auth" "$kg_device_mode" "$kg_protocol" "$kg_layer" "$kg_resolve" "$kg_elapsed" "${kg_source:-diagnostic}"
}

known_good_timeout() {
	kg_elapsed="${1:-0}"
	case "$kg_elapsed" in ''|*[!0-9]*) kg_elapsed=0;; esac
	if [ "$kg_elapsed" -le 0 ] 2>/dev/null; then
		echo 8
		return 0
	fi
	# A known-good request should not need the old diagnostic 30-second window.
	# Give it 3x the measured successful duration, with 5..15 second bounds.
	kg_sec=$(( (kg_elapsed * 3 + 999) / 1000 ))
	[ "$kg_sec" -ge 5 ] 2>/dev/null || kg_sec=5
	[ "$kg_sec" -le 15 ] 2>/dev/null || kg_sec=15
	echo "$kg_sec"
}

bootstrap_known_good_from_diagnostics() {
	kg_marker="$(known_good_bootstrap_marker)"
	[ ! -e "$kg_marker" ] || return 1
	mkdir -p "$STATE" 2>/dev/null || true
	: >"$kg_marker" 2>/dev/null || true
	chmod 600 "$kg_marker" 2>/dev/null || true
	[ -d "$STATE/diagjobs" ] || return 1
	kg_current_fp="$(airvpn_key_fingerprint 2>/dev/null || true)"
	[ -n "$kg_current_fp" ] || return 1
	# Recover a known-good request shape from retained diagnostic output.
	for kg_dir in $(ls -1dt "$STATE"/diagjobs/diag-* 2>/dev/null); do
		kg_out="$kg_dir/output"
		[ -r "$kg_out" ] || continue
		kg_old_fp="$(sed -n 's/^API key fingerprint: //p' "$kg_out" | head -n1)"
		[ -n "$kg_old_fp" ] && [ "$kg_old_fp" = "$kg_current_fp" ] || continue
		kg_modes="$(sed -n 's/^Successful diagnostic variants: //p' "$kg_out" | tail -n1)"
		[ -n "$kg_modes" ] || continue
		kg_params="$(grep '^Generator parameters:' "$kg_out" 2>/dev/null | tail -n1)"
		kg_protocol="$(printf '%s\n' "$kg_params" | sed -n "s/.* protocol='\([^']*\)'.*/\1/p")"
		kg_layer="$(printf '%s\n' "$kg_params" | sed -n "s/.* layer='\([^']*\)'.*/\1/p")"
		kg_resolve="$(printf '%s\n' "$kg_params" | sed -n "s/.* resolve='\([^']*\)'.*/\1/p")"
		[ -n "$kg_protocol" ] && [ -n "$kg_layer" ] && [ -n "$kg_resolve" ] || continue
		# Prefer header authentication when older diagnostic output has no timing data.
		kg_variant=""
		case ",$kg_modes," in *,header-id,*) kg_variant=header-id;; esac
		if [ -z "$kg_variant" ]; then case ",$kg_modes," in *,header-name,*) kg_variant=header-name;; esac; fi
		if [ -z "$kg_variant" ]; then case ",$kg_modes," in *,query-id,*) kg_variant=query-id;; esac; fi
		if [ -z "$kg_variant" ]; then case ",$kg_modes," in *,both-id,*) kg_variant=both-id;; esac; fi
		[ -n "$kg_variant" ] || continue
		kg_auth="${kg_variant%-*}"; kg_device_mode="${kg_variant#*-}"
		save_known_good_generator "$kg_auth" "$kg_device_mode" "$kg_protocol" "$kg_layer" "$kg_resolve" 0 diagnostic-history || continue
		echo "Recovered known-good Generator Diagnostic method: auth=$kg_auth device=$kg_device_mode protocol=$kg_protocol layer=$kg_layer resolve=$kg_resolve."
		return 0
	done
	return 1
}

select_and_save_diagnostic_known_good() {
	kg_candidates="$1"; kg_protocol="$2"; kg_layer="$3"; kg_resolve="$4"
	[ -s "$kg_candidates" ] || return 1
	# Prefer header-auth successes because they keep the API key out of the URL.
	# Within that class choose the lowest measured elapsed time. Only if no header
	# variant worked do we choose the fastest query/both success.
	kg_best="$(awk -F '\t' '$1=="header" {if(!f || $3+0 < best){f=1;best=$3+0;line=$0}} END{if(f)print line}' "$kg_candidates")"
	[ -n "$kg_best" ] || kg_best="$(awk -F '\t' '{if(!f || $3+0 < best){f=1;best=$3+0;line=$0}} END{if(f)print line}' "$kg_candidates")"
	[ -n "$kg_best" ] || return 1
	kg_auth="$(printf '%s\n' "$kg_best" | cut -f1)"
	kg_device_mode="$(printf '%s\n' "$kg_best" | cut -f2)"
	kg_elapsed="$(printf '%s\n' "$kg_best" | cut -f3)"
	save_known_good_generator "$kg_auth" "$kg_device_mode" "$kg_protocol" "$kg_layer" "$kg_resolve" "$kg_elapsed" diagnostic || return 1
	printf '%s|%s|%s\n' "$kg_auth" "$kg_device_mode" "$kg_elapsed"
}

show_generator_error() {
	selector="$1"; out="$2"; protocol="$3"; device="$4"; resolve="$5"; layer="$6"; rc="$7"
	if [ "$rc" -eq 10 ]; then
		code="$(awk 'toupper($1) ~ /^HTTP\// {c=$2} END{print c}' "$out.headers" 2>/dev/null || true)"
		echo "AirVPN generator HTTP ${code:-error} for selector '$selector', device '$device'." >&2
	elif [ "$rc" -eq 12 ]; then
		echo "AirVPN generator rejected authorization for the saved API key/device pair." >&2
	elif [ "$rc" -eq 14 ]; then
		echo "AirVPN generator transport request timed out or failed before a usable HTTP response." >&2
	else
		echo "AirVPN returned HTTP 200 but not a WireGuard configuration." >&2
	fi
	echo "Attempt: selector='$selector' device='$device' protocol='$protocol' layer='$layer' resolve='$resolve'." >&2
	[ -s "$out" ] && {
		echo "AirVPN response:" >&2
		sed -n '1,12p' "$out" >&2
	}
	[ -s "$out.error" ] && {
		echo "curl error:" >&2
		sed -n '1,6p' "$out.error" >&2
	}
}

generate_one() {
	selector="$1"; out="$2"
	request_selector="$selector"
	if resolved="$(discover_selector "$selector" 2>/tmp/airvpn-discovery.$$)"; then
		[ -s /tmp/airvpn-discovery.$$ ] && cat /tmp/airvpn-discovery.$$ >&2
		rm -f /tmp/airvpn-discovery.$$
		selector="$resolved"
	else
		rc=$?
		[ -s /tmp/airvpn-discovery.$$ ] && cat /tmp/airvpn-discovery.$$ >&2
		rm -f /tmp/airvpn-discovery.$$
		echo "Server discovery failed for '$request_selector'; trying original selector." >&2
		selector="$request_selector"
	fi
	protocol="$(get protocol)"; [ -n "$protocol" ] || protocol=wireguard_1_udp_1637
	device_name="$(get device)"; [ -n "$device_name" ] || device_name=default
	device="${RESOLVED_DEVICE_ID:-$(cat "$STATE/device-id" 2>/dev/null || true)}"
	if [ -z "$device" ]; then
		resolve_airvpn_device "$device_name" || return 13
		device="$RESOLVED_DEVICE_ID"
	fi
	resolve="$(get resolve)"; [ -n "$resolve" ] || resolve=off
	layer="$(get ip_layer)"; [ -n "$layer" ] || layer=ipv4
	strategy="$(get generator_strategy)"; [ -n "$strategy" ] || strategy=adaptive

	# Reuse the request shape proven by Generator Diagnostic before probing alternatives.
	known_good=""
	if [ "$strategy" = adaptive ]; then
		known_good="$(load_known_good_generator 2>/dev/null || true)"
		if [ -z "$known_good" ]; then
			bootstrap_known_good_from_diagnostics >&2 || true
			known_good="$(load_known_good_generator 2>/dev/null || true)"
		fi
	fi
	known_good_exact_failed=""
	if [ -n "$known_good" ]; then
		kg_auth="${known_good%%|*}"; kg_rest="${known_good#*|}"
		kg_device_mode="${kg_rest%%|*}"; kg_rest="${kg_rest#*|}"
		kg_protocol="${kg_rest%%|*}"; kg_rest="${kg_rest#*|}"
		kg_layer="${kg_rest%%|*}"; kg_rest="${kg_rest#*|}"
		kg_resolve="${kg_rest%%|*}"; kg_rest="${kg_rest#*|}"
		kg_elapsed="${kg_rest%%|*}"; kg_source="${kg_rest#*|}"
		kg_combo="$kg_protocol|$kg_layer|$kg_resolve"
		kg_device="$device"
		if [ "$kg_device_mode" = name ]; then
			kg_device="${RESOLVED_DEVICE_NAME:-$(cat "$STATE/device-name" 2>/dev/null || true)}"
			[ -n "$kg_device" ] || kg_device="$device_name"
		fi
		kg_timeout="$(known_good_timeout "$kg_elapsed")"
		kg_connect=4; [ "$kg_timeout" -lt "$kg_connect" ] 2>/dev/null && kg_connect="$kg_timeout"
		echo "Trying Generator Diagnostic known-good method first: auth=$kg_auth device=$kg_device_mode protocol=$kg_protocol layer=$kg_layer resolve=$kg_resolve (ceiling ${kg_timeout}s, source=$kg_source)."
		kg_started="$(monotonic_ms)"
		if generator_request "$selector" "$out" "$kg_protocol" "$kg_device" "$kg_resolve" "$kg_layer" "$kg_timeout" "$kg_connect" "$kg_auth"; then
			kg_ended="$(monotonic_ms)"
			case "$kg_started:$kg_ended" in *[!0-9:]*) kg_actual=0;; *)
				if [ "$kg_ended" -ge "$kg_started" ] 2>/dev/null; then kg_actual=$((kg_ended-kg_started)); else kg_actual=0; fi;;
			esac
			record_generator_performance "$kg_combo" success "$kg_actual"
			{
				echo "protocol=$kg_protocol"
				echo "layer=$kg_layer"
				echo "resolve=$kg_resolve"
			} >"$out.effective"
			rm -f "$out.error" "$out.headers"
			save_cached_attempt "$request_selector" "$kg_protocol" "$kg_layer" "$kg_resolve"
			save_known_good_generator "$kg_auth" "$kg_device_mode" "$kg_protocol" "$kg_layer" "$kg_resolve" "$kg_actual" add-server-verified || true
			echo "Known-good Generator Diagnostic method succeeded in ${kg_actual}ms; fallback probing skipped."
			return 0
		else
			kg_rc=$?
			kg_ended="$(monotonic_ms)"
			case "$kg_started:$kg_ended" in *[!0-9:]*) kg_actual=0;; *)
				if [ "$kg_ended" -ge "$kg_started" ] 2>/dev/null; then kg_actual=$((kg_ended-kg_started)); else kg_actual=0; fi;;
			esac
			record_generator_performance "$kg_combo" failure "$kg_actual"
			echo "Known-good Generator Diagnostic method failed after ${kg_actual}ms (rc=$kg_rc); forgetting it and falling back safely." >&2
			show_generator_error "$selector" "$out" "$kg_protocol" "$kg_device" "$kg_resolve" "$kg_layer" "$kg_rc"
			invalidate_known_good_generator
			if [ "$kg_auth" = header ] && [ "$kg_device_mode" = id ]; then
				known_good_exact_failed="$kg_combo"
			fi
			if [ "$kg_rc" -eq 14 ]; then
				echo "Transport failure: skipping additional generator probes to avoid repeated timeout stalls." >&2
				return 14
			fi
			if [ "$kg_rc" -eq 12 ] && [ "$kg_auth" = header ] && [ "$kg_device_mode" = id ]; then
				return 12
			fi
		fi
	fi

	# Use the global known-good request shape before per-selector timing data.
	attempts=""
	adaptive=""
	adaptive_source=""
	adaptive_avg=""
	if [ "$strategy" = adaptive ]; then
		perf="$(fastest_generator_attempt 2>/dev/null || true)"
		if [ -n "$perf" ]; then
			adaptive="$(printf '%s\n' "$perf" | cut -f1)"
			adaptive_avg="$(printf '%s\n' "$perf" | cut -f2)"
			adaptive_source=timed
		elif adaptive="$(most_common_cached_attempt 2>/dev/null || true)"; [ -n "$adaptive" ]; then
			adaptive_source=successful-cache-bootstrap
		fi
	fi
	cached="$(load_cached_attempt "$request_selector" 2>/dev/null || true)"

	add_attempt() {
		a="$1"
		[ -n "$a" ] || return 0
		case "
$attempts
" in *"
$a
"*) return 0;; esac
		attempts="${attempts}${attempts:+
}$a"
	}

	if [ -n "$adaptive" ]; then
		add_attempt "$adaptive"
		if [ "$adaptive_source" = timed ]; then
			echo "Adaptive AirVPN generator default: $adaptive (historical average ${adaptive_avg}ms)."
		else
			echo "Adaptive AirVPN generator bootstrap: $adaptive (most common prior successful combination)."
		fi
	fi
	if [ -n "$cached" ]; then
		add_attempt "$cached"
		[ "$cached" = "$adaptive" ] || echo "Cached AirVPN generator combination found for '$request_selector': $cached"
	fi

	add_attempt "$protocol|$layer|$resolve"
	[ "$layer" = "ipv6" ] && add_attempt "$protocol|ipv6|off"
	add_attempt "$protocol|ipv4|$resolve"
	add_attempt "$protocol|ipv4|off"
	[ "$protocol" != "wireguard_1_udp_1637" ] && add_attempt "wireguard_1_udp_1637|ipv4|off"

	seen="$known_good_exact_failed"
	last_rc=1
	oldIFS="$IFS"; IFS='
'
	for a in $attempts; do
		[ -n "$a" ] || continue
		case "
$seen
" in *"
$a
"*) continue;; esac
		seen="${seen}${seen:+
}$a"
		p="${a%%|*}"
		rest="${a#*|}"
		l="${rest%%|*}"
		r="${rest#*|}"

		if [ -n "$adaptive" ] && [ "$a" = "$adaptive" ]; then
			echo "Trying adaptive AirVPN generator: selector=$selector protocol=$p layer=$l resolve=$r"
		elif [ -n "$cached" ] && [ "$a" = "$cached" ]; then
			echo "Trying selector-cached AirVPN generator: selector=$selector protocol=$p layer=$l resolve=$r"
		else
			echo "Trying AirVPN generator: selector=$selector protocol=$p layer=$l resolve=$r"
		fi

		request_timeout="$(generator_timeout_for_attempt "$a")"
		connect_timeout=4
		[ "$request_timeout" -lt "$connect_timeout" ] 2>/dev/null && connect_timeout="$request_timeout"
		echo "Generator request ceiling: ${request_timeout}s (adaptive; old ceiling was 30s)."
		attempt_started="$(monotonic_ms)"
		if generator_request "$selector" "$out" "$p" "$device" "$r" "$l" "$request_timeout" "$connect_timeout"; then
			attempt_ended="$(monotonic_ms)"
			case "$attempt_started:$attempt_ended" in *[!0-9:]*) elapsed_ms=0;; *)
				if [ "$attempt_ended" -ge "$attempt_started" ] 2>/dev/null; then elapsed_ms=$((attempt_ended-attempt_started)); else elapsed_ms=0; fi;;
			esac
			record_generator_performance "$a" success "$elapsed_ms"
			{
				echo "protocol=$p"
				echo "layer=$l"
				echo "resolve=$r"
			} >"$out.effective"
			rm -f "$out.error" "$out.headers"

			save_cached_attempt "$request_selector" "$p" "$l" "$r"
			# A normal header/id Add Server success is itself proof of a working
			# request shape, so future adaptive adds can take the same direct path.
			save_known_good_generator header id "$p" "$l" "$r" "$elapsed_ms" add-server-learned || true
			echo "AirVPN generator succeeded in ${elapsed_ms}ms: protocol=$p layer=$l resolve=$r"
			new_fast="$(fastest_generator_attempt 2>/dev/null || true)"
			if [ -n "$new_fast" ]; then
				fast_combo="$(printf '%s\n' "$new_fast" | cut -f1)"
				fast_avg="$(printf '%s\n' "$new_fast" | cut -f2)"
				echo "Learned adaptive default: $fast_combo (average ${fast_avg}ms)."
			fi
			IFS="$oldIFS"
			return 0
		else
			last_rc=$?
			attempt_ended="$(monotonic_ms)"
			case "$attempt_started:$attempt_ended" in *[!0-9:]*) elapsed_ms=0;; *)
				if [ "$attempt_ended" -ge "$attempt_started" ] 2>/dev/null; then elapsed_ms=$((attempt_ended-attempt_started)); else elapsed_ms=0; fi;;
			esac
			record_generator_performance "$a" failure "$elapsed_ms"
			echo "AirVPN generator attempt failed after ${elapsed_ms}ms: protocol=$p layer=$l resolve=$r" >&2
			if [ "$last_rc" -eq 12 ]; then
				show_generator_error "$selector" "$out" "$p" "$device" "$r" "$l" "$last_rc"
				echo "The API key passed userinfo, so verify the configured AirVPN device and key/device permissions before replacing the key." >&2
				IFS="$oldIFS"
				return 12
			fi
			if [ "$last_rc" -eq 14 ]; then
				# A transport timeout is not evidence that protocol/layer/resolve is
				# wrong. Trying the same endpoint repeatedly with different query
				# values only multiplies the wait, so fail this add quickly.
				show_generator_error "$selector" "$out" "$p" "$device" "$r" "$l" "$last_rc"
				echo "Transport failure: skipping generator configuration fallbacks to avoid repeated timeout stalls." >&2
				IFS="$oldIFS"
				return 14
			fi
			# A stale per-selector result should not remain preferred after failing.
			if [ -n "$cached" ] && [ "$a" = "$cached" ]; then
				cf="$(cache_file_for_selector "$request_selector")"
				rm -f "$cf"
				echo "Selector-cached combination failed; cache entry removed and fresh probing continues." >&2
			fi
			show_generator_error "$selector" "$out" "$p" "$device" "$r" "$l" "$last_rc"
		fi
	done
	IFS="$oldIFS"
	return "$last_rc"
}

airvpn_key_fingerprint() {
	need_key
	if command -v sha256sum >/dev/null 2>&1; then
		printf '%s' "$API_KEY" | sha256sum | awk '{print substr($1,1,16)}'
	elif command -v md5sum >/dev/null 2>&1; then
		printf '%s' "$API_KEY" | md5sum | awk '{print "md5:" substr($1,1,12)}'
	else
		printf '%s' "$API_KEY" | cksum | awk '{print "cksum:" $1}'
	fi
}

diagnostic_pick_server() {
	# Diagnostics need one unused server; avoid building the full catalog here.
	mkdir -p "$STATE/tmp"
	names="$STATE/tmp/diag-server-names.$$"
	managed="$STATE/tmp/diag-managed-selectors.$$"
	rm -f "$names" "$managed" 2>/dev/null || true
	: >"$managed"

	status="$raw_status_cache_file"
	if [ ! -s "$status" ]; then
		diag_progress 36 "3/5 — Server cache missing; downloading AirVPN status (30s maximum)"
		raw_status_refresh >/dev/null 2>&1 || { rm -f "$names" "$managed"; return 1; }
	fi
	[ -s "$status" ] || { rm -f "$names" "$managed"; return 1; }

	diag_progress 38 "3/5 — Reading cached AirVPN server names"
	jsonfilter -i "$status" -e '@.servers[*].public_name' >"$names" 2>/dev/null || true
	[ -s "$names" ] || jsonfilter -i "$status" -e '@.servers[*].name' >"$names" 2>/dev/null || true
	[ -s "$names" ] || { rm -f "$names" "$managed"; return 1; }

	diag_progress 40 "3/5 — Reading existing AirVPN profiles"
	# Build the managed-selector set once before scanning candidates.
	for p in $(managed_peer_ids); do
		sel="$(uci -q get "wireguard.$p.airvpn_selector" 2>/dev/null || true)"
		[ -n "$sel" ] && printf '%s\n' "$sel" >>"$managed"
	done

	diag_progress 42 "3/5 — Choosing an unmanaged diagnostic server"
	choice="$(awk 'NR==FNR { if (NF) used[tolower($0)]=1; next } NF && !used[tolower($0)] { print; exit }' "$managed" "$names" 2>/dev/null || true)"
	rm -f "$names" "$managed" 2>/dev/null || true
	[ -n "$choice" ] || return 1
	printf '%s\n' "$choice"
}

diagnostic_http_code() {
	hdr="$1"
	awk 'toupper($1) ~ /^HTTP\// {c=$2} END{print c}' "$hdr" 2>/dev/null || true
}

diagnostic_safe_headers() {
	hdr="$1"
	[ -s "$hdr" ] || return 0
	grep -Ei '^(HTTP/|content-type:|content-length:|retry-after:|x-ratelimit|x-rate-limit|date:|server:|location:)' "$hdr" 2>/dev/null | sed -n '1,20p' || true
}

diagnostic_generator_request() {
	selector="$1"; out="$2"; protocol="$3"; device="$4"; resolve="$5"; layer="$6"; mode="$7"
	err="$out.error"; hdr="$out.headers"; norm="$out.normalized"
	rm -f "$out" "$err" "$hdr" "$norm"
	umask 077

	case "$mode" in
		header)
			code="$(curl -sS --connect-timeout 8 --max-time 30 \
				-H "API-KEY: $API_KEY" -D "$hdr" -o "$out" -w '%{http_code}' -G "$API/generator/" \
				--data-urlencode 'format=json' --data-urlencode 'system=linux' --data-urlencode 'download=auto' \
				--data-urlencode "protocols=$protocol" --data-urlencode "servers=$selector" \
				--data-urlencode "device=$device" --data-urlencode "resolve=$resolve" \
				--data-urlencode "iplayer_entry=$layer" 2>"$err" || true)";;
		query)
			code="$(curl -sS --connect-timeout 8 --max-time 30 \
				-D "$hdr" -o "$out" -w '%{http_code}' -G "$API/generator/" \
				--data-urlencode "key=$API_KEY" \
				--data-urlencode 'format=json' --data-urlencode 'system=linux' --data-urlencode 'download=auto' \
				--data-urlencode "protocols=$protocol" --data-urlencode "servers=$selector" \
				--data-urlencode "device=$device" --data-urlencode "resolve=$resolve" \
				--data-urlencode "iplayer_entry=$layer" 2>"$err" || true)";;
		both)
			code="$(curl -sS --connect-timeout 8 --max-time 30 \
				-H "API-KEY: $API_KEY" -D "$hdr" -o "$out" -w '%{http_code}' -G "$API/generator/" \
				--data-urlencode "key=$API_KEY" \
				--data-urlencode 'format=json' --data-urlencode 'system=linux' --data-urlencode 'download=auto' \
				--data-urlencode "protocols=$protocol" --data-urlencode "servers=$selector" \
				--data-urlencode "device=$device" --data-urlencode "resolve=$resolve" \
				--data-urlencode "iplayer_entry=$layer" 2>"$err" || true)";;
		*) return 20;;
	esac

	[ "$code" = 200 ] || return 10
	auth_response_rejected "$out" && return 12
	if normalize_generator_output "$out" "$norm"; then return 0; fi
	return 11
}

diagnostic_profile_summary() {
	f="$1"
	[ -s "$f" ] || return 0
	awk '
		/^\[Interface\]/ {print; next}
		/^\[Peer\]/ {print; next}
		/^[[:space:]]*PrivateKey[[:space:]]*=/ {print "PrivateKey = <redacted>"; next}
		/^[[:space:]]*PresharedKey[[:space:]]*=/ {print "PresharedKey = <redacted>"; next}
		/^[[:space:]]*(Address|DNS|MTU|PublicKey|Endpoint|AllowedIPs|PersistentKeepalive)[[:space:]]*=/ {print}
	' "$f" | sed -n '1,24p'
}

diag_progress() {
	status_file="${DIAG_STATUS_FILE:-}"
	percent="$1"; shift
	stage="$*"
	[ -n "$status_file" ] || return 0
	started="${DIAG_STARTED:-$(date +%s)}"
	tmp="$status_file.tmp.$$"
	{
		echo "state=running"
		echo "percent=$percent"
		echo "started=$started"
		echo "stage=$stage"
	} >"$tmp" && mv -f "$tmp" "$status_file"
}

diag_finish() {
	status_file="${DIAG_STATUS_FILE:-}"
	state="$1"; percent="$2"; shift 2
	stage="$*"
	[ -n "$status_file" ] || return 0
	started="${DIAG_STARTED:-$(date +%s)}"
	tmp="$status_file.tmp.$$"
	{
		echo "state=$state"
		echo "percent=$percent"
		echo "started=$started"
		echo "stage=$stage"
	} >"$tmp" && mv -f "$tmp" "$status_file"
}

generator_diagnostic() {
	requested="${1:-}"
	need_key
	mkdir -p "$STATE/tmp"
	chmod 700 "$STATE" "$STATE/tmp" 2>/dev/null || true
	tmpdir="$STATE/tmp/generator-diag.$$"
	rm -rf "$tmpdir" 2>/dev/null || true
	mkdir -p "$tmpdir" || return 1
	chmod 700 "$tmpdir" 2>/dev/null || true

	echo "AirVPN Generator Diagnostic v$PLUGIN_VERSION"
	echo "========================================"
	echo "Purpose: exercise AirVPN profile generation without importing or changing VPN Dashboard state."
	echo "API base: $API"
	if [ -n "$(get api_key)" ]; then key_source="OpenWrt UCI"; else key_source="legacy file fallback"; fi
	echo "API key source: $key_source"
	echo "API key length: ${#API_KEY}"
	echo "API key fingerprint: $(airvpn_key_fingerprint)"
	echo "Stored validation flag: $(get api_key_validated)"
	echo "Stored validation time: $(get api_key_validation_time)"
	echo

	diag_progress 5 "1/5 — Checking AirVPN account authorization"
	echo "[1/5] User account authorization"
	userinfo="$tmpdir/userinfo.json"
	if api_userinfo_request "$userinfo" "$API_KEY"; then
		login="$(jsonfilter -i "$userinfo" -e '@.user.login' 2>/dev/null || true)"
		echo "PASS userinfo authorization${login:+ (login=$login)}"
	else
		rc=$?
		echo "FAIL userinfo authorization rc=$rc"
		echo "OVERALL RESULT: FAIL"
		[ -s "$userinfo" ] && { echo "Response:"; sed -n '1,12p' "$userinfo"; }
		[ -s "$userinfo.error" ] && { echo "curl:"; sed -n '1,8p' "$userinfo.error"; }
		rm -rf "$tmpdir"
		return 0
	fi
	echo

	diag_progress 20 "2/5 — Reading AirVPN account devices"
	echo "[2/5] Account devices"
	devjson="$tmpdir/devices.json"
	if api_devices_request "$devjson" "$API_KEY"; then
		echo "PASS device-list authorization"
		ids="$tmpdir/device.ids"; names="$tmpdir/device.names"
		jsonfilter -i "$devjson" -e '@.devices[*].id' >"$ids" 2>/dev/null || true
		jsonfilter -i "$devjson" -e '@.devices[*].name' >"$names" 2>/dev/null || true
		exec 3<"$names"
		while IFS= read -r id; do IFS= read -r name <&3 || name=""; [ -n "$id" ] && echo "device id=$id name=$name"; done <"$ids"
		exec 3<&-
	else
		rc=$?
		echo "FAIL device-list authorization rc=$rc"
		echo "OVERALL RESULT: FAIL"
		[ -s "$devjson" ] && { echo "Response:"; sed -n '1,16p' "$devjson"; }
		[ -s "$devjson.error" ] && { echo "curl:"; sed -n '1,8p' "$devjson.error"; }
		rm -rf "$tmpdir"
		return 0
	fi

	configured_device="$(get device)"; [ -n "$configured_device" ] || configured_device=default
	resolved="$(resolve_device_id_from_json "$devjson" "$configured_device" 2>/dev/null || true)"
	if [ -z "$resolved" ]; then
		echo "FAIL configured device '$configured_device' did not resolve and the account has multiple/no usable devices."
		echo "OVERALL RESULT: FAIL"
		rm -rf "$tmpdir"
		return 0
	fi
	device_id="${resolved%%|*}"; device_name="${resolved#*|}"
	configured_lc="$(printf '%s' "$configured_device" | tr '[:upper:]' '[:lower:]')"
	device_name_lc="$(printf '%s' "$device_name" | tr '[:upper:]' '[:lower:]')"
	if [ "$configured_device" != "$device_id" ] && [ "$configured_lc" != "$device_name_lc" ]; then
		echo "WARN configured device '$configured_device' is not present; because the account exposes one device, diagnostic will use '$device_name' (id=$device_id)."
	else
		echo "Resolved configured device: '$configured_device' -> name='$device_name' id='$device_id'"
	fi
	echo

	diag_progress 35 "3/5 — Selecting a fresh diagnostic server"
	echo "[3/5] Fresh diagnostic server"
	selector="$requested"
	if [ -z "$selector" ]; then selector="$(diagnostic_pick_server 2>/dev/null || true)"; fi
	if [ -z "$selector" ]; then
		echo "FAIL no uncached/unmanaged server could be selected. Download Servers first or enter an exact server name in the diagnostic field."
		echo "OVERALL RESULT: FAIL"
		rm -rf "$tmpdir"
		return 0
	fi
	if find_peer_for_selector "$selector" >/dev/null 2>&1; then
		echo "NOTE requested server '$selector' already exists in VPN Client Profile; generation is still forced and no cached profile is reused."
	else
		echo "Selected unmanaged server: $selector"
	fi
	protocol="$(get protocol)"; [ -n "$protocol" ] || protocol=wireguard_1_udp_1637
	resolve="$(get resolve)"; [ -n "$resolve" ] || resolve=off
	layer="$(get ip_layer)"; [ -n "$layer" ] || layer=ipv4
	echo "Generator parameters: server='$selector' protocol='$protocol' layer='$layer' resolve='$resolve'"
	echo

	diag_progress 45 "4/5 — Preparing generator authorization matrix"
	echo "[4/5] Generator authorization/profile matrix"
	success_modes=""
	known_good_candidates="$tmpdir/known-good.tsv"
	: >"$known_good_candidates"
	attempt_no=0
	for mode in header query both; do
		attempt_no=$((attempt_no + 1))
		case "$attempt_no" in 1) pct=52;; 2) pct=64;; *) pct=76;; esac
		diag_progress "$pct" "4/5 — Generator attempt $attempt_no/4: auth=$mode, device ID $device_id (30s timeout)"
		out="$tmpdir/generator-$mode.out"
		diag_started="$(monotonic_ms)"
		if diagnostic_generator_request "$selector" "$out" "$protocol" "$device_id" "$resolve" "$layer" "$mode"; then rc=0; else rc=$?; fi
		diag_ended="$(monotonic_ms)"
		case "$diag_started:$diag_ended" in *[!0-9:]*) diag_elapsed=0;; *)
			if [ "$diag_ended" -ge "$diag_started" ] 2>/dev/null; then diag_elapsed=$((diag_ended-diag_started)); else diag_elapsed=0; fi;;
		esac
		code="$(diagnostic_http_code "$out.headers")"
		echo "--- auth=$mode device=id:$device_id http=${code:-none} rc=$rc elapsed=${diag_elapsed}ms ---"
		diagnostic_safe_headers "$out.headers"
		case "$rc" in
			0)
				echo "PASS AirVPN produced a valid WireGuard profile."
				diagnostic_profile_summary "$out.normalized"
				success_modes="${success_modes}${success_modes:+,}$mode-id"
				printf '%s\t%s\t%s\n' "$mode" id "$diag_elapsed" >>"$known_good_candidates";;
			12)
				echo "FAIL authorization: AirVPN returned Not authorized."
				[ -s "$out" ] && sed -n '1,12p' "$out";;
			10)
				echo "FAIL HTTP/transport response."
				[ -s "$out" ] && sed -n '1,12p' "$out"
				[ -s "$out.error" ] && sed -n '1,8p' "$out.error";;
			11)
				echo "FAIL HTTP 200 but response was not a usable WireGuard profile."
				[ -s "$out" ] && sed -n '1,16p' "$out";;
			*) echo "FAIL unexpected diagnostic rc=$rc";;
		esac
		echo
	done

	if [ "$device_name" != "$device_id" ]; then
		diag_progress 88 "4/5 — Generator attempt 4/4: header auth, device name $device_name (30s timeout)"
		out="$tmpdir/generator-header-name.out"
		diag_started="$(monotonic_ms)"
		if diagnostic_generator_request "$selector" "$out" "$protocol" "$device_name" "$resolve" "$layer" header; then rc=0; else rc=$?; fi
		diag_ended="$(monotonic_ms)"
		case "$diag_started:$diag_ended" in *[!0-9:]*) diag_elapsed=0;; *)
			if [ "$diag_ended" -ge "$diag_started" ] 2>/dev/null; then diag_elapsed=$((diag_ended-diag_started)); else diag_elapsed=0; fi;;
		esac
		code="$(diagnostic_http_code "$out.headers")"
		echo "--- auth=header device=name:$device_name http=${code:-none} rc=$rc elapsed=${diag_elapsed}ms ---"
		case "$rc" in
			0) echo "PASS AirVPN produced a valid profile when device NAME was supplied."; diagnostic_profile_summary "$out.normalized"; success_modes="${success_modes}${success_modes:+,}header-name"; printf '%s\t%s\t%s\n' header name "$diag_elapsed" >>"$known_good_candidates";;
			12) echo "FAIL authorization: Not authorized."; [ -s "$out" ] && sed -n '1,12p' "$out";;
			10) echo "FAIL HTTP/transport."; [ -s "$out.error" ] && sed -n '1,8p' "$out.error";;
			11) echo "FAIL response was not a usable WireGuard profile."; [ -s "$out" ] && sed -n '1,16p' "$out";;
		esac
		echo
	fi

	diag_progress 96 "5/5 — Interpreting generator results"
	echo "[5/5] Interpretation"
	if diag_known="$(select_and_save_diagnostic_known_good "$known_good_candidates" "$protocol" "$layer" "$resolve" 2>/dev/null)"; then
		diag_auth="${diag_known%%|*}"; diag_rest="${diag_known#*|}"; diag_device_mode="${diag_rest%%|*}"; diag_elapsed="${diag_rest#*|}"
		echo "Saved Add Server known-good method: auth=$diag_auth device=$diag_device_mode protocol=$protocol layer=$layer resolve=$resolve elapsed=${diag_elapsed}ms"
		case "$diag_auth" in query|both) echo "NOTE: header-only authentication did not provide the selected successful method; Add Server may use the diagnostic-proven query-key transport until a header method is proven.";; esac
	else
		echo "No known-good Add Server generator method was saved."
	fi
	echo "Fallback request shape when no diagnostic method is available: auth=header, device=id:$device_id"
	if [ -n "$success_modes" ]; then
		echo "Successful diagnostic variants: $success_modes"
		case ",$success_modes," in
			*,header-id,*)
				echo "RESULT: preferred header-auth/device-ID generation works and has been saved as an Add Server fast path."
				echo "OVERALL RESULT: PASS";;
			*,header-name,*)
				echo "RESULT: device-NAME generation works. The compatibility request shape has been saved and Add Server can use it directly."
				echo "OVERALL RESULT: PASS";;
			*,query-id,*|*,both-id,*)
				echo "RESULT: a query-key compatibility transport works. It has been saved because header-only generation did not succeed; rerunning the diagnostic later can replace it with a header-auth method if available."
				echo "OVERALL RESULT: PASS";;
			*)
				echo "RESULT: at least one generator variant succeeded and a known-good Add Server method was saved."
				echo "OVERALL RESULT: PASS";;
		esac
	else
		echo "RESULT: userinfo and device listing were authorized, but every generator-profile attempt failed. This strongly isolates the problem to AirVPN generator authorization/parameters for this API key/device/server combination."
		echo "OVERALL RESULT: FAIL"
	fi
	echo "No generated profile was imported and VPN Dashboard state was not modified."
	rm -rf "$tmpdir"
	return 0
}

generator_diagnostic_start() {
	requested="${1:-}"
	jobs="$STATE/diagjobs"
	mkdir -p "$jobs" || return 1
	chmod 700 "$jobs" 2>/dev/null || true
	job="diag-$(date +%s)-$$"
	dir="$jobs/$job"
	mkdir -p "$dir" || return 1
	chmod 700 "$dir" 2>/dev/null || true
	started="$(date +%s)"
	cat >"$dir/status" <<EOF
state=starting
percent=1
started=$started
stage=Starting generator/profile diagnostic
EOF
	: >"$dir/output"
	chmod 600 "$dir/status" "$dir/output" 2>/dev/null || true
	if command -v nohup >/dev/null 2>&1; then
		DIAG_STATUS_FILE="$dir/status" DIAG_STARTED="$started" nohup "$0" generator-diagnostic-run "$requested" "$job" >"$dir/output" 2>&1 </dev/null &
	else
		(DIAG_STATUS_FILE="$dir/status" DIAG_STARTED="$started" "$0" generator-diagnostic-run "$requested" "$job" >"$dir/output" 2>&1 </dev/null) &
	fi
	echo $! >"$dir/pid"
	echo "$job"
}

generator_diagnostic_run() {
	requested="${1:-}"; job="${2:-}"
	case "$job" in diag-[0-9]*-[0-9]*) ;; *) return 2;; esac
	dir="$STATE/diagjobs/$job"
	[ -d "$dir" ] || return 2
	export DIAG_STATUS_FILE="$dir/status"
	[ -n "${DIAG_STARTED:-}" ] || DIAG_STARTED="$(sed -n 's/^started=//p' "$dir/status" | head -n1)"
	export DIAG_STARTED
	diag_progress 2 "Initializing diagnostic"
	if (generator_diagnostic "$requested"); then
		if grep -q '^OVERALL RESULT: PASS$' "$dir/output" 2>/dev/null; then
			diag_finish complete 100 "OVERALL PASS — generator/profile diagnostic passed"
		else
			diag_finish complete 100 "OVERALL FAIL — review diagnostic output below"
		fi
	else
		rc=$?
		diag_finish failed 100 "Diagnostic process failed (rc=$rc)"
		return "$rc"
	fi
}

generator_diagnostic_status() {
	job="${1:-}"
	case "$job" in diag-[0-9]*-[0-9]*) ;; *) echo "Invalid diagnostic job id"; return 2;; esac
	dir="$STATE/diagjobs/$job"
	[ -d "$dir" ] || { echo "Diagnostic job not found"; return 3; }
	cat "$dir/status" 2>/dev/null || true
	started="$(sed -n 's/^started=//p' "$dir/status" 2>/dev/null | head -n1)"
	now="$(date +%s)"
	case "$started" in ''|*[!0-9]*) elapsed=0;; *) elapsed=$((now-started)); [ "$elapsed" -ge 0 ] || elapsed=0;; esac
	# Hard diagnostic safety ceiling.  Every network request is already bounded,
	# but this prevents an unexpected local loop/tool failure from leaving a
	# router worker alive forever.  Status polling performs the cleanup.
	state_now="$(sed -n 's/^state=//p' "$dir/status" 2>/dev/null | head -n1)"
	if [ "$elapsed" -gt 210 ] && { [ "$state_now" = running ] || [ "$state_now" = starting ]; }; then
		pid="$(cat "$dir/pid" 2>/dev/null || true)"
		case "$pid" in ''|*[!0-9]*) ;; *)
			if kill -0 "$pid" 2>/dev/null; then
				cmdline="$(tr '\000' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
				case "$cmdline" in *airvpn-native*generator-diagnostic-run*) kill "$pid" 2>/dev/null || true;; esac
			fi;;
		esac
		{ echo "state=failed"; echo "percent=100"; echo "started=$started"; echo "stage=OVERALL FAIL — diagnostic exceeded 210s safety limit"; } >"$dir/status.tmp.$$"
		mv -f "$dir/status.tmp.$$" "$dir/status"
		grep -q '^OVERALL RESULT:' "$dir/output" 2>/dev/null || echo "OVERALL RESULT: FAIL" >>"$dir/output"
	fi
	echo "elapsed=$elapsed"
	echo "---OUTPUT---"
	cat "$dir/output" 2>/dev/null || true
}
