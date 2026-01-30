# FixInsight self-test

This folder contains a self-contained FixInsight run script that uses our
DelphiAIKit to analyze this repo's own project.

## What it does

- Resolves the project configuration from `projects\DelphiAIKit.dproj`.
- Runs FixInsightCL via `DelphiAIKit.exe analyze`.
- Writes a combined report file and resolver log next to this script.
- Writes DAK outputs under `Out\` (summary.md, run.log, fixinsight\*.txt).
- Optionally generates raw FixInsight outputs (txt/xml/csv) under `Reports\fixinsight\`.

## Files

- `fixinsight-run.bat` - main runner
- `fixInsight-DelphiAIKit-report.txt` - combined run report (example)
- `fixInsight-DelphiAIKit-resolver.log` - resolver log (example)
- `Out\summary.md` / `Out\run.log` - DAK analysis outputs
- `Out\fixinsight\` - FixInsight outputs (default TXT)
- `Reports\fixinsight\` - raw outputs when `ML_GENERATE_SAMPLE_REPORTS=true`

## How to run

From Windows:

```
scripts\fixinsight-selftest\fixinsight-run.bat
```

From WSL:

```
/mnt/c/Windows/System32/cmd.exe /c "$(wslpath -w ./scripts/fixinsight-selftest/fixinsight-run.bat)"
```

## Notes

- The script is designed to be editable. Update the parameters at the top of
  the .bat if we need a different platform/config/Delphi version.
- FixInsight must be installed, otherwise the run fails with a clear error.
- By default we emit TXT only. Change `ML_FI_FORMATS` for xml/csv/all.
- We keep results under `Out\` so `--clean` never wipes the script folder.
