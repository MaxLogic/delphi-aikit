unit Dak.RemoveWith.Output;

interface

uses
  Dak.RemoveWith.Discovery, Dak.RemoveWith.Planner, Dak.RemoveWith.Resolver, Dak.RemoveWith.Symbols,
  Dak.RemoveWith.TempPolicy, Dak.RemoveWith.Transaction, Dak.Types;

type
  TRemoveWithPlannerPhaseMetrics = record
    fTotalMs: Int64;
    fProjectModelMs: Int64;
    fDiscoveryMs: Int64;
    fSymbolInventoryMs: Int64;
    fSymbolInventoryPhaseMetrics: TRemoveWithFactSetPhaseMetrics;
    fSemanticProjectFactsMs: Int64;
    fSemanticCompatibilityFactsMs: Int64;
    fSemanticBindingMs: Int64;
    fSemanticPlanDtoMs: Int64;
    fDakLookupIndexMs: Int64;
    fDakLookupCacheHits: Int64;
    fDakLookupCacheMisses: Int64;
    fDakResolverClassifyMs: Int64;
    fResolverReportMetrics: TRemoveWithResolverReportMetrics;
    fDakPlannerRewriteMs: Int64;
    fSymbolMapBridgeMs: Int64;
    fResolverMs: Int64;
    fPlannerMs: Int64;
    fOutputSerializationMs: Int64;
    fContextFingerprint: string;
    fContextMode: string;
    fContextNote: string;
    fProjectUnitCount: Integer;
    fParsedUnitCount: Integer;
    fProjectProblemCount: Integer;
    fWithStatementCount: Integer;
    fSymbolCount: Integer;
    fClassificationCount: Integer;
    fPlannedEditCount: Integer;
    fSkippedStatementCount: Integer;
  end;

function RemoveWithModeToText(const aMode: TRemoveWithMode): string;
function RemoveWithFormatToText(const aFormat: TRemoveWithFormat): string;
function RemoveWithTargetKindToText(const aKind: TRemoveWithTargetKind): string;
function BuildRemoveWithJsonReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult;
  const aResolverResult: TRemoveWithResolverResult; const aPlanResult: TRemoveWithPlanResult;
  const aTransactionResult: TRemoveWithTransactionResult; const aMetrics: TRemoveWithPlannerPhaseMetrics): string;
function BuildRemoveWithTextReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult;
  const aPlanResult: TRemoveWithPlanResult; const aTransactionResult: TRemoveWithTransactionResult;
  const aMetrics: TRemoveWithPlannerPhaseMetrics): string;

implementation

uses
  System.Diagnostics, System.IOUtils, System.JSON, System.StrUtils, System.SysUtils,
  DelphiSemantics.Api.RemoveWith.Compatibility;

const
  cRemoveWithSchemaVersion = 2;
  cVerificationDiagnosticLineLimit = 40;

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

function BuildProjectObject(const aProjectPath: string;
  const aMetrics: TRemoveWithPlannerPhaseMetrics): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('path', aProjectPath);
  Result.AddPair('name', TPath.GetFileNameWithoutExtension(aProjectPath));
  Result.AddPair('dir', TPath.GetDirectoryName(aProjectPath));
  Result.AddPair('contextMode', aMetrics.fContextMode);
  if aMetrics.fContextNote <> '' then
    Result.AddPair('contextNote', aMetrics.fContextNote);
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

function RemoveWithDetailedReason(const aStatus: TRemoveWithIdentifierStatus; const aReason: string): string;
begin
  Result := aReason;
  if (aStatus = TRemoveWithIdentifierStatus.rwisUnresolved) and SameText(aReason, 'symbol-not-found') then
    Result := 'true-symbol-not-found';
end;

function BuildSymbolMapClassificationObject(const aClassification: TRemoveWithIdentifierClassification): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('found', TJSONBool.Create(aClassification.fSymbolMapFound));
  Result.AddPair('kind', aClassification.fSymbolMapKind);
  Result.AddPair('sourceKind', aClassification.fSymbolMapSourceKind);
  Result.AddPair('confidence', aClassification.fSymbolMapConfidence);
  Result.AddPair('ownerName', aClassification.fSymbolMapOwnerName);
  Result.AddPair('reason', aClassification.fSymbolMapReason);
end;

procedure AddReasonCount(const aObject: TJSONObject; const aReason: string);
var
  lCount: Integer;
  lPair: TJSONPair;
  lReason: string;
begin
  lReason := aReason;
  if lReason = '' then
    lReason := 'unclassified';
  lPair := aObject.Get(lReason);
  if Assigned(lPair) and (lPair.JsonValue is TJSONNumber) then
    lCount := (lPair.JsonValue as TJSONNumber).AsInt
  else
    lCount := 0;
  if Assigned(lPair) then
    aObject.RemovePair(lReason).Free;
  aObject.AddPair(lReason, TJSONNumber.Create(lCount + 1));
