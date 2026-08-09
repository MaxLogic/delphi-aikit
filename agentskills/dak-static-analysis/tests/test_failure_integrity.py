import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SKILL_DIR = Path(__file__).resolve().parents[1]


def load_postprocess():
    spec = importlib.util.spec_from_file_location(
        "dak_static_analysis_postprocess", SKILL_DIR / "postprocess.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class WrapperExitTests(unittest.TestCase):
    wrappers = {
        "analyze.bat": "dummy.dproj",
        "analyze-unit.bat": "dummy.pas",
        "doctor.bat": None,
    }

    def assert_wrapper_exit_codes(self, env):
        cmd_exe = str(Path(os.environ["SystemRoot"]) / "System32" / "cmd.exe")
        for wrapper_name, argument in self.wrappers.items():
            with self.subTest(wrapper=wrapper_name):
                command = [cmd_exe, "/d", "/c", str(SKILL_DIR / wrapper_name)]
                if argument is not None:
                    command.append(argument)
                result = subprocess.run(
                    command,
                    cwd=SKILL_DIR,
                    env=env,
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(7, result.returncode, result.stdout + result.stderr)

    def test_windows_wrappers_preserve_python_exit_code(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            (temp_path / "py.cmd").write_text("@exit /b 7\r\n", encoding="ascii")
            env = os.environ.copy()
            env["PATH"] = os.pathsep.join(
                [str(temp_path), str(Path(os.environ["SystemRoot"]) / "System32")]
            )
            self.assert_wrapper_exit_codes(env)

    def test_windows_wrappers_preserve_fallback_python_exit_code(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            (temp_path / "python.cmd").write_text("@exit /b 7\r\n", encoding="ascii")
            env = os.environ.copy()
            env["PATH"] = os.pathsep.join(
                [str(temp_path), str(Path(os.environ["SystemRoot"]) / "System32")]
            )
            self.assert_wrapper_exit_codes(env)


class SummaryIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.postprocess = load_postprocess()

    def test_summary_errors_are_parsed(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            summary_path = Path(temp_dir) / "summary.md"
            summary_path.write_text(
                "# Static analysis\n\n"
                "## Errors\n\n"
                "- FixInsight TXT failed (exit=1).\n"
                "- Pascal Analyzer failed (exit=99).\n",
                encoding="utf-8",
            )

            summary = self.postprocess.parse_dak_summary_md(summary_path)

            self.assertEqual(
                [
                    "FixInsight TXT failed (exit=1).",
                    "Pascal Analyzer failed (exit=99).",
                ],
                summary.get("errors"),
            )

    def test_failed_run_writes_status_and_preserves_baseline_bytes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            baseline_path = out_root / "accepted" / "baseline.json"
            baseline_md_path = baseline_path.with_suffix(".md")
            baseline_path.parent.mkdir()
            baseline_path.write_bytes(b'{\r\n  "version": 1\r\n}\r\n')
            baseline_md_path.write_bytes(b"accepted baseline\r\n")
            baseline_bytes = baseline_path.read_bytes()
            baseline_md_bytes = baseline_md_path.read_bytes()
            (out_root / "summary.md").write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-07-15T10:00:00Z\n"
                "- Project: `C:\\work\\sample.dproj`\n\n"
                "## FixInsight\n\n"
                "- Findings (by code): 2\n\n"
                "## Pascal Analyzer\n\n"
                "- Totals: unavailable\n\n"
                "## Errors\n\n"
                "- FixInsight TXT failed (exit=1).\n"
                "- Pascal Analyzer failed (exit=99).\n",
                encoding="utf-8",
            )
            (out_root / "summary.json").write_text(
                json.dumps(
                    {
                        "schema_version": 2,
                        "subject": {
                            "kind": "project",
                            "path": "C:\\work\\sample.dproj",
                        },
                        "status": {
                            "infrastructure": "failed",
                            "policy": "not_evaluated",
                        },
                        "analyzers": {
                            "fixinsight": {
                                "requested": True,
                                "status": "failed",
                                "count_quality": "partial",
                            },
                            "pascal_analyzer": {
                                "requested": True,
                                "status": "failed",
                                "count_quality": "unavailable",
                            },
                        },
                        "counts": {
                            "fixinsight": {"quality": "partial", "total": 2},
                            "pascal_analyzer": {"quality": "unavailable"},
                        },
                        "errors": [
                            "FixInsight TXT failed (exit=1).",
                            "Pascal Analyzer failed (exit=99).",
                        ],
                    }
                ),
                encoding="utf-8",
            )

            with patch.dict(
                os.environ,
                {
                    "DAK_BASELINE": str(baseline_path),
                    "DAK_UPDATE_BASELINE": "1",
                },
                clear=False,
            ):
                result = self.postprocess.run_postprocess(out_root, title="sample")

            self.assertFalse(result.get("gate_pass"))
            status = json.loads((out_root / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(2, status["schema_version"])
            self.assertEqual("failed", status["status"]["infrastructure"])
            self.assertEqual("not_evaluated", status["status"]["policy"])
            self.assertEqual("partial", status["analyzers"]["fixinsight"]["count_quality"])
            self.assertEqual(
                "unavailable", status["analyzers"]["fixinsight"]["version"]
            )
            self.assertEqual(2, status["counts"]["fixinsight"]["total"])
            self.assertEqual(
                "unavailable",
                status["analyzers"]["pascal_analyzer"]["count_quality"],
            )
            self.assertEqual(
                "unavailable", status["analyzers"]["pascal_analyzer"]["version"]
            )
            self.assertNotIn("total", status["counts"]["pascal_analyzer"])
            self.assertEqual(baseline_bytes, baseline_path.read_bytes())
            self.assertEqual(baseline_md_bytes, baseline_md_path.read_bytes())
            self.assertFalse(result["baseline_created"])
            self.assertFalse(result["baseline_updated"])


class AnalyzeFailureTests(unittest.TestCase):
    def setUp(self):
        self.postprocess = load_postprocess()

    def test_valid_failed_summary_is_postprocessed_without_masking_dak_exit(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            out_root = root / ".dak" / "Sample"
            project = root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            source_summary = root / "failed-summary.md"
            source_summary.write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-07-15T10:00:00Z\n"
                f"- Project: `{project}`\n\n"
                "## FixInsight\n\n"
                "- Findings (by code): (TXT not generated)\n\n"
                "## Pascal Analyzer\n\n"
                "- Version: 9.21.3\n"
                "- Compiler target: Delphi 13 (Win64)\n"
                "- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0\n",
                encoding="utf-8",
            )
            source_seed = root / "failed-summary.json"
            source_seed.write_text(
                json.dumps(
                    {
                        "schema_version": 2,
                        "subject": {"kind": "project", "path": str(project)},
                        "status": {
                            "infrastructure": "failed",
                            "policy": "not_evaluated",
                        },
                        "analyzers": {
                            "pascal_analyzer": {
                                "requested": True,
                                "status": "failed",
                                "count_quality": "unavailable",
                            }
                        },
                        "counts": {
                            "pascal_analyzer": {"quality": "unavailable"}
                        },
                        "errors": ["Pascal Analyzer failed (exit=99)."],
                    }
                ),
                encoding="utf-8",
            )
            fake_dak = root / "fake-dak.cmd"
            # The installed analyzer is version-dependent, so this process fake keeps the failure contract deterministic.
            fake_dak.write_text(
                "@echo off\r\n"
                "if not exist \"%DAK_OUT%\" mkdir \"%DAK_OUT%\"\r\n"
                "copy /y \"%DAK_FAKE_SUMMARY%\" \"%DAK_OUT%\\summary.md\" >nul\r\n"
                "copy /y \"%DAK_FAKE_SEED%\" \"%DAK_OUT%\\summary.json\" >nul\r\n"
                "exit /b 7\r\n",
                encoding="ascii",
            )
            baseline = root / "accepted-baseline.json"
            baseline.write_bytes(b'{\r\n  "version": 1\r\n}\r\n')
            baseline_bytes = baseline.read_bytes()
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            subprocess.run(["git", "add", "."], cwd=root, check=True)
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
                cwd=root,
                check=True,
            )
            env = os.environ.copy()
            env.update(
                {
                    "DAK_EXE": str(fake_dak),
                    "DAK_OUT": str(out_root),
                    "DAK_FAKE_SUMMARY": str(source_summary),
                    "DAK_FAKE_SEED": str(source_seed),
                    "DAK_PASCAL_ANALYZER": "true",
                    "DAK_BASELINE": str(baseline),
                    "DAK_UPDATE_BASELINE": "1",
                }
            )

            result = subprocess.run(
                [sys.executable, str(SKILL_DIR / "analyze.py"), str(project)],
                cwd=root,
                env=env,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(7, result.returncode, result.stdout + result.stderr)
            self.assertTrue((out_root / "delta.json").exists())
            status = json.loads((out_root / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual("failed", status["status"]["infrastructure"])
            self.assertEqual("not_evaluated", status["status"]["policy"])
            self.assertEqual(
                "9.21.3", status["analyzers"]["pascal_analyzer"]["version"]
            )
            self.assertEqual(baseline_bytes, baseline.read_bytes())
            self.assertNotIn("total", status["counts"]["pascal_analyzer"])
            self.assertTrue(
                subprocess.run(
                    ["git", "status", "--porcelain"],
                    cwd=root,
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout
            )
            self.assertFalse(status["provenance"]["target"]["dirty"])
            self.assertEqual(
                40, len(status["provenance"]["target"]["head"])
            )

    def test_stale_seed_subject_fails_before_baseline_mutation(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            project = out_root / "Current.dproj"
            project.write_text("<Project />", encoding="ascii")
            (out_root / "summary.md").write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-07-15T10:00:00Z\n"
                f"- Project: `{project}`\n\n"
                "## FixInsight\n\n"
                "- Findings (by code): 0\n\n"
                "## Pascal Analyzer\n\n"
                "- Skipped.\n",
                encoding="utf-8",
            )
            (out_root / "summary.json").write_text(
                json.dumps(
                    {
                        "schema_version": 2,
                        "subject": {
                            "kind": "project",
                            "path": str(out_root / "Old.dproj"),
                        },
                        "status": {
                            "infrastructure": "complete",
                            "policy": "not_evaluated",
                        },
                    }
                ),
                encoding="utf-8",
            )
            baseline = out_root / "accepted.json"
            baseline.write_bytes(b'{\r\n  "version": 3\r\n}\r\n')
            before = baseline.read_bytes()

            with patch.dict(
                os.environ,
                {"DAK_BASELINE": str(baseline), "DAK_UPDATE_BASELINE": "1"},
                clear=False,
            ):
                with self.assertRaisesRegex(ValueError, "seed subject"):
                    self.postprocess.run_postprocess(out_root, title="Current")

            self.assertEqual(before, baseline.read_bytes())

    def test_malformed_seed_fails_before_baseline_and_history_mutation(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            project = out_root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            (out_root / "summary.md").write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-07-15T10:00:00Z\n"
                f"- Project: `{project}`\n\n"
                "## FixInsight\n\n"
                "- Findings (by code): 0\n\n"
                "## Pascal Analyzer\n\n"
                "- Skipped.\n",
                encoding="utf-8",
            )
            (out_root / "summary.json").write_text("{broken", encoding="ascii")
            baseline = out_root / "accepted.json"
            baseline_md = baseline.with_suffix(".md")
            history = out_root / "history.jsonl"
            baseline.write_bytes(b'{\r\n  "version": 3\r\n}\r\n')
            baseline_md.write_bytes(b"accepted markdown\r\n")
            history.write_bytes(b'{"accepted": true}\r\n')
            before = {
                baseline: baseline.read_bytes(),
                baseline_md: baseline_md.read_bytes(),
                history: history.read_bytes(),
            }

            with patch.dict(
                os.environ,
                {"DAK_BASELINE": str(baseline), "DAK_UPDATE_BASELINE": "1"},
                clear=False,
            ):
                with self.assertRaises(json.JSONDecodeError):
                    self.postprocess.run_postprocess(out_root, title="Sample")

            for path, data in before.items():
                self.assertEqual(data, path.read_bytes())


if __name__ == "__main__":
    unittest.main()
