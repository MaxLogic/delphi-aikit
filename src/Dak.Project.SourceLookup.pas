unit Dak.Project.SourceLookup;

interface

uses
  System.Generics.Collections,
  Dak.Diagnostics, Dak.Types;

function TryBuildProjectSourceLookup(const aDprojPath, aConfig, aPlatform, aDelphiVersion: string;
  const aEnvVars: TDictionary<string, string>; aDiagnostics: TDiagnostics; out aLookup: TProjectSourceLookup;
  out aError: string): Boolean;

implementation

uses
  DelphiSemantics.Api,
  Dak.Semantics.Session;

procedure AddSemanticDiagnostics(const aDiagnostics: TDiagnostics;
  const aResult: TDelphiSemanticContextResult);
var
  lDiagnostic: TDelphiSemanticDiagnostic;
begin
  if aDiagnostics = nil then
    Exit;

  for lDiagnostic in aResult.Diagnostics do
    if lDiagnostic.Message <> '' then
      aDiagnostics.AddWarning(lDiagnostic.Message);
end;

function FirstSemanticErrorMessage(const aResult: TDelphiSemanticContextResult): string;
var
  lDiagnostic: TDelphiSemanticDiagnostic;
begin
  for lDiagnostic in aResult.Diagnostics do
    if lDiagnostic.Severity = dsError then
      Exit(lDiagnostic.Message);

  Result := '';
end;

function TryBuildProjectSourceLookup(const aDprojPath, aConfig, aPlatform, aDelphiVersion: string;
  const aEnvVars: TDictionary<string, string>; aDiagnostics: TDiagnostics; out aLookup: TProjectSourceLookup;
  out aError: string): Boolean;
var
  lAppOptions: TAppOptions;
  lOptions: TDelphiSemanticApiOptions;
  lResult: TDelphiSemanticContextResult;
begin
  aError := '';
  aLookup := Default(TProjectSourceLookup);
  lAppOptions := Default(TAppOptions);
  lAppOptions.fDprojPath := aDprojPath;
  lAppOptions.fConfig := aConfig;
  lAppOptions.fPlatform := aPlatform;
  lAppOptions.fDelphiVersion := aDelphiVersion;
  lOptions := BuildSemanticApiOptions(lAppOptions, aEnvVars, nil);

  lResult := TDelphiSemanticApi.LoadProjectContext(aDprojPath, lOptions);
  AddSemanticDiagnostics(aDiagnostics, lResult);
  if not lResult.Success then
  begin
    aError := FirstSemanticErrorMessage(lResult);
    if aError = '' then
      aError := 'Failed to load project context.';
    Exit(False);
  end;

  aLookup.fProjectDproj := lResult.Project.ProjectFileName;
  aLookup.fProjectDir := lResult.Project.ProjectDirectory;
  aLookup.fMainSourcePath := lResult.Project.MainSourceFileName;
  aLookup.fSourceFileNames := lResult.Project.SourceFileNames;
  aLookup.fDefines := lResult.Project.Defines;
  aLookup.fSearchPaths := lResult.Project.SourceLookupPaths;
  Result := True;
end;

end.
