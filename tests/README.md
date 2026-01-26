# Tests

`tests\run.bat` is an end-to-end feature test that exercises:

- resolver output generation (`--out-kind ini|xml|bat`) for fixtures and for our own `projects\DelphiConfigResolver.dproj`
- FixInsightCL execution in `txt/xml/csv` (`--run-fixinsight`)
- report filtering (`--exclude-path-masks`, `[ReportFilter]`)
- warning-id filtering (`--ignore-warning-ids`, `[FixInsightIgnore]`)
- Pascal Analyzer execution (`--run-pascal-analyzer`) if installed

## Prereqs

- `bin\DelphiConfigResolver.exe` exists (run.bat will attempt to build it if missing)
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

Or simply:

```bash
./tests/run.sh
```

Artifacts are written under `tests\out\` (this folder is expected to be disposable).

## DUnitX suite (unit + integration)

The DUnitX test runner lives under `tests\` and exercises:

- build + resolver smoke checks
- FixInsight txt/xml/csv runs and filtering
- Pascal Analyzer runs and output validation

Build and run from a Windows shell:

```bat
build-delphi.bat tests\DelphiConfigResolver.Tests.dproj -config Debug -platform Win32 -ver 23
tests\DelphiConfigResolver.Tests.exe
```

If `pawelspc=1` is set, missing FixInsight/PALCMD is treated as a failure; otherwise the relevant tests are skipped.

## Useful env vars

- `DCR_PLATFORM` (default: `Win32`)
- `DCR_CONFIG` (default: `Release`)
- `DCR_DELPHI` (default: `23.0`)
- `RSVARS` (optional; passed as `--rsvars`)
- `ENVOPTIONS` (optional; passed as `--envoptions`)
- `PA_PATH` (optional; forwarded to `--pa-path` and/or `[PascalAnalyzer].Path`)
- `SKIP_PASCAL_ANALYZER` (set to any value to skip PALCMD tests)
