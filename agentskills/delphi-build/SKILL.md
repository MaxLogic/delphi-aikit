---
name: delphi-build
description: Build Delphi projects via DelphiAIKit from WSL or Windows. Use when asked to compile or rebuild a .dproj (or .dpr/.dpk with sibling .dproj), verify build output, or troubleshoot build failures.
version: "1.1"
---

# Delphi Build

Use this execution order:

1. Use `"$DAK_EXE" build ...` as the canonical interface.
2. Use `"$DAK_BUILD_SH" ...` on WSL only when wrapper path conversion is helpful.
3. Never call raw `msbuild.exe` unless we are explicitly debugging wrappers.

Before running commands, load [setup.md](setup.md) variables.
Commands assume current directory is the target repository root.

Supported project inputs (`--project`):

- `.dproj`
- `.dpr` / `.dpk` only when a sibling `.dproj` exists
- `.groupproj` is not a guaranteed DAK contract in current code

## Preflight

```bash
test -x "$DAK_EXE" || { echo "DAK_EXE not executable"; exit 1; }
if grep -qi microsoft /proc/version 2>/dev/null; then
  if [ -n "${DAK_BUILD_SH:-}" ]; then
    test -x "$DAK_BUILD_SH" || { echo "DAK_BUILD_SH is set but not executable"; exit 1; }
  fi
fi
```

## WSL path conversion (canonical)

`DelphiAIKit.exe build --project` accepts both:

- Linux-style absolute paths from WSL only in `/mnt/<drive>/...` form
- Windows-style absolute paths (`F:\...`)

Other Linux absolute paths (for example `/home/...`) are rejected with a clear error.
`wslpath` conversion remains our canonical safe route, and also helps compatibility with older DelphiAIKit builds.

```bash
PROJECT_LINUX="<path-to-project.dproj>"
PROJECT_WIN="$(wslpath -w -a "$PROJECT_LINUX")"
```

## WSL (Primary)

Canonical build:

```bash
PROJECT_LINUX="_Source/ActiveAppView.dproj"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform Win32 --config Debug --ai
```

Full rebuild:

```bash
PROJECT_LINUX="_Source/ActiveAppView.dproj"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform Win32 --config Debug --target Rebuild --ai
```

Locked-output-safe rebuild (for `F2039` / running EXE):

```bash
PROJECT_LINUX="_Source/ActiveAppView.dproj"
TEST_OUT_WIN="$(wslpath -w -a _build_verify/test-out)"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform Win32 --config Debug --target Rebuild --test-output-dir "$TEST_OUT_WIN" --ai
```

WSL wrapper (`build-delphi.sh`) example:

```bash
PROJECT_LINUX="_Source/ActiveAppView.dproj"
"$DAK_BUILD_SH" "$PROJECT_LINUX" -config Debug -platform Win32 -ver 23 -ai
```

## Windows (Secondary)

PowerShell:

```powershell
$Project = "F:\projects\SomeRepo\_Source\App.dproj"
& $env:DAK_EXE build --project $Project --delphi 23.0 --platform Win32 --config Debug --ai
```

## Setup

Use [setup.md](setup.md) to define `DAK_EXE` and optionally `DAK_BUILD_SH`.

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
- `--dfmcheck` (presence flag; when present, run DFM validation after a successful build)
- `--show-warnings`, `--show-hints`
- `--ai`, `--json`

## Workflow

1. Run build with `--ai`.
2. Add `--dfmcheck` when we want build + DFM streaming validation in one call.
3. If automation needs structured output, rerun with `--json`.
4. If output is locked, either stop the locking process or use `--test-output-dir`.
5. Report actionable diagnostics with exact failing unit/error line and next fix step.

Build plus DFM check example:

```bash
PROJECT_LINUX="_Source/ActiveAppView.dproj"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform Win32 --config Debug --dfmcheck --ai
```
