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
import platform
import posixpath
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional


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

    pal_version_m = re.search(r"^- Version:\s*([0-9.]+)\s*$", text, flags=re.MULTILINE)
    if pal_version_m:
        data["pal_version"] = pal_version_m.group(1)

    pal_target_m = re.search(r"^- Compiler target:\s*(.+)\s*$", text, flags=re.MULTILINE)
    if pal_target_m:
        data["pal_compiler_target"] = pal_target_m.group(1).strip()

    return data


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

    fi_line = _last_matching_line(text, prefix="CMD:", contains="fixinsightcl.exe")
    if fi_line:
        m = re.search(r'^CMD:\s*"(?P<exe>[^"]*FixInsightCL\.exe)"', fi_line, flags=re.IGNORECASE)
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
            ["git", "status", "--porcelain=v1", "-z"],
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
        # Rename/copy are encoded as: `R  old\0new\0` (same for `C`).
        if status[:1] in ("R", "C") or status[1:2] in ("R", "C"):
            if i < len(entries):
                path2 = entries[i]
                i += 1
                if path2:
                    out.add(path2)
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


def _normalize_path_value(raw_path: str, *, repo_root: Optional[Path], base_dirs: list[Path]) -> str:
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
                mapped = _repo_unique_basename_index(repo_root).get(base.lower())
                if mapped:
                    return mapped

    # Fallback: normalize separators + dot segments deterministically.
    s = s.replace("\\", "/")
    return posixpath.normpath(s)


_REPO_UNIQUE_BASENAME_INDEX_CACHE: dict[str, dict[str, str]] = {}


def _repo_unique_basename_index(repo_root: Path) -> dict[str, str]:
    cache_key = str(repo_root.resolve()).lower()
    hit = _REPO_UNIQUE_BASENAME_INDEX_CACHE.get(cache_key)
    if hit is not None:
        return hit

    # Use a uniqueness filter: if two files share a basename, we prefer to not map at all.
    seen: dict[str, Optional[str]] = {}
    patterns = ("*.pas", "*.dpr", "*.dpk", "*.inc")
    for pat in patterns:
        for p in repo_root.rglob(pat):
            # Skip analysis artifacts and VCS internals.
            parts = {x.lower() for x in p.parts}
            if ".git" in parts or "_analysis" in parts:
                continue
            try:
                rel = p.relative_to(repo_root).as_posix()
            except ValueError:
                continue
            key = p.name.lower()
            if key in seen:
                seen[key] = None
            else:
                seen[key] = rel

    idx = {k: v for k, v in seen.items() if v is not None}
    _REPO_UNIQUE_BASENAME_INDEX_CACHE[cache_key] = idx
    return idx


def _write_triage_changed(out_root: Path, *, title: str, summary: dict[str, Any], fi_jsonl_path: Path, pal_jsonl_path: Path) -> Path:
    triage_path = out_root / "triage-changed.md"

    repo_root = _find_git_root(out_root)
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
    lines.append(f"- Repo root: `{repo_root}`")
    lines.append(f"- Changed files: {len(changed_sorted)}")
    lines.append("")

    if not changed_sorted:
        lines.append("No Git-changed files detected.")
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
        for obj in _iter_jsonl(fi_jsonl_path):
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
    changed_units = {Path(p).stem.lower() for p in changed_files if p.lower().endswith(".pas")}
    if pal_jsonl_path.exists() and changed_units:
        for obj in _iter_jsonl(pal_jsonl_path):
            mod = str(obj.get("module") or "").strip()
            if not mod:
                continue
            if mod.lower() not in changed_units:
                continue
            section = obj.get("section", "")
            line_no = obj.get("line", "?")
            msg = obj.get("message", "")
            pal_items.append(f"[{section}] {mod}:{line_no} - {msg}")

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