end;

function BuildResolverObject(const aResolverResult: TRemoveWithResolverResult): TJSONObject;
var
  lClassification: TRemoveWithIdentifierClassification;
  lClassifications: TJSONArray;
  lCounts: TJSONObject;
  lDetailedReason: string;
  lExternalCount: Integer;
  lUnresolvedReasons: TJSONObject;
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
  lUnresolvedReasons := TJSONObject.Create;

  lClassifications := TJSONArray.Create;
  for lClassification in aResolverResult.fClassifications do
  begin
    lDetailedReason := RemoveWithDetailedReason(lClassification.fStatus, lClassification.fReason);
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
    begin
      Inc(lUnresolvedCount);
      AddReasonCount(lUnresolvedReasons, lDetailedReason);
    end;
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
      .AddPair('symbolMap', BuildSymbolMapClassificationObject(lClassification))
      .AddPair('memberKind', RemoveWithSymbolKindToText(lClassification.fMemberKind))
      .AddPair('reason', lClassification.fReason)
      .AddPair('detailedReason', lDetailedReason));
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
  Result.AddPair('unresolvedReasons', lUnresolvedReasons);
end;

function BuildRemoveWithRequiredVerificationArray(
  const aValues: TArray<TDelphiSemanticRemoveWithVerification>): TJSONArray;
var
  i: Integer;
  lValue: TJSONObject;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(aValues) do
  begin
    lValue := TJSONObject.Create;
    lValue.AddPair('kind', aValues[i].Kind);
    lValue.AddPair('description', aValues[i].Description);
    Result.AddElement(lValue);
  end;
end;

function BuildVerificationObject(
  const aRequiredVerification: TArray<TDelphiSemanticRemoveWithVerification>): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', 'not-run');
  Result.AddPair('requiredVerification', BuildRemoveWithRequiredVerificationArray(aRequiredVerification));
  Result.AddPair('gates', TJSONArray.Create);
end;

procedure AddVerificationDiagnosticLine(const aDiagnostics: TJSONArray; const aText: string;
  var aCount: Integer);
var
  lText: string;
begin
  if aCount >= cVerificationDiagnosticLineLimit then
    Exit;

  lText := Trim(aText);
  if lText = '' then
    Exit;

  aDiagnostics.AddElement(TJSONString.Create(lText));
  Inc(aCount);
end;

procedure AddVerificationDiagnosticsFromFile(const aDiagnostics: TJSONArray; const aFileName: string;
  var aCount: Integer);
var
  lLine: string;
  lLines: TArray<string>;
begin
  if (aFileName = '') or (not TFile.Exists(aFileName)) then
    Exit;

  try
    lLines := TFile.ReadAllLines(aFileName, TEncoding.UTF8);
    for lLine in lLines do
      AddVerificationDiagnosticLine(aDiagnostics, lLine, aCount);
  except
    on E: Exception do
      AddVerificationDiagnosticLine(aDiagnostics, 'log-read-failed: ' + aFileName + ': ' + E.Message,
        aCount);
  end;
end;

function BuildVerificationDiagnosticsArray(const aTransactionResult: TRemoveWithTransactionResult): TJSONArray;
var
  lCount: Integer;
begin
  Result := TJSONArray.Create;
  lCount := 0;
  AddVerificationDiagnosticLine(Result, aTransactionResult.fVerificationError, lCount);
  AddVerificationDiagnosticsFromFile(Result, aTransactionResult.fVerificationStdOutLogPath, lCount);
  AddVerificationDiagnosticsFromFile(Result, aTransactionResult.fVerificationStdErrLogPath, lCount);
end;

function RemoveWithRequirementGate(const aKind: string): string;
begin
  if SameText(aKind, 'baseline-compile') then
    Exit('preflight-build');
  if SameText(aKind, 'context-fingerprint') then
    Exit('context-validation');
  if SameText(aKind, 'source-range') then
    Exit('source-validation');
  if SameText(aKind, 'post-edit-compile') then
    Exit('post-edit-build');
  if SameText(aKind, 'rollback-on-failure') then
    Exit('rollback');
  Result := '';
end;

function RemoveWithApplyWithoutEdits(const aTransactionResult: TRemoveWithTransactionResult): Boolean;
begin
  Result := (aTransactionResult.fStatus = TRemoveWithTransactionStatus.rwtxApplied) and
    SameText(aTransactionResult.fVerificationStatus, 'not-run') and
    (Length(aTransactionResult.fFiles) = 0);
end;

function RemoveWithRequirementStatus(const aKind: string;
  const aTransactionResult: TRemoveWithTransactionResult): string;
