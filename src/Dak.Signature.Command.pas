unit Dak.Signature.Command;

interface

uses
  DelphiSemantics.Refactor.Binding,
  Dak.Refactor.Artifact, Dak.Types;

function RunSignatureCommand(const aOptions: TAppOptions): Integer;
// DAK-385: creates the baseline build's log directory, .dak\<ProjectName>\signature\<run token>.
function TryCreateSignatureRunDirectory(const aDprojPath: string; out aDirectory: string;
  out aError: string): Boolean;
function TryFreshSignatureArtifact(const aOptions: TAppOptions; const aRequestJson: string;
  out aArtifact: TRefactoringArtifact; var aBound: TDelphiSemanticBoundPlanResult;
  out aReason: string): Boolean;

implementation

uses
  System.Classes, System.Diagnostics, System.IOUtils, System.JSON, System.SysUtils,
  DelphiSemantics.Cache, DelphiSemantics.Model, DelphiSemantics.ProjectContext,
  DelphiSemantics.ProjectSession, DelphiSemantics.Query,
  DelphiSemantics.Refactor.Plan, DelphiSemantics.Refactor.SignatureAlignment,
  DelphiSemantics.Resolve.TypeResolver, DelphiSemantics.SemanticGraph, DelphiSemantics.Snapshot,
  AutoFree, maxLogic.ioutils,
  Dak.Build.Runner, Dak.Build.Summary, Dak.Build.Types, Dak.ExitCodes,
  Dak.Paths, Dak.RsVars, Dak.Semantics.Session;

const
  // DAK-385: baseline build logs go to .dak\<ProjectName>\signature\<run token>\.
  cSignatureDirName = 'signature';

type
  TSignatureRequest = record
    fFileName: string;
    fOperation: string;
    fOffset: Integer;
  end;

procedure AddDiagnostic(const aReport: TJSONObject; const aReason, aMessage: string);
var
  lItem: TJSONObject;
begin
  lItem := TJSONObject.Create;
  aReport.GetValue<TJSONArray>('diagnostics').AddElement(lItem);
  lItem.AddPair('reason', aReason);
  lItem.AddPair('message', aMessage);
end;

function ParseSignatureRequest(const aOptions: TAppOptions; const aJson: string; out aRequest: TSignatureRequest;
  out aReason: string): Boolean;
var
  lJson: TJSONValue;
  lRoot, lDeclaration: TJSONObject;
  lValue: TJSONValue;
begin
  Result := False;
  aRequest := Default(TSignatureRequest);
  aReason := 'request.invalid';
  if (Length(aJson) = 0) or (Length(aJson) > 65536) then
    Exit;
  lJson := TJSONObject.ParseJSONValue(aJson);
  try
    if not (lJson is TJSONObject) then
      Exit;
    lRoot := lJson as TJSONObject;
    if lRoot.Count <> 3 then
      Exit;
    lValue := lRoot.GetValue('schemaVersion');
    if not (lValue is TJSONNumber) or (lValue.Value <> '1') then
      Exit;
    lValue := lRoot.GetValue('operation');
    if not (lValue is TJSONString) or
      ((lValue.Value <> 'compare') and (lValue.Value <> 'align')) then
    begin
      aReason := 'request.operation-unsupported';
      Exit;
    end;
    aRequest.fOperation := lValue.Value;
    lValue := lRoot.GetValue('declaration');
    if not (lValue is TJSONObject) then
      Exit;
    lDeclaration := lValue as TJSONObject;
    if lDeclaration.Count <> 2 then
      Exit;
    lValue := lDeclaration.GetValue('fileName');
    if not (lValue is TJSONString) or (Trim(lValue.Value) = '') then
      Exit;
    aRequest.fFileName := lValue.Value;
    if not TPath.IsPathRooted(aRequest.fFileName) then
      aRequest.fFileName := TPath.Combine(ExtractFilePath(ExpandFileName(aOptions.fDprojPath)),
        aRequest.fFileName);
    aRequest.fFileName := ExpandFileName(aRequest.fFileName);
    lValue := lDeclaration.GetValue('offset');
    Result := (lValue is TJSONNumber) and TryStrToInt(lValue.Value, aRequest.fOffset) and
      (aRequest.fOffset > 0);
    if Result then
      aReason := '';
  finally
    lJson.Free;
  end;
end;

