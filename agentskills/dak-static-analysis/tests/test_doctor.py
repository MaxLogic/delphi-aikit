import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest


SKILL_DIR = Path(__file__).resolve().parents[1]


def load_doctor():
    spec = importlib.util.spec_from_file_location(
        "dak_static_analysis_doctor", SKILL_DIR / "doctor.py"
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class DoctorPalTests(unittest.TestCase):
    def test_pal_override_wins_over_known_install_root(self):
        module = load_doctor()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            override = root / "override" / "palcmd.exe"
            installed = root / "Peganza" / "Pascal Analyzer 9" / "palcmd.exe"
            override.parent.mkdir()
            installed.parent.mkdir(parents=True)
            override.touch()
            installed.touch()

            resolved = module._resolve_palcmd(str(override), [root])

            self.assertEqual(override.resolve(), resolved)

    def test_pal_is_found_in_known_install_root_without_path(self):
        module = load_doctor()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            installed = root / "Peganza" / "Pascal Analyzer 9" / "palcmd.exe"
            installed.parent.mkdir(parents=True)
            installed.touch()

            resolved = module._resolve_palcmd("", [root])

            self.assertEqual(installed.resolve(), resolved)

    def test_missing_explicit_pal_override_is_an_error(self):
        module = load_doctor()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)

            with self.assertRaises(FileNotFoundError):
                module._resolve_palcmd(str(root / "missing"), [root])

    def test_pal_override_expands_windows_environment_variables(self):
        module = load_doctor()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            executable = root / "palcmd.exe"
            executable.touch()
            old_value = os.environ.get("DAK_DOCTOR_PAL_ROOT")
            os.environ["DAK_DOCTOR_PAL_ROOT"] = str(root)
            try:
                resolved = module._resolve_palcmd(
                    r"%DAK_DOCTOR_PAL_ROOT%\palcmd.exe", []
                )
            finally:
                if old_value is None:
                    os.environ.pop("DAK_DOCTOR_PAL_ROOT", None)
                else:
                    os.environ["DAK_DOCTOR_PAL_ROOT"] = old_value

            self.assertEqual(executable.resolve(), resolved)

    def test_windows_environment_output_expands_wsl_missing_variables(self):
        module = load_doctor()
        windows_env = module._parse_windows_environment(
            "ProgramFiles=C:\\Program Files\r\nProgramW6432=C:\\Program Files\r\n"
        )

        expanded = module._expand_windows_env(
            r"%programfiles%\Peganza\Pascal Analyzer 9\palcmd.exe", windows_env
        )

        self.assertEqual(
            r"C:\Program Files\Peganza\Pascal Analyzer 9\palcmd.exe", expanded
        )

    def test_relative_pal_override_uses_dak_executable_directory(self):
        module = load_doctor()
        with tempfile.TemporaryDirectory() as temp_dir:
            executable_dir = Path(temp_dir)
            executable = executable_dir / "tools" / "palcmd.exe"
            executable.parent.mkdir()
            executable.touch()

            resolved = module._resolve_palcmd("tools", [], executable_dir)

            self.assertEqual(executable.resolve(), resolved)

    def test_pal_help_reports_version_architecture_and_supported_targets(self):
        module = load_doctor()
        help_text = """Pascal Analyzer (64-bits) version 9.21.3.0
Syntax: PALCMD [options] project-file
  /CD12W64  Emulate Delphi 12 Win64
  /CD13W64  Emulate Delphi 13 Win64
"""

        info = module._parse_pal_help(help_text)

        self.assertEqual("9.21.3.0", info.version)
        self.assertEqual("64-bit", info.architecture)
        self.assertTrue(info.help_available)
        self.assertEqual(
            (("Delphi 12", "Win64", "/CD12W64"), ("Delphi 13", "Win64", "/CD13W64")),
            info.supported_targets,
        )

    def test_pal_report_contains_resolved_tool_and_capabilities(self):
        module = load_doctor()
        info = module.PalHelpInfo(
            "9.21.3.0",
            "64-bit",
            True,
            (("Delphi 12", "Win64", "/CD12W64"), ("Delphi 13", "Win64", "/CD13W64")),
        )

        report = module._format_pal_report(Path(r"C:\PAL\palcmd.exe"), info)

        self.assertIn("Executable: C:\\PAL\\palcmd.exe", report)
        self.assertIn("Architecture: 64-bit", report)
        self.assertIn("Version: 9.21.3.0", report)
        self.assertIn("Help: available", report)
        self.assertIn("Delphi 12 Win64: supported (/CD12W64)", report)
        self.assertIn("Delphi 13 Win64: supported (/CD13W64)", report)

    def test_requested_bds_target_is_mapped_and_validated_against_help(self):
        module = load_doctor()
        info = module.PalHelpInfo(
            "9.21.3.0",
            "64-bit",
            True,
            (("Delphi 13", "Win32", "/CD13W32"),),
        )

        requested = module._requested_pal_target("37.0", "Win32")
        report = module._format_pal_report(Path("palcmd.exe"), info, requested)

        self.assertEqual(("Delphi 13", "Win32", "/CD13W32"), requested)
        self.assertTrue(module._pal_target_supported(info, requested))
        self.assertIn(
            "Requested target: Delphi 13 Win32: supported (/CD13W32)", report
        )

    def test_missing_requested_target_is_a_doctor_error(self):
        module = load_doctor()
        info = module.PalHelpInfo("9.21.3.0", "64-bit", True, ())
        requested = module._requested_pal_target("37.0", "Win64")

        error = module._pal_check_error(0, info, requested)

        self.assertIn("not supported", error)

    def test_project_dak_ini_override_wins_over_executable_defaults(self):
        module = load_doctor()
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / ".git").mkdir()
            executable = root / "bin" / "DelphiAIKit.exe"
            target = root / "projects" / "Sample.dproj"
            executable.parent.mkdir()
            target.parent.mkdir()
            executable.touch()
            target.touch()
            (executable.parent / "dak.ini").write_text(
                "[PascalAnalyzer]\nPath=C:\\PAL\\default\\palcmd.exe\n", encoding="ascii"
            )
            (root / "dak.ini").write_text(
                "[PascalAnalyzer]\nPath=C:\\PAL\\repo\\palcmd.exe\n", encoding="ascii"
            )
            (target.parent / "dak.ini").write_text(
                "[PascalAnalyzer]\nPath=%PAL_HOME%\\project\\palcmd.exe\n", encoding="ascii"
            )

            settings, paths = module._load_dak_settings(executable, target)

            self.assertEqual(
                r"%PAL_HOME%\project\palcmd.exe", settings["PascalAnalyzer"]["Path"]
            )
            self.assertEqual(
                [executable.parent / "dak.ini", root / "dak.ini", target.parent / "dak.ini"],
                paths,
            )


if __name__ == "__main__":
    unittest.main()
