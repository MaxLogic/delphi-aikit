# DelphiAIKit

“Utilities for AI-assisted Delphi code analysis and builds.”

## What it can do

- Resolve project settings from `.dproj` and an optional `.optset`
- Expand IDE macros and environment variables
- Merge project search paths with the IDE library path
- Emit FixInsightCL parameters as `ini`, `xml`, or a runnable `bat`

## Good use cases

- Running FixInsight in CI or scripted builds
- Reproducing the exact IDE configuration in a headless environment
- Comparing config differences between platforms or build types

## Requirements

- Windows (we use the registry and `rsvars.bat`)
- Delphi (any supported version); build scripts/examples default to 12 / 23.0, but we can pass other versions
- FixInsightCL.exe only if we plan to run FixInsight (`analyze`) or use the generated `bat`
- Pascal Analyzer (PALCMD.EXE / PALCMD32.EXE) only if we plan to run it (`--pascal-analyzer true`)

## Build

The project file is `projects\DelphiAIKit.dproj` and the executable is output to `bin\DelphiAIKit.exe`.

Build from Windows:

```
build-delphi.bat projects\DelphiAIKit.dproj -config Debug -platform Win32 -ver 23
```

Use `-target Rebuild` (or `-rebuild`) when we need a full clean rebuild:

```
build-delphi.bat projects\DelphiAIKit.dproj -config Debug -platform Win32 -ver 23 -target Rebuild
```

Build from WSL (calls Windows `cmd.exe`):

```
./build-delphi.sh projects/DelphiAIKit.dproj -config Debug -platform Win32 -ver 23
```

`build.bat` is a convenience wrapper that builds the resolver in Debug (Win32) with the default Delphi version.

Or via the CLI:

```
bin\DelphiAIKit.exe build --project "projects\DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug
```

`build` defaults to incremental `Build`; use `--target Rebuild` (or `--rebuild true`) for a full rebuild.
Additional build flags:
- `--json` emits machine-readable build results.
- `--max-findings N` caps printed findings per category (default `5`).
- `--build-timeout-sec N` terminates hung builds after `N` seconds (`0` disables timeout).
- `--test-output-dir "<path>"` writes build artifacts to an isolated output directory.

## Quick start

Build the console app, then run:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0
```

`--project` (alias: `--dproj`) accepts `.dproj`, `.dpr`, or `.dpk`. If we pass `.dpr`/`.dpk`, the resolver uses the sibling `.dproj`.
`--delphi` is required; `23` is normalized to `23.0`. We can pass other Delphi versions here as well.

If `--platform` or `--config` is omitted, we default to `Win32` and `Release`.

By default, we write `ini` output to stdout. To write a file or change the output kind:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win64 --config Release --delphi 23.0 --format bat --out-file "C:\temp\run_fixinsight.bat"
```

For extra diagnostics during troubleshooting, enable verbose output:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --verbose true
```

To run FixInsightCL directly, use `analyze` (FixInsight is on by default):

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0
```

To capture resolver diagnostics (warnings, missing paths, macro issues) into a log file:

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --log-file "C:\temp\resolver.log"
```

To also include resolver diagnostics in stderr/stdout output (useful when redirecting into a report), add:

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --log-file "C:\temp\resolver.log" --log-tee true
```

When `resolve` writes to stdout, `--format` and `--out-file` control output. `analyze` always writes reports to files.

We run `rsvars.bat` from the default Delphi installation path to pick up IDE environment variables.
If Delphi is installed in a non-standard location, pass the path explicitly:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --rsvars "D:\Apps\Embarcadero\Studio\23.0\bin\rsvars.bat"
```

If the IDE library path is missing in the registry, we fall back to `EnvOptions.proj`. We can override that path too:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --envoptions "D:\Config\EnvOptions.proj"
```

## FixInsightCL pass-through options

We can pass extra FixInsightCL flags either via cascading `dak.ini` files or the CLI. CLI values win.

### Cascading `dak.ini` lookup

`dak.ini` files are loaded in **cascading** order (lowest → highest precedence):

1. `dak.ini` next to the executable (global defaults).
2. `dak.ini` at repo root (folder containing `.git` or `.svn`), then each subfolder on the path down to the `.dproj` folder.
3. The `.dproj` folder `dak.ini` (already included by the path walk).

We **do not** use the current working directory for settings lookup.

List-like values are merged + deduped case-insensitively, preserving first-seen order; singular strings override only when non-empty.

Example layout (more local files override/extend more global ones):

```
repo/
  dak.ini
  src/
    dak.ini
    app/
      MyApp.dproj
      dak.ini
```

Supported pass-through options:

- `--fi-output`
- `--fi-ignore`
- `--fi-settings`
- `--fi-silent`
- `--fi-xml`
- `--fi-csv`

