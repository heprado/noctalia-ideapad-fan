# NixOS module: lets a group write the ideapad_acpi fan_mode attribute, so
# the Noctalia plugin can switch fan modes without root.
#
# udev's GROUP=/MODE= only apply to /dev nodes, not to sysfs attributes, so
# the rule chgrp/chmods the attribute itself. It matches both the coldplug
# "add" (driver already bound) and the "bind" that follows when udev loads
# ideapad_laptop from the device's modalias.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.ideapad-fan;
  attr = "/sys%p/fan_mode";
in
{
  options.hardware.ideapad-fan = {
    enable = lib.mkEnableOption "unprivileged writes to the Lenovo IdeaPad fan_mode attribute";

    group = lib.mkOption {
      type = lib.types.str;
      default = "ideapad-fan";
      description = "Group allowed to write fan_mode.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "alice" ];
      description = "Users added to the group. Takes effect at their next login.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.group} = { };
    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [ cfg.group ];
    });

    services.udev.extraRules = ''
      ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="ideapad_acpi", TEST=="fan_mode", RUN+="${pkgs.coreutils}/bin/chgrp ${cfg.group} ${attr}", RUN+="${pkgs.coreutils}/bin/chmod g+w ${attr}"
    '';
  };
}
