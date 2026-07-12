#!/bin/sh
set -eu

ROOT="${ROOT:-/}"
PROFILE_DIR="$ROOT/etc/tuned/profiles"
PPD_CONF="$ROOT/etc/tuned/ppd.conf"
CONFIG_DIR="$ROOT/etc/z13-tuned"
EHPS_CONFIG="$CONFIG_DIR/ehps.config"
BIN_DIR="$ROOT/opt/z13-tuned/bin"
SYSTEMD_DIR="$ROOT/etc/systemd/system"
ADDON_DIR="$ROOT/boot/loader/addons"
SRC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BUILD_DIR="${BUILD_DIR:-${TMPDIR:-/tmp}/z13-tuned-build}"
ADDON_STUB="${ADDON_STUB:-/usr/lib/systemd/boot/efi/addonx64.efi.stub}"

CC="${CC:-cc}"
CFLAGS="${CFLAGS:--O2 -Wall -Wextra}"

install -Dm644 "$SRC_DIR/profiles/z13-balanced/tuned.conf" \
    "$PROFILE_DIR/z13-balanced/tuned.conf"
install -Dm755 "$SRC_DIR/profiles/z13-balanced/script.sh" \
    "$PROFILE_DIR/z13-balanced/script.sh"
install -Dm644 "$SRC_DIR/profiles/z13-power-saver/tuned.conf" \
    "$PROFILE_DIR/z13-power-saver/tuned.conf"
install -Dm755 "$SRC_DIR/profiles/z13-power-saver/script.sh" \
    "$PROFILE_DIR/z13-power-saver/script.sh"
install -Dm644 "$SRC_DIR/profiles/z13-performance/tuned.conf" \
    "$PROFILE_DIR/z13-performance/tuned.conf"
install -Dm755 "$SRC_DIR/profiles/z13-performance/script.sh" \
    "$PROFILE_DIR/z13-performance/script.sh"
install -Dm644 "$SRC_DIR/profiles/z13-ac-balanced/tuned.conf" \
    "$PROFILE_DIR/z13-ac-balanced/tuned.conf"
install -Dm644 "$SRC_DIR/profiles/z13-ac-power-saver/tuned.conf" \
    "$PROFILE_DIR/z13-ac-power-saver/tuned.conf"
install -Dm644 "$SRC_DIR/ppd.conf" "$PPD_CONF"

mkdir -p "$BUILD_DIR"
"$CC" $CFLAGS -o "$BUILD_DIR/ehpsctl" "$SRC_DIR/src/ehpsctl.c"
install -Dm755 "$BUILD_DIR/ehpsctl" "$BIN_DIR/ehpsctl"
rm -f "$BIN_DIR/ryzenadj"
install -Dm644 "$SRC_DIR/systemd/z13-haptic-touchpad.service" \
    "$SYSTEMD_DIR/z13-haptic-touchpad.service"
INITRD_DIR="$BUILD_DIR/addon-initrd"
rm -rf "$INITRD_DIR"
install -Dm644 "$SRC_DIR/uki/modprobe.d/z13-amdgpu.conf" \
    "$INITRD_DIR/etc/modprobe.d/z13-amdgpu.conf"
(cd "$INITRD_DIR" && find . -print | cpio -o -H newc --quiet) \
    > "$BUILD_DIR/z13-tuned-initrd.cpio"
ukify build --stub "$ADDON_STUB" --cmdline "@$SRC_DIR/uki/z13-tuned.cmdline" \
    --initrd "$BUILD_DIR/z13-tuned-initrd.cpio" \
    --output "$BUILD_DIR/z13-tuned.addon.efi"
install -Dm644 "$BUILD_DIR/z13-tuned.addon.efi" \
    "$ADDON_DIR/z13-tuned.addon.efi"

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

printf '%s\n' "Installed Z13 TuneD profiles and AC performance aliases."
printf '%s\n' "Installed ehpsctl and z13-haptic-touchpad.service."
printf '%s\n' "Installed z13-tuned UKI command-line addon."
printf '%s\n' "Reboot for UKI addon kernel parameters to take effect."
printf '%s\n' "Restart tuned.service for PPD mapping changes to be reloaded."
