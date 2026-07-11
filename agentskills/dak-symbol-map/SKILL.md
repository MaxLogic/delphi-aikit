---
name: dak-symbol-map
description: Use DelphiAIKit `symbol-map` for cached Delphi project source indexing, definition lookup, symbol search, symbol description, reference-like token matches, and cache stats. Use this when Codex needs reusable project-wide symbol inventory or fast repeated lookup; prefer `dak-lsp` for editor-style hover/definition at one position and `dak-semantic-refactoring` for rename/apply workflows.
---

# DAK Symbol Map

Use `DelphiAIKit.exe symbol-map` when we need a reusable source index instead of a one-shot LSP probe.

If `DAK_EXE` is missing, use [dak-build setup](../dak-build/setup.md).

## Use When

- Build or refresh a project symbol index.
- Find a definition from a file/line/column.
- Search symbols by name.
- Describe a named symbol and optional owner.
- Get reference-like matches for a symbol.
- Inspect central/project cache status.

## Do Not Use For

- Compiler/build verification: use `dak-build`.
- Unit dependency topology: use `dak-project-unit-topology`.
- Global read/write ownership: use `dak-global-vars`.
- Transactional rename/apply work: use `dak-semantic-refactoring`.
- Broad raw text search: use `rg`.

## Canonical Commands

```bash
"$DAK_EXE" symbol-map stats --project "<path-to-project.dproj>" --format json
"$DAK_EXE" symbol-map index --project "<path-to-project.dproj>" --format json
"$DAK_EXE" symbol-map find-definition --project "<path-to-project.dproj>" --file "<path-to-unit.pas>" --line 42 --col 17 --format json
"$DAK_EXE" symbol-map search-symbols --project "<path-to-project.dproj>" --query "Customer" --limit 20 --format json
"$DAK_EXE" symbol-map describe-symbol --project "<path-to-project.dproj>" --symbol "Name" --owner "TCustomer" --format json
"$DAK_EXE" symbol-map find-references --project "<path-to-project.dproj>" --symbol "TCustomer" --limit 20 --format json
```

Use `--cache-root "<path>"` only when a run needs an isolated or disposable cache.

## Platform/Config

Pass `--platform` and `--config` when the target project requires a non-default context. For DelphiAIKit itself, use `--platform Win64`.

## Read Output

Prefer JSON. Report:

1. command and project analyzed
2. context/cache status when relevant
3. exact file/line/column for definitions or hits
4. confidence/provenance fields when present
5. limitations that affect the claim

`find-references` currently reports indexed token-name matches with explicit confidence metadata. Treat that as useful search evidence, not compiler-proven reference identity.

## Rules

1. Always pass a real project with `--project`; Symbol Map is project-context driven.
2. Let query commands refresh the project index when needed before answering.
3. Missing source-available RTL roots are diagnostics, not automatic failure; compiler intrinsics may still be seeded.
4. Do not delete caches to fix a result unless the user asks or the cache is clearly corrupt. Prefer `stats` first.
5. Finish behavior-changing work with `dak-build`; Symbol Map evidence is not build proof.
