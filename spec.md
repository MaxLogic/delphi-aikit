# FixInsight Params Extractor (Delphi) — Implementation Specification

Date: 2025-12-23

## Scope note (tool vs. skill)

This `spec.md` covers the main DelphiAIKit tool only.

The repo also includes a repo-local agent skill for running static analysis via this tool:

- Skill root: `agentskills/delphi-static-analysis/`
- Skill entrypoint: `agentskills/delphi-static-analysis/SKILL.md`
- Skill docs: `agentskills/delphi-static-analysis/README.md`, `agentskills/delphi-static-analysis/SETUP.md`, `agentskills/delphi-static-analysis/references/`

Keep skill workflow/output guidance in the skill docs (not in this spec).

## Related spec slices

- `docs/spec-slices/pascal-analyser-cli.md` (Pascal analyser CLI contract and conventions)

## 1. Purpose

Build a **Delphi 12 console application** that accepts a **`.dproj`** plus target **Platform** and **Configuration**, then outputs a fully expanded set of **TMS FixInsightCL** command-line parameters (defines, unit search path, library path, unit scopes, etc.) so analysis can be run deterministically outside the IDE.

FixInsightCL supports the relevant CLI parameters such as `--project`, `--defines`, `--searchpath`, `--libpath`, `--unitscopes`, `--unitaliases`, `--settings`, etc. (see FixInsight manual).  

## 2. Command line interface

### 2.1 Invocation

```
DelphiAIKit.exe <command> [global options] [command options]
DelphiAIKit.exe --help
DelphiAIKit.exe <command> --help
```

Commands:

- `resolve` — generate resolved FixInsight params output (ini/xml/bat)
- `analyze` — run FixInsightCL and/or Pascal Analyzer with stable report output
- `build` — build a `.dproj` via DAK's native Delphi or TMS WEB Core build runner
- `dfm-check` — validate DFM streaming via generated harness project
- `dfm-inspect` — inspect text DFM structure, key properties, and event bindings
- `global-vars` — report project globals, usages, and ambiguities

### 2.2 Global options (shared)

- `--project <path>` (required for `resolve`/`analyze`/`build`)  
  Alias: `--dproj`. Accepts `.dproj`, `.dpr`, or `.dpk`. If `.dpr`/`.dpk`, we resolve the sibling `.dproj`.

- `--platform <Win32|Win64|...>` (optional)  
  Default: `Win32`.

- `--config <Debug|Release|...>` (optional)  
  Default: `Release`.

- `--delphi <23.0>` (required for `resolve`, `analyze`, and Delphi/MSBuild builds)  
  Accept also `23` and normalize to `23.0` (append `.0` if missing).

- `--rsvars <path>` (optional)  
  Override the rsvars.bat path.

- `--envoptions <path>` (optional)  
  Override EnvOptions.proj path.

- `--log-file <path>` (optional)  
  Alias: `--logfile`.

- `--log-tee [true|false]` (optional)  
  When used with `--log-file`, also write diagnostics to stderr/stdout.

- `--verbose [true|false]` (optional)
- `--source-context <auto|off|on>` (optional)
  Controls whether build/`dfm-check` failures emit nearby source lines when DAK can resolve a file and line.

- `--source-context-lines <N>` (optional)
  Controls how many lines before/after the hit are shown. Default: `2`.

Notes:

- `--delphi` is required for `resolve` and `analyze`.
- `--delphi` is required for `build` only when DAK resolves the Delphi/MSBuild backend.
- `--delphi` is optional for `dfm-check` and `global-vars`; when omitted, load `[Build] DelphiVersion` from cascading `dak.ini`.

### 2.3 `resolve` — generate params

```
DelphiAIKit.exe resolve --project "<path>\MyProject.dproj" --delphi 23.0 ^
  [--platform Win32] [--config Release] ^
  [--format ini|xml|bat] [--out-file "<path>\out.ext"] ^
  [--fi-output "<path>"] [--fi-ignore "<list>"] [--fi-settings "<path>"] ^
  [--fi-silent [true|false]] [--fi-xml [true|false]] [--fi-csv [true|false]] ^
  [--exclude-path-masks "<list>"] [--ignore-warning-ids "<list>"]
```

