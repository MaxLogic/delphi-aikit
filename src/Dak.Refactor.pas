unit Dak.Refactor;

interface

uses
  Dak.Types;

function RunFindUsagesCommand(const aOptions: TAppOptions): Integer;
function RunRenameCommand(const aOptions: TAppOptions): Integer;
function RunDeadCodeCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Classes, System.Diagnostics, System.Generics.Collections, System.Hash, System.IOUtils,
  System.JSON, System.SysUtils,
  DelphiSemantics.DeadCode, DelphiSemantics.Model.Text, DelphiSemantics.ProjectContext,
  DelphiSemantics.Refactor, DelphiSemantics.Usage,
  Dak.Build, Dak.DeadCodeProfile, Dak.ExitCodes, Dak.Paths, Dak.Refactor.RenameGuards,
  Dak.Semantics.Session, Dak.SourceText;

type
  TRefactorSemanticPhaseMetrics = record
    ProjectContextMs: Int64;
    ProjectUnitIndexMs: Int64;
    ProjectUnitCount: Integer;
    UnitModelExtractionMs: Int64;
    UnitModelExtractionCount: Integer;
    ProjectSymbolIndexBuildMs: Int64;
    ProjectSymbolIndexBuildCount: Integer;
    ReferenceReconciliationFallbackCount: Integer;
    CommandPlanningMs: Int64;
    CommandPlanningCount: Integer;
    TotalMs: Int64;
  end;

  TAppliedFile = record
    FileName: string;
    BackupFileName: string;
    Hash: string;
  end;

  TRenameVerification = record
    Status: string;
    ExitCode: Integer;
    Diagnostic: string;
    DiagnosticsDir: string;
  end;

  TDeadCodeApplyResult = record
    Status: string;
    Diagnostic: string;
    ManifestPath: string;
    AppliedFiles: TArray<TAppliedFile>;
    Verification: TRenameVerification;
  end;

function JsonValueText(const aValue: TJSONValue): string;
begin
  try
    Result := aValue.ToJSON;
  finally
    aValue.Free;
  end;
end;

function BuildJsonStringArray(const aValues: array of string): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(aValues) do
    Result.Add(aValues[i]);
end;

