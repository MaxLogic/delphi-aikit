#!/usr/bin/env python3
# Thin wrapper around DelphiConfigResolver.exe analyze-unit.
# Handles WSL path conversion and prints summary.md when available.

from __future__ import annotations

import os
import platform
import re
import subprocess
import sys
from pathlib import Path


def _is_wsl() -> bool:
    return bool(os.environ.get("WSL_DISTRO_NAME")) or ("microsoft" in platform.release().lower())


def _wslpath_to_windows(p: Path) -> str:
    out = subprocess.check_output(["wslpath", "-w", str(p)], text=True).strip()
    if not out:
        raise RuntimeError(f"wslpath returned empty output for: {p}")
    return out


def _to_win_arg(p: Path) -> str:
    s = str(p)
    if not _is_wsl():
        return s
    if re.match(r"^[A-Za-z]:[\\/]", s) or s.startswith("\\\\"):
        return s
    return _wslpath_to_windows(p)


def _find_dcr_exe(repo_root: Path) -> Path:
    env = os.environ.get("DCR_EXE", "").strip()
    if env:
        p = Path(env)
        if p.exists():
            return p
        raise FileNotFoundError(f"DCR_EXE points to missing file: {p}")
    p = repo_root / "bin" / "DelphiConfigResolver.exe"
    if not p.exists():
        raise FileNotFoundError(f"DelphiConfigResolver.exe not found at: {p} (set DCR_EXE to override)")
    return p


def _maybe_add_arg(args: list[str], flag: str, value: str | None) -> None:
    if not value:
        return
    v = value.strip()
    if not v:
        return
    args.extend([flag, v])


def _resolve_out_root(repo_root: Path, unit_path: Path) -> Path:
    raw = os.environ.get("DCR_OUT", "").strip()
    if not raw:
        return repo_root / "_analysis" / "_unit" / unit_path.stem
    p = Path(raw).expanduser()
    if not p.is_absolute():
        p = (Path.cwd() / p).resolve()
    return p


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: analyze-unit.py <path-to-unit.pas>", file=sys.stderr)
        return 2

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent

    unit_path = Path(argv[1]).expanduser()
    if not unit_path.is_absolute():
        unit_path = (Path.cwd() / unit_path).resolve()
    else:
        unit_path = unit_path.resolve()
    if not unit_path.exists():
        print(f"ERROR: .pas not found: {unit_path}", file=sys.stderr)
        return 2

    dcr_exe = _find_dcr_exe(repo_root)

    pa_path = os.environ.get("PA_PATH", "").strip()
    pa_args = os.environ.get("PA_ARGS", "").strip()
    pal_flag = os.environ.get("DCR_PAL", "").strip()
    clean_flag = os.environ.get("DCR_CLEAN", "").strip()
    summary_flag = os.environ.get("DCR_WRITE_SUMMARY", "").strip()

    args = [
        str(dcr_exe),
        "analyze-unit",
        "--unit",
        _to_win_arg(unit_path),
    ]

    _maybe_add_arg(args, "--pal", pal_flag)
    _maybe_add_arg(args, "--clean", clean_flag)
    _maybe_add_arg(args, "--write-summary", summary_flag)

    if pa_path:
        args += ["--pa-path", _to_win_arg(Path(pa_path))]
    if pa_args:
        args += ["--pa-args", pa_args]

    dcr_out = os.environ.get("DCR_OUT", "").strip()
    if dcr_out:
        out_path = Path(dcr_out).expanduser()
        if not out_path.is_absolute():
            out_path = (Path.cwd() / out_path).resolve()
        args += ["--out", _to_win_arg(out_path)]

    p = subprocess.run(args, cwd=str(repo_root))

    out_root = _resolve_out_root(repo_root, unit_path)
    summary_path = out_root / "summary.md"
    if summary_path.exists():
        print(summary_path.read_text(encoding="utf-8", errors="replace"))
    else:
        print(f"Summary not found: {summary_path}", file=sys.stderr)

    return p.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
