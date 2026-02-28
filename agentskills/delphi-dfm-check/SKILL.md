---
name: delphi-dfm-check
description: Validate Delphi DFM resources by running DelphiAIKit `dfm-check` (or `build --dfmcheck`) and fail on streaming errors.
---

# Delphi DFM Check

Use this skill when we need deterministic DFM streaming validation in CI or local automation.

## Canonical Interface

1. Run `"$DAK_EXE" dfm-check ...` for standalone validation.
2. Run `"$DAK_EXE" build ... --dfmcheck` when we want build + DFM validation in one command.
3. Do not call `msbuild.exe` or internal helper scripts directly unless we are debugging tool internals.

Before running commands, set `DAK_EXE` to an absolute path of `DelphiAIKit.exe`.

## Command

```bash
"$DAK_EXE" dfm-check --dproj "<path-to-project.dproj>" --config Release --platform Win32
```

Optional:

- `--rsvars "<path-to-rsvars.bat>"`

Defaults:

- `config=Release`
- `platform=Win32`

## Build Integration Command

```bash
"$DAK_EXE" build --project "<path-to-project.dproj>" --delphi 23.0 --platform Win32 --config Release --dfmcheck --ai
```

`--dfmcheck` is a presence flag. If present, DFM validation runs after successful build.

## Expected Output Behavior

- Stage markers for generation/build/run phases.
- Per-resource lines with `OK` or `FAIL`.
- Exit code `0` when all streamable DFM resources are valid.
- Non-zero exit code when any DFM stream fails.

## Proof Commands

Run relevant test gates in repo root:

```bash
./tests/DelphiAIKit.Tests.exe
tests/run.sh
```

For manual validation:

1. Clean project: command exits `0`, only `OK` resource lines.
2. Broken DFM project: command exits non-zero and prints `FAIL ...` with streaming exception text.