Sample `dak.ini`:

```
[FixInsightCL]
Path=
Output=
Ignore=
Settings=
Silent=false
Xml=false
Csv=false

[FixInsightIgnore]
; semicolon-separated FixInsight rule IDs to suppress in report post-processing (e.g. W502;C101;O801)
Warnings=

[ReportFilter]
; semicolon-separated Windows-style file mask patterns for report post-processing
ExcludePathMasks=

[PascalAnalyzer]
; path to palcmd.exe / palcmd32.exe (or its folder)
Path=
; report root folder (PALCMD /R=...)
Output=
; extra PALCMD args (passed verbatim)
Args=

[MadExcept]
; path to madExceptPatch.exe (or its folder)
Path=
```

`Path` is optional and can point to FixInsightCL.exe (or its folder). Relative paths are resolved against the executable folder.

`[MadExcept].Path` is optional and can point to `madExceptPatch.exe` (or its folder). If empty, `build-delphi.bat` tries `PATH` and common madExcept install folders.

## Report filtering (post-processing)

We support deterministic report filtering after analysis:

- `--exclude-path-masks "<m1;m2;...>"` (or `[ReportFilter].ExcludePathMasks`) removes findings whose reported file path matches any mask.
- `--ignore-warning-ids "W502;C101;O801"` (or `[FixInsightIgnore].Warnings`) removes findings for those FixInsight rule IDs.

Notes:

- This is post-processing only, so it does not speed up FixInsightCL.
- Filtering only applies when FixInsightCL writes to a file (`--fi-output`), because we need a report file to rewrite.
- Supported FixInsight report formats: text (default), `--fi-xml`, and `--fi-csv`.

Example (CSV, filtered):

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Release --delphi 23.0 ^
  --out "C:\temp\analysis" --fi-formats csv --fixinsight true --pascal-analyzer false ^
  --exclude-path-masks "*\lib\*;*\thirdparty\*" ^
  --ignore-warning-ids "O802;O803"
```

## Pascal Analyzer (PALCMD) runner

To run Peganza Pascal Analyzer headlessly using our resolved project inputs:

- `analyze --pascal-analyzer true`
- optional overrides:
  - `--pa-path "...\palcmd.exe"` (or `palcmd32.exe`, or a folder containing it)
  - `--pa-output "C:\temp\pa"` (report root folder, passed as `/R=...`)
  - `--pa-args "/F=X /Q ..."` (extra PALCMD options, passed verbatim)

If `--pa-args` is omitted, we use sensible defaults (`/F=X /Q /A+ /FA /T=min(CPU, 64)`) and we derive `/CD...` from `--delphi` + `--platform`.

Example:

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Release --delphi 23.0 ^
  --fixinsight false --pascal-analyzer true --pa-output "C:\temp\pa" --pa-args "/F=X /Q"
```

## Output formats

- `ini` (default): easy to read and edit
- `xml`: structured output for tooling
- `bat`: runnable FixInsightCL command line

## Notes

- We read IDE configuration from the registry for the requested Delphi version (for example `23.0` for Delphi 12).
- We run `rsvars.bat` first so the IDE environment variables are available for macro expansion.
- If the IDE library path is not in the registry, we fall back to `EnvOptions.proj` from `BDSUSERDIR`.
  If `BDSUSERDIR` is missing, we derive it from `%APPDATA%\Embarcadero\BDS\<version>` and then `%USERPROFILE%\Documents\Embarcadero\Studio\<version>`.
- We resolve `FixInsightCL.exe` from `dak.ini` (`Path`), then `PATH`, then FixInsight registry keys (HKCU/HKLM, 32/64-bit).
- `build-delphi.bat` runs `madExceptPatch.exe` only when a sibling `.mes` exists, the `.dpr`/`.dproj` base names match, and `madExcept` is defined for the selected build config/platform.
- Sample inputs live in `tests\fixtures\` so we can quickly try the resolver.
- `scripts\fixinsight-selftest\fixinsight-run.bat` runs FixInsight against this repo and can generate raw reports under `scripts\fixinsight-selftest\Reports\`.
- `scripts\pascal-analyzer-selftest\pascal-analyzer-run.bat` runs Pascal Analyzer against this repo and writes reports under `scripts\pascal-analyzer-selftest\Reports\`.

## Tests

There are no automated unit tests in this repo. Manual checks live in `tests\README.md`.
We can also run `tests\run.bat`, which executes the resolver against all fixture `.dproj` files and writes outputs to `tests\out`.
It expects `bin\DelphiAIKit.exe` to exist and accepts optional `RSVARS` and `ENVOPTIONS` environment variables for overrides.
