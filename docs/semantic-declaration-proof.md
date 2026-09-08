# Semantic declaration verification, 2026-09-08

The T-257/T-258/T-259 batch corrects inline declaration extraction and typed-constant handling in DelphiSemantics. It completes the related declaration-scope, globals and cache changes already present in the working tree.

Inline `const` and `var` declarations retain their source positions. Shared symbol queries retain read-only typed constants, while mutable-global reports exclude them. Mutability follows active compiler directives in source order, including inline switches and includes; examples in comments and strings have no effect. Parser identity 6 invalidates older unit models, and snapshot identity v7 retains immutable symbols with an explicit flag.

Retained regressions cover extraction and rename positions, declaration/header boundaries, real SQLite cold/warm reuse and obsolete-cache rejection, and directive ordering. Independent review found two additional include/comment-order defects; each received its own failing regression and correction. Isolated Delphi 12 compiler controls confirm which constants permit assignment.

| Check | Result |
| --- | --- |
| DAK production, Win64 Release rebuild | Zero owned warnings; four identified vendor warnings |
| DAK tests, Win64 Debug rebuild | Zero owned warnings; four identified vendor warnings |
| DelphiSemantics tests, Win64 Release rebuild | Zero owned warnings; three vendor lexer warnings |
| Fresh `tests/DelphiAIKit.Tests.exe` | 656/656; zero ignored, failed, errored or leaked |
| Fresh `DelphiSemantics/tests/bin/delphiSemanticsTests.exe` | 604/604; zero ignored, failed, errored or leaked |
| Python analyzer tests | 110/110 |
| Focused Semantics fixtures | UnitModel 64, Preprocess 19, Cache 66, ProjectSession 46, GlobalVars 6; all pass |
| Complete ordered rewrite plan comparison | 24 planned, 2 covered, 0 skipped; text, ranges and order match |
| DAK full analysis | 898 actionable findings, unchanged; zero unknown ownership |
| Semantics full analysis | 845 actionable findings; zero owned FixInsight warnings, PAL strong findings or unknown ownership |

Both analyzer report sets pass `postprocess.py --verify`. Current baselines initialize the rebuilt executable/context; they do not independently prove historical compatibility. Separate raw finding comparisons show no new production PAL findings. One removed unused-variable row is balanced by an intentional obsolete-cache priming call in a test. FixInsight adds three maintainability rows: the directive handler and the snapshot regression's length/local count. Changed existing metrics remain visible. DAK's inherited owned PAL strong finding also remains recorded.

The standard Semantics runner excludes `MaxTdbProof` under its existing policy. That historical category, fresh workflow benchmarks, T-212 certification and upstream capability checks remain separate open work. These results do not certify those tasks or complete the overall goal.

Exact commands, durations, input manifests, executable hashes, RED/GREEN logs, review scope and raw deltas are retained locally under `projects/.dak/DelphiAIKit/goal-current/`, starting with `t259-task-proof.json` and `t259-batch-proof.json`. The analysis-generated resource matches the previously audited RT_VERSION-only change; the original tracked resource was restored and executable hashes remained unchanged. Existing ignore policy is preserved.
