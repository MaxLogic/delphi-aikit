unit Test.RemoveWith;

interface

uses
  System.IOUtils, System.JSON, System.SysUtils,
  DUnitX.TestFramework,
  Test.Support;

type
  TRemoveWithTestBase = class
  protected
    function RunRemoveWith(const aMode, aFormat, aLogName: string; out aExitCode: Cardinal): string;
    procedure AssertJsonHasKey(const aObject: TJSONObject; const aName: string);
    procedure AssertJsonObjectKey(const aObject: TJSONObject; const aName: string; out aChild: TJSONObject);
    procedure AssertJsonArrayKey(const aObject: TJSONObject; const aName: string; out aChild: TJSONArray);
    procedure AssertJsonStringKey(const aObject: TJSONObject; const aName: string);
    procedure AssertJsonNumberKey(const aObject: TJSONObject; const aName: string);
    procedure AssertJsonBoolKey(const aObject: TJSONObject; const aName: string);
  end;

  [TestFixture]
  TRemoveWithCommandTests = class(TRemoveWithTestBase)
  public
    [Test]
    procedure ScanModeWritesJsonShellWithoutEditingSource;
  end;

  [TestFixture]
  TRemoveWithReportTests = class(TRemoveWithTestBase)
  public
    [Test]
    procedure ScanJsonReportUsesStableBaseSchema;
    [Test]
    procedure PlanJsonReportUsesStableBaseSchema;
    [Test]
    procedure TextReportShowsSkippedFailuresAndVerification;
  end;

  [TestFixture]
  TRemoveWithDiscoveryTests = class(TRemoveWithTestBase)
  private
    function RunDiscoveryFixture(const aTargetArgs, aLogName: string; out aExitCode: Cardinal): string;
  public
    [Test]
    procedure ScanFindsSingleMultipleAndNestedWithStatements;
    [Test]
    procedure ScanCliReportsDiscoveryFixtureStatements;
    [Test]
    procedure ScanUnitTargetFiltersFilesAndWarnings;
    [Test]
    procedure ScanDirTargetKeepsScopedWarnings;
  end;

implementation

function TRemoveWithTestBase.RunRemoveWith(const aMode, aFormat, aLogName: string; out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
  lUnitPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\LspProjectFixture.dproj');
  lUnitPath := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\Unit1.pas');
  lLogPath := TPath.Combine(TempRoot, aLogName);

  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --unit ' + QuoteArg(lUnitPath) +
    ' --mode ' + aMode + ' --format ' + aFormat;

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start remove-with process.');

  Result := '';
  if FileExists(lLogPath) then
    Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithTestBase.AssertJsonHasKey(const aObject: TJSONObject; const aName: string);
begin
  Assert.IsNotNull(aObject.Values[aName], 'Expected JSON key: ' + aName);
end;

procedure TRemoveWithTestBase.AssertJsonObjectKey(const aObject: TJSONObject; const aName: string;
  out aChild: TJSONObject);
begin
  AssertJsonHasKey(aObject, aName);
  Assert.IsTrue(aObject.Values[aName] is TJSONObject, 'Expected JSON object key: ' + aName);
  aChild := aObject.Values[aName] as TJSONObject;
end;

procedure TRemoveWithTestBase.AssertJsonArrayKey(const aObject: TJSONObject; const aName: string; out aChild: TJSONArray);
begin
  AssertJsonHasKey(aObject, aName);
  Assert.IsTrue(aObject.Values[aName] is TJSONArray, 'Expected JSON array key: ' + aName);
  aChild := aObject.Values[aName] as TJSONArray;
end;

procedure TRemoveWithTestBase.AssertJsonStringKey(const aObject: TJSONObject; const aName: string);
begin
  AssertJsonHasKey(aObject, aName);
  Assert.IsTrue(aObject.Values[aName] is TJSONString, 'Expected JSON string key: ' + aName);
end;

procedure TRemoveWithTestBase.AssertJsonNumberKey(const aObject: TJSONObject; const aName: string);
begin
  AssertJsonHasKey(aObject, aName);
  Assert.IsTrue(aObject.Values[aName] is TJSONNumber, 'Expected JSON number key: ' + aName);
end;

procedure TRemoveWithTestBase.AssertJsonBoolKey(const aObject: TJSONObject; const aName: string);
begin
  AssertJsonHasKey(aObject, aName);
  Assert.IsTrue(aObject.Values[aName] is TJSONBool, 'Expected JSON boolean key: ' + aName);
end;

procedure TRemoveWithCommandTests.ScanModeWritesJsonShellWithoutEditingSource;
var
  lExitCode: Cardinal;
  lLogText: string;
  lSourceAfter: string;
  lSourceBefore: string;
  lUnitPath: string;
begin
  lUnitPath := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\Unit1.pas');
  lSourceBefore := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);

  lLogText := RunRemoveWith('scan', 'json', 'remove-with-scan-shell.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with scan shell to succeed.');

  Assert.IsTrue(Pos('"operation":"remove-with"', lLogText) > 0,
    'Expected operation in remove-with JSON output.');
  Assert.IsTrue(Pos('"mode":"scan"', lLogText) > 0, 'Expected scan mode in remove-with JSON output.');
  Assert.IsTrue(Pos('"workspace"', lLogText) > 0, 'Expected workspace object in remove-with JSON output.');
  Assert.IsTrue(Pos('remove-with', lLogText) > 0, 'Expected remove-with workspace path in JSON output.');
  Assert.IsTrue(Pos('"warnings":[]', lLogText) > 0, 'Expected empty warning array in shell output.');

  lSourceAfter := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.AreEqual(lSourceBefore, lSourceAfter, 'Scan mode must not modify the target unit.');
