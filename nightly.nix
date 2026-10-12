# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.0.0-unstable-2026-10-12.82ef40ab";
  pinRev = "82ef40ab2956505b6c2a8d8957c94874abdbed3c";
  pinHash = "sha256-mulHhCVeby1AlsiwyKCoNkfVsFNHiA7tOYEqSJ+kC4Q=";
}
