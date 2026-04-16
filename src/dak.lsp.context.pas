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
    fSourceLookup: TProjectSourceLookup;
    fParams: TFixInsightParams;
  end;

function TryBuildStrictLspContext(const aOptions: TAppOptions; out aContext: TLspContext; out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.SysUtils,
  Dak.FixInsightSettings, Dak.Project, Dak.Registry, Dak.RsVars, Dak.Utils;

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
  Result := True;
end;

end.
