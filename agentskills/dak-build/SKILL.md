---
name: dak-build
description: Build Delphi and TMS WEB Core projects via DelphiAIKit from WSL or Windows. Use when asked to compile or rebuild a .dproj (or .dpr/.dpk with sibling .dproj), verify build output, or troubleshoot build failures.
---

# DAK Build

Use this execution order:

1. Read repository/user execution-domain rules. They decide Windows versus WSL.
2. Use `DelphiAIKit.exe build ...` as the canonical interface for both Delphi and TMS WEB Core projects.
3. Use `"$DAK_BUILD_SH" ...` only when WSL is authorized and wrapper path conversion is helpful for a regular Delphi project.
4. Never call raw `msbuild.exe` unless we are explicitly debugging wrappers.
5. Do not use the legacy `build-webcore` scripts when `DelphiAIKit.exe build` is available.

For a Windows-only repository, invoke the Windows executable from PowerShell or
`cmd.exe`; do not start WSL merely to call the same executable. Never let a DAK
helper make a Linux-native process open a Windows-owned database, fixture,
output, lock file, or other mutable runtime resource.

If `DAK_EXE` is missing, use [setup.md](setup.md) to define it and optional WSL helpers.
Commands assume current directory is the target repository root.

Supported project inputs (`--project`):

- `.dproj`
- `.dpr` / `.dpk` only when a sibling `.dproj` exists
- `.groupproj` is not a guaranteed DAK contract in current code

## Platform Rule

Use the target project's required platform. When building or testing DelphiAIKit itself, use `Win64`; this repo's `AGENTS.md` makes DAK a Win64 tool and the DAK test project should not fall back to implicit Win32 defaults.

TMS WEB Core builds use `TMSWebCompiler.exe`, not MSBuild. `--platform`, `--delphi`, `--rsvars`, `--dfmcheck`, `--define`, and `--unit-search-path` are Delphi-backend concerns; avoid them for WebCore unless DAK explicitly requires otherwise.

## Preflight

Windows PowerShell (`powershell.exe` or Windows-native `pwsh` as policy allows):

```powershell
$DakExe = (Get-Command $env:DAK_EXE -ErrorAction Stop).Source
if (-not (Test-Path -LiteralPath $DakExe -PathType Leaf)) {
  throw "DAK_EXE does not resolve to a file: $DakExe"
}
```

WSL, only when the target repository authorizes it:

```bash
test -x "$DAK_EXE" || { echo "DAK_EXE not executable"; exit 1; }
if grep -qi microsoft /proc/version 2>/dev/null; then
  if [ -n "${DAK_BUILD_SH:-}" ]; then
    test -x "$DAK_BUILD_SH" || { echo "DAK_BUILD_SH is set but not executable"; exit 1; }
  fi
fi
```

## WSL path conversion (only when WSL is authorized)

`DelphiAIKit.exe build --project` accepts both:

- Linux-style absolute paths from WSL only in `/mnt/<drive>/...` form
- Windows-style absolute paths (`F:\...`)

Other Linux absolute paths (for example `/home/...`) are rejected with a clear error.
`wslpath` conversion remains our canonical safe route, and also helps compatibility with older DelphiAIKit builds.

```bash
PROJECT_LINUX="<path-to-project.dproj>"
PROJECT_WIN="$(wslpath -w -a "$PROJECT_LINUX")"
```

## WSL (when authorized by the target repository)

Regular Delphi build:

Canonical build:

```bash
PROJECT_LINUX="src/App.dproj" # Replace with a project whose policy authorizes WSL.
PLATFORM="${DAK_PLATFORM:-Win32}"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform "$PLATFORM" --config Debug --ai
```

Full rebuild:

```bash
PROJECT_LINUX="src/App.dproj" # Replace with a project whose policy authorizes WSL.
PLATFORM="${DAK_PLATFORM:-Win32}"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform "$PLATFORM" --config Debug --target Rebuild --ai
```

Locked-output-safe rebuild (for `F2039` / running EXE):

