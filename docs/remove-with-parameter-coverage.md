# Procedure parameter coverage, T-256

The planner rejected a record-pointer rewrite in a procedure whenever a body
reference resolved to an ordinary value parameter without a same-named global.
That global is irrelevant: removing `with` does not remove the procedure's
parameter scope. The equivalent function case was already supported.

The correction removes that extra rejection. Existing binding, ambiguity,
temporary-name, addressability, and complete-rewrite checks still decide whether
a statement can be replaced. A pointer temporary addresses the existing record;
for a value parameter this is the callee's copy, and for a `var` parameter it is
the caller's record.

The new `RemoveWithValueParameter` fixture checks a record passed by value,
mutation of that copy, an independent scalar parameter, and a parameter name
that collides with a receiver field. Both the original and DAK-applied Win64
program compile without warnings and produce the same result. The caller's
record remains unchanged, and the receiver field retains precedence.

On the retained maxTdb workload, all 232 previous replacements and all 19
covered statements are unchanged. Nine previous `symbol-not-found` skips now
produce replacements:

| Unit | Source line | Replaced statement |
| --- | ---: | --- |
| md5.pas | 259 | MD5Update context counters |
| tdb01.pas | 215 | Nested cache item update |
| TDBJOBS.pas | 495 | LastError fields |
| bitarray.pas | 79, 95 | SetBit and ResetBit |
| winblobs.pas | 311 | Blob block fields inside the repeat loop |
| ramfiles.pas | 704, 757, 774 | Read, seek, and write record fields |

The new totals are 667 statements: 241 planned, 407 skipped, and 19 covered.
One remaining parent at `tdb01.pas:203` now reaches the later
`semantic-rewrite-incomplete` check and stays skipped. The other 406 remaining
skips are unchanged. `symbol-not-found` decreases from 329 to 319; this is a
specific coverage correction, not a general solution for the remaining skips.

The exact added plans, original-versus-applied fixture proof, and regression
logs are retained in `projects/.dak/DelphiAIKit/t250-t256/`. The real project
source was not rewritten; its comparison used plan mode.

## Controlled record-array receivers, T-278

A global record's fixed array field can now be captured inside WHILE and IF
statements when its declaration and named record element type are unambiguous.
For `Container.Items[i]`, the pointer is initialized at each original WITH
entry. Changing `i` inside the body does not change the selected element, and a
false guard or zero iterations never evaluate the selector.

The exception requires a same-unit global record, one directly declared fixed
array field, a simple index identifier and a named same-unit record element.
Every indexed root-name projection must identify that same variable declaration.
Competing declarations, property/getter results, default indexers and nested
routine or implicit Self shadows retain the conservative skip. Existing type
visibility, member resolution and transactional verification still apply.

The real fixture covers loop and IF captures, unchanged plain/pointer controls,
and four getter/shadow negatives. Original and transactional-apply Win64 Release
programs compile without warnings and produce identical output. Four statements
are rewritten and four skipped; complete ordered cold/warm plans match. The
owning fixture passes 101 tests, including separately retained failing shadow
regressions before their fixes.

The complete 633-record MaxTdb plan changes only TDB01:994 and its declaration
owner at 986. The former gains a per-iteration capture; the latter includes that
capture in its shared declaration. All 437 emitted edits across 21 units compile
in an isolated copy. The 445 inherited warning messages and order are unchanged;
two locations move by three lines. All 709 original source/configuration hashes
remain unchanged. The shared gate passes Semantics 666/666, SQLite 68/68,
Python 110/110 and DAK 659/659, with zero owned compiler warnings. Both project
analysis gates pass; advisory metric changes remain visible. T-209 historical
acceptance and performance certification remain open.

Evidence: `projects/.dak/DelphiAIKit/goal-current/t278-verified-runtime-proof.json`,
`t278-identity-owner-green.json`, `t278-final-maxtdb-plan-delta.json`,
`t278-maxtdb-compiler-proof.json`, `t278-candidate-review.md` and
`t278-task-proof.json`.


## T-280/T-283 body boundaries and controlled wrappers

The range extractor distinguishes an END opened inside the WITH body from an
enclosing END. A compound before an outer ELSE keeps its own END. A final
conditional, numeric literal or string/comment body excludes the enclosing
routine END. Parser identity 12 invalidates persisted ranges from identity 11
and the dependent project facts.

Generated capture wrappers bypass source-tail trimming. The planner checks the
first code token after the inclusive body endpoint, skipping whitespace and
comments across lines. An outer ELSE keeps its attachment without a generated
semicolon. Nested compounds without ELSE retain their closing tokens.

