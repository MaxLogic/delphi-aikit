# DelphiAIKit

DelphiAIKit builds Delphi projects, runs static analysis, and provides symbol
lookup and refactoring commands for developers and AI agents.

## What it can do

- Resolve project settings from `.dproj` and an optional `.optset`
- Expand IDE macros and environment variables
- Merge project search paths with the IDE library path
- Emit FixInsightCL parameters as `ini`, `xml`, or a runnable `bat`
- Run FixInsight and Pascal Analyzer through `analyze`
- Validate compiled DFM resources by streaming them in a generated test program via `dfm-check`
- Inspect text DFM component trees and event bindings via `dfm-inspect`
- Analyze project-level globals via `global-vars` with JSON/text reports, ambiguity reporting, and SQLite caching
- Inspect project unit dependencies via `deps`, with JSON/text reports, focused unit views, and cycle detection
- Navigate Delphi symbols semantically via `lsp` with `definition`, `hover`, file-scoped `symbols`, and capability probing backed by `DelphiLSP.exe`
- Build and query a reusable local Symbol Map via `symbol-map` with project/RTL/compiler-intrinsic indexing, definition lookup, symbol search, description, references, and central/project SQLite caches
- Find project-scoped Delphi symbol usages, plan or apply project-scoped renames, and review or transactionally apply conservative dead-code candidates via `find-usages`, `rename`, and `dead-code`
- Inspect, plan, and transactionally remove Delphi `with` statements via `remove-with`
- Compare class-method signatures or request guarded alignment suggestions and plan artifacts with [`signature`](docs/signature.md)

## Good use cases

- Running FixInsight in CI or scripted builds
- Reproducing the exact IDE configuration in a headless environment
- Comparing config differences between platforms or build types
- Checking unit dependencies before debugging or refactoring
- Finding a symbol's definition, hover text, or file-scoped document symbols
- Looking up project, source-available RTL, and compiler-intrinsic symbols through a deterministic cache when LSP is unavailable, incomplete, or too expensive for bulk work
- Reviewing exact project-scoped symbol usages before making a rename, then applying the rename with backups and rollback behavior
- Reviewing dead-code candidates before approving removal with transaction support
- Planning conservative `with` statement cleanup with JSON reports, safe skips, build verification, and rollback

## Repo-local AI skills

The [`agentskills/`](agentskills/) folder contains instructions and wrappers for AI agents using DelphiAIKit.

- `dak`: choose the skill for the task from the list below.
- `dak-build`: build or rebuild Delphi and TMS WEB Core projects through DelphiAIKit.
- `dak-static-analysis`: run Delphi static analysis through DelphiAIKit.exe and thin launchers (no Python required), then triage and apply conservative verified fixes.
- `dak-dfm-check`: inspect and validate `.dfm`-backed forms through `dfm-inspect`, `dfm-check`, or `build --dfmcheck`.
- `dak-global-vars`: analyze project-level globals, declaration sites, and read/write usage before refactoring shared state.
- `dak-project-unit-topology`: use `DelphiAIKit.exe deps` to inspect project unit topology, unresolved unit references, focused unit neighborhoods, and resolved project-unit cycles. Useful for questions like "why is this unit included?", "what fans into this area?", and "do we have cycles?"
- `dak-lsp`: use `DelphiAIKit.exe lsp` for semantic symbol navigation. Prefer it for definition/hover and file-scoped symbol lookup; route usages/references to `dak-semantic-refactoring` or `dak-symbol-map`, and switch back to `deps`, `global-vars`, or `rg` when the question is not semantic navigation.
- `dak-symbol-map`: use `DelphiAIKit.exe symbol-map` for cached project indexing, definition lookup, symbol search, symbol description, reference-like matches, and cache stats.
- `dak-semantic-refactoring`: use DAK `find-usages`, `rename`, and `dead-code` for declaration-aware evidence, dry-run plans, and explicitly approved transactional refactoring.
- `dak-remove-with`: use `DelphiAIKit.exe remove-with` to scan, plan, or apply conservative Delphi `with` statement rewrites with JSON reports, transactional backups, build verification, and rollback.

## Requirements

- Windows (we use the registry and `rsvars.bat`)
- Delphi (any supported version); build scripts/examples default to 12 / 23.0, but we can pass other versions
- FixInsightCL.exe only if we plan to run FixInsight (`analyze`) or use the generated `bat`
- Pascal Analyzer (PALCMD.EXE / PALCMD32.EXE) only if we plan to run it (`--pascal-analyzer true`)

## Build

Use a known-good Win64 DAK executable as the build host. Debug builds of
`projects\DelphiAIKit.dproj` produce `bin\Debug\DelphiAIKit.exe`; the host at
`bin\DelphiAIKit.exe` stays available if a candidate is broken.

Build from Windows:

```
bin\DelphiAIKit.exe build --project projects\DelphiAIKit.dproj --delphi 23.0 --config Debug --platform Win64 --ai
```

Use `--target Rebuild` when we need a full clean rebuild:

```
bin\DelphiAIKit.exe build --project projects\DelphiAIKit.dproj --delphi 23.0 --config Debug --platform Win64 --target Rebuild --ai
```

Only after the required candidate tests and analysis pass, build Release using
a known-good host outside the release destination (for example a verified copy
at `bin\stable\DelphiAIKit.exe`). Windows cannot overwrite a running host:

```
bin\stable\DelphiAIKit.exe build --project projects\DelphiAIKit.dproj --delphi 23.0 --config Release --platform Win64 --target Rebuild --ai
```

`build.bat` runs these native builds for production and tests in Win64 Debug.
`DAK_BUILD_HOST` can select another known-good executable; `DAK_DELPHI` defaults
to `23.0`. A missing host is an explicit prerequisite, with no alternate scripted
compiler pipeline. Test output is `tests\bin\Debug\DelphiAIKit.Tests.exe`.

The `build-delphi.bat` and `build-delphi.sh` wrappers are removed; call
`DelphiAIKit.exe build` directly. From WSL, run the same executable with
`/mnt/<drive>/...` or relative project paths; no launcher is needed. The
compiler's stdout and stderr are temporary files removed after the run, unless
we ask to keep them. `--keep-logs` keeps them as `stdout.log` and `stderr.log`
in a new `run-<guid>` folder under `<project dir>\.dak\<ProjectName>\build`;
`--log-dir "<path>"` replaces that root and implies `--keep-logs` (a relative
path is resolved against the project directory, not the working directory).
The kept folder is printed, and `--json` adds `kept_logs_dir`. If it cannot be
created, the build does not start; if the logs cannot be copied afterwards, the
build result is still reported together with `kept_logs_error` and the exit
code is nonzero. Kept logs are MSBuild's raw output and can echo a rejected
property value, so keep them under the ignored `.dak` or a folder we own.
`DAK_BUILD_DIAGNOSTICS_DIR` still copies the same two files into one named
directory (overwriting them) without the `run-<guid>` folder.

