unit Test.RemoveWith;

interface

uses
  System.IOUtils, System.JSON, System.SysUtils,
  DUnitX.TestFramework,
  Dak.RemoveWith.Symbols, Test.Support;

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

  [TestFixture]
  TRemoveWithRangeTests = class(TRemoveWithTestBase)
  private
    function RunRangeFixture(const aTargetArgs, aLogName: string; out aExitCode: Cardinal): string;
    function ReadSourceText(const aPath: string): string;
    function OffsetForLineColumn(const aSourceText: string; const aLine, aColumn: Integer): Integer;
    function ExtractRangeText(const aSourceText: string; const aRange: TJSONObject): string;
    function FindStatementContaining(const aStatements: TJSONArray; const aText: string): TJSONObject;
    function FindStatementAtLine(const aStatements: TJSONArray; const aLine: Integer): TJSONObject;
  public
    [Test]
    procedure ScanReportsExactSelectorBodyAndWholeWithRanges;
    [Test]
    procedure ScanKeepsUtf8BomLineOneColumnMapping;
  end;

  [TestFixture]
  TRemoveWithPrecedenceTests = class(TRemoveWithTestBase)
  private
    procedure CleanPrecedenceFixtureArtifacts(const aFixtureDir: string);
    function CommandExePath: string;
    function RunPrecedenceFixture(out aExitCode: Cardinal): string;
    function BuildExpectedPrecedenceOutput: string;
    function NormalizePrecedenceOutput(const aOutput: string): string;
  public
    [Test]
    procedure CompilerFixtureReportsExpectedWithLookupPrecedence;
  end;

  [TestFixture]
  TRemoveWithSymbolTests = class(TRemoveWithTestBase)
  private
    procedure BuildSymbolFixture(out aInventory: TRemoveWithSymbolInventory);
    function CountSymbols(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string): Integer;
    function DescribeSymbols(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string): string;
    function FindSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean;
    procedure AssertSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName, aTypeName: string);
  public
    [Test]
    procedure InventoryReportsRoutineScopesAndDeclarationLocations;
    [Test]
    procedure InventoryReportsUnitAndDirectTypeDeclarations;
    [Test]
    procedure InventoryReportsMissingSourceUnitsAsExternal;
  end;

implementation

uses
  Dak.Types;

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

function TRemoveWithRangeTests.RunRangeFixture(const aTargetArgs, aLogName: string; out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithRangeFixture\RemoveWithRangeFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' ' + aTargetArgs + ' --mode scan --format json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start remove-with range process.');
  Result := '';
  if FileExists(lLogPath) then
    Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

function TRemoveWithRangeTests.ReadSourceText(const aPath: string): string;
begin
  Result := TFile.ReadAllText(aPath, TEncoding.UTF8);
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

function TRemoveWithRangeTests.OffsetForLineColumn(const aSourceText: string; const aLine,
  aColumn: Integer): Integer;
var
  lIndex: Integer;
  lLine: Integer;
