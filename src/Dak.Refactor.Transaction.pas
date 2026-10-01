unit Dak.Refactor.Transaction;

interface

uses
  DelphiSemantics.Refactor.Plan,
  Dak.Types;

type
  TRefactoringTransactionFile = record
    FileName: string;
    OriginalHash: string;
    ProposedHash: string;
    Status: string;
    Error: string;
  end;

  TRefactoringTransactionResult = record
    Status: string;
    Error: string;
    JournalPath: string;
    BaselineLog: string;
    VerificationLog: string;
    Files: TArray<TRefactoringTransactionFile>;
  end;

  // Progress is synchronous. No source lease is held during notification;
  // every following mutation must revalidate its own source under a lease.
  TRefactoringProgress = reference to procedure(const aPhase: string; const aIndex: Integer);

// Infrastructure only: this byte transaction does not authorize semantic apply.
// New-operation CLI apply remains disabled pending T-625/T-355 certification.
function ApplyRefactoringTransaction(const aOptions: TAppOptions;
  const aPlan: TSemanticRefactoringPlan; const aWorkspaceRoot: string;
  out aResult: TRefactoringTransactionResult;
  const aProgress: TRefactoringProgress = nil): Boolean;
function RecoverRefactoringTransaction(const aProjectPath, aWorkspaceRoot, aJournalPath: string;
  out aResult: TRefactoringTransactionResult): Boolean;
// .dak\<ProjectName>\refactor-transactions: one <run token> directory per transaction. Recovery finds journals
// by scanning it, whatever the directory names (older DAK versions used a 38-character GUID).
function TransactionRoot(const aProject: string): string;
// DAK-385: creates one transaction's directory below TransactionRoot.
function TryCreateTransactionDirectory(const aProject: string; out aDirectory: string; out aError: string): Boolean;
// DAK-385: the temporary file an atomic journal or staging write creates beside aPath.
function AtomicArtifactTempPath(const aPath: string): string;
{$IFDEF DAK_TRANSACTION_TEST_ACCESS}
// Test-only declaration of the unchanged private budget implementation.
// Preparation reserves half the reader budget for recovery status/error growth.
function RefactoringJournalLimitError(const aFileCount: Integer; const aByteCount: Int64;
  const aState: string): string;
{$ENDIF}

implementation

uses
  System.Classes, System.Hash, System.IOUtils, System.JSON, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  AutoFree, maxLogic.ioutils,
  Dak.Build.Runner, Dak.Paths, Dak.Refactor.Preflight, Dak.Utils;

const
  cMaxTransactionFiles = 1000;
  cPreparedJournalBytes: Int64 = 2097152;
  cRecoveryJournalBytes: Int64 = 4194304;

function RefactoringJournalLimitError(const aFileCount: Integer; const aByteCount: Int64;
  const aState: string): string;
begin
  Result := '';
  if aFileCount > cMaxTransactionFiles then
    Exit('transaction.too-many-files');
  if (aByteCount > cRecoveryJournalBytes) or
    ((aState = 'prepared') and (aByteCount > cPreparedJournalBytes)) then
    Result := 'transaction.journal-too-large';
end;

function HashBytes(const aBytes: TBytes): string;
var
  lHash: THashSHA2;
begin
  lHash := THashSHA2.Create;
  lHash.Update(aBytes);
  Result := lHash.HashAsString;
end;

{$WARN SYMBOL_PLATFORM OFF}
function HandlePath(const aHandle: THandle): string;
var
  lCount: Cardinal;
