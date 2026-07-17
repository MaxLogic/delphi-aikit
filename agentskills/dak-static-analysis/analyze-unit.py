#!/usr/bin/env python3
# Thin wrapper around DelphiAIKit.exe analyze --unit.
# Handles WSL path conversion and prints summary.md when available.

from __future__ import annotations

import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional


def _is_wsl() -> bool:
    return bool(os.environ.get("WSL_DISTRO_NAME")) or ("microsoft" in platform.release().lower())


def _cmd_exe() -> str:
    return "/mnt/c/Windows/System32/cmd.exe" if _is_wsl() else "cmd.exe"


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


def _to_win_arg(p: Path) -> str:
    s = str(p)
    if not _is_wsl():
        return s
    if _looks_like_windows_path(s):
        return s
    return _wslpath_to_windows(p)


def _find_dak_exe(unit_path: Path) -> Path:
    env = os.environ.get("DAK_EXE", "").strip()
    if env:
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

    if _is_wsl():
        try:
            out = subprocess.check_output([_cmd_exe(), "/C", "where", "DelphiAIKit.exe"], text=True, stderr=subprocess.STDOUT)
            for line in (out or "").splitlines():
                s = line.strip()
                if not s:
                    continue
                if _looks_like_windows_path(s):
                    try:
                        p = Path(_wslpath_to_unix(s))
                        if p.exists():
                            return p
                    except Exception:
                        continue
        except Exception:
            pass
    else:
        found = shutil.which("DelphiAIKit.exe")
        if found:
            p = Path(found)
            if p.exists():
                return p

    roots: list[Path] = []

    cwd = Path.cwd()
    roots.append(cwd)
    cwd_root, _ = _find_vcs_root(cwd)
    if cwd_root is not None:
        roots.append(cwd_root)

    target_root, _ = _find_vcs_root(unit_path.parent)
    if target_root is not None:
        roots.append(target_root)

    script_dir = Path(__file__).resolve().parent
    roots.append(script_dir.parent.parent)

    seen: set[str] = set()
    for r in roots:
        rr = str(r.resolve())
        if rr in seen:
            continue
        seen.add(rr)
        cand = r / "bin" / "DelphiAIKit.exe"
        if cand.exists():
            return cand

    raise FileNotFoundError(
        "DelphiAIKit.exe not found. Set DAK_EXE to the full path of DelphiAIKit.exe "
        "or add it to Windows PATH (so `where DelphiAIKit.exe` works)."
    )


def _maybe_add_arg(args: list[str], flag: str, value: Optional[str]) -> None:
    if not value:
        return
    v = value.strip()
    if not v:
        return
    args.extend([flag, v])


def _get_env(name: str, default: str) -> str:
    val = os.environ.get(name, "").strip()
    return val if val else default


def _resolve_out_root(repo_root: Path, unit_path: Path) -> Path:
    raw = os.environ.get("DAK_OUT", "").strip()
    if not raw:
        return unit_path.parent / ".dak" / "_unit" / unit_path.stem
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


def _build_dak_args(
    dak_exe_arg: str,
    unit_path: Path,
    out_root: Path,
    project_context: Optional[Path],
) -> list[str]:
    delphi_ver = _get_env("DAK_DELPHI", "23.0")
    pal_flag = _get_env("DAK_PASCAL_ANALYZER", os.environ.get("DAK_PAL", "").strip() or "true")
    clean_flag = os.environ.get("DAK_CLEAN", "").strip()
    summary_flag = os.environ.get("DAK_WRITE_SUMMARY", "").strip()

    args = [
        dak_exe_arg,
        "analyze",
        "--unit",
        _to_win_arg(unit_path),
        "--delphi",
        delphi_ver,
        "--out",
        _to_win_arg(out_root),
    ]
    if project_context is not None:
        args += [
            "--project-context",
            _to_win_arg(project_context),
            "--platform",
            _get_env("DAK_PLATFORM", "Win64"),
            "--config",
            _get_env("DAK_CONFIG", "Release"),
        ]

    _maybe_add_arg(args, "--fixinsight", "false")
    _maybe_add_arg(args, "--pascal-analyzer", pal_flag)
    _maybe_add_arg(args, "--clean", clean_flag)
    _maybe_add_arg(args, "--write-summary", summary_flag)

    pa_path = os.environ.get("PA_PATH", "").strip()
    pa_args = os.environ.get("PA_ARGS", "").strip()
    if pa_path:
        args += ["--pa-path", _to_win_arg(Path(pa_path))]
    if pa_args:
        args += ["--pa-args", pa_args]
    return args


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        print("Usage: analyze-unit.py <path-to-unit.pas> [project.dproj]", file=sys.stderr)
        return 2

    unit_path = _normalize_input_path(argv[1])
    if not unit_path.is_absolute():
        unit_path = (Path.cwd() / unit_path).resolve()
    else:
        unit_path = unit_path.resolve()
    if not unit_path.exists():
        print(f"ERROR: .pas not found: {unit_path}", file=sys.stderr)
        return 2

    project_context: Optional[Path] = None
    if len(argv) == 3 and argv[2].strip():
        project_context = _normalize_input_path(argv[2])
        if not project_context.is_absolute():
            project_context = (Path.cwd() / project_context).resolve()
        else:
            project_context = project_context.resolve()
        if not project_context.exists():
            print(f"ERROR: .dproj not found: {project_context}", file=sys.stderr)
            return 2

    dak_exe = _find_dak_exe(unit_path)
    dak_exe_arg = _to_win_arg(dak_exe) if _is_wsl() else str(dak_exe)

    out_root = _resolve_out_root(Path.cwd(), unit_path)
    args = _build_dak_args(dak_exe_arg, unit_path, out_root, project_context)

    vcs_root, _ = _find_vcs_root(unit_path.parent)
    work_root = vcs_root if vcs_root is not None else unit_path.parent

    if _is_wsl():
        p = subprocess.run([_cmd_exe(), "/C"] + args, cwd=str(work_root))
    else:
        p = subprocess.run(args, cwd=str(work_root))

    summary_path = out_root / "summary.md"
    if summary_path.exists():
        print(summary_path.read_text(encoding="utf-8", errors="replace"))
    else:
        print(f"Summary not found: {summary_path}", file=sys.stderr)

    gate_pass = True
    if p.returncode == 0 and summary_path.exists():
        from postprocess import run_postprocess

        res = run_postprocess(out_root, title=unit_path.stem)
        gate_pass = bool(res.get("gate_pass", True))
        if not gate_pass:
            print(f"Static analysis gate failed (see: {res.get('delta', '')})", file=sys.stderr)

    if p.returncode != 0:
        return p.returncode
    if not summary_path.exists():
        return 3
    return 0 if gate_pass else 3


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
