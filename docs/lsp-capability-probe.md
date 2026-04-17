# Delphi LSP Capability Probe Baseline

## Purpose

`DelphiAIKit.exe lsp probe` compares the installed external `DelphiLSP.exe` capability matrix across two handshake modes:

- `contextFile`: DAK's current owned `.dak/<ProjectName>/lsp/context.delphilsp.json` flow
- `settingsFile`: an official-style `.delphilsp.json` file plus `workspace/didChangeConfiguration`

This gives us a repeatable baseline before revisiting Delphi 13.x.

## Current Delphi 23.0 Baseline

Date: 2026-04-17

Project fixture:
`tests/fixtures/LspProjectFixture/LspProjectFixture.dproj`

Server:
`C:\Program Files (x86)\Embarcadero\Studio\23.0\bin64\DelphiLSP.exe`

Both handshake modes currently advertise the same capability matrix:

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
On the locally installed Delphi 23.0 server, the missing external capabilities are not explained by the `contextFile` versus `settingsFile` handshake difference. We should treat them as version or upstream-surface limits until Delphi 13.x is installed and rechecked.

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
