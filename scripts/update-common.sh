#!/usr/bin/env bash

set_output() {
  local name=$1 value=$2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
  fi
}

extract_sri_hash() {
  sed -nE 's/.*got:[[:space:]]*(sha256-[A-Za-z0-9+\/=]+).*/\1/p' "$1" | head -1
}

realize_flake_source() {
  nix build "$1.src" --no-link --print-out-paths 2>/dev/null | tail -1 || true
}

current_nix_system() {
  nix eval --impure --raw --expr builtins.currentSystem
}

publish_summary() {
  local report=$1
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" && -f "$report" ]]; then
    cat "$report" >>"$GITHUB_STEP_SUMMARY"
  fi
}

# Validation failure is data for the candidate PR, not a reason to discard it.
run_validation() {
  local log_file=$1
  shift
  if "$@" >"$log_file" 2>&1; then
    printf 'passed\n'
  else
    printf 'failed\n'
  fi
}

# Upstream's version since v0.21.6: semver release tags, while pyproject.toml
# keeps the placeholder 0.0.0 (the real version comes from an install stamp).
# Older calendar tags (v2026.9.24, a 4-digit "major") still carry it in
# pyproject.toml.
#   upstream_version <release-tag> <commit-sha>
upstream_version() {
  local tag=$1 sha=$2 version
  if [[ "$tag" =~ ^v([0-9]{1,3}\.[0-9]+\.[0-9]+)$ ]]; then
    version=${BASH_REMATCH[1]}
  else
    version=$(
      gh api -H "Accept: application/vnd.github.raw+json" \
        "/repos/NousResearch/hermes-agent/contents/pyproject.toml?ref=${sha}" |
        python3 -c 'import sys, tomllib; print(tomllib.load(sys.stdin.buffer)["project"]["version"])'
    )
  fi
  if [[ -z "$version" || "$version" == 0.0.0 ]]; then
    printf 'error: no usable upstream version for %s (%s)\n' "$tag" "$sha" >&2
    return 1
  fi
  printf '%s\n' "$version"
}
