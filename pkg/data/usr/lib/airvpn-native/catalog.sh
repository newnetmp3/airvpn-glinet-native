#!/bin/sh
# AirVPN native plugin module — sourced by /usr/bin/airvpn-native.

country_code_for_selector() {
	sel="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	case "$sel" in
		earth|all|world|global) echo ""; return 0 ;;
		canada|ca) echo "CA"; return 0 ;;
		united_states|united-states|"united states"|usa|us) echo "US"; return 0 ;;
		netherlands|nl) echo "NL"; return 0 ;;
		germany|de) echo "DE"; return 0 ;;
		switzerland|ch) echo "CH"; return 0 ;;
		united_kingdom|united-kingdom|"united kingdom"|uk|gb) echo "GB"; return 0 ;;
		france|fr) echo "FR"; return 0 ;;
		italy|it) echo "IT"; return 0 ;;
		spain|es) echo "ES"; return 0 ;;
		sweden|se) echo "SE"; return 0 ;;
		norway|no) echo "NO"; return 0 ;;
		denmark|dk) echo "DK"; return 0 ;;
		finland|fi) echo "FI"; return 0 ;;
		austria|at) echo "AT"; return 0 ;;
		belgium|be) echo "BE"; return 0 ;;
		poland|pl) echo "PL"; return 0 ;;
		czechia|czech_republic|cz) echo "CZ"; return 0 ;;
		romania|ro) echo "RO"; return 0 ;;
		japan|jp) echo "JP"; return 0 ;;
		singapore|sg) echo "SG"; return 0 ;;
		australia|au) echo "AU"; return 0 ;;
		new_zealand|"new zealand"|nz) echo "NZ"; return 0 ;;
		brazil|br) echo "BR"; return 0 ;;
		*)
			case "$sel" in
				[a-z][a-z]) printf '%s\n' "$sel" | tr '[:lower:]' '[:upper:]'; return 0 ;;
			esac
			echo "__NO_ALIAS__"; return 1 ;;
	esac
}

status_json() {
	mkdir -p "$STATE"
	need_key
	out="$STATE/status.json"
	curl -fsS --connect-timeout 10 --max-time 30 \
		-H "API-KEY: $API_KEY" "$API/status/" -o "$out"
	echo "$out"
}

raw_status_cache_file="$STATE/status.raw.cache.json"
raw_status_timestamp_file="$STATE/status.raw.timestamp"

raw_status_cached() {
	mkdir -p "$STATE"
	if [ -s "$raw_status_cache_file" ]; then
		cat "$raw_status_cache_file"
		return 0
	fi
	raw_status_refresh
}

raw_status_refresh() {
	mkdir -p "$STATE"; out="$STATE/status.raw.json.$$"; now="$(date +%s 2>/dev/null || echo 0)"
	min_gap="$(get refresh_min_seconds)"; [ -n "$min_gap" ] || min_gap=60
	last=0; [ -s "$raw_status_timestamp_file" ] && last="$(cat "$raw_status_timestamp_file" 2>/dev/null || echo 0)"
	case "$last" in ''|*[!0-9]*) last=0;; esac
	if [ -s "$raw_status_cache_file" ] && [ $((now-last)) -lt "$min_gap" ]; then
		record_refresh_result 1 "rate-limited; existing cache retained"; cat "$raw_status_cache_file"; return 0
	fi
	if curl -fsS --connect-timeout 8 --max-time 30 "$API/status/" -o "$out"; then
		if validate_status_json "$out"; then
			atomic_replace "$out" "$raw_status_cache_file" 600
			printf '%s\n' "$now" >"${raw_status_timestamp_file}.tmp"; mv "${raw_status_timestamp_file}.tmp" "$raw_status_timestamp_file"
			count="$(safe_json_count_servers "$raw_status_cache_file")"; record_refresh_result 1 "validated $count servers"
			rm -f "$out"; cat "$raw_status_cache_file"; return 0
		else
			err="$(validate_status_json "$out" 2>&1 || true)"; record_refresh_result 0 "validation rejected response: $err"; rm -f "$out"
		fi
	else record_refresh_result 0 "AirVPN status download failed"; rm -f "$out"; fi
	[ -s "$raw_status_cache_file" ] && { cat "$raw_status_cache_file"; return 0; }; return 1
}

