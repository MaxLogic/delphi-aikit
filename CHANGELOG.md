# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Added
- Added DelphiAIKit CLI to resolve FixInsight params from .dproj/.optset. (T-001)
- Added a `--verbose` flag to emit detailed diagnostics for troubleshooting. (T-001)
- Added `--rsvars` to override the `rsvars.bat` location for IDE environment setup. (T-001)
- Added `--envoptions` to override the `EnvOptions.proj` path when the default is not available. (T-001)
- Added `analyze` with `--project`/`--unit` to run FixInsight/PAL with stable `_analysis` output and summaries. (T-027, T-028)
- Added build output controls: `--show-warnings`, `--show-hints`, `--ignore-warnings`, `--ignore-hints`, `--ai`. (T-058, T-060, T-061)
- Added build options: `--target/--rebuild`, `--json`, `--max-findings`, `--build-timeout-sec`, and `--test-output-dir`. (T-062, T-063, T-064, T-065, T-066)
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
- Defaulted CLI `--platform` to `Win32` and `--config` to `Release` when omitted. (T-002)
- Generated FixInsight bat now uses one argument per line and no command echo. (T-002)
- Auto-detect FixInsightCL.exe via `PATH`, then `HKCU\Software\FixInsight\Path` for bat output. (T-003)
- Added FixInsightCL pass-through options via settings.ini defaults and CLI overrides. (T-004)
- Suppressed stdout output during FixInsightCL runs unless resolve output is explicitly requested. (T-010)
- Updated `fixinsight-run.bat` to generate sample FixInsight reports (txt/xml/csv) under `docs\sample-fix-insight-self-reports\`. (T-017)
- Static-analysis skill scripts now call DAK analyze subcommands directly. (T-029)
- Normalized `build` output paths to be repo-relative (VCS root when detected) for stable, machine-independent logs. (T-059)
- JSON build output now includes output file metadata and stale-output indicators (`output_stale`, `output_message`) plus bounded findings arrays. (T-067)
- `build-delphi.bat` now injects missing `environment.proj` variables into MSBuild as `/p:` properties when they are not already present in the process environment. (T-068)
- `build-delphi.bat` now runs `madExceptPatch.exe` only when `.mes` exists, `.dpr`/`.dproj` base names match, and `madExcept` is defined for the selected `Config`/`Platform`.

### Fixed
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