Notes:

- `--format` replaces `--out-kind`.
- `--out-file` replaces `--out`.
- FixInsightCL pass-through options are now namespaced with `--fi-*`.

### 2.4 `analyze` — run FixInsightCL / Pascal Analyzer

```
DelphiAIKit.exe analyze --project "<path>\MyProject.dproj" --delphi 23.0 ^
  [--platform Win32] [--config Release] [--out "<path>"] ^
  [--fixinsight [true|false]] [--pascal-analyzer [true|false]] ^
  [--fi-formats <txt|xml|csv|all>] ^
  [--exclude-path-masks "<list>"] [--ignore-warning-ids "<list>"] ^
  [--fi-settings "<path>"] [--fi-ignore "<list>"] [--fi-silent [true|false]] ^
  [--pa-path "<path>"] [--pa-output "<path>"] [--pa-args "<args>"] ^
  [--clean [true|false]] [--write-summary [true|false]]
```

Defaults:

- `--fixinsight` default: `true`
- `--pascal-analyzer` default: `false`
- `--fi-formats` default: `txt`
- If `--out` is omitted, DAK writes analysis outputs under the target's `.dak` working tree rather than a legacy `_analysis/` folder.

Unit analysis is supported via `--unit`:

```
DelphiAIKit.exe analyze --unit "<path>\Unit1.pas" --delphi 23.0 ^
  [--out "<path>"] [--pascal-analyzer [true|false]] [--pa-* ...]
```

### 2.5 `build` — build a `.dproj`

```
DelphiAIKit.exe build --project "<path>\MyProject.dproj" --delphi 23.0 ^
  [--platform Win32] [--config Release] [--builder auto|delphi|webcore] ^
  [--webcore-compiler "<path>"] [--pwa] [--no-pwa] ^
  [--source-context auto|off|on] [--source-context-lines N]
```

Implementation uses DAK's native build runners:

- Delphi backend: MSBuild + `rsvars.bat` + madExcept integration
- WebCore backend: `TMSWebCompiler.exe` with optional `patch-index-debug.ps1` compatibility hook

For Delphi builds, output-path resolution uses the effective project properties after applying any active `CfgDependentOn` `.optset` baseline and then reapplying the `.dproj` overrides. When madExcept patching is required and the resolved output file is missing after a successful compile, `build` must fail with a specific output-path diagnostic instead of a generic madExcept patch failure.

`build-delphi.bat` may remain as a compatibility/bootstrap wrapper, but the CLI `build` command does not rely on batch/PowerShell helper logic for normal execution.

WebCore backend notes:

- `auto` is the default backend and switches to WebCore only when strong project markers are present, such as `TMSWebProject`, `TMSWebHTMLFile`, or `TMSWEBCorePkg...`.
- `TMSWebCompiler.exe` resolves from `--webcore-compiler`, cascading `dak.ini` `[WebCore].CompilerPath`, `DAK_TMSWEB_COMPILER`, then `PATH`.
- `--pwa` / `--no-pwa` override the project `TMSWebPWA` setting.
- Delphi-only flags such as `--dfmcheck`, `--rsvars`, and `--envoptions` are rejected for WebCore builds.

### 2.6 `dfm-check` — validate DFM streaming

```
DelphiAIKit.exe dfm-check --dproj "<path>\MyProject.dproj" ^
  [--delphi 23.0] [--platform Win32] [--config Release] ^
  [--dfm "<file1.dfm,file2.dfm>"] [--all] [--source-context auto|off|on] ^
  [--source-context-lines N] [--rsvars "<path>"] [--verbose [true|false]]
```

- Generated `_DfmCheck` harness projects must preserve the source project's effective compile search path, including imported `.optset` / inherited `DCC_UnitSearchPath` inputs and IDE/library-path entries resolved from the active Delphi context, while keeping project/discovered form-unit directories ahead of inherited IDE/library paths so the generated register unit resolves the same project units as the normal build.
- When the generated checker project is relocated under `.dak/...`, DAK must also rebase relative MSBuild `<Import Project="...">` references and relative `Exists('...')` import conditions to the source-project directory so inherited property sets continue to resolve during the checker build.

