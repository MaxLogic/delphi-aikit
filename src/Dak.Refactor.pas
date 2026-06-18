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
  System.SysUtils,
  DelphiSemantics.DeadCode, DelphiSemantics.Model.Text, DelphiSemantics.ProjectContext,
  DelphiSemantics.Refactor, DelphiSemantics.Usage,
  Dak.Build, Dak.DeadCodeProfile, Dak.ExitCodes, Dak.Paths, Dak.Semantics.Session, Dak.SourceText;

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

function JsonEscape(const aValue: string): string;
var
  ch: Char;
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(aValue) do
  begin
    ch := aValue[i];
    case ch of
      '"':
        Result := Result + '\"';
      '\':
        Result := Result + '\\';
      #8:
        Result := Result + '\b';
      #9:
        Result := Result + '\t';
      #10:
        Result := Result + '\n';
      #12:
        Result := Result + '\f';
      #13:
        Result := Result + '\r';
    else
      if Ord(ch) < 32 then
        Result := Result + '\u' + IntToHex(Ord(ch), 4)
      else
        Result := Result + ch;
    end;
  end;
end;

function JsonStringArray(const aValues: array of string): string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(aValues) do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + '"' + JsonEscape(aValues[i]) + '"';
  end;
  Result := Result + ']';
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

function SemanticPhaseMetricsJson(const aPhaseMetrics: TRefactorSemanticPhaseMetrics;
  const aCacheMetrics: TDakSemanticCacheMetrics): string;
begin
  Result := '"semanticPhaseMetrics":{' +
    '"projectContextMs":' + aPhaseMetrics.ProjectContextMs.ToString +
    ',"projectUnitIndexMs":' + aPhaseMetrics.ProjectUnitIndexMs.ToString +
    ',"projectUnitCount":' + aPhaseMetrics.ProjectUnitCount.ToString +
    ',"unitModelExtractionMs":' + aPhaseMetrics.UnitModelExtractionMs.ToString +
    ',"unitModelExtractionCount":' + aPhaseMetrics.UnitModelExtractionCount.ToString +
    ',"semanticCacheWorkMs":' + aPhaseMetrics.UnitModelExtractionMs.ToString +
    ',"projectSymbolIndexBuildMs":' + aPhaseMetrics.ProjectSymbolIndexBuildMs.ToString +
    ',"projectSymbolIndexBuildCount":' + aPhaseMetrics.ProjectSymbolIndexBuildCount.ToString +
    ',"commandPlanningMs":' + aPhaseMetrics.CommandPlanningMs.ToString +
    ',"commandPlanningCount":' + aPhaseMetrics.CommandPlanningCount.ToString +
    ',"totalMs":' + aPhaseMetrics.TotalMs.ToString +
    ',"semanticCacheHits":' + aCacheMetrics.CacheHits.ToString +
    ',"semanticCacheMisses":' + aCacheMetrics.CacheMisses.ToString +
    ',"semanticCacheInvalidations":' + aCacheMetrics.Invalidations.ToString + '}';
end;

function UsageJson(const aUsage: TDelphiSemanticUsage): string;
begin
  Result := '{"name":"' + JsonEscape(aUsage.Name) + '","role":"' + JsonEscape(aUsage.Role) +
    '","routine":"' + JsonEscape(aUsage.RoutineName) + '","section":"' +
    JsonEscape(aUsage.SectionKind) + '","sourceKind":"' + JsonEscape(aUsage.SourceKind) +
    '","file":"' + JsonEscape(aUsage.FileName) + '","unit":"' + JsonEscape(aUsage.UnitName) +
    '","line":' + aUsage.Line.ToString + ',"column":' + aUsage.Column.ToString +
    ',"endLine":' + aUsage.EndLine.ToString + ',"endColumn":' + aUsage.EndColumn.ToString + '}';
end;