def _write_triage(out_root: Path, *, title: str, fi_jsonl_path: Path, pal_jsonl_path: Path) -> Path:
    triage_path = out_root / "triage.md"
    top_n = _int_env("DAK_TRIAGE_TOP", 20) or 20

    fi_items: list[dict[str, Any]] = []
    if fi_jsonl_path.exists():
        for obj in _iter_jsonl(fi_jsonl_path):
            path = obj.get("path") or obj.get("file") or "?"
            kind = str(obj.get("kind") or "").strip()
            fi_items.append(
                {
                    "priority": _fi_triage_priority(kind),
                    "path": str(path),
                    "code": obj.get("code") or "?",
                    "kind": kind,
                    "line": obj.get("line") or "?",
                    "col": obj.get("col") or "?",
                    "message": obj.get("message") or "",
                }
            )

    fi_items.sort(key=lambda x: (-int(x["priority"]), str(x["code"]), str(x["path"]), int(x["line"]) if str(x["line"]).isdigit() else 0))
    fi_top = fi_items[:top_n]

    pal_items: list[dict[str, Any]] = []
    if pal_jsonl_path.exists():
        for obj in _iter_jsonl(pal_jsonl_path):
            severity = str(obj.get("severity") or "").strip()
            path = obj.get("path") or obj.get("module") or "?"
            pal_items.append(
                {
                    "priority": _pal_triage_priority(severity),
                    "path": str(path),
                    "severity": severity,
                    "section": obj.get("section") or "",
                    "module": obj.get("module") or "?",
                    "line": obj.get("line") or "?",
                    "message": obj.get("message") or "",
                }
            )

    pal_items.sort(key=lambda x: (-int(x["priority"]), str(x["severity"]), str(x["path"]), int(x["line"]) if str(x["line"]).isdigit() else 0))
    pal_top = pal_items[:top_n]

    lines: list[str] = []
    lines.append(f"# {title} triage")
    lines.append("")
    lines.append(f"- Timestamp: {_utc_now_iso()}")
    lines.append(f"- FixInsight findings: {len(fi_items)} (showing top {min(top_n, len(fi_items))})")
    lines.append(f"- Pascal Analyzer findings: {len(pal_items)} (showing top {min(top_n, len(pal_items))})")
    lines.append("")

    lines.append("## FixInsight")
    if not fi_top:
        lines.append("No FixInsight findings.")
        lines.append("")
    else:
        groups: dict[str, list[dict[str, Any]]] = {}
        for it in fi_top:
            groups.setdefault(str(it["path"]), []).append(it)
        for path, items in groups.items():
            lines.append(f"### `{path}`")
            for it in items:
                lines.append(f"- [{it['code']}] {it['line']}:{it['col']} - {it['message']}")
            lines.append("")

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
                lines.append(f"- [{it['severity']}] {it['line']} - {section}: {it['message']}")
            lines.append("")

    _write_text(triage_path, "\n".join(lines).rstrip() + "\n")
    return triage_path


def _build_pascal_unit_index(repo_root: Path) -> dict[str, str]:
    idx: dict[str, str] = {}
    for p in repo_root.rglob("*.pas"):
        # Skip analysis artifacts and VCS internals.
        parts = {x.lower() for x in p.parts}
        if ".git" in parts or "_analysis" in parts:
            continue
        try:
            rel = p.relative_to(repo_root).as_posix()
        except ValueError:
            continue
        key = p.stem.lower()
        prev = idx.get(key)
        # Prefer a stable/shortest path when duplicates exist.
        if prev is None or len(rel) < len(prev):
            idx[key] = rel
    return idx


def _normalize_pal_findings_jsonl(pal_jsonl_path: Path, *, repo_root: Optional[Path]) -> None:
    if not pal_jsonl_path.exists() or repo_root is None:
        return

    # Avoid an expensive repo scan when the file is already normalized.
    # We treat `path: null` as "not normalized yet".
    needs_normalize = False
    for i, first in enumerate(_iter_jsonl(pal_jsonl_path)):
        if not isinstance(first, dict):
            continue
        if first.get("path") is None:
            needs_normalize = True
            break
        if "path" not in first:
            needs_normalize = True
            break
        if i >= 50:
            break
    if not needs_normalize:
        return

    idx = _build_pascal_unit_index(repo_root)
    out_items: list[dict[str, Any]] = []
    for obj in _iter_jsonl(pal_jsonl_path):
        if not isinstance(obj, dict):
            continue
        mod = str(obj.get("module") or "").strip()
        unit_key = mod.split("\\", 1)[0].split("/", 1)[0].strip().lower()
        obj2 = dict(obj)
        obj2["path"] = idx.get(unit_key)
        out_items.append(obj2)

    _write_jsonl(pal_jsonl_path, out_items)


def _fi_findings_to_jsonl(
    findings: Iterable[FixInsightFinding],
    *,
    repo_root: Optional[Path],
    base_dirs: list[Path],
) -> Iterable[dict[str, Any]]:
    for f in findings:
        norm_file = posixpath.normpath(f.file.replace("\\", "/"))
        norm_path = _normalize_path_value(f.file, repo_root=repo_root, base_dirs=base_dirs)
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


def _diff_run_context(baseline_ctx: Any, current_ctx: Any) -> list[str]:
    b = baseline_ctx if isinstance(baseline_ctx, dict) else {}
    c = current_ctx if isinstance(current_ctx, dict) else {}

    out: list[str] = []

    def add(label: str, before: Any, after: Any) -> None:
        bv = str(before or "").strip()
        av = str(after or "").strip()
        if not bv or not av:
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


