unit Dak.Refactor.ApplyCommand;

interface

uses System.SysUtils, Dak.Types;

function RunRefactorApplyCommand(const aOptions: TAppOptions): Integer;
function RunUsesPlanCommand(const aOptions: TAppOptions): Integer;
{$IFDEF DAK_TRANSACTION_TEST_ACCESS}
procedure WriteNewRefactoringArtifactForTest(const aPath, aJson: string; const aAfterCreate: TProc);
{$ENDIF}

implementation

uses
  System.Classes, System.IOUtils, System.JSON,
  DelphiSemantics.ProjectContext, DelphiSemantics.ProjectSession, DelphiSemantics.Refactor.Binding,
  DelphiSemantics.Refactor.Plan, DelphiSemantics.Refactor.UsesPlanner,
  DelphiSemantics.Snapshot, DelphiSemantics.Snapshot.ContextEvidence,
  Dak.ExitCodes, Dak.Refactor.Artifact, Dak.Refactor.Transaction,
  Dak.RsVars, Dak.Semantics.Session, Dak.Signature.Command;

const
  cSuggestImportsOperation = 'uses.suggest-explicit-import-candidates';

procedure AddImportSuggestionFacts(const aReport: TJSONObject;
  const aBinding: TDelphiSemanticBoundPlanResult; const aPlanning: TDelphiSemanticUsesPlanningResult);
var
  lCandidates, lRoots: TJSONArray;
  lScope, lSummary: TJSONObject;
  lName, lClassification: string;
  lComplete: Boolean;
begin
  lComplete := Assigned(aPlanning.Plan) and (aPlanning.Plan.Status = TSemanticPlanStatus.NoChange);
  lClassification := 'unknown';
  if aPlanning.Classification = TDelphiSemanticUsesClassification.ucExplicitImportCandidate then
    lClassification := 'unique-explicit-import-candidate'
  else if aPlanning.Classification = TDelphiSemanticUsesClassification.ucAmbiguousExplicitImportCandidate then
    lClassification := 'ambiguous-explicit-import-candidates'
  else if aPlanning.Classification = TDelphiSemanticUsesClassification.ucUnsupportedShape then
    lClassification := 'unsupported-shape'
  else if aPlanning.Classification = TDelphiSemanticUsesClassification.ucIncompleteScope then
    lClassification := 'incomplete-scope';
  aReport.AddPair('classification', lClassification);
  aReport.AddPair('contextFingerprint', aBinding.ContextFingerprint);
  lCandidates := TJSONArray.Create;
  aReport.AddPair('candidateUnitNames', lCandidates);
  for lName in aPlanning.CandidateUnitNames do
    lCandidates.Add(lName);
  lScope := TJSONObject.Create;
  aReport.AddPair('scope', lScope);
  lScope.AddPair('complete', TJSONBool.Create(lComplete));
  lRoots := TJSONArray.Create;
  lScope.AddPair('analyzedRoots', lRoots);
  for lName in aBinding.AnalyzedRootFileNames do
    lRoots.Add(lName);
  lSummary := TJSONObject.Create;
  aReport.AddPair('summary', lSummary);
  lSummary.AddPair('candidateCount', TJSONNumber.Create(lCandidates.Count));
  lSummary.AddPair('editCount', TJSONNumber.Create(0));
  lSummary.AddPair('omittedResultCount', TJSONNumber.Create(0));
end;

procedure CompleteImportSuggestionReport(const aReport: TJSONObject; const aReason: string);
var
  lScope, lSummary, lDiagnostic: TJSONObject;
  lDiagnostics: TJSONArray;
begin
  if aReport.GetValue('contextFingerprint') = nil then
    aReport.AddPair('contextFingerprint', '');
  if aReport.GetValue('classification') = nil then
    aReport.AddPair('classification', 'unknown');
  if aReport.GetValue('candidateUnitNames') = nil then
    aReport.AddPair('candidateUnitNames', TJSONArray.Create);
  if aReport.GetValue('scope') = nil then
  begin
    lScope := TJSONObject.Create;
    aReport.AddPair('scope', lScope);
    lScope.AddPair('complete', TJSONBool.Create(False));
    lScope.AddPair('analyzedRoots', TJSONArray.Create);
  end;
  if aReport.GetValue('summary') = nil then
  begin
    lSummary := TJSONObject.Create;
    aReport.AddPair('summary', lSummary);
    lSummary.AddPair('candidateCount', TJSONNumber.Create(0));
    lSummary.AddPair('editCount', TJSONNumber.Create(0));
    lSummary.AddPair('omittedResultCount', TJSONNumber.Create(0));
  end;
  lDiagnostics := TJSONArray.Create;
  aReport.AddPair('diagnostics', lDiagnostics);
  if aReason <> '' then
  begin
    lDiagnostic := TJSONObject.Create;
    lDiagnostics.AddElement(lDiagnostic);
    lDiagnostic.AddPair('reasonCode', aReason);
  end;
  aReport.GetValue<TJSONObject>('summary').AddPair('diagnosticCount', TJSONNumber.Create(lDiagnostics.Count));
