#!/usr/bin/env python3
# Post-process analysis outputs produced by DelphiAIKit.exe.
# - Normalizes FixInsight TXT report into JSONL/MD (for greppable triage + deltas).
# - Maintains a per-output-root baseline snapshot and produces delta reports.
#
# This file is intentionally dependency-free (stdlib only) so it runs on both
# Windows and WSL without extra installs.

from __future__ import annotations

import hashlib
import fnmatch
import json
import os
import platform
import posixpath
import re
import shutil
import subprocess
import sys
import tempfile
import traceback
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional
from xml.etree import ElementTree

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from workspace import delphi_source_files


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _truthy_env(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return default
    return raw in ("1", "true", "yes", "y", "on")


def _int_env(name: str, default: Optional[int]) -> Optional[int]:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        raise ValueError(f"{name} must be an integer, got: {raw!r}")


def _split_semicolon_patterns(raw: str) -> list[str]:
    parts: list[str] = []
    for item in raw.split(";"):
        s = item.strip()
        if not s:
            continue
        parts.append(s.replace("\\", "/").lower())
    return parts


def _triage_path_allowed(path: str, *, include: list[str], exclude: list[str]) -> bool:
    p = (path or "").strip().replace("\\", "/").lower()
    if not p:
        return not include
    if include:
        if not any(fnmatch.fnmatch(p, pat) for pat in include):
            return False
    if exclude:
        if any(fnmatch.fnmatch(p, pat) for pat in exclude):
            return False
    return True


def _sha1(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8", errors="replace")).hexdigest()


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="replace")).hexdigest()


def _read_text(path: Path) -> str:
    # FixInsight TXT often has a UTF-8 BOM; utf-8-sig strips it.
    return path.read_text(encoding="utf-8-sig", errors="replace")


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", errors="replace")


