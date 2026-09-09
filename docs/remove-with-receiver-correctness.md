# Remove-with receiver correctness

T-261 corrects receiver re-evaluation discovered during T-209's historical MaxTdb audit. Delphi evaluates a `with` receiver on entry. Directly repeating a pointer expression in the replacement can select another record after a body call changes that pointer. The isolated compiler control produced `2,0` with the original statement and `1,1` with the previous emitted rewrite; both compiled without warnings.

The planner now captures address-dependent receivers using its existing pointer-temporary strategy. Dependent receivers use the enclosing receiver's fields and actual field types, and nested statements capture their receiver at their own entry. The planner conservatively skips repeated explicit selectors in a single header when occurrence identity is unavailable. An unsupported child prevents a partial parent rewrite.

Selector extraction preserves literal and comment text from the original source. Qualification excludes hexadecimal digits, strings and comments; one shared lexical scan prevents apostrophes inside comments from hiding identifiers after the comment. Existing public API signatures are unchanged.

A captured receiver can be accessible even when its explicit type name is not. The planner now requires an unambiguous source declaration visible at the actual temporary insertion point. It safely skips transitive or inactive imports, conflicting declarations with the same name, and routine-local types declared after that insertion point. Direct imports and an outer local type used by a nested routine remain eligible. The existing unsupported alias-category skip is preserved.

One private visibility map retains each unit's direct active imports. It travels with cold snapshots and is stored as ordered relational rows for cached planning. Missing or truncated cache metadata causes invalidation. Import extraction ignores comments and strings. These changes introduced parser identity 8, snapshot identity 8, planning-facts identity 2 and SQLite schema 10. The adjacent T-262 initialized-variable fix advances the parser identity to 9; T-268 then advances it to 10 for correctly scoped main-program references.

Retained regressions cover direct/indexed pointers, field chains, dependent and nested selectors, repeated entry, shadowed receiver types, initializer construction, literal preservation and comment/index qualification. Each behavioral correction has a retained failing test followed by a passing run. Structural assertion updates preserve complete ranges, ownership, ordering, temporary-name reservations, control-flow attachment and conservative parent rejection.

## Retained T-261 proof

| Check | Result |
| --- | --- |
| DelphiSemantics Win64 Release rebuild | Zero owned warnings; three vendor lexer warnings |
| Remove-with owning suite | 75/75; zero ignored, failed, errored or leaked |
| Full standard DelphiSemantics suite | 625/625; zero ignored, failed, errored or leaked |
| Dedicated SQLite Win64 Debug executable | 68/68; zero ignored, failed, errored or leaked; three vendor compiler warnings |
| DAK production Win64 Release rebuild | Zero owned warnings; four identified vendor warnings |
| DAK test Win64 Debug rebuild | Zero owned warnings; four identified vendor warnings |
| Fresh pointer fixture original/applied runtime | Eight observations match exactly |
| Fresh literal/comment fixture original/applied runtime | `42`, `43`, `44` match exactly |
| Hidden-type and local-type original/applied runtime | Six observations match exactly; unsupported cases stay unchanged |
| Ambiguous-type fixture | Original runtime passes; sole statement safely skipped |
| All five fixture baseline builds and four post-edit builds | Zero warnings; applicable transactional verification passes |
| Five complete ordered cold/warm plans | Identical, including edits, statements, skips, covered children and required verification |
| Independent source and assertion reviews | Pass |
| Fresh Semantics project analysis after cleanup | Both analyzers and report verification pass; no added PAL findings or new production variable-count findings |

The pointer fixture applies seven root edits, covers three children and safely skips the repeated-header statement and its enclosing parent. The literal/comment fixture applies all three statements. Original fixture files remain byte-identical; apply runs use isolated copies.

An earlier ten-fixture compiler sweep also checked property/field chains, control bodies, DAK rewrite shapes, temporary-name collisions, else attachment and nested `FreeMem` handling. Two analysis fixtures deliberately contain illegal writes to non-addressable record results. Their isolated compiler copies replace only those negative-case writes with reads; the original fixtures and negative analysis expectations are preserved. One long generated verification path failed before mutation; the identical source passed at a shorter path. The independent path-handling defect is recorded as T-263 outside this effort.

