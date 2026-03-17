# Declarative Skills for nix-hermes-agent

Status: Draft
Owner: 0xrsydn / Ciphercat
Branch: `feat/skills`

## TL;DR

`nix-hermes-agent` already makes Hermes config, documents, auth seeding, and service wiring declarative.
The next maturity step is to make **skills** first-class declarative state too.

This document proposes a practical, upstream-aware design that:

1. preserves Hermes' filesystem-based skill model,
2. respects upstream bundled/optional/hub distinctions,
3. keeps Nix-managed state reproducible,
4. avoids fragile runtime-only snowflake setup,
5. leaves room for future hub/external skills without making the first version messy.

The recommended rollout is:

- **Phase 1:** declarative bundled + optional + local custom skills
- **Phase 2:** declarative enable/disable controls per platform
- **Phase 3:** optional support for declarative external/hub skills
- **Phase 4:** profile abstractions on top

---

## Problem

Today `nix-hermes-agent` can declaratively manage:

- package version
- service wiring
- `HERMES_HOME`
- generated config
- documents like `SOUL.md`, `AGENTS.md`, `USER.md`
- auth seed file
- env files
- MCP servers

But skills remain effectively under-managed.

That creates several problems:

### 1. Reproducibility gap

Useful Hermes deployments are shaped heavily by available skills.
Right now those are not modeled as deployable state in the Nix module.

### 2. Snowflake drift

A machine can gain skills interactively via Hermes CLI, but the resulting state is not cleanly captured in Nix.
Rebuilds and reprovisioning become less trustworthy.

### 3. Poor fleet ergonomics

If we want Hermes to live as:

- a gateway agent,
- a CLI/TUI agent over SSH,
- an ACP-connected IDE agent,
- a research/creative/coding sandbox on a dedicated VM,

then the skill substrate needs to be reproducible and composable.

### 4. Missing product maturity

A declarative agent deployment layer that cannot declaratively express skills is not finished.

---

## Goal

Make `nix-hermes-agent` mature enough that a user can declare Hermes skill state in Nix with the same confidence they already declare config and documents.

Success means a user can express:

- which built-in/bundled skills exist,
- which upstream optional skills are installed,
- which local custom skills are present,
- which skills are disabled globally or per platform,
- eventually, which external/hub skills are desired,

and rebuild a host into the same functional Hermes deployment.

---

## Non-goals

### Not a full rewrite of upstream skill management

We should not fork or replace Hermes' skill architecture.
We should layer on top of real upstream semantics.

### Not immediate perfect support for every hub workflow

Hub-managed skills involve remote registries, quarantine, audit, taps, lock files, and provenance.
We should not block the entire feature set on solving every edge case in v1.

### Not soul/prompt redesign

This effort is about capability substrate and deployment maturity, not voice tuning.

---

## Upstream architecture findings

This section captures the relevant upstream seams that matter for Nix integration.

## 1. Single runtime skill root

Hermes treats this as the runtime source of truth:

- `HERMES_HOME = Path(os.getenv("HERMES_HOME", Path.home() / ".hermes"))`
- `SKILLS_DIR = HERMES_HOME / "skills"`

Relevant upstream files:

- `tools/skills_tool.py`
- `tools/skills_hub.py`
- `tools/skills_sync.py`

Implication:

**Nix should target `${HERMES_HOME}/skills` as the canonical runtime location.**
Any declarative solution that ignores this will fight upstream.

## 2. Filesystem-based discovery

Skills are discovered by scanning `SKILLS_DIR` recursively for `SKILL.md`.

Relevant upstream behavior:

- `tools/skills_tool.py:_find_all_skills()`
- category derived from relative path under `SKILLS_DIR`
- category descriptions can come from `DESCRIPTION.md`

Implication:

**Declarative skills do not need a custom registry format.**
They mainly need correct directory materialization.

## 3. Bundled skills are synced via a manifest

Upstream has a sync layer for bundled skills:

- `tools/skills_sync.py`
- manifest file: `~/.hermes/skills/.bundled_manifest`

Behavior summary:

- bundled skills are synced into `~/.hermes/skills/`
- manifest tracks origin hashes
- user modifications/deletions are handled intentionally
- removed bundled skills are cleaned from manifest

Implication:

**Bundled skills are not just copied blindly.**
If we want to align with upstream behavior, we should respect that bundled skills have their own lifecycle semantics.

## 4. Optional skills are shipped in repo, but not bundled into runtime by default