### 2.7 `dfm-inspect` — inspect text DFM files

```
DelphiAIKit.exe dfm-inspect --dfm "<path>\MainForm.dfm" [--format tree|summary]
```

- `--dfm` is required and must point to a text DFM file.
- `--format tree` prints the component hierarchy with key properties and event bindings.
- `--format summary` prints total component count, per-class counts, and discovered event bindings.

### 2.8 `global-vars` — analyze globals

```
DelphiAIKit.exe global-vars --project "<path>\MyProject.dproj" ^
  [--delphi 23.0] [--platform Win32] [--config Release] ^
  [--format text|json] [--output "<path>|-"] ^
  [--cache "<path>"] [--refresh auto|force] ^
  [--unused-only] [--unit "<pattern>"] [--name "<pattern>"] ^
  [--reads-only] [--writes-only] [--verbose [true|false]]
```

Notes:

- `--unused-only` cannot be combined with `--reads-only` or `--writes-only`.
- `--reads-only` and `--writes-only` are mutually exclusive.
- `--unit` and `--name` use wildcard matching (`*`, `?`). If no wildcard is present, treat the value as `*text*`.
- `--cache` overrides the default sibling cache path under `.dak/<ProjectName>/global-vars/cache/`.
- `--refresh force` bypasses cache reuse and rebuilds the analysis database.

### 2.8 Exit codes

- `0` success
- `2` invalid CLI arguments
- `3` input file not found / unreadable
- `4` registry / IDE configuration not found for requested Delphi version
- `5` parse error (`.dproj` or `.optset`)
- `6` unresolved required values (e.g., no MainSource / no paths)
- `7` external tool not found (e.g., FixInsightCL / PALCMD when required)

### 2.9 `dak.ini` defaults (cascading)

Defaults come from `dak.ini` files loaded in **cascading** order (lowest → highest precedence):

1. `dak.ini` next to the executable (global defaults).
2. `dak.ini` at repo root (folder containing `.git` or `.svn`), then each subfolder on the path down to the target `.dproj` folder.
3. The `.dproj` folder `dak.ini` (already included by the path walk).

Repo root detection stops at the first folder that contains `.git` or `.svn` (that folder is included). If neither marker is found, we stop at filesystem root. The **current working directory is not used** for settings.

Each `dak.ini` is applied in order so more local settings override/extend more global ones.

The repo ships a tracked `dak-template.ini` as the canonical starting point for machine-local settings. When we need repo-root overrides, copy it to `dak.ini`; that root-local `dak.ini` is intentionally untracked and may contain absolute machine-specific paths.

If `dak.ini` exists next to the executable, read defaults from section `[FixInsightCL]`:

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

[Build]
; optional default Delphi version used when --delphi is omitted by dfm-check/global-vars
DelphiVersion=

[Diagnostics]
; bounded source snippets for build/dfm-check failures
; SourceContext = auto | off | on
; SourceContextLines = lines shown before/after the hit (default 2)
SourceContext=auto
SourceContextLines=2