The initial full DAK run passed 646 of 656 tests; ten assertions expected the old repeated-pointer text. Their compiler-backed migration passed all 157 tests in the standard remove-with scope, with no ignored tests. An explicit historical MaxTdb apply then exposed an invisible capture type and rolled back all 23 files. The visibility fix subsequently passed the full DAK suite, 656/656, and all 110 Python analyzer tests. Full analysis then identified two new PAL warnings and two new production variable-count findings. A behavior-preserving cleanup removed all four, as confirmed by fresh analysis, 75 owning tests, 625 Semantics tests, 68 SQLite tests and repeated isolated runtime/apply checks.

Three new FixInsight advisories describe retained test complexity: the pointer-chain assertion test is 52 lines, and the new visibility-cache regression is 67 lines with eight variables. Changed measurements of existing methods are recorded separately. These remain visible; no tests or analyzer settings were weakened. The full raw comparison is in `t261-final-analysis-triage.json`, with the per-method review in `t261-analysis-cleanup-review.json`.

T-261's task proof passes. The shared Win64, Python and project-analysis checkpoint is grouped with the adjacent T-262/T-268 extractor fixes. Earlier broad passes remain tied to their original source hashes. The historical MaxTdb category, new benchmarks and final goal certification remain separate work. T-265 must correct maintained external-library ownership before T-212 and final analysis certification can pass.

Exact commands, durations, source manifests, executable hashes and raw reports are retained locally under `projects/.dak/DelphiAIKit/goal-current/`. Start with `t261-task-proof.json`, `t261-clean-runtime-proof.json`, `t261-owned-warning-builds.json` and `t261-all-fixture-inputs.json`. The import, hidden-type, collision, insertion-point and cache regressions have separate `red` and `green` logs in that folder. Earlier proof records remain historical evidence; reuse requires unchanged relevant inputs.

## Subsequent extractor checkpoint

T-262 removes initializer values from declaration types without losing quoted or nested-comparison type expressions. Its full-suite check exposed a separate missing program-body reference: an assignment had previously supplied the reference accidentally through the declaration scanner. T-268 now extracts the root AST statement body with exact coordinates and no routine owner, respecting both extraction opt-outs. A retained regression also rejects coordinate-reconciliation fallback for an otherwise exact program body.

The current parser-10 semantic suite passes 629/629, and the separate SQLite runner passes 68/68, with no ignored, failed, errored or leaked tests. The Win64 builds have zero owned warnings. The shared checkpoint also passes the freshly built DAK runner (656/656), all 110 Python analyzer tests, and both project analysis/report-verification runs. It does not certify the historical MaxTdb category, maintained external ownership, or performance budgets. T-266 and T-267 retain the independently confirmed skipped-parent temporary metadata and indentation defects discovered during that audit. No historical expectations have been rewritten for them.

The shared checkpoint is sealed in `t262-batch-proof.json`; its full DAK run took 1225.950 seconds and retained unchanged input hashes. All 37 changed Delphi files match the independent review chain recorded in `t262-checkpoint-reviewed-files.json`.

## Skipped-parent metadata, T-266

A parent could accumulate captures from one successful child, then abandon its rewrite when a later child was unsupported. It released the reserved names but retained the child temporaries in its output. The failure paths now clear that metadata after releasing the names. Independently planned children still receive their own captures and declarations.

The retained regression failed with one temporary in a skipped parent where zero were required. It now verifies empty parent edits and recipe metadata, reuse of the released temporary name, the child's independently qualified initializer, and no false parent-coverage claims. The complete remove-with fixture passes 76/76. An isolated original and transactional rewrite both print `1,2`; all three original fixture files remain unchanged. Cold and warm plans match in all 19 fields outside generated execution paths, including complete ordered edits, skips and verification requirements.

Win64 Semantics and DAK production builds have zero owned warnings. Fresh Semantics PAL findings are unchanged. The only FixInsight delta is its existing `BuildFinalStatement` length advisory changing from 189 to 192 lines. Independent review covers all three cleanup exits; the retained runtime regression directly exercises the later-child failure path. Evidence is under `projects/.dak/DelphiAIKit/goal-current/`, including `t266-source-review.json`, `t266-runtime-proof.json`, `t266-complete-plan-parity.json` and `t266-analysis-triage.json`. T-267 is described below; historical MaxTdb acceptance and performance work remain open.

## Captured-body indentation, T-267

