unit Dak.RemoveWith.Transaction;

interface

uses
  Dak.RemoveWith.Planner, Dak.Types;

type
  TRemoveWithTransactionStatus = (rwtxNotRun, rwtxApplied, rwtxPreflightBuildFailed, rwtxRolledBack,
    rwtxRollbackFailed);

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
    fVerificationError: string;
    fVerificationStatus: string;
    fFiles: TArray<TRemoveWithTransactionFile>;
    fStatus: TRemoveWithTransactionStatus;
  end;

function RemoveWithTransactionStatusToText(const aStatus: TRemoveWithTransactionStatus): string;
function ApplyRemoveWithPlanTransactionally(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot: string;
  const aPlanResult: TRemoveWithPlanResult; out aTransactionResult: TRemoveWithTransactionResult;
  out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.Hash, System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows,
  Dak.Build.Runner, Dak.RemoveWith.Discovery, Dak.RemoveWith.Source;

const
  cRemoveWithFallbackDelphiVersion = '23.0';
  cBuildRequiresDelphiVersion = 'Delphi version is required';
  cBuildVerificationMutexName = 'Local\DakRemoveWithBuildVerification';
  cPreflightBuildFailed = 'preflight-build-failed';
  cBuildEnvironmentVariableNames: array[0..5] of string = ('BDS', 'BDSLIB', 'DCC_Namespace',
    'DCC_UnitSearchPath', 'DelphiLibraryPath', 'EnvOptions');

type
  TRemoveWithEnvironmentVariableState = record
    fName: string;
    fValue: string;
    fExisted: Boolean;
  end;

  TRemoveWithTransaction = record
  private
    class function FileHash(const aBytes: TBytes): string; static;
    class function DetectEncoding(const aBytes: TBytes): string; static;
    class function DetectLineEnding(const aBytes: TBytes): string; static;
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
    class function CaptureEnvironment: TArray<TRemoveWithEnvironmentVariableState>; static;
    class procedure AddEnvironmentVariable(var aEnvironment: TArray<TRemoveWithEnvironmentVariableState>;
      const aName, aValue: string); static;
    class procedure RestoreEnvironment(const aEnvironment: TArray<TRemoveWithEnvironmentVariableState>); static;
    class procedure RestoreEnvironmentVariable(const aName, aValue: string; const aExisted: Boolean); static;
    class procedure ClearInheritedBuildEnvironment; static;
    class function VerifyBuild(const aOptions: TAppOptions; const aProjectPath: string; out aError: string): Boolean;
      static;
  public
    class function Apply(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot: string;
      const aPlanResult: TRemoveWithPlanResult; out aTransactionResult: TRemoveWithTransactionResult;
      out aError: string): Boolean; static;
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
  else
    Result := 'not-run';
  end;
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

class function TRemoveWithTransaction.DetectEncoding(const aBytes: TBytes): string;
begin
  if (Length(aBytes) >= 3) and (aBytes[0] = $EF) and (aBytes[1] = $BB) and (aBytes[2] = $BF) then
    Exit(RemoveWithSourceEncodingToText(TRemoveWithSourceEncoding.rwseUtf8, True));
  try
    TEncoding.UTF8.GetString(aBytes);
    Result := RemoveWithSourceEncodingToText(TRemoveWithSourceEncoding.rwseUtf8, False);
  except
    on E: EEncodingError do
      Result := RemoveWithSourceEncodingToText(TRemoveWithSourceEncoding.rwseAnsi, False);
  end;
end;

class function TRemoveWithTransaction.DetectLineEnding(const aBytes: TBytes): string;
var
  lHasCrLf: Boolean;
  lHasLf: Boolean;
  i: Integer;
begin
  lHasCrLf := False;
  lHasLf := False;
  i := 0;
  while i < Length(aBytes) do
  begin
    if (aBytes[i] = 13) and (i + 1 < Length(aBytes)) and (aBytes[i + 1] = 10) then
    begin
      lHasCrLf := True;
      Inc(i, 2);
      Continue;
    end;
    if aBytes[i] = 10 then
      lHasLf := True;
    Inc(i);
  end;
  if lHasCrLf and lHasLf then
    Result := 'mixed'
  else if lHasCrLf then
    Result := 'crlf'
  else if lHasLf then
    Result := 'lf'
  else
    Result := 'none';
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
begin
  Result := False;
  aError := '';
  try
    if FileAlreadyTracked(aTransactionResult, aPath) then
      Exit(True);
    lBytes := TFile.ReadAllBytes(aPath);
    lIndex := Length(aTransactionResult.fFiles);
    lFile := Default(TRemoveWithTransactionFile);
    lFile.fPath := aPath;
    lFile.fBackupPath := TPath.Combine(aBackupRoot, IntToStr(lIndex + 1) + '-' + TPath.GetFileName(aPath) +
      '.bak');
    lFile.fHash := FileHash(lBytes);
    lFile.fLineEnding := DetectLineEnding(lBytes);
    lFile.fEncoding := DetectEncoding(lBytes);
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
      if not RemoveWithOffsetForLineColumn(lSource, lEdit.fRange.fStartLine, lEdit.fRange.fStartColumn,
        lStartOffset) then
      begin
        aError := 'edit-start-not-resolved';
        Exit(False);
      end;
      if lEdit.fKind = 'declare-temp' then
        Insert(lEdit.fReplacementText, lText, lStartOffset)
      else
      begin
        if not RemoveWithOffsetForLineColumn(lSource, lEdit.fRange.fEndLine, lEdit.fRange.fEndColumn, lEndOffset) then
        begin
          aError := 'edit-end-not-resolved';
          Exit(False);
        end;
        lEndOffset := RemoveWithInclusiveEndOffset(lSource, lEndOffset);
        Delete(lText, lStartOffset, lEndOffset - lStartOffset + 1);
        Insert(lEdit.fReplacementText, lText, lStartOffset);
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
    TDirectory.CreateDirectory(TPath.GetDirectoryName(aManifestPath));
    TFile.WriteAllText(aManifestPath, lRoot.ToJSON, TEncoding.UTF8);
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
  lRoot.Free;
end;

class procedure TRemoveWithTransaction.AddEnvironmentVariable(
  var aEnvironment: TArray<TRemoveWithEnvironmentVariableState>; const aName, aValue: string);
var
  lIndex: Integer;
begin
  lIndex := Length(aEnvironment);
  SetLength(aEnvironment, lIndex + 1);
  aEnvironment[lIndex].fName := aName;
  aEnvironment[lIndex].fValue := aValue;
  aEnvironment[lIndex].fExisted := True;
end;

class function TRemoveWithTransaction.CaptureEnvironment: TArray<TRemoveWithEnvironmentVariableState>;
var
  lBlock: PChar;
  lCursor: PChar;
  lLine: string;
  lName: string;
  lPos: Integer;
  lValue: string;
begin
  Result := nil;
  lBlock := Winapi.Windows.GetEnvironmentStrings;
  if lBlock = nil then
    Exit;

  try
    lCursor := lBlock;
    while lCursor^ <> #0 do
    begin
      lLine := string(lCursor);
      if (lLine <> '') and (lLine[1] <> '=') then
      begin
        lPos := Pos('=', lLine);
        if lPos > 1 then
        begin
          lName := Copy(lLine, 1, lPos - 1);
          lValue := Copy(lLine, lPos + 1, MaxInt);
          AddEnvironmentVariable(Result, lName, lValue);
        end;
      end;
      Inc(lCursor, StrLen(lCursor) + 1);
    end;
  finally
    Winapi.Windows.FreeEnvironmentStrings(lBlock);
  end;
end;

class procedure TRemoveWithTransaction.RestoreEnvironmentVariable(const aName, aValue: string;
  const aExisted: Boolean);
begin
  if aExisted then
    Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aValue))
  else
    Winapi.Windows.SetEnvironmentVariable(PChar(aName), nil);
