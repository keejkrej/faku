#!/usr/bin/env bash
# Build an amd64 Debian package from Native's Linux FHS install tree
# (zig-out/package/faku-linux → prefix /usr).
#
# Usage: packaging/linux/build-deb.sh <version> <install-tree> <outfile>

set -euo pipefail
umask 022

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <version> <install-tree> <outfile>" >&2
  exit 2
fi

VERSION="$1"
PKG="$2"
OUTFILE="$3"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

if [[ ! -d "$PKG" ]]; then
  echo "missing Native linux install tree: $PKG" >&2
  exit 1
fi
if [[ ! -x "$PKG/bin/faku" && ! -f "$PKG/bin/faku" ]]; then
  echo "missing $PKG/bin/faku" >&2
  exit 1
fi

# Debian upstream versions must start with a digit. A hyphen would start a
# debian_revision, so map remaining hyphens to tilde (pre-release).
deb_version="${VERSION#v}"
if [[ ! "$deb_version" =~ ^[0-9] ]]; then
  echo "Debian Version must start with a digit (got $deb_version)" >&2
  exit 1
fi
if [[ "$deb_version" == *-* ]]; then
  deb_version="${deb_version//-/\~}"
fi

description=$(
  python3 -c "import json, pathlib, sys
p = pathlib.Path(sys.argv[1]) / 'app.json'
d = json.loads(p.read_text()).get('description') or 'Faku desktop'
print(' '.join(d.split()))" "$ROOT"
)
if [[ -z "$description" ]]; then
  description="Faku desktop"
fi

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

mkdir -p "$staging/DEBIAN" "$staging/usr"
cp -a "$PKG"/. "$staging/usr/"
# mktemp dirs are 0700; dpkg would otherwise unpack ./usr as mode 0700.
find "$staging" -type d -exec chmod 755 {} +
chmod 755 "$staging/usr/bin/faku"

installed_size=$(du -sk "$staging/usr" | awk '{print $1}')

cat > "$staging/DEBIAN/control" <<EOF
Package: faku
Version: ${deb_version}
Architecture: amd64
Section: utils
Priority: optional
Depends: libgtk-4-1
Installed-Size: ${installed_size}
Maintainer: Faku <https://github.com/keejkrej/faku>
Homepage: https://github.com/keejkrej/faku
Description: ${description}
EOF

chmod 755 "$staging/DEBIAN"
chmod 644 "$staging/DEBIAN/control"

mkdir -p "$(dirname -- "$OUTFILE")"
dpkg-deb --root-owner-group --build "$staging" "$OUTFILE"
echo "built $OUTFILE"
