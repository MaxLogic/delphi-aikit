import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SKILL_DIR = Path(__file__).resolve().parents[1]


def load_postprocess():
    spec = importlib.util.spec_from_file_location(
        "dak_static_analysis_ai_reporting", SKILL_DIR / "postprocess.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def write_jsonl(path: Path, items: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(item) + "\n" for item in items), encoding="utf-8"
    )


def write_summary(path: Path, project: Path) -> None:
    path.write_text(
        "# Static analysis\n\n"
        "- Timestamp: 2026-07-16T10:00:00Z\n"
        f"- Project: `{project}`\n\n"
        "## FixInsight\n\n"
        "- Findings (by code): 2\n"
        "  - W101: 1\n"
        "  - C102: 1\n\n"
        "## Pascal Analyzer\n\n"
        "- Version: 9.21.3\n"
        "- Compiler target: Delphi 13 (Win64)\n"
        "- Totals: warnings=1, strong_warnings=1, optimizations=1, total=3\n",
        encoding="utf-8",
    )


def finding_streams(out_root: Path) -> tuple[Path, Path]:
    fi_path = out_root / "fixinsight" / "fi-findings.jsonl"
    pal_path = out_root / "pascal-analyzer" / "pal-findings.jsonl"
    write_jsonl(
        fi_path,
        [
            {
                "tool": "FixInsight",
                "code": "W101",
                "kind": "W",
                "path": "src/One.pas",
                "line": 10,
                "col": 2,
                "message": "warning",
            },
            {
                "tool": "FixInsight",
                "code": "C102",
                "kind": "C",
                "path": None,
                "line": 1,
                "col": 1,
                "message": "maintainability",
            },
        ],
    )
    write_jsonl(
        pal_path,
        [
            {
                "severity": "warning",
                "section": "Warnings",
                "module": "One",
                "path": "src/One.pas",
                "line": 20,
                "message": "warning",
            },
            {
                "severity": "strong-warning",
                "section": "Strong warnings",
                "module": "Two",
                "path": "src/Two.pas",
                "line": 30,
                "message": "strong warning",
            },
            {
                "severity": "optimization",
                "section": "Optimizations",
                "module": "Three",
                "path": None,
                "line": 40,
                "message": "optimization",
            },
        ],
    )
    return fi_path, pal_path


def write_schema2_seed(out_root: Path, project: Path) -> None:
    (out_root / "summary.json").write_text(
        json.dumps(
            {
                "schema_version": 2,
                "status": {
                    "infrastructure": "complete",
                    "policy": "not_evaluated",
                },
                "subject": {"kind": "project", "path": str(project)},
                "compiler": {
                    "platform": "Win64",
                    "config": "Debug",
                    "delphi": "23.0",
                    "search_path_sha256": "search-path-seed",
                },
                "analyzers": {
                    "fixinsight": {
                        "requested": True,
                        "status": "complete",
                        "executable": "FixInsightCL.exe",
                        "count_quality": "complete",
                    },
                    "pascal_analyzer": {
                        "requested": True,
                        "status": "complete",
                        "executable": "palcmd.exe",
                        "version": "9.21.3",
                        "count_quality": "complete",
                    },
                },
                "inputs": {
                    "project_sha256": "project-seed",
                    "main_source_sha256": "main-source-seed",
                    "config_manifests": [
                        {"name": "dak.ini", "sha256": "settings-seed"}
                    ],
                },
                "artifacts": {"summary_markdown": "summary.md"},
                "policy": {
                    "resolver": "Dak.Settings",
                    "status": "not_evaluated",
                    "values": {
                        "gate_ownership": ["project", "repository"],
                        "project_roots": [],
                        "third_party_roots": [],
                    },
                    "sources": [],
                    "sha256": "b" * 64,
                },
                "errors": [],
            }
        ),
        encoding="utf-8",
    )


