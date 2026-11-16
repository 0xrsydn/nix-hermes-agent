#!/usr/bin/env bash
set -euo pipefail

# Generate a reviewable stable candidate. The workflow owns commits and PRs;
# this script intentionally never mutates main or any remote branch.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_file="$repo_root/package.nix"
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
current_version=$(awk -F'"' '/pinVersion \? "/{print $2; exit}' "$package_file")
current_rev=$(awk -F'"' '/pinRev \? "/{print $2; exit}' "$package_file")
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
before_source=$(realize_flake_source ".#hermes-agent")
backup=$(mktemp)
build_log=$(mktemp)
cp "$package_file" "$backup"
candidate_ready=false
cleanup() {
  [[ "$candidate_ready" == true ]] || cp "$backup" "$package_file"
  rm -f "$backup" "$build_log"
}
trap cleanup EXIT

log "Preparing stable candidate $current_version -> $upstream_version"
[[ $(grep -c 'pinVersion ? "' "$package_file") == 1 ]] || die "unexpected pinVersion layout"
[[ $(grep -c 'pinRev ? "' "$package_file") == 1 ]] || die "unexpected pinRev layout"
[[ $(grep -c 'pinHash ? "' "$package_file") == 1 ]] || die "unexpected pinHash layout"
perl -0pi -e "s|pinVersion \\? \"[^\"]+\"|pinVersion ? \"${upstream_version}\"|" "$package_file"
perl -0pi -e "s|pinRev \\? \"[^\"]+\"|pinRev ? \"${tag_sha}\"|" "$package_file"
perl -0pi -e 's|pinHash \? "[^"]*"|pinHash ? "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' "$package_file"
grep -Fq "pinRev ? \"${tag_sha}\"" "$package_file" || die "failed to update stable revision"

if nix build '.#hermes-agent.src' --no-link --accept-flake-config >"$build_log" 2>&1; then
  cp "$backup" "$package_file"
  die "the fake source hash unexpectedly succeeded"
fi
source_hash=$(extract_sri_hash "$build_log")
if [[ -z "$source_hash" ]]; then
  cp "$backup" "$package_file"
  tail -80 "$build_log" >&2
  die "could not extract the candidate source hash"
fi
perl -0pi -e "s|pinHash \\? \"[^\"]*\"|pinHash ? \"${source_hash}\"|" "$package_file"

after_source=$(realize_flake_source ".#hermes-agent")
build_status=$(
  run_validation "$build_log" nix flake check --keep-going --no-write-lock-file --accept-flake-config
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
