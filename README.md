# z13-tuned

TuneD profiles for a ThinkPad Z13 Gen 1 AMD 6850U.

- `z13-balanced`: stock `powersave` plus Z13 extras, CPU boost on, EPP `balance_power|power`.
- `z13-power-saver`: inherits `z13-balanced`, but sets EPP to `power`.

AMDGPU ABM/backlight reduction is kept off with `panel_power_savings=0` and
`amdgpu.abmlevel=0`.

The bundled `ppd.conf` maps battery PPD modes to:

- `balanced` -> `z13-balanced`
- `power-saver` -> `z13-power-saver`

Install:

```sh
run0 ./install.sh
run0 systemctl restart tuned.service
```

The installer writes to `/etc/tuned/profiles` and `/etc/tuned/ppd.conf`.
