# Pascal Analyzer CLI (PALCMD) integration

This spec-slice captures the minimal contract we need to integrate Peganza Pascal Analyzer's CLI (`PALCMD.EXE` / `PALCMD32.EXE`) into DelphiAIKit.

## 1) Canonical CLI syntax

```text
PALCMD projectpath|sourcepath [options]
```

We run PALCMD against our resolved main project entrypoint (typically the `.dpr`).

## 2) PALCMD options we use (automation subset)

- Target/compiler mode: `/CD...` (example: `/CD12W32`, `/CD12W64`)
- Build configuration: `/BUILD=<ConfigName>` (case-sensitive; must match the DPROJ config name)
- Defines: `/D=DEF1;DEF2;...`
- Search folders: `/S="p1;p2;..."`
- Report root folder: `/R="C:\Out"` (output folder root)
- Report format: `/F=T|H|X` (Text/HTML/XML)
- Quiet mode: `/Q`
- Parse forms: `/A+` (source + form files)
- Parse scope: `/FA` (all files)
- Threads: `/T=n` (1..64)

## 3) DelphiAIKit contract

### CLI flags (new, non-breaking)

- `analyze --pascal-analyzer true`
- `--pa-path "<path>"` (optional)
- `--pa-output "<path>"` (optional)
- `--pa-args "<args>"` (optional)

### settings.ini section (new)

```ini
[PascalAnalyzer]
Path=
Output=
Args=
```

Semantics:

- `Path` may be a full path to `palcmd.exe` / `palcmd32.exe`, or a folder containing them.
- `Output` is a report root folder; we pass it to PALCMD as `/R=...`.
- `Args` are appended verbatim to the PALCMD invocation.

### Defaults when Args is empty

When `--pascal-analyzer true` is used and neither `--pa-args` nor `[PascalAnalyzer].Args` is set:

- Use `/F=X /Q /A+ /FA /T=min(CPUCount, 64)`
- Add `/CD...` derived from `--delphi` + `--platform` (unless the args already contain a `/CD...` flag)

## 4) Executable discovery (must be deterministic and fast)

Resolve `palcmd.exe`/`palcmd32.exe` in this order:

1. CLI override: `--pa-path`
2. settings.ini override: `[PascalAnalyzer].Path`
3. Known default (v9): `C:\Program Files\Peganza\Pascal Analyzer 9\palcmd.exe` (and `palcmd32.exe`)
4. Version sweep (Program Files + x86): `...\Peganza\Pascal Analyzer {5..15}\palcmd(.exe|32.exe)` (newest wins)
5. Folder scan (depth-limited): `...\Peganza\Pascal Analyzer*\` (top-level only), pick newest folder containing PALCMD
6. If still not found: hard error (exit code 7) telling the user to provide `--pa-path` or settings.ini `Path=...`.

## 5) Notes

- We do not try to map our mask-based excludes to PALCMD's `/X` and `/XF` automatically (PALCMD takes folder/file lists, not globs). If needed, the user can pass `/X` and `/XF` via `--pa-args`.

## PALCMD Help

to see the help for palmcmd.exe just run it, it will print the help.
We have a copy in 
./docs/spec-slices/palcmd.help.txt