The 16 range/cache cases reproduce 13 failures and retain three passing
controls. All 16 pass with the fix. The six renderer cases reproduce five
failures against the original producer and retain one passing control; all six
pass with the candidate.

The real BodyRanges fixture builds for Win64/Release/23.0 with zero warnings.
In an isolated copy, all seven eligible statements apply and all 17 output
lines match the original. Transaction backups match unchanged original bytes.
Three cast-bearing statements remain skipped. Complete ordered cold/warm
fixture plans match across 18 stable fields. Statistical performance
verification remains open.

The complete 633-row historical legacy API plan is identical before and after
the renderer correction on the T-280 range candidate. T-280 changes 27 final
DTOs without changing statuses; all 437 emitted edits compile in 21 isolated
units. TDB02:2866 now ends at 2875:7, and TDB02:3107 ends at 3119:21.
Historical expectation migration and full ownership/performance acceptance
remain open. The shared gate passes Semantics 688/688, SQLite 68/68, DAK
659/659 and Python 110/110, with zero owned compiler warnings. Both compatible
project analysis gates pass; advisory metrics and shifted finding locations
remain visible. T-265 still owns the maintained-root classification defect;
dedicated Semantics analysis covers those sources here.

Evidence: `projects/.dak/DelphiAIKit/goal-current/t280-regression-red.json`,
`t283-counterfactual-red.json`, `t283-counterfactual-green.json`,
`t283-final-runtime-proof.json`, `t283-current-all-rewritten-build.json`
and the source reviews `t280-candidate-review.md` and `t283-candidate-review.md`.
Exact inputs and shared gate results: `t280-t283-task-proof.json`.

The fresh historical run passes 159 of 203 tests. Its 39 prior failures are
unchanged. Five additional assertions retain the old boundaries in ClearBitArray,
MakeDirStr, NormIndFiles, h_FNr and getstructure. Their failures match the
source-reviewed T-280 corrections; expectation migration remains T-209 work.
See `t209-eighth-inventory.json` for the exact failures and unchanged inputs.

The five boundary expectations have now been migrated without changing their
planned/skip decisions. All five pass, and the full historical rerun passes
164/203 with the same 39 prior failure names and messages. The Win64 rebuild
has zero owned warnings, and touched-unit PAL analysis has no new findings.
Evidence: `t209-five-boundaries-proof.json` and `t209-after-boundary-inventory.json`.

## Compiler type casts inside WITH bodies, T-281

Body binding now retains compiler-owned type identity after receiver and lexical
lookup have failed. It reuses the existing compiler profile once per binding
session. Same-spelling user routines, types and receiver methods keep their
declaration identity. Selector-cast restrictions are unchanged. Planning-facts
producer v4 rejects older cached bindings; parser identity remains 12.

The eight retained cases fail five assertions before the fix and all pass after
it; three shadowing controls pass in both runs. Owning tests pass 209/209.
The real Win64 fixture checks writable Double, Pointer and Integer casts, a
Pointer value cast, false guards and the three shadow declarations. All seven
statements apply in an isolated copy, rebuild without warnings and reproduce
the original eleven output lines. Full cold/warm plans agree across 18 fields;
original files and transaction backups retain their bytes.

Complete MaxTdb comparisons cover explicit Win64/Release/23.0 and the historical
project-default context separately. Four parent bodies become planned: GetVar,
GetArrayVarPtr, build_str_array and Compile at TDBJOBS:2295. Two nested final
rows are now covered by their parents. All remaining row order is preserved.
Both complete 444-edit sets compile in 21 isolated units. The 445 inherited
MaxTdb warnings retain the same ordered messages after line/path normalization;
all 709 original files remain unchanged. This compiler proof does not claim
full MaxTdb runtime equivalence or close the historical T-209 assertions.

Evidence is under `projects/.dak/DelphiAIKit/goal-current/`:
`t281-regression-red.json`, `t281-conventions-exact-green.json`,
`t281-conventions-final-runtime-proof.json`, `t281-complete-plan-delta.json`,
`t281-conventions-plan-parity.json`, `t281-conventions-compiler-warning-delta.json`
and `t281-conventions-review.md`.
The shared gate passes Semantics 696/696, SQLite 68/68, DAK 659/659 and
Python 110/110, with zero owned compiler warnings. Both compatible project
analysis gates and output verification pass. Finding changes are documented
in `t281-conventions-analysis-disposition.md`; T-265 still owns maintained-root
classification. Exact task proof: `t281-task-proof.json`. T-209 historical
acceptance and final statistical performance remain open.
