# Native test migration

DAK-368, DAK-369 and DAK-370 track this migration. Remaining scripts stay in
place until their retained behavior has native coverage. Benchmarks are deferred.

| Removed check | Retained behavior and destination |
| --- | --- |
| `test-build-delphi-output-name.ps1` | `Test.Build.TBuildTests.BuildReportsTheExecutableTheCompilerEmitted` checks file naming and freshness; `NativeBuildOutputContracts` checks an empty successful build reports missing output and resolves `MSBuildProjectDirectory`, platform and configuration in output paths. |
| `test-build-delphi-msbuild-exit.ps1` | `Test.Build.TBuildTests.NativeBuildPreservesMsBuildFailure` checks a real MSBuild failure produces nonzero exit, error JSON, a nonzero error count and retained native diagnostics. It uses a project lacking the Build target (MSB4057), because the native CLI validates target names and does not expose the old wrapper's switch injection. |
| `test-build-warning-summary.ps1` | `Test.Build.TBuildTests.NativeBuildWarningSummary` checks real Win32/Win64 warning and hint counts, code filtering, source filtering and unmatched filters. Native JSON supplies both counts; the raw compiler log must still contain W1035 and H2077. The old wrapper's exact text-summary wording is not a native CLI contract. |
| `test-build-delphi-wrapper.ps1` | `Test.Build.TBuildTests.NativeConcurrentBuildsKeepOutputsAndDiagnosticsSeparate` builds two isolated copies concurrently with paths containing spaces, separate executable output directories and separate native stdout/stderr diagnostics. Wrapper-only timestamp log names, `-log-dir`, and `msbuild-full.log` checks are obsolete for the native runner. |
| `test-run-bat-bootstrap-host.ps1` and its stand-in host fixture | Bootstrap inside the legacy test runner is removed. `build.bat` uses a pre-existing native host and explicit Win64 Debug targets; tests consume the Debug candidate. The missing-candidate path was invoked directly and returned exit 2 without changing the host. Native `BuildResolverExe` validates the candidate through `EnsureResolverBuilt`, including its Win64 binary type. |
| `test-parallel-temp-roots.ps1` | `Test.ExternalToolProcess.TExternalToolProcessTests.ParallelTestRunsUseIndependentRoots` runs four native children with distinct roots and checks their nonempty passing results. |
| Fake Delphi LSP executable and self-tests | Removed (DAK-370). Per-case disposition in the LSP table below. |
| run.bat help checks | `Test.Cli` command metadata and dedicated help-route tests cover supported commands/options. |
| run.bat resolver formats | `Test.Build.TBuildTests.NativeResolverWritesFormats` writes nonempty ini/xml/bat outputs for the sample and DAK project. MSBuild fixture variants remain covered by `Test.MsBuild`; repeating each output format for every fixture is consolidated. |
| run.bat FixInsight execution and filtering | `Test.FixInsight.TFixInsightTests.FixInsightRawReportsPreserveFilteredEvidence` executes the real analyzer for base/path/rule cases. The batch assertions that filters erase raw reports are obsolete: the current native policy preserves raw evidence and filters actionable projections, covered by `Test.NativeAnalysisReports` and `Test.ReportPostprocess`. |
| run.bat settings cascade and override checks | `Test.Cli.TCliTests.LoadDakSettingsMergesTypedSections`, settings/override tests in `Test.Cli`, and native analysis settings tests retain merge, precedence, source-path and policy contracts. |
| run.bat FixInsight ignore merge (`[FixInsightCL].Ignore` plus `--fi-ignore`) | `Test.Utils.TUtilsTests.ResolveMergesSettingsAndCliFixInsightIgnore` runs the candidate's `resolve --format bat` with a project `dak.ini` and `--fi-ignore`. It checks settings-then-CLI order and that a repeated entry appears once. The merge itself is `Dak.Settings.ApplySettingsOverridesCore`. |
| run.bat PAL execution | `Test.PascalAnalyzer.TPascalAnalyzerTests.RunPascalAnalyzer` and the native project/unit analyzer fixtures retain installed-tool execution, output resolution and override coverage. |
| batch-only opt-out source assertions in `Test.Utils` | Removed with the batch's duplicated policy implementation. Native `ExternalToolSkipDecisionFailsClosedUnlessNamedOptOutIsOne` and the remaining portable-opt-out checks still cover the single policy owner. No skip option is enabled by the launcher. |