begin
  lLine := 1;
  lIndex := 1;
  while (lIndex <= Length(aSourceText)) and (lLine < aLine) do
  begin
    if aSourceText[lIndex] = #13 then
    begin
      Inc(lLine);
      if (lIndex < Length(aSourceText)) and (aSourceText[lIndex + 1] = #10) then
        Inc(lIndex);
    end else if aSourceText[lIndex] = #10 then
      Inc(lLine);
    Inc(lIndex);
  end;
  Result := lIndex + aColumn - 1;
end;

function TRemoveWithRangeTests.ExtractRangeText(const aSourceText: string; const aRange: TJSONObject): string;
var
  lEndOffset: Integer;
  lStartOffset: Integer;
begin
  lStartOffset := OffsetForLineColumn(aSourceText, aRange.GetValue<Integer>('startLine'),
    aRange.GetValue<Integer>('startColumn'));
  lEndOffset := OffsetForLineColumn(aSourceText, aRange.GetValue<Integer>('endLine'),
    aRange.GetValue<Integer>('endColumn'));
  Result := Copy(aSourceText, lStartOffset, lEndOffset - lStartOffset + 1);
end;

function TRemoveWithRangeTests.FindStatementContaining(const aStatements: TJSONArray; const aText: string): TJSONObject;
var
  i: Integer;
  lStatement: TJSONObject;
begin
  for i := 0 to aStatements.Count - 1 do
  begin
    Assert.IsTrue(aStatements.Items[i] is TJSONObject, 'Expected with statement item to be an object.');
    lStatement := aStatements.Items[i] as TJSONObject;
    if Pos(aText, lStatement.Values['selectorText'].Value) > 0 then
      Exit(lStatement);
  end;
  Assert.Fail('Expected with statement containing selector text: ' + aText);
  Result := nil;
end;

function TRemoveWithRangeTests.FindStatementAtLine(const aStatements: TJSONArray; const aLine: Integer): TJSONObject;
var
  i: Integer;
  lStatement: TJSONObject;
begin
  for i := 0 to aStatements.Count - 1 do
  begin
    Assert.IsTrue(aStatements.Items[i] is TJSONObject, 'Expected with statement item to be an object.');
    lStatement := aStatements.Items[i] as TJSONObject;
    if lStatement.GetValue<Integer>('line') = aLine then
      Exit(lStatement);
  end;
  Assert.Fail('Expected with statement at line: ' + aLine.ToString);
  Result := nil;
end;

procedure TRemoveWithRangeTests.ScanReportsExactSelectorBodyAndWholeWithRanges;
var
  lBodyRange: TJSONObject;
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lRange: TJSONObject;
  lRoot: TJSONObject;
  lSelectorRange: TJSONObject;
  lSourceText: string;
  lStatementWithComment: TJSONObject;
  lStatementWithIf: TJSONObject;
  lStatementWithLineComment: TJSONObject;
  lStatementWithDirective: TJSONObject;
  lStatement: TJSONObject;
  lStatements: TJSONArray;
begin
  lOutput := RunRangeFixture('--all', 'remove-with-ranges.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected range fixture scan to succeed.');

  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected range output to be JSON object.');
    lRoot := lJson as TJSONObject;
    AssertJsonArrayKey(lRoot, 'withStatements', lStatements);
    lStatement := FindStatementContaining(lStatements, 'lMatrix');

    AssertJsonObjectKey(lStatement, 'selectorRange', lSelectorRange);
    AssertJsonObjectKey(lStatement, 'bodyRange', lBodyRange);
    AssertJsonObjectKey(lStatement, 'range', lRange);
    Assert.AreEqual('2', lStatement.Values['selectorCount'].Value, 'Expected two top-level selectors.');

    lSourceText := ReadSourceText(lStatement.Values['file'].Value);
    Assert.AreEqual('lMatrix[lIndex, 0],' + #13#10 + '    lFactory.Make(''a,b'')',
      ExtractRangeText(lSourceText, lSelectorRange), 'Expected exact selector-list source span.');
    Assert.AreEqual('begin' + #13#10 + '    Name := ''comma,inside'';' + #13#10 + '    Save;' + #13#10 + '  end;',
      ExtractRangeText(lSourceText, lBodyRange), 'Expected exact compound body source span.');
    Assert.AreEqual('with lMatrix[lIndex, 0],' + #13#10 + '    lFactory.Make(''a,b'') do' + #13#10 +
      '  begin' + #13#10 + '    Name := ''comma,inside'';' + #13#10 + '    Save;' + #13#10 + '  end;',
      ExtractRangeText(lSourceText, lRange), 'Expected exact whole-with source span.');

    lStatementWithComment := FindStatementContaining(lStatements, 'selector comment');
    AssertJsonObjectKey(lStatementWithComment, 'selectorRange', lSelectorRange);
    AssertJsonObjectKey(lStatementWithComment, 'bodyRange', lBodyRange);
    AssertJsonObjectKey(lStatementWithComment, 'range', lRange);
    lSourceText := ReadSourceText(lStatementWithComment.Values['file'].Value);
    Assert.AreEqual('lLeft,' + #13#10 + '    {selector comment}' + #13#10 + '    lRight',
      ExtractRangeText(lSourceText, lSelectorRange), 'Expected selector range to preserve comments.');
    Assert.AreEqual('Save;', ExtractRangeText(lSourceText, lBodyRange),
      'Expected single-statement body range to include the semicolon.');
    Assert.AreEqual('with lLeft,' + #13#10 + '    {selector comment}' + #13#10 + '    lRight do' + #13#10 +
      '    Save;', ExtractRangeText(lSourceText, lRange), 'Expected whole-with range to include single body.');

    lStatementWithLineComment := FindStatementContaining(lStatements, 'selector line comment');
    AssertJsonObjectKey(lStatementWithLineComment, 'selectorRange', lSelectorRange);
    Assert.AreEqual('2', lStatementWithLineComment.Values['selectorCount'].Value,
      'Expected comma in line comment not to count as a selector.');
    Assert.AreEqual('lLeft, // selector line comment, with comma' + #13#10 + '    lRight',
      ExtractRangeText(lSourceText, lSelectorRange), 'Expected selector range to preserve line comments.');

    lStatementWithDirective := FindStatementContaining(lStatements, 'MSWINDOWS');
    AssertJsonObjectKey(lStatementWithDirective, 'selectorRange', lSelectorRange);
    lSourceText := ReadSourceText(lStatementWithDirective.Values['file'].Value);
    Assert.AreEqual('lLeft' + #13#10 + '    {$IFDEF MSWINDOWS}' + #13#10 + '    {$ENDIF}',
      ExtractRangeText(lSourceText, lSelectorRange), 'Expected selector range to preserve directives.');

    lStatementWithIf := FindStatementAtLine(lStatements, 72);
    AssertJsonObjectKey(lStatementWithIf, 'bodyRange', lBodyRange);
    AssertJsonObjectKey(lStatementWithIf, 'range', lRange);
    lSourceText := ReadSourceText(lStatementWithIf.Values['file'].Value);
    Assert.AreEqual('if lIndex = 0 then' + #13#10 + '    begin' + #13#10 + '      Name := ''if-body'';' +
      #13#10 + '      Save;' + #13#10 + '    end;', ExtractRangeText(lSourceText, lBodyRange),
      'Expected control-statement body range to include the nested block.');
    Assert.AreEqual('with lLeft do' + #13#10 + '    if lIndex = 0 then' + #13#10 + '    begin' + #13#10 +
      '      Name := ''if-body'';' + #13#10 + '      Save;' + #13#10 + '    end;',
      ExtractRangeText(lSourceText, lRange), 'Expected whole-with range to include the full control statement.');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithRangeTests.ScanKeepsUtf8BomLineOneColumnMapping;
var
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lRoot: TJSONObject;
  lSelectorRange: TJSONObject;
  lSourceText: string;
  lStatement: TJSONObject;
  lStatements: TJSONArray;
begin
  lOutput := RunRangeFixture('--all', 'remove-with-ranges-bom.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected range fixture scan to succeed.');

  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected range output to be JSON object.');
    lRoot := lJson as TJSONObject;
    AssertJsonArrayKey(lRoot, 'withStatements', lStatements);
    lStatement := FindStatementContaining(lStatements, 'lBom');
    AssertJsonObjectKey(lStatement, 'selectorRange', lSelectorRange);

    Assert.AreEqual('21', lStatement.Values['line'].Value, 'Expected BOM unit line numbers to ignore the BOM.');
    Assert.AreEqual('3', lStatement.Values['column'].Value, 'Expected BOM unit column numbers to ignore the BOM.');
    lSourceText := ReadSourceText(lStatement.Values['file'].Value);
    Assert.AreEqual('lBom', ExtractRangeText(lSourceText, lSelectorRange),
      'Expected selector extraction to ignore the UTF-8 BOM at file start.');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithPrecedenceTests.CleanPrecedenceFixtureArtifacts(const aFixtureDir: string);
var
  lPath: string;
begin
  for lPath in [
    TPath.Combine(aFixtureDir, 'PrecedenceMain.dcu'),
    TPath.Combine(aFixtureDir, 'RemoveWithPrecedenceFixture.res'),
    TPath.Combine(aFixtureDir, 'msbuild.log')
  ] do
  begin
    if TFile.Exists(lPath) then
      TFile.Delete(lPath);
  end;
end;

function TRemoveWithPrecedenceTests.CommandExePath: string;
begin
  Result := GetEnvironmentVariable('ComSpec');
  if Result = '' then
    Result := 'C:\Windows\System32\cmd.exe';
end;

function TRemoveWithPrecedenceTests.RunPrecedenceFixture(out aExitCode: Cardinal): string;
var
  lBuildArgs: string;
  lCmdArgs: string;
  lBuildExitCode: Cardinal;
  lBuildLogPath: string;
  lDprojPath: string;
  lExeFiles: TArray<string>;
  lExePath: string;
  lFixtureDir: string;
  lOutputDir: string;
  lRsVarsPath: string;
  lRunLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithPrecedenceFixture\RemoveWithPrecedenceFixture.dproj');
  lFixtureDir := ExtractFileDir(lDprojPath);
  CleanPrecedenceFixtureArtifacts(lFixtureDir);
  lOutputDir := TPath.Combine(TempRoot, 'remove-with-precedence-build');
  if TDirectory.Exists(lOutputDir) then
    TDirectory.Delete(lOutputDir, True);
  ForceDirectories(lOutputDir);

  try
    lBuildLogPath := TPath.Combine(TempRoot, 'remove-with-precedence-build.log');
    lRsVarsPath := 'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat';
    if not TFile.Exists(lRsVarsPath) then
      lRsVarsPath := TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
        'Embarcadero\Studio\23.0\bin\rsvars.bat');
    lBuildArgs := 'build --project ' + QuoteArg(lDprojPath) +
      ' --config Debug --platform Win32 --delphi 23.0 --rsvars ' + QuoteArg(lRsVarsPath) +
      ' --test-output-dir ' + QuoteArg(lOutputDir);
    lCmdArgs := '/C set "BDS=" & set "BDSLIB=" & set "DCC_UnitSearchPath=" & ' +
      'set "DelphiLibraryPath=" & set "EnvOptions=" & ' + QuoteArg(ResolverExePath) + ' ' + lBuildArgs;
    Assert.IsTrue(RunProcess(CommandExePath, lCmdArgs, RepoRoot, lBuildLogPath, lBuildExitCode),
      'Failed to start remove-with precedence build.');
    Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected precedence fixture to build. Log: ' + lBuildLogPath);

    lExeFiles := TDirectory.GetFiles(lOutputDir, 'RemoveWithPrecedenceFixture.exe', TSearchOption.soAllDirectories);
    Assert.AreEqual(1, Length(lExeFiles), 'Expected one built precedence fixture exe under: ' + lOutputDir);
    lExePath := lExeFiles[0];
    lRunLogPath := TPath.Combine(TempRoot, 'remove-with-precedence-output.txt');

    Assert.IsTrue(RunProcess(lExePath, '', ExtractFileDir(lExePath), lRunLogPath, aExitCode),
      'Failed to run remove-with precedence fixture.');
    Result := '';
    if FileExists(lRunLogPath) then
      Result := TFile.ReadAllText(lRunLogPath, TEncoding.UTF8);
  finally
    CleanPrecedenceFixtureArtifacts(lFixtureDir);
  end;
