# Setup: Delphi static analysis skill

This skill is repo-local. It expects a built `DelphiAIKit.exe` and
uses it to run FixInsightCL and PALCMD. We do not distribute the resolver
binary inside the skill; we build it in this repo and point the skill to it.

## Prerequisites

- Windows + WSL (optional but supported)
- Python 3 (for `analyze.py` / `analyze-unit.py`)
- Built resolver binary: `bin\DelphiAIKit.exe`
- FixInsightCL.exe (only if we run FixInsight)
- PALCMD.EXE / PALCMD32.EXE (required by default; set `DAK_PASCAL_ANALYZER=false` to opt out)

## Resolver discovery

The scripts find the resolver like this:

1. `DAK_EXE` environment variable (absolute path is recommended)
2. Default: `bin\DelphiAIKit.exe` under the repo root

If the resolver is not found, the scripts abort with a clear error.

Example overrides:

```
set DAK_EXE=C:\tools\DelphiAIKit.exe
```

From WSL:

```
export DAK_EXE=/mnt/c/tools/DelphiAIKit.exe
```

## Resolver configuration

`DelphiAIKit.exe` reads `bin\settings.ini` by default when it needs
configuration (FixInsightCL path, report filtering, Pascal Analyzer path, etc.).
We should keep that file next to the resolver binary. The skill does not pass
`--fi-settings` automatically, because that flag is a FixInsightCL setting file
passthrough and is not the same as our `settings.ini`.

If we need a FixInsightCL settings file, set one explicitly via:

```
set FI_SETTINGS=C:\path\FixInsight.settings
```

(Or `FIXINSIGHT_SETTINGS`.)

## Tool discovery behavior

- FixInsightCL: resolved by DelphiAIKit (settings.ini, PATH, registry)
- Pascal Analyzer: resolved by DelphiAIKit (settings.ini, known install
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

- `DAK_DELPHI`, `DAK_PLATFORM`, `DAK_CONFIG`
- `DAK_RSVARS`, `DAK_ENVOPTIONS`
- `DAK_EXCLUDE_PATH_MASKS`, `DAK_IGNORE_WARNING_IDS`
- `DAK_FI_FORMATS` (default: `txt`; values: `txt`, `csv`, `xml`, `all`)
- `DAK_OUT`, `DAK_FIXINSIGHT`, `DAK_PASCAL_ANALYZER` (or legacy `DAK_PAL`), `DAK_CLEAN`, `DAK_WRITE_SUMMARY`
  - default wrapper behavior: project runs use `DAK_FIXINSIGHT=true` and `DAK_PASCAL_ANALYZER=true`
- `FI_SETTINGS` / `FIXINSIGHT_SETTINGS`
- `PA_PATH`, `PA_ARGS`

## Should we ship DelphiAIKit.exe with the skill?

No. The skill is designed to live inside this repo and to use the resolver we
build here. Keeping the binary in `bin\` makes paths predictable and avoids
stale binaries inside the skill folder. If we want to use an external or
prebuilt resolver, set `DAK_EXE` to point to it.