`build` defaults to incremental `Build`; use `--target Rebuild` (or `--rebuild true`) for a full rebuild.
Additional build flags:
- `--json` emits machine-readable build results.
- `--max-findings N` caps printed findings per category (default `5`).
- `--build-timeout-sec N` terminates hung builds after `N` seconds (`0` disables timeout).
- `--test-output-dir "<path>"` builds without touching the project's normal output folders: executables, libraries, packages and `.dcp` files go directly into `<path>`, and unit output (`.dcu`, plus `.o`/`.obj` object files) goes into `<path>\dcu`. DAK sets `DCC_ExeOutput`, `DCC_BplOutput`, `DCC_DcpOutput` and `DCC_BpiOutput` to `<path>`, and `DCC_DcuOutput`, `DCC_ObjOutput` and `DCC_HppOutput` to `<path>\dcu`, on every platform. Object files move with the DCUs, including the `.o` files of Linux64 builds; C++ headers (`.hpp`) follow the DCUs, and `.bpi` package interfaces follow the `.dcp` files, so a project's own `DCC_HppOutput` and `DCC_BpiOutput` are not written during a test build. A relative `<path>` is resolved against the working directory; a value with invalid path characters, or one that depends on the current drive (`\out`, `D:out`), stops the build before it starts with `Test output directory is not usable`.
- `--keep-logs` keeps the MSBuild `stdout.log` and `stderr.log` in a per-run `run-<guid>` folder (see above); `--log-dir "<path>"` chooses the log root and implies `--keep-logs`. Delphi/MSBuild builds only.
- `--define <symbol>` adds a Delphi compiler define while preserving the project/config/platform `DCC_Define` value. Repeat the switch for multiple symbols.
- `--unit-search-path "<path>"` prepends a Delphi unit search path while preserving the project/config/platform `DCC_UnitSearchPath` value. Repeat the switch for multiple paths.
- `--dfmcheck` runs DFM streaming validation after a successful source build (presence flag; same as calling `dfm-check` separately). If the source build fails, DAK reports that `dfm-check` was not run instead of treating the skipped validation as the failing phase.
- `--dfm "MainForm.dfm,Frames\DetailSubEditDocs.dfm"` scopes post-build `--dfmcheck` to selected forms.
- `--all` scopes post-build `--dfmcheck` to all forms (default when `--dfm` is omitted).
- `--builder auto|delphi|webcore` selects the build backend. `auto` is the default; it detects TMS WEB Core project markers in the target `.dproj`.
- `--webcore-compiler "<path>"` overrides `TMSWebCompiler.exe` discovery for WebCore builds.
- `--pwa` and `--no-pwa` force WebCore `/PWA` on or off. Without either flag, DAK follows the project's `TMSWebPWA` setting.
- `--source-context auto|off|on` controls whether build/`dfm-check` failure output includes nearby source lines when a file and line can be resolved.
- `--source-context-lines N` controls how many lines before/after the hit are shown (default `2`).
- When `--ai` is enabled, build failures can append optional `lsp` semantic hints when DAK can resolve a meaningful token or enclosing symbol. Missing, unsupported, or empty LSP data leaves the original compiler failure untouched.
- `--rsvars "<path>"` overrides `rsvars.bat` for build and post-build `--dfmcheck` validation.

The reported output file (`Build succeeded: <path>`, `output` in `--json`) is the file the compiler writes, named the way the compiler names it. The platform's rules come from the compiler targets the project imports: `.exe`, `.dll` and `.bpl` on Windows; no extension for a Linux64 program, `lib<name>.so` for a Linux64 library and `bpl<name>.so` for a Linux64 package; an Android program is `lib<name>.so`, and an Android package is a static `lib<name>.a` in the `.dcp` folder (`DCC_DcpOutput`). The main `.dpr`/`.dpk` decides the rest, because the compiler reads it and ignores the project's `DllPrefix`, `DllSuffix`, `DllVersion` and `DCC_DependencyCheckOutputName` (the IDE only mirrors the source into them); the project's `OutputExt` (the IDE's "Target file extension") is the exception: it reaches the compiler for programs and libraries (with a dot put in front of the value, so `.ocx` gives `..ocx`), a package ignores it, and a `{$E}` in the source wins over it. `{$LIBPREFIX 'x'}` replaces the platform prefix (an empty value removes it), `{$LIBSUFFIX 'x'}` adds a suffix, `{$LIBVERSION 'x'}` adds a version (`<prefix><name><suffix>.<version>.<ext>` on Windows and macOS; on Linux64 and Android the version follows the extension, as in `lib<name><suffix>.so.<version>`), and `{$E ext}` / `{$EXTENSION ext}` replaces the extension. The `{$SOPREFIX}`, `{$SOSUFFIX}` and `{$SOVERSION}` aliases work the same. These apply to libraries and packages; a program keeps its name and takes only `{$E}`, except an Android program, which also takes the prefix and the suffix (not the version). `{$LIBSUFFIX AUTO}`, the default of new Delphi 12 packages, is the version of the installed RTL package, read from the one `rtl<N>.bpl` in the Delphi `bin` folder (`290` for Delphi 23.0, on Win32 and Linux64 alike). A package's `DCC_BplOutput` (or `DelphiDLLOutputPath` when that is empty) is where it is reported. DAK reads the source in order, as the compiler does: directives inside `//`, `{ }` and `(* *)` comments and string literals do not count, several directives on a line all count, and each `{$I file}` found next to the including file is expanded where it appears, so a directive after the include overrides one in it. An include it cannot find (for example `Jedi.inc` on the unit search path) does not stop the naming: the name assumes no directive in it and the result carries the note `naming include <name> not read; name assumes no directives in it`; if the compiler used a directive from that include, the predicted file is absent and the status is `output_missing` with the note. The name is unresolved, with the reason in the message, when the main source cannot be read, an include has a wildcard or `%`, a naming directive has a form DAK does not evaluate (for example an unquoted prefix), `AUTO` has no single `rtl<N>.bpl` to read, `MainSource` or `DCC_ExeOutput` is not a usable path, or the platform has no known rules. Conditional compilation (`{$IFDEF}`) around a directive is not evaluated, so a name that depends on it can be reported wrongly. If a successful build did not write that file, the status is `output_missing` with the expected path. If DAK has no naming rules for the platform, `output` is empty and the message says why.

Delphi/MSBuild builds also forward the IDE's `%APPDATA%\Embarcadero\BDS\<version>\environment.proj` properties to MSBuild, as the IDE does, so custom user variables that exist only there reach your project. DAK cannot know which variables a project references, so it forwards every property that the process environment does not already define; the process environment wins. Values are XML-entity-decoded (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#NN;`, `&#xNN;`) before they reach MSBuild. A value that contains a line break cannot be passed on a command line: DAK skips that property and `--verbose` names it without showing the value. `--verbose` also prints the generated MSBuild arguments with every `environment.proj` value redacted.