function UsageResultJson(const aSymbol: string; const aResult: TDelphiSemanticUsageResult;
  const aReferenceFallbackCount: Integer; const aCacheMetrics: TDakSemanticCacheMetrics;
  const aPhaseMetrics: TRefactorSemanticPhaseMetrics): string;
var
  i: Integer;
begin
  Result := '{"status":"' + JsonEscape(aResult.Status) + '","symbol":"' + JsonEscape(aSymbol) +
    '","diagnostic":"' + JsonEscape(aResult.Diagnostic) + '","count":' +
    Length(aResult.Usages).ToString + ',"referenceReconciliationFallbackCount":' +
    aReferenceFallbackCount.ToString + ',"semanticCacheHits":' +
    aCacheMetrics.CacheHits.ToString + ',"semanticCacheMisses":' +
    aCacheMetrics.CacheMisses.ToString + ',"semanticCacheInvalidations":' +
    aCacheMetrics.Invalidations.ToString + ',' +
    SemanticPhaseMetricsJson(aPhaseMetrics, aCacheMetrics) + ',"usages":[';
  for i := 0 to High(aResult.Usages) do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + UsageJson(aResult.Usages[i]);
  end;
  Result := Result + ']}';
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

function EditJson(const aEdit: TDelphiSemanticTextEdit): string;
begin
  Result := '{"file":"' + JsonEscape(aEdit.FileName) + '","role":"' + JsonEscape(aEdit.Role) +
    '","startLine":' + aEdit.StartLine.ToString + ',"startColumn":' +
    aEdit.StartColumn.ToString + ',"endLine":' + aEdit.EndLine.ToString + ',"endColumn":' +
    aEdit.EndColumn.ToString + ',"newText":"' + JsonEscape(aEdit.NewText) + '"}';
end;

function AppliedFilesJson(const aFiles: TArray<TAppliedFile>): string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(aFiles) do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + '{"file":"' + JsonEscape(aFiles[i].FileName) + '","backup":"' +
      JsonEscape(aFiles[i].BackupFileName) + '","hash":"' + JsonEscape(aFiles[i].Hash) + '"}';
  end;
  Result := Result + ']';
end;

function RenameVerification(const aStatus: string; aExitCode: Integer;
  const aDiagnostic, aDiagnosticsDir: string): TRenameVerification;
begin
  Result.Status := aStatus;
  Result.ExitCode := aExitCode;
  Result.Diagnostic := aDiagnostic;
  Result.DiagnosticsDir := aDiagnosticsDir;
end;

function RenameVerificationJson(const aVerification: TRenameVerification): string;
begin
  Result := '{"status":"' + JsonEscape(aVerification.Status) + '","exitCode":' +
    aVerification.ExitCode.ToString + ',"diagnostic":"' +
    JsonEscape(aVerification.Diagnostic) + '","diagnosticsDir":"' +
    JsonEscape(aVerification.DiagnosticsDir) + '"}';
end;

function RenameResultJson(const aSymbol: string; const aPlan: TDelphiSemanticRenamePlan;
  const aApply: Boolean; const aAppliedFiles: TArray<TAppliedFile>;
  const aVerification: TRenameVerification;
  const aReferenceFallbackCount: Integer; const aCacheMetrics: TDakSemanticCacheMetrics;
  const aPhaseMetrics: TRefactorSemanticPhaseMetrics): string;
var
  i: Integer;
  lStatus: string;
