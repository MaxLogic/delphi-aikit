# Delphi LSP Capability Probe Baseline

## Purpose

`DelphiAIKit.exe lsp probe` compares the installed external `DelphiLSP.exe` capability matrix across two handshake modes:

- `contextFile`: DAK's current owned `.dak/<ProjectName>/lsp/context.delphilsp.json` flow
- `settingsFile`: an official-style `.delphilsp.json` file plus `workspace/didChangeConfiguration`

This gives us a repeatable baseline across Delphi versions and handshake styles.

## Current Baseline

Date: 2026-04-20

Project fixture:
`tests/fixtures/LspProjectFixture/LspProjectFixture.dproj`

Servers:
`C:\Program Files (x86)\Embarcadero\Studio\23.0\bin64\DelphiLSP.exe`
`C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\DelphiLSP.exe`

Both Delphi 23.0 and Delphi 13 (`37.0`) advertise the same capability matrix in both handshake modes:

- `textDocumentSync`
- `definitionProvider`
- `declarationProvider`
- `implementationProvider`
- `documentSymbolProvider`
- `hoverProvider`
- `completionProvider`
- `signatureHelpProvider`
- `publishDiagnostics`

Not advertised in either mode:

- `referencesProvider`
- `workspaceSymbolProvider`

Conclusion:
On the locally installed Delphi 23.0 and Delphi 13 servers, the missing external capabilities are not explained by the `contextFile` versus `settingsFile` handshake difference. Delphi 13 also does not add them.

Direct raw JSON-RPC checks against Delphi 13 confirm the same result:

- `textDocument/references` returns `-32601 Method not found`
- `workspace/symbol` returns `-32601 Method not found`

Even the documented `serverType: "controller"` startup mode does not expose those methods. We should treat `references` and `workspace/symbol` as unsupported on the external Delphi LSP surface unless Embarcadero documents and ships them later.

## Commands

Capability comparison:

```bash
./bin/DelphiAIKit.exe lsp probe \
  --project /mnt/f/projects/MaxLogic/DelphiAiKit/tests/fixtures/LspProjectFixture/LspProjectFixture.dproj \
  --delphi 23.0 \
  --lsp-path "/mnt/c/Program Files (x86)/Embarcadero/Studio/23.0/bin64/DelphiLSP.exe" \
  --mode contextFile \
  --mode settingsFile
```

Official-style handshake details:

```bash
./bin/DelphiAIKit.exe lsp probe \
  --project /mnt/f/projects/MaxLogic/DelphiAiKit/tests/fixtures/LspProjectFixture/LspProjectFixture.dproj \
  --delphi 23.0 \
  --lsp-path "/mnt/c/Program Files (x86)/Embarcadero/Studio/23.0/bin64/DelphiLSP.exe" \
  --mode settingsFile \
  --show-init-options
```
