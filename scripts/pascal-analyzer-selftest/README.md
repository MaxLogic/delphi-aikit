# Pascal Analyzer self-test

This folder contains a self-contained Pascal Analyzer run script that uses our
DelphiAIKit to analyze this repo's own project.

## What it does

- Resolves the project configuration from `projects\DelphiAIKit.dproj`.
- Runs PALCMD via `DelphiAIKit.exe analyze`.
- Writes a combined report file and resolver log next to this script.
- Writes DAK outputs under `Out\` (summary.md, run.log, pascal-analyzer\).
- Writes PALCMD reports under `Out\Reports\` (configurable).

## Files

- `pascal-analyzer-run.bat` - main runner
- `pascal-analyzer-DelphiAIKit-report.txt` - combined run report (example)
- `pascal-analyzer-DelphiAIKit-resolver.log` - resolver log (example)
- `Out\summary.md` / `Out\run.log` - DAK analysis outputs
- `Out\pascal-analyzer\` - PALCMD reports when `--pa-output` is not set
- `Out\Reports\` - PALCMD report output (XML/text/etc.) when `ML_PA_OUTPUT_REL` is set

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
- We keep results under `Out\` so `--clean` never wipes the script folder.