end;

procedure TRemoveWithReportTests.ScanJsonReportUsesStableBaseSchema;
var
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lRoot: TJSONObject;
  lCounts: TJSONObject;
  lChildObject: TJSONObject;
  lChildArray: TJSONArray;
begin
  lOutput := RunRemoveWith('scan', 'json', 'remove-with-report-scan.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with scan report to succeed.');

  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected remove-with output to be a JSON object.');
    lRoot := lJson as TJSONObject;

    AssertJsonHasKey(lRoot, 'schemaVersion');
    AssertJsonHasKey(lRoot, 'operation');
    AssertJsonHasKey(lRoot, 'status');
    AssertJsonHasKey(lRoot, 'mode');
    AssertJsonObjectKey(lRoot, 'project', lChildObject);
    AssertJsonStringKey(lChildObject, 'path');
    AssertJsonStringKey(lChildObject, 'name');
    AssertJsonStringKey(lChildObject, 'dir');

    AssertJsonObjectKey(lRoot, 'run', lChildObject);
    AssertJsonStringKey(lChildObject, 'id');
    AssertJsonStringKey(lChildObject, 'workspaceRoot');

    AssertJsonObjectKey(lRoot, 'targets', lChildObject);
    AssertJsonStringKey(lChildObject, 'kind');
    Assert.AreEqual('unit', lChildObject.Values['kind'].Value, 'Expected unit target kind.');
    AssertJsonStringKey(lChildObject, 'unit');
    AssertJsonStringKey(lChildObject, 'dir');
    AssertJsonBoolKey(lChildObject, 'all');

    AssertJsonObjectKey(lRoot, 'workspace', lChildObject);
    AssertJsonStringKey(lChildObject, 'root');
    AssertJsonStringKey(lChildObject, 'reports');
    AssertJsonStringKey(lChildObject, 'tmp');
    AssertJsonStringKey(lChildObject, 'backup');
    AssertJsonStringKey(lChildObject, 'manifest');

    AssertJsonArrayKey(lRoot, 'files', lChildArray);
    AssertJsonArrayKey(lRoot, 'withStatements', lChildArray);
    AssertJsonObjectKey(lRoot, 'resolver', lChildObject);
    AssertJsonArrayKey(lChildObject, 'classifications', lChildArray);
    AssertJsonObjectKey(lChildObject, 'counts', lCounts);
    AssertJsonNumberKey(lCounts, 'resolved');
    AssertJsonNumberKey(lCounts, 'unchanged');
    AssertJsonNumberKey(lCounts, 'external');
    AssertJsonNumberKey(lCounts, 'unsupported');
    AssertJsonNumberKey(lCounts, 'unresolved');
    AssertJsonNumberKey(lCounts, 'ambiguousToDak');

    AssertJsonArrayKey(lRoot, 'plannedEdits', lChildArray);
    AssertJsonArrayKey(lRoot, 'skipped', lChildArray);
    AssertJsonArrayKey(lRoot, 'warnings', lChildArray);
    AssertJsonObjectKey(lRoot, 'verification', lChildObject);
    AssertJsonStringKey(lChildObject, 'status');
    Assert.AreEqual('not-run', lChildObject.Values['status'].Value, 'Expected verification status.');
    AssertJsonArrayKey(lChildObject, 'gates', lChildArray);

    AssertJsonObjectKey(lRoot, 'summary', lChildObject);
    AssertJsonNumberKey(lChildObject, 'filesScanned');
    AssertJsonNumberKey(lChildObject, 'withStatements');
    AssertJsonNumberKey(lChildObject, 'plannedEdits');
    AssertJsonNumberKey(lChildObject, 'appliedEdits');
    AssertJsonNumberKey(lChildObject, 'skipped');
    AssertJsonNumberKey(lChildObject, 'failed');
    AssertJsonNumberKey(lChildObject, 'rolledBack');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithReportTests.PlanJsonReportUsesStableBaseSchema;
