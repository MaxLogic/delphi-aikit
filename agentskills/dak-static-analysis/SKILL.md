---
name: dak-static-analysis
description: Run cadence-aware Delphi static analysis through DelphiAIKit.exe and its thin launchers, using project-context PAL for touched units, deliberate project analysis for maintained codebases, and advisory delta-oriented analysis for legacy applications, then triage findings and apply safe verified fixes.
license: internal
metadata:
  tags: [delphi, static-analysis]
allowed-tools:
  - read
  - rg
  - shell
---

# Delphi Static Analysis (DAK + FixInsight + PAL)

## Intent

Use this skill when we need repeatable static analysis on Delphi code, followed by conservative fixes and build/test verification.

Default policy:
- Project analysis: `FixInsight=true`, `PascalAnalyzer=true`.
- Unit analysis: `FixInsight=false`, `PascalAnalyzer=true`.
- PAL is a first-class analyzer and should be disabled only explicitly.
- A gated run checks `project` and `repository` findings, reports
  `third_party`, fails on `unknown`, and requires a compatible baseline
  fingerprint.
- Whether analysis is a hard gate or advisory evidence depends on the
  repository's maintenance profile described below.

## Third-party code in routine work

Exclude verified third-party libraries from routine analysis targets, cleanup
work, and acceptance findings. Start with changed owned units in their real
project context. Do not launch a whole dependency-tree audit for an ordinary
feature or bug fix. Shared libraries we maintain remain in scope; a `3rdParty`
folder name or a path outside the project is not enough to establish ownership.

Distinguish selecting work from supplying analyzer context. The default
`GateOwnership=project;repository` removes vendor findings from actionable
triage, but does not stop the analyzer reading dependency source. Retain the
declarations and contracts needed to check our calls. Do not remove search
paths or invent compiler defines to avoid vendor code.

If vendor parsing prevents a useful run, use the analyzer's supported input
exclusions in the affected project's `dak.ini`. For FixInsight, set
`[FixInsightCL].Ignore` to the verified failing `.pas` filenames or paths,
separated by semicolons; the CLI equivalent is `--fi-ignore`. Verify the exact
entries with the installed tool, preserve the real compiler context, and compare
our findings before and after. Ignoring an include file may not exclude the
containing unit. PAL input exclusions use the explicit `/X` and `/XF` settings
below; check for changed caller-side findings before adopting them.

DAK defaults `[FixInsightCL].ExcludeFlexCel` to `true`. For verified Smart Setup
FlexCel products on the resolved search/library paths, it adds recursive source
masks for the whole library, including units without a `FlexCel` name prefix.
The metadata and `Source/Core/FlexCel.Core.pas` marker establish the scope;
a similarly named folder alone does not. The status records the effective
ignore list and available FlexCel source roots, not proof of library consumption.
Other installation layouts still need verified project-local input exclusions.

For an explicit vendor diagnostic, use an isolated project's
`[FixInsightCL].ExcludeFlexCel=false` and remove manual FlexCel exclusions from
that diagnostic configuration. This setting only disables automatic masks.
Retry the raw packed-include case only after a newer FixInsight version is
available. Keep the routine workaround until an unexcluded correction is proved.

Record the excluded scope, reason, tool version, and remaining coverage. Keep
the upstream defect open and retest exclusions after tool updates. A successful
run with exclusions proves only the retained scope. Input exclusions are
different from report filters, which cannot repair a parser failure.

Reserve vendor-wide analysis for an explicit dependency audit, a maintained
fork change, or a diagnosis that requires it. For daily work, open the summary
and changed-file triage; do not review raw third-party rows by default.

## PAL implementation parsing default

For routine PAL analysis, set `CompleteParsing=1` in the effective PAL.INI's
`Parser` section. This is PAL's "Parse implementations for non-reported units" option.
It preserves dependency implementation context while keeping vendor reporting
exclusions in place. With PAL 9.21.4.0, disabling it produces false unused
receiver warnings for fields passed to `TInterlocked`.

DAK inherits PAL's configuration; it does not force this setting itself. Check
the effective INI during setup or after an analyzer/configuration change:
explicit `/I` first, otherwise PAL.INI beside PALCMD if present, otherwise the
user's `%APPDATA%\Peganza\Pascal Analyzer\PAL.INI`. An explicit PAP project may
have its own parser settings. Preserve unrelated settings and do not silently
edit global configuration without authorization. See [SETUP.md](SETUP.md).

