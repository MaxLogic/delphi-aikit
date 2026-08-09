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
        "dak_static_analysis_ownership_reporting", SKILL_DIR / "postprocess.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)


def commit_all(repo: Path, message: str) -> None:
    git(repo, "add", ".")
    git(
        repo,
        "-c",
        "user.name=DAK Test",
        "-c",
        "user.email=dak@example.invalid",
        "commit",
        "-qm",
        message,
    )


def write_jsonl(path: Path, items: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(item) + "\n" for item in items), encoding="utf-8"
    )


def ownership_counts(items: list[dict]) -> dict[str, int]:
    result = {name: 0 for name in ("project", "repository", "third_party", "unknown")}
    for item in items:
        result[item["ownership"]] += 1
    return result


class OwnershipReportingTests(unittest.TestCase):
    def setUp(self):
        self.postprocess = load_postprocess()

    def test_svn_and_unmanaged_workspace_ownership_is_path_based(self):
        for vcs in ("svn", "none"):
            with self.subTest(vcs=vcs), tempfile.TemporaryDirectory() as temp_dir:
                outer = Path(temp_dir)
                workspace = outer / "workspace"
                project_dir = workspace / "src"
                external_root = workspace / "vendor" / "external"
                outside = outer / "outside" / "Outside.pas"
                (outer / ".git").mkdir()
                project_dir.mkdir(parents=True)
                external_root.mkdir(parents=True)
                outside.parent.mkdir()
                if vcs == "svn":
                    (workspace / ".svn").mkdir()
                project_source = project_dir / "Owned.pas"
                project_source.write_text("unit Owned;\n", encoding="ascii")
                project = project_dir / "Sample.dproj"
                project.write_text(
                    '<Project><ItemGroup><DCCReference Include="Owned.pas"/>'
                    "</ItemGroup></Project>",
                    encoding="ascii",
                )
                repository_source = workspace / "extras" / "RepoOnly.pas"
                repository_source.parent.mkdir()
                repository_source.write_text("unit RepoOnly;\n", encoding="ascii")
                ignored_source = workspace / ".dak" / "ignored" / "RepoOnly.pas"
                ignored_source.parent.mkdir(parents=True)
                ignored_source.write_text("unit RepoOnly;\n", encoding="ascii")
                non_inventory_source = workspace / "notes" / "Owned.dfm"
                non_inventory_source.parent.mkdir()
                non_inventory_source.write_text("object Owned: TOwned\nend\n", encoding="ascii")
                for folder in ("a", "b"):
                    duplicate = workspace / folder / "Dupe.pas"
                    duplicate.parent.mkdir()
                    duplicate.write_text("unit Dupe;\n", encoding="ascii")
                external_source = external_root / "External.pas"
                external_source.write_text("unit External;\n", encoding="ascii")
                outside.write_text("unit Outside;\n", encoding="ascii")
                out_root = workspace / ".dak" / "Sample" / "ownership"
                out_root.mkdir(parents=True)
                seed = {
                    "workspace": {
                        "root": str(workspace),
                        "vcs": vcs,
                        "selector": vcs,
                        "source": "command_line",
                    },
                    "subject": {
                        "kind": "project",
                        "path": str(project_source),
                        "project_file": str(project),
                    },
                    "policy": {"values": {}},
                    "provenance": {
                        "target": {
                            "vcs": vcs,
                            "root": str(workspace),
                            "externals": [{"path": "vendor/external"}],
                        }
                    },
                }
                context = self.postprocess._build_ownership_context(
                    out_root, seed, None
                )
                cases = (
                    ("Owned.pas", "project"),
                    ("extras/RepoOnly.pas", "repository"),
                    ("RepoOnly.pas", "repository"),
                    ("notes/Owned.dfm", "repository"),
                    ("vendor/external/External.pas", "third_party"),
                    (str(outside), "third_party"),
                    ("Dupe.pas", "unknown"),
                    ("missing/RepoOnly.pas", "unknown"),
                    ("Missing.pas", "unknown"),
                )
                for raw_path, expected in cases:
                    with self.subTest(vcs=vcs, path=raw_path):
                        resolved = self.postprocess._resolve_ownership_path(
                            raw_path, context
                        )
                        ownership = self.postprocess._classify_ownership(
                            resolved, context
                        )
                        self.assertEqual(expected, ownership)
                        if raw_path == "vendor/external/External.pas":
                            self.assertEqual(
                                external_root,
                                self.postprocess._ownership_root(
                                    resolved, ownership, context
                                ),
                            )

    def test_unmanaged_workspace_does_not_attach_outer_git_history(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            outer = Path(temp_dir)
            git(outer, "init", "-q")
            workspace = outer / "workspace"
            project_dir = workspace / "src"
            project_dir.mkdir(parents=True)
            project = project_dir / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            source = project_dir / "Sample.dpr"
            source.write_text("program Sample; begin end.\n", encoding="ascii")
            repository_source = workspace / "extras" / "RepoOnly.pas"
            repository_source.parent.mkdir()
            repository_source.write_text("unit RepoOnly;\n", encoding="ascii")
            out_root = workspace / ".dak" / "Sample" / "ownership"
            out_root.mkdir(parents=True)
            (out_root / "summary.md").write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-08-08T10:00:00Z\n"
                f"- Project: `{source}`\n\n"
                "## FixInsight\n\n"
                "- Findings (by code): 1\n"
                "  - W101: 1\n\n"
                "## Pascal Analyzer\n\n"
                "- Version: disabled\n"
                "- Compiler target: Delphi 12 (Win64)\n"
                "- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0\n",
                encoding="utf-8",
            )
            write_jsonl(
                out_root / "fixinsight" / "fi-findings.jsonl",
                [
                    {
                        "tool": "FixInsight",
                        "code": "W101",
                        "kind": "W",
                        "file": "extras/RepoOnly.pas",
                        "path": "extras/RepoOnly.pas",
                        "line": 1,
                        "col": 1,
                        "message": "fixture warning",
                    }
                ],
            )
            write_jsonl(out_root / "pascal-analyzer" / "pal-findings.jsonl", [])
            (out_root / "summary.json").write_text(
                json.dumps(
                    {
                        "schema_version": 2,
                        "status": {
                            "infrastructure": "complete",
                            "policy": "not_evaluated",
                        },
                        "workspace": {
                            "root": str(workspace),
                            "vcs": "none",
                            "selector": "project",
                            "source": "command_line",
                        },
                        "subject": {
                            "kind": "project",
                            "path": str(source),
                            "project_file": str(project),
                        },
                        "compiler": {
                            "delphi": "23.0",
                            "platform": "Win64",
                            "config": "Debug",
                            "search_path_sha256": "1" * 64,
                        },
                        "analyzers": {
                            "fixinsight": {
                                "requested": True,
                                "status": "complete",
                                "version": "fixture",
                                "options": {"sha256": "2" * 64},
                                "count_quality": "complete",
                            },
                            "pascal_analyzer": {
                                "requested": False,
                                "status": "not_requested",
                                "options": {"sha256": "3" * 64},
                                "count_quality": "complete",
                            },
                        },
                        "inputs": {"project_sha256": "4" * 64},
                        "policy": {
                            "values": {
                                "gate_ownership": ["project", "repository"],
                                "project_roots": [],
                                "third_party_roots": [],
                                "exclude_path_masks": [],
                            },
                            "sha256": "5" * 64,
                            "reporting_sha256": "6" * 64,
                        },
                        "errors": [],
                        "artifacts": {"summary_markdown": "summary.md"},
                    }
                ),
                encoding="utf-8",
            )
            environment = {
                "DAK_BASELINE": str(out_root / "baseline.json"),
                "DAK_GATE": "0",
                "DAK_CI": "0",
                "DAK_UPDATE_BASELINE": "0",
                "DAK_GATE_REQUIRE_CONTEXT_MATCH": "0",
            }
            captured = {
                "target": {"vcs": "none", "root": str(workspace)},
                "dak": {"head": "fixture", "executable_sha256": "7" * 64},
            }
            with patch.dict(os.environ, environment, clear=False):
                result = self.postprocess.run_postprocess(
                    out_root,
                    title="Sample",
                    captured_provenance=captured,
                )

            self.assertTrue(result["gate_pass"])
            record = next(
                self.postprocess._iter_jsonl(
                    out_root / "fixinsight" / "fi-findings.jsonl"
                )
            )
            self.assertEqual("repository", record["ownership"])
            history = list(self.postprocess._iter_jsonl(out_root / "history.jsonl"))
            self.assertNotIn("git", history[-1])
            self.postprocess.verify_outputs(out_root)

    def test_path_safe_ownership_is_consistent_across_ai_artifacts(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            workspace = Path(temp_dir)
            library = workspace / "library"
            repo = workspace / "repo"
            external = workspace / "external"
            shadow = workspace / "shadow"
            stale = workspace / "stale"
            library.mkdir()
            repo.mkdir()
            external.mkdir()
            shadow.mkdir()
            stale.mkdir()

            git(library, "init", "-q")
            (library / "nested").mkdir()
            (library / "nested" / "NestedUnit.pas").write_text(
                "unit NestedUnit;\n", encoding="ascii"
            )
            commit_all(library, "library")

            git(repo, "init", "-q")
            for relative in (
                "src/Main.pas",
                "src/Main.inc",
                "src/Dupe.pas",
                "extras/RepoOnly.pas",
                "extras/Dupe.pas",
                "search-a/DuplicateUnit.pas",
                "search-a/GuessOnly.pas",
                "search-b/DuplicateUnit.pas",
            ):
                path = repo / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(
                    f"unit {path.stem};\ninterface\nimplementation\nend.\n",
                    encoding="ascii",
                )
            project = repo / "Sample.dproj"
            project.write_text(
                "<Project><ItemGroup>"
                '<DCCReference Include="src\\Main.pas"/>'
                f'<DCCReference Include="{external / "ExternalUnit.pas"}"/>'
                "</ItemGroup></Project>",
                encoding="ascii",
            )
            main_source = repo / "Sample.dpr"
            main_source.write_text(
                "program Sample;\nuses Main in 'src\\Main.pas';\nbegin\nend.\n",
                encoding="ascii",
            )
            (repo / ".gitignore").write_text(".dak/\n", encoding="ascii")
            commit_all(repo, "project")
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
                capture_output=True,
            )
            commit_all(repo, "submodule")

            (external / "ExternalUnit.pas").write_text(
                "unit ExternalUnit;\n", encoding="ascii"
            )
            for name in ("Main.pas", "Dupe.pas"):
                (shadow / name).write_text(
                    f"unit {Path(name).stem};\n", encoding="ascii"
                )
            (stale / "Main.pas").write_text("unit Main;\n", encoding="ascii")

            out_root = repo / ".dak" / "Sample" / "ownership-fixture"
            out_root.mkdir(parents=True)
            (out_root / "summary.md").write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-07-17T10:00:00Z\n"
                f"- Project: `{main_source}`\n\n"
                "## FixInsight\n\n"
                "- Findings (by code): 7\n"
                "  - W101: 7\n\n"
                "## Pascal Analyzer\n\n"
                "- Version: 9.21.3\n"
                "- Compiler target: Delphi 13 (Win64)\n"
                "- Totals: warnings=9, strong_warnings=1, optimizations=0, total=10\n",
                encoding="utf-8",
            )
            search_paths = [
                repo / "src",
                repo / "extras",
                repo / "vendor" / "library" / "nested",
                external,
                repo / "search-a",
                repo / "search-b",
            ]
            (out_root / "run.log").write_text(
                f'CMD: palcmd.exe "{main_source}" /S="{stale}" /CD13W64\n'
                f'CMD: palcmd.exe "{main_source}" '
                f'/S="{";".join(str(path) for path in search_paths)}" /CD13W64\n',
                encoding="utf-8",
            )
            (out_root / "summary.json").write_text(
                json.dumps(
                    {
                        "schema_version": 2,
                        "status": {
                            "infrastructure": "complete",
                            "policy": "not_evaluated",
                        },
                        "subject": {
                            "kind": "project",
                            "path": str(main_source),
                            "project_file": str(project),
                        },
                        "compiler": {
                            "delphi": "23.0",
                            "platform": "Win64",
                            "config": "Debug",
                            "search_path_sha256": "fixture",
                        },
                        "analyzers": {
                            "fixinsight": {
                                "requested": True,
                                "status": "complete",
                                "count_quality": "complete",
                                "options": {"sha256": "1" * 64},
                            },
                            "pascal_analyzer": {
                                "requested": True,
                                "status": "complete",
                                "version": "9.21.3",
                                "count_quality": "complete",
                                "options": {"sha256": "2" * 64},
                            },
                        },
                        "counts": {},
                        "inputs": {},
                        "policy": {
                            "resolver": "Dak.Settings",
                            "values": {
                                "gate_ownership": ["project", "repository"],
                                "project_roots": [],
                                "third_party_roots": [],
                                "exclude_path_masks": ["*ExternalUnit.pas"],
                            },
                            "sha256": "3" * 64,
                            "reporting_sha256": "4" * 64,
                        },
                        "errors": [],
                        "artifacts": {"summary_markdown": "summary.md"},
                    }
                ),
                encoding="utf-8",
            )

            fi_records = [
                ("src/Main.pas", "project"),
                ("extras/RepoOnly.pas", "repository"),
                ("vendor/library/nested/NestedUnit.pas", "third_party"),
                (str(external / "ExternalUnit.pas"), "third_party"),
                ("MissingUnit.pas", "unknown"),
                (str(shadow / "Main.pas"), "third_party"),
                (str(shadow / "Dupe.pas"), "third_party"),
            ]
            write_jsonl(
                out_root / "fixinsight" / "fi-findings.jsonl",
                [
                    {
                        "tool": "FixInsight",
                        "code": "W101",
                        "kind": "W",
                        "file": path,
                        "path": path,
                        "line": index + 1,
                        "col": 1,
                        "message": expected,
                    }
                    for index, (path, expected) in enumerate(fi_records)
                ],
            )
            pal_records = [
                {"module": "Main", "path": "src/Main.pas"},
                {"module": "Sample", "path": "Sample.dpr"},
                {"module": "RepoOnly", "path": "extras/RepoOnly.pas"},
                {
                    "module": "NestedUnit",
                    "path": "vendor/library/nested/NestedUnit.pas",
                },
                {
                    "module": "ExternalUnit",
                    "path": str(external / "ExternalUnit.pas"),
                },
                {"module": "DuplicateUnit", "path": None},
                {"module": "MissingModule", "path": None},
                {"module": "Main", "path": "SRC/main.PAS"},
                {
                    "module": "DuplicateUnit",
                    "path": "search-a/DuplicateUnit.pas",
                },
                {"module": "GuessOnly", "path": None},
            ]
            write_jsonl(
                out_root / "pascal-analyzer" / "pal-findings.jsonl",
                [
                    {
                        "severity": (
                            "strong-warning"
                            if record["module"] == "NestedUnit"
                            else "warning"
                        ),
                        "report": "Warnings.xml",
                        "section": "Warnings",
                        "module": record["module"],
                        "path": record["path"],
                        "line": index + 1,
                        "message": record["module"],
                    }
                    for index, record in enumerate(pal_records)
                ],
            )

            with patch.dict(os.environ, {"DAK_TRIAGE_TOP": "1"}, clear=False):
                result = self.postprocess.run_postprocess(out_root, title="Sample")
                result = self.postprocess.run_postprocess(out_root, title="Sample")

            self.assertTrue(result["gate_pass"])
            self.assertEqual(
                1,
                (out_root / "summary.md")
                .read_text(encoding="utf-8")
                .count("<!-- DAK ownership -->"),
            )
            fi = list(
                self.postprocess._iter_jsonl(
                    out_root / "fixinsight" / "fi-findings.jsonl"
                )
            )
            pal = list(
                self.postprocess._iter_jsonl(
                    out_root / "pascal-analyzer" / "pal-findings.jsonl"
                )
            )
            self.assertEqual(
                [expected for _, expected in fi_records],
                [item["ownership"] for item in fi],
            )
            self.assertEqual(
                [
                    "project",
                    "project",
                    "repository",
                    "third_party",
                    "third_party",
                    "unknown",
                    "unknown",
                    "project",
                    "repository",
                    "unknown",
                ],
                [item["ownership"] for item in pal],
            )
            self.assertEqual("src/Main.pas", fi[5]["path"])
            self.assertEqual("third_party", fi[5]["ownership"])
            self.assertEqual(str(shadow / "Dupe.pas").replace("\\", "/"), fi[6]["path"])
            self.assertEqual("src/Main.pas", pal[0]["path"])
            self.assertEqual("Sample.dpr", pal[1]["path"])
            self.assertIsNone(pal[5]["path"])
            self.assertIsNone(pal[6]["path"])
            self.assertIsNone(pal[9]["path"])
            self.assertEqual(str(repo).replace("\\", "/"), fi[0]["ownership_root"])
            self.assertEqual(str(repo).replace("\\", "/"), fi[1]["ownership_root"])
            self.assertEqual(
                str(repo / "vendor" / "library").replace("\\", "/"),
                fi[2]["ownership_root"],
            )
            self.assertEqual(
                str(external).replace("\\", "/"), fi[3]["ownership_root"]
            )
            self.assertIsNone(fi[4]["ownership_root"])

            raw_expected = {
                "project": 4,
                "repository": 3,
                "third_party": 6,
                "unknown": 4,
            }
            expected = {
                "project": 4,
                "repository": 3,
                "third_party": 0,
                "unknown": 0,
            }
            self.assertEqual(raw_expected, ownership_counts(fi + pal))
            summary = json.loads((out_root / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(3, summary["schema_version"])
            self.assertEqual(17, summary["counts"]["raw"]["total"])
            self.assertEqual(
                {"fixinsight": 7, "pascal_analyzer": 10},
                summary["counts"]["raw"]["by_analyzer"],
            )
            self.assertEqual(
                {
                    "warning": 16,
                    "strong_warning": 1,
                    "optimization": 0,
                    "maintainability": 0,
                    "hygiene": 0,
                    "other": 0,
                },
                summary["counts"]["raw"]["by_severity"],
            )
            self.assertEqual(raw_expected, summary["counts"]["raw"]["ownership"])
            self.assertEqual(7, summary["counts"]["actionable"]["total"])
            self.assertEqual(expected, summary["counts"]["actionable"]["ownership"])
            self.assertEqual(2, summary["counts"]["ignored"]["total"])
            self.assertEqual(4, summary["counts"]["external"]["total"])
            self.assertEqual(4, summary["counts"]["unknown"]["total"])
            self.assertEqual(0, summary["counts"]["advisory_metrics"]["total"])
            self.assertEqual(
                ["project", "repository"],
                summary["policy"]["active"]["gate_ownership"],
            )
            delta = json.loads((out_root / "delta.json").read_text(encoding="utf-8"))
            self.assertEqual(expected, delta["ownership"]["after"])
            actionable_sarif = json.loads(
                (out_root / "static-analysis.sarif").read_text(encoding="utf-8")
            )
            actionable_sarif_results = [
                result
                for run in actionable_sarif["runs"]
                for result in run.get("results", [])
            ]
            self.assertEqual(
                expected,
                ownership_counts(
                    [
                        {"ownership": result["properties"]["ownership"]}
                        for result in actionable_sarif_results
                    ]
                ),
            )
            self.assertTrue(
                all(
                    "ownership_root" in result["properties"]
                    for result in actionable_sarif_results
                )
            )
            full_sarif = json.loads(
                (out_root / "static-analysis.full.sarif").read_text(
                    encoding="utf-8"
                )
            )
            full_sarif_results = [
                result
                for run in full_sarif["runs"]
                for result in run.get("results", [])
            ]
            self.assertEqual(raw_expected, ownership_counts(
                [
                    {"ownership": result["properties"]["ownership"]}
                    for result in full_sarif_results
                ]
            ))
            self.assertEqual(
                "static-analysis.full.sarif",
                summary["artifacts"]["full_sarif"],
            )
            triage = (out_root / "triage.md").read_text(encoding="utf-8")
            self.assertIn("Sample.dpr", triage)
            self.assertNotIn("NestedUnit", triage)
            self.assertNotIn("ExternalUnit", triage)
            self.assertNotIn("MissingModule", triage)
            self.assertNotIn("GuessOnly", triage)
            self.assertIn("showing top 1", triage)
            external_summary = (out_root / "external-summary.md").read_text(
                encoding="utf-8"
            )
            self.assertIn("third_party", external_summary)
            self.assertIn(str(shadow).replace("\\", "/"), external_summary)
            for name in ("summary.md", "delta.md", "trend.md", "triage.md"):
                text = (out_root / name).read_text(encoding="utf-8")
                for ownership, count in expected.items():
                    self.assertIn(f"{ownership}={count}", text, name)
            trend = (out_root / "trend.md").read_text(encoding="utf-8")
            self.assertIn(
                "Latest raw ownership: project=4, repository=3, "
                "third_party=6, unknown=4",
                trend,
            )
            history = list(
                self.postprocess._iter_jsonl(out_root / "history.jsonl")
            )
            self.assertEqual(raw_expected, history[-1]["raw"]["ownership"])

            self.assertEqual(expected, self.postprocess.verify_outputs(out_root))
            triage_path = out_root / "triage.md"
            valid_triage = triage_path.read_text(encoding="utf-8")
            invalid_triage_lines = valid_triage.splitlines()
            row_index = next(
                index
                for index, line in enumerate(invalid_triage_lines)
                if line.startswith("- [")
            )
            invalid_triage_lines[row_index] += " corrupt"
            triage_path.write_text(
                "\n".join(invalid_triage_lines) + "\n", encoding="utf-8"
            )
            with self.assertRaisesRegex(
                ValueError, "triage.md evidence mismatch"
            ):
                self.postprocess.verify_outputs(out_root)
            triage_path.write_text(valid_triage, encoding="utf-8")

            sarif_path = out_root / "static-analysis.sarif"
            valid_sarif = json.loads(sarif_path.read_text(encoding="utf-8"))
            invalid_sarif = json.loads(json.dumps(valid_sarif))
            invalid_sarif["runs"][0]["results"][0]["message"]["text"] = "corrupt"
            sarif_path.write_text(json.dumps(invalid_sarif), encoding="utf-8")
            with self.assertRaisesRegex(
                ValueError, "static-analysis.sarif evidence mismatch"
            ):
                self.postprocess.verify_outputs(out_root)
            sarif_path.write_text(json.dumps(valid_sarif), encoding="utf-8")

            full_sarif_path = out_root / "static-analysis.full.sarif"
            valid_full_sarif = json.loads(
                full_sarif_path.read_text(encoding="utf-8")
            )
            invalid_full_sarif = json.loads(json.dumps(valid_full_sarif))
            invalid_full_sarif["runs"][0]["results"][0]["ruleId"] = "corrupt"
            full_sarif_path.write_text(
                json.dumps(invalid_full_sarif), encoding="utf-8"
            )
            with self.assertRaisesRegex(
                ValueError, "static-analysis.full.sarif evidence mismatch"
            ):
                self.postprocess.verify_outputs(out_root)
            full_sarif_path.write_text(
                json.dumps(valid_full_sarif), encoding="utf-8"
            )
            verify = subprocess.run(
                [
                    sys.executable,
                    str(SKILL_DIR / "postprocess.py"),
                    "--verify",
                    str(out_root),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(0, verify.returncode, verify.stdout + verify.stderr)

            with patch.dict(os.environ, {"DAK_GATE": "1"}, clear=False):
                gated = self.postprocess.run_postprocess(out_root, title="Sample")
            self.assertFalse(gated["gate_pass"])
            gated_delta = json.loads(
                (out_root / "delta.json").read_text(encoding="utf-8")
            )
            self.assertTrue(
                any(
                    "Unknown ownership findings: 4" in reason
                    for reason in gated_delta["gate"]["reasons"]
                )
            )

            fi_path = out_root / "fixinsight" / "fi-findings.jsonl"
            valid_fi = list(self.postprocess._iter_jsonl(fi_path))
            invalid_fi = [dict(item) for item in valid_fi]
            invalid_fi[0]["ownership"] = ""
            write_jsonl(fi_path, invalid_fi)
            with self.assertRaisesRegex(ValueError, "invalid ownership"):
                self.postprocess.verify_outputs(out_root)
            invalid_cli = subprocess.run(
                [
                    sys.executable,
                    str(SKILL_DIR / "postprocess.py"),
                    "--verify",
                    str(out_root),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(3, invalid_cli.returncode)
            self.assertIn("invalid ownership", invalid_cli.stderr)
            write_jsonl(fi_path, valid_fi)

            missing_path = fi_path.with_suffix(".missing")
            fi_path.replace(missing_path)
            try:
                with self.assertRaisesRegex(
                    ValueError, "requested FixInsight JSONL is missing"
                ):
                    self.postprocess.verify_outputs(out_root)
            finally:
                missing_path.replace(fi_path)

            delta_path = out_root / "delta.md"
            valid_delta = delta_path.read_text(encoding="utf-8")
            delta_path.write_text(
                valid_delta.replace(
                    f"- After: {self.postprocess._ownership_text(expected)}",
                    "- After: project=999, repository=0, third_party=0, unknown=0",
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "delta.md After ownership mismatch"):
                self.postprocess.verify_outputs(out_root)
            delta_path.write_text(valid_delta, encoding="utf-8")

            summary["counts"]["actionable"]["ownership"]["project"] += 1
            (out_root / "summary.json").write_text(
                json.dumps(summary), encoding="utf-8"
            )
            with self.assertRaisesRegex(
                ValueError, "summary.json projection mismatch"
            ):
                self.postprocess.verify_outputs(out_root)

    def test_advisory_metrics_require_explicit_policy_opt_in(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fi_path = root / "fixinsight" / "fi-findings.jsonl"
            pal_path = root / "pascal-analyzer" / "pal-findings.jsonl"
            write_jsonl(fi_path, [])
            write_jsonl(
                pal_path,
                [
                    {
                        "severity": "warning",
                        "section": "Method length",
                        "module": "Main",
                        "path": "src/Main.pas",
                        "line": 10,
                        "message": "120 statements",
                        "ownership": "project",
                        "ownership_root": str(root),
                    },
                    {
                        "severity": "warning",
                        "section": "Possible bad pointer usage",
                        "module": "Main",
                        "path": "src/Main.pas",
                        "line": 20,
                        "message": "Pointer cast",
                        "ownership": "project",
                        "ownership_root": str(root),
                    },
                ],
            )
            policy = {
                "gate_ownership": ["project", "repository"],
                "gate_metrics": [],
            }
            self.postprocess._apply_report_projections(fi_path, pal_path, policy)
            records = list(self.postprocess._iter_jsonl(pal_path))
            self.assertEqual("advisory_metrics", records[0]["report_projection"])
            self.assertEqual("actionable", records[1]["report_projection"])

            policy["gate_metrics"] = [
                "PAL.warnings.method-length-621eae6dfec836e8"
            ]
            self.postprocess._apply_report_projections(fi_path, pal_path, policy)
            records = list(self.postprocess._iter_jsonl(pal_path))
            self.assertEqual("actionable", records[0]["report_projection"])
            self.assertEqual("actionable", records[1]["report_projection"])

    def test_fixinsight_policy_keeps_raw_rows_and_marks_ignored_projection(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fi_path = root / "fixinsight" / "fi-findings.jsonl"
            pal_path = root / "pascal-analyzer" / "pal-findings.jsonl"
            write_jsonl(
                fi_path,
                [
                    {
                        "tool": "FixInsight",
                        "code": "W501",
                        "kind": "W",
                        "path": "src/Main.pas",
                        "line": 10,
                        "message": "ignored warning",
                        "ownership": "project",
                        "ownership_root": str(root),
                    },
                    {
                        "tool": "FixInsight",
                        "code": "C101",
                        "kind": "C",
                        "path": "src/Main.pas",
                        "line": 20,
                        "message": "actionable metric",
                        "ownership": "project",
                        "ownership_root": str(root),
                    },
                ],
            )
            write_jsonl(pal_path, [])
            policy = {
                "gate_ownership": ["project", "repository"],
                "fixinsight_ignore": ["W501"],
            }

            self.postprocess._apply_report_projections(fi_path, pal_path, policy)

            records = list(self.postprocess._iter_jsonl(fi_path))
            self.assertEqual(2, len(records))
            self.assertEqual("ignored", records[0]["report_projection"])
            self.assertEqual("actionable", records[1]["report_projection"])

    def test_unknown_ownership_stays_fail_closed_when_rule_is_ignored(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fi_path = root / "fixinsight" / "fi-findings.jsonl"
            pal_path = root / "pascal-analyzer" / "pal-findings.jsonl"
            write_jsonl(
                fi_path,
                [
                    {
                        "tool": "FixInsight",
                        "code": "W501",
                        "kind": "W",
                        "path": "Missing.pas",
                        "line": 10,
                        "message": "unresolved warning",
                        "ownership": "unknown",
                        "ownership_root": None,
                    }
                ],
            )
            write_jsonl(pal_path, [])
            policy = {
                "gate_ownership": ["project", "repository"],
                "fixinsight_ignore": ["W501"],
            }

            self.postprocess._apply_report_projections(fi_path, pal_path, policy)

            record = next(self.postprocess._iter_jsonl(fi_path))
            self.assertEqual("unknown", record["report_projection"])
            self.assertEqual(
                "ignored", record["report_policy"]["disposition"]
            )


if __name__ == "__main__":
    unittest.main()
