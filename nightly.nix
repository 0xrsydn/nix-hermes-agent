# Nightly: HEAD of NousResearch/hermes-agent main branch.
# Auto-updated by scripts/update-nightly.sh — do not edit manually.
{ pkgs }:
pkgs.callPackage ./package.nix {
  pinVersion = "0.21.4-unstable-2026-09-24.edecebf6";
  pinRev = "edecebf69deea907beca8e5a8bdd56e6d56c0bf7";
  pinHash = "sha256-QAVOBOnSxAjpaensnejiejYm+zpHhvVJlfPDVin7E6o=";
}
