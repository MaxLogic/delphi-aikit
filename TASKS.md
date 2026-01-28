# Tasks

## In Progress

## Next - Today

## Next - This Week

### T-022 [DOC] Specify PAL XML parsing + normalized findings format
Outcome: Add a focused spec slice that documents which Pascal Analyzer XML reports are actionable vs. inventory/metrics, and define a stable normalized output format for an AI-friendly `pal-findings.md` (and optional hotspots) derived from our real PAL XML outputs.
Proof:
- Command: ls docs/spec-slices/pascal-analyzer-xml-findings.md
- Expect: file exists and documents extraction rules for at least Warnings.xml / Strong Warnings.xml / Optimization.xml (including the observed XML patterns: <section>, <item>, <loc>, <locmod>, <locline>), plus a concrete `pal-findings.md` line format.
Touches: docs/spec-slices/, _analysis/DelphiConfigResolver/pascal-analyzer/DelphiConfigResolver/
Notes: Review the actual PAL XML files under `_analysis/DelphiConfigResolver/pascal-analyzer/DelphiConfigResolver/` and confirm semantics via Peganza docs found via docker MCP web search (PAL manual PDF + PALHelp pages).

### T-023 [CLI] Generate pal-findings.md from PALCMD XML output
Outcome: After a project-level Pascal Analyzer run (`--run-pascal-analyzer`), DelphiConfigResolver generates an AI-friendly `pal-findings.md` alongside the raw PAL output folder, containing only finding-like items (warnings/strong warnings/optimization/exceptions) in a stable one-line-per-finding format; keep the full PAL XML folder as an artifact.
Proof:
- Command: ./agentskill/delphi-static-analysis/analyze.sh projects/DelphiConfigResolver.dproj
- Expect: _analysis/DelphiConfigResolver/pascal-analyzer/pal-findings.md exists and contains normalized entries referencing modules and line numbers (e.g., `Dcr.*:<line>`).
Touches: src/Dcr.PascalAnalyzerRunner.pas
Deps: T-022
Notes: Start by parsing Warnings.xml / Strong Warnings.xml / Optimization.xml (and Exception.xml if non-empty). Avoid reading/serializing the full 52-report set by default.

### T-024 [TEST] Add fixture-based tests for PAL findings normalization
Outcome: Add DUnitX tests that validate PAL XML parsing and `pal-findings.md` normalization against checked-in sample PAL XML fixtures, so parsing stays stable without requiring PALCMD in CI.
Proof:
- Command: ./build-and-run-tests.sh
- Expect: DUnitX tests for PAL findings normalization pass (and are skipped only when fixtures are missing, not when PALCMD is missing).
Touches: tests/, docs/sample-pal-reports/
Deps: T-022
Notes: Use trimmed copies of real PAL XML files from `_analysis/DelphiConfigResolver/pascal-analyzer/DelphiConfigResolver/` as fixtures (remove unrelated sections but keep structure).

## Next - Later

### T-025 [CLI] Generate pal-hotspots.md from PAL metrics reports
Outcome: Produce an optional `pal-hotspots.md` derived from PAL metrics reports (Complexity.xml + Module Totals.xml), listing top hotspots (e.g., top 20 routines/modules by complexity/LOC) without dumping full XML.
Proof:
- Command: ./agentskill/delphi-static-analysis/analyze.sh projects/DelphiConfigResolver.dproj
- Expect: _analysis/DelphiConfigResolver/pascal-analyzer/pal-hotspots.md exists and contains only the top-N items (no raw XML dumps).
Touches: src/Dcr.PascalAnalyzerRunner.pas
Deps: T-022
Notes: Keep this strictly “refactor territory” output so it doesn’t distract from warnings; prefer stable ordering + top-N caps for token safety.

### T-026 [CLI] Emit pal-findings.jsonl (machine-readable)
Outcome: Optionally emit `pal-findings.jsonl` (one JSON object per finding) alongside `pal-findings.md` to support tooling (filtering/dedup/trends) while keeping Markdown as the primary agent surface.
Proof:
- Command: ./agentskill/delphi-static-analysis/analyze.sh projects/DelphiConfigResolver.dproj
- Expect: _analysis/DelphiConfigResolver/pascal-analyzer/pal-findings.jsonl exists; each line is valid JSON and includes at least severity, report, section, module, line, message/id.
Touches: src/Dcr.PascalAnalyzerRunner.pas
Deps: T-022, T-023
Notes: Keep JSON schema minimal and stable; do not embed full XML nodes.

