import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SKILL_DIR = Path(__file__).resolve().parents[1]


def load_analyze_unit():
    spec = importlib.util.spec_from_file_location(
        "dak_static_analysis_analyze_unit", SKILL_DIR / "analyze-unit.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_analyze():
    spec = importlib.util.spec_from_file_location(
        "dak_static_analysis_analyze", SKILL_DIR / "analyze.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class AnalyzeUnitWrapperTests(unittest.TestCase):
    def test_explicit_workspace_dak_discovery_does_not_climb_outer_git(self):
        repo_dak_exe = SKILL_DIR.parents[1] / "bin" / "DelphiAIKit.exe"
        self.assertTrue(repo_dak_exe.is_file(), f"DAK executable not found: {repo_dak_exe}")
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            workspace = outer / "workspace"
            source_dir = workspace / "src"
            outer_dak_exe = outer / "bin" / "DelphiAIKit.exe"
            (outer / ".git").mkdir()
            source_dir.mkdir(parents=True)
            outer_dak_exe.parent.mkdir()
            outer_dak_exe.touch()
            project = source_dir / "Sample.dproj"
            unit_path = source_dir / "Sample.pas"
            project.touch()
            unit_path.touch()
            old_cwd = Path.cwd()
            old_path = os.environ.get("PATH")
            old_dak_exe = os.environ.pop("DAK_EXE", None)
            os.environ["PATH"] = ""
            os.chdir(workspace)
            try:
                for module, subject in (
                    (load_analyze(), project),
                    (load_analyze_unit(), unit_path),
                ):
                    with self.subTest(wrapper=module.__name__):
                        self.assertEqual(
                            repo_dak_exe.resolve(),
                            module._find_dak_exe(subject, workspace),
                        )
            finally:
                os.chdir(old_cwd)
                if old_path is None:
                    os.environ.pop("PATH", None)
                else:
                    os.environ["PATH"] = old_path
                if old_dak_exe is not None:
                    os.environ["DAK_EXE"] = old_dak_exe

    def _assert_wrappers_ignore_outer_git_dak_executable(
        self, selector_args: tuple[str, ...], write_selector_ini: bool
    ):
        repo_root = SKILL_DIR.parents[1]
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            workspace = outer / "workspace"
            source_dir = workspace / "src"
            outer_dak_exe = outer / "bin" / "DelphiAIKit.exe"
            (outer / ".git").mkdir()
            source_dir.mkdir(parents=True)
            outer_dak_exe.parent.mkdir()
            outer_dak_exe.touch()
            if write_selector_ini:
                (workspace / "dak.ini").write_text(
                    "[Workspace]\nRoot=.\n", encoding="ascii"
                )
            project = source_dir / "Sample.dproj"
            shutil.copy2(
                repo_root / "tests" / "fixtures" / "Sample.dproj", project
            )
            shutil.copy2(
                repo_root / "tests" / "fixtures" / "Sample.dpr",
                source_dir / "Sample.dpr",
            )
            unit_path = source_dir / "Sample.pas"
            unit_path.write_text(
                "unit Sample; interface implementation end.", encoding="ascii"
            )
            environment = os.environ.copy()
            environment.pop("DAK_EXE", None)
            git_exe = shutil.which("git")
            self.assertIsNotNone(git_exe, "git executable not found")
            environment.update(
                {
                    "PATH": str(Path(git_exe).parent),
                    "DAK_FIXINSIGHT": "false",
                    "DAK_PASCAL_ANALYZER": "false",
                    "DAK_GATE": "0",
                }
            )
            cases = (
                ("analyze.py", [str(project)], outer / "project-out"),
                ("analyze-unit.py", [str(unit_path)], outer / "unit-out"),
            )
            for wrapper, arguments, out_root in cases:
                with self.subTest(wrapper=wrapper):
                    case_environment = environment.copy()
                    case_environment["DAK_OUT"] = str(out_root)
                    result = subprocess.run(
                        [
                            sys.executable,
                            str(SKILL_DIR / wrapper),
                            *arguments,
                            *selector_args,
                        ],
                        cwd=workspace,
                        env=case_environment,
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        check=False,
                    )
                    self.assertEqual(0, result.returncode, result.stdout)
                    summary = json.loads(
                        (out_root / "summary.json").read_text(encoding="utf-8-sig")
                    )
                    self.assertEqual(
                        str(workspace.resolve()), summary["workspace"]["root"]
                    )

    def test_explicit_workspace_wrappers_ignore_outer_git_dak_executable(self):
        self._assert_wrappers_ignore_outer_git_dak_executable(
            ("--workspace-root", "."), False
        )

    def test_closest_ini_workspace_wrappers_ignore_outer_git_dak_executable(self):
        self._assert_wrappers_ignore_outer_git_dak_executable((), True)

    def test_project_wrapper_forwards_relative_fixed_workspace(self):
        repo_root = SKILL_DIR.parents[1]
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            workspace = root / "workspace"
            project_dir = workspace / "src"
            project_dir.mkdir(parents=True)
            project = project_dir / "Sample.dproj"
            shutil.copy2(repo_root / "tests" / "fixtures" / "Sample.dproj", project)
            shutil.copy2(
                repo_root / "tests" / "fixtures" / "Sample.dpr",
                project_dir / "Sample.dpr",
            )
            out_root = root / "out"
            environment = os.environ.copy()
            environment.update(
                {
                    "DAK_EXE": str(repo_root / "bin" / "DelphiAIKit.exe"),
                    "DAK_FIXINSIGHT": "false",
                    "DAK_PASCAL_ANALYZER": "false",
                    "DAK_OUT": str(out_root),
                    "DAK_GATE": "0",
                }
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SKILL_DIR / "analyze.py"),
                    str(project),
                    "--workspace-root",
                    "workspace",
                ],
                cwd=root,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )

            self.assertEqual(0, result.returncode, result.stdout)
            summary = json.loads(
                (out_root / "summary.json").read_text(encoding="utf-8-sig")
            )
            self.assertEqual(str(workspace.resolve()), summary["workspace"]["root"])
            self.assertEqual("command_line", summary["workspace"]["source"])

    def test_wrappers_parse_workspace_root(self):
        analyze = load_analyze()
        analyze_unit = load_analyze_unit()

        self.assertEqual(
            ("Sample.dproj", "project"),
            analyze._parse_args(
                ["analyze.py", "Sample.dproj", "--workspace-root", "project"]
            ),
        )
        self.assertEqual(
            ("Sample.pas", "Sample.dproj", "svn"),
            analyze_unit._parse_args(
                [
                    "analyze-unit.py",
                    "Sample.pas",
                    "Sample.dproj",
                    "--workspace-root=svn",
                ]
            ),
        )

    def test_unit_builder_forwards_workspace_root(self):
        module = load_analyze_unit()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            args = module._build_dak_args(
                "DelphiAIKit.exe",
                root / "Sample.pas",
                root / "out",
                None,
                str(root),
            )

        self.assertIn("--workspace-root", args)
        self.assertEqual(str(root), args[args.index("--workspace-root") + 1])

    def test_launchers_forward_all_arguments(self):
        project_bat = (SKILL_DIR / "analyze.bat").read_text(encoding="utf-8")
        project_sh = (SKILL_DIR / "analyze.sh").read_text(encoding="utf-8")
        unit_bat = (SKILL_DIR / "analyze-unit.bat").read_text(encoding="utf-8")
        unit_sh = (SKILL_DIR / "analyze-unit.sh").read_text(encoding="utf-8")

        self.assertIn(" %*", project_bat)
        self.assertIn('"$@"', project_sh)
        self.assertIn(" %*", unit_bat)
        self.assertIn('"$@"', unit_sh)

    def test_windows_launchers_forward_help(self):
        for launcher in ("analyze.bat", "analyze-unit.bat"):
            with self.subTest(launcher=launcher):
                result = subprocess.run(
                    ["cmd.exe", "/D", "/C", str(SKILL_DIR / launcher), "--help"],
                    cwd=SKILL_DIR,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
                self.assertEqual(0, result.returncode, result.stdout)
                self.assertIn("--workspace-root", result.stdout)

    def test_project_context_is_forwarded_with_compiler_context(self):
        module = load_analyze_unit()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            unit_path = root / "Sample.pas"
            project_path = root / "Sample.dproj"
            out_root = root / "out"
            unit_path.write_text("unit Sample; interface implementation end.", encoding="ascii")
            project_path.write_text("<Project />", encoding="ascii")

            old_platform = os.environ.pop("DAK_PLATFORM", None)
            old_config = os.environ.pop("DAK_CONFIG", None)
            try:
                args = module._build_dak_args(
                    "DelphiAIKit.exe", unit_path, out_root, project_path
                )
            finally:
                if old_platform is not None:
                    os.environ["DAK_PLATFORM"] = old_platform
                if old_config is not None:
                    os.environ["DAK_CONFIG"] = old_config

            self.assertIn("--project-context", args)
            self.assertEqual(str(project_path), args[args.index("--project-context") + 1])
            self.assertEqual("Win64", args[args.index("--platform") + 1])
            self.assertEqual("Release", args[args.index("--config") + 1])

    def test_launchers_forward_optional_project_argument(self):
        bat = (SKILL_DIR / "analyze-unit.bat").read_text(encoding="utf-8")
        shell = (SKILL_DIR / "analyze-unit.sh").read_text(encoding="utf-8")

        self.assertIn(" %*", bat)
        self.assertIn('"$@"', shell)

    def test_wrappers_forward_explicit_pal_exclusions(self):
        module = load_analyze_unit()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            with patch.dict(
                os.environ,
                {
                    "DAK_PAL_EXCLUDE_SEARCH_FOLDERS": r"C:\Vendor<+>;D:\Shared<+>",
                    "DAK_PAL_EXCLUDE_FILES": "System.pas;Vendor.pas",
                },
                clear=False,
            ):
                args = module._build_dak_args(
                    "DelphiAIKit.exe", root / "Sample.pas", root / "out", None
                )

        self.assertEqual(
            r"C:\Vendor<+>;D:\Shared<+>",
            args[args.index("--pa-exclude-search-folders") + 1],
        )
        self.assertEqual(
            "System.pas;Vendor.pas",
            args[args.index("--pa-exclude-files") + 1],
        )
        project_wrapper = (SKILL_DIR / "analyze.py").read_text(encoding="utf-8")
        self.assertIn("DAK_PAL_EXCLUDE_SEARCH_FOLDERS", project_wrapper)
        self.assertIn("--pa-exclude-search-folders", project_wrapper)
        self.assertIn("DAK_PAL_EXCLUDE_FILES", project_wrapper)
        self.assertIn("--pa-exclude-files", project_wrapper)

    def test_wrappers_keep_fixinsight_and_pal_rule_filters_distinct(self):
        module = load_analyze_unit()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            with patch.dict(
                os.environ,
                {
                    "DAK_FI_IGNORE_RULES": "W501",
                    "DAK_IGNORE_WARNING_IDS": "W502",
                    "DAK_PAL_IGNORE_RULES": (
                        "WARN54;"
                        "PAL.optimization.parameter-is-var-can-be-changed-to-out-8d547169dfe78c92"
                    ),
                },
                clear=False,
            ):
                args = module._build_dak_args(
                    "DelphiAIKit.exe", root / "Sample.pas", root / "out", None
                )

        self.assertEqual(
            "W501;W502", args[args.index("--ignore-warning-ids") + 1]
        )
        self.assertEqual(
            "WARN54;PAL.optimization.parameter-is-var-can-be-changed-to-out-8d547169dfe78c92",
            args[args.index("--pal-ignore-rules") + 1],
        )
        project_wrapper = (SKILL_DIR / "analyze.py").read_text(encoding="utf-8")
        unit_wrapper = (SKILL_DIR / "analyze-unit.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("DAK_FI_IGNORE_RULES", project_wrapper)
        self.assertIn("DAK_IGNORE_WARNING_IDS", project_wrapper)
        self.assertIn("DAK_PAL_IGNORE_RULES", project_wrapper)
        self.assertIn("DAK_PAL_IGNORE_RULES_ORIGIN", project_wrapper)
        self.assertIn("DAK_PAL_IGNORE_RULES_ORIGIN", unit_wrapper)
        self.assertIn("--pal-ignore-rules", project_wrapper)
        doctor = (SKILL_DIR / "doctor.py").read_text(encoding="utf-8")
        self.assertIn("PascalAnalyzerIgnore", doctor)
        self.assertIn("DAK_FI_IGNORE_RULES", doctor)
        self.assertIn("DAK_PAL_IGNORE_RULES", doctor)


if __name__ == "__main__":
    unittest.main()
