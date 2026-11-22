#!/usr/bin/env python3
"""Render a small, deterministic compatibility report for an upstream update."""

from __future__ import annotations

import argparse
import hashlib
import re
import tomllib
from pathlib import Path


CONTRACT_PATHS = (
    "nix/packages.nix",
    "nix/hermes-agent.nix",
    "nix/python.nix",
    "nix/nixosModules.nix",
    "agent/codex_runtime.py",
    "agent/kanban_stop.py",
    "hermes_cli/config.py",
)


def metadata(source: Path | None) -> dict[str, object]:
    result: dict[str, object] = {
        "dependencies": set(),
        "dependency_specs": {},
        "optional_groups": set(),
        "scripts": {},
        "python": "unknown",
        "config_version": "unknown",
        "paths": {},
    }
    if source is None or not source.is_dir():
        return result

    pyproject = source / "pyproject.toml"
    if pyproject.is_file():
        try:
            with pyproject.open("rb") as handle:
                project = tomllib.load(handle).get("project", {})
            specs = {
                dependency_name(item): item for item in project.get("dependencies", [])
            }
            result["dependencies"] = set(specs)
            result["dependency_specs"] = specs
            result["optional_groups"] = set(project.get("optional-dependencies", {}))
            result["scripts"] = dict(project.get("scripts", {}))
            result["python"] = project.get("requires-python", "unknown")
        except (OSError, tomllib.TOMLDecodeError, TypeError, AttributeError):
            pass

    for config_path in (source / "hermes_cli/config.py", source / "hermes_constants.py"):
        if not config_path.is_file():
            continue
        contents = config_path.read_text(encoding="utf-8", errors="replace")
        matches = re.findall(
            r'(?:CURRENT_CONFIG_VERSION|["\']_config_version["\'])\s*(?::|=)\s*(\d+)',
            contents,
        )
        if matches:
            result["config_version"] = matches[-1]
            break

    result["paths"] = {
        path: hashlib.sha256((source / path).read_bytes()).hexdigest()
        for path in CONTRACT_PATHS
        if (source / path).is_file()
    }
    return result


def dependency_name(requirement: str) -> str:
    return re.split(r"[<>=!~;\[ @]", requirement, maxsplit=1)[0].strip().lower()


def changes(before: set[str], after: set[str]) -> str:
    added = sorted(after - before)
    removed = sorted(before - after)
    parts = []
    if added:
        parts.append("added: " + ", ".join(f"`{item}`" for item in added))
    if removed:
        parts.append("removed: " + ", ".join(f"`{item}`" for item in removed))
    return "; ".join(parts) if parts else "none"


def contract_changes(before: dict[str, str], after: dict[str, str]) -> str:
    changed = sorted(
        path for path in before.keys() | after.keys() if before.get(path) != after.get(path)
    )
    return ", ".join(f"`{path}`" for path in changed) if changed else "none"


def dependency_changes(before: dict[str, str], after: dict[str, str]) -> str:
    summary = changes(set(before), set(after))
    changed = sorted(name for name in before.keys() & after.keys() if before[name] != after[name])
    if changed:
        detail = ", ".join(
            f"`{name}` (`{before[name]}` → `{after[name]}`)" for name in changed
        )
        summary = (summary + "; " if summary != "none" else "") + "changed: " + detail
    return summary


def render(args: argparse.Namespace) -> str:
    before = metadata(args.before_source)
    after = metadata(args.after_source)
    status_icon = "✅" if args.build_status == "passed" else "❌"
    lines = [
        f"## Hermes Agent {args.channel} candidate",
        "",
        "This PR is a quarantined upstream candidate. Merge it only after required checks pass.",
        "",
        "| Contract | Current | Candidate |",
        "| --- | --- | --- |",
        f"| Version | `{args.current_version}` | `{args.candidate_version}` |",
        f"| Revision | `{args.current_rev}` | `{args.candidate_rev}` |",
        f"| Python | `{before['python']}` | `{after['python']}` |",
        f"| Config schema | `{before['config_version']}` | `{after['config_version']}` |",
        f"| Build validation | — | {status_icon} {args.build_status} |",
        "",
        "### Detected interface changes",
        "",
        f"- Direct dependencies: {dependency_changes(before['dependency_specs'], after['dependency_specs'])}",
        f"- Optional dependency groups: {changes(before['optional_groups'], after['optional_groups'])}",
        f"- CLI entry points: {changes(set(before['scripts']), set(after['scripts']))}",
        f"- Files the lean layer builds on: {contract_changes(before['paths'], after['paths'])}",
        "",
    ]
    if args.upstream_url:
        lines.extend((f"Upstream: {args.upstream_url}", ""))
    if args.build_log and args.build_log.is_file() and args.build_status != "passed":
        tail = args.build_log.read_text(encoding="utf-8", errors="replace").splitlines()[-80:]
        lines.extend(
            (
                "<details><summary>Validation failure (last 80 lines)</summary>",
                "",
                "```text",
                "\n".join(tail).replace("```", "'''"),
                "```",
                "</details>",
                "",
            )
        )
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--channel", required=True)
    parser.add_argument("--current-version", required=True)
    parser.add_argument("--candidate-version", required=True)
    parser.add_argument("--current-rev", required=True)
    parser.add_argument("--candidate-rev", required=True)
    parser.add_argument("--before-source", type=Path)
    parser.add_argument("--after-source", type=Path)
    parser.add_argument("--build-status", choices=("passed", "failed"), required=True)
    parser.add_argument("--build-log", type=Path)
    parser.add_argument("--upstream-url")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(args), encoding="utf-8")


if __name__ == "__main__":
    main()
