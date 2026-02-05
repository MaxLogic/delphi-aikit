---
name: delphi-static-analysis
description: Run Delphi static analysis with TMS FixInsight (FixInsightCL) and Peganza Pascal Analyzer (PALCMD) via DelphiAIKit (DAK), normalize reports, triage findings, and apply conservative, verified fixes.
license: internal
compatibility: "Requires Windows/WSL, DelphiAIKit.exe, FixInsightCL, PALCMD; may require commercial licenses"
metadata:
  tags: [delphi, static-analysis]
  version: "1.2"
disable-model-invocation: true
allowed-tools:
  - read
  - rg
  - shell
---

# Delphi Static Analysis (FixInsight + Pascal Analyzer)

Goal: give an AI a repeatable workflow to (1) run TMS FixInsightCL + Peganza PALCMD against a Delphi codebase using our `DelphiAIKit` (DAK), (2) store reports in a predictable folder tree, (3) triage results, and (4) apply safe fixes with build/test verification.

## Quick start

Generate reports for a project (FixInsight + Pascal Analyzer):

- Windows:
  - `agentskill\\delphi-static-analysis\\analyze.bat path\\to\\MyProject.dproj`
- WSL:
  - `DAK_PASCAL_ANALYZER=1 ./agentskill/delphi-static-analysis/analyze.sh /mnt/c/path/to/MyProject.dproj`

Preflight / environment check:

- Windows:
  - `agentskill\\delphi-static-analysis\\doctor.bat path\\to\\MyProject.dproj`
- WSL:
  - `./agentskill/delphi-static-analysis/doctor.sh /mnt/c/path/to/MyProject.dproj`

Generate Pascal Analyzer reports for a single unit:

- Windows:
  - `agentskill\\delphi-static-analysis\\analyze-unit.bat path\\to\\Unit1.pas`
- WSL:
  - `DAK_PASCAL_ANALYZER=1 ./agentskill/delphi-static-analysis/analyze-unit.sh /mnt/c/path/to/Unit1.pas`

## Tooling model (thin)

We do not call FixInsightCL/PALCMD directly for project analysis. We call our resolver tool and let it:

- parse the `.dproj` and resolve macros/search paths/defines consistently
- discover external tools (FixInsightCL, PALCMD) and run them via CreateProcess
- post-process FixInsight reports when filters are requested

Inputs/overrides are provided via environment variables (so `analyze.*` still takes exactly one argument).

Scripts delegate to the DAK subcommands:

- `DelphiAIKit.exe analyze --project ...`
- `DelphiAIKit.exe analyze --unit ...`

### DAK location

By default, scripts use:

- `bin/DelphiAIKit.exe`

Override with:

- `DAK_EXE=<path-to-DelphiAIKit.exe>`

### Common overrides

- `DAK_EXCLUDE_PATH_MASKS="*\\lib\\*;*\\3rdparty\\*"` (forwarded to `--exclude-path-masks`)
- `DAK_IGNORE_WARNING_IDS="C101;C103;O802"` (forwarded to `--ignore-warning-ids`)
- FixInsight default output is **TXT only**. Opt in to more with `DAK_FI_FORMATS="txt,csv"` or `DAK_FI_FORMATS="all"`.
- Optional overrides: `DAK_OUT`, `DAK_FIXINSIGHT`, `DAK_PASCAL_ANALYZER` (or legacy `DAK_PAL`), `DAK_CLEAN`,
  `DAK_WRITE_SUMMARY`

For the full list of supported environment variables and tool-specific gotchas, see `references/tooling.md`.

## Output tree (stable)

By default, scripts write analysis outputs under the analyzed project root:

- If we can discover a VCS root by searching up from the target (`.git` or `.svn`), we use that directory.
- Otherwise we use the directory containing the analyzed file (`*.dproj` / `*.pas`).
- If we detect a Git repo, we also ensure `_analysis/` is present in that repo’s `.gitignore`.

Scripts create:

