from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "check_confidential_paths.py"
SPEC = importlib.util.spec_from_file_location("check_confidential_paths", SCRIPT_PATH)
assert SPEC and SPEC.loader
GUARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARD)


class ConfidentialPathGuardTests(unittest.TestCase):
    def test_blocks_confidential_tree_but_allows_marker(self) -> None:
        paths = [
            "README.md",
            "tests/fixtures/test-projects/.gitignore",
            r"tests\fixtures\test-projects\maxTdb\src\private.pas",
            "TESTS/FIXTURES/TEST-PROJECTS/OtherPrivate/file.txt",
        ]

        self.assertEqual(
            [
                r"tests\fixtures\test-projects\maxTdb\src\private.pas",
                "TESTS/FIXTURES/TEST-PROJECTS/OtherPrivate/file.txt",
            ],
            GUARD.find_blocked_paths(paths),
        )

    def test_staged_mode_reads_real_git_index(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = Path(temp_dir)
            self.run_git(repo, "init")
            private_file = repo / "tests" / "fixtures" / "test-projects" / "secret" / "private.pas"
            private_file.parent.mkdir(parents=True)
            private_file.write_text("unit Private;\n", encoding="utf-8")
            self.run_git(repo, "add", str(private_file.relative_to(repo)))

            result = subprocess.run(
                [sys.executable, str(SCRIPT_PATH), "--staged"],
                cwd=repo,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(1, result.returncode)
            self.assertIn("tests/fixtures/test-projects/secret/private.pas", result.stderr)

    def test_pre_push_mode_reads_real_commit_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo = Path(temp_dir)
            self.run_git(repo, "init")
            self.run_git(repo, "config", "user.name", "Guard Test")
            self.run_git(repo, "config", "user.email", "guard@example.invalid")
            private_file = repo / "tests" / "fixtures" / "test-projects" / "secret" / "private.pas"
            private_file.parent.mkdir(parents=True)
            private_file.write_text("unit Private;\n", encoding="utf-8")
            self.run_git(repo, "add", str(private_file.relative_to(repo)))
            self.run_git(repo, "commit", "-m", "fixture")
            commit = self.run_git(repo, "rev-parse", "HEAD").stdout.strip()
            push_input = f"refs/heads/master {commit} refs/heads/master {'0' * 40}\n"

            result = subprocess.run(
                [sys.executable, str(SCRIPT_PATH), "--pre-push"],
                cwd=repo,
                input=push_input,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(1, result.returncode)
            self.assertIn("tests/fixtures/test-projects/secret/private.pas", result.stderr)

    @staticmethod
    def run_git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *args],
            cwd=repo,
            capture_output=True,
            text=True,
            check=True,
        )


if __name__ == "__main__":
    unittest.main()
