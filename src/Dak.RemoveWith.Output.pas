unit Dak.RemoveWith.Output;

interface

uses
  Dak.RemoveWith.Discovery, Dak.RemoveWith.Planner, Dak.RemoveWith.Resolver, Dak.RemoveWith.Symbols,
  Dak.RemoveWith.TempPolicy, Dak.RemoveWith.Transaction, Dak.Types;

function RemoveWithModeToText(const aMode: TRemoveWithMode): string;
function RemoveWithFormatToText(const aFormat: TRemoveWithFormat): string;
function RemoveWithTargetKindToText(const aKind: TRemoveWithTargetKind): string;
function BuildRemoveWithJsonReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult;
  const aResolverResult: TRemoveWithResolverResult; const aPlanResult: TRemoveWithPlanResult;
  const aTransactionResult: TRemoveWithTransactionResult): string;
function BuildRemoveWithTextReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult;
  const aPlanResult: TRemoveWithPlanResult; const aTransactionResult: TRemoveWithTransactionResult): string;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils;

const
  cRemoveWithSchemaVersion = 2;

function RemoveWithModeToText(const aMode: TRemoveWithMode): string;
begin
  case aMode of
    TRemoveWithMode.rwmScan:
      Result := 'scan';
    TRemoveWithMode.rwmApply:
      Result := 'apply';
  else
    Result := 'plan';
  end;
end;

function RemoveWithFormatToText(const aFormat: TRemoveWithFormat): string;
begin
  if aFormat = TRemoveWithFormat.rwfText then
    Result := 'text'
  else
    Result := 'json';
end;

function RemoveWithTargetKindToText(const aKind: TRemoveWithTargetKind): string;
begin
  case aKind of
    TRemoveWithTargetKind.rwtUnit:
      Result := 'unit';
    TRemoveWithTargetKind.rwtDir:
      Result := 'dir';
    TRemoveWithTargetKind.rwtAll:
      Result := 'all';
  else
    Result := 'none';
  end;
end;

