{
  description = "cramt's games, packaged as nixpkgs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      flake.overlays.default = final: prev: import ./pkgs {pkgs = final;};

      perSystem = {pkgs, ...}: {
        packages = import ./pkgs {inherit pkgs;};

        formatter = pkgs.alejandra;

        devShells.default = pkgs.mkShell {
          packages = [pkgs.alejandra pkgs.nix-prefetch];
        };
      };
    };
}