class AiSummaryTests(unittest.TestCase):
    def setUp(self):
        self.postprocess = load_postprocess()

    def test_summary_json_and_sarif_match_normalized_findings(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            project = out_root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            write_summary(out_root / "summary.md", project)
            finding_streams(out_root)
            write_schema2_seed(out_root, project)
            fake_fixinsight = out_root / "FixInsightCL.cmd"
            fake_fixinsight.write_text(
                "@echo FixInsightCL Pro version 2023.12\r\n", encoding="ascii"
            )
            (out_root / "run.log").write_text(
                f'CMD: "{fake_fixinsight}" --project=Sample.dpr\n',
                encoding="utf-8",
            )

            result = self.postprocess.run_postprocess(out_root, title="Sample")

            self.assertTrue(result["gate_pass"])
            self.assertTrue(result["baseline_created"])
            self.assertEqual(
                str(out_root / "summary.json"), result["summary_json"]
            )
            summary = json.loads((out_root / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(3, summary["schema_version"])
            self.assertEqual("complete", summary["status"]["infrastructure"])
            self.assertEqual("complete", summary["status"]["postprocessor"])
            self.assertEqual("complete", summary["status"]["finalization"])
            self.assertEqual("not_evaluated", summary["status"]["policy"])
            self.assertEqual(
                "search-path-seed", summary["compiler"]["search_path_sha256"]
            )
            self.assertEqual("complete", summary["analyzers"]["fixinsight"]["count_quality"])
            self.assertEqual(
                "2023.12", summary["analyzers"]["fixinsight"]["version"]
            )
            self.assertEqual(
                "complete",
                summary["analyzers"]["pascal_analyzer"]["count_quality"],
            )
            self.assertEqual("project-seed", summary["inputs"]["project_sha256"])
            self.assertNotIn("status", summary["policy"])
            self.assertEqual(5, summary["counts"]["raw"]["total"])
            self.assertEqual(0, summary["counts"]["actionable"]["total"])
            self.assertEqual(5, summary["counts"]["unknown"]["total"])
            self.assertEqual(
                {
                    "project": 0,
                    "repository": 0,
                    "third_party": 0,
                    "unknown": 5,
                },
                summary["counts"]["raw"]["ownership"],
            )
            self.assertEqual([], summary["errors"])
            self.assertEqual("summary.md", summary["artifacts"]["summary_markdown"])
            self.assertEqual("static-analysis.sarif", summary["artifacts"]["sarif"])
            self.assertEqual(
                "static-analysis.full.sarif", summary["artifacts"]["full_sarif"]
            )

            sarif = json.loads(
                (out_root / "static-analysis.sarif").read_text(encoding="utf-8")
            )
            self.assertEqual(0, sum(len(run["results"]) for run in sarif["runs"]))
            full_sarif = json.loads(
                (out_root / "static-analysis.full.sarif").read_text(encoding="utf-8")
            )
            self.assertEqual(
                5, sum(len(run["results"]) for run in full_sarif["runs"])
            )
            delta = json.loads((out_root / "delta.json").read_text(encoding="utf-8"))
            self.assertEqual(0, delta["pascal_analyzer"]["optimizations_after"])
            self.assertEqual(0, delta["pascal_analyzer"]["total_after"])
            trend = (out_root / "trend.md").read_text(encoding="utf-8")
            self.assertIn("PAL optimizations", trend)
            self.assertIn("PAL total", trend)
            triage = (out_root / "triage.md").read_text(encoding="utf-8")
            self.assertIn("FixInsight findings: 0", triage)
            self.assertIn("Pascal Analyzer findings: 0", triage)

            existing_baseline_result = self.postprocess.run_postprocess(
                out_root, title="Sample"
            )

            self.assertTrue(existing_baseline_result["gate_pass"])
            self.assertFalse(existing_baseline_result["baseline_updated"])
            self.assertEqual(
                str(out_root / "summary.json"),
                existing_baseline_result["summary_json"],
            )
            existing_baseline_summary = json.loads(
                (out_root / "summary.json").read_text(encoding="utf-8")
            )
            self.assertEqual(3, existing_baseline_summary["schema_version"])
            self.assertEqual(
                "complete",
                existing_baseline_summary["status"]["infrastructure"],
            )
            self.assertEqual(
                "complete",
                existing_baseline_summary["status"]["postprocessor"],
            )
            self.assertEqual(
                "complete",
                existing_baseline_summary["status"]["finalization"],
            )
            self.assertEqual(
                5, existing_baseline_summary["counts"]["raw"]["total"]
            )
            self.assertEqual(
                0, existing_baseline_summary["counts"]["actionable"]["total"]
            )
            self.assertIn("sarif", existing_baseline_summary["artifacts"])

    def test_summary_count_mismatch_is_a_required_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            project = out_root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            write_summary(out_root / "summary.md", project)
            _, pal_path = finding_streams(out_root)
            records = list(self.postprocess._iter_jsonl(pal_path))
            write_jsonl(pal_path, records[:-1])

            with self.assertRaisesRegex(ValueError, "Pascal Analyzer count mismatch"):
                self.postprocess.run_postprocess(out_root, title="Sample")

    def test_nonactionable_raw_findings_still_require_summary_totals(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            fi_path = out_root / "fixinsight" / "fi-findings.jsonl"
            pal_path = out_root / "pascal-analyzer" / "pal-findings.jsonl"
            write_jsonl(
                fi_path,
                [
                    {
                        "kind": "W",
                        "ownership": "third_party",
                        "report_projection": "external",
                    }
                ],
            )
            write_jsonl(pal_path, [])
            with self.assertRaisesRegex(
                ValueError, "FixInsight count mismatch: summary total is missing"
            ):
                self.postprocess._actionable_counts({}, fi_path, pal_path)

            write_jsonl(fi_path, [])
            write_jsonl(
                pal_path,
                [
                    {
                        "severity": "warning",
                        "ownership": "third_party",
                        "report_projection": "external",
                    }
                ],
            )
            with self.assertRaisesRegex(
                ValueError, "Pascal Analyzer count mismatch: summary totals are missing"
            ):
                self.postprocess._actionable_counts({}, fi_path, pal_path)

    def test_unit_summary_subject_and_pal_version_are_parsed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            summary_path = Path(temp_dir) / "summary.md"
            summary_path.write_text(
                "# Pascal Analyzer unit summary: Sample\n\n"
                "- Timestamp: 2026-07-16T10:00:00Z\n"
                "- Unit: `C:\\repo\\Sample.pas`\n"
                "- PAL version: 9.21.3\n"
                "- Compiler target: Delphi 13 (Win64)\n"
                "- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0\n",
                encoding="utf-8",
            )

            summary = self.postprocess.parse_dak_summary_md(summary_path)

            self.assertEqual("C:\\repo\\Sample.pas", summary["unit"])
            self.assertEqual("9.21.3", summary["pal_version"])
            self.assertEqual(0, summary["pal_totals"]["total"])

    def test_skipped_unit_summary_is_recognized_as_explicit_status(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            summary_path = Path(temp_dir) / "summary.md"
            summary_path.write_text(
                "# Pascal Analyzer unit summary: Sample\n\n"
                "- Timestamp: 2026-07-16T10:00:00Z\n"
                "- Unit: `C:\\repo\\Sample.pas`\n"
                "- Skipped.\n",
                encoding="utf-8",
            )

            summary = self.postprocess.parse_dak_summary_md(summary_path)
            self.postprocess._validate_success_summary(summary)

            self.assertEqual(["pascal_analyzer"], summary["analyzers"])

    def test_skipped_unit_is_not_reclassified_as_requested_clean_analysis(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            unit = out_root / "Sample.pas"
            unit.write_text("unit Sample;\n", encoding="ascii")
            (out_root / "summary.md").write_text(
                "# Pascal Analyzer unit summary: Sample\n\n"
                "- Timestamp: 2026-07-16T10:00:00Z\n"
                f"- Unit: `{unit}`\n"
                "- Skipped.\n",
                encoding="utf-8",
            )

            self.postprocess.run_postprocess(out_root, title="Sample")

            status = json.loads(
                (out_root / "summary.json").read_text(encoding="utf-8")
            )
            analyzer = status["analyzers"]["pascal_analyzer"]
            self.assertFalse(analyzer["requested"])
            self.assertEqual("not_requested", analyzer["status"])

    def test_enabled_gate_has_one_canonical_policy_outcome(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            project = out_root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            write_summary(out_root / "summary.md", project)
            finding_streams(out_root)
            write_schema2_seed(out_root, project)

            with patch.dict(os.environ, {"DAK_GATE": "1"}, clear=False):
                self.postprocess.run_postprocess(out_root, title="Sample")

            status = json.loads(
                (out_root / "summary.json").read_text(encoding="utf-8")
            )
            self.assertEqual("fail", status["status"]["policy"])
            self.assertNotIn("status", status["policy"])
            self.assertFalse((out_root / "baseline.json").exists())

    def test_missing_optional_snippet_source_does_not_fail(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            project = out_root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            write_summary(out_root / "summary.md", project)
            finding_streams(out_root)
            old_value = os.environ.get("DAK_TRIAGE_SNIPPETS")
            os.environ["DAK_TRIAGE_SNIPPETS"] = "1"
            try:
                result = self.postprocess.run_postprocess(out_root, title="Sample")
            finally:
                if old_value is None:
                    os.environ.pop("DAK_TRIAGE_SNIPPETS", None)
                else:
                    os.environ["DAK_TRIAGE_SNIPPETS"] = old_value

            self.assertTrue(result["gate_pass"])

    def test_disabled_analyzer_counts_are_zero_not_unknown(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            project = out_root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            (out_root / "summary.md").write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-07-16T10:00:00Z\n"
                f"- Project: `{project}`\n\n"
                "## FixInsight\n\n"
                "- Findings (by code): (TXT not generated)\n\n"
                "## Pascal Analyzer\n\n"
                "- Version: 9.21.3\n"
                "- Compiler target: Delphi 13 (Win64)\n"
                "- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0\n",
                encoding="utf-8",
            )

            self.postprocess.run_postprocess(out_root, title="Sample")

            delta = json.loads((out_root / "delta.json").read_text(encoding="utf-8"))
            self.assertEqual(0, delta["fixinsight"]["total_after"])
            trend = (out_root / "trend.md").read_text(encoding="utf-8")
            self.assertIn("| 2026-07-16T10:00:00Z | 0 |", trend)

    def test_malformed_present_summary_fails_before_state_mutation(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            analyzer_sections = {
                "both-empty": "## FixInsight\n\n## Pascal Analyzer\n",
                "pal-empty": (
                    "## FixInsight\n\n- Findings (by code): 0\n\n"
                    "## Pascal Analyzer\n"
                ),
                "fixinsight-empty": (
                    "## FixInsight\n\n## Pascal Analyzer\n\n- Skipped.\n"
                ),
            }
            for name, sections in analyzer_sections.items():
                with self.subTest(case=name):
                    out_root = root / name
                    out_root.mkdir()
                    (out_root / "summary.md").write_text(
                        "# Static analysis with truncated analyzer sections\n\n"
                        "- Timestamp: 2026-07-16T10:00:00Z\n"
                        "- Project: `C:\\repo\\Sample.dproj`\n\n"
                        + sections,
                        encoding="utf-8",
                    )

                    with self.assertRaisesRegex(ValueError, "Invalid analysis summary"):
                        self.postprocess.run_postprocess(out_root, title="Sample")

                    self.assertFalse((out_root / "baseline.json").exists())
                    self.assertFalse((out_root / "history.jsonl").exists())

    def test_sarif_validation_fails_before_baseline_and_history_mutation(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            project = out_root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            (out_root / "summary.md").write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-07-16T10:00:00Z\n"
                f"- Project: `{project}`\n\n"
                "## FixInsight\n\n"
                "- Findings (by code): 1\n\n"
                "## Pascal Analyzer\n\n"
                "- Version: 9.21.3\n"
                "- Compiler target: Delphi 13 (Win64)\n"
                "- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0\n",
                encoding="utf-8",
            )
            write_jsonl(
                out_root / "fixinsight" / "fi-findings.jsonl",
                [{"code": "", "kind": "W", "path": "src/One.pas", "message": "invalid"}],
            )

            with self.assertRaisesRegex(ValueError, "SARIF count mismatch"):
                self.postprocess.run_postprocess(out_root, title="Sample")

            self.assertFalse((out_root / "baseline.json").exists())
            self.assertFalse((out_root / "history.jsonl").exists())

    def test_run_context_captures_fixinsight_version(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            fake = out_root / "FixInsightCL.cmd"
            fake.write_text(
                "@echo FixInsightCL Pro version 2023.12\r\n", encoding="ascii"
            )
            (out_root / "run.log").write_text(
                f'CMD: "{fake}" --project=Sample.dpr\n', encoding="utf-8"
            )

            context = self.postprocess._build_run_context(
                out_root,
                {},
                allow_env=False,
                expected_summary_timestamp=None,
            )

            self.assertEqual("2023.12", context["tools"]["fixinsight_version"])

    def test_schema2_provenance_tracks_dirty_sources_and_recursive_submodules(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            workspace = Path(temp_dir)
            library = workspace / "library"
            repo = workspace / "repo"
            library.mkdir()
            repo.mkdir()
            subprocess.run(["git", "init", "-q"], cwd=library, check=True)
            (library / "LibraryUnit.pas").write_text(
                "unit LibraryUnit;\n", encoding="ascii"
            )
            subprocess.run(["git", "add", "."], cwd=library, check=True)
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=DAK Test",
                    "-c",
                    "user.email=dak@example.invalid",
                    "commit",
                    "-qm",
                    "library fixture",
                ],
                cwd=library,
                check=True,
            )

            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            project = repo / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            (repo / "Sample.dpr").write_text(
                "program Sample;\nbegin\nend.\n", encoding="ascii"
            )
            source = repo / "SampleUnit.pas"
            source.write_text("unit SampleUnit;\n", encoding="ascii")
            (repo / ".gitignore").write_text(".dak/\n", encoding="ascii")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=DAK Test",
                    "-c",
                    "user.email=dak@example.invalid",
                    "commit",
                    "-qm",
                    "project fixture",
                ],
                cwd=repo,
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    "-c",
                    "protocol.file.allow=always",
                    "submodule",
                    "add",
                    "-q",
                    str(library),
                    "vendor/library",
                ],
                cwd=repo,
                check=True,
            )
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=DAK Test",
                    "-c",
                    "user.email=dak@example.invalid",
                    "commit",
                    "-qm",
                    "add submodule",
                ],
                cwd=repo,
                check=True,
            )
            source.write_text("unit SampleUnit;\n// dirty\n", encoding="ascii")
            (repo / "NewUnit.pas").write_text("unit NewUnit;\n", encoding="ascii")

            out_root = repo / ".dak" / "Sample"
            out_root.mkdir(parents=True)
            write_summary(out_root / "summary.md", project)
            finding_streams(out_root)
            write_schema2_seed(out_root, project)

            self.postprocess.run_postprocess(out_root, title="Sample")

            summary = json.loads(
                (out_root / "summary.json").read_text(encoding="utf-8")
            )
            target = summary["provenance"]["target"]
            self.assertEqual(40, len(target["head"]))
            self.assertTrue(target["dirty"])
            self.assertEqual(
                "git-delphi-inputs-with-recursive-submodules",
                target["source_inputs"]["scope"],
            )
            self.assertGreaterEqual(target["source_inputs"]["file_count"], 4)
            self.assertEqual(64, len(target["source_inputs"]["sha256"]))
            self.assertEqual("vendor/library", target["submodules"][0]["path"])
            self.assertEqual(40, len(target["submodules"][0]["revision"]))

    def test_git_command_failure_is_not_reported_as_clean_provenance(self):
        failed = SimpleNamespace(
            returncode=128,
            stdout="",
            stderr="fatal: repository unavailable",
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(self.postprocess.subprocess, "run", return_value=failed):
                with self.assertRaisesRegex(RuntimeError, "repository unavailable"):
                    self.postprocess._git_identity(Path(temp_dir))


class ChangedFileTriageTests(unittest.TestCase):
    def setUp(self):
        self.postprocess = load_postprocess()

    def test_pal_uses_exact_path_before_unique_module_fallback(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = Path(temp_dir)
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            for rel in ("src/a/Shared.pas", "src/b/Shared.pas", "src/Unique.pas"):
                path = repo / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f"unit {path.stem};\n", encoding="ascii")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=DAK Test",
                    "-c",
                    "user.email=dak@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ],
                cwd=repo,
                check=True,
            )
            (repo / "src/a/Shared.pas").write_text("unit Shared;\n// changed\n", encoding="ascii")
            (repo / "src/Unique.pas").write_text("unit Unique;\n// changed\n", encoding="ascii")

            out_root = repo / ".dak" / "Sample"
            pal_path = out_root / "pascal-analyzer" / "pal-findings.jsonl"
            write_jsonl(
                pal_path,
                [
                    {"module": "Shared", "path": "src/a/Shared.pas", "section": "W", "line": 1, "message": "exact"},
                    {"module": "Shared", "path": "src/b/Shared.pas", "section": "W", "line": 2, "message": "wrong-path"},
                    {"module": "Shared", "path": None, "section": "W", "line": 3, "message": "ambiguous"},
                    {"module": "Unique", "path": None, "section": "W", "line": 4, "message": "unique-fallback"},
                ],
            )

            triage_path = self.postprocess._write_triage_changed(
                out_root,
                title="Sample",
                summary={},
                fi_jsonl_path=out_root / "fixinsight" / "fi-findings.jsonl",
                pal_jsonl_path=pal_path,
            )

            triage = triage_path.read_text(encoding="utf-8")
            self.assertIn("exact", triage)
            self.assertIn("unique-fallback", triage)
            self.assertNotIn("wrong-path", triage)
            self.assertNotIn("ambiguous", triage)

    def test_git_changed_files_keep_rename_target_and_full_untracked_path(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = Path(temp_dir)
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            old_path = repo / "src" / "Old.pas"
            old_path.parent.mkdir(parents=True)
            old_path.write_text("unit Old;\n", encoding="ascii")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=DAK Test",
                    "-c",
                    "user.email=dak@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ],
                cwd=repo,
                check=True,
            )
            new_path = repo / "src" / "Renamed.pas"
            old_path.rename(new_path)
            subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
            untracked = repo / "src" / "new" / "Added.pas"
            untracked.parent.mkdir(parents=True)
            untracked.write_text("unit Added;\n", encoding="ascii")

            changed, error = self.postprocess._git_changed_files(repo)

            self.assertIsNone(error)
            self.assertIn("src/Renamed.pas", changed)
            self.assertIn("src/new/Added.pas", changed)
            self.assertNotIn("src/Old.pas", changed)
            self.assertNotIn("src/", changed)


class RequiredPostprocessExitTests(unittest.TestCase):
    def test_project_wrapper_returns_nonzero_for_malformed_normalized_jsonl(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            project = root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            out_root = root / "out"
            fake_dak = root / "fake-dak.cmd"
            fake_dak.write_text(
                "@echo off\r\n"
                "set \"OUT=\"\r\n"
                ":args\r\n"
                "if \"%~1\"==\"\" goto run\r\n"
                "if /I \"%~1\"==\"--out\" set \"OUT=%~2\"\r\n"
                "shift\r\n"
                "goto args\r\n"
                ":run\r\n"
                "mkdir \"%OUT%\\pascal-analyzer\" 2>nul\r\n"
                "(echo # Static analysis&echo.&echo - Timestamp: 2026-07-16T10:00:00Z&echo - Project: `%CD%\\Sample.dproj`&echo.&echo ## FixInsight&echo.&echo - Findings ^(by code^): 0&echo.&echo ## Pascal Analyzer&echo.&echo - Version: 9.21.3&echo - Compiler target: Delphi 13 ^(Win64^)&echo - Totals: warnings=1, strong_warnings=0, optimizations=0, total=1)>\"%OUT%\\summary.md\"\r\n"
                "echo {\"schema_version\":2,\"status\":{\"infrastructure\":\"complete\",\"policy\":\"not_evaluated\"},\"subject\":{\"kind\":\"project\",\"path\":\"%CD:\\=/%/Sample.dproj\",\"project_file\":\"%CD:\\=/%/Sample.dproj\"},\"compiler\":{\"delphi\":\"23.0\",\"platform\":\"Win64\",\"config\":\"Debug\",\"search_path_sha256\":\"fixture\"},\"analyzers\":{\"fixinsight\":{\"requested\":false,\"status\":\"not_requested\",\"count_quality\":\"complete\",\"runs\":[]},\"pascal_analyzer\":{\"requested\":true,\"status\":\"complete\",\"version\":\"9.21.3\",\"count_quality\":\"complete\",\"runs\":[]}},\"counts\":{\"fixinsight\":{\"quality\":\"complete\",\"total\":0},\"pascal_analyzer\":{\"quality\":\"complete\",\"warnings\":1,\"strong_warnings\":0,\"optimizations\":0,\"total\":1},\"total\":1},\"inputs\":{},\"policy\":{\"resolver\":\"Dak.Settings\"},\"errors\":[],\"artifacts\":{\"summary_markdown\":\"summary.md\"}}>\"%OUT%\\summary.json\"\r\n"
                "echo {broken>\"%OUT%\\pascal-analyzer\\pal-findings.jsonl\"\r\n"
                "exit /b 0\r\n",
                encoding="ascii",
            )
            env = os.environ.copy()
            env["DAK_EXE"] = str(fake_dak)
            env["DAK_OUT"] = str(out_root)
            result = subprocess.run(
                [sys.executable, str(SKILL_DIR / "analyze.py"), str(project)],
                cwd=root,
                env=env,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertTrue((out_root / "summary.md").exists(), result.stdout + result.stderr)
            self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn(
                "Post-processing failed after successful analyzer:", result.stderr
            )
            self.assertIn("pal-findings.jsonl", result.stderr)
            status = json.loads(
                (out_root / "summary.json").read_text(encoding="utf-8")
            )
            self.assertEqual("complete", status["status"]["infrastructure"])
            self.assertEqual("failed", status["status"]["postprocessor"])
            self.assertEqual("incomplete", status["status"]["finalization"])
            diagnostic = out_root / status["artifacts"]["postprocessor_diagnostic"]
            self.assertTrue(diagnostic.exists())
            self.assertIn("JSONDecodeError", diagnostic.read_text(encoding="utf-8"))

    def test_wrappers_return_nonzero_when_required_summary_is_missing(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fake_dak = root / "fake-dak.cmd"
            fake_dak.write_text("@exit /b 0\r\n", encoding="ascii")
            env = os.environ.copy()
            env["DAK_EXE"] = str(fake_dak)
            for script, suffix in (("analyze.py", ".dproj"), ("analyze-unit.py", ".pas")):
                with self.subTest(script=script):
                    subject = root / f"Sample{suffix}"
                    subject.write_text("fixture", encoding="ascii")
                    out_root = root / f"out-{suffix[1:]}"
                    env["DAK_OUT"] = str(out_root)
                    result = subprocess.run(
                        [sys.executable, str(SKILL_DIR / script), str(subject)],
                        cwd=root,
                        env=env,
                        check=False,
                        capture_output=True,
                        text=True,
                    )

                    self.assertEqual(3, result.returncode, result.stdout + result.stderr)
                    self.assertIn("Summary not found", result.stderr)


if __name__ == "__main__":
    unittest.main()
