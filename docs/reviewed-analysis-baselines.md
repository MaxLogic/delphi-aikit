# Reviewed analysis baselines, September 10

T-212 now has separate reviewed baselines for the current DAK and
DelphiSemantics reports. All currently gated finding occurrences have individual
source reviews; their complete rows, source hashes and duplicate counts match.

| Project | FixInsight warnings | PAL strong findings |
| --- | ---: | ---: |
| DAK | 11 | 17 |
| DelphiSemantics tests | 1 | 8 |

These 37 observations include explained behavior and visible cleanup debt.
Follow-up tasks retain the unresolved Foundation risks, including T-295,
T-296 and T-297. The new timestamp test's low-word conversion is intentional:
it stores the other word separately and verifies the reconstructed native
timestamp. The full reports retain advisory findings and all raw evidence.

The local baselines are under
`projects/.dak/DelphiAIKit/goal-current/t212-reviewed-baselines/` as `dak.json`
and `sem.json`. They were prepared from the completed native reports and checked
by replaying report processing. This establishes baseline preparation and
report consistency; it is not an independent native stability run. Historical
reports and baseline bytes remain preserved.

The subsequent native Win64/Release runs passed both policy gates against those
explicit baselines, with no new gated findings. DAK completed analysis in
282.104 s and DelphiSemantics in 165.085 s; both report verification steps
passed. PAL was 9.21.4.0 and FixInsight was 2026.01beta. These results certify
the retained DAK executable and source inputs recorded in the proof, with DAK
revision `e7a6b6e`. Baseline compatibility also includes the DAK revision; a
later documentation-only commit still needs that compatibility difference
reviewed before a new comparison.

After the historical test IDs were migrated for the isolated fixture, full
Semantics native analysis passed again in 165.633 s against the same baseline.
The three touched-file PAL observations remained structurally identical.

Future comparison must set `DAK_BASELINE` explicitly to the appropriate reviewed
file, with `DAK_UPDATE_BASELINE=0` and `DAK_GATE=1`. A new output directory must
not silently create its own acceptance baseline. Changed source hashes, rows,
ownership, multiplicity or compiler/analyzer context require a new review.

The external `order_access_cli` baseline remains pending. T-293 records PAL
observations that appear or disappear on unchanged input. The existing
individual reviews and raw reports remain available; missing observations
are not counted as corrected. A corrected licensed/vendor PAL build or useful
support guidance is needed before retrying that acceptance proof.

Routine FixInsight analysis excludes the entire verified FlexCel library and
retains compiler context and owned caller coverage. T-225's raw packed-include
parser issue remains separate. Retry its unexcluded fixture after a relevant
FixInsight version change; preserve the workaround until correction is shown.
Production projects and shared/vendor sources remain read-only. External
analysis uses recorded DAK-local snapshots and DAK-owned output paths.

Evidence under `projects/.dak/DelphiAIKit/goal-current/`:

- `t209-identity-migration-proof.json`: post-migration Semantics native policy
  and test verification.
- `t212-maintained-final-proof.json`: subsequent native comparisons, unchanged
  baselines and input hashes.
- `t212-maintained-reviewed-baselines-proof.json`: preparation, replay checks
  and historical-file hashes.
- `t212-t313-maintained-matching.json`: all 37 complete finding occurrences,
  individual explanations, source hashes and follow-up links.
- `t212-individual-review-index.json`: the earlier 252 source reviews,
  including external findings and retained debt.

T-212 remains open until its external stability and final acceptance gates pass.

## September 11 configuration review

Fresh Win64/Release DAK and DelphiSemantics analysis under
`CompleteParsing=1` retains all 37 previously reviewed gated occurrences,
including complete rows, multiplicity and source hashes. Both analyzers
complete, ownership resolves with no unknown findings, and reports verify.
The original policy comparisons fail solely on the baseline's older DAK Git
revision. The mapped source revision differs from the current candidate only
in documentation; compiler, analyzer and ownership compatibility fields match.
The effective PAL.INI is also hashed separately in the retained input manifest.

The fresh reports differ from the retained reports by 16 advisory occurrences
across the two projects.
Each has a retained source review. Added reports concern initialized records
passed through Windows APIs or callbacks, and a system-time record populated
before conversion. Removed reports concern atomic counters that are read and
an input array consumed by sorting. No gated finding was added or removed, and
the advisory reports remain visible.

Separate compatibility copies preserve every original baseline finding and
update only compatibility metadata. Report-processing replays against these
copies pass both policy gates. These are reviewed replays of the fresh native
reports, not additional independent analyzer runs. Historical baselines and
the initially failed comparisons are preserved.

Evidence is under
`projects/.dak/DelphiAIKit/goal-current/pal-acceptance-20260911/`:
`maintained-proof.json`, `maintained-review.json`, the two
`reviewed-*-compatibility.json` copies, and `maintained-*-reviewed-replay/`.
DAK analysis took 269.17 s and DelphiSemantics 167.10 s.

T-293 still reproduces 19/59 BSON cast findings with either complete-parsing
setting on an unchanged isolated snapshot. The external baseline and overall
T-212 final gate therefore remain blocked. The full build, test and performance
certification was not repeated for these documentation and diagnostic changes;
this checkpoint does not claim final goal completion.
