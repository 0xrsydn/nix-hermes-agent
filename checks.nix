{ pkgs, hermes-agent }:

{
  # Verify package contents — binaries exist and are executable
  package-contents = pkgs.runCommand "hermes-package-contents" { } ''
    set -e

    echo "=== Checking binaries ==="
    test -x ${hermes-agent}/bin/hermes || (echo "FAIL: hermes binary missing"; exit 1)
    test -x ${hermes-agent}/bin/hermes-agent || (echo "FAIL: hermes-agent binary missing"; exit 1)
    test -x ${hermes-agent}/bin/hermes-acp || (echo "FAIL: hermes-acp binary missing"; exit 1)
    echo "PASS: All binaries present"

    echo "=== Checking version ==="
    ${hermes-agent}/bin/hermes version 2>&1 | grep -q "Hermes Agent" || (echo "FAIL: version check"; exit 1)
    echo "PASS: Version check"

    echo "=== Checking key Python modules ==="
    SITE=${hermes-agent}/lib/python3.12/site-packages
    for mod in agent cli.py gateway cron tools run_agent.py model_tools.py minisweagent_path.py acp_adapter honcho_integration; do
      if [ ! -e "$SITE/$mod" ] && [ ! -e "$SITE/$mod.py" ]; then
        echo "FAIL: Missing module $mod"
        exit 1
      fi
    done
    echo "PASS: All key modules present"

    echo "=== Checking wrapped PATH includes runtime deps ==="
    cat ${hermes-agent}/bin/hermes | grep -q "PATH" || (echo "FAIL: hermes not wrapped with PATH"; exit 1)
    echo "PASS: PATH wrapping"

    echo "=== All checks passed ==="
    mkdir -p $out
    echo "ok" > $out/result
  '';

  # Verify hermes CLI subcommands are accessible
  cli-commands = pkgs.runCommand "hermes-cli-commands" { } ''
    set -e
    export HOME=$(mktemp -d)

    echo "=== Checking hermes --help ==="
    ${hermes-agent}/bin/hermes --help 2>&1 | grep -q "gateway" || (echo "FAIL: gateway subcommand missing"; exit 1)
    ${hermes-agent}/bin/hermes --help 2>&1 | grep -q "claw" || (echo "FAIL: claw subcommand missing"; exit 1)
    ${hermes-agent}/bin/hermes --help 2>&1 | grep -q "config" || (echo "FAIL: config subcommand missing"; exit 1)
    ${hermes-agent}/bin/hermes --help 2>&1 | grep -q "cron" || (echo "FAIL: cron subcommand missing"; exit 1)
    ${hermes-agent}/bin/hermes --help 2>&1 | grep -q "skills" || (echo "FAIL: skills subcommand missing"; exit 1)
    ${hermes-agent}/bin/hermes --help 2>&1 | grep -q "acp" || (echo "FAIL: acp subcommand missing"; exit 1)
    echo "PASS: All subcommands accessible"

    echo "=== Checking hermes config ==="
    ${hermes-agent}/bin/hermes config 2>&1 | grep -q "Config:" || (echo "FAIL: config output"; exit 1)
    echo "PASS: Config command"

    echo "=== Checking hermes claw migrate --help ==="
    ${hermes-agent}/bin/hermes claw migrate --help 2>&1 | grep -q "OpenClaw" || (echo "FAIL: claw migrate"; exit 1)
    echo "PASS: Claw migrate"

    echo "=== All CLI checks passed ==="
    mkdir -p $out
    echo "ok" > $out/result
  '';

  # Verify hermes-agent doesn't crash on import (exit 124 = timeout, not import error)
  hermes-agent-import = pkgs.runCommand "hermes-agent-import" { } ''
    set -e
    export HOME=$(mktemp -d)

    echo "=== Testing hermes-agent starts without import errors ==="
    # hermes-agent is interactive (fire CLI), so it will hang waiting for input.
    # Exit 124 (timeout) = OK. Any other exit = import/crash error.
    timeout 3 ${hermes-agent}/bin/hermes-agent 2>&1 || CODE=$?
    if [ "''${CODE:-0}" = "124" ]; then
      echo "PASS: hermes-agent starts (timed out waiting for input, no import errors)"
    elif [ "''${CODE:-0}" = "0" ]; then
      echo "PASS: hermes-agent exited cleanly"
    else
      echo "FAIL: hermes-agent crashed with exit code $CODE"
      exit 1
    fi

    mkdir -p $out
    echo "ok" > $out/result
  '';

  # Verify doctor runs without crashing
  doctor = pkgs.runCommand "hermes-doctor" { } ''
    set -e
    export HOME=$(mktemp -d)

    echo "=== Running hermes doctor ==="
    ${hermes-agent}/bin/hermes doctor 2>&1 | grep -q "Python" || (echo "FAIL: doctor"; exit 1)
    echo "PASS: Doctor runs successfully"

    mkdir -p $out
    echo "ok" > $out/result
  '';

  # Verify upstream source exposed to the module contains skills trees
  skills-source-layout = pkgs.runCommand "hermes-skills-source-layout" { } ''
    set -e

    SRC=${hermes-agent.upstreamSrc}

    echo "=== Checking upstream skills trees ==="
    test -d "$SRC/skills" || (echo "FAIL: missing skills/ in upstream source"; exit 1)
    test -d "$SRC/optional-skills" || (echo "FAIL: missing optional-skills/ in upstream source"; exit 1)
    find "$SRC/skills" -name SKILL.md -print -quit | grep -q . || (echo "FAIL: no bundled SKILL.md found"; exit 1)
    find "$SRC/optional-skills" -name SKILL.md -print -quit | grep -q . || (echo "FAIL: no optional SKILL.md found"; exit 1)
    echo "PASS: upstream skills source layout present"

    mkdir -p $out
    echo "ok" > $out/result
  '';
}
