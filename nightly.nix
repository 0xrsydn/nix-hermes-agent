# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.3.0-unstable-2026-03-22";
  pinRev = "43bca6d107c86efc7e60a4a35ca8a55e1b4b4c1e";
  pinHash = "sha256-cd9jDrphEwjJqNLR3FNrg/xze2sFWhIzmvWLYa2CV5E=";
}
