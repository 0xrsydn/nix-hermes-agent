# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.21.1-unstable-2026-09-09.9e0dc431";
  pinRev = "9e0dc4319ae2d59c60f5226b5c0af58d17755bfa";
  pinHash = "sha256-4zG8gaSKeIN7sroibcKxI3zwuu9bqAKhl03QSf3jSnw=";
}