Upstream has `optional-skills/` and exposes them through hub-style install/search flows.

Relevant upstream behavior:

- `tools/skills_hub.py: OptionalSkillsSource`
- source path: repo `optional-skills/`
- install identifiers look like `official/category/skill` or `official/skill`

Implication:

Optional skills are a clean fit for declarative install because they are effectively pinned to the package revision already.

## 5. Skill enable/disable is config-driven

Skill disabling lives in Hermes config, not the filesystem.

Relevant upstream behavior:

- `hermes_cli/skills_config.py`
- `tools/skills_tool.py:_get_disabled_skill_names()`
- config keys:

```yaml
skills:
  disabled: []
  platform_disabled: {}
```

Implication:

**Installation and enablement are separate concerns.**
The Nix module should model both.

## 6. Hub/external skills carry provenance state

Hub state lives under:

- `~/.hermes/skills/.hub/lock.json`
- `~/.hermes/skills/.hub/taps.json`
- plus quarantine/audit state

Relevant upstream behavior:

- `tools/skills_hub.py:HubLockFile`
- `tools/skills_hub.py:TapsManager`
- install flow records source/trust/provenance/install_path/hash

Implication:

External skill support has real statefulness and should be treated as a separate phase.

---

## Product principles

## 1. Reproducibility first

The primary value of `nix-hermes-agent` is that Hermes deployment stops being snowflake state.
Skills must follow the same principle.

## 2. Align with upstream instead of papering over it

Where upstream already has a lifecycle concept:

- bundled manifest,
- optional skill source,
- hub lock file,
- disabled config,

we should design with those semantics in mind.

## 3. Prefer pinned/local skill materialization over runtime network installs

For Nix-managed deployments, local/pinned skills are cleaner than runtime remote fetches.

## 4. Separate “present on disk” from “enabled for runtime”

This mirrors upstream and keeps the module more expressive.

## 5. Make the first version boring and reliable

Copy/sync into runtime state first.
Do not over-optimize for immutable symlink purity if it breaks upstream assumptions.

---

## Proposed module design

## Phase 1: Declarative local skill materialization

### New option group: `services.hermes-agent.skills`

Suggested top-level shape:

```nix
services.hermes-agent.skills = {
  bundled.enable = true;

  optional = [
    "research/foo"
    "creative/bar"
  ];

  custom = {
    my-playbook = {
      category = "research";
      source = ./skills/my-playbook;
    };
  };

  disabled = [ "foo" ];

  platformDisabled = {
    telegram = [ "shell-heavy-skill" ];
    cli = [ ];
  };
};
```

### Sub-feature A: bundled skills

#### Goal
Allow `nix-hermes-agent` to ensure upstream bundled skills are present declaratively.

#### Why
This makes package upgrades and fresh machines deterministic.

#### Design options

##### Option A — let upstream sync bundled skills at runtime
Pros:
- closest to upstream lifecycle
- manifest semantics stay upstream-owned

Cons:
- requires that sync path is guaranteed to run in the packaged flow
- harder to reason about from Nix module alone

##### Option B — module-managed bundled sync/materialization
Pros:
- explicit and controllable from module
- can be tested from Nix side

Cons:
- risks partially duplicating upstream logic unless done carefully

#### Recommendation
Use **module-managed materialization** initially, but preserve upstream-compatible structure and manifest awareness.
If we later find an upstream-supported sync entrypoint that is stable, we can switch implementation without changing user-facing options.

### Sub-feature B: optional skills

#### Goal
Install upstream `optional-skills/` declaratively by package revision.

#### Why
These are the cleanest next-step skills because they are already version-pinned by the packaged source tree.

#### Recommendation
Expose a list of relative skill paths from upstream optional-skills.
Example:

```nix
services.hermes-agent.skills.optional = [
  "research/deep-research"
  "creative/story-ideation"
];
```

The module activation step should materialize these into `${HERMES_HOME}/skills/...` preserving category layout.

### Sub-feature C: custom local skills

#### Goal
Allow users to declaratively ship their own skills.

#### Recommendation
Support both:

- `source = ./path/to/skill-dir`
- later maybe `text = '' ... SKILL.md ... ''` for convenience

Suggested shape:

```nix
services.hermes-agent.skills.custom = {
  repo-watch = {
    category = "research";
    source = ./skills/repo-watch;
  };
};
```

This should build a derivation containing normalized skill trees, then copy/sync them into runtime state.

---

## Phase 2: Declarative enable/disable controls

