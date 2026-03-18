{
  self,
  nixpkgs,
  system,
}:

let
  pkgs = import nixpkgs { inherit system; };
  testSkill = builtins.path {
    path = ./fixtures/custom-skill;
    name = "hermes-test-custom-skill";
  };
in
pkgs.testers.runNixOSTest {
  name = "hermes-skills-coexistence";

  nodes.machine =
    { ... }:
    {
      imports = [ self.nixosModules.hermes-agent ];

      services.hermes-agent = {
        enable = true;
        package = self.packages.${system}.hermes-agent;
        skills = {
          bundled.enable = false;
          custom.repo-watch = {
            category = "research";
            source = testSkill;
          };
        };
        documents = {
          "SOUL.md" = "# SOUL.md\nTest soul\n";
          "AGENTS.md" = "# AGENTS.md\nTest agents\n";
          "USER.md" = "# USER.md\nTest user\n";
        };
        config = {
          toolsets = [ "all" ];
          model = {
            default = "moonshotai/kimi-k2.5";
            provider = "openrouter";
          };
        };
      };

      system.stateVersion = "25.05";
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    machine.succeed("test -f /var/lib/hermes/.hermes/skills/research/repo-watch/SKILL.md")
    machine.succeed("grep -F 'research/repo-watch' /var/lib/hermes/.hermes/skills/.nix-managed-skills.json")

    machine.succeed("mkdir -p /var/lib/hermes/.hermes/skills/manual-test")
    machine.succeed("cat > /var/lib/hermes/.hermes/skills/manual-test/SKILL.md <<'EOF'\n---\nname: manual-test\ndescription: unmanaged test skill\n---\n\n# manual-test\nEOF")
    machine.succeed("chown -R hermes:hermes /var/lib/hermes/.hermes/skills/manual-test")

    machine.succeed("/run/current-system/activate")

    machine.succeed("test -f /var/lib/hermes/.hermes/skills/research/repo-watch/SKILL.md")
    machine.succeed("test -f /var/lib/hermes/.hermes/skills/manual-test/SKILL.md")
  '';
}
