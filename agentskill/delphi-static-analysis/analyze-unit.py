#!/usr/bin/env python3
# Run Peganza PALCMD against a single Delphi unit and store reports
# under ./_analysis/_unit/{unitName}/.
#
# This script intentionally accepts exactly one argument (a .pas path).
# Everything else is configured via environment variables.

from __future__ import annotations

import datetime as _dt
import os
import platform
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Optional


def _is_wsl() -> bool:
    return bool(os.environ.get("WSL_DISTRO_NAME")) or ("microsoft" in platform.release().lower())


def _run_checked(cmd: list[str], log_path: Path, cwd: Path) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write("\n")
        f.write("=" * 78 + "\n")
        f.write(f"[{_dt.datetime.now().isoformat(timespec='seconds')}] RUN\n")
        f.write("CWD: " + str(cwd) + "\n")
        f.write("CMD: " + " ".join(cmd) + "\n")
        f.flush()
        p = subprocess.run(cmd, cwd=str(cwd), stdout=f, stderr=subprocess.STDOUT, text=True)
        if p.returncode != 0:
            raise RuntimeError(f"Command failed (exit={p.returncode}): {' '.join(cmd)}")


def _wslpath_to_windows(p: Path) -> str:
    out = subprocess.check_output(["wslpath", "-w", str(p)], text=True).strip()
    if not out:
        raise RuntimeError(f"wslpath returned empty output for: {p}")
    return out


def _to_win_arg(p: Path) -> str:
    s = str(p)
    if not _is_wsl():
        return s
    # In WSL, allow passing already-Windows paths via env vars without mangling them.
    if re.match(r"^[A-Za-z]:[\\/]", s) or s.startswith("\\\\"):
        return s
    return _wslpath_to_windows(p)


def _locate_palcmd() -> Path:
    # Prefer explicit override.
    env = os.environ.get("PA_PATH", "").strip()
    if env:
        p = Path(env)
        if p.exists():
            return p
        raise FileNotFoundError(f"PA_PATH points to missing file: {p}")

    # Best-effort discovery (same roots we use in DCR, but simplified).
    roots: list[Path] = []
    if _is_wsl():
        roots = [
            Path("/mnt/c/Program Files/Peganza"),
            Path("/mnt/c/Program Files (x86)/Peganza"),
        ]
    else:
        roots = [
            Path(r"C:\Program Files\Peganza"),
            Path(r"C:\Program Files (x86)\Peganza"),
        ]

    candidates: list[Path] = []
    # Common default first (v9).
    for r in roots:
        candidates.append(r / "Pascal Analyzer 9" / "palcmd.exe")
        candidates.append(r / "Pascal Analyzer 9" / "palcmd32.exe")

    # Version sweep.
    for r in roots:
        for n in range(5, 21):
            candidates.append(r / f"Pascal Analyzer {n}" / "palcmd.exe")
            candidates.append(r / f"Pascal Analyzer {n}" / "palcmd32.exe")

    # Directory scan under Peganza root.
    for r in roots:
        if not r.exists():
            continue
        for d in sorted(r.glob("Pascal Analyzer*")):
            candidates.append(d / "palcmd.exe")
            candidates.append(d / "palcmd32.exe")

    for c in candidates:
        if c.exists():
            return c

    raise FileNotFoundError('PALCMD not found. Set PA_PATH="...\\\\palcmd.exe" (or palcmd32.exe).')


def _find_report_root(pa_dir: Path) -> Optional[Path]:
    for p in pa_dir.rglob("Status.xml"):
        return p.parent
    return None


def _extract_text(root: ET.Element, path: str) -> str:
    el = root.find(path)
    if el is None or el.text is None:
        return ""
    return el.text.strip()


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

    palcmd = _locate_palcmd()

    out_root = repo_root / "_analysis" / "_unit" / unit_path.stem
    pa_dir = out_root / "pascal-analyzer"
    pa_dir.mkdir(parents=True, exist_ok=True)

    run_log = out_root / "run.log"

    # Defaults (can be overridden via env var PA_ARGS; keep 1-arg CLI contract).
    pa_args = os.environ.get("PA_ARGS", "").strip()
    if not pa_args:
        # Sensible defaults for automation (quiet, XML, parse source+dfm, main+direct uses).
        pa_args = "/F=X /Q /A+ /FR /T=8"

    # PALCMD accepts: PALCMD projectpath|sourcepath [options]
    cmd = [
        str(palcmd),
        _to_win_arg(unit_path),
        "/R=" + _to_win_arg(pa_dir),
    ]
    # Split the option string into args (PALCMD expects each option as a token).
    cmd += pa_args.split()

    _run_checked(cmd, log_path=run_log, cwd=repo_root)

    # Write a tiny summary for convenience.
    summary_path = out_root / "summary.md"
    report_root = _find_report_root(pa_dir)
    pa_ver = ""
    pa_compiler = ""
    if report_root is not None and (report_root / "Status.xml").exists():
        try:
            st_root = ET.parse(report_root / "Status.xml").getroot()
            pa_ver = _extract_text(st_root, "./section[@name='Overview']/version")
            pa_compiler = _extract_text(st_root, "./section[@name='Overview']/compiler")
        except Exception:
            pass

    lines: list[str] = []
    lines.append(f"# Pascal Analyzer unit summary: {unit_path.stem}")
    lines.append("")
    lines.append(f"- Timestamp: {_dt.datetime.now().isoformat(timespec='seconds')}")
    lines.append(f"- Unit: `{unit_path}`")
    lines.append(f"- Output: `{out_root}`")
    lines.append(f"- PALCMD: `{palcmd}`")
    if pa_ver:
        lines.append(f"- PAL version: {pa_ver}")
    if pa_compiler:
        lines.append(f"- Compiler target: {pa_compiler}")
    if report_root is not None:
        lines.append(f"- Report folder: `{report_root}`")
    lines.append("")
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