end;

function FreshUsesPlan(const aOptions: TAppOptions; const aOperation, aRequestJson: string;
  out aFresh: TRefactoringArtifact; var aBound: TDelphiSemanticBoundPlanResult;
  out aReason: string; const aAnalysis: TJSONObject = nil): Boolean;
var
  i: Integer;
  lConsumer: string;
  lExtension: TObject;
  lInitial: TDelphiSemanticBoundPlanResult;
  lJson: TJSONValue;
  lOpen: TDelphiSemanticProjectSessionResult;
  lPlanning: TDelphiSemanticUsesPlanningResult;
  lRequest: TDelphiSemanticPlanBindingRequest;
  lEnvironment: TRsVarsEnvironment;
  lOptions: TDelphiSemanticOptions;
  lSnapshot: TDelphiProjectSnapshot;
  lUnit: string;
  lSelectorField: string;
begin
  Result := False;
  aBound := nil;
  aFresh := Default(TRefactoringArtifact);
  aReason := 'operation.verifier-unavailable';
  if (aOperation <> 'uses.remove-implementation-import') and
    ((aOperation <> cSuggestImportsOperation) or not Assigned(aAnalysis)) then
    Exit;
  lSelectorField := 'unitName';
  if aOperation = cSuggestImportsOperation then
    lSelectorField := 'identifier';
  aReason := 'request.invalid';
  lJson := TJSONObject.ParseJSONValue(aRequestJson);
  try
    if not (lJson is TJSONObject) or (TJSONObject(lJson).Count <> 2) then
      Exit;
    if not TJSONObject(lJson).TryGetValue<string>('consumerFileName', lConsumer) or
      not TJSONObject(lJson).TryGetValue<string>(lSelectorField, lUnit) or
      (Trim(lConsumer) = '') or (Trim(lUnit) = '') then
      Exit;
  finally
    lJson.Free;
  end;
  lOptions := BuildSemanticSessionOptions(
    aOptions.fDprojPath, aOptions.fConfig, aOptions.fPlatform,
    aOptions.fDelphiVersion, aOptions.fRsVarsPath, aOptions.fEnvOptionsPath, '');
  if not TryLoadRsVars(aOptions.fDelphiVersion, aOptions.fRsVarsPath, nil, lEnvironment, aReason) then
    Exit;
  SetLength(lOptions.EnvironmentVariables, Length(lEnvironment.Variables));
  for i := 0 to High(lEnvironment.Variables) do
  begin
    lOptions.EnvironmentVariables[i].Name := lEnvironment.Variables[i].Name;
    lOptions.EnvironmentVariables[i].Value := lEnvironment.Variables[i].Value;
  end;
  lOpen := TDelphiSemanticProjectSession.Open(lOptions);
  try
    aReason := 'context.open-failed';
    if not lOpen.Success or not Assigned(lOpen.Session) then
      Exit;
    lSnapshot := lOpen.Session.BuildSnapshot;
    try
      aReason := 'context.evidence-missing';
      if not Assigned(lSnapshot) or not lSnapshot.TryGetExtension(
        cDelphiSemanticContextEvidenceExtensionName, lExtension) or
        not (lExtension is TDelphiSemanticContextEvidenceExtension) then
        Exit;
      lRequest := Default(TDelphiSemanticPlanBindingRequest);
      lRequest.OperationIdentity := aOperation;
      lRequest.SelectedConfigurationIdentities :=
        [TDelphiSemanticContextEvidenceExtension(lExtension).ProjectConfigurationIdentity];
      lRequest.RequiredAnalysisKinds := [pakBodyAnalysis, pakReferenceExtraction];
      lRequest.Status := TSemanticPlanStatus.NoChange;
      lInitial := TDelphiSemanticPlanBinder.Bind(lSnapshot, lRequest);
      try
        aReason := lInitial.Reason;
        if lInitial.Status <> TSemanticPlanStatus.NoChange then
        begin
          if aReason = 'binding.project-context-diagnostic' then
            aReason := aReason + ': ' + SemanticSessionDiagnosticsText(
              TDelphiSemanticContextEvidenceExtension(lExtension).ProjectDiagnostics);
          Exit;
        end;
        if aOperation = cSuggestImportsOperation then
          lPlanning := TDelphiSemanticUsesPlanner.SuggestExplicitImportCandidates(
            lSnapshot, lInitial, lConsumer, lUnit)
        else
          lPlanning := TDelphiSemanticUsesPlanner.PlanRemoveImplementationImport(
            lSnapshot, lInitial, lConsumer, lUnit);
        try
          aReason := lPlanning.Reason;
          if aOperation = cSuggestImportsOperation then
          begin
            AddImportSuggestionFacts(aAnalysis, lInitial, lPlanning);
            // Discovery is not an edit verifier and cannot produce an apply artifact.
            Exit(Assigned(lPlanning.Plan) and (lPlanning.Plan.Status = TSemanticPlanStatus.NoChange));
          end;
          if not Assigned(lPlanning.Plan) or not (lPlanning.Plan.Status in
            [TSemanticPlanStatus.Complete, TSemanticPlanStatus.NoChange]) then
            Exit;
          lRequest.Status := lPlanning.Plan.Status;
          SetLength(lRequest.Edits, lPlanning.Plan.EditCount);
          for i := 0 to High(lRequest.Edits) do
            lRequest.Edits[i] := lPlanning.Plan.Edits[i];
          aBound := TDelphiSemanticPlanBinder.Bind(lSnapshot, lRequest);
          aReason := aBound.Reason;
          if not Assigned(aBound.Plan) or not (aBound.Status in
            [TSemanticPlanStatus.Complete, TSemanticPlanStatus.NoChange]) then
            Exit;
          Result := TryCreateBoundRefactoringArtifact(aBound, aRequestJson, aFresh, aReason);
        finally
          lPlanning.Plan.Free;
        end;
      finally
        lInitial.Free;
      end;
    finally
      lSnapshot.Free;
    end;
  finally
    lOpen.Session.Free;
  end;
