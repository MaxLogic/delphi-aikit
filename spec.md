# FixInsight Params Extractor (Delphi) — Implementation Specification

Date: 2025-12-23

## Scope note (tool vs. skill)

This `spec.md` covers the main DelphiConfigResolver tool only.

The repo also includes a repo-local agent skill for running static analysis via this tool:

- Skill root: `agentskill/delphi-static-analysis/`
- Skill entrypoint: `agentskill/delphi-static-analysis/SKILL.md`
- Skill docs: `agentskill/delphi-static-analysis/README.md`, `agentskill/delphi-static-analysis/SETUP.md`, `agentskill/delphi-static-analysis/references/`

Keep skill workflow/output guidance in the skill docs (not in this spec).

## Related spec slices

- `docs/spec-slices/pascal-analyser-cli.md` (Pascal analyser CLI contract and conventions)

## 1. Purpose

Build a **Delphi 12 console application** that accepts a **`.dproj`** plus target **Platform** and **Configuration**, then outputs a fully expanded set of **TMS FixInsightCL** command-line parameters (defines, unit search path, library path, unit scopes, etc.) so analysis can be run deterministically outside the IDE.

FixInsightCL supports the relevant CLI parameters such as `--project`, `--defines`, `--searchpath`, `--libpath`, `--unitscopes`, `--unitaliases`, `--settings`, etc. (see FixInsight manual).  

## 2. Command line interface

### 2.1 Invocation

```
FixInsightParams.exe ^
  --dproj "<path>\DelphiCompanion.dproj" ^
  --platform Win32 ^
  --config Debug ^
  --delphi 23.0 ^
  --out-kind bat|ini|xml ^
  --out "<path>\outFile.ext"
```

### 2.2 Parameters

- `--dproj` (required)  
  Path to a Delphi `.dproj`.

- `--platform` (optional)  
  Example: `Win32`, `Win64`. Default: `Win32` if omitted.

- `--config` (optional)  
  Example: `Debug`, `Release`, `Base` (if used by the project). Default: `Release` if omitted.

- `--delphi` (required)  
  Delphi IDE registry version, e.g. `23.0` for Delphi 12.  
  Accept also `23` and normalize to `23.0` (append `.0` if missing).

- `--out-kind` (optional)  
  Output kind:  
  - `bat`  -> emit a **Windows batch** that runs `FixInsightCL.exe` with computed params  
  - `ini`  -> emit an **INI** containing all computed params  
  - `xml`  -> emit an **XML** containing all computed params  
  Default: output to **stdout** as `ini` (human readable) if `--out-kind` omitted.

- `--out` (optional)  
  Output file path. If absent -> stdout.

- FixInsightCL pass-through options (optional):  
  `--output`, `--ignore`, `--settings`, `--silent`, `--xml`, `--csv`.  
  Defaults are read from `settings.ini` next to the executable and can be overridden by CLI.

- `--exclude-path-masks` (optional)  
  Semicolon-separated Windows-style file masks used to exclude findings during report post-processing (see §12).  
  Overrides `[ReportFilter].ExcludePathMasks`.

- `--ignore-warning-ids` (optional)  
  Semicolon-separated FixInsight rule IDs to suppress in report post-processing (e.g. `W502;C101;O801`).  
  Merged with `[FixInsightIgnore].Warnings`.

- `--run-fixinsight` (optional)  
  If present, run FixInsightCL directly via CreateProcess after resolving parameters.  
  This avoids cmd.exe 8K command line limits. Default: false.

- `--run-pascal-analyzer` (optional)  
  If present, run Pascal Analyzer (`palcmd.exe`) directly via CreateProcess after resolving parameters (see §13).

- `--pa-path` (optional)  
  Override `palcmd.exe` path (see §13.1).

- `--pa-output` (optional)  
  Output folder (report root) for the Pascal Analyzer report (see §13.3).

- `--pa-args` (optional)  
  Extra arguments appended verbatim to the `palcmd.exe` command line.

- `--logfile` (optional)  
  Write resolver diagnostics (warnings, missing paths, macros) to the specified file.  
  When set, diagnostics are not written to stderr.

- `--log-tee` (optional)  
  When used with `--logfile`, also write diagnostics to stderr/stdout (for capture into a report).

### 2.3 Exit codes

