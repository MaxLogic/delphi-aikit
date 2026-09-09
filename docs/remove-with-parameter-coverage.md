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
