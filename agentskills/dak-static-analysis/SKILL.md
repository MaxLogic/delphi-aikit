---
name: dak-static-analysis
description: Run Delphi static analysis through DelphiAIKit wrappers with FixInsight and Pascal Analyzer enabled by default, then triage and apply safe verified fixes.
license: internal
metadata:
  tags: [delphi, static-analysis]
allowed-tools:
  - read
  - rg
  - shell
---

# Delphi Static Analysis (DAK + FixInsight + PAL)

## Intent

Use this skill when we need repeatable static analysis on Delphi code, followed by conservative fixes and build/test verification.

Default policy:
- Project analysis: `FixInsight=true`, `PascalAnalyzer=true`.
- Unit analysis: `FixInsight=false`, `PascalAnalyzer=true`.
- PAL is a first-class analyzer and should be disabled only explicitly.

## Run Commands

WSL (primary):
- Project doctor: `./agentskills/dak-static-analysis/doctor.sh /mnt/c/path/to/MyProject.dproj`
- Project analyze: `./agentskills/dak-static-analysis/analyze.sh /mnt/c/path/to/MyProject.dproj`
- Unit analyze: `./agentskills/dak-static-analysis/analyze-unit.sh /mnt/c/path/to/Unit1.pas`

Windows:
- Project doctor: `agentskills\\dak-static-analysis\\doctor.bat C:\\path\\to\\MyProject.dproj`
- Project analyze: `agentskills\\dak-static-analysis\\analyze.bat C:\\path\\to\\MyProject.dproj`
- Unit analyze: `agentskills\\dak-static-analysis\\analyze-unit.bat C:\\path\\to\\Unit1.pas`

## Environment Contract

Recommended baseline:
- `DAK_EXE`: absolute path to `DelphiAIKit.exe`.
- If `DAK_EXE` is unset, wrappers fall back to Windows `PATH` (`where DelphiAIKit.exe`), then repo-local `bin/DelphiAIKit.exe`.

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
- Disable PAL for one run: `DAK_PASCAL_ANALYZER=false ./agentskills/dak-static-analysis/analyze.sh /mnt/c/path/to/MyProject.dproj`
- PAL only (project): `DAK_FIXINSIGHT=false ./agentskills/dak-static-analysis/analyze.sh /mnt/c/path/to/MyProject.dproj`

## Execution Model

Wrappers call DAK only:
- `DelphiAIKit.exe analyze --project ...`
- `DelphiAIKit.exe analyze --unit ...`

Path note:
- Direct DAK calls accept Linux-style absolute paths only in `/mnt/<drive>/...` form for `--project` and `--unit` when run from WSL.
- Other Linux absolute paths (for example `/home/...`) are rejected with a clear error.
- Wrapper scripts with `wslpath` conversion remain the canonical safe route.

We do not call `FixInsightCL` or `PALCMD` directly in normal workflow.

Wrapper defaults are project-local:
- Project: `.dak/<ProjectName>/`
- Unit: `.dak/_unit/<UnitName>/`

Agent-run policy:
- Never set `DAK_OUT` to `.agents/`; analyzer output is generated tool state, not memory.
- For a large or disposable run, set `DAK_OUT` to a unique directory under the OS temp root. Include the repository/project and run identity so concurrent runs cannot collide.
- Use project-local `.dak/` only when the reports or caches should survive for reuse in that checkout.
- At the end of a task or goal, retain the small evidence reports we actually need and remove verified disposable output trees.

PowerShell example:

```powershell
$env:DAK_OUT = Join-Path $env:TEMP ("dak\\MyProject\\analysis-{0}" -f $PID)
```

WSL example:

```bash
export DAK_OUT="${TMPDIR:-/tmp}/dak/MyProject/analysis-$$"
```

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
   - WSL/Windows: `"$DAK_EXE" build --project "<project.dproj>" --delphi 23.0 --platform "<platform>" --config Debug --ai`
   - For DelphiAiKit itself, use `--platform Win64`.
6. Re-run analysis and confirm no regression in `delta.md` / gate output.
7. Preserve only the summary, triage, baseline, or delta needed for the task record; clean disposable analyzer trees after the evidence is recorded.

After a coherent batch of Delphi source edits, run the shared `encodingfix-delphi-cleanup` source-hygiene check once before the final task gate. Do not duplicate it if another DAK workflow already ran the same check over the same files. Ordinary analysis must not silently rewrite source files.

## Report-Driven Fix Loop

1. Start with `<DAK_OUT>/summary.md` and `<DAK_OUT>/triage.md` (or the wrapper's project-local default when `DAK_OUT` is unset).
2. If triage is too broad, re-run with path/rule filters:
   - `DAK_EXCLUDE_PATH_MASKS="*\\3rdParty\\*;*\\lib\\*"`
   - `DAK_IGNORE_WARNING_IDS="W502;O801"`
3. If triage lacks detail, open:
   - `fixinsight/fi-findings.md`
   - `pascal-analyzer/pal-findings.md`
4. For PAL prioritization, fix in this order:
   - strong warnings
   - exception/warning findings
   - optimization findings
5. Use `delta.md` to confirm net reduction and no regression after each batch.

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
- FixInsight not found: configure `[FixInsightCL].Path` in `dak.ini` or install/discoverable path.
- WSL path issues: pass Linux paths to shell scripts; wrappers convert with `wslpath`.
- `cmd.exe` quoting issues: prefer wrapper scripts over manual `cmd.exe` command construction.

## Local References

- Setup and environment: `agentskills/dak-static-analysis/SETUP.md`
- Tooling notes: `agentskills/dak-static-analysis/references/tooling.md`
- Triage heuristics: `agentskills/dak-static-analysis/references/triage.md`