raw_status_age() {
	now="$(date +%s 2>/dev/null || echo 0)"
	then=0
	[ -s "$raw_status_timestamp_file" ] && then="$(cat "$raw_status_timestamp_file" 2>/dev/null || echo 0)"
	case "$then" in *[!0-9]*|'') then=0;; esac
	age=$((now-then))
	[ "$age" -lt 0 ] && age=0
	printf '%s\n' "$age"
}

raw_status_meta() {
	age="$(raw_status_age)"; has=0; count=0; last_ok=""; last_msg=""; last_time=0
	[ -s "$raw_status_cache_file" ] && { has=1; count="$(safe_json_count_servers "$raw_status_cache_file")"; }
	if [ -s "$REFRESH_STATUS" ]; then
		last_ok="$(sed -n 's/^ok=//p' "$REFRESH_STATUS" | head -n1)"
		last_time="$(sed -n 's/^time=//p' "$REFRESH_STATUS" | head -n1)"
		last_msg="$(sed -n 's/^message=//p' "$REFRESH_STATUS" | head -n1)"
	fi
	seed="$STATE/background-refresh.schedule"; minute=""; offset=""
	if [ -s "$seed" ]; then . "$seed"; minute="${MINUTE:-}"; offset="${HOUR_OFFSET:-}"; fi
	due=$(( $(date +%s 2>/dev/null || echo 0) + (age<18000 ? 18000-age : 0) ))
	printf '{"cached":%s,"age_seconds":%s,"refresh_seconds":18000,"next_refresh_due":%s,"server_count":%s,"last_refresh_ok":"%s","last_refresh_time":%s,"last_refresh_message":"%s","schedule_minute":"%s","schedule_hour_offset":"%s"}\n' \
	 "$has" "$age" "$due" "${count:-0}" "$(printf '%s' "$last_ok" | sed 's/"/\\"/g')" "${last_time:-0}" "$(printf '%s' "$last_msg" | sed 's/"/\\"/g')" "$minute" "$offset"
}

raw_status_background_refresh() {
	# Refresh only when cache is missing or at least 5 hours old.
	age="$(raw_status_age)"
	if [ ! -s "$raw_status_cache_file" ] || [ "$age" -ge 18000 ]; then
		raw_status_refresh >/dev/null
	fi
}

