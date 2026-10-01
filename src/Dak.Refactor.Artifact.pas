unit Dak.Refactor.Artifact;

interface

uses
  System.SysUtils,
  DelphiSemantics.Refactor.Binding, DelphiSemantics.Refactor.Plan;

type
  TRefactoringArtifactSource = record
    FileName: string;
    ContentHash: string;
    IncludeGraphHash: string;
  end;

  // Pure transport facts. A caller-populated record is never apply authority.
  TRefactoringArtifact = record
    Operation: string;
    Status: string;
    ContextFingerprint: string;
    BindingFingerprint: string;
    RequestJson: string;
    SelectedConfigurations: TArray<string>;
    ScopeRoots: TArray<string>;
    ExpectedRoots: TArray<string>;
    AnalyzedRoots: TArray<string>;
    RequiredAnalysisKinds: TArray<string>;
    Diagnostics: TArray<string>;
    Sources: TArray<TRefactoringArtifactSource>;
    Edits: TArray<TSemanticPlanEdit>;
    OmittedResultCount: Integer;
    FocusedChecks: TArray<string>;
  end;

// An artifact is untrusted input. This header check never authorizes its edits.
function TryReadRefactoringArtifactHeader(const aPath: string; out aReason: string): Boolean;
function TryReadRefactoringArtifact(const aPath: string;
  out aArtifact: TRefactoringArtifact; out aReason: string): Boolean;
function TryWriteRefactoringArtifactJson(const aArtifact: TRefactoringArtifact;
  out aJson, aReason: string): Boolean;
function RefactoringArtifactsMatch(const aSaved, aFresh: TRefactoringArtifact;
  out aReason: string): Boolean;
function TryCreateBoundRefactoringArtifact(const aBound: TDelphiSemanticBoundPlanResult;
  const aRequestJson: string; out aArtifact: TRefactoringArtifact; out aReason: string): Boolean;
procedure WriteNewRefactoringArtifact(const aPath, aJson: string; const aAfterCreate: TProc = nil);

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.JSON,
  System.StrUtils,
  Winapi.Windows;

const
  cMaxArtifactBytes: Int64 = 64 * 1024 * 1024;
  cMaxJsonDepth = 64;

type
  TJsonWalkItem = record
    Value: TJSONValue;
    Depth: Integer;
  end;

function TryCreateBoundRefactoringArtifact(const aBound: TDelphiSemanticBoundPlanResult;
  const aRequestJson: string; out aArtifact: TRefactoringArtifact; out aReason: string): Boolean;
begin
  Result := False;
  aArtifact := Default(TRefactoringArtifact);
  aReason := 'artifact.bound-plan-unavailable';
  if not Assigned(aBound) or not Assigned(aBound.Plan) or
    not (aBound.Status in [TSemanticPlanStatus.Complete, TSemanticPlanStatus.NoChange]) then
    Exit;
  if (aBound.RequiredAnalysisKinds <> [pakBodyAnalysis, pakReferenceExtraction]) or
    (aBound.RequiredVerifications <> [pvFreshContextRevalidation, pvSameIntentFeatureReplan,
      pvBaselineBuild, pvPostEditBuild]) then
    Exit;
  aArtifact.Operation := aBound.OperationIdentity;
  aArtifact.RequestJson := aRequestJson;
  if aBound.Status = TSemanticPlanStatus.Complete then
    aArtifact.Status := 'complete'
  else
    aArtifact.Status := 'no-change';
  aArtifact.ContextFingerprint := aBound.ContextFingerprint;
  aArtifact.BindingFingerprint := aBound.BindingFingerprint;
  aArtifact.SelectedConfigurations := aBound.SelectedConfigurationIdentities;
  aArtifact.ScopeRoots := aBound.ScopeRootFileNames;
  aArtifact.ExpectedRoots := aBound.ExpectedRootFileNames;
  aArtifact.AnalyzedRoots := aBound.AnalyzedRootFileNames;
  aArtifact.RequiredAnalysisKinds := ['body', 'references'];
  aArtifact.Diagnostics := aBound.Diagnostics;
  SetLength(aArtifact.Edits, aBound.Plan.EditCount);
  for var i := 0 to High(aArtifact.Edits) do
    aArtifact.Edits[i] := aBound.Plan.Edits[i];
  SetLength(aArtifact.Sources, aBound.Plan.SourceCount);
  for var i := 0 to High(aArtifact.Sources) do
  begin
    aArtifact.Sources[i].FileName := aBound.Plan.Sources[i].FileName;
    aArtifact.Sources[i].ContentHash := aBound.Plan.Sources[i].ContentHash;
    aArtifact.Sources[i].IncludeGraphHash := aBound.Plan.Sources[i].IncludeGraphHash;
  end;
  aReason := '';
  Result := True;
