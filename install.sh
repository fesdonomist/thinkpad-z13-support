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
INSTALL_RYZENADJ="${INSTALL_RYZENADJ:-auto}"
RYZENADJ_REPO="${RYZENADJ_REPO:-https://github.com/FlyGoat/RyzenAdj.git}"
RYZENADJ_REF="${RYZENADJ_REF:-master}"

CC="${CC:-cc}"
CFLAGS="${CFLAGS:--O2 -Wall -Wextra}"

have() {
    command -v "$1" >/dev/null 2>&1
}

install_ryzenadj() {
    case "$INSTALL_RYZENADJ" in
        0|no|false|off)
            return 0
            ;;
        auto)
            [ "$ROOT" = "/" ] || return 0
            ;;
        1|yes|true|on)
            ;;
        *)
            printf '%s\n' "INSTALL_RYZENADJ must be auto, 1, or 0" >&2
            return 2
            ;;
    esac

    for tool in git cmake; do
        if ! have "$tool"; then
            printf '%s\n' "Cannot build ryzenadj: $tool not found" >&2
            return 1
        fi
    done

    RYZENADJ_SRC="$BUILD_DIR/RyzenAdj"
    RYZENADJ_BUILD="$BUILD_DIR/RyzenAdj-build"
    rm -rf "$RYZENADJ_SRC" "$RYZENADJ_BUILD"

    git clone --depth 1 --branch "$RYZENADJ_REF" "$RYZENADJ_REPO" "$RYZENADJ_SRC"
    cmake -S "$RYZENADJ_SRC" -B "$RYZENADJ_BUILD" \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build "$RYZENADJ_BUILD"

    RYZENADJ_BIN="$(find "$RYZENADJ_BUILD" -type f -name ryzenadj -perm -111 | head -n 1)"
    if [ -z "$RYZENADJ_BIN" ]; then
        printf '%s\n' "Cannot find built ryzenadj binary" >&2
        return 1
    fi

    install -Dm755 "$RYZENADJ_BIN" "$BIN_DIR/ryzenadj"
}

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
install -Dm644 "$SRC_DIR/ppd.conf" "$PPD_CONF"

mkdir -p "$BUILD_DIR"
"$CC" $CFLAGS -o "$BUILD_DIR/ehpsctl" "$SRC_DIR/src/ehpsctl.c"
install -Dm755 "$BUILD_DIR/ehpsctl" "$BIN_DIR/ehpsctl"
install_ryzenadj
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

printf '%s\n' "Installed z13-balanced, z13-power-saver, and z13-performance TuneD profiles."
printf '%s\n' "Installed ehpsctl and z13-haptic-touchpad.service."
if [ -x "$BIN_DIR/ryzenadj" ]; then
    printf '%s\n' "Installed ryzenadj."
fi
printf '%s\n' "Installed z13-tuned UKI command-line addon."
printf '%s\n' "Reboot for UKI addon kernel parameters to take effect."
printf '%s\n' "Restart tuned.service for PPD mapping changes to be reloaded."
