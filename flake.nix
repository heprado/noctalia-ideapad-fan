{
  description = "IdeaPad Fan Mode: a Noctalia bar widget for the Lenovo IdeaPad firmware fan mode";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The plugin source tree as Noctalia expects it: catalog.toml plus one
      # directory per plugin.
      packages = forAllSystems (pkgs: rec {
        noctalia-ideapad-fan = pkgs.runCommand "noctalia-ideapad-fan" { } ''
          mkdir -p $out
          cp -r ${./ideapad-fan} $out/ideapad-fan
          cp ${./catalog.toml} $out/catalog.toml
        '';
        default = noctalia-ideapad-fan;
      });

      nixosModules = rec {
        ideapad-fan = import ./nix/nixos-module.nix;
        default = ideapad-fan;
      };

      homeManagerModules = rec {
        noctalia-ideapad-fan = import ./nix/hm-module.nix self;
        default = noctalia-ideapad-fan;
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
