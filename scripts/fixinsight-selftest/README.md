# FixInsight self-test

This folder contains a self-contained FixInsight run script that uses our
DelphiConfigResolver to analyze this repo's own project.

## What it does

- Resolves the project configuration from `projects\DelphiConfigResolver.dproj`.
- Runs FixInsightCL directly via `DelphiConfigResolver.exe --run-fixinsight`.
- Writes a combined report file and resolver log next to this script.
- Optionally generates raw FixInsight outputs (txt/xml/csv) under `Reports\`.

## Files

- `fixinsight-run.bat` - main runner
- `fixInsight-DelphiConfigResolver-report.txt` - combined run report (example)
- `fixInsight-DelphiConfigResolver-resolver.log` - resolver log (example)
- `fixInsight-DelphiConfigResolver-params.ini` - last ini output (example)
- `Reports\` - sample FixInsight outputs (txt/xml/csv)

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
  the .bat if you need a different platform/config/Delphi version.
- If FixInsight is not installed, the run will fail with a clear error.
- We keep results next to the script to make diffs and inspection easy.
