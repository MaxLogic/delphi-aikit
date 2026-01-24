unit Dcr.Messages;

interface

resourcestring
  SUsage =
    'DelphiConfigResolver.exe --dproj "<path>" --delphi <23.0> [--platform <Win32|Win64>] [--config <Debug|Release>] ' +
    '[--out-kind <bat|ini|xml>] [--out "<path>"] [--output "<path>"] [--ignore "<list>"] [--settings "<path>"] ' +
    '[--silent [true|false]] [--xml [true|false]] [--csv [true|false]] [--run-fixinsight [true|false]] [--logfile "<path>"] ' +
    '[--exclude-path-masks "<list>"] [--ignore-warning-ids "<list>"] ' +
    '[--run-pascal-analyzer [true|false]] [--pa-path "<path>"] [--pa-output "<path>"] [--pa-args "<args>"] ' +
    '[--log-tee [true|false]] ' +
    '[--verbose <true|false>] ' +
    '[--rsvars "<path>"] [--envoptions "<path>"]';
  SInvalidArgs = 'Invalid command line arguments.';
  SArgMissingValue = 'Missing value for parameter: %s';
  SInvalidOutKind = 'Invalid --out-kind value: %s';
  SInvalidBoolValue = 'Invalid value for %s: %s';
  SUnknownArg = 'Unknown argument: %s';
  SFileNotFound = 'File not found: %s';
  SAssociatedDprojMissing = 'Associated .dproj not found for: %s';
  SInfoAssociatedDproj = 'Using associated .dproj: %s';
  SRegistryBaseMissing = 'Delphi registry base key not found for version %s.';
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
  SInfoSettingsPath = 'settings.ini: %s';
  SInfoResolvedDefines = 'Defines resolved: %s';
  SInfoResolvedUnitScopes = 'Unit scopes resolved: %s';
  SInfoResolvedProjectSearchPath = 'Project search path resolved: %s';
  SInfoResolvedLibraryPath = 'Library path resolved: %s';
  SInfoResolvedCombinedSearchPath = 'Combined search path resolved: %s';
  SInfoFixInsightPath = 'FixInsightCL.exe: %s';
  SFixInsightNotFound =
    'FixInsightCL.exe not found in PATH or FixInsight registry (HKCU/HKLM 32/64-bit; FixInsight/TMS FixInsight Pro).';
  SFixInsightPathInvalid = 'FixInsightCL.exe not found at settings.ini Path: %s';
  SFixInsightExeMissing = 'FixInsightCL.exe path is not resolved.';
  SFixInsightRunFailed = 'FixInsightCL.exe failed to start: %s';
  SFixInsightRunExit = 'FixInsightCL.exe exited with code %d.';
  SLogFileOpenFailed = 'Failed to open log file: %s';
  SSettingsInvalidBool = 'Invalid settings.ini boolean for %s: %s';

implementation

end.
