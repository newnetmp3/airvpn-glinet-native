#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PKG="$HERE/pkg"
VERSION="$(awk '$1 == "Version:" { print $2; exit }' "$PKG/control/control")"
[ -n "$VERSION" ] || { echo "Unable to read package version" >&2; exit 1; }
DEST="${1:-$HERE/airvpn-glinet-native_${VERSION}_all.ipk}"
TMP="$HERE/.build-ipk.$$"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$TMP"
(
  cd "$PKG/control"
  tar --owner=0 --group=0 -czf "$TMP/control.tar.gz" .
)
(
  cd "$PKG/data"
  tar --owner=0 --group=0 -czf "$TMP/data.tar.gz" .
)
printf '2.0\n' >"$TMP/debian-binary"
(
  cd "$TMP"
  tar --owner=0 --group=0 -czf "$DEST" debian-binary control.tar.gz data.tar.gz
)
echo "$DEST"