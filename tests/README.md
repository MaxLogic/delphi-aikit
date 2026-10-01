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

Timing note:

- The full DUnitX suite is not a fast smoke test. On Pawel's machine it took about 3.5 minutes on 2026-04-07 (`153` tests, all green).
- `Test.FixInsight.TFixInsightTests` accounts for most of that time. It runs FixInsight analysis three times (`base`, `exclude`, `ignore-ids`) and took about 190-200 seconds on 2026-04-07.
- Avoid using a 120s or 240s watchdog for the full suite or the FixInsight fixture; those bounds are short enough to produce false "hang" diagnoses.
- `run-dunitx.ps1 -TimeoutSeconds` defaults to 14400; `0` means no limit (the run waits for the test process to exit) and a negative value is a parameter error. `summary.json` records `timeoutSeconds` (0 = no limit) and `timedOut`.
- Size automation timeouts from current runs. On 2026-09-10 the five-test FixInsight fixture passed in 666 seconds; a full 661-test run took 1003 seconds before reporting path-length failures. Allow at least `1800s` for the full suite and `900s` for the FixInsight fixture on this machine, and inspect process progress before diagnosing a hang.

Keep `DAK_TEST_OUTPUT_ROOT` unset for the full suite unless an alternative root
has been checked against the deepest fixtures. The runner defaults to
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
