{
  lib,
  python312Packages,
  python312,
  fetchFromGitHub,
  fetchPypi,
  fetchurl,
  makeWrapper,
  nodejs_22,
  ripgrep,
  ffmpeg,
  git,
  pinVersion ? "0.21.1",
  pinRev ? "2237be355906fbe6065ce1815711eee52b2d646e",
  pinHash ? "sha256-2NuDx7rjsoBDO4I/iMoZsJ+5IaAbiNrDc+sFuzOe08w=",
}:

let
  # Override python package set to fix broken upstream tests
  python = python312.override {
    packageOverrides = _final: prev: {
      sanic = prev.sanic.overridePythonAttrs (_old: {
        # sanic 25.12.0 has a flaky test_keep_alive_client_timeout in nixpkgs sandbox
        doCheck = false;
      });
      pytest-services = prev.pytest-services.overridePythonAttrs (_old: {
        # pytest-services fails with PermissionError in Nix sandbox (/tmp/service-locks)
        doCheck = false;
      });
      cherrypy = prev.cherrypy.overridePythonAttrs (_old: {
        # cherrypy test_logging tests crash in macOS Nix sandbox (signal 0)
        doCheck = false;
      });
      apscheduler = prev.apscheduler.overridePythonAttrs (_old: {
        # apscheduler processpool tests fail in the nix sandbox (signal handling)
        doCheck = false;
      });
      slack-bolt = prev.slack-bolt.overridePythonAttrs (_old: {
        # slack-bolt 1.27.0 tests crash at interpreter shutdown in the nix
        # sandbox (_enter_buffered_busy: could not acquire lock for stderr)
        doCheck = false;
      });
      tenacity = prev.tenacity.overridePythonAttrs (_old: rec {
        # hermes-agent >=0.4.0 requires tenacity >=9.1.4; nixpkgs has 9.1.2
        version = "9.1.4";
        src = fetchPypi {
          pname = "tenacity";
          inherit version;
          hash = "sha256-rbMdTCY/K9BBCBqzO0mDCaV8d/ms8ttlqt8ImBec+To=";
        };
        patches = [ ];
      });
      firecrawl-py = prev.firecrawl-py.overridePythonAttrs (_old: rec {
        # hermes-agent >=0.4.0 requires firecrawl-py >=4.16.0; nixpkgs builds from GitHub
        version = "4.16.0";
        src = fetchPypi {
          pname = "firecrawl_py";
          inherit version;
          hash = "sha256-X21v3rNARCnIUfxaTpkPZlmp6ccld7Q0SArRYWuwM3Q=";
        };
        sourceRoot = null;
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

  parallel-web = pythonPackages.buildPythonPackage rec {
    pname = "parallel-web";
    version = "0.4.2";
    pyproject = true;
    src = fetchPypi {
      pname = "parallel_web";
      inherit version;
      hash = "sha256-WZtajzh9w1x9yMgeNy6t9pWKQKys6li/Fw38ZjwAPac=";
    };
    build-system = with pythonPackages; [
      hatchling
      hatch-fancy-pypi-readme
    ];
    pythonRelaxDeps = true;
    postPatch = ''
      # Relax exact hatchling pin so nixpkgs version works
      sed -i 's/hatchling==1.26.3/hatchling>=1.26.3/' pyproject.toml
    '';
    dependencies = with pythonPackages; [
      anyio
      distro
      httpx
      pydantic
      sniffio
      typing-extensions
    ];
    doCheck = false;
    pythonImportsCheck = [ "parallel" ];
  };

  nemo-relay = pythonPackages.buildPythonPackage rec {
    pname = "nemo-relay";
    version = "0.6.0";
    # Upstream 0.6.x ships only compiled abi3 wheels on PyPI (no buildable
    # sdist for the Nix sandbox); the prebuilt manylinux wheel has no base
    # runtime dependencies.
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/a3/f4/d1dfaed022da0f6f14765a122867f976a69cc520fe1faaf99757f5719d1f/nemo_relay-0.6.0-cp311-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
      hash = "sha256-hJ2qnkUVisWB5UUG4PzHok9VfR7Qbb3AdPXeegA5PLw=";
    };
    doCheck = false;
    pythonImportsCheck = [ "nemo_relay" ];
  };

  firecrawl-anydoc = pythonPackages.buildPythonPackage rec {
    pname = "firecrawl-anydoc";
    version = "0.2.4";
    # Upstream ships only Rust/maturin artifacts; the prebuilt abi3 wheel has
    # no base runtime dependencies (PyPI requires_dist is empty). x86_64-linux
    # wheel only — matches the system the flake's checks target.
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/fc/16/feeca9705bfdb237f1cb69ede0b373b144c0d51df4297e595a74b815557e/firecrawl_anydoc-0.2.4-cp310-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
      hash = "sha256-DlrtAb9tTlxYjTNjiIKT8s7rn+sARJoy4LqZN5fPC9M=";
    };
    doCheck = false;
    pythonImportsCheck = [ "anydoc" ];
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

  version = pinVersion;
  rev = pinRev;

  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    inherit rev;
    hash = pinHash;
    fetchSubmodules = true;
  };

in
pythonPackages.buildPythonApplication {
  pname = "hermes-agent";
  inherit version src;
  pyproject = true;

  build-system = [ pythonPackages.setuptools ];

  # Upstream setup.py refuses wheel builds unless HERMES_NIX_BUILD=1 is set;
  # their nix/python.nix sets it in the build sandbox (see setup.py ~line 32).
  env.HERMES_NIX_BUILD = "1";

  # litellm is compromised — strip it from wheel metadata so pythonRuntimeDepsCheck passes
  pythonRemoveDeps = [ "litellm" ];
  pythonRelaxDeps = true;

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
    ruamel-yaml
    requests
    jinja2
    markdown
    pydantic
    prompt-toolkit
    psutil
    pathspec
    fastapi
    # Tools
    firecrawl-py
    fal-client
    parallel-web
    # Document conversion (upstream >=0.21.0, firecrawl-anydoc==0.2.4)
    firecrawl-anydoc
    # tool_search BM25 stemming (upstream >=0.20.6, snowballstemmer==3.1.1)
    snowballstemmer
    # TTS
    edge-tts
    faster-whisper
    # mini-swe-agent deps
    typer
    platformdirs
    # Skills Hub
    pyjwt
    cryptography
    pillow
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
    # Relay (lazy-imported per profile via agent/relay_runtime.py)
    nemo-relay
  ];

  nativeBuildInputs = [ makeWrapper ];

  # Don't run tests during build
  doCheck = false;

  # Upstream pyproject.toml may be missing minisweagent_path / mini_swe_runner
  # from py-modules. Also ensure mini-swe-agent/src is importable.
  postPatch = ''
    # Relax pinned build backend: upstream requires setuptools==83.0.0, nixpkgs
    # (locked c06b4ae) ships 80.10.1; the exact pin fails the pypa build check.
    sed -i 's/setuptools==83.0.0/setuptools>=80/' pyproject.toml

    # Fix: add minisweagent_path.py to py-modules if missing from pyproject.toml
    if [ -f minisweagent_path.py ] && ! grep -q minisweagent_path pyproject.toml; then
      sed -i 's/py-modules = \[/py-modules = ["minisweagent_path", /' pyproject.toml
    fi

    # Fix: add mini_swe_runner.py to py-modules if missing (upstream rename)
    if [ -f mini_swe_runner.py ] && ! grep -q mini_swe_runner pyproject.toml; then
      sed -i 's/py-modules = \[/py-modules = ["mini_swe_runner", /' pyproject.toml
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
