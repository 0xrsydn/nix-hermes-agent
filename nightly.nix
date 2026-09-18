# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.21.3-unstable-2026-09-18.c62bd9f2";
  pinRev = "c62bd9f2078a946108f1c9d9b24bf118963277ef";
  pinHash = "sha256-hdKTqxd4u1/ss3dSlrPrUVa2+GLHB9UAy8w0TGqpBd4=";
}
