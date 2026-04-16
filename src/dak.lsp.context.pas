unit Dak.Lsp.Context;

interface

uses
  Dak.Types;

type
  TLspContext = record
    fProjectPath: string;
    fProjectName: string;
    fProjectDir: string;
    fMainSourcePath: string;
    fDelphiVersion: string;
    fLibraryPath: string;
    fLibrarySource: TPropertySource;
    fDakProjectRoot: string;
    fDakLspRoot: string;
    fContextFilePath: string;
    fLogsDir: string;
    fSourceLookup: TProjectSourceLookup;
    fParams: TFixInsightParams;
  end;

function TryBuildStrictLspContext(const aOptions: TAppOptions; out aContext: TLspContext; out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.JSON, System.SysUtils,
  Dak.FixInsightSettings, Dak.Messages, Dak.Project, Dak.Registry, Dak.RsVars, Dak.Utils;

function NormalizeDelphiVersion(const aValue: string): string;
begin
  Result := Trim(aValue);
  if (Result <> '') and (Pos('.', Result) = 0) then
    Result := Result + '.0';
end;

procedure ApplyLspDefaults(const aOptions: TAppOptions; out aNormalizedOptions: TAppOptions);
begin
  aNormalizedOptions := aOptions;
  if Trim(aNormalizedOptions.fPlatform) = '' then
    aNormalizedOptions.fPlatform := 'Win32';
  if Trim(aNormalizedOptions.fConfig) = '' then
    aNormalizedOptions.fConfig := 'Release';
end;

function PropertySourceText(aSource: TPropertySource): string;
begin
  case aSource of
    TPropertySource.psDproj:
      Result := 'dproj';
    TPropertySource.psOptset:
      Result := 'optset';
    TPropertySource.psRegistry:
      Result := 'registry';
    TPropertySource.psEnvOptions:
      Result := 'envoptions';
  else
    Result := 'unknown';
  end;
end;

procedure AddStringArray(aObject: TJSONObject; const aName: string; const aValues: TArray<string>);
var
  lArray: TJSONArray;
  lValue: string;
begin
  lArray := TJSONArray.Create;
  for lValue in aValues do
    lArray.Add(lValue);
  aObject.AddPair(aName, lArray);
end;

function BuildContextJson(const aContext: TLspContext): string;
var
  lCompiler: TJSONObject;
  lPaths: TJSONObject;
  lProject: TJSONObject;
  lRoot: TJSONObject;
  lWorkspace: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  try
    lProject := TJSONObject.Create;
    lProject.AddPair('dproj', aContext.fProjectPath);
    lProject.AddPair('dir', aContext.fProjectDir);
    lProject.AddPair('name', aContext.fProjectName);
    lProject.AddPair('mainSource', aContext.fMainSourcePath);
    lRoot.AddPair('project', lProject);

    lCompiler := TJSONObject.Create;
    lCompiler.AddPair('delphiVersion', aContext.fDelphiVersion);
    lCompiler.AddPair('config', aContext.fParams.fConfig);
    lCompiler.AddPair('platform', aContext.fParams.fPlatform);
    lCompiler.AddPair('librarySource', PropertySourceText(aContext.fLibrarySource));
    AddStringArray(lCompiler, 'defines', aContext.fParams.fDefines);
    lRoot.AddPair('compiler', lCompiler);

    lPaths := TJSONObject.Create;
    AddStringArray(lPaths, 'unitSearchPath', aContext.fParams.fUnitSearchPath);
    AddStringArray(lPaths, 'libraryPath', aContext.fParams.fLibraryPath);
    AddStringArray(lPaths, 'unitScopes', aContext.fParams.fUnitScopes);
    AddStringArray(lPaths, 'unitAliases', aContext.fParams.fUnitAliases);
    lRoot.AddPair('paths', lPaths);

    lWorkspace := TJSONObject.Create;
    lWorkspace.AddPair('root', aContext.fDakLspRoot);
    lWorkspace.AddPair('contextFile', aContext.fContextFilePath);
    lWorkspace.AddPair('logsDir', aContext.fLogsDir);
    lRoot.AddPair('workspace', lWorkspace);

    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

function TryWriteContextArtifacts(var aContext: TLspContext; out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  try
    ForceDirectories(aContext.fDakLspRoot);
    aContext.fLogsDir := TPath.Combine(aContext.fDakLspRoot, 'logs');
    ForceDirectories(aContext.fLogsDir);
    aContext.fContextFilePath := TPath.Combine(aContext.fDakLspRoot, 'context.delphilsp.json');
    TFile.WriteAllText(aContext.fContextFilePath, BuildContextJson(aContext), TEncoding.UTF8);
    Result := True;
  except
    on E: Exception do
    begin
      if (aContext.fContextFilePath <> '') and FileExists(aContext.fContextFilePath) then
        System.SysUtils.DeleteFile(aContext.fContextFilePath);
      aError := Format(SLspContextArtifactsWriteFailed, [E.Message]);
    end;
  end;
end;

function TryBuildStrictLspContext(const aOptions: TAppOptions; out aContext: TLspContext; out aError: string): Boolean;
var
  lEnvVars: TDictionary<string, string>;
  lErrorCode: Integer;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lNormalizedOptions: TAppOptions;
  lProjectPath: string;
begin
  Result := False;
  aError := '';
  aContext := Default(TLspContext);

  ApplyLspDefaults(aOptions, lNormalizedOptions);
  if not TryResolveDprojPath(lNormalizedOptions.fDprojPath, lProjectPath, aError) then
    Exit(False);

  aContext.fProjectPath := lProjectPath;
  aContext.fProjectDir := TPath.GetDirectoryName(lProjectPath);
  aContext.fProjectName := TPath.GetFileNameWithoutExtension(lProjectPath);
  aContext.fDakProjectRoot := TPath.Combine(TPath.Combine(aContext.fProjectDir, '.dak'), aContext.fProjectName);
  aContext.fDakLspRoot := TPath.Combine(aContext.fDakProjectRoot, 'lsp');

  lNormalizedOptions.fDprojPath := lProjectPath;
  lNormalizedOptions.fDelphiVersion := NormalizeDelphiVersion(lNormalizedOptions.fDelphiVersion);
  if lNormalizedOptions.fDelphiVersion = '' then
  begin
    if not LoadDefaultDelphiVersion(lProjectPath, lNormalizedOptions.fDelphiVersion) then
    begin
      aError := 'Failed to read default Delphi version from dak.ini.';
      Exit(False);
    end;
    lNormalizedOptions.fDelphiVersion := NormalizeDelphiVersion(lNormalizedOptions.fDelphiVersion);
  end;
  if lNormalizedOptions.fDelphiVersion = '' then
  begin
    aError := 'Delphi version is required. Pass --delphi <major.minor> or set [Build] DelphiVersion in dak.ini.';
    Exit(False);
  end;

  if not TryLoadRsVars(lNormalizedOptions.fDelphiVersion, lNormalizedOptions.fRsVarsPath, nil, aError) then
    Exit(False);

  lEnvVars := nil;
  try
    if not TryReadIdeConfig(lNormalizedOptions.fDelphiVersion, lNormalizedOptions.fPlatform, lNormalizedOptions.fEnvOptionsPath,
      lEnvVars, lLibraryPath, lLibrarySource, nil, aError) then
    begin
      Exit(False);
    end;

    if not TryBuildProjectSourceLookup(lProjectPath, lNormalizedOptions.fConfig, lNormalizedOptions.fPlatform,
      lNormalizedOptions.fDelphiVersion, lEnvVars, nil, aContext.fSourceLookup, aError) then
    begin
      Exit(False);
    end;

    if not TryBuildParams(lNormalizedOptions, lEnvVars, lLibraryPath, lLibrarySource, nil, aContext.fParams, aError,
      lErrorCode) then
    begin
      Exit(False);
    end;
  finally
    lEnvVars.Free;
  end;

  aContext.fDelphiVersion := lNormalizedOptions.fDelphiVersion;
  aContext.fLibraryPath := lLibraryPath;
  aContext.fLibrarySource := lLibrarySource;
  if aContext.fSourceLookup.fMainSourcePath <> '' then
    aContext.fMainSourcePath := aContext.fSourceLookup.fMainSourcePath
  else
    aContext.fMainSourcePath := aContext.fParams.fProjectDpr;
  if not TryWriteContextArtifacts(aContext, aError) then
    Exit(False);
  Result := True;
end;

end.