def _select_new_fi_items(fi_jsonl_path: Path, new_hashes: set[str], *, use_normalized_path: bool) -> list[str]:
    if not fi_jsonl_path.exists() or not new_hashes:
        return []
    items: list[str] = []
    for obj in _iter_jsonl(fi_jsonl_path):
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
        reasons.append(f"New FixInsight W-findings: {new_fi_w} > {max_new_fi_w}")

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

    repo_root = _find_git_root(out_root)
    project_dir: Optional[Path] = None
    proj_local = _to_local_path(str(summary.get("project") or ""))
    if proj_local is not None:
        project_dir = proj_local.parent
    elif repo_root is not None:
        cand = repo_root / "projects"
        if cand.exists():
            project_dir = cand

    base_dirs = [x for x in [project_dir, repo_root] if isinstance(x, Path)]

    fi_norm = {}
    if fixinsight_dir.exists():
        fi_norm = write_fixinsight_normalized(fixinsight_dir, repo_root=repo_root, base_dirs=base_dirs)

    pal_jsonl_path = pal_dir / "pal-findings.jsonl"
    fi_jsonl_path = fixinsight_dir / "fi-findings.jsonl"

    _normalize_pal_findings_jsonl(pal_jsonl_path, repo_root=repo_root)

    baseline_path = Path(os.environ.get("DAK_BASELINE", "")).expanduser().resolve() if os.environ.get("DAK_BASELINE", "").strip() else (out_root / "baseline.json")
    update_baseline = _truthy_env("DAK_UPDATE_BASELINE", False)
    gate_enabled = _truthy_env("DAK_GATE", False) or _truthy_env("DAK_CI", False)
    scope = os.environ.get("DAK_SCOPE", "").strip().lower()

    baseline_exists = baseline_path.exists()
    baseline: Optional[dict[str, Any]] = _load_json(baseline_path) if baseline_exists else None

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

    current_fi_w_hashes_raw: list[str] = []
    current_fi_w_hashes_norm: list[str] = []
    current_fi_counts_by_code: dict[str, int] = {}
    fi_total = None

    # Prefer summary totals for consistency with DAK output.
    if "fixinsight_total" in summary:
        fi_total = int(summary["fixinsight_total"])

    if fi_norm.get("counts_by_code"):
        current_fi_counts_by_code = {k: int(v) for k, v in fi_norm["counts_by_code"].items()}
        if fi_total is None:
            fi_total = int(fi_norm.get("findings", 0))

    if isinstance(fi_norm.get("w_hashes_raw"), list):
        current_fi_w_hashes_raw = [str(x) for x in (fi_norm.get("w_hashes_raw") or [])]
    if isinstance(fi_norm.get("w_hashes_norm"), list):
        current_fi_w_hashes_norm = [str(x) for x in (fi_norm.get("w_hashes_norm") or [])]

    pal_totals = (summary.get("pal_totals") or {}) if isinstance(summary, dict) else {}

    current_snapshot: dict[str, Any] = {
        "version": 3,
        "created_at": summary.get("timestamp") or _utc_now_iso(),
        "run_context": _build_run_context(out_root, summary, allow_env=True, expected_summary_timestamp=None),
        "summary": summary,
        "fixinsight": {
            "total": fi_total,
            "counts_by_code": current_fi_counts_by_code,
            "w_hashes": sorted(set(current_fi_w_hashes_norm)),
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
            "baseline": {
                "path": str(baseline_path),
                "timestamp": current_snapshot["created_at"],
                "created": True,
                "run_context": current_snapshot.get("run_context") or {},
            },
            "current": {
                "summary_path": str(summary_path),
                "timestamp": current_snapshot["created_at"],
                "run_context": current_snapshot.get("run_context") or {},
            },
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
        triage_path = _write_triage(out_root, title=title, fi_jsonl_path=fi_jsonl_path, pal_jsonl_path=pal_jsonl_path)
        res = {"baseline": str(baseline_path), "delta": str(delta_md_path), "gate_pass": True, "baseline_created": True, "triage": str(triage_path)}
        if scope == "changed":
            triage_changed_path = _write_triage_changed(out_root, title=title, summary=summary, fi_jsonl_path=fi_jsonl_path, pal_jsonl_path=pal_jsonl_path)
            res["triage_changed"] = str(triage_changed_path)
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

    if baseline_dirty:
        _write_json(baseline_path, baseline)

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
    try:
        baseline_ver_now = int(baseline.get("version", 0))
    except (TypeError, ValueError):
        baseline_ver_now = 0
    use_norm_fi = baseline_ver_now >= 3
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

    delta_obj: dict[str, Any] = {
        "title": title,
        "baseline": {
            "path": str(baseline_path),
            "timestamp": baseline.get("created_at") or baseline.get("summary", {}).get("timestamp"),
            "run_context": baseline.get("run_context") or {},
        },
        "current": {
            "summary_path": str(summary_path),
            "timestamp": current_snapshot["created_at"],
            "run_context": current_snapshot.get("run_context") or {},
        },
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
    snapshot_for_baseline_md = current_snapshot if update_baseline else baseline
    _write_text(baseline_md_path, _render_baseline_md(title, baseline_path, snapshot_for_baseline_md, summary_path=summary_path))

    if update_baseline:
        _write_json(baseline_path, current_snapshot)

    triage_path = _write_triage(out_root, title=title, fi_jsonl_path=fi_jsonl_path, pal_jsonl_path=pal_jsonl_path)
    res = {
        "baseline": str(baseline_path),
        "delta": str(delta_md_path),
        "gate_pass": bool(delta_obj["gate"]["pass"]),
        "baseline_updated": bool(update_baseline),
        "triage": str(triage_path),
    }
    if scope == "changed":
        triage_changed_path = _write_triage_changed(out_root, title=title, summary=summary, fi_jsonl_path=fi_jsonl_path, pal_jsonl_path=pal_jsonl_path)
        res["triage_changed"] = str(triage_changed_path)
    return res


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
