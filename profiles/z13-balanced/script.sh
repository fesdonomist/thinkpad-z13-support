#!/bin/sh
# ThinkPad Z13 Gen 1 AMD 6850U extras for TuneD.

set -u

PROFILE_NAME="${Z13_TUNED_PROFILE:-${0%/*}}"
PROFILE_NAME="${PROFILE_NAME##*/}"
case "$PROFILE_NAME" in
    z13-balanced|z13-power-saver|z13-performance)
        ;;
    balanced|power-saver|performance)
        PROFILE_NAME="z13-$PROFILE_NAME"
        ;;
    *)
        PROFILE_NAME="z13-balanced"
        ;;
esac

TAG="$PROFILE_NAME"
RYZENADJ="${RYZENADJ:-/opt/z13-tuned/bin/ryzenadj}"

info() {
    printf '%s: %s\n' "$TAG" "$*"
}

warn() {
    printf '%s: %s\n' "$TAG" "$*"
}

error() {
    printf '%s: %s\n' "$TAG" "$*" >&2
}

read_one() {
    [ -r "$1" ] && cat "$1" 2>/dev/null || true
}

write_one() {
    value="$1"
    path="$2"

    [ -e "$path" ] || return 0

    if [ ! -w "$path" ]; then
        info "skip non-writable $path"
        return 0
    fi

    if { printf '%s\n' "$value" > "$path"; } 2>/dev/null; then
        info "set $path=$value"
    else
        warn "failed to set $path=$value"
    fi
}

write_glob() {
    value="$1"
    shift

    for pattern in "$@"; do
        # Intentional glob expansion.
        for path in $pattern; do
            [ -e "$path" ] || continue
            write_one "$value" "$path"
        done
    done
}

check_amd_pstate() {
    status="$(read_one /sys/devices/system/cpu/amd_pstate/status)"
    driver="$(read_one /sys/devices/system/cpu/cpufreq/policy0/scaling_driver)"

    if [ "$status" = "active" ] && [ "$driver" = "amd-pstate-epp" ]; then
        info "amd-pstate EPP active"
        return 0
    fi

    warn "amd-pstate EPP is not active"
    warn "status='$status' scaling_driver='$driver'"
    warn "add amd_pstate=active to the kernel command line and reboot"
}

apply_cpu_boost_on() {
    write_one 1 /sys/devices/system/cpu/cpufreq/boost
    write_glob 1 /sys/devices/system/cpu/cpufreq/policy*/boost
}

ensure_dev_mem() {
    if [ -e /dev/mem ]; then
        return 0
    fi

    if ! command -v mknod >/dev/null 2>&1; then
        warn "skip /dev/mem creation: mknod not found"
        return 0
    fi

    if mknod /dev/mem c 1 1 2>/dev/null; then
        chmod 600 /dev/mem 2>/dev/null || true
        info "created /dev/mem for ryzenadj fallback"
    else
        warn "failed to create /dev/mem for ryzenadj fallback"
    fi
}

apply_ryzenadj_policy() {
    if [ ! -x "$RYZENADJ" ]; then
        info "skip ryzenadj: $RYZENADJ not executable"
        return 0
    fi

    ensure_dev_mem

    case "$PROFILE_NAME" in
        z13-power-saver)
            set -- --power-saving \
                --fast-limit=15000 \
                --slow-limit=6000
            ;;
        z13-performance)
            set -- --max-performance \
                --fast-limit=40000 \
                --slow-limit=30000
            ;;
        *)
            set -- --power-saving \
                --fast-limit=15000 \
                --slow-limit=8000
            ;;
    esac

    if "$RYZENADJ" "$@" >/dev/null 2>&1; then
        info "applied ryzenadj policy for $PROFILE_NAME"
    else
        warn "failed to apply ryzenadj policy for $PROFILE_NAME"
    fi
}

apply_pci_runtime_pm() {
    write_glob auto /sys/bus/pci/devices/*/power/control
}

apply_amdgpu_extras() {
    write_glob auto /sys/class/drm/card*/device/power/control
    case "$PROFILE_NAME" in
        z13-power-saver)
            write_glob low /sys/class/drm/card*/device/power_dpm_force_performance_level
            ;;
        z13-performance)
            write_glob auto /sys/class/drm/card*/device/power_dpm_force_performance_level
            ;;
        *)
            write_glob low /sys/class/drm/card*/device/power_dpm_force_performance_level
            ;;
    esac
}

apply_display_polling_off() {
    write_one N /sys/module/drm_kms_helper/parameters/poll
}

apply_audio_power_save() {
    write_one 1 /sys/module/snd_hda_intel/parameters/power_save
}

apply_nvme_apst() {
    write_one 100000 /sys/module/nvme_core/parameters/default_ps_max_latency_us
    write_glob auto /sys/class/nvme/nvme*/device/power/control
    write_glob auto /sys/block/nvme*n*/device/power/control
}

