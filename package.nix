{
  lib,
  python312Packages,
  python312,
  fetchFromGitHub,
  fetchPypi,
  makeWrapper,
  nodejs_22,
  ripgrep,
  ffmpeg,
  git,
}:

let
  # Override python package set to fix broken upstream tests
  python = python312.override {
    packageOverrides = _final: prev: {
      sanic = prev.sanic.overridePythonAttrs (_old: {
        # sanic 25.12.0 has a flaky test_keep_alive_client_timeout in nixpkgs sandbox
        doCheck = false;
      });
    };
  };
  pythonPackages = python.pkgs;

  # --- Missing PyPI packages ---

  fal-client = pythonPackages.buildPythonPackage rec {
    pname = "fal-client";
    version = "0.13.1";
    pyproject = true;
    src = fetchPypi {
      pname = "fal_client";
      inherit version;
      hash = "sha256-nhwH0KYbRSqP+0jBmd5fJUPXVG8SMPYxI3BEMSfF6Tc=";
    };
    build-system = with pythonPackages; [
      setuptools
      setuptools-scm
    ];
    dependencies = with pythonPackages; [
      httpx
      httpx-sse
      msgpack
      websockets
    ];
    doCheck = false;
    pythonImportsCheck = [ "fal_client" ];
  };

  honcho-ai = pythonPackages.buildPythonPackage rec {
    pname = "honcho-ai";
    version = "2.0.1";
    pyproject = true;
    src = fetchPypi {
      pname = "honcho_ai";
      inherit version;
      hash = "sha256-b97r+UVOYrxSPVeIjlA1nme6r9sh9oYh+cFOCNwAYjo=";
    };
    build-system = with pythonPackages; [
      setuptools
      wheel
    ];
    dependencies = with pythonPackages; [
      httpx
      pydantic
      typing-extensions
    ];
    doCheck = false;
    pythonImportsCheck = [ "honcho" ];
  };

  agent-client-protocol = pythonPackages.buildPythonPackage rec {
    pname = "agent-client-protocol";
    version = "0.8.1";
    pyproject = true;
    src = fetchPypi {
      pname = "agent_client_protocol";
      inherit version;
      hash = "sha256-G78VZjv1H2SUJZf2OOMqYoTF2pGAVdlnLTUQ6WUUPb0=";
    };
    build-system = [ pythonPackages.pdm-backend ];
    dependencies = with pythonPackages; [
      pydantic
    ];
    doCheck = false;
    pythonImportsCheck = [ "acp" ];
  };

  version = "0.3.0";
  rev = "6ebb816e5611aaf1f3f7187ba8b10e985e899c75";

  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    inherit rev;
    hash = "sha256-JGjusff/jGjvCCdUtl9IErBTGmpIq6BVA5Gj8mwqVYg=";
    fetchSubmodules = true;
  };

in
pythonPackages.buildPythonApplication {
  pname = "hermes-agent";
  inherit version src;
  pyproject = true;

  build-system = [ pythonPackages.setuptools ];

  dependencies = with pythonPackages; [
    # Core
    openai
    anthropic
    python-dotenv
    fire
    httpx
    rich
    tenacity
    pyyaml
    requests
    jinja2
    pydantic
    prompt-toolkit
    # Tools
    firecrawl-py
    fal-client
    # TTS
    edge-tts
    faster-whisper
    # mini-swe-agent deps
    litellm
    typer
    platformdirs
    # Skills Hub
    pyjwt
    # Messaging
    python-telegram-bot
    discordpy
    aiohttp
    slack-bolt
    slack-sdk
    # Cron
    croniter
    # CLI
    simple-term-menu
    # TTS premium
    elevenlabs
    # Voice
    sounddevice
    numpy
    # PTY
    ptyprocess
    # Honcho
    honcho-ai
    # MCP
    mcp
    # ACP
    agent-client-protocol
  ];

  nativeBuildInputs = [ makeWrapper ];

  # Don't run tests during build
  doCheck = false;

  # Upstream pyproject.toml is missing minisweagent_path from py-modules.
  # Also ensure mini-swe-agent/src is importable.
  postPatch = ''
    # Fix: add minisweagent_path.py to py-modules if missing from pyproject.toml
    if [ -f minisweagent_path.py ] && ! grep -q minisweagent_path pyproject.toml; then
      sed -i 's/py-modules = \[/py-modules = ["minisweagent_path", /' pyproject.toml
    fi

    # Make mini-swe-agent importable by copying src into the package
    if [ -d mini-swe-agent/src/minisweagent ]; then
      cp -r mini-swe-agent/src/minisweagent .
    fi
  '';

  postFixup = ''
    # Wrap binaries with runtime deps on PATH
    for bin in $out/bin/hermes $out/bin/hermes-agent $out/bin/hermes-acp; do
      if [ -f "$bin" ]; then
        wrapProgram "$bin" \
          --prefix PATH : ${
            lib.makeBinPath [
              nodejs_22
              ripgrep
              ffmpeg
              git
            ]
          }
      fi
    done
  '';

  passthru = {
    upstreamSrc = src;
  };

  meta = with lib; {
    description = "The self-improving AI agent by Nous Research";
    homepage = "https://github.com/NousResearch/hermes-agent";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "hermes";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