[WebCore]
; path to TMSWebCompiler.exe
CompilerPath=
```

Notes:

- Singular string values (`Path`, `Output`, `Settings`, `Args`) override only when the new value is non-empty.
- Booleans (`Silent`, `Xml`, `Csv`) override only when the key is present and parseable (`true/false/1/0/yes/no`).
- List-like values are **merged + deduped** case-insensitively, preserving first-seen order:
  - `[FixInsightCL].Ignore`
  - `[FixInsightIgnore].Warnings`
  - `[ReportFilter].ExcludePathMasks`
- `[FixInsightIgnore].Warnings` is used for report post-processing only (see §12).
- Effective FixInsight path ignore list passed as `--fi-ignore="..."` is merged from:
  - merged `dak.ini` defaults
  - CLI `--fi-ignore`
  Dedupe case-insensitively and keep first-seen order.
- `[ReportFilter].ExcludePathMasks` only affects report post-processing (see §12); it does not affect parameter generation.
- `[PascalAnalyzer]` is only used when `--pascal-analyzer true` is present (see §13).

## 3. Output model

### 3.1 Common computed fields (internal representation)

- `ProjectDpr` (absolute) — resolved from `.dproj` MainSource
- `Defines` (list of strings)
- `UnitSearchPath` (list of absolute paths; deduped; expanded)
- `LibraryPath` (list of absolute paths; deduped; expanded)
- `UnitScopes` (list of strings) — from `DCC_Namespace` (or option set)
- `UnitAliases` (optional list)
- `FixInsightExe` (optional; resolved from `PATH` or `HKCU\Software\FixInsight\Path`)
- `FixInsightExtra` (optional; output/ignore/settings/xml/csv/silent, from cascading `dak.ini` + CLI overrides)
- `SettingsFile` (optional; user may add later)

### 3.2 Output kinds

### 3.3 `global-vars` output model

`global-vars` reports unit-level declarations with these declaration kinds:

- `var`
- `threadvar`
- `typedconst`
- `classvar`

JSON output shape:

```json
{
  "summary": {
    "total": 483,
    "used": 447,
    "unused": 36,
    "ambiguities": 494,
    "emitted": 4,
    "filter": "writes-only;unit=*BTREES*"
  },
  "symbols": [
    {
      "declaringUnit": "BTREES",
      "fileName": "F:\\path\\BTREES.pas",
      "name": "HeapError",
      "type": "Boolean",
      "kind": "var",
      "line": 17,
      "column": 3,
      "usedBy": [
        {
          "unit": "BTREES",
          "routine": "InitHeap",
          "file": "F:\\path\\BTREES.pas",
          "line": 88,
          "column": 9,
          "access": "write"
        }
      ]
    }
  ],
  "ambiguities": [
    {
      "name": "SomeGlobal",
      "unit": "ConsumerUnit",
      "routine": "RunWork",
      "file": "F:\\path\\ConsumerUnit.pas",
      "line": 42,
      "column": 7,
      "access": "read",
      "candidates": "UnitA.SomeGlobal; UnitB.SomeGlobal"
    }
  ]
}
```

Text output starts with:

```text
Summary: total=483 used=447 unused=36 ambiguities=494 emitted=4 filter=writes-only;unit=*BTREES*
```

Cache location:

- sibling `.dak/<ProjectName>/global-vars/cache/global-vars-cache.sqlite3`

Generated report location:

- sibling `.dak/<ProjectName>/global-vars/reports/`

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

In our CLI, these are toggled via `--fi-xml` / `--fi-csv` and the output file path is controlled by `--fi-output`
(`resolve`) or by the `analyze` output root.

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

Implementation note: when FixInsightCL is invoked and the output path is relative, we canonicalize it to an absolute
path before running so the report lands in a deterministic location for post-processing.

Apply `ExcludePathMasks` in two layers:

1. Best case: if FixInsight supports source include/exclude via its settings file or another CLI flag, use it (we already pass `--fi-settings` through).
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

When `--pascal-analyzer true` is present (via `analyze`), run `palcmd.exe` (or `palcmd32.exe`) using the same
`.dproj` resolution + macro expansion pipeline we use for FixInsight.

### 13.1 `palcmd.exe` / `palcmd32.exe` path discovery (required)

Discovery order:

1. CLI override: `--pa-path "...\\palcmd.exe"` or `--pa-path "...\\palcmd32.exe"`
2. `dak.ini` override: `[PascalAnalyzer] Path=...`
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
- `/FA` (parse all files)
- `/T=n` where `n = min(CPUCount, 64)`

### 13.3 Output

If `--pa-output` (or `[PascalAnalyzer].Output`) is provided, treat it as the report root folder and pass it to PALCMD as `/R=...`.

## Appendix A — What we saw in the sample `.dproj`

In the provided sample `.dproj`, relevant properties appeared in the active `Base` group such as:

- `DCC_Define=...;$(DCC_Define)`
- `DCC_UnitSearchPath=...;$(DCC_UnitSearchPath)`
- `DCC_Namespace=...;$(DCC_Namespace)`
- `CfgDependentOn=mecDefault.optset`

This is exactly the chaining pattern we must support (property references itself at the tail to append defaults).
