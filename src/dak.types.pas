unit Dak.Types;

interface

{$SCOPEDENUMS ON}

type
  TCommandKind = (ckResolve, ckAnalyzeProject, ckAnalyzeUnit, ckBuild, ckDfmCheck, ckDfmInspect, ckGlobalVars,
    ckDeps, ckLsp, ckRemoveWith, ckSymbolMap, ckFindUsages, ckRename, ckDeadCode);

  TOutputKind = (okIni, okXml, okBat);
  TBuildBackend = (bbAuto, bbDelphi, bbWebCore);

  TPropertySource = (psUnknown, psDproj, psOptset, psRegistry, psEnvOptions);

  TReportFormat = (rfText, rfXml, rfCsv);
  TReportFormatSet = set of TReportFormat;

  TGlobalVarsFormat = (gvfText, gvfJson);
  TGlobalVarsRefresh = (gvrAuto, gvrForce);
  TDepsFormat = (dfJson, dfText);
  TSourceContextMode = (scmAuto, scmOff, scmOn);
  TLspOperation = (loNone, loDefinition, loHover, loSymbols, loProbe);
  TLspFormat = (lfJson, lfText);
  TLspProbeMode = (lpmContextFile, lpmSettingsFile);
  TLspProbeModeSet = set of TLspProbeMode;
  TRemoveWithMode = (rwmScan, rwmPlan, rwmApply);
  TRemoveWithFormat = (rwfJson, rwfText);
  TRemoveWithTargetKind = (rwtNone, rwtUnit, rwtDir, rwtAll);
  TSymbolMapOperation = (smoNone, smoIndex, smoFindDefinition, smoFindReferences, smoSearchSymbols,
    smoDescribeSymbol, smoStats);
  TSymbolMapFormat = (smfJson, smfText);
  TSymbolMapRefresh = (smrAuto, smrForce);
  TRefactorFormat = (rffJson, rffText);

  TDiagnosticsDefaults = record
    fSourceContextMode: TSourceContextMode;
    fSourceContextLines: Integer;
  end;

  TProjectSourceLookup = record
    fProjectDproj: string;
    fProjectDir: string;
    fMainSourcePath: string;
    fSourceFileNames: TArray<string>;
    fDefines: TArray<string>;
    fSearchPaths: TArray<string>;
  end;

  TProjectAnalysisContextQuality = (pcqStrictSemantic, pcqDegradedProjectOnly);
  TProjectAnalysisContextRequirement = (AllowDegraded, StrictSemantic);

  TProjectAnalysisContext = record
  private
    fProjectPath: string;
    fProjectName: string;
    fProjectDir: string;
    fMainSourcePath: string;
    fSourceFileNames: TArray<string>;
    fParserDefines: string;
    fParserSearchPath: string;
    fUnitScopes: TArray<string>;
    fUnitAliases: TArray<string>;
    fDakProjectRoot: string;
    fHasDelphiContext: Boolean;
    fContextNote: string;
    function GetQuality: TProjectAnalysisContextQuality;
    function GetSourceFileNames: TArray<string>;
    function GetUnitAliases: TArray<string>;
    function GetUnitScopes: TArray<string>;
  public
    class function Create(const aProjectPath, aProjectName, aProjectDir,
      aMainSourcePath: string; const aSourceFileNames: TArray<string>;
      const aParserDefines, aParserSearchPath: string;
      const aUnitScopes, aUnitAliases: TArray<string>;
      const aDakProjectRoot: string; const aHasDelphiContext: Boolean;
      const aContextNote: string): TProjectAnalysisContext; static;
    function WithParserDefines(const aParserDefines: string): TProjectAnalysisContext;
    property ProjectPath: string read fProjectPath;
    property ProjectName: string read fProjectName;
    property ProjectDir: string read fProjectDir;
    property MainSourcePath: string read fMainSourcePath;
    property SourceFileNames: TArray<string> read GetSourceFileNames;
    property ParserDefines: string read fParserDefines;
    property ParserSearchPath: string read fParserSearchPath;
    property UnitScopes: TArray<string> read GetUnitScopes;
    property UnitAliases: TArray<string> read GetUnitAliases;
    property DakProjectRoot: string read fDakProjectRoot;
    property Quality: TProjectAnalysisContextQuality read GetQuality;
    property HasDelphiContext: Boolean read fHasDelphiContext;
    property ContextNote: string read fContextNote;
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
    fBuildQuiet: Boolean;
    fBuildBackend: TBuildBackend;
    fBuildRunDfmCheck: Boolean;
    fDfmCheckFilter: string;
    fDfmCheckAll: Boolean;
    fDfmInspectPath: string;
    fDfmInspectFormat: string;
    fBuildTarget: string;
    fBuildMaxFindings: Integer;
    fBuildTimeoutSec: Integer;
    fBuildDiagnosticsDir: string;
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
    fFixTimeoutSec: Integer;
    fHasFixTimeoutSec: Boolean;
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
    fPaTimeoutSec: Integer;
    fHasPaTimeoutSec: Boolean;
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
    fLspOperation: TLspOperation;
    fLspFormat: TLspFormat;
    fLspPath: string;
    fHasLspPath: Boolean;
    fLspFilePath: string;
    fLspLine: Integer;
    fLspCol: Integer;
    fLspQuery: string;
    fLspLimit: Integer;
    fHasLspLimit: Boolean;
    fLspProbeModes: TLspProbeModeSet;
    fLspShowInitOptions: Boolean;
    fHasLspShowInitOptions: Boolean;
    fRemoveWithMode: TRemoveWithMode;
    fRemoveWithFormat: TRemoveWithFormat;
    fRemoveWithTargetKind: TRemoveWithTargetKind;
    fRemoveWithUnitPath: string;
    fRemoveWithDirPath: string;
    fRemoveWithAll: Boolean;
    fRemoveWithOutputPath: string;
    fHasRemoveWithOutputPath: Boolean;
    fRemoveWithSemanticCachePath: string;
    fHasRemoveWithSemanticCachePath: Boolean;
    fRemoveWithSkipCompatibilityFacts: Boolean;
    fSymbolMapOperation: TSymbolMapOperation;
    fSymbolMapFormat: TSymbolMapFormat;
    fSymbolMapRefresh: TSymbolMapRefresh;
    fHasSymbolMapRefresh: Boolean;
    fSymbolMapUnitPath: string;
    fSymbolMapFilePath: string;
    fSymbolMapLine: Integer;
    fSymbolMapCol: Integer;
    fSymbolMapQuery: string;
    fSymbolMapSymbol: string;
    fSymbolMapOwner: string;
    fSymbolMapCacheRoot: string;
    fHasSymbolMapCacheRoot: Boolean;
    fSymbolMapLimit: Integer;
    fHasSymbolMapLimit: Boolean;
    fRefactorFormat: TRefactorFormat;
    fRefactorSymbol: string;
    fRefactorFilePath: string;
    fRefactorLine: Integer;
    fRefactorCol: Integer;
    fRefactorNewName: string;
    fRefactorApply: Boolean;
    fHasRefactorApply: Boolean;
    fRefactorSemanticCachePath: string;
    fHasRefactorSemanticCachePath: Boolean;
    fDeadCodeProfile: string;
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
    fTimeoutSec: Integer;
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
    fTimeoutSec: Integer;
  end;

  TFixInsightParams = record
    fEnvironmentBlock: string;
    fProjectDpr: string;
    fFixInsightExe: string;
    fFixOutput: string;
    fFixIgnore: string;
    fFixSettings: string;
    fFixSilent: Boolean;
    fFixXml: Boolean;
    fFixCsv: Boolean;
    fTimeoutSec: Integer;
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

