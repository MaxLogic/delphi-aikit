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

## Multiline routine headers, T-284

Wrapping a routine's parameter list across lines previously omitted the routine
from the semantic model. This could leave both its own result name and calls
through its interface declaration unresolved. The extractor now retains the
original signature, ordered parameters and source coordinates. It also stops
an incomplete header before the following routine declaration.

The `RemoveWithMultilineHeaders` fixture pairs single-line and wrapped functions
with typed and untyped parameters, a same-unit function implemented later, and
a parameter that shadows a unit type. A fourth case calls an earlier sibling
procedure from a nested function. All four WITH statements are planned
and transactionally applied in an isolated copy. Original and rewritten Win64
Release programs compile without warnings and print the same five lines.
Complete ordered cold/warm plans match, and the original files and transaction
backups retain identical bytes. A separate model assertion covers nested
default parentheses, a string containing parentheses, and a multiline comment
containing a fake routine declaration.

The retained original-extractor replay fails the missing model and both calls
to the later-declared function; the shadow control passes. The candidate passes
all four cases. The additional nested-scope and cached-facts regressions also
pass after their retained failures; the owning semantic fixtures pass 351/351.
Routine inventory now retains model body extents, so sibling calls keep their
enclosing scope. Parser identity
13 invalidates older models and the snapshots and WITH facts that depend on
their unit-cache identities. WITH facts producer version 6 also invalidates
older projected routine extents. All 478 emitted historical edits compile in
both retained contexts, preserving 709 original files and the same 445 inherited
warning messages. Fresh extraction after the delimiter refactor reproduces both
complete ordered historical reports exactly; the retained compiler inputs and
emitted source hashes also match. The global-vars provenance assertion now
expects parser identity 13, with all other assertions preserved.

The final shared gate passes Semantics 721/721, SQLite 68/68, DAK 659/659 and
Python 110/110, with zero owned compiler warnings. Both project analysis gates
and report verification pass. PAL findings are unchanged; the partial enum-case
advisories were removed by an equivalent delimiter refactor. FixInsight's three
net Semantics metric additions remain visible and are explained in
`t284-analysis-disposition.md`. One PAL reference run crashed; an identical-input
diagnostic retry and candidate pass succeeded. Its cause remains unresolved,
and this does not establish an upstream fix.

Evidence is retained under `projects/.dak/DelphiAIKit/goal-current/`, including
`t284-task-proof.json`, `t284-delimiter-runtime-proof.json`,
`t284-delimiter-plan-equivalence.json`, `t284-delimiter-compiler-reconciliation.json`
and `t284-pal-retry-comparison.json`. T-285 imported procedures, T-209 historical
acceptance/performance and T-265 maintained-root ownership remain open.

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

## Pointer-cast receivers, T-282

A source-visible pointer alias followed by record dereference can now use the
existing capture-once renderer. The binder checks the actual alias and target
declarations, caller visibility, lexical scope and receiver-member precedence.
Imported functions, procedure variables and same-spelling members remain calls.
For nested selectors with identical text, the innermost binding controls the
decision. Planning-facts producer v5 rejects cached bindings from v4; the public
interfaces and parser identity remain unchanged.

Retained RED covers six failures among thirteen initial cases, one imported
callable failure, and two nested callable failures. The final focused set passes
20/20 and its owning fixtures pass 225/225. Three prior body-range assertions
were migrated only after real apply and runtime proof. They retain exact source
ranges, verification text, complete replacements and parent/child ownership.

The Win64 pointer fixture applies six statements and keeps ten excluded.
Changing a slot pointer between writes still updates the originally captured
record. False guards and zero-iteration loops do not evaluate nil receivers.
The body-range fixture applies nine parents and covers one child. Both isolated
copies rebuild with zero warnings and reproduce all original output, sixteen
and seventeen lines respectively. Their complete ordered cold/warm plans agree
across eighteen fields; original sources and transaction backups retain their
bytes.

Both complete MaxTdb contexts add ten planned parents and cover one child;
ten other casts remain skipped because body names are unresolved. All other
final records and surviving order are unchanged. Each complete set of 464 edits
compiles across 21 isolated units, with 445 unchanged inherited warning
messages after line/path normalization. All 709 original files remain intact.
This is compiler proof; full historical runtime equivalence and T-209 acceptance
remain open.

Evidence under `projects/.dak/DelphiAIKit/goal-current/` includes
`t282-implementation-checkpoint.json`, `t282-current-runtime-proof.json`,
`t282-complete-plan-delta.json`, `t282-historical-plan-review.md`,
`t282-all-compiler-proof.json` and `t282-current-source-review.md`.
The shared gate passes Semantics 712/712, SQLite 68/68, DAK 659/659 and
Python 110/110, with zero owned compiler warnings. Both compatible project
analysis gates and report verification pass. PAL findings are unchanged;
FixInsight metric changes and an inherited MaxLogicFoundation W541 reference
omission are documented in `t282-analysis-disposition.md`. Maintained-root
classification remains T-265 work. Exact task proof: `t282-task-proof.json`.
T-209 historical acceptance and final performance certification remain open.

## Imported procedures and nested selectors, T-285 through T-287

A procedure exported by a directly imported unit can remain in a rewritten
body without a return type. The planner requires a unique source-backed
declaration and actual visibility. Unknown, private, unimported and ambiguous
calls remain excluded; local and receiver members retain precedence.

Selector partitioning now uses the Delphi lexer and balanced delimiters.
Commas inside indexes, parentheses, strings or comments remain part of their
selector. Before producing edits, the planner checks the complete ordered
selector list against that statement's own bindings. An inherited selector
cannot stand in for a missing own selector. Planning-facts producer v7
invalidates v6 payloads; existing public signatures remain unchanged.