## Fake Delphi LSP cases (DAK-370)

Source of the old cases: `tests/units/test.lsp.pas` and
`tests/fixtures/LspFixture/FakeDelphiLspMain.pas` at 391871d. `Protocol` is
`Test.Lsp.Protocol.TLspProtocolTests`; `Runner`, `Architecture` and `Real` are
`Test.Lsp.TLspRunnerTests`, `Test.Lsp.TLspArchitectureTests` and
`Test.Lsp.TRealLspAcceptanceTests`. Native child modes (`DAK_TEST_IDLE_CHILD`,
`DAK_TEST_DESCENDANT_PID`, `DAK_TEST_STDOUT_FRAME`, `DAK_TEST_STDOUT_HOLDER`)
either stay silent or replay fixed bytes; none reads a request.

| Old case | Disposition |
| --- | --- |
| `TLspFixtureTests.FakeServerSupportsInitializeAndShutdown` | Obsolete, fake-server-only: it verified the fake's scripted replies and its clean shutdown. The approved workaround replaces vendor shutdown with controlled cleanup (`Protocol.NativeTransportControlledStop`, `NativeTransportDestructorStopsDescendants`); real request/response exchange is in `Real`. |
| `TLspFixtureTests.FakeServerReturnsScriptedDefinitionAndHoverPayloads` | Obsolete, fake-server-only: it checked that the fake echoed its script. DAK's transformation of such payloads is in `Protocol.DefinitionCoordinatesAndUris` and `HoverPreservesTextAndRange`. |
| `TLspFixtureTests.FakeServerCanSimulateEmptyAndErrorResponses` | Merged. Empty results: `Protocol.EmptyResultShapesStayValid`. Server errors now fail the request (the old test expected success with an error payload): `Protocol.NativeTransportRejectsMalformedFrames` (Server error response), `ResponseValidation` (Server error), `ServerErrorKeepsStageCodeAndMessage`. |
| `TLspFixtureTests.FakeServerAssertsContextFileHandshakeAndNotifications` | Obsolete, fake-server-only: the test itself sent the messages the fake checked, so no DAK code chose them. The probe's contextFile options are checked against the real server in `Real.RealDelphi23ProbePreservesBothHandshakeModes`. |
| `TLspFixtureTests.FakeServerAssertsSettingsFileHandshakeAndNotifications` | Obsolete, fake-server-only, same reason. The settingsFile options and the configuration notification are checked in `Real.RealDelphi23ProbePreservesBothHandshakeModes`. |
| `TLspRunnerTests.LspDiscoveryPrefersExplicitPathThenResolvedInstall` | Retained: `Test.Lsp.TLspContextTests.LspDiscoveryPrefersExplicitPathThenResolvedInstall` (never needed the fake). |
| `TLspRunnerTests.LspRunnerInitializesOpensRequestsAndShutsDownAgainstFakeServer` | Split. The initialize options, the `initialized` then `didChangeConfiguration` (settings file) then `didOpen` order, and the canonical settings file are in `Runner.LspRequestWireSequenceUsesCanonicalSettings`. It tests the builders that `TryRunLspRequest` sends in order. Stale context-file deletion and the canonical settings file: `Runner.LspRequestPreparationReplacesStaleContextFile`. Envelope, lsp metadata and locations from a real run: `Real.RealDelphi23DefinitionMatchesFixtureGoldenAnswer`. Gap below. |
| `TLspRunnerTests.LspRunnerReportsSpecificDiscoveryAndInitFailures` | Merged: `Runner.LspRunnerReportsExecutableFailures` (missing and non-executable file) and `Runner.LspRunnerReportsStageForServerFailures` (initialize error: stage, code, message). |
| `TLspRunnerTests.LspDefinitionReturnsNormalizedLocations` | Merged: `Protocol.DefinitionCoordinatesAndUris` (Local URI); real answer in `Real`. |
| `TLspRunnerTests.LspPositionConversionUsesOneBasedCliAndZeroBasedProtocol` | Merged: `Protocol.RequestUsesZeroBasedPosition`. |
| `TLspRunnerTests.LspDefinitionNormalizesHostQualifiedPlusUris` | Merged: `Protocol.DefinitionCoordinatesAndUris` (Drive authority URI, UNC LocationLink with targetRange preferred, Host URI with literal plus). |
| `TLspRunnerTests.LspHoverReturnsContentsAndOptionalRange` | Merged: `Protocol.HoverPreservesTextAndRange` (Text). |
| `TLspRunnerTests.LspHoverTextOutputStaysCompact` | Merged: `Protocol.HoverPreservesTextAndRange` (Text) checks the `Hover:` heading, one-based `Range:` line and no envelope fields. |
| `TLspRunnerTests.LspHoverRepresentsEmptyResultsExplicitly` | Merged: `Protocol.HoverPreservesTextAndRange` (Empty, no range) and `EmptyResultShapesStayValid`. |
| `TLspRunnerTests.LspSymbolsRequestDocumentSymbolsForFile` | Merged: `Protocol.SymbolsRequestHasNoPosition` (request), `SymbolsFlattenThenFilter` (request file in results), `Real.RealDelphi23SymbolsMatchFixtureGoldenAnswer`. |
| `TLspRunnerTests.LspSymbolsFlattenHierarchicalDocumentSymbols` | Merged: `Protocol.SymbolsUseSelectionRangeAcrossNesting` (three levels, selectionRange preferred, container names). |
| `TLspRunnerTests.LspSymbolsRespectQueryAndLimitAfterFlattening` | Merged: `Protocol.SymbolsFlattenThenFilter` (Query and limit). |
| `TLspRunnerTests.LspSymbolsRepresentEmptyResultsExplicitly` | Merged: `Protocol.EmptyResultShapesStayValid` and `SymbolsFlattenThenFilter` (No matches). |
| `TLspRunnerTests.LspProbeContextFileModeUsesOwnedHandshake` | Merged: `Real.RealDelphi23ProbePreservesBothHandshakeModes` (contextFile mode, no settingsFile key, no configuration notification). |
| `TLspRunnerTests.LspProbeSettingsFileModeUsesSettingsHandshake` | Merged: `Real.RealDelphi23ProbePreservesBothHandshakeModes` (settingsFile mode, reported path, configuration notification). |
| `TLspRunnerTests.LspRunnerTimesOutNonResponsiveServer` | Merged: `Runner.LspRunnerReportsStageForServerFailures` (Unresponsive initialize), `Protocol.NativeTransportBoundsUnresponsiveInput`, and `NativeTransportDestructorStopsDescendants` (Request timeout, tree terminated). |
| `TLspArchitectureTests.LspTransportImplementationLivesOutsideRunner` | Retained: `Architecture.LspTransportImplementationLivesOutsideRunner`. |

