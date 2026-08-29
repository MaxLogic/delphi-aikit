import re
from pathlib import Path
import unittest


SKILL_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SKILL_DIR.parents[1]
DOCUMENT_PATHS = (
    SKILL_DIR / "SKILL.md",
    SKILL_DIR / "SETUP.md",
    SKILL_DIR / "references" / "triage.md",
    SKILL_DIR / "references" / "tooling.md",
    SKILL_DIR / "references" / "fix-recipes.md",
)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class SkillDocumentationContractTests(unittest.TestCase):
    def setUp(self):
        self.documents = "\n".join(
            read_text(path) for path in DOCUMENT_PATHS
        )
        implementation_paths = (
            SKILL_DIR / "analyze.py",
            SKILL_DIR / "analyze-unit.py",
            SKILL_DIR / "doctor.py",
            SKILL_DIR / "postprocess.py",
            REPO_ROOT / "src" / "dak.cli.pas",
            REPO_ROOT / "src" / "dak.messages.pas",
            REPO_ROOT / "src" / "Dak.Settings.pas",
        )
        self.implementation = "\n".join(
            read_text(path) for path in implementation_paths
        )
        self.workspace_documents = "\n".join(
            read_text(path)
            for path in (
                REPO_ROOT / "README.md",
                REPO_ROOT / "spec.md",
                REPO_ROOT / "dak-template.ini",
                SKILL_DIR / "SKILL.md",
                SKILL_DIR / "SETUP.md",
                SKILL_DIR / "references" / "tooling.md",
                SKILL_DIR / "references" / "triage.md",
            )
        )

    def test_bundled_resources_resolve_from_loaded_skill_directory(self):
        skill = read_text(SKILL_DIR / "SKILL.md")

        self.assertIn(
            "directory containing this `SKILL.md`",
            skill,
        )
        self.assertNotIn("agentskills/dak-static-analysis", skill)
        self.assertNotIn(r"agentskills\\dak-static-analysis", skill)
        for resource in (
            "doctor.bat",
            "analyze.bat",
            "analyze-unit.bat",
            "doctor.sh",
            "analyze.sh",
            "analyze-unit.sh",
            "postprocess.py",
        ):
            with self.subTest(resource=resource):
                self.assertRegex(
                    skill,
                    rf"<skill-root>[\\/]+{re.escape(resource)}",
                )

    def test_filtering_guidance_uses_only_implemented_contracts(self):
        blanket_lib_mask = "*" + "\\lib\\" + "*"
        self.assertNotIn(blanket_lib_mask, self.documents)
        self.assertNotRegex(
            self.documents,
            r"PALOFF[^\r\n]*(?:STWA;|WARN1;|OPTI8;)",
        )

        for phrase in (
            "Filtering decision table",
            "Ownership-aware actionable projection",
            "Post-analysis path filter",
            "Analyzer-specific report rule filter",
            "reviewed `PALOFF` with reason",
            "Explicit PAL `/X` or `/XF`",
            "static-analysis.full.sarif",
            "external-summary.md",
            "metrics.md",
            "unknown ownership",
            "method length",
            "parameter count",
            "advisory",
            "non-gating by default",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, self.documents)

        documented_options = set(
            re.findall(r"--[a-z][a-z0-9-]*", self.documents)
        )
        external_fixinsight_options = {"--libpath", "--unitscopes"}
        for option in sorted(
            documented_options - external_fixinsight_options
        ):
            with self.subTest(option=option):
                self.assertIn(option, self.implementation)

        documented_environment = set(
            re.findall(
                r"\b(?:DAK|PA|FI|FIXINSIGHT)_[A-Z0-9_]+\b",
                self.documents,
            )
        )
        for variable in sorted(documented_environment):
            with self.subTest(variable=variable):
                self.assertIn(variable, self.implementation)

        documented_ini = set(
            re.findall(
                r"\[([A-Za-z][A-Za-z0-9]*)\]\.([A-Za-z][A-Za-z0-9]*)",
                self.documents,
            )
        )
        documented_ini.update(
            re.findall(
                r"\[([A-Za-z][A-Za-z0-9]*)\]\s+"
                r"([A-Za-z][A-Za-z0-9]*)=",
                self.documents,
            )
        )
        documented_ini.update(
            (
                ("ReportFilter", "ExcludePathMasks"),
                ("FixInsightIgnore", "Warnings"),
                ("PascalAnalyzerIgnore", "Rules"),
                ("PascalAnalyzer", "ExcludeSearchFolders"),
                ("PascalAnalyzer", "ExcludeFiles"),
                ("AnalysisPolicy", "GateMetrics"),
            )
        )
        for section, key in sorted(documented_ini):
            with self.subTest(section=section, key=key):
                self.assertIn(section, self.implementation)
                self.assertIn(key, self.implementation)

        for section, key in (
            ("ReportFilter", "ExcludePathMasks"),
            ("FixInsightIgnore", "Warnings"),
            ("PascalAnalyzerIgnore", "Rules"),
            ("PascalAnalyzer", "ExcludeSearchFolders"),
            ("PascalAnalyzer", "ExcludeFiles"),
            ("AnalysisPolicy", "GateMetrics"),
        ):
            with self.subTest(section=section, key=key):
                self.assertIn(f"[{section}].{key}", self.documents)
                self.assertIn(section, self.implementation)
                self.assertIn(key, self.implementation)

        required_artifacts = {
            "summary.json",
            "triage.md",
            "triage-changed.md",
            "static-analysis.sarif",
            "static-analysis.full.sarif",
            "external-summary.md",
            "metrics.md",
            "baseline.json",
            "delta.json",
        }
        documented_artifacts = set(
            re.findall(
                r"`(?:[^`\r\n]*/)?"
                r"([a-z][a-z0-9-]*\.(?:jsonl|json|sarif|md|log))`",
                self.documents,
                flags=re.IGNORECASE,
            )
        )
        for artifact in sorted(
            documented_artifacts | required_artifacts
        ):
            with self.subTest(artifact=artifact):
                if artifact in required_artifacts:
                    self.assertIn(artifact, self.documents)
                exists_as_document = any(
                    path.is_file()
                    for path in (
                        REPO_ROOT / artifact,
                        SKILL_DIR / artifact,
                    )
                ) or any(SKILL_DIR.rglob(artifact))
                self.assertTrue(
                    artifact in self.implementation
                    or exists_as_document,
                    f"Documented artifact has no implementation: {artifact}",
                )

    def test_workspace_and_provenance_contract_is_documented(self):
        template = read_text(REPO_ROOT / "dak-template.ini")
        self.assertRegex(template, r"(?m)^\[Workspace\]\s*$")
        self.assertRegex(template, r"(?m)^Root=auto\s*$")

        for phrase in (
            "[Workspace].Root",
            "`--workspace-root`",
            "closest ancestor",
            "executable `dak.ini` fallback",
            "filesystem root",
            "fixed root",
            "`auto`",
            "`git`",
            "`svn`",
            "`project`",
            "revision",
            "dirty",
            "changed_files",
            "source_inputs",
            "inventory",
            "nested_roots",
            "submodules",
            "externals",
            "complete",
            "available",
            "fallback",
            "unavailable",
            "not_applicable",
            "svn info --xml",
            "svn status --xml",
            "svn list --xml -R",
            "svnversion",
            "bounded filesystem inventory",
            "does not fail analysis",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, self.workspace_documents)

        self.assertNotIn(
            "repo root (folder containing `.git` or `.svn`)",
            self.workspace_documents,
        )
        self.assertNotIn(
            "Repo root detection stops at the first folder",
            self.workspace_documents,
        )


if __name__ == "__main__":
    unittest.main()