For TMS WEB Core projects, `build` can call `TMSWebCompiler.exe` directly:

```
bin\DelphiAIKit.exe build --project "C:\path\WebApp.dproj" --builder webcore --config Debug --webcore-compiler "F:\TMS-SmartSetUp\Products\tms.webcore\Bin\Win64\TMSWebCompiler.exe" --ai
```

`--builder` can usually be omitted for WebCore projects because `auto` detects strong markers such as `TMSWebProject`, `TMSWebHTMLFile`, and `TMSWEBCorePkg...` package references:

```
bin\DelphiAIKit.exe build --project "C:\path\WebApp.dproj" --config Debug --webcore-compiler "F:\TMS-SmartSetUp\Products\tms.webcore\Bin\Win64\TMSWebCompiler.exe" --ai
```

For WebCore builds, Delphi-only options such as `--dfmcheck`, `--rsvars`, `--envoptions`, `--define`, and `--unit-search-path` are rejected instead of being silently ignored.

For MaxProfiler or other temporary instrumented Delphi builds, prefer a real project build configuration when one exists. If the project should not be edited, use the typed overlays instead of raw MSBuild property injection:

```cmd
bin\DelphiAIKit.exe build --project "C:\path\App.dproj" --delphi 23.0 --platform Win64 --config Debug --target Rebuild --define maxProfiling --unit-search-path "C:\path\MaxProfiler\runtime" --ai
```

Raw `msbuild.exe /p:DCC_Define=...` or `/p:DCC_UnitSearchPath=...` calls are reserved for debugging DAK's build behavior, not normal profiler builds.

## Command Unit Layout

Command entry units in `src/` follow this naming pattern:
- `Dak.Build` and `Dak.Resolve` are thin facades that keep the public entry points.
- `Dak.Build.Runner`, `Dak.Resolve.Runner`, `Dak.Analyze.ProjectRunner`, and `Dak.Analyze.UnitRunner` hold the command execution logic.
- Shared command helpers stay in dedicated support units such as `Dak.Build.Summary`, `Dak.Build.Types`, and `Dak.Analyze.Common`.

## Quick start

Build the console app, then run:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0
```

`--project` (alias: `--dproj`) accepts `.dproj`, `.dpr`, or `.dpk`. If we pass `.dpr`/`.dpk`, the resolver uses the sibling `.dproj`.
`--delphi` is required; `23` is normalized to `23.0`. We can pass other Delphi versions here as well.
From WSL, `--project` and `--unit` accept and normalize Linux-style absolute paths in `/mnt/<drive>/...` form.
Other Linux absolute paths (for example `/home/...`) are rejected.
Use `wslpath -w` when explicit conversion or compatibility with other callers is needed.

If `--platform` or `--config` is omitted, we default to `Win32` and `Release`.

By default, we write `ini` output to stdout. To write a file or change the output kind:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win64 --config Release --delphi 23.0 --format bat --out-file "C:\temp\run_fixinsight.bat"
```

For extra diagnostics during troubleshooting, enable verbose output:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --verbose true
```

WSL example with Linux-style path:

```
./bin/DelphiAIKit.exe resolve --project /mnt/c/path/MyProject.dproj --platform Win32 --config Debug --delphi 23.0
```

To run FixInsightCL directly, use `analyze` (FixInsight is on by default):

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0
```

When `--out` is omitted, `analyze` writes under the target's sibling `.dak` working tree:
- project runs: `.dak/<ProjectName>/`
- unit runs: `.dak/_unit/<UnitName>/`

To inspect workspace selection and source provenance without running analyzers:

```text
bin\DelphiAIKit.exe analyze-workspace --project "C:\path\Project.dproj" --json
bin\DelphiAIKit.exe analyze-workspace --unit "C:\path\Main.pas" --project-context "C:\path\Project.dproj" --json
```

`--workspace-root` uses the same selectors and settings precedence as analysis.
The JSON contains `workspace` and `provenance` records for the target and DAK.
Inspection creates no report or scratch files; an optional `--out` hint is accepted without changing that directory.
Exit codes are 0 for complete or inapplicable VCS evidence, 2 for invalid input/settings,
3 for partial evidence such as missing VCS tools, and 4 for capture/output failures.

To validate DFMs in CI using generated DFMCheck projects:

```
bin\DelphiAIKit.exe dfm-check --dproj "C:\path\Project.dproj" --config Release --platform Win32 --all
```

To inspect a text DFM without generating a harness project:

```
bin\DelphiAIKit.exe dfm-inspect --dfm "tests\fixtures\MainForm.dfm" --format tree
bin\DelphiAIKit.exe dfm-inspect --dfm "tests\fixtures\MainForm.dfm" --format summary
```

To analyze global variables used in a Delphi project:

```
bin\DelphiAIKit.exe global-vars --project "C:\path\Project.dproj" --format json
```

To inspect project unit dependencies for AI debugging:

```
bin\DelphiAIKit.exe deps --project "C:\path\Project.dproj" --format json
bin\DelphiAIKit.exe deps --project "C:\path\Project.dproj" --format text --unit ProblemUnit
```

To navigate Delphi symbols semantically:

```
bin\DelphiAIKit.exe lsp definition --project "C:\path\Project.dproj" --file "C:\path\Unit1.pas" --line 42 --col 17 --format json
bin\DelphiAIKit.exe lsp symbols --project "C:\path\Project.dproj" --file "C:\path\Unit1.pas" --query "Customer" --format json
```

To build and query DAK's local Symbol Map:

```
bin\DelphiAIKit.exe symbol-map stats --project "C:\path\Project.dproj" --format json
bin\DelphiAIKit.exe symbol-map stats --project "C:\path\Project.dproj" --cache-root "C:\dak-cache\symbol-map" --format json
bin\DelphiAIKit.exe symbol-map index --project "C:\path\Project.dproj" --format json
bin\DelphiAIKit.exe symbol-map find-definition --project "C:\path\Project.dproj" --file "C:\path\Unit1.pas" --line 42 --col 17 --format json
bin\DelphiAIKit.exe symbol-map search-symbols --project "C:\path\Project.dproj" --query "Customer" --limit 20 --format json
bin\DelphiAIKit.exe symbol-map describe-symbol --project "C:\path\Project.dproj" --symbol "Name" --owner "TCustomer" --format json
bin\DelphiAIKit.exe symbol-map find-references --project "C:\path\Project.dproj" --symbol "TCustomer" --limit 20 --format json
```

`symbol-map` is DAK's own deterministic source index, independent of DelphiLSP and `delphi-lookup`. Use LSP for semantic editor-style queries and Symbol Map for reusable project indexes and cached source inventories. The index also provides a basis for future bulk refactoring support such as `remove-with`.

