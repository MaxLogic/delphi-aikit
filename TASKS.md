# Tasks
Next task ID: T-046


## Summary
Open tasks: 8 (In Progress: 0, Next Today: 4, Next This Week: 4, Next Later: 0, Blocked: 0)
Done tasks: 36


## In Progress

## Next - Today

### T-043 [CLI] Capture run context in baselines and fix delta wording
Outcome: Extend baseline/delta artifacts to include the run context (platform/config/delphi, tool versions when available) and rename misleading labels (e.g. “New W-codes” -> “New W-findings”).
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/baseline.json` includes a `run_context` section (platform/config/delphi at minimum).
- Expect: `_analysis/DelphiAIKit/delta.md` uses “New W-findings”.
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-042 [CLI] Add Git changed-file scope triage
Outcome: Add a `DAK_SCOPE=changed` mode that emits `_analysis/<project>/triage-changed.md` filtered to Git-changed files (and degrades gracefully when Git is unavailable).
Proof:
- Command: DAK_SCOPE=changed python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/triage-changed.md` exists (and when the repo is clean, indicates no changed files).
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-041 [CLI] Normalize finding paths for stable deltas
Outcome: Normalize FixInsight and Pascal Analyzer findings to stable, repo-relative paths (slashes/case/relativization) so baselines and deltas are resilient across machines and working directories.
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/fixinsight/fi-findings.jsonl` contains a normalized `path` field and does not contain `..\\` segments.
- Expect: Running the command twice does not introduce spurious “new” findings in `_analysis/DelphiAIKit/delta.md`.
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-040 [CLI] Emit prioritized triage.md from analysis outputs
Outcome: Generate `_analysis/<project>/triage.md` with a prioritized, fix-oriented shortlist (top 20 by default), grouped by file where possible and referencing line numbers.
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/triage.md` exists and includes sections for FixInsight and Pascal Analyzer.
Touches: agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/SKILL.md, agentskill/delphi-static-analysis/references/triage.md

## Next - This Week

### T-039 Remove PAL bad typecast warning in maxConsoleRunner ExitCode
Outcome: Update exit-code retrieval to avoid PAL "Possible bad typecast" for `fExitCode` while keeping the public `ExitCode: Integer` unchanged.
Proof:
- Command: DAK_PASCAL_ANALYZER=true ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: pal-findings no longer reports "Possible bad typecast" for `lib/MaxLogicFoundation/maxConsoleRunner.pas` exit-code handling.
Touches: lib/MaxLogicFoundation/maxConsoleRunner.pas

### T-038 Refactor TAsyncLoop.Run to avoid PAL bad pointer usage warning
Outcome: Update `TAsyncLoop.Run` to avoid capturing a local loop instance inside anonymous methods while preserving behavior and keeping public API signatures unchanged.
Proof:
- Command: DAK_PASCAL_ANALYZER=true ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: pal-findings no longer reports "Possible bad pointer usage" for `maxAsync.pas:1267`.
Touches: lib/MaxLogicFoundation/maxAsync.pas
Notes: Keep the change internal to the unit; do not change any public/protected signatures.

### T-037 Use safe JSON array cast in Pascal Analyzer runner
Outcome: Replace the hard cast in `TryGetJsonArray` with a safe cast after the `is TJSONArray` guard to clear the PAL strong warning without changing behavior.
Proof:
- Command: DAK_PASCAL_ANALYZER=true ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: pal-findings no longer reports "Possible bad typecast" for `dak.pascalanalyzerrunner.pas:169`.
Touches: src/dak.pascalanalyzerrunner.pas

### T-036 Fix GetExitCodeProcess out param cast in maxConsoleRunner
Outcome: Use a local `DWORD` for `GetExitCodeProcess` and then assign to `fExitCode` to avoid the unsafe typecast and keep the public `ExitCode: Integer` unchanged.
Proof:
- Command: DAK_PASCAL_ANALYZER=true ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: pal-findings no longer reports "Possible bad typecast" for `maxConsoleRunner.pas:334`.
Touches: lib/MaxLogicFoundation/maxConsoleRunner.pas

## Next - Later

## Blocked

## Done

### T-044 [CLI] Make static-analysis wrappers Python 3.9+ compatible
Outcome: Update the Python wrappers under `agentskill/delphi-static-analysis/` to run on Python 3.9+ (avoid `X | Y` union syntax) while preserving behavior.
Proof:
- Command: python3 -m py_compile agentskill/delphi-static-analysis/analyze.py agentskill/delphi-static-analysis/analyze-unit.py agentskill/delphi-static-analysis/postprocess.py agentskill/delphi-static-analysis/doctor.py
- Expect: Exit code 0.
Touches: agentskill/delphi-static-analysis/analyze.py, agentskill/delphi-static-analysis/analyze-unit.py, agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/doctor.py

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