The pointer-body indentation rule previously required an empty capture initializer. Adding a capture therefore left some bodies at two spaces even when their statement began at column 5 or 7. Removing that condition restores the existing first-line indentation rule. Controlled wrappers, source ranges and trailing control-flow handling remain unchanged.

The retained plain and indexed pointer cases fail before the fix and pass afterward; a controlled statement is a preservation control. All three assert complete replacement text, declaration insertion and source ranges. The owning fixture passes 79/79. Original and isolated rewritten programs both print `1`, `2`, `13`, `10`, including a false guard that would expose an escaped body. All three original source files remain unchanged, and the 19 plan fields outside generated execution paths compare exactly between cold and warm runs. Both Win64 builds have zero owned warnings, and independent source review passes. These checks are recorded in `t267-source-review.json`, `t267-runtime-proof.json` and `t267-complete-plan-parity.json`; historical MaxTdb acceptance and performance certification remain separate.

Fresh Semantics project analysis and report verification also pass with no PAL or FixInsight finding deltas from T-266. The complete task gate is sealed in `t267-task-proof.json`.


## Historical MaxTdb checks

After T-266/T-267, the explicit historical category reports 35/203 passing and 168 failing, with no new failure names. The OpenDB parent test passes unchanged. Fresh default-options DPR and DPROJ API plans agree across all 11 fields and contain 633 final statements.

Five old expectations have since been updated after separate source review and actual-unit compiler proof. Two DBFUTIL cases now require receiver captures while preserving four- and six-space indentation, edit boundaries and the shared declaration owner. TestBit, TruncBitArray and SkipRamText now stop their replacement at the WITH body; the enclosing routine terminator remains in the untouched source. Full replacement strings remain exact; no trimming or bulk expectation rewrite was used.

The isolated real MaxTdb project compiles before and after these nine selected API edits. Both builds retain the same 445 legacy warning signatures, with no added warnings; all 709 original fixture files remain unchanged. These are compiler and source-control-flow checks, not an execution of the legacy database routines or a DAK transactional apply test. T-267's separate retained runtime controls remain the runtime evidence for captured-body handling.

All five migrated tests and the unchanged parent test pass together (6/6). The historical category still needs its remaining acceptance work and a fresh complete run; this focused result does not certify that category or performance. Evidence: `t209-current-project-kind-parity.json`, `t209-dbf-compiler-proof.json`, `t209-boundary-compiler-proof.json` and `t209-five-migrations-exact.json` under `projects/.dak/DelphiAIKit/goal-current/`.

## Nested forward declarations, T-270

The routine-scope index previously pushed an unfinished routine frame for a nested forward declaration. The implementation closed its own frame, leaving the forward frame to claim the surrounding routine's later references and WITH statements. Captures for `CheckLinkFiles` were consequently declared inside its nested `CheckDirekt` routine.

The index now recognizes bodyless `forward` and `external` declarations through the installed lexer before adding a body frame. It preserves ordinary nested implementations, parent ownership and bounded scope queries. Planning-facts identity 3 invalidates the affected cached ownership; parser identity 10, snapshot identity 8 and SQLite schema 10 remain unchanged.

Retained regressions cover inline and next-line directives, split parameters, comment text and external declarations. The ownership cases and older-schema cache case each have recorded failures before the fix. The current owning suite passes 158/158 and the standard Semantics suite passes 640/640, with no ignored, failed, errored or leaked tests. Win64 production and test builds have zero owned warnings; vendor warnings remain separately identified.

An actual cache produced by the old executable first returns the wrong nested owner on a warm hit. The fixed producer misses that planning entry, writes corrected facts and subsequently hits them. The old row and both unit-model rows remain unchanged. Complete ordered upgraded, warm and fresh plans agree. A freshly rebuilt probe also confirms that the final refactor preserves those complete plans.

The isolated original and transactional rewrite both print `3`. All three original fixture files remain unchanged, and cold/warm plans agree in all 18 fields outside generated run and workspace details. The full isolated MaxTdb rewrite removes all 11 prior LINKFILE compiler errors. It then exposes two indexed-member errors in TDBUTILS, recorded separately as T-271; this is not a successful full-project compiler certification.

