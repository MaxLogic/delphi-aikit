unit Dak.RemoveWith.Output;

interface

uses
  Dak.RemoveWith.Discovery,
  Dak.Types;

function RemoveWithModeToText(const aMode: TRemoveWithMode): string;
function RemoveWithFormatToText(const aFormat: TRemoveWithFormat): string;
function RemoveWithTargetKindToText(const aKind: TRemoveWithTargetKind): string;
function BuildRemoveWithJsonReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult): string;
function BuildRemoveWithTextReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult): string;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils;

const
  cRemoveWithSchemaVersion = 2;

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

function BuildProjectObject(const aProjectPath: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('path', aProjectPath);
  Result.AddPair('name', TPath.GetFileNameWithoutExtension(aProjectPath));
  Result.AddPair('dir', TPath.GetDirectoryName(aProjectPath));
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

function BuildResolverObject: TJSONObject;
var
  lCounts: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('classifications', TJSONArray.Create);

  lCounts := TJSONObject.Create;
  lCounts.AddPair('resolved', TJSONNumber.Create(0));
  lCounts.AddPair('unchanged', TJSONNumber.Create(0));
  lCounts.AddPair('external', TJSONNumber.Create(0));
  lCounts.AddPair('unsupported', TJSONNumber.Create(0));
  lCounts.AddPair('unresolved', TJSONNumber.Create(0));
  lCounts.AddPair('ambiguousToDak', TJSONNumber.Create(0));
  Result.AddPair('counts', lCounts);
end;

function BuildVerificationObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', 'not-run');
  Result.AddPair('gates', TJSONArray.Create);
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

function BuildSummaryObject(const aScanResult: TRemoveWithScanResult): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('filesScanned', TJSONNumber.Create(Length(aScanResult.fFiles)));
  Result.AddPair('withStatements', TJSONNumber.Create(Length(aScanResult.fWithStatements)));
  Result.AddPair('plannedEdits', TJSONNumber.Create(0));
  Result.AddPair('appliedEdits', TJSONNumber.Create(0));
  Result.AddPair('skipped', TJSONNumber.Create(0));
  Result.AddPair('failed', TJSONNumber.Create(0));
  Result.AddPair('rolledBack', TJSONNumber.Create(0));
end;

function BuildRemoveWithJsonReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult): string;
var
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('schemaVersion', TJSONNumber.Create(cRemoveWithSchemaVersion));
    lRoot.AddPair('operation', 'remove-with');
    lRoot.AddPair('status', 'ok');
    lRoot.AddPair('mode', RemoveWithModeToText(aOptions.fRemoveWithMode));
    lRoot.AddPair('format', RemoveWithFormatToText(aOptions.fRemoveWithFormat));
    lRoot.AddPair('project', BuildProjectObject(aProjectPath));
    lRoot.AddPair('run', BuildRunObject(aRunId, aWorkspaceRoot));
    lRoot.AddPair('targets', BuildTargetsObject(aOptions, aUnitPath, aDirPath));
    lRoot.AddPair('workspace', BuildWorkspaceObject(aWorkspaceRoot));
    lRoot.AddPair('files', BuildFilesArray(aScanResult));
    lRoot.AddPair('withStatements', BuildWithStatementsArray(aScanResult));
    lRoot.AddPair('resolver', BuildResolverObject);
    lRoot.AddPair('plannedEdits', TJSONArray.Create);
    lRoot.AddPair('skipped', TJSONArray.Create);
    lRoot.AddPair('warnings', BuildWarningsArray(aScanResult));
    lRoot.AddPair('verification', BuildVerificationObject);
    lRoot.AddPair('summary', BuildSummaryObject(aScanResult));
    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

function BuildRemoveWithTextReport(const aOptions: TAppOptions; const aProjectPath, aWorkspaceRoot, aRunId,
  aUnitPath, aDirPath: string; const aScanResult: TRemoveWithScanResult): string;
var
  lTargetValue: string;
begin
  lTargetValue := aUnitPath;
  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtDir then
    lTargetValue := aDirPath
  else if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtAll then
    lTargetValue := '<all project units>';

  Result := 'schemaVersion=' + IntToStr(cRemoveWithSchemaVersion) + sLineBreak +
    'operation=remove-with' + sLineBreak +
    'status=ok' + sLineBreak +
    'mode=' + RemoveWithModeToText(aOptions.fRemoveWithMode) + sLineBreak +
    'project=' + aProjectPath + sLineBreak +
    'run=' + aRunId + sLineBreak +
    'target=' + RemoveWithTargetKindToText(aOptions.fRemoveWithTargetKind) + ':' + lTargetValue + sLineBreak +
    'workspace=' + aWorkspaceRoot + sLineBreak +
    'filesScanned=' + IntToStr(Length(aScanResult.fFiles)) + sLineBreak +
    'withStatements=' + IntToStr(Length(aScanResult.fWithStatements)) + sLineBreak +
    'plannedEdits=0' + sLineBreak +
    'appliedEdits=0' + sLineBreak +
    'skipped=0' + sLineBreak +
    'failed=0' + sLineBreak +
    'rolledBack=0' + sLineBreak +
    'verification=not-run';
end;

end.
