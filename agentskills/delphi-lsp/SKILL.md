---
name: delphi-lsp
description: "Use DelphiAIKit `lsp` for semantic Delphi symbol navigation through `definition`, `hover`, file-scoped `symbols`, and version-gated `references`, and route non-semantic questions to `deps`, `global-vars`, or text search instead of guessing."
version: "1.0"
---

# Delphi LSP

Use `DelphiAIKit.exe lsp` for one-shot semantic navigation against a real Delphi project context.

Load [setup.md](setup.md) first.

Preflight:

```bash
test -x "$DAK_EXE" || { echo "DAK_EXE not executable"; exit 1; }
```

## Route The Request

Use this routing before running commands:

| User intent | Command | Notes |
| --- | --- | --- |
| "Where is this symbol defined?" | `lsp definition --format json` | Requires `--file`, `--line`, `--col` |
| "Who references this symbol?" | `lsp references --format json` | Version-gated; if unsupported by the external DelphiLSP build, fall back to `deps`, `global-vars`, or `rg` |
| "What does this symbol mean here?" | `lsp hover --format json` | Use when hover/type text matters |
| "Find symbols matching this name" | `lsp symbols --format json` | File-scoped on Delphi 23 external `DelphiLSP.exe`; pass `--file`, then use `--query` and optional `--limit` |
| "What depends on what?" / "Do we have cycles?" | switch skill | `delphi-project-unit-topology` |
| "Who reads or writes this global?" | switch skill | `delphi-global-vars` |
| broad raw text / regex search | text search | use `rg`, not `lsp` |

Start with JSON unless the user explicitly wants a quick terminal summary.

## Command Patterns

Definition:

```bash
"$DAK_EXE" lsp definition --project "<path-to-project.dproj>" --file "<path-to-unit.pas>" --line 42 --col 17 --format json
```

References:

```bash
"$DAK_EXE" lsp references --project "<path-to-project.dproj>" --file "<path-to-unit.pas>" --line 42 --col 17 --include-declaration false --format json
```

Hover:

```bash
"$DAK_EXE" lsp hover --project "<path-to-project.dproj>" --file "<path-to-unit.pas>" --line 42 --col 17 --format json
```

Symbols:

```bash
"$DAK_EXE" lsp symbols --project "<path-to-project.dproj>" --file "<path-to-unit.pas>" --query "Customer" --limit 20 --format json
```

## Rules

1. Always pass a real Delphi project with `--project`/`--dproj`; `lsp` is project-context-driven, not file-only.
2. `--line` and `--col` are 1-based.
3. `symbols` is file-scoped on Delphi 23 external `DelphiLSP.exe`; pass `--file` and read the result as `textDocument/documentSymbol`, not as workspace-wide search.
4. `references` is version-gated on the external DelphiLSP capability set. If `referencesProvider` is absent, fall back to `deps`, `global-vars`, or `rg` instead of pretending the capability exists.
5. `--rsvars` and `--envoptions` are optional advanced overrides. Do not add them unless normal context discovery fails or we need reproducible nonstandard setup.
6. DAK owns generated context and logs under sibling `.dak/<ProjectName>/lsp/`. Do not create ad hoc `.delphilsp.json` files beside the source project for normal use.
7. `lsp` hard-fails when DAK cannot build a real Delphi semantic context. Do not treat that as equivalent to `deps`, `global-vars`, or text search.
8. Delphi 13.x will be revisited as soon as it is installed locally; current external-server guidance is based on verified Delphi 23 behavior.
9. Do not emulate raw JSON-RPC or call `DelphiLSP.exe` directly when `DelphiAIKit.exe lsp` can answer the question.

## Read The JSON

The important result fields are:

- `definition`: `result.locations[]`
- `references`: `result.references[]` when the external DelphiLSP build supports `textDocument/references`
- `hover`: `result.contentsText`, optional `result.contentsMarkdown`, optional `result.range`
- `symbols`: `result.symbols[]` from file-scoped `documentSymbol` output

Use the normalized DAK fields (`file`, `line`, `col`, and related range fields) instead of reasoning about raw LSP URIs or 0-based coordinates.
