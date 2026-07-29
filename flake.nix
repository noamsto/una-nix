{
  description = "Nix toolchain and app builder for the UNA Watch SDK";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    una-sdk = {
      url = "github:UNAWatch/una-sdk";
      flake = false;
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      imports = [
        ./nix/sdk.nix
        ./nix/lib.nix
        ./nix/apps.nix
        ./nix/devshell.nix
        ./nix/checks.nix
        ./nix/simulator.nix
      ];
    };
}
