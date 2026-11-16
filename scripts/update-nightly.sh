#!/usr/bin/env bash
set -euo pipefail

# Generate a reviewable nightly candidate without pushing to main.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
nightly_file="$repo_root/nightly.nix"
report=${HERMES_UPDATE_REPORT:-/tmp/hermes-nightly-update.md}

# shellcheck source=scripts/update-common.sh
source "$repo_root/scripts/update-common.sh"

log() { printf '>> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null || die "gh is required"
command -v python3 >/dev/null || die "python3 is required"

head_sha=$(gh api /repos/NousResearch/hermes-agent/commits/main --jq '.sha')
[[ -n "$head_sha" ]] || die "failed to resolve upstream main"
current_rev=$(awk -F'"' '/pinRev = /{print $2; exit}' "$nightly_file")
current_version=$(awk -F'"' '/pinVersion = /{print $2; exit}' "$nightly_file")
[[ -n "$current_rev" && -n "$current_version" ]] || die "could not read current nightly pin"
if [[ "$current_rev" == "$head_sha" ]]; then
  log "Nightly already tracks $head_sha"
  set_output update_available false
  set_output compatible true
  exit 0
fi

# HEAD's pyproject.toml says 0.0.0, so name the nightly after the latest release.
latest_tag=$(gh api /repos/NousResearch/hermes-agent/releases/latest --jq '.tag_name // empty')
[[ -n "$latest_tag" ]] || die "latest release has no tag"
upstream_version=$(upstream_version "$latest_tag" "$head_sha") || die "could not determine the nightly base version"
python3 - "$upstream_version" <<'PY' || die "upstream pyproject contains an invalid version"
import re, sys
raise SystemExit(0 if re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", sys.argv[1]) else 1)
PY
nightly_version="${upstream_version}-unstable-$(date -u +%Y-%m-%d).${head_sha:0:8}"
set_output update_available true

before_source=$(realize_flake_source ".#hermes-agent-nightly")
backup=$(mktemp)
build_log=$(mktemp)
cp "$nightly_file" "$backup"
candidate_ready=false
cleanup() {
  [[ "$candidate_ready" == true ]] || cp "$backup" "$nightly_file"
  rm -f "$backup" "$build_log"
}
trap cleanup EXIT

log "Preparing nightly candidate ${current_rev:0:12} -> ${head_sha:0:12}"
[[ $(grep -c 'pinVersion = "' "$nightly_file") == 1 ]] || die "unexpected nightly version layout"
[[ $(grep -c 'pinRev = "' "$nightly_file") == 1 ]] || die "unexpected nightly revision layout"
[[ $(grep -c 'pinHash = "' "$nightly_file") == 1 ]] || die "unexpected nightly hash layout"
perl -0pi -e "s|pinVersion = \"[^\"]+\";|pinVersion = \"${nightly_version}\";|" "$nightly_file"
perl -0pi -e "s|pinRev = \"[^\"]+\";|pinRev = \"${head_sha}\";|" "$nightly_file"
perl -0pi -e 's|pinHash = "[^"]*";|pinHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";|' "$nightly_file"
grep -Fq "pinRev = \"${head_sha}\";" "$nightly_file" || die "failed to update nightly revision"

if nix build '.#hermes-agent-nightly.src' --no-link --accept-flake-config >"$build_log" 2>&1; then
  cp "$backup" "$nightly_file"
  die "the fake source hash unexpectedly succeeded"
fi
source_hash=$(extract_sri_hash "$build_log")
if [[ -z "$source_hash" ]]; then
  cp "$backup" "$nightly_file"
  tail -80 "$build_log" >&2
  die "could not extract the candidate source hash"
fi
perl -0pi -e "s|pinHash = \"[^\"]*\";|pinHash = \"${source_hash}\";|" "$nightly_file"

after_source=$(realize_flake_source ".#hermes-agent-nightly")
system=$(current_nix_system)
build_status=$(
  run_validation "$build_log" nix build ".#legacyPackages.${system}.nightlyChecks.all" --accept-flake-config
)

source_args=()
[[ -n "$before_source" ]] && source_args+=(--before-source "$before_source")
[[ -n "$after_source" ]] && source_args+=(--after-source "$after_source")
python3 "$repo_root/scripts/render-update-report.py" \
  --channel nightly \
  --current-version "$current_version" --candidate-version "$nightly_version" \
  --current-rev "$current_rev" --candidate-rev "$head_sha" \
  "${source_args[@]}" \
  --build-status "$build_status" --build-log "$build_log" \
  --upstream-url "https://github.com/NousResearch/hermes-agent/commit/${head_sha}" \
  --output "$report"

publish_summary "$report"
set_output compatible "$([[ "$build_status" == passed ]] && echo true || echo false)"
candidate_ready=true
log "Candidate prepared; validation: $build_status. The workflow will open or update its PR."
