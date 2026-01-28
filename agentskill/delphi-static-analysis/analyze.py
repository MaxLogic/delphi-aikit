#!/usr/bin/env python3
# Run FixInsightCL and PALCMD via DelphiConfigResolver.exe and store reports
# in a stable ./_analysis/{projectName}/ folder tree.
#
# This script intentionally accepts exactly one argument (a .dproj path).
# Everything else is configured via environment variables.

from __future__ import annotations

import datetime as _dt
import os
import platform
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from typing import Iterable, Optional


def _is_wsl() -> bool:
    return bool(os.environ.get("WSL_DISTRO_NAME")) or ("microsoft" in platform.release().lower())


def _run(cmd: list[str], log_path: Path, cwd: Path) -> int:
    """Run a command and append stdout/stderr to log_path; return exit code."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8") as f:
        f.write("\n")
        f.write("=" * 78 + "\n")
        f.write(f"[{_dt.datetime.now().isoformat(timespec='seconds')}] RUN\n")
        f.write("CWD: " + str(cwd) + "\n")
        f.write("CMD: " + " ".join(cmd) + "\n")
        f.flush()
        p = subprocess.run(cmd, cwd=str(cwd), stdout=f, stderr=subprocess.STDOUT, text=True)
        return p.returncode


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


def _get_env(name: str, default: str) -> str:
    val = os.environ.get(name, "").strip()
    return val if val else default


def _maybe_add_arg(args: list[str], flag: str, value: Optional[str]) -> None:
    if value is None:
        return
    v = value.strip()
    if not v:
        return
    args.extend([flag, v])


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


def _parse_fi_formats(raw: str) -> list[str]:
    val = raw.strip().lower()
    if not val:
        return ["txt"]
    if val == "all":
        return ["txt", "xml", "csv"]
    parts = re.split(r"[,\s;]+", val)
    result = []
    for p in parts:
        if not p:
            continue
        if p not in {"txt", "xml", "csv"}:
            raise ValueError(f"Unsupported DCR_FI_FORMATS value: '{p}'. Use txt, xml, csv, or all.")
        if p not in result:
            result.append(p)
    return result if result else ["txt"]


def _count_fixinsight_codes(txt_path: Path) -> Counter[str]:
    c = Counter()
    if not txt_path.exists():
        return c
    rx = re.compile(r"^\s*([A-Z]\d{3})\b")
    for line in txt_path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        m = rx.match(line)
        if m:
            c[m.group(1)] += 1
    return c


def _find_pa_report_root(pa_dir: Path) -> Optional[Path]:
    # PALCMD (via /R) typically creates a subfolder. Locate it by Status.xml.
    for p in pa_dir.rglob("Status.xml"):
        return p.parent
    return None


def _pa_report_totals(report_path: Path) -> int:
    try:
        root = ET.parse(report_path).getroot()
    except Exception:
        return 0
    total = 0
    for sec in root.findall(".//section"):
        c = sec.get("count")
        if not c:
            continue
        try:
            total += int(c)
        except ValueError:
            pass
    return total


def _extract_text(root: ET.Element, path: str) -> str:
    el = root.find(path)
    if el is None or el.text is None:
        return ""
    return el.text.strip()


def _write_summary(
    out_root: Path,
    dproj: Path,
    fi_txt: Path,
    fi_outputs: dict[str, Path],
    fi_exit_codes: dict[str, int],
    pa_dir: Path,
    pa_rc: int,
    errors: list[str],
) -> None:
    summary_path = out_root / "summary.md"

    fi_codes = _count_fixinsight_codes(fi_txt)
    fi_total = sum(fi_codes.values())
    fi_top = fi_codes.most_common(10)

    pa_root = _find_pa_report_root(pa_dir)
    pa_ver = ""
    pa_compiler = ""
    pa_warn_total = 0
    pa_strong_total = 0
    pa_exc_total = 0
    if pa_root is not None and (pa_root / "Status.xml").exists():
        try:
            st_root = ET.parse(pa_root / "Status.xml").getroot()
            pa_ver = _extract_text(st_root, "./section[@name='Overview']/version")
            pa_compiler = _extract_text(st_root, "./section[@name='Overview']/compiler")
        except Exception:
            pass
        pa_warn_total = _pa_report_totals(pa_root / "Warnings.xml")
        pa_strong_total = _pa_report_totals(pa_root / "Strong Warnings.xml")
        pa_exc_total = _pa_report_totals(pa_root / "Exception.xml")

    lines: list[str] = []
    lines.append(f"# Static analysis summary: {dproj.stem}")
    lines.append("")
    lines.append(f"- Timestamp: {_dt.datetime.now().isoformat(timespec='seconds')}")
    lines.append(f"- Project: `{dproj}`")
    lines.append(f"- Outputs: `{out_root}`")
    lines.append("")

    lines.append("## FixInsight")
    lines.append("")
    if fi_outputs:
        outputs = ", ".join(f"`{p}`" for p in fi_outputs.values())
        lines.append(f"- Report files: {outputs}")
    else:
        lines.append("- Report files: (none)")

    if fi_exit_codes:
        codes = ", ".join(f"{k}={v}" for k, v in fi_exit_codes.items())
        lines.append(f"- Exit codes: {codes}")
    else:
        lines.append("- Exit codes: (none)")

    missing = [name for name, path in fi_outputs.items() if not path.exists()]
    if missing:
        missing_str = ", ".join(missing)
        lines.append(f"- Note: some outputs are missing ({missing_str}); see run.log and per-run *.log files.")

    if fi_txt.exists():
        lines.append(f"- Findings (by code): {fi_total}")
    else:
        lines.append("- Findings (by code): (TXT not generated)")
    if fi_top:
        lines.append("- Top codes:")
        for code, count in fi_top:
            lines.append(f"  - {code}: {count}")
    lines.append("")

    lines.append("## Pascal Analyzer")
    lines.append("")
    lines.append(f"- Output root: `{pa_dir}`")
    lines.append(f"- Exit code: {pa_rc}")
    if pa_root is not None:
        lines.append(f"- Report folder: `{pa_root}`")
    if pa_ver:
        lines.append(f"- Version: {pa_ver}")
    if pa_compiler:
        lines.append(f"- Compiler target: {pa_compiler}")
    lines.append(f"- Totals: warnings={pa_warn_total}, strong_warnings={pa_strong_total}, exceptions={pa_exc_total}")
    lines.append("")

    if errors:
        lines.append("## Errors")
        lines.append("")
        for e in errors:
            lines.append(f"- {e}")
        lines.append("")

    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


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

    dcr_exe = _find_dcr_exe(repo_root)

    out_root = repo_root / "_analysis" / dproj.stem
    fi_dir = out_root / "fixinsight"
    pa_dir = out_root / "pascal-analyzer"
    out_root.mkdir(parents=True, exist_ok=True)
    if fi_dir.exists():
        shutil.rmtree(fi_dir)
    if pa_dir.exists():
        shutil.rmtree(pa_dir)
    fi_dir.mkdir(parents=True, exist_ok=True)
    pa_dir.mkdir(parents=True, exist_ok=True)

    run_log = out_root / "run.log"
    run_log.write_text("", encoding="utf-8")

    platform_name = _get_env("DCR_PLATFORM", "Win32")
    config_name = _get_env("DCR_CONFIG", "Release")
    delphi_ver = _get_env("DCR_DELPHI", "23.0")  # Delphi 12 Athens = 23.0

    # Optional report filters (kept off by default; provided via env vars only).
    exclude_masks = os.environ.get("DCR_EXCLUDE_PATH_MASKS", "").strip()
    ignore_rule_ids = os.environ.get("DCR_IGNORE_WARNING_IDS", "").strip()

    dcr_rsvars = os.environ.get("DCR_RSVARS", "").strip()
    dcr_envoptions = os.environ.get("DCR_ENVOPTIONS", "").strip()

    pa_path = os.environ.get("PA_PATH", "").strip()
    pa_args = os.environ.get("PA_ARGS", "").strip()
    fi_settings = (os.environ.get("FIXINSIGHT_SETTINGS", "").strip() or os.environ.get("FI_SETTINGS", "").strip())

    common = [
        str(dcr_exe),
        "--dproj",
        _to_win_arg(dproj),
        "--platform",
        platform_name,
        "--config",
        config_name,
        "--delphi",
        delphi_ver,
        "--log-tee",
        "false",
        "--verbose",
        "false",
    ]
    if dcr_rsvars:
        common += ["--rsvars", _to_win_arg(Path(dcr_rsvars))]
    if dcr_envoptions:
        common += ["--envoptions", _to_win_arg(Path(dcr_envoptions))]
    if exclude_masks:
        common += ["--exclude-path-masks", exclude_masks]
    if ignore_rule_ids:
        common += ["--ignore-warning-ids", ignore_rule_ids]

    # FixInsight (default: TXT only; override via DCR_FI_FORMATS)
    fi_formats = _parse_fi_formats(os.environ.get("DCR_FI_FORMATS", ""))
    fi_txt = fi_dir / "fixinsight.txt"
    fi_xml = fi_dir / "fixinsight.xml"
    fi_csv = fi_dir / "fixinsight.csv"

    errors: list[str] = []
    fi_base = common + ["--run-fixinsight"]
    if fi_settings:
        fi_base += ["--settings", _to_win_arg(Path(fi_settings))]

    fi_outputs: dict[str, Path] = {}
    fi_exit_codes: dict[str, int] = {}

    if "txt" in fi_formats:
        fi_outputs["txt"] = fi_txt
        fi_rc_txt = _run(
            fi_base
            + ["--logfile", _to_win_arg(fi_dir / "fixinsight.txt.log"), "--output", _to_win_arg(fi_txt)],
            log_path=run_log,
            cwd=repo_root,
        )
        fi_exit_codes["txt"] = fi_rc_txt
        if fi_rc_txt != 0:
            errors.append(f"FixInsight TXT failed (exit={fi_rc_txt}).")

    if "xml" in fi_formats:
        fi_outputs["xml"] = fi_xml
        fi_rc_xml = _run(
            fi_base
            + ["--xml", "true", "--logfile", _to_win_arg(fi_dir / "fixinsight.xml.log"), "--output", _to_win_arg(fi_xml)],
            log_path=run_log,
            cwd=repo_root,
        )
        fi_exit_codes["xml"] = fi_rc_xml
        if fi_rc_xml != 0:
            errors.append(f"FixInsight XML failed (exit={fi_rc_xml}).")

    if "csv" in fi_formats:
        fi_outputs["csv"] = fi_csv
        fi_rc_csv = _run(
            fi_base
            + ["--csv", "true", "--logfile", _to_win_arg(fi_dir / "fixinsight.csv.log"), "--output", _to_win_arg(fi_csv)],
            log_path=run_log,
            cwd=repo_root,
        )
        fi_exit_codes["csv"] = fi_rc_csv
        if fi_rc_csv != 0:
            errors.append(f"FixInsight CSV failed (exit={fi_rc_csv}).")

    # Pascal Analyzer (project-level) via DCR
    pa_log = pa_dir / "pascal-analyzer.log"
    pa_cmd = common + ["--run-pascal-analyzer", "--logfile", _to_win_arg(pa_log), "--pa-output", _to_win_arg(pa_dir)]
    if pa_path:
        pa_cmd += ["--pa-path", _to_win_arg(Path(pa_path))]
    if pa_args:
        # Pass verbatim; PALCMD uses spaces within the arg string.
        pa_cmd += ["--pa-args", pa_args]
    pa_rc = _run(pa_cmd, log_path=run_log, cwd=repo_root)
    if pa_rc != 0:
        errors.append(f"Pascal Analyzer failed (exit={pa_rc}).")

    _write_summary(out_root, dproj, fi_txt, fi_outputs, fi_exit_codes, pa_dir, pa_rc, errors)

    # Keep reports even on failures; still return non-zero so CI can detect tool crashes.
    return 0 if not errors else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        raise
