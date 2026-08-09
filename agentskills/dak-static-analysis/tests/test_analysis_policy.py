import importlib.util
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SKILL_DIR = Path(__file__).resolve().parents[1]
OWNERSHIP_NAMES = ("project", "repository", "third_party", "unknown")
CAPTURED_PROVENANCE = {
    "target": {"head": "fixture", "dirty": False, "submodules": []},
    "dak": {"head": "dak-fixture", "executable_sha256": "8" * 64},
}


def load_postprocess():
    spec = importlib.util.spec_from_file_location(
        "dak_static_analysis_policy", SKILL_DIR / "postprocess.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)


def write_jsonl(path: Path, items: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(json.dumps(item) + "\n" for item in items), encoding="utf-8"
    )


class PolicyFixture:
    def __init__(self, root: Path):
        self.root = root
        self.repo = root / "repo"
        self.external = root / "external"
        self.repo.mkdir()
        self.external.mkdir()
        git(self.repo, "init", "-q")
        for relative in ("src/Owned.pas", "extras/RepoOnly.pas"):
            path = self.repo / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"unit {path.stem};\n", encoding="ascii")
        self.project = self.repo / "Sample.dproj"
        self.project.write_text(
            '<Project><ItemGroup><DCCReference Include="src\\Owned.pas"/>'
            "</ItemGroup></Project>",
            encoding="ascii",
        )
        self.main_source = self.repo / "Sample.dpr"
        self.main_source.write_text(
            "program Sample;\nuses Owned in 'src\\Owned.pas';\nbegin\nend.\n",
            encoding="ascii",
        )
        (self.repo / ".gitignore").write_text(".dak/\n", encoding="ascii")
        git(self.repo, "add", ".")
        git(
            self.repo,
            "-c",
            "user.name=DAK Test",
            "-c",
            "user.email=dak@example.invalid",
            "commit",
            "-qm",
            "fixture",
        )
        self.external_source = self.external / "External.pas"
        self.external_source.write_text("unit External;\n", encoding="ascii")
        self.out = self.repo / ".dak" / "Sample" / "policy"
        self.out.mkdir(parents=True)

    def write(
        self,
        findings: list[dict],
        *,
        gate_ownership: tuple[str, ...] = ("project", "repository"),
        project_roots: tuple[Path, ...] = (),
        third_party_roots: tuple[Path, ...] = (),
        search_hash: str = "1" * 64,
        policy_hash: str = "2" * 64,
    ) -> None:
        self.out.joinpath("summary.md").write_text(
            "# Static analysis\n\n"
            "- Timestamp: 2026-07-17T12:00:00Z\n"
            f"- Project: `{self.main_source}`\n\n"
            "## FixInsight\n\n"
            f"- Findings (by code): {len(findings)}\n"
            + (f"  - W101: {len(findings)}\n" if findings else "")
            + "\n## Pascal Analyzer\n\n"
            "- Version: 9.21.3\n"
            "- Compiler target: Delphi 13 (Win64)\n"
            "- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0\n",
            encoding="utf-8",
        )
        write_jsonl(self.out / "fixinsight" / "fi-findings.jsonl", findings)
        write_jsonl(self.out / "pascal-analyzer" / "pal-findings.jsonl", [])
        self.out.joinpath("run.log").write_text(
            f'CMD: palcmd.exe "{self.main_source}" /S="{self.repo / "src"}" /CD13W64\n',
            encoding="utf-8",
        )
        self.out.joinpath("summary.json").write_text(
            json.dumps(
                {
                    "schema_version": 2,
                    "status": {
                        "infrastructure": "complete",
                        "policy": "not_evaluated",
                    },
                    "subject": {
                        "kind": "project",
                        "path": str(self.main_source),
                        "project_file": str(self.project),
                    },
                    "compiler": {
                        "delphi": "23.0",
                        "platform": "Win64",
                        "config": "Debug",
                        "search_path_sha256": search_hash,
                    },
                    "analyzers": {
                        "fixinsight": {
                            "requested": True,
                            "status": "complete",
                            "version": "2023.12",
                            "options": {"sha256": "3" * 64},
                            "count_quality": "complete",
                            "runs": [],
                        },
                        "pascal_analyzer": {
                            "requested": True,
                            "status": "complete",
                            "version": "9.21.3",
                            "options": {"sha256": "4" * 64},
                            "count_quality": "complete",
                            "runs": [],
                        },
                    },
                    "inputs": {
                        "project_sha256": "5" * 64,
                        "main_source_sha256": "6" * 64,
                        "config_manifests": [
                            {"path": str(self.repo / "dak.ini"), "sha256": "7" * 64}
                        ],
                    },
                    "policy": {
                        "resolver": "Dak.Settings",
                        "values": {
                            "gate_ownership": list(gate_ownership),
                            "project_roots": [str(path) for path in project_roots],
                            "third_party_roots": [
                                str(path) for path in third_party_roots
                            ],
                        },
                        "sources": [str(self.repo / "dak.ini")],
                        "sha256": policy_hash,
                    },
                    "errors": [],
                    "artifacts": {"summary_markdown": "summary.md"},
                }
            ),
            encoding="utf-8",
        )

    def environment(self, **overrides: str) -> dict[str, str]:
        values = {
            "DAK_BASELINE": str(self.out / "baseline.json"),
            "DAK_GATE": "0",
            "DAK_CI": "0",
            "DAK_UPDATE_BASELINE": "0",
            "DAK_GATE_REQUIRE_CONTEXT_MATCH": "0",
            "DAK_GATE_INCLUDE_PATHS": "",
            "DAK_GATE_EXCLUDE_PATHS": "",
        }
        values.update(overrides)
        return values