To inspect and rename a project-scoped symbol through DelphiSemantics:

```
bin\DelphiAIKit.exe find-usages --project "C:\path\Project.dproj" --symbol "OldName" --format json
bin\DelphiAIKit.exe rename --project "C:\path\Project.dproj" --symbol "OldName" --new-name "NewName" --format text
bin\DelphiAIKit.exe rename --project "C:\path\Project.dproj" --symbol "OldName" --new-name "NewName" --apply --format json
bin\DelphiAIKit.exe dead-code --project "C:\path\Project.dproj" --profile conservative --format json
bin\DelphiAIKit.exe dead-code --project "C:\path\Project.dproj" --profile conservative --apply --format json
```

`rename` is non-mutating by default. `--apply` creates per-file `.bak` backups and restores original bytes if edit application fails.
`dead-code` is report-only by default; use `audit`, `conservative`, or `legacy-static` profiles to control how aggressively candidates are classified. Guarded `--apply` requires an explicit profile, writes project-scoped backups/manifests, verifies the build, and rolls back on verification failure.

The central cache stores reusable unit models by content and compiler context. By default it is created under `%LOCALAPPDATA%\DelphiAIKit\symbol-map\v1\symbol-map.sqlite3`, with `%USERPROFILE%\.dak\symbol-map\v1\symbol-map.sqlite3` as the fallback. Override it with `--cache-root "<path>"` or the `DAK_SYMBOL_MAP_CACHE_ROOT` environment variable; JSON output reports the resolved cache paths so WSL/Windows path confusion is visible.

Each project also gets a lightweight project cache under the `.dproj` sibling `.dak/<ProjectName>/symbol-map/project-index.sqlite3`. That project cache records the resolved project context and links project units to central cache rows, but it does not duplicate the central unit model. Deleting the project `.dak/<ProjectName>/symbol-map/` folder forces project relinking on the next query. Deleting the central cache forces all shared unit models, compiler intrinsics, and source-available RTL rows to be rebuilt. Both cleanup operations are safe because Symbol Map is derived data.

Changing source content or compiler profile context creates new central unit keys. Changing project context relinks project rows on the next index or query.

`symbol-map index` scans project units and, when source roots are available for the selected Delphi context, indexes source-available RTL units into the compiler profile. Targeted `symbol-map index --unit <path>` indexes only the requested unit and reports `rtlSource.status` as `not-indexed`; run the project-wide index or a query command when the RTL cache should be warmed. Missing RTL roots are non-fatal diagnostics because compiler intrinsics are seeded synthetically. Query commands refresh the project index when needed before answering. `find-references` currently reports token-name matches with explicit `confidence="token-name-match"` metadata; it is useful as an indexed search result, not yet a compiler-proven semantic reference identity.

To inspect or remove Delphi `with` statements:

```
bin\DelphiAIKit.exe remove-with --project "C:\path\Project.dproj" --all --mode scan --format json
bin\DelphiAIKit.exe remove-with --project "C:\path\Project.dproj" --dir "C:\path\Project\src" --mode plan --format json
bin\DelphiAIKit.exe remove-with --project "C:\path\Project.dproj" --unit "C:\path\Project\CustomerUnit.pas" --mode apply --format json
```

`remove-with` has three modes:
- `scan` parses selected project units and reports each `with` statement, selector text, source ranges, selector counts, and nesting depth.
- `plan` adds AST-backed symbol resolution, resolver classifications, planned source edits, skipped statements, and warnings without changing source files.
- `apply` writes planned safe edits transactionally, then runs build verification.

Target exactly one scope with `--unit`, `--dir`, or `--all`. Output defaults to JSON and can be written with `--output "<path>"`; `--output -` keeps stdout output.

Plan and apply reports account for every discovered `with` statement across three top-level arrays: `planned`, `skipped`, and `covered`. Covered rows are nested statements already handled by a parent rewrite; they are counted in `summary.covered` and `telemetry.coveredStatements` without duplicating planned edit counts.

DAK builds one shared project model, extracts AST-backed unit data, and uses indexed semantic lookups for local variables, parameters, current-class members, unit globals/constants, source-available ancestors, interfaces, helpers, indexed/default properties, and active nested `with` receiver stacks. The legacy declaration scanner is retained only as a flat compatibility inventory while the AST-backed semantic model reaches full reporting parity. DAK qualifies only identifiers it can resolve safely. Ambiguous or unproven bindings are reported as skipped, including classifications such as `external`, `unsupported`, `unresolved`, and `ambiguous-to-DAK`.

Record selectors that require preserved aliasing use pointer temps where the planner can prove the selector is addressable. Object and interface selectors can use reference temps. Non-addressable selectors, property selectors, call selectors, controlled statement contexts, and source-unavailable member lookups are skipped instead of guessed.

`apply` creates a run workspace under `.dak/<ProjectName>/remove-with/<RunId>/`, backs up every changed file, writes a manifest with hashes and encoding/line-ending facts, and performs exact-byte rollback if verification fails. Successful and rolled-back runs report verification gates, transaction status, manifest paths, and per-file changed/restored status.

`remove-with` resolves symbols through the local AST/source model and verifies rewrites through builds and rollback. DelphiLSP remains available for navigation and future capability probes.

The guarded refactoring artifact workflow supports removing one explicit
implementation `uses` import. Give `uses` a UTF-8 request file:

```json
{"operation":"uses.remove-implementation-import","consumerFileName":"C:\\path\\Project\\Consumer.pas","unitName":"UnusedUnit"}
```

```text
bin\DelphiAIKit.exe uses --project "C:\path\Project.dproj" --platform Win64 --config Debug --delphi 23.0 --format json --request "C:\path\request.json" --plan-out "C:\path\new-plan.json"
bin\DelphiAIKit.exe refactor-apply --project "C:\path\Project.dproj" --platform Win64 --config Debug --delphi 23.0 --apply-plan "C:\path\new-plan.json"
```

The plan command never edits source and creates the plan file only when the
semantic evidence is complete; it will not overwrite an existing output file.
Its JSON response has `status`, `reason`, and, on success, `plan`.
`refactor-apply` treats the saved file as intent, rebuilds the semantic plan
from a fresh project snapshot, and requires exact agreement before mutation.
It runs a baseline build and a post-edit build, returns `status`, `reason`, and
`journal`, and rolls back an ordinary post-edit failure. On a rollback conflict,
preserve the reported journal and changed bytes for explicit recovery; do not
blindly rerun apply. A rejected or stale plan does not authorize edits.

For read-only import discovery, use the same command without `--plan-out` and
this request:

```json
{"operation":"uses.suggest-explicit-import-candidates","consumerFileName":"C:\\path\\Project\\Consumer.pas","identifier":"MissingName"}
```

