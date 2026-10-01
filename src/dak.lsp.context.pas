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
    fEnvironmentBlock: string;
    fSourceLookup: TProjectSourceLookup;
    fParams: TFixInsightParams;
  end;

function TryBuildStrictLspContext(const aOptions: TAppOptions; out aContext: TLspContext; out aError: string): Boolean;
function TryDeleteLspContextFile(const aContext: TLspContext; out aError: string): Boolean;
function TryWriteLspContextFile(const aContext: TLspContext; out aError: string): Boolean;
// Resolves the compiler DLL for the settings "dllname". Returns '' when it is
// resolved, otherwise a named warning; aDllName is then '' and the settings
// omit "dllname", so the query still runs as before.
function ResolveLspCompilerDllForRequest(const aLspExePath, aPlatform: string; out aDllName: string): string;
// The two-output writers keep their original contract and omit "dllname"; the
// overloads with aCompilerDllName write it when it is not empty.
function TryWriteCanonicalLspSettingsFile(const aContext: TLspContext; out aSettingsFilePath: string;
  out aError: string): Boolean; overload;
function TryWriteCanonicalLspSettingsFile(const aContext: TLspContext; const aCompilerDllName: string;
  out aSettingsFilePath: string; out aError: string): Boolean; overload;
function TryWriteOfficialLspSettingsFile(const aContext: TLspContext; out aSettingsFilePath: string;
  out aError: string): Boolean; overload;
function TryWriteOfficialLspSettingsFile(const aContext: TLspContext; const aCompilerDllName: string;
  out aSettingsFilePath: string; out aError: string): Boolean; overload;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.JSON, System.StrUtils, System.SysUtils,
  DelphiSemantics.Lsp,
  Dak.Messages, Dak.Paths, Dak.Project.BuildParams, Dak.Project.SourceLookup, Dak.Registry, Dak.RsVars, Dak.Settings,
  Dak.Utils;

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

function IsCompilerDllName(const aFileName, aPrefix: string): Boolean;
var
  i: Integer;
  lSuffix: string;
begin
  // Exactly <prefix><3 digits>.dll, e.g. dcc64290.dll; dcc64290N.dll does not match.
  Result := StartsText(aPrefix, aFileName) and SameText(TPath.GetExtension(aFileName), '.dll');
  if not Result then
    Exit;
  lSuffix := Copy(TPath.GetFileNameWithoutExtension(aFileName), Length(aPrefix) + 1, MaxInt);
  Result := Length(lSuffix) = 3;
  for i := 1 to Length(lSuffix) do
    Result := Result and CharInSet(lSuffix[i], ['0'..'9']);
end;

function TryResolveLspCompilerDllName(const aLspExePath, aPlatform: string; out aDllName: string;
  out aError: string): Boolean;
var
  lBinDir: string;
  lFilePath: string;
  lMatches: TArray<string>;
  lPrefix: string;
begin
  // DelphiLSP loads the platform compiler named by the settings "dllname" from
  // its own folder; without it hover and most definitions return null. Only
  // Win32 and Win64 are proven against the installed server. On failure
  // aError is a reason fragment for the caller's warning.
  Result := False;
  aDllName := '';
  aError := '';
  if SameText(aPlatform, 'Win32') then
    lPrefix := 'dcc32'
  else if SameText(aPlatform, 'Win64') then
    lPrefix := 'dcc64'
  else
  begin
    aError := Format('platform %s is not supported; only Win32 and Win64 are', [aPlatform]);
    Exit(False);
  end;

  lBinDir := TPath.GetDirectoryName(aLspExePath);
  lMatches := [];
  if TDirectory.Exists(lBinDir) then
    for lFilePath in TDirectory.GetFiles(lBinDir, lPrefix + '*.dll') do
      if IsCompilerDllName(TPath.GetFileName(lFilePath), lPrefix) then
        lMatches := lMatches + [TPath.GetFileName(lFilePath)];
  if Length(lMatches) = 0 then
    aError := Format('no %sNNN.dll found beside %s', [lPrefix, aLspExePath])
  else if Length(lMatches) > 1 then
    aError := Format('more than one %sNNN.dll found beside %s: %s',
      [lPrefix, aLspExePath, String.Join(', ', lMatches)])
  else
  begin
    aDllName := lMatches[0];
    Result := True;
  end;
end;

function ResolveLspCompilerDllForRequest(const aLspExePath, aPlatform: string; out aDllName: string): string;
var
  lReason: string;
begin
  Result := '';
  if not TryResolveLspCompilerDllName(aLspExePath, aPlatform, aDllName, lReason) then
  begin
    // Only hover (and some definitions) depend on the compiler DLL.
    aDllName := '';
    Result := Format('DelphiLSP compiler DLL not resolved (%s); hover may return no content.', [lReason]);
  end;
end;

function TryWriteLspSettingsFile(const aContext: TLspContext; const aCompilerDllName, aFileName: string;
  out aSettingsFilePath: string; out aError: string): Boolean;
var
  lSettings: TDelphiSemanticLspSettings;
