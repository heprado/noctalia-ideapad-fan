# noctalia-ideapad-fan

A [Noctalia](https://github.com/noctalia-dev/noctalia) bar widget that switches the **Lenovo IdeaPad firmware fan
mode** through the `ideapad_acpi` driver's `fan_mode` attribute: the same setting Lenovo Vantage changes on Windows.

| Mode        | `fan_mode` |
| ----------- | ---------- |
| Quiet       | 0          |
| Standard    | 1          |
| Max cooling | 4          |

- **Click** steps to the next mode (standard → max cooling → quiet), **right click** steps back.
- The tooltip shows the mode and the CPU package temperature.
- The last mode is saved and reapplied when Noctalia starts, since the firmware resets it on boot (setting
  *Restore mode on start*).

Reading `fan_mode` back isn't reliable on every model (an IdeaPad Gaming 3 15IMH05 reports codes like `133` and `3`),
so the widget shows the last mode it set rather than parsing the attribute.

## Layout

```
ideapad-fan/
  plugin.toml
  service.luau        the only writer: applies, saves and restores the mode, polls the CPU temperature
  widget.luau         the bar widget; asks the service for a mode through noctalia.state
  lib/modes.luau      the mode table and click cycle
  translations/       en, pt-BR
nix/
  nixos-module.nix    udev rule + group so fan_mode is writable without root
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
