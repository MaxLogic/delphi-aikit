unit Dak.RemoveWith.Transaction;

interface

uses
  Dak.RemoveWith.Planner, Dak.Types;

type
  TRemoveWithSourceFingerprint = record
    fFilePath: string;
    fHash: string;
  end;

  TRemoveWithPlanApplyContext = record
    fContextFingerprint: string;
    fSemanticContextFingerprint: string;
    fSourceFingerprints: TArray<TRemoveWithSourceFingerprint>;
  end;

  TRemoveWithTransactionStatus = (rwtxNotRun, rwtxApplied, rwtxPreflightBuildFailed, rwtxRolledBack,
    rwtxRollbackFailed, rwtxContextFingerprintMismatch, rwtxContextFingerprintMissing);

  TRemoveWithTransactionFile = record
    fPath: string;
    fBackupPath: string;
    fHash: string;
    fLineEnding: string;
    fEncoding: string;
    fStatus: string;
    fSize: Int64;
  end;

  TRemoveWithTransactionResult = record
    fBackupRoot: string;
    fError: string;
    fManifestPath: string;
    fContextFingerprint: string;
    fCurrentContextFingerprint: string;
    fVerificationError: string;
    fVerificationStdErrLogPath: string;
    fVerificationStdOutLogPath: string;
    fVerificationStatus: string;
    fFiles: TArray<TRemoveWithTransactionFile>;
    fStatus: TRemoveWithTransactionStatus;
  end;

function RemoveWithTransactionStatusToText(const aStatus: TRemoveWithTransactionStatus): string;
function BuildRemoveWithPlanApplyContext(const aPlanResult: TRemoveWithPlanResult;
  out aContext: TRemoveWithPlanApplyContext; out aError: string): Boolean;
