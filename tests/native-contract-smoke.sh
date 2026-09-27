#!/bin/sh
set -eu
MOD="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../pkg/data/usr/lib/airvpn-native" && pwd)/glinet-vpn.sh}"
TMP="${TMPDIR:-/tmp}/airvpn-native-contract.$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin"
CAP="$TMP/calls"
: >"$CAP"
export CAP

# Minimal UCI facade for the GL.iNet state read by the adapter.
cat >"$TMP/bin/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" = "-q" ] && shift
cmd="${1:-}"; shift || true
case "$cmd:${1:-}" in
  get:wireguard.peer_1000) echo peers;;
  get:wireguard.peer_1001) echo peers;;
  get:wireguard.peer_1000.group_id|get:wireguard.peer_1001.group_id) echo 1000;;
  get:route_policy.@rule\[0\].tunnel_id) echo 1000;;
  get:route_policy.@rule\[0\].enabled) echo 1;;
  *) exit 1;;
esac
EOF
chmod +x "$TMP/bin/uci"
PATH="$TMP/bin:$PATH"; export PATH

# Globals/modules expected by glinet-vpn.sh.
STATE="$TMP/state"; mkdir -p "$STATE"
MANAGED="$STATE/managed-peers"; printf 'peer_1000\npeer_1001\n' >"$MANAGED"
DASHBOARD_TUNNEL_ID_FILE="$STATE/dashboard-tunnel-id"
GROUPID_FILE="$STATE/group-id"
PLUGIN_VERSION=0.11.0
get() {
  case "${1:-}" in
    mtu) echo 1320;;
    local_access) echo 0;;
    masquerade) echo 1;;
    native_reload) echo 0;;
    active_selector) echo alpha;;
    *) echo '';;
  esac
}
log() { :; }
add_progress() { :; }
find_peer_for_selector() { echo peer_1000; }

. "$MOD"

# Override transport so the test validates the JSON payload without a router.
glinet_vpn_client_call() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$CAP"
  printf '%s\n' '{"result":{"err_code":0}}'
}
managed_peer_ids() { printf 'peer_1000\npeer_1001\n'; }
preferred_airvpn_peer() { echo peer_1000; }

: >"$CAP"
native_set_tunnel_state 1000 1 peer_1000
line="$(tail -n1 "$CAP")"
printf '%s' "$line" | grep -Fq 'set_tunnel'
printf '%s' "$line" | grep -Fq '"enabled":true'
printf '%s' "$line" | grep -Fq '"tunnel_id":1000'
printf '%s' "$line" | grep -Fq '"via":{"type":"wireguard","configs":[{"group_id":1000,"id_list":[1000,1001]}]}'

: >"$CAP"
native_update_dashboard_profiles '@rule[0]' peer_1001
line="$(tail -n1 "$CAP")"
printf '%s' "$line" | grep -Fq 'set_tunnel'
printf '%s' "$line" | grep -Fq '"enabled":true'
printf '%s' "$line" | grep -Fq '"id_list":[1001,1000]'

: >"$CAP"
native_set_tunnel_options 1000
line="$(tail -n1 "$CAP")"
printf '%s' "$line" | grep -Fq 'set_options'
printf '%s' "$line" | grep -Fq '"mtu":1320'
printf '%s' "$line" | grep -Fq '"local_access":false'
printf '%s' "$line" | grep -Fq '"masq":true'
printf '%s' "$line" | grep -Fq '"service_policy":false'
printf '%s' "$line" | grep -Fq '"killswitch":true'

# Ensure native transport failures are propagated instead of falling through to
# destructive custom cleanup.
glinet_vpn_client_call() { return 7; }
rc=0
native_remove_dashboard_tunnel 1000 >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 7 ]

printf '%s\n' 'PASS native VPN contract smoke test'