status_servers_tsv() {
	status="$(status_json)" || return 1
	tmp="$STATE/status.tsv"
	: >"$tmp"
	i=0
	while :; do
		name="$(jsonfilter -i "$status" -e "@.servers[$i].public_name" 2>/dev/null || true)"
		[ -n "$name" ] || name="$(jsonfilter -i "$status" -e "@.servers[$i].name" 2>/dev/null || true)"
		[ -n "$name" ] || break

		cc="$(jsonfilter -i "$status" -e "@.servers[$i].country_code" 2>/dev/null || true)"

		country="$(jsonfilter -i "$status" -e "@.servers[$i].country_name" 2>/dev/null || true)"
		[ -n "$country" ] || country="$(jsonfilter -i "$status" -e "@.servers[$i].country" 2>/dev/null || true)"

		city="$(jsonfilter -i "$status" -e "@.servers[$i].city_name" 2>/dev/null || true)"
		[ -n "$city" ] || city="$(jsonfilter -i "$status" -e "@.servers[$i].location" 2>/dev/null || true)"

		health="$(jsonfilter -i "$status" -e "@.servers[$i].health" 2>/dev/null || true)"
		score="$(jsonfilter -i "$status" -e "@.servers[$i].score" 2>/dev/null || true)"

		load="$(jsonfilter -i "$status" -e "@.servers[$i].load" 2>/dev/null || true)"
		[ -n "$load" ] || load="$(jsonfilter -i "$status" -e "@.servers[$i].currentload" 2>/dev/null || true)"

		bw="$(jsonfilter -i "$status" -e "@.servers[$i].bw" 2>/dev/null || true)"
		[ -n "$bw" ] || bw="$(jsonfilter -i "$status" -e "@.servers[$i].bandwidth" 2>/dev/null || true)"

		eff_bw="$(jsonfilter -i "$status" -e "@.servers[$i].effective_bandwidth" 2>/dev/null || true)"
		[ -n "$eff_bw" ] || eff_bw="$(jsonfilter -i "$status" -e "@.servers[$i].bw_effective" 2>/dev/null || true)"

		max_bw="$(jsonfilter -i "$status" -e "@.servers[$i].bw_max" 2>/dev/null || true)"
		[ -n "$max_bw" ] || max_bw="$(jsonfilter -i "$status" -e "@.servers[$i].max_bandwidth" 2>/dev/null || true)"

		users="$(jsonfilter -i "$status" -e "@.servers[$i].users" 2>/dev/null || true)"
		available="$(jsonfilter -i "$status" -e "@.servers[$i].available" 2>/dev/null || true)"
		ipv4="$(jsonfilter -i "$status" -e "@.servers[$i].supports_ipv4" 2>/dev/null || true)"
		ipv6="$(jsonfilter -i "$status" -e "@.servers[$i].supports_ipv6" 2>/dev/null || true)"

		ip="$(jsonfilter -i "$status" -e "@.servers[$i].ip_v4_in1" 2>/dev/null || true)"
		[ -n "$ip" ] || ip="$(jsonfilter -i "$status" -e "@.servers[$i].ip_entry" 2>/dev/null || true)"

		[ -n "$score" ] || score=0
		[ -n "$load" ] || load=999
		[ -n "$bw" ] || bw=0
		[ -n "$eff_bw" ] || eff_bw=0
		[ -n "$max_bw" ] || max_bw=0
		[ -n "$users" ] || users=0

		# Catalog columns:
		# 1 name, 2 country code, 3 country, 4 city/location, 5 score,
		# 6 load, 7 current bandwidth, 8 effective bandwidth,
		# 9 maximum bandwidth, 10 users, 11 health, 12 available,
		# 13 IPv4 support, 14 IPv6 support, 15 entry IP.
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$name" "$cc" "$country" "$city" "$score" "$load" "$bw" "$eff_bw" \
			"$max_bw" "$users" "$health" "$available" "$ipv4" "$ipv6" "$ip" >>"$tmp"
		i=$((i+1))
	done
	echo "$tmp"
}

filter_servers() {
	selector="$1"
	infile="$2"
	outfile="$3"
	code="$(country_code_for_selector "$selector" 2>/dev/null || true)"
	[ "$code" != "__NO_ALIAS__" ] || code=""

	# Optional explicit country filter overrides selector-derived country.
	cf="$(get country_filter)"
	[ -n "$cf" ] && code="$(printf '%s' "$cf" | tr '[:lower:]' '[:upper:]')"

	health_only="$(get health_only)"; [ -n "$health_only" ] || health_only=1
	min_score="$(get min_score)"; [ -n "$min_score" ] || min_score=0
	max_load="$(get max_load)"; [ -n "$max_load" ] || max_load=100
	include_pat="$(get include_server)"
	exclude_pat="$(get exclude_server)"

	awk -F '\t' \
		-v code="$code" \
		-v health_only="$health_only" \
		-v min_score="$min_score" \
		-v max_load="$max_load" \
		-v inc="$include_pat" \
		-v exc="$exclude_pat" '
	BEGIN { OFS="\t" }
	{
		name=$1; cc=toupper($2); score=$5+0; load=$6+0; health=tolower($11); avail=tolower($12)
		if (code != "" && cc != code) next
		if (health_only == "1") {
			if (health != "" && health != "ok" && health != "healthy") next
			if (avail == "no" || avail == "false" || avail == "0") next
		}
		if (score < min_score) next
		if (load > max_load) next
		if (inc != "" && name !~ inc) next
		if (exc != "" && name ~ exc) next
		print
	}' "$infile" >"$outfile"
}