function ApplyRemoveWithPlanTransactionally(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot: string;
  const aPlanResult: TRemoveWithPlanResult; const aApplyContext: TRemoveWithPlanApplyContext;
  out aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean; overload;
function ApplyRemoveWithPlanTransactionally(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot: string;
  const aPlanResult: TRemoveWithPlanResult; out aTransactionResult: TRemoveWithTransactionResult;
  out aError: string): Boolean; overload;

implementation

uses
  System.Generics.Collections, System.Hash, System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows,
  MaxLogic.StrUtils,
  Dak.Build.Runner, Dak.RemoveWith.Discovery, Dak.RemoveWith.Source;

const
  cApplyTransactionMutexPrefix = 'Local\DakRemoveWithApplyTransaction-';
  cApplyTransactionMutexTimeoutMs = 30 * 60 * 1000;
  cBuildVerificationMutexPrefix = 'Local\DakRemoveWithBuildVerification-';
  cBuildVerificationMutexTimeoutMs = 30 * 60 * 1000;
  cPreflightBuildFailed = 'preflight-build-failed';

type
  TRemoveWithTransaction = record
  private
    class function FileHash(const aBytes: TBytes): string; static;
    class function CanonicalProjectIdentity(const aProjectPath: string): string; static;
    class function ProjectScopedMutexName(const aPrefix, aProjectPath: string): string; static;
    class function ApplyTransactionMutexName(const aProjectPath: string): string; static;
    class function BuildVerificationMutexName(const aProjectPath: string): string; static;
    class function FileAlreadyTracked(const aTransactionResult: TRemoveWithTransactionResult;
      const aPath: string): Boolean; static;
    class function HasPlannedEdits(const aPlanResult: TRemoveWithPlanResult): Boolean; static;
    class function BackupFile(const aPath, aBackupRoot: string; var aTransactionResult: TRemoveWithTransactionResult;
      out aError: string): Boolean; static;
    class function Rollback(const aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean;
      static;
    class procedure SortEditsDescending(var aEdits: TArray<TRemoveWithPlannedTextEdit>); static;
    class procedure SetFileStatuses(var aTransactionResult: TRemoveWithTransactionResult;
      const aStatus: string); static;
    class function ApplyFileEdits(const aPath: string; const aEdits: TArray<TRemoveWithPlannedTextEdit>;
      out aError: string): Boolean; static;
    class function ApplyEdits(const aPlanResult: TRemoveWithPlanResult;
      var aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean; static;
    class function WriteManifest(const aManifestPath: string;
      const aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean; static;
    class function ValidatePlanContext(const aApplyContext: TRemoveWithPlanApplyContext;
      var aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean; static;
    class function ValidateSemanticPlanContext(const aPlanResult: TRemoveWithPlanResult;
      const aApplyContext: TRemoveWithPlanApplyContext; out aError: string): Boolean; static;
    class function VerifyBuild(const aOptions: TAppOptions; const aProjectPath, aDiagnosticsDir: string;
      var aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean; static;
    class function ApplyLocked(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot: string;
      const aPlanResult: TRemoveWithPlanResult; const aApplyContext: TRemoveWithPlanApplyContext;
      var aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean; static;
  public
    class function Apply(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot: string;
      const aPlanResult: TRemoveWithPlanResult; const aApplyContext: TRemoveWithPlanApplyContext;
      out aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean; static;
  end;

function RemoveWithTransactionStatusToText(const aStatus: TRemoveWithTransactionStatus): string;
begin
  case aStatus of
    TRemoveWithTransactionStatus.rwtxApplied:
      Result := 'applied';
    TRemoveWithTransactionStatus.rwtxPreflightBuildFailed:
      Result := cPreflightBuildFailed;
    TRemoveWithTransactionStatus.rwtxRolledBack:
      Result := 'rolledBack';
    TRemoveWithTransactionStatus.rwtxRollbackFailed:
      Result := 'rollbackFailed';
    TRemoveWithTransactionStatus.rwtxContextFingerprintMismatch:
      Result := 'context-fingerprint-mismatch';
    TRemoveWithTransactionStatus.rwtxContextFingerprintMissing:
      Result := 'context-fingerprint-missing';
  else
    Result := 'not-run';
  end;
end;

function ReplacementTextForSource(const aText: string; const aSource: TRemoveWithSourceBuffer): string;
begin
  Result := aText;
  if (aSource.fLineBreak = '') or (aSource.fLineBreak = sLineBreak) then
    Exit;

  Result := StringReplace(Result, sLineBreak, aSource.fLineBreak, [rfReplaceAll]);
end;

procedure AddUniquePlanFile(const aFiles: TList<string>; const aFileName: string);
var
  lFileName: string;
begin
  lFileName := TPath.GetFullPath(aFileName);
  if aFiles.Contains(lFileName) then
    Exit;
  aFiles.Add(lFileName);
end;

function PlannedSourceFiles(const aPlanResult: TRemoveWithPlanResult): TArray<string>;
var
  lEdit: TRemoveWithPlannedTextEdit;
  lFiles: TList<string>;
  lSeen: TDictionary<string, Byte>;
  lStatement: TRemoveWithPlannedStatement;
begin
  lFiles := nil;
  lSeen := nil;
  try
    lFiles := TList<string>.Create;
    lSeen := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
    for lStatement in aPlanResult.fStatements do
    begin
      if lStatement.fStatus <> 'planned' then
        Continue;
      for lEdit in lStatement.fEdits do
        if lEdit.fFilePath <> '' then
        begin
          if lSeen.ContainsKey(lEdit.fFilePath) then
            Continue;
          lSeen.Add(lEdit.fFilePath, 0);
          AddUniquePlanFile(lFiles, lEdit.fFilePath);
        end;
    end;
    Result := lFiles.ToArray;
  finally
    lSeen.Free;
    lFiles.Free;
  end;
end;

function BuildRemoveWithPlanApplyContextForFiles(const aFileNames: TArray<string>;
  out aContext: TRemoveWithPlanApplyContext; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lFileName: string;
  lFingerprint: TRemoveWithSourceFingerprint;
  lIndex: Integer;
begin
  Result := False;
  aContext := Default(TRemoveWithPlanApplyContext);
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    try
      for lFileName in aFileNames do
      begin
        if not TFile.Exists(lFileName) then
        begin
          aError := 'planned-source-missing: ' + lFileName;
          Exit(False);
        end;
        lIndex := Length(aContext.fSourceFingerprints);
        SetLength(aContext.fSourceFingerprints, lIndex + 1);
        lFingerprint := Default(TRemoveWithSourceFingerprint);
        lFingerprint.fFilePath := TPath.GetFullPath(lFileName);
        lFingerprint.fHash := THashSHA2.GetHashStringFromFile(lFingerprint.fFilePath);
        aContext.fSourceFingerprints[lIndex] := lFingerprint;
        lBuilder.Append(AnsiLowerCase(lFingerprint.fFilePath));
        lBuilder.Append('=');
        lBuilder.Append(lFingerprint.fHash);
        lBuilder.AppendLine;
      end;
      if lBuilder.Length > 0 then
        aContext.fContextFingerprint := THashSHA2.GetHashString(lBuilder.ToString);
      Result := True;
    except
      on E: Exception do
        aError := E.Message;
    end;
  finally
    lBuilder.Free;
  end;
end;

function BuildRemoveWithPlanApplyContext(const aPlanResult: TRemoveWithPlanResult;
  out aContext: TRemoveWithPlanApplyContext; out aError: string): Boolean;
begin
  Result := BuildRemoveWithPlanApplyContextForFiles(PlannedSourceFiles(aPlanResult), aContext, aError);
  if Result and SameText(aPlanResult.fSemanticPlan.Operation, 'remove-with') then
    aContext.fSemanticContextFingerprint := aPlanResult.fSemanticPlan.ContextFingerprint;
end;

class function TRemoveWithTransaction.FileHash(const aBytes: TBytes): string;
var
  lHash: THashSHA2;
begin
  lHash := THashSHA2.Create;
  if Length(aBytes) > 0 then
    lHash.Update(aBytes);
  Result := lHash.HashAsString;
end;

class function TRemoveWithTransaction.CanonicalProjectIdentity(const aProjectPath: string): string;
begin
  Result := LowerCase(TPath.GetFullPath(aProjectPath));
end;

class function TRemoveWithTransaction.ProjectScopedMutexName(const aPrefix,
  aProjectPath: string): string;
var
  i: Integer;
  lHash: UInt64;
  lIdentity: string;
  lSafeIdentity: string;
begin
  lIdentity := CanonicalProjectIdentity(aProjectPath);
  lSafeIdentity := '';
  lHash := 0;
  for i := 1 to Length(lIdentity) do
  begin
    lHash := ((lHash * 131) + Ord(lIdentity[i])) mod UInt64($100000000);
    if CharInSet(lIdentity[i], ['a'..'z', '0'..'9']) then
      lSafeIdentity := lSafeIdentity + lIdentity[i]
    else
      lSafeIdentity := lSafeIdentity + '_';
  end;
  Result := aPrefix + Copy(lSafeIdentity, 1, 80) + '-' + IntToHex(lHash, 8);
end;

class function TRemoveWithTransaction.ApplyTransactionMutexName(
  const aProjectPath: string): string;
begin
  Result := ProjectScopedMutexName(cApplyTransactionMutexPrefix, aProjectPath);
end;

class function TRemoveWithTransaction.BuildVerificationMutexName(const aProjectPath: string): string;
begin
  Result := ProjectScopedMutexName(cBuildVerificationMutexPrefix, aProjectPath);
end;

class function TRemoveWithTransaction.FileAlreadyTracked(
  const aTransactionResult: TRemoveWithTransactionResult; const aPath: string): Boolean;
var
  lFile: TRemoveWithTransactionFile;
begin
  for lFile in aTransactionResult.fFiles do
  begin
    if SameText(lFile.fPath, aPath) then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithTransaction.HasPlannedEdits(const aPlanResult: TRemoveWithPlanResult): Boolean;
var
  lStatement: TRemoveWithPlannedStatement;
begin
  for lStatement in aPlanResult.fStatements do
  begin
    if lStatement.fStatus = 'planned' then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithTransaction.BackupFile(const aPath, aBackupRoot: string;
  var aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean;
var
  lBytes: TBytes;
  lFile: TRemoveWithTransactionFile;
  lIndex: Integer;
  lSource: TRemoveWithSourceBuffer;
begin
  Result := False;
  aError := '';
  try
    if FileAlreadyTracked(aTransactionResult, aPath) then
      Exit(True);
    if not LoadRemoveWithSource(aPath, lSource, aError) then
      Exit(False);
    lBytes := TFile.ReadAllBytes(aPath);
    lIndex := Length(aTransactionResult.fFiles);
    lFile := Default(TRemoveWithTransactionFile);
    lFile.fPath := aPath;
    lFile.fBackupPath := TPath.Combine(aBackupRoot, IntToStr(lIndex + 1) + '.bak');
    lFile.fHash := FileHash(lBytes);
    lFile.fLineEnding := lSource.fLineEndingName;
    lFile.fEncoding := RemoveWithSourceEncodingToText(lSource.fEncoding, lSource.fHasUtf8Bom);
    lFile.fStatus := 'backed-up';
    lFile.fSize := Length(lBytes);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lFile.fBackupPath));
    TFile.WriteAllBytes(lFile.fBackupPath, lBytes);
    SetLength(aTransactionResult.fFiles, lIndex + 1);
    aTransactionResult.fFiles[lIndex] := lFile;
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

class function TRemoveWithTransaction.Rollback(const aTransactionResult: TRemoveWithTransactionResult;
  out aError: string): Boolean;
var
  lBytes: TBytes;
  lFile: TRemoveWithTransactionFile;
  lRestoredBytes: TBytes;
begin
  Result := False;
  aError := '';
  try
    for lFile in aTransactionResult.fFiles do
    begin
      if not FileExists(lFile.fBackupPath) then
      begin
        aError := 'backup-missing: ' + lFile.fBackupPath;
        Exit(False);
      end;
      lBytes := TFile.ReadAllBytes(lFile.fBackupPath);
      TFile.WriteAllBytes(lFile.fPath, lBytes);
      lRestoredBytes := TFile.ReadAllBytes(lFile.fPath);
      if FileHash(lRestoredBytes) <> lFile.fHash then
      begin
        aError := 'rollback-verify-failed: ' + lFile.fPath;
        Exit(False);
      end;
    end;
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

class procedure TRemoveWithTransaction.SortEditsDescending(var aEdits: TArray<TRemoveWithPlannedTextEdit>);
var
  lChanged: Boolean;
  lLeft: TRemoveWithPlannedTextEdit;
  lLeftOffset: Integer;
  lRightOffset: Integer;
  i: Integer;
begin
  repeat
    lChanged := False;
    for i := 0 to High(aEdits) - 1 do
    begin
      lLeftOffset := aEdits[i].fRange.fStartLine * 10000 + aEdits[i].fRange.fStartColumn;
      lRightOffset := aEdits[i + 1].fRange.fStartLine * 10000 + aEdits[i + 1].fRange.fStartColumn;
      if lLeftOffset < lRightOffset then
      begin
        lLeft := aEdits[i];
        aEdits[i] := aEdits[i + 1];
        aEdits[i + 1] := lLeft;
        lChanged := True;
      end;
    end;
  until not lChanged;
end;

class procedure TRemoveWithTransaction.SetFileStatuses(var aTransactionResult: TRemoveWithTransactionResult;
  const aStatus: string);
var
  i: Integer;
begin
  for i := 0 to High(aTransactionResult.fFiles) do
    aTransactionResult.fFiles[i].fStatus := aStatus;
end;

class function TRemoveWithTransaction.ApplyFileEdits(const aPath: string;
  const aEdits: TArray<TRemoveWithPlannedTextEdit>; out aError: string): Boolean;
var
  lEdits: TArray<TRemoveWithPlannedTextEdit>;
  lEdit: TRemoveWithPlannedTextEdit;
  lEndOffset: Integer;
  lReplacementText: string;
  lSource: TRemoveWithSourceBuffer;
  lStartOffset: Integer;
  lText: string;
begin
  Result := False;
  aError := '';
  try
    if not LoadRemoveWithSource(aPath, lSource, aError) then
      Exit(False);
    lText := lSource.fText;
    lEdits := Copy(aEdits);
    SortEditsDescending(lEdits);
    for lEdit in lEdits do
    begin
      lReplacementText := ReplacementTextForSource(lEdit.fReplacementText, lSource);
      if not RemoveWithOffsetForLineColumn(lSource, lEdit.fRange.fStartLine, lEdit.fRange.fStartColumn,
        lStartOffset) then
      begin
        aError := 'edit-start-not-resolved';
        Exit(False);
      end;
      if lEdit.fKind = 'declare-temp' then
        Insert(lReplacementText, lText, lStartOffset)
      else
      begin
        if not RemoveWithOffsetForLineColumn(lSource, lEdit.fRange.fEndLine, lEdit.fRange.fEndColumn, lEndOffset) then
        begin
          aError := 'edit-end-not-resolved';
          Exit(False);
        end;
        lEndOffset := RemoveWithInclusiveEndOffset(lSource, lEndOffset);
        Delete(lText, lStartOffset, lEndOffset - lStartOffset + 1);
        Insert(lReplacementText, lText, lStartOffset);
      end;
    end;
    TFile.WriteAllBytes(aPath, RemoveWithTextToBytes(lText, lSource.fEncoding, lSource.fHasUtf8Bom));
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

class function TRemoveWithTransaction.ApplyEdits(const aPlanResult: TRemoveWithPlanResult;
  var aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean;
var
  lEdit: TRemoveWithPlannedTextEdit;
  lEditsByFile: TDictionary<string, TList<TRemoveWithPlannedTextEdit>>;
  lFilePair: TPair<string, TList<TRemoveWithPlannedTextEdit>>;
  lStatement: TRemoveWithPlannedStatement;
begin
  Result := False;
  aError := '';
  lEditsByFile := TDictionary<string, TList<TRemoveWithPlannedTextEdit>>.Create;
  try
    for lStatement in aPlanResult.fStatements do
    begin
      if lStatement.fStatus <> 'planned' then
        Continue;
      for lEdit in lStatement.fEdits do
      begin
        if not lEditsByFile.ContainsKey(lEdit.fFilePath) then
          lEditsByFile.Add(lEdit.fFilePath, TList<TRemoveWithPlannedTextEdit>.Create);
        lEditsByFile[lEdit.fFilePath].Add(lEdit);
      end;
    end;

    for lFilePair in lEditsByFile do
    begin
      if not BackupFile(lFilePair.Key, aTransactionResult.fBackupRoot, aTransactionResult, aError) then
        Exit(False);
      if not ApplyFileEdits(lFilePair.Key, lFilePair.Value.ToArray, aError) then
        Exit(False);
    end;
    Result := True;
  finally
    for lFilePair in lEditsByFile do
      lFilePair.Value.Free;
    lEditsByFile.Free;
  end;
end;

class function TRemoveWithTransaction.WriteManifest(const aManifestPath: string;
  const aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean;
var
  lFile: TRemoveWithTransactionFile;
  lFiles: TJSONArray;
  lRoot: TJSONObject;
begin
  Result := False;
  aError := '';
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('status', RemoveWithTransactionStatusToText(aTransactionResult.fStatus));
    lRoot.AddPair('backupRoot', aTransactionResult.fBackupRoot);
    lRoot.AddPair('contextFingerprint', aTransactionResult.fContextFingerprint);
    lRoot.AddPair('currentContextFingerprint', aTransactionResult.fCurrentContextFingerprint);
    lFiles := TJSONArray.Create;
    for lFile in aTransactionResult.fFiles do
    begin
      lFiles.AddElement(TJSONObject.Create
        .AddPair('path', lFile.fPath)
        .AddPair('backupPath', lFile.fBackupPath)
        .AddPair('hash', lFile.fHash)
        .AddPair('status', lFile.fStatus)
        .AddPair('size', TJSONNumber.Create(lFile.fSize))
        .AddPair('lineEnding', lFile.fLineEnding)
        .AddPair('encoding', lFile.fEncoding));
    end;
    lRoot.AddPair('files', lFiles);
    lRoot.AddPair('verificationStatus', aTransactionResult.fVerificationStatus);
    lRoot.AddPair('verificationError', aTransactionResult.fVerificationError);
    lRoot.AddPair('verificationStdOutLog', aTransactionResult.fVerificationStdOutLogPath);
    lRoot.AddPair('verificationStdErrLog', aTransactionResult.fVerificationStdErrLogPath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(aManifestPath));
    TFile.WriteAllBytes(aManifestPath, RemoveWithTextToBytes(lRoot.ToJSON,
      TRemoveWithSourceEncoding.rwseUtf8, False));
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
  lRoot.Free;
end;

class function TRemoveWithTransaction.ValidatePlanContext(const aApplyContext: TRemoveWithPlanApplyContext;
  var aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean;
var
  lCurrentContext: TRemoveWithPlanApplyContext;
  lCurrentFingerprint: string;
  lFileNames: TArray<string>;
  i: Integer;
begin
  Result := False;
  aError := '';
  aTransactionResult.fContextFingerprint := aApplyContext.fContextFingerprint;
  if (aApplyContext.fContextFingerprint = '') or (Length(aApplyContext.fSourceFingerprints) = 0) then
  begin
    aError := 'context-fingerprint-missing';
    Exit(False);
  end;

  SetLength(lFileNames, Length(aApplyContext.fSourceFingerprints));
  for i := 0 to High(aApplyContext.fSourceFingerprints) do
    lFileNames[i] := aApplyContext.fSourceFingerprints[i].fFilePath;

  if not BuildRemoveWithPlanApplyContextForFiles(lFileNames, lCurrentContext, aError) then
    Exit(False);

  lCurrentFingerprint := lCurrentContext.fContextFingerprint;
  aTransactionResult.fCurrentContextFingerprint := lCurrentFingerprint;
  if not SameText(aApplyContext.fContextFingerprint, lCurrentFingerprint) then
  begin
    aError := 'context-fingerprint-mismatch';
    Exit(False);
  end;
  Result := True;
end;

class function TRemoveWithTransaction.ValidateSemanticPlanContext(
  const aPlanResult: TRemoveWithPlanResult; const aApplyContext: TRemoveWithPlanApplyContext;
  out aError: string): Boolean;
begin
  Result := True;
  aError := '';
  if not SameText(aPlanResult.fSemanticPlan.Operation, 'remove-with') then
    Exit;

  if (aPlanResult.fSemanticPlan.ContextFingerprint = '') or
    (aApplyContext.fSemanticContextFingerprint = '') then
  begin
    aError := 'context-fingerprint-missing';
    Exit(False);
  end;

  if not SameText(aPlanResult.fSemanticPlan.ContextFingerprint,
    aApplyContext.fSemanticContextFingerprint) then
  begin
    aError := 'context-fingerprint-mismatch';
    Exit(False);
  end;
end;

class function TRemoveWithTransaction.VerifyBuild(const aOptions: TAppOptions;
  const aProjectPath, aDiagnosticsDir: string; var aTransactionResult: TRemoveWithTransactionResult;
  out aError: string): Boolean;
var
  lBuildOptions: TAppOptions;
  lExitCode: Integer;
  lMutex: THandle;
  lMutexAcquired: Boolean;
  lMutexName: string;
  lStdErrLogPath: string;
  lStdOutLogPath: string;
  lWaitResult: DWORD;
begin
  lBuildOptions := aOptions;
  lBuildOptions.fDprojPath := aProjectPath;
  lBuildOptions.fBuildBackend := TBuildBackend.bbDelphi;
  lBuildOptions.fBuildShowWarnings := False;
  lBuildOptions.fBuildShowHints := False;
  lBuildOptions.fBuildJson := False;
  lBuildOptions.fBuildQuiet := True;
  lBuildOptions.fBuildAi := False;
  lBuildOptions.fVerbose := False;
  lBuildOptions.fBuildDiagnosticsDir := aDiagnosticsDir;

  lStdOutLogPath := TPath.Combine(aDiagnosticsDir, 'stdout.log');
  lStdErrLogPath := TPath.Combine(aDiagnosticsDir, 'stderr.log');
  lMutexName := BuildVerificationMutexName(aProjectPath);
  lMutex := Winapi.Windows.CreateMutex(nil, False, PChar(lMutexName));
  if lMutex = 0 then
  begin
    aError := 'build-verification-lock-create-failed: ' + SysErrorMessage(Winapi.Windows.GetLastError);
    Exit(False);
  end;
  lMutexAcquired := False;
  try
    lWaitResult := Winapi.Windows.WaitForSingleObject(lMutex, cBuildVerificationMutexTimeoutMs);
    lMutexAcquired := lWaitResult in [Winapi.Windows.WAIT_OBJECT_0, Winapi.Windows.WAIT_ABANDONED];
    if lWaitResult = Winapi.Windows.WAIT_FAILED then
    begin
      aError := 'build-verification-lock-wait-failed: ' + SysErrorMessage(Winapi.Windows.GetLastError);
      Exit(False);
    end;
    if not lMutexAcquired then
    begin
      aError := 'build-verification-lock-timeout';
      Exit(False);
    end;

    Result := TryRunBuildInternal(lBuildOptions, lExitCode, aError) and (lExitCode = 0);
    if (not Result) and (aError = '') then
      aError := 'build-verification-failed';
    if FileExists(lStdOutLogPath) then
      aTransactionResult.fVerificationStdOutLogPath := lStdOutLogPath;
    if FileExists(lStdErrLogPath) then
      aTransactionResult.fVerificationStdErrLogPath := lStdErrLogPath;
  finally
    if lMutexAcquired then
      Winapi.Windows.ReleaseMutex(lMutex);
    Winapi.Windows.CloseHandle(lMutex);
  end;
end;

class function TRemoveWithTransaction.Apply(const aOptions: TAppOptions; const aProjectPath,
  aWorkspaceRoot: string; const aPlanResult: TRemoveWithPlanResult;
  const aApplyContext: TRemoveWithPlanApplyContext; out aTransactionResult: TRemoveWithTransactionResult;
  out aError: string): Boolean;
var
  lMutex: THandle;
  lMutexAcquired: Boolean;
  lMutexName: string;
  lWaitResult: DWORD;
begin
  aTransactionResult := Default(TRemoveWithTransactionResult);
  aTransactionResult.fBackupRoot := TPath.Combine(aWorkspaceRoot, 'backup');
  aTransactionResult.fManifestPath := TPath.Combine(aWorkspaceRoot, 'manifest.json');
  aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxNotRun;
  aTransactionResult.fVerificationStatus := 'not-run';
  aError := '';

  lMutexName := ApplyTransactionMutexName(aProjectPath);
  lMutex := Winapi.Windows.CreateMutex(nil, False, PChar(lMutexName));
  if lMutex = 0 then
  begin
    aError := 'apply-transaction-lock-create-failed: ' +
      SysErrorMessage(Winapi.Windows.GetLastError);
    aTransactionResult.fError := aError;
    Exit(False);
  end;

  lMutexAcquired := False;
  try
    lWaitResult := Winapi.Windows.WaitForSingleObject(lMutex, cApplyTransactionMutexTimeoutMs);
    lMutexAcquired := lWaitResult in [Winapi.Windows.WAIT_OBJECT_0, Winapi.Windows.WAIT_ABANDONED];
    if lWaitResult = Winapi.Windows.WAIT_FAILED then
    begin
      aError := 'apply-transaction-lock-wait-failed: ' +
        SysErrorMessage(Winapi.Windows.GetLastError);
      aTransactionResult.fError := aError;
      Exit(False);
    end;
    if not lMutexAcquired then
    begin
      aError := 'apply-transaction-lock-timeout';
      aTransactionResult.fError := aError;
      Exit(False);
    end;

    Result := ApplyLocked(aOptions, aProjectPath, aWorkspaceRoot, aPlanResult,
      aApplyContext, aTransactionResult, aError);
  finally
    if lMutexAcquired then
      Winapi.Windows.ReleaseMutex(lMutex);
    Winapi.Windows.CloseHandle(lMutex);
  end;
end;

class function TRemoveWithTransaction.ApplyLocked(const aOptions: TAppOptions; const aProjectPath,
  aWorkspaceRoot: string; const aPlanResult: TRemoveWithPlanResult;
  const aApplyContext: TRemoveWithPlanApplyContext; var aTransactionResult: TRemoveWithTransactionResult;
  out aError: string): Boolean;
var
  lContextValid: Boolean;
  lManifestError: string;
  lValidationError: string;
begin
  if not HasPlannedEdits(aPlanResult) then
  begin
    aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxApplied;
    Exit(WriteManifest(aTransactionResult.fManifestPath, aTransactionResult, aError));
  end;

  lContextValid := ValidateSemanticPlanContext(aPlanResult, aApplyContext, lValidationError);
  if lContextValid then
    lContextValid := ValidatePlanContext(aApplyContext, aTransactionResult, lValidationError);
  if lContextValid then
    lValidationError := '';
  if lValidationError <> '' then
  begin
    if SameText(lValidationError, 'context-fingerprint-missing') then
    begin
      aError := lValidationError;
      aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxContextFingerprintMissing;
    end else if lValidationError <> '' then
    begin
      aError := 'context-fingerprint-mismatch: ' + lValidationError;
      aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxContextFingerprintMismatch;
    end else
    begin
      aError := 'context-fingerprint-mismatch';
      aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxContextFingerprintMismatch;
    end;
    aTransactionResult.fError := aError;
    aTransactionResult.fVerificationStatus := 'not-run';
    aTransactionResult.fVerificationError := aError;
    WriteManifest(aTransactionResult.fManifestPath, aTransactionResult, lManifestError);
    Exit(False);
  end;

  if not VerifyBuild(aOptions, aProjectPath, TPath.Combine(aWorkspaceRoot, 'verification-preflight'),
    aTransactionResult, aError) then
  begin
    if aError <> '' then
      aError := cPreflightBuildFailed + ': ' + aError
    else
      aError := cPreflightBuildFailed;
    aTransactionResult.fError := aError;
    aTransactionResult.fVerificationStatus := 'failed';
    aTransactionResult.fVerificationError := aError;
    aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxPreflightBuildFailed;
    WriteManifest(aTransactionResult.fManifestPath, aTransactionResult, lManifestError);
    Exit(False);
  end;

  if ApplyEdits(aPlanResult, aTransactionResult, aError) then
  begin
    if VerifyBuild(aOptions, aProjectPath, TPath.Combine(aWorkspaceRoot, 'verification-apply'),
      aTransactionResult, aError) then
    begin
      aTransactionResult.fVerificationStatus := 'passed';
      SetFileStatuses(aTransactionResult, 'changed');
      aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxApplied;
      if WriteManifest(aTransactionResult.fManifestPath, aTransactionResult, aError) then
        Exit(True);
    end else
    begin
      aTransactionResult.fVerificationStatus := 'failed';
      aTransactionResult.fVerificationError := aError;
    end;
  end;

  aTransactionResult.fError := aError;
  if Rollback(aTransactionResult, aError) then
  begin
    SetFileStatuses(aTransactionResult, 'restored');
    aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxRolledBack;
    if aTransactionResult.fError = '' then
      aTransactionResult.fError := aError;
  end else
  begin
    aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxRollbackFailed;
    if aTransactionResult.fError <> '' then
      aTransactionResult.fError := aTransactionResult.fError + '; rollback: ' + aError
    else
      aTransactionResult.fError := 'rollback: ' + aError;
  end;
  WriteManifest(aTransactionResult.fManifestPath, aTransactionResult, aError);
  Result := False;
end;

function ApplyRemoveWithPlanTransactionally(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot: string;
  const aPlanResult: TRemoveWithPlanResult; const aApplyContext: TRemoveWithPlanApplyContext;
  out aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean;
begin
  Result := TRemoveWithTransaction.Apply(aOptions, aProjectPath, aWorkspaceRoot, aPlanResult, aApplyContext,
    aTransactionResult, aError);
end;

function ApplyRemoveWithPlanTransactionally(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot: string;
  const aPlanResult: TRemoveWithPlanResult; out aTransactionResult: TRemoveWithTransactionResult;
  out aError: string): Boolean;
var
  lApplyContext: TRemoveWithPlanApplyContext;
begin
  lApplyContext := Default(TRemoveWithPlanApplyContext);
  Result := ApplyRemoveWithPlanTransactionally(aOptions, aProjectPath, aWorkspaceRoot, aPlanResult,
    lApplyContext, aTransactionResult, aError);
end;

end.
