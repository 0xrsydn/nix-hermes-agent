{
  pkgs,
  mkHermesAgent,
  release,
  upstreamRev,
  src,
}:
let
  inherit (pkgs) lib;

  hermes = mkHermesAgent { inherit pkgs; };
  extended = hermes.override { extraDependencyGroups = [ "exa" ]; };
  unpatchedVenv =
    (mkHermesAgent {
      inherit pkgs;
      patches = [ ];
    }).passthru.hermesVenv;

  python = pkg: "${pkg.passthru.hermesVenv}/bin/python3";

  check =
    name: script:
    pkgs.runCommand "hermes-${name}" { } ''
      set -euo pipefail
      export HOME=$(mktemp -d)
      ${script}
      touch "$out"
    '';
in
{
  release-pin = check "release-pin" ''
    if [ ${lib.escapeShellArg upstreamRev} != ${lib.escapeShellArg release.rev} ]; then
      echo "flake.lock pins hermes-agent at ${upstreamRev}, release.nix says ${release.rev}" >&2
      exit 1
    fi
  '';

  cli = check "cli" ''
    for bin in hermes hermes-agent hermes-acp; do
      test -x ${hermes}/bin/$bin
    done
    ${hermes}/bin/hermes --version | tee version.txt
    grep -F ${lib.escapeShellArg release.version} version.txt
    help=$(${hermes}/bin/hermes --help)
    for command in gateway config cron skills profile plugins; do
      grep -qw "$command" <<<"$help" || { echo "missing subcommand: $command" >&2; exit 1; }
    done
    doctor=$(${hermes}/bin/hermes doctor 2>&1 || true)
    grep -q Python <<<"$doctor"
  '';

  patches-live = check "patches-live" ''
    grep -q build_kanban_stop_nudge ${hermes.passthru.hermesVenv}/lib/python*/site-packages/agent/codex_runtime.py
    if grep -rqF ${unpatchedVenv} ${hermes}; then
      echo "the package still references the unpatched venv:" >&2
      grep -rlF ${unpatchedVenv} ${hermes} >&2
      exit 1
    fi
    grep -qF ${hermes.passthru.hermesVenv} ${hermes}/bin/hermes
  '';

  provider-plugin-from-store = check "provider-plugin-from-store" ''
    export HERMES_HOME=$HOME/.hermes
    mkdir -p "$HERMES_HOME/plugins/model-providers"
    ln -s ${./tests/fixtures/store-provider} "$HERMES_HOME/plugins/model-providers/store-provider"
    ${python hermes} -c 'from providers import get_provider_profile; assert get_provider_profile("store-provider"), "a store-path provider plugin did not register"'
  '';

  dependency-groups = check "dependency-groups" ''
    ${python hermes} -c 'import telegram, discord, slack_sdk'
    for module in faster_whisper av elevenlabs edge_tts boto3 modal daytona lark_oapi dingtalk_stream mautrix; do
      if ${python hermes} -c "import $module" 2>/dev/null; then
        echo "dropped dependency is importable: $module" >&2
        exit 1
      fi
    done
  '';

  override-keeps-layer = check "override-keeps-layer" ''
    ${python extended} -c 'import exa_py, telegram'
    grep -q build_kanban_stop_nudge ${extended.passthru.hermesVenv}/lib/python*/site-packages/agent/codex_runtime.py
    ${extended}/bin/hermes --version | grep -F ${lib.escapeShellArg release.version}
  '';

  shared-tools = check "shared-tools" ''
    grep -qF ${lib.getBin pkgs.ffmpeg-headless}/bin ${hermes}/bin/hermes
    grep -qF ${lib.getBin pkgs.git}/bin ${hermes}/bin/hermes
  '';

  lint =
    pkgs.runCommand "hermes-lint"
      {
        nativeBuildInputs = [
          pkgs.nixfmt
          pkgs.statix
        ];
        src = lib.fileset.toSource {
          root = src;
          fileset = lib.fileset.fileFilter (file: file.hasExt "nix") src;
        };
      }
      ''
        cd "$src"
        find . -name '*.nix' -print0 | xargs -0 nixfmt --check
        statix check .
        touch "$out"
      '';

  update-scripts =
    pkgs.runCommand "hermes-update-scripts"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        src = lib.fileset.toSource {
          root = src;
          fileset = lib.fileset.unions [
            (src + "/scripts")
            (src + "/tests/test_render_update_report.py")
            (src + "/tests/update-common.sh")
          ];
        };
      }
      ''
        cp -r "$src" work
        chmod -R u+w work
        cd work
        python3 -m unittest tests/test_render_update_report.py
        bash tests/update-common.sh
        touch "$out"
      '';
}
