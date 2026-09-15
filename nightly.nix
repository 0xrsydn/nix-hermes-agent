# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.21.3-unstable-2026-09-15.2932195c";
  pinRev = "2932195c22736249999776f52aa85db727bfa04e";
  pinHash = "sha256-gGKG90z0AOGmHIyfwZqs/op3YIesmfvf80cNkPlUxy4=";
}
