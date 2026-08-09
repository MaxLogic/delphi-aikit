from __future__ import annotations

import configparser
import os
from pathlib import Path
from typing import NamedTuple, Optional


class Workspace(NamedTuple):
    selector: str
    root: Path
    vcs: str
    source: str


class WorkspaceError(ValueError):
    pass


def delphi_source_files(root: Path) -> list[Path]:
    result: list[Path] = []
    excluded = {".dak", ".git", ".svn"}
    suffixes = {".pas", ".dpr", ".dpk", ".inc"}
    for current, directories, files in os.walk(root, followlinks=False):
        current_path = Path(current)
        directories[:] = sorted(
            name
            for name in directories
            if name.casefold() not in excluded
            and not (current_path / name).is_symlink()
        )
        for name in sorted(files):
            path = current_path / name
            if path.suffix.casefold() in suffixes and not path.is_symlink():
                result.append(path.resolve())
    return result


def _has_marker(root: Path, name: str) -> bool:
    marker = root / name
    return marker.is_dir() if name == ".svn" else marker.exists()


def _find_marker(start_dir: Path, name: str) -> Optional[Path]:
    current = start_dir.resolve()
    while True:
        if _has_marker(current, name):
            return current
        if current.parent == current:
            return None
        current = current.parent


def _vcs_at(root: Path) -> str:
    if _has_marker(root, ".git"):
        return "git"
    if _has_marker(root, ".svn"):
        return "svn"
    return "none"


def find_vcs_root(start_dir: Path) -> tuple[Optional[Path], str]:
    current = start_dir.resolve()
    while True:
        vcs = _vcs_at(current)
        if vcs != "none":
            return current, vcs
        if current.parent == current:
            return None, "none"
        current = current.parent


def _find_auto_root(start_dir: Path) -> tuple[Path, str]:
    root, vcs = find_vcs_root(start_dir)
    return (root, vcs) if root is not None else (start_dir.resolve(), "none")


def _read_selector(path: Path) -> Optional[str]:
    if not path.is_file():
        return None
    settings = configparser.ConfigParser(interpolation=None)
    try:
        settings.read(path, encoding="utf-8-sig")
    except (configparser.Error, OSError, UnicodeError) as error:
        raise WorkspaceError(f'Cannot read workspace selector from "{path}": {error}') from error
    section = next(
        (name for name in settings.sections() if name.casefold() == "workspace"),
        None,
    )
    if section is None or not settings.has_option(section, "Root"):
        return None
    return settings.get(section, "Root").strip()


def _discover_selector(start_dir: Path, executable_ini: Optional[Path]) -> tuple[str, str, Path]:
    current = start_dir.resolve()
    while True:
        ini_path = current / "dak.ini"
        value = _read_selector(ini_path)
        if value is not None:
            return value, str(ini_path.resolve()), current
        if current.parent == current:
            break
        current = current.parent
    if executable_ini is not None:
        value = _read_selector(executable_ini)
        if value is not None:
            resolved_ini = executable_ini.resolve()
            return value, str(resolved_ini), resolved_ini.parent
    return "auto", "default", start_dir.resolve()


def resolve_workspace(
    subject: Path,
    selector: str = "",
    *,
    executable_ini: Optional[Path] = None,
    cwd: Optional[Path] = None,
) -> Workspace:
    start_dir = subject.resolve().parent
    if selector.strip():
        value = selector.strip()
        source = "command_line"
        base_dir = (cwd or Path.cwd()).resolve()
    else:
        value, source, base_dir = _discover_selector(start_dir, executable_ini)
    if not value:
        raise WorkspaceError(f'Workspace Root in "{source}" is empty.')
    normalized = value.casefold()
    if normalized in {"git", "svn"}:
        vcs = normalized
        root = _find_marker(start_dir, f".{vcs}")
        if root is None:
            raise WorkspaceError(
                f"Workspace Root={vcs} requires a .{vcs} marker above {start_dir}."
            )
        return Workspace(vcs, root, vcs, source)
    if normalized == "project":
        return Workspace("project", start_dir, _vcs_at(start_dir), source)
    if normalized == "auto":
        root, vcs = _find_auto_root(start_dir)
        return Workspace("auto", root, vcs, source)
    if value:
        path_value = value.replace("\\", os.sep) if os.name != "nt" else value
        root = Path(path_value).expanduser()
        if not root.is_absolute():
            root = base_dir / root
        root = root.resolve()
        if not root.is_dir():
            raise WorkspaceError(f'Workspace root "{root}" from "{source}" does not exist.')
        if not start_dir.is_relative_to(root):
            raise WorkspaceError(
                f'Workspace root "{root}" does not contain subject directory "{start_dir}".'
            )
        return Workspace(value, root, _vcs_at(root), source)
    raise AssertionError("unreachable")


def settings_paths(
    subject: Path, workspace: Workspace, executable_ini: Optional[Path] = None
) -> list[Path]:
    paths: list[Path] = []
    seen: set[str] = set()

    def add(path: Path) -> None:
        resolved = path.resolve()
        key = str(resolved).casefold()
        if key not in seen:
            seen.add(key)
            paths.append(resolved)

    if workspace.source == "default" and executable_ini is not None:
        add(executable_ini)
    current = workspace.root.resolve()
    add(current / "dak.ini")
    relative = subject.resolve().parent.relative_to(current)
    for part in relative.parts:
        current /= part
        add(current / "dak.ini")
    return paths
