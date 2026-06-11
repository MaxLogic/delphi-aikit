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
  Dak.Project;

function BuildProjectInfo(const aOptions: TAppOptions): TProjectInfo;
var
  lContext: TProjectAnalysisContext;
  lError: string;
begin
  if not TryBuildProjectAnalysisContext(aOptions, lContext, lError) then
    raise Exception.Create(lError);

  Result.ProjectPath := lContext.fProjectPath;
  Result.ProjectName := lContext.fProjectName;
  Result.MainSourcePath := lContext.fMainSourcePath;
  Result.ParserDefines := lContext.fParserDefines;
  Result.ParserSearchPath := lContext.fParserSearchPath;
  Result.UnitAliases := lContext.fUnitAliases;
  Result.UnitScopes := lContext.fUnitScopes;
  Result.OutputPath := TPath.Combine(lContext.fDakProjectRoot, 'global-vars');
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

function RenderGlobalVarsOutput(const aSymbols, aFilteredSymbols:
  TObjectList<TGlobalVarSymbol>; const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aOptions: TAppOptions): string;
begin
  if aOptions.fGlobalVarsFormat = TGlobalVarsFormat.gvfJson then
    Result := RenderJson(aSymbols, aFilteredSymbols, aAmbiguities, aOptions)
  else
    Result := RenderText(aSymbols, aFilteredSymbols, aAmbiguities, aOptions);
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
  lFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  lIdentity: TGlobalVarsSemanticIdentity;
  lOutputText: string;
  lProject: TProjectInfo;
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
  lSymbols := nil;
  lAmbiguities := nil;
  try
    if (aOptions.fGlobalVarsRefresh <> TGlobalVarsRefresh.gvrForce) and
      TryLoadCachedSymbols(lCacheFileName, lProject.ProjectPath, lIdentity.IdentityHash,
      lCacheSymbols, lCacheAmbiguities) then
    begin
      lSymbols := lCacheSymbols;
      lAmbiguities := lCacheAmbiguities;
    end else begin
      lAnalysis := AnalyzeGlobalVarsProject(lProject, aOptions);
      lSymbols := lAnalysis.Symbols;
      lAmbiguities := lAnalysis.Ambiguities;
      SaveCachedSymbols(lCacheFileName, lProject.ProjectPath, lAnalysis.IdentityHash,
        lAnalysis.CacheIdentities, lSymbols, lAmbiguities);
    end;

    lFilteredSymbols := BuildFilteredSymbols(lSymbols, aOptions);
    try
      lOutputText := RenderGlobalVarsOutput(lSymbols, lFilteredSymbols, lAmbiguities,
        aOptions);
    finally
      lFilteredSymbols.Free;
    end;
    WriteOutput(OutputFileName(lProject, aOptions), lOutputText);
  finally
    lCacheAmbiguities.Free;
    lCacheSymbols.Free;
    lAnalysis.Free;
  end;
end;

end.
