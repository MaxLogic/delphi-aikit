# Tasks
Next task ID: T-088

## Summary
Open tasks: 0 (In Progress: 0, Next Today: 0, Next This Week: 0, Next Later: 0, Blocked: 0)
Done tasks: 87

## In Progress

## Next - Today

## Next - This Week

## Next - Later

## Blocked

## Done

### T-087 [CLI] Warn on invalid `[Diagnostics]` dak.ini values
Outcome:
- Invalid `[Diagnostics]` values in `dak.ini` no longer fail silently in `build` and `dfm-check`; they are surfaced as warnings while DAK still falls back to safe defaults.
- `build` emits warnings when `SourceContext` or `SourceContextLines` are invalid in layered `dak.ini` settings.
- `dfm-check` emits structured warning lines for the same invalid diagnostics settings instead of silently ignoring them.
Proof:
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Build.TBuildTests.BuildWarnsOnInvalidDiagnosticsIniValues,Test.DfmCheck.TDfmCheckTests.DfmCheckWarnsOnInvalidDiagnosticsIniValues -cm:Quiet`
  Expect: Tests Found `2`, Failed `0`, Leaked `0`.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -cm:Quiet`
  Expect: Exit code `0`.
- Run: `timeout 1800 ./tests/run.sh`
  Expect: Exit code `0`.
Touches: src/dak.build.pas, src/dak.dfmcheck.pas, src/dak.diagnostics.pas, tests/units/test.build.pas, tests/units/test.dfmcheck.pas
Verify: unit-test, cli-proof
Notes: Follow-up from the T-082 review. Keep invalid diagnostics config as a warning-only condition with fallback defaults rather than turning it into a hard failure.

### T-083 [DOC] Refresh repo-local agent skills for current DAK capabilities
Outcome:
- Audit the repo-local skills under `agentskills/` against the current `DelphiAIKit.exe` command surface so no skill keeps stale command names, flags, output locations, or workflow assumptions.
- Update the existing skill docs, setup notes, and helper scripts for the DAK capabilities we actively use from agents, including build, `dfm-check`, static analysis, and `global-vars`, with current examples and current repo conventions such as sibling `.dak/<ProjectName>/` working directories.
- Fold `dfm-inspect` guidance from `T-081` into the existing DFM-oriented skill instead of creating a separate narrow skill, unless the inspection surface later grows beyond simple form inspection workflows.
- Add or split skill coverage when a shipped DAK capability that agents should invoke directly is currently undocumented in `agentskills/`, instead of leaving that knowledge implicit.
Proof:
- Run: `./bin/DelphiAIKit.exe --help`
  Expect: Exit code `0` and output lists the top-level commands referenced by the updated skill set.
- Run: `rg -n "DelphiAIKit\\.exe (build|dfm-check|global-vars|analyze)|\\.dak/<ProjectName>|--dfmcheck|--test-output-dir|--refresh|dfm-inspect|source-context" agentskills`
  Expect: Updated skill files reference the canonical current DAK commands, key flags, `dfm-inspect`, source-context options, and project-scoped `.dak` convention where relevant.
- Run: `rg -n "build-delphi\\.bat|_analysis/<project>|\\.dproj directory" agentskills`
  Expect: No stale skill guidance remains for superseded build flow or outdated project-output locations unless a file explicitly labels it as legacy compatibility behavior.
Touches: agentskills/delphi-build/, agentskills/delphi-dfm-check/, agentskills/delphi-global-vars/, agentskills/delphi-static-analysis/, AGENTS.md, README.md
Deps: T-079, T-081, T-082
Verify: cli-proof, manual
Notes: Keep repo-local skills aligned with what DAK actually ships now. If `dfm-inspect` from `T-081` lands during the same batch, either extend the relevant DFM skill in the same change or record a focused follow-up task instead of burying it here.
Prefer extending `agentskills/delphi-dfm-check/SKILL.md` into an inspect-and-validate form workflow so `dfm-inspect` and `dfm-check` stay documented together. Only split out a dedicated inspection skill if `dfm-inspect` later gains a materially broader surface than `tree`/`summary` style form inspection.

### T-082 [CLI] Add shared source-context snippets for resolved failures
Outcome:
- Add a reusable helper that resolves diagnostic file references against the analyzed project and returns a bounded source snippet around a target line.
- Use that helper in failure paths where DAK already knows a file and line, including build-related findings and `dfm-check` clues, so actionable output includes nearby source when it can be resolved safely.
- Keep snippet emission bounded and configurable so normal output stays concise while `--verbose` and explicit overrides can expand the context window.
Proof:
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.SourceContext.TSourceContextTests -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`, including absolute-path, project-relative, search-path, and missing-file cases.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Build.TBuildTests.BuildSummaryIncludesResolvedSourceContextForErrors -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.DfmCheck.TDfmCheckTests.DfmCheckFailureIncludesResolvedSourceContextWhenPascalLocationIsKnown -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -cm:Quiet`
  Expect: Exit code `0`.
Touches: src/dak.build.pas, src/dak.dfmcheck.pas, src/dak.messages.pas, src/dak.msbuild.pas, src/dak.project.pas, src/dak.types.pas, tests/units/, README.md, spec.md
Verify: unit-test, cli-proof
Notes: Reimplement the `read_source_context` and `resolve_error_file` ideas from `claude-pascal-mcp` on top of DAK's evaluated project model rather than a shallow `.dproj` scan. Start with text output; JSON shaping can stay a follow-up if needed.

### T-079 [CLI] Canonicalize project-scoped tool state under sibling .dak folders
Outcome: Review DelphiAIKit commands and shared path utilities, then move project-related caches, temp files, generated reports, and similar working artifacts to the canonical sibling `.dak/<dproj-base-name>/` directory next to the analyzed `.dproj` so multiple projects in one folder remain isolated and project state stops leaking into ad hoc locations.
Proof:
- Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Expect: Exit code `0`, including coverage for `.dak/<project-name>/` path resolution, same-directory multi-`.dproj` isolation, and updated command-specific work-directory behavior.
- Command: timeout 1800 ./tests/run.sh
- Expect: Exit code `0`.
- Command: ./bin/DelphiAIKit.exe analyze --project /mnt/f/projects/OEC/TE5/maxTdb/src/maxtdb.dproj --platform Win32 --config Debug --delphi 23.0 --fixinsight false --pascal-analyzer false
- Expect: Project-scoped scratch and report state is created under `/mnt/f/projects/OEC/TE5/maxTdb/src/.dak/maxtdb/` instead of an ad hoc repo-root or machine-temp location.
Touches: src/, tests/units/, AGENTS.md, TASKS.md, README.md
Notes: Apply this directory convention across all DelphiAIKit tools, not only the planned global-vars feature. Code review showed `global-vars` already used `.dak`, while `analyze` and the repo-local static-analysis wrappers still defaulted to `_analysis/...`. `T-086` and `T-085` closed those concrete migration gaps, and the broader proof surface has now been re-run and recorded here.

