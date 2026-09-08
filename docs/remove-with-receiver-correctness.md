# Remove-with receiver correctness, 2026-09-08

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
