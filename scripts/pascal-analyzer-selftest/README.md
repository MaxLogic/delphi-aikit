# Pascal Analyzer self-test

This folder contains a self-contained Pascal Analyzer run script that uses our
DelphiConfigResolver to analyze this repo's own project.

## What it does

- Resolves the project configuration from `projects\DelphiConfigResolver.dproj`.
- Runs PALCMD directly via `DelphiConfigResolver.exe --run-pascal-analyzer`.
- Writes a combined report file and resolver log next to this script.
- Writes PALCMD reports under `Reports\`.

## Files

- `pascal-analyzer-run.bat` - main runner
- `pascal-analyzer-DelphiConfigResolver-report.txt` - combined run report (example)
- `pascal-analyzer-DelphiConfigResolver-resolver.log` - resolver log (example)
- `pascal-analyzer-DelphiConfigResolver-params.ini` - last ini output (example)
- `Reports\` - PALCMD report output (XML/text/etc.)

## How to run

From Windows:

```
scripts\pascal-analyzer-selftest\pascal-analyzer-run.bat
```

From WSL:

```
/mnt/c/Windows/System32/cmd.exe /c "$(wslpath -w ./scripts/pascal-analyzer-selftest/pascal-analyzer-run.bat)"
```

## Notes

- The script is designed to be editable. Update the parameters at the top of
  the .bat if you need a different platform/config/Delphi version.
- If Pascal Analyzer is not installed, the run will fail with a clear error.
- We keep results next to the script to make diffs and inspection easy.
