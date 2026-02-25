---
name: delphi-build
description: Build Delphi projects in this repository from WSL via DelphiAIKit. Use when asked to compile or rebuild .dproj files, or .dpr/.dpk files that have a sibling .dproj, verify build output, or troubleshoot compiler and MSBuild failures.
---

# Delphi Build

Use this execution order:

1. Use `"$DAK_EXE" build ...` as canonical interface.
2. Use `"$DAK_BUILD_SH" ...` on WSL when path conversion is needed.
3. Never call raw `msbuild.exe` unless explicitly debugging wrappers.

Before running commands, load [setup.md](setup.md) variables in the shell session.
Commands assume repo root as current directory. If needed: `cd "$DAK_REPO_ROOT"`.

Supported project inputs (canonical DAK path):

- `.dproj`
- `.dpr` / `.dpk` only when a sibling `.dproj` exists
- `.groupproj` is not a guaranteed DAK contract in current code

## Preflight

```bash
test -x "$DAK_EXE" || { echo "DAK_EXE not executable"; exit 1; }
test -d "$DAK_REPO_ROOT" || { echo "DAK_REPO_ROOT not found"; exit 1; }
if grep -qi microsoft /proc/version 2>/dev/null; then
  test -x "$DAK_BUILD_SH" || { echo "DAK_BUILD_SH required on WSL"; exit 1; }
fi
```

## WSL (Primary)

Canonical build:

```bash
cd "$DAK_REPO_ROOT"
"$DAK_EXE" build --project "projects/DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug --ai
```

WSL wrapper:

```bash
cd "$DAK_REPO_ROOT"
"$DAK_BUILD_SH" projects/DelphiAIKit.dproj -config Debug -platform Win32 -ver 23 -ai
```

Full rebuild:

```bash
cd "$DAK_REPO_ROOT"
"$DAK_EXE" build --project "projects/DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug --target Rebuild
```

## Windows (Secondary)

PowerShell:

```powershell
Set-Location $env:DAK_REPO_ROOT
& $env:DAK_EXE build --project "projects/DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug --ai
```

## Setup

Use [setup.md](setup.md) to define `DAK_EXE`, `DAK_REPO_ROOT`, and `DAK_BUILD_SH` (mandatory on WSL).

## Defaults

- `platform=Win32`, `config=Release`, `target=Build`
- `max-findings=5`
- `build-timeout-sec=0`
- warnings and hints hidden unless requested

## Key Flags

- `--target Build|Rebuild`, `--rebuild true|false`
- `--max-findings N`
- `--build-timeout-sec N`
- `--test-output-dir "<path>"`
- `--show-warnings`, `--show-hints`
- `--ai`, `--json`

## Workflow

1. Run build with `--ai`.
2. If automation needs structured output, rerun with `--json`.
3. If output is locked or artifacts must stay untouched, use `--test-output-dir`.
4. Verify repo gate:
   - `"$DAK_EXE" build --project "projects/DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug --ai`
   - `tests/run.sh`