end;

function FreshFeaturePlan(const aOptions: TAppOptions; const aSaved: TRefactoringArtifact;
  out aFresh: TRefactoringArtifact; var aBound: TDelphiSemanticBoundPlanResult;
  out aReason: string): Boolean;
begin
  if aSaved.Operation = 'signature.align-implementation' then
    Result := TryFreshSignatureArtifact(aOptions, aSaved.RequestJson, aFresh, aBound, aReason)
  else
    Result := FreshUsesPlan(aOptions, aSaved.Operation, aSaved.RequestJson, aFresh, aBound, aReason);
end;

function RunRefactorApplyCommand(const aOptions: TAppOptions): Integer;
var
  lBound: TDelphiSemanticBoundPlanResult;
  lFresh: TRefactoringArtifact;
  lJournalPath: string;
  lJson: TJSONObject;
  lReason: string;
  lSaved: TRefactoringArtifact;
  lStatus: string;
  lTransaction: TRefactoringTransactionResult;
begin
  Result := cExitRejectedResult;
  lStatus := 'blocked';
  lBound := nil;
  lJournalPath := '';
  try
    try
      if TryReadRefactoringArtifact(aOptions.fRefactorApplyPlanPath, lSaved, lReason) and
        FreshFeaturePlan(aOptions, lSaved, lFresh, lBound, lReason) and
        RefactoringArtifactsMatch(lSaved, lFresh, lReason) then
      begin
        if ApplyRefactoringTransaction(aOptions, lBound.Plan,
          TPath.GetDirectoryName(TPath.GetFullPath(aOptions.fDprojPath)), lTransaction) then
          Result := 0;
        lJournalPath := lTransaction.JournalPath;
        lStatus := lTransaction.Status;
        lReason := lTransaction.Error;
      end;
    except
      on E: Exception do
      begin
        // Source/context failures are refusals; saved edits never bypass replanning.
        lReason := 'operation.verification-failed';
        lStatus := 'blocked';
        Result := cExitRejectedResult;
      end;
    end;
    lJson := TJSONObject.Create;
    try
      lJson.AddPair('status', lStatus);
      lJson.AddPair('reason', lReason);
      lJson.AddPair('journal', lJournalPath);
      WriteLn(lJson.ToJSON);
    finally
      lJson.Free;
    end;
  finally
    lBound.Free;
  end;
end;

function ReadUsesRequest(const aPath: string; out aOperation, aRequestJson, aReason: string): Boolean;
var
  lBytes: TBytes;
  lRoundTrip: TBytes;
  lText: string;
  lJson: TJSONValue;
  lObject: TJSONObject;
  lStream: TFileStream;
  lSelectorField: string;