When a parent WITH remains in the source, a child rewrite preserves the
nearest retained member's unqualified spelling. This applies to body reads,
writes and capture initializers. An active child receiver still takes
precedence. A separate lookup result distinguishes a known retained member
from an unresolved name, including the packed-record inventory case.

Retained regression replays show T-285's two failures becoming ten passes,
T-286's 26 failures becoming 54 passes, and T-287's three initial failures
plus its later packed-record failure becoming five passes. The final focused
and owning sets pass 63/63 and 257/257. Complete ordered results also agree
after reopening real SQLite caches and loading standalone planning facts.

Each of three isolated Release Win64 fixtures applies five rewrites. Original
and rewritten programs produce identical output, compile without warnings,
and preserve source and backup bytes. Both historical MaxTdb contexts compile
all 674 emitted edits across 23 isolated units, with zero errors and the same
445 inherited warnings. Cleanup produces byte-identical complete plans, so
the emitted-program compiler proof remains applicable. All 709 original
project files retain their bytes. This does not establish full MaxTdb runtime
equivalence or close T-209.

Both project analysis gates and report verification pass. PAL findings are
unchanged; the reviewed FixInsight changes are method-size and variable-count
metrics. Maintained-root ownership remains T-265 work. Evidence lives under
`projects/.dak/DelphiAIKit/goal-current/`, including
`t285-t287-final-source-review.md`, `t287-cleanup-compiler-reconciliation.json`,
the three `t287-batch-t28*-runtime-proof.json` files, and
`t287-analysis-disposition.md`. The shared gate passes Semantics 769/769,
SQLite 68/68, DAK 659/659 and Python 110/110, with zero owned compiler
warnings and no ignored tests, errors or leaks. Exact task records are
`t285-task-proof.json`, `t286-task-proof.json` and `t287-task-proof.json`.
T-209 historical acceptance and final performance certification remain open.


## Historical characterization after T-287

An initial twenty-eight historical methods were aligned with the verified
post-T-287 contracts.
Seven methods account for new sibling captures and shared declarations;
two preserve unqualified members of retained parent WITH scopes; fifteen
update exact conservative skip reasons. Those twenty-four retain their
existing body, range, identity, covered-child and negative checks.

Four other methods replace unsupported positive recipes with complete
original-source, range, hash, identity and zero-edit assertions. The real
compiler, runtime and effective-profile witnesses below establish the
conditional-scope and hidden-capture-type boundaries. These are test
characterizations; production behavior and public APIs remain unchanged.
Separately recorded model limits remain open.

Four further methods cover the Jump declaration owner, the complete NewInd
parent and covered child, and IndProc's callback body. Jump retains its full
replacement checks with the third capture name and verifies that the shared
declaration is emitted once by the first capture. NewInd pins both captures,
the allocation/error path and the child's ownership. IndProc retains its full
IF/ELSE, callback, GOTO and EXIT behavior.

Five further methods now pin eight receiver captures in GetVar, DoMarkBits,
GetBitArrayVar, BitArrayOp, InArray, InArrayPos, andmarks and KonvertVarNr.
They retain the complete bodies and the first BitArrayOp skip. New assertions
cover original source, capture metadata, declarations and recipes. Corrected
replacement ranges exclude the enclosing routine end or following ELSE.

Six further methods cover NaechsteRecNr, NextRec, getdef, GetAuto, the array
size check and the report SubR branch. NextRec retains its three capture
entry points and explicit child coverage. The two getdef selectors remain
ordered. GetAuto and the other conditional rewrites keep initialization
inside the original guards, with enclosing END/ELSE syntax outside the edits.
Complete source, body, identity, declaration and recipe assertions remain.

The six focused tests pass, the owning fixtures pass 257/257, and the standard
Semantics suite passes 769/769. The historical category is now at 189/203,
with exactly 14 remaining failures and unchanged failure messages. The Win64
build has zero owned warnings and three DelphiAST warnings. Project-context
PAL retains the same 322 findings; report ownership verification passes.
All 3,350 production inputs remain unchanged from the verified T-285 through
T-287 batch. Evidence: `t209-imported-controlled-six-proof.json` under the
evidence folder above. The preceding checkpoints remain in
`t209-capture-five-proof.json`, `t209-next-four-proof.json` and
`t209-final-characterization-proof.json`. T-209 remains open.

Two diagnostic witnesses establish limits of the remaining investigation.
Removing a WITH while preserving unbound conditional text can compile yet
change behavior in another profile. The original alternate-profile program
prints `12,100`; the handwritten incomplete rewrite prints `2,110`. This is
a counterexample, not output emitted by DAK. The actual project loader and
preprocessor confirm that the unresolved `WaitRead` call in `tdb01:964` is
inactive in both retained profiles. That fact alone does not authorize
removing its enclosing scope. See `t209-conditional-witness-proof.json` and
`t209-effective-profile-proof.json`.

A separate indexed-getter witness confirms why an explicit pointer capture
needs a type visible to the consumer. A hidden `TEntry` pointer declaration
fails compilation; importing its declaring unit makes the existing DAK
capture recipe available. Real isolated apply preserves `18,1`, including
one getter evaluation. A handwritten two-operation expansion evaluates the
getter twice and prints `18,2`. The narrower single-assignment hypothesis
was falsified: that handwritten expression evaluates the getter once on the
installed compiler. No runtime defect is claimed for that exact expression.
The evidence is retained in `t209-hidden-getter-single-assignment-observation.json`,
`t209-hidden-getter-two-operations-proof.json` and
`t209-getter-visible-runtime-proof.json`. These small witnesses do not establish
full MaxTdb runtime equivalence or complete historical acceptance.
