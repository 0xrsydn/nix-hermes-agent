import argparse
import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "render-update-report.py"
SPEC = importlib.util.spec_from_file_location("render_update_report", SCRIPT)
REPORT = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(REPORT)


class RenderUpdateReportTest(unittest.TestCase):
    def write_source(self, root: Path, dependencies: list[str], config_version: int) -> None:
        (root / "hermes_cli").mkdir(parents=True)
        deps = ", ".join(f'"{item}"' for item in dependencies)
        (root / "pyproject.toml").write_text(
            "[project]\n"
            'requires-python = ">=3.11"\n'
            f"dependencies = [{deps}]\n"
            "[project.scripts]\n"
            'hermes = "hermes_cli.main:main"\n',
            encoding="utf-8",
        )
        (root / "hermes_cli" / "config.py").write_text(
            f'CURRENT_CONFIG_VERSION = {config_version}\n', encoding="utf-8"
        )

    def test_reports_dependency_and_schema_changes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            before, after = root / "before", root / "after"
            self.write_source(before, ["openai>=1", "pydantic"], 3)
            self.write_source(after, ["openai>=2", "pillow", "cryptography"], 4)
            args = argparse.Namespace(
                channel="stable",
                current_version="0.16.0",
                candidate_version="0.18.2",
                current_rev="old",
                candidate_rev="new",
                before_source=before,
                after_source=after,
                build_status="failed",
                build_log=None,
                upstream_url="https://example.invalid/release",
            )

            rendered = REPORT.render(args)

            self.assertIn("added: `cryptography`, `pillow`; removed: `pydantic`", rendered)
            self.assertIn("changed: `openai` (`openai>=1` → `openai>=2`)", rendered)
            self.assertIn("| Config schema | `3` | `4` |", rendered)
            self.assertIn("❌ failed", rendered)
            self.assertIn("Files the lean layer builds on: `hermes_cli/config.py`", rendered)

    def test_reads_config_schema_from_config_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            (source / "hermes_cli").mkdir()
            (source / "hermes_cli" / "config_defaults.py").write_text(
                'DEFAULT_CONFIG = {\n    "_config_version": 54,  # schema\n}\n', encoding="utf-8"
            )
            self.assertEqual(REPORT.metadata(source)["config_version"], "54")

    def test_missing_sources_are_reported_without_crashing(self) -> None:
        args = argparse.Namespace(
            channel="nightly",
            current_version="old",
            candidate_version="new",
            current_rev="old-rev",
            candidate_rev="new-rev",
            before_source=None,
            after_source=None,
            build_status="passed",
            build_log=None,
            upstream_url=None,
        )
        rendered = REPORT.render(args)
        self.assertIn("| Python | `unknown` | `unknown` |", rendered)
        self.assertIn("✅ passed", rendered)


if __name__ == "__main__":
    unittest.main()
