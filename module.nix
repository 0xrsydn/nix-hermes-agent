self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.hermes-agent;
  inherit (self.packages.${pkgs.system}) hermes-agent;

  # Deep-merge config type (same pattern as nix-openclaw)
  deepConfigType = lib.types.mkOptionType {
    name = "hermes-config-attrs";
    description = "Hermes YAML config (attrset), merged deeply via lib.recursiveUpdate.";
    check = builtins.isAttrs;
    merge = _loc: defs: lib.foldl' lib.recursiveUpdate { } (map (d: d.value) defs);
  };

  # Convert Nix attrset → YAML via JSON intermediary
  # (Hermes reads YAML but YAML is a superset of JSON, so JSON works)
  configJson = builtins.toJSON cfg.config;
  generatedConfigFile = pkgs.writeText "cli-config.yaml" configJson;
  configFile = if cfg.configFile != null then cfg.configFile else generatedConfigFile;

  # Generate .env file from environment attrset (non-secret env vars)
  envFileContent = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k}=${v}") cfg.environment);
  generatedEnvFile = pkgs.writeText "hermes-env" envFileContent;

  # Document files → symlinked into workspace
  documentDerivation = pkgs.runCommand "hermes-documents" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: value:
        if builtins.isPath value || lib.isStorePath value then
          "cp ${value} $out/${name}"
        else
          "cat > $out/${name} <<'HERMES_DOC_EOF'\n${value}\nHERMES_DOC_EOF"
      ) cfg.documents
    )
  );