Fresh Semantics analysis has unchanged PAL findings and the same FixInsight finding count. Two existing advisories change their measurements: `BuildRoutineScopeIndex` grows from 70 to 77 lines and from 10 to 11 variables. The lexer cursor and its cleanup account for that change. No suppression or ownership-policy change was introduced.

One earlier full-suite process stalled with sustained CPU use. Later full runs, 30 isolated cases and 1,000 instrumented calls passed, but they do not establish its cause. T-272 records that investigation separately; a recurrence requires a thread-stack capture before terminating the process. Evidence is retained in `t270-full-suite-stall.json`. Current behavior proof is in `t270-current-runtime-proof.json`, `t270-cache-upgrade-proof.json`, `t270-current-sem-all.json` and `t270-final-sem-change-delta.json` under the same local evidence folder.

The T-270 shared checkpoint passes DAK 659/659, Semantics 640/640, SQLite 68/68 and Python 110/110. All four explicit Win64 builds have zero owned warnings, and both current-host project analyses pass report verification and their comparison gates. DAK-owned findings are unchanged. The complete DAK run took 1047.959 seconds. `t270-batch-proof.json` records the commands and unchanged proof-input hash `06a07296480cf0cb808f3e97b4a4c824a9fcbf5f72b579e7796926d047e7cb48`. Maintained-library ownership, the historical MaxTdb category and performance certification remain separate open work.

## Indexed argument precedence, T-273

The indexed-argument renderer previously preferred an outer local over a same-named WITH field. A retained test expected that behavior, but Delphi compiler and runtime evidence disproved it: the original wrote array element 0, while the old transactional rewrite compiled successfully and wrote element 1.

The renderer now resolves the active receiver member before considering an outer local. An unrelated lexical index remains lexical. Explicit qualification also survives whitespace after a dot; the renderer reuses its existing qualification check. No public API or persisted planning-facts identity changed.

The corrected retained expectation first failed on the old renderer. A further regression then caught an explicit `lOther. Index` being rewritten as `lOther. lWithIndexedRecordPtr^.Index`. Both pass after the fixes, together with all 99 owning tests. The isolated original and actual transactional rewrite produce the same four results: `7,0`, `7,0`, `0,7`, `0,7`. All four statements are planned, cold/warm plans agree across all 18 fields outside generated run/workspace details, and original sources remain unchanged. Original and transactional builds have zero warnings. Production/test Win64 builds retain only identified vendor warnings.

Evidence is in `t273-red.json`, `t273-qualified-red.json`, `t273-qualified-green.json`, `t273-qualified-owning.json`, `t273-runtime-proof.json` and `t273-final-source-review.md` under `projects/.dak/DelphiAIKit/goal-current/`. Fresh project analysis and report verification pass: PAL findings are unchanged, and the existing FixInsight measurements change from 85 to 128 test-method lines and from 9 to 8 renderer variables. No suppression or ownership changes were made. `t273-task-proof.json` seals the task gate. The shared broad checkpoint now follows the adjacent T-274 inline-declaration fix, grouping three renderer tasks.


## Receiver and field name collisions, T-271

For `with v do v[1,n] := j`, the receiver record can itself contain the array field `v`. The renderer previously treated the repeated name as an explicit receiver access and left the array base unqualified. Delphi instead resolves it to the WITH member. The fix checks the innermost matching receiver type before overriding the lexical and selector-text exemptions. Explicit dots, including whitespace after a dot, remain qualification boundaries.

An initial implementation borrowed membership from an outer receiver. Full ordered-plan comparison caught its incorrect rejection of anonymous `Struktur` children under skipped parents. A retained regression now checks that boundary, including the unchanged exact replacement and edit range. The corrected helper returns the matching receiver's own result immediately. A subsequent cleanup removes a redundant scan of all bound references; the complete ordered MaxTdb plan is identical before and after that cleanup. No measured performance improvement is claimed.

The six collision cases and separate nested case have retained failures before their fixes. All 106 owning tests pass, with zero ignored, failed, errored or leaked tests. Two isolated original/transactional rewrite programs produce identical results: the collision program prints `0,0,0`, four instances of `1,7,9`, `1,11,13` and `1,0,0`; the nested program prints `3`. All seven planned edits apply successfully. Their complete cold/warm plans agree across the 18 fields outside generated run/workspace details. The nested outer statement remains safely skipped, and all original fixture files stay unchanged. The fixture builds have zero warnings; Win64 production/test builds retain only identified vendor warnings.

