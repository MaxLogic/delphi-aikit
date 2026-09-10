# Vendor analyzer retry, 2026-09-08

The three PAL reports map to T-232, T-233 and T-234. The FixInsight packed-include reproducer belongs to T-225. All four remain open after fresh, serialized runs against unchanged isolated fixtures.

| Task | Installed analyzer result | Additional control |
| --- | --- | --- |
| T-232, `Inc/Dec(Int64, Int64)` | PAL 9.21.4.0 reports all four disputed calls and the deliberate narrowing control on Win32 and Win64. | Evaluation 9.21.5.0 still exposes disputed rows; its report limits the displayed details. |
| T-233, record-field writes and missing `const` | PAL 9.21.4.0 reports the three disputed parameters plus the pointer/read-only controls on both targets. | Evaluation 9.21.5.0 still exposes disputed rows. Compiling the `CONST_VARIANT` fails with E2064 and E2197 on both targets, confirming that the proposed `const` changes are invalid. |
| T-234, object-field receiver references | PAL 9.21.4.0 reports both disputed receiver variables and the unused control on both targets. | Evaluation 9.21.5.0 reports zero rows, but explicitly omits identifiers beginning with J, K or L. That hides both `lState` and `lUnused`; it cannot establish a fix. |
| T-225, include-based `packed class` | FixInsightCL Pro 2026.01beta fails at line 9, column 34 with `InvalidStructuredType found class` on both targets. | The public archive supplies 2023.12 and fails identically. Both executables accept the equivalent direct `packed class` declaration. |

The six normal PAL fixture builds and four FixInsight control builds passed with zero errors and warnings. All six PAL runtime checks exited successfully. Both deliberately invalid `CONST_VARIANT` builds failed as expected. The source manifests still match. These upstream reproductions received no new exclusions; the PAL raw status files retain the analyzer's existing System/RTL exclusions and show all reproducer source files loaded.

The approved routine policy excludes third-party libraries while retaining our maintained shared libraries. The September 8 review identified the T-265 maintained-source ownership defect. T-265 is now fixed, and T-294 verifies whole-FlexCel routine exclusion with owned caller coverage preserved. T-212 has [reviewed DAK and Semantics baselines](reviewed-analysis-baselines.md); external PAL stability remains unresolved under T-293. Neither routine exclusions nor ownership classification prove a vendor parser is corrected. No vendor or external project source was edited.

PAL's [published history](https://www.peganza.com/history_pal.html) lists 9.21.5, but the evaluation build cannot certify the hidden receiver findings. The smallest next step is a licensed or vendor-supplied build that passes the same raw reproductions without evaluation omissions. FixInsight likewise needs a vendor build that passes the include-based fixture.

Exact commands, durations, binary versions and hashes, raw XML excerpts, control classifications and source hashes are retained under `projects/.dak/DelphiAIKit/goal-current/`:

- `vendor-pal-runs.json` and `vendor-pal-fresh-review.json`
- `vendor-fixinsight-runs.json` and `vendor-fixinsight-source-proof.json`
- `vendor-repro/*/.dak/*/retry-20260908/`

The separate real DelphiLSP retry is recorded in [lsp-capability-probe.md](lsp-capability-probe.md).


## Availability check, 2026-09-09

Installed PAL remains 9.21.4.0; its executable hash matches the retained retry evidence.