### T-086 [CLI] Move `analyze` default output roots under sibling `.dak` working dirs
Outcome:
- Stop defaulting `analyze --project` outputs to `_analysis/<ProjectName>/` and instead place project-scoped reports, logs, and derived artifacts under the analyzed project's sibling `.dak/<ProjectName>/` working tree.
- Align `analyze --unit` default output behavior with the repo `.dak` convention as well, so unit-mode runs no longer create ad hoc `_analysis/_unit/...` trees when no explicit `--out` is supplied.
- Add regression coverage proving omitted `--out` now resolves through the `.dak` convention while explicit `--out` still wins unchanged.
Proof:
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.AnalyzeProjectDefaultOutRootUsesSiblingDakFolder -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.AnalyzeProjectDefaultOutRootUsesSiblingDprojFolderWhenMainSourceLivesElsewhere -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.AnalyzeUnitDefaultOutRootUsesDakConvention -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `./bin/DelphiAIKit.exe analyze --project tests/fixtures/Sample.dproj --platform Win32 --config Debug --delphi 23.0 --fixinsight false --pascal-analyzer false`
  Expect: When `--out` is omitted, default project-scoped artifacts are created under `tests/fixtures/.dak/Sample/` rather than `_analysis/`.
Touches: src/dak.analyze.pas, src/dak.cli.pas, tests/units/test.cli.pas, README.md, spec.md
Deps: T-079
Verify: unit-test, cli-proof
Notes: This task existed because code review found `BuildOutputRoot`/`BuildUnitOutputRoot` still hardcoded `_analysis/...` defaults in `src/dak.analyze.pas`. The regression coverage now also locks the split-layout case where the analyzed `.dproj` lives above the main `.dpr`.

### T-085 [CLI] Move static-analysis wrapper defaults and docs off `_analysis`
Outcome:
- Update the repo-local static-analysis wrapper scripts and doctor tooling so their computed default output roots follow the `.dak` convention instead of generating `_analysis/...` trees.
- Update the static-analysis skill docs and setup docs so examples, artifact paths, and troubleshooting steps match the post-`T-079` `.dak` layout rather than the legacy `_analysis` layout.
- Keep explicit `DAK_OUT` / `--out` overrides working as-is while removing automatic `_analysis/` insertion and related `.gitignore` assumptions from the wrappers.
Proof:
- Run: `python3 agentskills/delphi-static-analysis/doctor.py /mnt/f/projects/MaxLogic/DelphiAiKit/projects/DelphiAIKit.dproj`
  Expect: Default output root reported by the doctor uses `.dak/` naming rather than `_analysis/`.
- Run: `rg -n "_analysis/|_analysis<|_analysis\\\\|ensure_gitignore_has_analysis_root" agentskills/delphi-static-analysis`
  Expect: No default-path logic or user guidance still hardcodes legacy `_analysis` roots unless a file explicitly labels it as historical context.
- Run: `rg -n "\\.dak/<ProjectName>|\\.dak/" agentskills/delphi-static-analysis`
  Expect: The wrapper docs and scripts reference the canonical `.dak` project-scoped layout.
Touches: agentskills/delphi-static-analysis/, AGENTS.md, README.md, spec.md
Deps: T-079
Verify: cli-proof, manual
Notes: This was the repo-local wrapper half of the remaining `T-079` gap surfaced by code review. `postprocess.py` now skips `.dak` artifact trees as well so report normalization does not recurse into generated outputs.

### T-081 [CLI] Add `dfm-inspect` command for lightweight form structure inspection
Outcome:
- Add a `dfm-inspect` CLI command that reads text DFM files and emits a structured view of the form tree without requiring a build or generated harness.
- Support at least `tree` and `summary` output modes so we can inspect component hierarchy, key visual properties, and event-handler bindings from the command line.
- Reuse the parsed form information to improve future `dfm-check` clueing and related diagnostics instead of reparsing ad hoc.
Proof:
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.DfmInspect.TDfmInspectTests -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `./bin/DelphiAIKit.exe dfm-inspect --dfm tests/fixtures/MainForm.dfm --format tree`
  Expect: Exit code `0` and stdout contains the root form name/class plus at least one child component entry.
- Run: `./bin/DelphiAIKit.exe dfm-inspect --dfm tests/fixtures/MainForm.dfm --format summary`
  Expect: Exit code `0` and stdout contains component counts and at least one discovered event binding when present.
Touches: projects/DelphiAIKit.dpr, src/dak.cli.pas, src/dak.messages.pas, src/dak.types.pas, src/dak.dfmcheck.pas, tests/units/, README.md, spec.md
Verify: unit-test, cli-proof
Notes: Inspired by the MIT-licensed form parser in `claude-pascal-mcp`. Implement on top of DAK conventions and CLI contracts; text-form parsing only, not a replacement for compiled `dfm-check` validation.

