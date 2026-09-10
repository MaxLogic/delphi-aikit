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
