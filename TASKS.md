# Tasks

## In Progress

## Next - Today

## Next - This Week

## Next - Later

## Blocked

## Done

### T-035 [FixInsight] Address W510 in NormalizePath
Outcome: Update `NormalizePath` to avoid the "values on both sides of the operator are equal" warning while keeping output identical.
Proof:
- Command: ./build-delphi.sh projects/DelphiAIKit.dproj
- Expect: Build succeeds.
- Command: ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: FixInsight report no longer lists W510 for `lib/MaxLogicFoundation/MaxLogic.ioUtils.pas`.
Touches: lib/MaxLogicFoundation/MaxLogic.ioUtils.pas

### T-034 [FixInsight] Remove unused loop variable in OccurrencesOfChar
Outcome: Rewrite the loop in `OccurrencesOfChar` to avoid the unused `i` variable while keeping the same semantics and performance.
Proof:
- Command: ./build-delphi.sh projects/DelphiAIKit.dproj
- Expect: Build succeeds.
- Command: ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: FixInsight report no longer lists W528 for `lib/MaxLogicFoundation/MaxLogic.StrUtils.pas`.
Touches: lib/MaxLogicFoundation/MaxLogic.StrUtils.pas

### T-033 [FixInsight] Avoid empty FINALLY in TFastCaseAwareComparer.Equals
Outcome: Adjust the `try..finally` in `TFastCaseAwareComparer.Equals` so the FINALLY section is non-empty under current compile defines, preserving behavior while clearing W502.
Proof:
- Command: ./build-delphi.sh projects/DelphiAIKit.dproj
- Expect: Build succeeds.
- Command: ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: FixInsight report no longer lists W502 for `lib/MaxLogicFoundation/MaxLogic.StrUtils.pas`.
Touches: lib/MaxLogicFoundation/MaxLogic.StrUtils.pas

### T-032 [FixInsight] Handle missing enum cases in ReplacePlaceholder
Outcome: Add explicit handling for `raReplace` and `raReplaceAndStop` in the `ReplacePlaceholder` case on `lAction` to clear W535 without changing behavior.
Proof:
- Command: ./build-delphi.sh projects/DelphiAIKit.dproj
- Expect: Build succeeds.
- Command: ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: FixInsight report no longer lists W535 for `lib/MaxLogicFoundation/MaxLogic.StrUtils.pas`.
Touches: lib/MaxLogicFoundation/MaxLogic.StrUtils.pas

### T-030 [CLI] Refactor long CLI/analyze routines to reduce FixInsight complexity warnings
Outcome: Extract helper routines from `TryParseOptions` in `src/dak.cli.pas` plus `RunAnalyzeProject`/`RunAnalyzeUnit` in `src/dak.analyze.pas` to reduce C101/C103 without changing any public API signatures.
Proof:
- Command: ./build-delphi.sh projects/DelphiAIKit.dproj
- Expect: Build succeeds.
- Command: ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: FixInsight report no longer flags C101/C103 for `TryParseOptions` in `src/dak.cli.pas` and `RunAnalyzeProject`/`RunAnalyzeUnit` in `src/dak.analyze.pas`.
Touches: src/dak.cli.pas, src/dak.analyze.pas
Notes: Keep helper routines non-local (unit/private methods) to avoid nested routine rule in conventions.

### T-031 [CLI] Remove unused ResourceStrings in dak.messages
Outcome: Remove or repurpose unused ResourceStrings in `src/dak.messages.pas` so FixInsight O802 is cleared for that unit.
Proof:
- Command: ./build-delphi.sh projects/DelphiAIKit.dproj
- Expect: Build succeeds.
- Command: ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: FixInsight report no longer lists O802 unused ResourceStrings in `src/dak.messages.pas`.
Touches: src/dak.messages.pas

### T-027 [CLI] Add analyze command (project/unit)
Summary: Added analyze subcommand parsing, options, and help output for project/unit analysis.

### T-028 [CLI] Implement analysis orchestration + output tree in DAK
Summary: Added DAK analysis runner that writes _analysis outputs, run logs, and summaries while invoking FixInsight and PAL.

### T-029 [DOC] Make static-analysis scripts thin wrappers
Summary: Simplified static-analysis scripts to call DAK analyze subcommands and updated skill docs.

### T-022 [DOC] Specify PAL XML parsing + normalized findings format
Summary: Added a spec slice documenting PAL XML findings extraction patterns and normalized pal-findings/pal-hotspots formats.

### T-023 [CLI] Generate pal-findings.md from PALCMD XML output
Summary: Generate pal-findings.md after PAL runs, parsing warning/optimization/exception XML into normalized lines.

### T-024 [TEST] Add fixture-based tests for PAL findings normalization
Summary: Added PAL XML fixtures and DUnitX tests that validate pal-findings normalization without PALCMD.

### T-025 [CLI] Generate pal-hotspots.md from PAL metrics reports
Summary: Added pal-hotspots.md generation from Complexity.xml and Module Totals.xml with top-N caps.

### T-026 [CLI] Emit pal-findings.jsonl (machine-readable)
Summary: Added pal-findings.jsonl alongside pal-findings.md with stable JSONL records.

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
Summary: Added `--ignore-warning-ids` and `[FixInsightIgnore].Warnings` and suppress matching rule IDs via report post-processing (keep `--fi-ignore` for paths).

### T-014 [CLI] Filter analyzer reports by ExcludePathMasks
Summary: Added deterministic report filtering for FixInsight outputs (text/xml/csv) via `[ReportFilter].ExcludePathMasks` / `--exclude-path-masks`.

### T-015 [CLI] Run Pascal Analyzer (palcmd.exe) with resolved project config
Summary: Added `analyze --pascal-analyzer true` runner with PALCMD discovery (`palcmd.exe`/`palcmd32.exe`), Delphi target mapping, and sensible defaults.

### T-016 [DOC] Update README for ignore/filter + Pascal Analyzer features
Summary: Documented new settings.ini sections and CLI flags for report filtering and Pascal Analyzer, including examples.

### T-017 [DOC] Capture sample FixInsight self reports (txt/xml/csv) for filtering
Summary: Added sample FixInsight self reports under `docs\\sample-fix-insight-self-reports\\` and updated `fixinsight-run.bat` to regenerate them.

### T-001 Implement DelphiAIKit console app
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
Summary: Add `analyze --fixinsight true` to execute FixInsightCL via CreateProcess to avoid cmd.exe limits.

### T-010 Add resolver logfile support
Summary: Write resolver diagnostics to a separate log file via --log-file.

### T-011 Add log tee option for resolver diagnostics
Summary: Allow resolver diagnostics to be mirrored to output when --log-file is used.
