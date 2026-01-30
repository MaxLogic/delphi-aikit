#!/usr/bin/env python3
# Thin wrapper around DelphiAIKit.exe analyze.
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
    # Allow passing already-Windows paths via env vars without mangling them.
    if re.match(r"^[A-Za-z]:[\\/]", s) or s.startswith("\\\\"):
        return s
    return _wslpath_to_windows(p)


def _get_env(name: str, default: str) -> str:
    val = os.environ.get(name, "").strip()
    return val if val else default


def _find_dak_exe(repo_root: Path) -> Path:
    env = os.environ.get("DAK_EXE", "").strip()
    if env:
        p = Path(env)
        if p.exists():
            return p
        raise FileNotFoundError(f"DAK_EXE points to missing file: {p}")
    p = repo_root / "bin" / "DelphiAIKit.exe"
    if not p.exists():
        raise FileNotFoundError(f"DelphiAIKit.exe not found at: {p} (set DAK_EXE to override)")
    return p


def _maybe_add_arg(args: list[str], flag: str, value: str | None) -> None:
    if not value:
        return
    v = value.strip()
    if not v:
        return
    args.extend([flag, v])


def _resolve_out_root(repo_root: Path, dproj: Path) -> Path:
    raw = os.environ.get("DAK_OUT", "").strip()
    if not raw:
        return repo_root / "_analysis" / dproj.stem
    p = Path(raw).expanduser()
    if not p.is_absolute():
        p = (Path.cwd() / p).resolve()
    return p


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: analyze.py <path-to-project.dproj>", file=sys.stderr)
        return 2

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent

    dproj = Path(argv[1]).expanduser()
    if not dproj.is_absolute():
        dproj = (Path.cwd() / dproj).resolve()
    else:
        dproj = dproj.resolve()
    if not dproj.exists():
        print(f"ERROR: .dproj not found: {dproj}", file=sys.stderr)
        return 2

    dak_exe = _find_dak_exe(repo_root)

    platform_name = _get_env("DAK_PLATFORM", "Win32")
    config_name = _get_env("DAK_CONFIG", "Release")
    delphi_ver = _get_env("DAK_DELPHI", "23.0")

    dak_rsvars = os.environ.get("DAK_RSVARS", "").strip()
    dak_envoptions = os.environ.get("DAK_ENVOPTIONS", "").strip()
    fi_formats = os.environ.get("DAK_FI_FORMATS", "").strip()
    exclude_masks = os.environ.get("DAK_EXCLUDE_PATH_MASKS", "").strip()
    ignore_rule_ids = os.environ.get("DAK_IGNORE_WARNING_IDS", "").strip()
    fi_settings = (os.environ.get("FIXINSIGHT_SETTINGS", "").strip() or os.environ.get("FI_SETTINGS", "").strip())
    pa_path = os.environ.get("PA_PATH", "").strip()
    pa_args = os.environ.get("PA_ARGS", "").strip()
    fixinsight_flag = os.environ.get("DAK_FIXINSIGHT", "").strip()
    pal_flag = _get_env("DAK_PASCAL_ANALYZER", os.environ.get("DAK_PAL", "").strip())
    clean_flag = os.environ.get("DAK_CLEAN", "").strip()
    summary_flag = os.environ.get("DAK_WRITE_SUMMARY", "").strip()

    args = [
        str(dak_exe),
        "analyze",
        "--project",
        _to_win_arg(dproj),
        "--platform",
        platform_name,
        "--config",
        config_name,
        "--delphi",
        delphi_ver,
    ]

    if fi_formats:
        args += ["--fi-formats", fi_formats]
    _maybe_add_arg(args, "--fixinsight", fixinsight_flag)
    _maybe_add_arg(args, "--pascal-analyzer", pal_flag)
    _maybe_add_arg(args, "--clean", clean_flag)
    _maybe_add_arg(args, "--write-summary", summary_flag)

    if dak_rsvars:
        args += ["--rsvars", _to_win_arg(Path(dak_rsvars))]
    if dak_envoptions:
        args += ["--envoptions", _to_win_arg(Path(dak_envoptions))]
    if exclude_masks:
        args += ["--exclude-path-masks", exclude_masks]
    if ignore_rule_ids:
        args += ["--ignore-warning-ids", ignore_rule_ids]
    if fi_settings:
        args += ["--fi-settings", _to_win_arg(Path(fi_settings))]
    if pa_path:
        args += ["--pa-path", _to_win_arg(Path(pa_path))]
    if pa_args:
        args += ["--pa-args", pa_args]

    dak_out = os.environ.get("DAK_OUT", "").strip()
    if dak_out:
        out_path = Path(dak_out).expanduser()
        if not out_path.is_absolute():
            out_path = (Path.cwd() / out_path).resolve()
        args += ["--out", _to_win_arg(out_path)]

    p = subprocess.run(args, cwd=str(repo_root))

    out_root = _resolve_out_root(repo_root, dproj)
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