The complete MaxTdb API plan retains 633 final statements with unchanged identity, ordering, status and reasons. Compared with T-270, only the two intended TDBUTILS indexed bases change, together with their edit and recipe text. Applying all 434 edits across 21 isolated units now compiles with zero errors. Original and rewritten builds retain exactly the same 445 inherited legacy warning signatures, and all 709 original files remain unchanged. This establishes full API-edit compiler proof; the legacy application itself was not executed.

Fresh current-host analysis and report verification pass. PAL findings are unchanged. FixInsight retains two new advisories: the six-case assertion method has 86 lines, and the completeness check has eight variables. Its existing `PrepareFinalBodyText` length measurement changes from 132 to 133 lines. The added variable names the proven receiver/member collision reused by both checks. No findings were suppressed or reclassified.

Evidence is retained under `projects/.dak/DelphiAIKit/goal-current/`: `t271-task-proof.json`, `t271-bound-final-source-review.md`, `t271-bound-runtime-proof.json`, `t271-bound-plan-comparison.json`, `t271-bound-maxtdb-compiler-proof.json` and `t271-bound-sem-change-delta.json`. T-274 remains open: a separate inline-declaration control compiles successfully but changes runtime output from `17,0` to `17,99` after rewriting. Historical MaxTdb expectations, performance certification, ownership and the final goal gate remain open.


## Inline declaration precedence, T-274

An inline variable declaration inside WITH does not make every later matching expression refer to that local. Delphi still gives the receiver member precedence. The former name-based exemption could silently change a whole-array assignment: the original program printed `17,0`, while the rewritten program printed `17,99`. Both programs compiled without warnings.

The renderer now protects declaration positions with one private lexer scan per body. Initializer expressions and loop bodies remain eligible for member qualification. The scan respects nested type punctuation, distinguishes a field named `On` from an exception header, and preserves unit-level conditional context. The completeness check builds its own position mask after rewriting. The existing scope guard remains for unrelated inline locals that the symbol inventory does not expose. Public APIs and cache identities are unchanged.

Two older scalar tests generated invalid Delphi: one omitted System.SysUtils for IntToStr; the other redeclared the same inline name in a nested block. Their exact original failures are retained. Minimal valid copies then proved the expression-binding defect. Four related Semantics/DAK test methods were corrected only after isolated compiler/runtime controls demonstrated the old rewrite's wrong output. Declaration, lexical-local, range and complete replacement assertions remain covered.

Eight exact semantic regressions, all 112 owning tests and all three affected DAK apply tests pass. Six fresh transactional fixture comparisons preserve their original output:

| Fixture | Output before and after apply |
| --- | --- |
| Nested inline scope | `8,8`; `0,0` |
| Inline blocks and try/finally | `24,receiverx`; `11,receiverx` |
| Array, initializer, loop and handler control | `17,0`; `4,4`; `3,6`; `5` |
| Contextual On and unit define | `5,2`; `6,2` |
| Bound rewrite | `4,cast` |
| Expression roles | `7,default` |

A seventh controlled runtime check preserves all four original ScopedDeclaration WITH bodies and adds observations after each block. Starting Count at 10 and -5, the original and current rewrite agree in all eight observations. The old rewrite differs, including `11,1` instead of `11,11`. This justified correcting three assertions in its existing DAK test. All three affected DAK tests fail with the old producer and pass with the current one. The exception path remains compiled and text-checked; it was not forced at runtime.

The six fixtures with complete cold/warm comparisons apply 16 planned edits and retain one unsupported handler skip. All fixture builds have zero warnings. Complete cold/warm plans match across all 18 fields outside generated run/workspace details, and original files remain unchanged.

The fresh MaxTdb planner emits the same complete 633-statement plan byte for byte as before the equivalent token-switch cleanup. This probe leaves API platform/configuration at the project defaults, which are Release/Linux64 in the pinned DPROJ. It does not certify explicit Win64 planning; the Win64 evidence below is compilation of the emitted edits. T-275 makes the benchmark context explicit before T-209 certification. Its 434 edits across 21 isolated units retain the earlier compiler result: zero errors and 445 identical inherited warning signatures. All generated compiler inputs and 709 original files were checked before reusing that result. No legacy application runtime or performance improvement is claimed.

