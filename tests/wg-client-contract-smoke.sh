#!/bin/sh
set -eu
MOD="${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../pkg/data/usr/lib/airvpn-native" && pwd)/profiles.sh}"
TMP="${TMPDIR:-/tmp}/airvpn-wg-contract.$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP/bin" "$TMP/state"
CAP="$TMP/calls"; MARKER="$TMP/group-created"; : >"$CAP"
export CAP MARKER
cat >"$TMP/bin/uci" <<'EOF'
#!/bin/sh
[ "${1:-}" = "-q" ] && shift
cmd="${1:-}"; shift || true
arg="${1:-}"
case "$cmd:$arg" in
  show:wireguard)
    [ -e "$MARKER" ] && echo "wireguard.group_2345=groups"
    [ -e "$MARKER" ] && echo "wireguard.peer_3456=peers"
    ;;
  get:wireguard.group_2345) [ -e "$MARKER" ] && echo groups || exit 1;;
  get:wireguard.group_2345.group_name) [ -e "$MARKER" ] && echo AirVPN || exit 1;;
  get:wireguard.peer_3456) [ -e "$MARKER" ] && echo peers || exit 1;;
  get:wireguard.peer_3456.group_id) [ -e "$MARKER" ] && echo 2345 || exit 1;;
  get:wireguard.peer_3456.public_key) [ -e "$MARKER" ] && echo 'PUBKEY=' || exit 1;;
  set:*|commit:*) exit 0;;
  *) exit 1;;
esac
EOF
chmod +x "$TMP/bin/uci"
PATH="$TMP/bin:$PATH"; export PATH
STATE="$TMP/state"; MANAGED="$STATE/managed-peers"; GROUPID_FILE="$STATE/group-id"; PROFILE_SOURCE_DIR="$STATE/profile-sources"
get() {
  case "${1:-}" in
    group_name) echo AirVPN;; prefix) echo AirVPN;; mtu) echo 1320;; keepalive) echo 15;; *) echo '';;
  esac
}
sanitate_unused=1
sanitize() { printf '%s' "$1" | tr ' /,:()' '______' | tr -cd 'A-Za-z0-9_.-'; }
json_string_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/[[:cntrl:]]/ /g'; }
glinet_rpc_failed() { printf '%s' "${1:-}" | grep -Eq '"err_code"[[:space:]]*:[[:space:]]*[1-9][0-9]*'; }
glinet_wg_client_call() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$CAP"
  case "$1" in add_group|add_config) touch "$MARKER";; esac
  printf '%s\n' '{"result":{"err_code":0}}'
}
managed_peer_ids() { [ -f "$MANAGED" ] && cat "$MANAGED" || true; }
. "$MOD"

gid="$(ensure_group)"
[ "$gid" = 2345 ]
grep -Fq 'add_group' "$CAP"

CFG="$TMP/test.conf"
cat >"$CFG" <<'EOF'
[Interface]
Address = 10.1.2.3/32, fd00::123/128
PrivateKey = PRIVATE=
DNS = 10.4.0.1
MTU = 1400

[Peer]
PublicKey = PUBKEY=
PresharedKey = PSK=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 198.51.100.25:1637
PersistentKeepalive = 25
EOF
cat >"$CFG.effective" <<'EOF'
protocol=wireguard_1_udp_1637
layer=ipv4
resolve=off
EOF
out="$(import_conf "$CFG" 'TestServer' 2345 1)"
printf '%s' "$out" | grep -Fq 'peer_3456'
line="$(grep '^add_config' "$CAP" | tail -n1)"
printf '%s' "$line" | grep -Fq '"group_id":2345'
printf '%s' "$line" | grep -Fq '"address_v4":"10.1.2.3/32"'
printf '%s' "$line" | grep -Fq '"address_v6":"fd00::123/128"'
printf '%s' "$line" | grep -Fq '"private_key":"PRIVATE="'
printf '%s' "$line" | grep -Fq '"public_key":"PUBKEY="'
printf '%s' "$line" | grep -Fq '"allowed_ips":"0.0.0.0/0, ::/0"'
printf '%s' "$line" | grep -Fq '"end_point":"198.51.100.25:1637"'
printf '%s' "$line" | grep -Fq '"dns":"10.4.0.1"'
printf '%s' "$line" | grep -Fq '"mtu":1320'
printf '%s' "$line" | grep -Fq '"persistent_keepalive":15'
printf '%s' "$line" | grep -Fq '"presharedkey_enable":true'
printf '%s' "$line" | grep -Fq '"preshared_key":"PSK="'
[ -f "$PROFILE_SOURCE_DIR/peer_3456.conf" ]
grep -Fxq peer_3456 "$MANAGED"
printf '%s\n' 'PASS native wg-client contract smoke test'