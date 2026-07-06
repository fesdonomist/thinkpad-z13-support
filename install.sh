#!/bin/sh
set -eu

ROOT="${ROOT:-/}"
PROFILE_DIR="$ROOT/etc/tuned/profiles"
PPD_CONF="$ROOT/etc/tuned/ppd.conf"
CONFIG_DIR="$ROOT/etc/z13-tuned"
EHPS_CONFIG="$CONFIG_DIR/ehps.config"
BIN_DIR="$ROOT/opt/z13-tuned/bin"
SYSTEMD_DIR="$ROOT/etc/systemd/system"
SRC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="${BUILD_DIR:-${TMPDIR:-/tmp}/z13-tuned-build}"

CC="${CC:-cc}"
CFLAGS="${CFLAGS:--O2 -Wall -Wextra}"

install -Dm644 "$SRC_DIR/profiles/z13-balanced/tuned.conf" \
    "$PROFILE_DIR/z13-balanced/tuned.conf"
install -Dm755 "$SRC_DIR/profiles/z13-balanced/script.sh" \
    "$PROFILE_DIR/z13-balanced/script.sh"
install -Dm644 "$SRC_DIR/profiles/z13-power-saver/tuned.conf" \
    "$PROFILE_DIR/z13-power-saver/tuned.conf"
install -Dm644 "$SRC_DIR/ppd.conf" "$PPD_CONF"

mkdir -p "$BUILD_DIR"
"$CC" $CFLAGS -o "$BUILD_DIR/ehpsctl" "$SRC_DIR/src/ehpsctl.c"
install -Dm755 "$BUILD_DIR/ehpsctl" "$BIN_DIR/ehpsctl"
install -Dm644 "$SRC_DIR/systemd/z13-haptic-touchpad.service" \
    "$SYSTEMD_DIR/z13-haptic-touchpad.service"

if [ ! -e "$EHPS_CONFIG" ]; then
    install -Dm644 /dev/null "$EHPS_CONFIG"
    printf '\025\026\031\025\026\026' > "$EHPS_CONFIG"
fi

if command -v tuned-adm >/dev/null 2>&1 && [ "$ROOT" = "/" ]; then
    tuned-adm list >/dev/null
fi

if command -v systemctl >/dev/null 2>&1 && [ "$ROOT" = "/" ]; then
    systemctl daemon-reload
    systemctl enable z13-haptic-touchpad.service
fi

printf '%s\n' "Installed z13-balanced and z13-power-saver TuneD profiles."
printf '%s\n' "Installed ehpsctl and z13-haptic-touchpad.service."
printf '%s\n' "Restart tuned.service for PPD mapping changes to be reloaded."
