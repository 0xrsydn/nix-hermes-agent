# nix-hermes-agent

A lean Nix package and NixOS module for
[Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research.

Upstream ships its own uv2nix package and NixOS module. This flake builds on
both and changes what gets installed:

- **Only the integrations you use.** Upstream's default package turns on every
  optional dependency group: local speech-to-text, premium TTS, DingTalk,
  Feishu, Matrix, Bedrock, Modal, Daytona, Vercel and more. This package starts
  from upstream's `minimal` variant and adds only the groups you list.
- **Shared tools.** `ffmpeg`, `git` and `openssh` come from your nixpkgs, so
  Hermes uses the same store paths as the rest of your system instead of
  bringing its own (upstream's ffmpeg alone is 432 MiB).
- **A real version.** Upstream's package reports `0.0.0`, which makes plugins
  with a `requires_hermes` gate refuse to load. This package stamps the release
  version from `release.nix`.
- **Carried fixes.** Patches in `patches/` apply to the installed Python code,
  and every launcher points at the patched environment.

Python dependencies stay exactly as upstream locks them in `uv.lock`, so you
run the dependency set upstream tested.

## Use the NixOS module

```nix
{
  inputs.nix-hermes.url = "github:0xrsydn/nix-hermes-agent";

  outputs = { nixpkgs, nix-hermes, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        nix-hermes.nixosModules.default
        {
          services.hermes-agent = {
            enable = true;
            settings.model.default = "anthropic/claude-sonnet-4.6";
            environmentFiles = [ "/run/secrets/hermes-env" ];
          };
        }
      ];
    };
  };
}
```

`nixosModules.default` is upstream's module with this package as the default
`services.hermes-agent.package`. Every upstream option works unchanged; see
upstream's `nix/moduleCommon.nix` and `nix/nixosModules.nix`.

## Choose the integrations

```nix
services.hermes-agent.package = nix-hermes.lib.mkHermesAgent {
  inherit pkgs;
  dependencyGroups = [ "messaging" "exa" "fal" "parallel-web" ];
  ffmpeg = pkgs.ffmpeg;
};
```

| Argument | Default | Meaning |
| --- | --- | --- |
| `pkgs` | required | Your nixpkgs. `ffmpeg`, `git` and `openssh` default to its packages. |
| `dependencyGroups` | `[ "messaging" ]` | Upstream's optional dependency groups (the extras in its `pyproject.toml`). `messaging` covers Telegram, Discord and Slack. |
| `ffmpeg` | `pkgs.ffmpeg-headless` | The ffmpeg on Hermes' `PATH`. Pass the one already on your system to share it. |
| `git`, `openssh` | `pkgs.git`, `pkgs.openssh` | The same, for git and ssh. |
| `patches` | `patches/*.patch` | Patches applied to the installed Python code; `[ ]` disables them. |

The result keeps `.override`, so upstream's module options
`extraDependencyGroups` and `extraPythonPackages` still add to it, and the
version and patches survive the override.

## Just the package

```bash
nix run github:0xrsydn/nix-hermes-agent -- --version
```

## Updates

`release.nix` names the upstream release, and the `hermes-agent` input in
`flake.nix` pins its tag. A scheduled workflow opens a candidate PR for each new
release, and a nightly job checks this layer against upstream `main`. See
[docs/UPDATE-POLICY.md](docs/UPDATE-POLICY.md).

## Upgrading from the 0.21 module

Up to Hermes 0.21 this flake had its own NixOS module (`services.hermes-agent.config`,
`skills`, rendered `cli-config.yaml`) and rebuilt the Python dependencies from
nixpkgs. Upstream's module now covers the same ground, and upstream pins its
dependencies exactly, so both were replaced. The last version is tagged
`legacy-0.21`; pin `github:0xrsydn/nix-hermes-agent/legacy-0.21` to stay on it.
To migrate, move `config` to upstream's `settings`, and keep `documents`,
`environment` and `environmentFiles` as they are.

## License

MIT
