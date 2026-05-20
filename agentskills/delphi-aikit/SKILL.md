---
name: delphi-aikit
description: "Route DelphiAIKit work to the correct repo-local skill. Use when Codex needs to choose between DAK build, static analysis, DFM validation, globals, dependency topology, LSP navigation, Symbol Map, or remove-with workflows before running commands."
version: "1.0"
---

# DelphiAIKit Skill Router

Use this skill first when the user asks for DelphiAIKit help and the right DAK workflow is not already obvious.

This is a router, not a command manual. Pick the target skill, load it, and follow that skill as the source of truth.

## Routing Table

| User intent | Load skill | Why |
| --- | --- | --- |
| Build, rebuild, compiler errors, `--ai` build hints | `delphi-build` | Owns project build orchestration and build failure handling |
| DFM forms, frames, datamodules, DFM stream validation | `delphi-dfm-check` | Owns `dfm-inspect`, `dfm-check`, and `build --dfmcheck` |
| Static analysis, FixInsight, Pascal Analyzer, warnings cleanup | `delphi-static-analysis` | Owns analyzer orchestration and conservative triage |
| Project globals, shared mutable state, reads/writes, unused globals | `delphi-global-vars` | Owns `global-vars` inventory and JSON interpretation |
| Unit dependency graph, unresolved units, cycles, hotspot candidates | `delphi-project-unit-topology` | Owns `deps` topology reports |
| Symbol definition, hover, file-scoped symbol lookup | `delphi-lsp` | Owns editor-style semantic navigation through DelphiLSP |
| `with` statement discovery, planning, removal, rollback reports | `delphi-remove-with` | Owns `remove-with` scan/plan/apply workflow |
| Raw text, exact strings, broad repository search | no DAK skill | Use `rg`; do not force semantic tooling onto text search |

## Combination Rules

1. For refactoring work, run analysis before editing and build after editing.
2. For UI/form work, combine the implementation flow with `delphi-dfm-check`.
3. For dependency cleanup, use `delphi-project-unit-topology` before and after the change.
4. For globals cleanup, use `delphi-global-vars` for the decision surface and `delphi-build` for final verification.
5. For `with` cleanup, use `delphi-remove-with`; do not route the resolver through `delphi-lsp`.
6. For compiler errors, start with `delphi-build`. Use `delphi-lsp` only as optional navigation after the build output identifies a meaningful location.

## Overlap Rules

- `lsp` answers local navigation questions; it is not the bulk refactoring engine.
- `deps` answers unit topology; it does not answer symbol ownership or read/write usage.
- `global-vars` answers project-level global state usage; it is not a general reference finder.
- `remove-with` owns `with` statement rewrites and its own safety model.
- Static analysis findings are not proof of build correctness; finish code changes with a build/test gate.

## Output Discipline

When reporting which workflow we chose, state:

- the selected skill
- the reason it matches the user intent
- any secondary skill needed for verification

Then load the selected skill and follow it. Do not duplicate command syntax here unless the target skill is missing or unavailable.