function ReadRequest(const aOptions: TAppOptions; out aRequest: TSignatureRequest;
  out aReason: string): Boolean;
var
  g: TGarbos;
  lStream: TFileStream;
  lBytes, lRoundTrip: TBytes;
  lText: string;
begin
  Result := False;
  aRequest := Default(TSignatureRequest);
  aReason := 'request.invalid';
  GC(lStream, TFileStream.Create(aOptions.fRefactorRequestPath, fmOpenRead or fmShareDenyWrite), g);
  if (lStream.Size = 0) or (lStream.Size > 65536) then
    Exit;
  SetLength(lBytes, lStream.Size);
  lStream.ReadBuffer(lBytes[0], Length(lBytes));
  try
    lText := TEncoding.UTF8.GetString(lBytes);
  except
    // Invalid request bytes are a validation refusal, not an operation failure.
    on EEncodingError do
      Exit;
  end;
  lRoundTrip := TEncoding.UTF8.GetBytes(lText);
  if (Length(lRoundTrip) <> Length(lBytes)) or
    not CompareMem(@lBytes[0], @lRoundTrip[0], Length(lBytes)) then
    Exit;
  Result := ParseSignatureRequest(aOptions, lText.TrimLeft([#$FEFF]), aRequest, aReason);
end;

function SignatureRequestJson(const aRequest: TSignatureRequest): string;
var
  g: TGarbos;
  lRoot, lDeclaration: TJSONObject;
begin
  GC(lRoot, TJSONObject.Create, g);
  lRoot.AddPair('schemaVersion', TJSONNumber.Create(1));
  lRoot.AddPair('operation', aRequest.fOperation);
  lDeclaration := TJSONObject.Create;
  lRoot.AddPair('declaration', lDeclaration);
  lDeclaration.AddPair('fileName', aRequest.fFileName);
  lDeclaration.AddPair('offset', TJSONNumber.Create(aRequest.fOffset));
  Result := lRoot.ToJSON;
end;

function SemanticOptions(const aOptions: TAppOptions;
  out aSemanticOptions: TDelphiSemanticOptions; out aReason: string): Boolean;
var
  i: Integer;
  lEnvironment: TRsVarsEnvironment;
begin
  Result := TryLoadRsVars(aOptions.fDelphiVersion, aOptions.fRsVarsPath, nil, lEnvironment, aReason);
  if not Result then
    Exit;
  aSemanticOptions := BuildSemanticSessionOptions(aOptions.fDprojPath, aOptions.fConfig, aOptions.fPlatform,
    aOptions.fDelphiVersion, aOptions.fRsVarsPath, aOptions.fEnvOptionsPath, '');
  SetLength(aSemanticOptions.EnvironmentVariables, Length(lEnvironment.Variables));
  for i := 0 to High(lEnvironment.Variables) do
  begin
    aSemanticOptions.EnvironmentVariables[i].Name := lEnvironment.Variables[i].Name;
    aSemanticOptions.EnvironmentVariables[i].Value := lEnvironment.Variables[i].Value;
  end;
end;

function SessionModels(const aSession: TDelphiSemanticProjectSession): TArray<TDelphiSemanticUnitModel>;
var
  i: Integer;
  lCache: TDelphiSemanticCacheMetrics;
  lMilliseconds: Int64;
  lQuery: TDelphiSemanticSymbolQueryContext;
begin
  lQuery := aSession.BuildSymbolQueryContext(lCache, lMilliseconds);
  Result := nil;
  if lQuery.UnitModel.FileName = '' then
    Exit;
  SetLength(Result, Length(lQuery.IndexedUnitModels) + 1);
  Result[0] := lQuery.UnitModel;
  for i := 0 to High(lQuery.IndexedUnitModels) do
    Result[i + 1] := lQuery.IndexedUnitModels[i];
end;

function AddScope(const aSession: TDelphiSemanticProjectSession;
  const aModels: TArray<TDelphiSemanticUnitModel>; const aReport: TJSONObject): Boolean;
var
  lScope: TJSONObject;
  lRoots: TJSONArray;
  lModel: TDelphiSemanticUnitModel;
  lFileName: string;
  lFound: Boolean;
begin
  Result := (Length(aModels) > 0) and (Length(aSession.Diagnostics) = 0);
  lScope := aReport.GetValue<TJSONObject>('scope');
  lRoots := TJSONArray.Create;
  lScope.AddPair('analyzedRoots', lRoots);
  for lModel in aModels do
  begin
    lRoots.Add(lModel.FileName);
    if not lModel.Success or (lModel.ScopeModelStatus <> 'ast') or
      (lModel.RejectedDeclarationCount <> 0) or (Length(lModel.Diagnostics) > 0) then
      Result := False;
  end;
  for lFileName in aSession.Project.SourceFileNames do
  begin
    lFound := False;
    for lModel in aModels do
      if SameFileName(lFileName, lModel.FileName) then
        lFound := True;
    if not lFound then
      Result := False;
  end;
  if not Result then
    AddDiagnostic(aReport, 'scope.incomplete', 'Project context or source-model coverage is incomplete.');
end;

function SignatureJson(const aSignature: TDelphiSemanticProcedureSignature): TJSONObject;
var
  lParameters: TJSONArray;
  lParameter: TDelphiSemanticSignatureParameter;
  lItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('known', TJSONBool.Create(aSignature.Known));
  Result.AddPair('kind', aSignature.Kind);
  Result.AddPair('ofObject', TJSONBool.Create(aSignature.OfObject));
  Result.AddPair('callingConvention', aSignature.CallingConvention);
  Result.AddPair('returnType', aSignature.ReturnType);
  lParameters := TJSONArray.Create;
  Result.AddPair('parameters', lParameters);
  for lParameter in aSignature.Parameters do
  begin
    lItem := TJSONObject.Create;
    lParameters.AddElement(lItem);
    lItem.AddPair('name', lParameter.Name);
    lItem.AddPair('typeName', lParameter.TypeName);
    lItem.AddPair('modifier', lParameter.Modifier);
  end;
end;

procedure AddComparedSignatures(const aModels: TArray<TDelphiSemanticUnitModel>;
  const aRequest: TSignatureRequest; const aComparison: TDelphiSemanticAlignmentComparison;
  const aJson: TJSONObject);
var
  lModel: TDelphiSemanticUnitModel;
  lMember: TDelphiSemanticMember;
  lRoutine: TDelphiSemanticRoutine;
  lJson: TJSONObject;
begin
  for lModel in aModels do
    if SameFileName(lModel.FileName, aRequest.fFileName) then
    begin
      if (aComparison.DeclarationIndex >= 0) and (aComparison.DeclarationIndex < Length(lModel.Members)) then
      begin
        lMember := lModel.Members[aComparison.DeclarationIndex];
        lJson := SignatureJson(lMember.ProcedureSignature);
        aJson.AddPair('declaration', lJson);
        lJson.AddPair('name', lMember.Name);
        lJson.AddPair('ownerName', lMember.OwnerName);
        lJson.AddPair('line', TJSONNumber.Create(lMember.Line));
        lJson.AddPair('column', TJSONNumber.Create(lMember.Column));
      end;
      if (aComparison.ImplementationIndex >= 0) and
        (aComparison.ImplementationIndex < Length(lModel.Routines)) then
      begin
        lRoutine := lModel.Routines[aComparison.ImplementationIndex];
        lJson := SignatureJson(lRoutine.ProcedureSignature);
        aJson.AddPair('implementation', lJson);
        lJson.AddPair('name', lRoutine.Name);
        lJson.AddPair('ownerName', lRoutine.OwnerName);
        lJson.AddPair('line', TJSONNumber.Create(lRoutine.Line));
        lJson.AddPair('column', TJSONNumber.Create(lRoutine.Column));
      end;
      Exit;
    end;
end;

function CompareInSession(const aSession: TDelphiSemanticProjectSession;
  const aRequest: TSignatureRequest; const aReport: TJSONObject): string;
var
  lModels: TArray<TDelphiSemanticUnitModel>;
  lGraph: TDelphiSemanticSemanticGraph;
  lComparison: TDelphiSemanticAlignmentComparison;
  lJson: TJSONObject;
  lComplete: Boolean;
begin
  lModels := SessionModels(aSession);
  lComplete := AddScope(aSession, lModels, aReport);
  lGraph := TDelphiSemanticSemanticGraphBuilder.Build(aSession.Project, lModels);
  try
    lComparison := TDelphiSemanticSignatureAlignment.Compare(lModels,
      TDelphiSemanticTypeResolver.BuildIndex(lGraph), aRequest.fFileName, aRequest.fOffset);
  finally
    lGraph.Free;
  end;
  lJson := TJSONObject.Create;
  aReport.AddPair('comparison', lJson);
  lJson.AddPair('status', lComparison.Status);
  lJson.AddPair('reason', lComparison.Reason);
  lJson.AddPair('declarationIndex', TJSONNumber.Create(lComparison.DeclarationIndex));
  lJson.AddPair('implementationIndex', TJSONNumber.Create(lComparison.ImplementationIndex));
  AddComparedSignatures(lModels, aRequest, lComparison, lJson);
  Result := 'ok';
  if (lComparison.Status = 'unknown') or not lComplete then
  begin
    Result := 'incomplete';
    if lComparison.Reason <> '' then
      AddDiagnostic(aReport, lComparison.Reason, 'The selected declaration has no proven comparison.');
  end;
  aReport.GetValue<TJSONObject>('scope').AddPair('complete', TJSONBool.Create(Result = 'ok'));
end;

procedure AddSuggestedEdits(const aPlan: TSemanticRefactoringPlan; const aReport: TJSONObject);
var
  i: Integer;
  lEdits: TJSONArray;
  lEdit: TSemanticPlanEdit;
  lItem: TJSONObject;
begin
  lEdits := TJSONArray.Create;
  aReport.AddPair('suggestedEdits', lEdits);
  for i := 0 to aPlan.EditCount - 1 do
  begin
    lEdit := aPlan.Edits[i];
    lItem := TJSONObject.Create;
    lEdits.AddElement(lItem);
    lItem.AddPair('fileName', lEdit.FileName);
    lItem.AddPair('startLine', TJSONNumber.Create(lEdit.StartLine));
    lItem.AddPair('startColumn', TJSONNumber.Create(lEdit.StartColumn));
    lItem.AddPair('endLine', TJSONNumber.Create(lEdit.EndLine));
    lItem.AddPair('endColumn', TJSONNumber.Create(lEdit.EndColumn));
    lItem.AddPair('expectedText', lEdit.ExpectedText);
    lItem.AddPair('replacementText', lEdit.ReplacementText);
  end;
end;

function TryCreateSignatureRunDirectory(const aDprojPath: string; out aDirectory: string;
  out aError: string): Boolean;
begin
  // DAK-385: .dak\<ProjectName>\signature\<run token>, created exclusively (was a 38-character GUID).
  aDirectory := '';
  try
    Result := TryCreateDakRunDirectory(DakProjectPath(DakProjectRootForProjectPath(aDprojPath), [cSignatureDirName]),
      aDirectory, aError);
  except
    on E: Exception do
    begin
      // GetFullPath rejects an invalid project path; report it instead of raising out of a Try routine.
      aError := E.Message;
      Result := False;
    end;
  end;
end;

// aDirectoryError is set only when the log directory could not be created; the build then does not run.
function AddAlignmentBaseline(const aOptions: TAppOptions; const aReport: TJSONObject;
  out aDirectoryError: string): Boolean;
var
  lOptions: TAppOptions;
  lSummaryOptions: TBuildSummaryOptions;
  lSummary: TBuildSummary;
  lBuild, lCompiler: TJSONObject;
  lDirectory, lError: string;
  lExit: Integer;
  lTimer: TStopwatch;
begin
  lExit := -1;
  lError := '';
  lDirectory := '';
  aDirectoryError := '';
  Result := TryCreateSignatureRunDirectory(aOptions.fDprojPath, lDirectory, lError);
  if not Result then
    aDirectoryError := lError;
  lOptions := aOptions;
  lOptions.fBuildBackend := TBuildBackend.bbDelphi;
  lOptions.fBuildTarget := 'Rebuild';
  lOptions.fBuildQuiet := True;
  lOptions.fBuildAi := False;
  lOptions.fBuildJson := False;
  lOptions.fBuildDiagnosticsDir := lDirectory;
  lOptions.fBuildMaxFindings := 0;
  lTimer := TStopwatch.StartNew;
  // Without a log directory the build does not run; the report carries the directory error.
  if Result then
    Result := TryRunBuildInternal(lOptions, lExit, lError) and (lExit = 0);
  lTimer.Stop;
  lSummaryOptions := Default(TBuildSummaryOptions);
  lSummaryOptions.fProjectRoot := ExtractFilePath(ExpandFileName(aOptions.fDprojPath));
  lSummaryOptions.fIncludeWarnings := True;
  if lDirectory <> '' then
    lSummary := ParseBuildLogs(TPath.Combine(lDirectory, 'stdout.log'),
      TPath.Combine(lDirectory, 'stderr.log'), lSummaryOptions)
  else
    lSummary := Default(TBuildSummary);
  lSummary.fExitCode := lExit;
  if Result then
    lSummary.fStatus := 'success'
  else
    lSummary.fStatus := 'failed';
  lBuild := TJSONObject.Create;
  aReport.AddPair('buildVerification', lBuild);
  if Result then
    lBuild.AddPair('status', 'passed')
  else
    lBuild.AddPair('status', 'failed');
  lBuild.AddPair('error', lError);
  lBuild.AddPair('logDirectory', lDirectory);
  lCompiler := TJSONObject.ParseJSONValue(BuildSummaryAsJson(aOptions.fDprojPath,
    lOptions, lSummary, 'Rebuild', lTimer.ElapsedMilliseconds)) as TJSONObject;
  lBuild.AddPair('compiler', lCompiler);
end;

function PlanAlignmentInSession(const aSession: TDelphiSemanticProjectSession;
  const aRequest: TSignatureRequest): TDelphiSemanticBoundPlanResult;
var
  lModels: TArray<TDelphiSemanticUnitModel>;
  lGraph: TDelphiSemanticSemanticGraph;
  lSnapshot: TDelphiProjectSnapshot;
begin
  lModels := SessionModels(aSession);
  lSnapshot := aSession.BuildSnapshot;
  try
    lGraph := TDelphiSemanticSemanticGraphBuilder.Build(aSession.Project, lModels);
    try
      Result := TDelphiSemanticSignatureAlignment.PlanAlignment(lModels,
        TDelphiSemanticTypeResolver.BuildIndex(lGraph), lSnapshot,
        aRequest.fFileName, aRequest.fOffset);
    finally
      lGraph.Free;
    end;
  finally
    lSnapshot.Free;
  end;
end;

function TryFreshSignatureArtifact(const aOptions: TAppOptions; const aRequestJson: string;
  out aArtifact: TRefactoringArtifact; var aBound: TDelphiSemanticBoundPlanResult;
  out aReason: string): Boolean;
var
  g: TGarbos;
  lRequest: TSignatureRequest;
  lOptions: TDelphiSemanticOptions;
  lOpen: TDelphiSemanticProjectSessionResult;
begin
  Result := False;
  aArtifact := Default(TRefactoringArtifact);
  aBound := nil;
  if not ParseSignatureRequest(aOptions, aRequestJson, lRequest, aReason) then
    Exit;
  aReason := 'request.operation-unsupported';
  if lRequest.fOperation <> 'align' then
    Exit;
  if not SemanticOptions(aOptions, lOptions, aReason) then
    Exit;
  lOpen := TDelphiSemanticProjectSession.Open(lOptions);
  GC(lOpen.Session, g);
  aReason := 'context.open-failed';
  if not lOpen.Success or not Assigned(lOpen.Session) then
    Exit;
  aBound := PlanAlignmentInSession(lOpen.Session, lRequest);
  Result := TryCreateBoundRefactoringArtifact(aBound, SignatureRequestJson(lRequest), aArtifact, aReason);
end;

function PublishAlignmentArtifact(const aOptions: TAppOptions; const aRequest: TSignatureRequest;
  const aBound: TDelphiSemanticBoundPlanResult; const aReport: TJSONObject): Boolean;
var
  lArtifact: TRefactoringArtifact;
  lJson, lReason, lPath: string;
  lArtifacts: TJSONArray;
begin
  Result := TryCreateBoundRefactoringArtifact(aBound, SignatureRequestJson(aRequest), lArtifact, lReason) and
    TryWriteRefactoringArtifactJson(lArtifact, lJson, lReason);
  if not Result then
  begin
    AddDiagnostic(aReport, lReason, 'The alignment artifact could not be materialized.');
    Exit;
  end;
  lPath := TPath.GetFullPath(aOptions.fRefactorPlanOutPath);
  WriteNewRefactoringArtifact(lPath, lJson);
  lArtifacts := TJSONArray.Create;
  aReport.AddPair('artifacts', lArtifacts);
  lArtifacts.Add(lPath);
end;

function AlignmentStillMatches(const aOptions: TAppOptions; const aRequest: TSignatureRequest;
  const aBound: TDelphiSemanticBoundPlanResult): Boolean;
var
  lOptions: TDelphiSemanticOptions;
  lOpen: TDelphiSemanticProjectSessionResult;
  lFresh: TDelphiSemanticBoundPlanResult;
  lReason: string;
begin
  Result := False;
  if not SemanticOptions(aOptions, lOptions, lReason) then
    Exit;
  lOpen := TDelphiSemanticProjectSession.Open(lOptions);
  try
    if not lOpen.Success or not Assigned(lOpen.Session) then
      Exit;
    lFresh := PlanAlignmentInSession(lOpen.Session, aRequest);
    try
      // Bound fingerprints include observed source/include/project/model facts and exact edits.
      Result := Assigned(lFresh.Plan) and (lFresh.Status = aBound.Status) and
        (lFresh.ContextFingerprint = aBound.ContextFingerprint) and
        (lFresh.BindingFingerprint = aBound.BindingFingerprint);
    finally
      lFresh.Free;
    end;
  finally
    lOpen.Session.Free;
  end;
end;

function AlignInSession(const aOptions: TAppOptions; const aSession: TDelphiSemanticProjectSession;
  const aRequest: TSignatureRequest; const aReport: TJSONObject): string;
var
  lBound: TDelphiSemanticBoundPlanResult;
  lBaselinePassed: Boolean;
  lDirectoryError: string;
begin
  Result := 'incomplete';
  lBound := PlanAlignmentInSession(aSession, aRequest);
  try
    if not Assigned(lBound.Plan) or not (lBound.Status in
      [TSemanticPlanStatus.Complete, TSemanticPlanStatus.NoChange]) then
    begin
      AddDiagnostic(aReport, lBound.Reason, 'No complete alignment suggestion is available.');
      Exit;
    end;
    lBaselinePassed := AddAlignmentBaseline(aOptions, aReport, lDirectoryError);
    if not AlignmentStillMatches(aOptions, aRequest, lBound) then
    begin
      AddDiagnostic(aReport, 'build.inputs-changed',
        'The baseline build changed or invalidated the observed inputs; discard the original plan.');
      Exit('blocked');
    end;
    AddSuggestedEdits(lBound.Plan, aReport);
    if lBaselinePassed then
    begin
      if lBound.Status = TSemanticPlanStatus.NoChange then
        Result := 'no-change'
      else
        Result := 'suggestion';
      if aOptions.fRefactorPlanOutPath <> '' then
      begin
        if not PublishAlignmentArtifact(aOptions, aRequest, lBound, aReport) then
          Exit('blocked');
        if Result = 'suggestion' then
          Result := 'ok';
      end;
    end else if lDirectoryError <> '' then
    begin
      // DAK-385: the compiler never ran; name the directory failure instead of blaming the baseline.
      AddDiagnostic(aReport, 'build.baseline-failed',
        'The compiler baseline could not run; suggested edits are not applicable. ' + lDirectoryError);
      Result := 'repair-suggestion';
    end else begin
      AddDiagnostic(aReport, 'build.baseline-failed',
        'The compiler baseline failed; suggested edits are not applicable.');
      Result := 'repair-suggestion';
    end;
  finally
    lBound.Free;
  end;
end;

function InspectSignature(const aOptions: TAppOptions; const aReport: TJSONObject): string;
var
  lRequest: TSignatureRequest;
  lOptions: TDelphiSemanticOptions;
  lOpen: TDelphiSemanticProjectSessionResult;
  lReason: string;
  lSelection: TJSONObject;
begin
  Result := 'blocked';
  if not ReadRequest(aOptions, lRequest, lReason) then
  begin
    AddDiagnostic(aReport, lReason, 'Expected a versioned compare or align request with an explicit declaration.');
    Exit;
  end;
  if lRequest.fOperation = 'align' then
  begin
    aReport.RemovePair('operation').Free;
    aReport.AddPair('operation', 'signature.align-implementation');
  end;
  if (aOptions.fRefactorPlanOutPath <> '') and (lRequest.fOperation <> 'align') then
  begin
    AddDiagnostic(aReport, 'request.plan-requires-align', 'Only an alignment request can produce an artifact.');
    Exit;
  end;
  lSelection := TJSONObject.Create;
  aReport.AddPair('declaration', lSelection);
  lSelection.AddPair('fileName', lRequest.fFileName);
  lSelection.AddPair('offset', TJSONNumber.Create(lRequest.fOffset));
  if not SemanticOptions(aOptions, lOptions, lReason) then
  begin
    AddDiagnostic(aReport, 'context.environment-unavailable', lReason);
    Exit;
  end;
  lOpen := TDelphiSemanticProjectSession.Open(lOptions);
  try
    if not lOpen.Success or not Assigned(lOpen.Session) then
    begin
      AddDiagnostic(aReport, 'context.open-failed', SemanticSessionDiagnosticsText(lOpen.Diagnostics));
      Exit;
    end;
    aReport.AddPair('contextFingerprint', lOpen.Session.Project.ContextFingerprint);
    Result := CompareInSession(lOpen.Session, lRequest, aReport);
    if (Result = 'ok') and (lRequest.fOperation = 'align') then
      Result := AlignInSession(aOptions, lOpen.Session, lRequest, aReport);
  finally
    lOpen.Session.Free;
  end;
end;

procedure CompleteReport(const aReport: TJSONObject; const aStatus: string);
var
  lSummary, lBuild, lScope: TJSONObject;
  lArtifacts: TJSONArray;
begin
  aReport.AddPair('status', aStatus);
  if aReport.GetValue('contextFingerprint') = nil then
    aReport.AddPair('contextFingerprint', '');
  lScope := aReport.GetValue<TJSONObject>('scope');
  if (aStatus = 'blocked') or (aStatus = 'incomplete') then
    lScope.RemovePair('complete').Free;
  if lScope.GetValue('complete') = nil then
    lScope.AddPair('complete', TJSONBool.Create(False));
  if lScope.GetValue('analyzedRoots') = nil then
    lScope.AddPair('analyzedRoots', TJSONArray.Create);
  if aReport.GetValue('buildVerification') = nil then
  begin
    lBuild := TJSONObject.Create;
    aReport.AddPair('buildVerification', lBuild);
    lBuild.AddPair('status', 'not-run');
  end;
  lArtifacts := aReport.GetValue('artifacts') as TJSONArray;
  if lArtifacts = nil then
  begin
    lArtifacts := TJSONArray.Create;
    aReport.AddPair('artifacts', lArtifacts);
  end;
  aReport.AddPair('applicable', TJSONBool.Create((aStatus = 'ok') and (lArtifacts.Count > 0)));
  lSummary := TJSONObject.Create;
  aReport.AddPair('summary', lSummary);
  if aReport.GetValue('suggestedEdits') = nil then
    aReport.AddPair('suggestedEdits', TJSONArray.Create);
  lSummary.AddPair('editCount', TJSONNumber.Create(aReport.GetValue<TJSONArray>('suggestedEdits').Count));
  lSummary.AddPair('comparisonCount', TJSONNumber.Create(Ord(aReport.GetValue('comparison') <> nil)));
  lSummary.AddPair('diagnosticCount', TJSONNumber.Create(aReport.GetValue<TJSONArray>('diagnostics').Count));
  lSummary.AddPair('omittedResultCount', TJSONNumber.Create(0));
  if aReport.GetValue('artifacts') = nil then
    aReport.AddPair('artifacts', TJSONArray.Create);
end;

function RunSignatureCommand(const aOptions: TAppOptions): Integer;
var
  lReport: TJSONObject;
  lStatus: string;
begin
  Result := cExitRejectedResult;
  lReport := TJSONObject.Create;
  try
    lReport.AddPair('schemaVersion', TJSONNumber.Create(1));
    lReport.AddPair('operation', 'signature.compare');
    lReport.AddPair('project', ExpandFileName(aOptions.fDprojPath));
    lReport.AddPair('platform', aOptions.fPlatform);
    lReport.AddPair('config', aOptions.fConfig);
    lReport.AddPair('scope', TJSONObject.Create);
    lReport.AddPair('diagnostics', TJSONArray.Create);
    lStatus := 'blocked';
    try
      lStatus := InspectSignature(aOptions, lReport);
    except
      on E: Exception do
      begin
        // A managed function result may already have updated lStatus before
        // publication raises. Never retain that provisional success on error.
        lStatus := 'blocked';
        AddDiagnostic(lReport, 'signature.failed', E.Message);
      end;
    end;
    CompleteReport(lReport, lStatus);
    WriteLn(lReport.ToJSON);
    if (lStatus = 'ok') or (lStatus = 'no-change') then
      Result := cExitSuccess;
  finally
    lReport.Free;
  end;
end;

end.