end;

class procedure TRemoveWithTransaction.RestoreEnvironment(
  const aEnvironment: TArray<TRemoveWithEnvironmentVariableState>);
var
  lCurrent: TArray<TRemoveWithEnvironmentVariableState>;
  lState: TRemoveWithEnvironmentVariableState;
begin
  lCurrent := CaptureEnvironment;
  for lState in lCurrent do
    RestoreEnvironmentVariable(lState.fName, '', False);
  for lState in aEnvironment do
    RestoreEnvironmentVariable(lState.fName, lState.fValue, True);
end;

class procedure TRemoveWithTransaction.ClearInheritedBuildEnvironment;
var
  lName: string;
begin
  for lName in cBuildEnvironmentVariableNames do
    Winapi.Windows.SetEnvironmentVariable(PChar(lName), nil);
end;

class function TRemoveWithTransaction.VerifyBuild(const aOptions: TAppOptions; const aProjectPath: string;
  out aError: string): Boolean;
var
  lBuildOptions: TAppOptions;
  lEnvironment: TArray<TRemoveWithEnvironmentVariableState>;
  lExitCode: Integer;
  lMutex: THandle;
  lMutexAcquired: Boolean;
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

  lEnvironment := CaptureEnvironment;
  lMutex := Winapi.Windows.CreateMutex(nil, False, PChar(cBuildVerificationMutexName));
  lMutexAcquired := False;
  try
    if lMutex <> 0 then
    begin
      lWaitResult := Winapi.Windows.WaitForSingleObject(lMutex, Winapi.Windows.INFINITE);
      lMutexAcquired := lWaitResult in [Winapi.Windows.WAIT_OBJECT_0, Winapi.Windows.WAIT_ABANDONED];
    end;

    ClearInheritedBuildEnvironment;
    Result := TryRunBuildInternal(lBuildOptions, lExitCode, aError) and (lExitCode = 0);
    if (not Result) and (Trim(lBuildOptions.fDelphiVersion) = '') and
      (Pos(cBuildRequiresDelphiVersion, aError) > 0) then
    begin
      lBuildOptions.fDelphiVersion := cRemoveWithFallbackDelphiVersion;
      aError := '';
      Result := TryRunBuildInternal(lBuildOptions, lExitCode, aError) and (lExitCode = 0);
    end;
    if (not Result) and (aError = '') then
      aError := 'build-verification-failed';
  finally
    if lMutexAcquired then
      Winapi.Windows.ReleaseMutex(lMutex);
    if lMutex <> 0 then
      Winapi.Windows.CloseHandle(lMutex);
    RestoreEnvironment(lEnvironment);
  end;