begin
  if RemoveWithApplyWithoutEdits(aTransactionResult) then
    Exit('not-run');

  if SameText(aKind, 'context-fingerprint') then
  begin
    case aTransactionResult.fStatus of
      TRemoveWithTransactionStatus.rwtxContextFingerprintMissing,
      TRemoveWithTransactionStatus.rwtxContextFingerprintMismatch:
        Exit('failed');
      TRemoveWithTransactionStatus.rwtxNotRun:
        Exit('not-run');
    else
      Exit('passed');
    end;
  end;

  if SameText(aKind, 'source-range') then
  begin
    case aTransactionResult.fStatus of
      TRemoveWithTransactionStatus.rwtxApplied:
        Exit('passed');
      TRemoveWithTransactionStatus.rwtxPreflightBuildFailed:
        Exit('not-run');
      TRemoveWithTransactionStatus.rwtxRolledBack,
      TRemoveWithTransactionStatus.rwtxRollbackFailed:
        if aTransactionResult.fVerificationStatus = 'not-run' then
          Exit('failed')
        else
          Exit('passed');
      TRemoveWithTransactionStatus.rwtxContextFingerprintMissing,
      TRemoveWithTransactionStatus.rwtxContextFingerprintMismatch,
      TRemoveWithTransactionStatus.rwtxNotRun:
        Exit('not-run');
    end;
  end;

  if SameText(aKind, 'baseline-compile') then
  begin
    case aTransactionResult.fStatus of
      TRemoveWithTransactionStatus.rwtxPreflightBuildFailed:
        Exit('failed');
      TRemoveWithTransactionStatus.rwtxApplied,
      TRemoveWithTransactionStatus.rwtxRolledBack,
      TRemoveWithTransactionStatus.rwtxRollbackFailed:
        Exit('passed');
    else
      Exit('not-run');
    end;
  end;

  if SameText(aKind, 'post-edit-compile') then
  begin
    case aTransactionResult.fStatus of
      TRemoveWithTransactionStatus.rwtxApplied:
        Exit('passed');
      TRemoveWithTransactionStatus.rwtxRolledBack,
      TRemoveWithTransactionStatus.rwtxRollbackFailed:
        Exit('failed');
    else
      Exit('not-run');
    end;
  end;

  if SameText(aKind, 'rollback-on-failure') then
  begin
    case aTransactionResult.fStatus of
      TRemoveWithTransactionStatus.rwtxApplied:
        Exit('available');
      TRemoveWithTransactionStatus.rwtxRolledBack:
        Exit('passed');
      TRemoveWithTransactionStatus.rwtxRollbackFailed:
        Exit('failed');
    else
      Exit('not-run');
    end;
  end;

  Result := 'unknown';
end;

function BuildBuildGateSatisfiesArray(const aTransactionResult: TRemoveWithTransactionResult): TJSONArray;
begin
  Result := TJSONArray.Create;
  if aTransactionResult.fStatus = TRemoveWithTransactionStatus.rwtxPreflightBuildFailed then
    Result.AddElement(TJSONString.Create('baseline-compile'))
  else
    Result.AddElement(TJSONString.Create('post-edit-compile'));
end;

function RemoveWithBuildGatePhase(const aTransactionResult: TRemoveWithTransactionResult): string;
begin
  if aTransactionResult.fStatus = TRemoveWithTransactionStatus.rwtxPreflightBuildFailed then
    Result := 'preflight'
  else
    Result := 'post-edit';
end;

function BuildRequirementReconciliationArray(
  const aRequiredVerification: TArray<TDelphiSemanticRemoveWithVerification>;
  const aTransactionResult: TRemoveWithTransactionResult): TJSONArray;
var
  i: Integer;
  lValue: TJSONObject;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(aRequiredVerification) do
  begin
    lValue := TJSONObject.Create;
    lValue.AddPair('kind', aRequiredVerification[i].Kind);
    lValue.AddPair('description', aRequiredVerification[i].Description);
    lValue.AddPair('gate', RemoveWithRequirementGate(aRequiredVerification[i].Kind));
    lValue.AddPair('status', RemoveWithRequirementStatus(aRequiredVerification[i].Kind,
      aTransactionResult));
    Result.AddElement(lValue);
  end;
end;

function BuildApplyVerificationObject(const aTransactionResult: TRemoveWithTransactionResult;
  const aRequiredVerification: TArray<TDelphiSemanticRemoveWithVerification>): TJSONObject;