Keep disabled/private configurations for deliberate vendor reproductions.
Record the effective INI hash with proof; a setting change invalidates affected
PAL comparisons and requires baseline review, not automatic replacement.

## Legacy application policy

Treat static analysis as advisory for an established legacy application when
repository guidance identifies it as such, or when verified evidence shows a
large inherited finding baseline, unsupported language constructs, or analyzer
limitations that prevent reliable traversal of the existing project. Do not
classify a project as legacy merely because the first analysis result is
inconvenient.

For a legacy application:

- Prefer touched-unit, changed-file, and baseline-delta evidence. Do not make a
  full-project FixInsight or PAL run a routine task, batch, or final hard gate.
- Report findings that are attributable to the current change and apply safe,
  in-scope improvements when practical. Treat remaining findings as
  recommendations unless the user or repository explicitly requires a
  reliable changed-code gate.
- Do not block an otherwise tested and compiling feature solely because an
  analyzer exits non-zero on inherited findings, cannot parse existing source,
  or cannot reach the touched unit through the legacy project graph. State
  clearly that analysis was advisory or incomplete; never call it passing.
- Do not broaden a focused feature into a repository-wide cleanup to obtain a
  clean report. Explain when comprehensive remediation is likely to require a
  dedicated, staged refactoring effort with its own tests and review.
- Reserve full-project analysis for an explicitly requested audit, a dedicated
  technical-debt initiative, or a separately scheduled release/maintenance
  lane. Preserve historical totals and parser/tool limitations as diagnostic
  context rather than feature acceptance criteria.

Builds, focused tests, DFM validation, and other applicable behavioral proof
remain authoritative. This exception changes the acceptance role of static
analysis; it does not permit suppressing findings, misclassifying owned code,
or claiming unsupported coverage.

## Cadence and candidate contract

- Run `doctor` on first use, after a tool/configuration change, or when
  discovery fails. Do not repeat it before every unchanged analysis.
- At task tier, analyze touched units with their project context. A
  context-free unit result is useful diagnosis but is not project-equivalent
  gate evidence when a `.dproj` exists.
- For maintained projects with a reliable baseline, run project-wide
  FixInsight and PAL at scheduled batch/final gates. For legacy applications,
  follow the advisory policy above instead of scheduling full analysis by
  default.
- Review and stabilize production changes before expensive project analysis.
  Review-driven fixes change the candidate and invalidate that evidence.
- Fingerprint source/manifests, project configuration, dependency revisions,
  compiler/analyzer versions, and analyzer options. Reuse a result only while
  those inputs match. Test, task-ledger, or documentation edits do not
  invalidate source-only analysis when they are not analyzer inputs.
- Compare changed-file/delta findings as well as totals. A lower total can still
  hide a new owned-code finding, and dependency/tool drift can change totals
  without a source regression.

## Run Commands

Choose the host from repository/user policy. For Windows-only repositories use
the Windows launchers directly. Use WSL launchers only when the target repository
permits WSL and path conversion is useful.

Resolve `<skill-root>` from the skill path supplied by the harness. It is the
directory containing this `SKILL.md`. Do not derive it from the current
repository or assume that the repository contains an `agentskills/` directory.
Project-local installations commonly expose this directory through
`.agents/skills/dak-static-analysis`; junction and symlink targets are equally
valid.

WSL (when authorized):
- Project doctor: `bash "<skill-root>/doctor.sh" /mnt/c/path/to/MyProject.dproj`
- Project analyze: `bash "<skill-root>/analyze.sh" /mnt/c/path/to/MyProject.dproj`
- Unit analyze with project context: `bash "<skill-root>/analyze-unit.sh" /mnt/c/path/to/Unit1.pas /mnt/c/path/to/MyProject.dproj`

Windows PowerShell:
- Project doctor: `& "<skill-root>\doctor.bat" "C:\path\to\MyProject.dproj"`
- Project analyze: `& "<skill-root>\analyze.bat" "C:\path\to\MyProject.dproj"`
- Unit analyze with project context: `& "<skill-root>\analyze-unit.bat" "C:\path\to\Unit1.pas" "C:\path\to\MyProject.dproj"`

