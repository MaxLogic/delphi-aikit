# Tests

`tests\run.bat` is an end-to-end feature test that exercises:

- resolver output generation (`--out-kind ini|xml|bat`) for fixtures and for our own `projects\DelphiConfigResolver.dproj`
- FixInsightCL execution in `txt/xml/csv` (`--run-fixinsight`)
- report filtering (`--exclude-path-masks`, `[ReportFilter]`)
- warning-id filtering (`--ignore-warning-ids`, `[FixInsightIgnore]`)
- Pascal Analyzer execution (`--run-pascal-analyzer`) if installed

## Prereqs

- `bin\DelphiConfigResolver.exe` exists (build it first if needed)
- FixInsightCL is installed and discoverable (PATH / registry / settings)
- Pascal Analyzer is installed (optional; can be skipped)

## Run

From a Windows shell:

```bat
tests\run.bat
```

From WSL (runs via Windows `cmd.exe`):

```bash
/mnt/c/Windows/System32/cmd.exe /C tests\\run.bat
```

Artifacts are written under `tests\out\` (this folder is expected to be disposable).

## Useful env vars

- `DCR_PLATFORM` (default: `Win32`)
- `DCR_CONFIG` (default: `Release`)
- `DCR_DELPHI` (default: `23.0`)
- `RSVARS` (optional; passed as `--rsvars`)
- `ENVOPTIONS` (optional; passed as `--envoptions`)
- `PA_PATH` (optional; forwarded to `--pa-path` and/or `[PascalAnalyzer].Path`)
- `SKIP_PASCAL_ANALYZER` (set to any value to skip PALCMD tests)
