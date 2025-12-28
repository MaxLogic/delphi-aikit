# DelphiConfigResolver

DelphiConfigResolver is a small console tool that reads a Delphi `.dproj` plus a target platform and configuration, then emits a fully expanded set of FixInsightCL parameters. We can use it to run FixInsight analysis outside the IDE in a repeatable way.

## What it can do

- Resolve project settings from `.dproj` and an optional `.optset`
- Expand IDE macros and environment variables
- Merge project search paths with the IDE library path
- Emit FixInsightCL parameters as `ini`, `xml`, or a runnable `bat`

## Good use cases

- Running FixInsight in CI or scripted builds
- Reproducing the exact IDE configuration in a headless environment
- Comparing config differences between platforms or build types

## Quick start

Build the console app with Delphi 12+, then run:

```
DelphiConfigResolver.exe --dproj "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0
```

If `--platform` or `--config` is omitted, we default to `Win32` and `Release`.

By default, we write `ini` output to stdout. To write a file or change the output kind:

```
DelphiConfigResolver.exe --dproj "C:\path\Project.dproj" --platform Win64 --config Release --delphi 23.0 --out-kind bat --out "C:\temp\run_fixinsight.bat"
```

For extra diagnostics during troubleshooting, enable verbose output:

```
DelphiConfigResolver.exe --dproj "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --verbose true
```

To run FixInsightCL directly (avoids cmd.exe 8K limit), add:

```
DelphiConfigResolver.exe --dproj "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --run-fixinsight
```

To capture resolver diagnostics (warnings, missing paths, macro issues) into a log file:

```
DelphiConfigResolver.exe --dproj "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --run-fixinsight --logfile "C:\temp\resolver.log"
```

To also include resolver diagnostics in stderr/stdout output (useful when redirecting into a report), add:

```
DelphiConfigResolver.exe --dproj "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --run-fixinsight --logfile "C:\temp\resolver.log" --log-tee true
```

When `--run-fixinsight` is used, we suppress stdout output unless `--out` or `--out-kind` is explicitly provided.

We run `rsvars.bat` from the default Delphi installation path to pick up IDE environment variables.
If Delphi is installed in a non-standard location, pass the path explicitly:

```
DelphiConfigResolver.exe --dproj "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --rsvars "D:\Apps\Embarcadero\Studio\23.0\bin\rsvars.bat"
```

If `EnvOptions.proj` is stored elsewhere, we can override that path too:

```
DelphiConfigResolver.exe --dproj "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --envoptions "D:\Config\EnvOptions.proj"
```

## FixInsightCL pass-through options

We can pass extra FixInsightCL flags either via `settings.ini` (next to the executable) or the CLI. CLI values win.

Supported pass-through options:

- `--output`
- `--ignore`
- `--settings`
- `--silent`
- `--xml`
- `--csv`

Sample `settings.ini`:

```
[FixInsightCL]
Path=
Output=
Ignore=
Settings=
Silent=false
Xml=false
Csv=false
```

`Path` is optional and can point to FixInsightCL.exe (or its folder). Relative paths are resolved against the executable folder.

## Output formats

- `ini` (default): easy to read and edit
- `xml`: structured output for tooling
- `bat`: runnable FixInsightCL command line

## Notes

- We read IDE configuration from the registry for the requested Delphi version (for example `23.0` for Delphi 12).
- We run `rsvars.bat` first so the IDE environment variables are available for macro expansion.
- If the IDE library path is not in the registry, we fall back to `EnvOptions.proj` from `%AppData%\Embarcadero\BDS\<version>\EnvOptions.proj`.
- For `bat` output, we try to resolve `FixInsightCL.exe` from `PATH`, then from FixInsight registry keys (HKCU/HKLM, 32/64-bit).
- Sample inputs live in `tests\fixtures\` so we can quickly try the resolver.
