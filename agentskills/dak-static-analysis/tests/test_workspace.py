import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SKILL_DIR = Path(__file__).resolve().parents[1]
if str(SKILL_DIR) not in sys.path:
    sys.path.insert(0, str(SKILL_DIR))

from workspace import WorkspaceError, resolve_workspace, settings_paths
from postprocess import _workspace_target_identity, capture_run_provenance


class WorkspaceTests(unittest.TestCase):
    def test_fixed_cli_root_overrides_ini_and_outer_git(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            workspace = outer / "workspace"
            project = workspace / "src" / "Sample.dproj"
            (outer / ".git").mkdir()
            project.parent.mkdir(parents=True)
            project.touch()
            (project.parent / "dak.ini").write_text(
                "[Workspace]\nRoot=project\n", encoding="ascii"
            )

            resolved = resolve_workspace(project, str(workspace), cwd=outer)

            self.assertEqual(workspace.resolve(), resolved.root)
            self.assertEqual(str(workspace), resolved.selector)
            self.assertEqual("none", resolved.vcs)
            self.assertEqual("command_line", resolved.source)

    def test_strict_svn_stops_at_inner_working_copy(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            workspace = outer / "workspace"
            project = workspace / "src" / "Sample.dproj"
            (outer / ".git").mkdir()
            (workspace / ".svn").mkdir(parents=True)
            project.parent.mkdir(parents=True)
            project.touch()

            resolved = resolve_workspace(project, "svn")

            self.assertEqual(workspace.resolve(), resolved.root)
            self.assertEqual("svn", resolved.selector)
            self.assertEqual("svn", resolved.vcs)
            self.assertEqual("command_line", resolved.source)

    def test_closest_ini_project_selector_wins(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            project = outer / "workspace" / "src" / "Sample.dproj"
            project.parent.mkdir(parents=True)
            project.touch()
            (outer / "dak.ini").write_text(
                "[Workspace]\nRoot=missing\n", encoding="ascii"
            )
            selector_ini = project.parent / "dak.ini"
            selector_ini.write_text("[workspace]\nroot=project\n", encoding="ascii")

            try:
                resolved = resolve_workspace(project)
            except WorkspaceError as error:
                self.fail(str(error))

            self.assertEqual(project.parent.resolve(), resolved.root)
            self.assertEqual("project", resolved.selector)
            self.assertEqual("none", resolved.vcs)
            self.assertEqual(str(selector_ini.resolve()), resolved.source)

    def test_executable_ini_is_selector_fallback(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            workspace = outer / "workspace"
            project = workspace / "src" / "Sample.dproj"
            executable_ini = outer / "bin" / "dak.ini"
            project.parent.mkdir(parents=True)
            executable_ini.parent.mkdir()
            project.touch()
            executable_ini.write_text(
                "[Workspace]\nRoot=..\\workspace\n", encoding="ascii"
            )

            resolved = resolve_workspace(project, executable_ini=executable_ini)

            self.assertEqual(workspace.resolve(), resolved.root)
            self.assertEqual(r"..\workspace", resolved.selector)
            self.assertEqual(str(executable_ini.resolve()), resolved.source)

    def test_auto_uses_nearest_marker_and_no_vcs_uses_subject_directory(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            svn_root = outer / "svn"
            project = svn_root / "src" / "Sample.dproj"
            (outer / ".git").mkdir()
            (svn_root / ".svn").mkdir(parents=True)
            project.parent.mkdir(parents=True)
            project.touch()

            try:
                resolved = resolve_workspace(project, "auto")
            except WorkspaceError as error:
                self.fail(str(error))
            self.assertEqual(svn_root.resolve(), resolved.root)
            self.assertEqual("svn", resolved.vcs)

        with tempfile.TemporaryDirectory() as temp_dir:
            project = Path(temp_dir) / "Sample.dproj"
            project.touch()
            resolved = resolve_workspace(project)
            self.assertEqual(project.parent.resolve(), resolved.root)
            self.assertEqual("auto", resolved.selector)
            self.assertEqual("none", resolved.vcs)
            self.assertEqual("default", resolved.source)

        with tempfile.TemporaryDirectory() as temp_dir:
            workspace = Path(temp_dir)
            project = workspace / "src" / "Sample.dproj"
            (workspace / ".svn").mkdir()
            (workspace / ".git").write_text(
                "gitdir: elsewhere\n", encoding="ascii"
            )
            project.parent.mkdir()
            project.touch()
            resolved = resolve_workspace(project, "auto")
            self.assertEqual(workspace.resolve(), resolved.root)
            self.assertEqual("git", resolved.vcs)

    def test_project_selector_and_invalid_selectors(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            project = Path(temp_dir) / "src" / "Sample.dproj"
            project.parent.mkdir()
            project.touch()

            try:
                resolved = resolve_workspace(project, "project")
            except WorkspaceError as error:
                self.fail(str(error))
            self.assertEqual(project.parent.resolve(), resolved.root)
            self.assertEqual("project", resolved.selector)

            with self.assertRaisesRegex(WorkspaceError, "requires a .git marker"):
                resolve_workspace(project, "git")
            with self.assertRaisesRegex(WorkspaceError, "does not exist"):
                resolve_workspace(project, str(project.parent / "missing"))
            outside = Path(temp_dir) / "outside"
            outside.mkdir()
            with self.assertRaisesRegex(WorkspaceError, "does not contain"):
                resolve_workspace(project, str(outside))

            (project.parent / "dak.ini").write_text(
                "[Workspace]\nRoot=\n", encoding="ascii"
            )
            with self.assertRaisesRegex(WorkspaceError, "is empty"):
                resolve_workspace(project)

    def test_settings_paths_stay_inside_selected_workspace(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            workspace = outer / "workspace"
            project = workspace / "src" / "Sample.dproj"
            executable_ini = outer / "bin" / "dak.ini"
            project.parent.mkdir(parents=True)
            executable_ini.parent.mkdir()
            project.touch()
            selector_ini = outer / "dak.ini"
            selector_ini.write_text(
                "[Workspace]\nRoot=workspace\n[FixInsightIgnore]\nWarnings=WOUT\n",
                encoding="ascii",
            )

            resolved = resolve_workspace(project, executable_ini=executable_ini)
            paths = settings_paths(project, resolved, executable_ini)

            self.assertEqual(
                [workspace / "dak.ini", project.parent / "dak.ini"], paths
            )
            self.assertNotIn(selector_ini, paths)
            self.assertNotIn(executable_ini, paths)

    def test_default_settings_paths_are_deduplicated(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            workspace = Path(temp_dir)
            project = workspace / "src" / "Sample.dproj"
            executable_ini = workspace / "dak.ini"
            (workspace / ".git").mkdir()
            project.parent.mkdir()
            project.touch()
            executable_ini.write_text(
                "[PascalAnalyzer]\nPath=palcmd.exe\n", encoding="ascii"
            )

            resolved = resolve_workspace(project, executable_ini=executable_ini)
            paths = settings_paths(project, resolved, executable_ini)

            self.assertEqual(
                [executable_ini.resolve(), project.parent / "dak.ini"], paths
            )

    def test_svn_workspace_does_not_capture_outer_git_identity(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            subprocess.run(["git", "init", "-q", str(outer)], check=True)
            tracked = outer / "tracked.txt"
            tracked.write_text("tracked\n", encoding="ascii")
            subprocess.run(["git", "-C", str(outer), "add", "tracked.txt"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(outer),
                    "-c",
                    "user.name=DAK Test",
                    "-c",
                    "user.email=dak@example.invalid",
                    "commit",
                    "-qm",
                    "fixture",
                ],
                check=True,
            )
            workspace_root = outer / "svn"
            project = workspace_root / "src" / "Sample.dproj"
            (workspace_root / ".svn").mkdir(parents=True)
            project.parent.mkdir(parents=True)
            project.touch()
            workspace = resolve_workspace(project, "svn")

            provenance = capture_run_provenance(
                project, Path(sys.executable), workspace
            )

            self.assertEqual("svn", provenance["target"]["vcs"])
            self.assertEqual(
                str(workspace_root.resolve()), provenance["target"]["root"]
            )

    def test_windows_seed_root_is_converted_before_wsl_provenance_resolution(self):
        old_distro = os.environ.get("WSL_DISTRO_NAME")
        os.environ["WSL_DISTRO_NAME"] = "DAK-Test"
        try:
            identity = _workspace_target_identity(
                {"vcs": "svn", "root": r"C:\repo"}
            )
        finally:
            if old_distro is None:
                os.environ.pop("WSL_DISTRO_NAME", None)
            else:
                os.environ["WSL_DISTRO_NAME"] = old_distro

        self.assertEqual(
            str((Path("/mnt") / "c" / "repo").resolve()), identity["root"]
        )

    def test_delphi_seed_matches_python_selector_matrix(self):
        repo_root = SKILL_DIR.parents[1]
        dak_exe = repo_root / "bin" / "DelphiAIKit.exe"
        self.assertTrue(dak_exe.is_file(), f"DAK executable not found: {dak_exe}")
        cases = (
            ("default", "", "none"),
            ("project", "project", "none"),
            ("fixed", "fixed", "none"),
            ("git", "git", "git"),
            ("svn", "svn", "svn"),
            ("auto-svn", "auto", "svn"),
            ("ini-project", "", "none"),
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            matrix_root = Path(temp_dir)
            for name, selector_kind, expected_vcs in cases:
                with self.subTest(name=name):
                    case_root = matrix_root / name
                    workspace_root = case_root / "workspace"
                    project_dir = workspace_root / "src"
                    project_dir.mkdir(parents=True)
                    project = project_dir / "Sample.dproj"
                    shutil.copy2(
                        repo_root / "tests" / "fixtures" / "Sample.dproj", project
                    )
                    shutil.copy2(
                        repo_root / "tests" / "fixtures" / "Sample.dpr",
                        project_dir / "Sample.dpr",
                    )
                    if name == "git":
                        (workspace_root / ".git").write_text(
                            "gitdir: elsewhere\n", encoding="ascii"
                        )
                    if name in {"svn", "auto-svn"}:
                        (workspace_root / ".svn").mkdir()
                        (case_root / ".git").mkdir()
                    if name == "ini-project":
                        (project_dir / "dak.ini").write_text(
                            "[workspace]\nroot=project\n", encoding="ascii"
                        )
                    selector = (
                        str(workspace_root)
                        if selector_kind == "fixed"
                        else selector_kind
                    )
                    python_workspace = resolve_workspace(
                        project,
                        selector,
                        executable_ini=dak_exe.parent / "dak.ini",
                        cwd=case_root,
                    )
                    out_root = case_root / "out"
                    command = [
                        str(dak_exe),
                        "analyze",
                        "--project",
                        str(project),
                        "--delphi",
                        "23.0",
                        "--platform",
                        "Win64",
                        "--config",
                        "Debug",
                        "--fixinsight",
                        "false",
                        "--pascal-analyzer",
                        "false",
                        "--out",
                        str(out_root),
                    ]
                    if selector:
                        command.extend(["--workspace-root", selector])
                    result = subprocess.run(
                        command,
                        cwd=case_root,
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        check=False,
                    )
                    self.assertEqual(0, result.returncode, result.stdout)
                    seed = json.loads(
                        (out_root / "summary.json").read_text(encoding="utf-8-sig")
                    )
                    self.assertEqual(2, seed["schema_version"])
                    self.assertEqual(str(python_workspace.root), seed["workspace"]["root"])
                    self.assertEqual(python_workspace.selector, seed["workspace"]["selector"])
                    self.assertEqual(expected_vcs, seed["workspace"]["vcs"])
                    self.assertEqual(python_workspace.source, seed["workspace"]["source"])


if __name__ == "__main__":
    unittest.main()
