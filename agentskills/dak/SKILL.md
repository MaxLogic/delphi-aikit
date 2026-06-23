---
name: dak
description: "Route DAK (DelphiAIKit) work to the correct repo-local skill. Use when Codex needs to choose between DAK build, static analysis, DFM validation, globals, dependency topology, LSP navigation, Symbol Map, semantic refactoring, or remove-with workflows before running commands."
version: "1.0"
---

# DAK Skill Router

Use this skill first when the user asks for DAK or DelphiAIKit help and the right workflow is not already obvious.

This is a router, not a command manual. Pick the target skill, load it, and follow that skill as the source of truth.

## Routing Table

| User intent | Load skill | Why |
| --- | --- | --- |
| Build, rebuild, compiler errors, TMS WEB Core builds, `--ai` build hints | `dak-build` | Owns Delphi and WebCore project build orchestration and build failure handling |
| DFM forms, frames, datamodules, DFM stream validation | `dak-dfm-check` | Owns `dfm-inspect`, `dfm-check`, and `build --dfmcheck` |
| Static analysis, FixInsight, Pascal Analyzer, warnings cleanup | `dak-static-analysis` | Owns analyzer orchestration and conservative triage |
| Project globals, shared mutable state, reads/writes, unused globals | `dak-global-vars` | Owns `global-vars` inventory and JSON interpretation |
| Unit dependency graph, unresolved units, cycles, hotspot candidates | `dak-project-unit-topology` | Owns `deps` topology reports |
| Symbol definition, hover, file-scoped symbol lookup | `dak-lsp` | Owns editor-style semantic navigation through DelphiLSP |
| Cached project symbol index, definition lookup, symbol search, symbol description, reference-like matches | `dak-symbol-map` | Owns `symbol-map` project indexing and cache-backed lookup |
| Find usages, rename plan/apply, dead-code reports | `dak-semantic-refactoring` | Owns DAK semantic refactoring commands and safety review |
| `with` statement discovery, planning, removal, rollback reports | `dak-remove-with` | Owns `remove-with` scan/plan/apply workflow |
| Raw text, exact strings, broad repository search | no DAK skill | Use `rg`; do not force semantic tooling onto text search |

## Combination Rules

1. For refactoring work, run analysis before editing and build after editing.
2. For UI/form work, combine the implementation flow with `dak-dfm-check`.
3. For dependency cleanup, use `dak-project-unit-topology` before and after the change.
4. For globals cleanup, use `dak-global-vars` for the decision surface and `dak-build` for final verification.
5. For general rename/usages/dead-code work, use `dak-semantic-refactoring`; use `dak-symbol-map` for non-mutating symbol index questions.
6. For `with` cleanup, use `dak-remove-with`; do not route the resolver through `dak-lsp`.
7. For compiler errors, start with `dak-build`. Use `dak-lsp` only as optional navigation after the build output identifies a meaningful location.

## Overlap Rules

- `lsp` answers local navigation questions; it is not the bulk refactoring engine.
- `symbol-map` answers cached project index questions; reference hits are useful search evidence, not full rename/apply proof.
- `deps` answers unit topology; it does not answer symbol ownership or read/write usage.
- `global-vars` answers project-level global state usage; it is not a general reference finder.
- `find-usages`, `rename`, and `dead-code` belong to semantic refactoring, not Symbol Map or LSP.
- `remove-with` owns `with` statement rewrites and its own safety model.
- Static analysis findings are not proof of build correctness; finish code changes with a build/test gate.

## Output Discipline

When reporting which workflow we chose, state:

- the selected skill
- the reason it matches the user intent
- any secondary skill needed for verification

Then load the selected skill and follow it. Do not duplicate command syntax here unless the target skill is missing or unavailable.