function BuildProjectObject(const aProjectPath: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('path', aProjectPath);
  Result.AddPair('name', TPath.GetFileNameWithoutExtension(aProjectPath));
  Result.AddPair('dir', TPath.GetDirectoryName(aProjectPath));
end;

function BuildRunObject(const aRunId, aWorkspaceRoot: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', aRunId);
  Result.AddPair('workspaceRoot', aWorkspaceRoot);
end;

function BuildTargetsObject(const aOptions: TAppOptions; const aUnitPath, aDirPath: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', RemoveWithTargetKindToText(aOptions.fRemoveWithTargetKind));
  Result.AddPair('unit', aUnitPath);
  Result.AddPair('dir', aDirPath);
  Result.AddPair('all', TJSONBool.Create(aOptions.fRemoveWithAll));
end;

function BuildWorkspaceObject(const aWorkspaceRoot: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('root', aWorkspaceRoot);
  Result.AddPair('reports', TPath.Combine(aWorkspaceRoot, 'reports'));
  Result.AddPair('tmp', TPath.Combine(aWorkspaceRoot, 'tmp'));
  Result.AddPair('backup', TPath.Combine(aWorkspaceRoot, 'backup'));
  Result.AddPair('manifest', TPath.Combine(aWorkspaceRoot, 'manifest.json'));
end;

function BuildResolverObject(const aResolverResult: TRemoveWithResolverResult): TJSONObject;
var
  lClassification: TRemoveWithIdentifierClassification;
  lClassifications: TJSONArray;
  lCounts: TJSONObject;
  lExternalCount: Integer;
  lResolvedCount: Integer;
  lUnchangedCount: Integer;
  lUnsupportedCount: Integer;
  lUnresolvedCount: Integer;
  lAmbiguousCount: Integer;
begin
  Result := TJSONObject.Create;
  lResolvedCount := 0;
  lUnchangedCount := 0;
  lExternalCount := 0;
  lUnsupportedCount := 0;
  lUnresolvedCount := 0;
  lAmbiguousCount := 0;

  lClassifications := TJSONArray.Create;
  for lClassification in aResolverResult.fClassifications do
  begin
    case lClassification.fStatus of
      TRemoveWithIdentifierStatus.rwisResolved:
        Inc(lResolvedCount);
      TRemoveWithIdentifierStatus.rwisUnchanged:
        Inc(lUnchangedCount);
      TRemoveWithIdentifierStatus.rwisExternal:
        Inc(lExternalCount);
      TRemoveWithIdentifierStatus.rwisUnsupported:
        Inc(lUnsupportedCount);
      TRemoveWithIdentifierStatus.rwisAmbiguousToDak:
        Inc(lAmbiguousCount);
    else
      Inc(lUnresolvedCount);
    end;

    lClassifications.AddElement(TJSONObject.Create
      .AddPair('statementId', lClassification.fStatementId)
      .AddPair('file', lClassification.fFilePath)
      .AddPair('line', TJSONNumber.Create(lClassification.fLine))
      .AddPair('column', TJSONNumber.Create(lClassification.fColumn))
      .AddPair('identifier', lClassification.fIdentifier)
      .AddPair('status', RemoveWithIdentifierStatusToText(lClassification.fStatus))
      .AddPair('receiver', lClassification.fReceiverText)
      .AddPair('receiverType', lClassification.fReceiverType)
      .AddPair('resolutionKind', lClassification.fResolutionKind)
      .AddPair('sourceOwnerType', lClassification.fSourceOwnerType)
      .AddPair('memberKind', RemoveWithSymbolKindToText(lClassification.fMemberKind))
      .AddPair('reason', lClassification.fReason));
  end;
  Result.AddPair('classifications', lClassifications);

  lCounts := TJSONObject.Create;
  lCounts.AddPair('resolved', TJSONNumber.Create(lResolvedCount));
  lCounts.AddPair('unchanged', TJSONNumber.Create(lUnchangedCount));
  lCounts.AddPair('external', TJSONNumber.Create(lExternalCount));
  lCounts.AddPair('unsupported', TJSONNumber.Create(lUnsupportedCount));
  lCounts.AddPair('unresolved', TJSONNumber.Create(lUnresolvedCount));
  lCounts.AddPair('ambiguousToDak', TJSONNumber.Create(lAmbiguousCount));
  Result.AddPair('counts', lCounts);
end;

function BuildVerificationObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', 'not-run');
  Result.AddPair('gates', TJSONArray.Create);
end;

function BuildTransactionFilesArray(const aTransactionResult: TRemoveWithTransactionResult): TJSONArray;
var
  lFile: TRemoveWithTransactionFile;
begin
  Result := TJSONArray.Create;
  for lFile in aTransactionResult.fFiles do
  begin
    Result.AddElement(TJSONObject.Create
      .AddPair('path', lFile.fPath)
      .AddPair('backupPath', lFile.fBackupPath)
      .AddPair('hash', lFile.fHash)
      .AddPair('size', TJSONNumber.Create(lFile.fSize))
      .AddPair('lineEnding', lFile.fLineEnding)
      .AddPair('encoding', lFile.fEncoding));
  end;
end;

function BuildTransactionObject(const aTransactionResult: TRemoveWithTransactionResult): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', RemoveWithTransactionStatusToText(aTransactionResult.fStatus));
  Result.AddPair('backupRoot', aTransactionResult.fBackupRoot);
  Result.AddPair('manifestPath', aTransactionResult.fManifestPath);
  Result.AddPair('error', aTransactionResult.fError);
  Result.AddPair('files', BuildTransactionFilesArray(aTransactionResult));
end;

function BuildFilesArray(const aScanResult: TRemoveWithScanResult): TJSONArray;
var
  lFile: TRemoveWithFileInfo;
begin
  Result := TJSONArray.Create;
  for lFile in aScanResult.fFiles do
  begin
    Result.AddElement(TJSONObject.Create
      .AddPair('path', lFile.fPath)
      .AddPair('scanned', TJSONBool.Create(lFile.fScanned))
      .AddPair('withStatementCount', TJSONNumber.Create(lFile.fWithStatementCount)));
  end;
end;

function BuildRangeObject(const aRange: TRemoveWithRange): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('startLine', TJSONNumber.Create(aRange.fStartLine));
  Result.AddPair('startColumn', TJSONNumber.Create(aRange.fStartColumn));
  Result.AddPair('endLine', TJSONNumber.Create(aRange.fEndLine));
  Result.AddPair('endColumn', TJSONNumber.Create(aRange.fEndColumn));
end;

function BuildWithStatementsArray(const aScanResult: TRemoveWithScanResult): TJSONArray;
var
  lStatement: TRemoveWithStatementInfo;
begin
  Result := TJSONArray.Create;
  for lStatement in aScanResult.fWithStatements do
  begin
    Result.AddElement(TJSONObject.Create
      .AddPair('id', lStatement.fId)
      .AddPair('file', lStatement.fFilePath)
      .AddPair('line', TJSONNumber.Create(lStatement.fLine))
      .AddPair('column', TJSONNumber.Create(lStatement.fColumn))
      .AddPair('selectorText', lStatement.fSelectorText)
      .AddPair('selectorCount', TJSONNumber.Create(lStatement.fSelectorCount))
      .AddPair('nestingDepth', TJSONNumber.Create(lStatement.fNestingDepth))
      .AddPair('selectorRange', BuildRangeObject(lStatement.fSelectorRange))
      .AddPair('range', BuildRangeObject(lStatement.fRange))
      .AddPair('bodyRange', BuildRangeObject(lStatement.fBodyRange)));
  end;
end;

function BuildWarningsArray(const aScanResult: TRemoveWithScanResult): TJSONArray;
var
  lWarning: TRemoveWithWarningInfo;
begin
  Result := TJSONArray.Create;
  for lWarning in aScanResult.fWarnings do
  begin
    Result.AddElement(TJSONObject.Create
      .AddPair('file', lWarning.fFilePath)
      .AddPair('line', TJSONNumber.Create(lWarning.fLine))
      .AddPair('column', TJSONNumber.Create(lWarning.fColumn))
      .AddPair('code', lWarning.fCode)
      .AddPair('message', lWarning.fMessage));
  end;
end;

function BuildPlannedEditRangeObject(const aRange: TRemoveWithRange): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('startLine', TJSONNumber.Create(aRange.fStartLine));
  Result.AddPair('startColumn', TJSONNumber.Create(aRange.fStartColumn));
  Result.AddPair('endLine', TJSONNumber.Create(aRange.fEndLine));
  Result.AddPair('endColumn', TJSONNumber.Create(aRange.fEndColumn));
end;

function BuildTempDecisionObject(const aDecision: TRemoveWithTempDecision): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('selector', aDecision.fSelectorText);
  Result.AddPair('strategy', RemoveWithTempStrategyToText(aDecision.fStrategy));
  Result.AddPair('receiverType', aDecision.fReceiverType);
  Result.AddPair('tempName', aDecision.fTempName);
  Result.AddPair('declaration', aDecision.fDeclarationText);
  Result.AddPair('initialization', aDecision.fInitializationText);
  Result.AddPair('qualifier', aDecision.fQualifierText);
  Result.AddPair('reason', aDecision.fReason);
end;

function BuildPlannedEditsArray(const aPlanResult: TRemoveWithPlanResult): TJSONArray;
var
  lEdit: TRemoveWithPlannedTextEdit;
  lEditObject: TJSONObject;
  lEdits: TJSONArray;
  lStatement: TRemoveWithPlannedStatement;
  lTemp: TRemoveWithTempDecision;
  lTemps: TJSONArray;
begin
  Result := TJSONArray.Create;
  for lStatement in aPlanResult.fStatements do
  begin
    if lStatement.fStatus <> 'planned' then
      Continue;

    lEdits := TJSONArray.Create;
    for lEdit in lStatement.fEdits do
    begin
      lEditObject := TJSONObject.Create;
      lEditObject.AddPair('kind', lEdit.fKind);
      lEditObject.AddPair('file', lEdit.fFilePath);
      lEditObject.AddPair('statementId', lEdit.fStatementId);
      lEditObject.AddPair('range', BuildPlannedEditRangeObject(lEdit.fRange));
      lEditObject.AddPair('replacementText', lEdit.fReplacementText);
      lEdits.AddElement(lEditObject);
    end;

    lTemps := TJSONArray.Create;
    for lTemp in lStatement.fTemps do
      lTemps.AddElement(BuildTempDecisionObject(lTemp));

    Result.AddElement(TJSONObject.Create
      .AddPair('statementId', lStatement.fStatementId)
      .AddPair('file', lStatement.fFilePath)
      .AddPair('status', lStatement.fStatus)
      .AddPair('replacementText', lStatement.fReplacementText)
      .AddPair('temps', lTemps)
      .AddPair('edits', lEdits));
  end;
end;

function BuildSkippedArray(const aPlanResult: TRemoveWithPlanResult): TJSONArray;
var
  lStatement: TRemoveWithPlannedStatement;
begin
  Result := TJSONArray.Create;
  for lStatement in aPlanResult.fStatements do
  begin
    if lStatement.fStatus <> 'skipped' then
      Continue;
    Result.AddElement(TJSONObject.Create
      .AddPair('statementId', lStatement.fStatementId)
      .AddPair('file', lStatement.fFilePath)
      .AddPair('reason', lStatement.fReason));
  end;
end;

procedure CountPlanResult(const aPlanResult: TRemoveWithPlanResult; out aPlannedCount, aSkippedCount: Integer);
var
  lStatement: TRemoveWithPlannedStatement;
begin
  aPlannedCount := 0;
  aSkippedCount := 0;
  for lStatement in aPlanResult.fStatements do
  begin
    if lStatement.fStatus = 'planned' then
      Inc(aPlannedCount)
    else if lStatement.fStatus = 'skipped' then
      Inc(aSkippedCount);
  end;
end;

function BuildSummaryObject(const aOptions: TAppOptions; const aScanResult: TRemoveWithScanResult;
  const aPlanResult: TRemoveWithPlanResult; const aTransactionResult: TRemoveWithTransactionResult): TJSONObject;
var
  lAppliedCount: Integer;
  lPlannedCount: Integer;
  lRolledBackCount: Integer;
  lSkippedCount: Integer;
begin
  CountPlanResult(aPlanResult, lPlannedCount, lSkippedCount);
  lAppliedCount := 0;
  lRolledBackCount := 0;
  if aOptions.fRemoveWithMode = TRemoveWithMode.rwmApply then
  begin
    if aTransactionResult.fStatus = TRemoveWithTransactionStatus.rwtxApplied then
      lAppliedCount := lPlannedCount
    else if aTransactionResult.fStatus = TRemoveWithTransactionStatus.rwtxRolledBack then
      lRolledBackCount := Length(aTransactionResult.fFiles);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('filesScanned', TJSONNumber.Create(Length(aScanResult.fFiles)));
  Result.AddPair('withStatements', TJSONNumber.Create(Length(aScanResult.fWithStatements)));
  Result.AddPair('plannedEdits', TJSONNumber.Create(lPlannedCount));
  Result.AddPair('appliedEdits', TJSONNumber.Create(lAppliedCount));
  Result.AddPair('skipped', TJSONNumber.Create(lSkippedCount));
  Result.AddPair('failed', TJSONNumber.Create(0));
  Result.AddPair('rolledBack', TJSONNumber.Create(lRolledBackCount));
end;

function BuildRootStatus(const aOptions: TAppOptions;
  const aTransactionResult: TRemoveWithTransactionResult): string;
begin
  if aOptions.fRemoveWithMode = TRemoveWithMode.rwmApply then
    Exit(RemoveWithTransactionStatusToText(aTransactionResult.fStatus));

  Result := 'ok';
end;

function BuildRemoveWithJsonReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult;
  const aResolverResult: TRemoveWithResolverResult; const aPlanResult: TRemoveWithPlanResult;
  const aTransactionResult: TRemoveWithTransactionResult): string;
var
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('schemaVersion', TJSONNumber.Create(cRemoveWithSchemaVersion));
    lRoot.AddPair('operation', 'remove-with');
    lRoot.AddPair('status', BuildRootStatus(aOptions, aTransactionResult));
    lRoot.AddPair('mode', RemoveWithModeToText(aOptions.fRemoveWithMode));
    lRoot.AddPair('format', RemoveWithFormatToText(aOptions.fRemoveWithFormat));
    lRoot.AddPair('project', BuildProjectObject(aProjectPath));
    lRoot.AddPair('run', BuildRunObject(aRunId, aWorkspaceRoot));
    lRoot.AddPair('targets', BuildTargetsObject(aOptions, aUnitPath, aDirPath));
    lRoot.AddPair('workspace', BuildWorkspaceObject(aWorkspaceRoot));
    lRoot.AddPair('files', BuildFilesArray(aScanResult));
    lRoot.AddPair('withStatements', BuildWithStatementsArray(aScanResult));
    lRoot.AddPair('resolver', BuildResolverObject(aResolverResult));
    lRoot.AddPair('plannedEdits', BuildPlannedEditsArray(aPlanResult));
    lRoot.AddPair('skipped', BuildSkippedArray(aPlanResult));
    lRoot.AddPair('warnings', BuildWarningsArray(aScanResult));
    lRoot.AddPair('verification', BuildVerificationObject);
    lRoot.AddPair('transaction', BuildTransactionObject(aTransactionResult));
    lRoot.AddPair('summary', BuildSummaryObject(aOptions, aScanResult, aPlanResult, aTransactionResult));
    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

function BuildRemoveWithTextReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult;
  const aPlanResult: TRemoveWithPlanResult; const aTransactionResult: TRemoveWithTransactionResult): string;
var
  lAppliedCount: Integer;
  lPlannedCount: Integer;
  lRolledBackCount: Integer;
  lSkippedCount: Integer;
  lStatusText: string;
  lTargetValue: string;
begin
  CountPlanResult(aPlanResult, lPlannedCount, lSkippedCount);
  lStatusText := BuildRootStatus(aOptions, aTransactionResult);
  lAppliedCount := 0;
  lRolledBackCount := 0;
  if aOptions.fRemoveWithMode = TRemoveWithMode.rwmApply then
  begin
    if aTransactionResult.fStatus = TRemoveWithTransactionStatus.rwtxApplied then
      lAppliedCount := lPlannedCount
    else if aTransactionResult.fStatus in [TRemoveWithTransactionStatus.rwtxRolledBack,
      TRemoveWithTransactionStatus.rwtxRollbackFailed] then
      lRolledBackCount := Length(aTransactionResult.fFiles);
  end;

  lTargetValue := aUnitPath;
  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtDir then
    lTargetValue := aDirPath
  else if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtAll then
    lTargetValue := '<all project units>';

  Result := 'schemaVersion=' + IntToStr(cRemoveWithSchemaVersion) + sLineBreak +
    'operation=remove-with' + sLineBreak +
    'status=' + lStatusText + sLineBreak +
    'mode=' + RemoveWithModeToText(aOptions.fRemoveWithMode) + sLineBreak +
    'project=' + aProjectPath + sLineBreak +
    'run=' + aRunId + sLineBreak +
    'target=' + RemoveWithTargetKindToText(aOptions.fRemoveWithTargetKind) + ':' + lTargetValue + sLineBreak +
    'workspace=' + aWorkspaceRoot + sLineBreak +
    'filesScanned=' + IntToStr(Length(aScanResult.fFiles)) + sLineBreak +
    'withStatements=' + IntToStr(Length(aScanResult.fWithStatements)) + sLineBreak +
    'plannedEdits=' + IntToStr(lPlannedCount) + sLineBreak +
    'appliedEdits=' + IntToStr(lAppliedCount) + sLineBreak +
    'skipped=' + IntToStr(lSkippedCount) + sLineBreak +
    'failed=0' + sLineBreak +
    'rolledBack=' + IntToStr(lRolledBackCount) + sLineBreak +
    'transactionManifest=' + aTransactionResult.fManifestPath + sLineBreak +
    'verification=' + RemoveWithTransactionStatusToText(aTransactionResult.fStatus);
end;

end.
