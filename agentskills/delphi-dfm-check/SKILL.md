---
name: delphi-dfm-check
description: Enforce Delphi DFM streaming validation for form-related changes via `dfm-check` or `build --dfmcheck`.
---

# Delphi DFM Check

Use this skill whenever we touch Delphi forms, frames, datamodules, or any `.dfm`-backed UI changes.

## Mandatory Policy

1. After every form-related change, run DFM validation before we finalize work.
2. Prefer `build --dfmcheck` when we are already building the project.
3. Use `dfm-check` standalone when we only need DFM validation.
4. Treat any `FAIL` line as a critical error and fix it immediately.
5. Do not skip, suppress, or defer DFM failures.

## Environment Contract (same as delphi-build)

Use the same environment variables as `agentskills/delphi-build`:

- `DAK_EXE` (required): absolute path to `DelphiAIKit.exe`
- `DAK_BUILD_SH` (optional, WSL convenience)

Preflight:

```bash
test -x "$DAK_EXE" || { echo "DAK_EXE not executable"; exit 1; }
if grep -qi microsoft /proc/version 2>/dev/null; then
  if [ -n "${DAK_BUILD_SH:-}" ]; then
    test -x "$DAK_BUILD_SH" || { echo "DAK_BUILD_SH is set but not executable"; exit 1; }
  fi
fi
```

## Canonical Commands

Standalone DFM validation:

```bash
"$DAK_EXE" dfm-check --dproj "<path-to-project.dproj>" --config Release --platform Win32
```

Optional:

- `--rsvars "<path-to-rsvars.bat>"`

Build with integrated DFM validation:

```bash
"$DAK_EXE" build --project "<path-to-project.dproj>" --delphi 23.0 --platform Win32 --config Release --dfmcheck
```

`--dfmcheck` is a presence flag. If present, DFM validation runs after successful build.
For broader build workflow and options, use `agentskills/delphi-build/SKILL.md`.

Defaults:

- `config=Release`
- `platform=Win32`

## Success/Failure Contract

- Stage markers for generation/build/run phases.
- Per-resource lines with `OK` or `FAIL`.
- Exit code `0`: all streamable DFM resources are valid.
- Exit code `>0`: one or more DFM streams failed; this blocks completion.

## Remediation Rules (required)

When validation reports `FAIL`, we must fix DFM-related issues and re-run validation until exit code is `0`.

Typical fixes:

1. Remove or correct stale properties in `.dfm` that no longer exist in the class.
2. Restore missing published properties/components expected by the `.dfm`.
3. Align renamed controls/components between `.pas` and `.dfm`.
4. Re-run `dfm-check` (or `build --dfmcheck`) after each fix batch.

Task completion gate:

- Do not finish form-related tasks while DFM validation is failing.
