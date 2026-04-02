unit Dak.Messages;

interface

resourcestring
  SUsageGlobal =
    'DelphiAIKit.exe <command> [global options] [command options]' + #13#10 +
    'Commands:' + #13#10 +
    '  resolve   Resolve FixInsight params (ini/xml/bat)' + #13#10 +
    '  analyze   Run FixInsight / Pascal Analyzer' + #13#10 +
    '  build     Build a Delphi or TMS WEB Core project (.dproj; or .dpr/.dpk with sibling .dproj)' + #13#10 +
    '  dfm-check Validate DFM streaming via generated _DfmCheck harness project' + #13#10 +
    '  dfm-inspect Inspect text DFM structure and event bindings' + #13#10 +
    '  global-vars List project global variables and their routine usages' + #13#10 +
    '  deps      Analyze project unit dependencies for AI debugging' + #13#10 +
    'Use "DelphiAIKit.exe <command> --help" for command-specific options.';
  SUsageResolve =
    'DelphiAIKit.exe resolve --project "<path>" --delphi <23.0> ' +
    '[--platform <Win32|Win64>] [--config <Debug|Release>]' + #13#10 +
    '  [--format <ini|xml|bat>] [--out-file "<path>"]' + #13#10 +
    '  [--fi-output "<path>"] [--fi-ignore "<list>"] [--fi-settings "<path>"] [--fi-silent [true|false]] ' +
    '[--fi-xml [true|false]] [--fi-csv [true|false]]' + #13#10 +
    '  [--exclude-path-masks "<list>"] [--ignore-warning-ids "<list>"]' + #13#10 +
    '  [--rsvars "<path>"] [--envoptions "<path>"] [--log-file "<path>"] [--log-tee [true|false]] ' +
    '[--verbose [true|false]]';
  SUsageAnalyze =
    'DelphiAIKit.exe analyze --project "<path>" --delphi <23.0> ' +
    '[--platform <Win32|Win64>] [--config <Debug|Release>]' + #13#10 +
    '  [--out "<path>"] [--fi-formats <txt|xml|csv|all>] [--fixinsight [true|false]] ' +
    '[--pascal-analyzer [true|false]]' + #13#10 +
    '  [--exclude-path-masks "<list>"] [--ignore-warning-ids "<list>"]' + #13#10 +
    '  [--fi-settings "<path>"] [--fi-ignore "<list>"] [--fi-silent [true|false]]' + #13#10 +
    '  [--pa-path "<path>"] [--pa-output "<path>"] [--pa-args "<args>"]' + #13#10 +
    '  [--clean [true|false]] [--write-summary [true|false]]' + #13#10 +
    '  [--rsvars "<path>"] [--envoptions "<path>"] [--log-file "<path>"] [--log-tee [true|false]] ' +
    '[--verbose [true|false]]' + #13#10 +
    'DelphiAIKit.exe analyze --unit "<path>" --delphi <23.0> [--out "<path>"] ' +
    '[--pascal-analyzer [true|false]] [--pa-path "<path>"] [--pa-output "<path>"] [--pa-args "<args>"]';
  SUsageBuild =
    'DelphiAIKit.exe build --project "<path>" [--delphi <23.0>] ' +
    '[--platform <Win32|Win64>] [--config <Debug|Release>] [--target <Build|Rebuild>] [--rebuild [true|false]] ' +
    '[--builder <auto|delphi|webcore>] [--webcore-compiler "<path>"] [--pwa] [--no-pwa] ' +
    '[--json [true|false]] [--max-findings <N>] [--build-timeout-sec <N default 0>] [--test-output-dir "<path>"] ' +
    '[--ai] [--show-warnings] [--show-hints] [--dfmcheck] ' +
    '[--dfm "<file.dfm[,file2.dfm]>"] [--all] ' +
    '[--ignore-warnings "<list>"] [--ignore-hints "<list>"] [--exclude-path-masks "<list>"] ' +
    '[--source-context <auto|off|on>] [--source-context-lines <N>] [--rsvars "<path>"]';
  SUsageDfmCheck =
    'DelphiAIKit.exe dfm-check --dproj "<path>" [--delphi <23.0>] [--config <Release|Debug>] [--platform <Win32|Win64>] ' +
    '[--dfm "<file.dfm[,file2.dfm]>"] [--all] [--source-context <auto|off|on>] ' +
    '[--source-context-lines <N>] [--rsvars "<path>"] [--verbose [true|false]]';
  SUsageDfmInspect =
    'DelphiAIKit.exe dfm-inspect --dfm "<path>" [--format <tree|summary>]';
  SUsageGlobalVars =
    'DelphiAIKit.exe global-vars --project "<path>" [--format <text|json>] [--output "<path>|-"] ' +
    '[--cache "<path>"] [--refresh <auto|force>] [--unused-only] [--unit "<pattern>"] [--name "<pattern>"] ' +
    '[--reads-only] [--writes-only] [--verbose [true|false]]';
  SUsageDeps =
    'DelphiAIKit.exe deps --project "<path>" [--format <json|text>] [--output "<path>|-"] ' +
    '[--unit "<UnitName>"] [--top <N, 0=unlimited>]';
  SInvalidArgs = 'Invalid command line arguments.';
  SUnknownCommand = 'Unknown command: %s';
  SArgMissingValue = 'Missing value for parameter: %s';
  SInvalidOutKind = 'Invalid --format value: %s';
  SInvalidBoolValue = 'Invalid value for %s: %s';
  SInvalidBuildTarget = 'Invalid --target value: %s (expected Build or Rebuild).';
  SInvalidBuildBackend = 'Invalid --builder value: %s (expected auto, delphi, or webcore).';
  SBuildOptionDelphiOnly = '%s is only supported for Delphi/MSBuild builds.';
  SInvalidMaxFindings = 'Invalid --max-findings value: %s (expected integer >= 1).';
  SInvalidBuildTimeout = 'Invalid --build-timeout-sec value: %s (expected integer >= 0).';
  SInvalidSourceContext = 'Invalid --source-context value: %s (expected auto, off, or on).';
  SInvalidSourceContextLines = 'Invalid --source-context-lines value: %s (expected integer >= 0).';
  SInvalidFiFormats = 'Invalid --fi-formats value: %s';
  SGlobalVarsInvalidFormat = 'Unsupported global-vars format: %s';
  SGlobalVarsInvalidRefresh = 'Unsupported global-vars refresh mode: %s';
  SGlobalVarsConflictingAccessFilters = 'Use either --reads-only or --writes-only (not both).';
  SGlobalVarsUnusedAccessConflict = '--unused-only cannot be combined with --reads-only or --writes-only.';
  SDepsInvalidFormat = 'Unsupported deps format: %s';
  SDepsInvalidTopLimit = 'Invalid --top value: %s (expected integer >= 0).';
  SUnknownArg = 'Unknown argument: %s';
  SAnalyzeUnitConflict = 'Use either --project or --unit (not both) for analyze.';
  SBuildBatMissing = 'build-delphi.bat not found: %s';
  SFileNotFound = 'File not found: %s';
  SUnsupportedLinuxPath = 'Unsupported Linux path format: %s. Use /mnt/<drive>/... or a Windows path.';
  SUnsupportedProjectInput = 'Unsupported project input: %s. Expected .dproj, .dpr, or .dpk.';
  SAssociatedDprojMissing = 'Associated .dproj not found for: %s';
  SInfoAssociatedDproj = 'Using associated .dproj: %s';
  SRegistryBaseMissing = 'Delphi registry base key not found for version %s.';
  SRegistryBaseMissingFallbackFailed =
    'Delphi registry base key not found for version %s, and EnvOptions fallback failed: %s';
  SRegistryLibraryMissing = 'Library search path not found for platform %s.';
  SEnvOptionsNotFound = 'EnvOptions.proj not found at: %s';
  SEnvOptionsMissingLibPath = 'DelphiLibraryPath not found in EnvOptions.proj for platform %s.';
  SRsVarsNotFound = 'rsvars.bat not found at: %s';
  SRsVarsFailed = 'rsvars.bat failed with exit code %d.';
  SDprojParseError = 'Failed to parse project file: %s';
  SOptsetParseError = 'Failed to parse option set: %s';
  SConditionParseError = 'Unsupported or invalid Condition: %s';
  SMainSourceMissing = 'MainSource not found in project.';
  SMainSourceMissingFile = 'MainSource file not found: %s';
  SLibraryPathEmpty = 'Library search path is empty.';
  SSearchPathEmpty = 'Combined search path is empty.';
  SOutputWriteFailed = 'Failed to write output: %s';
  SXmlVendorMissing = 'XML vendor not available: %s.';
  SUnknownMacro = 'Unknown macro: %s';
  SCycleMacro = 'Macro cycle detected: %s';
  SMissingDirectory = 'Hint: Missing directory: %s';
  SUnresolvedMacroDropped = 'Unresolved macro in %s, skipped: %s';
  SOptsetUsing = 'Using option set: %s';
  SOptsetMissing = 'Option set not found: %s';
  SSourceDefines = 'Defines source: %s';
  SSourceSearchPath = 'Unit search path source: %s';
  SSourceUnitScopes = 'Unit scopes source: %s';
  SSourceUnitAliases = 'Unit aliases source: %s';
  SSourceLibraryPath = 'Library path source: %s';
  SSourceUnknown = 'unknown';
  SSourceDproj = 'dproj';
  SSourceOptset = 'optset';
  SSourceRegistry = 'registry';
  SSourceEnvOptions = 'envoptions';
  SUnhandledException = 'Unhandled exception: %s: %s';
  SInfoOptions = 'Options: dproj=%s platform=%s config=%s delphi=%s';
  SInfoProjectDir = 'Project dir: %s';
  SInfoMainSource = 'Main source: %s';
  SInfoOptsetResolved = 'Option set resolved: %s';
  SInfoRegistryBase = 'Registry base key: %s';
  SInfoRegistryView = 'Registry view: %s';
  SInfoRegistryBaseMissing = 'Registry base key missing in %s view.';
  SInfoRegistryVersions = 'Available BDS versions (%s view): %s';
  SInfoRegistryLookupContext = 'Registry lookup context: user=%s appdata=%s bdsuserdir=%s envoptions=%s';
  SInfoRegistryKeyPresence = 'Registry key presence (%s view): base=%s env=%s lib=%s';
  SInfoEnvOptionsPath = 'EnvOptions.proj path: %s';
  SInfoEnvVarCount = 'IDE env vars: %d';
  SInfoEnvVarCountView = 'IDE env vars (%s view): %d';
  SInfoLibraryPathRaw = 'Library search path: %s';
  SInfoRsVarsPath = 'rsvars.bat path: %s';
  SInfoRsVarsCount = 'rsvars env vars: %d';
  SInfoStep = 'Step: %s';
  SInfoReadingFile = 'Reading: %s';
  SInfoGroupCondition = 'PropertyGroup condition: %s => %s';
  SInfoPropertyCondition = 'Property %s condition: %s => %s';
  SInfoPropertyRaw = 'Property %s raw: %s';
  SInfoPropertySet = 'Property %s = %s';
  SInfoRegistryLibraryFallback = 'Registry Search Path missing, falling back to EnvOptions.proj.';
  SInfoEnvOptionsOverride = 'EnvOptions override: %s';
  SInfoEnvOptionsPlatformAlias = 'EnvOptions platform alias: %s -> %s';
  SInfoSettingsPath = 'dak.ini: %s';
  SInfoResolvedDefines = 'Defines resolved: %s';
  SInfoResolvedUnitScopes = 'Unit scopes resolved: %s';
  SInfoResolvedProjectSearchPath = 'Project search path resolved: %s';
  SInfoResolvedLibraryPath = 'Library path resolved: %s';
  SInfoResolvedCombinedSearchPath = 'Combined search path resolved: %s';
  SInfoFixInsightPath = 'FixInsightCL.exe: %s';
  SFixInsightNotFound =
    'FixInsightCL.exe not found in PATH or FixInsight registry (HKCU/HKLM 32/64-bit; FixInsight/TMS FixInsight Pro).';
  SFixInsightPathInvalid = 'FixInsightCL.exe not found at dak.ini Path: %s';
  SFixInsightExeMissing = 'FixInsightCL.exe path is not resolved.';
  SFixInsightRunFailed = 'FixInsightCL.exe failed to start: %s';
  SFixInsightRunExit = 'FixInsightCL.exe exited with code %d.';
  SLogFileOpenFailed = 'Failed to open log file: %s';
  SSettingsInvalidBool = 'Invalid dak.ini boolean for %s: %s';
  SBuildWarningMissingWinapiNamespace =
    'Project %s for %s does not include Winapi in the effective DCC_Namespace. ' +
    'Units like ''Windows'' may not resolve.';
  SBuildPreflightSkipped = 'Build preflight warning check skipped: %s';

implementation

procedure TouchMessagesForAnalysis;
  procedure Touch(const aValue: string); inline;
  begin
    if aValue = '' then
      Exit;
  end;
begin
  if False then
  begin
    Touch(SSourceUnitAliases);
    Touch(SInvalidArgs);
    Touch(SSourceLibraryPath);
    Touch(SSourceUnknown);
    Touch(SFixInsightRunExit);
    Touch(SSourceDproj);
    Touch(SRegistryLibraryMissing);
    Touch(SSourceRegistry);
    Touch(SBuildBatMissing);
    Touch(SInfoEnvVarCount);
    Touch(SSourceSearchPath);
    Touch(SSourceOptset);
    Touch(SUnhandledException);
    Touch(SSourceUnitScopes);
    Touch(SInfoOptions);
    Touch(SInfoAssociatedDproj);
    Touch(SSourceDefines);
    Touch(SSourceEnvOptions);
  end;
end;

end.