end;

function TRemoveWithPrecedenceTests.BuildExpectedPrecedenceOutput: string;
begin
  Result :=
    'selector-order=right' + #10 +
    'nested-inner=inner' + #10 +
    'nested-fallback=outer-only' + #10 +
    'selector-beats-local=receiver' + #10 +
    'local-fallback=local-only' + #10 +
    'selector-beats-param=receiver' + #10 +
    'param-fallback=param-only' + #10 +
    'selector-beats-current=receiver' + #10 +
    'current-fallback=current-only' + #10 +
    'selector-beats-global=receiver' + #10 +
    'global-fallback=global-only' + #10 +
    'inherited-member=ancestor' + #10 +
    'helper-member=helper' + #10 +
    'overload-int=receiver-int' + #10 +
    'overload-string=receiver-string' + #10;
end;

function TRemoveWithPrecedenceTests.NormalizePrecedenceOutput(const aOutput: string): string;
begin
  Result := StringReplace(aOutput, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

procedure TRemoveWithPrecedenceTests.CompilerFixtureReportsExpectedWithLookupPrecedence;
var
  lExitCode: Cardinal;
  lOutput: string;
begin
  lOutput := RunPrecedenceFixture(lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected precedence fixture executable to succeed.');

  Assert.AreEqual(BuildExpectedPrecedenceOutput, NormalizePrecedenceOutput(lOutput),
    'Expected exact compiler-observed with precedence output.');
end;

procedure TRemoveWithSymbolTests.BuildSymbolFixture(out aInventory: TRemoveWithSymbolInventory);
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithSymbolsFixture\RemoveWithSymbolsFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, aInventory, lError),
    'Expected symbol inventory build to succeed: ' + lError);
  Assert.IsTrue(Length(aInventory.fSymbols) > 0, 'Expected symbol inventory to contain fixture declarations.');
