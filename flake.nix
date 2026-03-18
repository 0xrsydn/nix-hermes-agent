{
  description = "Nix package and NixOS module for Hermes Agent by Nous Research";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages = {
          hermes-agent = pkgs.callPackage ./package.nix { };
          default = self.packages.${system}.hermes-agent;
        };

        checks =
          (import ./checks.nix {
            inherit pkgs;
            inherit (self.packages.${system}) hermes-agent;
          })
          // {
            skills-coexistence = import ./tests/skills-coexistence.nix {
              inherit self nixpkgs system;
            };
          };

        devShells.default = pkgs.mkShell {
          packages = [ self.packages.${system}.hermes-agent ];
        };
      }
    )
    // {
      nixosModules = {
        hermes-agent = import ./module.nix self;
        default = self.nixosModules.hermes-agent;
      };

      overlays.default = final: prev: {
        hermes-agent = final.callPackage ./package.nix { };
      };
    };
}
