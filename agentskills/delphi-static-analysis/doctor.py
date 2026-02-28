#!/usr/bin/env python3
# Environment "doctor" for the Delphi static analysis skill.
#
# Goal: fail fast on predictable setup issues and print enough context to make
# static analysis runs repeatable (especially in CI).

from __future__ import annotations

import configparser
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
    # In some restricted WSL environments, executing `cmd.exe` via PATH is blocked, while
    # invoking it by absolute path remains allowed.
    return "/mnt/c/Windows/System32/cmd.exe" if _is_wsl() else "cmd.exe"


def _looks_like_windows_path(s: str) -> bool:
    return bool(re.match(r"^[A-Za-z]:[\\/]", s) or s.startswith("\\\\"))


def _run_capture(cmd: list[str]) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False)
        return p.returncode, (p.stdout or "").strip()
    except Exception as e:
        return 127, f"{type(e).__name__}: {e}"


def _wslpath_to_unix(p: str) -> str:
    code, out = _run_capture(["wslpath", "-u", p])
    if code != 0 or not out:
        raise RuntimeError(f"wslpath -u failed for {p!r}: {out}")
    return out


def _normalize_input_path(arg: str) -> Path:
    s = arg.strip()
    if _is_wsl() and _looks_like_windows_path(s):
        return Path(_wslpath_to_unix(s))
    return Path(s).expanduser()


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


def _find_dak_exe(target_dir: Path) -> Path:
    env = os.environ.get("DAK_EXE", "").strip()
    if env:
        candidates: list[Path] = [_normalize_input_path(env)]
        for p in candidates:
            if p.exists():
                return p.resolve()
        raise FileNotFoundError(f"DAK_EXE points to missing file: {env}")

    if _is_wsl():
        code, out = _run_capture([_cmd_exe(), "/C", "where", "DelphiAIKit.exe"])
        if code == 0 and out:
            for line in out.splitlines():
                s = line.strip()
                if not s:
                    continue
                if not _looks_like_windows_path(s):
                    continue
                try:
                    p = Path(_wslpath_to_unix(s))
                    if p.exists():
                        return p.resolve()
                except Exception:
                    continue
    else:
        found = shutil.which("DelphiAIKit.exe")
        if found:
            p = Path(found)
            if p.exists():
                return p.resolve()

    roots: list[Path] = []

    cwd = Path.cwd()
    roots.append(cwd)
    cwd_root, _ = _find_vcs_root(cwd)
    if cwd_root is not None:
        roots.append(cwd_root)

    roots.append(target_dir)
    tgt_root, _ = _find_vcs_root(target_dir)
    if tgt_root is not None:
        roots.append(tgt_root)

    # Back-compat when the skill lives inside a tooling repo.
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
            return cand.resolve()

    raise FileNotFoundError(
        "DelphiAIKit.exe not found. Set DAK_EXE to the full path of DelphiAIKit.exe "
        "or add it to Windows PATH (so `where DelphiAIKit.exe` works)."
    )


def _load_ini(path: Path) -> configparser.ConfigParser:
    cp = configparser.ConfigParser()
    cp.read(path, encoding="utf-8")
    return cp


def _fmt_kv(k: str, v: str) -> str:
    v = (v or "").strip()
    return f"{k}={v if v else '<empty>'}"


