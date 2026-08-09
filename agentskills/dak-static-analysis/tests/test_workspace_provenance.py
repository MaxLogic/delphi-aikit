import importlib.util
from contextlib import contextmanager
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest


SKILL_DIR = Path(__file__).resolve().parents[1]


def load_postprocess():
    spec = importlib.util.spec_from_file_location(
        "dak_static_analysis_workspace_provenance",
        SKILL_DIR / "postprocess.py",
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class WorkspaceProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.postprocess = load_postprocess()

    @classmethod
    def setUpClass(cls):
        cls.svn_exe = Path(
            os.environ.get("DAK_SVN_EXE")
            or shutil.which("svn")
            or r"C:\Program Files\TortoiseSVN\bin\svn.exe"
        )
        cls.svnadmin_exe = Path(
            os.environ.get("DAK_SVNADMIN_EXE")
            or shutil.which("svnadmin")
            or r"C:\Program Files\TortoiseSVN\bin\svnadmin.exe"
        )
        if not cls.svn_exe.is_file() or not cls.svnadmin_exe.is_file():
            raise RuntimeError(
                "Real SVN integration requires svn.exe and svnadmin.exe"
            )

    @staticmethod
    def _remove_readonly(function, path, _error) -> None:
        os.chmod(path, stat.S_IWRITE)
        function(path)

    def svn(self, *arguments: str, cwd: Path | None = None) -> str:
        result = subprocess.run(
            [str(self.svn_exe), *arguments],
            cwd=cwd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
        )
        self.assertEqual(0, result.returncode, result.stdout)
        return result.stdout

    @contextmanager
    def svn_workspace(self):
        fixture_root = Path(tempfile.mkdtemp(prefix="dak-t239-svn-"))
        repository = fixture_root / "repository"
        seed = fixture_root / "seed"
        working_copy = fixture_root / "working-copy"
        seed.mkdir()
        (seed / "Main.pas").write_text("unit Main;\n", encoding="ascii")
        (seed / "Shared.inc").write_text("CONST VALUE = 1;\n", encoding="ascii")
        try:
            subprocess.run(
                [str(self.svnadmin_exe), "create", str(repository)],
                check=True,
                capture_output=True,
            )
            repository_url = repository.as_uri()
            self.svn("import", str(seed), repository_url, "-m", "initial")
            self.svn("checkout", repository_url, str(working_copy))
            yield fixture_root, working_copy, repository_url
        finally:
            if fixture_root.exists():
                shutil.rmtree(fixture_root, onerror=self._remove_readonly)
            self.assertFalse(
                fixture_root.exists(), f"SVN fixture leaked: {fixture_root}"
            )

    def test_unmanaged_workspace_has_bounded_source_identity(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "src").mkdir()
            (root / "src" / "Main.pas").write_text(
                "unit Main;\n", encoding="ascii"
            )
            (root / "Shared.inc").write_text("CONST VALUE = 1;\n", encoding="ascii")
            ignored = root / ".dak" / "ignored.pas"
            ignored.parent.mkdir()
            ignored.write_text("unit Ignored;\n", encoding="ascii")

            first = self.postprocess._workspace_target_identity(
                {"root": str(root), "vcs": "none"}
            )
            second = self.postprocess._workspace_target_identity(
                {"root": str(root), "vcs": "none"}
            )

            self.assertEqual("none", first["vcs"])
            self.assertEqual(str(root.resolve()), first["root"])
            self.assertEqual("not_applicable", first.get("status"))
            self.assertIsNone(first.get("revision"))
            self.assertIsNone(first.get("dirty"))
            self.assertIsNone(first.get("changed_files"))
            self.assertEqual(
                {
                    "revision": "not_applicable",
                    "status": "not_applicable",
                    "changed_files": "not_applicable",
                    "inventory": "available",
                    "nested_roots": "not_applicable",
                },
                first.get("capabilities"),
            )
            source_inputs = first.get("source_inputs") or {}
            self.assertEqual(2, source_inputs.get("file_count"))
            self.assertEqual(
                "filesystem-delphi-inputs", source_inputs.get("scope")
            )
            self.assertRegex(str(source_inputs.get("sha256") or ""), r"^[0-9a-f]{64}$")
            self.assertEqual(source_inputs, second.get("source_inputs"))

            (root / "src" / "Main.pas").write_text(
                "unit Main; // changed\n", encoding="ascii"
            )
            changed = self.postprocess._workspace_target_identity(
                {"root": str(root), "vcs": "none"}
            )
            self.assertNotEqual(
                source_inputs.get("sha256"),
                (changed.get("source_inputs") or {}).get("sha256"),
            )

    def test_git_identity_preserves_existing_fields_and_adds_capabilities(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "Main.pas").write_text("unit Main;\n", encoding="ascii")
            subprocess.run(["git", "-C", str(root), "add", "Main.pas"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(root),
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
            (root / "Extra.pas").write_text("unit Extra;\n", encoding="ascii")

            identity = self.postprocess._workspace_target_identity(
                {"root": str(root), "vcs": "git"}
            )

            self.assertEqual("git", identity["vcs"])
            self.assertRegex(identity["head"], r"^[0-9a-f]{40}$")
            self.assertEqual(identity["head"], identity.get("revision"))
            self.assertTrue(identity["dirty"])
            self.assertEqual(["Extra.pas"], identity.get("changed_files"))
            self.assertEqual("complete", identity.get("status"))
            self.assertEqual(
                {
                    "revision": "available",
                    "status": "available",
                    "changed_files": "available",
                    "inventory": "available",
                    "nested_roots": "available",
                },
                identity.get("capabilities"),
            )
            self.assertEqual([], identity["submodules"])
            self.assertEqual(2, identity["source_inputs"]["file_count"])
            self.assertEqual(
                "git-delphi-inputs-with-recursive-submodules",
                identity["source_inputs"]["scope"],
            )

    def test_missing_git_cli_uses_truthful_filesystem_fallback(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / ".git").mkdir()
            (root / "Main.pas").write_text("unit Main;\n", encoding="ascii")
            old_path = os.environ.get("PATH")
            os.environ["PATH"] = ""
            try:
                try:
                    identity = self.postprocess._workspace_target_identity(
                        {"root": str(root), "vcs": "git"}
                    )
                except Exception as error:
                    self.fail(f"missing Git CLI must degrade, not raise: {error}")
            finally:
                if old_path is None:
                    os.environ.pop("PATH", None)
                else:
                    os.environ["PATH"] = old_path

            self.assertEqual("git", identity["vcs"])
            self.assertEqual("unavailable", identity.get("status"))
            self.assertIsNone(identity.get("head"))
            self.assertIsNone(identity.get("revision"))
            self.assertIsNone(identity.get("dirty"))
            self.assertIsNone(identity.get("changed_files"))
            self.assertIn("git", str(identity.get("diagnostic") or "").casefold())
            self.assertEqual([], identity.get("submodules"))
            self.assertEqual(
                {
                    "revision": "unavailable",
                    "status": "unavailable",
                    "changed_files": "unavailable",
                    "inventory": "fallback",
                    "nested_roots": "unavailable",
                },
                identity.get("capabilities"),
            )
            self.assertEqual(1, identity["source_inputs"]["file_count"])
            self.assertEqual(
                "filesystem-delphi-inputs", identity["source_inputs"]["scope"]
            )

    def test_provenance_capture_survives_missing_git_cli(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / ".git").mkdir()
            subject = root / "Main.pas"
            subject.write_text("unit Main;\n", encoding="ascii")
            executable = root / "DelphiAIKit.exe"
            executable.write_bytes(b"fixture")
            old_path = os.environ.get("PATH")
            os.environ["PATH"] = ""
            try:
                try:
                    provenance = self.postprocess.capture_run_provenance(
                        subject,
                        executable,
                        {"root": str(root), "vcs": "git"},
                    )
                except Exception as error:
                    self.fail(
                        f"missing Git CLI must not abort provenance capture: {error}"
                    )
            finally:
                if old_path is None:
                    os.environ.pop("PATH", None)
                else:
                    os.environ["PATH"] = old_path

            self.assertEqual("unavailable", provenance["target"]["status"])
            self.assertEqual("unavailable", provenance["dak"]["status"])
            self.assertEqual(
                str(executable.resolve()), provenance["dak"]["executable"]
            )

    def test_clean_svn_workspace_has_complete_provenance(self):
        with self.svn_workspace() as (_fixture_root, working_copy, repository_url):
            identity = self.postprocess._workspace_target_identity(
                {"root": str(working_copy), "vcs": "svn"}
            )

            self.assertEqual("svn", identity["vcs"])
            self.assertEqual(str(working_copy.resolve()), identity["root"])
            self.assertEqual("complete", identity.get("status"))
            self.assertRegex(str(identity.get("revision") or ""), r"^\d+$")
            self.assertFalse(identity.get("dirty"))
            self.assertEqual([], identity.get("changed_files"))
            self.assertEqual([], identity.get("externals"))
            self.assertEqual(repository_url, identity.get("url"))
            self.assertEqual(repository_url, identity.get("repository_root"))
            self.assertRegex(
                str(identity.get("repository_uuid") or ""),
                r"^[0-9a-f-]{36}$",
            )
            self.assertEqual(
                {
                    "revision": "available",
                    "status": "available",
                    "changed_files": "available",
                    "inventory": "available",
                    "nested_roots": "available",
                },
                identity.get("capabilities"),
            )
            self.assertEqual(2, identity["source_inputs"]["file_count"])
            self.assertEqual(
                "svn-versioned-plus-unversioned-delphi-inputs",
                identity["source_inputs"]["scope"],
            )

    def test_svn_content_properties_and_unversioned_sources_are_dirty(self):
        with self.svn_workspace() as (_fixture_root, working_copy, _repository_url):
            (working_copy / "Main.pas").write_text(
                "unit Main; // modified\n", encoding="ascii"
            )
            self.svn(
                "propset",
                "dak-test",
                "yes",
                str(working_copy / "Shared.inc"),
                cwd=working_copy,
            )
            (working_copy / "Unversioned.pas").write_text(
                "unit Unversioned;\n", encoding="ascii"
            )

            identity = self.postprocess._workspace_target_identity(
                {"root": str(working_copy), "vcs": "svn"}
            )

            self.assertEqual("complete", identity.get("status"))
            self.assertTrue(identity.get("dirty"))
            self.assertEqual(
                ["Main.pas", "Shared.inc", "Unversioned.pas"],
                identity.get("changed_files"),
            )
            self.assertTrue(identity["svnversion"]["modified"])
            self.assertEqual(3, identity["source_inputs"]["file_count"])

    def test_svn_mixed_revision_is_not_reduced_to_one_revision(self):
        with self.svn_workspace() as (_fixture_root, working_copy, _repository_url):
            (working_copy / "New.pas").write_text("unit New;\n", encoding="ascii")
            self.svn("add", "New.pas", cwd=working_copy)
            self.svn("commit", "-m", "revision two", cwd=working_copy)

            identity = self.postprocess._workspace_target_identity(
                {"root": str(working_copy), "vcs": "svn"}
            )

            self.assertEqual("1:2", identity.get("revision"))
            self.assertEqual(1, identity["svnversion"]["minimum"])
            self.assertEqual(2, identity["svnversion"]["maximum"])
            self.assertFalse(identity["svnversion"]["modified"])
            self.assertEqual("complete", identity.get("status"))

    def test_svn_checked_out_external_is_a_clean_nested_root(self):
        with self.svn_workspace() as (fixture_root, working_copy, _repository_url):
            external_repository = fixture_root / "external-repository"
            external_seed = fixture_root / "external-seed"
            external_seed.mkdir()
            (external_seed / "Vendor.pas").write_text(
                "unit Vendor;\n", encoding="ascii"
            )
            subprocess.run(
                [str(self.svnadmin_exe), "create", str(external_repository)],
                check=True,
                capture_output=True,
            )
            external_url = external_repository.as_uri()
            self.svn("import", str(external_seed), external_url, "-m", "external")
            self.svn(
                "propset",
                "svn:externals",
                f"external {external_url}",
                str(working_copy),
                cwd=working_copy,
            )
            self.svn("commit", "-m", "register external", cwd=working_copy)
            self.svn("update", cwd=working_copy)

            identity = self.postprocess._workspace_target_identity(
                {"root": str(working_copy), "vcs": "svn"}
            )

            self.assertEqual("complete", identity.get("status"))
            self.assertFalse(identity.get("dirty"))
            self.assertEqual([], identity.get("changed_files"))
            self.assertEqual([{"path": "external"}], identity.get("externals"))
            self.assertEqual(
                "available", identity["capabilities"]["nested_roots"]
            )

    def test_missing_svnversion_only_reduces_revision_capability(self):
        with self.svn_workspace() as (fixture_root, working_copy, repository_url):
            tool_dir = fixture_root / "svn-tools-without-svnversion"

            def link_or_copy(source, destination):
                try:
                    os.link(source, destination)
                    return destination
                except OSError:
                    return shutil.copy2(source, destination)

            shutil.copytree(
                self.svn_exe.parent,
                tool_dir,
                ignore=shutil.ignore_patterns("svnversion.exe"),
                copy_function=link_or_copy,
            )
            previous_svn = os.environ.get("DAK_SVN_EXE")
            previous_path = os.environ.get("PATH")
            os.environ["DAK_SVN_EXE"] = str(tool_dir / "svn.exe")
            os.environ["PATH"] = ""
            try:
                identity = self.postprocess._workspace_target_identity(
                    {"root": str(working_copy), "vcs": "svn"}
                )
            finally:
                if previous_svn is None:
                    os.environ.pop("DAK_SVN_EXE", None)
                else:
                    os.environ["DAK_SVN_EXE"] = previous_svn
                if previous_path is None:
                    os.environ.pop("PATH", None)
                else:
                    os.environ["PATH"] = previous_path

            self.assertEqual("unavailable", identity.get("status"))
            self.assertIsNone(identity.get("revision"))
            self.assertFalse(identity.get("dirty"))
            self.assertEqual([], identity.get("changed_files"))
            self.assertEqual(repository_url, identity.get("url"))
            self.assertIn("svnversion", identity.get("diagnostic", ""))
            self.assertEqual(
                {
                    "revision": "unavailable",
                    "status": "available",
                    "changed_files": "available",
                    "inventory": "available",
                    "nested_roots": "available",
                },
                identity.get("capabilities"),
            )
            self.assertEqual(
                "svn-versioned-plus-unversioned-delphi-inputs",
                identity["source_inputs"]["scope"],
            )

    def test_missing_svn_cli_uses_truthful_filesystem_fallback(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / ".svn").mkdir()
            subject = root / "Main.pas"
            subject.write_text("unit Main;\n", encoding="ascii")
            executable = root / "DelphiAIKit.exe"
            executable.write_bytes(b"fixture")
            previous = os.environ.get("DAK_SVN_EXE")
            os.environ["DAK_SVN_EXE"] = str(root / "missing-svn.exe")
            try:
                captured = self.postprocess.capture_run_provenance(
                    subject,
                    executable,
                    {"root": str(root), "vcs": "svn"},
                )
            finally:
                if previous is None:
                    os.environ.pop("DAK_SVN_EXE", None)
                else:
                    os.environ["DAK_SVN_EXE"] = previous
            identity = captured["target"]

            self.assertEqual("svn", identity.get("vcs"))
            self.assertEqual("unavailable", identity.get("status"))
            self.assertIsNone(identity.get("revision"))
            self.assertIsNone(identity.get("dirty"))
            self.assertIsNone(identity.get("changed_files"))
            self.assertEqual([], identity.get("externals"))
            self.assertIn("svn", identity.get("diagnostic", "").casefold())
            self.assertEqual(
                {
                    "revision": "unavailable",
                    "status": "unavailable",
                    "changed_files": "unavailable",
                    "inventory": "fallback",
                    "nested_roots": "unavailable",
                },
                identity.get("capabilities"),
            )
            self.assertEqual(1, identity["source_inputs"]["file_count"])
            self.assertEqual(
                "filesystem-delphi-inputs", identity["source_inputs"]["scope"]
            )

            seed = {
                "workspace": {"root": str(root), "vcs": "svn"},
                "inputs": {},
                "provenance": {},
                "status": {"infrastructure": "complete"},
                "errors": [],
            }
            self.postprocess._enrich_provenance(
                seed,
                {"project": str(subject)},
                root / ".dak" / "Sample",
                captured_provenance=captured,
            )
            self.assertEqual("complete", seed["status"]["infrastructure"])
            self.assertEqual([], seed["errors"])
            self.assertEqual(
                "unavailable", seed["provenance"]["target"]["status"]
            )

    def test_failing_svn_workspace_metadata_degrades_without_raising(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / ".svn").mkdir()
            (root / "Main.pas").write_text("unit Main;\n", encoding="ascii")

            try:
                identity = self.postprocess._workspace_target_identity(
                    {"root": str(root), "vcs": "svn"}
                )
            except Exception as error:
                self.fail(f"failing SVN metadata must degrade, not raise: {error}")

            self.assertEqual("unavailable", identity.get("status"))
            self.assertIsNone(identity.get("revision"))
            self.assertIsNone(identity.get("dirty"))
            self.assertIsNone(identity.get("changed_files"))
            self.assertEqual(
                "filesystem-delphi-inputs", identity["source_inputs"]["scope"]
            )

    def test_changed_file_triage_uses_svn_provenance_without_git(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "Main.pas"
            source.write_text("unit Main;\n", encoding="ascii")
            out_root = root / ".dak" / "Sample"
            fixinsight = out_root / "fixinsight" / "fi-findings.jsonl"
            pascal_analyzer = (
                out_root / "pascal-analyzer" / "pal-findings.jsonl"
            )
            self.postprocess._write_jsonl(
                fixinsight,
                [
                    {
                        "code": "W101",
                        "path": "Main.pas",
                        "line": 1,
                        "col": 1,
                        "message": "SVN changed finding",
                    }
                ],
            )
            self.postprocess._write_jsonl(pascal_analyzer, [])

            triage_path = self.postprocess._write_triage_changed(
                out_root,
                title="Sample",
                summary={
                    "project": str(root / "Sample.dproj"),
                    "provenance": {
                        "target": {
                            "vcs": "svn",
                            "root": str(root),
                            "status": "complete",
                            "changed_files": ["Main.pas"],
                        }
                    },
                },
                fi_jsonl_path=fixinsight,
                pal_jsonl_path=pascal_analyzer,
            )

            triage = triage_path.read_text(encoding="utf-8")
            self.assertIn("- VCS: `svn`", triage)
            self.assertIn(f"- Workspace root: `{root}`", triage)
            self.assertIn("SVN changed finding", triage)
            self.assertNotIn("Git repo not found", triage)

    def test_changed_file_triage_is_not_applicable_without_vcs(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            out_root = root / ".dak" / "Sample"
            triage_path = self.postprocess._write_triage_changed(
                out_root,
                title="Sample",
                summary={
                    "provenance": {
                        "target": {
                            "vcs": "none",
                            "root": str(root),
                            "status": "not_applicable",
                            "changed_files": None,
                        }
                    }
                },
                fi_jsonl_path=out_root / "fixinsight" / "fi-findings.jsonl",
                pal_jsonl_path=(
                    out_root / "pascal-analyzer" / "pal-findings.jsonl"
                ),
            )

            triage = triage_path.read_text(encoding="utf-8")
            self.assertIn("No-VCS changed-file scope is not applicable.", triage)
            self.assertNotIn("unavailable", triage)


if __name__ == "__main__":
    unittest.main()