[Peganza's current history](https://peganza.com/history_pal.html) still lists 9.21.5, dated August 11, 2026. [TMS's FixInsight history](https://www.tmssoftware.com/site/fixinsight.asp?s=history) lists 2026.01. Neither entry explicitly documents correction of these retained reproductions. This refresh checked published version availability only; the raw native reproduction results above remain dated September 8. No vendor source or analyzer installation was changed.

Evidence: `projects/.dak/DelphiAIKit/goal-current/vendor-availability-20260909.json` and `vendor-installed-metadata-20260909.json`. The upstream tasks and three active PAL reports remain open.


## Maintainer decisions, 2026-09-10

Retry vendor reproductions after a relevant version or configuration change.
An unchanged-version rerun alone does not establish a correction.

Always exclude FlexCel from routine FixInsight analysis. The current
`order_access_cli/project/dak.ini` contains ten verified exact-file exclusions;
it does not yet exclude the whole library. T-294 records the broader routine
input-exclusion implementation and its caller-coverage proof. Preserve the
existing exclusions until that proof passes. Retry the raw packed-include case
only when a newer FixInsight version is available, with exclusions disabled for
that explicit diagnostic run. A newer version alone does not prove correction.

T-212 will use a reviewed baseline under the corrected ownership contract.
Fix confirmed correctness defects first where edits are authorized. Keep every
accepted finding visible with a reason and a follow-up task where appropriate.
Retain the historical baseline and raw findings; this decision does not accept
an unreviewed replacement or certify PAL's inconsistent BSON reports.

Both production repositories, `F:/projects/OEC/TE5/maxTdb` and
`F:/projects/OEC/_git/TE5/order_access_cli`, are read-only for this effort,
including their project files and configuration. Use recorded snapshots under
DAK's test fixtures and keep generated analysis/build output inside DAK.
Snapshot edits invalidate affected proof.

T-292 is optional fixture-only cleanup debt, not a production fix or an
automatic prerequisite for DAK completion. The redundant assignment arose from
external-project analysis, not a failing DAK unit test. Keep its individual
review reason if retained; do not change source or tests merely to quiet the
analyzer. The historical production patch must not be applied.

## Whole-library routine exclusion proof, 2026-09-10

DAK now defaults `[FixInsightCL].ExcludeFlexCel` to `true`. It recognizes the
installed Smart Setup product from `tmsfetch.info.txt` and the
`Source/Core/FlexCel.Core.pas` marker, then adds absolute and project-relative
source masks. This covers units without a FlexCel filename prefix. Other
installation layouts need verified project-local exclusions. Existing manual
exclusions and compiler search paths, defines, aliases and scopes are preserved.
Both native analysis and generated FixInsight commands use the same policy;
the status records its switch, effective ignore list and detected source roots.

The isolated `order-access-analysis-t294` fixture contains maxTdb source from
revision `93681be36c8fd23dcbe7c6f5e40175df13db3fdc`, byte-identical caller/backend
copies and project paths redirected into DAK. Its resolved Win32/Release/23.0
context matches the retained context after the recorded path substitutions.
No T-292 cleanup was applied. Production source and configuration were not edited.

With FixInsight 2026.01beta, comparing the ten-file policy with the complete
FlexCel source exclusion on this same snapshot produced:

| Observation | Ten files | Whole library |
| --- | ---: | ---: |
| Owned finding records | 962 | 962 |
| FlexCel finding records | 5,306 | 0 |
| Unknown ownership | 0 | 0 |
| Ignored owned records | 0 | 0 |

Every owned record matches in full, preserving duplicate counts. Both native
runs and report verification completed; guarded inputs and historical baseline
bytes remained unchanged. The policy result still fails against that retained
baseline. This FI-only comparison does not close T-212 or prove a vendor parser
correction. FlexCel itself is outside routine FixInsight coverage.

A separate real CLI control checked relative and absolute nested vendor paths,
an owned caller, a similarly named owned sibling, explicit raw mode and an
unverified product folder. Only verified vendor units were excluded by default;
owned diagnostics remained visible. Raw mode disables automatic masks only.

Evidence under `projects/.dak/DelphiAIKit/goal-current/`:
`t294-snapshot.json`, `t294-context-comparison.json`, `t294-caller-proof.json`,
`t294-caller-comparison.json` and `t294-native-control.json`. Raw reports remain
under the isolated fixture's project-local `.dak/order_access_cli/` directory.
