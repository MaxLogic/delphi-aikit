unit Dak.Types;

interface

{$SCOPEDENUMS ON}

type
  TCommandKind = (ckResolve, ckAnalyzeProject, ckAnalyzeUnit, ckBuild, ckDfmCheck, ckDfmInspect, ckGlobalVars,
    ckDeps);

  TOutputKind = (okIni, okXml, okBat);
  TBuildBackend = (bbAuto, bbDelphi, bbWebCore);

  TPropertySource = (psUnknown, psDproj, psOptset, psRegistry, psEnvOptions);

  TReportFormat = (rfText, rfXml, rfCsv);
  TReportFormatSet = set of TReportFormat;

  TGlobalVarsFormat = (gvfText, gvfJson);
  TGlobalVarsRefresh = (gvrAuto, gvrForce);
  TDepsFormat = (dfJson, dfText);
  TSourceContextMode = (scmAuto, scmOff, scmOn);

  TDiagnosticsDefaults = record
    fSourceContextMode: TSourceContextMode;
    fSourceContextLines: Integer;
  end;

  TProjectSourceLookup = record
    fProjectDproj: string;
    fProjectDir: string;
    fMainSourcePath: string;
    fSearchPaths: TArray<string>;
  end;

  TProjectAnalysisContext = record
    fProjectPath: string;
    fProjectName: string;
    fProjectDir: string;
    fMainSourcePath: string;
    fParserDefines: string;
    fParserSearchPath: string;
    fDakProjectRoot: string;
    fHasDelphiContext: Boolean;
    fContextNote: string;
  end;

  TSourceContextSnippet = record
    fFilePath: string;
    fTargetLine: Integer;
    fStartLine: Integer;
    fLines: TArray<string>;
  end;

  TAppOptions = record
    fCommand: TCommandKind;
    fDprojPath: string;
    fPlatform: string;
    fConfig: string;
    fDelphiVersion: string;
    fBuildShowWarnings: Boolean;
    fBuildShowHints: Boolean;
    fBuildAi: Boolean;
    fBuildJson: Boolean;
    fBuildBackend: TBuildBackend;
    fBuildRunDfmCheck: Boolean;
    fDfmCheckFilter: string;
    fDfmCheckAll: Boolean;
    fDfmInspectPath: string;
    fDfmInspectFormat: string;
    fBuildTarget: string;
    fBuildMaxFindings: Integer;
    fBuildTimeoutSec: Integer;
    fBuildTestOutputDir: string;
    fHasBuildTestOutputDir: Boolean;
    fWebCoreCompilerPath: string;
    fHasWebCoreCompilerPath: Boolean;
    fWebCorePwaEnabled: Boolean;
    fHasWebCorePwaEnabled: Boolean;
    fBuildIgnoreWarnings: string;
    fHasBuildIgnoreWarnings: Boolean;
    fBuildIgnoreHints: string;
    fHasBuildIgnoreHints: Boolean;
    fOutKind: TOutputKind;
    fOutPath: string;
    fHasOutPath: Boolean;
    fHasOutKind: Boolean;
    fVerbose: Boolean;
    fSourceContextMode: TSourceContextMode;
    fHasSourceContextMode: Boolean;
    fSourceContextLines: Integer;
    fHasSourceContextLines: Boolean;
    fRsVarsPath: string;
    fHasRsVarsPath: Boolean;
    fEnvOptionsPath: string;
    fHasEnvOptionsPath: Boolean;
    fFixOutput: string;
    fHasFixOutput: Boolean;
    fFixIgnore: string;
    fHasFixIgnore: Boolean;
    fFixSettings: string;
    fHasFixSettings: Boolean;
    fFixSilent: Boolean;
    fHasFixSilent: Boolean;
    fFixXml: Boolean;
    fHasFixXml: Boolean;
    fFixCsv: Boolean;
    fHasFixCsv: Boolean;
    fRunFixInsight: Boolean;
    fExcludePathMasks: string;
    fHasExcludePathMasks: Boolean;
    fIgnoreWarningIds: string;
    fHasIgnoreWarningIds: Boolean;
    fRunPascalAnalyzer: Boolean;
    fPaPath: string;
    fHasPaPath: Boolean;
    fPaOutput: string;
    fHasPaOutput: Boolean;
    fPaArgs: string;
    fHasPaArgs: Boolean;
    fLogFile: string;
    fHasLogFile: Boolean;
    fLogTee: Boolean;
    fHasLogTee: Boolean;
    fAnalyzeOutPath: string;
    fHasAnalyzeOutPath: Boolean;
    fAnalyzeFiFormats: TReportFormatSet;
    fAnalyzeFixInsight: Boolean;
    fAnalyzePal: Boolean;
    fAnalyzeClean: Boolean;
    fAnalyzeWriteSummary: Boolean;
    fGlobalVarsFormat: TGlobalVarsFormat;
    fGlobalVarsOutputPath: string;
    fHasGlobalVarsOutputPath: Boolean;
    fGlobalVarsCachePath: string;
    fHasGlobalVarsCachePath: Boolean;
    fGlobalVarsRefresh: TGlobalVarsRefresh;
    fGlobalVarsUnusedOnly: Boolean;
    fGlobalVarsUnitFilter: string;
    fHasGlobalVarsUnitFilter: Boolean;
    fGlobalVarsNameFilter: string;
    fHasGlobalVarsNameFilter: Boolean;
    fGlobalVarsReadsOnly: Boolean;
    fGlobalVarsWritesOnly: Boolean;
    fDepsFormat: TDepsFormat;
    fDepsOutputPath: string;
    fHasDepsOutputPath: Boolean;
    fDepsUnitName: string;
    fHasDepsUnitName: Boolean;
    fDepsTopLimit: Integer;
    fUnitPath: string;
  end;

  TFixInsightExtraOptions = record
    fExePath: string;
    fOutput: string;
    fIgnore: string;
    fSettings: string;
    fSilent: Boolean;
    fXml: Boolean;
    fCsv: Boolean;
  end;

  TFixInsightIgnoreDefaults = record
    fWarnings: string;
  end;

  TReportFilterDefaults = record
    fExcludePathMasks: string;
  end;

  TPascalAnalyzerDefaults = record
    fPath: string;
    fOutput: string;
    fArgs: string;
  end;

  TFixInsightParams = record
    fProjectDpr: string;
    fFixInsightExe: string;
    fFixOutput: string;
    fFixIgnore: string;
    fFixSettings: string;
    fFixSilent: Boolean;
    fFixXml: Boolean;
    fFixCsv: Boolean;
    fDefines: TArray<string>;
    fUnitSearchPath: TArray<string>;
    fLibraryPath: TArray<string>;
    fUnitScopes: TArray<string>;
    fUnitAliases: TArray<string>;
    fDelphiVersion: string;
    fPlatform: string;
    fConfig: string;
    fLibrarySource: TPropertySource;
    fDefineSource: TPropertySource;
    fSearchPathSource: TPropertySource;
    fUnitScopesSource: TPropertySource;
    fUnitAliasesSource: TPropertySource;
  end;

implementation

end.