var
  lDiagnostics: TJSONArray;
  lGates: TJSONArray;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', aTransactionResult.fVerificationStatus);
  Result.AddPair('requiredVerification', BuildRemoveWithRequiredVerificationArray(aRequiredVerification));
  Result.AddPair('requirementReconciliation', BuildRequirementReconciliationArray(aRequiredVerification,
    aTransactionResult));
  lGates := TJSONArray.Create;
  if aTransactionResult.fVerificationStatus <> 'not-run' then
  begin
    lDiagnostics := BuildVerificationDiagnosticsArray(aTransactionResult);
    lGates.AddElement(TJSONObject.Create
      .AddPair('name', 'build')
      .AddPair('phase', RemoveWithBuildGatePhase(aTransactionResult))
      .AddPair('status', aTransactionResult.fVerificationStatus)
      .AddPair('satisfies', BuildBuildGateSatisfiesArray(aTransactionResult))
      .AddPair('error', aTransactionResult.fVerificationError)
      .AddPair('stdoutLog', aTransactionResult.fVerificationStdOutLogPath)
      .AddPair('stderrLog', aTransactionResult.fVerificationStdErrLogPath)
      .AddPair('diagnostics', lDiagnostics));
  end;
  Result.AddPair('stdoutLog', aTransactionResult.fVerificationStdOutLogPath);
  Result.AddPair('stderrLog', aTransactionResult.fVerificationStdErrLogPath);
  Result.AddPair('gates', lGates);
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
      .AddPair('status', lFile.fStatus)
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
      .AddPair('hasScopedDeclarationInBody', TJSONBool.Create(lStatement.fHasScopedDeclarationInBody))
      .AddPair('hasUnsupportedIdentifierRoleInBody',
        TJSONBool.Create(lStatement.fHasUnsupportedIdentifierRoleInBody))
      .AddPair('unsupportedIdentifierRole', lStatement.fUnsupportedIdentifierRole)
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

function BuildWarningsText(const aScanResult: TRemoveWithScanResult): string;
var
  lBuilder: TStringBuilder;
  lWarning: TRemoveWithWarningInfo;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('warnings=' + IntToStr(Length(aScanResult.fWarnings)));
    for lWarning in aScanResult.fWarnings do
    begin
      lBuilder.AppendLine('warning=' + lWarning.fCode + '|' + lWarning.fFilePath + '|' +
        lWarning.fMessage);
    end;
    Result := lBuilder.ToString.TrimRight;
  finally
    lBuilder.Free;
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

function LegacySkippedReasonForReport(const aReason: string): string;
begin
  if SameText(aReason, 'member-not-found') then
    Result := 'symbol-not-found'
  else
    Result := aReason;
end;

function BuildSkippedArray(const aPlanResult: TRemoveWithPlanResult): TJSONArray;
var
  lItem: TJSONObject;
  lReportReason: string;
  lStatement: TRemoveWithPlannedStatement;
begin
  Result := TJSONArray.Create;
  for lStatement in aPlanResult.fStatements do
  begin
    if lStatement.fStatus <> 'skipped' then
      Continue;
    lReportReason := LegacySkippedReasonForReport(lStatement.fReason);
    lItem := TJSONObject.Create
      .AddPair('statementId', lStatement.fStatementId)
      .AddPair('file', lStatement.fFilePath)
      .AddPair('reason', lReportReason)
      .AddPair('detailedReason', RemoveWithDetailedReason(TRemoveWithIdentifierStatus.rwisUnresolved,
      lReportReason))
      .AddPair('unsupportedIdentifierRole', lStatement.fUnsupportedIdentifierRole);
    if not SameText(lReportReason, lStatement.fReason) then
      lItem.AddPair('semanticReason', lStatement.fReason);
    Result.AddElement(lItem);
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

function IsIntrinsicAllowlistFallback(const aClassification: TRemoveWithIdentifierClassification): Boolean;
begin
  Result := (aClassification.fStatus = TRemoveWithIdentifierStatus.rwisUnchanged) and
    SameText(aClassification.fResolutionKind, 'external-routine-call') and
    (aClassification.fMemberKind = TRemoveWithSymbolKind.rwskRoutine) and
    (not aClassification.fSymbolMapFound) and
    (not SameText(aClassification.fSymbolMapSourceKind, 'compiler-intrinsic'));
end;

function IsLocalModelHit(const aClassification: TRemoveWithIdentifierClassification): Boolean;
begin
  Result := False;
  if aClassification.fStatus = TRemoveWithIdentifierStatus.rwisResolved then
    Exit(True);

  if aClassification.fStatus <> TRemoveWithIdentifierStatus.rwisUnchanged then
    Exit;
  if aClassification.fSymbolMapFound and SameText(aClassification.fSymbolMapSourceKind, 'compiler-intrinsic') then
    Exit;
  if IsIntrinsicAllowlistFallback(aClassification) then
    Exit;

  Result := MatchText(aClassification.fReason, ['routine-scope', 'unit-qualifier', 'unit-source-not-indexed',
    'type-name']);
end;

function BuildMigrationTelemetryObject(const aResolverResult: TRemoveWithResolverResult;
  const aPlanResult: TRemoveWithPlanResult): TJSONObject;
var
  lClassification: TRemoveWithIdentifierClassification;
  lIntrinsicAllowlistFallbacks: Integer;
  lLocalModelHits: Integer;
  lPlannedCount: Integer;
  lSkippedCount: Integer;
  lSymbolMapHits: Integer;
  lSymbolMapMisses: Integer;
  lTrueUnknowns: Integer;
