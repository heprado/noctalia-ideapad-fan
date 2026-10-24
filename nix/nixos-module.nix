# NixOS module: lets a group write the ideapad_acpi fan_mode attribute, so
# the Noctalia plugin can switch fan modes without root.
#
# udev's GROUP=/MODE= only apply to /dev nodes, not to sysfs attributes, so
# the rule chgrp/chmods the attribute itself. It matches both the coldplug
# "add" (driver already bound) and the "bind" that follows when udev loads
# ideapad_laptop from the device's modalias.
#
# fullSpeed: even fan_mode 4 follows the EC's own curve, so the fan keeps
# switching on and off under a spiky load. Lenovo's GameZone WMI method
# SetFanCooling (0x0D) pins both fans at full speed instead. It is reached
# through acpi_call by a root unit, and polkit lets the group start and stop
# only that unit, not run arbitrary ACPI methods.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.ideapad-fan;
  attr = "/sys%p/fan_mode";
  unit = "ideapad-fan-full-speed.service";

  # $1: 1 = full speed, 0 = back to the firmware curve.
  setFullSpeed = pkgs.writeShellScript "ideapad-fan-full-speed" ''
    printf '%s 0 0x0D %s' ${lib.escapeShellArg cfg.fullSpeed.acpiMethod} "$1" > /proc/acpi/call
    result=$(tr -d '\0' < /proc/acpi/call)
    case $result in
      Error*)
        echo "$result" >&2
        exit 1
        ;;
    esac
  '';
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

    fullSpeed = {
      enable = lib.mkEnableOption ''
        the ${unit} unit, which pins the fans at full speed through the
        GameZone WMI method SetFanCooling, and lets the group start and stop
        it (the plugin's game preset does). Only enable it on a model whose
        firmware implements that method (check the DSDT)'';

      acpiMethod = lib.mkOption {
        type = lib.types.str;
        default = "\\_SB.GZFD.WMAA";
        description = "ACPI path of the GameZone WMI method (WMAA of the device with GUID 887B54E3-DDDC-4B2C-8B88-68A26A8835D0).";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        users.groups.${cfg.group} = { };
        users.users = lib.genAttrs cfg.users (_: {
          extraGroups = [ cfg.group ];
        });

        services.udev.extraRules = ''
          ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="ideapad_acpi", TEST=="fan_mode", RUN+="${pkgs.coreutils}/bin/chgrp ${cfg.group} ${attr}", RUN+="${pkgs.coreutils}/bin/chmod g+w ${attr}"
        '';
      }

      (lib.mkIf cfg.fullSpeed.enable {
        boot.extraModulePackages = [ config.boot.kernelPackages.acpi_call ];
        boot.kernelModules = [ "acpi_call" ];

        systemd.services.ideapad-fan-full-speed = {
          description = "Lenovo GameZone fans at full speed";
          after = [ "systemd-modules-load.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${setFullSpeed} 1";
            ExecStop = "${setFullSpeed} 0";
          };
        };

        # The EC may drop back to its own curve across a suspend.
        powerManagement.resumeCommands = ''
          ${config.systemd.package}/bin/systemctl try-restart ${unit}
        '';

        security.polkit.enable = true;
        security.polkit.extraConfig = ''
          polkit.addRule(function(action, subject) {
            if (action.id == "org.freedesktop.systemd1.manage-units" &&
                action.lookup("unit") == "${unit}" &&
                ["start", "stop", "restart"].indexOf(action.lookup("verb")) >= 0 &&
                subject.isInGroup("${cfg.group}")) {
              return polkit.Result.YES;
            }
          });
        '';
      })
    ]
  );
}
