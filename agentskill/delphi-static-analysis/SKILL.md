---
name: delphi-static-analysis
description: Run Delphi static analysis through DelphiAIKit wrappers with FixInsight and Pascal Analyzer enabled by default, then triage and apply safe verified fixes.
license: internal
compatibility: "Requires Windows/WSL, DelphiAIKit.exe, FixInsightCL, PALCMD; commercial tool licenses may apply"
metadata:
  tags: [delphi, static-analysis]
  version: "1.5"
disable-model-invocation: true
allowed-tools:
  - read
  - rg
  - shell
---

# Delphi Static Analysis (DAK + FixInsight + PAL)

## Intent

Use this skill when we need repeatable static analysis on Delphi code with deterministic output under `_analysis/`, followed by conservative fixes and build/test verification.

Default policy:
- Project analysis: `FixInsight=true`, `PascalAnalyzer=true`.
- Unit analysis: `FixInsight=false`, `PascalAnalyzer=true`.
- PAL is a first-class analyzer and should be disabled only explicitly.

## Run Commands

WSL (primary):
- Project doctor: `./agentskill/delphi-static-analysis/doctor.sh /mnt/c/path/to/MyProject.dproj`
- Project analyze: `./agentskill/delphi-static-analysis/analyze.sh /mnt/c/path/to/MyProject.dproj`
- Unit analyze: `./agentskill/delphi-static-analysis/analyze-unit.sh /mnt/c/path/to/Unit1.pas`

Windows:
- Project doctor: `agentskill\\delphi-static-analysis\\doctor.bat C:\\path\\to\\MyProject.dproj`
- Project analyze: `agentskill\\delphi-static-analysis\\analyze.bat C:\\path\\to\\MyProject.dproj`
- Unit analyze: `agentskill\\delphi-static-analysis\\analyze-unit.bat C:\\path\\to\\Unit1.pas`

## Environment Contract

Recommended baseline:
- `DAK_EXE`: absolute path to `DelphiAIKit.exe`.

Analyzer toggles:
- `DAK_PASCAL_ANALYZER`: default `true` (project and unit wrappers). Set `false` only when PAL must be skipped.
- `DAK_FIXINSIGHT`: default `true` for project wrapper.

Common overrides:
- `DAK_DELPHI`, `DAK_PLATFORM`, `DAK_CONFIG`
- `DAK_OUT`
- `DAK_RSVARS`, `DAK_ENVOPTIONS`
- `DAK_FI_FORMATS` (`txt|csv|xml|all`, default `txt`)
- `DAK_EXCLUDE_PATH_MASKS`, `DAK_IGNORE_WARNING_IDS`
- `PA_PATH`, `PA_ARGS`
- `FI_SETTINGS` or `FIXINSIGHT_SETTINGS`

Examples:
- Disable PAL for one run: `DAK_PASCAL_ANALYZER=false ./agentskill/delphi-static-analysis/analyze.sh /mnt/c/path/to/MyProject.dproj`
- PAL only (project): `DAK_FIXINSIGHT=false ./agentskill/delphi-static-analysis/analyze.sh /mnt/c/path/to/MyProject.dproj`

## Execution Model

Wrappers call DAK only:
- `DelphiAIKit.exe analyze --project ...`
- `DelphiAIKit.exe analyze --unit ...`

We do not call `FixInsightCL` or `PALCMD` directly in normal workflow.

Default output root:
- Project: `_analysis/<ProjectName>/`
- Unit: `_analysis/_unit/<UnitName>/`

Primary artifacts:
- `summary.md`
- `triage.md`
- `run.log`
- `delta.md`, `baseline.json` (after first baseline run)

## Agent Workflow

1. Run `doctor` first for tool/path sanity.
2. Run `analyze` (project) or `analyze-unit` (single unit).
3. Read `summary.md`, then `triage.md`.
4. Apply only low-risk fixes in small batches.
5. Verify with DAK build:
   - WSL: `./build-delphi.sh <project.dproj> -config Debug -platform Win32 -ver 23 -ai`
   - Windows: `build-delphi.bat <project.dproj> -config Debug -platform Win32 -ver 23 -ai`
6. Re-run analysis and confirm no regression in `delta.md` / gate output.

## Safe Fix Rules

Allowed without extra design review:
- remove unused locals
- remove dead no-op statements
- narrow local-scope cleanups that do not alter public/protected API signatures

Require explicit review before change:
- signature changes (`const/var/out`, visibility, overloads)
- lifecycle/exception-flow rewrites
- large refactors driven only by metrics warnings

## Troubleshooting

- PAL not found: set `PA_PATH` or configure `[PascalAnalyzer].Path` in `dak.ini`.
- FixInsight not found: configure `[FixInsight].Path` in `dak.ini` or install/discoverable path.
- WSL path issues: pass Linux paths to shell scripts; wrappers convert with `wslpath`.
- `cmd.exe` quoting issues: prefer wrapper scripts over manual `cmd.exe` command construction.

## Local References

- Setup and environment: `agentskill/delphi-static-analysis/SETUP.md`
- Tooling notes: `agentskill/delphi-static-analysis/references/tooling.md`
- Triage heuristics: `agentskill/delphi-static-analysis/references/triage.md`
