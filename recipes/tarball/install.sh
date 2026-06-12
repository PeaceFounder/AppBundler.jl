#!/bin/bash
#
# Installer for {{APP_DISPLAY_NAME}} {{APP_VERSION}}.
#
# Copies this unpacked bundle to a prefix (default /opt/{{APP_NAME}}), symlinks
# the launcher onto PATH, and registers a desktop entry + icon. Per-user state
# (chats, projects, depot cache) lives under ~/.local/share/{{APP_DISPLAY_NAME}}
# and is never touched by install/uninstall.

set -euo pipefail

APP_NAME="{{APP_NAME}}"
APP_DISPLAY_NAME="{{APP_DISPLAY_NAME}}"

PREFIX="/opt/${APP_NAME}"
BIN_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/icons/hicolor/512x512/apps"
DO_UNINSTALL=0

usage() {
    cat <<EOF
Install ${APP_DISPLAY_NAME} ${APP_VERSION:-}.

Usage: sudo ./install.sh [--prefix DIR] [--uninstall]

  --prefix DIR   install location (default: ${PREFIX})
  --uninstall    remove a previous installation at --prefix
  -h, --help     show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --prefix=*) PREFIX="${1#*=}"; shift ;;
        --uninstall) DO_UNINSTALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

LAUNCHER="${BIN_DIR}/${APP_NAME}"
DESKTOP_FILE="${DESKTOP_DIR}/${APP_NAME}.desktop"
ICON_FILE="${ICON_DIR}/${APP_NAME}.png"

if [ "$(id -u)" -ne 0 ]; then
    echo "This installer writes to ${PREFIX}, ${BIN_DIR} and ${DESKTOP_DIR}." >&2
    echo "Please re-run with sudo." >&2
    exit 1
fi

if [ "$DO_UNINSTALL" -eq 1 ]; then
    echo "Removing ${APP_DISPLAY_NAME} from ${PREFIX}..."
    rm -f "$LAUNCHER" "$DESKTOP_FILE" "$ICON_FILE"
    rm -rf "$PREFIX"
    echo "Done. (Per-user data under ~/.local/share/${APP_DISPLAY_NAME} was left intact.)"
    exit 0
fi

SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if [ "$SRC_DIR" = "$PREFIX" ]; then
    echo "Refusing to install into the bundle's own directory ($PREFIX)." >&2
    echo "Unpack elsewhere or choose a different --prefix." >&2
    exit 1
fi

echo "Installing ${APP_DISPLAY_NAME} to ${PREFIX}..."
rm -rf "$PREFIX"
mkdir -p "$PREFIX"
# Stream-copy the whole tree (preserves symlinks, perms and the executable bits
# on bin/julia, the launcher and this script).
( cd "$SRC_DIR" && tar -cf - . ) | ( cd "$PREFIX" && tar -xf - )

mkdir -p "$BIN_DIR"
ln -sf "${PREFIX}/bin/${APP_NAME}" "$LAUNCHER"

if [ -f "${PREFIX}/meta/gui/${APP_NAME}.desktop" ]; then
    mkdir -p "$DESKTOP_DIR"
    sed -e "s|@EXEC@|${LAUNCHER}|g" -e "s|@ICON@|${ICON_FILE}|g" \
        "${PREFIX}/meta/gui/${APP_NAME}.desktop" > "$DESKTOP_FILE"
fi
if [ -f "${PREFIX}/meta/icon.png" ]; then
    mkdir -p "$ICON_DIR"
    cp "${PREFIX}/meta/icon.png" "$ICON_FILE"
fi

cat <<EOF

${APP_DISPLAY_NAME} installed.
  Run:       ${APP_NAME}        (or ${LAUNCHER})
  Uninstall: sudo ${PREFIX}/install.sh --uninstall
EOF
