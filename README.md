# nix-hermes-agent

Declarative Nix package and NixOS module for [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research.

Everything is configured in Nix. Config, documents, secrets, service — one `nixos-rebuild switch` and it's live.

## Quick Start

### 1. Add to your flake

```nix
{
  inputs.nix-hermes.url = "github:0xrsydn/nix-hermes-agent";

  outputs = { self, nixpkgs, nix-hermes, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        nix-hermes.nixosModules.hermes-agent
        ./hermes.nix  # your config (see below)
      ];
    };
  };
}
```

### 2. Configure declaratively

```nix
# hermes.nix
{ ... }:
{
  services.hermes-agent = {
    enable = true;

    # ── Declarative config (renders to cli-config.yaml) ──
    config = {
      model = {
        default = "anthropic/claude-opus-4.6";
        provider = "openrouter";
      };
      terminal = {
        backend = "local";
        timeout = 180;
        lifetime_seconds = 300;
      };
      agent = {
        max_turns = 60;
        reasoning_effort = "medium";
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
        memory_char_limit = 2200;
        nudge_interval = 10;
      };
      compression = {
        enabled = true;
        threshold = 0.85;
        summary_model = "google/gemini-3-flash-preview";
      };
      toolsets = [ "all" ];
    };

    # ── Secrets (not in Nix store) ──
    environmentFiles = [
      "/run/secrets/hermes-env"  # ANTHROPIC_API_KEY, TELEGRAM_TOKEN, etc.
    ];

    # ── Non-secret env vars ──
    environment = {
      LLM_MODEL = "anthropic/claude-opus-4.6";
    };

    # ── Workspace documents (inline or file paths) ──
    documents = {
      "SOUL.md" = ''
        # SOUL.md
        You are a sharp, pragmatic AI assistant.
      '';
      "AGENTS.md" = ''
        # AGENTS.md
        Read SOUL.md first. Then help the user.
      '';
      "USER.md" = ''
        # USER.md
        Name: Your Human
      '';
      # Or reference a file:
      # "SOUL.md" = ./documents/SOUL.md;
    };

    # ── Declarative skills (phase 1) ──
    skills = {
      bundled.enable = true;
      optional = [
        "creative/blender-mcp"
      ];
      custom = {
        repo-watch = {
          category = "research";
          source = ./skills/repo-watch;
        };
      };
    };

    # ── MCP servers ──
    mcpServers = {
      context7 = {
        command = "npx";
        args = [ "-y" "@upstash/context7-mcp@latest" ];
      };
    };

    # ── Extra tools on PATH ──
    extraPackages = with pkgs; [ jq ripgrep curl ];
  };
}
```

### Secrets Management

#### Plain files approach

```nix
services.hermes-agent = {
  environmentFiles = [ "/run/secrets/hermes-env" ];
  authFile = "/run/secrets/hermes-auth.json";  # optional, for OAuth tokens
};
```

#### sops-nix approach

```nix
sops.secrets."hermes/env" = {
  sopsFile = ./secrets/hermes.yaml;
  owner = "hermes";
  group = "hermes";
};

sops.secrets."hermes/auth" = {
  sopsFile = ./secrets/hermes.yaml;
  owner = "hermes";
  group = "hermes";
};

services.hermes-agent = {
  enable = true;
  environmentFiles = [ config.sops.secrets."hermes/env".path ];
  authFile = config.sops.secrets."hermes/auth".path;
  config.model = {
    default = "anthropic/claude-opus-4.6";
    provider = "openrouter";
  };
};
```

#### Example secrets file structure

```yaml
hermes/env: |
    OPENROUTER_API_KEY=sk-or-...
    ANTHROPIC_API_KEY=sk-ant-...
    TELEGRAM_TOKEN=123456:ABC...
    GLM_API_KEY=...
hermes/auth: |
    {"nous": {"token": "...", "refresh": "..."}, "codex": {"token": "..."}}
```

### 3. Create secrets file

```bash
# /run/secrets/hermes-env (or wherever you manage secrets)
OPENROUTER_API_KEY=sk-or-...
ANTHROPIC_API_KEY=sk-ant-...
TELEGRAM_TOKEN=123456:ABC...
TELEGRAM_ALLOWED_USERS=your_user_id
```

### 4. Deploy

```bash
nixos-rebuild switch
systemctl status hermes-agent
journalctl -u hermes-agent -f
```

## Architecture

```
You (Telegram/Discord/WhatsApp/Slack) → Gateway → Tools → Machine does things
```

### How it works

1. `services.hermes-agent.config` attrset is deep-merged and rendered to `cli-config.yaml`
2. Documents are installed into the workspace directory
3. Secrets stay outside the Nix store via `environmentFiles`
4. systemd service runs `hermes gateway` with everything wired up

### Directory layout

```
/var/lib/hermes/              # stateDir
├── .hermes/                  # Hermes home (HERMES_HOME)
│   ├── cli-config.yaml       # Generated from config option
│   ├── .env                  # Secrets (from environmentFiles)
│   ├── memory/               # Agent memory (runtime)
│   ├── skills/               # Skills (runtime)
│   └── logs/                 # Session logs
├── workspace/                # workingDirectory
│   ├── SOUL.md               # From documents option
│   ├── AGENTS.md
│   └── USER.md
└── logs/
    └── gateway.log           # Service log
```

## Declarative Skills vs Native Hermes Skills

The `skills` option is designed to **augment Hermes**, not replace Hermes' native skill workflow.

Both approaches compose into the same runtime directory:

- `${stateDir}/.hermes/skills/`

That means you can use both:

- **declarative skills** from Nix
- **interactive/runtime skills** from `hermes skills install`

### Ownership model

#### Nix-managed
Skills declared via:

- `services.hermes-agent.skills.bundled`
- `services.hermes-agent.skills.optional`
- `services.hermes-agent.skills.custom`

are reconciled by the module and tracked in:

- `.nix-managed-skills.json`

These paths are considered **owned by Nix**.

#### Hermes-managed
Skills installed later via Hermes CLI, plus hub metadata under:

- `.hermes/skills/.hub/`

are left alone by the module **unless they collide with a Nix-managed path**.

### Collision rule

If a Hermes CLI install and a declarative Nix skill target the same installed path,
**the declarative Nix version wins on the next activation/rebuild**.

Example:

- Nix declares `creative/blender-mcp`
- user later installs another `creative/blender-mcp` via Hermes CLI

On the next rebuild, the Nix-declared version is restored.

### Recommended workflow

Use **Hermes CLI** for:

- experimentation
- hub/community skill discovery
- temporary installs
- trying before keeping

Use **Nix declarative skills** for:

- stable/reproducible deployments
- bundled upstream skills you always want
- selected optional skills you want pinned to the package revision
- local custom house skills stored in git

A good pattern is:

1. install/try a skill interactively,
2. decide it is worth keeping,
3. promote it into Nix config if you want it reproducible.

This keeps `nix-hermes-agent` useful without interfering with the native Hermes experience.

## Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Hermes Agent gateway |
| `config` | attrset | `{}` | Declarative config (→ cli-config.yaml) |
| `configFile` | path | `null` | Use existing config file (overrides `config`) |
| `documents` | attrset | `{}` | Workspace files (string or path values) |
| `skills` | attrset | `{}` | Declarative Hermes skills (bundled, optional, custom local) |
| `environmentFiles` | list | `[]` | Secret env files (systemd EnvironmentFile) |
| `environment` | attrset | `{}` | Non-secret env vars |
| `authFile` | path | `null` | OAuth credentials file (auth.json) |
| `mcpServers` | attrset | `{}` | MCP server configs (merged into config) |
| `user` | string | `"hermes"` | Service user |
| `group` | string | `"hermes"` | Service group |
| `stateDir` | path | `/var/lib/hermes` | State directory |
| `workingDirectory` | path | `${stateDir}/workspace` | Working directory |
| `extraPackages` | list | `[]` | Extra packages on PATH |
| `extraArgs` | list | `[]` | Extra `hermes gateway` args |
| `logPath` | path | `${stateDir}/logs/gateway.log` | Log file |
| `restart` | string | `"always"` | systemd Restart policy |
| `restartSec` | int | `5` | Restart delay |

## Config Reference

The `config` attrset maps directly to Hermes' `cli-config.yaml`. Key sections:

| Section | Purpose |
|---------|---------|
| `model` | Default model, provider, base_url |
| `terminal` | Backend (local/ssh/docker/modal), cwd, timeout |
| `agent` | max_turns, verbose, reasoning_effort, personalities |
| `memory` | memory_enabled, user_profile_enabled, char limits |
| `compression` | Context compression settings |
| `session_reset` | Auto-reset policy for messaging |
| `skills` | Skill creation nudge settings |
| `toolsets` | Which tool groups to enable |
| `mcp_servers` | MCP server connections |
| `delegation` | Subagent settings |
| `browser` | Browser tool settings |
| `stt` | Voice transcription config |
| `display` | UI/skin settings |

See the [full config reference](https://raw.githubusercontent.com/NousResearch/hermes-agent/main/cli-config.yaml.example).

## Just the Package

```bash
# Run directly
nix run github:0xrsydn/nix-hermes-agent -- --help

# In a dev shell
nix develop github:0xrsydn/nix-hermes-agent

# Use the overlay
nixpkgs.overlays = [ nix-hermes.overlays.default ];
```

## License

MIT (same as upstream)
