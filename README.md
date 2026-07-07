# z13-tuned

TuneD profiles for a ThinkPad Z13 Gen 1 AMD 6850U.

- `z13-balanced`: stock `powersave` plus Z13 extras, CPU boost on, EPP `balance_power|power`, RyzenAdj 9 W sustained / 15 W fast, 7 A sustained / 15 A peak SoC current, and 15 A sustained CPU current.
- `z13-power-saver`: inherits `z13-balanced`, but sets EPP to `power`, RyzenAdj 9 W sustained / 15 W fast, 7 A sustained / 15 A peak SoC current, and 15 A sustained CPU current.
- `z13-performance`: inherits `z13-balanced`, but sets EPP to `balance_performance|performance`, RyzenAdj 30 W sustained / 35 W fast, and restores higher CPU/SoC current limits.

AMDGPU ABM/backlight reduction is kept off with `panel_power_savings=0`.
The installer also builds a systemd-stub UKI addon at
`/boot/loader/addons/z13-tuned.addon.efi` so early kernel/module parameters
apply even when KDE Linux downloads prebuilt UKIs. The addon carries an initrd
fragment with `/etc/modprobe.d/z13-amdgpu.conf` for AMDGPU module options:

- `abmlevel=0`
- `dcdebugmask=0`
- `aspm=1`
- `bapm=1`
- `dpm=1`

The addon command line only contains options that are not available through
`modprobe.d`:

- `pcie_aspm=force`
- `pcie_aspm.policy=powersupersave`
- `iomem=relaxed`

Reboot after installing for the addon parameters to take effect. If Secure Boot
is enabled, the addon must be signed with a trusted key. AMDGPU
`power_dpm_state` is a runtime sysfs setting, not a kernel command-line
parameter, and it did not affect iGPU clock behavior on this machine.
`iomem=relaxed` is included so RyzenAdj can attempt its `/dev/mem` fallback on
kernels that permit relaxed I/O memory access.

USB autosuspend is enabled with a short delay for fixed internal non-HID
devices. Root hubs, removable/external-port devices, and USB HID devices such as
keyboards, mice, trackpads, and receivers are kept awake.

HDA audio power saving is set to a 1 second idle timeout.

The bundled `ppd.conf` maps PPD modes to:

On AC power:

- `balanced` -> `z13-ac-balanced` -> `z13-performance`
- `power-saver` -> `z13-ac-power-saver` -> `z13-performance`
- `performance` -> `z13-performance`

On battery:

- `balanced` -> `z13-balanced`
- `power-saver` -> `z13-power-saver`
- `performance` -> `z13-performance`

It also includes `ehpsctl`, a small replacement for the ELAN haptic touchpad
settings loader. The installer builds it, writes a default
`/etc/z13-tuned/ehps.config`, and enables `z13-haptic-touchpad.service` so the
settings are applied on boot.

On live installs, the installer also clones and builds RyzenAdj into
`/opt/z13-tuned/bin/ryzenadj`. Set `INSTALL_RYZENADJ=0` to skip it, or
`INSTALL_RYZENADJ=1` to force it during staged installs. Override the source
with `RYZENADJ_REPO` and `RYZENADJ_REF`.

When RyzenAdj is installed, the TuneD profile script applies profile-specific
APU policy on activation:

- `z13-balanced`: `--power-saving`, 9 W STAPM/slow PPT, 15 W fast PPT, 7 A sustained / 15 A peak SoC current, 15 A sustained CPU current.
- `z13-power-saver`: `--power-saving`, 9 W STAPM/slow PPT, 15 W fast PPT, 7 A sustained / 15 A peak SoC current, 15 A sustained CPU current.
- `z13-performance`: `--max-performance`, 30 W slow PPT, 35 W fast PPT, 13 A sustained / 17 A peak SoC current, 50 A sustained / 105 A peak CPU current.

The profiles do not set RyzenAdj temperature limits or STAPM/slow time
constants; those stay at firmware defaults.

Set `RYZENADJ=/path/to/ryzenadj` if the binary is installed somewhere else.

Install:

```sh
run0 ./install.sh
run0 systemctl restart tuned.service
```

Configure the haptic touchpad:

```sh
run0 ehpsctl set --click-force medium --feedback-state 4
run0 ehpsctl set --post-button-force high --topzone-post-button on
ehpsctl show
```

The installer writes to `/etc/tuned/profiles`, `/etc/tuned/ppd.conf`,
`/boot/loader/addons/z13-tuned.addon.efi`, `/etc/z13-tuned/ehps.config`,
`/opt/z13-tuned/bin`, and `/etc/systemd/system/z13-haptic-touchpad.service`.
