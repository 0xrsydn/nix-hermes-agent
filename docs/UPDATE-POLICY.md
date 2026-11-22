# Upstream update policy

Hermes Agent changes quickly: a patch release can carry thousands of commits.
An upstream release is a candidate until this layer's checks pass on it.
Automation never pushes an upstream pin directly to `main`.

## Where the pin lives

- `flake.nix` pins the `hermes-agent` input to a release tag.
- `release.nix` records that release's version and commit. Upstream's source
  has no version number, so the package stamps this one.
- The `release-pin` check fails when `flake.lock` and `release.nix` disagree.

## Stable candidates

`.github/workflows/update-pins.yml` runs `scripts/update-pins.sh` daily. When
upstream publishes a newer release, the script bumps the tag, `release.nix` and
the lock, runs `nix flake check`, and opens or updates the
`automation/hermes-agent-stable-candidate` PR. Do not put manual commits on that
branch; the next run may replace it.

The PR report lists changes in Python bounds, direct dependencies, optional
dependency groups and CLI entry points. It also lists which files this layer
builds on have changed upstream: the Nix packaging, the files the patches touch,
and the config schema. A failed build is included in the report and marks the
job red, but the candidate stays open for review.

The updater uses the built-in `GITHUB_TOKEN`. The repository setting "Allow
GitHub Actions to create and approve pull requests" must be on. PRs opened with
that token start no workflows, so the updater dispatches `ci.yml` on the
candidate branch itself.

## Nightly

`.github/workflows/nightly-ci.yml` builds the package checks daily against
upstream `main` with `--override-input`. Nothing is committed. A red run is an
early warning that the next release will need work on this layer, such as a
patch that no longer applies.

## Carried patches

Each file in `patches/` fixes an upstream bug. When a candidate fails because a
patch no longer applies, check whether upstream has fixed the bug. If it has,
delete the patch; otherwise rebase it.

- `codex-kanban-stop-guard.patch`: the Codex app-server runtime skips the
  conversation loop's kanban stop check, so a worker that ends its turn without
  `kanban_complete` or `kanban_block` is recorded as a protocol violation and
  retried until blocked. The patch runs the same stop nudge for Codex turns.
- `provider-plugin-snapshot-writable.patch`: since 0.23.3, Hermes loads a
  model-provider plugin from a private copy of it. `shutil.copytree` keeps the
  source's modes, so a plugin installed from the read-only Nix store yields a
  read-only copy, the copy cannot be renamed into place, and the provider never
  registers ("Unknown provider"). The patch makes the private copy
  owner-writable. The `provider-plugin-from-store` check reproduces the bug.

## Manual validation

```bash
nix flake check --keep-going

nix build --no-link --override-input hermes-agent github:NousResearch/hermes-agent \
  .#checks.x86_64-linux.cli .#checks.x86_64-linux.patches-live
```
