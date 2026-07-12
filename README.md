# WARNING! The code is predominantly AI slop, and this pokes at hardware so YMMV.

# z13-tuned

TuneD profiles for a ThinkPad Z13 Gen 1 AMD 6850U.

- `z13-balanced`: stock `powersave` plus Z13 extras, CPU boost on, EPP `balance_power|power`, and ACPI `low-power`.
- `z13-power-saver`: inherits `z13-balanced`, sets EPP to `power`, and ACPI `low-power`.
- `z13-performance`: inherits `z13-balanced`, sets EPP to `balance_performance|performance`, and ACPI `performance`.

AMDGPU ABM/backlight reduction is kept off with `panel_power_savings=0`.
AMDGPU's forced DPM performance level is left at `auto` in every profile.
The installer also builds a systemd-stub UKI addon at
`/boot/loader/addons/z13-tuned.addon.efi` so early kernel/module parameters
apply even when KDE Linux downloads prebuilt UKIs. The addon carries an initrd
fragment with `/etc/modprobe.d/z13-amdgpu.conf` for AMDGPU module options:

- `abmlevel=0`
- `aspm=1`
- `bapm=1`
- `dpm=1`

The addon command line only contains options that are not available through
`modprobe.d`:

- `pcie_aspm.policy=powersupersave`
- `amdgpu.dcdebugmask=0`
- `amdgpu.dcfeaturemask=0x28b`

Reboot after installing for the addon parameters to take effect. If Secure Boot
is enabled, the addon must be signed with a trusted key. AMDGPU
`power_dpm_state` is a runtime sysfs setting, not a kernel command-line
parameter, and it did not affect iGPU clock behavior on this machine.
`amdgpu.dcdebugmask=0` is intentionally a kernel command-line override, not a
`modprobe.d` option, so it can append after KDE Linux's shipped
`amdgpu.dcdebugmask=0x10` and stop disabling AMDGPU PSR on this 680M machine.
`amdgpu.dcfeaturemask=0x28b` preserves the currently enabled `0x2` DC feature
bit, adds `DC_FBC_MASK` (`0x1`), `DC_PSR_MASK` (`0x8`),
`DC_PSR_ALLOW_SMU_OPT` (`0x80`), and `DC_REPLAY_MASK` (`0x200`).

USB autosuspend is enabled with a short delay for fixed internal non-HID
devices. Root hubs, removable/external-port devices, and USB HID devices such as
keyboards, mice, trackpads, and receivers are kept awake.

HDA audio power saving is set to a 1 second idle timeout.

Wi-Fi power save is enabled only in `z13-power-saver`. `z13-balanced` and
`z13-performance` keep Wi-Fi power save off and force the wireless PCI function
awake for better link quality. Wake-on-Wi-Fi remains disabled.

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

Package power limits remain under firmware control through the ACPI platform
profile. The installer removes binaries installed by older versions of this
repository and does not use RyzenAdj or access the SMU directly.

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
