#!/usr/bin/env bash

set_output() {
  local name=$1 value=$2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
  fi
}

upstream_source() {
  nix flake archive --json 2>/dev/null | jq -r '.inputs["hermes-agent"].path // empty' || true
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
