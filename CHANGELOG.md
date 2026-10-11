# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Fixed
- Symbol Map indexing keeps routine-local types, consts, vars and local enum values out of the top-level declaration inventory and the `index-unit` symbol counts, using the semantic model's routine scope facts.
- Refactor transactions report `transaction.busy` only when another process holds the project lock; any other failure to open the lock file now reports `transaction.lock-failed` with the OS error code and message.
- Refactor transactions now create their lock directory and read their journals beyond the Windows path limit, so a project nested deeper than 260 characters can reach lock, journal, staging and recovery (the build verification still needs a path within the limit).
- `analyze` and `analyze-unit` output cleanup now reports a refused cleanup (an output folder that is or contains a reparse point such as a junction) as a handled error on stderr with exit code 4, instead of an unhandled exception that exits 207 under `MAXLOGIC_MADEXCEPT_AI=1`. Nothing is deleted through the link.
- Pascal Analyzer summary counts, status details and normalized findings now read retained XML beyond the Windows path limit while keeping report paths and XML encoding intact.
- `DelphiAIKit.exe` can run unattended with `MAXLOGIC_MADEXCEPT_AI=1`: an uncaught madExcept exception writes a fresh `bugreport.txt` beside the executable and exits with code 207 without an exception or please-wait dialog.
- `dfm-check` reports MSBuild and validator timeouts by phase and keeps their diagnostic logs, instead of reporting a failure to start.
- `remove-with` now resolves nested indexed default-property and pointer selectors through an enclosing `with` using the bound member type's declaring unit; unknown or ambiguous provenance refuses the rewrite.
- Pascal Analyzer findings that use a project's dotted report name now resolve to its recorded main DPR when Modules.xml uniquely identifies that source under a different Pascal program name; conflicting metadata remains unresolved.
- Analysis baseline comparison rejects non-object `top_warning_sections` rows with a controlled error, without changing the accepted baseline or history.
- `analyze-report --verify` rejects non-object retained FixInsight and Pascal Analyzer finding rows with a controlled error while preserving the report files.
- Symbol Map cache databases now open and reuse through extended-length Windows paths when the central or project cache lies beyond the classic path limit; reported paths and cache identity stay unchanged.
- Symbol Map search and describe now mark declarations from unverified semantic scope as `scope-unverified`, including cached fallback members; AST-backed declarations retain their normal confidence.
- `find-usages`, `rename`, and Symbol Map position queries resolve `--file` paths passed with forward or mixed separators, including paths relative to the caller's current directory.
- `remove-with` now refuses plans and apply for a `with` in an unverified unit or include-expanded source, with a named reason instead of an unsafe edit or range error. A project-wide plan still includes verified units and reports the include refusal as a warning.
- `rename` no longer plans edits at unrelated positions for names used or declared in an `{$I}` include file (for example inside an inactive `{$IFDEF}` branch, in another routine, or on the `{$I}` directive). Include occurrences are listed under `unresolved` with the include file, line and column (an include expanded in the middle of a line at its directive, reason `include-position-unknown`), the plan is `incomplete`, and `--apply` changes no file. `find-usages` reports include positions, and a rename plan whose edit position does not hold the old name is `blocked`.
- `dead-code` no longer reports a routine used only from a program main block or from another unit's `initialization` or `finalization` block as `definitely-unused`, so `--apply` keeps it. Overloads called without provable binding and short-form implementation bodies are kept as well. A routine declared in an include file is reported at that file and blocked (`declared-in-include`).
- The symbol-map cache key includes the DelphiSemantics unit-model parser version, so a change to extracted references no longer reuses stale symbol-map rows.
- `lsp hover` now returns DelphiLSP's hover text instead of an empty result, and `lsp definition` resolves positions that previously returned no location. The generated DelphiLSP settings name the platform compiler DLL (`dllname`, for example `dcc64290.dll`), found beside the resolved `DelphiLSP.exe`. When the DLL cannot be resolved (a platform other than Win32 or Win64, or no single matching DLL), the query still runs without `dllname`, as before, and reports a "DelphiLSP compiler DLL not resolved (...)" warning; hover may then return no content.
- Read-only LSP queries isolate the vendor server in an owned Windows process job and explicitly report controlled cleanup, avoiding reproduced DelphiLSP shutdown crashes and hangs. Responses are checked for matching JSON-RPC IDs; project-settings acceptance remains explicitly unverified. See [the vendor defect record](issues/active/2026-09-29-delphilsp-shutdown.md).
- An LSP query no longer hangs when DelphiLSP stops reading its input. Sending a request or notification is bounded by the same deadline as the response (`DAK_LSP_REQUEST_TIMEOUT_MS`, default 30 s); on timeout the query fails with a "timed out ... while writing" error and the owned server process tree is stopped.
- Unattended test subprocesses and the Pascal Analyzer help probe no longer allocate or inherit console windows; captured output and exit codes are preserved.
- DAK no longer hangs on a Windows "Unsupported 16-bit application" message box when a configured tool such as `DelphiLSP.exe`, MSBuild, FixInsightCL or PALCMD is not a valid executable. DAK sets its process error mode at startup, so DAK and every tool it starts fail with an error instead of waiting on an OS message box, whatever program launched DAK. DelphiLSP and the tools that `build` and the analyzers start by path are also checked for a PE header first, and fail at once with `<path> is not a valid Windows executable`. Side effect: Windows Error Reporting (crash dialogs, WER reports and LocalDumps) is suppressed for DAK and the tools it starts; exit codes are unchanged and madExcept still reports crashes inside DAK.
- `build` no longer fails with `MSB1006` when a value forwarded from the IDE's `environment.proj` contains a comma. MSBuild property values with commas, embedded quotes, or a space plus a trailing backslash (including `--test-output-dir`) are now quoted so that MSBuild receives them unchanged. `--verbose` prints the MSBuild executable and the generated arguments with `environment.proj` values redacted, and an `MSB1006` result names the rejected property without showing its value.
- `dfm-check` and `build --dfmcheck` quote the generated MSBuild property values with the same rule as `build`, so a project directory that contains a space no longer fails with `MSB1008`: the generated output directories end in `\`, and that backslash used to swallow the closing quote and the following arguments. Values forwarded from `environment.proj` are XML-entity-decoded, and a value with a line break is skipped and named in `--verbose` instead of being passed to MSBuild.
- A successful Linux64 `build` no longer reports "resolved output file does not exist: ….exe". The output file is named by the platform's rules from the imported compiler targets (a Linux64 program has no extension; libraries are `lib<name>.so`, packages `bpl<name>.so`), and a platform DAK has no rules for is reported with the reason and an empty `output` instead of a guessed path. `--verbose` prints the resolved name and where it came from.
- `build` reports a package in its `DCC_BplOutput` directory (or `DelphiDLLOutputPath`) instead of the executable directory. A `--test-output-dir` value with invalid characters or one that depends on the current drive now fails with `Test output directory is not usable` before the build starts, instead of an unhandled error.
- `build` reports the file the compiler writes for libraries, packages and programs. The compiler takes the name from `{$LIBPREFIX}`, `{$LIBSUFFIX}`, `{$LIBVERSION}` and `{$E}` (and the `SO*` aliases) in the main `.dpr`/`.dpk` and ignores the project's `DllPrefix`, `DllSuffix`, `DllVersion` and `DCC_DependencyCheckOutputName`, so DAK now reads the source (including `{$I}` files next to it) instead of those properties; a `{$LIBSUFFIX AUTO}` package (the default of new Delphi 12 packages) is named with the installed RTL package version, for example `MyPkg290.bpl` and `bplMyPkg290.so`. A source DAK cannot read, a wildcard include, or a directive form it does not evaluate leaves the name unresolved with the reason. An include DAK cannot find (such as `Jedi.inc` on the search path) is noted (`naming include <name> not read; name assumes no directives in it`) and the name assumes no directive in it; the usual existence check then decides between `ok` and `output_missing`. An Android package is reported as the static `lib<name>.a` in the `.dcp` folder.
- `build` honours the project's `OutputExt` (the IDE's "Target file extension") when it names a program or library, as the compiler does (`{$E}` in the source still wins; packages ignore it), and reads the naming directives in source order: directives in comments or string literals are ignored, several on one line all apply, and an included file's directives apply where the `{$I}` stands.
- `build` runs `madExceptPatch` only for Win32 and Win64 builds. For another platform the patch is skipped, and `--verbose` says so, instead of handing an ELF or `.so` file to the Windows patcher.
- `build` no longer fails with an unhandled error when the evaluated `DCC_ExeOutput` is not a usable path; the output name is reported as unresolved with that reason. A legacy `DCC_DependencyCheckOutputName` such as `App.exe` no longer overrides the platform's own naming on Linux64 and Android, where the compiler ignores it. `--test-output-dir` also redirects `DCC_HppOutput` (to `<path>\dcu`) and `DCC_BpiOutput` (to `<path>`).
- Concurrent runs of `rename --apply`, `dead-code --apply` and `dfm-check` on the same project no longer interfere. `rename` and `dead-code` put each run's backups, manifest and verification logs in its own `.dak\<ProjectName>\rename\<RunId>` or `dead-code\<RunId>` folder (8-character hex id) instead of a millisecond timestamp that two runs could share; manifests of older runs still point to their backups. `dfm-check` no longer deletes the workspace of another run that is still in progress: each run keeps `runs\<RunId>\run.lock` open while it runs, and a new run removes only run folders whose lock nobody holds, including those left by a crashed run. `dfm-check` also refuses a too-deep project before any work when the copied `DfmCheckRuntimeGuard.pas` (one- or two-character project names) or the DCU of a unit listed in the project would pass the Windows path limit, and the refusal shows the run folder as `<run-id>`.

### Added
- `remove-with` can prove that a name is not a member of the implicit `System.TObject` root with a native compiler check, so selectors that previously refused on an unverified inherited root member can be rewritten. DAK reads the project's effective Win32/Win64 compiler context from MSBuild, compiles a small isolated check with the selected Delphi compiler using only the SDK paths, and accepts the proof only when the freshly run check reports its expected result. The plan JSON reports `nativeRootProof`, `nativeRootProofSchema` and `nativeRootProofFingerprint`, or `nativeRootProofDiagnostic` when the proof is unavailable; the existing refusal is kept in that case. `--apply` re-checks the compiler, `System`/`SysInit` and project inputs under the project lock before the preflight build and before editing, and refuses with `native-request-inputs-changed` when they changed, `native-root-proof-guard-missing` when a proof-dependent plan lacks its guard, or `native-root-proof-finalization-failed`; no file is changed.
- `build --keep-logs` keeps the MSBuild `stdout.log` and `stderr.log` of a Delphi build in a unique `run-<guid>` folder under `<project dir>\.dak\<ProjectName>\build`, and `--log-dir "<path>"` (relative to the project directory, or absolute) chooses another root. The folder is printed and reported as `kept_logs_dir` in `--json`; a folder that cannot be created stops the build before it starts, and logs that cannot be copied are reported as `kept_logs_error` with a nonzero exit code alongside the build result. This replaces the retired `build-delphi` wrapper's `-keep-logs` and `-log-dir`; `DAK_BUILD_DIAGNOSTICS_DIR` is unchanged.
- `uses` can report source-backed explicit import candidates for an unbound identifier, retaining ambiguous candidates and incomplete evidence without selecting an import or publishing an edit plan.
- `signature` compares an explicitly selected declaration and implementation, including parameter and result facts. Alignment suggestions retain native baseline-build diagnostics and remain non-applicable when the compiler fails. Optional `--plan-out` saves a new artifact only after a successful baseline and unchanged-context check; `refactor-apply` independently replans its intent and refuses stale context. Existing output files are preserved, and publication failures return a blocked result.
- Read-only `consistency` reports interface GUIDs and source-backed DFM event signatures as versioned JSON. Missing or unsupported resource/ancestry inputs return incomplete results; supported inherited text DFMs retain assignment locations, overrides and nil clears, while broader ancestry coverage remains in progress. Omitted calling conventions compare as `register`; explicit differences remain mismatches. Supported source-defined type aliases resolve in their declaring scope, preserving strong type identity and underlying event declaration locations.
- Native `analyze-doctor` previews effective settings, sources, environment values, policy and output paths in readable text or JSON without creating analysis state. Optional checks report FixInsight discovery, compiler configuration and PAL capabilities; PAL help uses a 15-second default timeout and validates the requested Delphi target.
- Native `analyze-workspace` inspects workspace selection and Git, SVN or unmanaged source provenance in human-readable or JSON form without running analyzers or changing reports.
- Routine FixInsight analysis excludes verified Smart Setup FlexCel source trees while preserving compiler context and recording the effective input masks. Isolated vendor diagnostics can disable this default with `[FixInsightCL].ExcludeFlexCel=false`.
- Added VCS-neutral static-analysis workspaces with deterministic `auto`, `git`, `svn`, `project`, fixed-path, and `--workspace-root` selection.
- Added PAL 9.21 help-aware Delphi 13 support, including BDS 37 Win64 target mapping and doctor reporting for the resolved PAL executable, version, architecture, help availability, and Delphi 12/13 capabilities.
- Added project-context unit analysis and compact `summary.json`, JSONL, SARIF, delta, trend, and triage artifacts for AI-assisted static-analysis review.
- Added deterministic PAL `Modules.xml` path resolution plus explicit validated `--pa-exclude-search-folders` (`/X`) and `--pa-exclude-files` (`/XF`) settings for CLI, `dak.ini`, and static-analysis wrappers.
- Added schema-3 raw/actionable static-analysis projections, full-evidence SARIF, compact external and advisory-metric reports, explicit metric opt-in, and fail-closed ownership verification.
- Added collision-safe canonical PAL rule identities, version-verified native aliases, PAL-specific actionable-report filtering, per-value filter provenance, and raw/ignored rule evidence across summary, baseline, delta, and SARIF artifacts.

### Changed
- `rename` and `find-usages` now resolve member references across units: typed receivers (`a.Member`), inherited members (`Self.Member` and plain names in descendants) and `with` selectors. Same-name occurrences that cannot be proven either way are listed in `unresolved[]` with a `reason`, counted in `unresolvedCount`, and the result is `incomplete` with a non-zero exit. `rename --apply` refuses while any occurrence is listed.
- DAK's per-run working folders under `.dak\<ProjectName>\` use shorter names, so projects in deeper directories stay within the Windows path limit: `remove-with\<RunId>`, `dfm-check\runs\<RunId>`, `refactor-transactions\<id>` and `signature\<id>` use an 8-character hex id instead of a 32- to 38-character GUID, and the `remove-with` verification logs move from `verification-preflight` and `verification-apply` to `vpre` and `vapp`. Existing runs keep their paths, and their manifests and journals still point to their backups and logs. `dfm-check` on a project too deep for its generated harness stops before any work with `dfm-check path too long`, naming the path, its length and the 259-character limit. The symbol-map cache, the kept build logs (`build\run-<guid>`) and other persistent locations are unchanged.
- `build --test-output-dir "<path>"` now also moves unit output: `.dcu` and `.o`/`.obj` files go to `<path>\dcu` instead of the project's own unit folder. Executables, libraries and packages still go directly into `<path>`. The retired wrapper passed `DCC_UnitOutputDirectory`, which the compiler ignores, so DCUs used to land in the project's normal unit folder.
- Static analysis no longer needs Python. Project and unit analysis, report finalization, baseline and gate policy, triage, SARIF and verification run inside `DelphiAIKit.exe` (`analyze`, `analyze-unit`, `analyze-doctor`, `analyze-report --verify`), which also reads the analysis environment variables itself. The skill's `analyze.py`, `analyze-unit.py`, `doctor.py`, `postprocess.py` and `workspace.py` are removed; its `.bat` and `.sh` launchers keep their arguments and only find `DelphiAIKit.exe`, forward, and convert WSL paths.
- The launchers look for `DelphiAIKit.exe` in `DAK_EXE`, then `PATH`, then the `bin` folder of the repository that holds the skill. They no longer search the current directory or the analyzed workspace, and they no longer assume Delphi 23.0: set `DAK_DELPHI` or pass `--delphi`.
- `lsp references` now explains that the installed Delphi 12 and 13 language servers do not provide references, and points to `find-usages`, instead of reporting an unsupported operation.
- `analyze-report` verification and replay of large reports are faster. Count projections read each finding once, and SARIF output converts line endings in a single pass. On the 10,000-finding verification fixture the median fell by about a third, with byte-identical output.
- `--pa-output` and `[PascalAnalyzer].Output` now relocate only Pascal Analyzer's raw XML reports. `pal-findings.jsonl`, `pal-findings.md` and `pal-hotspots.md` always go to the report's `pascal-analyzer` folder, so a relocated run finalizes instead of failing with exit 4 on a count mismatch.
- Analysis provenance is captured before the run writes its output, so a committed workspace is no longer reported dirty because of the run's own `run.log`.
- Source-cache validation preserves precise Windows timestamps with one ordinary-file metadata query. Two isolated Win64 certification batches meet the remove-with and rename budgets; see `docs/remove-with-performance.md`.
- Semantic refactoring reuses coordinate indexes, builds project snapshot lookups once on a cold cache, and indexes binding candidates per operation. The September 7 maxTdb Win64 Release baseline measured medians of 14.594 seconds for cold remove-with, 8.960 seconds warm, and 6.620 seconds for cold rename; see `docs/remove-with-performance.md`.
- PAL analysis now stages reports under a unique short path when the requested output would exceed PAL's Windows path budget, then publishes the retained reports to the requested directory. Failed staging and publication identify retained evidence.
- Legacy PAL argument errors now identify the effective INI or CLI/environment source, list all conflicting DAK-owned switches, and explain how to migrate exclusions. The static-analysis doctor checks the same configuration.
- Static-analysis ownership, source identity, change triage, and provenance now use the resolved workspace and report truthful Git, SVN, or unmanaged capabilities instead of requiring Git.
- The static-analysis skill now treats large legacy applications as an advisory, delta-oriented workflow by default: inherited findings and analyzer parser limitations no longer become routine feature gates, while full-project analysis remains available for explicit audits and dedicated maintenance work.
- The static-analysis skill now distinguishes actionable, raw, ignored, external, advisory-metric, and unknown findings; documents only implemented analyzer-specific filters and explicit coverage exclusions; and contract-tests every named option and artifact.
- PAL reporting now uses consistent actionable totals for strong warnings, warnings, and optimizations across all compact artifacts; raw `Exception.xml` call-tree rows no longer contribute to findings.
- Required report post-processing failures now fail the analysis run instead of leaving a partial success result.
- External tools that DAK starts (MSBuild, FixInsight, Pascal Analyzer, git) now run in an owned Windows job object and stop when DAK stops, including when it is interrupted. FixInsight and Pascal Analyzer run in a separate hidden console.

### Removed
- Breaking: `build-delphi.bat` and `build-delphi.sh` are gone. Call `DelphiAIKit.exe build --project <project.dproj> --delphi 23.0 --platform <Win32|Win64> --config <Debug|Release> --ai` instead. Option names use the native form (`--config`, `--platform`, `--delphi`, `--target`, `--rebuild`, `--max-findings`, `--build-timeout-sec`, `--test-output-dir`, `--ignore-warnings`, `--ignore-hints`, `--exclude-path-masks`, `--show-warnings`, `--show-hints`, `--json`, `--ai`). The wrapper's `-log-dir` and `-keep-logs` are now `--log-dir` and `--keep-logs`; its `-no-brand` and `-show-warnings-on-success` have no direct equivalent: pass `--show-warnings --show-hints`. WSL callers run the executable directly with `/mnt/<drive>/...` project paths, without the `build-delphi.sh` launcher. There is no default Delphi version: pass `--delphi`, or set `DAK_DELPHI` or `[Build] DelphiVersion`. Exit codes follow DAK's own scheme (for example 6 for a missing project or other tool failure) instead of the wrapper's 1 and 2; treat any nonzero code as failure.

### Fixed
- The build wrapper resolves `$(MSBuildProjectDirectory)` in executable output paths and builds projects in directories containing spaces. Native MSBuild failures now produce a nonzero exit and error status even when they occur before file logging starts.
- `remove-with --mode apply` works when its verification and backup workspace inside the project's `.dak` folder passes the classic 260-character path limit; previously the preflight build crashed with an unhandled `EInOutError` and backups could not be written.
- `build` and `build-delphi.bat` report the executable the compiler emits, named after the main source file, when the program identifier differs (for example `DelphiAIKit.Tests.exe`). A successful build whose resolved output does not exist reports `output_missing` with `output_stale=true` instead of a fresh result.
- Report verification with a baseline no longer leaks memory.
- Builds started outside the repository root retain compiler source snippets and semantic hints while keeping diagnostic paths repository-relative.
- UTF-8 BOM settings files now preserve the selected workspace boundary. The selector uses the same decoder as other settings while retaining case-insensitive key matching.
- Routine header references keep their own lexical scope at adjacent and same-line routine boundaries.
- Indented type aliases remain visible to snapshot-backed find-usages and rename.
- Windows process arguments retain embedded quotes and trailing backslashes, including quoted PAL configuration paths passed through Python subprocess arguments.
- Semantic declaration indexing excludes assignments, preserves globals declared after class methods, and includes packed-record fields and multiline field names. Existing cached models are rebuilt.
- Static analysis includes checked maintained libraries regardless of finding-path format, preserves registered nested vendor boundaries, and rejects ownership conflicts and incompatible ownership baselines.
- Remove-with preserves visible imported procedure calls and keeps complete selector expressions, including commas inside indexes, strings and comments. Child rewrites preserve member lookup under retained parent WITH statements; older cached selector facts are rebuilt.
- Semantic indexing preserves multiline routine signatures, parameter types and source positions. Remove-with can resolve those routines and their parameters; comments and default strings no longer create false parameter type references, and older cached models are rebuilt.
- Remove-with captures source-visible pointer casts once at statement entry, preserving guards and loops. Same-spelling routines and receiver members retain precedence; ambiguous or invisible record targets remain excluded.
- Remove-with preserves compiler type casts inside statement bodies, including writable Double and Pointer casts, while retaining user declarations and receiver-member precedence. Older cached planning facts are rebuilt.
- Remove-with keeps nested and conditional body boundaries intact, preserves generated capture wrappers, and retains outer ELSE branches across whitespace and comments.
- Remove-with captures unambiguous global record-array fields at each controlled statement entry, preserving index mutation and skipped guards. Getter and shadowed receivers remain excluded.
- Remove-with now keeps reference coordinates correct in LF source files, including qualified pointer fields; cached models with the old coordinates are rebuilt.
- Remove-with preserves receiver-member precedence across inline declarations, including initializer expressions and loop bodies, without qualifying declaration identifiers.
- Remove-with now qualifies indexed fields whose name matches the receiver, while preserving explicit qualifiers and anonymous nested receivers under skipped parents.
- Remove-with preserves receiver-field precedence over outer locals in indexed arguments, while retaining lexical indexes and explicit qualifiers, including whitespace after a dot.
- Remove-with captures following nested forward declarations are now declared in the enclosing routine; older cached planning facts are rebuilt automatically.
- Analyzer cleanup preserves shared project caches, retained evidence, baselines and history, and rejects linked output trees before deleting generated reports.
- Remove-with replacements now keep pointer-body indentation when a receiver capture precedes the body, including indexed pointers and controlled statements.
- Skipped remove-with parents now discard rolled-back child temporary metadata from their plans and rewrite recipes, while independently planned children keep their valid captures.
- Semantic indexing now extracts main-program references with exact coordinates and no routine owner, preserving partial-cache resolution and avoiding coordinate-repair work.
- Semantic variable types now exclude initializers while preserving type expressions, source coordinates and type-reference boundaries; older cached type facts are invalidated.
- Remove-with now captures pointer and dependent receivers at statement entry, preserves nested receiver types and evaluation order, and retains literal/comment text in selectors. Unsupported repeated selectors remain unchanged.
- Typed-constant mutability now follows active compiler directives in source order, including inline switches and includes; directive examples in comments and strings no longer change semantic results.
- Shared symbol queries now retain read-only typed constants across cold and warm caches while mutable-global reports continue to exclude them.
- Semantic indexing and rename now recognize declarations on the same line as `const` or `var`, preserve identifier positions, and invalidate older parser cache entries.
- Remove-with now handles resolved by-value record parameters in procedures while preserving copy semantics and receiver-field precedence.
- PAL report reprocessing now preserves source identity and ownership when external and repository files share a basename or a relative path also exists under the project directory.
- Fixed PAL include-file path resolution from nested `Modules.xml` entries, preserving ambiguous paths and class-qualified finding locations.
- Fixed nondeterministic mutability metadata on rejected semantic declarations by initializing declaration records before extraction.
- The `build-delphi.bat` wrapper now counts compiler warnings and hints correctly in its success and JSON summaries, including diagnostics with relative source paths. Warning-code and path filters continue to apply.
- DFM validation now passes sanitized effective compiler defines as an immutable MSBuild property, preventing imported option sets from restoring the exact `madExcept` symbol while preserving all other defines.
- Command output now treats a closed stdout pipe as normal downstream termination, preventing `deps --output -` and other shared output paths from raising madExcept reports when a consumer exits early; requested file output still completes.
- `global-vars` now requires AST-verified declaration roles and lexical ownership, excluding locals, `Result`, assignments, fields, and properties while preserving class-variable identity, routine provenance, cache invalidation, and decision-grade diagnostics.
- PAL normalization now preserves each location's full analyzer `<info>` message when present, while retaining the previous fallback for reports without per-location detail.

## [1.2.1] - 2026-07-11

### Changed
- DFM validation now removes the `madExcept` define only from its generated `.dak` project clone, leaves all input sources untouched, and fails generated compilation with actionable `{$IFNDEF DFMCheck}` guidance when application units still link madExcept-related code unconditionally.
- Updated repo-local DAK skills and README command guidance to match the current bounded DFM-check timeout, guarded `dead-code --apply`, LSP capability surface, and typed build overlays; canonical skills now pass current Codex skill validation.

### Fixed
- Replaced Unicode-unsafe character set expressions in DAK source units with `CharInSet`, eliminating compiler `W1050` warnings from repository-owned `src` code while leaving vendored/external units unchanged.
- DFM validation now intercepts standard madExcept startup-unit linkage during generated project compilation, avoiding the previous Win32 exit 217 and Win64 access violation paths and returning a source-preparation error instead.

## [1.2.0] - 2026-07-01

### Added
- Added typed `build --define` and `--unit-search-path` overlays for Delphi/MSBuild builds, preserving project compiler defines and unit search paths while rejecting the switches for WebCore builds. (T-202)

## [1.1.0] - 2026-06-25

### Added
- Added guarded `dead-code --apply` mode with explicit profile approval, project-scoped
  backups/manifests, post-apply build verification, no-op handling, and rollback
  on verification failure.
- Added isolated `build-delphi.bat` log directories with optional `-log-dir`, so parallel wrapper builds no longer share root build/error log filenames.
- Added bounded FixInsightCL and Pascal Analyzer process waits with `--fi-timeout-sec`, `--pa-timeout-sec`, and matching `dak.ini` `TimeoutSec` defaults.
- Added additive `remove-with` planner metrics for semantic receiver-member
  resolution, lexical resolution, semantic reference-cache hits/misses, and
  legacy resolver-report receiver/use/enrichment timing.
- Added additive `remove-with` planner subphase metrics for semantic inventory,
  with-binding, final DTO planning, and resolver-report fallback/projection
  timings and counts.
- Added explicit `remove-with` covered-statement accounting to JSON and text
  reports, including plan/apply parity checks for the proprietary fixture.
- Added proprietary fixture semantic rename dogfood coverage that clones the fixture, applies
  real project-scoped renames, verifies `.dak` backups/manifests, compiles the
  renamed clone, and byte-checks that the original fixture stays unchanged.
- Added `find-usages` and `rename` project-scoped refactoring commands backed by
  DelphiSemantics, including JSON/text output, dry-run rename by default, and
  apply mode with per-file backups plus rollback on edit failure.
- Added a report-only `dead-code` command backed by DelphiSemantics, with
  JSON/text output, explicit `audit`/`conservative`/`legacy-static` profiles, and
  non-mutating safety semantics.
- Added `remove-with --semantic-cache "<sqlite-path>"` to persist DelphiSemantics
  unit-model parsing across runs, with verbose per-unit cache hit/miss/invalidation
  telemetry.
- Added an optional proprietary fixture `remove-with` performance and telemetry gate that clones the proprietary fixture, runs plan mode with JSON `--output`, asserts current resolution/timing baselines, and verifies original sources remain unchanged. (T-176)
- Added `remove-with` migration telemetry for local-model hits, Symbol Map hits/misses, intrinsic allowlist fallbacks, true unknowns, planned/skipped counts, and planner elapsed time, with a current proprietary fixture temp-clone baseline. (T-200)
- Added Symbol Map-backed `remove-with` recognition for compiler/RTL intrinsics and a stale-intrinsic cache repair check, so seeded compiler symbols such as `Abs`, `Sqr`, `Succ`, and `Assert` resolve without expanding the legacy allowlist. (T-178)
- Added an internal `remove-with` Symbol Map lookup bridge that prepares a project Symbol Map session once per command, exposes compiler/profile/project lookup metadata in resolver JSON, and keeps current rewrite decisions unchanged. (T-199)
- Documented Symbol Map CLI usage, central and project cache behavior, cleanup/invalidation, cache-root overrides, and relationship to LSP and `remove-with`. (T-197)
- Added a direct Symbol Map resolver API for definition lookups by name or source position with cache/compiler-profile status reporting. (T-196)
- Added Symbol Map token-reference indexing and `find-references` query output with explicit non-semantic `token-name-match` confidence. (T-195)
- Added Symbol Map `find-definition`, `search-symbols`, and `describe-symbol` query results over project-indexed units, source-available profile units, and synthetic compiler intrinsics. (T-194)
- Added Symbol Map RTL source indexing into compiler profiles, including root-aware profile cache identity, non-fatal missing-root diagnostics, and `rtlSource` hit/miss reporting. (T-193)
- Added Symbol Map compiler profile seeding with reusable synthetic Delphi intrinsic rows and JSON/text compiler-profile reporting. (T-192)
- Added Symbol Map central unit cache reuse with content/context unit keys, project-level `DCCReference` indexing, cache hit/miss reporting, and normalized define handling across equivalent project contexts. (T-191)
- Added Symbol Map member extraction for class, record, interface, and helper fields, methods, properties, indexed/default property metadata, source locations, JSON output, and central cache member rows. (T-190)
- Added Symbol Map top-level declaration extraction for types, aliases, enum values, constants, globals, routines, source locations, signatures, and JSON symbol output. (T-189)
- Added a focused `remove-with` semantic binder proof suite covering receiver precedence, outer scopes, helpers, inheritance, interfaces, overloads, missing receiver members, and unknown routine-call safety. (T-174)
- Added targeted `symbol-map index --unit` source-unit extraction with UTF-8/ANSI fallback loading, unit-name detection, interface/implementation uses reporting, and source fixture coverage. (T-188)
- Added Symbol Map SQLite cache initialization for central and project caches, including schema version reporting, created/reused flags, unsupported-version protection, and process-level central-cache serialization. (T-187)
- Added Symbol Map project-context and cache-root reporting, including `.dak/<ProjectName>/symbol-map` project roots, central cache-root overrides, and compiler-context fields in `symbol-map stats` JSON. (T-186)
- Added the initial `symbol-map` CLI shell with `index`, `find-definition`, `find-references`, `search-symbols`, `describe-symbol`, and `stats` operations, command help, validation, and stable JSON/text shell output. (T-185)
- Added dictionary-backed `remove-with` semantic indexes for units, types, members, routines, scoped symbols, helpers, aliases, pointer aliases, array aliases, inheritance, and default/indexed properties, including coverage for pointer-alias syntax and non-array generic aliases. (T-173)
- Added an AST-backed `remove-with` unit model extractor that captures uses, types, members, routines, scoped symbols, `with` statements, and identifier references from the shared project model. (T-172)
- Added verbose `remove-with` progress diagnostics for discovery, symbol inventory, resolver, planner, and apply stages, including deeper symbol-inventory timing when `--verbose true` is used.
- Added optional `remove-with` smoke coverage for the proprietary local `tests/fixtures/test-projects/<proprietary-fixture>` fixture, running only when the folder exists and scanning a temp clone so original sources stay untouched.
- Added transactional apply/build proof coverage across the `remove-with` hardening fixtures, including skipped-only byte preservation and explicit skipped-reason assertions. (T-169)
- Added a multi-unit `remove-with` corpus smoke fixture that plan-scans representative messy Delphi syntax and asserts stable JSON counts plus unchanged sources. (T-168)
- Added DelphiAIKit CLI to resolve FixInsight params from .dproj/.optset. (T-001)
- Added a `--verbose` flag to emit detailed diagnostics for troubleshooting. (T-001)
- Added `--rsvars` to override the `rsvars.bat` location for IDE environment setup. (T-001)
- Added `--envoptions` to override the `EnvOptions.proj` path when the default is not available. (T-001)
- Added `analyze` with `--project`/`--unit` to run FixInsight/PAL with stable `_analysis` output and summaries. (T-027, T-028)
- Added build output controls: `--show-warnings`, `--show-hints`, `--ignore-warnings`, `--ignore-hints`, `--ai`. (T-058, T-060, T-061)
- Added build options: `--target/--rebuild`, `--json`, `--max-findings`, `--build-timeout-sec`, and `--test-output-dir`. (T-062, T-063, T-064, T-065, T-066)
- Added native TMS WEB Core builds to `DelphiAIKit.exe build`, including `--builder auto|delphi|webcore`, `--webcore-compiler`, `--pwa` / `--no-pwa`, compiler-path discovery from cascading config/env/PATH, and compatibility execution of `tools\patch-index-debug.ps1`. (T-092)
- Added `deps` for project dependency topology analysis, including deterministic JSON output, text summaries, focused unit views, cycle reporting over resolved project units, and default artifact copies under sibling `.dak/<ProjectName>/deps/`. (T-101, T-102)

### Changed
- `remove-with` plan reports now preserve DelphiSemantics' full statement
  ledger internally while public planned/apply counts include only statements
  with concrete source edits.
- Default no-filter DUnitX runs now exclude long proprietary `<proprietary-fixture-proof-category>`
  dogfood lanes; run those lanes explicitly with category include filters when
  proprietary fixture proof is needed.
- `remove-with` now builds its normal typed plan through the DelphiSemantics
  session-backed snapshot API instead of rebuilding a temporary snapshot from
  compatibility facts.
- `remove-with` now consumes DelphiSemantics explicit fact-build results and
  reports structured diagnostics instead of inferring API failure from an empty
  context fingerprint.
- SymbolMap semantic projection merge now uses indexed keys and pre-sized
  projection arrays during cache-miss and force-refresh construction, avoiding
  per-row growth and linear duplicate scans.
- `symbol-map index` now reports `parseAvoided` / `parse-avoided` for unit
  cache hits that reuse an existing central projection without parsing, and
  accepts `--refresh force` to bypass the cache-hit fast path.
- Project-analysis commands now make their semantic context quality explicit:
  degraded-tolerant commands report context mode/note in command output, while
  strict commands fail closed when Delphi IDE context cannot be resolved.
- rsvars loading now returns an explicit environment snapshot for child tools and
  semantic evaluators instead of mutating the long-lived DelphiAIKit process.
- DFMCheck generated project rewrites now use structured MSBuild XML handling,
  preserving quoted import attributes, entity-encoded conditions, Unicode paths,
  and paths containing spaces.
- LSP JSON-RPC requests now fail with a bounded timeout instead of blocking
  indefinitely when DelphiLSP accepts input but never responds.
- DFMCheck build and validator subprocesses now fail with a bounded timeout
  instead of waiting indefinitely; timeout runs keep diagnostics under the
  project `.dak` run directory.
- DFMCheck all-mode cache writes now use a cache-path lock and atomic replace
  publish path so concurrent runs cannot corrupt the cache file.
- Analyze runs now keep FixInsight and Pascal Analyzer stdout/stderr in
  per-child log files while `run.log` indexes those logs and report artifacts.
- Added `deps --top` plus hotspot-ranked text output sections for cycle components, cycle units, and cycle edges, with equal-rank `implementation` edges prioritized ahead of `interface` edges. (T-106)
- Added optional build-error enrichment that appends best-effort `lsp` semantic hints to AI build failures when DAK can resolve a meaningful token or enclosing symbol, while leaving the original compiler error untouched when LSP returns nothing useful. (T-128, T-129, T-130, T-132, T-133, T-134)
- Added one-shot `lsp` execution for `definition`/`references`/`hover`/`symbols`, including DelphiLSP discovery from explicit path or resolved Delphi install, JSON/text envelopes, owned `.dak/<ProjectName>/lsp/` context artifacts, and deterministic fake-server-backed lifecycle coverage. (T-110, T-111, T-112, T-113, T-114, T-115)
- Added `lsp probe` to compare `contextFile` versus `settingsFile` handshakes, emit DelphiLSP capability matrices, and capture the Delphi 23 baseline for future Delphi 13 rechecks. (T-124)
- Added normalized `lsp definition` and `lsp references` results with stable DAK location objects, 1-based coordinates, support for host-qualified file URIs, and `--include-declaration` filtering. (T-116)
- Added normalized `lsp hover` results with `contentsText`, optional markdown/range data, explicit empty-result signaling, and compact text output. (T-117)
- Added normalized `lsp symbols` results with stable symbol rows, explicit empty arrays, and deterministic ordinal sorting before `--limit` trimming. (T-118)
- Added repo-local `delphi-lsp` skill guidance plus README `lsp` command docs covering semantic-routing, `.dak/<ProjectName>/lsp/` ownership, and optional `--rsvars`/`--envoptions` overrides. (T-119)
- Added the initial `remove-with` CLI shell with `scan`, `plan`, and `apply` modes, mutually exclusive `--unit`/`--dir`/`--all` targets, and a non-mutating JSON report skeleton under `.dak/<ProjectName>/remove-with/`. (T-136)
- Added a stable `remove-with` base report schema for files, `with` statements, resolver classifications, planned edits, skipped reasons, warnings, verification gates, and text summaries. (T-149)
- Added `remove-with` scan discovery for project-selected units, including selector text/counts, body ranges, nesting depth, and scoped parser warnings. (T-137)
- Added exact `remove-with` source ranges for selector lists, bodies, and whole `with` statements, preserving CRLF, UTF-8 BOM line mapping, comments, directives, and single control-statement bodies. (T-146)
- Added compiler-backed `remove-with` precedence fixtures for selector order, nested `with`, local/parameter/current/global fallback, inherited members, helpers, and overload call sites. (T-138)
- Added the source-backed `remove-with` symbol inventory core for locals, parameters, current-class context, unit globals, direct class/record members, constants, class vars, and external source classification. (T-139)
- Added `remove-with --mode plan` resolver classifications for identifiers inside single, multiple, and nested `with` statements, including unchanged, external, unsupported, unresolved, ambiguous, direct, inherited, hidden, overridden, helper-origin, helper-precedence, interface-contract, global-scope, qualified-unit, external-unit, indexed-selector, default-property, and source-owner cases. (T-141, T-152, T-153, T-154, T-155, T-156)
- Added standalone `remove-with` temp-policy decisions for direct qualification, object/interface reference temps, addressable record pointer temps, reserved temp-name allocation, and unsafe selector skips. (T-148)
- Added `remove-with --mode plan` source edit plans for standalone safe `with` rewrites, including temp declaration/replacement edits and skipped reasons for unsafe selectors or controlled statement contexts. (T-142)
- Added transactional `remove-with --mode apply` with run-scoped backups/manifests, quiet build verification, exact-byte rollback on failed verification, and applied/rolledBack reporting. (T-143)
- Added stable `remove-with --mode apply` report details for verification gates, transaction manifest paths, and per-file changed/restored statuses. (T-150)
- Added README and CLI help documentation for the `remove-with` safety model, modes, target filters, report classifications, LSP limits, and rollback behavior. (T-145)
- Added `dfm-inspect` with `tree` and `summary` output for lightweight text DFM inspection. (T-081)
- Added shared source-context snippets for resolved build and `dfm-check` failures, with `--source-context` / `--source-context-lines` CLI overrides and `[Diagnostics]` `dak.ini` defaults. (T-082)
- Added madExcept integration to `build-delphi.bat` with optional `dak.ini` key `[MadExcept].Path` and fallback discovery from common install locations.
- Added FixInsightCL execution via `analyze --fixinsight true` (CreateProcess). (T-009)
- Added `--log-file` (alias `--logfile`) to capture resolver diagnostics in a file. (T-010)
- Added `--log-tee` to mirror resolver diagnostics to output when using `--log-file`. (T-011)
- Added FixInsight report post-processing filters: `--exclude-path-masks`, `--ignore-warning-ids` and settings.ini sections `[ReportFilter]` + `[FixInsightIgnore]`. (T-013, T-014)
- Added Pascal Analyzer runner: `analyze --pascal-analyzer true` with PALCMD discovery + `--pa-path/--pa-output/--pa-args` and `[PascalAnalyzer]` settings.ini section. (T-015)
- Added PAL findings outputs (`pal-findings.md`, `pal-findings.jsonl`) after Pascal Analyzer runs. (T-023, T-026)
- Added PAL hotspots output (`pal-hotspots.md`) derived from PAL metrics reports. (T-025)
- Added SARIF output (`static-analysis.sarif`) from static-analysis postprocess for PR annotations. (T-055)
- Added `DAK_GATE_INCLUDE_PATHS` / `DAK_GATE_EXCLUDE_PATHS` to gate only selected paths during static analysis. (T-056)
- Added static-analysis fix recipes reference to speed up safe warning remediation. (T-057)

### Changed
- `remove-with --mode plan` now uses a compact high-volume report path: the
  root `withStatements` array is kept but omits detailed rows, summary/planned/
  skipped counts remain authoritative, legacy resolver classifications are
  skipped for large plan reports, and the old `.project-facts.json` semantic
  sidecar is no longer written. The proprietary fixture proof is cold `9.224s` median, warm
  `5.972s`, scan count `667`, and planned edit count `215`.
- `remove-with` now obtains its semantic final plan from the DelphiSemantics
  typed snapshot planner while preserving DAK report and apply compatibility.
- The earlier compact DelphiSemantics project-facts sidecar path is now
  superseded by typed snapshot planning; `projectFactsCache*` planner metrics
  remain zero for the remove-with snapshot path.
- `remove-with --mode plan` report JSON is now semantic-facts-first: legacy
  resolver-report compatibility timing/classification fields are removed,
  report-only projection no longer runs the legacy fallback resolver, and
  inactive conditional references stay out of semantic classifications.
- `remove-with --mode plan` report fallback decisions now consume
  DelphiSemantics scope-conflict facts instead of recomputing scope symbols in
  DAK, reducing the proprietary fixture `fallbackDecisionMs` proof metric to `4ms` while
  preserving scan count `667` and planned edit count `215`.
- `remove-with --mode plan` report generation now uses semantic report
  projection for the measured safe subset before falling back to the legacy
  resolver report path, while keeping the existing JSON contract additive.

- Project analysis commands now pass target-derived compiler/platform defines to
  DelphiAST and disable host-process compiler defines when parsing another
  target platform.
- `remove-with` now relies on Symbol Map/RTL-source provenance for `Math.Min` and
  `Math.Max` instead of treating them as generic compiler-intrinsic fallbacks.
- DAK project metadata and remove-with semantic inventory integration now route through
  the stable `DelphiSemantics.Api` facade where that facade covers the needed behavior.
- DAK RTL source symbol inventory and Symbol Map indexing now use DelphiSemantics
  compiler profiles instead of local duplicate RTL extraction paths.
- `remove-with` symbol inventory now runs under the shared AST-backed project model phase and logs `model-unit` inventory progress, while the legacy declaration scanner is isolated as flat compatibility inventory until semantic model reporting parity is complete. (T-177)
- Reworked `remove-with` body rewriting to apply resolver-bound source ranges instead of rescanning replacement text, with regression coverage for labels, type names, scoped declarations, nested replacement ordering, and transactional apply safety. (T-175)
- Hardened `rsvars.bat` imports in both the build script and Delphi runner against stale RAD/DCC environment variables, overlong inherited PATH values, and oversized MSBuild environment-prop command lines. (T-197)
- `remove-with` resolver, selector-expression, temp-policy, and planner lookups now use scoped dictionaries and the live project-model semantic index where complete, while preserving compatibility fallback behavior for existing resolver metadata. (T-173)
- `remove-with` now bootstraps one shared project model per command and reuses that indexed project data for discovery and symbol inventory, removing the previous duplicate project-index pass in plan/apply mode. (T-171)
- Clarified external `lsp` docs for Delphi 23: `symbols` is file-scoped `documentSymbol`, `references` is version-gated, and Delphi 13.x will be rechecked once installed. (T-121)
- Reworked external `lsp symbols` to use file-scoped `textDocument/documentSymbol`, require `--file`, and flatten hierarchical document symbols into deterministic rows. (T-122)
- Defaulted CLI `--platform` to `Win32` and `--config` to `Release` when omitted. (T-002)
- Generated FixInsight bat now uses one argument per line and no command echo. (T-002)
- Auto-detect FixInsightCL.exe via `PATH`, then `HKCU\Software\FixInsight\Path` for bat output. (T-003)
- Added FixInsightCL pass-through options via settings.ini defaults and CLI overrides. (T-004)
- Suppressed stdout output during FixInsightCL runs unless resolve output is explicitly requested. (T-010)
- Updated `fixinsight-run.bat` to generate sample FixInsight reports (txt/xml/csv) under `docs\sample-fix-insight-self-reports\`. (T-017)
- Static-analysis skill scripts now call DAK analyze subcommands directly. (T-029)
- Normalized `build` output paths to be repo-relative (VCS root when detected) for stable, machine-independent logs. (T-059)
- `DelphiAIKit.exe build` now runs through a native Delphi build runner instead of delegating to `build-delphi.bat`, while the batch file remains as a compatibility/bootstrap wrapper. (T-080)
- `DelphiAIKit.exe build` now auto-detects strong TMS WEB Core project markers and routes those projects through the WebCore backend instead of requiring separate wrapper scripts. (T-092)
- JSON build output now includes output file metadata and stale-output indicators (`output_stale`, `output_message`) plus bounded findings arrays. (T-067)
- `build-delphi.bat` now injects missing `environment.proj` variables into MSBuild as `/p:` properties when they are not already present in the process environment. (T-068)
- `build-delphi.bat` now runs `madExceptPatch.exe` only when `.mes` exists, `.dpr`/`.dproj` base names match, and `madExcept` is defined for the selected `Config`/`Platform`.

### Fixed
- Fixed `build --dfmcheck` so DFM validation is gated on the actual source build result, not later post-build failures, and post-build failures now print the failed phase instead of only `FAILED. Errors: 0`.
- Fixed `build-delphi.bat` parallel-run temp handoff files to use the per-run
  GUID and fail closed when MSBuild emits logger/temp file-access errors.
- Fixed build summary parsing so compiler, fatal, and hint-warning diagnostics now preserve structured severity, file token, line, column, code, and message data for source-context and LSP enrichment.
- Fixed `remove-with --mode apply` to fail closed with a
  `report-apply-mismatch` report when the apply statement ID set diverges from
  the semantic report-only plan, including empty apply sets that would otherwise
  look like no-op applies.
- Fixed `remove-with` DTO-primary planning to preserve DelphiSemantics statement
  IDs directly instead of remapping final statements through DAK scan coordinates.
- Fixed slash-style refactoring switches such as `/new-name` after optional
  boolean flags such as `--apply`, by routing CLI switch value policy and
  slash-switch boundary detection through one descriptor table. (T-475)
- Fixed `symbol-map index --unit` so targeted unit indexing completes quickly when stdout/stderr are redirected, while project-wide indexing remains responsible for warming source-available RTL cache rows. (T-457)
- `build-delphi.bat` environment-prop forwarding now quotes semicolon-delimited
  values and avoids passing `DCC_UnitSearchPath` as a global MSBuild property,
  preserving project-defined search paths such as `..\src`.
- Failed `remove-with --mode apply` build verification reports now include bounded
  diagnostic lines in the JSON build gate, not only links to stdout/stderr logs.
- Fixed `remove-with` resolution for Delphi compiler intrinsics, built-in type aliases, implicit `System` qualifiers, inactive conditional branches, implementation globals after routines, captured outer locals in nested routines, legacy `^J`/`^M` literals, and multiline enum/type-alias declarations. Added detailed unresolved-reason buckets to JSON reports.
- Fixed `remove-with` planning for selector expressions that depend on earlier `with` selectors, and for identifiers ending in digits, so generated rewrites qualify those references instead of leaving undeclared names such as `fd`, `f1`, or `Code1`.
- Fixed `remove-with` source inventory comment handling so ordinary `{...}` and `(*...*)` comments before type declarations no longer corrupt resolved owner type names, restoring selector resolution for cases such as proprietary fixture `DF[d]^`.
- Fixed `remove-with` large-project planning throughput by building a resolver-scoped symbol name index and broadening safe known compiler/RTL calls such as `FillChar`, `Move`, `SizeOf`, and `Exit`.
- Fixed `remove-with` plan-mode timeouts on large projects by indexing symbol de-duplication, current-class member expansion, and resolver lookup caches with case-insensitive dictionaries.
- Fixed `remove-with` parsing for ANSI-encoded Delphi units by falling back from UTF-8 to the Windows default source encoding during read-only source loading and symbol extraction.
- Fixed `remove-with` resolver handling for known compiler/RTL calls (`Inc`, `Dec`, `Assigned`, `Length`, `SetLength`, `Low`, `High`, `Include`, `Exclude`) so safe `with` rewrites can proceed while unknown external calls still block. (T-167)
- Fixed `remove-with` source-model hardening so attributes, conditional regions, multiline member declarations, generic declarations, and nested type declarations are conservatively skipped with explicit `unsupported-source-model-*` reasons instead of being guessed by the line parser. (T-166)
- Fixed `remove-with` expression-role safety so labels, case labels, declaration-like bodies, type qualifiers, and unit/type qualifier collisions are skipped or preserved with explicit role details instead of being lexically rewritten as receiver members. (T-165)
- Fixed `remove-with` planning so `with` bodies containing inline scoped declarations (`var`, `for var`, or `except on`) are skipped with an explicit `scoped-declaration-in-with-body` reason and apply mode leaves those sources unchanged. (T-164)
- Fixed `remove-with --mode apply` temp handling so repeated record/object selectors in the same routine reserve unique temp names and aggregate declarations into one legal routine-level insertion point, including existing `var` sections and local routine declarations. (T-163)
- Fixed post-build `--dfmcheck` diagnostics so source-build failures clearly report that DFM validation was skipped, and missing `madExcept.dcu` failures explain the `madExcept` define/library-path cause.
- Fixed generated `dfm-check` helper projects so optional madExcept startup units are not injected into the checker DPR, while existing madExcept defines/search paths remain available for project units that intentionally use madExcept.
- Fixed generated `dfm-check` `DCC_UnitSearchPath` insertion so Windows paths containing backslash-digit segments such as `\3rdParty` or `\23.0` are not corrupted by regex replacement.
- Fixed MSBuild condition parsing so RAD Studio targets using unary `!`, `Exists(...)`, `HasTrailingSlash(...)`, and quoted empty property values no longer block `analyze` project parsing. (T-135)
- Fixed `dfm-check` generated helper projects so they now reuse the source build's effective compile search path, preserving EnvOptions/IDE library-path entries and imported search-path context alongside discovered form-unit directories instead of failing early with false `Unit ... not found` errors in the generated `_DfmCheck.dproj`. (T-109)
- Fixed `dfm-check` temp-artifact ownership so generated harness files, forced build outputs, and preserved debug artifacts now live under sibling `.dak/<ProjectName>/dfm-check/runs/<RunId>/...`; startup prunes stale run folders, keep-artifacts mode preserves only that owned run workspace, and copied `.dproj` files with multiple relative `Icon_MainIcon` entries remain valid XML. (T-108)
- Fixed `deps` JSON output so it now caches SCC hotspot analysis once per build, emits structured cycle/hotspot sections with inline node and edge metadata, keeps the compatibility `cycles` array, and ranks equal-impact cycle edges with `implementation` dependencies ahead of `interface` ones. (T-105)
- Improved `lsp` unsupported-method diagnostics during the real `DelphiLSP.exe` verification work, so DAK now fails early with clear capability messages when an installed server does not advertise `textDocument/references`, instead of surfacing a later raw JSON-RPC method-not-found failure. (T-120, T-123)
- Fixed `deps` cycle reporting so SCC summaries now emit real representative traversal paths instead of alphabetically joined member lists, and the cycle builder now releases its temporary discovery state correctly under exception paths. (T-104)
- Fixed CLI startup crash handling so true unhandled exceptions now reach madExcept, and startup applies the MaxLogic bugreport upload configuration from one executable-derived path. (T-099, T-100)
- Fixed `dfm-check` so verbose Win32 runs no longer overflow when MSBuild reports a native exit code larger than `Integer`, and the CLI now preserves the unsigned and hexadecimal exit code text in diagnostics. (T-098)
- Fixed bundled `dfm-check` frame validation so injected `DfmStreamAll.pas` now retries VCL frames through the constructor path when stream validation hits duplicate-component false positives such as `A component named pnlFilter already exists`.
- Fixed `dfm-check` helper-project generation so projects that inherit `DCC_UnitSearchPath` only from imported `.optset` files now get a synthesized search-path node in the generated `_DfmCheck.dproj`, preventing false `F2613 Unit not found` failures for form units such as `uMainForm`; cleanup-on-failure is regression-tested, and keep-artifacts mode now announces itself explicitly when `DAK_DFMCHECK_KEEP_ARTIFACTS=true`.
- Fixed `dfm-check` bundled inject-file discovery so detached/copy-built `DelphiAIKit.exe` binaries can still find `tools\inject` (with `docs\delphi-dfm-checker\tools\inject` fallback) by walking ancestor directories from the executable.
- Fixed `build` and `dfm-check` so invalid `[Diagnostics]` `dak.ini` values for `SourceContext` / `SourceContextLines` now surface as warnings instead of silently falling back to defaults. (T-087)
- Fixed help-mode command routing to reject trailing unknown positional tokens after an explicit command (for example `--help analyze foo`) instead of silently accepting them. (T-078)
- Fixed MSBuild property expansion so undefined self-references (for example `$(PreBuildEvent)` in `PreBuildEvent`) now resolve to empty text instead of remaining unresolved macro tokens. (T-077)
- Fixed help-mode command detection so unknown explicit command tokens (for example `foo --help`) now return an invalid-arguments error instead of silently falling back to global help. (T-076)
- Fixed help-command detection so switch-consumed values that match command names (for example `--project analyze --help`) are no longer treated as explicit commands, and explicit command tokens are still detected correctly. (T-075)
- Fixed FixInsight CSV delimiter/layout validation so numeric/rule-like message fragments cannot spoof headerless column layout and cause incorrect `--ignore-warning-ids` filtering. (T-075)
- Fixed help command routing so `--help` no longer treats switch values (for example `--project C:\...`) as command tokens, and explicit commands after switch values are now detected correctly. (T-074)
- Fixed native build madExcept gating so `.mes` `GeneralSettings` can disable post-build patching via `HandleExceptions=0` or `LinkInCode=0`, including UTF-8-with-BOM `.mes` files. (T-084)
- Fixed native Delphi build output-path resolution so imported `CfgDependentOn` `.optset` values now feed the effective `DCC_ExeOutput` used by JSON summaries and madExcept patching, and missing resolved outputs now report a specific diagnostic instead of a generic madExcept patch failure. (T-107)
- Changed `analyze` so omitted `--out` now writes project/unit artifacts under sibling `.dak` working trees instead of legacy `_analysis` roots. (T-086)
- Changed the repo-local static-analysis wrappers/docs to default to sibling `.dak` roots and to skip `.dak` artifact trees during report post-processing. (T-085)
- Fixed `analyze` summary generation to ignore stale FixInsight TXT findings/top-codes when TXT report generation is skipped (for example `--fixinsight false --clean false`), preventing carry-over from previous runs. (T-073)
- Fixed CLI argument validation so `analyze-unit` now rejects simultaneous `--project` and `--unit` inputs with a clear conflict error, matching `analyze` command behavior. (T-072)
- Fixed MSBuild `Condition` parsing to treat single-quote boundaries as token delimiters for `and`/`or`, so valid expressions without surrounding whitespace (for example `'A'=='A'or'B'=='B'`) are accepted. (T-071)
- Fixed FixInsight CSV post-processing header detection so headerless rows are not mistaken for header rows when the message column contains header-like words (for example `line`), restoring correct `--ignore-warning-ids` filtering. (T-071)
- Fixed FixInsight CSV post-processing delimiter/layout validation so `--ignore-warning-ids` uses the actual rule column and is not confused by rule-like tokens inside message text.
- Fixed CLI project input validation to reject unsupported `--project` file types early (now only `.dproj`, `.dpr`, `.dpk` are accepted), with a clear error instead of late XML parse failures.
- Fixed MSBuild project evaluation to bind `TXMLDocument` to the detected OmniXML DOM vendor, so `.dproj` parsing no longer fails on systems where MSXML is unavailable.
- Fixed MSBuild `Condition` parsing to reject malformed trailing tokens/operators instead of silently accepting invalid expressions.
- Fixed FixInsightCL.exe discovery across HKCU/HKLM 32/64-bit registry views. (T-005)
- Fixed missing macro defaults (BDSUSERDIR/BDSCatalogRepository/BDSLIB/DCC_*) to avoid unresolved paths. (T-005)
- Fixed FixInsightCL discovery for the TMS FixInsight Pro registry key. (T-006)
- Fixed FixInsightCL resolution via settings.ini Path fallback. (T-007)
- Fixed bat output to avoid UTF-8 BOM, set UTF-8 codepage, and prevent overlong command lines. (T-008)
