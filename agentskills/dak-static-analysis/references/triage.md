# Triage heuristics and suppression guidance

## Generated triage.md (shortlist)

Our `postprocess.py` emits `.dak/<ProjectName>/triage.md` as a prioritized shortlist (top 20 by default; override with `DAK_TRIAGE_TOP=<N>`). It is intentionally a *short* "what to fix next" view; full detail remains in `fi-findings.*` and `pal-findings.*` / raw PAL XML.

`summary.json` is the compact AI entry point. Read it first for analyzer
completeness, raw/actionable/ignored/external/advisory/unknown counts, active
policy, provenance, and artifact paths. Then open `triage-changed.md` or
`triage.md`; both are actionable views. `triage-changed.md` uses the captured
Git/SVN `changed_files`, matches normalized workspace-relative paths first,
and falls back to a unit name only when that name
identifies one source file.

Read `provenance.target` before interpreting a changed-file view. A complete
target includes `revision`, status, `source_inputs`, and `nested_roots`
capabilities. `unavailable` means the VCS command failed or was absent;
`fallback` means bounded filesystem inventory was used. Neither state is a
clean result, and either capability reduction is reported without making a
successful analyzer run fail.

Every normalized finding carries one `ownership` value: `project`, `repository`, `third_party`, or `unknown`. Classification uses the resolved source path before display-path fallback. PAL module-only rows resolve only when the exact project/PAL search-path context identifies one source file; ambiguous and unresolved modules remain `unknown`. Ownership totals in `summary.md`, `summary.json`, delta, trend, triage, history, and SARIF come from the normalized JSONL records.

Complete normalized evidence stays in `fixinsight/fi-findings.jsonl`,
`pascal-analyzer/pal-findings.jsonl`, and `static-analysis.full.sarif`.
Actionable SARIF is `static-analysis.sarif`. Ignored rows remain in raw
evidence, dependency groups are in `external-summary.md`, and advisory metrics
are in `metrics.md`. Open these full/non-actionable views for ownership
diagnosis, dependency drift, analyzer failure, or an explicit full audit.

Run `python postprocess.py --verify <analysis-output>` for a read-only
consistency check before consuming or retaining a report. It fails when
normalized totals, identities, ownership, projections, baseline/delta
evidence, or SARIF disagree, and when a passing gated report has stale or
incompatible policy/baseline fingerprints.

Optional: set `DAK_TRIAGE_SNIPPETS=1` to also emit `.dak/<ProjectName>/triage-snippets.md` with small, bounded source snippets for the top triage items. This is meant to speed up fixing without opening files manually; it will only include snippets for repo-local paths that exist on disk.

## FixInsight (signal first)

FixInsight reports rule IDs like `W502`, `O801`, `C101`.

Practical triage:

1. New owned strong warnings.
2. New owned correctness warnings.
3. Changed-file owned findings.
4. Existing owned maintainability and hygiene.
5. Advisory metrics and optimization hints.

Confidence:

- High when a finding is local and mechanically provable by the compiler (e.g., unused local variable).
- Medium when it changes control flow or resource lifetime (e.g., empty except/finally, missing inherited).
- Low when it is a design/style heuristic (e.g., long method).

## Pascal Analyzer (what to care about)

PALCMD produces multiple reports. Triage order:

1. "Strong Warnings": treat as highest priority.
2. `Warnings.xml`: likely defects, suspicious code, unused/uninitialized.
3. `Optimization.xml`: often safe but can be noisy; review for free wins.
4. `Complexity.xml`: style/maintainability; do in refactor batches.

`Exception.xml`, including the Exception Call Tree, remains raw diagnostic evidence for throw propagation. It is not an actionable finding source and does not enter JSONL, counts, gates, triage, or SARIF.

Normalization, `summary.json`, and SARIF are required outputs: their failure makes the wrapper fail. Source snippets are optional and remain best-effort.

## Suppressions and baselines (avoid churn)

The default checked ownership policy gates `project` and `repository`, reports
`third_party` separately, and fails on every `unknown` finding. A baseline is
not created or changed when infrastructure, ownership, or compatibility
validation fails.

Prefer fixing real issues over blanket suppression, but when we must suppress:

- Third-party noise needs ownership-aware actionable projection, not a path
  guess.
- For generated/vendor results that should not be reported, use the
  post-analysis path contract: `DAK_EXCLUDE_PATH_MASKS`,
  `--exclude-path-masks`, or `[ReportFilter].ExcludePathMasks`.
- For an audited noisy FixInsight rule, use `DAK_FI_IGNORE_RULES`,
  `--ignore-warning-ids`, or `[FixInsightIgnore].Warnings`.
- For an audited noisy PAL rule, use `DAK_PAL_IGNORE_RULES`,
  `--pal-ignore-rules`, or `[PascalAnalyzerIgnore].Rules`. Use a canonical PAL
  identity or an alias verified for the reported installed version.
- For local, intentional exceptions:
  - FixInsight supports inline suppression comments (see FixInsight manual).
  - Use one reviewed PAL marker with a reason, such as
    `end; //PALOFF reviewed exception: callback intentionally has no action`,
    then compile and rerun the installed PAL to prove exactly one intended
    finding disappears.

All report filters preserve raw JSONL/full SARIF and record ignored counts plus
policy provenance. They cannot hide `unknown` ownership.

Use PAL `/X` or `/XF` only when a dependency truly must not be analyzed:
`DAK_PAL_EXCLUDE_SEARCH_FOLDERS` / `--pa-exclude-search-folders` /
`[PascalAnalyzer].ExcludeSearchFolders`, or `DAK_PAL_EXCLUDE_FILES` /
`--pa-exclude-files` / `[PascalAnalyzer].ExcludeFiles`. These are explicit
coverage reductions, not denoising. A verified TMS exclusion removed 7,558
external rows but introduced eight owned caller-side warnings.

Metric-only findings such as method length, parameter count, nesting, and
complexity thresholds are advisory and non-gating by default. They normally
do not justify a rewrite; `[AnalysisPolicy].GateMetrics` is an explicit opt-in.
A lower total is not success unless analyzer completeness, owned deltas,
ownership, filter provenance, and coverage also agree.
