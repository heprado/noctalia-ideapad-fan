# noctalia-ideapad-fan

A [Noctalia](https://github.com/noctalia-dev/noctalia) bar widget with **quiet / normal / game presets** for Lenovo
IdeaPads. Each preset sets the **firmware fan mode** (the `ideapad_acpi` driver's `fan_mode`, the same setting Lenovo
Vantage changes on Windows) together with the **power profile** (power-profiles-daemon, which drives the firmware
`platform_profile` and the CPU's energy preference). The fan and how much heat CPU/GPU may make change together.

| Preset | Fan (`fan_mode`)   | Power profile |
| ------ | ------------------ | ------------- |
| Quiet  | Quiet (0)          | power-saver   |
| Normal | Standard (1)       | balanced      |
| Game   | Max cooling (4)    | performance   |

- **Click** steps to the next preset (normal → game → quiet), **right click** steps back.
- The tooltip shows the preset, fan mode, power profile and CPU package temperature.
- If the power profile is changed elsewhere (Noctalia's power profile widget, `powerprofilesctl`), the widget shows
  **Custom**.
- The last preset is saved and reapplied when Noctalia starts, since the firmware resets the fan mode on boot
  (setting *Restore preset on start*).
- Setting *Change the power profile* off (or no `powerprofilesctl`): presets only change the fan mode.

Reading `fan_mode` back isn't reliable on every model (an IdeaPad Gaming 3 15IMH05 reports codes like `133` and `3`),
so the widget shows the last preset it applied rather than parsing the attribute. `fan_mode` 2 ("dust cleaning", a
short full-speed cycle) and 3 (rejected by the driver) aren't used.

## Full speed fans (game preset)

Even max cooling (`fan_mode` 4) follows the EC's own curve, so under a spiky load the fans keep switching on and off.
Lenovo's GameZone WMI interface (GUID `887B54E3-DDDC-4B2C-8B88-68A26A8835D0`) has a `SetFanCooling` method (id `0x0D`)
that pins both fans at full speed: on an IdeaPad Gaming 3 15IMH05 they go from ~2800/2600 to ~6000/5000 RPM and
stay there. The NixOS module's `fullSpeed` option wraps it in a root unit, `ideapad-fan-full-speed.service` (through
`acpi_call`), and a polkit rule lets the `ideapad-fan` group start and stop only that unit. When the unit exists, the
game preset starts it and the other presets stop it (setting *Full speed fans in game*).

Check the firmware first: in the decompiled DSDT, the GameZone device's `WMAA` method should handle `Arg1 == 0x0D`
with an EC command (`NCMD (0x59, 0x77)` / `0x76` on the 15IMH05). If the method lives elsewhere than `\_SB.GZFD.WMAA`,
set `fullSpeed.acpiMethod`.

## Layout

```
ideapad-fan/
  plugin.toml
  service.luau        the only writer: applies, saves and restores the preset, polls profile and CPU temperature
  widget.luau         the bar widget; asks the service for a preset through noctalia.state
  lib/presets.luau    the preset table and click cycle
  translations/       en, pt-BR
nix/
  nixos-module.nix    udev rule + group so fan_mode is writable without root; optional full-speed unit
  hm-module.nix       installs the plugin into ~/.local/share/noctalia/plugins
```

## Permissions

`fan_mode` is root-only by default. udev's `GROUP=`/`MODE=` don't apply to sysfs attributes, so a rule has to
chgrp/chmod the file itself:

```
ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="ideapad_acpi", TEST=="fan_mode", RUN+="/usr/bin/chgrp ideapad-fan /sys%p/fan_mode", RUN+="/usr/bin/chmod g+w /sys%p/fan_mode"
```

Then add your user to the `ideapad-fan` group and log in again.

## NixOS

```nix
inputs.noctalia-ideapad-fan.url = "github:heprado/noctalia-ideapad-fan";

# NixOS configuration
imports = [ inputs.noctalia-ideapad-fan.nixosModules.default ];
hardware.ideapad-fan = {
  enable = true;
  users = [ "alice" ];
  # Optional, see "Full speed fans" above.
  fullSpeed.enable = true;
};

# home-manager configuration
imports = [ inputs.noctalia-ideapad-fan.homeManagerModules.default ];
programs.noctalia-ideapad-fan.enable = true;
```

Then enable the plugin once, and add `heprado/ideapad-fan:widget` to a bar:

```sh
noctalia msg plugins enable heprado/ideapad-fan
```

## Other distros

Add this repo as a plugin source (`noctalia msg plugins source add ideapad-fan git
https://github.com/heprado/noctalia-ideapad-fan`), enable `heprado/ideapad-fan`, and install the udev rule above.