Remaining gaps:

- No test watches the runner put `initialized`, `didChangeConfiguration` and
  `didOpen` on the wire in that order. That would need a process that parses
  requests, which is a fake server. The builders it iterates are tested, and
  the real goldens depend on the sequence working.
- Stages after a successful initialize (`definition request`, notifications)
  are only checked through `BuildLspStageError`. Reaching them through the
  runner needs a scripted initialize reply first.
- Cleanup-failure reporting is fault-injected at the transport
  (`Protocol.NativeTransportReportsCleanupFailure`). The runner's use of
  `StopAfterFailure` on each failure path is not injected separately.

The native build ports passed all 66 owning fixture cases on 2026-09-29.
Evidence is retained under
`tests/.dak/DelphiAIKit.Tests/test-modernization/resume-20260929/`:
`run-78e4da23a034483a942224152b83b286/summary.json` and
`native-build-ports-inputs.json`. This is focused characterization, not full
migration acceptance. The LSP fixture passed 34 cases at
`run-4801546fd92b41c59c2a8e009a98e616/summary.json`.

After fixing a PID-file publication race in the native child fixture, the
combined Build/LSP/ExternalToolProcess/Utils selection passed 119/119 at
`run-5bee182ee4c74768a31c986d8efffe70/summary.json`. Current inputs and the
remaining analysis/review limitations are recorded in
`native-modernization-candidate.json` and `native-migration-proof.md` beside it.

