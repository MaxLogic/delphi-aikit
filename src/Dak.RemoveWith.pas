unit Dak.RemoveWith;

interface

uses
  Dak.Types;

function RunRemoveWithCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  Dak.ExitCodes, Dak.Utils;

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

function BuildRemoveWithJsonReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aUnitPath,
  aDirPath: string): string;
var
  lProjectJson: TJSONObject;
  lRoot: TJSONObject;
  lSummary: TJSONObject;
  lTargets: TJSONObject;
  lWorkspace: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('operation', 'remove-with');
    lRoot.AddPair('mode', RemoveWithModeToText(aOptions.fRemoveWithMode));
    lRoot.AddPair('format', RemoveWithFormatToText(aOptions.fRemoveWithFormat));

    lProjectJson := TJSONObject.Create;
    lProjectJson.AddPair('path', aProjectPath);
    lProjectJson.AddPair('name', TPath.GetFileNameWithoutExtension(aProjectPath));
    lProjectJson.AddPair('dir', TPath.GetDirectoryName(aProjectPath));
    lRoot.AddPair('project', lProjectJson);

    lTargets := TJSONObject.Create;
    lTargets.AddPair('kind', RemoveWithTargetKindToText(aOptions.fRemoveWithTargetKind));
    lTargets.AddPair('unit', aUnitPath);
    lTargets.AddPair('dir', aDirPath);
    lTargets.AddPair('all', TJSONBool.Create(aOptions.fRemoveWithAll));
    lRoot.AddPair('targets', lTargets);

    lWorkspace := TJSONObject.Create;
    lWorkspace.AddPair('root', aWorkspaceRoot);
    lWorkspace.AddPair('reports', TPath.Combine(aWorkspaceRoot, 'reports'));
    lWorkspace.AddPair('tmp', TPath.Combine(aWorkspaceRoot, 'tmp'));
    lRoot.AddPair('workspace', lWorkspace);

    lSummary := TJSONObject.Create;
    lSummary.AddPair('filesScanned', TJSONNumber.Create(0));
    lSummary.AddPair('withStatements', TJSONNumber.Create(0));
    lSummary.AddPair('plannedEdits', TJSONNumber.Create(0));
    lSummary.AddPair('appliedEdits', TJSONNumber.Create(0));
    lSummary.AddPair('skipped', TJSONNumber.Create(0));
    lSummary.AddPair('failed', TJSONNumber.Create(0));
    lSummary.AddPair('rolledBack', TJSONNumber.Create(0));
    lRoot.AddPair('summary', lSummary);

    lRoot.AddPair('warnings', TJSONArray.Create);
    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

function BuildRemoveWithTextReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aUnitPath,
  aDirPath: string): string;
var
  lTargetValue: string;
begin
  lTargetValue := aUnitPath;
  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtDir then
    lTargetValue := aDirPath
  else if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtAll then
    lTargetValue := '<all project units>';

  Result := 'operation=remove-with' + sLineBreak +
    'mode=' + RemoveWithModeToText(aOptions.fRemoveWithMode) + sLineBreak +
    'project=' + aProjectPath + sLineBreak +
    'target=' + RemoveWithTargetKindToText(aOptions.fRemoveWithTargetKind) + ':' + lTargetValue + sLineBreak +
    'workspace=' + aWorkspaceRoot + sLineBreak +
    'withStatements=0';
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
  lRunId: string;
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

  if aOptions.fRemoveWithFormat = TRemoveWithFormat.rwfText then
    lOutputText := BuildRemoveWithTextReport(aOptions, lProjectPath, lWorkspaceRoot, lUnitPath, lDirPath)
  else
    lOutputText := BuildRemoveWithJsonReport(aOptions, lProjectPath, lWorkspaceRoot, lUnitPath, lDirPath);
  WriteRemoveWithOutput(aOptions, lOutputText);
  Result := cExitSuccess;
end;

end.