usb_has_interface_class() {
    device="$1"
    class="$2"

    for interface in "$device":*; do
        [ -e "$interface/bInterfaceClass" ] || continue
        [ "$(read_one "$interface/bInterfaceClass")" = "$class" ] && return 0
    done

    return 1
}

apply_usb_autosuspend() {
    write_one 2 /sys/module/usbcore/parameters/autosuspend

    for device in /sys/bus/usb/devices/*; do
        [ -d "$device" ] || continue

        name="${device##*/}"
        control="$device/power/control"
        [ -e "$control" ] || continue

        # Keep root hubs and anything on external/removable ports awake.
        case "$name" in
            usb*)
                write_one on "$control"
                continue
                ;;
        esac

        if [ "$(read_one "$device/removable")" = "removable" ]; then
            write_one on "$control"
            continue
        fi

        # Keep USB HID devices awake: keyboards, mice, trackpads, receivers.
        if usb_has_interface_class "$device" 03; then
            write_one on "$control"
            continue
        fi

        write_one auto "$control"
        write_one 2000 "$device/power/autosuspend_delay_ms"
    done
}

apply_bluetooth_adapter_pm() {
    write_one Y /sys/module/btusb/parameters/enable_autosuspend

    for hci in /sys/class/bluetooth/hci*; do
        [ -e "$hci" ] || continue
        write_one auto "$hci/power/control"
        write_one 2000 "$hci/power/autosuspend_delay_ms"
        write_one disabled "$hci/power/wakeup"

        backing="$(readlink -f "$hci/device" 2>/dev/null || true)"
        [ -n "$backing" ] || continue
        write_one auto "$backing/power/control"
        write_one 2000 "$backing/power/autosuspend_delay_ms"
        write_one disabled "$backing/power/wakeup"

        controller="$(dirname "$backing")"
        if [ -e "$controller/idVendor" ] && [ -e "$controller/idProduct" ]; then
            write_one auto "$controller/power/control"
            write_one 2000 "$controller/power/autosuspend_delay_ms"
            write_one disabled "$controller/power/wakeup"
        fi
    done
}

apply_soft_watchdog_off() {
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -q -w kernel.soft_watchdog=0 || true
    else
        write_one 0 /proc/sys/kernel/soft_watchdog
    fi
}

apply_qualcomm_wifi_powersave() {
    if command -v iw >/dev/null 2>&1; then
        for iface_path in /sys/class/net/*; do
            [ -d "$iface_path/wireless" ] || continue
            iface="${iface_path##*/}"

            case "$PROFILE_NAME" in
                z13-power-saver)
                    wifi_power_save=on
                    wifi_runtime_pm=auto
                    ;;
                *)
                    wifi_power_save=off
                    wifi_runtime_pm=on
                    ;;
            esac

            if iw dev "$iface" set power_save "$wifi_power_save" 2>/dev/null; then
                info "set Wi-Fi power_save $wifi_power_save on $iface"
            else
                warn "failed to set Wi-Fi power_save $wifi_power_save on $iface"
            fi

            write_one "$wifi_runtime_pm" "$iface_path/device/power/control"
            write_one disabled "$iface_path/device/power/wakeup"
        done

        for phy_path in /sys/class/ieee80211/phy*; do
            [ -e "$phy_path" ] || continue
            phy="${phy_path##*/}"
            if iw phy "$phy" wowlan disable 2>/dev/null; then
                info "disabled WoWLAN on $phy"
            else
                warn "failed to disable WoWLAN on $phy"
            fi
        done
    else
        warn "iw not found; cannot set runtime Wi-Fi power_save or WoWLAN"
    fi

}

apply_network_wake_off() {
    for iface_path in /sys/class/net/*; do
        [ -e "$iface_path" ] || continue
        iface="${iface_path##*/}"
        [ "$iface" = "lo" ] && continue

        write_one disabled "$iface_path/device/power/wakeup"

        [ -d "$iface_path/wireless" ] && continue
        if command -v ethtool >/dev/null 2>&1; then
            if ethtool -s "$iface" wol d >/dev/null 2>&1; then
                info "disabled Wake-on-LAN on $iface"
            fi
        fi
    done
}

apply_all() {
    check_amd_pstate
    apply_cpu_boost_on
    apply_ryzenadj_policy
    apply_pci_runtime_pm
    apply_amdgpu_extras
    apply_display_polling_off
    apply_audio_power_save
    apply_nvme_apst
    apply_usb_autosuspend
    apply_bluetooth_adapter_pm
    apply_soft_watchdog_off
    apply_qualcomm_wifi_powersave
    apply_network_wake_off
}

case "${1:-start}" in
    start|verify)
        apply_all
        ;;
    stop)
        exit 0
        ;;
    *)
        error "unknown action: $1"
        exit 2
        ;;
esac
