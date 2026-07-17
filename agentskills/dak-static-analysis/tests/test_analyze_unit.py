import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest


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


class AnalyzeUnitWrapperTests(unittest.TestCase):
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

        self.assertIn('"%~2"', bat)
        self.assertIn('"${2:-}"', shell)


if __name__ == "__main__":
    unittest.main()