def main(argv: list[str]) -> int:
    script_dir = Path(__file__).resolve().parent
    target_dir = Path.cwd()
    target = None
    if len(argv) >= 2:
        target = _normalize_input_path(argv[1])
        if not target.is_absolute():
            target = (Path.cwd() / target).resolve()
        target_dir = target.parent

    print("# Delphi static analysis doctor")
    print()
    print(f"- Python: {sys.version.split()[0]}")
    print(f"- Platform: {platform.platform()}")
    print(f"- WSL: {_is_wsl()}")
    print(f"- Skill dir: {script_dir}")
    print(f"- CWD: {Path.cwd()}")

    if _is_wsl():
        code, out = _run_capture(["wslpath", "-u", "C:\\"])
        print(f"- wslpath: {'ok' if code == 0 else 'missing/failed'}")

    try:
        dak_exe = _find_dak_exe(target_dir)
    except Exception as e:
        print()
        print(f"ERROR: {e}")
        return 2

    dak_dir = dak_exe.parent
    dak_ini = dak_dir / "dak.ini"

    print()
    print("## Resolver")
    print(f"- DAK_EXE: {os.environ.get('DAK_EXE','').strip() or '<default>'}")
    print(f"- DelphiAIKit.exe: {dak_exe}")
    print(f"- dak.ini: {dak_ini if dak_ini.exists() else '<missing>'}")

    if dak_ini.exists():
        ini = _load_ini(dak_ini)
        print()
        print("## dak.ini (high-signal)")
        fi = ini["FixInsightCL"] if ini.has_section("FixInsightCL") else {}
        print(f"- FixInsightCL.{_fmt_kv('Silent', fi.get('Silent', ''))}")
        print(f"- FixInsightCL.{_fmt_kv('Settings', fi.get('Settings', ''))}")
        filt = ini["ReportFilter"] if ini.has_section("ReportFilter") else {}
        print(f"- ReportFilter.{_fmt_kv('ExcludePathMasks', filt.get('ExcludePathMasks', ''))}")
        ign = ini["FixInsightIgnore"] if ini.has_section("FixInsightIgnore") else {}
        print(f"- FixInsightIgnore.{_fmt_kv('Warnings', ign.get('Warnings', ''))}")
        pa = ini["PascalAnalyzer"] if ini.has_section("PascalAnalyzer") else {}
        print(f"- PascalAnalyzer.{_fmt_kv('Path', pa.get('Path', ''))}")
        print(f"- PascalAnalyzer.{_fmt_kv('Args', pa.get('Args', ''))}")

        diag = ini["Diagnostics"] if ini.has_section("Diagnostics") else {}
        if diag:
            print(f"- Diagnostics.{_fmt_kv('IgnoreUnknownMacros', diag.get('IgnoreUnknownMacros', ''))}")
            print(f"- Diagnostics.{_fmt_kv('IgnoreMissingPaths', diag.get('IgnoreMissingPaths', ''))}")

        pa_path = (pa.get("Path", "") or "").strip()
        if pa_path:
            try:
                p = _normalize_input_path(pa_path)
                exists = p.exists()
                print(f"- PascalAnalyzer.Path exists: {exists} ({p})")
            except Exception as e:
                print(f"- PascalAnalyzer.Path exists: error ({e})")

    print()
    print("## Run options (env)")
    for k in (
        "DAK_DELPHI",
        "DAK_PLATFORM",
        "DAK_CONFIG",
        "DAK_FI_FORMATS",
        "DAK_FIXINSIGHT",
        "DAK_PASCAL_ANALYZER",
        "DAK_PAL",
        "DAK_EXCLUDE_PATH_MASKS",
        "DAK_IGNORE_WARNING_IDS",
        "DAK_OUT",
        "DAK_CLEAN",
        "DAK_WRITE_SUMMARY",
        "DAK_BASELINE",
        "DAK_UPDATE_BASELINE",
        "DAK_GATE",
        "DAK_CI",
    ):
        v = os.environ.get(k, "").strip()
        if not v:
            continue
        print(f"- {k}={v}")

    if target is not None:
        print()
        print("## Target")
        print(f"- Path: {target}")
        print(f"- Exists: {target.exists()}")
        # Mirror analyze.py default out-root mapping.
        out_raw = os.environ.get("DAK_OUT", "").strip()
        if out_raw:
            out_root = _normalize_input_path(out_raw)
            if not out_root.is_absolute():
                out_root = (Path.cwd() / out_root).resolve()
        else:
            vcs_root, _ = _find_vcs_root(target.parent)
            base = vcs_root if vcs_root is not None else target.parent
            if target.suffix.lower() == ".pas":
                out_root = base / "_analysis" / "_unit" / target.stem
            else:
                out_root = base / "_analysis" / target.stem
        print(f"- Output root: {out_root}")
        print("- Parity check: after a run, inspect `run.log` for FixInsightCL args (`--libpath`, `--unitscopes`).")

    # Optional tool discovery checks that require running Windows commands from WSL.
    if os.environ.get("DAK_DOCTOR_RUN", "").strip():
        print()
        print("## Optional discovery checks (DAK_DOCTOR_RUN)")
        if _is_wsl():
            code, out = _run_capture([_cmd_exe(), "/C", "where", "FixInsightCL.exe"])
            print(f"- where FixInsightCL.exe: exit={code} {out}")
            code, out = _run_capture([_cmd_exe(), "/C", "where", "PALCMD.exe"])
            print(f"- where PALCMD.exe: exit={code} {out}")
        else:
            code, out = _run_capture(["where", "FixInsightCL.exe"])
            print(f"- where FixInsightCL.exe: exit={code} {out}")
            code, out = _run_capture(["where", "PALCMD.exe"])
            print(f"- where PALCMD.exe: exit={code} {out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