server_catalog() {
	country="${1:-ALL}"
	all="$(status_servers_tsv)" || exit 1
	out="$STATE/status.catalog.tsv"

	if [ -z "$country" ] || [ "$(printf '%s' "$country" | tr '[:lower:]' '[:upper:]')" = "ALL" ]; then
		cp "$all" "$out"
	else
		cc="$(printf '%s' "$country" | tr '[:lower:]' '[:upper:]')"
		awk -F '\t' -v cc="$cc" 'BEGIN{OFS="\t"} { if (toupper($2)==cc) print }' "$all" >"$out"
	fi

	sorted="$STATE/status.catalog.sorted.tsv"
	sort_filtered_servers "$out" "$sorted"
	cat "$sorted"
}

server_countries() {
	# Populate the country selector from AirVPN's aggregate country data.
	mkdir -p "$STATE"
	out="$STATE/countries-status.json"
	cache="$STATE/countries.tsv"
	now="$(date +%s 2>/dev/null || echo 0)"

	# Reuse a very recent result when reopening the AirVPN panel.
	if [ -s "$cache" ] && [ -s "$STATE/countries.timestamp" ]; then
		then="$(cat "$STATE/countries.timestamp" 2>/dev/null || echo 0)"
		case "$then" in *[!0-9]*|'') then=0;; esac
		age=$((now-then))
		if [ "$age" -ge 0 ] && [ "$age" -lt 300 ]; then
			cat "$cache"
			return 0
		fi
	fi

	# The status endpoint is public; no API-key lookup is needed for the
	# country selector. Only one compact status response is downloaded.
	if ! curl -fsS --connect-timeout 5 --max-time 12 "$API/status/" -o "$out"; then
		[ -s "$cache" ] && { cat "$cache"; return 0; }
		return 1
	fi

	tmp="$STATE/countries.new.tsv"
	: >"$tmp"
	i=0
	while :; do
		cc="$(jsonfilter -i "$out" -e "@.countries[$i].country_code" 2>/dev/null || true)"
		name="$(jsonfilter -i "$out" -e "@.countries[$i].country_name" 2>/dev/null || true)"
		servers="$(jsonfilter -i "$out" -e "@.countries[$i].servers" 2>/dev/null || true)"
		health="$(jsonfilter -i "$out" -e "@.countries[$i].health" 2>/dev/null || true)"
		[ -n "$cc" ] || break

		# A country in AirVPN's countries[] aggregate with a positive server
		# count is currently represented by VPN hosts. Warning states stay
		# listed; only explicit offline/disabled aggregate states are skipped.
		case "$(printf '%s' "$health" | tr '[:upper:]' '[:lower:]')" in
			offline|disabled) i=$((i+1)); continue ;;
		esac
		case "$servers" in
			''|*[!0-9]*) ;;
			0) i=$((i+1)); continue ;;
		esac

		printf '%s\t%s\n' "$(printf '%s' "$cc" | tr '[:lower:]' '[:upper:]')" "$name" >>"$tmp"
		i=$((i+1))
	done

	if [ -s "$tmp" ]; then
		sort -t "$(printf '\t')" -k2,2f -k1,1 "$tmp" >"$cache"
		printf '%s\n' "$now" >"$STATE/countries.timestamp"
		rm -f "$tmp"
		cat "$cache"
		return 0
	fi

	rm -f "$tmp"
	[ -s "$cache" ] && { cat "$cache"; return 0; }
	return 1
}