## Blocked

## Done

### T-018 [TEST] Add DUnitX test project scaffold
Summary: Created a DUnitX test project under `tests/` with temp cleanup at run start and shared helpers for building and running the resolver.

### T-019 [TEST] Add FixInsight integration tests in DUnitX
Summary: Added DUnitX FixInsight runs that validate txt/xml/csv outputs and exercise path-mask and warning-ID filtering.

### T-020 [TEST] Add Pascal Analyzer integration tests in DUnitX
Summary: Added DUnitX Pascal Analyzer runs that store outputs under `tests/temp/` and skip when PALCMD is unavailable.

### T-021 [TEST] Revisit run.bat reliability
Summary: Made run.bat build the resolver when missing and documented DUnitX/run scripts in tests README.

### T-012 [CLI] Extend settings.ini schema for ignore/filter/Pascal Analyzer
Summary: Extended `settings.ini` schema with `[FixInsightIgnore]`, `[ReportFilter]`, and `[PascalAnalyzer]` and added corresponding CLI overrides.

### T-013 [FixInsight] Add ignored-warnings defaults
Summary: Added `--ignore-warning-ids` and `[FixInsightIgnore].Warnings` and suppress matching rule IDs via report post-processing (keep `--ignore` for paths).

### T-014 [CLI] Filter analyzer reports by ExcludePathMasks
Summary: Added deterministic report filtering for FixInsight outputs (text/xml/csv) via `[ReportFilter].ExcludePathMasks` / `--exclude-path-masks`.

### T-015 [CLI] Run Pascal Analyzer (palcmd.exe) with resolved project config
Summary: Added `--run-pascal-analyzer` runner with PALCMD discovery (`palcmd.exe`/`palcmd32.exe`), Delphi target mapping, and sensible defaults.

### T-016 [DOC] Update README for ignore/filter + Pascal Analyzer features
Summary: Documented new settings.ini sections and CLI flags for report filtering and Pascal Analyzer, including examples.

### T-017 [DOC] Capture sample FixInsight self reports (txt/xml/csv) for filtering
Summary: Added sample FixInsight self reports under `docs\\sample-fix-insight-self-reports\\` and updated `fixinsight-run.bat` to regenerate them.

### T-001 Implement DelphiConfigResolver console app
Summary: Build the CLI tool that resolves FixInsight params from .dproj/.optset and IDE config.

### T-002 Refine FixInsight bat output and CLI defaults
Summary: Make the generated FixInsight bat multi-line and default platform/config when omitted.

### T-003 Resolve FixInsightCL.exe path for bat output
Summary: Detect FixInsightCL.exe via PATH or HKCU registry when generating the batch file.

### T-004 Add FixInsightCL pass-through options
Summary: Support settings.ini defaults and CLI overrides for extra FixInsightCL arguments in bat output.

### T-005 Improve FixInsightCL discovery and macro defaults
Summary: Resolve FixInsightCL.exe across registry views and fill missing IDE macro defaults to reduce unresolved paths.

### T-006 Detect FixInsight registry key used by TMS installer
Summary: Include HKCU/HKLM Software\TMSSoftware\TMS FixInsight Pro when resolving FixInsightCL.exe.

### T-007 Add settings.ini fallback for FixInsightCL.exe
Summary: Read FixInsightCL.exe path from settings.ini when registry/PATH lookup fails.

### T-008 Fix bat encoding and long argument formatting
Summary: Write UTF-8 bat without BOM, set codepage, and split long path lists into variables.

### T-009 Add direct FixInsightCL execution
Summary: Add --run to execute FixInsightCL via CreateProcess to avoid cmd.exe limits.

### T-010 Add resolver logfile support
Summary: Write resolver diagnostics to a separate log file via --logfile.

### T-011 Add log tee option for resolver diagnostics
Summary: Allow resolver diagnostics to be mirrored to output when --logfile is used.
