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
  Dak.Semantics.Session, Dak.Utils;

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
  lBuildOptions: TAppOptions;
  lContextNote: string;
  lHasDelphiContext: Boolean;
  lParserSearchPath: string;
  lProjectDir: string;
  lProjectName: string;
  lProjectPath: string;
  lResult: TDelphiSemanticContextResult;
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
    BuildSemanticApiOptions(lBuildOptions, nil, nil));
  if not lResult.Success then
  begin
    aError := FirstSemanticErrorMessage(lResult);
    if aError = '' then
      aError := 'Failed to load project context.';
    Exit(False);
  end;

  lSearchPaths := ConcatDedup(lResult.Project.SourceLookupPaths,
    [lResult.Project.ProjectDirectory]);
  lParserSearchPath := String.Join(';', lSearchPaths);
  if lParserSearchPath = '' then
    lParserSearchPath := lResult.Project.ProjectDirectory;

  lHasDelphiContext := Trim(aOptions.fDelphiVersion) <> '';
  if (Trim(aOptions.fRsVarsPath) <> '') and (not TFile.Exists(aOptions.fRsVarsPath)) then
    lHasDelphiContext := False;
  if lHasDelphiContext then
    lContextNote := ''
  else
    lContextNote := cDefaultContextNote;
  aContext := TProjectAnalysisContext.Create(lResult.Project.ProjectFileName,
    lResult.Project.ProjectName, lResult.Project.ProjectDirectory,
    lResult.Project.MainSourceFileName, lResult.Project.SourceFileNames,
    String.Join(';', lResult.Project.Defines), lParserSearchPath,
    lResult.Project.UnitScopeNames, lResult.Project.UnitAliases,
    TPath.Combine(TPath.Combine(lResult.Project.ProjectDirectory, '.dak'),
      lResult.Project.ProjectName), lHasDelphiContext, lContextNote);

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