begin
  Result := False;
  aOperation := '';
  aRequestJson := '';
  aReason := 'request.invalid';
  lStream := TFileStream.Create(aPath, fmOpenRead or fmShareDenyWrite);
  try
    if (lStream.Size = 0) or (lStream.Size > 65536) then
      Exit;
    SetLength(lBytes, lStream.Size);
    lStream.ReadBuffer(lBytes[0], Length(lBytes));
  finally
    lStream.Free;
  end;
  lText := TEncoding.UTF8.GetString(lBytes);
  lRoundTrip := TEncoding.UTF8.GetBytes(lText);
  if (Length(lRoundTrip) <> Length(lBytes)) or
    not CompareMem(@lRoundTrip[0], @lBytes[0], Length(lBytes)) then
    Exit;
  lJson := TJSONObject.ParseJSONValue(lText.TrimLeft([#$FEFF]));
  try
    if not (lJson is TJSONObject) then
      Exit;
    lObject := lJson as TJSONObject;
    if (lObject.Count <> 3) or not (lObject.GetValue('operation') is TJSONString) or
      not (lObject.GetValue('consumerFileName') is TJSONString) then
      Exit;
    aOperation := lObject.GetValue<string>('operation');
    lSelectorField := 'unitName';
    if aOperation = cSuggestImportsOperation then
      lSelectorField := 'identifier';
    if not (lObject.GetValue(lSelectorField) is TJSONString) then
      Exit;
    lObject.RemovePair('operation').Free;
    aRequestJson := lObject.ToJSON;
    Result := True;
  finally
    lJson.Free;
  end;
end;

{$IFDEF DAK_TRANSACTION_TEST_ACCESS}
procedure WriteNewRefactoringArtifactForTest(const aPath, aJson: string; const aAfterCreate: TProc);
begin
  WriteNewRefactoringArtifact(aPath, aJson, aAfterCreate);
end;
{$ENDIF}

function RunUsesPlanCommand(const aOptions: TAppOptions): Integer;
var
  lBound: TDelphiSemanticBoundPlanResult;
  lFresh: TRefactoringArtifact;
  lJson: string;
  lOperation: string;
  lOutput: TJSONObject;
  lReason: string;
  lRequestJson: string;
  lStatus: string;
  lReadOnly: Boolean;
begin
  Result := cExitRejectedResult;
  lBound := nil;
  lStatus := 'blocked';
  lReadOnly := False;
  lOutput := TJSONObject.Create;
  try
    try
      if ReadUsesRequest(aOptions.fRefactorRequestPath, lOperation, lRequestJson, lReason) then
      begin
        lReadOnly := lOperation = cSuggestImportsOperation;
        if lReadOnly and (aOptions.fRefactorPlanOutPath <> '') then
          lReason := 'request.discovery-has-no-plan'
        else if not lReadOnly and (aOptions.fRefactorPlanOutPath = '') then
          lReason := 'request.plan-out-required'
        else if FreshUsesPlan(aOptions, lOperation, lRequestJson, lFresh, lBound, lReason, lOutput) then
        begin
          if lReadOnly then
          begin
            lStatus := 'ok';
            Result := cExitSuccess;
          end else if TryWriteRefactoringArtifactJson(lFresh, lJson, lReason) then
          begin
            WriteNewRefactoringArtifact(TPath.GetFullPath(aOptions.fRefactorPlanOutPath), lJson);
            lStatus := lFresh.Status;
            Result := cExitSuccess;
          end;
        end;
      end;
    except
      on E: Exception do
      begin
        lReason := 'operation.plan-failed: ' + E.Message;
        Result := cExitRejectedResult;
      end;
    end;
    lOutput.AddPair('schemaVersion', TJSONNumber.Create(1));
    lOutput.AddPair('operation', lOperation);
    lOutput.AddPair('status', lStatus);
    lOutput.AddPair('reason', lReason);
    lOutput.AddPair('applicable', TJSONBool.Create(False));
    lOutput.AddPair('artifacts', TJSONArray.Create);
    if lOperation = cSuggestImportsOperation then
      CompleteImportSuggestionReport(lOutput, lReason);
    if (Result = 0) and not lReadOnly then
    begin
      lOutput.AddPair('plan', TPath.GetFullPath(aOptions.fRefactorPlanOutPath));
      lOutput.GetValue<TJSONArray>('artifacts').Add(TPath.GetFullPath(aOptions.fRefactorPlanOutPath));
    end;
    WriteLn(lOutput.ToJSON);
  finally
    lOutput.Free;
    lBound.Free;
  end;
end;

end.