### Goal
Manage the upstream config shape declaratively.

Suggested mapping:

```nix
services.hermes-agent.skills.disabled = [ "foo" ];
services.hermes-agent.skills.platformDisabled.telegram = [ "bar" ];
```

Module implementation should merge this into generated Hermes config:

```nix
config.skills = {
  disabled = ...;
  platform_disabled = ...;
};
```

### Why separate from installation?
Because upstream separates them, and it enables useful patterns:

- skill present but disabled on messaging platforms
- skill enabled only in CLI/ACP contexts
- same deployment with different platform affordances

This matters a lot if Hermes is used across:

- gateway,
- SSH CLI/TUI,
- ACP/IDE connection.

---

## Phase 3: Declarative external / hub skills

This should be treated as a separate feature set, not bundled into v1.

### Problem
Hub skills are not just files.
They have upstream lifecycle semantics:

- provenance
- trust level
- lock entries
- taps
- audit log
- quarantine/security scanning

### Two viable models

#### Model A — runtime installation via Hermes CLI
Declare desired hub skills in Nix, then reconcile at activation/runtime using Hermes itself:

```nix
services.hermes-agent.skills.hub = [
  {
    identifier = "owner/repo/path/to/skill";
    source = "github";
  }
];
```

Pros:
- preserves upstream lock/audit/scan behavior

Cons:
- network-dependent
- less reproducible
- slower/more stateful

#### Model B — pin external skill sources in Nix and treat them as local skills
Use `fetchFromGitHub` or flake inputs, then place them under `custom`/local managed skills.

Pros:
- reproducible
- reviewable
- pinned by hash
- easier to reason about in infra repos

Cons:
- bypasses hub provenance model unless explicitly emulated

### Recommendation
For `nix-hermes-agent`, **prefer Model B philosophically**.
Support Model A later as an escape hatch for people who want native Hermes Hub behavior.

---

## Phase 4: Profiles

Once the substrate exists, we can define higher-level role profiles.
Examples:

- `researcher`
- `creative-lab`
- `ops-lite`
- `coding-explorer`

These profiles would be syntactic sugar over:

- installed skills
- disabled skills
- model/tool config
- maybe documents

This should come after raw primitives are solid.

---

## Proposed option schema

This is a proposed user-facing module API, not final code.

```nix
services.hermes-agent.skills = {
  enable = lib.mkEnableOption "declarative Hermes skills";

  bundled = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  optional = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "research/deep-research" ];
  };

  custom = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ ... }: {
      options = {
        category = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        source = lib.mkOption {
          type = lib.types.path;
        };
      };
    }));
    default = { };
  };

  disabled = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  platformDisabled = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
  };

  hub = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule ({ ... }: {
      options = {
        identifier = lib.mkOption { type = lib.types.str; };
        source = lib.mkOption {
          type = lib.types.enum [ "github" "official" "well-known" "skills-sh" ];
          default = "github";
        };
      };
    }));
    default = [ ];
  };
};
```

---

## Implementation plan

## Milestone 1 — groundwork and packaging introspection

### Deliverables
- confirm packaged source paths for bundled skills and optional-skills
- add tests or at least build-time assertions that those paths exist in the package output
- document path assumptions

### Notes
Current package already fetches upstream source with submodules and builds Hermes as a Python app.
We need a stable way to refer to upstream skills trees from the installed package or derivation source.

### Risks
- packaged output may not expose source trees exactly where activation expects them
- upstream package layout may shift across releases

### Mitigation
Add explicit path probes in checks/docs and keep implementation centralized.

---

## Milestone 2 — declarative bundled + optional + custom skill materialization

### Deliverables
- module options for bundled/optional/custom skills
- activation step that creates `${HERMES_HOME}/skills`
- copy/sync logic preserving category layout
- initial tests covering presence of selected skills in state dir

### Implementation guidance
Use a generated derivation to normalize all Nix-managed skill content into one tree, then reconcile that tree into runtime state.

Example conceptual pipeline:

1. build a Nix store tree containing:
   - selected bundled skills
   - selected optional skills
   - custom local skills
2. activation script syncs that tree into `${cfg.stateDir}/.hermes/skills`
3. preserve non-Nix-managed hub state unless explicitly managing it

### Important constraint
Do **not** clobber `.hub/` blindly.
Do **not** wipe user-managed runtime state unless explicitly requested.

---

## Milestone 3 — declarative disabled/platformDisabled wiring