### T-084 [CLI] Respect `.mes` enablement before running madExcept patch
Outcome:
- Treat the sibling `.mes` file as structured configuration rather than a presence-only sentinel when deciding whether `madExceptPatch.exe` should run after build.
- Skip the madExcept post-build patch step when the parsed `.mes` settings show madExcept is disabled for the effective project/build context, even if the file exists and the `madExcept` define is present.
- Keep the current guards for missing `.mes`, main-source/project name mismatch, and missing `madExceptPatch.exe`, while adding regression coverage for disabled `HandleExceptions`, disabled `LinkInCode`, and UTF-8-with-BOM `.mes` files.
Proof:
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Build.TBuildTests.BuildSkipsMadExceptPatchWhenMesDisablesMadExcept -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Build.TBuildTests.BuildSkipsMadExceptPatchWhenMesDisablesLinkInCode -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Build.TBuildTests.BuildSkipsMadExceptPatchWhenUtf8BomMesDisablesMadExcept -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Build.TBuildTests.BuildStillRunsMadExceptPatchWhenMesEnablesMadExcept -cm:Quiet`
  Expect: Tests Found `>=1`, Failed `0`, Leaked `0`.
- Run: `timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Build.TBuildTests -cm:Quiet`
  Expect: Build-suite regression tests pass with `Tests Found 8`, `Failed 0`, `Leaked 0`.
Touches: src/dak.build.pas, tests/units/test.build.pas, README.md, spec.md
Deps: T-080
Verify: unit-test, cli-proof
Notes: `.mes` is an INI-style file. Review and parse it instead of assuming that mere file presence means madExcept patching is required.

### T-080 [CLI] Replace batch-backed build pipeline with a native Delphi runner
Outcome: Move `DelphiAIKit.exe build` off `build-delphi.bat` and onto a native Delphi build runner that handles MSBuild execution, timeout, log capture/filtering, JSON/plain/AI output shaping, project-scoped settings, and `madExcept` post-build patching without relying on bundled batch/PowerShell helper logic.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "cd /d F:\\projects\\MaxLogic\\DelphiAiKit && build-delphi.bat projects\\DelphiAIKit.dproj -config Release -platform Win32 -ver 23 -test-output-dir tests\\temp\\resolver-build-out-native"
- Expect: Build exits `0` with `SUCCESS` and writes the current native-runner `DelphiAIKit.exe` to `projects\\tests\\temp\\resolver-build-out-native\\DelphiAIKit.exe`.
- GREEN Command: /mnt/c/Windows/System32/cmd.exe /C "cd /d F:\\projects\\MaxLogic\\DelphiAiKit && build-delphi.bat tests\\DelphiAIKit.Tests.dproj -config Debug -platform Win32 -ver 23 -test-output-dir tests\\temp\\test-bin-native"
- GREEN Expect: Build exits `0` with `SUCCESS`.
- GREEN Command: /mnt/c/Windows/System32/cmd.exe /C "set DAK_TEST_RESOLVER_EXE=F:\\projects\\MaxLogic\\DelphiAiKit\\projects\\tests\\temp\\resolver-build-out-native\\DelphiAIKit.exe && F:\\projects\\MaxLogic\\DelphiAiKit\\tests\\tests\\temp\\test-bin-native\\DelphiAIKit.Tests.exe -r:Test.Build.TBuildTests -cm:Quiet"
- GREEN Expect: Tests Found `8`, Passed `8`, Failed `0`, Leaked `0`.
- GREEN Command: /mnt/c/Windows/System32/cmd.exe /C "set DAK_TEST_RESOLVER_EXE=F:\\projects\\MaxLogic\\DelphiAiKit\\projects\\tests\\temp\\resolver-build-out-native\\DelphiAIKit.exe && F:\\projects\\MaxLogic\\DelphiAiKit\\tests\\tests\\temp\\test-bin-native\\DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests -cm:Quiet"
- GREEN Expect: Tests Found `28`, Passed `28`, Failed `0`, Leaked `0`.
- GREEN Command: /mnt/c/Windows/System32/cmd.exe /C "set DAK_TEST_RESOLVER_EXE=F:\\projects\\MaxLogic\\DelphiAiKit\\projects\\tests\\temp\\resolver-build-out-native\\DelphiAIKit.exe && F:\\projects\\MaxLogic\\DelphiAiKit\\tests\\tests\\temp\\test-bin-native\\DelphiAIKit.Tests.exe -r:Test.MsBuild.TMsBuildTests -cm:Quiet"
- GREEN Expect: Tests Found `6`, Passed `6`, Failed `0`, Leaked `0`.
- GREEN Command: /mnt/c/Windows/System32/cmd.exe /C "set DAK_TEST_RESOLVER_EXE=F:\\projects\\MaxLogic\\DelphiAiKit\\projects\\tests\\temp\\resolver-build-out-native\\DelphiAIKit.exe && F:\\projects\\MaxLogic\\DelphiAiKit\\tests\\tests\\temp\\test-bin-native\\DelphiAIKit.Tests.exe -r:Test.DfmCheck.TDfmCheckTests -cm:Quiet"
- GREEN Expect: Tests Found `19`, Passed `19`, Failed `0`, Leaked `0`.
Touches: projects/DelphiAIKit.dpr, src/, tests/units/, README.md, spec.md, CHANGELOG.md, TASKS.md
Notes: Keep `build-delphi.bat` only as a compatibility shim if external callers still need it; the CLI build engine itself must live in Delphi. Full-suite `DelphiAIKit.Tests.exe -cm:Quiet` still stalls in the pre-existing unrelated `Test.FixInsight.TFixInsightTests` area, so only the change-relevant suites above are green for this task, and they must be run serially because they share `tests/temp`.

### T-078 [CLI] Reject trailing unknown tokens after explicit help command
Outcome: `TryGetCommand` now validates the full positional token stream in help mode after detecting an explicit command, so trailing unknown tokens (for example `--help analyze foo`) are rejected instead of being silently ignored.
Proof:
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandRejectsTrailingUnknownTokenAfterExplicitCommand -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` with `Expected trailing unknown token to be rejected in help command mode.`
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandRejectsTrailingUnknownTokenAfterExplicitCommand -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 900 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Pre-commit Expect: Tests Found `32`, Passed `32`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 1800 ./tests/run.sh
- Pre-commit Expect: Exit code `0`.
Touches: src/dak.cli.pas, tests/units/test.cli.pas, TASKS.md, CHANGELOG.md

### T-077 [MSBUILD] Resolve undefined self-referential properties as empty
Outcome: `TMsBuildEvaluator.ApplyProperty` now seeds the current property with an empty default when it is undefined before macro expansion, so self-referential values like `$(PreBuildEvent)` and `$(DCC_UsePackage)` resolve to empty text instead of remaining unresolved macros.
Proof:
- BLOCKER Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.MsBuild.TMsBuildTests.SelfReferenceFallsBackToEmptyWhenPropertyWasUndefined -cm:Quiet
- BLOCKER Expect: Tests Found `0` (non-execution due stale test binary), so rebuild is required before RED/GREEN proof.
- BLOCKER Fix Command: timeout 1200 ./build-delphi.sh tests/DelphiAIKit.Tests.dproj -config Debug -platform Win32 -ver 23
- BLOCKER Fix Expect: Build exits `0` with `SUCCESS`.
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.MsBuild.TMsBuildTests.SelfReferenceFallsBackToEmptyWhenPropertyWasUndefined -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` with `Expected [echo before] but got [echo before$(PreBuildEvent)]`.
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.MsBuild.TMsBuildTests.SelfReferenceFallsBackToEmptyWhenPropertyWasUndefined -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 900 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Pre-commit Expect: Tests Found `31`, Passed `31`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 1800 ./tests/run.sh
- Pre-commit Expect: Exit code `0`.
Touches: src/dak.msbuild.pas, tests/units/test.msbuild.pas, TASKS.md, CHANGELOG.md

### T-076 [CLI] Reject unknown explicit command tokens in help mode
Outcome: `TryGetCommand` now rejects unknown positional command tokens even when `--help` is present, while still ignoring positional values explicitly consumed by value-taking switches.
Proof:
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandRejectsUnknownExplicitToken -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` with `Expected unknown explicit token to be rejected even when --help is present.`
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandRejectsUnknownExplicitToken -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 900 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Pre-commit Expect: Tests Found `29`, Passed `29`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 1800 ./tests/run.sh
- Pre-commit Expect: Exit code `0`.
Touches: src/dak.cli.pas, tests/units/test.cli.pas, CHANGELOG.md

