#!/usr/bin/env bash
# Install (or remove) Faku as an Omarchy user app: ~/.local/bin, a Super+Space
# desktop launcher, and hicolor icons. Session files in ~/.local/share/faku
# are left alone on uninstall.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/install-omarchy.sh [options]

Build Faku and install it as an Omarchy desktop app (launcher + icons).

Options:
  --build        Force native build + linux package
  --no-build     Install from an existing zig-out binary (package if present)
  --uninstall    Remove the launcher, icons, and ~/.local/bin/faku
  --prefix DIR   Install prefix (default: ~/.local)
  -h, --help     Show this help
EOF
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)

PREFIX="${HOME}/.local"
FORCE_BUILD=0
NO_BUILD=0
UNINSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build) FORCE_BUILD=1; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    --prefix)
      PREFIX="${2:?--prefix requires a directory}"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if (( FORCE_BUILD && NO_BUILD )); then
  echo "choose one of --build or --no-build" >&2
  exit 2
fi

BIN_DIR="${PREFIX}/bin"
DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
if [[ ${PREFIX} != "${HOME}/.local" ]]; then
  DATA_HOME="${PREFIX}/share"
fi
APP_DATA="${DATA_HOME}/faku"
APPLICATIONS="${DATA_HOME}/applications"
HICOLOR="${DATA_HOME}/icons/hicolor"
DESKTOP="${APPLICATIONS}/Faku.desktop"
BIN="${BIN_DIR}/faku"

uninstall() {
  rm -f -- "${BIN}" "${BIN}.bin" "${DESKTOP}"
  find "${HICOLOR}" -type f -name 'faku.png' -delete 2>/dev/null || true
  rm -f -- "${APP_DATA}/assets/icon.png"
  rmdir --ignore-fail-on-non-empty "${APP_DATA}/assets" 2>/dev/null || true
  update-desktop-database "${APPLICATIONS}" 2>/dev/null || true
  gtk-update-icon-cache -f -t "${HICOLOR}" &>/dev/null || true
  if command -v omarchy >/dev/null 2>&1; then
    omarchy menu refresh >/dev/null 2>&1 || true
  fi
  echo "removed Faku Omarchy launcher"
}

if (( UNINSTALL )); then
  uninstall
  exit 0
fi

BIN_SRC="${ROOT}/zig-out/bin/faku"
PKG="${ROOT}/zig-out/package/faku-linux"
ICON_SRC="${ROOT}/assets/icon.png"

need_native() {
  if ! command -v native >/dev/null 2>&1; then
    echo "native CLI not found. Install with: npm install -g @native-sdk/cli" >&2
    exit 1
  fi
}

if (( FORCE_BUILD )) || { (( ! NO_BUILD )) && [[ ! -x ${BIN_SRC} ]]; }; then
  need_native
  (cd "${ROOT}" && native build --yes)
fi

if [[ ! -x ${BIN_SRC} ]]; then
  echo "missing ${BIN_SRC}; run without --no-build or build first" >&2
  exit 1
fi

if [[ ! -f ${ICON_SRC} ]]; then
  echo "missing ${ICON_SRC}" >&2
  exit 1
fi

if (( ! NO_BUILD )) && command -v native >/dev/null 2>&1; then
  (cd "${ROOT}" && native package --target linux)
fi

install -d "${BIN_DIR}"
# GDK_SCALE=2 on Hyprland 1.6 collapses layout and makes the software
# rasterizer paint 4x pixels. Install the binary directly.
rm -f -- "${BIN}.bin"
install -m 755 "${BIN_SRC}" "${BIN}"

install -d "${APP_DATA}/assets"
install -m 644 "${ICON_SRC}" "${APP_DATA}/assets/icon.png"

install_icon_size() {
  local size="$1" src="$2"
  local dest="${HICOLOR}/${size}/apps"
  install -d "${dest}"
  install -m 644 "${src}" "${dest}/faku.png"
}

if [[ -d ${PKG}/share/icons/hicolor ]]; then
  while IFS= read -r src; do
    size=$(basename "$(dirname "$(dirname "${src}")")")
    install_icon_size "${size}" "${src}"
  done < <(find "${PKG}/share/icons/hicolor" -type f -name 'app-icon.png' | sort)
fi
install_icon_size 1024x1024 "${ICON_SRC}"
if [[ ! -f ${HICOLOR}/256x256/apps/faku.png ]]; then
  install_icon_size 256x256 "${ICON_SRC}"
fi

install -d "${APPLICATIONS}"
cat >"${DESKTOP}" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Faku
Comment=Native desktop for coding agents
Exec=${BIN}
Path=${APP_DATA}
Icon=faku
Terminal=false
StartupNotify=true
Categories=Development;
Keywords=agent;coding;fx;waku;zig;
EOF
chmod +x "${DESKTOP}"

update-desktop-database "${APPLICATIONS}" 2>/dev/null || true
gtk-update-icon-cache -f -t "${HICOLOR}" &>/dev/null || true
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "${DESKTOP}"
fi
if command -v omarchy >/dev/null 2>&1; then
  omarchy menu refresh >/dev/null 2>&1 || true
fi

echo "installed Faku → ${BIN}"
echo "launcher ${DESKTOP}"
echo "open from Super+Space (search Faku)"