begin
  Result := False;
  aError := '';
  aSettingsFilePath := TPath.Combine(aContext.fDakLspRoot, aFileName);
  try
    if not ForceDirectories(aContext.fDakLspRoot) then
      raise Exception.Create('Failed to create directory: ' + aContext.fDakLspRoot);
    lSettings := TDelphiSemanticLspBoundary.BuildSettings(aContext.fMainSourcePath,
      aContext.fParams.fDefines, aContext.fParams.fUnitSearchPath, aContext.fParams.fLibraryPath,
      aContext.fParams.fUnitScopes, aContext.fParams.fUnitAliases);
    lSettings.CompilerDllName := aCompilerDllName;
    TFile.WriteAllText(aSettingsFilePath,
      TDelphiSemanticLspBoundary.BuildOfficialSettingsJson(lSettings), TEncoding.UTF8);
    Result := True;
  except
    on E: Exception do
    begin
      if FileExists(aSettingsFilePath) then
        System.SysUtils.DeleteFile(aSettingsFilePath);
      aError := Format(SLspContextArtifactsWriteFailed, [E.Message]);
    end;
  end;
end;

function TryWriteCanonicalLspSettingsFile(const aContext: TLspContext; out aSettingsFilePath: string;
  out aError: string): Boolean;
begin
  Result := TryWriteLspSettingsFile(aContext, '', 'settings.delphilsp.json', aSettingsFilePath, aError);
end;

function TryWriteOfficialLspSettingsFile(const aContext: TLspContext; out aSettingsFilePath: string;
  out aError: string): Boolean;
begin
  Result := TryWriteLspSettingsFile(aContext, '', 'probe.delphilsp.json', aSettingsFilePath, aError);
end;

function TryWriteCanonicalLspSettingsFile(const aContext: TLspContext; const aCompilerDllName: string;
  out aSettingsFilePath: string; out aError: string): Boolean;
begin
  Result := TryWriteLspSettingsFile(aContext, aCompilerDllName, 'settings.delphilsp.json', aSettingsFilePath, aError);
end;

function TryWriteOfficialLspSettingsFile(const aContext: TLspContext; const aCompilerDllName: string;
  out aSettingsFilePath: string; out aError: string): Boolean;
begin
  Result := TryWriteLspSettingsFile(aContext, aCompilerDllName, 'probe.delphilsp.json', aSettingsFilePath, aError);
end;

function TryPrepareLspWorkspace(var aContext: TLspContext; out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  try
    if not ForceDirectories(aContext.fDakLspRoot) then
      raise Exception.Create('Failed to create directory: ' + aContext.fDakLspRoot);
    aContext.fLogsDir := TPath.Combine(aContext.fDakLspRoot, 'logs');
    if not ForceDirectories(aContext.fLogsDir) then
      raise Exception.Create('Failed to create directory: ' + aContext.fLogsDir);
    aContext.fContextFilePath := TPath.Combine(aContext.fDakLspRoot, 'context.delphilsp.json');
    Result := True;
  except
    on E: Exception do
    begin
      aError := Format(SLspContextArtifactsWriteFailed, [E.Message]);
    end;
  end;
end;

function TryWriteLspContextFile(const aContext: TLspContext; out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  try
    if not ForceDirectories(aContext.fDakLspRoot) then
      raise Exception.Create('Failed to create directory: ' + aContext.fDakLspRoot);
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

function TryDeleteLspContextFile(const aContext: TLspContext; out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  try
    if (aContext.fContextFilePath <> '') and FileExists(aContext.fContextFilePath) then
    begin
      if not System.SysUtils.DeleteFile(aContext.fContextFilePath) then
        raise Exception.Create('Failed to delete file: ' + aContext.fContextFilePath);
    end;
    Result := True;
  except
    on E: Exception do
    begin
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
  lRsVarsEnvironment: TRsVarsEnvironment;
  lRsVarsEnvVars: TDictionary<string, string>;
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
  aContext.fDakProjectRoot := DakProjectRoot(aContext.fProjectDir, aContext.fProjectName);
  aContext.fDakLspRoot := DakProjectPath(aContext.fDakProjectRoot, ['lsp']);

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

  if not TryLoadRsVars(lNormalizedOptions.fDelphiVersion, lNormalizedOptions.fRsVarsPath, nil, lRsVarsEnvironment,
    aError) then
    Exit(False);

  lEnvVars := nil;
  lRsVarsEnvVars := lRsVarsEnvironment.ToDictionary;
  try
    if not TryReadIdeConfig(lNormalizedOptions.fDelphiVersion, lNormalizedOptions.fPlatform, lNormalizedOptions.fEnvOptionsPath,
      lRsVarsEnvVars, lEnvVars, lLibraryPath, lLibrarySource, nil, aError) then
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
    aContext.fEnvironmentBlock := lRsVarsEnvironment.ToEnvironmentBlock;
    aContext.fParams.fEnvironmentBlock := aContext.fEnvironmentBlock;
  finally
    lRsVarsEnvVars.Free;
    lEnvVars.Free;
  end;

  aContext.fDelphiVersion := lNormalizedOptions.fDelphiVersion;
  aContext.fLibraryPath := lLibraryPath;
  aContext.fLibrarySource := lLibrarySource;
  if aContext.fSourceLookup.fMainSourcePath <> '' then
    aContext.fMainSourcePath := aContext.fSourceLookup.fMainSourcePath
  else
    aContext.fMainSourcePath := aContext.fParams.fProjectDpr;
  if not TryPrepareLspWorkspace(aContext, aError) then
    Exit(False);
  Result := True;
end;

end.
