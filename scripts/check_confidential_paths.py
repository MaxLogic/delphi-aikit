#!/usr/bin/env python3
"""Reject repository paths reserved for local confidential fixtures."""

from __future__ import annotations

import sys
import subprocess
from collections.abc import Iterable


CONFIDENTIAL_ROOT = "tests/fixtures/test-projects/"
ALLOWED_PATH = CONFIDENTIAL_ROOT + ".gitignore"


def normalize_path(path: str) -> str:
    normalized = path.strip().replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized.lstrip("/")


def find_blocked_paths(paths: Iterable[str]) -> list[str]:
    blocked: list[str] = []
    for path in paths:
        original = path.strip()
        normalized = normalize_path(original).casefold()
        if normalized.startswith(CONFIDENTIAL_ROOT) and normalized != ALLOWED_PATH:
            blocked.append(original)
    return blocked


def staged_paths() -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.splitlines()


def pushed_paths(lines: Iterable[str]) -> list[str]:
    paths: list[str] = []
    for line in lines:
        fields = line.split()
        if len(fields) < 2:
            continue
        commit = fields[1]
        if not commit or set(commit) == {"0"}:
            continue
        result = subprocess.run(
            ["git", "ls-tree", "-r", "--name-only", commit],
            capture_output=True,
            text=True,
            check=True,
        )
        paths.extend(result.stdout.splitlines())
    return paths


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    try:
        if args == ["--staged"]:
            paths = staged_paths()
        elif args == ["--pre-push"]:
            paths = pushed_paths(sys.stdin)
        elif args:
            print("usage: check_confidential_paths.py [--staged|--pre-push]", file=sys.stderr)
            return 2
        else:
            paths = sys.stdin
        blocked = find_blocked_paths(paths)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"confidential-path guard failed closed: {error}", file=sys.stderr)
        return 2

    if not blocked:
        return 0

    print("Blocked confidential paths:", file=sys.stderr)
    for path in blocked:
        print(f"  {path}", file=sys.stderr)
    print(
        f"Keep private fixtures outside this repository; only {ALLOWED_PATH} is allowed.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