sort_filtered_servers() {
	infile="$1"
	outfile="$2"
	col="$(get sort_column)"; [ -n "$col" ] || col=score
	dir="$(get sort_direction)"; [ -n "$dir" ] || dir=desc
	tab="$(printf '\t')"

	case "$col" in
		name) n=1; numeric=0 ;;
		country_code) n=2; numeric=0 ;;
		country) n=3; numeric=0 ;;
		city) n=4; numeric=0 ;;
		score) n=5; numeric=1 ;;
		load) n=6; numeric=1 ;;
		bandwidth) n=7; numeric=1 ;;
		effective_bandwidth) n=8; numeric=1 ;;
		max_bandwidth) n=9; numeric=1 ;;
		available_bandwidth) n=9; numeric=2 ;;
		users) n=10; numeric=1 ;;
		health) n=11; numeric=0 ;;
		available) n=12; numeric=0 ;;
		supports_ipv4) n=13; numeric=0 ;;
		supports_ipv6) n=14; numeric=0 ;;
		entry_ip) n=15; numeric=0 ;;
		*) n=5; numeric=1 ;;
	esac

	if [ "$numeric" -eq 2 ]; then
		# Derived headroom: maximum bandwidth minus current bandwidth.
		awk -F '\t' 'BEGIN{OFS="\t"} {avail=($9+0)-($7+0); if(avail<0) avail=0; print avail,$0}' "$infile" >"${outfile}.avail"
		if [ "$dir" = asc ]; then
			sort -t "$tab" -k1,1n -k2,2 "${outfile}.avail" | cut -f2- >"$outfile"
		else
			sort -t "$tab" -k1,1nr -k2,2 "${outfile}.avail" | cut -f2- >"$outfile"
		fi
		rm -f "${outfile}.avail"
	elif [ "$numeric" -eq 1 ]; then
		if [ "$dir" = asc ]; then
			sort -t "$tab" -k${n},${n}n -k1,1 "$infile" >"$outfile"
		else
			sort -t "$tab" -k${n},${n}nr -k1,1 "$infile" >"$outfile"
		fi
	else
		if [ "$dir" = asc ]; then
			sort -f -t "$tab" -k${n},${n} -k1,1 "$infile" >"$outfile"
		else
			sort -f -r -t "$tab" -k${n},${n} -k1,1 "$infile" >"$outfile"
		fi
	fi
}

select_best_server() {
	selector="$1"
	all="$(status_servers_tsv)" || return 1
	filtered="$STATE/status.filtered.tsv"
	filter_servers "$selector" "$all" "$filtered"
	[ -s "$filtered" ] || return 4

	mode="$(get discovery_mode)"; [ -n "$mode" ] || mode=best_score

	# Random remains truly random. All other modes are now expressed through the
	# configurable sort column + direction so preview and selection agree.
	if [ "$mode" = random ]; then
		if command -v shuf >/dev/null 2>&1; then
			line="$(shuf -n1 "$filtered")"
		else
			count="$(wc -l <"$filtered" | tr -d ' ')"
			n=$((1 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % count))
			line="$(sed -n "${n}p" "$filtered")"
		fi
	else
		# Backward-compatible mapping from the older strategy selector.
		case "$mode" in
			lowest_load)
				uci -q get "$CFG.sort_column" >/dev/null 2>&1 || {
					uci set "$CFG.sort_column=load"
					uci set "$CFG.sort_direction=asc"
				}
				;;
			lowest_bandwidth)
				uci -q get "$CFG.sort_column" >/dev/null 2>&1 || {
					uci set "$CFG.sort_column=bandwidth"
					uci set "$CFG.sort_direction=asc"
				}
				;;
			best_score)
				uci -q get "$CFG.sort_column" >/dev/null 2>&1 || {
					uci set "$CFG.sort_column=score"
					uci set "$CFG.sort_direction=desc"
				}
				;;
		esac
		sorted="$STATE/status.sorted.tsv"
		sort_filtered_servers "$filtered" "$sorted"
		line="$(head -n1 "$sorted")"
	fi

	[ -n "$line" ] || return 5
	printf '%s\n' "$line"
}

server_cache_file() {
	key="$(cache_key_for_selector "$1")"
	[ -n "$key" ] || key=default
	printf '%s/server-%s' "$CACHE_DIR" "$key"
}

load_server_cache() {
	cf="$(server_cache_file "$1")"
	[ -r "$cf" ] || return 1
	server="$(sed -n 's/^server=//p' "$cf" | head -n1)"
	[ -n "$server" ] || return 1
	printf '%s\n' "$server"
}

save_server_cache() {
	selector="$1"; server="$2"; cc="$3"; score="$4"; load="$5"; bw="$6"; health="$7"; ip="$8"; city="$9"
	mkdir -p "$CACHE_DIR"; chmod 700 "$CACHE_DIR"
	cf="$(server_cache_file "$selector")"
	umask 077
	{
		echo "server=$server"
		echo "country_code=$cc"
		echo "score=$score"
		echo "load=$load"
		echo "bandwidth=$bw"
		echo "health=$health"
		echo "ip=$ip"
		echo "city=$city"
		echo "saved=$(date +%s 2>/dev/null || echo 0)"
	} >"$cf"
	chmod 600 "$cf"
}

