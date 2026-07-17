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
- Report identity: `/NAME=<exact-project-name>`
- Report format: `/F=T|H|X` (Text/HTML/XML)
- Quiet mode: `/Q`
- Parse forms: `/A+` (source + form files)
- Parse scope: `/FA` (all files)
- Threads: `/T=n` (1..64; DAK selects the automatic value)

## 3) DelphiAIKit contract

### CLI flags (new, non-breaking)

- `analyze --pascal-analyzer true`
- `--pa-path "<path>"` (optional)
- `--pa-output "<path>"` (optional)
- `--pa-args "<args>"` (optional)
- `--pa-timeout-sec N` (optional, positive integer seconds)

### dak.ini section

```ini
[PascalAnalyzer]
Path=
Output=
Args=
TimeoutSec=
```

Semantics:

- `Path` may be a full path to `palcmd.exe` / `palcmd32.exe`, or a folder containing them.
- `Output` is a report root folder; we pass it to PALCMD as `/R=...`.
- `Args` are parsed as additive PAL options. DAK rejects attempts to override
  its report format/root/name, quiet mode, parse scope, or thread count.
- `TimeoutSec` bounds the external PALCMD wait; the CLI override wins when both are present.

### Invariant automation arguments

When `--pascal-analyzer true` is used, DAK always supplies:

- `/F=X /Q /A+ /FA /T=<automatic-count>`
- an exact `/NAME` and `/R`
- `/CD...` derived from `--delphi` + `--platform` unless additive args contain
  an explicit compiler target
- `/BUILD`, `/D`, and `/S` from project context when available

PAL help is authoritative for target availability. PAL 9.21 exposes Delphi 12
and Delphi 13 Win64 (`/CD12W64`, `/CD13W64`); BDS 37 maps to Delphi 13. Version
mapping is used only when help cannot be read.

## 4) Executable discovery (must be deterministic and fast)

Resolve `palcmd.exe`/`palcmd32.exe` in this order:

1. CLI override: `--pa-path`
2. cascading `dak.ini` override: `[PascalAnalyzer].Path`
3. Known default (v9): `C:\Program Files\Peganza\Pascal Analyzer 9\palcmd.exe` (and `palcmd32.exe`)
4. Version sweep (Program Files + x86): `...\Peganza\Pascal Analyzer {5..15}\palcmd(.exe|32.exe)` (newest wins)
5. Folder scan (depth-limited): `...\Peganza\Pascal Analyzer*\` (top-level only), pick newest folder containing PALCMD
6. If still not found: hard error (exit code 7) telling the user to provide `--pa-path` or `dak.ini` `Path=...`.

## 5) Notes

- We do not map mask-based excludes to PALCMD `/X` or `/XF`; filtering remains
  deterministic post-processing of normalized findings.

## PALCMD Help

Run `palcmd.exe` without arguments to print its help. The reviewed PAL 9.21.3
snapshot is stored in `docs/spec-slices/palcmd.help.txt`.