### T-075 [CLI] Harden help-command value handling and CSV delimiter spoof resistance
Outcome: Help command detection now skips positional tokens consumed by value-taking switches so command-like values (for example `--project analyze`) are not treated as explicit commands, and FixInsight CSV post-processing now rejects delimiter layouts where file fields embed an alternate headerless row signature (line/column/rule), preventing message-token spoofing from removing non-ignored findings.
Proof:
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandDoesNotTreatSwitchValueAsExplicitCommand -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` with `Expected no explicit command when command-like token is consumed by --project.`
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.ReportPostProcess.TReportPostProcessTests.CsvIgnoreRuleIdsDoesNotInferDelimiterFromNumericMessageTokens -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` (`Expected [1] but got [0]`).
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandDoesNotTreatSwitchValueAsExplicitCommand -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.ReportPostProcess.TReportPostProcessTests.CsvIgnoreRuleIdsDoesNotInferDelimiterFromNumericMessageTokens -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 900 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Pre-commit Expect: Tests Found `27`, Passed `27`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 1800 ./tests/run.sh
- Pre-commit Expect: Exit code `0`.
Touches: src/dak.cli.pas, src/dak.reportpostprocess.pas, tests/units/test.cli.pas, tests/units/test.reportpostprocess.pas, CHANGELOG.md

### T-074 [CLI] Ignore switch values while resolving help command context
Outcome: `TryGetCommand` now skips non-command positional tokens when help mode is active, so value arguments for switches like `--project` no longer trigger false `Unknown command` errors, and explicit commands after those values are still detected.
Proof:
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandIgnoresSwitchValueTokens -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` with `Unknown command: C:\repo\Sample.dproj`.
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandFindsExplicitCommandAfterSwitchValues -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` with `Unknown command: C:\repo\Sample.dproj`.
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandIgnoresSwitchValueTokens -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.HelpCommandFindsExplicitCommandAfterSwitchValues -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 900 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Pre-commit Expect: Tests Found `25`, Passed `25`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 1800 ./tests/run.sh
- Pre-commit Expect: Exit code `0`.
Touches: src/dak.cli.pas, tests/units/test.cli.pas, CHANGELOG.md

### T-073 [ANALYZE] Ignore stale TXT summary data when TXT report is skipped
Outcome: `analyze` summaries now report FixInsight findings/top-codes only when TXT output was actually generated in the current run, so stale `fixinsight.txt` files (for example after `--fixinsight false --clean false`) no longer contaminate `summary.md`.
Proof:
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.AnalyzeProjectSummarySkipsStaleTxtWhenTxtReportWasNotRun -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` with `Expected summary to ignore stale TXT findings when TXT report was not run.`
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.AnalyzeProjectSummarySkipsStaleTxtWhenTxtReportWasNotRun -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 900 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Pre-commit Expect: Tests Found `23`, Passed `23`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 1200 ./build-and-run-tests.sh
- Pre-commit Expect: Exit code `0`.
Touches: src/dak.analyze.pas, tests/units/test.cli.pas, CHANGELOG.md

### T-072 [CLI] Reject conflicting analyze-unit target arguments
Outcome: `analyze-unit` now rejects simultaneous `--project` and `--unit` inputs with the existing conflict message, so we consistently enforce the “project or unit, never both” contract across all analyze command variants.
Proof:
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.AnalyzeUnitCommandRejectsProjectAndUnitConflict -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` with `Expected analyze-unit to reject simultaneous --project and --unit.`
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.Cli.TCliTests.AnalyzeUnitCommandRejectsProjectAndUnitConflict -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 900 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Pre-commit Expect: Tests Found `22`, Passed `22`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 1200 ./build-and-run-tests.sh
- Pre-commit Expect: Exit code `0`.
Touches: src/dak.cli.pas, tests/units/test.cli.pas, CHANGELOG.md

