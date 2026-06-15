unit Dak.GlobalVars;

interface

uses
  Dak.Types;

function RunGlobalVarsCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  Dak.GlobalVars.Cache,
  Dak.GlobalVars.Model,
  Dak.GlobalVars.Output,
  Dak.GlobalVars.Semantics,
  Dak.Project.Semantics;

function BuildProjectInfo(const aOptions: TAppOptions): TProjectInfo;
var
  lContext: TProjectAnalysisContext;
  lError: string;
begin
  if not TryBuildProjectAnalysisContext(aOptions, TProjectAnalysisContextRequirement.AllowDegraded,
    lContext, lError) then
    raise Exception.Create(lError);

  Result.ProjectPath := lContext.ProjectPath;
  Result.ProjectName := lContext.ProjectName;
  Result.MainSourcePath := lContext.MainSourcePath;
  Result.ContextMode := ProjectAnalysisContextQualityToText(lContext.Quality);
  Result.ContextNote := lContext.ContextNote;
  Result.ParserDefines := lContext.ParserDefines;
  Result.ParserSearchPath := lContext.ParserSearchPath;
  Result.UnitAliases := lContext.UnitAliases;
  Result.UnitScopes := lContext.UnitScopes;
  Result.OutputPath := TPath.Combine(lContext.DakProjectRoot, 'global-vars');
  Result.CachePath := TPath.Combine(Result.OutputPath, 'cache');
  Result.ReportsPath := TPath.Combine(Result.OutputPath, 'reports');
  Result.TempPath := TPath.Combine(Result.OutputPath, 'tmp');
end;

procedure EnsureProjectFolders(const aProject: TProjectInfo);
begin
  TDirectory.CreateDirectory(aProject.CachePath);
  TDirectory.CreateDirectory(aProject.ReportsPath);
  TDirectory.CreateDirectory(aProject.TempPath);
end;

function CacheFileName(const aProject: TProjectInfo; const aOptions: TAppOptions): string;
begin
  if aOptions.fHasGlobalVarsCachePath and (Trim(aOptions.fGlobalVarsCachePath) <> '') then
    Result := aOptions.fGlobalVarsCachePath
  else
    Result := TPath.Combine(aProject.CachePath, 'global-vars-cache.sqlite3');
end;

function OutputFileName(const aProject: TProjectInfo; const aOptions: TAppOptions): string;
begin
  if aOptions.fHasGlobalVarsOutputPath and (Trim(aOptions.fGlobalVarsOutputPath) <> '') then
    Result := aOptions.fGlobalVarsOutputPath
  else if aOptions.fGlobalVarsFormat = TGlobalVarsFormat.gvfJson then
    Result := TPath.Combine(aProject.ReportsPath, 'global-vars.json')
  else
    Result := TPath.Combine(aProject.ReportsPath, 'global-vars.txt');
end;

function RenderGlobalVarsOutput(const aFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aSummary: TGlobalVarsSummary;
  const aProject: TProjectInfo; const aOptions: TAppOptions): string;
begin
  if aOptions.fGlobalVarsFormat = TGlobalVarsFormat.gvfJson then
    Result := RenderJson(aFilteredSymbols, aAmbiguities, aSummary, aProject,
      aOptions)
  else
    Result := RenderText(aFilteredSymbols, aAmbiguities, aSummary, aProject,
      aOptions);
end;

function BuildCacheLoadFilter(const aOptions: TAppOptions): TGlobalVarsCacheLoadFilter;
begin
  Result := Default(TGlobalVarsCacheLoadFilter);
  Result.HasUnitFilter := aOptions.fHasGlobalVarsUnitFilter;
  Result.UnitFilter := aOptions.fGlobalVarsUnitFilter;
  Result.HasNameFilter := aOptions.fHasGlobalVarsNameFilter;
  Result.NameFilter := aOptions.fGlobalVarsNameFilter;
  Result.UnusedOnly := aOptions.fGlobalVarsUnusedOnly;
  Result.ReadsOnly := aOptions.fGlobalVarsReadsOnly;
  Result.WritesOnly := aOptions.fGlobalVarsWritesOnly;
