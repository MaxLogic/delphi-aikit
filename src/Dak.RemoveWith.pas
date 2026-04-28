unit Dak.RemoveWith;

interface

uses
  Dak.Types;

function RunRemoveWithCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.IOUtils, System.SysUtils,
  Dak.ExitCodes, Dak.RemoveWith.Discovery, Dak.RemoveWith.Output, Dak.RemoveWith.Resolver,
  Dak.RemoveWith.Symbols, Dak.Utils;

function NewRemoveWithRunId: string;
var
  lGuid: TGUID;
begin
  if CreateGUID(lGuid) <> 0 then
    Exit(FormatDateTime('yyyymmddhhnnsszzz', Now));

  Result := GUIDToString(lGuid);
  Result := StringReplace(Result, '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
  Result := LowerCase(Result);
end;

procedure WriteRemoveWithOutput(const aOptions: TAppOptions; const aOutputText: string);
var
  lOutputDir: string;
begin
  WriteLn(aOutputText);
  if (not aOptions.fHasRemoveWithOutputPath) or (Trim(aOptions.fRemoveWithOutputPath) = '') or
    (aOptions.fRemoveWithOutputPath = '-') then
    Exit;

  lOutputDir := TPath.GetDirectoryName(aOptions.fRemoveWithOutputPath);
  if lOutputDir <> '' then
    TDirectory.CreateDirectory(lOutputDir);
  TFile.WriteAllText(aOptions.fRemoveWithOutputPath, aOutputText, TEncoding.UTF8);
end;

function ResolveRemoveWithTargetPaths(const aOptions: TAppOptions; out aUnitPath, aDirPath, aError: string): Boolean;
begin
  aUnitPath := '';
  aDirPath := '';
  aError := '';

  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtUnit then
  begin
    if not TryResolveAbsolutePath(aOptions.fRemoveWithUnitPath, aUnitPath, aError) then
      Exit(False);
    if not FileExists(aUnitPath) then
    begin
      aError := Format('File not found: %s', [aUnitPath]);
      Exit(False);
    end;
  end else if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtDir then
  begin
    if not TryResolveAbsolutePath(aOptions.fRemoveWithDirPath, aDirPath, aError) then
      Exit(False);
    if not TDirectory.Exists(aDirPath) then
    begin
      aError := Format('Directory not found: %s', [aDirPath]);
      Exit(False);
    end;
  end;

  Result := True;
end;

function RunRemoveWithCommand(const aOptions: TAppOptions): Integer;
var
  lDirPath: string;
  lError: string;
  lOutputText: string;
  lProjectName: string;
  lProjectPath: string;
  lResolverResult: TRemoveWithResolverResult;
  lRunId: string;
  lScanResult: TRemoveWithScanResult;
  lSymbolInventory: TRemoveWithSymbolInventory;
  lUnitPath: string;
  lWorkspaceRoot: string;
begin
  if not TryResolveDprojPath(aOptions.fDprojPath, lProjectPath, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;

  if not ResolveRemoveWithTargetPaths(aOptions, lUnitPath, lDirPath, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;

  lProjectName := TPath.GetFileNameWithoutExtension(lProjectPath);
  lRunId := NewRemoveWithRunId;
  lWorkspaceRoot := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetDirectoryName(lProjectPath), '.dak'), lProjectName),
    TPath.Combine('remove-with', lRunId));
  TDirectory.CreateDirectory(lWorkspaceRoot);

  if not DiscoverRemoveWithStatements(aOptions, lProjectPath, lScanResult, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitToolFailure);
  end;
  lResolverResult := Default(TRemoveWithResolverResult);
  if aOptions.fRemoveWithMode <> TRemoveWithMode.rwmScan then
  begin
    if not BuildRemoveWithSymbolInventory(aOptions, lSymbolInventory, lError) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(cExitToolFailure);
    end;
    if not ResolveRemoveWithIdentifiers(lSymbolInventory, lScanResult, lResolverResult, lError) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(cExitToolFailure);
    end;
  end;

  if aOptions.fRemoveWithFormat = TRemoveWithFormat.rwfText then
    lOutputText := BuildRemoveWithTextReport(aOptions, lProjectPath, lWorkspaceRoot, lRunId, lUnitPath, lDirPath,
      lScanResult)
  else
    lOutputText := BuildRemoveWithJsonReport(aOptions, lProjectPath, lWorkspaceRoot, lRunId, lUnitPath, lDirPath,
      lScanResult, lResolverResult);
  WriteRemoveWithOutput(aOptions, lOutputText);
  Result := cExitSuccess;
end;

end.