### T-071 [CLI] Fix MSBuild boolean token boundaries and CSV headerless detection
Outcome: MSBuild `Condition` parsing now accepts valid `and/or` operators even when no whitespace surrounds quoted operands, and FixInsight CSV post-processing no longer misclassifies headerless rows as headers when message text equals header-like tokens (for example `line`).
Proof:
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.MsBuild.TMsBuildTests.AcceptsConditionWithoutWhitespaceAroundOr -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` with `Unsupported or invalid Condition`.
- RED Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.ReportPostProcess.TReportPostProcessTests.CsvIgnoreRuleIdsDoesNotTreatHeaderlessRowAsHeaderWhenMessageIsLine -cm:Quiet
- RED Expect: Tests Found `1`, Passed `0`, Failed `1` (`Expected [0] but got [1]`).
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.MsBuild.TMsBuildTests.AcceptsConditionWithoutWhitespaceAroundOr -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- GREEN Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.ReportPostProcess.TReportPostProcessTests.CsvIgnoreRuleIdsDoesNotTreatHeaderlessRowAsHeaderWhenMessageIsLine -cm:Quiet
- GREEN Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Pre-commit Expect: Tests Found `21`, Passed `21`, Failed `0`, Leaked `0`.
- Pre-commit Command: timeout 900 ./build-and-run-tests.sh
- Pre-commit Expect: Exit code `0`.
Touches: src/dak.msbuild.pas, src/dak.reportpostprocess.pas, tests/units/test.msbuild.pas, tests/units/test.reportpostprocess.pas, CHANGELOG.md

### T-070 [CLI] Fix CSV rule-ignore delimiter misdetection
Outcome: FixInsight CSV post-processing now validates headerless row layout (including numeric line/column fields) before accepting a delimiter, preventing `--ignore-warning-ids` from matching rule-like tokens inside message text.
Proof:
- Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -r:Test.ReportPostProcess.TReportPostProcessTests.CsvIgnoreRuleIdsUsesActualRuleColumnWhenMessageLooksLikeRuleTokens -cm:Quiet
- Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Command: timeout 600 ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Expect: Tests Found `18`, Passed `18`, Failed `0`, Leaked `0`.
- Command: timeout 900 ./build-and-run-tests.sh
- Expect: Exit code `0`.
Touches: src/dak.reportpostprocess.pas, tests/units/test.reportpostprocess.pas, CHANGELOG.md

### T-069 [TEST] Fix diagnostics log reopen handle leak
Outcome: Reopening diagnostics log files now releases previously opened writer/stream/encoding objects before opening the next file, preventing stale file locks and memory leaks.
Proof:
- Command: ./tests/DelphiAIKit.Tests.exe -r:Test.Diagnostics.TDiagnosticsTests.ReopenLogFileReleasesPreviousHandle -cm:Quiet
- Expect: Tests Found `1`, Passed `1`, Failed `0`, Leaked `0`.
- Command: ./tests/DelphiAIKit.Tests.exe -cm:Quiet
- Expect: Tests Found `6`, Passed `6`, Failed `0`, Leaked `0`.
- Command: timeout 900 ./tests/run.sh
- Expect: Exit code `0`.
- Command: timeout 900 ./build-and-run-tests.sh
- Expect: Exit code `0`.
Touches: src/dak.diagnostics.pas, tests/DelphiAIKit.Tests.dpr, tests/units/test.diagnostics.pas

### T-062 [CLI] Build: Add bounded findings output (`--max-findings`)
Outcome: Add a build option to cap how many findings are printed per category (errors/warnings/hints), defaulting to `5`, while preserving current behavior where warnings and hints remain hidden unless explicitly requested.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --project "F:\\projects\\MaxLogic\\DelphiConfigResolver\\tests\\DelphiAIKit.Tests.dproj" --delphi 23.0 --platform Win32 --config Debug --ai
- Expect: Build output does not print warning/hint lines by default; success/failure summary is still shown.
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --project "F:\\projects\\MaxLogic\\DelphiConfigResolver\\tests\\DelphiAIKit.Tests.dproj" --delphi 23.0 --platform Win32 --config Debug --show-warnings --show-hints --max-findings 5 --ai
- Expect: At most 5 warning lines and at most 5 hint lines are printed.
Touches: src/dak.cli.pas, src/dak.messages.pas, src/dak.types.pas, build-delphi.bat, README.md

### T-063 [CLI] Build: Add `--json` output mode
Outcome: Add machine-readable JSON output for `DelphiAIKit.exe build` with status, exit code, timing, counts, and bounded findings so CI and AI tooling can consume build results deterministically.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --project "F:\\projects\\MaxLogic\\DelphiConfigResolver\\projects\\DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug --json
- Expect: Stdout is valid JSON containing at least `status`, `exit_code`, `errors`, `warnings`, `hints`, and `time_ms`.
Touches: projects/DelphiAIKit.dpr, src/dak.cli.pas, src/dak.messages.pas, src/dak.types.pas, build-delphi.bat, README.md

### T-064 [CLI] Build: Add configurable build timeout
Outcome: Add a build timeout option so hung MSBuild processes are terminated and reported with a clear timeout failure message and non-zero exit code.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --help
- Expect: Help includes timeout option and default value.
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --project "F:\\projects\\MaxLogic\\DelphiConfigResolver\\projects\\DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug --build-timeout-sec 1
- Expect: If build exceeds timeout, process is terminated and build exits non-zero with timeout reason.
Touches: projects/DelphiAIKit.dpr, src/dak.cli.pas, src/dak.messages.pas, src/dak.types.pas, build-delphi.bat, README.md
Notes: Deterministic timeout behavior additionally verified via scripts/build-delphi-run-msbuild.ps1 (TimeoutSec=1, exit 124).

### T-065 [CLI] Build: Expose MSBuild target selection (`Build|Rebuild`)
Outcome: Add an explicit target option so we can choose `/t:Build` (incremental) or `/t:Rebuild` (clean + full compile) without editing scripts.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --help
- Expect: Help documents target option with accepted values `Build` and `Rebuild`.
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\build-delphi.bat" "F:\\projects\\MaxLogic\\DelphiConfigResolver\\projects\\DelphiAIKit.dproj" -config Debug -platform Win32 -ver 23 -target Rebuild
- Expect: MSBuild invocation uses `/t:Rebuild`.
Touches: src/dak.cli.pas, src/dak.messages.pas, src/dak.types.pas, build-delphi.bat, README.md

### T-066 [CLI] Build: Add optional isolated output directory mode
Outcome: Add an option to compile into an isolated output directory (test/scratch mode) so we can validate compilation without overwriting normal build artifacts.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\build-delphi.bat" "F:\\projects\\MaxLogic\\DelphiConfigResolver\\projects\\DelphiAIKit.dproj" -config Debug -platform Win32 -ver 23 -test-output-dir "F:\\temp\\dak-build-scratch"
- Expect: Build outputs are written under `F:\\temp\\dak-build-scratch` and normal `bin` output remains unchanged.
Touches: build-delphi.bat, src/dak.cli.pas, src/dak.messages.pas, src/dak.types.pas, README.md

### T-067 [CLI] Build: Detect stale/locked output executable
Outcome: Detect when compilation reports success but output binary timestamp did not advance, and report this as an explicit `output_locked` style failure/warning to reduce false positives.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --project "F:\\projects\\MaxLogic\\DelphiConfigResolver\\projects\\DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug --json
- Expect: JSON includes output path metadata and, when stale output is detected, a dedicated stale/locked indicator.
Touches: projects/DelphiAIKit.dpr, build-delphi.bat, src/dak.cli.pas, src/dak.messages.pas, README.md

### T-068 [CLI] Build: Inject missing `environment.proj` variables into MSBuild
Outcome: When command-line MSBuild lacks IDE-only variables from `environment.proj`, inject missing values as `/p:` properties to improve parity with IDE builds.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\build-delphi.bat" "F:\\projects\\MaxLogic\\DelphiConfigResolver\\projects\\DelphiAIKit.dproj" -config Debug -platform Win32 -ver 23 -keep-logs
- Expect: Build succeeds in environments where required custom variables are defined only in `environment.proj`.
Touches: build-delphi.bat, src/dak.rsvars.pas, src/dak.project.pas, README.md

### T-061 [CLI] Build: Token-Saving “AI Mode” Output
Outcome: Add an “AI mode” for `DelphiAIKit.exe build` that prints only what matters to review a build: error summary first, then (optional) a bounded list of warning/hint lines, stripping compiler banners and other noise by default.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --project "F:\\projects\\MaxLogic\\DelphiConfigResolver\\tests\\DelphiAIKit.Tests.dproj" --delphi 23.0 --platform Win32 --config Release --ai
- Expect: Output contains a concise success line and does not print the compiler banner.
Touches: projects/DelphiAIKit.dpr, src/dak.cli.pas, src/dak.types.pas, build-delphi.bat
Notes: Consider mapping to `build-delphi.bat -no-brand` and adding a bounded “top N warnings/hints” summary.

### T-060 [CLI] Build: Honor dak.ini Ignores For Compiler Warnings/Hints
Outcome: Honor ignore lists from `dak.ini` (and CLI overrides) for compiler warnings/hints so build output can hide known-noise findings while still surfacing new/high-signal ones.
Proof:
- Command: ./build-delphi.sh tests/DelphiAIKit.Tests.dproj
- Expect: Build succeeds.
- Command: tests/run.sh
- Expect: Exit code `0`.
Touches: bin/dak.ini, src/dak.analyze.pas, src/dak.diagnostics.pas, projects/DelphiAIKit.dpr, src/dak.cli.pas, src/dak.types.pas
Notes: Add a dedicated `dak.ini` section for build ignores (e.g. `[BuildIgnore] Warnings=... Hints=...`) and ensure CLI can override.

### T-059 [CLI] Build: Normalize Paths In Output (Repo-Relative + WSL-Friendly)
Outcome: Normalize paths in `DelphiAIKit.exe build` output so AI output is stable across machines: make paths repo-relative where possible (VCS root if detected, else `.dproj` dir), and optionally emit WSL/Linux-style paths when running under WSL.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --project "F:\\projects\\MaxLogic\\DelphiConfigResolver\\tests\\DelphiAIKit.Tests.dproj" --delphi 23.0 --platform Win32 --config Release
- Expect: Output does not contain absolute `F:\\projects\\MaxLogic\\DelphiConfigResolver\\` prefixes for project files; paths are relative where applicable.
Touches: projects/DelphiAIKit.dpr, src/dak.output.pas, src/dak.messages.pas, build-delphi.bat
Notes: Prefer a single normalization function shared with static-analysis postprocess (same “repo root vs `.dproj` dir” logic).

### T-058 [CLI] Build: Expose Warnings/Hints Output Switches
Outcome: Extend `DelphiAIKit.exe build` with switches to control build output verbosity, including separate switches to include compiler warnings and hints in output on success.
Proof:
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --help
- Expect: Help text mentions `--show-warnings` and `--show-hints`.
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --project "F:\\projects\\MaxLogic\\DelphiConfigResolver\\tests\\DelphiAIKit.Tests.dproj" --delphi 23.0 --platform Win32 --config Release --show-warnings
- Expect: Output includes a `SUCCESS. Warnings:` line (counts may be 0).
- Command: /mnt/c/Windows/System32/cmd.exe /C "F:\\projects\\MaxLogic\\DelphiConfigResolver\\bin\\DelphiAIKit.exe" build --project "F:\\projects\\MaxLogic\\DelphiConfigResolver\\tests\\DelphiAIKit.Tests.dproj" --delphi 23.0 --platform Win32 --config Release --show-hints
- Expect: Output includes a `SUCCESS. ... Hints:` line (counts may be 0).
Touches: src/dak.cli.pas, src/dak.types.pas, projects/DelphiAIKit.dpr, build-delphi.bat, src/dak.messages.pas
Notes: `build-delphi.bat` already supports `-show-warnings-on-success`; we will likely extend it to support separate hints/warnings switches and forward those from `DelphiAIKit.exe build`.

### T-057 [DOC] Add static-analysis fix recipes
Outcome: Add `agentskill/delphi-static-analysis/references/fix-recipes.md` with safe, conservative fix recipes for common FixInsight/PAL findings, including what to verify (build/tests) and links to our rules in `conventions.md` (especially AutoFree.GC and managed types).
Proof:
- Command: test -f agentskill/delphi-static-analysis/references/fix-recipes.md
- Expect: Exit code `0`.
- Command: rg -n \"AutoFree\\.GC\\(\\)|Managed Types|PALOFF\" agentskill/delphi-static-analysis/references/fix-recipes.md
- Expect: Outputs at least 3 matching lines.
Touches: agentskill/delphi-static-analysis/references/fix-recipes.md

### T-056 [CLI] Gate: include/exclude paths for CI gating
Outcome: Add `DAK_GATE_INCLUDE_PATHS` / `DAK_GATE_EXCLUDE_PATHS` (semicolon-separated glob patterns; same semantics as triage) so the CI gate only considers findings in selected paths (e.g. `src/*`) and ignores vendor/submodules.
Proof:
- Command: python3 - <<'PY'\nimport json, shutil\nfrom pathlib import Path\nroot = Path('/tmp/dak-gate-paths')\nshutil.rmtree(root, ignore_errors=True)\n(root / 'pascal-analyzer').mkdir(parents=True)\n(root / 'fixinsight').mkdir(parents=True)\n(root / 'summary.md').write_text('\\n'.join([\n  '# Static analysis summary',\n  '- Timestamp: 2026-01-01T00:00:00Z',\n  '- Project: `F:\\\\tmp\\\\Foo.dproj`',\n  '- Findings (by code): 0',\n  '- Totals: warnings=0, strong_warnings=0, exceptions=0',\n  '',\n]) + '\\n', encoding='utf-8')\n(root / 'pascal-analyzer' / 'pal-findings.jsonl').write_text(json.dumps({\n  'tool': 'pal',\n  'severity': 'strong-warning',\n  'path': 'vendor/Lib.pas',\n  'line': 10,\n  'col': 1,\n  'section': 'Possible nil access',\n  'message': 'Synthetic strong warning',\n}) + '\\n', encoding='utf-8')\n(root / 'baseline.json').write_text(json.dumps({\n  'version': 3,\n  'created_at': '2026-01-01T00:00:00Z',\n  'run_context': {'platform':'unknown','config':'unknown','delphi':'unknown'},\n  'summary': {'timestamp':'2026-01-01T00:00:00Z'},\n  'fixinsight': {'total': 0, 'counts_by_code': {}, 'w_hashes': []},\n  'pascal_analyzer': {'totals': {'warnings': 0, 'strong_warnings': 0, 'exceptions': 0}, 'warning_hashes': [], 'strong_hashes': []},\n}, indent=2) + '\\n', encoding='utf-8')\nprint(root)\nPY
- Expect: Prints `/tmp/dak-gate-paths`.
- Command: DAK_GATE=1 python3 agentskill/delphi-static-analysis/postprocess.py /tmp/dak-gate-paths
- Expect: Exit code `3` (gate fail due to a new PAL strong warning).
- Command: DAK_GATE=1 DAK_GATE_EXCLUDE_PATHS='vendor/*' python3 agentskill/delphi-static-analysis/postprocess.py /tmp/dak-gate-paths
- Expect: Exit code `0` (gate pass; vendor finding excluded).
Touches: agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/SKILL.md

### T-055 [CLI] Emit SARIF report for PR annotations
Outcome: Emit `_analysis/<project>/static-analysis.sarif` (SARIF v2.1.0) from our normalized FixInsight/PAL findings so PRs can annotate findings inline (e.g., GitHub code scanning) without opening `triage.md`.
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/static-analysis.sarif` exists.
- Command: python3 - <<'PY'\nimport json\nfrom pathlib import Path\np = Path('_analysis/DelphiAIKit/static-analysis.sarif')\nobj = json.loads(p.read_text(encoding='utf-8'))\nassert obj.get('version') == '2.1.0'\nassert isinstance(obj.get('runs'), list) and obj['runs']\nprint('ok')\nPY
- Expect: Prints `ok`.
Touches: agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/SKILL.md

### T-054 [CLI] Include triage-snippets path in postprocess JSON result
Outcome: When `DAK_TRIAGE_SNIPPETS=1` produces `triage-snippets.md`, include its path in the JSON result as `triage_snippets` so wrappers/CI can link it directly.
Proof:
- Command: DAK_TRIAGE_SNIPPETS=1 python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: JSON output includes a `triage_snippets` field pointing at `_analysis/DelphiAIKit/triage-snippets.md`.
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-053 [CLI] Split FixInsight triage into defects vs maintainability
Outcome: Update `triage.md` (and snippets) rendering so FixInsight findings are grouped by kind: `W` (defects), `C` (maintainability/refactor pressure), `O` (hygiene), to keep the fix workflow focused.
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/triage.md` contains headings for FixInsight `W`, `C`, and `O` groups (even if a group is empty).
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-052 [CLI] Deprioritize PAL Exception Call Tree entries in triage
Outcome: Keep `Exception Call Tree` entries out of the top triage list by default (low priority), unless explicitly enabled via `DAK_TRIAGE_PAL_INCLUDE_CALL_TREE=1`.
Proof:
- Command: python3 -c "import importlib.util, sys; spec=importlib.util.spec_from_file_location('pp','agentskill/delphi-static-analysis/postprocess.py'); m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m); assert m._pal_triage_priority('warning') > m._pal_item_priority('exception','Exception.xml','Exception Call Tree',''); print('ok')"
- Expect: Prints `ok`.
Touches: agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/SKILL.md

### T-051 [CLI] Add triage include/exclude path filters
Outcome: Add `DAK_TRIAGE_INCLUDE_PATHS` and `DAK_TRIAGE_EXCLUDE_PATHS` (semicolon-separated glob patterns) so `triage.md`/`triage-snippets.md` can focus on selected paths without re-running analyzers.
Proof:
- Command: DAK_TRIAGE_INCLUDE_PATHS='src/*' python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/triage.md` does not contain `lib/MaxLogicFoundation/`.
- Command: DAK_TRIAGE_EXCLUDE_PATHS='lib/*' python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/triage.md` does not contain `lib/MaxLogicFoundation/`.
Touches: agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/SKILL.md

### T-050 [CLI] Gate: optionally require matching analysis context
Outcome: Add `DAK_GATE_REQUIRE_CONTEXT_MATCH=1` that makes the postprocess gate fail when baseline/current `run_context` differ materially (platform/config/delphi/tool target), ignoring `unknown` values.
Proof:
- Command: python3 - <<'PY'\nimport json\nfrom pathlib import Path\nsrc = Path('_analysis/DelphiAIKit/baseline.json')\ndst = Path('/tmp/baseline-mismatch-gate.json')\nobj = json.loads(src.read_text(encoding='utf-8'))\nrc = dict(obj.get('run_context') or {})\nrc['platform'] = 'Win64'\nrc['config'] = 'Debug'\nrc['delphi'] = '99.9'\nobj['run_context'] = rc\ndst.write_text(json.dumps(obj, indent=2, sort_keys=True) + '\\n', encoding='utf-8')\nprint(dst)\nPY
- Expect: Creates `/tmp/baseline-mismatch-gate.json`.
- Command: DAK_GATE=1 DAK_GATE_REQUIRE_CONTEXT_MATCH=1 DAK_BASELINE=/tmp/baseline-mismatch-gate.json python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: Exit code `3` and `_analysis/DelphiAIKit/delta.md` includes a Gate FAIL reason about context mismatch.
Touches: agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/SKILL.md

### T-049 [CLI] Emit triage-snippets.md with bounded source context
Outcome: Add an optional `DAK_TRIAGE_SNIPPETS=1` mode that emits `_analysis/<project>/triage-snippets.md` containing small, bounded source snippets for the top triage items (best-effort; repo-local paths only) to speed up fixing without opening files manually.
Proof:
- Command: DAK_TRIAGE_SNIPPETS=1 python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/triage-snippets.md` exists and contains at least one ```delphi code block.
- Expect: Snippets are bounded by `DAK_TRIAGE_TOP` and `DAK_TRIAGE_SNIPPET_CONTEXT` (default), and the file is truncated when exceeding `DAK_TRIAGE_SNIPPET_MAX_BYTES`.
Touches: agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/SKILL.md, agentskill/delphi-static-analysis/references/triage.md

### T-036 Fix GetExitCodeProcess out param cast in maxConsoleRunner
Outcome: Use a local `DWORD` for `GetExitCodeProcess` and then assign to `fExitCode` to avoid the unsafe typecast and keep the public `ExitCode: Integer` unchanged.
Proof:
- Command: DAK_PASCAL_ANALYZER=true ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: pal-findings no longer reports "Possible bad typecast" for `maxConsoleRunner.pas:334`.
Touches: lib/MaxLogicFoundation/maxConsoleRunner.pas

### T-037 Use safe JSON array cast in Pascal Analyzer runner
Outcome: Replace the hard cast in `TryGetJsonArray` with a safe cast after the `is TJSONArray` guard to clear the PAL strong warning without changing behavior.
Proof:
- Command: DAK_PASCAL_ANALYZER=true ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: pal-findings no longer reports "Possible bad typecast" for `dak.pascalanalyzerrunner.pas:169`.
Touches: src/dak.pascalanalyzerrunner.pas

### T-038 Refactor TAsyncLoop.Run to avoid PAL bad pointer usage warning
Outcome: Update `TAsyncLoop.Run` to avoid capturing a local loop instance inside anonymous methods while preserving behavior and keeping public API signatures unchanged.
Proof:
- Command: DAK_PASCAL_ANALYZER=true ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: pal-findings no longer reports "Possible bad pointer usage" for `maxAsync.pas:1267`.
Touches: lib/MaxLogicFoundation/maxAsync.pas
Notes: Keep the change internal to the unit; do not change any public/protected signatures.

### T-039 Remove PAL bad typecast warning in maxConsoleRunner ExitCode
Outcome: Update exit-code retrieval to avoid PAL "Possible bad typecast" for `fExitCode` while keeping the public `ExitCode: Integer` unchanged.
Proof:
- Command: DAK_PASCAL_ANALYZER=true ./agentskill/delphi-static-analysis/analyze.sh /mnt/f/projects/MaxLogic/DelphiConfigResolver/projects/DelphiAIKit.dproj
- Expect: pal-findings no longer reports "Possible bad typecast" for `lib/MaxLogicFoundation/maxConsoleRunner.pas` exit-code handling.
Touches: lib/MaxLogicFoundation/maxConsoleRunner.pas

### T-048 [CLI] Track metrics history and emit trend.md (continuous monitoring)
Outcome: Append a per-run metrics snapshot to `_analysis/<project>/history.jsonl` (deduped by summary timestamp) and emit `_analysis/<project>/trend.md` summarizing recent runs to support continuous monitoring (spotting spikes in warnings/complexity over time).
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/history.jsonl` exists and contains at least 1 JSONL record.
- Expect: `_analysis/DelphiAIKit/trend.md` exists and contains a table of FixInsight + PAL totals.
Touches: agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/SKILL.md

### T-047 [CLI] Warn on baseline/current context mismatches in delta.md
Outcome: When baseline and current `run_context` differ materially (platform/config/delphi or tool versions), emit an explicit warning in `delta.md` so we don’t trust deltas/gates computed across incompatible runs.
Proof:
- Command: python3 - <<'PY'\nimport json\nfrom pathlib import Path\nsrc = Path('_analysis/DelphiAIKit/baseline.json')\ndst = Path('/tmp/baseline-mismatch.json')\nobj = json.loads(src.read_text(encoding='utf-8'))\nrc = dict(obj.get('run_context') or {})\nrc['platform'] = 'Win64'\nrc['config'] = 'Debug'\nrc['delphi'] = '99.9'\nobj['run_context'] = rc\ndst.write_text(json.dumps(obj, indent=2, sort_keys=True) + '\\n', encoding='utf-8')\nprint(dst)\nPY
- Expect: Creates `/tmp/baseline-mismatch.json`.
- Command: DAK_BASELINE=/tmp/baseline-mismatch.json python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/delta.md` contains a “context mismatch” warning.
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-046 [CLI] Map FixInsight absolute file paths to repo-relative paths when possible
Outcome: When FixInsight reports absolute paths outside the current repo but the corresponding unit exists in our repo/submodule, populate the normalized `path` field with a repo-relative path (unique basename match) while preserving the original `file` value.
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/fixinsight/fi-findings.jsonl` records for MaxLogicFoundation use `path` starting with `lib/MaxLogicFoundation/` (instead of `f:/...`).
- Command: python3 - <<'PY'\nimport json\nfrom pathlib import Path\np = Path('_analysis/DelphiAIKit/fixinsight/fi-findings.jsonl')\nitems = [json.loads(l) for l in p.read_text(encoding='utf-8', errors='replace').splitlines() if l.strip()]\nmf = [it for it in items if 'maxlogicfoundation' in (it.get('file','').lower())]\nassert mf, 'no MaxLogicFoundation FixInsight findings found to validate'\nbad = [it for it in mf if not str(it.get('path','')).startswith('lib/MaxLogicFoundation/')]\nassert not bad, bad[:2]\nprint('ok', len(mf))\nPY
- Expect: Prints `ok <n>`.
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-045 [CLI] Fix FixInsight triage ordering (W > C > O)
Outcome: Adjust triage prioritization so FixInsight findings are ordered `W` first, then `C`, then `O` (default), preventing low-value optimization/style hints from hiding higher-signal issues.
Proof:
- Command: python3 -c "import importlib.util, sys; spec=importlib.util.spec_from_file_location('pp','agentskill/delphi-static-analysis/postprocess.py'); m=importlib.util.module_from_spec(spec); sys.modules[spec.name]=m; spec.loader.exec_module(m); assert m._fi_triage_priority('C') > m._fi_triage_priority('O'); print('ok')"
- Expect: Prints `ok`.
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/triage.md` exists and FixInsight top entries are not dominated by `O*` codes when `C*`/`W*` findings exist.
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-040 [CLI] Emit prioritized triage.md from analysis outputs
Outcome: Generate `_analysis/<project>/triage.md` with a prioritized, fix-oriented shortlist (top 20 by default), grouped by file where possible and referencing line numbers.
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/triage.md` exists and includes sections for FixInsight and Pascal Analyzer.
Touches: agentskill/delphi-static-analysis/postprocess.py, agentskill/delphi-static-analysis/SKILL.md, agentskill/delphi-static-analysis/references/triage.md

### T-041 [CLI] Normalize finding paths for stable deltas
Outcome: Normalize FixInsight and Pascal Analyzer findings to stable, repo-relative paths (slashes/case/relativization) so baselines and deltas are resilient across machines and working directories.
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/fixinsight/fi-findings.jsonl` contains a normalized `path` field and does not contain `..\\` segments.
- Expect: Running the command twice does not introduce spurious “new” findings in `_analysis/DelphiAIKit/delta.md`.
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-042 [CLI] Add Git changed-file scope triage
Outcome: Add a `DAK_SCOPE=changed` mode that emits `_analysis/<project>/triage-changed.md` filtered to Git-changed files (and degrades gracefully when Git is unavailable).
Proof:
- Command: DAK_SCOPE=changed python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/triage-changed.md` exists (and when the repo is clean, indicates no changed files).
Touches: agentskill/delphi-static-analysis/postprocess.py

### T-043 [CLI] Capture run context in baselines and fix delta wording
Outcome: Extend baseline/delta artifacts to include the run context (platform/config/delphi, tool versions when available) and rename misleading labels (e.g. “New W-codes” -> “New W-findings”).
Proof:
- Command: python3 agentskill/delphi-static-analysis/postprocess.py _analysis/DelphiAIKit
- Expect: `_analysis/DelphiAIKit/baseline.json` includes a `run_context` section (platform/config/delphi at minimum).
- Expect: `_analysis/DelphiAIKit/delta.md` uses “New W-findings”.
Touches: agentskill/delphi-static-analysis/postprocess.py

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
