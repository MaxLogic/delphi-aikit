# Semantic refactoring performance, 2026-09-07

The measurements below are historical. The DAK executable was built for Win64,
but the benchmark calls omitted target options and used the CLI's Win32/Release
semantic defaults. They are not explicit Win64 planning measurements. The
separate 633-statement API probe inherited Release/Linux64 from its project.
T-209 must establish new API/CLI plan parity in one explicit context before its
next timing batches.

The T-253/T-254/T-255 follow-up meets the tighter cold and warm budgets on the
retained maxTdb workload. Measurements use Delphi 12, Release Win64 DAK, the
same Windows machine and the existing benchmark harness. Builds, tests and
analyzers ran outside the timing batches. The timed interval includes source
snapshot preparation; report processing and between-run cache cleanup are outside it.

| Workflow | Cache | Samples | Previous T-247 median | Current median | Current p95 | Median budget |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Remove-with plan | Cold | 5 | 26.365 s | 14.594 s | 14.905 s | 22 s |
| Remove-with plan | Warm | 10 | 11.950 s | 8.960 s | 9.249 s | 10 s |
| Rename dry-run | Cold | 5 | 72.848 s | 6.620 s | 7.064 s | 55 s |
| Rename dry-run | Warm | 10 | 1.152 s | 1.192 s | 1.281 s | 2 s |

Warm rename also passes its 2.5-second p95 budget. These are measurements of this
workload on this machine, not latency guarantees for arbitrary projects.

## What changed

- **T-253:** source coordinate mapping and reconciliation share a private,
  operation-local line index. The previous reference-only index became the
  common implementation for declarations, routines, members, locals and references.
  Repeated scans of source prefixes become one linear indexing pass plus
  logarithmic lookups. UTF-16 offsets, CRLF/LF boundaries, section precedence,
  original-coordinate validation and fallback ordering remain unchanged.
- **T-254:** a completely empty snapshot cache uses the existing whole-project
  builder. Previously each unit rebuilt the project reference-target lookup:
  59 builds consumed 55.498 seconds in the diagnostic run. Full hits and partial
  invalidation keep their existing paths; cache formats and public APIs are unchanged.
- **T-255:** each binding operation indexes interface-declaration candidates once
  in the existing member-index owner. Requested names receive cached candidate
  model arrays. The unchanged resolver still decides precedence and ambiguity.
  Candidate order and duplicates remain intact; complex names and other contexts
  use the original path. The index is released with the operation. The diagnostic
  baseline made 5,422 indexed lookups for 968 names, spending 5.167 seconds there.

No shared mutable cache, parallel execution or public API change was introduced.
Temporary probes were removed before the final measurements. Fresh performance
RED checks were 29.304 seconds for cold remove-with (22-second target),
65.213 seconds for cold rename (55-second target), and 15.971 seconds for warm
remove-with (10-second target). Retained characterization tests passed before
and after each optimization.

## Correctness and evidence

All 30 measured outputs match their complete ordered pre-optimization projections.
The coverage correction T-256 is separate: it adds nine provable replacements,
so the current plan contains 241 planned, 407 skipped and 19 covered statements
out of 667, with zero semantic DTO mismatches. All 232 earlier replacements are
unchanged. See [procedure parameter coverage](remove-with-parameter-coverage.md).
The previous T-247 timing column used 232 planned replacements; the current
measurements include the additional coverage. Rename still produces four
identical edits. No real project source was applied or modified.

The cache characterization requires real three-edit rename plans from uncached,
cold and warm contexts, then four identical edits after changing a consumer.
The owning ProjectSession suite also checks partial-cache semantic fact equality,
cross-unit targets, include changes and full-hit reuse. The binding tests cover
local/member precedence, duplicate candidates, complex selectors, missing names,
and changed declarations in subsequent operations.

For the T-209 recheck, run the harness from DelphiSemantics with an explicit
semantic context. T-275 adds optional `-Platform`, `-Config`, and `-DelphiVersion`
parameters shared by warmup, measured calls and `-List`. Omitting them preserves
the existing CLI defaults. List prints complete commands for each selected
workflow/cache mode without creating benchmark output. Existing positional
parameters retain their order.

First verify complete ordered API/CLI plans against the same Win64/Release/23.0
context. Then run two independent timing batches, with no concurrent builds,
tests or analyzers:

```powershell
$fixture = 'F:/projects/MaxLogic/DelphiAiKit/tests/fixtures/test-projects/maxTdb/src/maxtdb.dproj'
$dak = 'F:/projects/MaxLogic/DelphiAiKit/bin/DelphiAIKit.exe'
$proof = 'F:/projects/MaxLogic/DelphiAiKit/tests/fixtures/test-projects/maxTdb/src/.dak/maxtdb/t209-' +
  (Get-Date -Format 'yyyyMMdd-HHmmss')
$common = @{
  DakExe = $dak
  Project = $fixture
  Workflow = @('remove-with-plan-all', 'rename-dry-run-allfiles')
  Platform = 'Win64'
  Config = 'Release'
  DelphiVersion = '23.0'
  NoBaselineCopy = $true
}
foreach ($batch in @('batch-1', 'batch-2')) {
  & ./scripts/benchmark-maxtdb-semantic-workflows.ps1 @common `
    -CacheMode cold -Repeat 5 -OutputDir "$proof/$batch/cold"
  if ($LASTEXITCODE -ne 0) { throw "Cold benchmark failed: $batch" }
  & ./scripts/benchmark-maxtdb-semantic-workflows.ps1 @common `
    -CacheMode warm -Repeat 10 -OutputDir "$proof/$batch/warm"
  if ($LASTEXITCODE -ne 0) { throw "Warm benchmark failed: $batch" }
  python F:/projects/MaxLogic/DelphiAiKit/tests/scripts/verify-semantic-budgets.py `
    "$proof/$batch/cold/baseline.json" "$proof/$batch/warm/baseline.json"
  if ($LASTEXITCODE -ne 0) { throw "Semantic budgets failed: $batch" }
}
```

These commands define the pending certification. No new timings or Win64 plan
parity are claimed by the harness change.

Historical benchmark outputs are under
`F:/projects/OEC/TE5/maxTdb/.dak/DelphiAIKit-fixture/src/.dak/maxtdb/t250-t256/`,
in the `final-cold/` and `final-warm/` folders. DAK's
`projects/.dak/DelphiAIKit/t250-t256/` retains the RED/GREEN logs, profiles,
all-plan comparison script, input hashes, build warning audit and final test logs.
`final2-*` build/test/analysis artifacts contain the final constructor cleanup;
earlier `final-*` test/analysis files are intermediate proof. The final timing
folders and manifests use that rebuilt candidate.

These tasks do not close T-209 historical MaxTdbProof certification. Its separate
pre-change diagnostic baseline has 129 failures among 203 tests and is excluded
by the pre-existing standard-suite category policy. The changed SetBit expectation
was updated and passed separately. T-257 records the separately discovered
unsupported inline `var`/`const` section declaration shape; the cache fixture now
uses a multiline declaration and explicitly rejects blocked rename plans.

## Historical T-247 measurements

The Release Win64 maxTdb cold plan median fell from 57.731 to 26.365 seconds
without changing the plan. The 42-second budget now passes.

### Change

Two repeated scans in `DelphiSemantics.Model.Coordinates` accounted for much
of the extraction cost:

- Reference mapping rebuilt source section boundaries for every reference.
  It now computes them once per call.
- Reference reconciliation repeatedly scanned source prefixes to recover line
  and column positions, both for known references and fallback token candidates.
  It now builds a local array of line starts and uses binary search.
  This replaces a source-prefix scan per lookup with linear preprocessing
  followed by logarithmic lookups over the line count.

The index lives only for the reconciliation call. Public APIs, cache formats,
section precedence, newline handling, fallback selection, and edit ordering
remain unchanged. No shared cache or parallel execution was added.

A temporary extraction probe attributed 20.133 seconds to reference
reconciliation and 6.513 seconds to reference mapping after the section change.
The probe was removed before acceptance measurements. Further optimization of
mapping was deferred because the measured result meets the budget.

### Measurements

Same Windows machine, Delphi 12, Release Win64 DAK, real maxTdb proof fixture,
and existing benchmark harness. Cold runs clear the workflow cache; warm runs
prime it first. Builds, tests, and analyzers were serialized outside timing runs.
The harness timing includes its source-snapshot preparation.

| Workflow | Cache | Samples | Before median | After median | After p95 | Median budget |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Remove-with plan | Cold | 5 | 57.731 s | 26.365 s | 27.607 s | 42 s |
| Remove-with plan | Warm | 10 | 11.873 s | 11.950 s | 14.718 s | 15.9 s |
| Rename dry-run | Cold | 5 | 86.791 s | 72.848 s | 75.921 s | 128 s |
| Rename dry-run | Warm | 10 | 1.129 s | 1.152 s | 1.321 s | 2 s |

Warm rename also passes its 2.5-second p95 budget. Warm medians were slightly higher
than the retained baseline; this change targets cold extraction and does not establish a
warm-path improvement. Cold remove-with saved 31.366 seconds, about 54%.

The retained before batch was checked against current semantic source and
harness inputs. A fresh pre-change smoke reproduced 57.725 seconds. The
section change alone reached 52.667 seconds; the indexed version reached
27.0 seconds. The latter smoke has a wrong repository label from its invocation
directory, so the table uses the final batches run from DelphiSemantics.

### Correctness and reproduction

All 30 final executions succeeded with unchanged fixture source. Complete,
ordered plan and edit projections match the retained pre-change outputs:

- Remove-with: 667 statements, 232 planned, 416 skipped, 19 covered,
  and zero semantic DTO mismatches.
- Rename: four identical edits, zero reference reconciliation fallbacks,
  and no applied files.

The 48-test UnitModel fixture passed before and after the line index, including
a new characterization for mixed CRLF/LF, repeated names, multiline comments,
empty reference lists, and fallback end-of-source ranges. The real budget assertion was
RED at 57.725 seconds and GREEN for the final five-run median.

The complete semantic suite also exposed an uninitialized `Mutable` field in
rejected declaration records. Extraction now initializes the record before
assigning fields. The regression failed without that initializer; all 576
semantic tests pass with it. The table and all 30 output comparisons above
use the final build containing this correction.

Historical T-247 logs and manifests remain in DAK's `projects/.dak/DelphiAIKit/remove-with-performance-20260907/`; benchmark outputs remain in the fixture's `.dak/maxtdb/t247/verified-cold/` and `verified-warm/`.