function ProjectAnalysisContextQualityToText(
  const aQuality: TProjectAnalysisContextQuality): string;

implementation

function ProjectAnalysisContextQualityToText(
  const aQuality: TProjectAnalysisContextQuality): string;
begin
  case aQuality of
    TProjectAnalysisContextQuality.pcqStrictSemantic:
      Result := 'strict-semantic';
  else
    Result := 'degraded-project-only';
  end;
end;

class function TProjectAnalysisContext.Create(const aProjectPath, aProjectName,
  aProjectDir, aMainSourcePath: string; const aSourceFileNames: TArray<string>;
  const aParserDefines, aParserSearchPath: string;
  const aUnitScopes, aUnitAliases: TArray<string>; const aDakProjectRoot: string;
  const aHasDelphiContext: Boolean; const aContextNote: string):
  TProjectAnalysisContext;
begin
  Result.fProjectPath := aProjectPath;
  Result.fProjectName := aProjectName;
  Result.fProjectDir := aProjectDir;
  Result.fMainSourcePath := aMainSourcePath;
  Result.fSourceFileNames := Copy(aSourceFileNames);
  Result.fParserDefines := aParserDefines;
  Result.fParserSearchPath := aParserSearchPath;
  Result.fUnitScopes := Copy(aUnitScopes);
  Result.fUnitAliases := Copy(aUnitAliases);
  Result.fDakProjectRoot := aDakProjectRoot;
  Result.fHasDelphiContext := aHasDelphiContext;
  Result.fContextNote := aContextNote;
end;

function TProjectAnalysisContext.WithParserDefines(
  const aParserDefines: string): TProjectAnalysisContext;
begin
  Result := TProjectAnalysisContext.Create(fProjectPath, fProjectName,
    fProjectDir, fMainSourcePath, fSourceFileNames, aParserDefines,
    fParserSearchPath, fUnitScopes, fUnitAliases, fDakProjectRoot,
    fHasDelphiContext, fContextNote);
end;

function TProjectAnalysisContext.GetSourceFileNames: TArray<string>;
begin
  Result := Copy(fSourceFileNames);
end;

function TProjectAnalysisContext.GetQuality: TProjectAnalysisContextQuality;
begin
  if fHasDelphiContext then
    Result := TProjectAnalysisContextQuality.pcqStrictSemantic
  else
    Result := TProjectAnalysisContextQuality.pcqDegradedProjectOnly;
end;

function TProjectAnalysisContext.GetUnitAliases: TArray<string>;
begin
  Result := Copy(fUnitAliases);
end;

function TProjectAnalysisContext.GetUnitScopes: TArray<string>;
begin
  Result := Copy(fUnitScopes);
end;

end.
