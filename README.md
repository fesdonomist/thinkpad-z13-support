# z13-tuned

TuneD profiles for a ThinkPad Z13 Gen 1 AMD 6850U.

- `z13-balanced`: stock `powersave` plus Z13 extras, CPU boost on, EPP `balance_power|power`.
- `z13-power-saver`: inherits `z13-balanced`, but sets EPP to `power`.

AMDGPU ABM/backlight reduction is kept off with `panel_power_savings=0` and
`amdgpu.abmlevel=0`. AMDGPU DPM is left dynamic, but biased to the battery
state so the 680M iGPU is less eager to boost for light desktop work.

USB autosuspend is enabled with a short delay for fixed internal non-HID
devices. Root hubs, removable/external-port devices, and USB HID devices such as
keyboards, mice, trackpads, and receivers are kept awake.

HDA audio power saving is set to a 1 second idle timeout.

The bundled `ppd.conf` maps PPD modes to:

- `balanced` -> `z13-balanced`
- `power-saver` -> `z13-power-saver`
- `performance` -> `throughput-performance`

It also includes `ehpsctl`, a small replacement for the ELAN haptic touchpad
settings loader. The installer builds it, writes a default
`/etc/z13-tuned/ehps.config`, and enables `z13-haptic-touchpad.service` so the
settings are applied on boot.

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
`/etc/z13-tuned/ehps.config`, `/opt/z13-tuned/bin/ehpsctl`, and
`/etc/systemd/system/z13-haptic-touchpad.service`.