discover_selector() {
	selector="$1"

	# earth/global stays as AirVPN's native aggregate selector unless discovery is
	# explicitly requested through country_filter.
	code="$(country_code_for_selector "$selector" 2>/dev/null || true)"
	if [ -z "$code" ] && [ -z "$(get country_filter)" ]; then
		printf '%s\n' "$selector"
		return 0
	fi

	use="$(get use_server_discovery)"; [ -n "$use" ] || use=1
	[ "$use" = 1 ] || { printf '%s\n' "$selector"; return 0; }

	cached_server="$(load_server_cache "$selector" 2>/dev/null || true)"
	if [ -n "$cached_server" ]; then
		echo "Using cached AirVPN server for '$selector': $cached_server" >&2
		printf '%s\n' "$cached_server"
		return 0
	fi

	line="$(select_best_server "$selector" 2>/dev/null || true)"
	[ -n "$line" ] || {
		echo "No AirVPN server matched filters for selector '$selector'." >&2
		return 6
	}
	IFS="$(printf '\t')" read -r name cc country city score load bw eff_bw max_bw users health available ipv4 ipv6 ip <<EOF
$line
EOF
	save_server_cache "$selector" "$name" "$cc" "$score" "$load" "$bw" "$health" "$ip" "$city"
	echo "Selected AirVPN server for '$selector': $name ($cc ${city:+/ $city}) score=$score load=$load" >&2
	printf '%s\n' "$name"
}

servers() {
	all="$(status_servers_tsv)" || exit 1
	cat "$all"
}

filtered_servers() {
	selector="${1:-earth}"
	all="$(status_servers_tsv)" || exit 1
	out="$STATE/status.filtered.tsv"
	sorted="$STATE/status.sorted.tsv"
	filter_servers "$selector" "$all" "$out"
	sort_filtered_servers "$out" "$sorted"
	cat "$sorted"
}

cache_key_for_selector() {
	selector="$1"
	printf '%s' "$selector" | tr ' /,:;()[]{}' '____________' | tr -cd 'A-Za-z0-9_.-'
}

cache_file_for_selector() {
	key="$(cache_key_for_selector "$1")"
	[ -n "$key" ] || key=default
	printf '%s/%s' "$CACHE_DIR" "$key"
}

load_cached_attempt() {
	selector="$1"
	cf="$(cache_file_for_selector "$selector")"
	[ -r "$cf" ] || return 1
	c_protocol="$(sed -n 's/^protocol=//p' "$cf" | head -n1)"
	c_layer="$(sed -n 's/^layer=//p' "$cf" | head -n1)"
	c_resolve="$(sed -n 's/^resolve=//p' "$cf" | head -n1)"
	[ -n "$c_protocol" ] && [ -n "$c_layer" ] && [ -n "$c_resolve" ] || return 1
	printf '%s|%s|%s\n' "$c_protocol" "$c_layer" "$c_resolve"
}

save_cached_attempt() {
	selector="$1"; protocol="$2"; layer="$3"; resolve="$4"
	mkdir -p "$CACHE_DIR"
	chmod 700 "$CACHE_DIR"
	cf="$(cache_file_for_selector "$selector")"
	umask 077
	{
		echo "protocol=$protocol"
		echo "layer=$layer"
		echo "resolve=$resolve"
		echo "saved=$(date +%s 2>/dev/null || echo 0)"
	} >"$cf"
	chmod 600 "$cf"
}

generator_performance_file() {
	printf '%s/.generator-performance.tsv' "$CACHE_DIR"
}

monotonic_ms() {
	# /proc/uptime is monotonic and available on OpenWrt. Fall back to wall-clock
	# seconds only if procfs is unexpectedly unavailable.
	if [ -r /proc/uptime ]; then
		awk '{printf "%.0f\n", $1 * 1000}' /proc/uptime 2>/dev/null && return 0
	fi
	now="$(date +%s 2>/dev/null || echo 0)"
	case "$now" in ''|*[!0-9]*) now=0;; esac
	echo $((now * 1000))
}