Add `--workspace-root auto|git|svn|project|<fixed-root>` after the subject when
the automatic nearest Git/SVN boundary is not the intended workspace. The CLI
overrides `[Workspace].Root`; otherwise the closest ancestor selector wins,
with the executable `dak.ini` fallback. Unmanaged projects are supported.

## Environment Contract

Recommended baseline:
- `DAK_EXE`: absolute path to `DelphiAIKit.exe`.
- If `DAK_EXE` is unset, the launchers use `DelphiAIKit.exe` from Windows `PATH`
  (`where DelphiAIKit.exe`), then `bin/DelphiAIKit.exe` of the repository that
  contains this skill. They never search the analyzed workspace or the current
  directory.
- `DAK_DELPHI` (or `--delphi`): the BDS version, for example `23.0`. Project and
  unit analysis require it; there is no implicit default.

DAK reads the variables below itself, so direct `DelphiAIKit.exe` calls and the
launchers behave the same. A switch given on the command line wins.

Analyzer toggles:
- `DAK_PASCAL_ANALYZER`: default `true` for project and unit analysis. Set `false` only when PAL must be skipped.
- `DAK_FIXINSIGHT`: default `true` for project analysis.

Common overrides:
- `DAK_PLATFORM`, `DAK_CONFIG`
- `DAK_OUT`
- `DAK_RSVARS`, `DAK_ENVOPTIONS`
- `DAK_FI_FORMATS` (`txt|csv|xml|all`, default `txt`)
- `DAK_EXCLUDE_PATH_MASKS` -> `--exclude-path-masks` /
  `[ReportFilter].ExcludePathMasks`
- `DAK_FI_IGNORE_RULES` -> `--ignore-warning-ids` /
  `[FixInsightIgnore].Warnings`
- `DAK_PAL_IGNORE_RULES` -> `--pal-ignore-rules` /
  `[PascalAnalyzerIgnore].Rules`
- `DAK_PAL_EXCLUDE_SEARCH_FOLDERS` -> `--pa-exclude-search-folders` /
  `[PascalAnalyzer].ExcludeSearchFolders` (explicit PAL `/X`)
- `DAK_PAL_EXCLUDE_FILES` -> `--pa-exclude-files` /
  `[PascalAnalyzer].ExcludeFiles` (explicit PAL `/XF`)
- `DAK_IGNORE_WARNING_IDS` is a deprecated FixInsight-only alias merged with
  `DAK_FI_IGNORE_RULES`; it never applies to PAL.
- `PA_PATH`, `PA_ARGS`
- `FI_SETTINGS` or `FIXINSIGHT_SETTINGS`

Provenance is VCS-neutral. `summary.json` reports nullable revision/status and
changed-file data, `source_inputs`, nested roots, and `available`, `fallback`,
`unavailable`, or `not_applicable` capability states. Missing Git/SVN tooling
uses a bounded filesystem inventory and does not fail analysis.

Examples:
- Disable PAL for one WSL run: `DAK_PASCAL_ANALYZER=false bash "<skill-root>/analyze.sh" /mnt/c/path/to/MyProject.dproj`
- PAL only in WSL: `DAK_FIXINSIGHT=false bash "<skill-root>/analyze.sh" /mnt/c/path/to/MyProject.dproj`

## Execution Model

The launchers find DAK, forward their arguments and, under WSL, convert paths.
All analysis logic runs inside `DelphiAIKit.exe`:
- `analyze.* <project.dproj> [options]` runs
  `DelphiAIKit.exe analyze --project <project.dproj> [options]`.
- `analyze-unit.* <unit.pas> [project.dproj] [options]` runs
  `DelphiAIKit.exe analyze-unit --unit <unit.pas> [--project-context <project.dproj>] [options]`.
- `doctor.* [subject] [options]` runs `DelphiAIKit.exe analyze-doctor` with
  `--unit` for a `.pas` subject and `--project` otherwise.

Path note:
- Direct DAK calls accept Linux-style absolute paths only in `/mnt/<drive>/...` form for `--project` and `--unit` when run from WSL.
- Other Linux absolute paths (for example `/home/...`) are rejected with a clear error.
- The WSL launchers convert path arguments and path-valued variables with
  `wslpath` and share the analysis variables through `WSLENV`; they remain the
  safe route from WSL.