def finding(path: str) -> dict:
    return {
        "tool": "FixInsight",
        "code": "W101",
        "kind": "W",
        "file": path,
        "path": path,
        "line": 1,
        "col": 1,
        "message": "fixture warning",
    }


class AnalysisPolicyTests(unittest.TestCase):
    def setUp(self):
        self.postprocess = load_postprocess()

    def create_baseline(self, fixture: PolicyFixture, **write_kwargs) -> bytes:
        fixture.write([], **write_kwargs)
        with patch.dict(os.environ, fixture.environment(), clear=False):
            result = self.postprocess.run_postprocess(
                fixture.out,
                title="Sample",
                captured_provenance=CAPTURED_PROVENANCE,
            )
            self.assertTrue(result["gate_pass"])
        return (fixture.out / "baseline.json").read_bytes()

    def test_unit_project_context_participates_in_compatibility(self):
        seed = {
            "subject": {"kind": "unit"},
            "compiler": {},
            "analyzers": {},
            "inputs": {"project_context_sha256": "1" * 64},
            "policy": {"sha256": "2" * 64},
            "provenance": CAPTURED_PROVENANCE,
        }
        first = self.postprocess._compatibility_snapshot(seed)
        seed["inputs"]["project_context_sha256"] = "3" * 64
        second = self.postprocess._compatibility_snapshot(seed)
        self.assertNotEqual(first["sha256"], second["sha256"])

    def test_workspace_semantics_participate_in_compatibility(self):
        seed = {
            "workspace": {"root": r"C:\work", "vcs": "svn"},
            "subject": {"kind": "project"},
            "compiler": {},
            "analyzers": {},
            "inputs": {},
            "policy": {"sha256": "1" * 64},
            "provenance": {
                "target": {
                    "root": r"C:\work",
                    "vcs": "svn",
                    "status": "complete",
                    "dirty": False,
                    "diagnostic": "fixture",
                    "source_inputs": {
                        "scope": "svn-versioned-plus-unversioned-delphi-inputs",
                        "sha256": "2" * 64,
                        "file_count": 12,
                    },
                    "capabilities": {
                        "revision": "available",
                        "status": "available",
                        "inventory": "available",
                    },
                    "externals": [
                        {"path": "vendor/external", "revision": "42"}
                    ],
                },
                "dak": {},
            },
        }
        baseline = self.postprocess._compatibility_snapshot(seed)
        semantic_mutations = (
            ("root", lambda value: value["workspace"].update(root=r"D:\work")),
            ("vcs", lambda value: value["workspace"].update(vcs="none")),
            (
                "status",
                lambda value: value["provenance"]["target"].update(
                    status="unavailable"
                ),
            ),
            (
                "inventory_scope",
                lambda value: value["provenance"]["target"][
                    "source_inputs"
                ].update(scope="filesystem-delphi-inputs"),
            ),
            (
                "capability",
                lambda value: value["provenance"]["target"][
                    "capabilities"
                ].update(inventory="fallback"),
            ),
            (
                "external",
                lambda value: value["provenance"]["target"]["externals"][0].update(
                    path="vendor/other"
                ),
            ),
        )
        for name, mutate in semantic_mutations:
            with self.subTest(name=name):
                changed = copy.deepcopy(seed)
                mutate(changed)
                self.assertNotEqual(
                    baseline["sha256"],
                    self.postprocess._compatibility_snapshot(changed)["sha256"],
                )

        candidate = copy.deepcopy(seed)
        candidate["provenance"]["target"].update(
            dirty=True, diagnostic="changed", head="different"
        )
        candidate["provenance"]["target"]["source_inputs"].update(
            sha256="3" * 64, file_count=99
        )
        self.assertEqual(
            baseline["sha256"],
            self.postprocess._compatibility_snapshot(candidate)["sha256"],
        )

    def test_default_policy_gates_owned_but_not_third_party_findings(self):
        cases = (
            ("project", "src/Owned.pas", False),
            ("repository", "extras/RepoOnly.pas", False),
            ("third_party", None, True),
        )
        for name, path, expected_pass in cases:
            with self.subTest(ownership=name), tempfile.TemporaryDirectory() as temp_dir:
                fixture = PolicyFixture(Path(temp_dir))
                self.create_baseline(fixture)
                finding_path = path or str(fixture.external_source)
                fixture.write([finding(finding_path)])
                with patch.dict(
                    os.environ, fixture.environment(DAK_GATE="1"), clear=False
                ):
                    result = self.postprocess.run_postprocess(
                        fixture.out,
                        title="Sample",
                        captured_provenance=CAPTURED_PROVENANCE,
                    )
                self.assertEqual(expected_pass, result["gate_pass"])
                summary = json.loads(
                    (fixture.out / "summary.json").read_text(encoding="utf-8")
                )
                self.assertEqual(
                    "pass" if expected_pass else "fail",
                    summary["status"]["policy"],
                )
                self.assertEqual(1, summary["counts"]["raw"]["ownership"][name])

    def test_optional_total_threshold_runs_after_ownership_selection(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = PolicyFixture(Path(temp_dir))
            self.create_baseline(fixture)
            fixture.write([finding(str(fixture.external_source))])
            with patch.dict(
                os.environ,
                fixture.environment(
                    DAK_GATE="1", DAK_MAX_FI_TOTAL_INCREASE="0"
                ),
                clear=False,
            ):
                result = self.postprocess.run_postprocess(
                    fixture.out,
                    title="Sample",
                    captured_provenance=CAPTURED_PROVENANCE,
                )
            self.assertTrue(result["gate_pass"])
            delta = json.loads(
                (fixture.out / "delta.json").read_text(encoding="utf-8")
            )
            self.assertEqual(
                [],
                delta["fixinsight"]["top_code_deltas"],
                "External FixInsight rows must stay out of actionable deltas.",
            )

    def test_unknown_ownership_fails_before_first_baseline_creation(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = PolicyFixture(Path(temp_dir))
            fixture.write([finding("Missing.pas")])
            with patch.dict(
                os.environ, fixture.environment(DAK_GATE="1"), clear=False
            ):
                result = self.postprocess.run_postprocess(
                    fixture.out,
                    title="Sample",
                    captured_provenance=CAPTURED_PROVENANCE,
                )
            self.assertFalse(result["gate_pass"])
            self.assertFalse((fixture.out / "baseline.json").exists())
            delta = json.loads(
                (fixture.out / "delta.json").read_text(encoding="utf-8")
            )
            self.assertTrue(
                any("unknown ownership" in reason.lower() for reason in delta["gate"]["reasons"])
            )

    def test_policy_root_resolves_only_an_otherwise_unknown_finding(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = PolicyFixture(Path(temp_dir))
            self.create_baseline(
                fixture, third_party_roots=(fixture.external,)
            )
            fixture.write(
                [finding("External.pas")],
                third_party_roots=(fixture.external,),
            )
            with patch.dict(
                os.environ, fixture.environment(DAK_GATE="1"), clear=False
            ):
                result = self.postprocess.run_postprocess(
                    fixture.out,
                    title="Sample",
                    captured_provenance=CAPTURED_PROVENANCE,
                )
            self.assertTrue(result["gate_pass"])
            record = json.loads(
                (fixture.out / "fixinsight" / "fi-findings.jsonl")
                .read_text(encoding="utf-8")
                .strip()
            )
            self.assertEqual("third_party", record["ownership"])
            self.assertEqual(
                str(fixture.external).replace("\\", "/"), record["ownership_root"]
            )

    def test_overlapping_policy_roots_remain_unknown(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = PolicyFixture(Path(temp_dir))
            fixture.write(
                [finding("External.pas")],
                project_roots=(fixture.external,),
                third_party_roots=(fixture.external,),
            )
            with patch.dict(
                os.environ, fixture.environment(DAK_GATE="1"), clear=False
            ):
                result = self.postprocess.run_postprocess(
                    fixture.out,
                    title="Sample",
                    captured_provenance=CAPTURED_PROVENANCE,
                )
            self.assertFalse(result["gate_pass"])
            record = json.loads(
                (fixture.out / "fixinsight" / "fi-findings.jsonl")
                .read_text(encoding="utf-8")
                .strip()
            )
            self.assertEqual("unknown", record["ownership"])
            self.assertFalse((fixture.out / "baseline.json").exists())

    def test_incompatible_gated_update_preserves_baseline_bytes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = PolicyFixture(Path(temp_dir))
            baseline_before = self.create_baseline(fixture)
            baseline_md_before = (fixture.out / "baseline.md").read_bytes()
            fixture.write([], search_hash="9" * 64)
            with patch.dict(
                os.environ,
                fixture.environment(DAK_GATE="1", DAK_UPDATE_BASELINE="1"),
                clear=False,
            ):
                result = self.postprocess.run_postprocess(
                    fixture.out,
                    title="Sample",
                    captured_provenance=CAPTURED_PROVENANCE,
                )
            self.assertFalse(result["gate_pass"])
            self.assertEqual(
                baseline_before, (fixture.out / "baseline.json").read_bytes()
            )
            self.assertEqual(
                baseline_md_before, (fixture.out / "baseline.md").read_bytes()
            )
            summary = json.loads(
                (fixture.out / "summary.json").read_text(encoding="utf-8")
            )
            self.assertEqual("fail", summary["status"]["policy"])
            delta = json.loads(
                (fixture.out / "delta.json").read_text(encoding="utf-8")
            )
            self.assertTrue(
                any("compatibility" in reason.lower() for reason in delta["gate"]["reasons"])
            )

    def test_compatibility_excludes_candidate_source_identity(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = PolicyFixture(Path(temp_dir))
            self.create_baseline(fixture)
            fixture.main_source.write_text(
                "program Sample;\n// dirty candidate\nbegin\nend.\n",
                encoding="ascii",
            )
            fixture.write([])
            with patch.dict(
                os.environ, fixture.environment(DAK_GATE="1"), clear=False
            ):
                result = self.postprocess.run_postprocess(
                    fixture.out,
                    title="Sample",
                    captured_provenance=CAPTURED_PROVENANCE,
                )
            self.assertTrue(result["gate_pass"])

    def test_verify_rejects_stale_compatibility_in_a_passing_gate(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            fixture = PolicyFixture(Path(temp_dir))
            self.create_baseline(fixture)
            fixture.write([])
            with patch.dict(
                os.environ, fixture.environment(DAK_GATE="1"), clear=False
            ):
                result = self.postprocess.run_postprocess(
                    fixture.out,
                    title="Sample",
                    captured_provenance=CAPTURED_PROVENANCE,
                )
            self.assertTrue(result["gate_pass"])
            summary_path = fixture.out / "summary.json"
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
            summary["compatibility"]["sha256"] = "0" * 64
            summary_path.write_text(json.dumps(summary), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "compatibility"):
                self.postprocess.verify_outputs(fixture.out)


if __name__ == "__main__":
    unittest.main()