def _write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temp_path.write_text(
            json.dumps(obj, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        os.replace(temp_path, path)
    finally:
        temp_path.unlink(missing_ok=True)


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _record_postprocessor_failure(out_root: Path, error: Exception) -> Path:
    diagnostic_path = out_root / "postprocessor-error.txt"
    _write_text(diagnostic_path, traceback.format_exc())
    summary_path = out_root / "summary.json"
    try:
        summary = _load_json(summary_path)
    except (OSError, ValueError, json.JSONDecodeError):
        return diagnostic_path
    if not isinstance(summary, dict):
        return diagnostic_path
    status = summary.setdefault("status", {})
    if isinstance(status, dict):
        status["postprocessor"] = "failed"
        status["finalization"] = "incomplete"
    errors = summary.setdefault("errors", [])
    if isinstance(errors, list):
        errors.append(f"Postprocessor failed: {error}")
    artifacts = summary.setdefault("artifacts", {})
    if isinstance(artifacts, dict):
        artifacts["postprocessor_diagnostic"] = diagnostic_path.name
    _write_json(summary_path, summary)
    return diagnostic_path


def _iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(
                    f"Malformed JSONL in {path} at line {line_number}: {exc.msg}"
                ) from exc


def _record_is_actionable(obj: dict[str, Any]) -> bool:
    projection = obj.get("report_projection")
    if isinstance(projection, str):
        return projection == "actionable"
    policy = obj.get("report_policy")
    return not (
        isinstance(policy, dict) and policy.get("disposition") == "ignored"
    )


def _iter_actionable_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    for obj in _iter_jsonl(path):
        if _record_is_actionable(obj):
            yield obj


def _write_jsonl(path: Path, items: Iterable[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for obj in items:
            f.write(json.dumps(obj, ensure_ascii=True) + "\n")


def _slug_id(text: str, *, max_len: int = 64) -> str:
    s = (text or "").strip().lower()
    if not s:
        return "unknown"
    out: list[str] = []
    last_dash = False
    for ch in s:
        is_alnum = ("a" <= ch <= "z") or ("0" <= ch <= "9")
        if is_alnum:
            out.append(ch)
            last_dash = False
            continue
        if last_dash:
            continue
        out.append("-")
        last_dash = True
    slug = "".join(out).strip("-")
    if not slug:
        return "unknown"
    return slug[:max_len]


def _sarif_level_for_fixinsight_kind(kind: str) -> str:
    k = (kind or "").strip().upper()
    if k == "W":
        return "warning"
    # C=maintainability/refactor pressure, O=hygiene; keep visible but non-blocking.
    return "note"


def _sarif_level_for_pal_severity(severity: str) -> str:
    sev = (severity or "").strip().lower()
    if sev == "strong-warning":
        return "warning"
    return "note"


def _sarif_uri_for_path(path: str) -> Optional[str]:
    p = (path or "").strip().replace("\\", "/")
    if not p or p == ".":
        return None
    norm = posixpath.normpath(p)
    if norm.startswith("../"):
        return None
    return norm


def _write_sarif(
    out_root: Path,
    *,
    fi_jsonl_path: Path,
    pal_jsonl_path: Path,
    full_evidence: bool = False,
) -> Optional[Path]:
    runs: list[dict[str, Any]] = []
    iter_records = _iter_jsonl if full_evidence else _iter_actionable_jsonl

    if fi_jsonl_path.exists():
        rules_by_id: dict[str, dict[str, Any]] = {}
        results: list[dict[str, Any]] = []
        for obj in iter_records(fi_jsonl_path):
            code = str(obj.get("code") or "").strip()
            if not code:
                continue
            kind = str(obj.get("kind") or "").strip()
            uri = _sarif_uri_for_path(str(obj.get("path") or obj.get("file") or ""))
            line = int(obj.get("line") or 1)
            col = int(obj.get("col") or 1)
            msg = str(obj.get("message") or "").strip() or code

            if code not in rules_by_id:
                rules_by_id[code] = {"id": code, "shortDescription": {"text": f"FixInsight {code}"}}

            result: dict[str, Any] = {
                "ruleId": code,
                "level": _sarif_level_for_fixinsight_kind(kind),
                "message": {"text": msg},
                "properties": {
                    "tool": "FixInsight",
                    "kind": kind,
                    "code": code,
                    "ownership": str(obj.get("ownership") or "unknown"),
                    "ownership_root": obj.get("ownership_root"),
                },
            }
            if uri:
                result["locations"] = [
                    {
                        "physicalLocation": {
                            "artifactLocation": {"uri": uri},
                            "region": {"startLine": line, "startColumn": col},
                        }
                    }
                ]
            results.append(result)

        if results:
            runs.append(
                {
                    "tool": {
                        "driver": {
                            "name": "FixInsight",
                            "rules": list(rules_by_id.values()),
                        }
                    },
                    "results": results,
                }
            )

    if pal_jsonl_path.exists():
        rules_by_id = {}
        results = []
        for obj in iter_records(pal_jsonl_path):
            severity = str(obj.get("severity") or "").strip()
            section = str(obj.get("section") or "").strip()
            uri = _sarif_uri_for_path(str(obj.get("path") or ""))
            line = int(obj.get("line") or 1)
            col = int(obj.get("col") or 1)
            ident = str(obj.get("id") or obj.get("message") or "").strip()

            rule_id = str(obj.get("normalized_rule") or "").strip()
            if not rule_id:
                rule_id = _normalized_rule_id(obj)
            pal_code = str(obj.get("pal_code") or "").strip()
            if rule_id not in rules_by_id:
                rules_by_id[rule_id] = {
                    "id": rule_id,
                    "name": section or rule_id,
                    "shortDescription": {"text": section or "Pascal Analyzer finding"},
                }
                if pal_code:
                    rules_by_id[rule_id]["properties"] = {
                        "nativeCode": pal_code
                    }

            if section and ident:
                msg = f"{section}: {ident}"
            else:
                msg = section or ident or "Pascal Analyzer finding"

            result = {
                "ruleId": rule_id,
                "level": _sarif_level_for_pal_severity(severity),
                "message": {"text": msg},
                "properties": {
                    "tool": "Pascal Analyzer",
                    "severity": severity,
                    "report": str(obj.get("report") or ""),
                    "section": section,
                    "normalized_rule": rule_id,
                    "pal_code": pal_code or None,
                    "ownership": str(obj.get("ownership") or "unknown"),
                    "ownership_root": obj.get("ownership_root"),
                },
            }
            if uri:
                result["locations"] = [
                    {
                        "physicalLocation": {
                            "artifactLocation": {"uri": uri},
                            "region": {"startLine": line, "startColumn": col},
                        }
                    }
                ]
            results.append(result)

        if results:
            runs.append(
                {
                    "tool": {
                        "driver": {
                            "name": "Pascal Analyzer",
                            "rules": list(rules_by_id.values()),
                        }
                    },
                    "results": results,
                }
            )

    sarif_obj: dict[str, Any] = {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": runs,
    }
    sarif_name = (
        "static-analysis.full.sarif"
        if full_evidence
        else "static-analysis.sarif"
    )
    sarif_path = out_root / sarif_name
    _write_json(sarif_path, sarif_obj)
    return sarif_path


def _validate_sarif_count(sarif_path: Path, expected_count: int) -> None:
    sarif = _load_json(sarif_path)
    actual_count = sum(
        len(run.get("results") or [])
        for run in (sarif.get("runs") or [])
        if isinstance(run, dict)
    )
    if actual_count != expected_count:
        raise ValueError(
            f"SARIF count mismatch: SARIF={actual_count}, JSONL={expected_count}"
        )


def _is_wsl() -> bool:
    return bool(os.environ.get("WSL_DISTRO_NAME")) or ("microsoft" in platform.release().lower())


@dataclass(frozen=True)
class FixInsightFinding:
    code: str
    file: str
    line: int
    col: int
    message: str

    @property
    def kind(self) -> str:
        # Common convention: C=Convention/Complexity, W=Warning, O=Optimization
        return self.code[:1]

    def strict_key(self) -> str:
        return f"{self.code}|{self.file}|{self.line}|{self.col}|{self.message}"


def parse_dak_summary_md(summary_path: Path) -> dict[str, Any]:
    data: dict[str, Any] = {"path": str(summary_path)}
    if not summary_path.exists():
        return data

    text = _read_text(summary_path)
    ts_m = re.search(r"^- Timestamp:\s*([0-9TZ:.-]+)\s*$", text, flags=re.MULTILINE)
    if ts_m:
        data["timestamp"] = ts_m.group(1)

    proj_m = re.search(r"^- Project:\s*`([^`]+)`\s*$", text, flags=re.MULTILINE)
    if proj_m:
        data["project"] = proj_m.group(1)

    unit_m = re.search(r"^- Unit:\s*`([^`]+)`\s*$", text, flags=re.MULTILINE)
    if unit_m:
        data["unit"] = unit_m.group(1)

    fi_total_m = re.search(r"^- Findings \(by code\):\s*(\d+)\s*$", text, flags=re.MULTILINE)
    if fi_total_m:
        data["fixinsight_total"] = int(fi_total_m.group(1))

    fi_top: dict[str, int] = {}
    for m in re.finditer(r"^\s*-\s*([A-Z]\d{3}):\s*(\d+)\s*$", text, flags=re.MULTILINE):
        fi_top[m.group(1)] = int(m.group(2))
    if fi_top:
        data["fixinsight_top_codes"] = fi_top

    pal_totals_m = re.search(
        r"^- Totals:\s*warnings=(\d+),\s*strong_warnings=(\d+),\s*optimizations=(\d+),\s*total=(\d+)\s*$",
        text,
        flags=re.MULTILINE,
    )
    if pal_totals_m:
        data["pal_totals"] = {
            "warnings": int(pal_totals_m.group(1)),
            "strong_warnings": int(pal_totals_m.group(2)),
            "optimizations": int(pal_totals_m.group(3)),
            "total": int(pal_totals_m.group(4)),
        }

    pal_version_m = re.search(r"^- (?:PAL )?Version:\s*([0-9.]+)\s*$", text, flags=re.MULTILINE | re.IGNORECASE)
    if pal_version_m:
        data["pal_version"] = pal_version_m.group(1)

    pal_target_m = re.search(r"^- Compiler target:\s*(.+)\s*$", text, flags=re.MULTILINE)
    if pal_target_m:
        data["pal_compiler_target"] = pal_target_m.group(1).strip()

    errors_section_m = re.search(
        r"^## Errors\s*$\s*(.*?)(?=^##\s|\Z)",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    if errors_section_m:
        errors = [
            m.group(1).strip()
            for m in re.finditer(
                r"^\s*-\s+(.+?)\s*$", errors_section_m.group(1), flags=re.MULTILINE
            )
        ]
        if errors:
            data["errors"] = errors

    analyzers: list[str] = []
    fi_section_m = re.search(
        r"^## FixInsight\s*$\s*(.*?)(?=^##\s|\Z)",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    if "fixinsight_total" in data or (
        fi_section_m
        and re.search(
            r"^- (?:Findings \(by code\):\s*\(TXT not generated\)|Skipped\.)\s*$",
            fi_section_m.group(1),
            flags=re.MULTILINE,
        )
    ):
        analyzers.append("fixinsight")

    pal_section_m = re.search(
        r"^## Pascal Analyzer\s*$\s*(.*?)(?=^##\s|\Z)",
        text,
        flags=re.MULTILINE | re.DOTALL,
    )
    unit_summary = bool(
        re.search(r"^# Pascal Analyzer unit summary:", text, flags=re.MULTILINE)
    )
    pal_skipped = bool(
        re.search(r"^- Skipped\.\s*$", text, flags=re.MULTILINE)
        if unit_summary
        else pal_section_m
        and re.search(r"^- Skipped\.\s*$", pal_section_m.group(1), flags=re.MULTILINE)
    )
    if "pal_totals" in data or pal_skipped:
        analyzers.append("pascal_analyzer")
    if analyzers:
        data["analyzers"] = analyzers

    return data


def _validate_success_summary(summary: dict[str, Any]) -> None:
    problems: list[str] = []
    if not summary.get("timestamp"):
        problems.append("timestamp is missing")
    subjects = [key for key in ("project", "unit") if summary.get(key)]
    if len(subjects) != 1:
        problems.append("exactly one project or unit subject is required")
    actual_analyzers = set(summary.get("analyzers") or [])
    required_analyzers = (
        {"fixinsight", "pascal_analyzer"}
        if summary.get("project")
        else {"pascal_analyzer"}
    )
    missing_analyzers = sorted(required_analyzers - actual_analyzers)
    if missing_analyzers:
        problems.append(f"analyzer status is missing for {', '.join(missing_analyzers)}")
    if problems:
        raise ValueError(f"Invalid analysis summary: {'; '.join(problems)}")


def parse_fixinsight_txt(txt_path: Path) -> list[FixInsightFinding]:
    if not txt_path.exists():
        return []

    findings: list[FixInsightFinding] = []
    current_file: Optional[str] = None

    # Example:
    # File: ..\src\foo.pas
    #   C101 Method 'Bar' is too long (66 lines) (484, 1)
    loc_re = re.compile(r"^\s*(?P<code>[A-Z]\d{3})\s+(?P<msg>.*)\s+\((?P<ln>\d+),\s*(?P<col>\d+)\)\s*$")

    for raw_line in _read_text(txt_path).splitlines():
        line = raw_line.strip("\r\n")
        if not line.strip():
            continue
        if line.startswith("File:"):
            current_file = line[len("File:") :].strip()
            continue

        if current_file is None:
            continue

        m = loc_re.match(line)
        if not m:
            continue

        findings.append(
            FixInsightFinding(
                code=m.group("code"),
                file=current_file,
                line=int(m.group("ln")),
                col=int(m.group("col")),
                message=m.group("msg").strip(),
            )
        )

    return findings


def _parse_pal_compiler_target(target: str) -> tuple[Optional[str], Optional[str]]:
    # Example: "Delphi 12 (Win32)" -> ("Delphi 12", "Win32")
    t = target.strip()
    if not t:
        return None, None
    m = re.match(r"^(?P<label>.+?)\s*\((?P<plat>[^)]+)\)\s*$", t)
    if not m:
        return t, None
    label = m.group("label").strip()
    plat_raw = m.group("plat").strip()
    plat = plat_raw
    if plat_raw.lower() == "win32":
        plat = "Win32"
    elif plat_raw.lower() == "win64":
        plat = "Win64"
    return label, plat


def _last_matching_line(text: str, *, prefix: str, contains: str) -> Optional[str]:
    last: Optional[str] = None
    needle = contains.lower()
    for line in text.splitlines():
        if not line.startswith(prefix):
            continue
        if needle not in line.lower():
            continue
        last = line
    return last


_TOOL_VERSION_CACHE: dict[str, Optional[str]] = {}


def _query_fixinsight_version(executable: str) -> Optional[str]:
    cache_key = executable.lower()
    if cache_key in _TOOL_VERSION_CACHE:
        return _TOOL_VERSION_CACHE[cache_key]
    command = [executable, "--version"]
    if _is_wsl():
        command = ["cmd.exe", "/C", executable, "--version"]
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        output = (result.stdout or "") + "\n" + (result.stderr or "")
        match = re.search(
            r"FixInsightCL(?:\s+Pro)?\s+version\s+([^\s]+)",
            output,
            flags=re.IGNORECASE,
        )
        version = match.group(1) if match else None
    except (OSError, subprocess.SubprocessError):
        version = None
    _TOOL_VERSION_CACHE[cache_key] = version
    return version


def _parse_run_log_context(run_log_path: Path) -> dict[str, Any]:
    ctx: dict[str, Any] = {}
    if not run_log_path.exists():
        return ctx

    text = run_log_path.read_text(encoding="utf-8", errors="replace")

    # Last recorded CWD (we append new runs; last is the current one).
    cwd: Optional[str] = None
    for m in re.finditer(r"^CWD:\s*(.+?)\s*$", text, flags=re.MULTILINE):
        cwd = m.group(1).strip()
    if cwd:
        ctx["analysis_cwd"] = cwd

    fi_line = _last_matching_line(text, prefix="CMD:", contains="fixinsightcl.")
    if fi_line:
        m = re.search(r'^CMD:\s*"(?P<exe>[^"]*FixInsightCL\.(?:exe|cmd))"', fi_line, flags=re.IGNORECASE)
        if m:
            ctx["fixinsight_exe"] = m.group("exe")

    pal_line = _last_matching_line(text, prefix="CMD:", contains="palcmd.exe")
    if pal_line:
        m = re.search(r'^CMD:\s*"(?P<exe>[^"]*palcmd\.exe)"', pal_line, flags=re.IGNORECASE)
        if m:
            ctx["pal_exe"] = m.group("exe")

        m = re.search(r"/BUILD=(?P<cfg>\S+)", pal_line, flags=re.IGNORECASE)
        if m:
            ctx["config"] = m.group("cfg")

        m = re.search(r"/CD(?P<cd>\S+)", pal_line, flags=re.IGNORECASE)
        if m:
            cd = m.group("cd").strip()
            ctx["pal_compiler_switch"] = f"CD{cd}"
            cd_u = cd.upper()
            if "W32" in cd_u:
                ctx["platform"] = "Win32"
            elif "W64" in cd_u:
                ctx["platform"] = "Win64"

    # Best-effort: infer Delphi/BDS version from RAD Studio path fragments.
    studio_versions = re.findall(r"Embarcadero[\\/]+Studio[\\/]+(\d+\.\d+)", text, flags=re.IGNORECASE)
    if studio_versions:
        ctx["delphi"] = studio_versions[-1]

    return ctx


def _build_run_context(out_root: Path, summary: dict[str, Any], *, allow_env: bool, expected_summary_timestamp: Optional[str]) -> dict[str, Any]:
    ctx: dict[str, Any] = {}

    if allow_env:
        for k, env_name in (("platform", "DAK_PLATFORM"), ("config", "DAK_CONFIG"), ("delphi", "DAK_DELPHI")):
            raw = os.environ.get(env_name, "").strip()
            if raw:
                ctx[k] = raw

    # We only trust run.log parsing for baselines when we can prove the outputs match.
    run_log_ctx: dict[str, Any] = {}
    if expected_summary_timestamp is None or str(summary.get("timestamp") or "") == expected_summary_timestamp:
        run_log_ctx = _parse_run_log_context(out_root / "run.log")

    for k in ("platform", "config", "delphi"):
        if not ctx.get(k) and run_log_ctx.get(k):
            ctx[k] = str(run_log_ctx[k])

    pal_target = str(summary.get("pal_compiler_target") or "").strip()
    if pal_target:
        label, plat = _parse_pal_compiler_target(pal_target)
        if not ctx.get("platform") and plat:
            ctx["platform"] = plat
        if not ctx.get("delphi") and label:
            ctx["delphi"] = label

    # Ensure required keys always exist.
    for k in ("platform", "config", "delphi"):
        if not ctx.get(k):
            ctx[k] = "unknown"

    tools: dict[str, Any] = {}
    if run_log_ctx.get("fixinsight_exe"):
        tools["fixinsight_exe"] = run_log_ctx["fixinsight_exe"]
        fixinsight_version = _query_fixinsight_version(str(run_log_ctx["fixinsight_exe"]))
        if fixinsight_version:
            tools["fixinsight_version"] = fixinsight_version
    if run_log_ctx.get("pal_exe"):
        tools["pal_exe"] = run_log_ctx["pal_exe"]
    if run_log_ctx.get("pal_compiler_switch"):
        tools["pal_compiler_switch"] = run_log_ctx["pal_compiler_switch"]
    if summary.get("pal_version"):
        tools["pal_version"] = summary["pal_version"]
    if pal_target:
        tools["pal_compiler_target"] = pal_target
    if tools:
        ctx["tools"] = tools

    host: dict[str, Any] = {
        "os": platform.system(),
        "release": platform.release(),
        "python": platform.python_version(),
        "wsl": _is_wsl(),
    }
    analysis_cwd = run_log_ctx.get("analysis_cwd")
    if analysis_cwd:
        host["analysis_cwd"] = analysis_cwd
    ctx["host"] = host

    return ctx


def _actionable_counts(
    summary: dict[str, Any], fi_jsonl_path: Path, pal_jsonl_path: Path
) -> dict[str, Any]:
    raw_fi_records = list(_iter_jsonl(fi_jsonl_path)) if fi_jsonl_path.exists() else []
    raw_pal_records = list(_iter_jsonl(pal_jsonl_path)) if pal_jsonl_path.exists() else []
    fi_records = [obj for obj in raw_fi_records if _record_is_actionable(obj)]
    pal_records = [obj for obj in raw_pal_records if _record_is_actionable(obj)]

    fi_by_kind = Counter(str(obj.get("kind") or "").strip().upper() for obj in fi_records)
    unknown_fi = sorted(k for k in fi_by_kind if k not in ("W", "C", "O"))
    if unknown_fi:
        raise ValueError(f"Unsupported FixInsight finding kinds: {', '.join(unknown_fi)}")
    fi_counts = {
        "total": len(fi_records),
        "warnings": fi_by_kind.get("W", 0),
        "maintainability": fi_by_kind.get("C", 0),
        "hygiene": fi_by_kind.get("O", 0),
        "ownership": _ownership_counts(fi_records),
    }
    if "fixinsight_total" in summary and int(summary["fixinsight_total"]) != len(raw_fi_records):
        raise ValueError(
            "FixInsight count mismatch: "
            f"summary={summary['fixinsight_total']}, JSONL={len(raw_fi_records)}"
        )
    if raw_fi_records and "fixinsight_total" not in summary:
        raise ValueError("FixInsight count mismatch: summary total is missing")

    pal_by_severity = Counter(
        str(obj.get("severity") or "").strip().lower() for obj in pal_records
    )
    unknown_pal = sorted(
        severity
        for severity in pal_by_severity
        if severity not in ("warning", "strong-warning", "optimization")
    )
    if unknown_pal:
        raise ValueError(
            f"Unsupported Pascal Analyzer finding severities: {', '.join(unknown_pal)}"
        )
    pal_counts = {
        "warnings": pal_by_severity.get("warning", 0),
        "strong_warnings": pal_by_severity.get("strong-warning", 0),
        "optimizations": pal_by_severity.get("optimization", 0),
        "total": len(pal_records),
        "ownership": _ownership_counts(pal_records),
    }
    summary_pal = summary.get("pal_totals")
    if isinstance(summary_pal, dict):
        expected = {
            key: int(summary_pal.get(key, 0))
            for key in ("warnings", "strong_warnings", "optimizations", "total")
        }
        raw_by_severity = Counter(
            str(obj.get("severity") or "").strip().lower()
            for obj in raw_pal_records
        )
        actual = {
            "warnings": raw_by_severity.get("warning", 0),
            "strong_warnings": raw_by_severity.get("strong-warning", 0),
            "optimizations": raw_by_severity.get("optimization", 0),
            "total": len(raw_pal_records),
        }
        if expected != actual:
            raise ValueError(
                f"Pascal Analyzer count mismatch: summary={expected}, JSONL={actual}"
            )
    elif raw_pal_records:
        raise ValueError("Pascal Analyzer count mismatch: summary totals are missing")

    ownership = {
        name: fi_counts["ownership"][name] + pal_counts["ownership"][name]
        for name in _OWNERSHIP_NAMES
    }
    return {
        "fixinsight": fi_counts,
        "pascal_analyzer": pal_counts,
        "ownership": ownership,
        "total": fi_counts["total"] + pal_counts["total"],
    }


def _projection_counts(
    fi_records: list[dict[str, Any]], pal_records: list[dict[str, Any]]
) -> dict[str, Any]:
    fi_by_kind = Counter(
        str(obj.get("kind") or "").strip().upper() for obj in fi_records
    )
    pal_by_severity = Counter(
        str(obj.get("severity") or "").strip().lower() for obj in pal_records
    )
    fi_severity = Counter(
        {"W": "warning", "C": "maintainability", "O": "hygiene"}.get(
            str(obj.get("kind") or "").strip().upper(), "other"
        )
        for obj in fi_records
    )
    pal_severity = Counter(
        str(obj.get("severity") or "").strip().lower().replace("-", "_")
        or "other"
        for obj in pal_records
    )
    severity = fi_severity + pal_severity
    by_severity = {
        name: severity.get(name, 0)
        for name in (
            "warning",
            "strong_warning",
            "optimization",
            "maintainability",
            "hygiene",
            "other",
        )
    }
    for name in sorted(severity):
        by_severity.setdefault(name, severity[name])
    all_records = [*fi_records, *pal_records]
    return {
        "fixinsight": {
            "total": len(fi_records),
            "warnings": fi_by_kind.get("W", 0),
            "maintainability": fi_by_kind.get("C", 0),
            "hygiene": fi_by_kind.get("O", 0),
            "by_severity": dict(sorted(fi_severity.items())),
            "ownership": _ownership_counts(fi_records),
            "by_rule": dict(
                sorted(
                    Counter(
                        str(obj.get("normalized_rule") or "")
                        for obj in fi_records
                    ).items()
                )
            ),
        },
        "pascal_analyzer": {
            "total": len(pal_records),
            "warnings": pal_by_severity.get("warning", 0),
            "strong_warnings": pal_by_severity.get("strong-warning", 0),
            "optimizations": pal_by_severity.get("optimization", 0),
            "by_severity": dict(sorted(pal_severity.items())),
            "ownership": _ownership_counts(pal_records),
            "by_rule": dict(
                sorted(
                    Counter(
                        str(obj.get("normalized_rule") or "")
                        for obj in pal_records
                    ).items()
                )
            ),
        },
        "ownership": _ownership_counts(all_records),
        "by_analyzer": {
            "fixinsight": len(fi_records),
            "pascal_analyzer": len(pal_records),
        },
        "by_severity": by_severity,
        "by_rule": dict(
            sorted(
                Counter(
                    str(obj.get("normalized_rule") or "")
                    for obj in all_records
                ).items()
            )
        ),
        "total": len(all_records),
    }


def _report_projections(
    summary: dict[str, Any], fi_jsonl_path: Path, pal_jsonl_path: Path
) -> dict[str, Any]:
    _actionable_counts(summary, fi_jsonl_path, pal_jsonl_path)
    raw_fi = list(_iter_jsonl(fi_jsonl_path)) if fi_jsonl_path.exists() else []
    raw_pal = list(_iter_jsonl(pal_jsonl_path)) if pal_jsonl_path.exists() else []
    result = {"raw": _projection_counts(raw_fi, raw_pal)}
    for projection in (
        "actionable",
        "ignored",
        "external",
        "advisory_metrics",
        "unknown",
    ):
        result[projection] = _projection_counts(
            [
                obj
                for obj in raw_fi
                if obj.get("report_projection") == projection
            ],
            [
                obj
                for obj in raw_pal
                if obj.get("report_projection") == projection
            ],
        )
    return result


def _relative_artifact(out_root: Path, path_value: Any) -> Optional[str]:
    if not path_value:
        return None
    path = Path(str(path_value)).resolve()
    if not path.exists():
        return None
    try:
        return path.relative_to(out_root).as_posix()
    except ValueError:
        return str(path)


def _sha256_file(path: Path) -> Optional[str]:
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _run_git(repo_root: Path, args: list[str], *, binary: bool = False) -> Any:
    result = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=not binary,
    )
    if result.returncode != 0:
        error = result.stderr
        if isinstance(error, bytes):
            error = error.decode("utf-8", errors="replace")
        raise RuntimeError(
            f"git {' '.join(args)} failed in {repo_root}: "
            f"{str(error or '').strip() or f'exit {result.returncode}'}"
        )
    return result.stdout


def _git_source_files(repo_root: Path) -> list[str]:
    raw = _run_git(
        repo_root,
        ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        binary=True,
    )
    if not raw:
        return []
    extensions = {".pas", ".dpr", ".dpk", ".inc"}
    return sorted(
        {
            value.decode("utf-8", errors="surrogateescape").replace("\\", "/")
            for value in raw.split(b"\0")
            if value
            and Path(value.decode("utf-8", errors="surrogateescape")).suffix.lower()
            in extensions
        }
    )


def _git_submodules(repo_root: Path) -> list[dict[str, Any]]:
    raw = str(_run_git(repo_root, ["submodule", "status", "--recursive"]) or "")
    submodules: list[dict[str, Any]] = []
    states = {" ": "clean", "+": "modified", "-": "uninitialized", "U": "conflict"}
    for line in raw.splitlines():
        if not line:
            continue
        state_prefix = line[0]
        fields = line[1:].strip().split()
        if len(fields) < 2:
            continue
        submodules.append(
            {
                "path": fields[1].replace("\\", "/"),
                "revision": fields[0],
                "state": states.get(state_prefix, "unknown"),
            }
        )
    return submodules


def _hash_source_inputs(
    sources: Iterable[tuple[str, Path]], scope: str
) -> dict[str, Any]:
    digest = hashlib.sha256()
    file_count = 0
    for relative, path in sorted(sources):
        digest.update(relative.encode("utf-8", errors="surrogateescape"))
        digest.update(b"\0")
        if path.is_file():
            digest.update(str(path.stat().st_size).encode("ascii"))
            digest.update(b"\0")
            with path.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            digest.update(b"missing")
        digest.update(b"\0")
        file_count += 1
    return {
        "sha256": digest.hexdigest(),
        "file_count": file_count,
        "scope": scope,
    }


def _source_input_identity(
    repo_root: Path, submodules: list[dict[str, Any]]
) -> dict[str, Any]:
    sources: list[tuple[str, Path]] = [
        (relative, repo_root / relative) for relative in _git_source_files(repo_root)
    ]
    for submodule in submodules:
        sub_path = str(submodule.get("path") or "")
        sub_root = repo_root / sub_path
        if not sub_root.is_dir() or not (sub_root / ".git").exists():
            continue
        sources.extend(
            (f"{sub_path}/{relative}", sub_root / relative)
            for relative in _git_source_files(sub_root)
        )
    return _hash_source_inputs(
        sources, "git-delphi-inputs-with-recursive-submodules"
    )


def _filesystem_source_identity(root: Path) -> dict[str, Any]:
    return _hash_source_inputs(
        (
            (path.relative_to(root).as_posix(), path)
            for path in delphi_source_files(root)
        ),
        "filesystem-delphi-inputs",
    )


def _unavailable_workspace_identity(
    root: Path,
    vcs: str,
    error: Exception,
    *,
    include_sources: bool = True,
) -> dict[str, Any]:
    identity: dict[str, Any] = {
        "vcs": vcs,
        "revision": None,
        "dirty": None,
        "changed_files": None,
        "status": "unavailable",
        "diagnostic": f"{vcs} metadata unavailable: {error}",
        "capabilities": {
            "revision": "unavailable",
            "status": "unavailable",
            "changed_files": "unavailable",
            "inventory": "fallback" if include_sources else "unavailable",
            "nested_roots": "unavailable",
        },
    }
    if include_sources:
        identity["source_inputs"] = _filesystem_source_identity(root)
    if vcs == "git":
        identity.update({"head": None, "submodules": []})
    elif vcs == "svn":
        identity["externals"] = []
    return identity


def _svn_executable() -> Optional[Path]:
    configured = os.environ.get("DAK_SVN_EXE")
    if configured:
        path = Path(configured)
        return path if path.is_file() else None

    discovered = shutil.which("svn")
    if discovered:
        return Path(discovered)

    installed = Path(r"C:\Program Files\TortoiseSVN\bin\svn.exe")
    return installed if installed.is_file() else None


def _svnversion_executable(svn: Path) -> Optional[Path]:
    adjacent = svn.with_name(f"svnversion{svn.suffix}")
    return adjacent if adjacent.is_file() else None


def _run_svn(executable: Path, args: list[str], root: Path) -> str:
    result = subprocess.run(
        [str(executable), *args, str(root)],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"{executable.name} {' '.join(args)} failed in {root}: "
            f"{result.stderr.strip() or f'exit {result.returncode}'}"
        )
    return result.stdout


def _svn_relative_path(root: Path, value: str) -> str:
    path = Path(value)
    if not path.is_absolute():
        path = root / path
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def _svn_info(raw: str) -> dict[str, Optional[str]]:
    entry = ElementTree.fromstring(raw).find("entry")
    repository = entry.find("repository") if entry is not None else None
    return {
        "url": entry.findtext("url") if entry is not None else None,
        "repository_root": (
            repository.findtext("root") if repository is not None else None
        ),
        "repository_uuid": (
            repository.findtext("uuid") if repository is not None else None
        ),
        "root_revision": entry.get("revision") if entry is not None else None,
    }


def _svn_version(raw: str) -> dict[str, Any]:
    value = raw.strip()
    match = re.fullmatch(r"(\d+)(?::(\d+))?([MSP]*)", value)
    if match is None:
        raise ValueError(f"unexpected svnversion output: {value or '<empty>'}")
    first, last, flags = match.groups()
    return {
        "raw": value,
        "revision": f"{first}:{last}" if last else first,
        "minimum": int(first),
        "maximum": int(last or first),
        "modified": "M" in flags,
        "switched": "S" in flags,
        "sparse": "P" in flags,
    }


def _svn_status(
    raw: str, root: Path
) -> tuple[list[str], list[str], list[str]]:
    dirty_items = {
        "added",
        "conflicted",
        "deleted",
        "incomplete",
        "merged",
        "missing",
        "modified",
        "obstructed",
        "replaced",
        "unversioned",
    }
    changed: set[str] = set()
    unversioned_sources: set[str] = set()
    externals: set[str] = set()
    source_extensions = {".pas", ".dpr", ".dpk", ".inc"}
    for entry in ElementTree.fromstring(raw).iterfind(".//entry"):
        relative = _svn_relative_path(root, entry.get("path") or "")
        status = entry.find("wc-status")
        if status is None:
            continue
        item = status.get("item") or "none"
        properties = status.get("props") or "none"
        if item == "external":
            externals.add(relative)
            continue
        if item in dirty_items or properties in {"conflicted", "modified"}:
            changed.add(relative)
        if item in {"added", "unversioned"} and Path(relative).suffix.lower() in source_extensions:
            unversioned_sources.add(relative)
    return sorted(changed), sorted(unversioned_sources), sorted(externals)


def _svn_list(raw: str) -> list[str]:
    source_extensions = {".pas", ".dpr", ".dpk", ".inc"}
    return sorted(
        {
            (entry.findtext("name") or "").replace("\\", "/")
            for entry in ElementTree.fromstring(raw).iterfind(".//entry")
            if entry.get("kind") == "file"
            and Path(entry.findtext("name") or "").suffix.lower()
            in source_extensions
        }
    )


def _svn_identity(root: Path) -> dict[str, Any]:
    svn = _svn_executable()
    if svn is None:
        return _unavailable_workspace_identity(
            root, "svn", FileNotFoundError("svn executable not found")
        )

    errors: list[str] = []

    try:
        info = _svn_info(_run_svn(svn, ["info", "--xml"], root))
        info_available = bool(info["url"] and info["repository_root"])
        if not info_available:
            raise ValueError("svn info did not identify a working copy")
    except (ElementTree.ParseError, OSError, RuntimeError, ValueError) as error:
        info_available = False
        info = {
            "url": None,
            "repository_root": None,
            "repository_uuid": None,
            "root_revision": None,
        }
        errors.append(str(error))

    svnversion = _svnversion_executable(svn)
    try:
        if svnversion is None:
            raise FileNotFoundError("svnversion executable not found")
        version = _svn_version(_run_svn(svnversion, [], root))
    except (OSError, RuntimeError, ValueError) as error:
        version = None
        errors.append(str(error))

    try:
        changed, unversioned, externals = _svn_status(
            _run_svn(svn, ["status", "--xml"], root), root
        )
        status_available = info_available
    except (ElementTree.ParseError, OSError, RuntimeError, ValueError) as error:
        changed, unversioned, externals = [], [], []
        status_available = False
        errors.append(str(error))

    try:
        versioned = _svn_list(_run_svn(svn, ["list", "--xml", "-R"], root))
        inventory_available = status_available
    except (ElementTree.ParseError, OSError, RuntimeError, ValueError) as error:
        versioned = []
        inventory_available = False
        errors.append(str(error))

    if inventory_available:
        relative_sources = sorted(set(versioned) | set(unversioned))
        source_inputs = _hash_source_inputs(
            ((relative, root / relative) for relative in relative_sources),
            "svn-versioned-plus-unversioned-delphi-inputs",
        )
    else:
        source_inputs = _filesystem_source_identity(root)

    complete = not errors
    identity: dict[str, Any] = {
        "vcs": "svn",
        "revision": version["revision"] if version is not None else None,
        "dirty": bool(changed) if status_available else None,
        "changed_files": changed if status_available else None,
        "status": "complete" if complete else "unavailable",
        "capabilities": {
            "revision": "available" if version is not None else "unavailable",
            "status": "available" if status_available else "unavailable",
            "changed_files": "available" if status_available else "unavailable",
            "inventory": "available" if inventory_available else "fallback",
            "nested_roots": "available" if status_available else "unavailable",
        },
        "source_inputs": source_inputs,
        "externals": [{"path": path} for path in externals],
        **info,
    }
    if version is not None:
        identity["svnversion"] = version
    if errors:
        identity["diagnostic"] = "; ".join(errors)
    return identity


def _git_identity(
    repo_root: Optional[Path], *, include_sources: bool = True
) -> dict[str, Any]:
    if repo_root is None:
        return {"vcs": "none"}
    head = str(_run_git(repo_root, ["rev-parse", "HEAD"]) or "").strip()
    changed_files, changed_error = _git_changed_files(repo_root)
    if changed_error is not None:
        raise RuntimeError(changed_error)
    changed = sorted(path.replace("\\", "/") for path in changed_files)
    identity = {
        "vcs": "git",
        "head": head or "unknown",
        "revision": head or "unknown",
        "dirty": bool(changed),
        "changed_files": changed,
        "status": "complete",
        "capabilities": {
            "revision": "available",
            "status": "available",
            "changed_files": "available",
            "inventory": "available",
            "nested_roots": "available",
        },
    }
    if include_sources:
        submodules = _git_submodules(repo_root)
        identity["source_inputs"] = _source_input_identity(repo_root, submodules)
        identity["submodules"] = submodules
    return identity


def _workspace_target_identity(workspace: Any) -> dict[str, Any]:
    if isinstance(workspace, dict):
        vcs = str(workspace.get("vcs") or "none")
        root_value = workspace.get("root")
    else:
        vcs = str(getattr(workspace, "vcs", "none"))
        root_value = getattr(workspace, "root", None)
    root = _to_local_path(str(root_value)) if root_value else None
    if root is None and root_value:
        root = Path(str(root_value))
    if root is not None:
        root = root.resolve()
    if vcs == "git" and root is not None:
        try:
            identity = _git_identity(root)
        except (OSError, RuntimeError) as error:
            identity = _unavailable_workspace_identity(root, "git", error)
    elif vcs == "svn" and root is not None:
        identity = _svn_identity(root)
    elif vcs == "none" and root is not None:
        identity = {
            "vcs": "none",
            "revision": None,
            "dirty": None,
            "changed_files": None,
            "status": "not_applicable",
            "capabilities": {
                "revision": "not_applicable",
                "status": "not_applicable",
                "changed_files": "not_applicable",
                "inventory": "available",
                "nested_roots": "not_applicable",
            },
            "source_inputs": _filesystem_source_identity(root),
        }
    else:
        identity = {"vcs": vcs}
    if root is not None:
        identity["root"] = str(root)
    return identity


def _dak_identity() -> dict[str, Any]:
    dak_root = _find_git_root(Path(__file__).resolve().parent)
    try:
        return _git_identity(dak_root, include_sources=False)
    except (OSError, RuntimeError) as error:
        assert dak_root is not None
        return _unavailable_workspace_identity(
            dak_root, "git", error, include_sources=False
        )


def capture_run_provenance(
    subject_path: Path, dak_executable: Path, workspace: Any = None
) -> dict[str, Any]:
    if workspace is not None:
        target = _workspace_target_identity(workspace)
    else:
        target_root = _find_git_root(subject_path.resolve().parent)
        target = (
            _workspace_target_identity({"root": target_root, "vcs": "git"})
            if target_root is not None
            else _git_identity(None)
        )
    dak = _dak_identity()
    dak["executable"] = str(dak_executable.resolve())
    dak["executable_sha256"] = _sha256_file(dak_executable.resolve())
    return {
        "target": target,
        "dak": dak,
    }


def _load_status_seed(
    out_root: Path,
    summary: dict[str, Any],
    run_context: dict[str, Any],
    *,
    required: bool = False,
) -> dict[str, Any]:
    seed_path = out_root / "summary.json"
    if seed_path.exists():
        seed = _load_json(seed_path)
        if (
            not isinstance(seed, dict)
            or int(seed.get("schema_version", 0) or 0) not in (2, 3)
        ):
            raise ValueError(f"Invalid analysis status seed: {seed_path}")
        expected_subject = str(summary.get("project") or summary.get("unit") or "")
        seed_subject = seed.get("subject")
        actual_subject = (
            str(seed_subject.get("path") or "")
            if isinstance(seed_subject, dict)
            else ""
        )
        normalize = lambda value: value.replace("\\", "/").rstrip("/").lower()
        if normalize(actual_subject) != normalize(expected_subject):
            raise ValueError(
                f"Analysis seed subject does not match summary: "
                f"seed={actual_subject!r}, summary={expected_subject!r}"
            )
        return seed
    if required:
        raise ValueError(f"Required schema-2 analysis seed is missing: {seed_path}")
    fixinsight_requested = "fixinsight_total" in summary
    pal_requested = "pal_totals" in summary
    return {
        "schema_version": 2,
        "status": {"infrastructure": "complete", "policy": "not_evaluated"},
        "subject": {
            "kind": "project" if summary.get("project") else "unit",
            "path": summary.get("project") or summary.get("unit"),
        },
        "compiler": {
            "platform": run_context.get("platform", "unknown"),
            "config": run_context.get("config", "unknown"),
            "delphi": run_context.get("delphi", "unknown"),
        },
        "analyzers": {
            "fixinsight": {
                "requested": fixinsight_requested,
                "status": "complete" if fixinsight_requested else "not_requested",
                "count_quality": "complete",
            },
            "pascal_analyzer": {
                "requested": pal_requested,
                "status": "complete" if pal_requested else "not_requested",
                "count_quality": "complete",
            },
        },
        "errors": summary.get("errors") or [],
    }


def _enrich_analyzer_versions(
    seed: dict[str, Any], run_context: dict[str, Any]
) -> None:
    analyzers = seed.setdefault("analyzers", {})
    tools = run_context.get("tools") or {}
    versions = {
        "fixinsight": tools.get("fixinsight_version"),
        "pascal_analyzer": tools.get("pal_version"),
    }
    for name, version in versions.items():
        analyzer = analyzers.setdefault(name, {})
        if analyzer.get("requested"):
            analyzer["version"] = str(version or analyzer.get("version") or "unavailable")


def _enrich_provenance(
    seed: dict[str, Any],
    summary: dict[str, Any],
    out_root: Path,
    captured_provenance: Optional[dict[str, Any]] = None,
) -> None:
    provenance = seed.setdefault("provenance", {})
    subject_path = _to_local_path(
        str(summary.get("project") or summary.get("unit") or "")
    )
    workspace = seed.get("workspace")
    target_root = _find_git_root(subject_path.parent) if subject_path else None
    captured_target = (
        captured_provenance.get("target")
        if isinstance(captured_provenance, dict)
        else None
    )
    if isinstance(captured_target, dict):
        target = dict(captured_target)
    elif isinstance(workspace, dict):
        target = _workspace_target_identity(workspace)
    else:
        target = _git_identity(target_root)
    inputs = seed.setdefault("inputs", {})
    if subject_path and subject_path.is_file():
        inputs.setdefault("project_sha256", _sha256_file(subject_path))
    target["project_sha256"] = inputs.get("project_sha256")
    target["main_source_sha256"] = inputs.get("main_source_sha256")
    target["config_manifests"] = inputs.get("config_manifests") or []
    provenance["target"] = target

    dak = provenance.setdefault("dak", {})
    captured_dak = (
        captured_provenance.get("dak")
        if isinstance(captured_provenance, dict)
        else None
    )
    if isinstance(captured_dak, dict):
        dak.update(captured_dak)
    else:
        dak.update(_dak_identity())
    executable = str(dak.get("executable") or os.environ.get("DAK_EXE") or "").strip()
    if executable:
        executable_path = Path(executable)
        dak["executable_sha256"] = _sha256_file(executable_path)


def _write_ai_summary(
    out_root: Path,
    *,
    status_seed: dict[str, Any],
    summary: dict[str, Any],
    snapshot: dict[str, Any],
    result: dict[str, Any],
    fi_jsonl_path: Path,
    pal_jsonl_path: Path,
    captured_provenance: Optional[dict[str, Any]] = None,
) -> Path:
    counts = _report_projections(summary, fi_jsonl_path, pal_jsonl_path)
    sarif_path = out_root / "static-analysis.sarif"
    sarif = _load_json(sarif_path)
    sarif_count = sum(
        len(run.get("results") or [])
        for run in (sarif.get("runs") or [])
        if isinstance(run, dict)
    )
    if sarif_count != counts["actionable"]["total"]:
        raise ValueError(
            "SARIF count mismatch: "
            f"SARIF={sarif_count}, JSONL={counts['actionable']['total']}"
        )

    run_context = snapshot.get("run_context") or {}
    artifacts: dict[str, str] = {}
    artifact_sources = {
        "summary_markdown": out_root / "summary.md",
        "fixinsight_jsonl": fi_jsonl_path,
        "pascal_analyzer_jsonl": pal_jsonl_path,
        "baseline": result.get("baseline"),
        "delta": result.get("delta"),
        "triage": result.get("triage"),
        "triage_changed": result.get("triage_changed"),
        "triage_snippets": result.get("triage_snippets"),
        "sarif": result.get("sarif"),
        "full_sarif": result.get("full_sarif"),
        "external_summary": result.get("external_summary"),
        "metrics": result.get("metrics"),
        "history": result.get("history"),
        "trend": result.get("trend"),
    }
    for name, source in artifact_sources.items():
        relative = _relative_artifact(out_root, source)
        if relative:
            artifacts[name] = relative

    summary_json = status_seed
    summary_json["schema_version"] = 3
    summary_json["timestamp"] = summary.get("timestamp") or snapshot.get("created_at")
    status = summary_json.setdefault("status", {})
    status["infrastructure"] = "complete"
    status["postprocessor"] = "complete"
    status["finalization"] = "complete"
    status["ownership_resolution"] = (
        "failed" if counts["unknown"]["total"] else "complete"
    )
    if result.get("policy_evaluated"):
        status["policy"] = "pass" if result.get("gate_pass") else "fail"
    else:
        status["policy"] = "not_evaluated"
    compiler = summary_json.setdefault("compiler", {})
    compiler.setdefault("platform", run_context.get("platform", "unknown"))
    compiler.setdefault("config", run_context.get("config", "unknown"))
    compiler.setdefault("delphi", run_context.get("delphi", "unknown"))
    analyzers = summary_json.setdefault("analyzers", {})
    for name in ("fixinsight", "pascal_analyzer"):
        analyzer = analyzers.setdefault(name, {})
        analyzer["count_quality"] = "complete"
    _enrich_analyzer_versions(summary_json, run_context)
    policy_context = summary_json.get("policy")
    if isinstance(policy_context, dict):
        policy_context.pop("status", None)
        resolved_policy = _resolved_analysis_policy(summary_json)
        policy_context["active"] = {
            "gate_ownership": resolved_policy["gate_ownership"],
            "exclude_path_masks": resolved_policy["exclude_path_masks"],
            "gate_metrics": resolved_policy["gate_metrics"],
            "fixinsight_ignore": resolved_policy["fixinsight_ignore"],
            "pal_ignore_rules": resolved_policy["pal_ignore_rules"],
            "triage": _active_triage_policy(),
        }
    pal_analyzer = analyzers.get("pascal_analyzer")
    pal_analyzer = (
        pal_analyzer if isinstance(pal_analyzer, dict) else {}
    )
    pal_analyzer["verified_rule_aliases"] = dict(
        sorted(
            _pal_registered_aliases(
                str(pal_analyzer.get("version") or "")
            ).items()
        )
    )
    summary_json["counts"] = counts
    summary_json["compatibility"] = snapshot.get("compatibility") or {}
    summary_json["errors"] = summary.get("errors") or []
    summary_json.setdefault("artifacts", {}).update(artifacts)
    _enrich_provenance(
        summary_json,
        summary,
        out_root,
        captured_provenance=captured_provenance,
    )
    summary_json_path = out_root / "summary.json"
    _write_json(summary_json_path, summary_json)
    return summary_json_path


def _find_git_root(start_dir: Path) -> Optional[Path]:
    p = start_dir.resolve()
    while True:
        # `.git` is usually a directory, but can also be a file for worktrees/submodules.
        if (p / ".git").exists():
            return p
        if p.parent == p:
            return None
        p = p.parent


def _git_changed_files(repo_root: Path) -> tuple[set[str], Optional[str]]:
    try:
        p = subprocess.run(
            ["git", "status", "--porcelain=v1", "-z", "--untracked-files=all"],
            cwd=str(repo_root),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        return set(), "git not found on PATH"

    if p.returncode != 0:
        msg = (p.stderr or b"").decode("utf-8", errors="replace").strip()
        return set(), msg or f"git status failed (exit code {p.returncode})"

    raw = (p.stdout or b"").decode("utf-8", errors="replace")
    if not raw:
        return set(), None

    entries = raw.split("\0")
    out: set[str] = set()
    i = 0
    while i < len(entries):
        s = entries[i]
        i += 1
        if not s:
            continue
        status = s[:2]
        path1 = s[3:]
        # With porcelain v1 -z, rename/copy are encoded as: `R  new\0old\0`.
        if status[:1] in ("R", "C") or status[1:2] in ("R", "C"):
            if path1:
                out.add(path1)
            if i < len(entries):
                i += 1
            continue
        if path1:
            out.add(path1)

    return out, None


def _looks_like_windows_path(s: str) -> bool:
    return bool(re.match(r"^[A-Za-z]:[\\/]", s) or s.startswith("\\\\"))


def _windows_drive_to_wsl_path(win: str) -> Optional[Path]:
    m = re.match(r"^(?P<drive>[A-Za-z]):[\\/](?P<rest>.*)$", win)
    if not m:
        return None
    drive = m.group("drive").lower()
    rest = m.group("rest").replace("\\", "/")
    return (Path("/mnt") / drive / rest).resolve()


def _to_local_path(raw: str) -> Optional[Path]:
    s = raw.strip()
    if not s:
        return None
    if _is_wsl() and _looks_like_windows_path(s):
        return _windows_drive_to_wsl_path(s)
    p = Path(s)
    return p if p.is_absolute() else None


def _normalize_to_repo_relative(raw_path: str, *, repo_root: Path, base_dirs: list[Path]) -> Optional[str]:
    s = raw_path.strip()
    if not s:
        return None

    # Make separators predictable so `Path` can resolve `..` segments even on WSL.
    s = s.replace("\\", "/")

    # Absolute paths (Windows or Unix).
    is_abs_input = bool(s.startswith("/") or re.match(r"^[A-Za-z]:/", s))
    abs_candidate: Optional[Path] = None
    if s.startswith("/"):
        abs_candidate = Path(s)
    elif re.match(r"^[A-Za-z]:/", s):
        abs_candidate = _to_local_path(s)

    if abs_candidate is not None:
        try:
            resolved = abs_candidate.resolve()
            if resolved.is_relative_to(repo_root):
                return resolved.relative_to(repo_root).as_posix()
        except Exception:
            pass
        # It was absolute, but not under this repo root.
        return None

    if is_abs_input:
        return None

    rel = Path(s)
    for base in base_dirs:
        try:
            resolved = (base / rel).resolve()
            if resolved.is_relative_to(repo_root):
                return resolved.relative_to(repo_root).as_posix()
        except Exception:
            continue
    return None


def _normalize_path_value(
    raw_path: str,
    *,
    repo_root: Optional[Path],
    base_dirs: list[Path],
    basename_index: Optional[dict[str, str]] = None,
) -> str:
    s = raw_path.strip()
    if not s:
        return ""

    if repo_root is not None:
        rel = _normalize_to_repo_relative(raw_path, repo_root=repo_root, base_dirs=base_dirs)
        if rel:
            return rel

        # FixInsight can report files using absolute paths outside the current repo even when we
        # have a repo-local copy (e.g. submodule). When the input is absolute, and the basename
        # uniquely exists under `repo_root`, map it to that repo-relative path so triage/deltas
        # are stable and we can open the file locally.
        norm = s.replace("\\", "/")
        is_abs_input = bool(norm.startswith("/") or norm.startswith("//") or re.match(r"^[A-Za-z]:/", norm))
        if is_abs_input:
            base = posixpath.basename(norm)
            if base:
                index = (
                    basename_index
                    if basename_index is not None
                    else _repo_unique_basename_index(repo_root)
                )
                mapped = index.get(base.lower())
                if mapped:
                    return mapped

    # Fallback: normalize separators + dot segments deterministically.
    s = s.replace("\\", "/")
    return posixpath.normpath(s)


_OWNERSHIP_NAMES = ("project", "repository", "third_party", "unknown")


def _empty_ownership_counts() -> dict[str, int]:
    return {name: 0 for name in _OWNERSHIP_NAMES}


def _ownership_counts(records: Iterable[dict[str, Any]]) -> dict[str, int]:
    counts = _empty_ownership_counts()
    for obj in records:
        ownership = obj.get("ownership")
        if not isinstance(ownership, str) or ownership not in counts:
            raise ValueError(f"invalid ownership category: {ownership!r}")
        counts[ownership] += 1
    return counts


def _resolved_analysis_policy(status_seed: dict[str, Any]) -> dict[str, Any]:
    policy = status_seed.get("policy")
    policy = policy if isinstance(policy, dict) else {}
    values = policy.get("values")
    values = values if isinstance(values, dict) else {}
    errors: list[str] = []

    def names(key: str, default: list[str]) -> list[str]:
        raw = values.get(key)
        if raw is None:
            errors.append(f"Resolved AnalysisPolicy value is missing: {key}")
            return default
        if not isinstance(raw, list) or any(
            not isinstance(value, str) or not value.strip() for value in raw
        ):
            errors.append(f"Resolved AnalysisPolicy value is invalid: {key}")
            return default
        return [value.strip() for value in raw]

    def optional_names(key: str) -> list[str]:
        raw = values.get(key)
        if raw is None:
            return []
        if not isinstance(raw, list) or any(
            not isinstance(value, str) or not value.strip() for value in raw
        ):
            errors.append(f"Resolved AnalysisPolicy value is invalid: {key}")
            return []
        return [value.strip() for value in raw]

    gate_ownership = names("gate_ownership", ["project", "repository"])
    invalid = [
        value
        for value in gate_ownership
        if value not in ("project", "repository", "third_party")
    ]
    if invalid or len(set(gate_ownership)) != len(gate_ownership):
        errors.append("Resolved AnalysisPolicy gate_ownership is invalid")
        gate_ownership = ["project", "repository"]

    project_roots = names("project_roots", [])
    third_party_roots = names("third_party_roots", [])
    exclude_path_masks = optional_names("exclude_path_masks")
    gate_metrics = optional_names("gate_metrics")
    fixinsight_ignore = optional_names("fixinsight_ignore")
    pal_ignore_rules = optional_names("pal_ignore_rules")
    policy_sha = str(policy.get("sha256") or "").strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", policy_sha):
        errors.append("Resolved AnalysisPolicy sha256 is missing or invalid")

    return {
        "gate_ownership": gate_ownership,
        "project_roots": project_roots,
        "third_party_roots": third_party_roots,
        "exclude_path_masks": exclude_path_masks,
        "gate_metrics": gate_metrics,
        "fixinsight_ignore": fixinsight_ignore,
        "pal_ignore_rules": pal_ignore_rules,
        "sha256": policy_sha,
        "errors": errors,
    }


def _compatibility_snapshot(status_seed: dict[str, Any]) -> dict[str, Any]:
    compiler = status_seed.get("compiler")
    compiler = compiler if isinstance(compiler, dict) else {}
    analyzers = status_seed.get("analyzers")
    analyzers = analyzers if isinstance(analyzers, dict) else {}
    inputs = status_seed.get("inputs")
    inputs = inputs if isinstance(inputs, dict) else {}
    policy = status_seed.get("policy")
    policy = policy if isinstance(policy, dict) else {}
    subject = status_seed.get("subject")
    subject = subject if isinstance(subject, dict) else {}
    provenance = status_seed.get("provenance")
    provenance = provenance if isinstance(provenance, dict) else {}
    target = provenance.get("target")
    target = target if isinstance(target, dict) else {}
    dak = provenance.get("dak")
    dak = dak if isinstance(dak, dict) else {}
    workspace = status_seed.get("workspace")
    workspace = workspace if isinstance(workspace, dict) else {}

    analyzer_context: dict[str, Any] = {}
    for name in ("fixinsight", "pascal_analyzer"):
        analyzer = analyzers.get(name)
        analyzer = analyzer if isinstance(analyzer, dict) else {}
        options = analyzer.get("options")
        options = options if isinstance(options, dict) else {}
        analyzer_context[name] = {
            "requested": bool(analyzer.get("requested")),
            "version": str(analyzer.get("version") or ""),
            "options_sha256": str(options.get("sha256") or ""),
        }

    config_hashes = [
        str(item.get("sha256") or "")
        for item in (inputs.get("config_manifests") or [])
        if isinstance(item, dict)
    ]
    submodules = sorted(
        (
            {
                "path": str(item.get("path") or "").replace("\\", "/"),
                "revision": str(item.get("revision") or ""),
            }
            for item in (target.get("submodules") or [])
            if isinstance(item, dict)
        ),
        key=lambda item: item["path"].lower(),
    )
    externals = sorted(
        (
            {
                "path": str(item.get("path") or "").replace("\\", "/"),
                "revision": str(item.get("revision") or ""),
            }
            for item in (target.get("externals") or [])
            if isinstance(item, dict)
        ),
        key=lambda item: item["path"].lower(),
    )
    source_inputs = target.get("source_inputs")
    source_inputs = source_inputs if isinstance(source_inputs, dict) else {}
    capabilities = target.get("capabilities")
    capabilities = capabilities if isinstance(capabilities, dict) else {}
    capability_states = {
        str(key): str(value)
        for key, value in sorted(capabilities.items())
        if isinstance(value, (str, int, float, bool)) or value is None
    }
    material = {
        "subject_kind": str(subject.get("kind") or ""),
        "compiler": {
            key: str(compiler.get(key) or "")
            for key in ("delphi", "platform", "config", "search_path_sha256")
        },
        "analyzers": analyzer_context,
        "policy_sha256": str(policy.get("sha256") or ""),
        "reporting_policy_sha256": str(policy.get("reporting_sha256") or ""),
        "reporting_policy_origins": (
            policy.get("origins")
            if isinstance(policy.get("origins"), dict)
            else {}
        ),
        "project_manifest_sha256": str(
            inputs.get("project_sha256")
            or inputs.get("project_context_sha256")
            or ""
        ),
        "config_manifest_sha256": config_hashes,
        "workspace": {
            "root": str(workspace.get("root") or target.get("root") or "").replace(
                "\\", "/"
            ),
            "vcs": str(workspace.get("vcs") or target.get("vcs") or ""),
            "status": str(target.get("status") or ""),
            "inventory_scope": str(source_inputs.get("scope") or ""),
            "capabilities": capability_states,
            "externals": externals,
        },
        "submodules": submodules,
        "dak": {
            "head": str(dak.get("head") or ""),
            "executable_sha256": str(dak.get("executable_sha256") or ""),
        },
    }
    encoded = json.dumps(material, sort_keys=True, separators=(",", ":"))
    return {"sha256": _sha256_text(encoded), "context": material}


def _ownership_text(counts: Any) -> str:
    values = counts if isinstance(counts, dict) else {}
    return ", ".join(f"{name}={int(values.get(name, 0))}" for name in _OWNERSHIP_NAMES)


def _active_triage_policy() -> dict[str, Any]:
    return {
        "top": _int_env("DAK_TRIAGE_TOP", 20) or 20,
        "include_paths": os.environ.get("DAK_TRIAGE_INCLUDE_PATHS", "").strip(),
        "exclude_paths": os.environ.get("DAK_TRIAGE_EXCLUDE_PATHS", "").strip(),
        "pal_include_call_tree": _truthy_env(
            "DAK_TRIAGE_PAL_INCLUDE_CALL_TREE", False
        ),
    }


def _write_summary_ownership(summary_path: Path, counts: dict[str, int]) -> None:
    marker = "<!-- DAK ownership -->"
    text = _read_text(summary_path).rstrip()
    if marker in text:
        text = text.split(marker, 1)[0].rstrip()
    _write_text(
        summary_path,
        text
        + "\n\n"
        + marker
        + "\n## Ownership\n\n- "
        + _ownership_text(counts)
        + "\n",
    )


def _write_external_summary(
    out_root: Path, fi_jsonl_path: Path, pal_jsonl_path: Path
) -> Path:
    path = out_root / "external-summary.md"
    records = [
        *(
            list(_iter_jsonl(fi_jsonl_path))
            if fi_jsonl_path.exists()
            else []
        ),
        *(
            list(_iter_jsonl(pal_jsonl_path))
            if pal_jsonl_path.exists()
            else []
        ),
    ]
    external = [
        obj for obj in records if obj.get("report_projection") == "external"
    ]
    grouped: Counter[tuple[str, str]] = Counter()
    roots: Counter[str] = Counter()
    root_ownership: dict[str, str] = {}
    for obj in external:
        root = str(obj.get("ownership_root") or "<unknown root>")
        rule = str(obj.get("normalized_rule") or "unknown")
        roots[root] += 1
        root_ownership[root] = str(obj.get("ownership") or "unknown")
        grouped[(root, rule)] += 1

    lines = [
        "# External static-analysis summary",
        "",
        f"- Findings: {len(external)}",
        "- Projection: external ownership outside the active gate policy",
        "",
    ]
    for root, count in sorted(roots.items(), key=lambda item: (-item[1], item[0].lower())):
        lines.extend(
            (
                f"## `{root}`",
                "",
                f"- Ownership: {root_ownership[root]}",
                f"- Findings: {count}",
            )
        )
        for (group_root, rule), rule_count in sorted(
            grouped.items(), key=lambda item: (item[0][0].lower(), item[0][1])
        ):
            if group_root == root:
                lines.append(f"- `{rule}`: {rule_count}")
        lines.append("")
    _write_text(path, "\n".join(lines).rstrip() + "\n")
    return path


def _write_metrics_summary(
    out_root: Path, fi_jsonl_path: Path, pal_jsonl_path: Path
) -> Path:
    path = out_root / "metrics.md"
    records = [
        *(
            list(_iter_jsonl(fi_jsonl_path))
            if fi_jsonl_path.exists()
            else []
        ),
        *(
            list(_iter_jsonl(pal_jsonl_path))
            if pal_jsonl_path.exists()
            else []
        ),
    ]
    advisory = [
        obj
        for obj in records
        if obj.get("report_projection") == "advisory_metrics"
    ]
    by_rule = Counter(
        str(obj.get("normalized_rule") or "unknown") for obj in advisory
    )
    lines = [
        "# Advisory static-analysis metrics",
        "",
        f"- Findings: {len(advisory)}",
        "- Gate behavior: advisory by default; only explicitly selected metric rules are actionable",
        "",
    ]
    for rule, count in sorted(by_rule.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"- `{rule}`: {count}")
    _write_text(path, "\n".join(lines).rstrip() + "\n")
    return path


def _canonical_path(path: Path) -> str:
    return os.path.normcase(str(path.resolve()))


def _case_safe_existing_path(path: Path) -> Optional[Path]:
    if path.exists():
        return path.resolve()
    anchor = Path(path.anchor) if path.is_absolute() else Path()
    parts = path.parts[1:] if path.is_absolute() else path.parts
    current = anchor
    for part in parts:
        if not current.exists() or not current.is_dir():
            return None
        matches = [child for child in current.iterdir() if child.name.lower() == part.lower()]
        if len(matches) != 1:
            return None
        current = matches[0]
    return current.resolve() if current.exists() else None


def _pal_search_paths(out_root: Path, project_dir: Optional[Path]) -> list[Path]:
    run_log = out_root / "run.log"
    if not run_log.exists():
        return []
    text = _read_text(run_log)
    pal_line = _last_matching_line(text, prefix="CMD:", contains="palcmd.exe")
    if pal_line is None:
        return []
    matches = re.findall(r'(?:^|\s)/S=(?:"([^"]*)"|(\S+))', pal_line)
    result: list[Path] = []
    seen: set[str] = set()
    for quoted, plain in matches:
        for raw in (quoted or plain).split(";"):
            value = raw.strip()
            if not value:
                continue
            local = _to_local_path(value)
            if local is None and project_dir is not None:
                local = project_dir / value
            if local is None:
                continue
            resolved = _case_safe_existing_path(local)
            if resolved is None or not resolved.is_dir():
                continue
            key = _canonical_path(resolved)
            if key not in seen:
                seen.add(key)
                result.append(resolved)
    return result


def _project_source_files(status_seed: dict[str, Any]) -> tuple[set[str], Optional[Path], Optional[Path]]:
    subject = status_seed.get("subject")
    subject = subject if isinstance(subject, dict) else {}
    subject_path = _to_local_path(str(subject.get("path") or ""))
    project_file = _to_local_path(
        str(subject.get("project_file") or subject.get("project_context") or "")
    )
    project_dir = project_file.parent if project_file is not None else (
        subject_path.parent if subject_path is not None else None
    )
    files: set[str] = set()
    for path in (subject_path, project_file):
        if path is not None and path.exists():
            files.add(_canonical_path(path))
    if project_file is not None and project_file.exists():
        try:
            root = ElementTree.parse(project_file).getroot()
            for node in root.iter():
                if node.tag.rsplit("}", 1)[-1] != "DCCReference":
                    continue
                include = str(node.attrib.get("Include") or "").strip()
                if not include:
                    continue
                include_path = _to_local_path(include)
                candidate = _case_safe_existing_path(
                    include_path if include_path is not None else project_file.parent / include
                )
                if candidate is not None and candidate.is_file():
                    files.add(_canonical_path(candidate))
        except (ElementTree.ParseError, OSError):
            pass
    return files, project_file, project_dir


def _workspace_context(
    status_seed: dict[str, Any], legacy_repo_root: Optional[Path]
) -> tuple[Optional[Path], str]:
    workspace = status_seed.get("workspace")
    workspace = workspace if isinstance(workspace, dict) else None
    provenance = status_seed.get("provenance")
    target = provenance.get("target") if isinstance(provenance, dict) else None
    target = target if isinstance(target, dict) else {}
    if workspace is not None:
        root_value = workspace.get("root")
        vcs = str(workspace.get("vcs") or target.get("vcs") or "none")
    elif target.get("root"):
        root_value = target.get("root")
        vcs = str(target.get("vcs") or "none")
    else:
        return legacy_repo_root, "git" if legacy_repo_root is not None else "none"
    local = _to_local_path(str(root_value or ""))
    root = _case_safe_existing_path(local) if local is not None else None
    return (root if root is not None and root.is_dir() else None), vcs.casefold()


def _registered_nested_roots(
    status_seed: dict[str, Any], workspace_root: Optional[Path], vcs: str
) -> list[Path]:
    if workspace_root is None:
        return []
    paths: set[str] = set()
    provenance = status_seed.get("provenance")
    target = provenance.get("target") if isinstance(provenance, dict) else {}
    target = target if isinstance(target, dict) else {}
    for name in ("submodules", "externals"):
        values = target.get(name)
        for item in values if isinstance(values, list) else []:
            if isinstance(item, dict) and item.get("path"):
                paths.add(str(item["path"]))
    gitmodules = workspace_root / ".gitmodules"
    if vcs == "git" and gitmodules.exists():
        for match in re.finditer(r"^\s*path\s*=\s*(.+?)\s*$", _read_text(gitmodules), flags=re.MULTILINE):
            paths.add(match.group(1))
    roots: list[Path] = []
    for value in sorted(paths):
        local = _to_local_path(value)
        resolved = _case_safe_existing_path(
            local if local is not None else workspace_root / value
        )
        if resolved is not None and resolved.is_dir():
            roots.append(resolved)
    return roots


def _git_delphi_files(repo_root: Optional[Path]) -> list[Path]:
    if repo_root is None:
        return []
    try:
        raw = _run_git(
            repo_root,
            ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        )
    except RuntimeError:
        return []
    result: list[Path] = []
    for relative in str(raw or "").split("\0"):
        if Path(relative).suffix.lower() not in (".pas", ".dpr", ".dpk", ".inc"):
            continue
        resolved = _case_safe_existing_path(repo_root / relative)
        if resolved is not None and resolved.is_file():
            result.append(resolved)
    return result


def _unique_basename_index(paths: Iterable[Path], repo_root: Optional[Path]) -> dict[str, str]:
    seen: dict[str, Optional[str]] = {}
    for path in paths:
        key = path.name.lower()
        display = (
            path.relative_to(repo_root).as_posix()
            if repo_root is not None and path.is_relative_to(repo_root)
            else str(path).replace("\\", "/")
        )
        if key not in seen:
            seen[key] = display
        elif seen[key] is not None and seen[key].lower() != display.lower():
            seen[key] = None
    return {key: value for key, value in seen.items() if value is not None}


def _build_ownership_context(
    out_root: Path,
    status_seed: dict[str, Any],
    legacy_repo_root: Optional[Path],
) -> dict[str, Any]:
    workspace_root, vcs = _workspace_context(status_seed, legacy_repo_root)
    policy = _resolved_analysis_policy(status_seed)
    policy_roots: list[tuple[str, Path]] = []
    for ownership, values in (
        ("project", policy["project_roots"]),
        ("third_party", policy["third_party_roots"]),
    ):
        for value in values:
            local = _to_local_path(value)
            resolved = (
                _case_safe_existing_path(local)
                if local is not None
                else None
            )
            if resolved is not None and resolved.is_dir():
                policy_roots.append((ownership, resolved))

    project_files, project_file, project_dir = _project_source_files(status_seed)
    search_paths = _pal_search_paths(out_root, project_dir)
    source_files: list[Path] = []
    for canonical in project_files:
        source_files.append(Path(canonical))
    workspace_files = (
        _git_delphi_files(workspace_root)
        if vcs == "git"
        else delphi_source_files(workspace_root)
        if workspace_root is not None
        else []
    )
    basename_index = _unique_basename_index(
        [*workspace_files, *source_files], workspace_root
    )
    base_dirs = [
        path
        for path in [project_dir, workspace_root, *search_paths]
        if isinstance(path, Path)
    ]
    return {
        "workspace_root": workspace_root,
        "vcs": vcs,
        "project_file": project_file,
        "project_dir": project_dir,
        "project_files": project_files,
        "search_paths": search_paths,
        "base_dirs": base_dirs,
        "nested_roots": _registered_nested_roots(
            status_seed, workspace_root, vcs
        ),
        "basename_index": basename_index,
        "policy_roots": policy_roots,
        "policy_resolution": {},
    }


def _resolve_ownership_path(raw_path: str, context: dict[str, Any]) -> Optional[Path]:
    value = raw_path.strip()
    if not value:
        return None
    local = _to_local_path(value)
    if local is not None:
        return _case_safe_existing_path(local)
    normalized = value.replace("\\", "/")
    for base in context["base_dirs"]:
        resolved = _case_safe_existing_path(base / normalized)
        if resolved is not None and resolved.is_file():
            return resolved

    if "/" not in normalized:
        mapped = context["basename_index"].get(normalized.casefold())
        if mapped:
            local = _to_local_path(mapped)
            resolved = _case_safe_existing_path(
                local
                if local is not None
                else context["workspace_root"] / mapped
            )
            if resolved is not None and resolved.is_file():
                return resolved

    candidates: dict[str, tuple[Path, str, Path]] = {}
    for ownership, root in context["policy_roots"]:
        resolved = _case_safe_existing_path(root / normalized)
        if resolved is not None and resolved.is_file():
            candidates[
                "|".join(
                    (
                        _canonical_path(resolved),
                        ownership,
                        _canonical_path(root),
                    )
                )
            ] = (resolved, ownership, root)
    if len(candidates) == 1:
        resolved, ownership, root = next(iter(candidates.values()))
        context["policy_resolution"][_canonical_path(resolved)] = (
            ownership,
            root,
        )
        return resolved
    return None


def _classify_ownership(path: Optional[Path], context: dict[str, Any]) -> str:
    if path is None:
        return "unknown"
    canonical = _canonical_path(path)
    policy_resolution = context["policy_resolution"].get(canonical)
    if policy_resolution is not None:
        return str(policy_resolution[0])
    workspace_root = context["workspace_root"]
    for root in context["nested_roots"]:
        if path.is_relative_to(root):
            return "third_party"
    if workspace_root is None:
        return "project" if canonical in context["project_files"] else "third_party"
    if not path.is_relative_to(workspace_root):
        return "third_party"
    if canonical in context["project_files"]:
        return "project"
    return "repository"


def _ownership_root(
    path: Optional[Path], ownership: str, context: dict[str, Any]
) -> Optional[Path]:
    if path is None or ownership == "unknown":
        return None
    policy_resolution = context["policy_resolution"].get(_canonical_path(path))
    if policy_resolution is not None:
        return policy_resolution[1]
    if ownership == "project":
        return context["project_dir"]
    if ownership == "repository":
        return context["workspace_root"]
    nested_roots = [
        root for root in context["nested_roots"] if path.is_relative_to(root)
    ]
    if nested_roots:
        return max(nested_roots, key=lambda root: len(root.parts))
    search_roots = [
        root for root in context["search_paths"] if path.is_relative_to(root)
    ]
    if search_roots:
        return max(search_roots, key=lambda root: len(root.parts))
    return path.parent


def _ownership_root_text(root: Optional[Path]) -> Optional[str]:
    return str(root).replace("\\", "/") if root is not None else None


def _display_ownership_path(
    raw_path: str, resolved: Optional[Path], context: dict[str, Any]
) -> str:
    workspace_root = context["workspace_root"]
    if (
        resolved is not None
        and workspace_root is not None
        and resolved.is_relative_to(workspace_root)
    ):
        return resolved.relative_to(workspace_root).as_posix()
    return _normalize_path_value(
        raw_path,
        repo_root=workspace_root,
        base_dirs=context["base_dirs"],
        basename_index=context["basename_index"],
    )


def _normalize_findings_ownership(
    fi_jsonl_path: Path,
    pal_jsonl_path: Path,
    *,
    out_root: Path,
    status_seed: dict[str, Any],
    repo_root: Optional[Path],
) -> None:
    context = _build_ownership_context(out_root, status_seed, repo_root)
    if fi_jsonl_path.exists():
        records: list[dict[str, Any]] = []
        for obj in _iter_jsonl(fi_jsonl_path):
            item = dict(obj)
            raw = str(item.get("file") or item.get("path") or "").strip()
            resolved = _resolve_ownership_path(raw, context)
            ownership = _classify_ownership(resolved, context)
            item["ownership"] = ownership
            item["ownership_root"] = _ownership_root_text(
                _ownership_root(resolved, ownership, context)
            )
            item["path"] = _display_ownership_path(raw, resolved, context)
            records.append(item)
        _write_jsonl(fi_jsonl_path, records)
    if pal_jsonl_path.exists():
        records = []
        for obj in _iter_jsonl(pal_jsonl_path):
            item = dict(obj)
            raw = str(item.get("path") or "").strip()
            resolved = _resolve_ownership_path(raw, context)
            ownership = _classify_ownership(resolved, context)
            item["ownership"] = ownership
            item["ownership_root"] = _ownership_root_text(
                _ownership_root(resolved, ownership, context)
            )
            item["path"] = (
                _display_ownership_path(raw or str(resolved), resolved, context)
                if resolved is not None or raw
                else None
            )
            records.append(item)
        _write_jsonl(pal_jsonl_path, records)


def _matching_path_mask(path: str, masks: list[str]) -> Optional[str]:
    normalized = path.replace("/", "\\").lower()
    for mask in masks:
        normalized_mask = mask.replace("/", "\\").lower()
        if fnmatch.fnmatchcase(normalized, normalized_mask):
            return mask
    return None


def _apply_report_path_masks(
    fi_jsonl_path: Path, pal_jsonl_path: Path, masks: list[str]
) -> None:
    for path in (fi_jsonl_path, pal_jsonl_path):
        if not path.exists():
            continue
        records: list[dict[str, Any]] = []
        for obj in _iter_jsonl(path):
            item = dict(obj)
            current = item.get("report_policy")
            if isinstance(current, dict) and current.get("reason") == "path_mask":
                item.pop("report_policy", None)
            value = str(item.get("path") or item.get("file") or "").strip()
            matched = _matching_path_mask(value, masks) if value else None
            if matched is not None:
                item["report_policy"] = {
                    "disposition": "ignored",
                    "reason": "path_mask",
                    "value": matched,
                }
            records.append(item)
        _write_jsonl(path, records)


_PAL_VERIFIED_RULE_ALIASES = {
    "9.21.3": {
        (
            "warnings",
            "Set before passed as out parameter",
        ): "WARN54",
        (
            "strong-warnings",
            'Possible bad typecast (for objects: consider using "as")',
        ): "STWA6",
        (
            "optimization",
            'Parameter is "var", can be changed to "out"',
        ): "OPTI8",
    },
    "9.21.3.0": {
        (
            "warnings",
            "Set before passed as out parameter",
        ): "WARN54",
        (
            "strong-warnings",
            'Possible bad typecast (for objects: consider using "as")',
        ): "STWA6",
        (
            "optimization",
            'Parameter is "var", can be changed to "out"',
        ): "OPTI8",
    },
}

_PAL_REPORT_NAMES = {
    "warnings": "Warnings",
    "strong-warnings": "Strong Warnings",
    "optimization": "Optimization",
}


def _pal_report_name(obj: dict[str, Any]) -> str:
    report = str(obj.get("report") or "").strip().replace("\\", "/")
    report_name = posixpath.basename(report)
    report_stem = posixpath.splitext(report_name)[0]
    if report_stem:
        return report_stem
    severity = str(obj.get("severity") or "").strip().lower()
    return {
        "warning": "Warnings",
        "strong-warning": "Strong Warnings",
        "optimization": "Optimization",
    }.get(severity, "Unknown Report")


def _pal_report_identity(obj: dict[str, Any]) -> str:
    return _slug_id(_pal_report_name(obj))


def _pal_rule_identity(
    obj: dict[str, Any], *, pal_version: str
) -> tuple[str, Optional[str]]:
    report_name = _pal_report_name(obj)
    report_identity = _pal_report_identity(obj)
    section = str(obj.get("section") or "").strip()
    exact_identity = _sha256_text(report_name + "\0" + section)[:16]
    canonical = (
        f"PAL.{report_identity}.{_slug_id(section)}-{exact_identity}"
    )
    verified = _PAL_VERIFIED_RULE_ALIASES.get(pal_version, {})
    return canonical, verified.get((report_identity, section))


def _pal_registered_aliases(pal_version: str) -> dict[str, str]:
    aliases: dict[str, str] = {}
    for (report_identity, section), code in (
        _PAL_VERIFIED_RULE_ALIASES.get(pal_version, {}).items()
    ):
        report_name = _PAL_REPORT_NAMES.get(
            report_identity, report_identity
        )
        canonical, _ = _pal_rule_identity(
            {
                "report": report_name + ".xml",
                "section": section,
            },
            pal_version="",
        )
        aliases[code] = canonical
    return aliases


def _pal_xml_rule_catalog(pal_jsonl_path: Path) -> dict[str, str]:
    rules: dict[str, str] = {}
    for report_path in sorted(pal_jsonl_path.parent.rglob("*.xml")):
        try:
            root = ElementTree.parse(report_path).getroot()
        except (ElementTree.ParseError, OSError):
            continue
        if root.tag.rsplit("}", 1)[-1] != "report":
            continue
        for section in root.iter():
            if section.tag.rsplit("}", 1)[-1] != "section":
                continue
            section_name = str(section.get("name") or "").strip()
            if not section_name:
                continue
            canonical, _ = _pal_rule_identity(
                {
                    "report": report_path.name,
                    "section": section_name,
                },
                pal_version="",
            )
            rules[canonical.lower()] = canonical
    return rules


def _normalized_rule_id(obj: dict[str, Any], *, pal_version: str = "") -> str:
    code = str(obj.get("code") or "").strip()
    if code:
        return f"FI.{code.upper()}"
    return _pal_rule_identity(obj, pal_version=pal_version)[0]


def _is_advisory_metric(obj: dict[str, Any]) -> bool:
    section = str(obj.get("section") or "").strip().lower()
    phrases = (
        "method length",
        "routine length",
        "parameter count",
        "nesting depth",
        "cyclomatic complexity",
        "too many parameters",
        "too many statements",
        "deeply nested",
        "long methods",
        "long routines",
    )
    return any(phrase in section for phrase in phrases)


def _apply_report_projections(
    fi_jsonl_path: Path,
    pal_jsonl_path: Path,
    analysis_policy: dict[str, Any],
    *,
    pal_version: str = "",
    pal_requested: bool = True,
) -> None:
    gate_ownership = set(analysis_policy["gate_ownership"])
    gate_metrics = {
        str(value).strip().lower()
        for value in analysis_policy.get("gate_metrics") or []
    }
    fixinsight_ignore = {
        str(value).strip().upper()
        for value in analysis_policy.get("fixinsight_ignore") or []
    }
    pal_ignore_requested = [
        str(value).strip()
        for value in analysis_policy.get("pal_ignore_rules") or []
    ]
    if not pal_requested and pal_jsonl_path.exists():
        _write_jsonl(pal_jsonl_path, [])
    pal_records = (
        [dict(obj) for obj in _iter_jsonl(pal_jsonl_path)]
        if pal_jsonl_path.exists()
        else []
    )
    pal_rules: dict[str, str] = {}
    pal_codes: dict[str, set[str]] = {}
    resolved_pal_ignore: dict[str, str] = {}
    unmatched: list[str] = []
    ambiguous: list[str] = []
    if pal_requested and pal_jsonl_path.exists():
        pal_rules.update(_pal_xml_rule_catalog(pal_jsonl_path))
        for code, canonical in _pal_registered_aliases(
            pal_version
        ).items():
            pal_rules[canonical.lower()] = canonical
            pal_codes.setdefault(code.upper(), set()).add(canonical)
        for item in pal_records:
            canonical, native_code = _pal_rule_identity(
                item, pal_version=pal_version
            )
            pal_rules[canonical.lower()] = canonical
            if native_code:
                pal_codes.setdefault(native_code.upper(), set()).add(
                    canonical
                )
        for requested in pal_ignore_requested:
            canonical = pal_rules.get(requested.lower())
            if canonical:
                resolved_pal_ignore[canonical.lower()] = requested
                continue
            code_matches = pal_codes.get(requested.upper(), set())
            if len(code_matches) == 1:
                canonical = next(iter(code_matches))
                resolved_pal_ignore[canonical.lower()] = requested
            elif len(code_matches) > 1:
                ambiguous.append(requested)
            else:
                unmatched.append(requested)
        if unmatched or ambiguous:
            details = []
            if unmatched:
                details.append("unmatched: " + ", ".join(unmatched))
            if ambiguous:
                details.append("ambiguous: " + ", ".join(ambiguous))
            available_rules = (
                ", ".join(sorted(pal_rules.values())) or "<none>"
            )
            available_codes = ", ".join(sorted(pal_codes)) or "<none>"
            raise ValueError(
                "Invalid Pascal Analyzer ignore rule(s) ("
                + "; ".join(details)
                + "). Available canonical rules: "
                + available_rules
                + ". Verified native codes: "
                + available_codes
            )
    for path in (fi_jsonl_path, pal_jsonl_path):
        if not path.exists():
            continue
        records: list[dict[str, Any]] = []
        for obj in _iter_jsonl(path):
            item = dict(obj)
            is_fixinsight = bool(str(item.get("code") or "").strip())
            item["normalized_rule"] = _normalized_rule_id(
                item, pal_version=pal_version
            )
            if not is_fixinsight:
                _, native_code = _pal_rule_identity(
                    item, pal_version=pal_version
                )
                if native_code:
                    item["pal_code"] = native_code
                else:
                    item.pop("pal_code", None)
            report_policy = item.get("report_policy")
            if (
                isinstance(report_policy, dict)
                and report_policy.get("reason")
                in ("fixinsight_ignore", "pal_rule_ignore")
            ):
                item.pop("report_policy", None)
                report_policy = None
            code = str(item.get("code") or "").strip().upper()
            if code and code in fixinsight_ignore and not isinstance(
                report_policy, dict
            ):
                report_policy = {
                    "disposition": "ignored",
                    "reason": "fixinsight_ignore",
                    "value": code,
                }
                item["report_policy"] = report_policy
            normalized_rule = item["normalized_rule"].lower()
            if (
                not is_fixinsight
                and normalized_rule in resolved_pal_ignore
                and not isinstance(report_policy, dict)
            ):
                report_policy = {
                    "disposition": "ignored",
                    "reason": "pal_rule_ignore",
                    "value": item["normalized_rule"],
                    "matched": resolved_pal_ignore[normalized_rule],
                }
                item["report_policy"] = report_policy
            ownership = str(item.get("ownership") or "unknown")
            if ownership == "unknown":
                projection = "unknown"
            elif (
                isinstance(report_policy, dict)
                and report_policy.get("disposition") == "ignored"
            ):
                projection = "ignored"
            else:
                if ownership not in gate_ownership:
                    projection = "external"
                elif (
                    _is_advisory_metric(item)
                    and item["normalized_rule"].lower() not in gate_metrics
                ):
                    projection = "advisory_metrics"
                else:
                    projection = "actionable"
            item["report_projection"] = projection
            records.append(item)
        _write_jsonl(path, records)


def _repo_unique_basename_index(repo_root: Path) -> dict[str, str]:
    return _unique_basename_index(_git_delphi_files(repo_root), repo_root)


def _write_triage_changed(out_root: Path, *, title: str, summary: dict[str, Any], fi_jsonl_path: Path, pal_jsonl_path: Path) -> Path:
    triage_path = out_root / "triage-changed.md"

    provenance = summary.get("provenance")
    target = provenance.get("target") if isinstance(provenance, dict) else None
    target = target if isinstance(target, dict) else None
    if target is not None:
        root_value = _to_local_path(str(target.get("root") or ""))
        repo_root = root_value.resolve() if root_value is not None else None
        vcs = str(target.get("vcs") or "none")
        changed_value = target.get("changed_files")
        if vcs == "none" and changed_value is None:
            _write_text(
                triage_path,
                f"# {title} (changed files)\n\nNo-VCS changed-file scope is not applicable.\n",
            )
            return triage_path
        if repo_root is None or not isinstance(changed_value, list):
            diagnostic = str(target.get("diagnostic") or "metadata unavailable")
            _write_text(
                triage_path,
                f"# {title} (changed files)\n\n{vcs.upper()} changed-file scope unavailable: {diagnostic}.\n",
            )
            return triage_path
        changed_files = {
            str(path).replace("\\", "/") for path in changed_value
        }
    else:
        repo_root = _find_git_root(out_root)
        vcs = "git"
        if repo_root is None:
            _write_text(triage_path, f"# {title} (changed files)\n\nGit repo not found; cannot compute changed-file scope.\n")
            return triage_path
        changed_files, err = _git_changed_files(repo_root)
        if err:
            _write_text(triage_path, f"# {title} (changed files)\n\nGit unavailable: {err}\n")
            return triage_path
        changed_files = {p.replace("\\", "/") for p in changed_files}
    changed_sorted = sorted(changed_files)

    lines: list[str] = []
    lines.append(f"# {title} (changed files)")
    lines.append("")
    lines.append(f"- Timestamp: {_utc_now_iso()}")
    if target is not None:
        lines.append(f"- VCS: `{vcs}`")
        lines.append(f"- Workspace root: `{repo_root}`")
    else:
        lines.append(f"- Repo root: `{repo_root}`")
    lines.append(f"- Changed files: {len(changed_sorted)}")
    lines.append("")

    if not changed_sorted:
        lines.append(f"No {vcs.upper()}-changed files detected.")
        lines.append("")
        _write_text(triage_path, "\n".join(lines).rstrip() + "\n")
        return triage_path

    lines.append("## Changed files")
    for p in changed_sorted:
        lines.append(f"- `{p}`")
    lines.append("")

    project_dir: Optional[Path] = None
    proj_raw = str(summary.get("project") or "").strip()
    proj_local = _to_local_path(proj_raw)
    if proj_local is not None:
        project_dir = proj_local.parent
    else:
        cand = repo_root / "projects"
        if cand.exists():
            project_dir = cand

    base_dirs = [x for x in [project_dir, repo_root] if isinstance(x, Path)]

    fi_items: list[str] = []
    if fi_jsonl_path.exists():
        for obj in _iter_actionable_jsonl(fi_jsonl_path):
            norm = str(obj.get("path") or "").strip()
            if norm:
                norm = posixpath.normpath(norm.replace("\\", "/"))
            if not norm:
                file_raw = str(obj.get("file") or "").strip()
                norm = _normalize_to_repo_relative(file_raw, repo_root=repo_root, base_dirs=base_dirs) or ""
            # If we still have an absolute path, try one more time with the normalized value.
            if norm and (norm.startswith("/") or norm.startswith("//") or re.match(r"^[A-Za-z]:/", norm)):
                norm2 = _normalize_to_repo_relative(norm, repo_root=repo_root, base_dirs=base_dirs)
                if norm2:
                    norm = norm2
            if not norm or norm not in changed_files:
                continue
            code = obj.get("code", "?")
            line_no = obj.get("line", "?")
            col_no = obj.get("col", "?")
            msg = obj.get("message", "")
            fi_items.append(f"[{code}] {norm}:{line_no}:{col_no} - {msg}")

    pal_items: list[str] = []
    changed_by_lower = {p.lower(): p for p in changed_files}
    unique_units = (
        _repo_unique_basename_index(repo_root)
        if vcs == "git"
        else _unique_basename_index(delphi_source_files(repo_root), repo_root)
    )
    if pal_jsonl_path.exists():
        for obj in _iter_actionable_jsonl(pal_jsonl_path):
            mod = str(obj.get("module") or "").strip()
            if not mod:
                continue

            norm = str(obj.get("path") or "").strip()
            if norm:
                norm = posixpath.normpath(norm.replace("\\", "/"))
                if norm.startswith("/") or norm.startswith("//") or re.match(r"^[A-Za-z]:/", norm):
                    norm = _normalize_to_repo_relative(
                        norm, repo_root=repo_root, base_dirs=base_dirs
                    ) or ""
                matched_path = changed_by_lower.get(norm.lower()) if norm else None
            else:
                unit_name = Path(mod.replace("\\", "/")).name
                if not unit_name.lower().endswith(".pas"):
                    unit_name += ".pas"
                unique_path = unique_units.get(unit_name.lower())
                matched_path = (
                    changed_by_lower.get(unique_path.lower()) if unique_path else None
                )
            if not matched_path:
                continue
            section = obj.get("section", "")
            line_no = obj.get("line", "?")
            msg = obj.get("message", "")
            pal_items.append(f"[{section}] {matched_path}:{line_no} - {msg}")

    lines.append("## FixInsight (changed files)")
    lines.append(f"- Findings: {len(fi_items)}")
    for item in fi_items[:200]:
        lines.append(f"- {item}")
    lines.append("")

    lines.append("## Pascal Analyzer (changed files)")
    lines.append(f"- Findings: {len(pal_items)}")
    for item in pal_items[:200]:
        lines.append(f"- {item}")
    lines.append("")

    _write_text(triage_path, "\n".join(lines).rstrip() + "\n")
    return triage_path


def _fi_triage_priority(kind: str) -> int:
    k = kind.strip().upper()
    if k == "W":
        return 300
    if k == "C":
        return 200
    if k == "O":
        return 100
    return 50


def _pal_triage_priority(severity: str) -> int:
    s = severity.strip().lower()
    if s in ("strong-warning", "strong_warning", "strongwarning"):
        return 300
    if s == "warning":
        return 200
    if s == "exception":
        return 150
    if s == "hint":
        return 100
    return 80


def _pal_item_priority(severity: str, report: str, section: str, message: str) -> int:
    base = _pal_triage_priority(severity)
    if base <= 0:
        return base

    # `Exception.xml` "Exception Call Tree" is rarely a "fix next" signal; keep it out
    # of the shortlist unless explicitly requested.
    if severity.strip().lower() == "exception":
        if not _truthy_env("DAK_TRIAGE_PAL_INCLUDE_CALL_TREE", False):
            s = (section or "").strip().lower()
            m = (message or "").strip().lower()
            r = (report or "").strip().lower()
            if ("call tree" in s) or ("call tree" in m) or (r == "exception.xml" and s == "exception call tree"):
                return 10

    return base


def _write_triage(out_root: Path, *, title: str, fi_jsonl_path: Path, pal_jsonl_path: Path) -> Path:
    triage_path = out_root / "triage.md"
    top_n = _int_env("DAK_TRIAGE_TOP", 20) or 20
    include_paths = _split_semicolon_patterns(os.environ.get("DAK_TRIAGE_INCLUDE_PATHS", "").strip())
    exclude_paths = _split_semicolon_patterns(os.environ.get("DAK_TRIAGE_EXCLUDE_PATHS", "").strip())

    fi_items: list[dict[str, Any]] = []
    fi_records = list(_iter_actionable_jsonl(fi_jsonl_path)) if fi_jsonl_path.exists() else []
    if fi_records:
        for obj in fi_records:
            path = obj.get("path") or obj.get("file") or "?"
            if not _triage_path_allowed(str(path), include=include_paths, exclude=exclude_paths):
                continue
            kind = str(obj.get("kind") or "").strip()
            fi_items.append(
                {
                    "priority": _fi_triage_priority(kind),
                    "path": str(path),
                    "code": obj.get("code") or "?",
                    "kind": kind,
                    "ownership": str(obj.get("ownership") or "unknown"),
                    "line": obj.get("line") or "?",
                    "col": obj.get("col") or "?",
                    "message": obj.get("message") or "",
                }
            )

    fi_items.sort(key=lambda x: (-int(x["priority"]), str(x["code"]), str(x["path"]), int(x["line"]) if str(x["line"]).isdigit() else 0))
    fi_top = fi_items[:top_n]

    pal_items: list[dict[str, Any]] = []
    pal_records = list(_iter_actionable_jsonl(pal_jsonl_path)) if pal_jsonl_path.exists() else []
    if pal_records:
        for obj in pal_records:
            severity = str(obj.get("severity") or "").strip()
            path = obj.get("path") or obj.get("module") or "?"
            if not _triage_path_allowed(str(path), include=include_paths, exclude=exclude_paths):
                continue
            section = obj.get("section") or ""
            message = obj.get("message") or ""
            report = obj.get("report") or ""
            pal_items.append(
                {
                    "priority": _pal_item_priority(severity, str(report), str(section), str(message)),
                    "path": str(path),
                    "severity": severity,
                    "ownership": str(obj.get("ownership") or "unknown"),
                    "section": section,
                    "module": obj.get("module") or "?",
                    "line": obj.get("line") or "?",
                    "message": message,
                }
            )

    pal_items.sort(key=lambda x: (-int(x["priority"]), str(x["severity"]), str(x["path"]), int(x["line"]) if str(x["line"]).isdigit() else 0))
    pal_top = pal_items[:top_n]

    lines: list[str] = []
    lines.append(f"# {title} triage")
    lines.append("")
    lines.append(f"- Timestamp: {_utc_now_iso()}")
    lines.append(
        f"- FixInsight findings: {len(fi_records)} "
        f"(eligible {len(fi_items)}, showing top {min(top_n, len(fi_items))})"
    )
    lines.append(
        f"- Pascal Analyzer findings: {len(pal_records)} "
        f"(eligible {len(pal_items)}, showing top {min(top_n, len(pal_items))})"
    )
    lines.append(
        f"- Ownership: {_ownership_text(_ownership_counts([*fi_records, *pal_records]))}"
    )
    lines.append("")

    lines.append("## FixInsight")
    if not fi_top:
        lines.append("No FixInsight findings.")
        lines.append("")
    else:
        by_kind: dict[str, list[dict[str, Any]]] = {"W": [], "C": [], "O": [], "other": []}
        for it in fi_top:
            k = str(it.get("kind") or "").strip().upper()
            if k in ("W", "C", "O"):
                by_kind[k].append(it)
            else:
                by_kind["other"].append(it)

        def emit_kind(kind: str, heading: str) -> None:
            items = by_kind.get(kind) or []
            lines.append(f"### {heading}")
            if not items:
                lines.append("No findings.")
                lines.append("")
                return
            groups: dict[str, list[dict[str, Any]]] = {}
            for it in items:
                groups.setdefault(str(it["path"]), []).append(it)
            for path, items2 in groups.items():
                lines.append(f"#### `{path}`")
                for it2 in items2:
                    lines.append(
                        f"- [{it2['code']}] [{it2['ownership']}] "
                        f"{it2['line']}:{it2['col']} - {it2['message']}"
                    )
                lines.append("")

        emit_kind("W", "W findings (defects)")
        emit_kind("C", "C findings (maintainability)")
        emit_kind("O", "O findings (hygiene)")
        if by_kind["other"]:
            emit_kind("other", "Other findings")

    lines.append("## Pascal Analyzer")
    if not pal_top:
        lines.append("No Pascal Analyzer findings.")
        lines.append("")
    else:
        groups2: dict[str, list[dict[str, Any]]] = {}
        for it in pal_top:
            groups2.setdefault(str(it["path"]), []).append(it)
        for path, items in groups2.items():
            lines.append(f"### `{path}`")
            for it in items:
                section = it.get("section") or ""
                lines.append(
                    f"- [{it['severity']}] [{it['ownership']}] "
                    f"{it['line']} - {section}: {it['message']}"
                )
            lines.append("")

    _write_text(triage_path, "\n".join(lines).rstrip() + "\n")

    if _truthy_env("DAK_TRIAGE_SNIPPETS", False):
        try:
            _write_triage_snippets(out_root, title=title, fi_top=fi_top, pal_top=pal_top)
        except Exception as e:
            # Keep postprocess resilient; snippets are an optional convenience.
            print(f"WARNING: failed to write triage snippets: {e}", file=sys.stderr)
    return triage_path


def _write_triage_snippets(
    out_root: Path,
    *,
    title: str,
    fi_top: list[dict[str, Any]],
    pal_top: list[dict[str, Any]],
) -> Path:
    snippets_path = out_root / "triage-snippets.md"

    repo_root = _find_git_root(out_root)
    ctx_lines = _int_env("DAK_TRIAGE_SNIPPET_CONTEXT", 2)
    if ctx_lines is None:
        ctx_lines = 2
    if ctx_lines < 0:
        ctx_lines = 0

    max_bytes = _int_env("DAK_TRIAGE_SNIPPET_MAX_BYTES", 200_000)
    if max_bytes is None:
        max_bytes = 200_000
    if max_bytes < 0:
        max_bytes = 0

    file_cache: dict[str, list[str]] = {}

    def try_load_lines(path_str: str) -> Optional[tuple[Path, list[str]]]:
        if repo_root is None:
            return None
        s = (path_str or "").strip()
        if not s or s in ("?", "unknown"):
            return None

        # Only repo-relative paths are eligible (avoid leaking huge absolute paths into output
        # and avoid reading files outside the repo).
        norm = s.replace("\\", "/")
        if norm.startswith("/") or norm.startswith("//") or _looks_like_windows_path(norm):
            return None

        p = (repo_root / norm).resolve()
        try:
            if not p.is_relative_to(repo_root):
                return None
        except Exception:
            return None

        if not p.exists() or not p.is_file():
            return None

        key = str(p)
        hit = file_cache.get(key)
        if hit is not None:
            return p, hit

        # Delphi sources are often UTF-8 these days, but not always; use a permissive decode.
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            text = p.read_text(encoding="latin-1", errors="replace")
        lines = text.splitlines()
        file_cache[key] = lines
        return p, lines

    def snippet_for(lines: list[str], line_no: int) -> str:
        if line_no <= 0:
            return ""
        idx = line_no - 1
        if idx >= len(lines):
            return ""
        start = max(0, idx - ctx_lines)
        end = min(len(lines) - 1, idx + ctx_lines)
        width = len(str(end + 1))

        out: list[str] = []
        for i in range(start, end + 1):
            mark = "=>" if i == idx else "  "
            out.append(f"{mark}{i + 1:>{width}}: {lines[i]}")
        return "\n".join(out).rstrip()

    buf: list[str] = []
    used_bytes = 0
    truncated = False

    def block_bytes(lines: list[str]) -> int:
        s = "\n".join(lines).rstrip() + "\n"
        return len(s.encode("utf-8", errors="replace"))

    def try_add_block(lines: list[str]) -> bool:
        nonlocal used_bytes, truncated
        b = block_bytes(lines)
        if used_bytes + b > max_bytes:
            truncated = True
            return False
        buf.extend(lines)
        used_bytes += b
        return True

    header = [
        f"# {title} triage (snippets)",
        "",
        f"- Timestamp: {_utc_now_iso()}",
        f"- Repo root: `{repo_root}`" if repo_root is not None else "- Repo root: `<unknown>`",
        f"- Context lines: {ctx_lines}",
        f"- Max bytes: {max_bytes}",
        "",
        "Snippets are best-effort and only emitted for repo-relative paths that exist on disk.",
        "",
    ]
    try_add_block(header)

    def emit_section(name: str, items: list[dict[str, Any]], *, is_fixinsight: bool) -> None:
        nonlocal truncated
        if truncated:
            return
        if not try_add_block([f"## {name}", ""]):
            return
        if not items:
            try_add_block([f"No {name} findings.", ""])
            return

        def emit_group(path: str, group_items: list[dict[str, Any]], *, path_heading: str) -> bool:
            nonlocal truncated
            if truncated:
                return False
            if not try_add_block([f"{path_heading} `{path}`", ""]):
                return False
            for it in group_items:
                if truncated:
                    return False
                line_val = it.get("line")
                try:
                    line_no = int(line_val) if line_val is not None else 0
                except Exception:
                    line_no = 0
                line_disp = str(line_val) if line_val is not None else "?"
                if line_no > 0:
                    line_disp = str(line_no)

                if is_fixinsight:
                    code = it.get("code", "?")
                    col = it.get("col", "?")
                    msg = it.get("message", "")
                    summary = f"- [{code}] {line_disp}:{col} - {msg}"
                else:
                    sev = it.get("severity", "?")
                    section = it.get("section", "")
                    msg = it.get("message", "")
                    summary = f"- [{sev}] {line_disp} - {section}: {msg}"

                snip_lines: list[str] = [summary]
                loaded = try_load_lines(path)
                if loaded is not None and line_no > 0:
                    _, src_lines = loaded
                    snip = snippet_for(src_lines, line_no)
                    if snip:
                        snip_lines += ["", "```delphi", snip, "```"]
                if len(snip_lines) == 1:
                    snip_lines[0] += " (snippet unavailable)"
                snip_lines.append("")
                if not try_add_block(snip_lines):
                    return False
            return True

        def emit_grouped_by_path(group_items: list[dict[str, Any]], *, path_heading: str) -> None:
            nonlocal truncated
            groups: dict[str, list[dict[str, Any]]] = {}
            for it in group_items:
                groups.setdefault(str(it.get("path") or "?"), []).append(it)
            for path, items2 in groups.items():
                if not emit_group(path, items2, path_heading=path_heading):
                    return

        if is_fixinsight:
            by_kind: dict[str, list[dict[str, Any]]] = {"W": [], "C": [], "O": [], "other": []}
            for it in items:
                k = str(it.get("kind") or "").strip().upper()
                if k in ("W", "C", "O"):
                    by_kind[k].append(it)
                else:
                    by_kind["other"].append(it)

            for kind, heading in (
                ("W", "### W findings (defects)"),
                ("C", "### C findings (maintainability)"),
                ("O", "### O findings (hygiene)"),
            ):
                if truncated:
                    return
                if not try_add_block([heading, ""]):
                    return
                if not by_kind[kind]:
                    if not try_add_block(["No findings.", ""]):
                        return
                    continue
                emit_grouped_by_path(by_kind[kind], path_heading="####")

            if by_kind["other"] and not truncated:
                if try_add_block(["### Other findings", ""]):
                    emit_grouped_by_path(by_kind["other"], path_heading="####")
            return

        emit_grouped_by_path(items, path_heading="###")

    emit_section("FixInsight", fi_top, is_fixinsight=True)
    emit_section("Pascal Analyzer", pal_top, is_fixinsight=False)

    if truncated:
        # Ensure we end on a clean paragraph; avoid leaving open code fences by truncating at block boundaries.
        try_add_block(["", "_Output truncated due to `DAK_TRIAGE_SNIPPET_MAX_BYTES` budget._", ""])

    _write_text(snippets_path, "\n".join(buf).rstrip() + "\n")
    return snippets_path


def _git_capture(repo_root: Path, args: list[str]) -> Optional[str]:
    try:
        p = subprocess.run(
            ["git"] + args,
            cwd=str(repo_root),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        return None
    if p.returncode != 0:
        return None
    return (p.stdout or b"").decode("utf-8", errors="replace").strip() or None


def _build_history_context(run_ctx: Any) -> dict[str, Any]:
    ctx = run_ctx if isinstance(run_ctx, dict) else {}
    out: dict[str, Any] = {}
    for k in ("platform", "config", "delphi"):
        v = ctx.get(k)
        if v:
            out[k] = v
    tools = ctx.get("tools") if isinstance(ctx.get("tools"), dict) else {}
    tools_out: dict[str, Any] = {}
    for k in ("pal_version", "pal_compiler_target"):
        v = tools.get(k)
        if v:
            tools_out[k] = v
    if tools_out:
        out["tools"] = tools_out
    return out


def _update_history_and_trend(
    out_root: Path,
    *,
    title: str,
    summary: dict[str, Any],
    snapshot: dict[str, Any],
    repo_root: Optional[Path],
) -> tuple[Path, Path, bool]:
    history_path = out_root / "history.jsonl"
    trend_path = out_root / "trend.md"

    summary_ts = str(summary.get("timestamp") or "").strip() or str(snapshot.get("created_at") or "").strip()

    entries: list[dict[str, Any]] = []
    if history_path.exists():
        for line in history_path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                if isinstance(obj, dict):
                    entries.append(obj)
            except Exception:
                continue

    appended = False
    last_ts = str(entries[-1].get("summary_timestamp") or "").strip() if entries else ""
    if summary_ts and summary_ts == last_ts:
        # Avoid writing duplicate history when postprocess is re-run on the same outputs.
        appended = False
    else:
        git_info: dict[str, Any] = {}
        if repo_root is not None:
            head = _git_capture(repo_root, ["rev-parse", "HEAD"])
            branch = _git_capture(repo_root, ["rev-parse", "--abbrev-ref", "HEAD"])
            changed_files, err = _git_changed_files(repo_root)
            git_info = {
                "root": str(repo_root),
                "head": head,
                "branch": branch,
                "dirty": bool(changed_files) if err is None else None,
                "changed_files": len(changed_files) if err is None else None,
            }
            git_info = {k: v for k, v in git_info.items() if v is not None and v != ""}

        pal_totals = snapshot.get("pascal_analyzer", {}).get("totals", {}) or {}
        fi_total = snapshot.get("fixinsight", {}).get("total")

        entry: dict[str, Any] = {
            "timestamp": _utc_now_iso(),
            "summary_timestamp": summary_ts,
            "project": title,
            "context": _build_history_context(snapshot.get("run_context")),
            "fixinsight": {"total": fi_total, "counts_by_code": snapshot.get("fixinsight", {}).get("counts_by_code", {})},
            "pascal_analyzer": {"totals": pal_totals},
            "ownership": snapshot.get("ownership") or _empty_ownership_counts(),
            "raw": snapshot.get("raw") or {},
        }
        if git_info:
            entry["git"] = git_info

        entries.append(entry)
        # Keep the history bounded to avoid unbounded growth.
        if len(entries) > 200:
            entries = entries[-200:]
        _write_jsonl(history_path, entries)
        appended = True

    # Emit a human-readable trend view of recent runs.
    show_n = _int_env("DAK_TREND_N", 20) or 20
    recent = entries[-show_n:] if entries else []
    lines: list[str] = []
    lines.append(f"# {title} trend")
    lines.append("")
    lines.append(f"- Updated: {_utc_now_iso()}")
    lines.append(f"- Entries: {len(entries)} (showing last {len(recent)})")
    if recent:
        lines.append(f"- Latest ownership: {_ownership_text(recent[-1].get('ownership'))}")
        raw = recent[-1].get("raw")
        raw = raw if isinstance(raw, dict) else {}
        lines.append(f"- Latest raw ownership: {_ownership_text(raw.get('ownership'))}")
    lines.append("")
    lines.append("| Summary timestamp | FI total | FI Δ | PAL strong | Δ | PAL warnings | Δ | PAL optimizations | Δ | PAL total | Δ |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    prev_fi: Optional[int] = None
    prev_strong: Optional[int] = None
    prev_warn: Optional[int] = None
    prev_optimizations: Optional[int] = None
    prev_total: Optional[int] = None
    for e in recent:
        ts = str(e.get("summary_timestamp") or e.get("timestamp") or "").strip() or "?"
        fi = e.get("fixinsight", {}) if isinstance(e.get("fixinsight"), dict) else {}
        pal = e.get("pascal_analyzer", {}) if isinstance(e.get("pascal_analyzer"), dict) else {}
        fi_total = fi.get("total")
        try:
            fi_total_i = int(fi_total) if fi_total is not None else None
        except Exception:
            fi_total_i = None
        totals = pal.get("totals") if isinstance(pal.get("totals"), dict) else {}
        strong = totals.get("strong_warnings")
        warn = totals.get("warnings")
        optimizations = totals.get("optimizations")
        total = totals.get("total")
        try:
            strong_i = int(strong) if strong is not None else None
        except Exception:
            strong_i = None
        try:
            warn_i = int(warn) if warn is not None else None
        except Exception:
            warn_i = None
        try:
            optimizations_i = int(optimizations) if optimizations is not None else None
        except Exception:
            optimizations_i = None
        try:
            total_i = int(total) if total is not None else None
        except Exception:
            total_i = None

        def delta(cur: Optional[int], prev: Optional[int]) -> str:
            if cur is None or prev is None:
                return ""
            d = cur - prev
            return f"{d:+d}" if d else "0"

        row = [
            ts,
            str(fi_total_i) if fi_total_i is not None else "?",
            delta(fi_total_i, prev_fi),
            str(strong_i) if strong_i is not None else "?",
            delta(strong_i, prev_strong),
            str(warn_i) if warn_i is not None else "?",
            delta(warn_i, prev_warn),
            str(optimizations_i) if optimizations_i is not None else "?",
            delta(optimizations_i, prev_optimizations),
            str(total_i) if total_i is not None else "?",
            delta(total_i, prev_total),
        ]
        lines.append("| " + " | ".join(row) + " |")

        prev_fi = fi_total_i if fi_total_i is not None else prev_fi
        prev_strong = strong_i if strong_i is not None else prev_strong
        prev_warn = warn_i if warn_i is not None else prev_warn
        prev_optimizations = optimizations_i if optimizations_i is not None else prev_optimizations
        prev_total = total_i if total_i is not None else prev_total

    _write_text(trend_path, "\n".join(lines).rstrip() + "\n")

    return history_path, trend_path, appended


def _fi_findings_to_jsonl(
    findings: Iterable[FixInsightFinding],
    *,
    repo_root: Optional[Path],
    base_dirs: list[Path],
) -> Iterable[dict[str, Any]]:
    for f in findings:
        norm_file = posixpath.normpath(f.file.replace("\\", "/"))
        norm_path = _normalize_path_value(
            f.file,
            repo_root=repo_root,
            base_dirs=base_dirs,
            basename_index={},
        )
        yield {
            "tool": "FixInsight",
            "code": f.code,
            "kind": f.kind,
            "file": norm_file,
            "path": norm_path,
            "line": f.line,
            "col": f.col,
            "message": f.message,
        }


def write_fixinsight_normalized(
    out_fixinsight_dir: Path,
    *,
    repo_root: Optional[Path],
    base_dirs: list[Path],
) -> dict[str, Any]:
    txt_path = out_fixinsight_dir / "fixinsight.txt"
    findings = parse_fixinsight_txt(txt_path)
    if not findings:
        return {"txt_path": str(txt_path), "findings": 0}

    jsonl_path = out_fixinsight_dir / "fi-findings.jsonl"
    md_path = out_fixinsight_dir / "fi-findings.md"

    records = list(_fi_findings_to_jsonl(findings, repo_root=repo_root, base_dirs=base_dirs))
    _write_jsonl(jsonl_path, records)

    md_lines: list[str] = []
    for r in records:
        loc = (r.get("path") or r.get("file") or "?")
        md_lines.append(f"{r.get('code','?')} | {loc}:{r.get('line','?')}:{r.get('col','?')} | {r.get('message','')}")
    _write_text(md_path, "\n".join(md_lines) + "\n")

    w_hashes_raw: set[str] = set()
    w_hashes_norm: set[str] = set()
    w_items_by_raw_hash: dict[str, str] = {}
    w_items_by_norm_hash: dict[str, str] = {}

    for f, r in zip(findings, records):
        if f.kind != "W":
            continue
        raw_hash = _sha1("|".join([str(f.code), str(f.file), str(f.line), str(f.col), str(f.message)]))
        norm_loc = str(r.get("path") or r.get("file") or "")
        norm_hash = _sha1("|".join([str(f.code), norm_loc, str(f.line), str(f.col), str(f.message)]))

        w_hashes_raw.add(raw_hash)
        w_hashes_norm.add(norm_hash)

        display = f"[{f.code}] {norm_loc}:{f.line}:{f.col} - {f.message}"
        w_items_by_raw_hash[raw_hash] = display
        w_items_by_norm_hash[norm_hash] = display

    counts_by_code: dict[str, int] = dict(Counter([f.code for f in findings]))

    return {
        "txt_path": str(txt_path),
        "jsonl_path": str(jsonl_path),
        "md_path": str(md_path),
        "findings": len(findings),
        "counts_by_code": counts_by_code,
        "w_hashes_raw": sorted(w_hashes_raw),
        "w_hashes_norm": sorted(w_hashes_norm),
        "w_items_by_raw_hash": w_items_by_raw_hash,
        "w_items_by_norm_hash": w_items_by_norm_hash,
    }


def _pal_fingerprint(obj: dict[str, Any]) -> str:
    # Canonical identity and location keep PAL deltas stable and actionable.
    parts = [
        str(obj.get("severity", "")),
        str(obj.get("normalized_rule", "")),
        str(obj.get("pal_code", "")),
        str(obj.get("module", "")),
        str(obj.get("line", "")),
        str(obj.get("message", "")),
        str(obj.get("id", "")),
        str(obj.get("kind", "")),
    ]
    return _sha1("|".join(parts))


def _fi_fingerprint(obj: dict[str, Any], *, use_normalized_path: bool) -> str:
    file_key = "path" if use_normalized_path else "file"
    file_val = obj.get(file_key) or obj.get("file") or obj.get("path") or ""
    parts = [
        str(obj.get("code", "")),
        str(file_val),
        str(obj.get("line", "")),
        str(obj.get("col", "")),
        str(obj.get("message", "")),
    ]
    return _sha1("|".join(parts))


def _top_section_counts(pal_jsonl_path: Path, *, severity: str) -> list[dict[str, Any]]:
    if not pal_jsonl_path.exists():
        return []
    ctr: Counter[str] = Counter()
    for obj in _iter_actionable_jsonl(pal_jsonl_path):
        if obj.get("severity") != severity:
            continue
        section = str(obj.get("section", "")).strip()
        if not section:
            continue
        ctr[section] += 1
    return [{"section": s, "count": c} for s, c in ctr.most_common(10)]


def _section_delta(before: list[dict[str, Any]], after: list[dict[str, Any]]) -> list[dict[str, Any]]:
    b = {x["section"]: int(x["count"]) for x in before if "section" in x and "count" in x}
    a = {x["section"]: int(x["count"]) for x in after if "section" in x and "count" in x}
    keys = set(b) | set(a)
    deltas = []
    for k in keys:
        before_count = b.get(k, 0)
        after_count = a.get(k, 0)
        d = after_count - before_count
        if d == 0:
            continue
        deltas.append({"section": k, "before": before_count, "after": after_count, "delta": d})
    deltas.sort(key=lambda x: abs(int(x["delta"])), reverse=True)
    return deltas[:10]


def _code_delta(before: dict[str, int], after: dict[str, int]) -> list[dict[str, Any]]:
    keys = set(before) | set(after)
    rows: list[dict[str, Any]] = []
    for k in keys:
        b = int(before.get(k, 0))
        a = int(after.get(k, 0))
        if a == b:
            continue
        rows.append({"code": k, "before": b, "after": a, "delta": a - b})
    rows.sort(key=lambda x: abs(int(x["delta"])), reverse=True)
    return rows[:10]


def _rule_count_delta(
    before: dict[str, Any], after: dict[str, Any]
) -> list[dict[str, Any]]:
    rows = []
    for rule in sorted(set(before) | set(after)):
        before_count = int(before.get(rule, 0))
        after_count = int(after.get(rule, 0))
        rows.append(
            {
                "rule": rule,
                "before": before_count,
                "after": after_count,
                "delta": after_count - before_count,
            }
        )
    return rows


def _diff_run_context(baseline_ctx: Any, current_ctx: Any) -> list[str]:
    b = baseline_ctx if isinstance(baseline_ctx, dict) else {}
    c = current_ctx if isinstance(current_ctx, dict) else {}

    out: list[str] = []

    def add(label: str, before: Any, after: Any) -> None:
        bv = str(before or "").strip()
        av = str(after or "").strip()
        if not bv or not av:
            return
        if bv.lower() in ("unknown", "?") or av.lower() in ("unknown", "?"):
            return
        if bv == av:
            return
        out.append(f"{label}: {bv} -> {av}")

    add("platform", b.get("platform"), c.get("platform"))
    add("config", b.get("config"), c.get("config"))
    add("delphi", b.get("delphi"), c.get("delphi"))

    bt = b.get("tools") if isinstance(b.get("tools"), dict) else {}
    ct = c.get("tools") if isinstance(c.get("tools"), dict) else {}
    add("pal_version", bt.get("pal_version"), ct.get("pal_version"))
    add("pal_compiler_target", bt.get("pal_compiler_target"), ct.get("pal_compiler_target"))
    add("pal_compiler_switch", bt.get("pal_compiler_switch"), ct.get("pal_compiler_switch"))

    return out


def _render_delta_md(delta: dict[str, Any]) -> str:
    lines: list[str] = []
    title = delta.get("title") or "Static analysis delta"
    lines.append(f"# {title}")
    lines.append("")

    baseline = delta.get("baseline") or {}
    current = delta.get("current") or {}
    lines.append(f"- Baseline: `{baseline.get('path', '')}` ({baseline.get('timestamp', 'unknown')})")
    lines.append(f"- Current: `{current.get('summary_path', '')}` ({current.get('timestamp', 'unknown')})")
    if baseline.get("run_context"):
        ctx = baseline["run_context"]
        lines.append(f"- Baseline context: platform={ctx.get('platform','?')}, config={ctx.get('config','?')}, delphi={ctx.get('delphi','?')}")
    if current.get("run_context"):
        ctx = current["run_context"]
        lines.append(f"- Current context: platform={ctx.get('platform','?')}, config={ctx.get('config','?')}, delphi={ctx.get('delphi','?')}")
    lines.append("")

    mismatches = _diff_run_context(baseline.get("run_context"), current.get("run_context"))
    if mismatches:
        lines.append("## Context mismatch")
        lines.append("Baseline and current analysis contexts differ; deltas and gates may be misleading.")
        for m in mismatches:
            lines.append(f"- {m}")
        lines.append("")

    fi = delta.get("fixinsight") or {}
    lines.append("## FixInsight")
    lines.append(f"- Findings: {fi.get('total_before', '?')} -> {fi.get('total_after', '?')} ({fi.get('total_delta', 0):+d})")
    lines.append(f"- New W-findings: {fi.get('new_w_count', 0)}")
    if fi.get("top_code_deltas"):
        lines.append("- Top code deltas:")
        for row in fi["top_code_deltas"]:
            lines.append(f"  - {row['code']}: {row['before']} -> {row['after']} ({row['delta']:+d})")
    lines.append("")

    pal = delta.get("pascal_analyzer") or {}
    lines.append("## Pascal Analyzer")
    lines.append(f"- Strong warnings: {pal.get('strong_before', '?')} -> {pal.get('strong_after', '?')} ({pal.get('strong_delta', 0):+d})")
    lines.append(f"- Warnings: {pal.get('warnings_before', '?')} -> {pal.get('warnings_after', '?')} ({pal.get('warnings_delta', 0):+d})")
    lines.append(f"- Optimizations: {pal.get('optimizations_before', '?')} -> {pal.get('optimizations_after', '?')} ({pal.get('optimizations_delta', 0):+d})")
    lines.append(f"- Total: {pal.get('total_before', '?')} -> {pal.get('total_after', '?')} ({pal.get('total_delta', 0):+d})")
    if pal.get("top_section_deltas"):
        lines.append("- Top section deltas (warnings):")
        for row in pal["top_section_deltas"]:
            lines.append(f"  - {row['section']}: {row['before']} -> {row['after']} ({row['delta']:+d})")
    lines.append("")

    if pal.get("new_strong"):
        lines.append(f"### New strong warnings ({len(pal['new_strong'])})")
        for item in pal["new_strong"][:20]:
            lines.append(f"- {item}")
        lines.append("")

    if pal.get("new_warnings_count", 0):
        lines.append(f"### New warnings ({pal.get('new_warnings_count', 0)})")
        for item in (pal.get("new_warnings_preview") or [])[:20]:
            lines.append(f"- {item}")
        lines.append("")

    if fi.get("new_w"):
        lines.append(f"### New FixInsight W-findings ({len(fi['new_w'])})")
        for item in fi["new_w"][:20]:
            lines.append(f"- {item}")
        lines.append("")

    ownership = delta.get("ownership") or {}
    lines.append("## Ownership")
    lines.append(f"- Before: {_ownership_text(ownership.get('before'))}")
    lines.append(f"- After: {_ownership_text(ownership.get('after'))}")
    lines.append(f"- Delta: {_ownership_text(ownership.get('delta'))}")
    lines.append("")

    gate = delta.get("gate") or {}
    if gate.get("enabled"):
        status = "PASS" if gate.get("pass") else "FAIL"
        lines.append("## Gate")
        lines.append(f"- Result: **{status}**")
        pf = gate.get("path_filter") if isinstance(gate.get("path_filter"), dict) else {}
        inc = pf.get("include") if isinstance(pf.get("include"), list) else []
        exc = pf.get("exclude") if isinstance(pf.get("exclude"), list) else []
        if inc or exc:
            inc_s = ";".join(str(x) for x in inc) if inc else "(none)"
            exc_s = ";".join(str(x) for x in exc) if exc else "(none)"
            lines.append(f"- Path filter: include={inc_s}, exclude={exc_s}")
        for r in gate.get("reasons", []):
            lines.append(f"- {r}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def _render_baseline_md(title: str, baseline_path: Path, snapshot: dict[str, Any], *, summary_path: Path) -> str:
    lines: list[str] = []
    lines.append(f"# Static analysis baseline: {title}")
    lines.append("")
    lines.append(f"- Timestamp: {snapshot.get('created_at', 'unknown')}")
    lines.append(f"- Baseline file: `{baseline_path}`")
    lines.append(f"- Summary: `{summary_path}`")
    ctx = snapshot.get("run_context") or {}
    if ctx:
        lines.append(f"- Context: platform={ctx.get('platform','?')}, config={ctx.get('config','?')}, delphi={ctx.get('delphi','?')}")
    lines.append("")

    fi = snapshot.get("fixinsight") or {}
    lines.append("## FixInsight")
    lines.append(f"- Findings: {fi.get('total', '?')}")
    counts_by_code = {k: int(v) for k, v in (fi.get('counts_by_code') or {}).items()}
    if counts_by_code:
        lines.append("- Top codes:")
        for code, count in sorted(counts_by_code.items(), key=lambda kv: kv[1], reverse=True)[:10]:
            lines.append(f"  - {code}: {count}")
    lines.append("")

    pal = snapshot.get("pascal_analyzer") or {}
    lines.append("## Pascal Analyzer")
    totals = pal.get("totals") or {}
    if totals:
        lines.append(
            f"- Totals: warnings={totals.get('warnings','?')}, "
            f"strong_warnings={totals.get('strong_warnings','?')}, "
            f"optimizations={totals.get('optimizations','?')}, total={totals.get('total','?')}"
        )
    top_sections = pal.get("top_warning_sections") or []
    if top_sections:
        lines.append("- Top warning sections:")
        for row in top_sections:
            lines.append(f"  - {row.get('section','?')}: {row.get('count','?')}")
    lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def _select_new_pal_items(pal_jsonl_path: Path, new_hashes: set[str], *, severity: str) -> list[str]:
    if not pal_jsonl_path.exists() or not new_hashes:
        return []
    items: list[str] = []
    for obj in _iter_actionable_jsonl(pal_jsonl_path):
        if obj.get("severity") != severity:
            continue
        h = _pal_fingerprint(obj)
        if h not in new_hashes:
            continue
        module = obj.get("module", "?")
        line = obj.get("line", "?")
        section = obj.get("section", "")
        msg = obj.get("message", "")
        items.append(f"[{section}] {module}:{line} - {msg}")
    return items


def _select_new_fi_items(fi_jsonl_path: Path, new_hashes: set[str], *, use_normalized_path: bool) -> list[str]:
    if not fi_jsonl_path.exists() or not new_hashes:
        return []
    items: list[str] = []
    for obj in _iter_actionable_jsonl(fi_jsonl_path):
        if obj.get("kind") != "W":
            continue
        h = _fi_fingerprint(obj, use_normalized_path=use_normalized_path)
        if h not in new_hashes:
            continue
        code = obj.get("code", "?")
        file = obj.get("path") or obj.get("file") or "?"
        line = obj.get("line", "?")
        col = obj.get("col", "?")
        msg = obj.get("message", "")
        items.append(f"[{code}] {file}:{line}:{col} - {msg}")
    return items


def _gate_eval(delta: dict[str, Any]) -> tuple[bool, list[str]]:
    max_new_pal_strong = _int_env("DAK_MAX_NEW_PAL_STRONG", 0)
    max_new_fi_w = _int_env("DAK_MAX_NEW_FI_W", 0)
    max_pal_warning_increase = _int_env("DAK_MAX_PAL_WARNING_INCREASE", None)
    max_fi_total_increase = _int_env("DAK_MAX_FI_TOTAL_INCREASE", None)
    reasons = list((delta.get("gate") or {}).get("preflight_reasons") or [])
    ok = not reasons

    baseline_compatibility = (delta.get("baseline") or {}).get("compatibility")
    current_compatibility = (delta.get("current") or {}).get("compatibility")
    baseline_sha = (
        str(baseline_compatibility.get("sha256") or "")
        if isinstance(baseline_compatibility, dict)
        else ""
    )
    current_sha = (
        str(current_compatibility.get("sha256") or "")
        if isinstance(current_compatibility, dict)
        else ""
    )
    if not baseline_sha:
        ok = False
        reasons.append("Baseline compatibility fingerprint is missing")
    elif not current_sha or baseline_sha != current_sha:
        ok = False
        reasons.append(
            f"Baseline compatibility mismatch: {baseline_sha or '<missing>'} -> "
            f"{current_sha or '<missing>'}"
        )

    pal = delta.get("pascal_analyzer") or {}
    fi = delta.get("fixinsight") or {}

    new_strong = int(pal.get("new_strong_count", 0))
    if max_new_pal_strong is not None and new_strong > max_new_pal_strong:
        ok = False
        reasons.append(f"New PAL strong warnings: {new_strong} > {max_new_pal_strong}")

    new_fi_w = int(fi.get("new_w_count", 0))
    if max_new_fi_w is not None and new_fi_w > max_new_fi_w:
        ok = False
        reasons.append(f"New FixInsight W-findings: {new_fi_w} > {max_new_fi_w}")

    if max_pal_warning_increase is not None:
        inc = int(
            pal.get("gated_warnings_delta", pal.get("warnings_delta", 0))
        )
        if inc > max_pal_warning_increase:
            ok = False
            reasons.append(f"PAL warnings increase: {inc} > {max_pal_warning_increase}")

    if max_fi_total_increase is not None:
        inc = int(fi.get("gated_total_delta", fi.get("total_delta", 0)))
        if inc > max_fi_total_increase:
            ok = False
            reasons.append(f"FixInsight findings increase: {inc} > {max_fi_total_increase}")

    return ok, reasons


def run_postprocess(
    out_root: Path,
    *,
    title: str,
    captured_provenance: Optional[dict[str, Any]] = None,
    execution_exit_code: Optional[int] = None,
) -> dict[str, Any]:
    out_root = out_root.resolve()
    fixinsight_dir = out_root / "fixinsight"
    pal_dir = out_root / "pascal-analyzer"

    summary_path = out_root / "summary.md"
    summary = parse_dak_summary_md(summary_path)
    run_context = _build_run_context(
        out_root,
        summary,
        allow_env=True,
        expected_summary_timestamp=None,
    )
    status_seed = _load_status_seed(
        out_root,
        summary,
        run_context,
        required=execution_exit_code is not None,
    )
    _enrich_analyzer_versions(status_seed, run_context)
    policy_context = status_seed.get("policy")
    if isinstance(policy_context, dict):
        policy_context.pop("status", None)
    _enrich_provenance(
        status_seed,
        summary,
        out_root,
        captured_provenance=captured_provenance,
    )
    summary["provenance"] = status_seed.get("provenance")

    infrastructure_errors = list(summary.get("errors") or [])
    if execution_exit_code not in (None, 0):
        infrastructure_errors.insert(
            0, f"DAK analyze failed (exit={execution_exit_code})."
        )
    seed_status = status_seed.get("status")
    seed_infrastructure = (
        str(seed_status.get("infrastructure") or "")
        if isinstance(seed_status, dict)
        else ""
    )
    analyzers = status_seed.get("analyzers")
    analyzer_failed = (
        any(
            isinstance(value, dict)
            and value.get("requested")
            and str(value.get("status") or "") != "complete"
            for value in analyzers.values()
        )
        if isinstance(analyzers, dict)
        else False
    )
    if seed_infrastructure == "failed" or analyzer_failed:
        for error in status_seed.get("errors") or []:
            if str(error) not in infrastructure_errors:
                infrastructure_errors.append(str(error))

    if infrastructure_errors or seed_infrastructure == "failed" or analyzer_failed:
        baseline_path = (
            Path(os.environ.get("DAK_BASELINE", "")).expanduser().resolve()
            if os.environ.get("DAK_BASELINE", "").strip()
            else out_root / "baseline.json"
        )
        delta_path = out_root / "delta.json"
        delta_md_path = out_root / "delta.md"
        reasons = [
            f"Analyzer infrastructure error: {error}"
            for error in infrastructure_errors
        ]
        if not reasons:
            reasons = ["Analyzer infrastructure status is incomplete."]
        _write_json(
            delta_path,
            {
                "title": title,
                "baseline": {"path": str(baseline_path), "created": False},
                "current": {"summary_path": str(summary_path)},
                "gate": {"enabled": True, "pass": False, "reasons": reasons},
            },
        )
        _write_text(
            delta_md_path,
            "# Static analysis gate\n\n" + "\n".join(f"- {reason}" for reason in reasons) + "\n",
        )
        status_summary = status_seed
        status_summary["schema_version"] = 2
        status_summary.setdefault("status", {})["infrastructure"] = "failed"
        status_summary["status"]["policy"] = "not_evaluated"
        status_summary["errors"] = infrastructure_errors
        status_summary.setdefault("artifacts", {}).update(
            {
                "summary_markdown": "summary.md",
                "delta": "delta.md",
                "delta_json": "delta.json",
            }
        )
        _write_json(out_root / "summary.json", status_summary)
        return {
            "baseline": str(baseline_path),
            "delta": str(delta_md_path),
            "gate_pass": False,
            "baseline_created": False,
            "baseline_updated": False,
        }

    _validate_success_summary(summary)

    legacy_repo_root = _find_git_root(out_root)
    project_dir: Optional[Path] = None
    subject_local = _to_local_path(
        str(summary.get("project") or summary.get("unit") or "")
    )
    if subject_local is not None:
        project_dir = subject_local.parent
        if legacy_repo_root is None:
            legacy_repo_root = _find_git_root(project_dir)
    elif legacy_repo_root is not None:
        cand = legacy_repo_root / "projects"
        if cand.exists():
            project_dir = cand

    workspace_root, workspace_vcs = _workspace_context(
        status_seed, legacy_repo_root
    )
    repo_root = workspace_root if workspace_vcs == "git" else None
    base_dirs = [
        path
        for path in (project_dir, workspace_root)
        if isinstance(path, Path)
    ]

    fi_norm = {}
    if fixinsight_dir.exists():
        fi_norm = write_fixinsight_normalized(
            fixinsight_dir, repo_root=workspace_root, base_dirs=base_dirs
        )

    pal_jsonl_path = pal_dir / "pal-findings.jsonl"
    fi_jsonl_path = fixinsight_dir / "fi-findings.jsonl"

    analyzers = status_seed.get("analyzers")
    analyzers = analyzers if isinstance(analyzers, dict) else {}
    for name, path in (
        ("fixinsight", fi_jsonl_path),
        ("pascal_analyzer", pal_jsonl_path),
    ):
        analyzer = analyzers.get(name)
        if (
            isinstance(analyzer, dict)
            and analyzer.get("requested")
            and analyzer.get("status") == "complete"
            and not path.exists()
        ):
            _write_jsonl(path, [])

    pal_analyzer_context = analyzers.get("pascal_analyzer")
    pal_analyzer_context = (
        pal_analyzer_context
        if isinstance(pal_analyzer_context, dict)
        else {}
    )
    pal_requested = bool(pal_analyzer_context.get("requested"))
    if not pal_requested and pal_jsonl_path.exists():
        _write_jsonl(pal_jsonl_path, [])

    analysis_policy = _resolved_analysis_policy(status_seed)
    _normalize_findings_ownership(
        fi_jsonl_path,
        pal_jsonl_path,
        out_root=out_root,
        status_seed=status_seed,
        repo_root=legacy_repo_root,
    )
    _apply_report_path_masks(
        fi_jsonl_path,
        pal_jsonl_path,
        analysis_policy["exclude_path_masks"],
    )
    pal_version = str(pal_analyzer_context.get("version") or "")
    _apply_report_projections(
        fi_jsonl_path,
        pal_jsonl_path,
        analysis_policy,
        pal_version=pal_version,
        pal_requested=pal_requested,
    )
    actionable_counts = _actionable_counts(summary, fi_jsonl_path, pal_jsonl_path)
    report_counts = _report_projections(summary, fi_jsonl_path, pal_jsonl_path)
    _write_summary_ownership(summary_path, actionable_counts["ownership"])
    required_sarif_path = _write_sarif(
        out_root, fi_jsonl_path=fi_jsonl_path, pal_jsonl_path=pal_jsonl_path
    )
    assert required_sarif_path is not None
    _validate_sarif_count(required_sarif_path, int(actionable_counts["total"]))
    full_sarif_path = _write_sarif(
        out_root,
        fi_jsonl_path=fi_jsonl_path,
        pal_jsonl_path=pal_jsonl_path,
        full_evidence=True,
    )
    assert full_sarif_path is not None
    _validate_sarif_count(full_sarif_path, int(report_counts["raw"]["total"]))
    external_summary_path = _write_external_summary(
        out_root, fi_jsonl_path, pal_jsonl_path
    )
    metrics_path = _write_metrics_summary(
        out_root, fi_jsonl_path, pal_jsonl_path
    )

    baseline_path = Path(os.environ.get("DAK_BASELINE", "")).expanduser().resolve() if os.environ.get("DAK_BASELINE", "").strip() else (out_root / "baseline.json")
    update_baseline = _truthy_env("DAK_UPDATE_BASELINE", False)
    gate_enabled = _truthy_env("DAK_GATE", False) or _truthy_env("DAK_CI", False)
    gated_ownership = set(analysis_policy["gate_ownership"])
    scope = os.environ.get("DAK_SCOPE", "").strip().lower()

    baseline_exists = baseline_path.exists()
    baseline: Optional[dict[str, Any]] = _load_json(baseline_path) if baseline_exists else None

    current_pal_warning_hashes: list[str] = []
    current_pal_strong_hashes: list[str] = []
    current_pal_warning_top = _top_section_counts(pal_jsonl_path, severity="warning")

    if pal_jsonl_path.exists():
        for obj in _iter_actionable_jsonl(pal_jsonl_path):
            sev = obj.get("severity")
            if sev == "warning":
                current_pal_warning_hashes.append(_pal_fingerprint(obj))
            elif sev == "strong-warning":
                current_pal_strong_hashes.append(_pal_fingerprint(obj))

    current_fi_w_hashes_raw: list[str] = []
    current_fi_w_hashes_norm: list[str] = []
    current_fi_counts_by_code: dict[str, int] = {}
    fi_total = int(actionable_counts["fixinsight"]["total"])

    if fi_jsonl_path.exists():
        for obj in _iter_actionable_jsonl(fi_jsonl_path):
            code = str(obj.get("code") or "")
            if code:
                current_fi_counts_by_code[code] = (
                    current_fi_counts_by_code.get(code, 0) + 1
                )
            if obj.get("kind") != "W":
                continue
            current_fi_w_hashes_raw.append(
                _fi_fingerprint(obj, use_normalized_path=False)
            )
            current_fi_w_hashes_norm.append(
                _fi_fingerprint(obj, use_normalized_path=True)
            )

    pal_totals = {
        key: actionable_counts["pascal_analyzer"][key]
        for key in ("warnings", "strong_warnings", "optimizations", "total")
    }
    pal_warning_records = [
        obj
        for obj in (
            list(_iter_actionable_jsonl(pal_jsonl_path))
            if pal_jsonl_path.exists()
            else []
        )
        if obj.get("severity") == "warning"
    ]
    verified_rule_aliases = _pal_registered_aliases(pal_version)

    current_snapshot: dict[str, Any] = {
        "version": 4,
        "created_at": summary.get("timestamp") or _utc_now_iso(),
        "run_context": run_context,
        "summary": summary,
        "fixinsight": {
            "total": fi_total,
            "counts_by_code": current_fi_counts_by_code,
            "w_hashes": sorted(set(current_fi_w_hashes_norm)),
            "ownership": actionable_counts["fixinsight"]["ownership"],
        },
        "pascal_analyzer": {
            "totals": pal_totals,
            "top_warning_sections": current_pal_warning_top,
            "warning_hashes": sorted(set(current_pal_warning_hashes)),
            "strong_hashes": sorted(set(current_pal_strong_hashes)),
            "rule_counts": report_counts["actionable"]["pascal_analyzer"][
                "by_rule"
            ],
            "raw_rule_counts": report_counts["raw"]["pascal_analyzer"][
                "by_rule"
            ],
            "ignored_rule_counts": report_counts["ignored"][
                "pascal_analyzer"
            ]["by_rule"],
            "verified_rule_aliases": dict(
                sorted(verified_rule_aliases.items())
            ),
            "ownership": actionable_counts["pascal_analyzer"]["ownership"],
            "warning_ownership": _ownership_counts(pal_warning_records),
        },
        "ownership": actionable_counts["ownership"],
        "raw": report_counts["raw"],
        "compatibility": _compatibility_snapshot(status_seed),
    }

    delta_path = out_root / "delta.json"
    delta_md_path = out_root / "delta.md"
    baseline_md_path = baseline_path.with_suffix(".md")
    preflight_reasons = list(analysis_policy["errors"])
    unknown_count = int(report_counts["unknown"]["total"])
    if unknown_count > 0:
        preflight_reasons.append(
            f"Unknown ownership findings: {unknown_count}"
        )

    if not baseline_exists:
        baseline_created = not (gate_enabled and preflight_reasons)
        if baseline_created:
            _write_json(baseline_path, current_snapshot)
            _write_text(
                baseline_md_path,
                _render_baseline_md(
                    title,
                    baseline_path,
                    current_snapshot,
                    summary_path=summary_path,
                ),
            )
        pal_totals = current_snapshot.get("pascal_analyzer", {}).get("totals", {}) or {}
        fi_total = current_snapshot.get("fixinsight", {}).get("total")
        ownership_before = (
            current_snapshot["ownership"]
            if baseline_created
            else _empty_ownership_counts()
        )
        delta_obj = {
            "title": title,
            "baseline": {
                "path": str(baseline_path),
                "timestamp": current_snapshot["created_at"],
                "created": baseline_created,
                "run_context": current_snapshot.get("run_context") or {},
                "compatibility": (
                    current_snapshot.get("compatibility") or {}
                    if baseline_created
                    else {}
                ),
            },
            "current": {
                "summary_path": str(summary_path),
                "timestamp": current_snapshot["created_at"],
                "run_context": current_snapshot.get("run_context") or {},
                "compatibility": current_snapshot.get("compatibility") or {},
            },
            "fixinsight": {
                "total_before": fi_total,
                "total_after": fi_total,
                "total_delta": 0,
                "gated_total_delta": 0,
                "top_code_deltas": [],
                "new_w_count": 0,
                "new_w": [],
            },
            "pascal_analyzer": {
                "warnings_before": pal_totals.get("warnings"),
                "warnings_after": pal_totals.get("warnings"),
                "warnings_delta": 0,
                "gated_warnings_delta": 0,
                "strong_before": pal_totals.get("strong_warnings"),
                "strong_after": pal_totals.get("strong_warnings"),
                "strong_delta": 0,
                "optimizations_before": pal_totals.get("optimizations"),
                "optimizations_after": pal_totals.get("optimizations"),
                "optimizations_delta": 0,
                "total_before": pal_totals.get("total"),
                "total_after": pal_totals.get("total"),
                "total_delta": 0,
                "new_strong_count": 0,
                "new_strong": [],
                "new_warnings_count": 0,
                "new_warnings_preview": [],
                "top_section_deltas": [],
                "rule_count_deltas": _rule_count_delta(
                    current_snapshot["pascal_analyzer"]["rule_counts"],
                    current_snapshot["pascal_analyzer"]["rule_counts"],
                ),
                "raw_rule_count_deltas": _rule_count_delta(
                    current_snapshot["pascal_analyzer"][
                        "raw_rule_counts"
                    ],
                    current_snapshot["pascal_analyzer"][
                        "raw_rule_counts"
                    ],
                ),
                "ignored_rule_count_deltas": _rule_count_delta(
                    current_snapshot["pascal_analyzer"][
                        "ignored_rule_counts"
                    ],
                    current_snapshot["pascal_analyzer"][
                        "ignored_rule_counts"
                    ],
                ),
                "verified_rule_aliases": {
                    "before": current_snapshot["pascal_analyzer"][
                        "verified_rule_aliases"
                    ],
                    "after": current_snapshot["pascal_analyzer"][
                        "verified_rule_aliases"
                    ],
                },
            },
            "ownership": {
                "before": ownership_before,
                "after": current_snapshot["ownership"],
                "delta": {
                    name: int(current_snapshot["ownership"].get(name, 0))
                    - int(ownership_before.get(name, 0))
                    for name in _OWNERSHIP_NAMES
                },
            },
            "note": (
                "Baseline created (no delta)."
                if baseline_created
                else "Baseline not created because policy evaluation failed."
            ),
            "gate": {
                "enabled": gate_enabled,
                "pass": not (gate_enabled and preflight_reasons),
                "reasons": preflight_reasons if gate_enabled else [],
            },
        }
        _write_json(delta_path, delta_obj)
        _write_text(delta_md_path, _render_delta_md(delta_obj))
        triage_path = _write_triage(out_root, title=title, fi_jsonl_path=fi_jsonl_path, pal_jsonl_path=pal_jsonl_path)
        res = {
            "baseline": str(baseline_path),
            "delta": str(delta_md_path),
            "gate_pass": bool(delta_obj["gate"]["pass"]),
            "policy_evaluated": gate_enabled,
            "baseline_created": baseline_created,
            "triage": str(triage_path),
        }
        if _truthy_env("DAK_TRIAGE_SNIPPETS", False):
            triage_snip = out_root / "triage-snippets.md"
            if triage_snip.exists():
                res["triage_snippets"] = str(triage_snip)
        res["sarif"] = str(required_sarif_path)
        res["full_sarif"] = str(full_sarif_path)
        res["external_summary"] = str(external_summary_path)
        res["metrics"] = str(metrics_path)
        history_path, trend_path, _ = _update_history_and_trend(out_root, title=title, summary=summary, snapshot=current_snapshot, repo_root=repo_root)
        res["history"] = str(history_path)
        res["trend"] = str(trend_path)
        if scope == "changed":
            triage_changed_path = _write_triage_changed(out_root, title=title, summary=summary, fi_jsonl_path=fi_jsonl_path, pal_jsonl_path=pal_jsonl_path)
            res["triage_changed"] = str(triage_changed_path)
        summary_json_path = _write_ai_summary(
            out_root,
            status_seed=status_seed,
            summary=summary,
            snapshot=current_snapshot,
            result=res,
            fi_jsonl_path=fi_jsonl_path,
            pal_jsonl_path=pal_jsonl_path,
            captured_provenance=captured_provenance,
        )
        res["summary_json"] = str(summary_json_path)
        return res

    assert baseline is not None

    # Baseline schema migration (metadata only). We keep baseline findings stable unless DAK_UPDATE_BASELINE=1.
    baseline_dirty = False
    try:
        baseline_ver = int(baseline.get("version", 0))
    except (TypeError, ValueError):
        baseline_ver = 0
    if baseline_ver < 2:
        baseline["version"] = 2
        baseline_dirty = True

    baseline_summary = baseline.get("summary") if isinstance(baseline.get("summary"), dict) else {}
    expected_ts = str(baseline_summary.get("timestamp") or "").strip() or None
    if expected_ts is None:
        expected_ts = str(baseline.get("created_at") or "").strip() or None

    can_trust_outputs = bool(expected_ts) and str(summary.get("timestamp") or "") == expected_ts

    # If outputs still match the baseline, we can safely upgrade the FixInsight W-hash scheme to normalized paths.
    # This avoids spurious deltas on machines where FixInsight emits different relative/absolute paths.
    try:
        baseline_ver_now = int(baseline.get("version", 0))
    except (TypeError, ValueError):
        baseline_ver_now = 0
    if can_trust_outputs and baseline_ver_now < 3:
        b_fi2 = baseline.get("fixinsight")
        if isinstance(b_fi2, dict):
            b_fi2 = dict(b_fi2)
            b_fi2["w_hashes"] = sorted(set(current_fi_w_hashes_norm))
            baseline["fixinsight"] = b_fi2
        baseline["version"] = 3
        baseline_dirty = True

    baseline_rc = baseline.get("run_context")
    if not isinstance(baseline_rc, dict):
        baseline_rc = {}

    if not baseline_rc:
        # If current summary matches the baseline timestamp, we can safely parse run.log for context.
        summary_for_ctx = summary if can_trust_outputs else baseline_summary
        baseline["run_context"] = _build_run_context(
            out_root,
            summary_for_ctx if isinstance(summary_for_ctx, dict) else {},
            allow_env=False,
            expected_summary_timestamp=expected_ts,
        )
        baseline_dirty = True
    else:
        # Ensure required keys exist in older baselines.
        for k in ("platform", "config", "delphi"):
            if k not in baseline_rc:
                baseline_rc[k] = "unknown"
                baseline_dirty = True

        # Backfill missing/unknown context only when we can prove the outputs match the baseline run.
        if can_trust_outputs:
            inferred = _build_run_context(out_root, summary, allow_env=False, expected_summary_timestamp=expected_ts)
            changed = False
            for k in ("platform", "config", "delphi"):
                cur = str(baseline_rc.get(k) or "").strip().lower()
                if k == "delphi":
                    # If we can infer a concrete BDS version (e.g. "23.0"), prefer it over a generic label ("Delphi 11").
                    cur_raw = str(baseline_rc.get(k) or "").strip()
                    inf_raw = str(inferred.get(k) or "").strip()
                    cur_is_label = bool(re.match(r"^Delphi\s+\d+\b", cur_raw, flags=re.IGNORECASE))
                    inf_is_bds = bool(re.match(r"^\d+\.\d+$", inf_raw))
                    if cur_raw and cur != "unknown" and not (cur_is_label and inf_is_bds):
                        continue
                else:
                    if cur not in ("", "unknown"):
                        continue
                inf = str(inferred.get(k) or "").strip()
                if inf and inf.lower() != "unknown":
                    baseline_rc[k] = inferred.get(k)
                    changed = True

            base_tools = baseline_rc.get("tools")
            inf_tools = inferred.get("tools")
            if isinstance(base_tools, dict) and isinstance(inf_tools, dict):
                for k, v in inf_tools.items():
                    if k not in base_tools:
                        base_tools[k] = v
                        changed = True
                baseline_rc["tools"] = base_tools
            elif not base_tools and isinstance(inf_tools, dict) and inf_tools:
                baseline_rc["tools"] = inf_tools
                changed = True

            if changed:
                baseline["run_context"] = baseline_rc
                baseline_dirty = True

    b_fi = baseline.get("fixinsight") or {}
    b_pal = baseline.get("pascal_analyzer") or {}
    ownership_before = baseline.get("ownership")
    if not isinstance(ownership_before, dict):
        ownership_before = _empty_ownership_counts()
    ownership_after = current_snapshot["ownership"]
    ownership_delta = {
        name: int(ownership_after.get(name, 0)) - int(ownership_before.get(name, 0))
        for name in _OWNERSHIP_NAMES
    }

    # Counts (prefer summary values when present).
    b_fi_total = b_fi.get("total")
    a_fi_total = current_snapshot["fixinsight"]["total"]
    total_delta = None
    if isinstance(b_fi_total, int) and isinstance(a_fi_total, int):
        total_delta = a_fi_total - b_fi_total
    b_fi_ownership = b_fi.get("ownership")
    b_fi_ownership = (
        b_fi_ownership
        if isinstance(b_fi_ownership, dict)
        else _empty_ownership_counts()
    )
    a_fi_ownership = current_snapshot["fixinsight"]["ownership"]
    gated_fi_total_delta = sum(
        int(a_fi_ownership.get(name, 0))
        - int(b_fi_ownership.get(name, 0))
        for name in gated_ownership
    )

    b_fi_counts = {k: int(v) for k, v in (b_fi.get("counts_by_code") or {}).items()}
    a_fi_counts = current_snapshot["fixinsight"]["counts_by_code"]
    top_code_deltas = _code_delta(b_fi_counts, a_fi_counts) if b_fi_counts or a_fi_counts else []

    b_pal_totals = b_pal.get("totals") or {}
    a_pal_totals = current_snapshot["pascal_analyzer"]["totals"] or {}

    warnings_before = b_pal_totals.get("warnings")
    warnings_after = a_pal_totals.get("warnings")
    warnings_delta = None
    if isinstance(warnings_before, int) and isinstance(warnings_after, int):
        warnings_delta = warnings_after - warnings_before
    b_pal_warning_ownership = b_pal.get("warning_ownership")
    b_pal_warning_ownership = (
        b_pal_warning_ownership
        if isinstance(b_pal_warning_ownership, dict)
        else _empty_ownership_counts()
    )
    a_pal_warning_ownership = current_snapshot["pascal_analyzer"][
        "warning_ownership"
    ]
    gated_pal_warning_delta = sum(
        int(a_pal_warning_ownership.get(name, 0))
        - int(b_pal_warning_ownership.get(name, 0))
        for name in gated_ownership
    )

    strong_before = b_pal_totals.get("strong_warnings")
    strong_after = a_pal_totals.get("strong_warnings")
    strong_delta = None
    if isinstance(strong_before, int) and isinstance(strong_after, int):
        strong_delta = strong_after - strong_before

    optimizations_before = b_pal_totals.get("optimizations")
    optimizations_after = a_pal_totals.get("optimizations")
    optimizations_delta = None
    if isinstance(optimizations_before, int) and isinstance(optimizations_after, int):
        optimizations_delta = optimizations_after - optimizations_before

    pal_total_before = b_pal_totals.get("total")
    pal_total_after = a_pal_totals.get("total")
    pal_total_delta = None
    if isinstance(pal_total_before, int) and isinstance(pal_total_after, int):
        pal_total_delta = pal_total_after - pal_total_before

    gate_include = _split_semicolon_patterns(os.environ.get("DAK_GATE_INCLUDE_PATHS", ""))
    gate_exclude = _split_semicolon_patterns(os.environ.get("DAK_GATE_EXCLUDE_PATHS", ""))
    gate_path_filter = bool(gate_include or gate_exclude)

    # Finding deltas (hash-based). Gate path filters (when provided) apply only to the *current*
    # run findings, so we can gate on our code even when baselines contain vendor findings.
    b_pal_warn = set(b_pal.get("warning_hashes") or [])
    b_pal_strong = set(b_pal.get("strong_hashes") or [])

    if pal_jsonl_path.exists():
        a_pal_warn = set()
        a_pal_strong = set()
        for obj in _iter_actionable_jsonl(pal_jsonl_path):
            if gate_enabled and obj.get("ownership") not in gated_ownership:
                continue
            p = str(obj.get("path") or "")
            if gate_path_filter and not _triage_path_allowed(
                p, include=gate_include, exclude=gate_exclude
            ):
                continue
            sev = str(obj.get("severity") or "")
            h = _pal_fingerprint(obj)
            if sev == "warning":
                a_pal_warn.add(h)
            elif sev == "strong-warning":
                a_pal_strong.add(h)
    else:
        a_pal_warn = set(current_snapshot["pascal_analyzer"]["warning_hashes"])
        a_pal_strong = set(current_snapshot["pascal_analyzer"]["strong_hashes"])

    new_pal_warn = a_pal_warn - b_pal_warn
    new_pal_strong = a_pal_strong - b_pal_strong

    b_fi_w = set(b_fi.get("w_hashes") or [])
    try:
        baseline_ver_now = int(baseline.get("version", 0))
    except (TypeError, ValueError):
        baseline_ver_now = 0
    use_norm_fi = baseline_ver_now >= 3

    if fi_jsonl_path.exists():
        a_fi_w = set()
        for obj in _iter_actionable_jsonl(fi_jsonl_path):
            if obj.get("kind") != "W":
                continue
            if gate_enabled and obj.get("ownership") not in gated_ownership:
                continue
            p = str(obj.get("path") or obj.get("file") or "")
            if gate_path_filter and not _triage_path_allowed(
                p, include=gate_include, exclude=gate_exclude
            ):
                continue
            a_fi_w.add(
                _fi_fingerprint(obj, use_normalized_path=use_norm_fi)
            )
    else:
        a_fi_w = set(current_fi_w_hashes_norm) if use_norm_fi else set(current_fi_w_hashes_raw)
    new_fi_w = a_fi_w - b_fi_w

    pal_new_strong_items = _select_new_pal_items(pal_jsonl_path, new_pal_strong, severity="strong-warning")
    pal_new_warn_preview = _select_new_pal_items(pal_jsonl_path, new_pal_warn, severity="warning")[:20]

    fi_new_w_items: list[str] = []
    if use_norm_fi:
        items_map = fi_norm.get("w_items_by_norm_hash") if isinstance(fi_norm, dict) else None
    else:
        items_map = fi_norm.get("w_items_by_raw_hash") if isinstance(fi_norm, dict) else None
    if isinstance(items_map, dict):
        fi_new_w_items = [str(items_map[h]) for h in sorted(new_fi_w) if h in items_map][:200]
    elif use_norm_fi:
        # Fallback for unusual setups where we couldn't compute item maps.
        fi_new_w_items = _select_new_fi_items(fi_jsonl_path, new_fi_w, use_normalized_path=True)

    b_top_sections = b_pal.get("top_warning_sections") or []
    a_top_sections = current_snapshot["pascal_analyzer"]["top_warning_sections"] or []
    top_section_deltas = _section_delta(b_top_sections, a_top_sections) if b_top_sections or a_top_sections else []
    b_pal_rule_counts = b_pal.get("rule_counts")
    b_pal_rule_counts = (
        b_pal_rule_counts if isinstance(b_pal_rule_counts, dict) else {}
    )
    a_pal_rule_counts = current_snapshot["pascal_analyzer"]["rule_counts"]
    rule_count_deltas = _rule_count_delta(
        b_pal_rule_counts, a_pal_rule_counts
    )
    b_raw_rule_counts = b_pal.get("raw_rule_counts")
    b_raw_rule_counts = (
        b_raw_rule_counts if isinstance(b_raw_rule_counts, dict) else {}
    )
    b_ignored_rule_counts = b_pal.get("ignored_rule_counts")
    b_ignored_rule_counts = (
        b_ignored_rule_counts
        if isinstance(b_ignored_rule_counts, dict)
        else {}
    )
    b_verified_aliases = b_pal.get("verified_rule_aliases")
    b_verified_aliases = (
        b_verified_aliases if isinstance(b_verified_aliases, dict) else {}
    )

    delta_obj: dict[str, Any] = {
        "title": title,
        "baseline": {
            "path": str(baseline_path),
            "timestamp": baseline.get("created_at") or baseline.get("summary", {}).get("timestamp"),
            "run_context": baseline.get("run_context") or {},
            "compatibility": baseline.get("compatibility") or {},
        },
        "current": {
            "summary_path": str(summary_path),
            "timestamp": current_snapshot["created_at"],
            "run_context": current_snapshot.get("run_context") or {},
            "compatibility": current_snapshot.get("compatibility") or {},
        },
        "fixinsight": {
            "total_before": b_fi_total,
            "total_after": a_fi_total,
            "total_delta": int(total_delta or 0),
            "gated_total_delta": gated_fi_total_delta,
            "top_code_deltas": top_code_deltas,
            "new_w_count": len(new_fi_w),
            "new_w": fi_new_w_items,
        },
        "pascal_analyzer": {
            "warnings_before": warnings_before,
            "warnings_after": warnings_after,
            "warnings_delta": int(warnings_delta or 0),
            "gated_warnings_delta": gated_pal_warning_delta,
            "strong_before": strong_before,
            "strong_after": strong_after,
            "strong_delta": int(strong_delta or 0),
            "optimizations_before": optimizations_before,
            "optimizations_after": optimizations_after,
            "optimizations_delta": int(optimizations_delta or 0),
            "total_before": pal_total_before,
            "total_after": pal_total_after,
            "total_delta": int(pal_total_delta or 0),
            "new_strong_count": len(new_pal_strong),
            "new_strong": pal_new_strong_items,
            "new_warnings_count": len(new_pal_warn),
            "new_warnings_preview": pal_new_warn_preview,
            "top_section_deltas": top_section_deltas,
            "rule_count_deltas": rule_count_deltas,
            "raw_rule_count_deltas": _rule_count_delta(
                b_raw_rule_counts,
                current_snapshot["pascal_analyzer"]["raw_rule_counts"],
            ),
            "ignored_rule_count_deltas": _rule_count_delta(
                b_ignored_rule_counts,
                current_snapshot["pascal_analyzer"][
                    "ignored_rule_counts"
                ],
            ),
            "verified_rule_aliases": {
                "before": b_verified_aliases,
                "after": current_snapshot["pascal_analyzer"][
                    "verified_rule_aliases"
                ],
            },
        },
        "ownership": {
            "before": ownership_before,
            "after": ownership_after,
            "delta": ownership_delta,
        },
        "gate": {
            "enabled": gate_enabled,
            "ownership": list(analysis_policy["gate_ownership"]),
            "preflight_reasons": preflight_reasons,
        },
    }

    if gate_path_filter:
        delta_obj["gate"]["path_filter"] = {"include": gate_include, "exclude": gate_exclude}

    if gate_enabled:
        gate_ok, reasons = _gate_eval(delta_obj)
        delta_obj["gate"]["pass"] = gate_ok
        delta_obj["gate"]["reasons"] = reasons
    else:
        delta_obj["gate"]["pass"] = True
        delta_obj["gate"]["reasons"] = []

    _write_json(delta_path, delta_obj)
    _write_text(delta_md_path, _render_delta_md(delta_obj))

    baseline_write_allowed = (not gate_enabled) or bool(delta_obj["gate"]["pass"])
    baseline_updated = bool(update_baseline and baseline_write_allowed)
    if baseline_write_allowed:
        snapshot_for_baseline_md = current_snapshot if update_baseline else baseline
        if update_baseline:
            _write_json(baseline_path, current_snapshot)
        elif baseline_dirty:
            _write_json(baseline_path, baseline)
        _write_text(
            baseline_md_path,
            _render_baseline_md(
                title,
                baseline_path,
                snapshot_for_baseline_md,
                summary_path=summary_path,
            ),
        )

    triage_path = _write_triage(out_root, title=title, fi_jsonl_path=fi_jsonl_path, pal_jsonl_path=pal_jsonl_path)
    res = {
        "baseline": str(baseline_path),
        "delta": str(delta_md_path),
        "gate_pass": bool(delta_obj["gate"]["pass"]),
        "policy_evaluated": gate_enabled,
        "baseline_updated": baseline_updated,
        "triage": str(triage_path),
    }
    if _truthy_env("DAK_TRIAGE_SNIPPETS", False):
        triage_snip = out_root / "triage-snippets.md"
        if triage_snip.exists():
            res["triage_snippets"] = str(triage_snip)
    res["sarif"] = str(required_sarif_path)
    res["full_sarif"] = str(full_sarif_path)
    res["external_summary"] = str(external_summary_path)
    res["metrics"] = str(metrics_path)
    history_path, trend_path, _ = _update_history_and_trend(out_root, title=title, summary=summary, snapshot=current_snapshot, repo_root=repo_root)
    res["history"] = str(history_path)
    res["trend"] = str(trend_path)
    if scope == "changed":
        triage_changed_path = _write_triage_changed(out_root, title=title, summary=summary, fi_jsonl_path=fi_jsonl_path, pal_jsonl_path=pal_jsonl_path)
        res["triage_changed"] = str(triage_changed_path)
    summary_json_path = _write_ai_summary(
        out_root,
        status_seed=status_seed,
        summary=summary,
        snapshot=current_snapshot,
        result=res,
        fi_jsonl_path=fi_jsonl_path,
        pal_jsonl_path=pal_jsonl_path,
        captured_provenance=captured_provenance,
    )
    res["summary_json"] = str(summary_json_path)
    return res


def _triage_without_timestamp(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.startswith("- Timestamp: ")
    )


def _verify_triage_evidence(
    out_root: Path,
    summary_json: dict[str, Any],
    fi_path: Path,
    pal_path: Path,
) -> None:
    triage_path = out_root / "triage.md"
    actual = _read_text(triage_path)
    first_line = actual.splitlines()[0] if actual.splitlines() else ""
    match = re.fullmatch(r"# (.+) triage", first_line)
    if match is None:
        raise ValueError("triage.md evidence mismatch")

    policy = summary_json.get("policy")
    policy = policy if isinstance(policy, dict) else {}
    active = policy.get("active")
    active = active if isinstance(active, dict) else {}
    triage = active.get("triage")
    if not isinstance(triage, dict):
        raise ValueError("summary.json active triage policy is missing")
    top = triage.get("top")
    if not isinstance(top, int) or top <= 0:
        raise ValueError("summary.json active triage policy is invalid")

    values = {
        "DAK_TRIAGE_TOP": str(top),
        "DAK_TRIAGE_INCLUDE_PATHS": str(triage.get("include_paths") or ""),
        "DAK_TRIAGE_EXCLUDE_PATHS": str(triage.get("exclude_paths") or ""),
        "DAK_TRIAGE_PAL_INCLUDE_CALL_TREE": (
            "1" if triage.get("pal_include_call_tree") else "0"
        ),
        "DAK_TRIAGE_SNIPPETS": "0",
    }
    previous = {name: os.environ.get(name) for name in values}
    try:
        os.environ.update(values)
        with tempfile.TemporaryDirectory(prefix="dak-triage-verify-") as temp_dir:
            expected_path = _write_triage(
                Path(temp_dir),
                title=match.group(1),
                fi_jsonl_path=fi_path,
                pal_jsonl_path=pal_path,
            )
            expected = _read_text(expected_path)
    finally:
        for name, value in previous.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
    if _triage_without_timestamp(actual) != _triage_without_timestamp(expected):
        raise ValueError("triage.md evidence mismatch")


def verify_outputs(out_root: Path) -> dict[str, int]:
    out_root = out_root.resolve()
    fi_path = out_root / "fixinsight" / "fi-findings.jsonl"
    pal_path = out_root / "pascal-analyzer" / "pal-findings.jsonl"
    summary_json = _load_json(out_root / "summary.json")
    analyzers = summary_json.get("analyzers")
    analyzers = analyzers if isinstance(analyzers, dict) else {}
    for name, label, path in (
        ("fixinsight", "FixInsight", fi_path),
        ("pascal_analyzer", "Pascal Analyzer", pal_path),
    ):
        analyzer = analyzers.get(name)
        if (
            isinstance(analyzer, dict)
            and analyzer.get("requested")
            and analyzer.get("status") == "complete"
            and not path.exists()
        ):
            raise ValueError(f"requested {label} JSONL is missing: {path}")
    fi_records = list(_iter_jsonl(fi_path)) if fi_path.exists() else []
    pal_records = list(_iter_jsonl(pal_path)) if pal_path.exists() else []
    raw_records = [*fi_records, *pal_records]
    if any("ownership" not in record for record in raw_records):
        raise ValueError("normalized JSONL ownership is missing")
    records = [record for record in raw_records if _record_is_actionable(record)]
    summary_markdown = parse_dak_summary_md(out_root / "summary.md")
    expected_projections = _report_projections(summary_markdown, fi_path, pal_path)
    expected_counts = _actionable_counts(summary_markdown, fi_path, pal_path)
    expected = expected_counts["ownership"]

    actual_counts = summary_json.get("counts") or {}
    if actual_counts != expected_projections:
        raise ValueError(
            "summary.json projection mismatch: "
            f"expected={expected_projections}, actual={actual_counts}"
        )
    total = int((actual_counts.get("actionable") or {}).get("total", -1))
    if total != len(records):
        raise ValueError(
            f"summary.json total mismatch: expected={len(records)}, actual={total}"
        )

    delta = _load_json(out_root / "delta.json")
    policy = summary_json.get("policy")
    policy = policy if isinstance(policy, dict) else {}
    resolved_policy = _resolved_analysis_policy(summary_json)
    active_policy = policy.get("active")
    active_policy = (
        active_policy if isinstance(active_policy, dict) else {}
    )
    if active_policy.get("pal_ignore_rules") != resolved_policy[
        "pal_ignore_rules"
    ]:
        raise ValueError("summary.json active PAL ignore policy mismatch")
    origins = policy.get("origins")
    origins = origins if isinstance(origins, dict) else {}
    pal_origins = origins.get("pal_ignore_rules")
    if resolved_policy["pal_ignore_rules"] and (
        not isinstance(pal_origins, list)
        or any(
            not isinstance(value, str) or not value.strip()
            for value in pal_origins
        )
        or not pal_origins
    ):
        raise ValueError("summary.json PAL ignore provenance is missing")
    pal_analyzer = analyzers.get("pascal_analyzer")
    pal_analyzer = (
        pal_analyzer if isinstance(pal_analyzer, dict) else {}
    )
    pal_version = str(pal_analyzer.get("version") or "")
    for record in pal_records:
        expected_rule, expected_code = _pal_rule_identity(
            record, pal_version=pal_version
        )
        actual_code = str(record.get("pal_code") or "").strip() or None
        if (
            record.get("normalized_rule") != expected_rule
            or actual_code != expected_code
        ):
            raise ValueError("normalized PAL identity mismatch")
    expected_aliases = dict(
        sorted(
            _pal_registered_aliases(pal_version).items()
        )
    )
    if pal_analyzer.get("verified_rule_aliases") != expected_aliases:
        raise ValueError("summary.json verified PAL alias mismatch")
    delta_pal = delta.get("pascal_analyzer")
    delta_pal = delta_pal if isinstance(delta_pal, dict) else {}
    delta_aliases = delta_pal.get("verified_rule_aliases")
    delta_aliases = (
        delta_aliases if isinstance(delta_aliases, dict) else {}
    )
    if delta_aliases.get("after") != expected_aliases:
        raise ValueError("delta.json verified PAL alias mismatch")

    baseline_json: Optional[dict[str, Any]] = None
    baseline_value = str((delta.get("baseline") or {}).get("path") or "")
    if baseline_value:
        baseline_path = Path(baseline_value)
        if not baseline_path.is_absolute():
            baseline_path = out_root / baseline_path
        if not baseline_path.exists():
            raise ValueError(
                f"referenced baseline is missing: {baseline_path}"
            )
        baseline_json = _load_json(baseline_path)
    baseline_pal = (
        baseline_json.get("pascal_analyzer")
        if isinstance(baseline_json, dict)
        else {}
    )
    baseline_pal = baseline_pal if isinstance(baseline_pal, dict) else {}
    if (
        baseline_json is not None
        and delta_aliases.get("before")
        != baseline_pal.get("verified_rule_aliases", {})
    ):
        raise ValueError("delta.json verified PAL alias baseline mismatch")

    def verify_rule_delta(
        field: str,
        expected_before: Optional[dict[str, Any]],
        expected_after: dict[str, Any],
    ) -> None:
        rows = delta_pal.get(field)
        if not isinstance(rows, list):
            raise ValueError(f"delta.json {field} is missing")
        before: dict[str, int] = {}
        after: dict[str, int] = {}
        seen_rules: set[str] = set()
        for row in rows:
            if not isinstance(row, dict):
                raise ValueError(f"delta.json {field} is invalid")
            rule = str(row.get("rule") or "")
            if not rule or rule in seen_rules:
                raise ValueError(f"delta.json {field} is invalid")
            seen_rules.add(rule)
            before_count = int(row.get("before", 0))
            after_count = int(row.get("after", 0))
            if int(row.get("delta", 0)) != after_count - before_count:
                raise ValueError(f"delta.json {field} is invalid")
            if before_count:
                before[rule] = before_count
            if after_count:
                after[rule] = after_count
        normalized_after = {
            str(rule): int(count)
            for rule, count in expected_after.items()
            if int(count)
        }
        if after != normalized_after:
            raise ValueError(f"delta.json {field} evidence mismatch")
        if expected_before is not None:
            normalized_before = {
                str(rule): int(count)
                for rule, count in expected_before.items()
                if int(count)
            }
            if before != normalized_before:
                raise ValueError(
                    f"delta.json {field} baseline evidence mismatch"
                )

    verify_rule_delta(
        "rule_count_deltas",
        baseline_pal.get("rule_counts")
        if baseline_json is not None
        else None,
        expected_projections["actionable"]["pascal_analyzer"]["by_rule"],
    )
    verify_rule_delta(
        "raw_rule_count_deltas",
        baseline_pal.get("raw_rule_counts")
        if baseline_json is not None
        else None,
        expected_projections["raw"]["pascal_analyzer"]["by_rule"],
    )
    verify_rule_delta(
        "ignored_rule_count_deltas",
        baseline_pal.get("ignored_rule_counts")
        if baseline_json is not None
        else None,
        expected_projections["ignored"]["pascal_analyzer"]["by_rule"],
    )
    reported_compatibility = summary_json.get("compatibility")
    expected_compatibility = _compatibility_snapshot(summary_json)
    if (
        not isinstance(reported_compatibility, dict)
        or reported_compatibility.get("sha256")
        != expected_compatibility["sha256"]
    ):
        raise ValueError("summary.json compatibility fingerprint mismatch")
    current_compatibility = (delta.get("current") or {}).get("compatibility")
    if (
        not isinstance(current_compatibility, dict)
        or current_compatibility.get("sha256")
        != reported_compatibility.get("sha256")
    ):
        raise ValueError("delta.json current compatibility mismatch")
    gate = delta.get("gate")
    gate = gate if isinstance(gate, dict) else {}
    if gate.get("enabled") and gate.get("pass"):
        baseline_compatibility = (delta.get("baseline") or {}).get(
            "compatibility"
        )
        if (
            not isinstance(baseline_compatibility, dict)
            or baseline_compatibility.get("sha256")
            != reported_compatibility.get("sha256")
        ):
            raise ValueError("passing gate baseline compatibility mismatch")
        if baseline_json is None:
            raise ValueError("passing gate baseline.json is missing")
        if (baseline_json.get("compatibility") or {}).get(
            "sha256"
        ) != reported_compatibility.get("sha256"):
            raise ValueError("baseline.json compatibility mismatch")

    actual = (delta.get("ownership") or {}).get("after")
    if actual != expected:
        raise ValueError(
            f"delta.json ownership mismatch: expected={expected}, actual={actual}"
        )
    delta_fi = delta.get("fixinsight") or {}
    if int(delta_fi.get("total_after", -1)) != expected_counts["fixinsight"]["total"]:
        raise ValueError("delta.json FixInsight total mismatch")
    if int(delta_pal.get("total_after", -1)) != expected_counts["pascal_analyzer"]["total"]:
        raise ValueError("delta.json Pascal Analyzer total mismatch")

    history_path = out_root / "history.jsonl"
    history = list(_iter_jsonl(history_path)) if history_path.exists() else []
    actual = history[-1].get("ownership") if history else None
    if actual != expected:
        raise ValueError(
            f"history.jsonl ownership mismatch: expected={expected}, actual={actual}"
        )
    history_fi = history[-1].get("fixinsight") or {}
    history_pal = (history[-1].get("pascal_analyzer") or {}).get("totals") or {}
    history_raw = history[-1].get("raw") or {}
    if int(history_fi.get("total", -1)) != expected_counts["fixinsight"]["total"]:
        raise ValueError("history.jsonl FixInsight total mismatch")
    if history_pal != {
        key: expected_counts["pascal_analyzer"][key]
        for key in ("warnings", "strong_warnings", "optimizations", "total")
    }:
        raise ValueError("history.jsonl Pascal Analyzer totals mismatch")
    if history_raw != expected_projections["raw"]:
        raise ValueError("history.jsonl raw projection mismatch")

    ownership_text = _ownership_text(expected)
    ownership_lines = (
        ("summary.md", "- ", "summary.md ownership mismatch"),
        ("delta.md", "- After: ", "delta.md After ownership mismatch"),
        ("trend.md", "- Latest ownership: ", "trend.md ownership mismatch"),
        ("triage.md", "- Ownership: ", "triage.md ownership mismatch"),
    )
    for name, prefix, error in ownership_lines:
        lines = _read_text(out_root / name).splitlines()
        if f"{prefix}{ownership_text}" not in lines:
            raise ValueError(f"{error}: expected {ownership_text!r}")
    raw_ownership_text = _ownership_text(expected_projections["raw"]["ownership"])
    trend_lines = _read_text(out_root / "trend.md").splitlines()
    if f"- Latest raw ownership: {raw_ownership_text}" not in trend_lines:
        raise ValueError(
            f"trend.md raw ownership mismatch: expected {raw_ownership_text!r}"
        )
    _verify_triage_evidence(out_root, summary_json, fi_path, pal_path)
    delta_markdown = _read_text(out_root / "delta.md")
    if not re.search(
        rf"^- Findings: .* -> {expected_counts['fixinsight']['total']} \(",
        delta_markdown,
        flags=re.MULTILINE,
    ):
        raise ValueError("delta.md FixInsight total mismatch")
    if not re.search(
        rf"^- Total: .* -> {expected_counts['pascal_analyzer']['total']} \(",
        delta_markdown,
        flags=re.MULTILINE,
    ):
        raise ValueError("delta.md Pascal Analyzer total mismatch")

    triage = _read_text(out_root / "triage.md")
    for label, count in (
        ("FixInsight", expected_counts["fixinsight"]["total"]),
        ("Pascal Analyzer", expected_counts["pascal_analyzer"]["total"]),
    ):
        if f"- {label} findings: {count} " not in triage:
            raise ValueError(f"triage.md {label} total mismatch")

    trend_rows = [
        [cell.strip() for cell in line.strip().strip("|").split("|")]
        for line in _read_text(out_root / "trend.md").splitlines()
        if line.startswith("| ") and not line.startswith("| ---")
    ]
    if len(trend_rows) < 2:
        raise ValueError("trend.md latest totals are missing")
    latest = trend_rows[-1]
    expected_trend = [
        expected_counts["fixinsight"]["total"],
        expected_counts["pascal_analyzer"]["strong_warnings"],
        expected_counts["pascal_analyzer"]["warnings"],
        expected_counts["pascal_analyzer"]["optimizations"],
        expected_counts["pascal_analyzer"]["total"],
    ]
    actual_trend = [int(latest[index]) for index in (1, 3, 5, 7, 9)]
    if actual_trend != expected_trend:
        raise ValueError(
            f"trend.md total mismatch: expected={expected_trend}, actual={actual_trend}"
        )

    sarif = _load_json(out_root / "static-analysis.sarif")
    full_sarif = _load_json(out_root / "static-analysis.full.sarif")
    with tempfile.TemporaryDirectory(prefix="dak-sarif-verify-") as temp_dir:
        expected_root = Path(temp_dir)
        expected_sarif_path = _write_sarif(
            expected_root,
            fi_jsonl_path=fi_path,
            pal_jsonl_path=pal_path,
        )
        expected_full_sarif_path = _write_sarif(
            expected_root,
            fi_jsonl_path=fi_path,
            pal_jsonl_path=pal_path,
            full_evidence=True,
        )
        if sarif != _load_json(expected_sarif_path):
            raise ValueError("static-analysis.sarif evidence mismatch")
        if full_sarif != _load_json(expected_full_sarif_path):
            raise ValueError("static-analysis.full.sarif evidence mismatch")
    sarif_records = [
        {
            "ownership": (result.get("properties") or {}).get("ownership"),
            "ownership_root": (result.get("properties") or {}).get("ownership_root"),
        }
        for run in sarif.get("runs") or []
        for result in run.get("results") or []
    ]
    if any(
        not record["ownership"] or "ownership_root" not in record
        for record in sarif_records
    ):
        raise ValueError("static-analysis.sarif ownership is missing")
    actual = _ownership_counts(sarif_records)
    expected_sarif = [
        {
            "ownership": record["ownership"],
            "ownership_root": record.get("ownership_root"),
        }
        for record in records
    ]
    if (
        actual != expected
        or len(sarif_records) != len(records)
        or sarif_records != expected_sarif
    ):
        raise ValueError(
            f"static-analysis.sarif ownership mismatch: "
            f"expected={expected}, actual={actual}"
        )
    full_sarif_records = [
        {
            "ownership": (result.get("properties") or {}).get("ownership"),
            "ownership_root": (result.get("properties") or {}).get(
                "ownership_root"
            ),
        }
        for run in full_sarif.get("runs") or []
        for result in run.get("results") or []
    ]
    expected_full_sarif = [
        {
            "ownership": record["ownership"],
            "ownership_root": record.get("ownership_root"),
        }
        for record in raw_records
    ]
    if (
        len(full_sarif_records) != len(raw_records)
        or full_sarif_records != expected_full_sarif
    ):
        raise ValueError(
            "static-analysis.full.sarif raw evidence mismatch: "
            f"expected={len(raw_records)}, actual={len(full_sarif_records)}"
        )
    return expected


def main(argv: list[str]) -> int:
    verify = len(argv) == 3 and argv[1] == "--verify"
    if not verify and len(argv) != 2:
        print(
            "Usage: postprocess.py [--verify] <path-to-analysis-out-root>",
            file=sys.stderr,
        )
        return 2

    out_root = Path(argv[2] if verify else argv[1]).expanduser()
    if not out_root.is_absolute():
        out_root = (Path.cwd() / out_root).resolve()
    if verify:
        try:
            counts = verify_outputs(out_root)
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 3
        print(json.dumps({"ownership": counts, "verified": True}, sort_keys=True))
        return 0
    title = out_root.name

    res = run_postprocess(out_root, title=title)
    print(json.dumps(res, indent=2, sort_keys=True))
    return 0 if res.get("gate_pass", True) else 3


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