The report lists source-backed providers for the selected unbound identifier,
including all ambiguous candidates without selecting one. It includes a
classification, context fingerprint, analyzed roots, counts and completeness.
Discovery currently supports simple integer-constant providers with complete
semantic evidence; unsupported or unavailable facts return a blocked report.
Discovery never changes source or creates an apply artifact, and rejects
`--plan-out` even when there is exactly one candidate.

This is not a general `uses` cleanup command yet. Import additions,
interface-to-implementation moves, conditional clauses, initialization-sensitive
units, unresolved bindings, and other unsupported evidence remain blocked or
candidate-only. No extract-interface or extract-method command is shipped.

`deps` is JSON-first. The JSON contract is intended for tooling and AI agents and includes:
- project metadata
- `nodes` with resolution state and project-membership flag
- `edges` labeled as `project`, `contains`, `interface`, or `implementation`
- `unresolvedUnits`
- `parserProblems`

`deps` always writes the rendered report to stdout. When `--output` is omitted, it also persists a copy under the target project's sibling `.dak/<ProjectName>/deps/` folder (`deps.json` or `deps.txt`).

`deps` shows which units depend on an area, which unit references are unresolved, and which resolved project units form cycles. It does not build a call graph, symbol graph, or full semantic/reference model.

Current scope:
- shipped: deterministic JSON topology, AI-friendly text summaries, `--unit` focus mode, cycle/SCC reporting over resolved project units
- deferred: DOT / Graphviz export

Optional:
- `--delphi 23.0` selects Delphi version for automatic `rsvars.bat` resolution.
- `--rsvars "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"` imports RAD Studio environment variables before `msbuild`.
- `--dfm "MainForm.dfm,Frames\DetailSubEditDocs.dfm"` validates only selected DFM resources.
- `--all` validates all DFM resources (default when `--dfm` is not provided).
- `--source-context auto|off|on` controls whether failures emit nearby source lines when DAK can resolve the file.
- `--source-context-lines N` controls the bounded source window (default `2`, meaning 2 lines before and after).
- `--verbose true` shows stage logs and detailed per-resource output.
- `tools\Validate-Dfm.ps1` is a thin wrapper around the same CLI command.

`dfm-check` auto-loads `rsvars.bat` when either:
- `--rsvars` is provided, or
- `--delphi` is provided, or
- `dak.ini` provides `[Build] DelphiVersion=<version>` (cascading settings).
If none is available, `dfm-check` fails because it requires a Delphi context.

`global-vars` auto-loads `rsvars.bat` when either:
- `--delphi` is provided, or
- `dak.ini` provides `[Build] DelphiVersion=<version>` (cascading settings).
If no Delphi context can be resolved, `global-vars` still runs with `.dproj`-only traversal where possible, but search-path-sensitive projects may be less accurate.

`dfm-check` stages:
- generate a `_DfmCheck` harness project under sibling `.dak/<ProjectName>/dfm-check/runs/<RunId>/generated/` (no external `DFMCheck.exe`)
- treat the source `.dpr`, `.dproj`, `.pas`, and `.dfm` files as read-only inputs; all project rewriting is confined to the generated run workspace
- remove the `madExcept` define only from the generated DPROJ clone and add generated blocker units for standard madExcept startup units
- synthesize the generated harness `DCC_UnitSearchPath` from the source project's effective compile search path while keeping project/discovered form-unit directories ahead of inherited IDE/library-path entries so normal builds and generated validation builds resolve the same units
- generate `_DfmCheck_Register.pas` inside that owned run workspace so source roots stay clean
- inject `tools\inject\DfmStreamAll.pas` into the generated harness project
- resolve bundled inject files by walking ancestor directories from `DelphiAIKit.exe` (`tools\inject` first, then `docs\delphi-dfm-checker\tools\inject`), so detached build/test binaries can still run `dfm-check`
- run the harness entrypoint with `ExitCode := TDfmStreamAll.Run;`
- build `_DfmCheck.dproj` via `msbuild`
- run `_DfmCheck.exe` and propagate its exit code (`0` success, non-zero means streaming failures)
- force Delphi response-file build mode (`DCC_ForceExecute=true`) to avoid long command-line failures
- isolate generated DCU/EXE output directories per run for deterministic CI behavior
- prune stale owned run directories from earlier interrupted `dfm-check` runs before generating a new workspace
- in full-scope mode (`--all` or no explicit `--dfm`), cache unchanged forms in `<Project>.dfmcheck.cache` and skip revalidation on later runs
- in full-scope + verbose mode, print progress lines as `CHECK <current>/<total> <resource>`
- generated build and validator processes use a 30-minute default timeout; set `DAK_DFMCHECK_TIMEOUT_MS` to a positive millisecond value to override it
- clean the owned `.dak/.../runs/<RunId>/` workspace by default, and when `DAK_DFMCHECK_KEEP_ARTIFACTS=true` keep only that owned run while still removing legacy source-root `_DfmCheck*` sidecars

`dfm-check` output contract:
- non-verbose: actionable output only (`FAIL` lines + summary + final result)
- verbose: full stage logs and per-resource output
- each `FAIL` line includes mapped source context when available: `[unit=... pas=... dfm=...]`
- on failure, DAK also reports details to help locate the cause:
  - `[dfm-check] FAIL target: resource=... unit=... pas=... dfm=...`
  - `[dfm-check] FAIL clue: member=...`
  - `[dfm-check] FAIL clue: handler=...`
  - `[dfm-check] FAIL clue: handler declaration line=<N>: procedure ...`
  - `[dfm-check] FAIL clue: source context: <file>`
  - `[dfm-check] FAIL clue: verify handler signature matches event type for <On...>.`
- if application units still link madExcept-related code unconditionally, generated compilation fails before execution with an instruction to wrap all related `uses` entries and calls in `{$IFNDEF DFMCheck} ... {$ENDIF}`; do not remove madExcept from the real application project

## `lsp`

`lsp` is DAK's one-shot semantic wrapper around `DelphiLSP.exe`.

Use it for:
- symbol definition lookup
- hover/type information
- file-scoped symbol search via `textDocument/documentSymbol`
- capability probing for the external DelphiLSP build

Core operations:
- `definition`
- `hover`
- `symbols` (file-scoped on Delphi 23 external `DelphiLSP.exe`)
- `probe` (compare `contextFile` and `settingsFile` capability handshakes)

Examples:

```
bin\DelphiAIKit.exe lsp definition --project "C:\path\Project.dproj" --file "C:\path\Unit1.pas" --line 42 --col 17 --format json
```

```
bin\DelphiAIKit.exe lsp hover --project "C:\path\Project.dproj" --file "C:\path\Unit1.pas" --line 42 --col 17 --format json
```

