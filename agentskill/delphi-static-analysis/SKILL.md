---
name: delphi-static-analysis
description: Run Delphi static analysis with TMS FixInsight (FixInsightCL) and Peganza Pascal Analyzer (PALCMD) via DelphiConfigResolver (DCR), normalize reports, triage findings, and apply conservative, verified fixes.
license: internal
compatibility: "Requires Windows/WSL, DelphiConfigResolver.exe, FixInsightCL, PALCMD; may require commercial licenses"
metadata:
  tags: [delphi, static-analysis]
  version: "1.0"
disable-model-invocation: true
allowed-tools:
  - read
  - rg
  - shell
---

# Delphi Static Analysis (FixInsight + Pascal Analyzer)

Goal: give an AI a repeatable workflow to (1) run TMS FixInsightCL + Peganza PALCMD against a Delphi codebase using our `DelphiConfigResolver` (DCR), (2) store reports in a predictable folder tree, (3) triage results, and (4) apply safe fixes with build/test verification.

## Quick start

Generate reports for a project:

- Windows:
  - `agentskill\\delphi-static-analysis\\analyze.bat path\\to\\MyProject.dproj`
- WSL:
  - `./agentskill/delphi-static-analysis/analyze.sh /mnt/c/path/to/MyProject.dproj`

Generate Pascal Analyzer reports for a single unit:

- Windows:
  - `agentskill\\delphi-static-analysis\\analyze-unit.bat path\\to\\Unit1.pas`
- WSL:
  - `./agentskill/delphi-static-analysis/analyze-unit.sh /mnt/c/path/to/Unit1.pas`

## Tooling model (thin)

We do not call FixInsightCL/PALCMD directly for project analysis. We call our resolver tool and let it:

- parse the `.dproj` and resolve macros/search paths/defines consistently
- discover external tools (FixInsightCL, PALCMD) and run them via CreateProcess
- post-process FixInsight reports when filters are requested

Inputs/overrides are provided via environment variables (so `analyze.*` still takes exactly one argument).

Scripts delegate to the DCR subcommands:

- `DelphiConfigResolver.exe analyze-project ...`
- `DelphiConfigResolver.exe analyze-unit ...`

### DCR location

By default, scripts use:

- `bin/DelphiConfigResolver.exe`

Override with:

- `DCR_EXE=<path-to-DelphiConfigResolver.exe>`

### Common overrides

- `DCR_EXCLUDE_PATH_MASKS="*\\lib\\*;*\\3rdparty\\*"` (forwarded to `--exclude-path-masks`)
- `DCR_IGNORE_WARNING_IDS="C101;C103;O802"` (forwarded to `--ignore-warning-ids`)
- FixInsight default output is **TXT only**. Opt in to more with `DCR_FI_FORMATS="txt,csv"` or `DCR_FI_FORMATS="all"`.
- Optional overrides: `DCR_OUT`, `DCR_PAL`, `DCR_CLEAN`, `DCR_WRITE_SUMMARY`

For the full list of supported environment variables and tool-specific gotchas, see `references/tooling.md`.

## Output tree (stable)

Scripts create:

```
_analysis/{projectName}/
  fixinsight/
    fixinsight.txt
    *.log
  pascal-analyzer/
    <ProjectName>/             (raw PALCMD XML output; many reports)
      *.xml
    pascal-analyzer.log
    pal-findings.md            (optional; normalized actionable surface when available)
    pal-hotspots.md            (optional)
    pal-findings.jsonl         (optional)
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
- If `pal-findings.md` exists, use it; only open raw XML if we still need detail.

## Pascal Analyzer XML (read selectively)

PALCMD can generate dozens of XML reports per run. Most are inventories/metrics (identifiers, call trees, cross-ref, etc.) and are not a good first-pass triage surface.

Default triage flow:

- Prefer `summary.md` (counts + quick context).
- If `pal-findings.md` exists, use it instead of opening raw XML.
- Otherwise, open only the finding-like XML reports we care about first (Warnings/Strong Warnings/Optimization, and Exception if non-empty) and treat Complexity/Module Totals as refactor/hotspot-only.

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

1. Run `analyze.*` to produce baseline reports and `summary.md`.
2. Identify top 3-5 high-signal issues to fix (prefer highest severity + highest confidence).
3. Make a small patch.
4. Build + run tests.
5. Re-run `analyze.*` and confirm the warning count drops (or at least does not spike).
6. Repeat.

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
- FixInsight TXT output present under `_analysis/<project>/fixinsight/` (or other formats if `DCR_FI_FORMATS` is set).
- Pascal Analyzer outputs present under `_analysis/<project>/pascal-analyzer/`.

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