end;

// The Delphi 12 WinAPI declarations omit this Vista+ handle-based API.
function SetArtifactFileInformation(const aHandle: THandle; const aInformationClass: Integer;
  const aInformation: Pointer; const aSize: DWORD): BOOL; stdcall;
  external kernel32 name 'SetFileInformationByHandle';

procedure WriteNewRefactoringArtifact(const aPath, aJson: string; const aAfterCreate: TProc);
const
  cFileDispositionInfo = 4;
var
  lBytes: TBytes;
  lDeleteOnClose: Byte;
  lHandle: THandle;
  lStream: THandleStream;
begin
  // CREATE_NEW prevents an output path from overwriting source or prior artifacts.
  lHandle := CreateFile(PChar(aPath), GENERIC_WRITE or _DELETE, 0, nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
  if lHandle = INVALID_HANDLE_VALUE then
    raise EInOutError.Create('artifact.output-not-new');
  try
    try
      {$IFDEF DAK_TRANSACTION_TEST_ACCESS}
      if Assigned(aAfterCreate) then
        aAfterCreate();
      {$ENDIF}
      lStream := THandleStream.Create(lHandle);
      try
        lBytes := TEncoding.UTF8.GetBytes(aJson);
        lStream.WriteBuffer(lBytes[0], Length(lBytes));
        if not FlushFileBuffers(lHandle) then
          RaiseLastOSError;
      finally
        // Release the stream before the separately owned native handle closes.
        lStream.Free;
      end;
    except
      on E: Exception do
      begin
        // Delete through the exclusive CREATE_NEW handle, never a reopened path.
        // FILE_DISPOSITION_INFO contains a one-byte Windows BOOLEAN.
        lDeleteOnClose := 1;
        if not SetArtifactFileInformation(lHandle, cFileDispositionInfo,
          @lDeleteOnClose, SizeOf(lDeleteOnClose)) then
          raise EInOutError.CreateFmt('%s; artifact.cleanup-failed: %d', [E.Message, GetLastError]);
        raise;
      end;
    end;
  finally
    CloseHandle(lHandle);
  end;
end;

function RefactoringArtifactsMatch(const aSaved, aFresh: TRefactoringArtifact;
  out aReason: string): Boolean;
var
  i: Integer;

  function SameStrings(const aLeft, aRight: TArray<string>): Boolean;
  var
    j: Integer;
  begin
    Result := False;
    if Length(aLeft) <> Length(aRight) then
      Exit;
    for j := 0 to High(aLeft) do
      if aLeft[j] <> aRight[j] then
        Exit;
    Result := True;
  end;

begin
  Result := False;
  aReason := 'artifact.intent-mismatch';
  if (aSaved.Operation <> aFresh.Operation) or
    (aSaved.RequestJson <> aFresh.RequestJson) then
    Exit;
  aReason := 'artifact.stale-context';
  if (aSaved.ContextFingerprint <> aFresh.ContextFingerprint) or
    (aSaved.BindingFingerprint <> aFresh.BindingFingerprint) then
    Exit;
  aReason := 'artifact.plan-mismatch';
  if (aSaved.Status <> aFresh.Status) or
    (aSaved.OmittedResultCount <> aFresh.OmittedResultCount) or
    not SameStrings(aSaved.SelectedConfigurations, aFresh.SelectedConfigurations) or
    not SameStrings(aSaved.ScopeRoots, aFresh.ScopeRoots) or
    not SameStrings(aSaved.ExpectedRoots, aFresh.ExpectedRoots) or
    not SameStrings(aSaved.AnalyzedRoots, aFresh.AnalyzedRoots) or
    not SameStrings(aSaved.RequiredAnalysisKinds, aFresh.RequiredAnalysisKinds) or
    not SameStrings(aSaved.Diagnostics, aFresh.Diagnostics) or
    not SameStrings(aSaved.FocusedChecks, aFresh.FocusedChecks) or
    (Length(aSaved.Sources) <> Length(aFresh.Sources)) or
    (Length(aSaved.Edits) <> Length(aFresh.Edits)) then
    Exit;
  for i := 0 to High(aSaved.Sources) do
    if (aSaved.Sources[i].FileName <> aFresh.Sources[i].FileName) or
      (aSaved.Sources[i].ContentHash <> aFresh.Sources[i].ContentHash) or
      (aSaved.Sources[i].IncludeGraphHash <> aFresh.Sources[i].IncludeGraphHash) then
      Exit;
  for i := 0 to High(aSaved.Edits) do
    if (aSaved.Edits[i].FileName <> aFresh.Edits[i].FileName) or
      (aSaved.Edits[i].StartLine <> aFresh.Edits[i].StartLine) or
      (aSaved.Edits[i].StartColumn <> aFresh.Edits[i].StartColumn) or
      (aSaved.Edits[i].EndLine <> aFresh.Edits[i].EndLine) or
      (aSaved.Edits[i].EndColumn <> aFresh.Edits[i].EndColumn) or
      (aSaved.Edits[i].ExpectedText <> aFresh.Edits[i].ExpectedText) or
      (aSaved.Edits[i].ReplacementText <> aFresh.Edits[i].ReplacementText) then
      Exit;
  aReason := '';
  Result := True;
end;

function HasDuplicateKeysOrExcessDepth(const aValue: TJSONValue;
  const aDepth: Integer): Boolean;
var
  lArray: TJSONArray;
  lChild: TJsonWalkItem;
  lItem: TJsonWalkItem;
  lName: string;
  lObject: TJSONObject;
  lSeen: TStringList;
  lStack: TStack<TJsonWalkItem>;
  i: Integer;
begin
  Result := True;
  lStack := TStack<TJsonWalkItem>.Create;
  try
    lItem.Value := aValue;
    lItem.Depth := aDepth;
    lStack.Push(lItem);
    while lStack.Count > 0 do
    begin
      lItem := lStack.Pop;
      if lItem.Depth > cMaxJsonDepth then
        Exit;
      if lItem.Value is TJSONObject then
      begin
        lObject := lItem.Value as TJSONObject;
        lSeen := TStringList.Create;
        try
          lSeen.CaseSensitive := True;
          lSeen.Sorted := True;
          for i := 0 to lObject.Count - 1 do
          begin
            lName := lObject.Pairs[i].JsonString.Value;
            if lSeen.IndexOf(lName) >= 0 then
              Exit;
            lSeen.Add(lName);
            lChild.Value := lObject.Pairs[i].JsonValue;
            lChild.Depth := lItem.Depth + 1;
            lStack.Push(lChild);
          end;
        finally
          lSeen.Free;
        end;
      end else if lItem.Value is TJSONArray then
      begin
        lArray := lItem.Value as TJSONArray;
        for i := 0 to lArray.Count - 1 do
        begin
          lChild.Value := lArray.Items[i];
          lChild.Depth := lItem.Depth + 1;
          lStack.Push(lChild);
        end;
      end;
    end;
    Result := False;
  finally
    lStack.Free;
  end;
end;

function HasStringField(const aObject: TJSONObject; const aName: string;
  const aAllowEmpty: Boolean = False): Boolean;
var
  lValue: TJSONValue;
begin
  lValue := aObject.GetValue(aName);
  Result := lValue is TJSONString;
  if Result and not aAllowEmpty then
    Result := Trim(TJSONString(lValue).Value) <> '';
end;

function HasPositiveIntegerField(const aObject: TJSONObject;
  const aName: string): Boolean;
var
  lNumber: Integer;
  lValue: TJSONValue;
begin
  lValue := aObject.GetValue(aName);
  Result := False;
  if not (lValue is TJSONNumber) then
    Exit;
  if not TryStrToInt(lValue.ToJSON, lNumber) then
    Exit;
  Result := lNumber > 0;
end;

function HasTypedPlanEntries(const aJson: TJSONObject): Boolean;
var
  lEdit: TJSONObject;
  lEdits: TJSONArray;
  lSource: TJSONObject;
  lSources: TJSONArray;
  i: Integer;
begin
  Result := False;
  lSources := aJson.GetValue('sources') as TJSONArray;
  lEdits := aJson.GetValue('edits') as TJSONArray;
  if lSources.Count = 0 then
    Exit;
  for i := 0 to lSources.Count - 1 do
  begin
    if not (lSources.Items[i] is TJSONObject) then
      Exit;
    lSource := TJSONObject(lSources.Items[i]);
    if not HasStringField(lSource, 'fileName') or
      not HasStringField(lSource, 'contentHash') or
      not HasStringField(lSource, 'includeGraphHash') then
      Exit;
  end;
  for i := 0 to lEdits.Count - 1 do
  begin
    if not (lEdits.Items[i] is TJSONObject) then
      Exit;
    lEdit := TJSONObject(lEdits.Items[i]);
    if not HasStringField(lEdit, 'fileName') or
      not HasPositiveIntegerField(lEdit, 'startLine') or
      not HasPositiveIntegerField(lEdit, 'startColumn') or
      not HasPositiveIntegerField(lEdit, 'endLine') or
      not HasPositiveIntegerField(lEdit, 'endColumn') or
      not HasStringField(lEdit, 'expectedText', True) or
      not HasStringField(lEdit, 'replacementText', True) then
      Exit;
  end;
  Result := True;
end;

function HasNonemptyStringArray(const aObject: TJSONObject;
  const aName: string): Boolean;
var
  lArray: TJSONArray;
  i: Integer;
begin
  Result := False;
  if not (aObject.GetValue(aName) is TJSONArray) then
    Exit;
  lArray := TJSONArray(aObject.GetValue(aName));
  if lArray.Count = 0 then
    Exit;
  for i := 0 to lArray.Count - 1 do
    if not (lArray.Items[i] is TJSONString) or
      (Trim(TJSONString(lArray.Items[i]).Value) = '') then
      Exit;
  Result := True;
end;

function HasTypedScope(const aJson: TJSONObject): Boolean;
var
  lScope: TJSONObject;
begin
  lScope := TJSONObject(aJson.GetValue('scope'));
  Result := HasNonemptyStringArray(lScope, 'selectedConfigurations') and
    HasNonemptyStringArray(lScope, 'scopeRoots') and
    HasNonemptyStringArray(lScope, 'expectedRoots') and
    HasNonemptyStringArray(lScope, 'analyzedRoots') and
    HasNonemptyStringArray(lScope, 'requiredAnalysisKinds');
end;

function TryNonnegativeIntegerField(const aObject: TJSONObject; const aName: string;
  out aValue: Integer): Boolean;
var
  lJsonValue: TJSONValue;
begin
  aValue := 0;
  lJsonValue := aObject.GetValue(aName);
  Result := False;
  if not (lJsonValue is TJSONNumber) then
    Exit;
  if not TryStrToInt(lJsonValue.ToJSON, aValue) then
    Exit;
  Result := aValue >= 0;
end;

function HasTypedSummary(const aJson: TJSONObject): Boolean;
var
  lDiagnosticCount: Integer;
  lEditCount: Integer;
  lOmittedCount: Integer;
  lSourceCount: Integer;
  lSummary: TJSONObject;
begin
  lSummary := TJSONObject(aJson.GetValue('summary'));
  Result := TryNonnegativeIntegerField(lSummary, 'sourceCount', lSourceCount) and
    TryNonnegativeIntegerField(lSummary, 'editCount', lEditCount) and
    TryNonnegativeIntegerField(lSummary, 'diagnosticCount', lDiagnosticCount) and
    TryNonnegativeIntegerField(lSummary, 'omittedResultCount', lOmittedCount);
  if not Result then
    Exit;
  Result := (lSourceCount = TJSONArray(aJson.GetValue('sources')).Count) and
    (lEditCount = TJSONArray(aJson.GetValue('edits')).Count) and
    (lDiagnosticCount = TJSONArray(aJson.GetValue('diagnostics')).Count) and
    (lOmittedCount >= 0);
end;

function HasTrueBooleanField(const aObject: TJSONObject; const aName: string): Boolean;
var
  lValue: TJSONValue;
begin
  lValue := aObject.GetValue(aName);
  Result := False;
  if not (lValue is TJSONBool) then
    Exit;
  Result := lValue.ToJSON = 'true';
end;

function HasTypedVerification(const aJson: TJSONObject): Boolean;
var
  lChecks: TJSONArray;
  lVerification: TJSONObject;
  i: Integer;
begin
  lVerification := TJSONObject(aJson.GetValue('verification'));
  Result := HasTrueBooleanField(lVerification, 'freshContextRevalidation') and
    HasTrueBooleanField(lVerification, 'sameIntentFeatureReplan') and
    HasTrueBooleanField(lVerification, 'baselineBuild') and
    HasTrueBooleanField(lVerification, 'postEditBuild') and
    (lVerification.GetValue('focusedChecks') is TJSONArray);
  if not Result then
    Exit;
  lChecks := TJSONArray(lVerification.GetValue('focusedChecks'));
  for i := 0 to lChecks.Count - 1 do
    if not (lChecks.Items[i] is TJSONString) or
      (Trim(TJSONString(lChecks.Items[i]).Value) = '') then
      Exit(False);
end;

function HasTypedDiagnostics(const aJson: TJSONObject): Boolean;
var
  lDiagnostics: TJSONArray;
  i: Integer;
begin
  Result := False;
  lDiagnostics := TJSONArray(aJson.GetValue('diagnostics'));
  for i := 0 to lDiagnostics.Count - 1 do
  begin
    if not (lDiagnostics.Items[i] is TJSONObject) then
      Exit;
    if not HasStringField(TJSONObject(lDiagnostics.Items[i]), 'code') then
      Exit;
  end;
  Result := True;
end;

function BuildStringArray(const aValues: TArray<string>): TJSONArray;
var
  lValue: string;
begin
  Result := TJSONArray.Create;
  for lValue in aValues do
    Result.Add(lValue);
end;

function HasNonemptyValues(const aValues: TArray<string>): Boolean;
var
  lValue: string;
begin
  Result := Length(aValues) > 0;
  if not Result then
    Exit;
  for lValue in aValues do
    if Trim(lValue) = '' then
      Exit(False);
end;

function TryWriteRefactoringArtifactJson(const aArtifact: TRefactoringArtifact;
  out aJson, aReason: string): Boolean;
var
  lDiagnostic: string;
  lDiagnostics: TJSONArray;
  lEdit: TSemanticPlanEdit;
  lEdits: TJSONArray;
  lItem: TJSONObject;
  lRequest: TJSONValue;
  lRoot: TJSONObject;
  lScope: TJSONObject;
  lSource: TRefactoringArtifactSource;
  lSources: TJSONArray;
  lSummary: TJSONObject;
  lVerification: TJSONObject;
begin
  Result := False;
  aJson := '';
  aReason := 'artifact.malformed';
  lRequest := nil;
  lRoot := nil;
  try
    lRequest := TJSONObject.ParseJSONValue(aArtifact.RequestJson, False, False);
    if not (lRequest is TJSONObject) or
      HasDuplicateKeysOrExcessDepth(lRequest, 0) then
      Exit;
    if (Trim(aArtifact.Operation) = '') or
      not MatchStr(aArtifact.Status, ['complete', 'no-change', 'incomplete', 'blocked']) or
      (Trim(aArtifact.ContextFingerprint) = '') or
      (Trim(aArtifact.BindingFingerprint) = '') or
      (aArtifact.OmittedResultCount < 0) or
      not HasNonemptyValues(aArtifact.SelectedConfigurations) or
      not HasNonemptyValues(aArtifact.ScopeRoots) or
      not HasNonemptyValues(aArtifact.ExpectedRoots) or
      not HasNonemptyValues(aArtifact.AnalyzedRoots) or
      not HasNonemptyValues(aArtifact.RequiredAnalysisKinds) or
      (Length(aArtifact.Sources) = 0) or
      ((aArtifact.Status = 'complete') <> (Length(aArtifact.Edits) > 0)) then
      Exit;

    lRoot := TJSONObject.Create;
    lRoot.AddPair('schemaVersion', TJSONNumber.Create(1));
    lRoot.AddPair('operation', aArtifact.Operation);
    lRoot.AddPair('status', aArtifact.Status);
    lRoot.AddPair('contextFingerprint', aArtifact.ContextFingerprint);
    lRoot.AddPair('bindingFingerprint', aArtifact.BindingFingerprint);
    lRoot.AddPair('request', lRequest);
    lRequest := nil;

    lScope := TJSONObject.Create;
    lRoot.AddPair('scope', lScope);
    lScope.AddPair('selectedConfigurations',
      BuildStringArray(aArtifact.SelectedConfigurations));
    lScope.AddPair('scopeRoots', BuildStringArray(aArtifact.ScopeRoots));
    lScope.AddPair('expectedRoots', BuildStringArray(aArtifact.ExpectedRoots));
    lScope.AddPair('analyzedRoots', BuildStringArray(aArtifact.AnalyzedRoots));
    lScope.AddPair('requiredAnalysisKinds',
      BuildStringArray(aArtifact.RequiredAnalysisKinds));

    lDiagnostics := TJSONArray.Create;
    lRoot.AddPair('diagnostics', lDiagnostics);
    for lDiagnostic in aArtifact.Diagnostics do
    begin
      if Trim(lDiagnostic) = '' then
        Exit;
      lItem := TJSONObject.Create;
      lItem.AddPair('code', lDiagnostic);
      lDiagnostics.AddElement(lItem);
    end;

    lSources := TJSONArray.Create;
    lRoot.AddPair('sources', lSources);
    for lSource in aArtifact.Sources do
    begin
      lItem := TJSONObject.Create;
      lItem.AddPair('fileName', lSource.FileName);
      lItem.AddPair('contentHash', lSource.ContentHash);
      lItem.AddPair('includeGraphHash', lSource.IncludeGraphHash);
      lSources.AddElement(lItem);
    end;

    lEdits := TJSONArray.Create;
    lRoot.AddPair('edits', lEdits);
    for lEdit in aArtifact.Edits do
    begin
      lItem := TJSONObject.Create;
      lItem.AddPair('fileName', lEdit.FileName);
      lItem.AddPair('startLine', TJSONNumber.Create(lEdit.StartLine));
      lItem.AddPair('startColumn', TJSONNumber.Create(lEdit.StartColumn));
      lItem.AddPair('endLine', TJSONNumber.Create(lEdit.EndLine));
      lItem.AddPair('endColumn', TJSONNumber.Create(lEdit.EndColumn));
      lItem.AddPair('expectedText', lEdit.ExpectedText);
      lItem.AddPair('replacementText', lEdit.ReplacementText);
      lEdits.AddElement(lItem);
    end;

    lSummary := TJSONObject.Create;
    lRoot.AddPair('summary', lSummary);
    lSummary.AddPair('sourceCount', TJSONNumber.Create(Length(aArtifact.Sources)));
    lSummary.AddPair('editCount', TJSONNumber.Create(Length(aArtifact.Edits)));
    lSummary.AddPair('diagnosticCount', TJSONNumber.Create(Length(aArtifact.Diagnostics)));
    lSummary.AddPair('omittedResultCount',
      TJSONNumber.Create(aArtifact.OmittedResultCount));

    lVerification := TJSONObject.Create;
    lRoot.AddPair('verification', lVerification);
    lVerification.AddPair('freshContextRevalidation', TJSONBool.Create(True));
    lVerification.AddPair('sameIntentFeatureReplan', TJSONBool.Create(True));
    lVerification.AddPair('baselineBuild', TJSONBool.Create(True));
    lVerification.AddPair('postEditBuild', TJSONBool.Create(True));
    lVerification.AddPair('focusedChecks', BuildStringArray(aArtifact.FocusedChecks));

    if not HasTypedPlanEntries(lRoot) or not HasTypedScope(lRoot) or
      not HasTypedSummary(lRoot) or not HasTypedVerification(lRoot) then
      Exit;
    aJson := lRoot.ToJSON;
    if TEncoding.UTF8.GetByteCount(aJson) > cMaxArtifactBytes then
    begin
      aJson := '';
      aReason := 'artifact.too-large';
      Exit;
    end;
    aReason := '';
    Result := True;
  finally
    lRoot.Free;
    lRequest.Free;
  end;
end;

function TryLoadRefactoringArtifactDocument(const aPath: string;
  out aDocument: TJSONObject; out aReason: string): Boolean;
var
  lBytes: TBytes;
  lBody: TBytes;
  lJson: TJSONObject;
  lStream: TFileStream;
  lStatus: string;
  lText: string;
  lValue: TJSONValue;
  lVersionCount: Integer;
  i: Integer;
begin
  Result := False;
  aDocument := nil;
  aReason := 'artifact.unreadable';
  lStream := nil;
  lValue := nil;
  try
    try
      if not TFile.Exists(aPath) then
      begin
        aReason := 'artifact.missing';
        Exit;
      end;
      lStream := TFileStream.Create(aPath, fmOpenRead or fmShareDenyWrite);
      if lStream.Size > cMaxArtifactBytes then
      begin
        aReason := 'artifact.too-large';
        Exit;
      end;
      SetLength(lBytes, lStream.Size);
      if Length(lBytes) > 0 then
        lStream.ReadBuffer(lBytes[0], Length(lBytes));
      if (Length(lBytes) >= 3) and (lBytes[0] = $EF) and (lBytes[1] = $BB) and
        (lBytes[2] = $BF) then
        lBody := Copy(lBytes, 3, Length(lBytes) - 3)
      else
        lBody := lBytes;
      aReason := 'artifact.invalid-utf8';
      if not TEncoding.UTF8.IsBufferValid(lBody) then
        Exit;
      lText := TEncoding.UTF8.GetString(lBody);
      aReason := 'artifact.malformed';
      lValue := TJSONObject.ParseJSONValue(lText, False, False);
      if not (lValue is TJSONObject) then
        Exit;
      lJson := TJSONObject(lValue);
      if HasDuplicateKeysOrExcessDepth(lJson, 0) then
        Exit;
      lVersionCount := 0;
      for i := 0 to lJson.Count - 1 do
        if lJson.Pairs[i].JsonString.Value = 'schemaVersion' then
          Inc(lVersionCount);
      if lVersionCount <> 1 then
        Exit;
      aReason := 'artifact.unsupported-version';
      if not (lJson.GetValue('schemaVersion') is TJSONNumber) or
        (lJson.GetValue('schemaVersion').ToJSON <> '1') then
        Exit;
      aReason := 'artifact.malformed';
      if not (lJson.GetValue('operation') is TJSONString) or
        (Trim(lJson.GetValue<string>('operation')) = '') or
        not (lJson.GetValue('status') is TJSONString) or
        not MatchStr(lJson.GetValue<string>('status'),
          ['complete', 'no-change', 'incomplete', 'blocked']) or
        not (lJson.GetValue('contextFingerprint') is TJSONString) or
        (Trim(lJson.GetValue<string>('contextFingerprint')) = '') or
        not (lJson.GetValue('bindingFingerprint') is TJSONString) or
        (Trim(lJson.GetValue<string>('bindingFingerprint')) = '') or
        not (lJson.GetValue('request') is TJSONObject) or
        not (lJson.GetValue('scope') is TJSONObject) or
        not (lJson.GetValue('diagnostics') is TJSONArray) or
        not (lJson.GetValue('summary') is TJSONObject) or
        not (lJson.GetValue('sources') is TJSONArray) or
        not (lJson.GetValue('edits') is TJSONArray) or
        not (lJson.GetValue('verification') is TJSONObject) then
        Exit;
      if not HasTypedPlanEntries(lJson) or not HasTypedScope(lJson) or
        not HasTypedSummary(lJson) or not HasTypedVerification(lJson) or
        not HasTypedDiagnostics(lJson) then
        Exit;
      lStatus := lJson.GetValue<string>('status');
      if MatchStr(lStatus, ['incomplete', 'blocked']) then
      begin
        aReason := 'artifact.incomplete';
        Exit;
      end;
      aReason := 'artifact.malformed';
      if ((lStatus = 'complete') and (TJSONArray(lJson.GetValue('edits')).Count = 0)) or
        ((lStatus = 'no-change') and (TJSONArray(lJson.GetValue('edits')).Count <> 0)) then
        Exit;
      aReason := '';
      aDocument := lJson;
      lValue := nil;
      Result := True;
    except
      on E: Exception do
        aReason := 'artifact.unreadable';
    end;
  finally
    lValue.Free;
    lStream.Free;
  end;
end;

function TryReadRefactoringArtifactHeader(const aPath: string; out aReason: string): Boolean;
var
  lDocument: TJSONObject;
begin
  Result := TryLoadRefactoringArtifactDocument(aPath, lDocument, aReason);
  lDocument.Free;
end;

function ReadStringArray(const aObject: TJSONObject; const aName: string): TArray<string>;
var
  lArray: TJSONArray;
  i: Integer;
begin
  lArray := TJSONArray(aObject.GetValue(aName));
  SetLength(Result, lArray.Count);
  for i := 0 to lArray.Count - 1 do
    Result[i] := TJSONString(lArray.Items[i]).Value;
end;

function TryReadRefactoringArtifact(const aPath: string;
  out aArtifact: TRefactoringArtifact; out aReason: string): Boolean;
var
  lDiagnostics: TJSONArray;
  lDocument: TJSONObject;
  lEdit: TJSONObject;
  lEdits: TJSONArray;
  lScope: TJSONObject;
  lSource: TJSONObject;
  lSources: TJSONArray;
  lSummary: TJSONObject;
  lVerification: TJSONObject;
  i: Integer;
begin
  aArtifact := Default(TRefactoringArtifact);
  Result := TryLoadRefactoringArtifactDocument(aPath, lDocument, aReason);
  if not Result then
    Exit;
  try
    aArtifact.Operation := lDocument.GetValue<string>('operation');
    aArtifact.Status := lDocument.GetValue<string>('status');
    aArtifact.ContextFingerprint := lDocument.GetValue<string>('contextFingerprint');
    aArtifact.BindingFingerprint := lDocument.GetValue<string>('bindingFingerprint');
    aArtifact.RequestJson := lDocument.GetValue('request').ToJSON;
    lScope := TJSONObject(lDocument.GetValue('scope'));
    aArtifact.SelectedConfigurations := ReadStringArray(lScope, 'selectedConfigurations');
    aArtifact.ScopeRoots := ReadStringArray(lScope, 'scopeRoots');
    aArtifact.ExpectedRoots := ReadStringArray(lScope, 'expectedRoots');
    aArtifact.AnalyzedRoots := ReadStringArray(lScope, 'analyzedRoots');
    aArtifact.RequiredAnalysisKinds := ReadStringArray(lScope, 'requiredAnalysisKinds');

    lDiagnostics := TJSONArray(lDocument.GetValue('diagnostics'));
    SetLength(aArtifact.Diagnostics, lDiagnostics.Count);
    for i := 0 to lDiagnostics.Count - 1 do
      aArtifact.Diagnostics[i] :=
        TJSONObject(lDiagnostics.Items[i]).GetValue<string>('code');

    lSources := TJSONArray(lDocument.GetValue('sources'));
    SetLength(aArtifact.Sources, lSources.Count);
    for i := 0 to lSources.Count - 1 do
    begin
      lSource := TJSONObject(lSources.Items[i]);
      aArtifact.Sources[i].FileName := lSource.GetValue<string>('fileName');
      aArtifact.Sources[i].ContentHash := lSource.GetValue<string>('contentHash');
      aArtifact.Sources[i].IncludeGraphHash := lSource.GetValue<string>('includeGraphHash');
    end;

    lEdits := TJSONArray(lDocument.GetValue('edits'));
    SetLength(aArtifact.Edits, lEdits.Count);
    for i := 0 to lEdits.Count - 1 do
    begin
      lEdit := TJSONObject(lEdits.Items[i]);
      aArtifact.Edits[i].FileName := lEdit.GetValue<string>('fileName');
      aArtifact.Edits[i].StartLine := lEdit.GetValue<Integer>('startLine');
      aArtifact.Edits[i].StartColumn := lEdit.GetValue<Integer>('startColumn');
      aArtifact.Edits[i].EndLine := lEdit.GetValue<Integer>('endLine');
      aArtifact.Edits[i].EndColumn := lEdit.GetValue<Integer>('endColumn');
      aArtifact.Edits[i].ExpectedText := lEdit.GetValue<string>('expectedText');
      aArtifact.Edits[i].ReplacementText := lEdit.GetValue<string>('replacementText');
    end;

    lSummary := TJSONObject(lDocument.GetValue('summary'));
    aArtifact.OmittedResultCount := lSummary.GetValue<Integer>('omittedResultCount');
    lVerification := TJSONObject(lDocument.GetValue('verification'));
    aArtifact.FocusedChecks := ReadStringArray(lVerification, 'focusedChecks');
  finally
    lDocument.Free;
  end;
end;

end.