| Additional retired check | Native coverage or disposition |
| --- | --- |
| `test-symbolmap-cache-concurrency.ps1` | `TSymbolMapCacheTests.HeldCacheMutexDoesNotBlockOtherRoots` retains held-lock isolation. `ConcurrentIndexPublishesReusableCache` runs four unit publishers or two full RTL-profile publishers, then verifies cache reuse. Existing `IncludedFileChangeProducesDifferentUnitCacheKey` retains include-only invalidation. |
| `test-symbolmap-cache-concurrency-temp-cleanup.ps1` | Its `KeepTemp`, prefix and deletion checks belonged to the retired script. Native cases use the test runner's isolated `UniqueTempPath` lifecycle; they do not implement another recursive cleanup policy. |
| `test-remove-with-build-verification-concurrency.ps1` | `TRemoveWithTransactionTests.HeldBuildMutexAllowsIndependentProjectApply` retains two real CLI processes, held-project blocking, independent-project success and build-log containment. Existing transaction serialization and typed-diagnostics checks remain. |
| `test-child-process-output-drain.ps1` | `TExternalToolProcessTests.NativeHelperCapturesLargeOutputAndExitCode` verifies all 40,000 lines and a nonzero child exit. The native helper redirects both streams to a file; there is no pipe-drain algorithm to retain. |
| `Dak.ChildProcess.ps1`, `test-support.ps1` | Retired after their last script consumers above were replaced. Native subprocesses use `Test.Support.RunProcessWithTimeout`; production process services remain separate. |

The initial combined native port selection passed 38/38 on 2026-09-30 with no
failed, errored, leaked or ignored tests. Evidence:
`test-modernization/resume-20260930/run-c45c89b04f4c4e13bc6c0f8a31b09299/summary.json`
under `tests/.dak/DelphiAIKit.Tests/`. After local JSON lifetime cleanup, the
affected selection passed 11/11 at
`run-b7fd9c864e6d48a4b6fb164a5190c8e5/summary.json` in the same directory.
Exact inputs and proof limits are recorded beside it in `proof.md` and
`native-concurrency-final-inputs.json`; this is not final certification.

Retained external tools have distinct purposes:

- `run-dunitx.ps1` and `dunitx-summary*` launch the native suite and validate its
  external exit/count/leak contract, including failures after its footer.
- `dak-static-analysis-launchers.Tests.ps1` and `dak-static-analysis-docs.Tests.ps1`
  test the delivered shell/documentation boundary.
- `test-delphisemantics-public-surface.ps1` audits imports across the separately
  maintained semantic-library boundary; it is not a product runtime dependency.
- `compare-native-analysis-*`, `verify-native-analysis-migration*` and
  `Dak.ProcessTrace.ps1` retain cross-implementation output and delivery/process
  evidence. Removing the Python reference would defeat the comparison contract.
- `verify-semantic-budgets.py` and benchmark comparison modes remain deferred
  with benchmark work; this migration does not certify or replace them.

## Process-runner proof (2026-09-30 review repair)

- Every test resolves the Win64 Debug candidate (`bin\Debug`, or
  `DAK_TEST_RESOLVER_EXE`). `ResolverExePath` validates it and fails with its
  path when it is missing; `ResolverExePathIsTheCandidateNotTheHost` fails if
  the build host is returned.
