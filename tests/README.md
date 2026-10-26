# Tests

`tests\run.bat` forwards to the DUnitX runner. Build and run with
`build-and-run-tests.bat`, or build once and select focused fixtures below.
Resolver formats, analyzer execution, settings and report policy are tested in
Pascal; the old batch workflow is mapped in [migration coverage](modernization-coverage.md).

## Prereqs

- Build an isolated Win64 Debug candidate first with `build.bat` (which uses the
  known-good native host). `run.bat` requires `bin\Debug\DelphiAIKit.exe`, or an
  explicit `DAK_TEST_RESOLVER_EXE`; it never rebuilds or replaces the host.
- PowerShell 7 (`pwsh.exe`) for the batch forwarding entry point. The compact
  runner `run-dunitx.ps1` also runs under Windows PowerShell 5.1 (`powershell.exe -File`).
- FixInsightCL is installed and discoverable (PATH / registry / settings), or `DAK_ALLOW_FIXINSIGHT_SKIP=1` is set intentionally
- Pascal Analyzer is installed, or `DAK_ALLOW_PAL_SKIP=1` is set intentionally

## Run

From a Windows shell:

```bat
tests\run.bat
rem A focused selection from cmd.exe uses the colon form for a dash-prefixed value:
tests\run.bat -TestArguments:--run:Test.Utils
```

From WSL (runs via Windows `cmd.exe`):

```bash
/mnt/c/Windows/System32/cmd.exe /C tests\\run.bat
```

Or use the WSL wrapper:

```bash
./tests/run.sh
```