record_generator_performance() {
	combo="$1" result="$2" elapsed_ms="$3"
	[ -n "$combo" ] || return 0
	case "$result" in success|failure) ;; *) return 2;; esac
	case "$elapsed_ms" in ''|*[!0-9]*) elapsed_ms=0;; esac
	mkdir -p "$CACHE_DIR" || return 0
	chmod 700 "$CACHE_DIR" 2>/dev/null || true
	pf="$(generator_performance_file)"
	[ -f "$pf" ] || : >"$pf"
	chmod 600 "$pf" 2>/dev/null || true
	tmp="$pf.tmp.$$"
	now="$(date +%s 2>/dev/null || echo 0)"
	# Columns: combo, successes, failures, total_success_ms, best_ms, last_ms,
	# last_result, updated.  A recently failed combination is not selected as the
	# adaptive default, but remains in history and can be rediscovered by fallback.
	awk -F '\t' -v OFS='\t' -v key="$combo" -v result="$result" -v ms="$elapsed_ms" -v now="$now" '
	BEGIN { found=0 }
	$1 == key {
		found=1; s=$2+0; f=$3+0; total=$4+0; best=$5+0;
		if (result == "success") {
			s++; total += ms;
			if (best == 0 || ms < best) best=ms;
		} else f++;
		print key, s, f, total, best, ms, result, now;
		next
	}
	NF >= 1 { print }
	END {
		if (!found) {
			s=(result == "success" ? 1 : 0); f=(result == "failure" ? 1 : 0);
			total=(result == "success" ? ms : 0); best=(result == "success" ? ms : 0);
			print key, s, f, total, best, ms, result, now;
		}
	}' "$pf" 2>/dev/null >"$tmp" || {
		rm -f "$tmp" 2>/dev/null || true
		return 0
	}
	chmod 600 "$tmp" 2>/dev/null || true
	mv -f "$tmp" "$pf" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
}

generator_attempt_avg_ms() {
	combo="$1"
	[ -n "$combo" ] || return 1
	pf="$(generator_performance_file)"
	[ -r "$pf" ] || return 1
	awk -F '\t' -v key="$combo" '
	$1 == key && $2+0 > 0 { printf "%.0f\n", ($4+0)/($2+0); found=1; exit }
	END { if (!found) exit 1 }
	' "$pf"
}

fastest_generator_attempt() {
	pf="$(generator_performance_file)"
	[ -r "$pf" ] || return 1
	# Choose the lowest average successful request time among combinations whose
	# most recent observation was successful. This avoids repeatedly preferring a
	# once-fast method that is currently failing.
	awk -F '\t' '
	$2+0 > 0 && $7 == "success" {
		avg=($4+0)/($2+0)
		if (!found || avg < bestavg || (avg == bestavg && ($2+0) > bestn)) {
			found=1; bestavg=avg; bestn=$2+0; best=$1; last=$6+0
		}
	}
	END { if (found) printf "%s\t%.0f\t%d\t%d\n", best, bestavg, bestn, last; else exit 1 }
	' "$pf"
}

most_common_cached_attempt() {
	# Bootstrap adaptive mode after an upgrade using the old per-selector caches.
	# These files prove a combination succeeded even though older versions did not
	# record its elapsed time.
	mkdir -p "$CACHE_DIR" 2>/dev/null || true
	for cf in "$CACHE_DIR"/*; do
		[ -f "$cf" ] || continue
		name="${cf##*/}"
		case "$name" in server-*) continue;; esac
		p="$(sed -n 's/^protocol=//p' "$cf" | head -n1)"
		l="$(sed -n 's/^layer=//p' "$cf" | head -n1)"
		r="$(sed -n 's/^resolve=//p' "$cf" | head -n1)"
		[ -n "$p" ] && [ -n "$l" ] && [ -n "$r" ] && printf '%s|%s|%s\n' "$p" "$l" "$r"
	done | awk 'NF { count[$0]++ } END { for (k in count) if (!best || count[k] > max) { best=k; max=count[k] } if (best) print best }'
}