end;

function TRemoveWithSymbolTests.CountSymbols(const aInventory: TRemoveWithSymbolInventory; const aName: string;
  const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string): Integer;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := 0;
  for lSymbol in aInventory.fSymbols do
  begin
    if SameText(lSymbol.fName, aName) and (lSymbol.fKind = aKind) and
      ((aOwnerType = '') or SameText(lSymbol.fOwnerType, aOwnerType)) and
      ((aRoutineName = '') or SameText(lSymbol.fRoutineName, aRoutineName)) then
      Inc(Result);
  end;
end;

function TRemoveWithSymbolTests.DescribeSymbols(const aInventory: TRemoveWithSymbolInventory; const aName: string;
  const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string): string;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := '';
  for lSymbol in aInventory.fSymbols do
  begin
    if SameText(lSymbol.fName, aName) and (lSymbol.fKind = aKind) and
      ((aOwnerType = '') or SameText(lSymbol.fOwnerType, aOwnerType)) and
      ((aRoutineName = '') or SameText(lSymbol.fRoutineName, aRoutineName)) then
      Result := Result + Format('%s:%d:%d owner=%s routine=%s type=%s; ', [lSymbol.fFilePath, lSymbol.fLine,
        lSymbol.fColumn, lSymbol.fOwnerType, lSymbol.fRoutineName, lSymbol.fTypeName]);
  end;
