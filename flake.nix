{
  description = "Lean Nix package and NixOS module for Hermes Agent, built on upstream's own packaging";

  inputs = {
    hermes-agent.url = "github:NousResearch/hermes-agent/v0.23.5";
    nixpkgs.follows = "hermes-agent/nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      hermes-agent,
    }:
    let
      inherit (nixpkgs) lib;
      release = import ./release.nix;
      systems = builtins.attrNames hermes-agent.packages;
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      lib.mkHermesAgent = import ./package.nix { inherit lib hermes-agent release; };

      packages = forAllSystems (pkgs: {
        default = self.lib.mkHermesAgent { inherit pkgs; };
        hermes-agent = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });

      nixosModules.default =
        { lib, pkgs, ... }:
        {
          imports = [ hermes-agent.nixosModules.default ];
          services.hermes-agent.package = lib.mkDefault (self.lib.mkHermesAgent { inherit pkgs; });
        };
      nixosModules.hermes-agent = self.nixosModules.default;

      checks = forAllSystems (
        pkgs:
        import ./checks.nix {
          inherit pkgs release;
          inherit (self.lib) mkHermesAgent;
          upstreamRev = hermes-agent.rev or "";
          src = ./.;
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
