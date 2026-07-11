---
name: dak-semantic-refactoring
description: Use DelphiAIKit project-scoped semantic commands for find-usages, rename dry-runs/apply, and dead-code review or guarded apply. Use this when Codex needs declaration-aware usage evidence, safe rename planning, conservative dead-code inspection, or explicitly approved transactional dead-code removal; prefer `dak-symbol-map` for index/search queries and never treat dead-code reports as automatic deletion approval.
---

# DAK Semantic Refactoring

Use DAK semantic refactoring commands when the answer depends on declaration-aware project context.

If `DAK_EXE` is missing, use [dak-build setup](../dak-build/setup.md).

## Use When

- Find usages of a symbol by name or source position.
- Plan a rename and review the affected files before applying.
- Apply a reviewed rename when the user explicitly wants the edit.
- Produce a dead-code report for inspection.
- Apply explicitly approved dead-code removals transactionally with build verification and rollback.

## Do Not Use For

- Build errors: use `dak-build`.
- Bulk text search: use `rg`.
- Unit graph/cycle questions: use `dak-project-unit-topology`.
- Global read/write inventory: use `dak-global-vars`.
- `with` rewrite planning: use `dak-remove-with`.

## Canonical Commands

```bash
"$DAK_EXE" find-usages --project "<path-to-project.dproj>" --symbol "OldName" --format json
"$DAK_EXE" find-usages --project "<path-to-project.dproj>" --file "<path-to-unit.pas>" --line 42 --col 17 --format json
"$DAK_EXE" rename --project "<path-to-project.dproj>" --symbol "OldName" --new-name "NewName" --format text
"$DAK_EXE" rename --project "<path-to-project.dproj>" --symbol "OldName" --new-name "NewName" --apply --format json
"$DAK_EXE" dead-code --project "<path-to-project.dproj>" --profile conservative --format json
"$DAK_EXE" dead-code --project "<path-to-project.dproj>" --profile conservative --apply --format json
```

Pass `--platform` and `--config` when the target project requires a non-default context. For DelphiAIKit itself, use `--platform Win64`.

## Rename Workflow

1. Run `find-usages` first when identity is unclear.
2. Run `rename` without `--apply` and review the plan.
3. Check ambiguous names, DFM handlers, RTTI-visible members, package boundaries, generated code, and external callers.
4. Use `--apply` only after the plan is acceptable or the user explicitly asked for the edit.
5. Verify the changed project with `dak-build`.

## Dead-Code Workflow

Dead-code output is review evidence, not deletion proof. The default command is report-only and non-mutating.

Before removing anything, inspect:

- RTTI and published members
- DFM event handlers
- exports and message methods
- initialization/finalization hooks
- registration calls
- package boundaries and external callers

Report findings as `definitely-unused`, `maybe-unused`, `externally-visible`, or `blocked` when the output supports that distinction.

Use `--apply` only when the user explicitly requests removal and after reviewing a run with the same explicit `--profile`. Apply mode creates project-scoped backups/manifests, verifies the build, and rolls back on verification failure. Confirm the transaction and verification fields before reporting completion.

## Output Discipline

State the project, command, symbol identity, number of usages/edits/findings, and unresolved or ambiguous cases. If confidence is degraded, say why and stop before destructive edits.
