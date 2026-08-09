#!/usr/bin/env python3
# Environment "doctor" for the Delphi static analysis skill.
#
# Goal: fail fast on predictable setup issues and print enough context to make
# static analysis runs repeatable (especially in CI).

from __future__ import annotations

import argparse
import configparser
from dataclasses import dataclass
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional, Sequence

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from workspace import WorkspaceError, find_vcs_root, resolve_workspace, settings_paths


@dataclass(frozen=True)
class PalHelpInfo:
    version: str
    architecture: str
    help_available: bool
    supported_targets: tuple[tuple[str, str, str], ...]


PalTarget = tuple[str, str, str]


def _is_wsl() -> bool:
    return bool(os.environ.get("WSL_DISTRO_NAME")) or ("microsoft" in platform.release().lower())


def _cmd_exe() -> str:
    # In some restricted WSL environments, executing `cmd.exe` via PATH is blocked, while
    # invoking it by absolute path remains allowed.
    return "/mnt/c/Windows/System32/cmd.exe" if _is_wsl() else "cmd.exe"


def _looks_like_windows_path(s: str) -> bool:
    return bool(re.match(r"^[A-Za-z]:[\\/]", s) or s.startswith("\\\\"))


def _run_capture(cmd: list[str], timeout: int = 15) -> tuple[int, str]:
    try:
        p = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            timeout=timeout,
        )
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


def _find_dak_exe(
    target_dir: Path, workspace_root: Optional[Path] = None
) -> Path:
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

    if workspace_root is not None:
        roots.append(workspace_root)
    else:
        cwd = Path.cwd()
        roots.append(cwd)
        cwd_root, _ = find_vcs_root(cwd)
        if cwd_root is not None:
            roots.append(cwd_root)

        roots.append(target_dir)
        tgt_root, _ = find_vcs_root(target_dir)
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


def _choose_palcmd(directory: Path) -> Optional[Path]:
    for name in ("palcmd.exe", "palcmd32.exe"):
        candidate = directory / name
        if candidate.is_file():
            return candidate.resolve()
    return None


def _pal_install_roots() -> list[Path]:
    roots: list[Path] = []
    environment = _pal_environment()
    for name in ("ProgramFiles", "ProgramFiles(x86)", "ProgramW6432"):
        value = environment.get(name.casefold(), "").strip()
        if not value:
            continue
        root = _normalize_input_path(value)
        if root not in roots:
            roots.append(root)
    if not roots:
        roots.extend(_normalize_input_path(p) for p in (r"C:\Program Files", r"C:\Program Files (x86)"))
    return roots