function CommaText(const aValues: array of string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(aValues) do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + aValues[i];
  end;
end;

function FileHash(const aBytes: TBytes): string;
var
  lHash: THashSHA2;
begin
  lHash := THashSHA2.Create;
  if Length(aBytes) > 0 then
    lHash.Update(aBytes);
  Result := lHash.HashAsString;
end;

function SameFileNameSafe(const aLeft, aRight: string): Boolean;
begin
  if (aLeft = '') or (aRight = '') then
    Exit(False);
  try
    Result := SameText(TPath.GetFullPath(aLeft), TPath.GetFullPath(aRight));
  except
    Result := SameText(aLeft, aRight);
  end;
end;

function BuildSemanticContext(const aOptions: TAppOptions;
  out aContext: IDakSemanticSymbolQueryContext; out aCacheMetrics: TDakSemanticCacheMetrics;
  out aPhaseMetrics: TRefactorSemanticPhaseMetrics; out aError: string): Boolean;
var
  lMetrics: TDakSemanticSymbolQueryMetrics;
  lSessionOptions: TDelphiSemanticOptions;
  lTotalStopwatch: TStopwatch;
begin
  Result := False;
  aError := '';
  aContext := nil;
  aCacheMetrics := Default(TDakSemanticCacheMetrics);
  aPhaseMetrics := Default(TRefactorSemanticPhaseMetrics);
  lTotalStopwatch := TStopwatch.StartNew;
  if aOptions.fHasRefactorSemanticCachePath then
    lSessionOptions := BuildSemanticSessionOptions(aOptions.fDprojPath, aOptions.fConfig,
      aOptions.fPlatform, aOptions.fDelphiVersion, aOptions.fRsVarsPath,
      aOptions.fEnvOptionsPath, aOptions.fRefactorSemanticCachePath)
  else
    lSessionOptions := BuildSemanticSessionOptions(aOptions.fDprojPath, aOptions.fConfig,
      aOptions.fPlatform, aOptions.fDelphiVersion, aOptions.fRsVarsPath,
      aOptions.fEnvOptionsPath, '');
  Result := OpenSemanticSymbolQueryContext(lSessionOptions, aContext, lMetrics, aError,
    True);
  aCacheMetrics := lMetrics.CacheMetrics;
  aPhaseMetrics.ProjectContextMs := lMetrics.SessionOpenMilliseconds;
  if not Result then
    Exit(False);

  aPhaseMetrics.ProjectUnitCount := aContext.UnitModelCount;
  aPhaseMetrics.UnitModelExtractionCount := aPhaseMetrics.ProjectUnitCount;
  aPhaseMetrics.UnitModelExtractionMs := lMetrics.ExtractionMilliseconds;
  aPhaseMetrics.ReferenceReconciliationFallbackCount := aContext.ReferenceFallbackCount;
  aPhaseMetrics.TotalMs := lTotalStopwatch.ElapsedMilliseconds;
  Result := True;
end;

function BuildSemanticPhaseMetricsObject(const aPhaseMetrics: TRefactorSemanticPhaseMetrics;
  const aCacheMetrics: TDakSemanticCacheMetrics): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('projectContextMs', TJSONNumber.Create(aPhaseMetrics.ProjectContextMs));
  Result.AddPair('projectUnitIndexMs', TJSONNumber.Create(aPhaseMetrics.ProjectUnitIndexMs));
  Result.AddPair('projectUnitCount', TJSONNumber.Create(aPhaseMetrics.ProjectUnitCount));
  Result.AddPair('unitModelExtractionMs', TJSONNumber.Create(aPhaseMetrics.UnitModelExtractionMs));
  Result.AddPair('unitModelExtractionCount',
    TJSONNumber.Create(aPhaseMetrics.UnitModelExtractionCount));
  Result.AddPair('semanticCacheWorkMs', TJSONNumber.Create(aPhaseMetrics.UnitModelExtractionMs));
  Result.AddPair('projectSymbolIndexBuildMs',
    TJSONNumber.Create(aPhaseMetrics.ProjectSymbolIndexBuildMs));
  Result.AddPair('projectSymbolIndexBuildCount',
    TJSONNumber.Create(aPhaseMetrics.ProjectSymbolIndexBuildCount));
  Result.AddPair('commandPlanningMs', TJSONNumber.Create(aPhaseMetrics.CommandPlanningMs));
  Result.AddPair('commandPlanningCount', TJSONNumber.Create(aPhaseMetrics.CommandPlanningCount));
  Result.AddPair('totalMs', TJSONNumber.Create(aPhaseMetrics.TotalMs));
  Result.AddPair('semanticCacheHits', TJSONNumber.Create(aCacheMetrics.CacheHits));
  Result.AddPair('semanticCacheMisses', TJSONNumber.Create(aCacheMetrics.CacheMisses));
  Result.AddPair('semanticCacheInvalidations', TJSONNumber.Create(aCacheMetrics.Invalidations));
end;

function BuildUsageObject(const aUsage: TDelphiSemanticUsage): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', aUsage.Name);
  Result.AddPair('role', aUsage.Role);
  Result.AddPair('routine', aUsage.RoutineName);
  Result.AddPair('section', aUsage.SectionKind);
  Result.AddPair('sourceKind', aUsage.SourceKind);
  Result.AddPair('file', aUsage.FileName);
  Result.AddPair('unit', aUsage.UnitName);
  Result.AddPair('line', TJSONNumber.Create(aUsage.Line));
  Result.AddPair('column', TJSONNumber.Create(aUsage.Column));
  Result.AddPair('endLine', TJSONNumber.Create(aUsage.EndLine));
  Result.AddPair('endColumn', TJSONNumber.Create(aUsage.EndColumn));
end;

function UsageResultJson(const aSymbol: string; const aResult: TDelphiSemanticUsageResult;
  const aReferenceFallbackCount: Integer; const aCacheMetrics: TDakSemanticCacheMetrics;
  const aPhaseMetrics: TRefactorSemanticPhaseMetrics): string;
var
  i: Integer;
  lRoot: TJSONObject;
  lUsages: TJSONArray;
begin
  lRoot := TJSONObject.Create;
  lUsages := TJSONArray.Create;
  for i := 0 to High(aResult.Usages) do
    lUsages.AddElement(BuildUsageObject(aResult.Usages[i]));

  lRoot.AddPair('status', aResult.Status);
  lRoot.AddPair('symbol', aSymbol);
  lRoot.AddPair('diagnostic', aResult.Diagnostic);
  lRoot.AddPair('count', TJSONNumber.Create(Length(aResult.Usages)));
  lRoot.AddPair('referenceReconciliationFallbackCount',
    TJSONNumber.Create(aReferenceFallbackCount));
  lRoot.AddPair('semanticCacheHits', TJSONNumber.Create(aCacheMetrics.CacheHits));
  lRoot.AddPair('semanticCacheMisses', TJSONNumber.Create(aCacheMetrics.CacheMisses));
  lRoot.AddPair('semanticCacheInvalidations', TJSONNumber.Create(aCacheMetrics.Invalidations));
  lRoot.AddPair('semanticPhaseMetrics', BuildSemanticPhaseMetricsObject(aPhaseMetrics,
    aCacheMetrics));
  lRoot.AddPair('usages', lUsages);
  Result := JsonValueText(lRoot);
end;

function UsageResultText(const aSymbol: string; const aResult: TDelphiSemanticUsageResult):
  string;
var
  lBuilder: TStringBuilder;
  lUsage: TDelphiSemanticUsage;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('find-usages: ' + aResult.Status);
    lBuilder.AppendLine('symbol: ' + aSymbol);
    lBuilder.AppendLine('count: ' + Length(aResult.Usages).ToString);
    if aResult.Diagnostic <> '' then
      lBuilder.AppendLine('diagnostic: ' + aResult.Diagnostic);
    for lUsage in aResult.Usages do
      lBuilder.AppendLine(Format('%s %s %s:%d:%d', [lUsage.Role, lUsage.UnitName,
        lUsage.FileName, lUsage.Line, lUsage.Column]));
    Result := TrimRight(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

function BuildEditObject(const aEdit: TDelphiSemanticTextEdit): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', aEdit.FileName);
  Result.AddPair('role', aEdit.Role);
  Result.AddPair('startLine', TJSONNumber.Create(aEdit.StartLine));
  Result.AddPair('startColumn', TJSONNumber.Create(aEdit.StartColumn));
  Result.AddPair('endLine', TJSONNumber.Create(aEdit.EndLine));
  Result.AddPair('endColumn', TJSONNumber.Create(aEdit.EndColumn));
  Result.AddPair('expectedFileHash', aEdit.ExpectedFileHash);
  Result.AddPair('expectedSourceText', aEdit.ExpectedSourceText);
  Result.AddPair('newText', aEdit.NewText);
end;

function BuildRenameRequiredVerificationArray(
  const aValues: TArray<TDelphiSemanticRenameVerification>): TJSONArray;
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

function BuildAppliedFilesArray(const aFiles: TArray<TAppliedFile>): TJSONArray;
var
  i: Integer;
  lFile: TJSONObject;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(aFiles) do
  begin
    lFile := TJSONObject.Create;
    lFile.AddPair('file', aFiles[i].FileName);
    lFile.AddPair('backup', aFiles[i].BackupFileName);
    lFile.AddPair('hash', aFiles[i].Hash);
    Result.AddElement(lFile);
  end;
end;

function RenameVerification(const aStatus: string; aExitCode: Integer;
  const aDiagnostic, aDiagnosticsDir: string): TRenameVerification;
begin
  Result.Status := aStatus;
  Result.ExitCode := aExitCode;
  Result.Diagnostic := aDiagnostic;
  Result.DiagnosticsDir := aDiagnosticsDir;
end;

function BuildRenameVerificationObject(const aVerification: TRenameVerification): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', aVerification.Status);
  Result.AddPair('exitCode', TJSONNumber.Create(aVerification.ExitCode));
  Result.AddPair('diagnostic', aVerification.Diagnostic);
  Result.AddPair('diagnosticsDir', aVerification.DiagnosticsDir);
end;

function RenameResultJson(const aSymbol: string; const aPlan: TDelphiSemanticRenamePlan;
  const aApply: Boolean; const aAppliedFiles: TArray<TAppliedFile>;
  const aVerification: TRenameVerification;
  const aReferenceFallbackCount: Integer; const aCacheMetrics: TDakSemanticCacheMetrics;
  const aPhaseMetrics: TRefactorSemanticPhaseMetrics): string;
var
  i: Integer;
  lEdits: TJSONArray;
  lRoot: TJSONObject;
  lStatus: string;
begin
  lStatus := aPlan.Status;
  if aApply and SameText(lStatus, 'planned') then
    lStatus := 'applied';
  lRoot := TJSONObject.Create;
  lEdits := TJSONArray.Create;
  for i := 0 to High(aPlan.Edits) do
    lEdits.AddElement(BuildEditObject(aPlan.Edits[i]));

  lRoot.AddPair('status', lStatus);
  lRoot.AddPair('symbol', aSymbol);
  lRoot.AddPair('apply', TJSONBool.Create(aApply));
  lRoot.AddPair('diagnostic', aPlan.Diagnostic);
  lRoot.AddPair('editCount', TJSONNumber.Create(Length(aPlan.Edits)));
  lRoot.AddPair('contextFingerprint', aPlan.ContextFingerprint);
  lRoot.AddPair('baselineSemanticModelVersion', aPlan.BaselineSemanticModelVersion);
  lRoot.AddPair('requiredVerification',
    BuildRenameRequiredVerificationArray(aPlan.RequiredVerification));
  lRoot.AddPair('verification', BuildRenameVerificationObject(aVerification));
  lRoot.AddPair('referenceReconciliationFallbackCount',
    TJSONNumber.Create(aReferenceFallbackCount));
  lRoot.AddPair('semanticCacheHits', TJSONNumber.Create(aCacheMetrics.CacheHits));
  lRoot.AddPair('semanticCacheMisses', TJSONNumber.Create(aCacheMetrics.CacheMisses));
  lRoot.AddPair('semanticCacheInvalidations', TJSONNumber.Create(aCacheMetrics.Invalidations));
  lRoot.AddPair('semanticPhaseMetrics', BuildSemanticPhaseMetricsObject(aPhaseMetrics,
    aCacheMetrics));
  lRoot.AddPair('edits', lEdits);
  lRoot.AddPair('appliedFiles', BuildAppliedFilesArray(aAppliedFiles));
  Result := JsonValueText(lRoot);
end;

function RenameResultText(const aSymbol: string; const aPlan: TDelphiSemanticRenamePlan;
  const aApply: Boolean; const aAppliedFiles: TArray<TAppliedFile>;
  const aVerification: TRenameVerification): string;
var
  lAppliedFile: TAppliedFile;
  lBuilder: TStringBuilder;
  lEdit: TDelphiSemanticTextEdit;
  lStatus: string;
begin
  lStatus := aPlan.Status;
  if aApply and SameText(lStatus, 'planned') then
    lStatus := 'applied';
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('rename: ' + lStatus);
    lBuilder.AppendLine('symbol: ' + aSymbol);
    lBuilder.AppendLine('apply: ' + LowerCase(BoolToStr(aApply, True)));
    lBuilder.AppendLine('edits: ' + Length(aPlan.Edits).ToString);
    lBuilder.AppendLine('verification: ' + aVerification.Status);
    if aVerification.Diagnostic <> '' then
      lBuilder.AppendLine('verificationDiagnostic: ' + aVerification.Diagnostic);
    if aVerification.DiagnosticsDir <> '' then
      lBuilder.AppendLine('verificationDiagnosticsDir: ' + aVerification.DiagnosticsDir);
    if aPlan.Diagnostic <> '' then
      lBuilder.AppendLine('diagnostic: ' + aPlan.Diagnostic);
    for lEdit in aPlan.Edits do
      lBuilder.AppendLine(Format('%s:%d:%d %s', [lEdit.FileName, lEdit.StartLine,
        lEdit.StartColumn, lEdit.NewText]));
    for lAppliedFile in aAppliedFiles do
      lBuilder.AppendLine('backup: ' + lAppliedFile.BackupFileName);
    Result := TrimRight(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

function DeadCodeReportJson(const aReport: TDelphiSemanticDeadCodeReport;
  const aReferenceFallbackCount: Integer; const aCacheMetrics: TDakSemanticCacheMetrics;
  const aPhaseMetrics: TRefactorSemanticPhaseMetrics): string;
var
  i: Integer;
  lCandidate: TDelphiSemanticDeadCodeCandidate;
  lCandidateObject: TJSONObject;
  lCandidates: TJSONArray;
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  lCandidates := TJSONArray.Create;
  for i := 0 to High(aReport.Candidates) do
  begin
    lCandidate := aReport.Candidates[i];
    lCandidateObject := TJSONObject.Create;
    lCandidateObject.AddPair('name', lCandidate.Name);
    lCandidateObject.AddPair('kind', lCandidate.Kind);
    lCandidateObject.AddPair('unit', lCandidate.UnitName);
    lCandidateObject.AddPair('owner', lCandidate.OwnerName);
    lCandidateObject.AddPair('file', lCandidate.FileName);
    lCandidateObject.AddPair('line', TJSONNumber.Create(lCandidate.Line));
    lCandidateObject.AddPair('column', TJSONNumber.Create(lCandidate.Column));
    lCandidateObject.AddPair('status', lCandidate.Status);
    lCandidateObject.AddPair('reason', lCandidate.Reason);
    lCandidateObject.AddPair('safetyProfile', lCandidate.SafetyProfile);
    lCandidateObject.AddPair('referenceCount', TJSONNumber.Create(lCandidate.ReferenceCount));
    lCandidateObject.AddPair('blockers', BuildJsonStringArray(lCandidate.Blockers));
    lCandidates.AddElement(lCandidateObject);
  end;

  lRoot.AddPair('status', 'ok');
  lRoot.AddPair('profile', aReport.Profile);
  lRoot.AddPair('count', TJSONNumber.Create(Length(aReport.Candidates)));
  lRoot.AddPair('referenceReconciliationFallbackCount',
    TJSONNumber.Create(aReferenceFallbackCount));
  lRoot.AddPair('semanticCacheHits', TJSONNumber.Create(aCacheMetrics.CacheHits));
  lRoot.AddPair('semanticCacheMisses', TJSONNumber.Create(aCacheMetrics.CacheMisses));
  lRoot.AddPair('semanticCacheInvalidations', TJSONNumber.Create(aCacheMetrics.Invalidations));
  lRoot.AddPair('semanticPhaseMetrics', BuildSemanticPhaseMetricsObject(aPhaseMetrics,
    aCacheMetrics));
  lRoot.AddPair('candidates', lCandidates);
  Result := JsonValueText(lRoot);
end;

function DeadCodeReportText(const aReport: TDelphiSemanticDeadCodeReport): string;
var
  lBuilder: TStringBuilder;
  lCandidate: TDelphiSemanticDeadCodeCandidate;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('dead-code: report');
    lBuilder.AppendLine('profile: ' + aReport.Profile);
    lBuilder.AppendLine('candidates: ' + IntToStr(Length(aReport.Candidates)));
    for lCandidate in aReport.Candidates do
      lBuilder.AppendLine(Format('%s %s %s %s:%d:%d refs=%d profile=%s reason=%s blockers=%s',
        [lCandidate.Status, lCandidate.Kind, lCandidate.Name, lCandidate.FileName,
        lCandidate.Line, lCandidate.Column, lCandidate.ReferenceCount, lCandidate.SafetyProfile,
        lCandidate.Reason, CommaText(lCandidate.Blockers)]));
    Result := lBuilder.ToString.TrimRight;
  finally
    lBuilder.Free;
  end;
end;

function BuildDeadCodeBlockersArray(
  const aBlockers: TArray<TDelphiSemanticDeadCodeRemovalBlocker>): TJSONArray;
var
  lBlocker: TDelphiSemanticDeadCodeRemovalBlocker;
  lValue: TJSONObject;
begin
  Result := TJSONArray.Create;
  for lBlocker in aBlockers do
  begin
    lValue := TJSONObject.Create;
    lValue.AddPair('name', lBlocker.Name);
    lValue.AddPair('status', lBlocker.Status);
    lValue.AddPair('reason', lBlocker.Reason);
    Result.AddElement(lValue);
  end;
end;

function DeadCodeApplyJson(const aPlan: TDelphiSemanticDeadCodeRemovalPlan;
  const aApplyResult: TDeadCodeApplyResult; const aReferenceFallbackCount: Integer;
  const aCacheMetrics: TDakSemanticCacheMetrics; const aPhaseMetrics: TRefactorSemanticPhaseMetrics):
  string;
var
  lEdit: TDelphiSemanticTextEdit;
  lEdits: TJSONArray;
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  lEdits := TJSONArray.Create;
  for lEdit in aPlan.Edits do
    lEdits.AddElement(BuildEditObject(lEdit));

  lRoot.AddPair('status', aApplyResult.Status);
  lRoot.AddPair('apply', TJSONBool.Create(True));
  lRoot.AddPair('profile', aPlan.Profile);
  lRoot.AddPair('diagnostic', aApplyResult.Diagnostic);
  lRoot.AddPair('planDiagnostic', aPlan.Diagnostic);
  lRoot.AddPair('editCount', TJSONNumber.Create(Length(aPlan.Edits)));
  lRoot.AddPair('blockerCount', TJSONNumber.Create(Length(aPlan.Blockers)));
  lRoot.AddPair('manifest', aApplyResult.ManifestPath);
  lRoot.AddPair('verification', BuildRenameVerificationObject(aApplyResult.Verification));
  lRoot.AddPair('referenceReconciliationFallbackCount',
    TJSONNumber.Create(aReferenceFallbackCount));
  lRoot.AddPair('semanticCacheHits', TJSONNumber.Create(aCacheMetrics.CacheHits));
  lRoot.AddPair('semanticCacheMisses', TJSONNumber.Create(aCacheMetrics.CacheMisses));
  lRoot.AddPair('semanticCacheInvalidations', TJSONNumber.Create(aCacheMetrics.Invalidations));
  lRoot.AddPair('semanticPhaseMetrics', BuildSemanticPhaseMetricsObject(aPhaseMetrics,
    aCacheMetrics));
  lRoot.AddPair('edits', lEdits);
  lRoot.AddPair('blockers', BuildDeadCodeBlockersArray(aPlan.Blockers));
  lRoot.AddPair('files', BuildAppliedFilesArray(aApplyResult.AppliedFiles));
  Result := JsonValueText(lRoot);
end;

function DeadCodeApplyText(const aPlan: TDelphiSemanticDeadCodeRemovalPlan;
  const aApplyResult: TDeadCodeApplyResult): string;
var
  lAppliedFile: TAppliedFile;
  lBuilder: TStringBuilder;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('dead-code: ' + aApplyResult.Status);
    lBuilder.AppendLine('profile: ' + aPlan.Profile);
    lBuilder.AppendLine('apply: true');
    lBuilder.AppendLine('edits: ' + Length(aPlan.Edits).ToString);
    lBuilder.AppendLine('blockers: ' + Length(aPlan.Blockers).ToString);
    lBuilder.AppendLine('verification: ' + aApplyResult.Verification.Status);
    if aApplyResult.Diagnostic <> '' then
      lBuilder.AppendLine('diagnostic: ' + aApplyResult.Diagnostic);
    if aApplyResult.ManifestPath <> '' then
      lBuilder.AppendLine('manifest: ' + aApplyResult.ManifestPath);
    for lAppliedFile in aApplyResult.AppliedFiles do
      lBuilder.AppendLine('backup: ' + lAppliedFile.BackupFileName);
    Result := TrimRight(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

procedure SortEditsDescending(var aEdits: TArray<TDelphiSemanticTextEdit>);
var
  i: Integer;
  lChanged: Boolean;
  lTemp: TDelphiSemanticTextEdit;
begin
  repeat
    lChanged := False;
    for i := 0 to High(aEdits) - 1 do
    begin
      if (aEdits[i].StartLine < aEdits[i + 1].StartLine) or
        ((aEdits[i].StartLine = aEdits[i + 1].StartLine) and
        (aEdits[i].StartColumn < aEdits[i + 1].StartColumn)) then
      begin
        lTemp := aEdits[i];
        aEdits[i] := aEdits[i + 1];
        aEdits[i + 1] := lTemp;
        lChanged := True;
      end;
    end;
  until not lChanged;
end;

function IdentifierLengthAtOffset(const aText: string; const aOffset: Integer): Integer;
var
  lIndex: Integer;
begin
  Result := 0;
  if (aOffset < 1) or (aOffset > Length(aText)) or not IsIdentifierChar(aText[aOffset]) then
    Exit;

  lIndex := aOffset;
  while (lIndex <= Length(aText)) and IsIdentifierChar(aText[lIndex]) do
  begin
    Inc(Result);
    Inc(lIndex);
  end;
end;

function TryIdentifierSpanAtOffset(const aText: string; const aOffset: Integer;
  const aExpectedName: string; out aStartOffset, aEndOffset: Integer): Boolean;
var
  lEndOffset: Integer;
  lStartOffset: Integer;
  lToken: string;
begin
  Result := False;
  aStartOffset := 0;
  aEndOffset := 0;
  if (aOffset < 1) or (aOffset > Length(aText)) or not IsIdentifierChar(aText[aOffset]) then
    Exit;

  lStartOffset := aOffset;
  while (lStartOffset > 1) and IsIdentifierChar(aText[lStartOffset - 1]) do
    Dec(lStartOffset);
  lEndOffset := aOffset;
  while (lEndOffset < Length(aText)) and IsIdentifierChar(aText[lEndOffset + 1]) do
    Inc(lEndOffset);
  lToken := Copy(aText, lStartOffset, lEndOffset - lStartOffset + 1);
  if not SameText(lToken, aExpectedName) then
    Exit;

  aStartOffset := lStartOffset;
  aEndOffset := lEndOffset;
  Result := True;
end;

function ResolveEditEndOffset(const aSource: TDakSourceBuffer;
  const aEdit: TDelphiSemanticTextEdit; const aStartOffset: Integer; out aEndOffset: Integer):
  Boolean;
var
  lLength: Integer;
begin
  if (aEdit.EndLine = aEdit.StartLine) and
    DakOffsetForLineColumn(aSource, aEdit.EndLine, aEdit.EndColumn, aEndOffset) and
    (aEndOffset >= aStartOffset) and (aEndOffset <= Length(aSource.fText)) then
    Exit(True);

  lLength := IdentifierLengthAtOffset(aSource.fText, aStartOffset);
  if lLength < 1 then
  begin
    aEndOffset := 0;
    Exit(False);
  end;
  aEndOffset := aStartOffset + lLength - 1;
  Result := True;
end;

procedure ApplyEditToSource(const aEdit: TDelphiSemanticTextEdit; const aOriginalName: string;
  const aSource: TDakSourceBuffer; var aText: string);
var
  lEndOffset: Integer;
  lStartOffset: Integer;
  lTokenStartOffset: Integer;
  lToken: string;
begin
  if not DakOffsetForLineColumn(aSource, aEdit.StartLine, aEdit.StartColumn,
    lStartOffset) then
    raise Exception.Create('Invalid rename edit start in ' + aEdit.FileName);
  if TryIdentifierSpanAtOffset(aSource.fText, lStartOffset, aOriginalName, lTokenStartOffset,
    lEndOffset) then
  begin
    lStartOffset := lTokenStartOffset;
  end else begin
    if not ResolveEditEndOffset(aSource, aEdit, lStartOffset, lEndOffset) then
      raise Exception.Create('Invalid rename edit range in ' + aEdit.FileName);
    lToken := Copy(aSource.fText, lStartOffset, lEndOffset - lStartOffset + 1);
    if not SameText(lToken, aOriginalName) then
      raise Exception.Create('Rename range does not match expected symbol in ' + aEdit.FileName);
  end;

  Delete(aText, lStartOffset, lEndOffset - lStartOffset + 1);
  Insert(aEdit.NewText, aText, lStartOffset);
end;

function AddAppliedFile(var aFiles: TArray<TAppliedFile>; const aFileName,
  aBackupFileName, aHash: string): Integer;
begin
  Result := Length(aFiles);
  SetLength(aFiles, Result + 1);
  aFiles[Result].FileName := aFileName;
  aFiles[Result].BackupFileName := aBackupFileName;
  aFiles[Result].Hash := aHash;
end;

function RenameWorkspaceRoot(const aOptions: TAppOptions): string;
var
  lProjectPath: string;
begin
  lProjectPath := TPath.GetFullPath(aOptions.fDprojPath);
  Result := DakProjectPath(DakProjectRootForProjectPath(lProjectPath),
    ['rename', FormatDateTime('yyyymmddhhnnsszzz', Now)]);
end;

procedure WriteRenameManifest(const aWorkspaceRoot, aStatus, aError: string;
  const aFiles: TArray<TAppliedFile>; const aVerification: TRenameVerification);
var
  lJson: string;
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  lRoot.AddPair('status', aStatus);
  lRoot.AddPair('error', aError);
  lRoot.AddPair('verification', BuildRenameVerificationObject(aVerification));
  lRoot.AddPair('files', BuildAppliedFilesArray(aFiles));
  lJson := JsonValueText(lRoot);
  TDirectory.CreateDirectory(aWorkspaceRoot);
  TFile.WriteAllText(TPath.Combine(aWorkspaceRoot, 'manifest.json'), lJson, TEncoding.UTF8);
end;

function RenameBuildVerificationOptions(const aOptions: TAppOptions;
  const aDiagnosticsDir: string): TAppOptions;
begin
  Result := aOptions;
  Result.fCommand := TCommandKind.ckBuild;
  Result.fBuildAi := False;
  Result.fBuildJson := False;
  Result.fBuildQuiet := True;
  Result.fBuildRunDfmCheck := False;
  Result.fBuildDiagnosticsDir := aDiagnosticsDir;
  if Trim(Result.fBuildTarget) = '' then
    Result.fBuildTarget := 'Build';
  if Result.fBuildMaxFindings <= 0 then
    Result.fBuildMaxFindings := 5;
end;

function VerifyRenameBuild(const aOptions: TAppOptions; const aWorkspaceRoot: string;
  out aVerification: TRenameVerification): Boolean;
var
  lBuildOptions: TAppOptions;
  lDiagnosticsDir: string;
  lError: string;
  lExitCode: Integer;
begin
  Result := False;
  lDiagnosticsDir := TPath.Combine(aWorkspaceRoot, 'build-verification');
  lBuildOptions := RenameBuildVerificationOptions(aOptions, lDiagnosticsDir);
  lError := '';
  lExitCode := 1;
  if not TryRunBuild(lBuildOptions, lExitCode, lError) then
  begin
    if lError = '' then
      lError := 'Build verification could not start.';
    aVerification := RenameVerification('failed', lExitCode,
      'Build verification failed: ' + lError + ' Diagnostics: ' + lDiagnosticsDir,
      lDiagnosticsDir);
    Exit(False);
  end;

  if lExitCode <> 0 then
  begin
    aVerification := RenameVerification('failed', lExitCode,
      Format('Build verification failed with exit code %d. Diagnostics: %s',
      [lExitCode, lDiagnosticsDir]), lDiagnosticsDir);
    Exit(False);
  end;

  aVerification := RenameVerification('passed', lExitCode, '', lDiagnosticsDir);
  Result := True;
end;

procedure ApplyRenamePlan(const aOptions: TAppOptions; const aPlan: TDelphiSemanticRenamePlan;
  const aOriginalName: string; out aAppliedFiles: TArray<TAppliedFile>;
  out aVerification: TRenameVerification);
var
  lBackupRoot: string;
  lBackupFileName: string;
  lBytes: TBytes;
  lEdit: TDelphiSemanticTextEdit;
  lEdits: TArray<TDelphiSemanticTextEdit>;
  lFileName: string;
  lGuardError: string;
  lManifestError: string;
  lOriginals: TDictionary<string, TBytes>;
  lPair: TPair<string, TBytes>;
  lSource: TDakSourceBuffer;
  lText: string;
  lWorkspaceRoot: string;
begin
  SetLength(aAppliedFiles, 0);
  aVerification := RenameVerification('not-run', -1, '', '');
  lOriginals := TDictionary<string, TBytes>.Create;
  lWorkspaceRoot := RenameWorkspaceRoot(aOptions);
  lBackupRoot := TPath.Combine(lWorkspaceRoot, 'backup');
  try
    try
      for lEdit in aPlan.Edits do
      begin
        lFileName := TPath.GetFullPath(lEdit.FileName);
        if not lOriginals.ContainsKey(lFileName) then
        begin
          lBytes := TFile.ReadAllBytes(lFileName);
          lOriginals.Add(lFileName, lBytes);
          lBackupFileName := TPath.Combine(lBackupRoot,
            IntToStr(Length(aAppliedFiles) + 1) + '-' + TPath.GetFileName(lFileName) + '.bak');
          TDirectory.CreateDirectory(TPath.GetDirectoryName(lBackupFileName));
          TFile.WriteAllBytes(lBackupFileName, lBytes);
          AddAppliedFile(aAppliedFiles, lFileName, lBackupFileName, FileHash(lBytes));
        end;
      end;

      for lPair in lOriginals do
      begin
        lFileName := lPair.Key;
        if not LoadDakSource(lFileName, lSource, lText) then
          raise Exception.Create('Failed to load source for rename: ' + lText);
        lText := lSource.fText;
        SetLength(lEdits, 0);
        for lEdit in aPlan.Edits do
          if SameFileNameSafe(lEdit.FileName, lFileName) then
          begin
            SetLength(lEdits, Length(lEdits) + 1);
            lEdits[High(lEdits)] := lEdit;
          end;
        if not ValidateRenamePlanGuards(aPlan, lFileName, lSource, lGuardError) then
          raise Exception.Create(lGuardError);
        SortEditsDescending(lEdits);
        for lEdit in lEdits do
          ApplyEditToSource(lEdit, aOriginalName, lSource, lText);
        TFile.WriteAllBytes(lFileName, DakTextToBytes(lText, lSource.fEncoding,
          lSource.fHasUtf8Bom));
      end;
      if not VerifyRenameBuild(aOptions, lWorkspaceRoot, aVerification) then
        raise Exception.Create(aVerification.Diagnostic);
      WriteRenameManifest(lWorkspaceRoot, 'applied', '', aAppliedFiles, aVerification);
    except
      for lPair in lOriginals do
      begin
        TFile.WriteAllBytes(lPair.Key, lPair.Value);
        if FileHash(TFile.ReadAllBytes(lPair.Key)) <> FileHash(lPair.Value) then
          raise Exception.Create('Rollback verification failed for ' + lPair.Key);
      end;
      if SameText(aVerification.Status, 'failed') then
        lManifestError := 'rename-build-verification-failed'
      else
        lManifestError := 'rename-apply-failed';
      WriteRenameManifest(lWorkspaceRoot, 'rolledBack', lManifestError, aAppliedFiles,
        aVerification);
      raise;
    end;
  finally
    lOriginals.Free;
  end;
end;

function DeadCodeWorkspaceRoot(const aOptions: TAppOptions): string;
var
  lProjectPath: string;
begin
  lProjectPath := TPath.GetFullPath(aOptions.fDprojPath);
  Result := DakProjectPath(DakProjectRootForProjectPath(lProjectPath),
    ['dead-code', FormatDateTime('yyyymmddhhnnsszzz', Now)]);
end;

procedure AddDeadCodeFileEdits(const aPlan: TDelphiSemanticDeadCodeRemovalPlan;
  const aFileName: string; out aEdits: TArray<TDelphiSemanticTextEdit>);
var
  lEdit: TDelphiSemanticTextEdit;
begin
  SetLength(aEdits, 0);
  for lEdit in aPlan.Edits do
    if SameFileNameSafe(lEdit.FileName, aFileName) then
    begin
      SetLength(aEdits, Length(aEdits) + 1);
      aEdits[High(aEdits)] := lEdit;
    end;
  SortEditsDescending(aEdits);
end;

procedure ApplyDeadCodeEditToSource(const aEdit: TDelphiSemanticTextEdit;
  const aSource: TDakSourceBuffer; var aText: string);
var
  lEndOffset: Integer;
  lExpectedText: string;
  lStartOffset: Integer;
begin
  if not DakOffsetForLineColumn(aSource, aEdit.StartLine, aEdit.StartColumn,
    lStartOffset) then
    raise Exception.Create('Invalid dead-code edit start in ' + aEdit.FileName);
  if not DakOffsetForLineColumn(aSource, aEdit.EndLine, aEdit.EndColumn, lEndOffset) then
    raise Exception.Create('Invalid dead-code edit end in ' + aEdit.FileName);
  if lEndOffset < lStartOffset then
    raise Exception.Create('Invalid dead-code edit range in ' + aEdit.FileName);

  if aEdit.ExpectedSourceText <> '' then
  begin
    lExpectedText := Copy(aSource.fText, lStartOffset, lEndOffset - lStartOffset);
    if lExpectedText <> aEdit.ExpectedSourceText then
      raise Exception.Create('Dead-code edit range does not match expected source in ' +
        aEdit.FileName);
  end;

  Delete(aText, lStartOffset, lEndOffset - lStartOffset);
  Insert(aEdit.NewText, aText, lStartOffset);
end;

procedure WriteDeadCodeManifest(const aWorkspaceRoot, aStatus, aDiagnostic: string;
  const aPlan: TDelphiSemanticDeadCodeRemovalPlan; const aFiles: TArray<TAppliedFile>;
  const aVerification: TRenameVerification);
var
  lJson: string;
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  lRoot.AddPair('status', aStatus);
  lRoot.AddPair('diagnostic', aDiagnostic);
  lRoot.AddPair('profile', aPlan.Profile);
  lRoot.AddPair('editCount', TJSONNumber.Create(Length(aPlan.Edits)));
  lRoot.AddPair('blockerCount', TJSONNumber.Create(Length(aPlan.Blockers)));
  lRoot.AddPair('verification', BuildRenameVerificationObject(aVerification));
  lRoot.AddPair('files', BuildAppliedFilesArray(aFiles));
  lJson := JsonValueText(lRoot);
  TDirectory.CreateDirectory(aWorkspaceRoot);
  TFile.WriteAllText(TPath.Combine(aWorkspaceRoot, 'manifest.json'), lJson, TEncoding.UTF8);
end;

procedure RollbackDeadCodeOriginals(const aOriginals: TDictionary<string, TBytes>);
var
  lPair: TPair<string, TBytes>;
begin
  for lPair in aOriginals do
    TFile.WriteAllBytes(lPair.Key, lPair.Value);
  for lPair in aOriginals do
    if FileHash(TFile.ReadAllBytes(lPair.Key)) <> FileHash(lPair.Value) then
      raise Exception.Create('Rollback verification failed for ' + lPair.Key);
end;

procedure ApplyDeadCodePlanEdits(const aPlan: TDelphiSemanticDeadCodeRemovalPlan;
  const aOriginals: TDictionary<string, TBytes>);
var
  lEdit: TDelphiSemanticTextEdit;
  lEdits: TArray<TDelphiSemanticTextEdit>;
  lFileName: string;
  lPair: TPair<string, TBytes>;
  lSource: TDakSourceBuffer;
  lText: string;
begin
  for lPair in aOriginals do
  begin
    lFileName := lPair.Key;
    if not LoadDakSource(lFileName, lSource, lText) then
      raise Exception.Create('Failed to load source for dead-code removal: ' + lText);
    lText := lSource.fText;
    AddDeadCodeFileEdits(aPlan, lFileName, lEdits);
    for lEdit in lEdits do
      ApplyDeadCodeEditToSource(lEdit, lSource, lText);
    TFile.WriteAllBytes(lFileName, DakTextToBytes(lText, lSource.fEncoding,
      lSource.fHasUtf8Bom));
  end;
end;

procedure BackupDeadCodeFiles(const aPlan: TDelphiSemanticDeadCodeRemovalPlan;
  const aBackupRoot: string; const aOriginals: TDictionary<string, TBytes>;
  var aAppliedFiles: TArray<TAppliedFile>);
var
  lBackupFileName: string;
  lBytes: TBytes;
  lEdit: TDelphiSemanticTextEdit;
  lFileName: string;
begin
  SetLength(aAppliedFiles, 0);
  for lEdit in aPlan.Edits do
  begin
    lFileName := TPath.GetFullPath(lEdit.FileName);
    if aOriginals.ContainsKey(lFileName) then
      Continue;
    lBytes := TFile.ReadAllBytes(lFileName);
    aOriginals.Add(lFileName, lBytes);
    lBackupFileName := TPath.Combine(aBackupRoot, IntToStr(Length(aAppliedFiles) + 1) +
      '-' + TPath.GetFileName(lFileName) + '.bak');
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lBackupFileName));
    TFile.WriteAllBytes(lBackupFileName, lBytes);
    AddAppliedFile(aAppliedFiles, lFileName, lBackupFileName, FileHash(lBytes));
  end;
end;

procedure ApplyDeadCodeRemovalPlan(const aOptions: TAppOptions;
  const aPlan: TDelphiSemanticDeadCodeRemovalPlan; out aApplyResult: TDeadCodeApplyResult);
var
  lBackupRoot: string;
  lOriginals: TDictionary<string, TBytes>;
  lWorkspaceRoot: string;
begin
  aApplyResult := Default(TDeadCodeApplyResult);
  aApplyResult.Verification := RenameVerification('not-run', -1, '', '');
  lWorkspaceRoot := DeadCodeWorkspaceRoot(aOptions);
  lBackupRoot := TPath.Combine(lWorkspaceRoot, 'backup');
  aApplyResult.ManifestPath := TPath.Combine(lWorkspaceRoot, 'manifest.json');
  lOriginals := TDictionary<string, TBytes>.Create;
  try
    if not SameText(aPlan.Status, 'planned') then
    begin
      aApplyResult.Status := aPlan.Status;
      aApplyResult.Diagnostic := aPlan.Diagnostic;
      WriteDeadCodeManifest(lWorkspaceRoot, aApplyResult.Status, aApplyResult.Diagnostic,
        aPlan, aApplyResult.AppliedFiles, aApplyResult.Verification);
      Exit;
    end;

    if Length(aPlan.Edits) = 0 then
    begin
      aApplyResult.Status := 'noop';
      WriteDeadCodeManifest(lWorkspaceRoot, aApplyResult.Status, '', aPlan,
        aApplyResult.AppliedFiles, aApplyResult.Verification);
      Exit;
    end;

    try
      BackupDeadCodeFiles(aPlan, lBackupRoot, lOriginals, aApplyResult.AppliedFiles);
      ApplyDeadCodePlanEdits(aPlan, lOriginals);
      if not VerifyRenameBuild(aOptions, lWorkspaceRoot, aApplyResult.Verification) then
        raise Exception.Create(aApplyResult.Verification.Diagnostic);
      aApplyResult.Status := 'applied';
      WriteDeadCodeManifest(lWorkspaceRoot, aApplyResult.Status, '', aPlan,
        aApplyResult.AppliedFiles, aApplyResult.Verification);
    except
      on E: Exception do
      begin
        aApplyResult.Diagnostic := E.Message;
        try
          RollbackDeadCodeOriginals(lOriginals);
          aApplyResult.Status := 'rolledBack';
        except
          on lRollbackError: Exception do
          begin
            aApplyResult.Status := 'rollbackFailed';
            aApplyResult.Diagnostic := E.Message + '; rollback failed: ' +
              lRollbackError.Message;
          end;
        end;
        WriteDeadCodeManifest(lWorkspaceRoot, aApplyResult.Status, aApplyResult.Diagnostic,
          aPlan, aApplyResult.AppliedFiles, aApplyResult.Verification);
      end;
    end;
  finally
    lOriginals.Free;
  end;
end;

function RunFindUsagesCommand(const aOptions: TAppOptions): Integer;
var
  lContext: IDakSemanticSymbolQueryContext;
  lCacheMetrics: TDakSemanticCacheMetrics;
  lError: string;
  lOutput: string;
  lPhaseMetrics: TRefactorSemanticPhaseMetrics;
  lPlanningStopwatch: TStopwatch;
  lReferenceFallbackCount: Integer;
  lResult: TDelphiSemanticUsageResult;
  lSymbol: string;
begin
  if not BuildSemanticContext(aOptions, lContext, lCacheMetrics, lPhaseMetrics, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;

  if aOptions.fRefactorSymbol <> '' then
  begin
    lSymbol := aOptions.fRefactorSymbol;
    lPlanningStopwatch := TStopwatch.StartNew;
    lResult := lContext.FindUsagesByName(lSymbol);
  end else begin
    lPlanningStopwatch := TStopwatch.StartNew;
    lResult := lContext.FindUsagesAtPosition(aOptions.fRefactorFilePath,
      aOptions.fRefactorLine, aOptions.fRefactorCol);
    lSymbol := lResult.Symbol.Name;
  end;
  lPhaseMetrics.CommandPlanningMs := lPlanningStopwatch.ElapsedMilliseconds;
  lPhaseMetrics.ProjectSymbolIndexBuildMs := lResult.IndexMetrics.BuildElapsedMilliseconds;
  lPhaseMetrics.ProjectSymbolIndexBuildCount := lResult.IndexMetrics.BuildInvocationCount;
  lPhaseMetrics.CommandPlanningCount := 1;
  lPhaseMetrics.TotalMs := lPhaseMetrics.TotalMs + lPhaseMetrics.CommandPlanningMs;
  lReferenceFallbackCount := lPhaseMetrics.ReferenceReconciliationFallbackCount;

  if aOptions.fRefactorFormat = TRefactorFormat.rffJson then
    lOutput := UsageResultJson(lSymbol, lResult, lReferenceFallbackCount, lCacheMetrics,
      lPhaseMetrics)
  else
    lOutput := UsageResultText(lSymbol, lResult);
  WriteLn(lOutput);
  if lResult.Status = 'resolved' then
    Result := cExitSuccess
  else
    Result := cExitToolFailure;
end;

function RunRenameCommand(const aOptions: TAppOptions): Integer;
var
  lAppliedFiles: TArray<TAppliedFile>;
  lCacheMetrics: TDakSemanticCacheMetrics;
  lContext: IDakSemanticSymbolQueryContext;
  lError: string;
  lOutput: string;
  lPhaseMetrics: TRefactorSemanticPhaseMetrics;
  lPlan: TDelphiSemanticRenamePlan;
  lPlanningStopwatch: TStopwatch;
  lReferenceFallbackCount: Integer;
  lSymbol: string;
  lUsageResult: TDelphiSemanticUsageResult;
  lVerification: TRenameVerification;
begin
  SetLength(lAppliedFiles, 0);
  lVerification := RenameVerification('not-run', -1, '', '');
  if not BuildSemanticContext(aOptions, lContext, lCacheMetrics, lPhaseMetrics, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;

  if aOptions.fRefactorSymbol <> '' then
  begin
    lSymbol := aOptions.fRefactorSymbol;
    lPlanningStopwatch := TStopwatch.StartNew;
    lPlan := lContext.PlanRename(lSymbol, aOptions.fRefactorNewName);
  end else begin
    lPlanningStopwatch := TStopwatch.StartNew;
    lUsageResult := lContext.FindUsagesAtPosition(aOptions.fRefactorFilePath,
      aOptions.fRefactorLine, aOptions.fRefactorCol);
    if lUsageResult.Status = 'resolved' then
      lSymbol := lUsageResult.Symbol.Name
    else
      lSymbol := '';
    lPlan := lContext.PlanRenameAtPosition(aOptions.fRefactorFilePath,
      aOptions.fRefactorLine, aOptions.fRefactorCol, aOptions.fRefactorNewName);
  end;
  lPhaseMetrics.CommandPlanningMs := lPlanningStopwatch.ElapsedMilliseconds;
  lPhaseMetrics.ProjectSymbolIndexBuildMs := lPlan.IndexMetrics.BuildElapsedMilliseconds;
  lPhaseMetrics.ProjectSymbolIndexBuildCount := lPlan.IndexMetrics.BuildInvocationCount;
  if aOptions.fRefactorSymbol = '' then
  begin
    lPhaseMetrics.ProjectSymbolIndexBuildMs := lPhaseMetrics.ProjectSymbolIndexBuildMs +
      lUsageResult.IndexMetrics.BuildElapsedMilliseconds;
    lPhaseMetrics.ProjectSymbolIndexBuildCount := lPhaseMetrics.ProjectSymbolIndexBuildCount +
      lUsageResult.IndexMetrics.BuildInvocationCount;
  end;
  lPhaseMetrics.CommandPlanningCount := 1;
  lPhaseMetrics.TotalMs := lPhaseMetrics.TotalMs + lPhaseMetrics.CommandPlanningMs;
  if SameText(lPlan.Status, 'planned') and aOptions.fRefactorApply then
  begin
    try
      ApplyRenamePlan(aOptions, lPlan, lSymbol, lAppliedFiles, lVerification);
    except
      on E: Exception do
      begin
        if SameText(lVerification.Status, 'failed') then
          lPlan.Status := 'rolledBack'
        else
          lPlan.Status := 'failed';
        lPlan.Diagnostic := E.Message;
      end;
    end;
  end;
  lReferenceFallbackCount := lPhaseMetrics.ReferenceReconciliationFallbackCount;

  if aOptions.fRefactorFormat = TRefactorFormat.rffJson then
    lOutput := RenameResultJson(lSymbol, lPlan, aOptions.fRefactorApply,
      lAppliedFiles, lVerification, lReferenceFallbackCount, lCacheMetrics, lPhaseMetrics)
  else
    lOutput := RenameResultText(lSymbol, lPlan, aOptions.fRefactorApply,
      lAppliedFiles, lVerification);
  WriteLn(lOutput);
  if SameText(lPlan.Status, 'planned') then
    Result := cExitSuccess
  else
    Result := cExitToolFailure;
end;

function RunDeadCodeCommand(const aOptions: TAppOptions): Integer;
var
  lApplyResult: TDeadCodeApplyResult;
  lCacheMetrics: TDakSemanticCacheMetrics;
  lContext: IDakSemanticSymbolQueryContext;
  lError: string;
  lOutput: string;
  lPhaseMetrics: TRefactorSemanticPhaseMetrics;
  lPlan: TDelphiSemanticDeadCodeRemovalPlan;
  lPlanningStopwatch: TStopwatch;
  lProfile: string;
  lReferenceFallbackCount: Integer;
  lReport: TDelphiSemanticDeadCodeReport;
begin
  if not BuildSemanticContext(aOptions, lContext, lCacheMetrics, lPhaseMetrics, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;

  lProfile := aOptions.fDeadCodeProfile;
  if lProfile = '' then
    lProfile := DefaultDeadCodeProfileName;
  lPlanningStopwatch := TStopwatch.StartNew;
  if aOptions.fRefactorApply then
  begin
    lPlan := lContext.PlanDeadCodeRemoval(lProfile);
    lReport := Default(TDelphiSemanticDeadCodeReport);
    lReport.Profile := lPlan.Profile;
    lReport.IndexMetrics.BuildElapsedMilliseconds := 0;
    lReport.IndexMetrics.BuildInvocationCount := 0;
  end else
    lReport := lContext.ReportDeadCode(lProfile);
  lPhaseMetrics.CommandPlanningMs := lPlanningStopwatch.ElapsedMilliseconds;
  lPhaseMetrics.ProjectSymbolIndexBuildMs := lReport.IndexMetrics.BuildElapsedMilliseconds;
  lPhaseMetrics.ProjectSymbolIndexBuildCount := lReport.IndexMetrics.BuildInvocationCount;
  lPhaseMetrics.CommandPlanningCount := 1;
  lPhaseMetrics.TotalMs := lPhaseMetrics.TotalMs + lPhaseMetrics.CommandPlanningMs;
  lReferenceFallbackCount := lPhaseMetrics.ReferenceReconciliationFallbackCount;
  if aOptions.fRefactorApply then
  begin
    ApplyDeadCodeRemovalPlan(aOptions, lPlan, lApplyResult);
    if aOptions.fRefactorFormat = TRefactorFormat.rffJson then
      lOutput := DeadCodeApplyJson(lPlan, lApplyResult, lReferenceFallbackCount,
        lCacheMetrics, lPhaseMetrics)
    else
      lOutput := DeadCodeApplyText(lPlan, lApplyResult);
    WriteLn(lOutput);
    if SameText(lApplyResult.Status, 'applied') or SameText(lApplyResult.Status, 'noop') then
      Exit(cExitSuccess);
    Exit(cExitToolFailure);
  end else if aOptions.fRefactorFormat = TRefactorFormat.rffJson then
    lOutput := DeadCodeReportJson(lReport, lReferenceFallbackCount, lCacheMetrics,
      lPhaseMetrics)
  else
    lOutput := DeadCodeReportText(lReport);
  WriteLn(lOutput);
  Result := cExitSuccess;
end;

end.