Semantics and DAK project analysis, plus refreshed project-context PAL for the touched DAK test unit, pass report verification against compatible references. The token-switch cleanup removes all 216 new PAL missing-enum-case advisories without suppression. Two new FixInsight size advisories remain visible: the declaration scanner has 54 lines and the completeness method has 51. Other changed messages describe renamed tests or existing size/variable measurements; the argument helper loses its previous variable-count advisory.

The first full DAK run passed 658 of 659 tests and exposed the stale ScopedDeclaration expectation. After its compiler/runtime characterization and reviewed assertion correction, the DAK test build, focused tests, touched-unit PAL and full DAK suite were refreshed. The unchanged Semantics, SQLite and Python test inputs and production analysis inputs were verified before reusing those results.

The shared T-273/T-271/T-274 checkpoint passes 653 Semantics tests, 68 SQLite tests, 659 freshly built DAK tests and 110 Python analyzer tests. Explicit Win64 builds have zero owned compiler warnings; the three Semantics and four DAK vendor warnings are reported separately. This closes the inline-declaration task, while historical MaxTdb acceptance, performance certification, maintained-library ownership, external capabilities and T-127 approval remain open.

Exact commands, durations and hashes are retained in `projects/.dak/DelphiAIKit/goal-current/t274-task-proof.json`. The supporting records include `t274-token-runtime-proof.json`, `t274-token-maxtdb-parity.json`, `t274-dak-characterization-proof.json`, `t274-scoped-characterization-proof.json`, the three current analysis deltas, and the source/token-refactor/scoped-assertion reviews.


## Historical MaxTdb test migration, T-209

The fresh historical run after T-274/T-275 passes 40 of 203 tests. Its 163 failures have no new names or changed shared messages compared with the prior run. Three expectations were then corrected using retained compiler evidence.

In LINKFILE.InitRelation, Delphi cannot name `TMaskEntry` through DEKLARAT's imports. An isolated local `^TMaskEntry` declaration fails with E2003; adding the declaring unit directly makes the same project compile. Original and positive controls have zero errors and the same 445 inherited warning signatures. All 709 original files remain unchanged. The two affected tests now require the visibility skip, exact source text and ranges, and empty capture/edit data.

The L_Nr indexed-pointer test now checks capture-once initialization, both exact edit ranges and the complete replacement body. A fresh default-context API run matches the complete retained 633-statement plan byte for byte. All 702 isolated compiler inputs still match the successful 434-edit compiler proof. This establishes compilation of that output for Win64/Release; the historical API context remains project-default Release/Linux64.

The three updated tests and all 112 owning tests pass on a fresh Win64 runner. There are zero owned compiler warnings and three vendor warnings. Project-context PAL retains the same 323 actionable findings, with no additions or removals. Independent review passes. This is a partial T-209 checkpoint; the remaining historical tests, explicit Win64 API/CLI parity, timings and final certification remain open.

Evidence: `projects/.dak/DelphiAIKit/goal-current/t209-three-migrations-proof.json`, `t209-linkfile-visibility-compiler-proof.json`, `t209-current-default-parity.json` and `t209-three-migration-review.md`.


The next visibility group covers 13 tests and 16 statements in seven consumer units. Fourteen exact routine-scope probes fail with undeclared `TMaskEntry`; each direct-import positive control compiles with zero errors and the same 445 inherited warning signatures. The 709 original files remain unchanged. Three positive controls needed line-ending normalization around their inserted uses clauses; their raw evidence is preserved, and the normalized copies were rebuilt with identical warning signatures.

The migrated tests pin the full original source, source hashes and exact ranges, plus the visibility reason and empty capture/edit/recipe data. Six test names now describe their skip behavior. The three mixed tests remain untouched because their other assertions concern five planned rewrites and two children covered by parent rewrites. All 13 focused tests and all 653 standard Semantics tests pass. The Win64 build has zero owned warnings and three vendor warnings; PAL retains 323 actionable findings with no delta. Independent review passes. T-209 and its final gate remain open.

Evidence: `projects/.dak/DelphiAIKit/goal-current/t209-visibility-migrations-proof.json`, `t209-cohort-visibility-compiler-proof.json`, `t209-cohort-positive-hygiene-proof.json` and `t209-visibility-migration-review.md`.
