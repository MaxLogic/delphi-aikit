---
name: dak-remove-with
description: "Use DelphiAIKit `remove-with` to inspect, plan, and transactionally apply conservative Delphi `with` statement rewrites. Use when Codex needs to remove or assess `with` statements, produce a safe refactoring plan, review skip reasons, or verify rollback/build behavior for `with` cleanup."
---

# Delphi Remove With

Use `DelphiAIKit.exe remove-with` for Delphi `with` statement discovery and conservative rewrite planning.

If `DAK_EXE` is missing, use [dak-build setup](../dak-build/setup.md).

Preflight:

```bash
test -x "$DAK_EXE" || { echo "DAK_EXE not executable"; exit 1; }
```

## Route The Request

| User intent | Use | Notes |
| --- | --- | --- |
| "Do we have `with` statements?" | `remove-with --mode scan --format json` | Non-mutating inventory only |
| "Can these be safely removed?" | `remove-with --mode plan --format json` | Produces planned edits, warnings, and skipped reasons without changing files |
| "Remove these `with` statements" | `remove-with --mode apply --format json` | Writes safe edits transactionally, runs build verification, and rolls back on failure |
| "Why was this skipped?" | inspect plan JSON | Read resolver classifications, skipped reasons, and warnings |
| "Should we use LSP for this?" | no | `remove-with` uses DAK's local AST/source model, not DelphiLSP, for bulk refactoring |

Start with `plan` unless the user only asks for an inventory. Use `apply` only after reviewing the plan output or when the user explicitly asks for the refactor to be applied.

## Command Patterns

Whole project:

```bash
"$DAK_EXE" remove-with --project "<path-to-project.dproj>" --all --mode plan --format json --output "<path-to-report.json>"
```

Directory scope:

```bash
"$DAK_EXE" remove-with --project "<path-to-project.dproj>" --dir "<path-to-src-dir>" --mode plan --format json --output "<path-to-report.json>"
```

Single unit:

```bash
"$DAK_EXE" remove-with --project "<path-to-project.dproj>" --unit "<path-to-unit.pas>" --mode plan --format json --output "<path-to-report.json>"
```

Apply reviewed safe edits:

```bash
"$DAK_EXE" remove-with --project "<path-to-project.dproj>" --unit "<path-to-unit.pas>" --mode apply --format json --output "<path-to-report.json>"
```

## Rules

1. Always pass a real Delphi project with `--project`/`--dproj`; `remove-with` is project-context-driven.
2. Target exactly one scope: `--unit`, `--dir`, or `--all`.
3. Prefer JSON output for agent work. Use `--output "<path>"` for durable reports, or `--output -` when stdout must stay machine-readable.
4. Treat `plan` as the normal first refactoring step. It is non-mutating and reports what would change.
5. Treat skipped statements as a safety feature, not a tool failure. Do not force a rewrite for ambiguous, unresolved, external, unsupported, non-addressable, property, call, controlled statement, or source-unavailable cases.
6. Do not use DelphiLSP as the primary resolver for this workflow. LSP can help with separate navigation questions, but `remove-with` relies on DAK's local AST/source model.
7. `apply` creates a run workspace under `.dak/<ProjectName>/remove-with/<RunId>/`, backs up changed files, writes a manifest, runs build verification, and rolls back exact bytes on verification failure.
8. If applying to proprietary or external fixtures, work on a temp clone unless the user explicitly allows editing the original project.
9. After `apply`, verify the reported transaction status, changed/restored file list, and build gate result before calling the task done.

## Read The JSON

Important fields to inspect:

- `summary.withStatements`
- `summary.plannedEdits`
- `summary.skipped`
- `files[*].withStatements[*].selectorText`
- `files[*].withStatements[*].plannedEdits`
- `files[*].withStatements[*].skippedReasons`
- `warnings`
- `verification`
- `transaction`
- `manifestPath`

Report both the useful edits and the skipped/ambiguous cases. A clean answer should say whether the run was `scan`, `plan`, or `apply`, which scope was analyzed, how many `with` statements were found, how many edits were planned/applied, and whether verification passed.
