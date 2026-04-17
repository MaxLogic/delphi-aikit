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

- Verified today against external Delphi 23 `DelphiLSP.exe`: `definition`, `hover`, and file-scoped `documentSymbol`-backed `symbols` are available; `references` remains version-gated.
- We will revisit Delphi 13.x as soon as it is installed locally.