### Deliverables
- module options
- merge into generated Hermes config
- tests that rendered config contains expected shape

### Why this milestone is low risk
This is a direct mapping to upstream config semantics and does not require custom lifecycle logic.

---

## Milestone 4 — docs and examples

### Deliverables
- README examples for:
  - basic bundled skill deployment
  - optional skills
  - custom local skills
  - platform-specific disabling
- migration guidance for users already managing skills interactively

---

## Milestone 5 — optional hub skill support

### Deliverables
- design decision: native runtime install vs pinned-local strategy
- if implemented, add explicit caveats about reproducibility and network dependency
- preserve upstream lock/audit semantics

### Recommendation
Do not block the core feature on this milestone.

---

## State reconciliation strategy

This is the most important implementation choice.

## Recommended approach: managed subtree reconciliation

Use a managed subset of `${HERMES_HOME}/skills` while leaving upstream-owned dynamic state alone.

### Desired behavior
Nix should manage:

- bundled skills selected by module policy
- optional skills selected by module policy
- custom local skills selected by module policy

Nix should avoid trampling:

- `.hub/`
- maybe `.bundled_manifest` unless we intentionally integrate with it
- runtime-installed non-managed skills unless user opts into strict mode

### Possible implementation pattern
Maintain a managed marker file or managed manifest under Hermes home, e.g.:

- `${HERMES_HOME}/skills/.nix-managed-manifest.json`

Track which installed paths belong to Nix-managed state.
On activation:

- create/update managed paths
- remove managed paths no longer desired
- leave unmanaged paths untouched

This avoids destructive full-directory replacement and plays better with upstream hub installs.

---

## Testing strategy

## 1. Evaluation tests
Ensure module options evaluate and merge correctly.

## 2. Render tests
Validate generated config contains expected skill disable keys.

## 3. Activation tests
On a NixOS test VM or shell-based checks:

- deploy with custom skill
- assert `SKILL.md` lands under expected path
- deploy with optional skill
- assert category structure preserved
- rebuild with skill removed
- assert only managed skill removed
- assert `.hub/` untouched

## 4. Regression tests
Check package path assumptions for upstream bundled and optional-skills trees.

---

## Open questions

## 1. Should bundled skills be managed by module or left to upstream sync?
Current recommendation: module-managed initially, but keep implementation swappable.

## 2. Should Nix-managed skills be copied or symlinked into runtime?
Current recommendation: **copy/sync first**.
This is more boring but more compatible with any upstream expectations around writable trees and file operations.

## 3. Should hub skills be in scope for the first PR series?
Current recommendation: **no**.
Document the plan, but ship local/offline-managed skills first.

## 4. Should we support inline `SKILL.md` text for custom skills?
Probably yes later, but path-based custom skills are enough for v1.

---

## Recommended PR breakdown

## PR 1 — groundwork
- package path assertions
- module option scaffolding
- docs stub

## PR 2 — declarative local skills
- bundled/optional/custom skill options
- managed reconciliation logic
- tests

## PR 3 — declarative disable controls
- `disabled`
- `platformDisabled`
- config wiring
- tests

## PR 4 — docs/examples
- README updates
- migration examples
- profile examples

## PR 5 — optional hub support (if still desired)
- separate decision doc
- explicit caveats

---

## Recommendation

The repo should focus on **declarative skills maturity now**, not soul tuning.

The best next step is to implement a boring, reliable, upstream-aware layer for:

- bundled skills,
- optional skills,
- custom local skills,
- disabled/platform-disabled config.

That will make `nix-hermes-agent` meaningfully more mature and unlock better Hermes roles across:

- gateway usage,
- SSH CLI/TUI usage,
- ACP/IDE connections,
- dedicated research/creative sandbox VMs.

---

## Appendix: Upstream files worth watching

For future maintainers, these upstream files are the primary integration seams:

- `tools/skills_tool.py`
  - `SKILLS_DIR`
  - `_find_all_skills()`
  - `_get_disabled_skill_names()`
  - category/path discovery

- `tools/skills_sync.py`
  - bundled skill sync behavior
  - `.bundled_manifest`

- `tools/skills_hub.py`
  - `OptionalSkillsSource`
  - `HubLockFile`
  - `TapsManager`
  - install/uninstall semantics

- `hermes_cli/skills_config.py`
  - user-facing config model for disabled/platform-disabled skills

- `hermes_cli/config.py`
  - `HERMES_HOME`
  - merged config semantics

These are the places likely to matter most when upstream changes skill behavior.