begin
  lStatus := aPlan.Status;
  if aApply and SameText(lStatus, 'planned') then
    lStatus := 'applied';
  Result := '{"status":"' + JsonEscape(lStatus) + '","symbol":"' + JsonEscape(aSymbol) +
    '","apply":' + LowerCase(BoolToStr(aApply, True)) + ',"diagnostic":"' +
    JsonEscape(aPlan.Diagnostic) + '","editCount":' + Length(aPlan.Edits).ToString +
    ',"verification":' + RenameVerificationJson(aVerification) +
    ',"referenceReconciliationFallbackCount":' + aReferenceFallbackCount.ToString +
    ',"semanticCacheHits":' + aCacheMetrics.CacheHits.ToString +
    ',"semanticCacheMisses":' + aCacheMetrics.CacheMisses.ToString +
    ',"semanticCacheInvalidations":' + aCacheMetrics.Invalidations.ToString +
    ',' + SemanticPhaseMetricsJson(aPhaseMetrics, aCacheMetrics) + ',"edits":[';
  for i := 0 to High(aPlan.Edits) do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + EditJson(aPlan.Edits[i]);
  end;
  Result := Result + '],"appliedFiles":' + AppliedFilesJson(aAppliedFiles) + '}';
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
begin
  Result := '{"status":"ok","profile":"' + JsonEscape(aReport.Profile) + '","count":' +
    IntToStr(Length(aReport.Candidates)) + ',"referenceReconciliationFallbackCount":' +
    aReferenceFallbackCount.ToString + ',"semanticCacheHits":' +
    aCacheMetrics.CacheHits.ToString + ',"semanticCacheMisses":' +
    aCacheMetrics.CacheMisses.ToString + ',"semanticCacheInvalidations":' +
    aCacheMetrics.Invalidations.ToString + ',' +
    SemanticPhaseMetricsJson(aPhaseMetrics, aCacheMetrics) + ',"candidates":[';
  for i := 0 to High(aReport.Candidates) do
  begin
    if i > 0 then
      Result := Result + ',';
    lCandidate := aReport.Candidates[i];
    Result := Result + '{"name":"' + JsonEscape(lCandidate.Name) + '","kind":"' +
      JsonEscape(lCandidate.Kind) + '","unit":"' + JsonEscape(lCandidate.UnitName) +
      '","owner":"' + JsonEscape(lCandidate.OwnerName) + '","file":"' +
      JsonEscape(lCandidate.FileName) + '","line":' + IntToStr(lCandidate.Line) +
      ',"column":' + IntToStr(lCandidate.Column) + ',"status":"' +
      JsonEscape(lCandidate.Status) + '","reason":"' + JsonEscape(lCandidate.Reason) +
      '","safetyProfile":"' + JsonEscape(lCandidate.SafetyProfile) +
      '","referenceCount":' + IntToStr(lCandidate.ReferenceCount) + ',"blockers":' +
      JsonStringArray(lCandidate.Blockers) + '}';
  end;
  Result := Result + ']}';
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
begin
  lJson := '{"status":"' + JsonEscape(aStatus) + '","error":"' + JsonEscape(aError) +
    '","verification":' + RenameVerificationJson(aVerification) + ',"files":' +
    AppliedFilesJson(aFiles) + '}';
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
  lCacheMetrics: TDakSemanticCacheMetrics;
  lContext: IDakSemanticSymbolQueryContext;
  lError: string;
  lOutput: string;
  lPhaseMetrics: TRefactorSemanticPhaseMetrics;
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
  lReport := lContext.ReportDeadCode(lProfile);
  lPhaseMetrics.CommandPlanningMs := lPlanningStopwatch.ElapsedMilliseconds;
  lPhaseMetrics.ProjectSymbolIndexBuildMs := lReport.IndexMetrics.BuildElapsedMilliseconds;
  lPhaseMetrics.ProjectSymbolIndexBuildCount := lReport.IndexMetrics.BuildInvocationCount;
  lPhaseMetrics.CommandPlanningCount := 1;
  lPhaseMetrics.TotalMs := lPhaseMetrics.TotalMs + lPhaseMetrics.CommandPlanningMs;
  lReferenceFallbackCount := lPhaseMetrics.ReferenceReconciliationFallbackCount;
  if aOptions.fRefactorFormat = TRefactorFormat.rffJson then
    lOutput := DeadCodeReportJson(lReport, lReferenceFallbackCount, lCacheMetrics,
      lPhaseMetrics)
  else
    lOutput := DeadCodeReportText(lReport);
  WriteLn(lOutput);
  Result := cExitSuccess;
end;

end.
