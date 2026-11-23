{
  lib,
  hermes-agent,
  release,
}:
{
  pkgs,
  dependencyGroups ? [ "messaging" ],
  ffmpeg ? pkgs.ffmpeg-headless,
  git ? pkgs.git,
  openssh ? pkgs.openssh,
  patches ? [
    ./patches/codex-kanban-stop-guard.patch
    ./patches/provider-plugin-snapshot-writable.patch
  ],
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  upstreamRev = hermes-agent.rev or "";
  version =
    if upstreamRev == release.rev then
      release.version
    else
      "${release.version}+unstable.${builtins.substring 0 7 upstreamRev}";

  applyPatches =
    pkg:
    let
      venv = pkg.passthru.hermesVenv;
      patchedVenv = venv.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          sp=$(echo "$out"/lib/python*/site-packages)
          hermes_sp=$(dirname "$(readlink -f "$sp/hermes_cli")")
          for entry in "$sp"/*; do
            [ -L "$entry" ] || continue
            target=$(readlink -f "$entry")
            case "$target" in
              "$hermes_sp"/*) ;;
              *) continue ;;
            esac
            rm "$entry"
            cp -r --no-preserve=mode "$target" "$entry"
          done
          ${lib.concatMapStrings (patch: ''
            patch -d "$sp" -p1 --forward --no-backup-if-mismatch < ${patch}
          '') patches}
        '';
      });
    in
    pkg.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        grep -rlZ -F ${venv} "$out" | xargs -0 -r sed -i "s|${venv}|${patchedVenv}|g"
      '';
      passthru = old.passthru // {
        hermesVenv = patchedVenv;
      };
    });

  finalize =
    pkg:
    (if patches == [ ] then pkg else applyPatches pkg)
    // {
      override = args: finalize (pkg.override args);
    };
in
finalize (
  hermes-agent.packages.${system}.minimal.override (prev: {
    inherit version git openssh;
    ffmpeg-headless = ffmpeg;
    defaultDependencyGroups = dependencyGroups;
    pmPackages = prev.pmPackages // {
      inherit ffmpeg;
    };
  })
)
