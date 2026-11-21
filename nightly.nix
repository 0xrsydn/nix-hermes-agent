# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.23.3-unstable-2026-11-21.aeb5a071";
  pinRev = "aeb5a071069dbd85d85f2c8d44337f16df29d475";
  pinHash = "sha256-ejI3sqo47A/7R1n06cX5YqVUP+8WhHLcSHC4YboLZHA=";
}
