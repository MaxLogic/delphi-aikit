---
name: delphi-dfm-check
description: Inspect and validate Delphi DFM forms via `dfm-inspect`, `dfm-check`, or `build --dfmcheck`.
version: "1.2"
---

# Delphi DFM Check

Use this skill whenever we touch Delphi forms, frames, datamodules, or any `.dfm`-backed UI changes.

## Mandatory Policy

1. After every form-related change, run DFM validation before we finalize work.
2. Prefer `build --dfmcheck` when we are already building the project.
3. Use `dfm-check` standalone when we only need DFM validation.
4. Treat any `FAIL` line as a critical error and fix it immediately.
5. Do not skip, suppress, or defer DFM failures.
6. Do not call `msbuild` directly; use `DelphiAIKit.exe` orchestration commands only.

## Environment Contract (same as delphi-build)

Use the same environment variables as `delphi-build`:

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

Lightweight text-DFM inspection:

```bash
"$DAK_EXE" dfm-inspect --dfm "<path-to-form.dfm>" --format tree
"$DAK_EXE" dfm-inspect --dfm "<path-to-form.dfm>" --format summary
```

Use `dfm-inspect` when we need to understand the component tree, key event bindings, or basic form shape before editing.
It is not a substitute for `dfm-check`; inspection is optional, validation is mandatory.

Standalone DFM validation:

```bash
"$DAK_EXE" dfm-check --dproj "<path-to-project.dproj>" --config Release --platform Win32
```

Optional:

- `--delphi 23.0` (or provide `[Build] DelphiVersion` in cascading `dak.ini`)
- `--rsvars "<path-to-rsvars.bat>"`
- `--dfm "MainForm.dfm,Frames\DetailSubEditDocs.dfm"` (selected forms only)
- `--all` (validate all forms; default when `--dfm` is omitted)
- `--source-context auto|off|on` (default `auto`; emit nearby source lines on failure when DAK can resolve them)
- `--source-context-lines N` (default `2`; number of lines before/after the hit)
- `--verbose true` (show stage logs and per-form progress in `--all` mode)

Build with integrated DFM validation:

```bash
"$DAK_EXE" build --project "<path-to-project.dproj>" --delphi 23.0 --platform Win32 --config Release --dfmcheck
```

`--dfmcheck` is a presence flag. If present, DFM validation runs after successful build.
For broader build workflow and options, use `delphi-build` skill.

Defaults:

- `config=Release`
- `platform=Win32`

## Success/Failure Contract

- Non-verbose output is concise: `FAIL` lines + summary + final result.
- Verbose output includes stage markers and full validator output.
- In `--all --verbose`, validator prints progress lines as `CHECK <current>/<total> <resource>`.
- When source context is enabled, handler/declaration failures append a bounded nearby snippet after the existing clue lines.
- Exit code `0`: all streamable DFM resources are valid.
- Exit code `>0`: one or more DFM streams failed; this blocks completion.
- In `--all`, unchanged forms may be skipped via `<Project>.dfmcheck.cache` in the `.dproj` directory.
- Validator timeout is disabled; long runs continue until completion.

## Remediation Rules (required)

When validation reports `FAIL`, we must fix DFM-related issues and re-run validation until exit code is `0`.

Typical fixes:

1. Remove or correct stale properties in `.dfm` that no longer exist in the class.
2. Restore missing published properties/components expected by the `.dfm`.
3. Align renamed controls/components between `.pas` and `.dfm`.
4. Re-run `dfm-check` (or `build --dfmcheck`) after each fix batch.

Task completion gate:

- Do not finish form-related tasks while DFM validation is failing.
