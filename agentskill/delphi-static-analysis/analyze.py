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
from typing import Optional


def _is_wsl() -> bool:
    return bool(os.environ.get("WSL_DISTRO_NAME")) or ("microsoft" in platform.release().lower())


def _looks_like_windows_path(s: str) -> bool:
    return bool(re.match(r"^[A-Za-z]:[\\/]", s) or s.startswith("\\\\"))


def _wslpath_to_windows(p: Path) -> str:
    out = subprocess.check_output(["wslpath", "-w", str(p)], text=True).strip()
    if not out:
        raise RuntimeError(f"wslpath returned empty output for: {p}")
    return out


def _wslpath_to_unix(p: str) -> str:
    out = subprocess.check_output(["wslpath", "-u", p], text=True).strip()
    if not out:
        raise RuntimeError(f"wslpath returned empty output for: {p}")
    return out


def _find_vcs_root(start_dir: Path) -> tuple[Optional[Path], str]:
    p = start_dir.resolve()
    while True:
        if (p / ".git").exists():
            return p, "git"
        if (p / ".svn").exists():
            return p, "svn"
        if p.parent == p:
            return None, ""
        p = p.parent


def _ensure_gitignore_has_analysis_root(repo_root: Path) -> None:
    gitignore_path = repo_root / ".gitignore"
    needle_re = re.compile(r"(?m)^[ \t]*_analysis/[ \t]*$")
    try:
        content = gitignore_path.read_text(encoding="utf-8", errors="replace") if gitignore_path.exists() else ""
        if needle_re.search(content):
            return
        if content and not content.endswith("\n"):
            content += "\n"
        content += "_analysis/\n"
        gitignore_path.write_text(content, encoding="utf-8", errors="replace")
    except Exception as e:
        print(f"WARNING: failed to update {gitignore_path}: {e}", file=sys.stderr)


def _to_win_arg(p: Path) -> str:
    s = str(p)
    if not _is_wsl():
        return s
    # Allow passing already-Windows paths via env vars without mangling them.
    if _looks_like_windows_path(s):
        return s
    return _wslpath_to_windows(p)


def _get_env(name: str, default: str) -> str:
    val = os.environ.get(name, "").strip()
    return val if val else default


def _find_dak_exe(repo_root: Path) -> Path:
    env = os.environ.get("DAK_EXE", "").strip()
    if env:
        # In WSL, allow `DAK_EXE=C:\path\DelphiAIKit.exe` and convert for existence/execution.
        candidates: list[Path] = [Path(env)]
        if _is_wsl() and _looks_like_windows_path(env):
            try:
                candidates.append(Path(_wslpath_to_unix(env)))
            except Exception:
                pass
        for p in candidates:
            if p.exists():
                return p
        raise FileNotFoundError(f"DAK_EXE points to missing file: {env}")
    p = repo_root / "bin" / "DelphiAIKit.exe"
    if not p.exists():
        raise FileNotFoundError(f"DelphiAIKit.exe not found at: {p} (set DAK_EXE to override)")
    return p


def _maybe_add_arg(args: list[str], flag: str, value: Optional[str]) -> None:
    if not value:
        return
    v = value.strip()
    if not v:
        return
    args.extend([flag, v])


def _resolve_out_root(repo_root: Path, dproj: Path) -> Path:
    raw = os.environ.get("DAK_OUT", "").strip()
    if not raw:
        vcs_root, vcs = _find_vcs_root(dproj.parent)
        base = vcs_root if vcs_root is not None else dproj.parent
        if vcs == "git":
            _ensure_gitignore_has_analysis_root(base)
        return base / "_analysis" / dproj.stem
    if _is_wsl() and _looks_like_windows_path(raw):
        p = Path(_wslpath_to_unix(raw))
    else:
        p = Path(raw).expanduser()
    if not p.is_absolute():
        p = (Path.cwd() / p).resolve()
    return p


def _normalize_input_path(arg: str) -> Path:
    s = arg.strip()
    if _is_wsl() and _looks_like_windows_path(s):
        return Path(_wslpath_to_unix(s))
    return Path(s).expanduser()


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: analyze.py <path-to-project.dproj>", file=sys.stderr)
        return 2

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent.parent

    dproj = _normalize_input_path(argv[1])
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

    out_root = _resolve_out_root(repo_root, dproj)
    args += ["--out", _to_win_arg(out_root)]

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

    p = subprocess.run(args, cwd=str(repo_root))

    summary_path = out_root / "summary.md"
    if summary_path.exists():
        print(summary_path.read_text(encoding="utf-8", errors="replace"))
    else:
        print(f"Summary not found: {summary_path}", file=sys.stderr)

    gate_pass = True
    if p.returncode == 0 and summary_path.exists():
        try:
            from postprocess import run_postprocess

            res = run_postprocess(out_root, title=dproj.stem)
            gate_pass = bool(res.get("gate_pass", True))
            if not gate_pass:
                print(f"Static analysis gate failed (see: {res.get('delta', '')})", file=sys.stderr)
        except Exception as e:
            print(f"Post-process ERROR: {e}", file=sys.stderr)

    if p.returncode != 0:
        return p.returncode
    return 0 if gate_pass else 3


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
