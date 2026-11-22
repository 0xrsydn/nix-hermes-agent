# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.23.3-unstable-2026-11-22.0f602c5f";
  pinRev = "0f602c5f6f18615632535251d62a2db74ce93b69";
  pinHash = "sha256-hFfJ9fkX1rUVp2vDYNw9JtBd57ej91jIbTVno8GzCqY=";
}
