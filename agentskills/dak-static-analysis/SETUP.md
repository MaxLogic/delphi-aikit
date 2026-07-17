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
2. Windows `PATH` (`where DelphiAIKit.exe` on WSL / `where` on Windows)
3. Repo-local `bin\DelphiAIKit.exe` under the current repo, the target repo, or the DAK repo

If the resolver is not found, the scripts abort with a clear error.

Example overrides:

```
set DAK_EXE=C:\tools\DelphiAIKit.exe
```

From WSL:

```
export DAK_EXE=/mnt/c/tools/DelphiAIKit.exe
```

WSL path note for direct DAK calls:
- Supported Linux absolute form is `/mnt/<drive>/...`.
- Other absolute Linux paths (for example `/home/...`) are rejected.
- Use wrapper scripts (or `wslpath -w`) as the canonical safe conversion path.

## Resolver configuration

`DelphiAIKit.exe` reads cascading `dak.ini` files when it needs configuration
(FixInsightCL path, report filtering, Pascal Analyzer path, diagnostics settings, etc.).
The lookup order is:

1. `dak.ini` next to the executable
2. repo-root `dak.ini` (folder containing `.git` or `.svn`)
3. nested `dak.ini` files on the path down to the analyzed `.dproj`

For repo-local machine settings, use repo-root `dak.ini` copied from
`dak-template.ini`. The skill does not pass `--fi-settings` automatically,
because that flag is a FixInsightCL settings file passthrough and is not the
same as our cascading `dak.ini`.

If we need a FixInsightCL settings file, set one explicitly via:

```
set FI_SETTINGS=C:\path\FixInsight.settings
```

(Or `FIXINSIGHT_SETTINGS`.)

## Tool discovery behavior

- FixInsightCL: resolved by DelphiAIKit (dak.ini, PATH, registry)
- Pascal Analyzer: resolved by DelphiAIKit (dak.ini, known install
  locations, and `--pa-path` override)

## Where outputs go

Project runs write to:

```
<path-to-project>/.dak/{ProjectName}/
  fixinsight/
  pascal-analyzer/
  summary.json
  summary.md
  triage.md
  triage-changed.md
  static-analysis.sarif
  delta.md
  trend.md
  run.log
```

Unit runs write to:

```
<path-to-unit-directory>/.dak/_unit/{UnitName}/
  pascal-analyzer/
  summary.json
  summary.md
  triage.md
  static-analysis.sarif
  delta.md
  trend.md
  run.log
```

These are sibling working directories next to the analyzed target, not under the
wrapper's current working directory unless we are already running from that same
target location.

Those paths are wrapper defaults, not a requirement for every run. For large,
disposable agent runs, set `DAK_OUT` to a unique directory under the OS temporary
root. Never redirect analyzer output into `.agents/`; that directory is for small
agent knowledge, decisions, plans, and run state. Preserve only the reports needed
as evidence, then remove the verified temporary output tree.

## Optional env vars

- `DAK_DELPHI`, `DAK_PLATFORM`, `DAK_CONFIG`
- `DAK_RSVARS`, `DAK_ENVOPTIONS`
- `DAK_EXCLUDE_PATH_MASKS`, `DAK_IGNORE_WARNING_IDS`
- `DAK_FI_FORMATS` (default: `txt`; values: `txt`, `csv`, `xml`, `all`)
- `DAK_OUT`, `DAK_FIXINSIGHT`, `DAK_PASCAL_ANALYZER` (or legacy `DAK_PAL`), `DAK_CLEAN`, `DAK_WRITE_SUMMARY`
  - default wrapper behavior: project runs use `DAK_FIXINSIGHT=true` and `DAK_PASCAL_ANALYZER=true`
- `FI_SETTINGS` / `FIXINSIGHT_SETTINGS`
- `PA_PATH`, `PA_ARGS`
  - `PA_ARGS` accepts only additive PAL options. DAK always owns report format,
    report/output identity, parse scope, quiet mode, and thread count;
    conflicting arguments fail before PAL starts. DAK derives the compiler
    target by default, while an explicit additive `/CD...` remains permitted.

Prefer `analyze-unit <unit.pas> <project.dproj>` so DAK derives search paths,
defines, build configuration, and compiler target from the project. Omitting
the project keeps the legacy PAL.INI-based unit mode and is not
project-equivalent analysis proof.

## Should we ship DelphiAIKit.exe with the skill?

No. The skill is designed to live inside this repo and to use the resolver we
build here. Keeping the binary in `bin\` makes paths predictable and avoids
stale binaries inside the skill folder. If we want to use an external or
prebuilt resolver, set `DAK_EXE` to point to it.
