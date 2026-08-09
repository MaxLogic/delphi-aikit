#!/usr/bin/env python3
# Thin wrapper around DelphiAIKit.exe analyze --unit.
# Handles WSL path conversion and prints summary.md when available.

from __future__ import annotations

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from workspace import WorkspaceError, find_vcs_root, resolve_workspace


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


def _to_win_arg(p: Path) -> str:
    s = str(p)
    if not _is_wsl():
        return s
    if _looks_like_windows_path(s):
        return s
    return _wslpath_to_windows(p)


def _find_dak_exe(
    unit_path: Path, workspace_root: Optional[Path] = None
) -> Path:
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

    if workspace_root is not None:
        roots.append(workspace_root)
    else:
        cwd = Path.cwd()
        roots.append(cwd)
        cwd_root, _ = find_vcs_root(cwd)
        if cwd_root is not None:
            roots.append(cwd_root)

        target_root, _ = find_vcs_root(unit_path.parent)
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


def _merge_rule_lists(*values: str) -> str:
    items: list[str] = []
    seen: set[str] = set()
    for value in values:
        for item in value.split(";"):
            rule = item.strip()
            if rule and rule.lower() not in seen:
                seen.add(rule.lower())
                items.append(rule)
    return ";".join(items)


def _dak_child_environment(pal_ignore_rules: str) -> dict[str, str]:
    environment = os.environ.copy()
    if pal_ignore_rules:
        environment["DAK_PAL_IGNORE_RULES_ORIGIN"] = (
            "environment:DAK_PAL_IGNORE_RULES"
        )
    else:
        environment.pop("DAK_PAL_IGNORE_RULES_ORIGIN", None)
    return environment


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
    workspace_selector: str = "",
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
    if workspace_selector:
        args += ["--workspace-root", workspace_selector]

    _maybe_add_arg(args, "--fixinsight", "false")
    _maybe_add_arg(args, "--pascal-analyzer", pal_flag)
    _maybe_add_arg(args, "--clean", clean_flag)
    _maybe_add_arg(args, "--write-summary", summary_flag)

    pa_path = os.environ.get("PA_PATH", "").strip()
    pa_args = os.environ.get("PA_ARGS", "").strip()
    pa_exclude_search_folders = os.environ.get(
        "DAK_PAL_EXCLUDE_SEARCH_FOLDERS", ""
    ).strip()
    pa_exclude_files = os.environ.get("DAK_PAL_EXCLUDE_FILES", "").strip()
    fi_ignore_rules = _merge_rule_lists(
        os.environ.get("DAK_FI_IGNORE_RULES", ""),
        os.environ.get("DAK_IGNORE_WARNING_IDS", ""),
    )
    pal_ignore_rules = os.environ.get("DAK_PAL_IGNORE_RULES", "").strip()
    if pa_path:
        args += ["--pa-path", _to_win_arg(Path(pa_path))]
    if pa_args:
        args += ["--pa-args", pa_args]
    if pa_exclude_search_folders:
        args += ["--pa-exclude-search-folders", pa_exclude_search_folders]
    if pa_exclude_files:
        args += ["--pa-exclude-files", pa_exclude_files]
    if fi_ignore_rules:
        args += ["--ignore-warning-ids", fi_ignore_rules]
    if pal_ignore_rules:
        args += ["--pal-ignore-rules", pal_ignore_rules]
    return args


def _parse_args(argv: list[str]) -> tuple[str, str, str]:
    parser = argparse.ArgumentParser(prog=Path(argv[0]).name)
    parser.add_argument("unit")
    parser.add_argument("project_context", nargs="?", default="")
    parser.add_argument("--workspace-root", default="")
    options = parser.parse_args(argv[1:])
    return options.unit, options.project_context, options.workspace_root


def main(argv: list[str]) -> int:
    unit_arg, project_arg, workspace_selector = _parse_args(argv)
    unit_path = _normalize_input_path(unit_arg)
    if not unit_path.is_absolute():
        unit_path = (Path.cwd() / unit_path).resolve()
    else:
        unit_path = unit_path.resolve()
    if not unit_path.exists():
        print(f"ERROR: .pas not found: {unit_path}", file=sys.stderr)
        return 2

    project_context: Optional[Path] = None
    if project_arg.strip():
        project_context = _normalize_input_path(project_arg)
        if not project_context.is_absolute():
            project_context = (Path.cwd() / project_context).resolve()
        else:
            project_context = project_context.resolve()
        if not project_context.exists():
            print(f"ERROR: .dproj not found: {project_context}", file=sys.stderr)
            return 2

    workspace_subject = project_context if project_context is not None else unit_path
    resolution_selector = workspace_selector
    if (
        workspace_selector
        and workspace_selector.casefold() not in {"auto", "git", "svn", "project"}
        and _is_wsl()
        and _looks_like_windows_path(workspace_selector)
    ):
        resolution_selector = str(_normalize_input_path(workspace_selector))
    try:
        workspace = resolve_workspace(
            workspace_subject, resolution_selector, cwd=Path.cwd()
        )
        if workspace.source != "default":
            dak_exe = _find_dak_exe(unit_path, workspace.root)
        else:
            dak_exe = _find_dak_exe(unit_path)
            workspace = resolve_workspace(
                workspace_subject,
                executable_ini=dak_exe.parent / "dak.ini",
                cwd=Path.cwd(),
            )
    except WorkspaceError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    dak_exe_arg = _to_win_arg(dak_exe) if _is_wsl() else str(dak_exe)
    forwarded_selector = workspace_selector
    if (
        forwarded_selector
        and forwarded_selector.casefold() not in {"auto", "git", "svn", "project"}
    ):
        forwarded_selector = _to_win_arg(workspace.root)

    out_root = _resolve_out_root(Path.cwd(), unit_path)
    args = _build_dak_args(
        dak_exe_arg, unit_path, out_root, project_context, forwarded_selector
    )

    work_root = workspace.root
    from postprocess import (
        _record_postprocessor_failure,
        capture_run_provenance,
        run_postprocess,
    )

    captured_provenance = capture_run_provenance(
        workspace_subject, dak_exe, workspace
    )
    for stale_name in ("summary.md", "summary.json"):
        (out_root / stale_name).unlink(missing_ok=True)
    pal_ignore_rules = os.environ.get("DAK_PAL_IGNORE_RULES", "").strip()
    child_environment = _dak_child_environment(pal_ignore_rules)

    if _is_wsl():
        p = subprocess.run(
            [_cmd_exe(), "/C"] + args,
            cwd=str(work_root),
            env=child_environment,
        )
    else:
        p = subprocess.run(args, cwd=str(work_root), env=child_environment)

    summary_path = out_root / "summary.md"
    if summary_path.exists():
        print(summary_path.read_text(encoding="utf-8", errors="replace"))
    else:
        print(f"Summary not found: {summary_path}", file=sys.stderr)

    gate_pass = True
    if summary_path.exists():
        try:
            res = run_postprocess(
                out_root,
                title=unit_path.stem,
                captured_provenance=captured_provenance,
                execution_exit_code=p.returncode,
            )
            gate_pass = bool(res.get("gate_pass", True))
            if not gate_pass:
                print(f"Static analysis gate failed (see: {res.get('delta', '')})", file=sys.stderr)
        except Exception as e:
            if p.returncode != 0:
                print(f"Post-processing failed after analyzer failure: {e}", file=sys.stderr)
                return p.returncode
            diagnostic = _record_postprocessor_failure(out_root, e)
            print(
                f"Post-processing failed after successful analyzer: {e} "
                f"(diagnostic: {diagnostic})",
                file=sys.stderr,
            )
            return 4

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
