# Delphi LSP Capability Probe Baseline

## Purpose

`DelphiAIKit.exe lsp probe` compares the capabilities of the installed external `DelphiLSP.exe` in two handshake modes:

- `contextFile`: DAK's generated `.dak/<ProjectName>/lsp/context.delphilsp.json`
- `settingsFile`: an official-style `.delphilsp.json` file plus `workspace/didChangeConfiguration`

Use the results to compare Delphi versions and handshake styles.

## Installed-server recheck, 2026-10-09 (DAK-349)

The installed `bin\DelphiAIKit.exe` (1.2.1.0) was checked against the unchanged
LspProjectFixture in Debug, on Win32 and Win64. The Delphi 12 server in
`Studio\23.0\bin` is version `29.0.53982.0329`; the Delphi 13 server in
`Studio\37.0\bin` is version `37.0.59082.6021`.

Both servers advertise the same nine capabilities listed below in both handshake
modes. Neither advertises `referencesProvider` or `workspaceSymbolProvider`.
All probe, hover and definition commands exited 0.

| Server | Platform | Method hover at `Unit1.pas:8:21` | Class hover at `13:18` | Definition at `8:21` |
| --- | --- | --- | --- | --- |
| Delphi 12 | Win32 | `class procedure TFixtureType.Run` | Not rerun | `Unit1.pas:13:1` |
| Delphi 12 | Win64 | `class procedure TFixtureType.Run` | Not rerun | `Unit1.pas:13:1` |
| Delphi 13 | Win32 | Empty | `type Unit1.TFixtureType = class(TObject)` | `Unit1.pas:13:1` |
| Delphi 13 | Win64 | Empty | `type Unit1.TFixtureType = class(TObject)` | `Unit1.pas:13:1` |

DAK-371 already supplies the compiler DLL setting needed for semantic hover.
That setting does not guarantee content at every symbol: the Delphi 13 method
hover is empty even though class hover and definition work. These observations
do not establish that the server accepted every supplied project setting.
Each invocation reports controlled process-tree termination, and no owned
DelphiLSP process remained after the checks.

Responses are retained under
`tests/fixtures/LspProjectFixture/.dak/LspProjectFixture/lsp/recheck-20261009/`.
The dated observations below remain historical evidence.

## Delphi 13 raw-protocol retry, 2026-09-08

The unchanged three-file fixture was copied into `projects/.dak/DelphiAIKit/goal-current/lsp-repro/`. DAK generated its project context for Win64 Debug using the installed Delphi 13 server, file version `37.0.59082.6021`. Four isolated raw sessions then tested a settings-file path, a settings-file URI, controller mode, and controller mode with `returnHoverModel: true`.

All four sessions initialized and shut down successfully. Definition at `Unit1.pas:8:21` returned `Unit1.pas:13:1`, and document symbols were non-empty. Hover returned `null` at all three positions (`8:21`, `6:7`, `13:32`) in every mode. Each direct references, workspace-symbol and rename request returned `-32601 Method not found`. No rename was applied. The fixture source hashes remained unchanged.

The missing methods remain unavailable in every tested initialization mode on this installed server. T-120 remains open until a supported server build or documented configuration returns references and useful hover content. On September 10 the maintainer dropped the T-127 LSP rename proposal and chose to concentrate on DelphiSemantics. No LSP rename provider or further T-127 design approval is planned. The historical raw rename probe remains capability evidence.

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

On the locally installed Delphi 23.0 and Delphi 13 servers, the missing external capabilities are not explained by the `contextFile` versus `settingsFile` handshake difference. Delphi 13 also does not add them.

Direct raw JSON-RPC checks against Delphi 13 confirm the same result:

- `textDocument/references` returns `-32601 Method not found`
- `workspace/symbol` returns `-32601 Method not found`

Even the documented `serverType: "controller"` startup mode does not expose those methods. Treat `references` and `workspace/symbol` as unsupported by these external Delphi LSP builds unless Embarcadero documents and ships support later.

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
