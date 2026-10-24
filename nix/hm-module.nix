# home-manager module: drops the plugin into Noctalia's local plugin
# directory (~/.local/share/noctalia/plugins), which Noctalia scans as its
# highest-precedence source. Like any plugin it still has to be enabled
# once: `noctalia msg plugins enable heprado/ideapad-fan`.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.noctalia-ideapad-fan;
in
{
  options.programs.noctalia-ideapad-fan = {
    enable = lib.mkEnableOption "the IdeaPad Fan Mode Noctalia plugin";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "noctalia-ideapad-fan.packages.\${system}.default";
      description = "The plugin source package (a directory holding ideapad-fan/).";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.dataFile."noctalia/plugins/ideapad-fan".source = "${cfg.package}/ideapad-fan";
  };
}