```bash
PROJECT_LINUX="src/App.dproj" # Replace with a project whose policy authorizes WSL.
PLATFORM="${DAK_PLATFORM:-Win32}"
TEST_OUT_WIN="$(wslpath -w -a _build_verify/test-out)"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform "$PLATFORM" --config Debug --target Rebuild --test-output-dir "$TEST_OUT_WIN" --ai
```

Profiler/compiler overlay build:

Use this when a Delphi project needs temporary compiler context, such as a MaxProfiler build, and editing the project file is not appropriate. Prefer an existing project `Profiling` config when one already carries the required defines/search paths.

```bash
PROJECT_LINUX="src/maxtdb.dproj"
PLATFORM="${DAK_PLATFORM:-Win64}"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform "$PLATFORM" --config Debug \
  --target Rebuild --define maxProfiling \
  --unit-search-path "/mnt/f/projects/MaxLogic/profiling/src/runtime" --ai
```

Use typed `--define` and `--unit-search-path` overlays instead of raw MSBuild `/p:DCC_Define=...` or `/p:DCC_UnitSearchPath=...` injection. Raw `msbuild.exe` is only for debugging DAK or wrapper behavior.

WSL wrapper (`build-delphi.sh`) example:

```bash
PROJECT_LINUX="src/App.dproj" # Replace with a project whose policy authorizes WSL.
PLATFORM="${DAK_PLATFORM:-Win32}"
"$DAK_BUILD_SH" "$PROJECT_LINUX" -config Debug -platform "$PLATFORM" -ver 23 -ai
```

TMS WEB Core build:

```bash
PROJECT_LINUX="Mobile-Solution/FrontEnd/KFZMeisterPWA/KFZMeisterPWA.dproj"
"$DAK_EXE" build --project "$PROJECT_LINUX" --builder webcore --config Debug \
  --webcore-compiler "/mnt/f/TMS-SmartSetUp/Products/tms.webcore/Bin/Win64/TMSWebCompiler.exe" --ai
```

For WebCore projects with strong markers such as `TMSWebProject`, `TMSWebHTMLFile`, or `TMSWEBCorePkg...`, `--builder` can usually be omitted and `auto` will select the WebCore backend:

```bash
"$DAK_EXE" build --project "$PROJECT_LINUX" --config Debug \
  --webcore-compiler "/mnt/f/TMS-SmartSetUp/Products/tms.webcore/Bin/Win64/TMSWebCompiler.exe" --ai
```

## Windows

PowerShell:

```powershell
$Project = "F:\projects\SomeRepo\_Source\App.dproj"
$Platform = if ($env:DAK_PLATFORM) { $env:DAK_PLATFORM } else { "Win32" }
& $env:DAK_EXE build --project $Project --delphi 23.0 --platform $Platform --config Debug --ai
```

TMS WEB Core:

```powershell
$Project = "F:\projects\SomeRepo\WebApp\WebApp.dproj"
& $env:DAK_EXE build --project $Project --builder webcore --config Debug --webcore-compiler "F:\TMS-SmartSetUp\Products\tms.webcore\Bin\Win64\TMSWebCompiler.exe" --ai
```

## Setup

Use [setup.md](setup.md) to define `DAK_EXE` and optionally `DAK_BUILD_SH`.

## Defaults

- tool default: `platform=Win32`, `config=Release`, `target=Build`
- builder default: `auto`; strong TMS WEB Core project markers route to the WebCore backend
- DelphiAIKit repo work: pass `--platform Win64` explicitly
- WebCore compiler resolution order: `--webcore-compiler`, cascading `dak.ini` `[WebCore].CompilerPath`, `DAK_TMSWEB_COMPILER`, then `PATH`
- `max-findings=5`
- `build-timeout-sec=0`
- `source-context=auto`, `source-context-lines=2`
- warnings and hints hidden unless requested
- when `--ai` is enabled, DAK may append best-effort `lsp` semantic hints to build failures; missing or empty LSP data is expected and must not fail the build

## Key Flags