We do not call `FixInsightCL` or `PALCMD` directly in normal workflow.

Default output locations are project-local:
- Project: `.dak/<ProjectName>/`
- Unit: `.dak/_unit/<UnitName>/`

Agent-run policy:
- Never set `DAK_OUT` to `.agents/`; analyzer output is generated tool state, not memory.
- For a large or disposable run, set `DAK_OUT` to a unique directory under the OS temp root. Include the repository/project and run identity so concurrent runs cannot collide.
- Use project-local `.dak/` only when the reports or caches should survive for reuse in that checkout.
- At the end of a task or goal, retain the small evidence reports we actually need and remove verified disposable output trees.

PowerShell example:

```powershell
$env:DAK_OUT = Join-Path $env:TEMP ("dak\\MyProject\\analysis-{0}" -f $PID)
```

WSL example:

```bash
export DAK_OUT="${TMPDIR:-/tmp}/dak/MyProject/analysis-$$"
```

Primary artifacts:
- Actionable entry points: `summary.json`, `triage-changed.md`, `triage.md`,
  and `static-analysis.sarif`.
- Complete raw evidence: `fixinsight/fi-findings.jsonl`,
  `pascal-analyzer/pal-findings.jsonl`, and `static-analysis.full.sarif`.
- Compact non-actionable views: `external-summary.md` and `metrics.md`.
- Human/run evidence: `summary.md`, `run.log`, `delta.md`, `delta.json`,
  `trend.md`, and `baseline.json` (after the first compatible baseline run).

Before retaining a gated result, run
`DelphiAIKit.exe analyze-report --out <output> --verify`.
It is read-only and exits 3 when the output is rejected.
The check covers counts, ownership, SARIF/report parity, and passing-gate
compatibility. Do not update a baseline to work around an incompatibility;
rerun with the correct compiler/analyzer/policy context.

## Agent Workflow

1. Run `doctor` first for tool/path sanity.
2. At task tier run `analyze-unit` for touched units when it can cover the
   change. Run project analysis at scheduled batch/final gates for maintained
   projects, or when a shared analyzer/build boundary changes. For legacy
   applications, keep routine analysis focused and advisory unless a separate
   audit or repository policy explicitly asks for the full project.
3. Open `summary.json` first and confirm analyzer completeness, actionable
   ownership, ignored/external/advisory projections, filter provenance, and
   `unknown=0`. Then open `triage-changed.md` or `triage.md`. Inspect raw/full
   or external evidence only for ownership diagnosis, dependency drift,
   analyzer failure, or an explicit full audit.
4. Apply only low-risk fixes in small batches.
5. Verify through `$dak-build` in the execution domain selected by repository/
   user policy. Use its separate PowerShell or Bash command form; do not paste
   Bash variable syntax into PowerShell. For DelphiAiKit itself, use
   `--platform Win64`.
6. Re-run the affected analysis scope and confirm no regression in `delta.md` /
   gate output. Do not repeat an unchanged full-project analysis after every
   leaf edit.
7. Preserve only the summary, triage, baseline, or delta needed for the task record; clean disposable analyzer trees after the evidence is recorded.

After a coherent batch of Delphi source edits, run the shared `encodingfix-delphi-cleanup` source-hygiene check once before the final task gate. Do not duplicate it if another DAK workflow already ran the same check over the same files. Ordinary analysis must not silently rewrite source files.

## Report-Driven Fix Loop

1. Start with `<DAK_OUT>/summary.json`, then `<DAK_OUT>/triage-changed.md` or
   `<DAK_OUT>/triage.md` (or the project-local default when
   `DAK_OUT` is unset).
2. Investigate every non-zero `unknown` ownership count. Never suppress or
   relabel an unknown row as third-party merely to make a gate pass.
3. Apply the narrowest truthful layer from the filtering decision table below.
4. Prioritize: new owned strong warnings; new owned correctness warnings;
   changed-file owned findings; existing owned maintainability/hygiene;
   advisory metrics and optimization hints.