```
_analysis/{projectName}/
  fixinsight/
    fixinsight.txt
    fi-findings.md            (normalized; greppable)
    fi-findings.jsonl         (normalized; machine-friendly)
    *.log
  pascal-analyzer/
    <ProjectName>/             (raw PALCMD XML output; many reports)
      *.xml
    pascal-analyzer.log
    pal-findings.md            (optional; normalized actionable surface when available)
    pal-hotspots.md            (optional)
    pal-findings.jsonl         (optional)
  baseline.json                (created on first run; used for deltas/gating)
  baseline.md                  (human baseline summary)
  delta.md                     (delta vs baseline)
  delta.json                   (machine delta vs baseline)
  triage.md                    (prioritized shortlist; top 20 by default)
  triage-changed.md            (when `DAK_SCOPE=changed`; filtered to Git-changed files)
  triage-snippets.md           (when `DAK_TRIAGE_SNIPPETS=1`; bounded source context for top triage items)
  history.jsonl                (per-run metrics snapshots; continuous monitoring)
  trend.md                     (recent history table + deltas)
  summary.md
  run.log
```

Unit runs create:

```
_analysis/_unit/{unitName}/
  pascal-analyzer/
    (PALCMD creates a report subfolder)
  summary.md
  run.log
```

## First-pass triage (always)

- Read `summary.md` first.
- Then read `triage.md` for a fix-oriented shortlist (top 20 by default).
- If `pal-findings.md` exists, use it; only open raw XML if we still need detail.

## Pascal Analyzer XML (read selectively)

PALCMD can generate dozens of XML reports per run. Most are inventories/metrics (identifiers, call trees, cross-ref, etc.) and are not a good first-pass triage surface.

Default triage flow:

- Prefer `summary.md` (counts + quick context).
- If `pal-findings.md` exists, use it instead of opening raw XML.
- Otherwise, open only the finding-like XML reports we care about first (Warnings/Strong Warnings/Optimization). Open `Exception.xml` only when it contains *finding-like* sections (ignore "Exception Call Tree" unless we explicitly need throw propagation). Treat Complexity/Module Totals as refactor/hotspot-only.

## Safe auto-fix policy (conservative)

We only auto-apply fixes when all are true:

- The change is local (single unit / single routine) and can be verified by compiling.
- The change does not change public API surface (no signature changes for public/protected methods, interface methods, published members).
- The change is trivially reversible and has clear intent.

Examples of usually safe fixes (still verify by compile/tests):

- Remove unused local variables, locals `uses` entries (only if the compiler confirms).
- Replace obviously redundant statements (e.g., `X := X;`) when no side effects exist.
- Delete empty `begin..end` blocks that are truly no-ops and not placeholders for conditional compilation.

Examples of do not auto-fix (plan and do in small PR-sized steps):

- Splitting long methods / reducing parameter counts (risk: subtle behavior changes).
- Adding/removing `const/var/out` in signatures (risk: interface/override/binary compatibility).
- Adding missing `inherited` calls (must understand lifecycle/contract first).
- Changing exception handling (empty except/finally) without understanding intent.

## Recommended workflow (repeatable)

1. Run `analyze.*` once to create `baseline.json` + baseline reports.
2. Identify top 3-5 high-signal issues to fix (prefer highest severity + highest confidence).
3. Make a small patch.
4. Build + run tests.
5. Re-run `analyze.*` and confirm the warning count drops (or at least does not spike).
6. Repeat.

## Baselines, deltas, and CI gating (optional)

By default:

- First run creates `_analysis/<project>/baseline.json`.
- Subsequent runs write `_analysis/<project>/delta.md` with counts + “new findings” vs the baseline.

Useful env vars (wrapper-level; not forwarded to DAK):

- `DAK_BASELINE=<path>` override baseline path (default: `_analysis/<project>/baseline.json`)
- `DAK_UPDATE_BASELINE=1` overwrite the baseline with the current run
- `DAK_TRIAGE_TOP=<N>` override triage shortlist cap (default: `20`)
- `DAK_SCOPE=changed` emit `triage-changed.md` filtered to Git-changed files
- `DAK_TRIAGE_SNIPPETS=1` emit `triage-snippets.md` with bounded source snippets for top triage items
- `DAK_TRIAGE_SNIPPET_CONTEXT=<N>` number of context lines around the finding line (default: `2`)
- `DAK_TRIAGE_SNIPPET_MAX_BYTES=<N>` truncate snippet output when exceeding this size (default: `200000`)
- `DAK_TREND_N=<N>` number of runs to show in `trend.md` (default: `20`)
- `DAK_GATE=1` (or `DAK_CI=1`) enable a conservative “don’t regress” gate
- Thresholds:
  - `DAK_MAX_NEW_PAL_STRONG=0` (default) fail if new PAL strong-warnings appear
  - `DAK_MAX_NEW_FI_W=0` (default) fail if new FixInsight `W*` codes appear
  - `DAK_MAX_PAL_WARNING_INCREASE=<N>` optional fail if PAL warnings increase by more than `N`
  - `DAK_MAX_FI_TOTAL_INCREASE=<N>` optional fail if FixInsight findings increase by more than `N`