end;

class function TRemoveWithTransaction.Apply(const aOptions: TAppOptions; const aProjectPath,
  aWorkspaceRoot: string; const aPlanResult: TRemoveWithPlanResult;
  out aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean;
var
  lManifestError: string;
begin
  aTransactionResult := Default(TRemoveWithTransactionResult);
  aTransactionResult.fBackupRoot := TPath.Combine(aWorkspaceRoot, 'backup');
  aTransactionResult.fManifestPath := TPath.Combine(aWorkspaceRoot, 'manifest.json');
  aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxNotRun;
  aTransactionResult.fVerificationStatus := 'not-run';
  aError := '';

  if not HasPlannedEdits(aPlanResult) then
  begin
    aTransactionResult.fStatus := TRemoveWithTransactionStatus.rwtxApplied;
    Exit(WriteManifest(aTransactionResult.fManifestPath, aTransactionResult, aError));
  end;

  if not VerifyBuild(aOptions, aProjectPath, aError) then
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
    if VerifyBuild(aOptions, aProjectPath, aError) then
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
  const aPlanResult: TRemoveWithPlanResult; out aTransactionResult: TRemoveWithTransactionResult;
  out aError: string): Boolean;
begin
  Result := TRemoveWithTransaction.Apply(aOptions, aProjectPath, aWorkspaceRoot, aPlanResult, aTransactionResult,
    aError);
end;

end.
