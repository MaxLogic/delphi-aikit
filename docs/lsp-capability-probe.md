# Delphi LSP Capability Probe Baseline

## Purpose

`DelphiAIKit.exe lsp probe` compares the installed external `DelphiLSP.exe` capability matrix across two handshake modes:

- `contextFile`: DAK's current owned `.dak/<ProjectName>/lsp/context.delphilsp.json` flow
- `settingsFile`: an official-style `.delphilsp.json` file plus `workspace/didChangeConfiguration`

This gives us a repeatable baseline across Delphi versions and handshake styles.

## Delphi 13 raw-protocol retry, 2026-09-08

The unchanged three-file fixture was copied into `projects/.dak/DelphiAIKit/goal-current/lsp-repro/`. DAK generated its project context for Win64 Debug using the installed Delphi 13 server, file version `37.0.59082.6021`. Four isolated raw sessions then tested a settings-file path, a settings-file URI, controller mode, and controller mode with `returnHoverModel: true`.

All four sessions initialized and shut down successfully. Definition at `Unit1.pas:8:21` returned `Unit1.pas:13:1`, and document symbols were non-empty. Hover returned `null` at all three positions (`8:21`, `6:7`, `13:32`) in every mode. Each direct references, workspace-symbol and rename request returned `-32601 Method not found`. No rename was applied. The fixture source hashes remained unchanged.

These fresh raw requests confirm that changing the documented initialization mode does not unblock the missing methods on this installed server. T-120 remains open. Its smallest unblock is a supported server build or documented configuration that returns references and useful hover content. On September 10 the maintainer dropped the T-127 LSP rename proposal and chose to concentrate on DelphiSemantics. No LSP rename provider or further T-127 design approval is planned. The historical raw rename probe remains capability evidence.

Exact requests, responses, settings and server hashes are retained in `projects/.dak/DelphiAIKit/goal-current/lsp-{path,uri,controller,hover-model}-20260908.json`. The probe script is `probe-lsp-raw.py` in the same folder. The configuration variants follow the [official DelphiLSP integration documentation](https://docwiki.embarcadero.com/RADStudio/Florence/en/Using_DelphiLSP_Code_Insight_with_Other_Editors).

## Delphi 13 recheck, 2026-09-07

Installed server: `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\DelphiLSP.exe`, file version `37.0.59082.6021`.

The fixture source files were copied unchanged into `tests/.dak/DelphiAIKit.Tests/task-retry-20260907/lsp-fixture/` to keep the probe's generated context separate from the running test suite. Both handshake modes advertise the same nine capabilities listed in the April baseline below. Neither advertises `referencesProvider` or `workspaceSymbolProvider`.

| Operation | Observed result |
| --- | --- |
| `probe` | Exit 0; both handshake modes succeeded. |
| `definition`, `Unit1.pas:8:21` | Exit 0; points to the implementation at `Unit1.pas:13:1`. |
| `symbols`, query `Fixture` | Exit 0; returns `TFixtureType` and `TFixtureType.Run`. |
| `hover`, `Unit1.pas:8:21` | Exit 0; empty contents. Checks at `6:7` and `13:32` were also empty. |
| `references` | Exit 2; the current DAK CLI rejects this unsupported operation before sending a server request. |

The `references` result above is a CLI check. The raw JSON-RPC `-32601` results below belong to the April audit and were not rerun in this recheck. T-125's installed-version recheck is complete; T-120's requirement for non-empty hover and references results remains unmet. DAK's own `find-usages` command is available for project-scoped reference searches.

Repeat from Windows PowerShell:

```powershell
$project = 'tests/fixtures/LspProjectFixture/LspProjectFixture.dproj'
$unit = 'tests/fixtures/LspProjectFixture/Unit1.pas'
$server = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\DelphiLSP.exe'
$context = @('--project', $project, '--delphi', '37.0', '--lsp-path', $server,
  '--platform', 'Win32', '--config', 'Debug', '--format', 'json')
& bin/DelphiAIKit.exe lsp probe @context
& bin/DelphiAIKit.exe lsp definition @context --file $unit --line 8 --col 21
& bin/DelphiAIKit.exe lsp hover @context --file $unit --line 8 --col 21
& bin/DelphiAIKit.exe lsp symbols @context --file $unit --query Fixture
& bin/DelphiAIKit.exe lsp references @context --file $unit --line 8 --col 21
```

Captured responses: `tests/.dak/DelphiAIKit.Tests/task-retry-20260907/lsp13-*.json`.

## Historical baseline

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