## Reporting format (agent output)

- Keep the header line `Results (from _analysis/<Project>/summary.md):`.
- Extend it with a short “Top 5 critical warnings/errors to fix (ours)” list. If none are important, say so explicitly.
- Do **not** emit a `Notes emitted by the run:` section. Only mention warnings or errors.

## PAL suppression (inline comments)

- Suppress a single line: append `//PALOFF` at end-of-line. Extra text after the marker is ok.
  - Example: `DoSomethingRisky(); //PALOFF false positive here`
- Suppress an identifier: put `//PALOFF` on the declaration line of the identifier (var/field/const/interface).
- Suppress specific PAL sections: add section codes after the marker, separated by semicolons.
  - Example: `//PALOFF STWA;WARN1;OPTI8`
- This is per-line/per-identifier (not a block pragma).

## Verification hint for lifetime/concurrency findings

When PAL/FixInsight flags lifetime, ownership, or concurrency hazards (e.g., “bad pointer”, “dangling reference”, “race”), validate with a targeted DUnitX test that:

- uses a timeout guard (so deadlocks are caught),
- and optionally includes a short stress loop (hundreds/thousands of iterations) to reproduce timing‑sensitive defects.

Only accept a fix when the tests pass reliably before/after and the analysis findings drop or are justified.

## PAL false‑positive pattern: unaligned reads

If PAL flags “bad pointer” on unaligned reads used for hashing/compare, prefer making the code portable rather than ignoring:

- use `{$IFDEF CPUARM}` (or other strict‑alignment targets) to read via `Move` into a local scalar,
- keep the fast `PCardinal`/`PUInt64` path on x86/x64,
- add `//PALOFF` only on the intentionally unaligned x86/x64 line if needed.

## Example outputs (minimal)

### summary.md (snippet)

```
# Static analysis summary
Project: MyProject
FixInsight: 12 total (C=2 W=8 O=2)
Pascal Analyzer: 3 strong, 10 warnings, 5 optimization
Top issues:
1. [FixInsight] C101 Resource leak in Foo.pas:123 (High)
2. [PAL] Exception.xml Possible nil access in Bar.pas:45 (High)
```

### Top 5 triage format (example)

```
1) [High][FixInsight][C101] Foo.pas:123 - Resource leak. Confidence: High. Fix: wrap in try..finally.
2) [High][PAL][Exception] Bar.pas:45 - Possible nil deref. Confidence: Medium. Fix: add guard.
3) [Medium][FixInsight][W502] Baz.pas:78 - Empty except. Confidence: Medium. Fix: log or rethrow.
4) [Low][PAL][Optimization] Qux.pas:210 - Unused local. Confidence: High. Fix: remove.
5) [Low][FixInsight][O801] Quux.pas:19 - Long method. Confidence: Low. Fix: defer refactor.
```

### Successful run signals

- Exit code 0 from `analyze.*`.
- `_analysis/<project>/summary.md` and `run.log` exist.
- FixInsight TXT output present under `_analysis/<project>/fixinsight/` (or other formats if `DAK_FI_FORMATS` is set).
- Pascal Analyzer outputs present under `_analysis/<project>/pascal-analyzer/`.
- `_analysis/<project>/baseline.json` created on first run; `_analysis/<project>/delta.md` updated on subsequent runs.

## Failure modes (quick checklist)

- FixInsight output missing: ensure working directory is writable and output paths are absolute.
- FixInsight CLI hangs or pops UI: validate `--libpath` values and avoid invalid entries.
- PALCMD returns `99`: treat as an error; re-check input path and PAL configuration.
- WSL + cmd.exe quoting issues: use `wslpath -w` for Windows paths or run the batch from a Windows shell.

## Local references (loaded only when needed)

- Tooling details and CLI gotchas: [references/tooling.md](references/tooling.md)
- Triage heuristics and suppression guidance: [references/triage.md](references/triage.md)
- External sources and audit notes: [references/sources.md](references/sources.md)

Only browse the external URLs listed in `references/sources.md` if local references do not answer the question, or when we explicitly need re-verification.