```
bin\DelphiAIKit.exe lsp symbols --project "C:\path\Project.dproj" --file "C:\path\Unit1.pas" --query "Customer" --limit 20 --format json
```

Rules:
- prefer `--format json` for agent/tool consumption
- `--line` and `--col` are 1-based
- `symbols` is file-scoped on Delphi 23 external `DelphiLSP.exe`; pass `--file` and treat results as `documentSymbol` output, not workspace-wide search
- external Delphi 23 and Delphi 13 `DelphiLSP.exe` builds do not provide `textDocument/references`; use `find-usages`, `symbol-map find-references`, `global-vars`, or `rg` according to the question
- generated context and logs live under sibling `.dak/<ProjectName>/lsp/`
- `--rsvars` and `--envoptions` are optional advanced overrides, not normal-use requirements
- unlike `deps` or `global-vars`, `lsp` hard-fails when DAK cannot build a real Delphi semantic context
- current external-server guidance is based on verified Delphi 23 (`23.0`) and Delphi 13 (`37.0`) behavior

Routing guidance:
- use `lsp` for semantic navigation questions
- use `deps` for project topology and cycle questions
- use `global-vars` for shared-state inventory and read/write usage
- use `rg` or other text search when the request is raw pattern matching instead of semantic binding

The JSON result contract is operation-specific:
- `definition` returns `result.locations[]`
- `probe` returns per-mode capability matrices for `contextFile` and `settingsFile`, and can show the generated init/config payloads with `--show-init-options`
- `hover` returns `result.contentsText` plus optional markdown/range data; it returns content for a symbol position when DAK resolves the Win32/Win64 compiler DLL beside `DelphiLSP.exe` (positions without a symbol stay empty); otherwise `warnings` names why and hover may be empty
- external Delphi 23 and Delphi 13 `DelphiLSP.exe` builds support `definition`, `hover`, and file-scoped `documentSymbol`; only `textDocument/references` and `workspace/symbol` are unsupported
- `symbols` returns `result.symbols[]` from file-scoped `documentSymbol` data

## `global-vars`

`global-vars` analyzes unit-level globals declared in project units and reports:
- declaration unit/file/line
- variable name and type
- declaration kind: `var`, `threadvar`, `typedconst`, `classvar`
- `usedBy` routines with access mode
- ambiguity records when a usage matches multiple visible candidates

Supported filters:
- `--unused-only`
- `--unit "<pattern>"`
- `--name "<pattern>"`
- `--reads-only`
- `--writes-only`

Examples:

```
bin\DelphiAIKit.exe global-vars --project "C:\path\Project.dproj" --format json --unused-only
```

```
bin\DelphiAIKit.exe global-vars --project "C:\path\Project.dproj" --format json --unit "*Data*" --name "Cache"
```

```
bin\DelphiAIKit.exe global-vars --project "C:\path\Project.dproj" --format text --writes-only
```

JSON output contract:

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
      "usedBy": []
    }
  ],
  "ambiguities": [
    {
      "name": "SomeGlobal",
      "unit": "ConsumerUnit",
      "routine": "RunWork",
      "file": "F:\\path\\ConsumerUnit.pas",
      "line": 88,
      "column": 14,
      "access": "read",
      "candidates": "UnitA.SomeGlobal; UnitB.SomeGlobal"
    }
  ]
}
```

Text output starts with a summary line:

```text
Summary: total=483 used=447 unused=36 ambiguities=494 emitted=4 filter=writes-only;unit=*BTREES*
```

Project cache location:
- sibling `.dak/<ProjectName>/global-vars/cache/global-vars-cache.sqlite3`

Generated reports location:
- sibling `.dak/<ProjectName>/global-vars/reports/`

To capture resolver diagnostics (warnings, missing paths, macro issues) into a log file:

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --log-file "C:\temp\resolver.log"
```

To also include resolver diagnostics in stderr/stdout output (useful when redirecting into a report), add:

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --log-file "C:\temp\resolver.log" --log-tee true
```

When `resolve` writes to stdout, `--format` and `--out-file` control output. `analyze` always writes reports to files.

We run `rsvars.bat` from the default Delphi installation path to pick up IDE environment variables.
If Delphi is installed in a non-standard location, pass the path explicitly:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --rsvars "D:\Apps\Embarcadero\Studio\23.0\bin\rsvars.bat"
```

If the IDE library path is missing in the registry, we fall back to `EnvOptions.proj`. We can override that path too:

```
bin\DelphiAIKit.exe resolve --project "C:\path\Project.dproj" --platform Win32 --config Debug --delphi 23.0 --envoptions "D:\Config\EnvOptions.proj"
```

## Analyzer pass-through and timeout options

We can pass analyzer options either via cascading `dak.ini` files or the CLI. CLI values win.

### Cascading `dak.ini` lookup

Workspace selection happens before the full settings cascade.
`--workspace-root` wins; otherwise the closest ancestor `[Workspace].Root`
selector wins, followed by the executable `dak.ini` fallback and default
`auto`. Bootstrap may scan to the filesystem root, but reads no other settings.

After selection, `dak.ini` files load in cascading order (lowest to highest
precedence) from the workspace root through each subfolder down to the `.dproj`
folder. Selector files above that boundary contribute only `[Workspace].Root`.
For backward compatibility, the executable INI contributes normal defaults
only when no selector exists and default `auto` is used. The
current working directory does not affect settings discovery.

Lists are merged in first-seen order, with duplicates removed case-insensitively. Single string values override earlier values only when non-empty.

Example layout (more local files override/extend more global ones):

```
workspace/
  dak.ini
  src/
    dak.ini
    app/
      MyApp.dproj
      dak.ini
```

The git-tracked reference file is `dak-template.ini`. Copy it to a
workspace-root `dak.ini` when we need machine-local overrides such as compiler
paths. That root `dak.ini` is intentionally untracked; nested project or fixture
`dak.ini` files remain normal tracked inputs when we add them on purpose.

Supported FixInsight options:

- `--fi-output`
- `--fi-ignore`
- `--fi-settings`
- `--fi-silent`
- `--fi-xml`
- `--fi-csv`
- `--fi-timeout-sec`

Supported Pascal Analyzer options:

- `--pa-path`
- `--pa-output`
- `--pa-args`
- `--pa-timeout-sec`

Tracked `dak-template.ini`:

```
[FixInsightCL]
Path=
Output=
Ignore=
Settings=
Silent=false
Xml=false
Csv=false
; external process timeout in seconds; empty uses the built-in default
TimeoutSec=

[FixInsightIgnore]
; semicolon-separated FixInsight rule IDs to suppress in report post-processing (e.g. W502;C101;O801)
Warnings=

[ReportFilter]
; semicolon-separated Windows-style file mask patterns for report post-processing
ExcludePathMasks=

[PascalAnalyzer]
; path to palcmd.exe / palcmd32.exe (or its folder)
Path=
; report root folder (PALCMD /R=...); raw XML reports only, findings stay in the report
Output=
; optional PALCMD args; DAK owns report, parse-scope, quiet, and thread arguments
Args=
; external process timeout in seconds; empty uses the built-in default
TimeoutSec=

[MadExcept]
; path to madExceptPatch.exe (or its folder)
Path=

[Build]
; optional default Delphi version used when --delphi is omitted (for example: dfm-check)
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

`Path` is optional and can point to FixInsightCL.exe (or its folder). Relative paths are resolved against the executable folder.
`TimeoutSec` is optional for `[FixInsightCL]` and `[PascalAnalyzer]`; CLI values override it. Omit or leave it empty to use the built-in bounded timeout.

`[MadExcept].Path` is optional and can point to `madExceptPatch.exe` (or its folder). If empty, the native `build` runner falls back to `PATH` and common madExcept install folders.

## Static-analysis workspace root

Static analysis uses a workspace boundary; it does not require a Git repository.
See [reviewed analysis baselines](docs/reviewed-analysis-baselines.md) for the
current finding reviews, recorded cleanup debt and remaining external acceptance limits.
Set `[Workspace].Root` in `dak.ini`, or pass `--workspace-root` to `analyze`,
`analyze-unit`, `analyze-doctor`, or the skill launchers. The CLI wins. Otherwise the closest
ancestor `dak.ini` selector wins, with the executable `dak.ini` fallback; if no
selector is configured, `auto` searches to the filesystem root and chooses the
nearest `.git` or `.svn` marker, then falls back to the project directory.

`Root` accepts `auto`, `git`, `svn`, `project`, or a fixed root path. `git` and
`svn` require that marker. `project` deliberately ignores surrounding version
control. A fixed root must exist and contain the analyzed project or unit.
Relative fixed paths are resolved from the `dak.ini` that declares them. After
root selection, the normal settings cascade is bounded by that workspace.

Schema-3 `summary.json` records `provenance.target` with the workspace root,
VCS kind, nullable `revision`, `dirty`, `changed_files`, `source_inputs`, Git
submodules or SVN externals, and capability states for revision, status,
changed files, inventory, and `nested_roots`. States are `available`,
`fallback`, `unavailable`, or `not_applicable`. Git/SVN command loss uses a
bounded filesystem inventory and does not fail analysis; it records a concise
diagnostic instead of a false clean state.

## Report filtering (post-processing)

We support deterministic report filtering after analysis:

- `--exclude-path-masks "<m1;m2;...>"` (or `[ReportFilter].ExcludePathMasks`) removes findings whose reported file path matches any mask.
- `--ignore-warning-ids "W502;C101;O801"` (or `[FixInsightIgnore].Warnings`) removes findings for those FixInsight rule IDs.
- `--pal-ignore-rules "WARN54;PAL.optimization.parameter-is-var-can-be-changed-to-out-8d547169dfe78c92"` (or `[PascalAnalyzerIgnore].Rules`) excludes matching PAL rules from actionable reports.

Notes:

- This is post-processing only, so it does not speed up FixInsightCL.
- Filtering only applies when FixInsightCL writes to a file (`--fi-output`), because we need a report file to rewrite.
- Supported FixInsight report formats: text (default), `--fi-xml`, and `--fi-csv`.
- `analyze` keeps its analyzer reports unmodified so the static-analysis
  postprocessor can retain complete evidence. Its path masks and ignored
  FixInsight IDs become reporting policy instead of deleting raw findings.
- PAL filtering accepts canonical
  `PAL.<report-slug>.<section-slug>-<exact-identity>` keys from normalized
  JSONL. The identity suffix hashes the exact report and section text so
  punctuation, case, and long-name collisions cannot suppress a neighboring
  rule. Native aliases are accepted only when verified for the reported PAL
  version; PAL 9.21.3 currently verifies `WARN54`, `STWA6`, and `OPTI8`.
  Canonical validation includes zero-count XML sections, while verified aliases
  remain valid on zero-finding runs. Unknown or ambiguous entries fail with the
  unmatched values and available rules. PAL ignores never become `/X`, `/XF`,
  or `PALOFF`.
- DAK reads `DAK_FI_IGNORE_RULES` for FixInsight and
  `DAK_PAL_IGNORE_RULES` for PAL. `DAK_IGNORE_WARNING_IDS` remains a deprecated
  FixInsight-only alias and is merged with `DAK_FI_IGNORE_RULES`.

Example (CSV, filtered):

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Release --delphi 23.0 ^
  --out "C:\temp\analysis" --fi-formats csv --fixinsight true --pascal-analyzer false ^
  --exclude-path-masks "*\lib\*;*\thirdparty\*" ^
  --ignore-warning-ids "O802;O803"
```

## Pascal Analyzer (PALCMD) runner

To run Peganza Pascal Analyzer headlessly using our resolved project inputs:

- `analyze --pascal-analyzer true`
- optional overrides:
  - `--pa-path "...\palcmd.exe"` (or `palcmd32.exe`, or a folder containing it)
  - `--pa-output "C:\temp\pa"` (report root folder, passed as `/R=...`; it receives only the raw
    PAL XML reports, while the normalized findings stay in the report's `pascal-analyzer` folder)
  - `--pa-args "..."` (additive PALCMD options; DAK-owned options are rejected)
  - `--pa-timeout-sec N` (external process timeout in seconds)

DAK always owns `/F=X /Q /A+ /FA`, the automatic thread count, `/NAME`, and the
report root. It derives `/CD...` from the requested Delphi/platform unless an
explicit additive `/CD...` argument is supplied. PAL help is authoritative for
target support; PAL 9.21 supports Delphi 12 and Delphi 13 Win64, including the
BDS 37 to Delphi 13 mapping. Conflicting report, parse-scope, quiet, or thread
arguments fail before PAL starts.

Example:

```
bin\DelphiAIKit.exe analyze --project "C:\path\Project.dproj" --platform Win32 --config Release --delphi 23.0 ^
  --fixinsight false --pascal-analyzer true --pa-output "C:\temp\pa"
```

For focused unit analysis, prefer
`bin\DelphiAIKit.exe analyze-unit --unit Unit1.pas --project-context MyProject.dproj --delphi 23.0`
or its launcher `agentskills\dak-static-analysis\analyze-unit.bat Unit1.pas MyProject.dproj`
(with `DAK_DELPHI` set). Verify a report read-only with
`bin\DelphiAIKit.exe analyze-report --out <DAK_OUT> --verify`.
The project argument supplies search paths, defines, build configuration, and
compiler target. Omitting it keeps the legacy PAL.INI-based mode and is not
project-equivalent proof.

AI consumers should start with `<DAK_OUT>\summary.json`, then use
`triage-changed.md` or `triage.md` for detail. Schema 3 separates `raw`,
`actionable`, `ignored`, `external`, `advisory_metrics`, and `unknown`
projections. The normalized JSONL files and `static-analysis.full.sarif`
preserve complete evidence; normal triage and `static-analysis.sarif` contain
only ownership selected by `[AnalysisPolicy].GateOwnership`. External findings
are grouped in `external-summary.md`, while complexity and size metrics are
listed in `metrics.md`.

Metrics are advisory by default. A repository may opt selected canonical PAL
rules into the actionable gate explicitly:

```ini
[AnalysisPolicy]
GateOwnership=project;repository
GateMetrics=PAL.warnings.method-length-621eae6dfec836e8;PAL.warnings.parameter-count-75ab87a447776473
```

Unknown ownership remains visible and fails a gated run. `GateMetrics` changes
reporting only; it never adds PAL `/X` or `/XF` analysis exclusions.

For day-to-day work, use project-context unit analysis and review changed-file
findings. The default `GateOwnership=project;repository` already keeps
third-party findings out of actionable triage. It does not prevent the analyzers
from reading dependency source. Reading declarations and method contracts can
help check calls in our code; excluding a dependency can change caller-side
findings as well as remove vendor findings. Shared code we maintain belongs in
our review scope even when another project consumes it as a dependency.

When a vendor unit breaks FixInsight parsing, put an explicit exclusion in the
affected project's `dak.ini`, beside its `.dproj`:

```ini
[FixInsightCL]
; Replace these example filenames with the verified failing vendor units.
Ignore=Vendor.UnitA.pas;Vendor.UnitB.pas
```

DAK forwards this setting to FixInsight's `--ignore`; `--fi-ignore` provides a
CLI override. Entries use semicolons. Verify the exact filenames or masks with
the installed analyzer: the packed-include reproducer passed with its `.pas`
filename excluded, while excluding `packed.inc` did not clear the fatal error.
This removes FixInsight coverage for the excluded units. It is separate from
`[FixInsightIgnore].Warnings`, which filters reported rule IDs, and from
`[AnalysisPolicy].ThirdPartyRoots`, which classifies ownership.

Keep vendor exclusions local and documented. Do not infer that every path
outside the project, or every folder named `3rdParty`, is disposable analysis
input. For maintained projects, use broader analysis at batch/release gates;
for legacy applications, use focused advisory results and reserve full-project
analysis for a deliberate audit. Retest parser workarounds after analyzer
updates before removing them.

For one reviewed source location, put a reason-bearing marker on PAL's reported
line, for example
`end; //PALOFF reviewed false positive: callback intentionally has no action`.
With source-file input, installed PAL 9.21.3 applies this setting only in PAL
project mode. Add `/P` explicitly, for example
`--pa-args "/P /I=C:\path\PAL.INI"`, then rerun the analyzer and compare the raw
finding before and after the marker. `/P` creates or reuses a `.pap` beside the
analyzed source, so retain that file only when it is an intended PAL project
artifact; otherwise remove it after proof. The verified fixture reduced only
`Warnings.xml` / `Empty begin/end-blocks` from one finding to zero on PAL
9.21.3.0. We do not document code-qualified or multi-code marker forms until
each form has equivalent installed-version proof.

## Consistency inspection

Use `consistency --project <file.dproj> --config Debug --platform Win64 --delphi 23.0`
for a read-only JSON GUID inventory and source-backed DFM event-signature report.
The current implementation reports unsupported or unresolved inputs explicitly.
See [the contract and current limitations](docs/consistency.md); inherited DFM
merging and full slice-7 acceptance remain in progress.

## Output formats

- `ini` (default): easy to read and edit
- `xml`: structured output for tooling
- `bat`: runnable FixInsightCL command line

## Notes

- We read IDE configuration from the registry for the requested Delphi version (for example `23.0` for Delphi 12).
- We run `rsvars.bat` first so the IDE environment variables are available for macro expansion.
- If the IDE library path is not in the registry, we fall back to `EnvOptions.proj` from `BDSUSERDIR`.
  If `BDSUSERDIR` is missing, we derive it from `%APPDATA%\Embarcadero\BDS\<version>` and then `%USERPROFILE%\Documents\Embarcadero\Studio\<version>`.
- We resolve `FixInsightCL.exe` from `dak.ini` (`Path`), then `PATH`, then FixInsight registry keys (HKCU/HKLM, 32/64-bit).
- The native `build` runner runs `madExceptPatch.exe` only when a sibling `.mes` exists, the `.dpr`/`.dproj` base names match, `madExcept` is defined for the selected build config/platform, `.mes` `GeneralSettings` does not disable `LinkInCode` or `HandleExceptions`, and the platform is Win32 or Win64 (another platform is skipped, with a `--verbose` note).
- When resolving build output paths for Delphi projects, the native `build` runner honors `CfgDependentOn` `.optset` baselines before applying `.dproj` overrides, so JSON output and madExcept patching use the effective `DCC_ExeOutput` value.
- Sample inputs live in `tests\fixtures\` so we can quickly try the resolver.
- `scripts\fixinsight-selftest\fixinsight-run.bat` runs FixInsight against this repo and can generate raw reports under `scripts\fixinsight-selftest\Reports\`.
- `scripts\pascal-analyzer-selftest\pascal-analyzer-run.bat` runs Pascal Analyzer against this repo and writes reports under `scripts\pascal-analyzer-selftest\Reports\`.

## Tests

Automated DUnitX tests live in `tests\DelphiAIKit.Tests.dproj`.

```
bin\DelphiAIKit.exe build --project tests\DelphiAIKit.Tests.dproj --delphi 23.0 --config Debug --platform Win64 --ai
pwsh -NoProfile -File tests\run-dunitx.ps1
```

The default no-filter test run excludes long proprietary dogfood lanes tagged
`<proprietary-fixture-proof-category>`. Run those lanes explicitly when we need proprietary fixture proof.
For the proprietary fixture refactor rename dogfood, use a 15-minute timeout
budget. The current measured lane is about 7 minutes on our local runner:

```
tests\bin\Debug\DelphiAIKit.Tests.exe --hidebanner --consolemode:quiet -r:Test.Refactor.ProprietaryRename -i:<proprietary-fixture-proof-category>
```

Test commands and prerequisites live in `tests\README.md`. `tests\run.bat` forwards to the same DUnitX runner using PowerShell 7. `build-and-run-tests.bat` first builds isolated Win64 Debug candidates through the known-good native host, then runs the suite. Logs stay under `tests\.dak\DelphiAIKit.Tests\test-runs`.

### Local confidentiality guard

Enable the tracked hooks once per checkout:

```
git config core.hooksPath .githooks
```

The pre-commit and pre-push hooks reject content under
`tests/fixtures/test-projects/`; only its marker `.gitignore` may be tracked.
Private test corpora must remain outside this repository.