def _parse_windows_environment(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        name, value = line.split("=", 1)
        if name:
            result[name.casefold()] = value
    return result


def _pal_environment() -> dict[str, str]:
    result = {name.casefold(): value for name, value in os.environ.items()}
    if _is_wsl():
        code, output = _run_capture([_cmd_exe(), "/D", "/C", "set"])
        if code == 0:
            result.update(_parse_windows_environment(output))
    return result


def _expand_windows_env(value: str, environment: Optional[dict[str, str]] = None) -> str:
    env = environment or _pal_environment()
    return re.sub(
        r"%([^%]+)%",
        lambda match: env.get(match.group(1).casefold(), match.group(0)),
        value,
    )


def _normalize_configured_path(value: str, base_dir: Optional[Path]) -> Path:
    path = _normalize_input_path(_expand_windows_env(value.strip()))
    if not path.is_absolute():
        path = (base_dir or Path.cwd()) / path
    return path


def _resolve_palcmd(
    override: str,
    roots: Optional[Sequence[Path]] = None,
    base_dir: Optional[Path] = None,
) -> Path:
    if override.strip():
        path = _normalize_configured_path(override, base_dir)
        if path.is_dir():
            resolved = _choose_palcmd(path)
            if resolved is not None:
                return resolved
            raise FileNotFoundError(f"PALCMD executable not found in folder: {path}")
        if path.is_file():
            return path.resolve()
        raise FileNotFoundError(f"PALCMD executable not found at: {path}")

    install_roots = list(roots) if roots is not None else _pal_install_roots()
    for root in install_roots:
        resolved = _choose_palcmd(root / "Peganza" / "Pascal Analyzer 9")
        if resolved is not None:
            return resolved

    for version in range(15, 4, -1):
        for root in install_roots:
            resolved = _choose_palcmd(root / "Peganza" / f"Pascal Analyzer {version}")
            if resolved is not None:
                return resolved

    best: tuple[int, Path] | None = None
    fallback: Optional[Path] = None
    for root in install_roots:
        peganza = root / "Peganza"
        if not peganza.is_dir():
            continue
        for directory in peganza.glob("Pascal Analyzer*"):
            resolved = _choose_palcmd(directory)
            if resolved is None:
                continue
            match = re.search(r"(\d+)\s*$", directory.name)
            if match:
                candidate = (int(match.group(1)), resolved)
                if best is None or candidate[0] > best[0]:
                    best = candidate
            elif fallback is None:
                fallback = resolved
    if best is not None:
        return best[1]
    if fallback is not None:
        return fallback
    raise FileNotFoundError("PALCMD not found. Set PA_PATH or [PascalAnalyzer].Path in dak.ini.")


def _parse_pal_help(text: str) -> PalHelpInfo:
    version_match = re.search(r"Pascal Analyzer\s+\((\d+)-bits\)\s+version\s+([0-9.]+)", text, re.IGNORECASE)
    architecture = f"{version_match.group(1)}-bit" if version_match else "unknown"
    version = version_match.group(2) if version_match else "unknown"
    targets = tuple(
        (delphi, platform_name, flag)
        for delphi, platform_name, flag in (
            ("Delphi 12", "Win32", "/CD12W32"),
            ("Delphi 12", "Win64", "/CD12W64"),
            ("Delphi 13", "Win32", "/CD13W32"),
            ("Delphi 13", "Win64", "/CD13W64"),
        )
        if re.search(rf"(?im)^\s*{re.escape(flag)}\b", text)
    )
    return PalHelpInfo(version, architecture, "Syntax:" in text, targets)


def _requested_pal_target(bds_version: str, platform_name: str) -> Optional[PalTarget]:
    bds = bds_version.strip()
    if not bds:
        return None
    try:
        bds_major = int(bds.split(".", 1)[0])
    except ValueError:
        return (f"BDS {bds}", platform_name.strip() or "<empty>", "")
    delphi = {23: "12", 37: "13"}.get(bds_major)
    platform_value = platform_name.strip().casefold() or "win32"
    platform_label = {"win32": "Win32", "win64": "Win64"}.get(platform_value)
    if delphi is None or platform_label is None:
        return (f"BDS {bds}", platform_name.strip() or "Win32", "")
    return (f"Delphi {delphi}", platform_label, f"/CD{delphi}W{platform_label[-2:]}")


def _pal_target_supported(info: PalHelpInfo, target: PalTarget) -> bool:
    return bool(target[2]) and target in info.supported_targets


def _pal_check_error(
    exit_code: int, info: PalHelpInfo, requested: Optional[PalTarget]
) -> str:
    if exit_code != 0 or not info.help_available:
        return f"PALCMD help failed (exit={exit_code})."
    if requested is not None and not _pal_target_supported(info, requested):
        return "Requested Delphi/platform target is not supported by PALCMD help."
    return ""


def _format_pal_report(
    executable: Path, info: PalHelpInfo, requested: Optional[PalTarget] = None
) -> str:
    lines = [
        f"- Executable: {executable}",
        f"- Architecture: {info.architecture}",
        f"- Version: {info.version}",
        f"- Help: {'available' if info.help_available else 'unavailable'}",
    ]
    supported = {(delphi, target): flag for delphi, target, flag in info.supported_targets}
    for delphi in ("Delphi 12", "Delphi 13"):
        flag = supported.get((delphi, "Win64"))
        status = f"supported ({flag})" if flag else "not listed by PAL help"
        lines.append(f"- {delphi} Win64: {status}")
    if requested is not None:
        delphi, platform_name, flag = requested
        if _pal_target_supported(info, requested):
            status = f"supported ({flag})"
        elif flag:
            status = f"not listed by PAL help ({flag})"
        else:
            status = "unsupported mapping"
        lines.append(f"- Requested target: {delphi} {platform_name}: {status}")
    return "\n".join(lines)


def _load_dak_settings(
    executable: Path, target: Optional[Path], workspace_selector: str = ""
) -> tuple[configparser.ConfigParser, list[Path]]:
    executable_ini = executable.parent / "dak.ini"
    if target is None:
        paths = [executable_ini]
    else:
        workspace = resolve_workspace(
            target,
            workspace_selector,
            executable_ini=executable_ini,
            cwd=Path.cwd(),
        )
        paths = settings_paths(target, workspace, executable_ini)

    cp = configparser.ConfigParser(interpolation=None)
    cp.read([str(path) for path in paths if path.is_file()], encoding="utf-8")
    return cp, paths


def _parse_args(argv: list[str]) -> tuple[str, str]:
    parser = argparse.ArgumentParser(prog=Path(argv[0]).name)
    parser.add_argument("target", nargs="?", default="")
    parser.add_argument("--workspace-root", default="")
    options = parser.parse_args(argv[1:])
    return options.target, options.workspace_root


def _fmt_kv(k: str, v: str) -> str:
    v = (v or "").strip()
    return f"{k}={v if v else '<empty>'}"


def _analysis_policy_source_paths(paths: list[Path]) -> list[Path]:
    result: list[Path] = []
    for path in paths:
        current = configparser.ConfigParser(interpolation=None)
        try:
            current.read([str(path)], encoding="utf-8-sig")
        except (configparser.Error, OSError, UnicodeError):
            continue
        if current.has_section("AnalysisPolicy") or current.has_section(
            "PascalAnalyzerIgnore"
        ):
            result.append(path)
    return result


def _format_analysis_policy_preview(
    settings: configparser.ConfigParser, sources: list[Path]
) -> str:
    policy = (
        settings["AnalysisPolicy"]
        if settings.has_section("AnalysisPolicy")
        else {}
    )
    diagnostics = (
        settings["Diagnostics"] if settings.has_section("Diagnostics") else {}
    )
    source_text = ", ".join(str(path) for path in sources) or "<none>"
    return "\n".join(
        (
            "- AnalysisPolicy."
            + _fmt_kv(
                "GateOwnership",
                policy.get("GateOwnership", "project;repository"),
            ),
            "- AnalysisPolicy."
            + _fmt_kv("ProjectRoots", policy.get("ProjectRoots", "")),
            "- AnalysisPolicy."
            + _fmt_kv(
                "ThirdPartyRoots", policy.get("ThirdPartyRoots", "")
            ),
            f"- AnalysisPolicy.Sources={source_text}",
            "- Diagnostics."
            + _fmt_kv(
                "IgnoreUnknownMacros",
                diagnostics.get("IgnoreUnknownMacros", ""),
            ),
            "- Diagnostics."
            + _fmt_kv(
                "IgnoreMissingPaths",
                diagnostics.get("IgnoreMissingPaths", ""),
            ),
        )
    )


def main(argv: list[str]) -> int:
    script_dir = Path(__file__).resolve().parent
    target_dir = Path.cwd()
    target = None
    target_arg, workspace_selector = _parse_args(argv)
    if target_arg:
        target = _normalize_input_path(target_arg)
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

    resolution_selector = workspace_selector
    if (
        workspace_selector
        and workspace_selector.casefold() not in {"auto", "git", "svn", "project"}
        and _is_wsl()
        and _looks_like_windows_path(workspace_selector)
    ):
        resolution_selector = str(_normalize_input_path(workspace_selector))
    try:
        if target is not None:
            workspace = resolve_workspace(
                target, resolution_selector, cwd=Path.cwd()
            )
            dak_exe = _find_dak_exe(
                target_dir,
                workspace.root if workspace.source != "default" else None,
            )
        else:
            dak_exe = _find_dak_exe(target_dir)
        if target is not None and workspace.source == "default":
            workspace = (
                resolve_workspace(
                    target,
                    executable_ini=dak_exe.parent / "dak.ini",
                    cwd=Path.cwd(),
                )
            )
        elif target is None:
            workspace = None
        ini, dak_ini_paths = _load_dak_settings(
            dak_exe, target, resolution_selector
        )
    except (FileNotFoundError, WorkspaceError) as error:
        print()
        print(f"ERROR: {error}")
        return 2
    dak_dir = dak_exe.parent
    existing_ini_paths = [path for path in dak_ini_paths if path.exists()]

    print()
    print("## Resolver")
    print(f"- DAK_EXE: {os.environ.get('DAK_EXE','').strip() or '<default>'}")
    print(f"- DelphiAIKit.exe: {dak_exe}")
    if workspace is not None:
        print(f"- Workspace selector: {workspace.selector}")
        print(f"- Workspace root: {workspace.root}")
        print(f"- Workspace VCS: {workspace.vcs}")
        print(f"- Workspace source: {workspace.source}")
    print(f"- dak.ini: {', '.join(str(path) for path in existing_ini_paths) or '<missing>'}")

    pa_path = ""
    if existing_ini_paths:
        print()
        print("## dak.ini (high-signal)")
        fi = ini["FixInsightCL"] if ini.has_section("FixInsightCL") else {}
        print(f"- FixInsightCL.{_fmt_kv('Silent', fi.get('Silent', ''))}")
        print(f"- FixInsightCL.{_fmt_kv('Settings', fi.get('Settings', ''))}")
        filt = ini["ReportFilter"] if ini.has_section("ReportFilter") else {}
        print(f"- ReportFilter.{_fmt_kv('ExcludePathMasks', filt.get('ExcludePathMasks', ''))}")
        ign = ini["FixInsightIgnore"] if ini.has_section("FixInsightIgnore") else {}
        print(f"- FixInsightIgnore.{_fmt_kv('Warnings', ign.get('Warnings', ''))}")
        pal_ign = (
            ini["PascalAnalyzerIgnore"]
            if ini.has_section("PascalAnalyzerIgnore")
            else {}
        )
        print(
            f"- PascalAnalyzerIgnore.{_fmt_kv('Rules', pal_ign.get('Rules', ''))}"
        )
        pa = ini["PascalAnalyzer"] if ini.has_section("PascalAnalyzer") else {}
        print(f"- PascalAnalyzer.{_fmt_kv('Path', pa.get('Path', ''))}")
        print(f"- PascalAnalyzer.{_fmt_kv('Args', pa.get('Args', ''))}")
        print(
            _format_analysis_policy_preview(
                ini, _analysis_policy_source_paths(existing_ini_paths)
            )
        )

        pa_path = (pa.get("Path", "") or "").strip()
        if pa_path:
            try:
                p = _normalize_configured_path(pa_path, dak_dir)
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
        "PA_PATH",
        "DAK_EXCLUDE_PATH_MASKS",
        "DAK_FI_IGNORE_RULES",
        "DAK_IGNORE_WARNING_IDS",
        "DAK_PAL_IGNORE_RULES",
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
            if target.suffix.lower() == ".pas":
                out_root = target.parent / ".dak" / "_unit" / target.stem
            else:
                out_root = target.parent / ".dak" / target.stem
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

        print()
        print("## Pascal Analyzer")
        try:
            palcmd = _resolve_palcmd(
                os.environ.get("PA_PATH", "").strip() or pa_path,
                base_dir=dak_dir,
            )
        except Exception as e:
            print(f"ERROR: {e}")
            return 3
        code, help_text = _run_capture([str(palcmd)])
        info = _parse_pal_help(help_text)
        requested = _requested_pal_target(
            os.environ.get("DAK_DELPHI", ""),
            os.environ.get("DAK_PLATFORM", "Win32"),
        )
        print(_format_pal_report(palcmd, info, requested))
        pal_error = _pal_check_error(code, info, requested)
        if pal_error:
            print(f"ERROR: {pal_error}")
            return 3

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
