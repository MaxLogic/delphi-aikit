import importlib.util
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

    def test_incomplete_summary_fails_without_creating_baseline(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            out_root = Path(temp_dir)
            (out_root / "summary.md").write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-07-15T10:00:00Z\n"
                "- Project: `C:\\work\\sample.dproj`\n\n"
                "## Errors\n\n"
                "- Pascal Analyzer failed (exit=99).\n",
                encoding="utf-8",
            )

            with patch.dict(os.environ, {"DAK_UPDATE_BASELINE": "1"}, clear=False):
                result = self.postprocess.run_postprocess(out_root, title="sample")

            self.assertFalse(result.get("gate_pass"))
            self.assertFalse((out_root / "baseline.json").exists())


if __name__ == "__main__":
    unittest.main()
