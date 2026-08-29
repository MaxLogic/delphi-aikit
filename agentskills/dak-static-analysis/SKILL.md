---
name: dak-static-analysis
description: Run cadence-aware Delphi static analysis through DelphiAIKit wrappers, using project-context PAL for touched units, deliberate project analysis for maintained codebases, and advisory delta-oriented analysis for legacy applications, then triage findings and apply safe verified fixes.
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
the Windows wrappers directly. Use WSL wrappers only when the target repository
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
- If `DAK_EXE` is unset, wrappers fall back to Windows `PATH` (`where DelphiAIKit.exe`), then repo-local `bin/DelphiAIKit.exe`.

Analyzer toggles:
- `DAK_PASCAL_ANALYZER`: default `true` (project and unit wrappers). Set `false` only when PAL must be skipped.
- `DAK_FIXINSIGHT`: default `true` for project wrapper.

Common overrides:
- `DAK_DELPHI`, `DAK_PLATFORM`, `DAK_CONFIG`
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

Wrappers call DAK only:
- `DelphiAIKit.exe analyze --project ...`
- `DelphiAIKit.exe analyze --unit ...`

Path note:
- Direct DAK calls accept Linux-style absolute paths only in `/mnt/<drive>/...` form for `--project` and `--unit` when run from WSL.
- Other Linux absolute paths (for example `/home/...`) are rejected with a clear error.
- Wrapper scripts with `wslpath` conversion remain the canonical safe route.

We do not call `FixInsightCL` or `PALCMD` directly in normal workflow.

Wrapper defaults are project-local:
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
`python "<skill-root>/postprocess.py" --verify <output>`.
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
   `<DAK_OUT>/triage.md` (or the wrapper's project-local default when
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
- WSL path issues: only in a WSL-authorized repository, pass Linux paths to
  shell scripts; wrappers convert with `wslpath`. Otherwise switch to the
  Windows wrapper instead of adding another path bridge.
- `cmd.exe` quoting issues: prefer wrapper scripts over manual `cmd.exe` command construction.

## Local References

- Setup and environment: [SETUP.md](SETUP.md)
- Tooling notes: [references/tooling.md](references/tooling.md)
- Triage heuristics: [references/triage.md](references/triage.md)
