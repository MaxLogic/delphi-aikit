#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    dak_exe = repo_root / "bin" / "DelphiAIKit.exe"
    if not dak_exe.exists():
        print(f"DelphiAIKit.exe not found: {dak_exe}", file=sys.stderr)
        return 1

    cmd = [str(dak_exe), "lsp", "probe", *sys.argv[1:]]
    completed = subprocess.run(cmd, cwd=str(repo_root))
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
