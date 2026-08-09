# Tooling notes (FixInsightCL, PALCMD, DAK)

## Environment variables (forwarded by analyze.*)

Common overrides:

- `DAK_EXE=<path>` (overrides resolver location)
- `PA_PATH=...` (forwarded to `--pa-path`)
- `PA_ARGS=...` (additive PAL options only; DAK-owned automation arguments are rejected)
- `FI_SETTINGS=...` / `FIXINSIGHT_SETTINGS=...` (forwarded to FixInsightCL `--fi-settings` via DAK)
- `DAK_RSVARS=...` (forwarded to `--rsvars`)
- `DAK_ENVOPTIONS=...` (forwarded to `--envoptions`)
- `DAK_EXCLUDE_PATH_MASKS=...` (forwarded to `--exclude-path-masks`)
- `DAK_FI_IGNORE_RULES=...` (forwarded to `--ignore-warning-ids`)
- `DAK_PAL_IGNORE_RULES=...` (forwarded to `--pal-ignore-rules`)
- `DAK_PAL_EXCLUDE_SEARCH_FOLDERS=...` (forwarded to
  `--pa-exclude-search-folders`, explicit PAL `/X`)
- `DAK_PAL_EXCLUDE_FILES=...` (forwarded to `--pa-exclude-files`, explicit
  PAL `/XF`)
- `DAK_IGNORE_WARNING_IDS=...` is a deprecated FixInsight-only alias merged
  with `DAK_FI_IGNORE_RULES`.
- `DAK_FI_FORMATS=txt|csv|xml|all` (default: `txt`)

## Workspace and provenance

Use `[Workspace].Root` or `--workspace-root` with `auto`, `git`, `svn`,
`project`, or a fixed root. CLI precedence is followed by the closest ancestor
selector and the executable `dak.ini` fallback; discovery may reach the
filesystem root, while the normal settings cascade stays bounded by the
selected workspace. A fixed root must exist and contain the analyzed subject.

`provenance.target` exposes `revision`, `dirty`, `changed_files`,
`source_inputs`, nested Git/SVN roots, and capability states for revision,
status, changed files, inventory, and `nested_roots`. Capability values are
`available`, `fallback`, `unavailable`, and `not_applicable`. SVN obtains its
data from `svn info --xml`, adjacent `svnversion`, `svn status --xml`, and
`svn list --xml -R`. Missing or failing VCS tooling uses bounded filesystem
inventory and does not fail analysis. DAK first requires `svn info` to identify
a valid working copy; remaining command capabilities are then independent.

## Environment variables (wrapper-only; not forwarded to DAK)

These are used by the skill wrappers to maintain baselines/deltas and optional CI gating:

- `DAK_BASELINE=<path>` (default: `.dak/<ProjectName>/baseline.json`)
- `DAK_UPDATE_BASELINE=1`
- `DAK_GATE=1` (or `DAK_CI=1`)
- `DAK_MAX_NEW_PAL_STRONG=0` (default)
- `DAK_MAX_NEW_FI_W=0` (default)
- `DAK_MAX_PAL_WARNING_INCREASE=<N>`
- `DAK_MAX_FI_TOTAL_INCREASE=<N>`
- `DAK_GATE_INCLUDE_PATHS=<patterns>` / `DAK_GATE_EXCLUDE_PATHS=<patterns>`
  narrow the already ownership-selected current findings; they cannot hide
  unknown ownership or change the checked ownership categories.

## FixInsightCL specifics

- `--project=<dpr>` is mandatory; DAK builds the command line for us. See `references/sources.md`.
- Prefer valid `--libpath` and `--unitscopes` for parity with the IDE.
- Some FixInsightCL versions can show a message box when `--libpath` includes invalid paths. Avoid invalid entries in CI.
- Some FixInsightCL versions can fail to create output if the current working directory is not writable. Use a writable CWD and absolute output paths.

## DAK diagnostics filters (dak.ini)

DAK can suppress noisy “unknown macro” / “missing directory” diagnostics via
cascading `dak.ini` files (executable dir, workspace root, then nested folders down to
the analyzed `.dproj`):

- `[Diagnostics] IgnoreUnknownMacros=` semicolon-separated list; supports `*` to ignore all
- `[Diagnostics] IgnoreMissingPaths=` semicolon-separated masks; supports `*` / `?`

## Ownership policy and compatible baselines

The same cascade accepts a minimal checked policy:

```ini
[AnalysisPolicy]
GateOwnership=project;repository
ProjectRoots=
ThirdPartyRoots=
```

`GateOwnership` accepts only `project`, `repository`, and `third_party`.
Unknown keys or categories make the configuration invalid. `ProjectRoots` and
`ThirdPartyRoots` resolve only paths that automatic project/VCS topology could
not classify; they cannot relabel an already resolved first-party file.

DAK writes the canonical values, contributing `dak.ini` paths, and policy
SHA-256 into `summary.json`. A gated comparison always requires a matching
compatibility fingerprint covering compiler/search-path context, requested
analyzer versions/options, policy, project/config manifests, recursive
submodule revisions, and the DAK candidate. HEAD/dirty/source-content identity
is recorded separately so normal source edits can still be compared with a
compatible baseline. Missing or incompatible fingerprints fail without
creating, migrating, or updating the baseline.

## Pascal Analyzer specifics

- `PALCMD projectpath|sourcepath [options]` supports analyzing a single `.pas` without a `.pap` project. See `references/sources.md`.
- `PALCMD` exits with code `99` on errors.
- DAK reads PAL help as the authority for supported compiler flags. PAL 9.21
  exposes Delphi 12 and Delphi 13 Win64 (`/CD12W64`, `/CD13W64`), and BDS 37
  maps to Delphi 13.
- DAK always supplies `/F=X /Q /A+ /FA`, an automatic `/T=<n>`, an exact
  `/NAME`, and the report root. It derives the target, build, defines, and
  search path from project context by default. `PA_ARGS` may add other PAL
  options, including an explicit `/CD...`, but cannot override DAK-owned
  report, parse-scope, quiet, or thread arguments.

Report suppression is separate from analysis coverage:

- `[PascalAnalyzerIgnore].Rules`, `--pal-ignore-rules`, and
  `DAK_PAL_IGNORE_RULES` remove reviewed PAL rules only from actionable
  projections. Raw JSONL and full SARIF retain them.
- `[PascalAnalyzer].ExcludeSearchFolders`, `--pa-exclude-search-folders`, and
  `DAK_PAL_EXCLUDE_SEARCH_FOLDERS` explicitly produce PAL `/X`.
- `[PascalAnalyzer].ExcludeFiles`, `--pa-exclude-files`, and
  `DAK_PAL_EXCLUDE_FILES` explicitly produce PAL `/XF`.

Never infer `/X` or `/XF` from ownership or report policy. Removing dependency
contracts can create false caller-side findings, so every exclusion proof must
state reduced coverage.

## FAQ

### Can FixInsight analyze a single unit directly?

Not directly via a unit mode. FixInsightCL is a project analyzer and requires `--project=...dpr` (mandatory). The practical workaround is:

1. Analyze the full project, then filter the report to a single unit path (post-process XML/CSV/TXT).

### Why does Pascal Analyzer unit-level analysis differ from project-level analysis?

Prefer `analyze-unit <unit.pas> <project.dproj>`. DAK then supplies the
project-derived `/S=...`, `/D=...`, `/BUILD=...`, and compiler target flag, so
the focused run uses project context. Omitting `<project.dproj>` keeps the
legacy PAL.INI-based unit mode and is not project-equivalent analysis proof.