end;

function TRemoveWithSymbolTests.FindSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
  const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string;
  out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  for lSymbol in aInventory.fSymbols do
  begin
    if SameText(lSymbol.fName, aName) and (lSymbol.fKind = aKind) and
      ((aOwnerType = '') or SameText(lSymbol.fOwnerType, aOwnerType)) and
      ((aRoutineName = '') or SameText(lSymbol.fRoutineName, aRoutineName)) then
    begin
      aSymbol := lSymbol;
      Exit(True);
    end;
  end;
end;

procedure TRemoveWithSymbolTests.AssertSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
  const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName, aTypeName: string);
var
  lLines: TArray<string>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Assert.IsTrue(FindSymbol(aInventory, aName, aKind, aOwnerType, aRoutineName, lSymbol),
    'Expected ' + RemoveWithSymbolKindToText(aKind) + ' symbol: ' + aName);
  if aTypeName <> '' then
    Assert.AreEqual(aTypeName, lSymbol.fTypeName, 'Unexpected type for symbol: ' + aName);
  Assert.AreNotEqual(0, lSymbol.fLine, 'Expected declaration line for symbol: ' + aName);
  Assert.AreNotEqual(0, lSymbol.fColumn, 'Expected declaration column for symbol: ' + aName);
  if TFile.Exists(lSymbol.fFilePath) then
  begin
    lLines := TFile.ReadAllLines(lSymbol.fFilePath, TEncoding.UTF8);
    Assert.IsTrue((lSymbol.fLine <= Length(lLines)) and (Pos(aName, lLines[lSymbol.fLine - 1]) > 0),
      'Expected declaration line to contain symbol name: ' + aName);
  end;
  Assert.IsTrue(SameText('SymbolUnit', lSymbol.fUnitName) or (aKind = TRemoveWithSymbolKind.rwskExternal),
    'Expected fixture unit for symbol: ' + aName);
end;

