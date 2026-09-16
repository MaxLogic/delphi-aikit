# Setup: Delphi static analysis skill

This skill is repo-local. It expects a built `DelphiAIKit.exe` and
uses it to run FixInsightCL and PALCMD. We do not distribute the resolver
binary inside the skill; we build it in this repo and point the skill to it.

## Prerequisites

- Windows + WSL (optional but supported)
- Built resolver binary: `bin\DelphiAIKit.exe` (the analysis workflow needs no Python)
- The Delphi version for analysis: `DAK_DELPHI` or `--delphi`, for example `23.0`
- FixInsightCL.exe (only if we run FixInsight)
- PALCMD.EXE / PALCMD32.EXE (required by default; set `DAK_PASCAL_ANALYZER=false` to opt out)

## PAL parser defaults

Enable **Parse implementations for non-reported units** in PAL's parser
defaults. In the effective PAL.INI's `Parser` section, set
`CompleteParsing=1`.

For ordinary DAK calls, PALCMD reads PAL.INI next to its executable if present,
otherwise `%APPDATA%\Peganza\Pascal Analyzer\PAL.INI`. An explicit `/I=<path>`
overrides that choice; check that private file too. Existing PAP projects can
retain their own parser settings. This is a PAL installation/setup policy,
not a setting that DAK currently enforces in compiled code.

Only change this value; preserve report selection, search paths and exclusions.
Complete implementation parsing supplies context for checking our callers; it
does not require routine vendor finding review. Record the effective INI hash
and review affected baselines after changing it. Keep explicit disabled settings
for raw comparison probes. See [verified before/after results](../../docs/pal-int64-and-parser-checks.md).

## Resolver discovery

The launchers (`analyze.*`, `analyze-unit.*`, `doctor.*`, through `find-dak.cmd`
and `find-dak.sh`) find the resolver like this:

1. `DAK_EXE` environment variable (absolute path is recommended)
2. Windows `PATH` (`where DelphiAIKit.exe`, also from WSL)
3. `bin\DelphiAIKit.exe` of the repository that contains this skill

They never search the current directory or the analyzed workspace, so an
unrelated checkout around the project cannot supply a different executable. If
the resolver is not found, or `DAK_EXE` names a missing file, the launchers exit
with code 2 and a clear error. Otherwise they return DAK's own exit code.

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
- Use the shell launchers (or `wslpath -w`) as the canonical safe conversion path.
  They convert path arguments and path-valued variables and share the analysis
  variables with the Windows process through `WSLENV`.

## Resolver configuration

`DelphiAIKit.exe` reads cascading `dak.ini` files when it needs configuration
(FixInsightCL path, report filtering, Pascal Analyzer path, diagnostics settings, etc.).
Workspace selection happens first. `[Workspace].Root` accepts `auto`, `git`,
`svn`, `project`, or a fixed root path; `--workspace-root` is the CLI override.
The command line wins, then the closest ancestor selector, then the executable
`dak.ini` fallback. Bootstrap discovery scans to the filesystem root. The
default `auto` selector chooses the nearest `.git` or `.svn`, otherwise the
project directory. `git`/`svn` are strict marker requests, `project` ignores
surrounding VCS, and a fixed root must contain the subject. Relative fixed paths
are based on their declaring INI.

Normal configuration then loads from the selected workspace root down to the
analyzed `.dproj`; selector files outside that boundary cannot leak other
settings. The executable INI contributes normal defaults only when no selector
exists and default `auto` is used. For workspace-local machine settings, copy
`dak-template.ini` to the workspace as `dak.ini`. The skill does not pass
`--fi-settings` automatically,
because that flag is a FixInsightCL settings file passthrough and is not the
same as our cascading `dak.ini`.

Git and SVN executables are optional provenance capabilities. With the CLI,
SVN uses `svn info --xml`, adjacent `svnversion`, `svn status --xml`, and
`svn list --xml -R`. Without a usable VCS command, reports retain a bounded
filesystem inventory, mark metadata `unavailable`, and do not fail analysis.

The optional checked ownership policy uses that same cascade:

```ini
[AnalysisPolicy]
GateOwnership=project;repository
ProjectRoots=
ThirdPartyRoots=
```

The two root lists are narrow fallbacks for otherwise unresolved paths.
Automatic project and VCS topology wins. Keep accepted macros and optional
missing paths under `[Diagnostics] IgnoreUnknownMacros` and
`IgnoreMissingPaths`; those keys are invalid under `[AnalysisPolicy]`.

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
  static-analysis.full.sarif
  external-summary.md
  metrics.md
  baseline.json
  delta.json
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
  static-analysis.full.sarif
  external-summary.md
  metrics.md
  baseline.json
  delta.json
  delta.md
  trend.md
  run.log
```

These are sibling working directories next to the analyzed target, not under the
caller's current working directory unless we are already running from that same
target location.

Those paths are defaults, not a requirement for every run. For large,
disposable agent runs, set `DAK_OUT` to a unique directory under the OS temporary
root. Never redirect analyzer output into `.agents/`; that directory is for small
agent knowledge, decisions, plans, and run state. Preserve only the reports needed
as evidence, then remove the verified temporary output tree.

## Optional env vars

DAK reads these itself; a switch given on the command line wins.

- `DAK_DELPHI` (required unless `--delphi` is given), `DAK_PLATFORM`, `DAK_CONFIG`
- `DAK_RSVARS`, `DAK_ENVOPTIONS`
- `DAK_EXCLUDE_PATH_MASKS` (`--exclude-path-masks`,
  `[ReportFilter].ExcludePathMasks`)
- `DAK_FI_IGNORE_RULES` (`--ignore-warning-ids`,
  `[FixInsightIgnore].Warnings`)
- `DAK_PAL_IGNORE_RULES` (`--pal-ignore-rules`,
  `[PascalAnalyzerIgnore].Rules`)
- `DAK_PAL_EXCLUDE_SEARCH_FOLDERS` (`--pa-exclude-search-folders`,
  `[PascalAnalyzer].ExcludeSearchFolders`, PAL `/X`)
- `DAK_PAL_EXCLUDE_FILES` (`--pa-exclude-files`,
  `[PascalAnalyzer].ExcludeFiles`, PAL `/XF`)
- Deprecated FixInsight-only alias: `DAK_IGNORE_WARNING_IDS`
- `DAK_FI_FORMATS` (default: `txt`; values: `txt`, `csv`, `xml`, `all`)
- `DAK_OUT`, `DAK_FIXINSIGHT`, `DAK_PASCAL_ANALYZER` (or legacy `DAK_PAL`), `DAK_CLEAN`, `DAK_WRITE_SUMMARY`
  - defaults: project runs use `DAK_FIXINSIGHT=true` and `DAK_PASCAL_ANALYZER=true`
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