begin
  lIntrinsicAllowlistFallbacks := 0;
  lLocalModelHits := 0;
  lSymbolMapHits := 0;
  lSymbolMapMisses := 0;
  lTrueUnknowns := 0;
  CountPlanResult(aPlanResult, lPlannedCount, lSkippedCount);

  for lClassification in aResolverResult.fClassifications do
  begin
    if IsLocalModelHit(lClassification) then
      Inc(lLocalModelHits)
    else if SameText(RemoveWithDetailedReason(lClassification.fStatus, lClassification.fReason),
      'true-symbol-not-found') then
      Inc(lTrueUnknowns);

    if lClassification.fSymbolMapFound then
      Inc(lSymbolMapHits)
    else if SameText(lClassification.fSymbolMapReason, 'miss') then
      Inc(lSymbolMapMisses);

    if IsIntrinsicAllowlistFallback(lClassification) then
      Inc(lIntrinsicAllowlistFallbacks);
  end;

  Result := TJSONObject.Create;
  Result.AddPair('localModelHits', TJSONNumber.Create(lLocalModelHits));
  Result.AddPair('symbolMapHits', TJSONNumber.Create(lSymbolMapHits));
  Result.AddPair('symbolMapMisses', TJSONNumber.Create(lSymbolMapMisses));
  Result.AddPair('intrinsicAllowlistFallbacks', TJSONNumber.Create(lIntrinsicAllowlistFallbacks));
  Result.AddPair('trueUnknowns', TJSONNumber.Create(lTrueUnknowns));
  Result.AddPair('plannedEdits', TJSONNumber.Create(lPlannedCount));
  Result.AddPair('skippedStatements', TJSONNumber.Create(lSkippedCount));
  Result.AddPair('elapsedPlanningMs', TJSONNumber.Create(aPlanResult.fElapsedPlanningMs));
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

function BuildSymbolInventoryPhaseMetricsObject(
  const aMetrics: TRemoveWithFactSetPhaseMetrics): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('semanticProjectFactsMs',
    TJSONNumber.Create(aMetrics.fSemanticProjectFactsMs));
  Result.AddPair('semanticCompatibilityFactsMs',
    TJSONNumber.Create(aMetrics.fSemanticCompatibilityFactsMs));
  Result.AddPair('semanticBindingMs', TJSONNumber.Create(aMetrics.fSemanticBindingMs));
  Result.AddPair('semanticPlanDtoMs', TJSONNumber.Create(aMetrics.fSemanticPlanDtoMs));
  Result.AddPair('dakLookupIndexMs', TJSONNumber.Create(aMetrics.fDakLookupIndexMs));
  Result.AddPair('dakLookupCacheHits', TJSONNumber.Create(aMetrics.fDakLookupCacheHits));
  Result.AddPair('dakLookupCacheMisses', TJSONNumber.Create(aMetrics.fDakLookupCacheMisses));
  Result.AddPair('semanticModelExtractionMs',
    TJSONNumber.Create(aMetrics.fSemanticModelExtractionMs));
  Result.AddPair('semanticInventoryBuildMs',
    TJSONNumber.Create(aMetrics.fSemanticInventoryBuildMs));
  Result.AddPair('semanticScopeIndexBuildMs',
    TJSONNumber.Create(aMetrics.fSemanticScopeIndexBuildMs));
  Result.AddPair('semanticSelectorBindingMs',
    TJSONNumber.Create(aMetrics.fSemanticSelectorBindingMs));
  Result.AddPair('semanticReferenceBindingMs',
    TJSONNumber.Create(aMetrics.fSemanticReferenceBindingMs));
  Result.AddPair('semanticReceiverMemberResolveMs',
    TJSONNumber.Create(aMetrics.fSemanticReceiverMemberResolveMs));
  Result.AddPair('semanticLexicalResolveMs',
    TJSONNumber.Create(aMetrics.fSemanticLexicalResolveMs));
  Result.AddPair('semanticReferenceCacheHitCount',
    TJSONNumber.Create(aMetrics.fSemanticReferenceCacheHitCount));
  Result.AddPair('semanticReferenceCacheMissCount',
    TJSONNumber.Create(aMetrics.fSemanticReferenceCacheMissCount));
  Result.AddPair('semanticLookupIndexBuildMs',
    TJSONNumber.Create(aMetrics.fSemanticLookupIndexBuildMs));
  Result.AddPair('semanticBindingIndexBuildMs',
    TJSONNumber.Create(aMetrics.fSemanticBindingIndexBuildMs));
  Result.AddPair('semanticInventoryExpansionMs',
    TJSONNumber.Create(aMetrics.fSemanticInventoryExpansionMs));
  Result.AddPair('semanticCacheHits',
    TJSONNumber.Create(aMetrics.fSemanticCacheHits));
  Result.AddPair('semanticCacheMisses',
    TJSONNumber.Create(aMetrics.fSemanticCacheMisses));
  Result.AddPair('semanticCacheInvalidations',
    TJSONNumber.Create(aMetrics.fSemanticCacheInvalidations));
  Result.AddPair('rtlSourceEnrichmentMs', TJSONNumber.Create(aMetrics.fRtlSourceEnrichmentMs));
  Result.AddPair('externalUnitSymbolsMs', TJSONNumber.Create(aMetrics.fExternalUnitSymbolsMs));
  Result.AddPair('externalTypeSymbolsMs', TJSONNumber.Create(aMetrics.fExternalTypeSymbolsMs));
  Result.AddPair('problemSymbolAssemblyMs', TJSONNumber.Create(aMetrics.fProblemSymbolAssemblyMs));