procedure TRemoveWithSymbolTests.InventoryReportsRoutineScopesAndDeclarationLocations;
var
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildSymbolFixture(lInventory);

  AssertSymbol(lInventory, 'aParamName', TRemoveWithSymbolKind.rwskParameter, '', 'TSymbolClass.Touch', 'string');
  AssertSymbol(lInventory, 'aCount', TRemoveWithSymbolKind.rwskParameter, '', 'TSymbolClass.Touch', 'Integer');
  AssertSymbol(lInventory, 'aExternal', TRemoveWithSymbolKind.rwskParameter, '', 'TSymbolClass.Touch',
    'TStringList');
  Assert.AreEqual(1, CountSymbols(lInventory, 'aParamName', TRemoveWithSymbolKind.rwskParameter, '',
    'TSymbolClass.Touch'), 'Expected only implementation-scope parameter rows for TSymbolClass.Touch: ' +
    DescribeSymbols(lInventory, 'aParamName', TRemoveWithSymbolKind.rwskParameter, '', 'TSymbolClass.Touch'));
  AssertSymbol(lInventory, 'lLocalName', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TSymbolClass.Touch', 'string');
  AssertSymbol(lInventory, 'lLocalRecord', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TSymbolClass.Touch',
    'TSymbolRecord');
  AssertSymbol(lInventory, 'lSecondRecord', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TSymbolClass.Touch',
    'TSymbolRecord');
  AssertSymbol(lInventory, 'lExternalList', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TSymbolClass.Touch',
    'TStringList');
  AssertSymbol(lInventory, 'FClassField', TRemoveWithSymbolKind.rwskCurrentClassMember, 'TSymbolClass',
    'TSymbolClass.Touch', 'string');
  AssertSymbol(lInventory, 'ClassProp', TRemoveWithSymbolKind.rwskCurrentClassMember, 'TSymbolClass',
    'TSymbolClass.Touch', 'string');
  AssertSymbol(lInventory, 'Touch', TRemoveWithSymbolKind.rwskCurrentClassMember, 'TSymbolClass',
    'TSymbolClass.Touch', '');
end;

procedure TRemoveWithSymbolTests.InventoryReportsUnitAndDirectTypeDeclarations;
var
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildSymbolFixture(lInventory);

  AssertSymbol(lInventory, 'UnitGlobal', TRemoveWithSymbolKind.rwskUnitGlobal, '', '', 'TSymbolRecord');
  AssertSymbol(lInventory, 'ExternalGlobal', TRemoveWithSymbolKind.rwskUnitGlobal, '', '', 'TStringList');
  AssertSymbol(lInventory, 'ImplGlobal', TRemoveWithSymbolKind.rwskUnitGlobal, '', '', 'Integer');
  AssertSymbol(lInventory, 'UnitConst', TRemoveWithSymbolKind.rwskConstant, '', '', '');
  AssertSymbol(lInventory, 'ImplConst', TRemoveWithSymbolKind.rwskConstant, '', '', 'string');
  AssertSymbol(lInventory, 'RecordField', TRemoveWithSymbolKind.rwskField, 'TSymbolRecord', '', 'string');
  AssertSymbol(lInventory, 'RecordProp', TRemoveWithSymbolKind.rwskProperty, 'TSymbolRecord', '', 'string');
  AssertSymbol(lInventory, 'RecordMethod', TRemoveWithSymbolKind.rwskMethod, 'TSymbolRecord', '', '');
  AssertSymbol(lInventory, 'FClassField', TRemoveWithSymbolKind.rwskField, 'TSymbolClass', '', 'string');
  AssertSymbol(lInventory, 'SharedValue', TRemoveWithSymbolKind.rwskClassVar, 'TSymbolClass', '', 'Integer');
  AssertSymbol(lInventory, 'ClassConst', TRemoveWithSymbolKind.rwskConstant, 'TSymbolClass', '', '');
  AssertSymbol(lInventory, 'Touch', TRemoveWithSymbolKind.rwskMethod, 'TSymbolClass', '', '');
  AssertSymbol(lInventory, 'Run', TRemoveWithSymbolKind.rwskMethod, 'TSymbolClass', '', '');
  AssertSymbol(lInventory, 'ClassProp', TRemoveWithSymbolKind.rwskProperty, 'TSymbolClass', '', 'string');
end;

procedure TRemoveWithSymbolTests.InventoryReportsMissingSourceUnitsAsExternal;
var
  lInventory: TRemoveWithSymbolInventory;
  lSymbol: TRemoveWithSymbolInfo;
begin
  BuildSymbolFixture(lInventory);

  Assert.IsTrue(FindSymbol(lInventory, 'MissingSymbolUnit', TRemoveWithSymbolKind.rwskExternal, '', '', lSymbol),
    'Expected missing unit to be reported as external.');
  Assert.AreEqual('', lSymbol.fUnitName, 'External missing source should not be assigned to a parsed unit.');
  Assert.IsTrue(FindSymbol(lInventory, 'TStringList', TRemoveWithSymbolKind.rwskExternal, '', '', lSymbol),
    'Expected source-unavailable library type to be reported as external.');
  Assert.AreEqual('', lSymbol.fUnitName, 'External library type should not be assigned to a parsed unit.');
end;

end.
