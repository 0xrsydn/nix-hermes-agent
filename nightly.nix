# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.21.3-unstable-2026-09-19.8df0a037";
  pinRev = "8df0a03793784205833f9e0db12395aa33ada433";
  pinHash = "sha256-tjckckPLURGxgto2b1y+VTyugOq7TOACL31spaf2xrg=";
}
