import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SKILL_DIR = Path(__file__).resolve().parents[1]


def load_postprocess():
    spec = importlib.util.spec_from_file_location(
        "dak_static_analysis_pal_rule_policy", SKILL_DIR / "postprocess.py"
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


class PalRulePolicyTests(unittest.TestCase):
    def setUp(self):
        self.postprocess = load_postprocess()

    def test_pal_rule_identity_keeps_exact_report_and_section_distinctions(self):
        collision_pairs = [
            (
                {"report": "Warnings.xml", "section": "Rule (A)"},
                {"report": "Warnings.xml", "section": "Rule - A"},
            ),
            (
                {
                    "report": "Warnings.xml",
                    "section": "A" * 64 + " first",
                },
                {
                    "report": "Warnings.xml",
                    "section": "A" * 64 + " second",
                },
            ),
            (
                {"report": "Report (A).xml", "section": "Same"},
                {"report": "Report - A.xml", "section": "Same"},
            ),
            (
                {"report": "Warnings.xml", "section": "Rule A"},
                {"report": "Warnings.xml", "section": "rule a"},
            ),
            (
                {"report": "Warnings.xml", "section": ""},
                {"report": "Warnings.xml", "section": "unknown"},
            ),
        ]
        for first, second in collision_pairs:
            with self.subTest(first=first, second=second):
                first_rule, _ = self.postprocess._pal_rule_identity(
                    first, pal_version=""
                )
                second_rule, _ = self.postprocess._pal_rule_identity(
                    second, pal_version=""
                )
                self.assertNotEqual(first_rule, second_rule)

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fi_path = root / "fixinsight" / "fi-findings.jsonl"
            pal_path = root / "pascal-analyzer" / "pal-findings.jsonl"
            write_jsonl(fi_path, [])
            findings = [
                {
                    "severity": "warning",
                    "report": "Warnings.xml",
                    "section": "Rule (A)",
                    "ownership": "project",
                },
                {
                    "severity": "warning",
                    "report": "Warnings.xml",
                    "section": "Rule - A",
                    "ownership": "project",
                },
            ]
            write_jsonl(pal_path, findings)
            ignored_rule, _ = self.postprocess._pal_rule_identity(
                findings[0], pal_version=""
            )

            self.postprocess._apply_report_projections(
                fi_path,
                pal_path,
                {
                    "gate_ownership": ["project", "repository"],
                    "pal_ignore_rules": [ignored_rule],
                },
            )

            records = list(self.postprocess._iter_jsonl(pal_path))
            self.assertEqual("ignored", records[0]["report_projection"])
            self.assertEqual("actionable", records[1]["report_projection"])

    def test_verified_alias_and_report_identity_drive_pal_suppression(self):
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
                        "report": "Warnings.xml",
                        "section": "Set before passed as out parameter",
                        "path": "src/One.pas",
                        "line": 10,
                        "ownership": "project",
                    },
                    {
                        "severity": "strong-warning",
                        "report": "Strong Warnings.xml",
                        "section": (
                            'Possible bad typecast (for objects: consider using "as")'
                        ),
                        "path": "src/Two.pas",
                        "line": 20,
                        "ownership": "project",
                    },
                    {
                        "severity": "optimization",
                        "report": "Optimization.xml",
                        "section": 'Parameter is "var", can be changed to "out"',
                        "path": "src/Three.pas",
                        "line": 30,
                        "ownership": "project",
                    },
                ],
            )

            self.postprocess._apply_report_projections(
                fi_path,
                pal_path,
                {
                    "gate_ownership": ["project", "repository"],
                    "pal_ignore_rules": ["WARN54"],
                },
                pal_version="9.21.3.0",
            )

            records = list(self.postprocess._iter_jsonl(pal_path))
            self.assertEqual(
                "PAL.warnings.set-before-passed-as-out-parameter-1f0b5be50a52e864",
                records[0]["normalized_rule"],
            )
            self.assertEqual("WARN54", records[0]["pal_code"])
            self.assertEqual("ignored", records[0]["report_projection"])
            self.assertEqual("pal_rule_ignore", records[0]["report_policy"]["reason"])
            self.assertEqual(
                "PAL.strong-warnings.possible-bad-typecast-for-objects-consider-using-as-2f1b8d64c282a875",
                records[1]["normalized_rule"],
            )
            self.assertEqual("STWA6", records[1]["pal_code"])
            self.assertEqual("actionable", records[1]["report_projection"])
            self.assertEqual(
                "PAL.optimization.parameter-is-var-can-be-changed-to-out-8d547169dfe78c92",
                records[2]["normalized_rule"],
            )
            self.assertEqual("OPTI8", records[2]["pal_code"])
            self.assertEqual("actionable", records[2]["report_projection"])

    def test_unknown_pal_filter_fails_with_unmatched_value(self):
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
                        "report": "Warnings.xml",
                        "section": "Set before passed as out parameter",
                        "path": "src/One.pas",
                        "line": 10,
                        "ownership": "project",
                    }
                ],
            )

            with self.assertRaisesRegex(ValueError, "UNKNOWN42"):
                self.postprocess._apply_report_projections(
                    fi_path,
                    pal_path,
                    {
                        "gate_ownership": ["project", "repository"],
                        "pal_ignore_rules": ["UNKNOWN42"],
                    },
                    pal_version="9.21.3.0",
                )

    def test_pal_filter_catalog_survives_zero_findings_and_absent_analyzer(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fi_path = root / "fixinsight" / "fi-findings.jsonl"
            pal_path = root / "pascal-analyzer" / "pal-findings.jsonl"
            write_jsonl(fi_path, [])
            write_jsonl(pal_path, [])
            report_path = pal_path.parent / "Sample" / "Warnings.xml"
            report_path.parent.mkdir()
            report_path.write_text(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<report name="Warnings Report">\n'
                '  <section name="Dormant rule" count="0"></section>\n'
                "</report>\n",
                encoding="utf-8",
            )
            dormant_rule, _ = self.postprocess._pal_rule_identity(
                {
                    "report": "Warnings.xml",
                    "section": "Dormant rule",
                },
                pal_version="9.21.3.0",
            )

            self.postprocess._apply_report_projections(
                fi_path,
                pal_path,
                {
                    "gate_ownership": ["project", "repository"],
                    "pal_ignore_rules": ["WARN54", dormant_rule],
                },
                pal_version="9.21.3.0",
            )

            self.assertEqual([], list(self.postprocess._iter_jsonl(pal_path)))

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fi_path = root / "fixinsight" / "fi-findings.jsonl"
            pal_path = root / "pascal-analyzer" / "pal-findings.jsonl"
            write_jsonl(fi_path, [])

            self.postprocess._apply_report_projections(
                fi_path,
                pal_path,
                {
                    "gate_ownership": ["project", "repository"],
                    "pal_ignore_rules": ["NOT-CHECKED-WITHOUT-PAL"],
                },
                pal_version="",
            )

    def test_pal_filter_origin_participates_in_compatibility(self):
        status_seed = {
            "policy": {
                "sha256": "1" * 64,
                "reporting_sha256": "2" * 64,
                "origins": {
                    "pal_ignore_rules": ["command_line"]
                },
            }
        }
        command_line = self.postprocess._compatibility_snapshot(status_seed)
        status_seed["policy"]["origins"]["pal_ignore_rules"] = [
            "C:/repo/dak.ini"
        ]
        ini_file = self.postprocess._compatibility_snapshot(status_seed)

        self.assertNotEqual(command_line["sha256"], ini_file["sha256"])

    def test_pal_not_requested_discards_retained_pal_evidence(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            unit = root / "Sample.pas"
            unit.write_text("unit Sample;\n", encoding="ascii")
            out_root = root / ".dak" / "Sample" / "retained-pal"
            out_root.mkdir(parents=True)
            (out_root / "summary.md").write_text(
                "# Pascal Analyzer unit summary: Sample\n\n"
                "- Timestamp: 2026-07-19T12:00:00Z\n"
                f"- Unit: `{unit}`\n"
                "- Skipped.\n",
                encoding="utf-8",
            )
            write_jsonl(out_root / "fixinsight" / "fi-findings.jsonl", [])
            pal_path = (
                out_root / "pascal-analyzer" / "pal-findings.jsonl"
            )
            pal_path.parent.mkdir(parents=True)
            pal_path.write_text(
                '{"severity":"warning","report":"Warnings.xml"',
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
                            "kind": "unit",
                            "path": str(unit),
                            "unit_file": str(unit),
                        },
                        "compiler": {
                            "delphi": "23.0",
                            "platform": "Win64",
                            "config": "Debug",
                            "search_path_sha256": "1" * 64,
                        },
                        "analyzers": {
                            "fixinsight": {
                                "requested": False,
                                "status": "not_requested",
                                "version": "",
                                "options": {"sha256": "2" * 64},
                                "count_quality": "complete",
                                "runs": [],
                            },
                            "pascal_analyzer": {
                                "requested": False,
                                "status": "not_requested",
                                "version": "9.21.3.0",
                                "options": {"sha256": "3" * 64},
                                "count_quality": "complete",
                                "runs": [],
                            },
                        },
                        "inputs": {
                            "unit_sha256": "4" * 64,
                            "config_manifests": [],
                        },
                        "policy": {
                            "resolver": "Dak.Settings",
                            "values": {
                                "gate_ownership": [
                                    "project",
                                    "repository",
                                ],
                                "gate_metrics": [],
                                "fixinsight_ignore": [],
                                "pal_ignore_rules": ["NOT-CURRENTLY-VALIDATED"],
                                "project_roots": [str(root)],
                                "third_party_roots": [],
                                "exclude_path_masks": [],
                            },
                            "origins": {
                                "pal_ignore_rules": ["command_line"]
                            },
                            "sources": [],
                            "sha256": "5" * 64,
                            "reporting_sha256": "6" * 64,
                        },
                        "errors": [],
                        "artifacts": {"summary_markdown": "summary.md"},
                    }
                ),
                encoding="utf-8",
            )
            (out_root / "run.log").write_text("", encoding="utf-8")

            self.postprocess.run_postprocess(
                out_root,
                title="Sample",
                captured_provenance={
                    "target": {
                        "head": "fixture",
                        "dirty": False,
                        "submodules": [],
                    },
                    "dak": {
                        "head": "dak-fixture",
                        "executable_sha256": "7" * 64,
                    },
                },
            )

            self.assertEqual([], list(self.postprocess._iter_jsonl(pal_path)))
            summary = json.loads(
                (out_root / "summary.json").read_text(encoding="utf-8")
            )
            self.assertEqual(
                0, summary["counts"]["raw"]["pascal_analyzer"]["total"]
            )

    def test_pal_rule_identity_survives_summary_sarif_and_fingerprint(self):
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
                        "report": "Warnings.xml",
                        "section": "Set before passed as out parameter",
                        "path": "src/One.pas",
                        "line": 10,
                        "ownership": "project",
                    },
                    {
                        "severity": "strong-warning",
                        "report": "Strong Warnings.xml",
                        "section": (
                            'Possible bad typecast (for objects: consider using "as")'
                        ),
                        "path": "src/Two.pas",
                        "line": 20,
                        "ownership": "project",
                    },
                ],
            )
            self.postprocess._apply_report_projections(
                fi_path,
                pal_path,
                {
                    "gate_ownership": ["project", "repository"],
                    "pal_ignore_rules": ["WARN54"],
                },
                pal_version="9.21.3.0",
            )

            projections = self.postprocess._report_projections(
                {
                    "pal_totals": {
                        "warnings": 1,
                        "strong_warnings": 1,
                        "optimizations": 0,
                        "total": 2,
                    }
                },
                fi_path,
                pal_path,
            )
            ignored_rule = (
                "PAL.warnings.set-before-passed-as-out-parameter-"
                "1f0b5be50a52e864"
            )
            self.assertEqual(
                1,
                projections["ignored"]["pascal_analyzer"]["by_rule"][
                    ignored_rule
                ],
            )
            actionable_sarif = self.postprocess._write_sarif(
                root,
                fi_jsonl_path=fi_path,
                pal_jsonl_path=pal_path,
            )
            full_sarif = self.postprocess._write_sarif(
                root,
                fi_jsonl_path=fi_path,
                pal_jsonl_path=pal_path,
                full_evidence=True,
            )
            actionable = json.loads(actionable_sarif.read_text(encoding="utf-8"))
            full = json.loads(full_sarif.read_text(encoding="utf-8"))
            actionable_results = [
                result for run in actionable["runs"] for result in run["results"]
            ]
            full_results = [
                result for run in full["runs"] for result in run["results"]
            ]
            self.assertNotIn(
                ignored_rule, {result["ruleId"] for result in actionable_results}
            )
            ignored_result = next(
                result for result in full_results if result["ruleId"] == ignored_rule
            )
            self.assertEqual("WARN54", ignored_result["properties"]["pal_code"])
            ignored_record = next(self.postprocess._iter_jsonl(pal_path))
            changed_identity = dict(ignored_record)
            changed_identity["normalized_rule"] = (
                "PAL.warnings.different-section"
            )
            self.assertNotEqual(
                self.postprocess._pal_fingerprint(ignored_record),
                self.postprocess._pal_fingerprint(changed_identity),
            )

    def test_fixinsight_filter_cannot_suppress_pascal_analyzer_rule(self):
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
                        "report": "Warnings.xml",
                        "section": "Set before passed as out parameter",
                        "path": "src/One.pas",
                        "line": 10,
                        "ownership": "project",
                    }
                ],
            )

            self.postprocess._apply_report_projections(
                fi_path,
                pal_path,
                {
                    "gate_ownership": ["project", "repository"],
                    "fixinsight_ignore": ["WARN54"],
                },
                pal_version="9.21.3.0",
            )

            record = next(self.postprocess._iter_jsonl(pal_path))
            self.assertEqual("actionable", record["report_projection"])
            self.assertNotIn("report_policy", record)

    def test_run_postprocess_keeps_pal_filter_in_baseline_and_delta_contract(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            project = root / "Sample.dproj"
            project.write_text("<Project />", encoding="ascii")
            (root / "One.pas").write_text("unit One;", encoding="ascii")
            (root / "Two.pas").write_text("unit Two;", encoding="ascii")
            out_root = root / ".dak" / "Sample" / "pal-rule-policy"
            out_root.mkdir(parents=True)
            (out_root / "summary.md").write_text(
                "# Static analysis\n\n"
                "- Timestamp: 2026-07-19T12:00:00Z\n"
                f"- Project: `{project}`\n\n"
                "## FixInsight\n\n"
                "- Findings (by code): 0\n\n"
                "## Pascal Analyzer\n\n"
                "- Version: 9.21.3.0\n"
                "- Compiler target: Delphi 12 (Win64)\n"
                "- Totals: warnings=1, strong_warnings=1, "
                "optimizations=0, total=2\n",
                encoding="utf-8",
            )
            write_jsonl(out_root / "fixinsight" / "fi-findings.jsonl", [])
            write_jsonl(
                out_root / "pascal-analyzer" / "pal-findings.jsonl",
                [
                    {
                        "severity": "warning",
                        "report": "Warnings.xml",
                        "section": "Set before passed as out parameter",
                        "module": "One",
                        "path": str(root / "One.pas"),
                        "line": 10,
                        "message": "value",
                    },
                    {
                        "severity": "strong-warning",
                        "report": "Strong Warnings.xml",
                        "section": (
                            'Possible bad typecast (for objects: consider using "as")'
                        ),
                        "module": "Two",
                        "path": str(root / "Two.pas"),
                        "line": 20,
                        "message": "cast",
                    },
                ],
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
                            "path": str(project),
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
                                "requested": False,
                                "status": "not_requested",
                                "version": "",
                                "options": {"sha256": "2" * 64},
                                "count_quality": "complete",
                                "runs": [],
                            },
                            "pascal_analyzer": {
                                "requested": True,
                                "status": "complete",
                                "version": "9.21.3.0",
                                "options": {"sha256": "3" * 64},
                                "count_quality": "complete",
                                "runs": [],
                            },
                        },
                        "inputs": {
                            "project_sha256": "4" * 64,
                            "main_source_sha256": "5" * 64,
                            "config_manifests": [],
                        },
                        "policy": {
                            "resolver": "Dak.Settings",
                            "values": {
                                "gate_ownership": [
                                    "project",
                                    "repository",
                                    "third_party",
                                ],
                                "gate_metrics": [],
                                "fixinsight_ignore": [],
                                "pal_ignore_rules": ["WARN54"],
                                "project_roots": [str(root)],
                                "third_party_roots": [],
                                "exclude_path_masks": [],
                            },
                            "sources": [str(root / "dak.ini")],
                            "origins": {
                                "pal_ignore_rules": [str(root / "dak.ini")]
                            },
                            "sha256": "6" * 64,
                            "reporting_sha256": "7" * 64,
                        },
                        "errors": [],
                        "artifacts": {"summary_markdown": "summary.md"},
                    }
                ),
                encoding="utf-8",
            )
            (out_root / "run.log").write_text("", encoding="utf-8")
            provenance = {
                "target": {"head": "fixture", "dirty": False, "submodules": []},
                "dak": {
                    "head": "dak-fixture",
                    "executable_sha256": "8" * 64,
                },
            }
            environment = {
                "DAK_GATE": "0",
                "DAK_CI": "0",
                "DAK_UPDATE_BASELINE": "0",
            }

            with patch.dict(os.environ, environment, clear=False):
                result = self.postprocess.run_postprocess(
                    out_root,
                    title="Sample",
                    captured_provenance=provenance,
                )

            self.assertTrue(result["baseline_created"])
            summary = json.loads(
                (out_root / "summary.json").read_text(encoding="utf-8")
            )
            self.assertEqual(
                1, summary["counts"]["ignored"]["pascal_analyzer"]["total"]
            )
            self.assertEqual(
                1,
                summary["counts"]["actionable"]["pascal_analyzer"][
                    "strong_warnings"
                ],
                summary["counts"],
            )
            self.assertEqual(
                ["WARN54"],
                summary["policy"]["active"]["pal_ignore_rules"],
            )
            expected_aliases = {
                "OPTI8": (
                    "PAL.optimization."
                    "parameter-is-var-can-be-changed-to-out-8d547169dfe78c92"
                ),
                "STWA6": (
                    "PAL.strong-warnings."
                    "possible-bad-typecast-for-objects-consider-using-as-"
                    "2f1b8d64c282a875"
                ),
                "WARN54": (
                    "PAL.warnings.set-before-passed-as-out-parameter-"
                    "1f0b5be50a52e864"
                ),
            }
            self.assertEqual(
                expected_aliases,
                summary["analyzers"]["pascal_analyzer"][
                    "verified_rule_aliases"
                ],
            )
            baseline = json.loads(
                (out_root / "baseline.json").read_text(encoding="utf-8")
            )
            self.assertEqual(
                summary["compatibility"]["sha256"],
                baseline["compatibility"]["sha256"],
            )
            self.assertEqual(
                1, len(baseline["pascal_analyzer"]["strong_hashes"])
            )
            self.assertEqual(
                0, len(baseline["pascal_analyzer"]["warning_hashes"])
            )
            self.assertEqual(
                {
                    "PAL.strong-warnings.possible-bad-typecast-for-objects-consider-using-as-2f1b8d64c282a875": 1
                },
                baseline["pascal_analyzer"]["rule_counts"],
            )
            self.assertEqual(
                expected_aliases,
                baseline["pascal_analyzer"]["verified_rule_aliases"],
            )
            delta = json.loads(
                (out_root / "delta.json").read_text(encoding="utf-8")
            )
            self.assertTrue(delta["baseline"]["created"])
            self.assertEqual(
                "PAL.strong-warnings.possible-bad-typecast-for-objects-consider-using-as-2f1b8d64c282a875",
                delta["pascal_analyzer"]["rule_count_deltas"][0]["rule"],
            )
            self.assertEqual(
                {
                    "before": expected_aliases,
                    "after": expected_aliases,
                },
                delta["pascal_analyzer"]["verified_rule_aliases"],
            )
            self.assertEqual(
                [
                    {
                        "rule": (
                            "PAL.warnings."
                            "set-before-passed-as-out-parameter-"
                            "1f0b5be50a52e864"
                        ),
                        "before": 1,
                        "after": 1,
                        "delta": 0,
                    }
                ],
                delta["pascal_analyzer"]["ignored_rule_count_deltas"],
            )
            self.postprocess.verify_outputs(out_root)

            baseline_path = out_root / "baseline.json"
            delta_path = out_root / "delta.json"
            count_fields = (
                ("rule_count_deltas", "rule_counts"),
                ("raw_rule_count_deltas", "raw_rule_counts"),
                ("ignored_rule_count_deltas", "ignored_rule_counts"),
            )
            for delta_field, baseline_field in count_fields:
                with self.subTest(delta_field=delta_field, change="new"):
                    changed_baseline = json.loads(json.dumps(baseline))
                    changed_delta = json.loads(json.dumps(delta))
                    new_row = next(
                        row
                        for row in changed_delta["pascal_analyzer"][
                            delta_field
                        ]
                        if row["after"] > 0
                    )
                    changed_baseline["pascal_analyzer"][
                        baseline_field
                    ].pop(new_row["rule"])
                    new_row["before"] = 0
                    new_row["delta"] = new_row["after"]
                    baseline_path.write_text(
                        json.dumps(changed_baseline), encoding="utf-8"
                    )
                    delta_path.write_text(
                        json.dumps(changed_delta), encoding="utf-8"
                    )
                    self.postprocess.verify_outputs(out_root)

                with self.subTest(
                    delta_field=delta_field, change="removed"
                ):
                    removed_rule = (
                        "PAL.warnings.removed-fixture-"
                        "0123456789abcdef"
                    )
                    changed_baseline = json.loads(json.dumps(baseline))
                    changed_delta = json.loads(json.dumps(delta))
                    changed_baseline["pascal_analyzer"][
                        baseline_field
                    ][removed_rule] = 1
                    changed_delta["pascal_analyzer"][delta_field].append(
                        {
                            "rule": removed_rule,
                            "before": 1,
                            "after": 0,
                            "delta": -1,
                        }
                    )
                    baseline_path.write_text(
                        json.dumps(changed_baseline), encoding="utf-8"
                    )
                    delta_path.write_text(
                        json.dumps(changed_delta), encoding="utf-8"
                    )
                    self.postprocess.verify_outputs(out_root)

            baseline_path.write_text(
                json.dumps(baseline), encoding="utf-8"
            )
            delta_path.write_text(json.dumps(delta), encoding="utf-8")
            baseline_path.unlink()
            with self.assertRaisesRegex(ValueError, "baseline.*missing"):
                self.postprocess.verify_outputs(out_root)
            baseline_path.write_text(
                json.dumps(baseline), encoding="utf-8"
            )

            summary["policy"]["active"]["pal_ignore_rules"] = []
            (out_root / "summary.json").write_text(
                json.dumps(summary), encoding="utf-8"
            )
            with self.assertRaisesRegex(
                ValueError, "active PAL ignore policy"
            ):
                self.postprocess.verify_outputs(out_root)
            summary["policy"]["active"]["pal_ignore_rules"] = ["WARN54"]
            (out_root / "summary.json").write_text(
                json.dumps(summary), encoding="utf-8"
            )

            delta["pascal_analyzer"]["verified_rule_aliases"]["after"] = {}
            (out_root / "delta.json").write_text(
                json.dumps(delta), encoding="utf-8"
            )
            with self.assertRaisesRegex(
                ValueError, "verified PAL alias"
            ):
                self.postprocess.verify_outputs(out_root)
            delta["pascal_analyzer"]["verified_rule_aliases"]["after"] = (
                expected_aliases
            )

            delta["pascal_analyzer"]["verified_rule_aliases"]["before"] = {}
            (out_root / "delta.json").write_text(
                json.dumps(delta), encoding="utf-8"
            )
            with self.assertRaisesRegex(
                ValueError, "verified PAL alias"
            ):
                self.postprocess.verify_outputs(out_root)
            delta["pascal_analyzer"]["verified_rule_aliases"]["before"] = (
                expected_aliases
            )

            for field in (
                "rule_count_deltas",
                "raw_rule_count_deltas",
                "ignored_rule_count_deltas",
            ):
                with self.subTest(field=field):
                    row = delta["pascal_analyzer"][field][0]
                    row["before"] += 1
                    row["delta"] = row["after"] - row["before"]
                    (out_root / "delta.json").write_text(
                        json.dumps(delta), encoding="utf-8"
                    )
                    with self.assertRaisesRegex(ValueError, field):
                        self.postprocess.verify_outputs(out_root)
                    row["before"] -= 1
                    row["delta"] = row["after"] - row["before"]

            (out_root / "delta.json").write_text(
                json.dumps(delta), encoding="utf-8"
            )
            pal_path = (
                out_root / "pascal-analyzer" / "pal-findings.jsonl"
            )
            pal_records = list(self.postprocess._iter_jsonl(pal_path))
            pal_records[0]["pal_code"] = "STWA6"
            write_jsonl(pal_path, pal_records)
            self.postprocess._write_sarif(
                out_root,
                fi_jsonl_path=(
                    out_root / "fixinsight" / "fi-findings.jsonl"
                ),
                pal_jsonl_path=pal_path,
                full_evidence=True,
            )
            with self.assertRaisesRegex(ValueError, "PAL identity"):
                self.postprocess.verify_outputs(out_root)

    def test_unverified_pal_version_does_not_publish_native_alias(self):
        finding = {
            "report": "Warnings.xml",
            "section": "Set before passed as out parameter",
        }

        rule, code = self.postprocess._pal_rule_identity(
            finding, pal_version="9.21.4.0"
        )

        self.assertEqual(
            "PAL.warnings.set-before-passed-as-out-parameter-1f0b5be50a52e864",
            rule,
        )
        self.assertIsNone(code)


if __name__ == "__main__":
    unittest.main()
