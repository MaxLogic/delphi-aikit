# Setup: Delphi static analysis skill

This skill is repo-local. It expects a built `DelphiConfigResolver.exe` and
uses it to run FixInsightCL and PALCMD. We do not distribute the resolver
binary inside the skill; we build it in this repo and point the skill to it.

## Prerequisites

- Windows + WSL (optional but supported)
- Python 3 (for `analyze.py` / `analyze-unit.py`)
- Built resolver binary: `bin\DelphiConfigResolver.exe`
- FixInsightCL.exe (only if we run FixInsight)
- PALCMD.EXE / PALCMD32.EXE (only if we run Pascal Analyzer)

## Resolver discovery

The scripts find the resolver like this:

1. `DCR_EXE` environment variable (absolute path is recommended)
2. Default: `bin\DelphiConfigResolver.exe` under the repo root

If the resolver is not found, the scripts abort with a clear error.

Example overrides:

```
set DCR_EXE=C:\tools\DelphiConfigResolver.exe
```

From WSL:

```
export DCR_EXE=/mnt/c/tools/DelphiConfigResolver.exe
```

## Resolver configuration

`DelphiConfigResolver.exe` reads `bin\settings.ini` by default when it needs
configuration (FixInsightCL path, report filtering, Pascal Analyzer path, etc.).
We should keep that file next to the resolver binary. The skill does not pass
`--settings` automatically, because that flag is a FixInsightCL setting file
passthrough and is not the same as our `settings.ini`.

If we need a FixInsightCL settings file, set one explicitly via:

```
set FI_SETTINGS=C:\path\FixInsight.settings
```

(Or `FIXINSIGHT_SETTINGS`.)

## Tool discovery behavior

- FixInsightCL: resolved by DelphiConfigResolver (settings.ini, PATH, registry)
- Pascal Analyzer: resolved by DelphiConfigResolver (settings.ini, known install
  locations, and `--pa-path` override)

## Where outputs go

Project runs write to:

```
./_analysis/{ProjectName}/
  fixinsight/
  pascal-analyzer/
  summary.md
  run.log
```

Unit runs write to:

```
./_analysis/_unit/{UnitName}/
  pascal-analyzer/
  summary.md
  run.log
```

## Optional env vars

- `DCR_DELPHI`, `DCR_PLATFORM`, `DCR_CONFIG`
- `DCR_RSVARS`, `DCR_ENVOPTIONS`
- `DCR_EXCLUDE_PATH_MASKS`, `DCR_IGNORE_WARNING_IDS`
- `DCR_FI_FORMATS` (default: `txt`; values: `txt`, `csv`, `xml`, `all`)
- `FI_SETTINGS` / `FIXINSIGHT_SETTINGS`
- `PA_PATH`, `PA_ARGS`

## Should we ship DelphiConfigResolver.exe with the skill?

No. The skill is designed to live inside this repo and to use the resolver we
build here. Keeping the binary in `bin\` makes paths predictable and avoids
stale binaries inside the skill folder. If we want to use an external or
prebuilt resolver, set `DCR_EXE` to point to it.
