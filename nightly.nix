# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.0.0-unstable-2026-10-10.7318e666";
  pinRev = "7318e666c236aa8fffc3506c705d1c00a4821441";
  pinHash = "sha256-2tsjqKVMkovIGPw8RP+GYRlEkncWokViN00yn3gIGVA=";
}
