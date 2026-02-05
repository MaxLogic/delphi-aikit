# Changelog

All notable user-visible changes to this project will be documented in this file.

## [Unreleased]

### Added
- Added DelphiAIKit CLI to resolve FixInsight params from .dproj/.optset. (T-001)
- Added a `--verbose` flag to emit detailed diagnostics for troubleshooting. (T-001)
- Added `--rsvars` to override the `rsvars.bat` location for IDE environment setup. (T-001)
- Added `--envoptions` to override the `EnvOptions.proj` path when the default is not available. (T-001)
- Added `analyze` with `--project`/`--unit` to run FixInsight/PAL with stable `_analysis` output and summaries. (T-027, T-028)
- Added FixInsightCL execution via `analyze --fixinsight true` (CreateProcess). (T-009)
- Added `--log-file` (alias `--logfile`) to capture resolver diagnostics in a file. (T-010)
- Added `--log-tee` to mirror resolver diagnostics to output when using `--log-file`. (T-011)
- Added FixInsight report post-processing filters: `--exclude-path-masks`, `--ignore-warning-ids` and settings.ini sections `[ReportFilter]` + `[FixInsightIgnore]`. (T-013, T-014)
- Added Pascal Analyzer runner: `analyze --pascal-analyzer true` with PALCMD discovery + `--pa-path/--pa-output/--pa-args` and `[PascalAnalyzer]` settings.ini section. (T-015)
- Added PAL findings outputs (`pal-findings.md`, `pal-findings.jsonl`) after Pascal Analyzer runs. (T-023, T-026)
- Added PAL hotspots output (`pal-hotspots.md`) derived from PAL metrics reports. (T-025)
- Added SARIF output (`static-analysis.sarif`) from static-analysis postprocess for PR annotations. (T-055)

### Changed
- Defaulted CLI `--platform` to `Win32` and `--config` to `Release` when omitted. (T-002)
- Generated FixInsight bat now uses one argument per line and no command echo. (T-002)
- Auto-detect FixInsightCL.exe via `PATH`, then `HKCU\Software\FixInsight\Path` for bat output. (T-003)
- Added FixInsightCL pass-through options via settings.ini defaults and CLI overrides. (T-004)
- Suppressed stdout output during FixInsightCL runs unless resolve output is explicitly requested. (T-010)
- Updated `fixinsight-run.bat` to generate sample FixInsight reports (txt/xml/csv) under `docs\sample-fix-insight-self-reports\`. (T-017)
- Static-analysis skill scripts now call DAK analyze subcommands directly. (T-029)

### Fixed
- Fixed FixInsightCL.exe discovery across HKCU/HKLM 32/64-bit registry views. (T-005)
- Fixed missing macro defaults (BDSUSERDIR/BDSCatalogRepository/BDSLIB/DCC_*) to avoid unresolved paths. (T-005)
- Fixed FixInsightCL discovery for the TMS FixInsight Pro registry key. (T-006)
- Fixed FixInsightCL resolution via settings.ini Path fallback. (T-007)
- Fixed bat output to avoid UTF-8 BOM, set UTF-8 codepage, and prevent overlong command lines. (T-008)