end;

function BuildResolverReportPhaseMetricsObject(
  const aMetrics: TRemoveWithResolverReportMetrics): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('directSemanticProjectionMs',
    TJSONNumber.Create(aMetrics.fDirectSemanticProjectionMs));
  Result.AddPair('fallbackDecisionMs',
    TJSONNumber.Create(aMetrics.fFallbackDecisionMs));
  Result.AddPair('fallbackStatementCount',
    TJSONNumber.Create(aMetrics.fFallbackStatementCount));
  Result.AddPair('semanticReferenceCount',
    TJSONNumber.Create(aMetrics.fSemanticReferenceCount));
  Result.AddPair('fallbackScopedDeclarationCount',
    TJSONNumber.Create(aMetrics.fFallbackScopedDeclarationCount));
  Result.AddPair('fallbackScopeShadowCount',
    TJSONNumber.Create(aMetrics.fFallbackScopeShadowCount));
  Result.AddPair('fallbackMultiSelectorCount',
    TJSONNumber.Create(aMetrics.fFallbackMultiSelectorCount));
  Result.AddPair('fallbackUppercaseLexicalCount',
    TJSONNumber.Create(aMetrics.fFallbackUppercaseLexicalCount));
  Result.AddPair('fallbackHelperReceiverCount',
    TJSONNumber.Create(aMetrics.fFallbackHelperReceiverCount));
  Result.AddPair('fallbackInheritedMemberCount',
    TJSONNumber.Create(aMetrics.fFallbackInheritedMemberCount));
  Result.AddPair('fallbackUnsupportedReferenceCount',
    TJSONNumber.Create(aMetrics.fFallbackUnsupportedReferenceCount));
  Result.AddPair('fallbackStrictNonMemberCount',
    TJSONNumber.Create(aMetrics.fFallbackStrictNonMemberCount));
end;