var
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lRoot: TJSONObject;
  lChildObject: TJSONObject;
  lChildArray: TJSONArray;
begin
  lOutput := RunRemoveWith('plan', 'json', 'remove-with-report-plan.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with plan report to succeed.');

  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected remove-with output to be a JSON object.');
    lRoot := lJson as TJSONObject;

    Assert.AreEqual('plan', lRoot.Values['mode'].Value, 'Expected plan mode in report.');
    AssertJsonArrayKey(lRoot, 'withStatements', lChildArray);
    AssertJsonObjectKey(lRoot, 'resolver', lChildObject);
    AssertJsonArrayKey(lRoot, 'plannedEdits', lChildArray);
    AssertJsonArrayKey(lRoot, 'skipped', lChildArray);
    AssertJsonObjectKey(lRoot, 'verification', lChildObject);
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithReportTests.TextReportShowsSkippedFailuresAndVerification;
var
  lExitCode: Cardinal;
  lOutput: string;
begin
  lOutput := RunRemoveWith('scan', 'text', 'remove-with-report-text.txt', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with text report to succeed.');
  Assert.IsTrue(Pos('skipped=0', lOutput) > 0, 'Expected skipped count in text report.');
  Assert.IsTrue(Pos('failed=0', lOutput) > 0, 'Expected failed count in text report.');
  Assert.IsTrue(Pos('verification=not-run', lOutput) > 0, 'Expected verification status in text report.');
end;

function TRemoveWithDiscoveryTests.RunDiscoveryFixture(const aTargetArgs, aLogName: string; out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithDiscoveryFixture\RemoveWithDiscoveryFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' ' + aTargetArgs + ' --mode scan --format json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start remove-with discovery process.');
  Result := '';
  if FileExists(lLogPath) then
    Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithDiscoveryTests.ScanFindsSingleMultipleAndNestedWithStatements;
var
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lRoot: TJSONObject;
  lStatement: TJSONObject;
  lStatements: TJSONArray;
  lSummary: TJSONObject;
  i: Integer;
  lHasMultipleSelector: Boolean;
  lHasNestedStatement: Boolean;
begin
  lOutput := RunDiscoveryFixture('--all', 'remove-with-discovery-all.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected discovery scan to succeed.');

  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected discovery output to be JSON object.');
    lRoot := lJson as TJSONObject;
    AssertJsonArrayKey(lRoot, 'withStatements', lStatements);
    Assert.AreEqual(4, lStatements.Count, 'Expected all single, multiple, outer, and nested with statements.');

    lHasMultipleSelector := False;
    lHasNestedStatement := False;
    for i := 0 to lStatements.Count - 1 do
    begin
      Assert.IsTrue(lStatements.Items[i] is TJSONObject, 'Expected with statement item to be an object.');
      lStatement := lStatements.Items[i] as TJSONObject;
      AssertJsonStringKey(lStatement, 'selectorText');
      AssertJsonNumberKey(lStatement, 'selectorCount');
      AssertJsonNumberKey(lStatement, 'nestingDepth');
      AssertJsonObjectKey(lStatement, 'bodyRange', lSummary);
      AssertJsonNumberKey(lSummary, 'startLine');
      AssertJsonNumberKey(lSummary, 'endLine');

      if lStatement.Values['selectorText'].Value = 'lLeft, lRight' then
      begin
        lHasMultipleSelector := True;
        Assert.AreEqual('2', lStatement.Values['selectorCount'].Value, 'Expected two selectors.');
      end;
      if lStatement.Values['nestingDepth'].Value = '1' then
      begin
        lHasNestedStatement := True;
        Assert.AreEqual('lRight', lStatement.Values['selectorText'].Value, 'Expected nested selector.');
      end;
    end;

    Assert.IsTrue(lHasMultipleSelector, 'Expected multiple-selector with statement.');
    Assert.IsTrue(lHasNestedStatement, 'Expected nested with statement.');
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    Assert.AreEqual('4', lSummary.Values['withStatements'].Value, 'Expected summary with count.');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithDiscoveryTests.ScanCliReportsDiscoveryFixtureStatements;
var
  lExitCode: Cardinal;
  lOutput: string;
begin
  lOutput := RunDiscoveryFixture('--all', 'remove-with-discovery-cli.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected discovery CLI proof to succeed.');
  Assert.IsTrue(Pos('"withStatements":[', lOutput) > 0, 'Expected withStatements array in output.');
  Assert.IsTrue(Pos('"selectorText":"lLeft, lRight"', lOutput) > 0, 'Expected multiple selector in output.');
  Assert.IsTrue(Pos('"nestingDepth":1', lOutput) > 0, 'Expected nested with depth in output.');
end;

procedure TRemoveWithDiscoveryTests.ScanUnitTargetFiltersFilesAndWarnings;
var
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lRoot: TJSONObject;
  lFiles: TJSONArray;
  lStatements: TJSONArray;
  lUnitPath: string;
  lWarnings: TJSONArray;
begin
  lUnitPath := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithDiscoveryFixture\DiscoveryUnit.pas');
  lOutput := RunDiscoveryFixture('--unit ' + QuoteArg(lUnitPath), 'remove-with-discovery-unit.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected unit-target discovery scan to succeed.');

  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected unit-target discovery output to be JSON object.');
    lRoot := lJson as TJSONObject;
    AssertJsonArrayKey(lRoot, 'files', lFiles);
    Assert.AreEqual(1, lFiles.Count, 'Expected --unit to scan only the selected unit.');
    AssertJsonArrayKey(lRoot, 'withStatements', lStatements);
    Assert.AreEqual(4, lStatements.Count, 'Expected selected unit with statements only.');
    AssertJsonArrayKey(lRoot, 'warnings', lWarnings);
    Assert.AreEqual(0, lWarnings.Count, 'Expected unrelated missing-unit warning to be filtered for --unit.');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithDiscoveryTests.ScanDirTargetKeepsScopedWarnings;
var
  lDirPath: string;
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lRoot: TJSONObject;
  lWarnings: TJSONArray;
begin
  lDirPath := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithDiscoveryFixture');
  lOutput := RunDiscoveryFixture('--dir ' + QuoteArg(lDirPath), 'remove-with-discovery-dir.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected dir-target discovery scan to succeed.');

  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected dir-target discovery output to be JSON object.');
    lRoot := lJson as TJSONObject;
    AssertJsonArrayKey(lRoot, 'warnings', lWarnings);
    Assert.IsTrue(lWarnings.Count > 0, 'Expected missing project unit warning to stay visible for scoped --dir.');
  finally
    lJson.Free;
  end;
end;

end.
