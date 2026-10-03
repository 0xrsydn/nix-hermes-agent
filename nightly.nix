# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.0.0-unstable-2026-10-03.c8301ea6";
  pinRev = "c8301ea6c9b797184df16a9c5dd462400b264ff4";
  pinHash = "sha256-49sv18vGFDl2R1x0P7/lpadnXD13+Qo8jmWH3QTfvWE=";
}