in
{
  options.services.hermes-agent = with lib; {
    enable = mkEnableOption "Hermes Agent gateway service";

    # ── Package ──────────────────────────────────────────────────────────
    package = mkOption {
      type = types.package;
      default = hermes-agent;
      description = "The hermes-agent package to use.";
    };

    # ── Service identity ─────────────────────────────────────────────────
    unitName = mkOption {
      type = types.str;
      default = "hermes-agent";
      description = "systemd unit name (<unitName>.service).";
    };

    user = mkOption {
      type = types.str;
      default = "hermes";
      description = "System user running the gateway.";
    };

    group = mkOption {
      type = types.str;
      default = "hermes";
      description = "System group running the gateway.";
    };

    createUser = mkOption {
      type = types.bool;
      default = true;
      description = "Create the user/group automatically.";
    };

    # ── Directories ──────────────────────────────────────────────────────
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/hermes";
      description = "State directory (HERMES_HOME base). Contains .hermes/ subdir.";
    };

    workingDirectory = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/workspace";
      defaultText = literalExpression ''"''${cfg.stateDir}/workspace"'';
      description = "Working directory for the agent (MESSAGING_CWD).";
    };

    # ── Config (declarative YAML) ────────────────────────────────────────
    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to an existing cli-config.yaml. If set, takes precedence over
        the declarative `config` option.
      '';
    };

    config = mkOption {
      type = deepConfigType;
      default = { };
      description = ''
        Declarative Hermes config (attrset). Deep-merged across module definitions
        and rendered as cli-config.yaml. See upstream cli-config.yaml.example for
        all available keys.
      '';
      example = literalExpression ''
        {
          model = {
            default = "anthropic/claude-sonnet-4-20250514";
            provider = "openrouter";
          };
          terminal = {
            backend = "local";
            timeout = 180;
          };
          agent = {
            max_turns = 60;
            reasoning_effort = "medium";
          };
          memory = {
            memory_enabled = true;
            user_profile_enabled = true;
          };
          toolsets = [ "all" ];
        }
      '';
    };

    # ── Secrets / environment ────────────────────────────────────────────
    environmentFiles = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Paths to environment files containing secrets (API keys, tokens).
        These are passed as systemd EnvironmentFile= entries.
        Use leading '-' to ignore missing files.

        Example file contents:
          ANTHROPIC_API_KEY=sk-ant-...
          OPENROUTER_API_KEY=sk-or-...
          TELEGRAM_TOKEN=123456:ABC...
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        Non-secret environment variables for Hermes. These are written to
        an env file (visible in the Nix store — do NOT put secrets here).
        Use `environmentFiles` for secrets.
      '';
      example = literalExpression ''
        {
          LLM_MODEL = "anthropic/claude-opus-4.6";
          MESSAGING_CWD = "/var/lib/hermes/workspace";
        }
      '';
    };

    authFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to an auth.json seed file containing OAuth credentials
        (Nous Portal, Codex, Anthropic OAuth).

        This file is only copied on first deploy — if auth.json already exists
        in the state directory, it is NOT overwritten. This preserves runtime
        token refreshes across rebuilds and restarts.

        To force a re-seed, delete the existing auth.json first:
          rm /var/lib/hermes/.hermes/auth.json

        If null, auth.json is managed entirely at runtime via `hermes login`.
      '';
    };

    authFileForceOverwrite = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If true, always overwrite auth.json from authFile on activation.
        WARNING: This destroys any runtime-refreshed tokens.
        Only use for testing or when you know the seed file has fresh tokens.
      '';
    };

    # ── Documents (SOUL.md, AGENTS.md, etc.) ─────────────────────────────
    documents = mkOption {
      type = types.attrsOf (types.either types.str types.path);
      default = { };
      description = ''
        Workspace document files. Keys are filenames, values are either
        inline strings or paths to files. These are symlinked into the
        workspace directory on activation.
      '';
      example = literalExpression ''
        {
          "SOUL.md" = '''
            # SOUL.md
            You are a helpful AI assistant.
          ''';
          "AGENTS.md" = ./my-agents.md;
          "USER.md" = '''
            # USER.md
            Name: Fay
          ''';
        }
      '';
    };

    # ── Service behavior ─────────────────────────────────────────────────
    logPath = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/logs/gateway.log";
      defaultText = literalExpression ''"''${cfg.stateDir}/logs/gateway.log"'';
      description = "Log file path.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra command-line arguments for `hermes gateway`.";
    };

    execStart = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Override ExecStart command. If unset, runs: hermes gateway.";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Extra packages to make available on PATH.";
    };

    restart = mkOption {
      type = types.str;
      default = "always";
      description = "systemd Restart= policy.";
    };

    restartSec = mkOption {
      type = types.int;
      default = 5;
      description = "systemd RestartSec= value.";
    };

    # ── MCP servers ──────────────────────────────────────────────────────
    mcpServers = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            command = mkOption {
              type = types.str;
              description = "MCP server command.";
            };
            args = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            env = mkOption {
              type = types.attrsOf types.str;
              default = { };
            };
            timeout = mkOption {
              type = types.nullOr types.int;
              default = null;
            };
          };
        }
      );
      default = { };
      description = "MCP server configurations (merged into config.mcp_servers).";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Merge MCP servers into config ────────────────────────────────────
    services.hermes-agent.config = lib.mkIf (cfg.mcpServers != { }) {
      mcp_servers = lib.mapAttrs (
        _name: srv:
        {
          inherit (srv) command args;
        }
        // lib.optionalAttrs (srv.env != { }) { inherit (srv) env; }
        // lib.optionalAttrs (srv.timeout != null) { inherit (srv) timeout; }
      ) cfg.mcpServers;
    };

    # ── User / group ─────────────────────────────────────────────────────
    users.groups.${cfg.group} = lib.mkIf cfg.createUser { };
    users.users.${cfg.user} = lib.mkIf cfg.createUser {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.stateDir;
      createHome = true;
      shell = pkgs.bashInteractive;
    };

    # ── Directories ──────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.stateDir}/.hermes 0750 ${cfg.user} ${cfg.group} - -"
      "d ${cfg.workingDirectory} 0750 ${cfg.user} ${cfg.group} - -"
      "d ${builtins.dirOf cfg.logPath} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    # ── Activation: link config + documents into state dir ───────────────
    system.activationScripts."hermes-agent-setup" = lib.stringAfter [ "users" ] ''
      # Link config file
      install -o ${cfg.user} -g ${cfg.group} -m 0640 -D ${configFile} ${cfg.stateDir}/.hermes/cli-config.yaml

      # Seed auth file if provided (only if not already present, unless force overwrite)
      ${lib.optionalString (cfg.authFile != null) ''
        ${
          if cfg.authFileForceOverwrite then
            ''
              install -o ${cfg.user} -g ${cfg.group} -m 0600 ${cfg.authFile} ${cfg.stateDir}/.hermes/auth.json
            ''
          else
            ''
              if [ ! -f ${cfg.stateDir}/.hermes/auth.json ]; then
                install -o ${cfg.user} -g ${cfg.group} -m 0600 ${cfg.authFile} ${cfg.stateDir}/.hermes/auth.json
              fi
            ''
        }
      ''}

      # Link documents into workspace
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: _value: ''
          install -o ${cfg.user} -g ${cfg.group} -m 0644 ${documentDerivation}/${name} ${cfg.workingDirectory}/${name}
        '') cfg.documents
      )}
    '';

    # ── systemd service ──────────────────────────────────────────────────
    systemd.services.${cfg.unitName} = {
      description = "Hermes Agent Gateway";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        HOME = cfg.stateDir;
        HERMES_HOME = "${cfg.stateDir}/.hermes";
        MESSAGING_CWD = cfg.workingDirectory;
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.workingDirectory;

        EnvironmentFile = [ generatedEnvFile ] ++ cfg.environmentFiles;

        ExecStart =
          if cfg.execStart != null then
            cfg.execStart
          else
            lib.concatStringsSep " " (
              [
                "${cfg.package}/bin/hermes"
                "gateway"
              ]
              ++ cfg.extraArgs
            );

        Restart = cfg.restart;
        RestartSec = cfg.restartSec;

        StandardOutput = "append:${cfg.logPath}";
        StandardError = "append:${cfg.logPath}";

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = false;
        ReadWritePaths = [ cfg.stateDir ];
        PrivateTmp = true;
      };

      path = [
        cfg.package
        pkgs.bash
        pkgs.coreutils
        pkgs.git
      ]
      ++ cfg.extraPackages;
    };
  };
}
