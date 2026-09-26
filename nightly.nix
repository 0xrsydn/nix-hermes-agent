# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.0.0-unstable-2026-09-26.d0288be5";
  pinRev = "d0288be5b3330d2442e3907185b8e9d0958297bb";
  pinHash = "sha256-6guR2TYEkqw04Qt+8Ek7ciOxdAtoTO9S9vBeQzv/hFc=";
}