function BuildPlannerPhaseMetricsObject(const aMetrics: TRemoveWithPlannerPhaseMetrics): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('totalMs', TJSONNumber.Create(aMetrics.fTotalMs));
  Result.AddPair('projectModelMs', TJSONNumber.Create(aMetrics.fProjectModelMs));
  Result.AddPair('discoveryMs', TJSONNumber.Create(aMetrics.fDiscoveryMs));
  Result.AddPair('symbolInventoryMs', TJSONNumber.Create(aMetrics.fSymbolInventoryMs));
  Result.AddPair('symbolInventorySubphaseMetrics',
    BuildSymbolInventoryPhaseMetricsObject(aMetrics.fSymbolInventoryPhaseMetrics));
  Result.AddPair('semanticProjectFactsMs',
    TJSONNumber.Create(aMetrics.fSemanticProjectFactsMs));
  Result.AddPair('semanticCompatibilityFactsMs',
    TJSONNumber.Create(aMetrics.fSemanticCompatibilityFactsMs));
  Result.AddPair('semanticBindingMs', TJSONNumber.Create(aMetrics.fSemanticBindingMs));
  Result.AddPair('semanticPlanDtoMs', TJSONNumber.Create(aMetrics.fSemanticPlanDtoMs));
  Result.AddPair('semanticCacheHits',
    TJSONNumber.Create(aMetrics.fSymbolInventoryPhaseMetrics.fSemanticCacheHits));
  Result.AddPair('semanticCacheMisses',
    TJSONNumber.Create(aMetrics.fSymbolInventoryPhaseMetrics.fSemanticCacheMisses));
  Result.AddPair('semanticCacheInvalidations',
    TJSONNumber.Create(aMetrics.fSymbolInventoryPhaseMetrics.fSemanticCacheInvalidations));
  Result.AddPair('snapshotSqlWriteMs',
    TJSONNumber.Create(aMetrics.fSymbolInventoryPhaseMetrics.fSnapshotSqlWriteMs));
  Result.AddPair('snapshotSqlReadMs',
    TJSONNumber.Create(aMetrics.fSymbolInventoryPhaseMetrics.fSnapshotSqlReadMs));
  Result.AddPair('snapshotDeserializeMs',
    TJSONNumber.Create(aMetrics.fSymbolInventoryPhaseMetrics.fSnapshotDeserializeMs));
  Result.AddPair('snapshotIndexRebuildMs',
    TJSONNumber.Create(aMetrics.fSymbolInventoryPhaseMetrics.fSnapshotIndexRebuildMs));
  Result.AddPair('dakLookupIndexMs', TJSONNumber.Create(aMetrics.fDakLookupIndexMs));
  Result.AddPair('dakLookupCacheHits', TJSONNumber.Create(aMetrics.fDakLookupCacheHits));
  Result.AddPair('dakLookupCacheMisses', TJSONNumber.Create(aMetrics.fDakLookupCacheMisses));
  Result.AddPair('dakResolverClassifyMs', TJSONNumber.Create(aMetrics.fDakResolverClassifyMs));
  Result.AddPair('resolverReportSubphaseMetrics',
    BuildResolverReportPhaseMetricsObject(aMetrics.fResolverReportMetrics));
  Result.AddPair('dakPlannerRewriteMs', TJSONNumber.Create(aMetrics.fDakPlannerRewriteMs));
  Result.AddPair('symbolMapBridgeMs', TJSONNumber.Create(aMetrics.fSymbolMapBridgeMs));
  Result.AddPair('resolverMs', TJSONNumber.Create(aMetrics.fResolverMs));
  Result.AddPair('plannerMs', TJSONNumber.Create(aMetrics.fPlannerMs));
  Result.AddPair('outputSerializationMs', TJSONNumber.Create(aMetrics.fOutputSerializationMs));
  Result.AddPair('contextFingerprint', aMetrics.fContextFingerprint);
  Result.AddPair('projectUnitCount', TJSONNumber.Create(aMetrics.fProjectUnitCount));
  Result.AddPair('parsedUnitCount', TJSONNumber.Create(aMetrics.fParsedUnitCount));
  Result.AddPair('projectProblemCount', TJSONNumber.Create(aMetrics.fProjectProblemCount));
  Result.AddPair('withStatementCount', TJSONNumber.Create(aMetrics.fWithStatementCount));
  Result.AddPair('symbolCount', TJSONNumber.Create(aMetrics.fSymbolCount));
  Result.AddPair('classificationCount', TJSONNumber.Create(aMetrics.fClassificationCount));
  Result.AddPair('plannedEditCount', TJSONNumber.Create(aMetrics.fPlannedEditCount));
  Result.AddPair('skippedStatementCount', TJSONNumber.Create(aMetrics.fSkippedStatementCount));
end;

function BuildSemanticDtoParityMismatchObject(
  const aMismatch: TDelphiSemanticRemoveWithPlanParityMismatch): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', aMismatch.Kind);
  Result.AddPair('statementId', aMismatch.StatementId);
  Result.AddPair('file', aMismatch.FileName);
  Result.AddPair('expectedStatus', aMismatch.ExpectedStatus);
  Result.AddPair('actualStatus', aMismatch.ActualStatus);
  Result.AddPair('reason', aMismatch.Reason);
  Result.AddPair('editKind', aMismatch.EditKind);
  Result.AddPair('editRange', aMismatch.EditRange);
  Result.AddPair('replacementTextDigest', aMismatch.ReplacementTextDigest);
  Result.AddPair('replacementTextExcerpt', aMismatch.ReplacementTextExcerpt);
  Result.AddPair('message', aMismatch.Message);
end;

function BuildSemanticDtoParityObject(
  const aReport: TDelphiSemanticRemoveWithPlanParityReport): TJSONObject;
var
  lMismatch: TDelphiSemanticRemoveWithPlanParityMismatch;
  lMismatches: TJSONArray;
begin
  Result := TJSONObject.Create;
  if aReport.MismatchCount = 0 then
    Result.AddPair('status', 'passed')
  else
    Result.AddPair('status', 'failed');
  Result.AddPair('mismatchCount', TJSONNumber.Create(aReport.MismatchCount));
  Result.AddPair('summaryText', aReport.SummaryText);
  lMismatches := TJSONArray.Create;
  for lMismatch in aReport.Mismatches do
    lMismatches.AddElement(BuildSemanticDtoParityMismatchObject(lMismatch));
  Result.AddPair('mismatches', lMismatches);
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
  const aTransactionResult: TRemoveWithTransactionResult; const aMetrics: TRemoveWithPlannerPhaseMetrics): string;
var
  lMetrics: TRemoveWithPlannerPhaseMetrics;
  lRoot: TJSONObject;
  lStopwatch: TStopwatch;