begin
  lCount := GetFinalPathNameByHandle(aHandle, nil, 0, 0);
  if lCount = 0 then
    RaiseLastOSError;
  SetLength(Result, lCount);
  lCount := GetFinalPathNameByHandle(aHandle, PChar(Result), Length(Result), 0);
  if (lCount = 0) or (lCount >= Cardinal(Length(Result))) then
    raise EInOutError.Create('transaction.path-identity-failed');
  SetLength(Result, lCount);
  if StartsText('\\?\UNC\', Result) then
    Result := '\\' + Copy(Result, 9, MaxInt)
  else if StartsText('\\?\', Result) then
    Delete(Result, 1, 4);
end;
{$WARN SYMBOL_PLATFORM ON}

function CanonicalDirectory(const aPath: string): string;
var
  lHandle: THandle;
begin
  lHandle := CreateFile(PChar(LongPathSafe(aPath)), FILE_READ_ATTRIBUTES, FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if lHandle = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
  try
    Result := ExcludeTrailingPathDelimiter(HandlePath(lHandle));
  finally
    CloseHandle(lHandle);
  end;
end;

function OpenChecked(const aPath, aRoot: string; const aMode: Word): TFileStream;
var
  lPath: string;
  lInfo: TByHandleFileInformation;
begin
  Result := TFileStream.Create(LongPathSafe(aPath), aMode);
  try
    lPath := HandlePath(Result.Handle);
    if not SameText(lPath, TPath.GetFullPath(aPath)) or
      not StartsText(IncludeTrailingPathDelimiter(aRoot), lPath) then
      raise EInOutError.Create('transaction.path-alias-or-out-of-scope');
    if not GetFileInformationByHandle(Result.Handle, lInfo) then
      RaiseLastOSError;
    if lInfo.nNumberOfLinks <> 1 then
      raise EInOutError.Create('transaction.hard-link');
  except
    Result.Free;
    raise;
  end;
end;

function ReadBytes(const aStream: TStream): TBytes;
begin
  if aStream.Size > MaxInt then
    raise EInOutError.Create('transaction.file-too-large');
  aStream.Position := 0;
  SetLength(Result, aStream.Size);
  if Length(Result) <> 0 then
    aStream.ReadBuffer(Result[0], Length(Result));
end;

function ReadChecked(const aPath, aRoot: string): TBytes;
var
  g: TGarbos;
  lStream: TFileStream;
begin
  g := Default(TGarbos);
  GC(lStream, OpenChecked(aPath, aRoot, fmOpenRead or fmShareDenyWrite), g);
  Result := ReadBytes(lStream);
end;

procedure WriteBytes(const aStream: TFileStream; const aBytes: TBytes);
begin
  aStream.Position := 0;
  if Length(aBytes) <> 0 then
    aStream.WriteBuffer(aBytes[0], Length(aBytes));
  aStream.Size := Length(aBytes);
  if not FlushFileBuffers(aStream.Handle) then
    RaiseLastOSError;
  if HashBytes(ReadBytes(aStream)) <> HashBytes(aBytes) then
    raise EInOutError.Create('transaction.write-verification-failed');
end;

function TryCreateTransactionDirectory(const aProject: string; out aDirectory: string; out aError: string): Boolean;
begin
  // DAK-385: <run token>, created exclusively so a new transaction never reuses a retained journal directory.
  Result := TryCreateDakRunDirectory(TransactionRoot(aProject), aDirectory, aError);
end;

function AtomicArtifactTempPath(const aPath: string): string;
begin
  // DAK-385: a short token (was a 38-character GUID). Every writer holds the project's transaction lock.
  Result := aPath + '.' + NewDakRunToken + '.tmp';
end;

procedure AtomicArtifact(const aPath: string; const aBytes: TBytes);
var
  lTemporary: string;
  lStream: TFileStream;
begin
  lTemporary := AtomicArtifactTempPath(aPath);
  try
    lStream := TFileStream.Create(LongPathSafe(lTemporary), fmCreate or fmShareExclusive);
    try
      WriteBytes(lStream, aBytes);
    finally
      lStream.Free;
    end;
    if not MoveFileEx(PChar(LongPathSafe(lTemporary)), PChar(LongPathSafe(aPath)),
      MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  finally
    if TFile.Exists(LongPathSafe(lTemporary)) then
      TFile.Delete(LongPathSafe(lTemporary));
  end;
end;

function TransactionRoot(const aProject: string): string;
begin
  // DAK-388: absolute like every other .dak root (a relative project path used to give a relative root).
  Result := DakProjectPath(DakProjectRootForProjectPath(aProject), ['refactor-transactions']);
end;

function StagePath(const aDirectory: string; const aIndex: Integer; const aKind: string): string;
begin
  Result := TPath.Combine(aDirectory, IntToStr(aIndex) + '.' + aKind);
end;

function AcquireLock(const aProject, aRoot: string): THandle;
var
  g: TGarbos;
  lDirectory: string;
  lProjectStream: TFileStream;
begin
  g := Default(TGarbos);
  // An existing project file proves the project is inside the selected root.
  GC(lProjectStream, OpenChecked(aProject, aRoot, fmOpenRead or fmShareDenyWrite), g);
  lDirectory := TransactionRoot(HandlePath(lProjectStream.Handle));
  TDirectory.CreateDirectory(lDirectory);
  if not SameText(CanonicalDirectory(lDirectory), lDirectory) then
    raise EInOutError.Create('transaction.journal-path-alias');
  Result := CreateFile(PChar(LongPathSafe(TPath.Combine(lDirectory, 'transaction.lock'))), GENERIC_READ or GENERIC_WRITE,
    0, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if Result = INVALID_HANDLE_VALUE then
    raise EInOutError.Create('transaction.busy');
end;

procedure SaveJournal(const aProject, aRoot: string; const aResult: TRefactoringTransactionResult);
var
  g: TGarbos;
  lJson, lFile: TJSONObject;
  lFiles: TJSONArray;
  lEntry: TRefactoringTransactionFile;
  lBytes: TBytes;
  lError: string;
begin
  g := Default(TGarbos);
  GC(lJson, TJSONObject.Create, g);
  lJson.AddPair('schemaVersion', TJSONNumber.Create(1));
  lJson.AddPair('project', aProject);
  lJson.AddPair('workspace', aRoot);
  lJson.AddPair('status', aResult.Status);
  lJson.AddPair('error', aResult.Error);
  lJson.AddPair('baselineLog', aResult.BaselineLog);
  lJson.AddPair('verificationLog', aResult.VerificationLog);
  lFiles := TJSONArray.Create;
  lJson.AddPair('files', lFiles);
  for lEntry in aResult.Files do
  begin
    lFile := TJSONObject.Create;
    lFiles.AddElement(lFile);
    lFile.AddPair('path', lEntry.FileName);
    lFile.AddPair('existed', TJSONBool.Create(True));
    lFile.AddPair('originalHash', lEntry.OriginalHash);
    lFile.AddPair('proposedHash', lEntry.ProposedHash);
    lFile.AddPair('status', lEntry.Status);
    lFile.AddPair('error', lEntry.Error);
  end;
  lBytes := TEncoding.UTF8.GetBytes(lJson.ToJSON);
  lError := RefactoringJournalLimitError(Length(aResult.Files), Length(lBytes), aResult.Status);
  if lError <> '' then
    raise EInOutError.Create(lError);
  AtomicArtifact(aResult.JournalPath, lBytes);
end;

function ReadJournal(const aPath: string): TJSONObject;
var
  lValue: TJSONValue;
begin
  if TFile.GetSize(aPath) > cRecoveryJournalBytes then
    raise EInOutError.Create('transaction.journal-too-large');
  lValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(aPath, TEncoding.UTF8));
  if not (lValue is TJSONObject) then
  begin
    lValue.Free;
    raise EInOutError.Create('transaction.invalid-journal');
  end;
  Result := lValue as TJSONObject;
end;

function PendingJournal(const aProject: string): string;
var
  g: TGarbos;
  lPath, lStatus: string;
  lJson: TJSONObject;
begin
  Result := '';
  for lPath in TDirectory.GetFiles(TransactionRoot(aProject), 'journal.json', TSearchOption.soAllDirectories) do
  begin
    g := Default(TGarbos);
    GC(lJson, ReadJournal(lPath), g);
    lStatus := lJson.GetValue<string>('status');
    if not MatchStr(lStatus, ['applied', 'rolled-back', 'baseline-failed', 'blocked']) then
      Exit(lPath);
  end;
end;

function VerifyBuild(const aOptions: TAppOptions; const aDirectory: string; out aError: string): Boolean;
var
  lOptions: TAppOptions;
  lExitCode: Integer;
begin
  lOptions := aOptions;
  lOptions.fBuildBackend := TBuildBackend.bbDelphi;
  lOptions.fBuildTarget := 'Rebuild';
  lOptions.fBuildQuiet := True;
  lOptions.fBuildAi := False;
  lOptions.fBuildJson := False;
  lOptions.fBuildDiagnosticsDir := aDirectory;
  Result := TryRunBuildInternal(lOptions, lExitCode, aError) and (lExitCode = 0);
  if not Result and (aError = '') then
    aError := 'compiler returned failure';
end;

procedure ReplaceOwnedBytes(const aPath, aRoot, aExpectedHash: string; const aReplacement: TBytes);
var
  g: TGarbos;
  lStream: TFileStream;
  lOriginal: TBytes;
  lPrimaryError: string;
begin
  g := Default(TGarbos);
  GC(lStream, OpenChecked(aPath, aRoot, fmOpenReadWrite or fmShareExclusive), g);
  lOriginal := ReadBytes(lStream);
  if HashBytes(lOriginal) <> aExpectedHash then
    raise EInOutError.Create('transaction.source-conflict');
  try
    WriteBytes(lStream, aReplacement);
  except
    on E: Exception do
    begin
      lPrimaryError := E.Message;
      // We still hold the exclusive source handle, so an ordinary failed write
      // remains ours. Restore before releasing it; preserve both failures.
      try
        WriteBytes(lStream, lOriginal);
      except
        on lRestoreError: Exception do
          raise EInOutError.Create(lPrimaryError + '; immediate-restore-failed: ' + lRestoreError.Message);
      end;
      raise EInOutError.Create(lPrimaryError);
    end;
  end;
end;

procedure VerifyWriteSet(const aRoot: string; const aResult: TRefactoringTransactionResult);
var
  lFile: TRefactoringTransactionFile;
  lExpected: string;
begin
  for lFile in aResult.Files do
  begin
    if lFile.Status = 'written' then
      lExpected := lFile.ProposedHash
    else
      lExpected := lFile.OriginalHash;
    if HashBytes(ReadChecked(lFile.FileName, aRoot)) <> lExpected then
      raise EInOutError.Create('transaction.source-conflict: ' + lFile.FileName);
  end;
end;

function Rollback(const aProject, aRoot: string; var aResult: TRefactoringTransactionResult): Boolean;
var
  i: Integer;
  lCurrentHash: string;
  lOriginal: TBytes;
begin
  Result := True;
  aResult.Status := 'rolling-back';
  for i := 0 to High(aResult.Files) do
  begin
    if MatchStr(aResult.Files[i].Status, ['staged', 'not-written', 'restored', 'unchanged']) then
    begin
      // We never acquired, or have already relinquished, this source. Even
      // exact proposed bytes can now belong to another actor.
      if aResult.Files[i].Status = 'staged' then
        aResult.Files[i].Status := 'not-written';
      Continue;
    end;
    try
      lCurrentHash := HashBytes(ReadChecked(aResult.Files[i].FileName, aRoot));
      // An untouched file may still be held read-only by another process.
      // Recognize original bytes before requesting an exclusive write lease.
      if lCurrentHash = aResult.Files[i].OriginalHash then
        aResult.Files[i].Status := 'unchanged'
      else if (aResult.Files[i].Status <> 'written') or (lCurrentHash <> aResult.Files[i].ProposedHash) then
      begin
        aResult.Files[i].Status := 'conflict';
        aResult.Files[i].Error := 'transaction.unowned-or-independent-bytes-preserved';
        Result := False;
      end else begin
        lOriginal := ReadChecked(StagePath(ExtractFileDir(aResult.JournalPath), i, 'original'), aRoot);
        if HashBytes(lOriginal) <> aResult.Files[i].OriginalHash then
          raise EInOutError.Create('transaction.backup-corrupt');
        // Release durable ownership before restoring. A crash after the source
        // write but before its completion marker must never authorize a retry
        // to overwrite a later independent edit that happens to match ours.
        aResult.Files[i].Status := 'restore-intent';
        SaveJournal(aProject, aRoot, aResult);
        ReplaceOwnedBytes(aResult.Files[i].FileName, aRoot, aResult.Files[i].ProposedHash, lOriginal);
        aResult.Files[i].Status := 'restored';
      end;
      SaveJournal(aProject, aRoot, aResult);
    except
      on E: Exception do
      begin
        aResult.Files[i].Status := 'restore-failed';
        aResult.Files[i].Error := E.Message;
        Result := False;
      end;
    end;
  end;
end;

function ValidRecoveryFileState(const aState, aFileState: string): Boolean;
begin
  if aState = 'prepared' then
    Exit(aFileState = 'staged');
  if aState = 'writing' then
    Exit(MatchStr(aFileState, ['staged', 'write-intent', 'written']));
  Result := MatchStr(aFileState, ['staged', 'not-written', 'write-intent', 'written',
    'restore-intent', 'restored', 'unchanged', 'conflict', 'restore-failed']);
end;

procedure LoadRecovery(const aProject, aRoot, aPath: string; out aResult: TRefactoringTransactionResult);
var
  g: TGarbos;
  lJson, lFile: TJSONObject;
  lFiles: TJSONArray;
  lDirectory: string;
  i, j: Integer;
begin
  aResult := Default(TRefactoringTransactionResult);
  g := Default(TGarbos);
  lDirectory := ExtractFileDir(TPath.GetFullPath(aPath));
  if not SameText(ExtractFileDir(lDirectory), TransactionRoot(aProject)) or
    not SameText(ExtractFileName(aPath), 'journal.json') or
    not SameText(CanonicalDirectory(lDirectory), lDirectory) then
    raise EInOutError.Create('transaction.invalid-journal-path');
  GC(lJson, ReadJournal(aPath), g);
  if (lJson.GetValue<Integer>('schemaVersion') <> 1) or
    not SameText(lJson.GetValue<string>('project'), aProject) or
    not SameText(lJson.GetValue<string>('workspace'), aRoot) then
    raise EInOutError.Create('transaction.journal-identity-mismatch');
  aResult.Status := lJson.GetValue<string>('status');
  if not MatchStr(aResult.Status, ['prepared', 'writing', 'rolling-back', 'rollback-failed']) then
    raise EInOutError.Create('transaction.not-interrupted');
  aResult.JournalPath := TPath.GetFullPath(aPath);
  aResult.BaselineLog := lJson.GetValue<string>('baselineLog');
  aResult.VerificationLog := lJson.GetValue<string>('verificationLog');
  aResult.Error := lJson.GetValue<string>('error');
  lFiles := lJson.GetValue<TJSONArray>('files');
  if (lFiles = nil) or (lFiles.Count > cMaxTransactionFiles) then
    raise EInOutError.Create('transaction.invalid-file-set');
  SetLength(aResult.Files, lFiles.Count);
  for i := 0 to lFiles.Count - 1 do
  begin
    lFile := lFiles.Items[i] as TJSONObject;
    aResult.Files[i].FileName := lFile.GetValue<string>('path');
    aResult.Files[i].OriginalHash := lFile.GetValue<string>('originalHash');
    aResult.Files[i].ProposedHash := lFile.GetValue<string>('proposedHash');
    aResult.Files[i].Status := lFile.GetValue<string>('status');
    if not ValidRecoveryFileState(aResult.Status, aResult.Files[i].Status) then
      raise EInOutError.Create('transaction.invalid-file-state');
    if not lFile.GetValue<Boolean>('existed') or
      not TPath.IsPathRooted(aResult.Files[i].FileName) or
      not StartsText(IncludeTrailingPathDelimiter(aRoot), TPath.GetFullPath(aResult.Files[i].FileName)) then
      raise EInOutError.Create('transaction.invalid-source-path');
    for j := 0 to i - 1 do
      if SameText(aResult.Files[j].FileName, aResult.Files[i].FileName) then
        raise EInOutError.Create('transaction.duplicate-source');
    if HashBytes(ReadChecked(StagePath(lDirectory, i, 'original'), aRoot)) <> aResult.Files[i].OriginalHash then
      raise EInOutError.Create('transaction.backup-corrupt');
    if HashBytes(ReadChecked(StagePath(lDirectory, i, 'proposed'), aRoot)) <> aResult.Files[i].ProposedHash then
      raise EInOutError.Create('transaction.staged-bytes-corrupt');
  end;
end;

function PrepareTransaction(const aOptions: TAppOptions; const aRoot: string;
  const aFiles: TArray<TDakMaterializedFile>; var aResult: TRefactoringTransactionResult): Boolean;
var
  lDirectory, lError: string;
  i: Integer;
begin
  Result := False;
  if not TryCreateTransactionDirectory(aOptions.fDprojPath, lDirectory, lError) then
    raise EInOutError.Create(lError);
  if not SameText(CanonicalDirectory(lDirectory), lDirectory) then
    raise EInOutError.Create('transaction.journal-path-alias');
  aResult.JournalPath := TPath.Combine(lDirectory, 'journal.json');
  aResult.BaselineLog := CombinePath([lDirectory, 'baseline', 'stdout.log']);
  aResult.VerificationLog := CombinePath([lDirectory, 'verification', 'stdout.log']);
  SetLength(aResult.Files, Length(aFiles));
  for i := 0 to High(aFiles) do
  begin
    aResult.Files[i].FileName := aFiles[i].FileName;
    aResult.Files[i].OriginalHash := aFiles[i].OriginalHash;
    aResult.Files[i].ProposedHash := aFiles[i].ProposedHash;
    aResult.Files[i].Status := 'staged';
    AtomicArtifact(StagePath(lDirectory, i, 'original'), aFiles[i].OriginalBytes);
    AtomicArtifact(StagePath(lDirectory, i, 'proposed'), aFiles[i].ProposedBytes);
  end;
  aResult.Status := 'prepared';
  SaveJournal(aOptions.fDprojPath, aRoot, aResult);
  if not VerifyBuild(aOptions, TPath.Combine(lDirectory, 'baseline'), lError) then
  begin
    aResult.Status := 'baseline-failed';
    aResult.Error := lError;
    SaveJournal(aOptions.fDprojPath, aRoot, aResult);
    Exit;
  end;
  Result := True;
end;

function ApplyPreparedTransaction(const aOptions: TAppOptions; const aRoot: string;
  const aFiles: TArray<TDakMaterializedFile>; var aResult: TRefactoringTransactionResult;
  const aProgress: TRefactoringProgress): Boolean;
var
  lDirectory, lError: string;
  i: Integer;
begin
  Result := False;
  lDirectory := ExtractFileDir(aResult.JournalPath);
  try
    VerifyWriteSet(aRoot, aResult);
    aResult.Status := 'writing';
    SaveJournal(aOptions.fDprojPath, aRoot, aResult);
    for i := 0 to High(aFiles) do
    begin
      aResult.Files[i].Status := 'write-intent';
      SaveJournal(aOptions.fDprojPath, aRoot, aResult);
      if HashBytes(ReadChecked(StagePath(lDirectory, i, 'proposed'), aRoot)) <> aFiles[i].ProposedHash then
        raise EInOutError.Create('transaction.staged-bytes-corrupt');
      ReplaceOwnedBytes(aFiles[i].FileName, aRoot, aFiles[i].OriginalHash, aFiles[i].ProposedBytes);
      aResult.Files[i].Status := 'written';
      SaveJournal(aOptions.fDprojPath, aRoot, aResult);
      if Assigned(aProgress) then
        aProgress('written', i);
      VerifyWriteSet(aRoot, aResult);
    end;
    if not VerifyBuild(aOptions, TPath.Combine(lDirectory, 'verification'), lError) then
      raise EInOutError.Create('post-build-failed: ' + lError);
    VerifyWriteSet(aRoot, aResult);
    aResult.Status := 'applied';
    SaveJournal(aOptions.fDprojPath, aRoot, aResult);
    Result := True;
  except
    on E: Exception do
    begin
      aResult.Error := E.Message;
      if Rollback(aOptions.fDprojPath, aRoot, aResult) then
        aResult.Status := 'rolled-back'
      else
        aResult.Status := 'rollback-failed';
      try
        SaveJournal(aOptions.fDprojPath, aRoot, aResult);
      except
        on lJournalError: Exception do
        begin
          aResult.Status := 'rollback-failed';
          aResult.Error := aResult.Error + '; journal-failed: ' + lJournalError.Message;
        end;
      end;
    end;
  end;
end;

function ApplyLocked(const aOptions: TAppOptions; const aPlan: TSemanticRefactoringPlan;
  const aRoot: string; out aResult: TRefactoringTransactionResult;
  const aProgress: TRefactoringProgress): Boolean;
var
  lFiles, lRefreshed: TArray<TDakMaterializedFile>;
  lError: string;
begin
  Result := False;
  aResult := Default(TRefactoringTransactionResult);
  aResult.JournalPath := PendingJournal(aOptions.fDprojPath);
  if aResult.JournalPath <> '' then
  begin
    aResult.Status := 'recovery-required';
    Exit;
  end;
  aResult.Status := 'blocked';
  if not MaterializeRefactoringPlan(aPlan, aRoot, lFiles, lError) then
  begin
    aResult.Error := lError;
    Exit;
  end;
  aResult.Error := RefactoringJournalLimitError(Length(lFiles), 0, 'prepared');
  if aResult.Error <> '' then
    Exit;
  if Length(lFiles) = 0 then
  begin
    aResult.Status := 'no-change';
    Exit(True);
  end;
  if not PrepareTransaction(aOptions, aRoot, lFiles, aResult) then
    Exit;
  // The baseline build is allowed to run arbitrary project build steps. Re-run
  // the complete byte preflight afterwards, before any source mutation.
  if not MaterializeRefactoringPlan(aPlan, aRoot, lRefreshed, lError) then
  begin
    aResult.Status := 'blocked';
    aResult.Error := lError;
    SaveJournal(aOptions.fDprojPath, aRoot, aResult);
    Exit;
  end;
  Result := ApplyPreparedTransaction(aOptions, aRoot, lFiles, aResult, aProgress);
end;

function ApplyRefactoringTransaction(const aOptions: TAppOptions;
  const aPlan: TSemanticRefactoringPlan; const aWorkspaceRoot: string;
  out aResult: TRefactoringTransactionResult; const aProgress: TRefactoringProgress): Boolean;
var
  lRoot: string;
  lOptions: TAppOptions;
  lLock: THandle;
begin
  Result := False;
  aResult := Default(TRefactoringTransactionResult);
  aResult.Status := 'blocked';
  lLock := INVALID_HANDLE_VALUE;
  try
    try
      if (aOptions.fPlatform = '') or (aOptions.fConfig = '') or (aOptions.fDelphiVersion = '') then
        raise EInOutError.Create('transaction.explicit-build-context-required');
      lRoot := CanonicalDirectory(aWorkspaceRoot);
      lOptions := aOptions;
      lOptions.fDprojPath := TPath.GetFullPath(aOptions.fDprojPath);
      lLock := AcquireLock(lOptions.fDprojPath, lRoot);
      Result := ApplyLocked(lOptions, aPlan, lRoot, aResult, aProgress);
    except
      on E: Exception do
      begin
        aResult.Error := E.Message;
        if MatchStr(aResult.Status, ['', 'prepared']) then
          aResult.Status := 'blocked';
      end;
    end;
  finally
    if lLock <> INVALID_HANDLE_VALUE then
      CloseHandle(lLock);
  end;
end;

function RecoverRefactoringTransaction(const aProjectPath, aWorkspaceRoot, aJournalPath: string;
  out aResult: TRefactoringTransactionResult): Boolean;
var
  lRoot, lProject: string;
  lLock: THandle;
  lRecoveryStarted: Boolean;
begin
  Result := False;
  aResult := Default(TRefactoringTransactionResult);
  aResult.Status := 'blocked';
  lLock := INVALID_HANDLE_VALUE;
  lRecoveryStarted := False;
  try
    try
      lRoot := CanonicalDirectory(aWorkspaceRoot);
      lProject := TPath.GetFullPath(aProjectPath);
      lLock := AcquireLock(lProject, lRoot);
      LoadRecovery(lProject, lRoot, aJournalPath, aResult);
      lRecoveryStarted := True;
      Result := Rollback(lProject, lRoot, aResult);
      if Result then
        aResult.Status := 'rolled-back'
      else
        aResult.Status := 'rollback-failed';
      SaveJournal(lProject, lRoot, aResult);
    except
      on E: Exception do
      begin
        Result := False;
        aResult.Error := E.Message;
        if lRecoveryStarted then
          aResult.Status := 'rollback-failed'
        else
          aResult.Status := 'blocked';
      end;
    end;
  finally
    if lLock <> INVALID_HANDLE_VALUE then
      CloseHandle(lLock);
  end;
end;

end.