generator_performance_status() {
	if command -v load_known_good_generator >/dev/null 2>&1; then
		kg="$(load_known_good_generator 2>/dev/null || true)"
		if [ -n "$kg" ]; then
			kg_auth="${kg%%|*}"; kg_rest="${kg#*|}"
			kg_dev="${kg_rest%%|*}"; kg_rest="${kg_rest#*|}"
			kg_proto="${kg_rest%%|*}"; kg_rest="${kg_rest#*|}"
			kg_layer="${kg_rest%%|*}"; kg_rest="${kg_rest#*|}"
			kg_resolve="${kg_rest%%|*}"; kg_rest="${kg_rest#*|}"
			kg_ms="${kg_rest%%|*}"; kg_source="${kg_rest#*|}"
			printf 'diagnostic_known_good=auth:%s,device:%s,protocol:%s,layer:%s,resolve:%s\telapsed_ms=%s\tsource=%s\n' "$kg_auth" "$kg_dev" "$kg_proto" "$kg_layer" "$kg_resolve" "$kg_ms" "$kg_source"
		else
			echo 'diagnostic_known_good=none'
		fi
	fi
	pf="$(generator_performance_file)"
	if fastest="$(fastest_generator_attempt 2>/dev/null)"; then
		combo="${fastest%%	*}"
		rest="${fastest#*	}"; avg="${rest%%	*}"; rest="${rest#*	}"; successes="${rest%%	*}"; last="${rest#*	}"
		printf 'adaptive_default=%s\tavg_ms=%s\tsuccesses=%s\tlast_ms=%s\n' "$combo" "$avg" "$successes" "$last"
	elif bootstrap="$(most_common_cached_attempt 2>/dev/null || true)"; [ -n "$bootstrap" ]; then
		printf 'adaptive_default=%s\tsource=successful-cache-bootstrap\n' "$bootstrap"
	else
		echo 'adaptive_default=none'
	fi
	[ -r "$pf" ] || return 0
	awk -F '\t' '$2+0 > 0 { printf "generator_perf=%s\tsuccesses=%d\tfailures=%d\tavg_ms=%.0f\tbest_ms=%d\tlast_ms=%d\tlast_result=%s\n", $1,$2,$3,$4/$2,$5,$6,$7 }' "$pf"
}

clear_cache() {
	rm -rf "$CACHE_DIR"
	mkdir -p "$CACHE_DIR"
	chmod 700 "$CACHE_DIR"
	# Clearing learned state blocks retained diagnostics until a new run succeeds.
	if command -v known_good_bootstrap_marker >/dev/null 2>&1; then
		marker="$(known_good_bootstrap_marker)"
		mkdir -p "$STATE" 2>/dev/null || true
		: >"$marker" 2>/dev/null || true
		chmod 600 "$marker" 2>/dev/null || true
	fi
	echo "AirVPN generator/server cache, diagnostic known-good method, and adaptive timing history cleared."
}

cache_status() {
	mkdir -p "$CACHE_DIR"
	generator_performance_status
	found=0
	for cf in "$CACHE_DIR"/*; do
		[ -f "$cf" ] || continue
		found=1
		name="${cf##*/}"
		case "$name" in
			server-*)
				printf '%s\tserver=%s\tcountry=%s\tscore=%s\tload=%s\tcity=%s\n' \
					"$name" \
					"$(sed -n 's/^server=//p' "$cf" | head -n1)" \
					"$(sed -n 's/^country_code=//p' "$cf" | head -n1)" \
					"$(sed -n 's/^score=//p' "$cf" | head -n1)" \
					"$(sed -n 's/^load=//p' "$cf" | head -n1)" \
					"$(sed -n 's/^city=//p' "$cf" | head -n1)"
				;;
			*)
				printf '%s\tprotocol=%s\tlayer=%s\tresolve=%s\n' \
					"$name" \
					"$(sed -n 's/^protocol=//p' "$cf" | head -n1)" \
					"$(sed -n 's/^layer=//p' "$cf" | head -n1)" \
					"$(sed -n 's/^resolve=//p' "$cf" | head -n1)"
				;;
		esac
	done
	[ "$found" -eq 1 ] || echo "No cached generator/server selections."
}