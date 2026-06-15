unit Dak.Project.Semantics;

interface

uses
  DelphiAST.ProjectIndexer,
  Dak.Types;

function TryBuildProjectAnalysisContext(const aOptions: TAppOptions; out aContext: TProjectAnalysisContext;
  out aError: string): Boolean; overload;
function TryBuildProjectAnalysisContext(const aOptions: TAppOptions;
  const aRequirement: TProjectAnalysisContextRequirement; out aContext: TProjectAnalysisContext;
  out aError: string): Boolean; overload;
function CreateProjectAnalysisIndexer(const aDefines, aSearchPath: string): TProjectIndexer; overload;
function CreateProjectAnalysisIndexer(const aContext: TProjectAnalysisContext): TProjectIndexer; overload;

implementation

uses
  System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.SysUtils,
  DelphiSemantics.Api, DelphiSemantics.CompilerProfile,
  maxLogic.StrUtils,
  Dak.FixInsightSettings, Dak.Registry, Dak.RsVars, Dak.Utils;

function SplitList(const aValue: string): TArray<string>;
var
  lParts: TArray<string>;
  lPart: string;
  lList: TList<string>;
  i: Integer;
begin
  lList := TList<string>.Create;
  try
    lParts := aValue.Split([';']);
    for i := 0 to High(lParts) do
    begin
      lPart := Trim(lParts[i]);
      if lPart <> '' then
        lList.Add(lPart);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function ConcatDedup(const aFirst, aSecond: TArray<string>): TArray<string>;
var
  lSet: THashSet<string>;
  lList: TList<string>;
  lItem: string;
begin
  lSet := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  lList := TList<string>.Create;
  try
    for lItem in aFirst do
      if lSet.Add(lItem) then
        lList.Add(lItem);
    for lItem in aSecond do
      if lSet.Add(lItem) then
        lList.Add(lItem);
    Result := lList.ToArray;
  finally
    lList.Free;
    lSet.Free;
  end;
end;

function TargetCompilerDefinesText(const aPlatform: string): string;
begin
  Result := String.Join(';', TDelphiSemanticCompilerProfileBuilder.DefinesForPlatform(aPlatform));
end;

function SemanticEnvironmentProperties(const aEnvVars: TDictionary<string, string>):
  TArray<TDelphiSemanticProperty>;
var
  i: Integer;
  lPair: TPair<string, string>;
begin
  if aEnvVars = nil then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  SetLength(Result, aEnvVars.Count);
  i := 0;
  for lPair in aEnvVars do
  begin
    Result[i].Name := lPair.Key;
    Result[i].Value := lPair.Value;
    Inc(i);
  end;
end;

function SemanticApiOptions(const aOptions: TAppOptions; const aEnvVars: TDictionary<string, string>;
  const aSearchPaths: TArray<string>): TDelphiSemanticApiOptions;
begin
  Result := Default(TDelphiSemanticApiOptions);
  Result.Configuration := aOptions.fConfig;
  Result.Platform := aOptions.fPlatform;
  Result.DelphiVersion := aOptions.fDelphiVersion;
  Result.RsVarsPath := aOptions.fRsVarsPath;
  Result.EnvOptionsPath := aOptions.fEnvOptionsPath;
  Result.EnvironmentVariables := SemanticEnvironmentProperties(aEnvVars);
  Result.SearchPaths := aSearchPaths;
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

function TryBuildProjectAnalysisContext(const aOptions: TAppOptions; out aContext: TProjectAnalysisContext;
  out aError: string): Boolean;
begin
  Result := TryBuildProjectAnalysisContext(aOptions, TProjectAnalysisContextRequirement.AllowDegraded,
    aContext, aError);
end;

function TryBuildProjectAnalysisContext(const aOptions: TAppOptions;
  const aRequirement: TProjectAnalysisContextRequirement; out aContext: TProjectAnalysisContext;
  out aError: string): Boolean;
const
  cDefaultContextNote = 'Using project-directory-only parser context; Delphi IDE context could not be resolved.';
var
  lBuildError: string;
  lBuildOptions: TAppOptions;
  lDelphiVersion: string;
  lEnvVars: TDictionary<string, string>;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lParserSearchPath: string;
  lProjectDir: string;
  lProjectName: string;
  lProjectPath: string;
  lResult: TDelphiSemanticContextResult;
  lRsVarsEnvironment: TRsVarsEnvironment;
  lRsVarsEnvVars: TDictionary<string, string>;
  lSearchPaths: TArray<string>;

  function FinishContext: Boolean;
  begin
    Result := True;
    if (aRequirement = TProjectAnalysisContextRequirement.StrictSemantic) and
      (not aContext.HasDelphiContext) then
    begin
      if aContext.ContextNote <> '' then
        aError := aContext.ContextNote
      else
        aError := cDefaultContextNote;
      Exit(False);
    end;
  end;
