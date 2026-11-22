#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/update-common.sh
source "$repo_root/scripts/update-common.sh"

log=$(mktemp)
trap 'rm -f "$log"' EXIT

status=$(run_validation "$log" bash -c 'echo dependency-broke; exit 42')
[[ "$status" == "failed" ]]
grep -q dependency-broke "$log"

status=$(run_validation "$log" bash -c 'echo all-good')
[[ "$status" == "passed" ]]
grep -q all-good "$log"
