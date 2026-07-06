#!/bin/sh
set -eu

ROOT="${ROOT:-/}"
PROFILE_DIR="$ROOT/etc/tuned/profiles"
PPD_CONF="$ROOT/etc/tuned/ppd.conf"
SRC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

install -Dm644 "$SRC_DIR/profiles/z13-balanced/tuned.conf" \
    "$PROFILE_DIR/z13-balanced/tuned.conf"
install -Dm755 "$SRC_DIR/profiles/z13-balanced/script.sh" \
    "$PROFILE_DIR/z13-balanced/script.sh"
install -Dm644 "$SRC_DIR/profiles/z13-power-saver/tuned.conf" \
    "$PROFILE_DIR/z13-power-saver/tuned.conf"
install -Dm644 "$SRC_DIR/ppd.conf" "$PPD_CONF"

if command -v tuned-adm >/dev/null 2>&1; then
    tuned-adm list >/dev/null
fi

printf '%s\n' "Installed z13-balanced and z13-power-saver TuneD profiles."
printf '%s\n' "Restart tuned.service for PPD mapping changes to be reloaded."
