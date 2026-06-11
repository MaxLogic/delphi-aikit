unit Dak.SymbolMap.Context;

interface

uses
  Dak.Types;

const
  cSymbolMapCacheEnvVar = 'DAK_SYMBOL_MAP_CACHE_ROOT';
  cSymbolMapCacheDirectoryVersion = 'v2';

type
  TSymbolMapContext = record
    fProject: TProjectAnalysisContext;
    fConfig: string;
    fPlatform: string;
    fDelphiVersion: string;
    fHasCompilerParams: Boolean;
    fDefines: TArray<string>;
    fUnitSearchPath: TArray<string>;
    fLibraryPath: TArray<string>;
    fUnitScopes: TArray<string>;
    fUnitAliases: TArray<string>;
    fRtlSourceRoot: string;
    fCentralCacheRoot: string;
    fProjectCacheRoot: string;
  end;

function TryBuildSymbolMapContext(const aOptions: TAppOptions; out aContext: TSymbolMapContext;
  out aError: string): Boolean;
function ResolveSymbolMapCentralCacheRoot(const aOptions: TAppOptions): string;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.SysUtils,
  DelphiSemantics.CompilerProfile,
  Dak.FixInsightSettings, Dak.Project, Dak.Registry, Dak.RsVars;

function NormalizeDelphiVersion(const aValue: string): string;
begin
  Result := Trim(aValue);
  if (Result <> '') and (Pos('.', Result) = 0) then
    Result := Result + '.0';
end;

function NormalizeCacheRoot(const aRoot: string): string;
begin
  Result := Trim(aRoot);
  if Result = '' then
    Exit('');
  Result := TPath.GetFullPath(Result);
end;

function ResolveDefaultCentralCacheRoot: string;
var
  lBaseRoot: string;
begin
  lBaseRoot := Trim(GetEnvironmentVariable('LOCALAPPDATA'));
  if lBaseRoot <> '' then
    Exit(TPath.Combine(TPath.Combine(lBaseRoot, 'DelphiAIKit\symbol-map'), cSymbolMapCacheDirectoryVersion));

  lBaseRoot := Trim(GetEnvironmentVariable('USERPROFILE'));
  if lBaseRoot <> '' then
    Exit(TPath.Combine(TPath.Combine(lBaseRoot, '.dak\symbol-map'), cSymbolMapCacheDirectoryVersion));

  Result := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'DelphiAIKit\symbol-map'),
    cSymbolMapCacheDirectoryVersion);
end;

function ResolveSymbolMapCentralCacheRoot(const aOptions: TAppOptions): string;
var
  lEnvRoot: string;
begin
  if aOptions.fHasSymbolMapCacheRoot then
    Exit(NormalizeCacheRoot(aOptions.fSymbolMapCacheRoot));

  lEnvRoot := Trim(GetEnvironmentVariable(cSymbolMapCacheEnvVar));
  if lEnvRoot <> '' then
    Exit(NormalizeCacheRoot(lEnvRoot));

  Result := NormalizeCacheRoot(ResolveDefaultCentralCacheRoot);
end;

function ResolveDefaultRtlSourceRoot(const aDelphiVersion, aRsVarsPath: string): string;
begin
  Result := TDelphiSemanticCompilerProfileBuilder.ResolveRtlSourceRoot(
    NormalizeDelphiVersion(aDelphiVersion), aRsVarsPath);
end;

function SplitSemanticList(const aValue: string): TArray<string>;
var
  i: Integer;
  lItems: TList<string>;
  lPart: string;
  lParts: TArray<string>;
begin
  lItems := TList<string>.Create;
  try
    lParts := aValue.Split([';']);
    for i := 0 to High(lParts) do
    begin
      lPart := Trim(lParts[i]);
      if lPart <> '' then
        lItems.Add(lPart);
    end;
    Result := lItems.ToArray;
  finally
    lItems.Free;
  end;
end;

procedure TryPopulateCompilerParams(const aOptions: TAppOptions; var aContext: TSymbolMapContext);
var
  lEnvVars: TDictionary<string, string>;
  lError: string;
  lErrorCode: Integer;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lOptions: TAppOptions;
  lParams: TFixInsightParams;
begin
  lOptions := aOptions;
  lOptions.fDprojPath := aContext.fProject.fProjectPath;
  lOptions.fConfig := aContext.fConfig;
  lOptions.fPlatform := aContext.fPlatform;
  lOptions.fDelphiVersion := NormalizeDelphiVersion(lOptions.fDelphiVersion);
  if lOptions.fDelphiVersion = '' then
  begin
    if not LoadDefaultDelphiVersion(aContext.fProject.fProjectPath, lOptions.fDelphiVersion) then
      Exit;
    lOptions.fDelphiVersion := NormalizeDelphiVersion(lOptions.fDelphiVersion);
  end;
  if lOptions.fDelphiVersion = '' then
    Exit;

  aContext.fDelphiVersion := lOptions.fDelphiVersion;
  if not TryLoadRsVars(lOptions.fDelphiVersion, lOptions.fRsVarsPath, nil, lError) then
    Exit;
  aContext.fRtlSourceRoot := NormalizeCacheRoot(ResolveDefaultRtlSourceRoot(aContext.fDelphiVersion,
    lOptions.fRsVarsPath));

  lEnvVars := nil;
  try
    if not TryReadIdeConfig(lOptions.fDelphiVersion, lOptions.fPlatform, lOptions.fEnvOptionsPath, lEnvVars,
      lLibraryPath, lLibrarySource, nil, lError) then
      Exit;
    if not TryBuildParams(lOptions, lEnvVars, lLibraryPath, lLibrarySource, nil, lParams, lError, lErrorCode) then
      Exit;

    aContext.fHasCompilerParams := True;
    aContext.fLibraryPath := lParams.fLibraryPath;
  finally
    lEnvVars.Free;
  end;
end;

function TryBuildSymbolMapContext(const aOptions: TAppOptions; out aContext: TSymbolMapContext;
  out aError: string): Boolean;
var
  lOptions: TAppOptions;
begin
  Result := False;
  aError := '';
  aContext := Default(TSymbolMapContext);

  lOptions := aOptions;
  if Trim(lOptions.fPlatform) = '' then
    lOptions.fPlatform := 'Win32';
  if Trim(lOptions.fConfig) = '' then
    lOptions.fConfig := 'Release';

  if not TryBuildProjectAnalysisContext(lOptions, aContext.fProject, aError) then
    Exit(False);

  aContext.fConfig := lOptions.fConfig;
  aContext.fPlatform := lOptions.fPlatform;
  aContext.fDelphiVersion := NormalizeDelphiVersion(lOptions.fDelphiVersion);
  aContext.fRtlSourceRoot := NormalizeCacheRoot(ResolveDefaultRtlSourceRoot(aContext.fDelphiVersion,
    lOptions.fRsVarsPath));
  aContext.fDefines := SplitSemanticList(aContext.fProject.fParserDefines);
  aContext.fUnitSearchPath := SplitSemanticList(aContext.fProject.fParserSearchPath);
  aContext.fUnitScopes := aContext.fProject.fUnitScopes;
  aContext.fUnitAliases := aContext.fProject.fUnitAliases;
  aContext.fCentralCacheRoot := ResolveSymbolMapCentralCacheRoot(lOptions);
  aContext.fProjectCacheRoot := TPath.Combine(TPath.Combine(aContext.fProject.fDakProjectRoot, 'symbol-map'),
    cSymbolMapCacheDirectoryVersion);
  TryPopulateCompilerParams(lOptions, aContext);
  Result := True;
end;

end.
