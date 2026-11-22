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

  patchedTopLevels = lib.unique (
    lib.concatMap (
      patch:
      map (line: lib.head (lib.splitString "/" (lib.removePrefix "+++ b/" line))) (
        lib.filter (lib.hasPrefix "+++ b/") (lib.splitString "\n" (builtins.readFile patch))
      )
    ) patches
  );

  applyPatches =
    pkg:
    let
      venv = pkg.passthru.hermesVenv;
      patchedVenv = venv.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          sp=$(echo "$out"/lib/python*/site-packages)
          for entry in ${lib.escapeShellArgs patchedTopLevels}; do
            target=$(readlink -f "$sp/$entry")
            rm -rf "$sp/$entry"
            cp -r --no-preserve=mode "$target" "$sp/$entry"
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
    defaultDependencyGroups = dependencyGroups;
    pmPackages = prev.pmPackages // {
      inherit ffmpeg;
    };
  })
)
