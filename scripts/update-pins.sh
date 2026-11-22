#!/usr/bin/env bash
set -euo pipefail

# Generate a reviewable stable candidate. The workflow owns commits and PRs;
# this script intentionally never mutates main or any remote branch.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
release_file="$repo_root/release.nix"
flake_file="$repo_root/flake.nix"
lock_file="$repo_root/flake.lock"
report=${HERMES_UPDATE_REPORT:-/tmp/hermes-stable-update.md}

# shellcheck source=scripts/update-common.sh
source "$repo_root/scripts/update-common.sh"

log() { printf '>> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null || die "gh is required"
command -v jq >/dev/null || die "jq is required"
command -v python3 >/dev/null || die "python3 is required"

release_json=$(gh api /repos/NousResearch/hermes-agent/releases/latest)
release_tag=$(printf '%s' "$release_json" | jq -r '.tag_name // empty')
[[ -n "$release_tag" ]] || die "latest release has no tag"

log "Resolving immutable commit for $release_tag"
tag_object=$(gh api "/repos/NousResearch/hermes-agent/git/ref/tags/${release_tag}")
tag_sha=$(printf '%s' "$tag_object" | jq -r '.object.sha // empty')
tag_type=$(printf '%s' "$tag_object" | jq -r '.object.type // empty')
for _depth in 1 2 3 4 5; do
  [[ "$tag_type" == "tag" ]] || break
  tag_object=$(gh api "/repos/NousResearch/hermes-agent/git/tags/${tag_sha}")
  tag_sha=$(printf '%s' "$tag_object" | jq -r '.object.sha // empty')
  tag_type=$(printf '%s' "$tag_object" | jq -r '.object.type // empty')
done
[[ "$tag_type" == "commit" && -n "$tag_sha" ]] || die "release tag does not resolve to a commit"

upstream_version=$(upstream_version "$release_tag" "$tag_sha") || die "could not determine the release version"
current_version=$(sed -nE 's/^[[:space:]]*version = "([^"]+)";/\1/p' "$release_file")
current_rev=$(sed -nE 's/^[[:space:]]*rev = "([^"]+)";/\1/p' "$release_file")
[[ -n "$current_version" && -n "$current_rev" ]] || die "could not read current stable pin"

if [[ "$current_rev" == "$tag_sha" ]]; then
  log "Already tracking $release_tag at $tag_sha"
  set_output update_available false
  set_output compatible true
  exit 0
fi

if [[ "$current_version" == "$upstream_version" ]]; then
  die "release version $upstream_version now points at a different commit; review the retag manually"
fi

python3 - "$current_version" "$upstream_version" <<'PY' || die "refusing an automatic version downgrade"
import re, sys
def version(value):
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:[-+].*)?", value)
    if not match:
        raise SystemExit(2)
    return tuple(map(int, match.groups()))
raise SystemExit(0 if version(sys.argv[2]) >= version(sys.argv[1]) else 1)
PY

set_output update_available true
before_source=$(upstream_source)
backup=$(mktemp -d)
build_log=$(mktemp)
cp "$release_file" "$flake_file" "$lock_file" "$backup/"
candidate_ready=false
cleanup() {
  if [[ "$candidate_ready" != true ]]; then
    cp "$backup"/release.nix "$backup"/flake.nix "$backup"/flake.lock "$repo_root/"
  fi
  rm -rf "$backup" "$build_log"
}
trap cleanup EXIT

log "Preparing stable candidate $current_version -> $upstream_version"
[[ $(grep -c 'github:NousResearch/hermes-agent/' "$flake_file") == 1 ]] || die "unexpected hermes-agent input layout"
perl -pi -e "s|github:NousResearch/hermes-agent/[^\"]+|github:NousResearch/hermes-agent/${release_tag}|" "$flake_file"
printf '{\n  version = "%s";\n  rev = "%s";\n}\n' "$upstream_version" "$tag_sha" >"$release_file"
nix flake update hermes-agent --accept-flake-config >"$build_log" 2>&1 || { tail -40 "$build_log" >&2; die "could not lock $release_tag"; }
locked_rev=$(jq -r '.nodes["hermes-agent"].locked.rev' "$lock_file")
[[ "$locked_rev" == "$tag_sha" ]] || die "$release_tag locked to $locked_rev, expected $tag_sha"

after_source=$(upstream_source)
build_status=$(
  run_validation "$build_log" nix flake check --keep-going --accept-flake-config
)

source_args=()
[[ -n "$before_source" ]] && source_args+=(--before-source "$before_source")
[[ -n "$after_source" ]] && source_args+=(--after-source "$after_source")
python3 "$repo_root/scripts/render-update-report.py" \
  --channel stable \
  --current-version "$current_version" --candidate-version "$upstream_version" \
  --current-rev "$current_rev" --candidate-rev "$tag_sha" \
  "${source_args[@]}" \
  --build-status "$build_status" --build-log "$build_log" \
  --upstream-url "https://github.com/NousResearch/hermes-agent/releases/tag/${release_tag}" \
  --output "$report"

publish_summary "$report"
set_output compatible "$([[ "$build_status" == passed ]] && echo true || echo false)"
candidate_ready=true
log "Candidate prepared; validation: $build_status. The workflow will open or update its PR."