- Headless launches are checked by console membership, not by
  `GetConsoleWindow` alone: a default-flag child of a windowless runner has no
  window but shares the runner's console. The child reports whether the runner
  is in its console process list and whether `SW_HIDE` was requested. A
  mutation build with flags 0 failed these checks while `console=0` still
  held. `DescendantsOfHeadlessChildrenStayWindowless` launches a grandchild
  with default flags and checks it inherits the child's hidden console.
- Descendant cleanup is covered for the timeout, normal-exit and helper
  exception paths, using handle identity with a published creation time. The
  timeout test's deadline starts after the child is ready.
- `Dak.ExternalToolProcess` owns a kill-on-close job for each tool, so a tool
  cannot outlive an interrupted DAK (`ExternalToolStopsWhenOwnerIsInterrupted`).
  Decision (2026-09-30, architect): the job applies to every
  `TryRunExternalToolProcess` caller: FixInsight, PAL, the native MSBuild build
  and git metadata capture. When a tool exits, anything it left running stops,
  including MSBuild reuse nodes and git helper daemons. If job creation or
  assignment fails, the start fails closed with the Win32 error. This relies on
  nested jobs (Windows 8 and later), because DAK may itself run inside a job,
  such as the test helper's. A candidate-run build of
  `tests\DelphiAIKit.Tests.dproj` exited 0, and none of its descendants
  (MSBuild, dcc64, conhost) survived, checked by PID and creation time.
- `NativeResolverWritesFormats` checks each format's own shape (INI section and
  keys, XML root and elements, batch header and FixInsight command) plus the
  UTF-8 BOM policy. A mutation that wrote INI content for `--format xml` failed
  both XML cases.

Known limitations, recorded rather than fixed:

- `Test.Support.RunProcessWithStartHook` does not restrict inherited handles
  with `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`. Concurrent test launches can
  inherit each other's capture handles. Mitigated: output goes to files, not
  pipes, so no reader waits for EOF, and each child's job ends with its run.
- `TSymbolMapCacheTests.HeldCacheMutexDoesNotBlockOtherRoots` rebuilds the
  cache mutex name with the production formula instead of calling it. After a
  formula change the test holds an unrelated mutex; it then fails only because
  the same-root command finishes within the 1.2 s wait, which a slow start
  can hide.
- The Symbol Map and remove-with concurrency tests do not prove that the two
  processes overlapped in time. They prove isolation and final state; a fast
  first process could finish before the second starts.
- Include-file invalidation is covered only at unit level
  (`IncludedFileChangeProducesDifferentUnitCacheKey`), not through the CLI.
- `PALCMD help` (`TryCapturePalCmdHelp`) uses its own launch without a job.
  It is bounded by its timeout, but an interrupted DAK can leave it running
  until it ends. The headless mutation proof did not cover that route.

Final suite, analysis and shared-runner review gates remain pending. These
focused results do not certify the whole migration.

## build-delphi wrapper retirement (DAK-368, 2026-09-30)

User decision 2026-09-30: `build-delphi.bat` (816 lines) and `build-delphi.sh`
(33 lines) are retired; callers run `DelphiAIKit.exe build` directly. Inventory
of every wrapper behavior, checked against `bin\Debug\DelphiAIKit.exe build --help`
(candidate SHA-256 prefix 5ED6134E6BC5) and the native runner
(`src\dak.build.runner.pas`, `src\dak.build.summary.pas`, `src\dak.cli.pas`).
Classes: E = equivalent in DAK, D = intentionally dropped, G = gap.

