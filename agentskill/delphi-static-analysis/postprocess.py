#!/usr/bin/env python3
# Post-process analysis outputs produced by DelphiAIKit.exe.
# - Normalizes FixInsight TXT report into JSONL/MD (for greppable triage + deltas).
# - Maintains a per-output-root baseline snapshot and produces delta reports.
#
# This file is intentionally dependency-free (stdlib only) so it runs on both
# Windows and WSL without extra installs.

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _truthy_env(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return default
    return raw in ("1", "true", "yes", "y", "on")


def _int_env(name: str, default: int | None) -> int | None:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        raise ValueError(f"{name} must be an integer, got: {raw!r}")


def _sha1(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8", errors="replace")).hexdigest()


def _read_text(path: Path) -> str:
    # FixInsight TXT often has a UTF-8 BOM; utf-8-sig strips it.
    return path.read_text(encoding="utf-8-sig", errors="replace")


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", errors="replace")


def _write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _iter_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            yield json.loads(line)


def _write_jsonl(path: Path, items: Iterable[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for obj in items:
            f.write(json.dumps(obj, ensure_ascii=True) + "\n")


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

    fi_total_m = re.search(r"^- Findings \(by code\):\s*(\d+)\s*$", text, flags=re.MULTILINE)
    if fi_total_m:
        data["fixinsight_total"] = int(fi_total_m.group(1))

    fi_top: dict[str, int] = {}
    for m in re.finditer(r"^\s*-\s*([A-Z]\d{3}):\s*(\d+)\s*$", text, flags=re.MULTILINE):
        fi_top[m.group(1)] = int(m.group(2))
    if fi_top:
        data["fixinsight_top_codes"] = fi_top

    pal_totals_m = re.search(
        r"^- Totals:\s*warnings=(\d+),\s*strong_warnings=(\d+),\s*exceptions=(\d+)\s*$",
        text,
        flags=re.MULTILINE,
    )
    if pal_totals_m:
        data["pal_totals"] = {
            "warnings": int(pal_totals_m.group(1)),
            "strong_warnings": int(pal_totals_m.group(2)),
            "exceptions": int(pal_totals_m.group(3)),
        }

    return data


def parse_fixinsight_txt(txt_path: Path) -> list[FixInsightFinding]:
    if not txt_path.exists():
        return []

    findings: list[FixInsightFinding] = []
    current_file: str | None = None

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


def _fi_findings_to_jsonl(findings: Iterable[FixInsightFinding]) -> Iterable[dict[str, Any]]:
    for f in findings:
        yield {
            "tool": "FixInsight",
            "code": f.code,
            "kind": f.kind,
            "file": f.file,
            "line": f.line,
            "col": f.col,
            "message": f.message,
        }


def write_fixinsight_normalized(out_fixinsight_dir: Path) -> dict[str, Any]:
    txt_path = out_fixinsight_dir / "fixinsight.txt"
    findings = parse_fixinsight_txt(txt_path)
    if not findings:
        return {"txt_path": str(txt_path), "findings": 0}

    jsonl_path = out_fixinsight_dir / "fi-findings.jsonl"
    md_path = out_fixinsight_dir / "fi-findings.md"

    _write_jsonl(jsonl_path, _fi_findings_to_jsonl(findings))

    md_lines: list[str] = []
    for f in findings:
        md_lines.append(f"{f.code} | {f.file}:{f.line}:{f.col} | {f.message}")
    _write_text(md_path, "\n".join(md_lines) + "\n")

    counts_by_code: dict[str, int] = dict(Counter([f.code for f in findings]))

    return {
        "txt_path": str(txt_path),
        "jsonl_path": str(jsonl_path),
        "md_path": str(md_path),
        "findings": len(findings),
        "counts_by_code": counts_by_code,
    }


def _pal_fingerprint(obj: dict[str, Any]) -> str:
    # We intentionally include "section" and location so deltas are actionable.
    parts = [
        str(obj.get("severity", "")),
        str(obj.get("report", "")),
        str(obj.get("section", "")),
        str(obj.get("module", "")),
        str(obj.get("line", "")),
        str(obj.get("message", "")),
        str(obj.get("id", "")),
        str(obj.get("kind", "")),
    ]
    return _sha1("|".join(parts))


def _fi_fingerprint(obj: dict[str, Any]) -> str:
    parts = [
        str(obj.get("code", "")),
        str(obj.get("file", "")),
        str(obj.get("line", "")),
        str(obj.get("col", "")),
        str(obj.get("message", "")),
    ]
    return _sha1("|".join(parts))


def _top_section_counts(pal_jsonl_path: Path, *, severity: str) -> list[dict[str, Any]]:
    if not pal_jsonl_path.exists():
        return []
    ctr: Counter[str] = Counter()
    for obj in _iter_jsonl(pal_jsonl_path):
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


def _render_delta_md(delta: dict[str, Any]) -> str:
    lines: list[str] = []
    title = delta.get("title") or "Static analysis delta"
    lines.append(f"# {title}")
    lines.append("")

    baseline = delta.get("baseline") or {}
    current = delta.get("current") or {}
    lines.append(f"- Baseline: `{baseline.get('path', '')}` ({baseline.get('timestamp', 'unknown')})")
    lines.append(f"- Current: `{current.get('summary_path', '')}` ({current.get('timestamp', 'unknown')})")
    lines.append("")

    fi = delta.get("fixinsight") or {}
    lines.append("## FixInsight")
    lines.append(f"- Findings: {fi.get('total_before', '?')} -> {fi.get('total_after', '?')} ({fi.get('total_delta', 0):+d})")
    lines.append(f"- New W-codes: {fi.get('new_w_count', 0)}")
    if fi.get("top_code_deltas"):
        lines.append("- Top code deltas:")
        for row in fi["top_code_deltas"]:
            lines.append(f"  - {row['code']}: {row['before']} -> {row['after']} ({row['delta']:+d})")
    lines.append("")

    pal = delta.get("pascal_analyzer") or {}
    lines.append("## Pascal Analyzer")
    lines.append(f"- Strong warnings: {pal.get('strong_before', '?')} -> {pal.get('strong_after', '?')} ({pal.get('strong_delta', 0):+d})")
    lines.append(f"- Warnings: {pal.get('warnings_before', '?')} -> {pal.get('warnings_after', '?')} ({pal.get('warnings_delta', 0):+d})")
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
        lines.append(f"### New FixInsight W-codes ({len(fi['new_w'])})")
        for item in fi["new_w"][:20]:
            lines.append(f"- {item}")
        lines.append("")

    gate = delta.get("gate") or {}
    if gate.get("enabled"):
        status = "PASS" if gate.get("pass") else "FAIL"
        lines.append("## Gate")
        lines.append(f"- Result: **{status}**")
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
        lines.append(f"- Totals: warnings={totals.get('warnings','?')}, strong_warnings={totals.get('strong_warnings','?')}, exceptions={totals.get('exceptions','?')}")
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
    for obj in _iter_jsonl(pal_jsonl_path):
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


def _select_new_fi_items(fi_jsonl_path: Path, new_hashes: set[str]) -> list[str]:
    if not fi_jsonl_path.exists() or not new_hashes:
        return []
    items: list[str] = []
    for obj in _iter_jsonl(fi_jsonl_path):
        if obj.get("kind") != "W":
            continue
        h = _fi_fingerprint(obj)
        if h not in new_hashes:
            continue
        code = obj.get("code", "?")
        file = obj.get("file", "?")
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

    reasons: list[str] = []
    ok = True

    pal = delta.get("pascal_analyzer") or {}
    fi = delta.get("fixinsight") or {}

    new_strong = int(pal.get("new_strong_count", 0))
    if max_new_pal_strong is not None and new_strong > max_new_pal_strong:
        ok = False
        reasons.append(f"New PAL strong warnings: {new_strong} > {max_new_pal_strong}")

    new_fi_w = int(fi.get("new_w_count", 0))
    if max_new_fi_w is not None and new_fi_w > max_new_fi_w:
        ok = False
        reasons.append(f"New FixInsight W-codes: {new_fi_w} > {max_new_fi_w}")

    if max_pal_warning_increase is not None:
        inc = int(pal.get("warnings_delta", 0))
        if inc > max_pal_warning_increase:
            ok = False
            reasons.append(f"PAL warnings increase: {inc} > {max_pal_warning_increase}")

    if max_fi_total_increase is not None:
        inc = int(fi.get("total_delta", 0))
        if inc > max_fi_total_increase:
            ok = False
            reasons.append(f"FixInsight findings increase: {inc} > {max_fi_total_increase}")

    return ok, reasons


def run_postprocess(out_root: Path, *, title: str) -> dict[str, Any]:
    out_root = out_root.resolve()
    fixinsight_dir = out_root / "fixinsight"
    pal_dir = out_root / "pascal-analyzer"

    summary_path = out_root / "summary.md"
    summary = parse_dak_summary_md(summary_path)

    fi_norm = {}
    if fixinsight_dir.exists():
        fi_norm = write_fixinsight_normalized(fixinsight_dir)

    pal_jsonl_path = pal_dir / "pal-findings.jsonl"
    fi_jsonl_path = fixinsight_dir / "fi-findings.jsonl"

    baseline_path = Path(os.environ.get("DAK_BASELINE", "")).expanduser().resolve() if os.environ.get("DAK_BASELINE", "").strip() else (out_root / "baseline.json")
    update_baseline = _truthy_env("DAK_UPDATE_BASELINE", False)
    gate_enabled = _truthy_env("DAK_GATE", False) or _truthy_env("DAK_CI", False)

    baseline_exists = baseline_path.exists()
    baseline: dict[str, Any] | None = _load_json(baseline_path) if baseline_exists else None

    current_pal_warning_hashes: list[str] = []
    current_pal_strong_hashes: list[str] = []
    current_pal_warning_top = _top_section_counts(pal_jsonl_path, severity="warning")

    if pal_jsonl_path.exists():
        for obj in _iter_jsonl(pal_jsonl_path):
            sev = obj.get("severity")
            if sev == "warning":
                current_pal_warning_hashes.append(_pal_fingerprint(obj))
            elif sev == "strong-warning":
                current_pal_strong_hashes.append(_pal_fingerprint(obj))

    current_fi_w_hashes: list[str] = []
    current_fi_counts_by_code: dict[str, int] = {}
    fi_total = None

    # Prefer summary totals for consistency with DAK output.
    if "fixinsight_total" in summary:
        fi_total = int(summary["fixinsight_total"])

    if fi_norm.get("counts_by_code"):
        current_fi_counts_by_code = {k: int(v) for k, v in fi_norm["counts_by_code"].items()}
        if fi_total is None:
            fi_total = int(fi_norm.get("findings", 0))

    if fi_jsonl_path.exists():
        for obj in _iter_jsonl(fi_jsonl_path):
            if obj.get("kind") != "W":
                continue
            current_fi_w_hashes.append(_fi_fingerprint(obj))

    pal_totals = (summary.get("pal_totals") or {}) if isinstance(summary, dict) else {}

    current_snapshot: dict[str, Any] = {
        "version": 1,
        "created_at": summary.get("timestamp") or _utc_now_iso(),
        "summary": summary,
        "fixinsight": {
            "total": fi_total,
            "counts_by_code": current_fi_counts_by_code,
            "w_hashes": sorted(set(current_fi_w_hashes)),
        },
        "pascal_analyzer": {
            "totals": pal_totals,
            "top_warning_sections": current_pal_warning_top,
            "warning_hashes": sorted(set(current_pal_warning_hashes)),
            "strong_hashes": sorted(set(current_pal_strong_hashes)),
        },
    }

    delta_path = out_root / "delta.json"
    delta_md_path = out_root / "delta.md"
    baseline_md_path = baseline_path.with_suffix(".md")

    if not baseline_exists:
        _write_json(baseline_path, current_snapshot)
        _write_text(baseline_md_path, _render_baseline_md(title, baseline_path, current_snapshot, summary_path=summary_path))
        pal_totals = current_snapshot.get("pascal_analyzer", {}).get("totals", {}) or {}
        fi_total = current_snapshot.get("fixinsight", {}).get("total")
        delta_obj = {
            "title": title,
            "baseline": {"path": str(baseline_path), "timestamp": current_snapshot["created_at"], "created": True},
            "current": {"summary_path": str(summary_path), "timestamp": current_snapshot["created_at"]},
            "fixinsight": {
                "total_before": fi_total,
                "total_after": fi_total,
                "total_delta": 0,
                "top_code_deltas": [],
                "new_w_count": 0,
                "new_w": [],
            },
            "pascal_analyzer": {
                "warnings_before": pal_totals.get("warnings"),
                "warnings_after": pal_totals.get("warnings"),
                "warnings_delta": 0,
                "strong_before": pal_totals.get("strong_warnings"),
                "strong_after": pal_totals.get("strong_warnings"),
                "strong_delta": 0,
                "new_strong_count": 0,
                "new_strong": [],
                "new_warnings_count": 0,
                "new_warnings_preview": [],
                "top_section_deltas": [],
            },
            "note": "Baseline created (no delta).",
            "gate": {"enabled": gate_enabled, "pass": True, "reasons": []},
        }
        _write_json(delta_path, delta_obj)
        _write_text(delta_md_path, _render_delta_md(delta_obj))
        return {"baseline": str(baseline_path), "delta": str(delta_md_path), "gate_pass": True, "baseline_created": True}

    assert baseline is not None

    b_fi = baseline.get("fixinsight") or {}
    b_pal = baseline.get("pascal_analyzer") or {}

    # Counts (prefer summary values when present).
    b_fi_total = b_fi.get("total")
    a_fi_total = current_snapshot["fixinsight"]["total"]
    total_delta = None
    if isinstance(b_fi_total, int) and isinstance(a_fi_total, int):
        total_delta = a_fi_total - b_fi_total

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

    strong_before = b_pal_totals.get("strong_warnings")
    strong_after = a_pal_totals.get("strong_warnings")
    strong_delta = None
    if isinstance(strong_before, int) and isinstance(strong_after, int):
        strong_delta = strong_after - strong_before

    # Finding deltas (hash-based).
    b_pal_warn = set(b_pal.get("warning_hashes") or [])
    b_pal_strong = set(b_pal.get("strong_hashes") or [])
    a_pal_warn = set(current_snapshot["pascal_analyzer"]["warning_hashes"])
    a_pal_strong = set(current_snapshot["pascal_analyzer"]["strong_hashes"])

    new_pal_warn = a_pal_warn - b_pal_warn
    new_pal_strong = a_pal_strong - b_pal_strong

    b_fi_w = set(b_fi.get("w_hashes") or [])
    a_fi_w = set(current_snapshot["fixinsight"]["w_hashes"])
    new_fi_w = a_fi_w - b_fi_w

    pal_new_strong_items = _select_new_pal_items(pal_jsonl_path, new_pal_strong, severity="strong-warning")
    pal_new_warn_preview = _select_new_pal_items(pal_jsonl_path, new_pal_warn, severity="warning")[:20]

    fi_new_w_items = _select_new_fi_items(fi_jsonl_path, new_fi_w)

    b_top_sections = b_pal.get("top_warning_sections") or []
    a_top_sections = current_snapshot["pascal_analyzer"]["top_warning_sections"] or []
    top_section_deltas = _section_delta(b_top_sections, a_top_sections) if b_top_sections or a_top_sections else []

    delta_obj: dict[str, Any] = {
        "title": title,
        "baseline": {"path": str(baseline_path), "timestamp": baseline.get("created_at") or baseline.get("summary", {}).get("timestamp")},
        "current": {"summary_path": str(summary_path), "timestamp": current_snapshot["created_at"]},
        "fixinsight": {
            "total_before": b_fi_total,
            "total_after": a_fi_total,
            "total_delta": int(total_delta or 0),
            "top_code_deltas": top_code_deltas,
            "new_w_count": len(new_fi_w),
            "new_w": fi_new_w_items,
        },
        "pascal_analyzer": {
            "warnings_before": warnings_before,
            "warnings_after": warnings_after,
            "warnings_delta": int(warnings_delta or 0),
            "strong_before": strong_before,
            "strong_after": strong_after,
            "strong_delta": int(strong_delta or 0),
            "new_strong_count": len(new_pal_strong),
            "new_strong": pal_new_strong_items,
            "new_warnings_count": len(new_pal_warn),
            "new_warnings_preview": pal_new_warn_preview,
            "top_section_deltas": top_section_deltas,
        },
        "gate": {"enabled": gate_enabled},
    }

    if gate_enabled:
        gate_ok, reasons = _gate_eval(delta_obj)
        delta_obj["gate"]["pass"] = gate_ok
        delta_obj["gate"]["reasons"] = reasons
    else:
        delta_obj["gate"]["pass"] = True
        delta_obj["gate"]["reasons"] = []

    _write_json(delta_path, delta_obj)
    _write_text(delta_md_path, _render_delta_md(delta_obj))

    # Write a human baseline summary too (helps review in PRs).
    _write_text(baseline_md_path, _render_baseline_md(title, baseline_path, current_snapshot, summary_path=summary_path))

    if update_baseline:
        _write_json(baseline_path, current_snapshot)

    return {
        "baseline": str(baseline_path),
        "delta": str(delta_md_path),
        "gate_pass": bool(delta_obj["gate"]["pass"]),
        "baseline_updated": bool(update_baseline),
    }


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: postprocess.py <path-to-analysis-out-root>", file=sys.stderr)
        return 2

    out_root = Path(argv[1]).expanduser()
    if not out_root.is_absolute():
        out_root = (Path.cwd() / out_root).resolve()
    title = out_root.name

    res = run_postprocess(out_root, title=title)
    print(json.dumps(res, indent=2, sort_keys=True))
    return 0 if res.get("gate_pass", True) else 3


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