begin
  Result := False;
  aError := '';
  aContext := Default(TProjectAnalysisContext);

  if not TryResolveDprojPath(aOptions.fDprojPath, lProjectPath, aError) then
  begin
    Exit(False);
  end;

  lProjectDir := TPath.GetDirectoryName(lProjectPath);
  lProjectName := TPath.GetFileNameWithoutExtension(lProjectPath);
  aContext := TProjectAnalysisContext.Create(lProjectPath, lProjectName,
    lProjectDir, '', nil, TargetCompilerDefinesText(aOptions.fPlatform),
    lProjectDir, nil, nil, TPath.Combine(TPath.Combine(lProjectDir, '.dak'),
      lProjectName), False, cDefaultContextNote);

  lBuildOptions := aOptions;
  lBuildOptions.fDprojPath := lProjectPath;
  lResult := TDelphiSemanticApi.LoadProjectContext(lProjectPath,
    SemanticApiOptions(lBuildOptions, nil, nil));
  if not lResult.Success then
  begin
    aError := FirstSemanticErrorMessage(lResult);
    if aError = '' then
      aError := 'Failed to load project context.';
    Exit(False);
  end;

  lSearchPaths := ConcatDedup(lResult.Project.SourceLookupPaths,
    TArray<string>.Create(lResult.Project.ProjectDirectory));
  lParserSearchPath := String.Join(';', lSearchPaths);
  if lParserSearchPath = '' then
    lParserSearchPath := lResult.Project.ProjectDirectory;
  aContext := TProjectAnalysisContext.Create(lResult.Project.ProjectFileName,
    lResult.Project.ProjectName, lResult.Project.ProjectDirectory,
    lResult.Project.MainSourceFileName, lResult.Project.SourceFileNames,
    String.Join(';', lResult.Project.Defines), lParserSearchPath,
    lResult.Project.UnitScopeNames, lResult.Project.UnitAliases,
    TPath.Combine(TPath.Combine(lResult.Project.ProjectDirectory, '.dak'),
      lResult.Project.ProjectName), False, cDefaultContextNote);

  lDelphiVersion := Trim(aOptions.fDelphiVersion);
  if (lDelphiVersion = '') and (not LoadDefaultDelphiVersion(lProjectPath, lDelphiVersion)) then
  begin
    Result := FinishContext;
    Exit;
  end;
  if (lDelphiVersion <> '') and (Pos('.', lDelphiVersion) = 0) then
  begin
    lDelphiVersion := lDelphiVersion + '.0';
  end;

  if not TryLoadRsVars(lDelphiVersion, aOptions.fRsVarsPath, nil, lRsVarsEnvironment, lBuildError) then
  begin
    Result := FinishContext;
    Exit;
  end;

  lRsVarsEnvVars := lRsVarsEnvironment.ToDictionary;
  try
    if not TryReadIdeConfig(lDelphiVersion, aOptions.fPlatform, aOptions.fEnvOptionsPath, lRsVarsEnvVars, lEnvVars,
      lLibraryPath, lLibrarySource, nil, lBuildError) then
    begin
      Result := FinishContext;
      Exit;
    end;

    lBuildOptions := aOptions;
    lBuildOptions.fDprojPath := lProjectPath;
    lBuildOptions.fDelphiVersion := lDelphiVersion;
    lSearchPaths := SplitList(lLibraryPath);
    lResult := TDelphiSemanticApi.LoadProjectContext(lProjectPath,
      SemanticApiOptions(lBuildOptions, lEnvVars, lSearchPaths));
    if lResult.Success then
    begin
      lSearchPaths := ConcatDedup(lResult.Project.SourceLookupPaths,
        TArray<string>.Create(lResult.Project.ProjectDirectory));
      lParserSearchPath := String.Join(';', lSearchPaths);
      if lParserSearchPath = '' then
        lParserSearchPath := lResult.Project.ProjectDirectory;
      aContext := TProjectAnalysisContext.Create(lResult.Project.ProjectFileName,
        lResult.Project.ProjectName, lResult.Project.ProjectDirectory,
        lResult.Project.MainSourceFileName, lResult.Project.SourceFileNames,
        String.Join(';', lResult.Project.Defines), lParserSearchPath,
        lResult.Project.UnitScopeNames, lResult.Project.UnitAliases,
        TPath.Combine(TPath.Combine(lResult.Project.ProjectDirectory, '.dak'),
          lResult.Project.ProjectName), True, '');
    end;
  finally
    lRsVarsEnvVars.Free;
    lEnvVars.Free;
  end;

  Result := FinishContext;
end;

function CreateProjectAnalysisIndexer(const aDefines, aSearchPath: string): TProjectIndexer;
begin
  Result := TProjectIndexer.Create;
  Result.Options := Result.Options - [piUseDefinesDefinedByCompiler];
  Result.Defines := aDefines;
  Result.SearchPath := aSearchPath;
end;

function CreateProjectAnalysisIndexer(const aContext: TProjectAnalysisContext): TProjectIndexer;
begin
  Result := CreateProjectAnalysisIndexer(aContext.ParserDefines, aContext.ParserSearchPath);
end;


end.