| # | Wrapper behavior | Native equivalent or reason | Class |
| --- | --- | --- | --- |
| 1 | `-ver N` (default 23) | `--delphi <major.minor>`; also `DAK_DELPHI` and `[Build] DelphiVersion`. No built-in default: omitting it fails with exit 6 and a clear message. Explicit version is the stricter contract. | D |
| 2 | `-config Debug\|Release` (default Release) | `--config`; default Release (`TOptionParser.InitDefaults`). | E |
| 3 | `-platform` (default Win32) | `--platform`, `DAK_PLATFORM`; default Win32. | E |
| 4 | `-target Build\|Rebuild`, `-rebuild` | `--target`, `--rebuild [true\|false]`; default Build. | E |
| 5 | `-max-findings N` (default 5) | `--max-findings`; default 5, validated >= 1. | E |
| 6 | `-build-timeout-sec N` (default 0, exit 124, status `timeout`) | `--build-timeout-sec`; default 0; `cStatusTimeout`, timeout exit code 124 in the runner. | E |
| 7 | `-test-output-dir` (redirects exe, dcu, bpl, dcp) | `--test-output-dir`; same DCC output properties and output resolution. | E |
| 8 | `-ignore-warnings`, `-ignore-hints`, `-exclude-path-masks` plus `[BuildIgnore]` in dak.ini | Same three `--` options plus cascading `[BuildIgnore]` (`Dak.Settings`, `Dak.Build.Summary`). Covered by `Test.Build.TBuildTests.NativeBuildWarningSummary`. | E |
| 9 | `-show-warnings`, `-show-hints` | Same options. | E |
| 10 | `-show-warnings-on-success` (both) | Pass `--show-warnings --show-hints`. Alias only. | D |
| 11 | `-ai`, `-json` | `--ai`, `--json`; statuses ok/warnings/hints/error/timeout/output_missing/output_locked/internal_error (`cStatus*`). | E |
| 12 | `-no-brand`, Embarcadero banner filtering, ASCII header box, "done in hh:mm:ss" line | Native summary owns formatting; no banner is printed and no header box exists. Cosmetic. | D |
| 13 | Path sanitizing (strip workspace root from diagnostics) | Native summary parser (`Dak.Build.Summary`) prints compact findings. Covered by the warning-summary test. | E |
| 14 | Project argument: positional, relative to cwd or the script folder | `--project` (required); relative paths resolve against cwd. The script-folder fallback is dropped. Verified from WSL: relative missing project reports the resolved Windows path, exit 6. | D |
| 15 | `.dproj`, `.dpr`, `.groupproj` inputs | `.dproj`, and `.dpr`/`.dpk` with sibling `.dproj`; `.groupproj` was never a guaranteed contract (SKILL.md). | D |
| 16 | BDS root lookup under `C:\Program Files (x86)\Embarcadero\{Studio,RAD Studio}\<ver>` and `rsvars.bat` call | `TryLoadRsVars` and `ResolveBdsRoot` via `Dak.Registry` and `Dak.RsVars`, plus `--rsvars` and `DAK_RSVARS` override. Superset (registry based). | E |
| 17 | PATH truncation above 6000 characters before `rsvars.bat` | The rsvars environment block is built and passed explicitly to the child (`ToEnvironmentBlock`); the inherited PATH length is irrelevant. | E |
| 18 | MSBuild discovery: BDS `msbuild.exe`, `vswhere`, `Framework64`, `Framework` | BDS / PATH / registry / `Framework64` / `Framework` (`TryFindMsBuild`). `vswhere` dropped: the BDS MSBuild is always present when rsvars resolves. | D |
| 19 | `environment.proj` properties forwarded as `/p:` (`build-delphi-envprops.ps1`) | `ApplyEnvironmentProjProps`; values are redacted in verbose traces. Covers the MSB1006 fix in the candidate. | E |
| 20 | Fixed MSBuild switches (`DCC_Quiet`, `DCC_UseMSBuildExternally`, response and command file, `/m`, `/nologo`, `/v:m`) | Built by the runner's property list; `Test.Build` proves a real MSBuild failure and success. | E |
| 21 | madExcept: probe (.mes, dpr/dproj name match, define for config/platform), patch tool resolution (`[MadExcept].Path`, PATH, Program Files, ProgramFiles(x86), ProgramData), patch run, failure messages | `BuildProjectInfo` reasons (`mes-missing`, `name-mismatch`, `define-missing`, `mes-disabled`, `enabled`), `ResolveMadExceptPatchExe`, patch step and failure messages (`cMadExcept*`). bin\dak.ini comment updated. No native DUnitX test runs madExceptPatch.exe (not installed here); source parity only. | E |
| 22 | Output freshness: pre/post timestamps, `output_locked`, `output_missing` | `cStatusOutputLocked`, `cStatusOutputMissing`, `fOutputStale`; `BuildReportsTheExecutableTheCompilerEmitted`. | E |
| 23 | Error detection fallbacks (`MSB4104`, "used by another process", localized text) | Nonzero MSBuild exit is authoritative; errors come from the error log. The localized-string scan is dropped. | D |
| 24 | Exit codes 0 / 1 / 2 | 0 success; other values are DAK codes (`Dak.ExitCodes`: 2 invalid args, 3 invalid project, 6 tool failure) or the MSBuild code. Scripted callers must test nonzero, not 1. Noted in CHANGELOG. | D |
| 25 | Logs. Base 391871d: every run creates `<log root>\run-<RUN_ID>\` holding `msbuild-full.log`, `msbuild-out.log`, `msbuild-errors.log` and, for a madExcept patch, `madexcept-patch.log`. Log root defaults to `<project dir>\.dak\<ProjectName>\build`; `-log-dir <path>` replaces it (relative paths resolve against the project directory). Without `-keep-logs` the wrapper deletes the log files and removes the empty run directory at exit, so nothing survives; with `-keep-logs` everything stays and it prints `(Logs kept due to -keep-logs)` (not in `-json` mode). | Native: unique temp files, deleted after the run, unless `--keep-logs` or `--log-dir <path>` keeps `stdout.log` and `stderr.log` in `<log root>\run-<guid>\` (root defaults to `<project dir>\.dak\<ProjectName>\build`; relative `--log-dir` resolves against the project directory), or `DAK_BUILD_DIAGNOSTICS_DIR` names a directory. No full or errors-only log (not required). | **E** (equivalent in DAK (DAK-379: --keep-logs/--log-dir)) |
| 26 | JSON emitter (`build-delphi-emit-json.ps1`) | Native `--json` summary. | E |
| 27 | Settings reader (`build-delphi-read-settings.ps1`) | `Dak.Settings` cascading `dak.ini`. | E |
| 28 | `build-delphi.sh`: `wslpath -w` on the first project argument, `cmd.exe /C build-delphi.bat` | Not needed. DAK accepts `/mnt/<drive>/...` and relative paths (verified, see below); other Linux paths are rejected with exit 6. No launcher is kept. | D |
| 29 | Environment variables `DAK_BUILD_SH` (skill only) | Removed from `dak-build` and `dak-dfm-check` skills. `DAK_EXE` stays. | D |

Counts: 29 rows; E = 19, D = 10, G = 0.

Row 25 is delivered by DAK-379's `--keep-logs`/`--log-dir`.
The six helper scripts `scripts\build-delphi-*.ps1` (emit-json, envprops,
madexcept-probe, madexcept-resolve-tool, read-settings, run-msbuild) were deleted
with the wrapper; no tracked file other than the wrapper called them.
`SBuildBatMissing` in `src\dak.messages.pas` was removed by DAK-379.

WSL probe (candidate, 2026-09-30): from `wsl.exe`, with cwd `/mnt/f/...`,
`DelphiAIKit.exe build --project /mnt/f/projects/MaxLogic/DelphiAiKit/tests/DelphiAIKit.Tests.dproj --delphi 23.0 --config Debug --platform Win64 --ai`
exited 0 (`SUCCESS. Warnings: 4`, about 20 s). `/home/x/a.dproj` is rejected
(`Unsupported Linux path format`, exit 6). A relative missing project reports
its resolved Windows path (exit 6).