- `0` success
- `2` invalid CLI arguments
- `3` input file not found / unreadable
- `4` registry / IDE configuration not found for requested Delphi version
- `5` parse error (`.dproj` or `.optset`)
- `6` unresolved required values (e.g., no MainSource / no paths)
- `7` external tool not found (e.g., FixInsightCL / palcmd when `--run-*` is requested)

If `--run-fixinsight` is used, the process exit code is the FixInsightCL exit code (non-zero propagates).
When `--run-fixinsight` is used and no `--out` or `--out-kind` is provided, stdout output is suppressed.

### 2.4 `settings.ini` defaults

If `settings.ini` exists next to the executable, read defaults from section `[FixInsightCL]`:

```
[FixInsightCL]
Path=
Output=
Ignore=
Settings=
Silent=false
Xml=false
Csv=false
```

`Path` (optional) points to FixInsightCL.exe (or its folder); relative paths are resolved against the executable folder.

CLI values override these defaults, except ignore lists which are merged/deduped (see notes below).

Additional sections used by our tool:

```
[FixInsightIgnore]
; semicolon-separated FixInsight rule IDs to suppress in report post-processing
; (e.g. W502;C101;O801). Default: empty (don't guess IDs).
Warnings=

[ReportFilter]
; simple file mask patterns, semicolon-separated
; default: empty (no report filtering)
ExcludePathMasks=

[PascalAnalyzer]
; path to palcmd.exe (or its folder)
Path=
; output folder (report root) for analyzer report (optional)
Output=
; extra args passed verbatim to palcmd.exe (optional)
Args=
```

Notes:

- `[FixInsightIgnore].Warnings` is used for report post-processing only (see §12). If empty, existing behavior is unchanged.
- Effective FixInsight path ignore list passed as `--ignore="..."` is merged from:
  - `[FixInsightCL].Ignore`
  - CLI `--ignore`
  Dedupe case-insensitively and keep first-seen order.
- `[ReportFilter].ExcludePathMasks` only affects report post-processing (see §12); it does not affect parameter generation.
- `[PascalAnalyzer]` is only used when `--run-pascal-analyzer` is present (see §13).

## 3. Output model

### 3.1 Common computed fields (internal representation)

- `ProjectDpr` (absolute) — resolved from `.dproj` MainSource
- `Defines` (list of strings)
- `UnitSearchPath` (list of absolute paths; deduped; expanded)
- `LibraryPath` (list of absolute paths; deduped; expanded)
- `UnitScopes` (list of strings) — from `DCC_Namespace` (or option set)
- `UnitAliases` (optional list)
- `FixInsightExe` (optional; resolved from `PATH` or `HKCU\Software\FixInsight\Path`)
- `FixInsightExtra` (optional; output/ignore/settings/xml/csv/silent, from `settings.ini` + CLI overrides)
- `SettingsFile` (optional; user may add later)

### 3.2 Output kinds

#### A) `bat` (FixInsight runner)

Generates a batch file that runs FixInsightCL with proper quoting:

- `<resolved FixInsightCL.exe path>`
- `--project="...\Main.dpr"`
- `--defines="A;B;C"`
- `--searchpath="p1;p2;..."`
- `--libpath="l1;l2;..."`
- `--unitscopes="Vcl;System;..."`
- optionally `--unitaliases="..."`

Batch should:

- `setlocal`
- ensure UTF-8 output if writing logs (optional)
- execute the computed command line (no echo by default). If the executable path is not resolved, use `FixInsightCL.exe`.

#### B) `ini`

INI schema:

```
[FixInsight]
ProjectDpr=...
Defines=A;B;C
SearchPath=...
LibPath=...
UnitScopes=...
UnitAliases=...
DelphiVersion=23.0
Platform=Win32
Config=Debug
```

#### C) `xml`

XML schema (simple, deterministic):

```
<FixInsightParams delphi="23.0" platform="Win32" config="Debug">
  <ProjectDpr>...</ProjectDpr>
  <Defines>
    <D>DEBUG</D>
    ...
  </Defines>
  <SearchPath>
    <P>...</P>
  </SearchPath>
  <LibPath>...</LibPath>
  <UnitScopes>...</UnitScopes>
  <UnitAliases>...</UnitAliases>
</FixInsightParams>
```

## 4. Data sources and precedence

We want the final analysis context to match “what the IDE would build for this platform/config”.

### 4.1 Registry base key

Read IDE settings from:

`HKCU\Software\Embarcadero\BDS\{DelphiVersion}\`

Where `{DelphiVersion}` is normalized input (`23.0`, `22.0`, etc.).

### 4.2 Registry: Environment Variables

Read:

`HKCU\Software\Embarcadero\BDS\{DelphiVersion}\Environment Variables\`

Values here are IDE “environment variables” used for macro expansion like `$(BDS)`, `$(BDSCOMMONDIR)`, `$(BDSCatalogRepository)`, etc.

Build a dictionary: `EnvVarsFromRegistry[name] = value`.

### 4.3 Registry: Library search path

Read:

`HKCU\Software\Embarcadero\BDS\{DelphiVersion}\Library\{Platform}\`

Value name: **`Search Path`**

This yields the IDE “Delphi library search path” for the platform.

Important: the value can contain `$(SomeVar)` which must be expanded using the macro expansion rules (see §6).

> **Fallback (recommended):** On newer IDEs, these values can also appear in `EnvOptions.proj` under the roaming profile.
> If registry keys are missing or incomplete, read:
> `{BDSUSERDIR}\EnvOptions.proj` and extract `DelphiLibraryPath` for the platform.

### 4.4 Project file: `.dproj`

Read and evaluate the `.dproj` MSBuild XML:

- Extract `<MainSource>` to get the `.dpr` file (relative to `.dproj` directory).
- Evaluate property groups in order using an MSBuild-like property dictionary.
- Capture at least these properties (when active for platform/config):
  - `DCC_Define`
  - `DCC_UnitSearchPath`
  - `DCC_Namespace` (maps to FixInsight `--unitscopes`)
  - optionally: `DCC_UnitAlias` / `DCC_UnitAliases` if present
  - optionally: `CfgDependentOn` (option set link)

### 4.5 Option Set: `.optset`

If the active project properties contain `CfgDependentOn`, load that `.optset` file:

- `.optset` is MSBuild XML similar to `.dproj`.
- Evaluate it with the **same** platform/config and merge its properties as a baseline.
- Then apply the `.dproj` properties on top (project overrides option set).

Resolution of option set path:

1. If absolute -> use it
2. Else -> resolve relative to `.dproj` directory
3. If not found -> treat as warning and continue (but mark in output)

## 5. MSBuild-ish evaluation approach (practical subset)

Delphi `.dproj` uses MSBuild property groups with conditions like:

- `"'$(Config)'=='Debug' or '$(Cfg_2)'!=''"`
- `"('$(Platform)'=='Win32' and '$(Cfg_2)'=='true') or '$(Cfg_2_Win32)'!=''"`

### 5.1 Evaluation strategy

Implement a small evaluator:

- Maintain a dictionary `Props` with current string values.
- Seed it with:
  - `Config`, `Platform` (from CLI)
  - `ProjectDir` (absolute)
  - `PROJECTDIR` (Delphi macro expected by many build events)
  - `BDS`, `BDSCOMMONDIR`, `BDSUSERDIR`, `BDSCatalogRepository`, etc. (from registry/env)
- Walk `<PropertyGroup>` nodes in file order:
  - If no `Condition` -> apply.
  - If `Condition` exists -> evaluate against current `Props`; if true apply.
- When applying a property:
  - Store raw string (not expanded yet), but allow `$(Var)` references.
  - Keep last-write-wins semantics.

### 5.2 Condition language (supported subset)

Support:

- string equality and inequality:
  - `'$(X)'=='Value'`
  - `'$(X)'!=''`
- Boolean composition:
  - `and`, `or`
- Parentheses `(` `)`
- Literal strings in single quotes.

**Non-goals:** full MSBuild evaluation (property functions, item groups, transforms).

This subset is sufficient for typical `.dproj` platform/config selection.

## 6. Macro expansion (`$(NAME)`)

We must expand `$(NAME)` references inside:

- Registry library search path
- `DCC_UnitSearchPath`
- `DCC_Namespace` (usually no paths, but keep consistent)
- `DCC_Define` (usually no macros but can reference `$(DCC_Define)` chaining)
- any other extracted value

### 6.1 Expansion sources (precedence)

When expanding `$(NAME)`:

1. `Props` (MSBuild/project/optset properties)
2. `EnvVarsFromRegistry` (IDE environment variables)
3. `GetEnvironmentVariable(NAME)` from OS

### 6.2 Recursion + safety

- Expand repeatedly until stable or max depth (e.g. 10 iterations).
- Detect cycles (`A -> $(A)` or longer) and stop with a warning.
- Keep unknown macros intact and report them (so callers can fix missing environment).

### 6.3 Path list handling

Many values are semicolon lists. For any path list:

1. Split on `;`
2. Trim whitespace
3. Expand macros in each entry
4. Normalize to absolute paths when possible:
   - if relative: resolve relative to `.dproj` directory
5. Deduplicate case-insensitively (Windows)
6. Preserve order of first occurrence

## 7. Constructing FixInsightCL arguments

FixInsightCL parameters we will emit:

- `--project="<ProjectDpr>"`
- `--defines="<DefinesJoinedBySemicolon>"`
- `--searchpath="<ProjectUnitSearchPath + LibraryPath>"`
- `--libpath="<LibraryPath>"`
- `--unitscopes="<UnitScopesJoinedBySemicolon>"`
- `--unitaliases="<AliasesJoinedBySemicolon>"` (if available)
- `--settings="<...ficfg>"` (NOT generated by this tool, but allow future extension)

### 7.1 Mapping rules

- Defines:
  - From evaluated `DCC_Define`
  - Split by `;`, trim, drop empties
  - Dedup case-insensitively

- UnitScopes:
  - From evaluated `DCC_Namespace` (Delphi namespaces are semicolon separated)
  - Split/dedup

- SearchPath:
  - `ProjectSearchPath = DCC_UnitSearchPath`
  - `LibraryPath = Registry/EnvOptions-derived Search Path`
  - `FixInsightSearchPath = ProjectSearchPath + LibraryPath` (concatenate, then dedup)

- LibPath:
  - Use `LibraryPath` (IDE library search path)

### 7.2 Required vs optional

Required for a useful run:

- `--project`
- `--searchpath` (at least IDE lib path)
Strongly recommended:

- `--unitscopes` (Delphi namespace search)
- `--defines`

## 8. Registry and filesystem details

### 8.1 Registry reading

Use `TRegistry` (read-only).

- Open base: `HKCU\Software\Embarcadero\BDS\{DelphiVersion}`
- Read string values under subkeys:
  - `Environment Variables`
  - `Library\{Platform}` value `Search Path`

Handle missing keys gracefully with clear errors.

### 8.2 Optional: EnvOptions.proj fallback

If registry `Search Path` missing:

- Determine `BDSUSERDIR` from env vars (or typical path `Documents\Embarcadero\Studio\{DelphiVersion}`)
- Find Roaming `EnvOptions.proj` and parse it as MSBuild XML:
  - Select `PropertyGroup Condition="'$(Platform)'=='Win32'"` etc
  - Read `DelphiLibraryPath` and treat it as library path

## 9. Logging and diagnostics

- Write human-readable diagnostics to stderr (never pollute stdout when stdout is used for output).
- Provide:
  - list of unresolved macros
  - list of missing directories (optional warning)
  - where each parameter came from (project vs optset vs registry)

## 10. Validation checklist

For the selected platform/config:

- Main `.dpr` exists
- Library path not empty
- Search path is non-empty
- All macros expanded (or unknown macros reported)
- Output produced in selected kind

## 11. Minimal test matrix

Create a small `tests` folder (or internal self-test mode) to validate:

1. Macro expansion:
   - nested `$(A)` -> `$(B)` -> literal
   - cycle detection
2. Condition evaluation:
   - basic `and`/`or` precedence
   - `!= ''` and `== 'X'`
3. `.dproj` merge:
   - base group + config group + platform group
4. `.optset` baseline then override by `.dproj`
5. Dedup ordering stability

---

## 12. Report filtering (ExcludePathMasks)

We filter analyzer reports in a deterministic post-processing layer so results can be cleaned even if the external tool does not support path filters.

### 12.1 Masks and matching rules

- Treat masks as Windows-style (`*` / `?`), case-insensitive.
- Normalize all paths to use `\` before matching.
- Apply masks to the full file path string as it appears in the report (after normalization).
- Multiple masks are separated by `;` (empty entries ignored).

### 12.2 FixInsightCL reports

FixInsightCL supports:

- text output (default)
- `--xml` (format output as XML)
- `--csv` (format output as CSV)

Post-processing applies only to file output we can rewrite (i.e., when FixInsightCL is invoked with `--output=...`). If FixInsightCL writes only to stdout, we do not filter.

Observed report formats (FixInsightCL 2023.12) we support for post-processing:

- Text: grouped by `File: <path>` lines; each finding line begins with a rule ID token like `W502`, `C101`, `O801`.
- CSV: headerless; each row is:

  ```text
  "<File>",<Line>,<Col>,<RuleId>,<Message>
  ```

- XML:

  ```xml
  <FixInsightReport version="...">
    <file name="...">
      <message line="..." col="..." id="C101">...</message>
    </file>
  </FixInsightReport>
  ```

Implementation note: when `--run-fixinsight` is used and `--output` is relative, we canonicalize it to an absolute path before invoking FixInsightCL so the report lands in a deterministic location for post-processing.

Apply `ExcludePathMasks` in two layers:

1. Best case: if FixInsight supports source include/exclude via its settings file or another CLI flag, use it (we already pass `--settings` through).
2. Fallback (guaranteed): post-process the produced report (text/xml/csv) and remove any finding whose file path matches any exclude mask.

Filtering is applied after analysis, so it does not speed up FixInsight, but it cleans the report reliably.

### 12.3 Suppressing FixInsight rule IDs (Warnings)

In addition to path filtering, we can suppress specific FixInsight rule IDs (e.g. `W502`, `C101`, `O801`) in the produced report via:

- `[FixInsightIgnore].Warnings=...`
- `--ignore-warning-ids "W502;C101;O801"`

This is post-processing only; it does not affect FixInsight analysis runtime.

### 12.4 Pascal Analyzer reports

PALCMD supports:

- `/F=T` (text)
- `/F=H` (HTML)
- `/F=X` (XML)

We do not post-process PALCMD reports yet. If exclusions are needed, pass `/X` (excluded folders) and `/XF` (excluded files) via `--pa-args` (PALCMD takes folder/file lists, not glob masks).

## 13. Pascal Analyzer (PALCMD) integration

When `--run-pascal-analyzer` is present, run `palcmd.exe` (or `palcmd32.exe`) using the same `.dproj` resolution + macro expansion pipeline we use for FixInsight.

### 13.1 `palcmd.exe` / `palcmd32.exe` path discovery (required)

Discovery order:

1. CLI override: `--pa-path "...\\palcmd.exe"` or `--pa-path "...\\palcmd32.exe"`
2. `settings.ini` override: `[PascalAnalyzer] Path=...`
3. Known default (v9): `C:\Program Files\Peganza\Pascal Analyzer 9\palcmd.exe` (or `palcmd32.exe`)
4. Version sweep: `C:\Program Files\Peganza\Pascal Analyzer {N}\palcmd.exe` (or `palcmd32.exe`) for `N = 5..15` (also check `Program Files (x86)`)
5. Directory scan (depth-limited): enumerate `C:\Program Files\Peganza\` (and x86) for folders matching `Pascal Analyzer*`, pick the newest version that contains `palcmd.exe` (prefer `palcmd.exe` over `palcmd32.exe` when both exist)
6. If still not found: hard error telling the user to provide `--pa-path`

### 13.2 Invocation model

- Execute PALCMD via CreateProcess (avoid cmd.exe limits).
- Use our resolved main project file (`ProjectDpr`) as the PALCMD input path (PALCMD accepts a single file path as `sourcepath`).
- Pass compiler mode flag mapped from `--delphi` + `--platform` (e.g. Delphi 12 + Win32 -> `/CD12W32`).
- Pass our resolved build config and defines:
  - `/BUILD=<Config>` (case-sensitive)
  - `/D=Def1;Def2;...`
  - `/S="p1;p2;..."` from our resolved search path
- If `--pa-output` / `[PascalAnalyzer].Output` is set, pass it as `/R="<folder>"` (report root folder).
- Use `--pa-args`/`[PascalAnalyzer].Args` for any additional PALCMD flags.

Defaults when `--pa-args` and `[PascalAnalyzer].Args` are empty:

- `/F=X` (XML)
- `/Q` (quiet)
- `/A+` (parse source + form files)
- `/FR` (main file + directly used files)
- `/T=n` where `n = min(8, CPUCount)`

### 13.3 Output

If `--pa-output` (or `[PascalAnalyzer].Output`) is provided, treat it as the report root folder and pass it to PALCMD as `/R=...`.

## Appendix A — What we saw in the sample `.dproj`

In the provided sample `.dproj`, relevant properties appeared in the active `Base` group such as:

- `DCC_Define=...;$(DCC_Define)`
- `DCC_UnitSearchPath=...;$(DCC_UnitSearchPath)`
- `DCC_Namespace=...;$(DCC_Namespace)`
- `CfgDependentOn=mecDefault.optset`

This is exactly the chaining pattern we must support (property references itself at the tail to append defaults).
