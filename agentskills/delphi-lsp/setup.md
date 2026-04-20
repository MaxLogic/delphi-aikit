# Setup

Required:

- `DAK_EXE`: absolute path to `DelphiAIKit.exe`

Example WSL setup:

```bash
export DAK_EXE="/mnt/f/projects/MaxLogic/DelphiAiKit/bin/DelphiAIKit.exe"
```

Smoke check:

```bash
test -x "$DAK_EXE"
```
Version note:

- Verified against external Delphi 23 (`23.0`) and Delphi 13 (`37.0`) `DelphiLSP.exe`: `definition`, `hover`, and file-scoped `documentSymbol`-backed `symbols` are available.
- Verified absent on both versions: `textDocument/references` (`referencesProvider`) and `workspace/symbol` (`workspaceSymbolProvider`). Direct raw JSON-RPC requests return `-32601 Method not found`.
- Prefer `deps`, `global-vars`, or `rg` when we need usages or broad search instead of semantic definition/hover/file-symbol navigation.
