unit Dak.Refactor.RenameGuards;

interface

uses
  DelphiSemantics.Refactor,
  Dak.SourceText;

function ValidateRenamePlanGuards(const aPlan: TDelphiSemanticRenamePlan;
  const aFileName: string; const aSource: TDakSourceBuffer; out aError: string): Boolean;

implementation

uses
  System.Hash, System.IOUtils, System.StrUtils, System.SysUtils;

function RenameGuardError(const aMessage: string; const aFileName: string = '';
  const aLine: Integer = 0; const aColumn: Integer = 0): string;
begin
  Result := 'stale-rename-plan: ' + aMessage;
  if aFileName <> '' then
    Result := Result + ' in ' + aFileName;
  if aLine > 0 then
    Result := Result + ':' + aLine.ToString + ':' + aColumn.ToString;
end;

function CurrentSourceFileHash(const aFileName: string; out aHash, aError: string): Boolean;
begin
  aHash := '';
  aError := '';
  Result := False;
  if not TFile.Exists(aFileName) then
  begin
    aError := RenameGuardError('source file missing', aFileName);
    Exit;
  end;

  try
    aHash := THashSHA2.GetHashStringFromFile(aFileName);
    Result := True;
  except
    on E: Exception do
      aError := RenameGuardError('source file hash failed: ' + E.Message, aFileName);
  end;
end;

function SameRenameGuardFileName(const aLeft, aRight: string): Boolean;
begin
  if (aLeft = '') or (aRight = '') then
    Exit(False);
  try
    Result := SameText(TPath.GetFullPath(aLeft), TPath.GetFullPath(aRight));
  except
    Result := SameText(aLeft, aRight);
  end;
end;

function ValidateRenamePlanContract(const aPlan: TDelphiSemanticRenamePlan;
  out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  if aPlan.ContextFingerprint = '' then
  begin
    aError := RenameGuardError('missing context fingerprint');
    Exit;
  end;
  if aPlan.BaselineSemanticModelVersion = '' then
  begin
    aError := RenameGuardError('missing baseline semantic model version');
    Exit;
  end;
  if Length(aPlan.RequiredVerification) = 0 then
  begin
    aError := RenameGuardError('missing required verification');
    Exit;
  end;
  Result := True;
end;

function PlannedSourceTextAtRange(const aEdit: TDelphiSemanticTextEdit;
  const aSource: TDakSourceBuffer; out aText: string): Boolean;
var
  lEndOffset: Integer;
  lStartOffset: Integer;
begin
  aText := '';
  Result := False;
  if not DakOffsetForLineColumn(aSource, aEdit.StartLine, aEdit.StartColumn, lStartOffset) or
    not DakOffsetForLineColumn(aSource, aEdit.EndLine, aEdit.EndColumn, lEndOffset) or
    (lEndOffset < lStartOffset) or (lEndOffset > Length(aSource.fText)) then
    Exit;

  aText := DakTextSlice(aSource, lStartOffset, lEndOffset);
  Result := True;
end;

function ValidateRenameEditGuard(const aEdit: TDelphiSemanticTextEdit;
  const aCurrentFileHash: string; const aSource: TDakSourceBuffer; out aError: string): Boolean;
var
  lActualText: string;
begin
  Result := False;
  aError := '';
  if aEdit.ExpectedFileHash = '' then
  begin
    aError := RenameGuardError('missing expected file hash', aEdit.FileName, aEdit.StartLine,
      aEdit.StartColumn);
    Exit;
  end;
  if not SameText(aEdit.ExpectedFileHash, aCurrentFileHash) then
  begin
    aError := RenameGuardError('source file hash changed', aEdit.FileName, aEdit.StartLine,
      aEdit.StartColumn);
    Exit;
  end;
  if aEdit.ExpectedSourceText = '' then
  begin
    aError := RenameGuardError('missing expected source text', aEdit.FileName,
      aEdit.StartLine, aEdit.StartColumn);
    Exit;
  end;
  if not PlannedSourceTextAtRange(aEdit, aSource, lActualText) then
  begin
    aError := RenameGuardError('invalid source range', aEdit.FileName, aEdit.StartLine,
      aEdit.StartColumn);
    Exit;
  end;
  if lActualText <> aEdit.ExpectedSourceText then
  begin
    aError := RenameGuardError('source range changed', aEdit.FileName, aEdit.StartLine,
      aEdit.StartColumn);
    Exit;
  end;
  Result := True;
end;

function ValidateRenamePlanGuards(const aPlan: TDelphiSemanticRenamePlan;
  const aFileName: string; const aSource: TDakSourceBuffer; out aError: string): Boolean;
var
  lCurrentFileHash: string;
  lEdit: TDelphiSemanticTextEdit;
  lMatched: Boolean;
begin
  Result := False;
  aError := '';
  if not ValidateRenamePlanContract(aPlan, aError) then
    Exit;
  if not CurrentSourceFileHash(aFileName, lCurrentFileHash, aError) then
    Exit;

  lMatched := False;
  for lEdit in aPlan.Edits do
    if SameRenameGuardFileName(lEdit.FileName, aFileName) then
    begin
      lMatched := True;
      if not ValidateRenameEditGuard(lEdit, lCurrentFileHash, aSource, aError) then
        Exit;
    end;

  if not lMatched then
  begin
    aError := RenameGuardError('no edits matched source file', aFileName);
    Exit;
  end;

  Result := True;
end;

end.
