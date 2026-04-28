unit Dak.RemoveWith.Transaction;

interface

uses
  Dak.RemoveWith.Planner, Dak.Types;

type
  TRemoveWithTransactionStatus = (rwtxNotRun, rwtxApplied, rwtxRolledBack, rwtxRollbackFailed);

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

type
  TRemoveWithTransaction = record
  private
    class function BytesToText(const aBytes: TBytes; const aHasUtf8Bom: Boolean): string; static;
    class function FileHash(const aBytes: TBytes): string; static;
    class function DetectEncoding(const aBytes: TBytes): string; static;
    class function DetectLineEnding(const aBytes: TBytes): string; static;
    class function TextToBytes(const aText: string; const aHasUtf8Bom: Boolean): TBytes; static;
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
    TRemoveWithTransactionStatus.rwtxRolledBack:
      Result := 'rolledBack';
    TRemoveWithTransactionStatus.rwtxRollbackFailed:
      Result := 'rollbackFailed';
  else
    Result := 'not-run';
  end;
end;

class function TRemoveWithTransaction.BytesToText(const aBytes: TBytes; const aHasUtf8Bom: Boolean): string;
var
  lOffset: Integer;
begin
  lOffset := 0;
  if aHasUtf8Bom then
    lOffset := 3;
  Result := TEncoding.UTF8.GetString(aBytes, lOffset, Length(aBytes) - lOffset);
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
    Result := 'utf-8-bom'
  else
    Result := 'utf-8';
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

class function TRemoveWithTransaction.TextToBytes(const aText: string; const aHasUtf8Bom: Boolean): TBytes;
var
  lBody: TBytes;
begin
  lBody := TEncoding.UTF8.GetBytes(aText);
  if not aHasUtf8Bom then
    Exit(lBody);
  SetLength(Result, Length(lBody) + 3);
  Result[0] := $EF;
  Result[1] := $BB;
  Result[2] := $BF;
  if Length(lBody) > 0 then
    Move(lBody[0], Result[3], Length(lBody));
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
  lBytes: TBytes;
  lEdits: TArray<TRemoveWithPlannedTextEdit>;
  lEdit: TRemoveWithPlannedTextEdit;
  lEndOffset: Integer;
  lHasBom: Boolean;
  lSource: TRemoveWithSourceBuffer;
  lStartOffset: Integer;
  lText: string;
begin
  Result := False;
  aError := '';
  try
    lBytes := TFile.ReadAllBytes(aPath);
    lHasBom := DetectEncoding(lBytes) = 'utf-8-bom';
    lText := BytesToText(lBytes, lHasBom);
    lSource := Default(TRemoveWithSourceBuffer);
    lSource.fPath := aPath;
    lSource.fText := lText;
    if not LoadRemoveWithSource(aPath, lSource, aError) then
      Exit(False);
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
        Delete(lText, lStartOffset, lEndOffset - lStartOffset + 1);
        Insert(lEdit.fReplacementText, lText, lStartOffset);
      end;
    end;
    TFile.WriteAllBytes(aPath, TextToBytes(lText, lHasBom));
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

class procedure TRemoveWithTransaction.ClearInheritedBuildEnvironment;
begin
  Winapi.Windows.SetEnvironmentVariable(PChar('BDS'), nil);
  Winapi.Windows.SetEnvironmentVariable(PChar('BDSLIB'), nil);
  Winapi.Windows.SetEnvironmentVariable(PChar('DCC_Namespace'), nil);
  Winapi.Windows.SetEnvironmentVariable(PChar('DCC_UnitSearchPath'), nil);
  Winapi.Windows.SetEnvironmentVariable(PChar('DelphiLibraryPath'), nil);
  Winapi.Windows.SetEnvironmentVariable(PChar('EnvOptions'), nil);
end;

class function TRemoveWithTransaction.VerifyBuild(const aOptions: TAppOptions; const aProjectPath: string;
  out aError: string): Boolean;
var
  lBuildOptions: TAppOptions;
  lExitCode: Integer;
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
end;

class function TRemoveWithTransaction.Apply(const aOptions: TAppOptions; const aProjectPath,
  aWorkspaceRoot: string; const aPlanResult: TRemoveWithPlanResult;
  out aTransactionResult: TRemoveWithTransactionResult; out aError: string): Boolean;
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
