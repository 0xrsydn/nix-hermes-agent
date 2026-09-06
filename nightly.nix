# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.21.0-unstable-2026-09-06.9a84bee2";
  pinRev = "9a84bee265daad14340a80d7585928cd8ea1f9eb";
  pinHash = "sha256-eYRZ5ZMNum7f8VutnlNiIlNDK3+tlxwWjenZ63Z8RYg=";
}