- `--target Build|Rebuild`, `--rebuild true|false`
- `--builder auto|delphi|webcore`
- `--webcore-compiler "<path-to-TMSWebCompiler.exe>"`
- `--pwa`, `--no-pwa`
- `--max-findings N`
- `--build-timeout-sec N`
- `--test-output-dir "<path>"`
- `--define <symbol>` (repeatable Delphi/MSBuild compiler define overlay)
- `--unit-search-path "<path>"` (repeatable Delphi/MSBuild unit search path overlay)
- `--dfmcheck` (presence flag; when present, run DFM validation after a successful build)
- `--dfm "<file.dfm[,file2.dfm]>"` (DFM scope for `--dfmcheck`; selected forms only)
- `--all` (DFM scope for `--dfmcheck`; validate all forms, default when `--dfm` is omitted)
- `--source-context auto|off|on`
- `--source-context-lines N`
- `--rsvars "<path>"` (overrides `rsvars.bat` for build and post-build DFM check)
- `--show-warnings`, `--show-hints`
- `--ai`, `--json`, `--verbose [true|false]`

## Workflow

## Artifact Policy

- Never place build outputs, disposable build clones, or DAK-generated state under `.agents/`.
- Prefer the normal project output for an ordinary build.
- Use `--test-output-dir` with a unique OS temporary directory when verification must avoid a locked or dirty project output.
- Remove verified disposable test-output directories after the proof is recorded; never remove normal project outputs merely as routine cleanup.

### Regular Delphi

1. Run build with `--ai`.
2. Add `--dfmcheck` when we want build + DFM streaming validation in one call.
3. Use `--dfm "<...>"` for targeted checks or `--all` for full checks (default scope).
4. If no Delphi version is passed to standalone `dfm-check`, ensure cascading `dak.ini` provides `[Build] DelphiVersion`.
5. In full-scope validation, reruns may skip unchanged forms via `<Project>.dfmcheck.cache`.
6. If automation needs structured output, rerun with `--json`.
7. If output is locked, follow repository policy for a safely identifiable process; otherwise use a unique temporary `--test-output-dir`.
8. Leave `--source-context` at `auto` unless we explicitly need more or less surrounding source.
9. Report actionable diagnostics with exact failing unit/error line and next fix step.
10. If `--ai` emits no semantic hints, keep the original compiler failure intact and continue with the source-context evidence we already have.

### TMS WEB Core

1. Run `DelphiAIKit.exe build --project <app.dproj> --config <Debug|Release>
   --ai` with the selected host's PowerShell or Bash syntax shown above.
2. Add `--builder webcore` when we want explicit backend selection or when auto-detection is uncertain.
3. Provide `TMSWebCompiler.exe` through `--webcore-compiler`, `[WebCore].CompilerPath`, `DAK_TMSWEB_COMPILER`, or `PATH`.
4. Use `--pwa` or `--no-pwa` only when we need to override the project setting.
5. Do not add Delphi-only options such as `--dfmcheck`, `--rsvars`, `--envoptions`, `--define`, or `--unit-search-path`; DAK rejects them for WebCore builds.
6. For Debug builds, DAK runs `tools\patch-index-debug.ps1` after a successful build when that hook exists, so the legacy shell wrapper is not required.
7. Use `--json` when automation needs structured status and output path data.

Build plus DFM check from Windows PowerShell:

```powershell
$Project = Join-Path $PWD "src\App.dproj"
$Platform = if ($env:DAK_PLATFORM) { $env:DAK_PLATFORM } else { "Win32" }
& $env:DAK_EXE build --project $Project --delphi 23.0 --platform $Platform --config Debug --dfmcheck --ai
```

Build plus targeted DFM check:

```powershell
$Project = Join-Path $PWD "src\App.dproj"
$Platform = if ($env:DAK_PLATFORM) { $env:DAK_PLATFORM } else { "Win32" }
& $env:DAK_EXE build --project $Project --delphi 23.0 --platform $Platform --config Debug --dfmcheck --dfm "MainForm.dfm,Frames\DetailSubEditDocs.dfm" --ai
```