end;

procedure WriteOutput(const aOutputPath, aOutputText: string);
begin
  if aOutputPath = '-' then
    WriteLn(aOutputText)
  else begin
    if TPath.GetDirectoryName(aOutputPath) <> '' then
      TDirectory.CreateDirectory(TPath.GetDirectoryName(aOutputPath));
    TFile.WriteAllText(aOutputPath, aOutputText, TEncoding.UTF8);
    WriteLn('Wrote: ' + aOutputPath);
  end;
end;

function RunGlobalVarsCommand(const aOptions: TAppOptions): Integer;
var
  lAnalysis: TGlobalVarsSemanticAnalysis;
  lAmbiguities: TList<TGlobalVarAmbiguity>;
  lCacheAmbiguities: TList<TGlobalVarAmbiguity>;
  lCacheFileName: string;
  lCacheSymbols: TObjectList<TGlobalVarSymbol>;
  lFilteredAmbiguities: TList<TGlobalVarAmbiguity>;
  lFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  lIdentity: TGlobalVarsSemanticIdentity;
  lOutputText: string;
  lProject: TProjectInfo;
  lSummary: TGlobalVarsSummary;
  lSymbols: TObjectList<TGlobalVarSymbol>;
begin
  Result := 0;
  lProject := BuildProjectInfo(aOptions);
  EnsureProjectFolders(lProject);
  lCacheFileName := CacheFileName(lProject, aOptions);
  lIdentity := BuildGlobalVarsProjectIdentity(lProject, aOptions);
  lAnalysis := nil;
  lCacheSymbols := nil;
  lCacheAmbiguities := nil;
  lFilteredSymbols := nil;
  lFilteredAmbiguities := nil;
  lSymbols := nil;
  lAmbiguities := nil;
  try
    if (aOptions.fGlobalVarsRefresh <> TGlobalVarsRefresh.gvrForce) and
      TryLoadCachedSymbols(lCacheFileName, lProject.ProjectPath, lIdentity.IdentityHash,
      BuildCacheLoadFilter(aOptions), lCacheSymbols, lCacheAmbiguities, lSummary) then
    begin
      lSymbols := lCacheSymbols;
      lAmbiguities := lCacheAmbiguities;
      lFilteredSymbols := lSymbols;
      lFilteredAmbiguities := lAmbiguities;
    end else begin
      lAnalysis := AnalyzeGlobalVarsProject(lProject, aOptions);
      lSymbols := lAnalysis.Symbols;
      lAmbiguities := lAnalysis.Ambiguities;
      SaveCachedSymbols(lCacheFileName, lProject.ProjectPath, lAnalysis.IdentityHash,
        lAnalysis.CacheIdentities, lSymbols, lAmbiguities);
      lFilteredSymbols := BuildFilteredSymbols(lSymbols, aOptions);
      lFilteredAmbiguities := BuildFilteredAmbiguities(lAmbiguities, aOptions);
      lSummary := BuildGlobalVarsSummary(lSymbols, lAmbiguities, lFilteredSymbols.Count,
        lFilteredAmbiguities.Count);
    end;

    lOutputText := RenderGlobalVarsOutput(lFilteredSymbols, lFilteredAmbiguities, lSummary,
      lProject, aOptions);
    WriteOutput(OutputFileName(lProject, aOptions), lOutputText);
  finally
    if lFilteredAmbiguities <> lAmbiguities then
      lFilteredAmbiguities.Free;
    if lFilteredSymbols <> lSymbols then
      lFilteredSymbols.Free;
    lCacheAmbiguities.Free;
    lCacheSymbols.Free;
    lAnalysis.Free;
  end;
end;

end.
