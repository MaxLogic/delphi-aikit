unit Dak.Project;

interface

uses
  System.Generics.Collections,
  DelphiAST.ProjectIndexer,
  Dak.Diagnostics, Dak.Types;

function TryBuildParams(const aOptions: TAppOptions; const aEnvVars: TDictionary<string, string>;
  const aLibraryPath: string; aLibrarySource: TPropertySource; aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aError: string; out aErrorCode: Integer): Boolean;
function TryBuildParamsFromProjectContext(const aOptions: TAppOptions; const aContext: TProjectAnalysisContext;
  const aEnvVars: TDictionary<string, string>; const aLibraryPath: string; aLibrarySource: TPropertySource;
  aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aError: string; out aErrorCode: Integer): Boolean;
function TryBuildProjectSourceLookup(const aDprojPath, aConfig, aPlatform, aDelphiVersion: string;
  const aEnvVars: TDictionary<string, string>; aDiagnostics: TDiagnostics; out aLookup: TProjectSourceLookup;
  out aError: string): Boolean;
function TryBuildProjectAnalysisContext(const aOptions: TAppOptions; out aContext: TProjectAnalysisContext;
  out aError: string): Boolean; overload;
function TryBuildProjectAnalysisContext(const aOptions: TAppOptions;
  const aRequirement: TProjectAnalysisContextRequirement; out aContext: TProjectAnalysisContext;
  out aError: string): Boolean; overload;
function CreateProjectAnalysisIndexer(const aDefines, aSearchPath: string): TProjectIndexer; overload;
function CreateProjectAnalysisIndexer(const aContext: TProjectAnalysisContext): TProjectIndexer; overload;

implementation

uses
  Dak.Project.BuildParams, Dak.Project.Semantics;

function TryBuildParams(const aOptions: TAppOptions; const aEnvVars: TDictionary<string, string>;
  const aLibraryPath: string; aLibrarySource: TPropertySource; aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aError: string; out aErrorCode: Integer): Boolean;
begin
  Result := Dak.Project.BuildParams.TryBuildParams(aOptions, aEnvVars, aLibraryPath, aLibrarySource,
    aDiagnostics, aParams, aError, aErrorCode);
end;

function TryBuildParamsFromProjectContext(const aOptions: TAppOptions; const aContext: TProjectAnalysisContext;
  const aEnvVars: TDictionary<string, string>; const aLibraryPath: string; aLibrarySource: TPropertySource;
  aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aError: string; out aErrorCode: Integer): Boolean;
begin
  Result := Dak.Project.BuildParams.TryBuildParamsFromProjectContext(aOptions, aContext, aEnvVars,
    aLibraryPath, aLibrarySource, aDiagnostics, aParams, aError, aErrorCode);
end;

function TryBuildProjectSourceLookup(const aDprojPath, aConfig, aPlatform, aDelphiVersion: string;
  const aEnvVars: TDictionary<string, string>; aDiagnostics: TDiagnostics; out aLookup: TProjectSourceLookup;
  out aError: string): Boolean;
begin
  Result := Dak.Project.BuildParams.TryBuildProjectSourceLookup(aDprojPath, aConfig, aPlatform,
    aDelphiVersion, aEnvVars, aDiagnostics, aLookup, aError);
end;

function TryBuildProjectAnalysisContext(const aOptions: TAppOptions; out aContext: TProjectAnalysisContext;
  out aError: string): Boolean;
begin
  Result := Dak.Project.Semantics.TryBuildProjectAnalysisContext(aOptions, aContext, aError);
end;

function TryBuildProjectAnalysisContext(const aOptions: TAppOptions;
  const aRequirement: TProjectAnalysisContextRequirement; out aContext: TProjectAnalysisContext;
  out aError: string): Boolean;
begin
  Result := Dak.Project.Semantics.TryBuildProjectAnalysisContext(aOptions, aRequirement, aContext, aError);
end;

function CreateProjectAnalysisIndexer(const aDefines, aSearchPath: string): TProjectIndexer;
begin
  Result := Dak.Project.Semantics.CreateProjectAnalysisIndexer(aDefines, aSearchPath);
end;

function CreateProjectAnalysisIndexer(const aContext: TProjectAnalysisContext): TProjectIndexer;
begin
  Result := Dak.Project.Semantics.CreateProjectAnalysisIndexer(aContext);
end;

end.