5. Use `delta.md` to confirm owned deltas without relying on total reduction.
   Analyzer completeness, ownership, filter provenance, and coverage must also
   agree. A quieter report is not proof of improvement.
   In legacy advisory mode, report the useful delta without converting
   inherited totals or parser failures into a feature gate.

## Filtering decision table

| Situation | Action |
| --- | --- |
| Third-party noise | Ownership-aware actionable projection; keep it summarized in `external-summary.md`. |
| Generated/vendor results that should not be reported | Post-analysis path filter via `DAK_EXCLUDE_PATH_MASKS`, `--exclude-path-masks`, or `[ReportFilter].ExcludePathMasks`. |
| Audited noisy rule across the repository | Analyzer-specific report rule filter: FixInsight uses `DAK_FI_IGNORE_RULES`, `--ignore-warning-ids`, or `[FixInsightIgnore].Warnings`; PAL uses `DAK_PAL_IGNORE_RULES`, `--pal-ignore-rules`, or `[PascalAnalyzerIgnore].Rules`. |
| Intentional exception at one location | Inline FixInsight suppression from its manual, or reviewed `PALOFF` with reason and a real PAL rerun. |
| Dependency must not be analyzed | Explicit PAL `/X` or `/XF` via the corresponding `DAK_PAL_EXCLUDE_*`, CLI, or `[PascalAnalyzer]` setting; report reduced coverage and caller-side risk. |

Path and rule filters change actionable projections only. Ignored findings stay
in normalized JSONL and `static-analysis.full.sarif`, with ignored counts and
active policy in `summary.json`. Ownership classification runs before policy,
so `unknown` remains fail-closed.

### Worked examples

- Third-party projection: the Accessibility Framework run retained 7,558 TMS
  rows in raw evidence, classified them `third_party`, summarized them in
  `external-summary.md`, and kept all 7,558 out of actionable triage.
- Repository-wide PAL rule: `DAK_PAL_IGNORE_RULES=WARN54` resolves only the
  installed-version-verified alias. Matching rows stay in raw JSONL/full SARIF,
  appear under ignored counts and policy provenance, and leave actionable
  triage/SARIF.
- Site-specific PAL exception:

  ```pascal
  end; //PALOFF reviewed exception: callback intentionally has no action
  ```

  Compile the fixture and rerun PAL to prove exactly the intended finding
  disappears. Do not publish multi-code syntax without separate installed-PAL
  proof.
- Explicit `/X`: the verified TMS exclusion removed 7,558 external rows but
  increased owned caller-side findings from 298 to 306: eight new
  out-parameter warnings caused by missing dependency contracts. Report this
  as reduced coverage, not improvement.

`/X` and `/XF` remove analysis input. Never add them merely to quiet a report.

Metric-only findings such as method length, parameter count, nesting, and
complexity thresholds are advisory and non-gating by default. They normally do
not justify a rewrite. `[AnalysisPolicy].GateMetrics` is an explicit,
repository-owned opt-in for selected canonical PAL metric identities.

## Safe Fix Rules

Allowed without extra design review:
- remove unused locals
- remove dead no-op statements
- narrow local-scope cleanups that do not alter public/protected API signatures

Require explicit review before change:
- signature changes (`const/var/out`, visibility, overloads)
- lifecycle/exception-flow rewrites
- large refactors driven only by metrics warnings

When a clean analyzer result would require any of these changes, propose a
separate refactoring effort instead of expanding the current feature.

## Troubleshooting

- PAL not found: set `PA_PATH` or configure `[PascalAnalyzer].Path` in `dak.ini`.
- FixInsight not found: configure `[FixInsightCL].Path` in `dak.ini` or install/discoverable path.
- DAK not found: set `DAK_EXE` or add `DelphiAIKit.exe` to Windows `PATH`.
- `--delphi` missing: set `DAK_DELPHI` or pass `--delphi <version>`.
- WSL path issues: only in a WSL-authorized repository, pass Linux paths to
  the shell launchers; they convert with `wslpath`. Otherwise switch to the
  Windows launcher instead of adding another path bridge.
- `cmd.exe` quoting issues: prefer the launchers over manual `cmd.exe` command construction.

## Local References

- Setup and environment: [SETUP.md](SETUP.md)
- Tooling notes: [references/tooling.md](references/tooling.md)
- Triage heuristics: [references/triage.md](references/triage.md)