Runner logs are written under `tests\.dak\DelphiAIKit.Tests\test-runs\`.

## DUnitX suite (unit + integration)

The DUnitX test runner lives under `tests\` and exercises:

- build + resolver smoke checks
- FixInsight txt/xml/csv runs and filtering
- Pascal Analyzer runs and output validation

Build and run from a Windows shell:

```bat
bin\DelphiAIKit.exe build --project tests\DelphiAIKit.Tests.dproj --delphi 23.0 --config Debug --platform Win64 --ai
tests\bin\Debug\DelphiAIKit.Tests.exe
```

For compact agent output, replace the direct executable invocation with this
PowerShell command (it runs the existing binary without rebuilding):

```powershell
.\tests\run-dunitx.ps1
# Or select a focused fixture:
.\tests\run-dunitx.ps1 -TestArguments '--run:Test.Cli.TCliTests'
```

The wrapper prints status, found/passed/failed/errored/leaked/ignored counts,
bounded failure details and log paths. Complete stdout and stderr are retained
in a unique `tests\.dak\DelphiAIKit.Tests\test-runs\run-*` directory alongside
`summary.json`. Nonzero process exits are preserved; missing or empty counts,
failed, errored, leaked or ignored tests also yield a nonzero wrapper exit.
Verify binary freshness and expected test selection separately. The batch entry
point uses this same wrapper and preserves its exit code.

Missing FixInsightCL, PALCMD, or real DelphiLSP acceptance tooling fails by default. Set `DAK_ALLOW_FIXINSIGHT_SKIP=1`, `DAK_ALLOW_PAL_SKIP=1`, or `DAK_ALLOW_LSP_SKIP=1` only when that tool's tests are intentionally outside the run's scope.

## Shards and fast feedback

Build the Win64 Debug candidates once, then run the same binary through either gate:

```powershell
# Full batch/final gate: four isolated processes, default MaxTdbProof exclusion preserved.
.\tests\run-shards.ps1 -LogRoot <owned-proof-root> -OutputRoot <short-owned-output-root>
# Small synthetic fixtures: no real builds, LSP sessions or large corpora.
.\tests\run-dunitx.ps1 -TestArguments:--include:Fast
# Discover selection coverage by retaining XML in the serial comparison run.
.\tests\run-dunitx.ps1 -TestArguments:--xmlfile:<owned-proof-root>\serial.xml
.\tests\run-shards.ps1 -LogRoot <owned-proof-root> -OutputRoot <short-owned-output-root> -SerialSummary <serial-run>\summary.json
```

The shard wrapper requires PowerShell 7. Each child has independent TEMP/TMP,
DAK_TEST_OUTPUT_ROOT, a private migration bundle and synthetic Git clones. LSP
uses stdio; the suite has no configured fixed TCP test port to allocate.
Replay and Verify stay in one shard because they share synthetic report output
paths. Fixtures remain sequential within each process. `-ShardCount` defaults
to four; `-Run` accepts fixture/unit prefixes for a focused process-isolation check.

The plan uses the measured fixture durations in `scripts/fixture-durations.json`
(from the 2026-10-25 serial baseline), with longest groups assigned first. The
roster is enumerated from the actual test binary via `DAK_TEST_LIST_PATH`, using
DUnitX's registry and the same default exclusion filter without running tests.
Named fixtures and parameterized cases are included. Every run compares its XML
identities with this roster; missing, extra or duplicate cases fail even without
`-SerialSummary`. New fixtures use a small default weight; update their measured
weight after profiling. Every independent FixInsight case can move separately; its raw
reports case stays intact. Replay/Verify's weight includes measured relocation work.
Ordinary groups select whole fixtures so the DUnitX expression parser preserves
parameterized case names containing commas.

The baseline was 3,887 seconds under contention. The critical FixInsight case
alone took about 1,174 seconds. The current quiet-machine target is at most
`max(1200 seconds, measured critical-path case * 1.10)`. No case is dropped or
weakened to meet that target. The complete suite remains the batch/final gate.
Fast and Slow categories select routine versus integration work; Fast is a
curated subset, not an alternative full gate. MaxTdbProof remains opt-in.

`aggregate.json` retains all native/wrapper exits, combined footer/case counts,
every failing case, shutdown leak reports, timing and the binary hash. Missing or
empty evidence, duplicate case identities, failure/error/leak/ignored counts and
unexpected child exits fail the gate. NUnit case results are checked even if the
fixture says Success. `-SerialSummary` checks the binary hash and compares every
fixture/case identity and result; missing/extra/changed tests fail. Raw stdout,
stderr, XML, plan and argument files are retained per shard. The wrapper runs
all started shards to their own deadlines when one fails, including when its XML
is truncated or its summary cannot be parsed. Keep successful proof and remove only
verified owned scratch through the project's cleanup workflow after writers stop.

Migration inputs are provisioned by `scripts/prepare-migration-inputs.ps1`,
automatically from `run-dunitx.ps1` for full or Replay/Verify selections of the real
test executable. Fast and unrelated focused selections skip provisioning. It discovers the
main checkout through Git, copies the exact pinned seed/reference bundles and
clones the two synthetic repositories without shared objects/hardlinks. It never
links writable outputs to main or rewrites reference files. Seed subject roots
are relocated to the private clones. Comparisons normalize only the exact
canonical checkout, synthetic repository and output root prefixes, with suffix
boundaries; relative suffixes, findings, ordering, counts and ownership stay exact.
Durable negative controls reject suffix/finding changes and noncanonical roots.
Direct execution of the test binary needs `DAK_TEST_MIGRATION_ROOT` pointing to a
bundle created by this script; prefer the wrapper. Generated bundle inputs remain
with the run as replayable proof inputs, including on failure.

## Source areas and focused fixtures

| Source area | DUnitX selection (`--run:` prefix) |
| --- | --- |
| CLI, app dispatch, environment | `Test.Cli`, `Test.App`, `Test.AnalyzeEnvironment` |
| Build, compiler context, project XML | `Test.Build`, `Test.MsBuild`, `Test.DakWorkingPaths` |
| Process lifetime, timeout, crash handling | `Test.ExternalToolProcess`, `Test.CrashReporting`, `Test.Utils` |
| Diagnostics and source context | `Test.Diagnostics`, `Test.SourceContext` |
| Analysis workspace, inputs, provenance | `Test.NativeAnalysisWorkspace`, `Test.NativeAnalysisWorkspace.Provenance`, `Test.NativeAnalysisWorkspace.Command` |
| Doctor and discovery | `Test.NativeAnalysisDoctor` (including its Settings/Paths/Contracts/Remaining/PalHelp units) |
| Analysis execution/status | `Test.NativeAnalysisProject`, `Test.NativeAnalysisUnit`, `Test.AnalyzeStatus` |
| Report replay, verification and policy | `Test.NativeAnalysisReports.Replay`, `Test.NativeAnalysisReports.Verify`, `Test.NativeAnalysisPolicy` |
| Ownership, projections, controls | `Test.NativeAnalysisReports.Ownership`, `Test.NativeAnalysisReports.Projections`, `Test.NativeAnalysisReports.Controls`, `Test.NativeAnalysisReports.OwnershipControls` |
| JSON, Unicode, numbers, import | `Test.NativeAnalysisReports.JsonText`, `Test.NativeAnalysisReports.Unicode`, `Test.NativeAnalysisReports.Numeric`, `Test.NativeAnalysisReports.Import` |
| FixInsight/PAL normalization and real tools | `Test.FixInsight`, `Test.PascalAnalyzer`, `Test.PalFindingNormalize`, `Test.ReportPostProcess` |
| DFM inspection/validation | `Test.DfmInspect`, `Test.DfmCheck` |
| Semantic index, dependencies, globals, LSP | `Test.SymbolMap`, `Test.Deps`, `Test.GlobalVars`, `Test.Lsp`, `Test.DelphiSemanticsIntegration` |
| Refactor transactions, consistency, signature | `Test.Refactor`, `Test.Refactor.Preflight`, `Test.Refactor.Transaction`, `Test.Refactor.ApplyCli`, `Test.Consistency`, `Test.SignatureCommand` |
| Dead code CLI/apply | `Test.DeadCodeCli`, `Test.DeadCodeApplyCli` |
| Remove-with and root absence | `Test.RemoveWith`, `Test.RemoveWith.LongPath`, `Test.RootMemberAbsence`, `Test.RootMemberAbsenceContext` |

The Fast roster covers synthetic environment parsing, MSBuild XML parsing,
report projection/numeric/JSON/import rules, refactor preflight and relocation
controls and repository-marker validation. Use the owning fixture for a touched area outside that roster. Every
other fixture carries Slow, including the opt-in proprietary corpus fixtures.

Use a short owned `DAK_TEST_OUTPUT_ROOT` for isolated full-suite runs. Validate any alternative root against the deepest fixtures. The runner defaults to
`tests\temp\run-<PID>-<8 hex>` and isolates each run automatically. Each copied
project keeps its analysis and refactoring artifacts in its sibling
`.dak\<ProjectName>` directory, inside DAK.

The runner refuses to start, with exit code 78 and the root and limit on stderr,
when its run root exceeds 113 characters. Exit code 78 is distinct from DUnitX
failures (1), `run.bat`/`run.sh` setup errors (2), fixture child modes (3, 7) and
the `run-dunitx.ps1` timeout (124). The limit is the 259-character classic
Windows path (MAX_PATH - 1) less a 146-character reserve: the deepest path the
retained fixtures create below the run root, measured on 2026-10-01 after
DAK-385 shortened DAK's per-run folders, is 136 characters (a git submodule
object in a `Test.NativeAnalysisWorkspace` fixture), plus a 10-character margin.
The persistent `Test.SymbolMap` cache (126), an SVN working copy (124), and the
`Test.RemoveWith` and `Test.DfmCheck` run workspaces (122 each, down from 164 and
146) follow; `Test.Support` documents the inventory beside
`cRunRootFileReserve`. The check counts the PID as 10 digits (the widest
Windows PID), so the verdict does not depend on the PID: the run root
`\run-<PID>-<8 hex>` then adds 24 characters to `DAK_TEST_OUTPUT_ROOT`, and an
explicit root may have at most 89 characters. `ParallelTestRunsUseIndependentRoots`
gives its children the same output root as the parent run, so they pass the check
whenever the parent does, and the test removes the run roots and no-repo folders
its children leave. The default root under this repository
(`F:\projects\MaxLogic\DelphiAiKit`) counts as a 67-character run root.

Adding checkpoint names or using a longer harness root can exceed Windows path
limits after fixture, project and transaction directory names are appended.
Observed failures include DFM file creation, SQLite cache creation and
remove-with verification directories. A subsequent UTF-8 decoding error can be
secondary to a native error message written in the console code page. Preserve
the raw output and rerun the exact failed test with the default root before
changing source or assertions. Put checkpoint names in the outer proof log
filenames instead. `DAK_TEST_KEEP_TEMP=1` retains the isolated outputs for review.

## Useful env vars

- `DAK_PLATFORM` (default: `Win64`)
- `DAK_CONFIG` (default: `Release`)
- `DAK_DELPHI` (default: `23.0`)
- `DAK_TEST_RESOLVER_EXE` selects an already-built candidate for native and legacy tests.
- `RSVARS` (optional; passed as `--rsvars`)
- `ENVOPTIONS` (optional; passed as `--envoptions`)
- `PA_PATH` (optional; forwarded to `--pa-path` and/or `[PascalAnalyzer].Path`)
- `DAK_ALLOW_FIXINSIGHT_SKIP=1` explicitly skips FixInsight-backed DUnitX acceptance tests when FixInsightCL is unavailable.
- `DAK_ALLOW_PAL_SKIP=1` explicitly skips PALCMD-backed DUnitX and batch acceptance tests when PALCMD is unavailable.
- `DAK_ALLOW_LSP_SKIP=1` explicitly skips real DelphiLSP-backed DUnitX acceptance tests when DelphiLSP is unavailable.
- `DAK_MAXTDB_FIXTURE` points opt-in `MaxTdbProof` tests at an external local-only
  fixture. Never place that proprietary corpus inside the DAK checkout.
- `DAK_ALLOW_MISSING_PAL_FIXTURES=1` explicitly skips PAL fixture-backed
  normalization tests when `docs\sample-pal-reports` is unavailable.

The [native migration coverage map](modernization-coverage.md) records replaced
scripts and the remaining migration work.
