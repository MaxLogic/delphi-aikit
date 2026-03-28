# Tooling notes (FixInsightCL, PALCMD, DAK)

## Environment variables (forwarded by analyze.*)

Common overrides:

- `DAK_EXE=<path>` (overrides resolver location)
- `PA_PATH=...` (forwarded to `--pa-path`)
- `FI_SETTINGS=...` / `FIXINSIGHT_SETTINGS=...` (forwarded to FixInsightCL `--fi-settings` via DAK)
- `DAK_RSVARS=...` (forwarded to `--rsvars`)
- `DAK_ENVOPTIONS=...` (forwarded to `--envoptions`)
- `DAK_EXCLUDE_PATH_MASKS=...` (forwarded to `--exclude-path-masks`)
- `DAK_IGNORE_WARNING_IDS=...` (forwarded to `--ignore-warning-ids`)
- `DAK_FI_FORMATS=txt|csv|xml|all` (default: `txt`)

## Environment variables (wrapper-only; not forwarded to DAK)

These are used by the skill wrappers to maintain baselines/deltas and optional CI gating:

- `DAK_BASELINE=<path>` (default: `.dak/<ProjectName>/baseline.json`)
- `DAK_UPDATE_BASELINE=1`
- `DAK_GATE=1` (or `DAK_CI=1`)
- `DAK_MAX_NEW_PAL_STRONG=0` (default)
- `DAK_MAX_NEW_FI_W=0` (default)
- `DAK_MAX_PAL_WARNING_INCREASE=<N>`
- `DAK_MAX_FI_TOTAL_INCREASE=<N>`

## FixInsightCL specifics

- `--project=<dpr>` is mandatory; DAK builds the command line for us. See `references/sources.md`.
- Prefer valid `--libpath` and `--unitscopes` for parity with the IDE.
- Some FixInsightCL versions can show a message box when `--libpath` includes invalid paths. Avoid invalid entries in CI.
- Some FixInsightCL versions can fail to create output if the current working directory is not writable. Use a writable CWD and absolute output paths.

## DAK diagnostics filters (dak.ini)

DAK can suppress noisy “unknown macro” / “missing directory” diagnostics via
cascading `dak.ini` files (executable dir, repo root, then nested folders down to
the analyzed `.dproj`):

- `[Diagnostics] IgnoreUnknownMacros=` semicolon-separated list; supports `*` to ignore all
- `[Diagnostics] IgnoreMissingPaths=` semicolon-separated masks; supports `*` / `?`

## Pascal Analyzer specifics

- `PALCMD projectpath|sourcepath [options]` supports analyzing a single `.pas` without a `.pap` project. See `references/sources.md`.
- `PALCMD` exits with code `99` on errors.

## FAQ

### Can FixInsight analyze a single unit directly?

Not directly via a unit mode. FixInsightCL is a project analyzer and requires `--project=...dpr` (mandatory). The practical workaround is:

1. Analyze the full project, then filter the report to a single unit path (post-process XML/CSV/TXT).

### Why does Pascal Analyzer unit-level analysis differ from project-level analysis?

When PALCMD is run on a single unit, it relies on defaults from `PAL.INI` unless we provide `/S=...` (search folders), `/D=...` (defines), `/BUILD=...`, and compiler target flags. Project-level runs via DAK supply these consistently from `.dproj`.