begin
  lMetrics := aMetrics;
  lStopwatch := TStopwatch.StartNew;
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('schemaVersion', TJSONNumber.Create(cRemoveWithSchemaVersion));
    lRoot.AddPair('operation', 'remove-with');
    lRoot.AddPair('status', BuildRootStatus(aOptions, aTransactionResult));
    lRoot.AddPair('mode', RemoveWithModeToText(aOptions.fRemoveWithMode));
    lRoot.AddPair('format', RemoveWithFormatToText(aOptions.fRemoveWithFormat));
    lRoot.AddPair('project', BuildProjectObject(aProjectPath, aMetrics));
    lRoot.AddPair('run', BuildRunObject(aRunId, aWorkspaceRoot));
    lRoot.AddPair('targets', BuildTargetsObject(aOptions, aUnitPath, aDirPath));
    lRoot.AddPair('workspace', BuildWorkspaceObject(aWorkspaceRoot));
    lRoot.AddPair('files', BuildFilesArray(aScanResult));
    if aOptions.fRemoveWithMode = TRemoveWithMode.rwmPlan then
      lRoot.AddPair('withStatements', TJSONArray.Create)
    else
      lRoot.AddPair('withStatements', BuildWithStatementsArray(aScanResult));
    lRoot.AddPair('resolver', BuildResolverObject(aResolverResult));
    lRoot.AddPair('plannedEdits', BuildPlannedEditsArray(aPlanResult));
    lRoot.AddPair('skipped', BuildSkippedArray(aPlanResult));
    lRoot.AddPair('warnings', BuildWarningsArray(aScanResult));
    lRoot.AddPair('requiredVerification',
      BuildRemoveWithRequiredVerificationArray(aPlanResult.fSemanticPlan.RequiredVerification));
    if aOptions.fRemoveWithMode = TRemoveWithMode.rwmApply then
      lRoot.AddPair('verification', BuildApplyVerificationObject(aTransactionResult,
        aPlanResult.fSemanticPlan.RequiredVerification))
    else
      lRoot.AddPair('verification', BuildVerificationObject(
        aPlanResult.fSemanticPlan.RequiredVerification));
    lRoot.AddPair('transaction', BuildTransactionObject(aTransactionResult));
    if aOptions.fRemoveWithDiagnostics then
      lRoot.AddPair('migrationTelemetry', BuildMigrationTelemetryObject(aResolverResult, aPlanResult));
    lRoot.AddPair('summary', BuildSummaryObject(aOptions, aScanResult, aPlanResult, aTransactionResult));
    if aOptions.fRemoveWithDiagnostics and (aOptions.fRemoveWithMode = TRemoveWithMode.rwmPlan) then
      lRoot.AddPair('semanticDtoParity', BuildSemanticDtoParityObject(
        aPlanResult.fSemanticParityReport));
    lMetrics.fOutputSerializationMs := lStopwatch.ElapsedMilliseconds;
    if aOptions.fRemoveWithDiagnostics then
      lRoot.AddPair('plannerPhaseMetrics', BuildPlannerPhaseMetricsObject(lMetrics));
    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

function BuildRemoveWithTextReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult;
  const aPlanResult: TRemoveWithPlanResult; const aTransactionResult: TRemoveWithTransactionResult;
  const aMetrics: TRemoveWithPlannerPhaseMetrics): string;
var
  lAppliedCount: Integer;
  lPlannedCount: Integer;
  lRolledBackCount: Integer;
  lSkippedCount: Integer;
  lStatusText: string;
  lTargetValue: string;
  lVerificationText: string;
begin
  CountPlanResult(aPlanResult, lPlannedCount, lSkippedCount);
  lStatusText := BuildRootStatus(aOptions, aTransactionResult);
  lVerificationText := aTransactionResult.fVerificationStatus;
  if lVerificationText = '' then
    lVerificationText := 'not-run';
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
    'contextMode=' + aMetrics.fContextMode + sLineBreak +
    IfThen(aMetrics.fContextNote <> '', 'contextNote=' + aMetrics.fContextNote + sLineBreak, '') +
    'run=' + aRunId + sLineBreak +
    'target=' + RemoveWithTargetKindToText(aOptions.fRemoveWithTargetKind) + ':' + lTargetValue + sLineBreak +
    'workspace=' + aWorkspaceRoot + sLineBreak +
    'filesScanned=' + IntToStr(Length(aScanResult.fFiles)) + sLineBreak +
    'withStatements=' + IntToStr(Length(aScanResult.fWithStatements)) + sLineBreak +
    'plannedEdits=' + IntToStr(lPlannedCount) + sLineBreak +
    'appliedEdits=' + IntToStr(lAppliedCount) + sLineBreak +
    'skipped=' + IntToStr(lSkippedCount) + sLineBreak +
    BuildWarningsText(aScanResult) + sLineBreak +
    'failed=0' + sLineBreak +
    'rolledBack=' + IntToStr(lRolledBackCount) + sLineBreak +
    'transactionManifest=' + aTransactionResult.fManifestPath + sLineBreak +
    'verification=' + lVerificationText;
end;

end.
