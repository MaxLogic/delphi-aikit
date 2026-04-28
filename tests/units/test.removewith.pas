unit Test.RemoveWith;

interface

uses
  System.IOUtils, System.JSON, System.SysUtils,
  DUnitX.TestFramework,
  Dak.RemoveWith.Discovery, Dak.RemoveWith.Expressions, Dak.RemoveWith.Resolver, Dak.RemoveWith.Symbols,
  Dak.RemoveWith.TempPolicy, Test.Support;

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

  [TestFixture]
  TRemoveWithExpressionTypeTests = class(TRemoveWithTestBase)
  private
    procedure BuildExpressionFixture(out aInventory: TRemoveWithSymbolInventory);
    procedure AssertSelector(const aInventory: TRemoveWithSymbolInventory; const aSelectorText: string;
      const aStatus: TRemoveWithSelectorTypeStatus; const aTypeName, aReason: string;
      const aAddressable: Boolean);
  public
    [Test]
    procedure ResolvesSupportedSelectorShapes;
    [Test]
    procedure ClassifiesUnsupportedAndExternalSelectors;
  end;

  [TestFixture]
  TRemoveWithSourceModelGoldenTests = class(TRemoveWithTestBase)
  private
    procedure BuildSourceModelFixture(out aInventory: TRemoveWithSymbolInventory);
    function DescribeSymbols(const aInventory: TRemoveWithSymbolInventory): string;
    function FindSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean;
    procedure AssertSelector(const aInventory: TRemoveWithSymbolInventory; const aSelectorText,
      aTypeName: string);
    procedure AssertSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName, aTypeName, aLineText: string);
  public
    [Test]
    procedure RecordsAndClassesExposeExpectedSourceModel;
    [Test]
    procedure SelectorShapesResolveThroughSourceModel;
  end;

  [TestFixture]
  TRemoveWithAncestorTests = class(TRemoveWithTestBase)
  private
    procedure BuildAncestorHelperFixture(out aInventory: TRemoveWithSymbolInventory);
    function FindSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean;
    procedure AssertSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType, aTypeName: string);
  public
    [Test]
    procedure InventoryReportsSourceAvailableAncestorMembers;
    [Test]
    procedure InventoryReportsExternalAncestorWithoutGuessing;
  end;

  [TestFixture]
  TRemoveWithHelperTests = class(TRemoveWithTestBase)
  private
    procedure BuildAncestorHelperFixture(out aInventory: TRemoveWithSymbolInventory);
    function FindSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean;
    procedure AssertSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType, aTypeName: string);
  public
    [Test]
    procedure InventoryReportsSourceAvailableHelperMembers;
    [Test]
    procedure InventoryReportsUnsupportedAndExternalHelperCases;
  end;

  [TestFixture]
  TRemoveWithResolverTests = class(TRemoveWithTestBase)
  private
    procedure BuildResolverFixture(out aInventory: TRemoveWithSymbolInventory;
      out aScanResult: TRemoveWithScanResult);
    function CommandExePath: string;
    function FindClassification(const aResult: TRemoveWithResolverResult; const aStatementId,
      aIdentifier: string; const aStatus: TRemoveWithIdentifierStatus;
      out aClassification: TRemoveWithIdentifierClassification): Boolean;
    function RunResolverFixtureCli(out aExitCode: Cardinal): string;
    procedure AssertClassification(const aResult: TRemoveWithResolverResult; const aStatementId,
      aIdentifier: string; const aStatus: TRemoveWithIdentifierStatus; const aReceiverText,
      aReason: string);
  public
    [Test]
    procedure ResolvesSingleMultipleAndNestedWithScopeStack;
    [Test]
    procedure ReportsExternalUnsupportedUnresolvedAndAmbiguousCases;
    [Test]
    procedure PlanCliEmitsResolverOnlyClassifications;
  end;

  [TestFixture]
  TRemoveWithInheritedOverrideGoldenTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    function RunInheritedOverrideFixture(out aExitCode: Cardinal): string;
    procedure AssertJsonClassification(const aClassifications: TJSONArray; const aStatementId,
      aIdentifier, aStatus, aResolutionKind, aSourceOwnerType: string);
  public
    [Test]
    procedure PlanReportDistinguishesInheritedOverrideHiddenAndExternalMembers;
  end;

  [TestFixture]
  TRemoveWithInterfaceResolverTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    function RunInterfaceFixture(out aExitCode: Cardinal): string;
    procedure AssertJsonClassification(const aClassifications: TJSONArray; const aStatementId,
      aIdentifier, aStatus, aResolutionKind, aSourceOwnerType: string);
  public
    [Test]
    procedure PlanReportUsesDeclaredInterfaceContract;
  end;

  [TestFixture]
  TRemoveWithHelperPrecedenceGoldenTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    function RunHelperPrecedenceFixture(out aExitCode: Cardinal): string;
    procedure AssertJsonClassification(const aClassifications: TJSONArray; const aStatementId,
      aIdentifier, aStatus, aResolutionKind, aSourceOwnerType: string);
  public
    [Test]
    procedure PlanReportDistinguishesDirectHelperAmbiguousAndExternalHelpers;
  end;

  [TestFixture]
  TRemoveWithGlobalScopeGoldenTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    function RunGlobalScopeFixture(out aExitCode: Cardinal): string;
    procedure AssertJsonClassification(const aClassifications: TJSONArray; const aStatementId,
      aIdentifier, aStatus, aResolutionKind, aMemberKind: string);
  public
    [Test]
    procedure PlanReportDistinguishesWithReceiversAndOuterScopes;
  end;

  [TestFixture]
  TRemoveWithIndexedPropertyTests = class(TRemoveWithTestBase)
  private
    procedure BuildIndexedPropertyFixture(out aInventory: TRemoveWithSymbolInventory);
    function CommandExePath: string;
    function FindSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
    function RunIndexedPropertyFixture(out aExitCode: Cardinal): string;
    procedure AssertResolvedName(const aClassifications: TJSONArray; const aStatementId, aReceiverText,
      aReceiverType: string);
    procedure AssertUnsupportedName(const aClassifications: TJSONArray; const aStatementId, aReceiverText,
      aReason: string);
  public
    [Test]
    procedure SymbolInventoryParsesIndexedAndDefaultProperties;
    [Test]
    procedure PlanReportDistinguishesIndexedVariablesAndUnsafeIndexedProperties;
  end;

  [TestFixture]
  TRemoveWithTempPolicyTests = class(TRemoveWithTestBase)
  private
    procedure BuildTempPolicyFixture(out aInventory: TRemoveWithSymbolInventory);
    procedure AssertPolicy(const aInventory: TRemoveWithSymbolInventory; const aSelectorText: string;
      const aStrategy: TRemoveWithTempStrategy; const aReceiverType, aQualifierText, aReason: string);
  public
    [Test]
    procedure ChoosesDirectReferenceRecordPointerAndSkipStrategies;
    [Test]
    procedure GeneratesCollisionFreeTempDeclarations;
    [Test]
    procedure ReservesGeneratedNamesAcrossSequentialPlans;
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
    Assert.IsFalse(Assigned(lRoot.Values['plannedEdits']), 'Resolver-only plan report should not include edits yet.');
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

procedure TRemoveWithExpressionTypeTests.BuildExpressionFixture(out aInventory: TRemoveWithSymbolInventory);
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithExpressionFixture\RemoveWithExpressionFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, aInventory, lError),
    'Expected expression fixture inventory build to succeed: ' + lError);
end;

procedure TRemoveWithExpressionTypeTests.AssertSelector(const aInventory: TRemoveWithSymbolInventory;
  const aSelectorText: string; const aStatus: TRemoveWithSelectorTypeStatus; const aTypeName, aReason: string;
  const aAddressable: Boolean);
var
  lInfo: TRemoveWithSelectorTypeInfo;
begin
  Assert.IsTrue(ResolveRemoveWithSelectorType(aInventory, 'TExpressionScope.Run', aSelectorText, lInfo),
    'Expected selector resolver to handle: ' + aSelectorText);
  Assert.AreEqual(RemoveWithSelectorTypeStatusToText(aStatus), RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Unexpected selector status for: ' + aSelectorText);
  Assert.AreEqual(aTypeName, lInfo.fTypeName, 'Unexpected selector type for: ' + aSelectorText);
  Assert.AreEqual(aReason, lInfo.fReason, 'Unexpected selector reason for: ' + aSelectorText);
  Assert.AreEqual(aAddressable, lInfo.fAddressable, 'Unexpected addressability for: ' + aSelectorText);
end;

procedure TRemoveWithExpressionTypeTests.ResolvesSupportedSelectorShapes;
var
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildExpressionFixture(lInventory);

  AssertSelector(lInventory, 'lLocalRecord', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '',
    True);
  AssertSelector(lInventory, 'aParamRecord', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '',
    True);
  AssertSelector(lInventory, 'FRecord', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '', True);
  AssertSelector(lInventory, 'Self.FRecord', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '',
    True);
  AssertSelector(lInventory, 'lAliasPtr^', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '',
    True);
  AssertSelector(lInventory, 'lRecordPtr^', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '',
    True);
  AssertSelector(lInventory, 'lRecords[0]', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '',
    True);
  AssertSelector(lInventory, 'lLocalRecord.Child', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionChild',
    '', True);
  AssertSelector(lInventory, 'lLocalRecord.Child.Name', TRemoveWithSelectorTypeStatus.rwstsResolved, 'string', '',
    True);
end;

procedure TRemoveWithExpressionTypeTests.ClassifiesUnsupportedAndExternalSelectors;
var
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildExpressionFixture(lInventory);

  AssertSelector(lInventory, 'ClassProp', TRemoveWithSelectorTypeStatus.rwstsUnsupported, '', 'property-selector',
    False);
  AssertSelector(lInventory, 'MakeRecord()', TRemoveWithSelectorTypeStatus.rwstsUnsupported, '', 'call-selector',
    False);
  AssertSelector(lInventory, 'TExpressionRecord(lLocalRecord)', TRemoveWithSelectorTypeStatus.rwstsUnsupported, '',
    'cast-selector', False);
  AssertSelector(lInventory, 'lExternalList', TRemoveWithSelectorTypeStatus.rwstsExternal, 'TStringList',
    'type-source-not-indexed', False);
  AssertSelector(lInventory, 'lExternalList.ClassName', TRemoveWithSelectorTypeStatus.rwstsExternal, 'TStringList',
    'type-source-not-indexed', False);
  AssertSelector(lInventory, 'OtherRecord', TRemoveWithSelectorTypeStatus.rwstsUnresolved, '', 'symbol-not-found',
    False);
  AssertSelector(lInventory, 'lOtherOnly', TRemoveWithSelectorTypeStatus.rwstsUnresolved, '', 'symbol-not-found',
    False);
end;

procedure TRemoveWithSourceModelGoldenTests.BuildSourceModelFixture(out aInventory: TRemoveWithSymbolInventory);
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithSourceModelGoldenFixture\RemoveWithSourceModelGoldenFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, aInventory, lError),
    'Expected source-model golden fixture inventory build to succeed: ' + lError);
end;

function TRemoveWithSourceModelGoldenTests.FindSymbol(const aInventory: TRemoveWithSymbolInventory;
  const aName: string; const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string;
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

function TRemoveWithSourceModelGoldenTests.DescribeSymbols(const aInventory: TRemoveWithSymbolInventory): string;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := '';
  for lSymbol in aInventory.fSymbols do
    Result := Result + Format('%s:%s:%s:%s; ', [lSymbol.fName, RemoveWithSymbolKindToText(lSymbol.fKind),
      lSymbol.fOwnerType, lSymbol.fTypeName]);
end;

procedure TRemoveWithSourceModelGoldenTests.AssertSelector(const aInventory: TRemoveWithSymbolInventory;
  const aSelectorText, aTypeName: string);
var
  lInfo: TRemoveWithSelectorTypeInfo;
begin
  Assert.IsTrue(ResolveRemoveWithSelectorType(aInventory, 'TGoldenScope.Run', aSelectorText, lInfo),
    'Expected selector resolver to handle: ' + aSelectorText);
  Assert.AreEqual(RemoveWithSelectorTypeStatusToText(TRemoveWithSelectorTypeStatus.rwstsResolved),
    RemoveWithSelectorTypeStatusToText(lInfo.fStatus), 'Unexpected selector status for: ' + aSelectorText);
  Assert.AreEqual(aTypeName, lInfo.fTypeName, 'Unexpected selector type for: ' + aSelectorText);
  Assert.IsTrue(lInfo.fAddressable, 'Expected source-model selector to be addressable: ' + aSelectorText);
end;

procedure TRemoveWithSourceModelGoldenTests.AssertSymbol(const aInventory: TRemoveWithSymbolInventory;
  const aName: string; const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName, aTypeName,
  aLineText: string);
var
  lLines: TArray<string>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Assert.IsTrue(FindSymbol(aInventory, aName, aKind, aOwnerType, aRoutineName, lSymbol),
    'Expected ' + RemoveWithSymbolKindToText(aKind) + ' symbol: ' + aName + ' inventory=' +
    DescribeSymbols(aInventory));
  if aTypeName <> '' then
    Assert.AreEqual(aTypeName, lSymbol.fTypeName, 'Unexpected type for symbol: ' + aName);
  Assert.AreNotEqual(0, lSymbol.fLine, 'Expected declaration line for symbol: ' + aName);
  Assert.AreNotEqual(0, lSymbol.fColumn, 'Expected declaration column for symbol: ' + aName);
  Assert.IsTrue(TFile.Exists(lSymbol.fFilePath), 'Expected symbol file to exist: ' + aName);
  lLines := TFile.ReadAllLines(lSymbol.fFilePath, TEncoding.UTF8);
  Assert.IsTrue(lSymbol.fLine <= Length(lLines), 'Expected declaration line inside file for symbol: ' + aName);
  Assert.IsTrue(Pos(aLineText, lLines[lSymbol.fLine - 1]) > 0,
    'Expected declaration line text for symbol: ' + aName);
end;

procedure TRemoveWithSourceModelGoldenTests.RecordsAndClassesExposeExpectedSourceModel;
var
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildSourceModelFixture(lInventory);

  AssertSymbol(lInventory, 'TGoldenChild', TRemoveWithSymbolKind.rwskTypeMember, '', '', '', 'TGoldenChild = record');
  AssertSymbol(lInventory, 'TGoldenRecord', TRemoveWithSymbolKind.rwskTypeMember, '', '', '', 'TGoldenRecord = record');
  AssertSymbol(lInventory, 'RecordName', TRemoveWithSymbolKind.rwskField, 'TGoldenRecord', '', 'string',
    'RecordName: string;');
  AssertSymbol(lInventory, 'Child', TRemoveWithSymbolKind.rwskField, 'TGoldenRecord', '', 'TGoldenChild',
    'Child: TGoldenChild;');
  AssertSymbol(lInventory, 'RecordTitle', TRemoveWithSymbolKind.rwskProperty, 'TGoldenRecord', '', 'string',
    'property RecordTitle: string read RecordName write RecordName;');
  AssertSymbol(lInventory, 'Touch', TRemoveWithSymbolKind.rwskMethod, 'TGoldenRecord', '', '', 'procedure Touch;');
  AssertSymbol(lInventory, 'Name', TRemoveWithSymbolKind.rwskField, 'TGoldenChild', '', 'string', 'Name: string;');
  AssertSymbol(lInventory, 'ClassLimit', TRemoveWithSymbolKind.rwskConstant, 'TGoldenClass', '', 'Integer',
    'ClassLimit: Integer = 7;');
  AssertSymbol(lInventory, 'SharedCount', TRemoveWithSymbolKind.rwskClassVar, 'TGoldenClass', '', 'Integer',
    'SharedCount: Integer;');
  AssertSymbol(lInventory, 'FClassRecord', TRemoveWithSymbolKind.rwskField, 'TGoldenClass', '', 'TGoldenRecord',
    'FClassRecord: TGoldenRecord;');
  AssertSymbol(lInventory, 'ClassRecord', TRemoveWithSymbolKind.rwskProperty, 'TGoldenClass', '', 'TGoldenRecord',
    'property ClassRecord: TGoldenRecord read FClassRecord write FClassRecord;');
  AssertSymbol(lInventory, 'Touch', TRemoveWithSymbolKind.rwskMethod, 'TGoldenClass', '', '', 'procedure Touch;');
  AssertSymbol(lInventory, 'Run', TRemoveWithSymbolKind.rwskMethod, 'TGoldenScope', '', '', 'class procedure Run;');
end;

procedure TRemoveWithSourceModelGoldenTests.SelectorShapesResolveThroughSourceModel;
var
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildSourceModelFixture(lInventory);

  AssertSymbol(lInventory, 'lObject', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'TGoldenClass', 'lObject: TGoldenClass;');
  AssertSymbol(lInventory, 'lRecord', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'TGoldenRecord', 'lRecord: TGoldenRecord;');
  AssertSymbol(lInventory, 'lRecordPtr', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'PGoldenRecord', 'lRecordPtr: PGoldenRecord;');
  AssertSymbol(lInventory, 'lRecords', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'TArray<TGoldenRecord>', 'lRecords: TArray<TGoldenRecord>;');

  AssertSelector(lInventory, 'lRecord', 'TGoldenRecord');
  AssertSelector(lInventory, 'lObject', 'TGoldenClass');
  AssertSelector(lInventory, 'lRecordPtr^', 'TGoldenRecord');
  AssertSelector(lInventory, 'lRecords[0]', 'TGoldenRecord');
  AssertSelector(lInventory, 'lRecord.Child', 'TGoldenChild');
  AssertSelector(lInventory, 'lRecord.Child.Name', 'string');
  AssertSelector(lInventory, 'lObject.FClassRecord.Child', 'TGoldenChild');
end;

procedure TRemoveWithAncestorTests.BuildAncestorHelperFixture(out aInventory: TRemoveWithSymbolInventory);
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithHelpersFixture\RemoveWithHelpersFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, aInventory, lError),
    'Expected ancestor/helper fixture inventory build to succeed: ' + lError);
end;

function TRemoveWithAncestorTests.FindSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
  const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType: string;
  out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  for lSymbol in aInventory.fSymbols do
  begin
    if SameText(lSymbol.fName, aName) and (lSymbol.fKind = aKind) and
      SameText(lSymbol.fOwnerType, aOwnerType) and SameText(lSymbol.fSourceOwnerType, aSourceOwnerType) then
    begin
      aSymbol := lSymbol;
      Exit(True);
    end;
  end;
end;

procedure TRemoveWithAncestorTests.AssertSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
  const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType, aTypeName: string);
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Assert.IsTrue(FindSymbol(aInventory, aName, aKind, aOwnerType, aSourceOwnerType, lSymbol),
    'Expected ' + RemoveWithSymbolKindToText(aKind) + ' symbol: ' + aName);
  if aTypeName <> '' then
    Assert.AreEqual(aTypeName, lSymbol.fTypeName, 'Unexpected type for symbol: ' + aName);
end;

procedure TRemoveWithAncestorTests.InventoryReportsSourceAvailableAncestorMembers;
var
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildAncestorHelperFixture(lInventory);

  AssertSymbol(lInventory, 'BaseName', TRemoveWithSymbolKind.rwskProperty, 'TDerivedWithClass', 'TBaseWithClass',
    'string');
  AssertSymbol(lInventory, 'BaseName', TRemoveWithSymbolKind.rwskCurrentClassMember, 'TDerivedWithClass',
    'TBaseWithClass', 'string');
  AssertSymbol(lInventory, 'BaseTouch', TRemoveWithSymbolKind.rwskMethod, 'TDerivedWithClass', 'TBaseWithClass', '');
  AssertSymbol(lInventory, 'BaseCount', TRemoveWithSymbolKind.rwskClassVar, 'TDerivedWithClass', 'TBaseWithClass',
    'Integer');
  AssertSymbol(lInventory, 'BaseLimit', TRemoveWithSymbolKind.rwskConstant, 'TDerivedWithClass', 'TBaseWithClass',
    'Integer');
  AssertSymbol(lInventory, 'BaseName', TRemoveWithSymbolKind.rwskProperty, 'TGrandDerivedWithClass',
    'TBaseWithClass', 'string');
  AssertSymbol(lInventory, 'DerivedName', TRemoveWithSymbolKind.rwskProperty, 'TGrandDerivedWithClass',
    'TDerivedWithClass', 'string');
end;

procedure TRemoveWithAncestorTests.InventoryReportsExternalAncestorWithoutGuessing;
var
  lInventory: TRemoveWithSymbolInventory;
  lSymbol: TRemoveWithSymbolInfo;
begin
  BuildAncestorHelperFixture(lInventory);

  Assert.IsFalse(FindSymbol(lInventory, 'Count', TRemoveWithSymbolKind.rwskProperty, 'TExternalDerivedList',
    'TStringList', lSymbol), 'Expected external ancestor members to stay unresolved.');
  Assert.IsTrue(FindSymbol(lInventory, 'TStringList', TRemoveWithSymbolKind.rwskExternal, '', '', lSymbol),
    'Expected source-unavailable ancestor type to be reported as external.');
end;

procedure TRemoveWithHelperTests.BuildAncestorHelperFixture(out aInventory: TRemoveWithSymbolInventory);
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithHelpersFixture\RemoveWithHelpersFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, aInventory, lError),
    'Expected ancestor/helper fixture inventory build to succeed: ' + lError);
end;

function TRemoveWithHelperTests.FindSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
  const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType: string;
  out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  for lSymbol in aInventory.fSymbols do
  begin
    if SameText(lSymbol.fName, aName) and (lSymbol.fKind = aKind) and
      SameText(lSymbol.fOwnerType, aOwnerType) and SameText(lSymbol.fSourceOwnerType, aSourceOwnerType) then
    begin
      aSymbol := lSymbol;
      Exit(True);
    end;
  end;
end;

procedure TRemoveWithHelperTests.AssertSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
  const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType, aTypeName: string);
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Assert.IsTrue(FindSymbol(aInventory, aName, aKind, aOwnerType, aSourceOwnerType, lSymbol),
    'Expected ' + RemoveWithSymbolKindToText(aKind) + ' symbol: ' + aName);
  if aTypeName <> '' then
    Assert.AreEqual(aTypeName, lSymbol.fTypeName, 'Unexpected type for symbol: ' + aName);
end;

procedure TRemoveWithHelperTests.InventoryReportsSourceAvailableHelperMembers;
var
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildAncestorHelperFixture(lInventory);

  AssertSymbol(lInventory, 'Normalize', TRemoveWithSymbolKind.rwskMethod, 'THelperRecordTarget',
    'THelperRecordTargetHelper', '');
  AssertSymbol(lInventory, 'HelperValue', TRemoveWithSymbolKind.rwskProperty, 'THelperRecordTarget',
    'THelperRecordTargetHelper', 'string');
  AssertSymbol(lInventory, 'ClearData', TRemoveWithSymbolKind.rwskMethod, 'THelperClassTarget',
    'THelperClassTargetHelper', '');
  AssertSymbol(lInventory, 'HelperData', TRemoveWithSymbolKind.rwskProperty, 'THelperClassTarget',
    'THelperClassTargetHelper', 'string');
end;

procedure TRemoveWithHelperTests.InventoryReportsUnsupportedAndExternalHelperCases;
var
  lInventory: TRemoveWithSymbolInventory;
  lSymbol: TRemoveWithSymbolInfo;
begin
  BuildAncestorHelperFixture(lInventory);

  Assert.IsTrue(FindSymbol(lInventory, 'TInheritedClassTargetHelper', TRemoveWithSymbolKind.rwskTypeMember, '',
    '', lSymbol), 'Expected unsupported helper type to be inventoried.');
  Assert.IsTrue(lSymbol.fIsHelper, 'Expected unsupported helper shape to be reported as a helper.');
  Assert.AreEqual('', lSymbol.fRelatedTypeName, 'Unsupported inherited helper target should not be guessed.');
  Assert.IsFalse(FindSymbol(lInventory, 'UnsupportedInheritedHelper', TRemoveWithSymbolKind.rwskMethod,
    'THelperClassTarget', 'TInheritedClassTargetHelper', lSymbol),
    'Expected unsupported helper members not to be materialized onto the target.');

  AssertSymbol(lInventory, 'ExternalTargetHelper', TRemoveWithSymbolKind.rwskMethod, 'TStringList',
    'TStringListVisibleHelper', '');
  Assert.IsTrue(FindSymbol(lInventory, 'TStringList', TRemoveWithSymbolKind.rwskExternal, '', '', lSymbol),
    'Expected external helper target to be reported as external.');
end;

procedure TRemoveWithResolverTests.BuildResolverFixture(out aInventory: TRemoveWithSymbolInventory;
  out aScanResult: TRemoveWithScanResult);
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithResolverFixture\RemoveWithResolverFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lOptions.fRemoveWithAll := True;

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, aInventory, lError),
    'Expected resolver fixture inventory build to succeed: ' + lError);
  Assert.IsTrue(DiscoverRemoveWithStatements(lOptions, lOptions.fDprojPath, aScanResult, lError),
    'Expected resolver fixture discovery to succeed: ' + lError);
end;

function TRemoveWithResolverTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

function TRemoveWithResolverTests.FindClassification(const aResult: TRemoveWithResolverResult;
  const aStatementId, aIdentifier: string; const aStatus: TRemoveWithIdentifierStatus;
  out aClassification: TRemoveWithIdentifierClassification): Boolean;
var
  lClassification: TRemoveWithIdentifierClassification;
begin
  Result := False;
  aClassification := Default(TRemoveWithIdentifierClassification);
  for lClassification in aResult.fClassifications do
  begin
    if SameText(lClassification.fStatementId, aStatementId) and SameText(lClassification.fIdentifier, aIdentifier)
      and (lClassification.fStatus = aStatus) then
    begin
      aClassification := lClassification;
      Exit(True);
    end;
  end;
end;

function TRemoveWithResolverTests.RunResolverFixtureCli(out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithResolverFixture\RemoveWithResolverFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-resolver-plan.json');
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode plan --format json';

  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath,
    aExitCode), 'Failed to start remove-with resolver process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithResolverTests.AssertClassification(const aResult: TRemoveWithResolverResult;
  const aStatementId, aIdentifier: string; const aStatus: TRemoveWithIdentifierStatus;
  const aReceiverText, aReason: string);
var
  lClassification: TRemoveWithIdentifierClassification;
begin
  Assert.IsTrue(FindClassification(aResult, aStatementId, aIdentifier, aStatus, lClassification),
    'Expected resolver classification ' + aStatementId + ':' + aIdentifier + ':' +
    RemoveWithIdentifierStatusToText(aStatus));
  Assert.AreEqual(aReceiverText, lClassification.fReceiverText, 'Unexpected receiver for ' + aIdentifier);
  Assert.AreEqual(aReason, lClassification.fReason, 'Unexpected reason for ' + aIdentifier);
  Assert.AreNotEqual(0, lClassification.fLine, 'Expected source line for ' + aIdentifier);
  Assert.AreNotEqual(0, lClassification.fColumn, 'Expected source column for ' + aIdentifier);
end;

procedure TRemoveWithResolverTests.ResolvesSingleMultipleAndNestedWithScopeStack;
var
  lError: string;
  lInfo: TRemoveWithSelectorTypeInfo;
  lInventory: TRemoveWithSymbolInventory;
  lResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
begin
  BuildResolverFixture(lInventory, lScanResult);

  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TResolverScope.Run', 'lExternal', lInfo),
    'Expected lExternal selector to be inspected.');
  Assert.AreEqual(RemoveWithSelectorTypeStatusToText(TRemoveWithSelectorTypeStatus.rwstsExternal),
    RemoveWithSelectorTypeStatusToText(lInfo.fStatus), 'Expected lExternal selector to be external.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TResolverScope.Run', 'MakeCustomer()', lInfo),
    'Expected MakeCustomer selector to be inspected.');
  Assert.AreEqual(RemoveWithSelectorTypeStatusToText(TRemoveWithSelectorTypeStatus.rwstsUnsupported),
    RemoveWithSelectorTypeStatusToText(lInfo.fStatus), 'Expected MakeCustomer selector to be unsupported.');

  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lResult, lError),
    'Expected resolver to succeed: ' + lError);

  AssertClassification(lResult, 'with-1', 'Name', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
  AssertClassification(lResult, 'with-1', 'Pick', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
  AssertClassification(lResult, 'with-1', 'Save', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
  AssertClassification(lResult, 'with-1', 'lLocalOnly', TRemoveWithIdentifierStatus.rwisUnchanged, '',
    'routine-scope');
  AssertClassification(lResult, 'with-2', 'Shared', TRemoveWithIdentifierStatus.rwisResolved, 'lAddress', '');
  AssertClassification(lResult, 'with-2', 'City', TRemoveWithIdentifierStatus.rwisResolved, 'lAddress', '');
  AssertClassification(lResult, 'with-2', 'Name', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
  AssertClassification(lResult, 'with-4', 'City', TRemoveWithIdentifierStatus.rwisResolved, 'Address', '');
  AssertClassification(lResult, 'with-4', 'Name', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
  AssertClassification(lResult, 'with-6', 'City', TRemoveWithIdentifierStatus.rwisUnsupported, 'AddressProp',
    'property-selector');
end;

procedure TRemoveWithResolverTests.ReportsExternalUnsupportedUnresolvedAndAmbiguousCases;
var
  lError: string;
  lInventory: TRemoveWithSymbolInventory;
  lResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
begin
  BuildResolverFixture(lInventory, lScanResult);

  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lResult, lError),
    'Expected resolver to succeed: ' + lError);

  AssertClassification(lResult, 'with-7', 'Count', TRemoveWithIdentifierStatus.rwisExternal, 'lExternal',
    'type-source-not-indexed');
  AssertClassification(lResult, 'with-8', 'Name', TRemoveWithIdentifierStatus.rwisUnsupported, 'MakeCustomer()',
    'call-selector');
  AssertClassification(lResult, 'with-8', 'Pick', TRemoveWithIdentifierStatus.rwisUnsupported, 'MakeCustomer()',
    'call-selector');
  AssertClassification(lResult, 'with-9', 'MissingMember', TRemoveWithIdentifierStatus.rwisUnresolved, '',
    'symbol-not-found');
  AssertClassification(lResult, 'with-10', 'Clash', TRemoveWithIdentifierStatus.rwisAmbiguousToDak, 'lDuplicate',
    'multiple-member-candidates');
end;

procedure TRemoveWithResolverTests.PlanCliEmitsResolverOnlyClassifications;
var
  lExitCode: Cardinal;
  lOutput: string;
begin
  lOutput := RunResolverFixtureCli(lExitCode);

  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with resolver plan report to succeed.');
  Assert.IsTrue(Pos('"resolved"', lOutput) > 0, 'Expected resolved classifications in plan output.');
  Assert.IsTrue(Pos('"unchanged"', lOutput) > 0, 'Expected unchanged classifications in plan output.');
  Assert.IsTrue(Pos('"ambiguous-to-DAK"', lOutput) > 0, 'Expected ambiguous classifications in plan output.');
  Assert.IsTrue(Pos('"plannedEdits"', lOutput) = 0, 'Resolver-only plan output must not include plannedEdits.');
end;

function TRemoveWithInheritedOverrideGoldenTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

function TRemoveWithInheritedOverrideGoldenTests.RunInheritedOverrideFixture(out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithInheritedOverrideFixture\RemoveWithInheritedOverrideFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-inherited-override-plan.json');
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode plan --format json';

  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath,
    aExitCode), 'Failed to start remove-with inherited override process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithInheritedOverrideGoldenTests.AssertJsonClassification(const aClassifications: TJSONArray;
  const aStatementId, aIdentifier, aStatus, aResolutionKind, aSourceOwnerType: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('statementId', ''), aStatementId) and
      SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) and
      SameText(lObject.GetValue<string>('status', ''), aStatus) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), aResolutionKind) and
      SameText(lObject.GetValue<string>('sourceOwnerType', ''), aSourceOwnerType) then
      Exit;
  end;
  Assert.Fail('Expected classification ' + aStatementId + ':' + aIdentifier + ':' + aStatus + ':' +
    aResolutionKind + ':' + aSourceOwnerType);
end;

procedure TRemoveWithInheritedOverrideGoldenTests.PlanReportDistinguishesInheritedOverrideHiddenAndExternalMembers;
var
  lClassifications: TJSONArray;
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
begin
  lOutput := RunInheritedOverrideFixture(lExitCode);

  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected inherited override plan report to succeed.');
  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected inherited override output to be a JSON object.');
    lRoot := lJson as TJSONObject;
    lResolver := lRoot.GetValue<TJSONObject>('resolver');
    Assert.IsNotNull(lResolver, 'Expected resolver object.');
    lClassifications := lResolver.GetValue<TJSONArray>('classifications');
    Assert.IsNotNull(lClassifications, 'Expected resolver classifications.');

    AssertJsonClassification(lClassifications, 'with-1', 'BaseField', 'resolved', 'inherited', 'TBaseGolden');
    AssertJsonClassification(lClassifications, 'with-1', 'DerivedField', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-1', 'DerivedProp', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-1', 'DerivedOnly', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-1', 'HiddenProp', 'resolved', 'hidden', '');
    AssertJsonClassification(lClassifications, 'with-1', 'HiddenMethod', 'resolved', 'hidden', '');
    AssertJsonClassification(lClassifications, 'with-1', 'OverrideMe', 'resolved', 'overridden', '');
    AssertJsonClassification(lClassifications, 'with-2', 'BaseProp', 'resolved', 'inherited', 'TBaseGolden');
    AssertJsonClassification(lClassifications, 'with-2', 'BaseOnly', 'resolved', 'inherited', 'TBaseGolden');
    AssertJsonClassification(lClassifications, 'with-2', 'BaseCount', 'resolved', 'inherited', 'TBaseGolden');
    AssertJsonClassification(lClassifications, 'with-2', 'BaseLimit', 'resolved', 'inherited', 'TBaseGolden');
    AssertJsonClassification(lClassifications, 'with-2', 'DerivedField', 'resolved', 'inherited', 'TDerivedGolden');
    AssertJsonClassification(lClassifications, 'with-2', 'MissingMember', 'unresolved', 'unresolved', '');
    AssertJsonClassification(lClassifications, 'with-3', 'Count', 'external', 'external-only', '');
  finally
    lJson.Free;
  end;
end;

function TRemoveWithInterfaceResolverTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

function TRemoveWithInterfaceResolverTests.RunInterfaceFixture(out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithInterfaceResolverFixture\RemoveWithInterfaceResolverFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-interface-plan.json');
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode plan --format json';

  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath,
    aExitCode), 'Failed to start remove-with interface resolver process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithInterfaceResolverTests.AssertJsonClassification(const aClassifications: TJSONArray;
  const aStatementId, aIdentifier, aStatus, aResolutionKind, aSourceOwnerType: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('statementId', ''), aStatementId) and
      SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) and
      SameText(lObject.GetValue<string>('status', ''), aStatus) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), aResolutionKind) and
      SameText(lObject.GetValue<string>('sourceOwnerType', ''), aSourceOwnerType) then
      Exit;
  end;
  Assert.Fail('Expected interface classification ' + aStatementId + ':' + aIdentifier + ':' + aStatus + ':' +
    aResolutionKind + ':' + aSourceOwnerType);
end;

procedure TRemoveWithInterfaceResolverTests.PlanReportUsesDeclaredInterfaceContract;
var
  lClassifications: TJSONArray;
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
begin
  lOutput := RunInterfaceFixture(lExitCode);

  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected interface resolver plan report to succeed.');
  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected interface resolver output to be a JSON object.');
    lRoot := lJson as TJSONObject;
    lResolver := lRoot.GetValue<TJSONObject>('resolver');
    Assert.IsNotNull(lResolver, 'Expected resolver object.');
    lClassifications := lResolver.GetValue<TJSONArray>('classifications');
    Assert.IsNotNull(lClassifications, 'Expected resolver classifications.');

    AssertJsonClassification(lClassifications, 'with-1', 'BaseTouch', 'resolved', 'inherited', 'IBaseContact');
    AssertJsonClassification(lClassifications, 'with-1', 'BaseName', 'resolved', 'inherited', 'IBaseContact');
    AssertJsonClassification(lClassifications, 'with-1', 'ChildTouch', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-1', 'ChildName', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-1', 'ConcreteOnly', 'unresolved', 'unresolved', '');
    AssertJsonClassification(lClassifications, 'with-2', 'ConcreteOnly', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-2', 'ChildTouch', 'resolved', 'direct', '');
  finally
    lJson.Free;
  end;
end;

function TRemoveWithHelperPrecedenceGoldenTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

function TRemoveWithHelperPrecedenceGoldenTests.RunHelperPrecedenceFixture(out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithHelperPrecedenceFixture\RemoveWithHelperPrecedenceFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-helper-precedence-plan.json');
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode plan --format json';

  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath,
    aExitCode), 'Failed to start remove-with helper precedence process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithHelperPrecedenceGoldenTests.AssertJsonClassification(const aClassifications: TJSONArray;
  const aStatementId, aIdentifier, aStatus, aResolutionKind, aSourceOwnerType: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('statementId', ''), aStatementId) and
      SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) and
      SameText(lObject.GetValue<string>('status', ''), aStatus) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), aResolutionKind) and
      SameText(lObject.GetValue<string>('sourceOwnerType', ''), aSourceOwnerType) then
      Exit;
  end;
  Assert.Fail('Expected helper classification ' + aStatementId + ':' + aIdentifier + ':' + aStatus + ':' +
    aResolutionKind + ':' + aSourceOwnerType);
end;

procedure TRemoveWithHelperPrecedenceGoldenTests.PlanReportDistinguishesDirectHelperAmbiguousAndExternalHelpers;
var
  lClassifications: TJSONArray;
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
begin
  lOutput := RunHelperPrecedenceFixture(lExitCode);

  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected helper precedence plan report to succeed.');
  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected helper precedence output to be a JSON object.');
    lRoot := lJson as TJSONObject;
    lResolver := lRoot.GetValue<TJSONObject>('resolver');
    Assert.IsNotNull(lResolver, 'Expected resolver object.');
    lClassifications := lResolver.GetValue<TJSONArray>('classifications');
    Assert.IsNotNull(lClassifications, 'Expected resolver classifications.');

    AssertJsonClassification(lClassifications, 'with-1', 'SharedName', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-1', 'DirectMethod', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-2', 'Normalize', 'resolved', 'helper',
      'THelperOnlyRecordHelper');
    AssertJsonClassification(lClassifications, 'with-2', 'HelperValue', 'resolved', 'helper',
      'THelperOnlyRecordHelper');
    AssertJsonClassification(lClassifications, 'with-3', 'Clash', 'ambiguous-to-DAK', 'ambiguous', '');
    AssertJsonClassification(lClassifications, 'with-4', 'HelperValue', 'resolved', 'helper',
      'THelperOnlyRecordHelper');
    AssertJsonClassification(lClassifications, 'with-5', 'ClearData', 'resolved', 'helper',
      'TClassHelperTargetHelper');
    AssertJsonClassification(lClassifications, 'with-5', 'HelperData', 'resolved', 'helper',
      'TClassHelperTargetHelper');
    AssertJsonClassification(lClassifications, 'with-6', 'ExternalHelper', 'external', 'external-only', '');
  finally
    lJson.Free;
  end;
end;

function TRemoveWithGlobalScopeGoldenTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

function TRemoveWithGlobalScopeGoldenTests.RunGlobalScopeFixture(out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithGlobalScopeFixture\RemoveWithGlobalScopeFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-global-scope-plan.json');
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode plan --format json';

  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath,
    aExitCode), 'Failed to start remove-with global scope process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithGlobalScopeGoldenTests.AssertJsonClassification(const aClassifications: TJSONArray;
  const aStatementId, aIdentifier, aStatus, aResolutionKind, aMemberKind: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('statementId', ''), aStatementId) and
      SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) and
      SameText(lObject.GetValue<string>('status', ''), aStatus) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), aResolutionKind) and
      SameText(lObject.GetValue<string>('memberKind', ''), aMemberKind) then
      Exit;
  end;
  Assert.Fail('Expected global-scope classification ' + aStatementId + ':' + aIdentifier + ':' + aStatus + ':' +
    aResolutionKind + ':' + aMemberKind);
end;

procedure TRemoveWithGlobalScopeGoldenTests.PlanReportDistinguishesWithReceiversAndOuterScopes;
var
  lClassifications: TJSONArray;
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
begin
  lOutput := RunGlobalScopeFixture(lExitCode);

  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected global scope plan report to succeed.');
  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected global scope output to be a JSON object.');
    lRoot := lJson as TJSONObject;
    lResolver := lRoot.GetValue<TJSONObject>('resolver');
    Assert.IsNotNull(lResolver, 'Expected resolver object.');
    lClassifications := lResolver.GetValue<TJSONArray>('classifications');
    Assert.IsNotNull(lClassifications, 'Expected resolver classifications.');

    AssertJsonClassification(lClassifications, 'with-1', 'Marker', 'resolved', 'direct', 'field');
    AssertJsonClassification(lClassifications, 'with-1', 'lLocalOnly', 'unchanged', 'unchanged', 'local-variable');
    AssertJsonClassification(lClassifications, 'with-1', 'aParamOnly', 'unchanged', 'unchanged', 'parameter');
    AssertJsonClassification(lClassifications, 'with-1', 'CurrentOnly', 'unchanged', 'unchanged',
      'current-class-member');
    AssertJsonClassification(lClassifications, 'with-1', 'UnitGlobalOnly', 'unchanged', 'unchanged', 'unit-global');
    AssertJsonClassification(lClassifications, 'with-1', 'ImplGlobalOnly', 'unchanged', 'unchanged', 'unit-global');
    AssertJsonClassification(lClassifications, 'with-1', 'UnitConstOnly', 'unchanged', 'unchanged', 'constant');
    AssertJsonClassification(lClassifications, 'with-1', 'ClassShared', 'unchanged', 'unchanged',
      'current-class-member');
    AssertJsonClassification(lClassifications, 'with-2', 'ShadowName', 'resolved', 'direct', 'field');
    AssertJsonClassification(lClassifications, 'with-3', 'GlobalScopeSupport', 'unchanged', 'qualified-unit',
      'unit');
    AssertJsonClassification(lClassifications, 'with-3', 'UnitGlobalOnly', 'unchanged', 'unchanged', 'unit-global');
    AssertJsonClassification(lClassifications, 'with-4', 'MissingGlobalScopeSupport', 'external', 'external-unit',
      'external');
    AssertJsonClassification(lClassifications, 'with-4', 'UnitGlobalOnly', 'unchanged', 'unchanged', 'unit-global');
    AssertJsonClassification(lClassifications, 'with-5', 'TStringList', 'unresolved', 'unresolved',
      'local-variable');
  finally
    lJson.Free;
  end;
end;

function TRemoveWithIndexedPropertyTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithIndexedPropertyTests.BuildIndexedPropertyFixture(out aInventory: TRemoveWithSymbolInventory);
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithIndexedPropertyFixture\RemoveWithIndexedPropertyFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, aInventory, lError),
    'Expected indexed property fixture inventory build to succeed: ' + lError);
end;

function TRemoveWithIndexedPropertyTests.FindSymbol(const aInventory: TRemoveWithSymbolInventory;
  const aName: string; const aKind: TRemoveWithSymbolKind; const aOwnerType: string;
  out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  for lSymbol in aInventory.fSymbols do
  begin
    if SameText(lSymbol.fName, aName) and (lSymbol.fKind = aKind) and
      SameText(lSymbol.fOwnerType, aOwnerType) then
    begin
      aSymbol := lSymbol;
      Exit(True);
    end;
  end;
end;

function TRemoveWithIndexedPropertyTests.RunIndexedPropertyFixture(out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithIndexedPropertyFixture\RemoveWithIndexedPropertyFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-indexed-property-plan.json');
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode plan --format json';

  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath,
    aExitCode), 'Failed to start remove-with indexed property process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithIndexedPropertyTests.AssertResolvedName(const aClassifications: TJSONArray;
  const aStatementId, aReceiverText, aReceiverType: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('statementId', ''), aStatementId) and
      SameText(lObject.GetValue<string>('identifier', ''), 'Name') and
      SameText(lObject.GetValue<string>('status', ''), 'resolved') and
      SameText(lObject.GetValue<string>('receiver', ''), aReceiverText) and
      SameText(lObject.GetValue<string>('receiverType', ''), aReceiverType) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), 'direct') and
      SameText(lObject.GetValue<string>('memberKind', ''), 'field') then
      Exit;
  end;
  Assert.Fail('Expected indexed selector to resolve Name for ' + aStatementId + ':' + aReceiverText);
end;

procedure TRemoveWithIndexedPropertyTests.AssertUnsupportedName(const aClassifications: TJSONArray;
  const aStatementId, aReceiverText, aReason: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('statementId', ''), aStatementId) and
      SameText(lObject.GetValue<string>('identifier', ''), 'Name') and
      SameText(lObject.GetValue<string>('status', ''), 'unsupported') and
      SameText(lObject.GetValue<string>('receiver', ''), aReceiverText) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), 'unsupported') and
      SameText(lObject.GetValue<string>('reason', ''), aReason) then
      Exit;
  end;
  Assert.Fail('Expected indexed selector to be unsupported for ' + aStatementId + ':' + aReceiverText + ':' +
    aReason);
end;

procedure TRemoveWithIndexedPropertyTests.SymbolInventoryParsesIndexedAndDefaultProperties;
var
  lInfo: TRemoveWithSelectorTypeInfo;
  lInventory: TRemoveWithSymbolInventory;
  lSymbol: TRemoveWithSymbolInfo;
begin
  BuildIndexedPropertyFixture(lInventory);

  Assert.IsTrue(FindSymbol(lInventory, 'Items', TRemoveWithSymbolKind.rwskProperty, 'TIndexedBox', lSymbol),
    'Expected indexed Items property symbol.');
  Assert.AreEqual('TIndexedRecord', lSymbol.fTypeName, 'Expected indexed property result type.');
  Assert.IsTrue(lSymbol.fIsDefault, 'Expected indexed Items property to be marked default.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TIndexedScope.Run', 'lBox.Items[0]', lInfo),
    'Expected selector resolver to handle indexed property selector.');
  Assert.AreEqual('unsupported', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected indexed property selector to be unsupported.');
  Assert.AreEqual('property-selector', lInfo.fReason, 'Expected indexed property selector reason.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TIndexedScope.Run', 'lBox[0]', lInfo),
    'Expected selector resolver to handle default property selector.');
  Assert.AreEqual('unsupported', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected default property selector to be unsupported.');
  Assert.AreEqual('property-selector', lInfo.fReason, 'Expected default property selector reason.');
end;

procedure TRemoveWithIndexedPropertyTests.PlanReportDistinguishesIndexedVariablesAndUnsafeIndexedProperties;
var
  lClassifications: TJSONArray;
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
begin
  lOutput := RunIndexedPropertyFixture(lExitCode);

  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected indexed property plan report to succeed.');
  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected indexed property output to be a JSON object.');
    lRoot := lJson as TJSONObject;
    lResolver := lRoot.GetValue<TJSONObject>('resolver');
    Assert.IsNotNull(lResolver, 'Expected resolver object.');
    lClassifications := lResolver.GetValue<TJSONArray>('classifications');
    Assert.IsNotNull(lClassifications, 'Expected resolver classifications.');

    AssertResolvedName(lClassifications, 'with-1', 'lRecords[0]', 'TIndexedRecord');
    AssertResolvedName(lClassifications, 'with-2', 'lNested[0].Items[0]', 'TIndexedRecord');
    AssertUnsupportedName(lClassifications, 'with-3', 'lBox.Items[0]', 'property-selector');
    AssertUnsupportedName(lClassifications, 'with-4', 'lBox[0]', 'property-selector');
    AssertUnsupportedName(lClassifications, 'with-5', 'MakeBox()[0]', 'call-selector');
    AssertResolvedName(lClassifications, 'with-7', 'Items[0]', 'TIndexedRecord');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithTempPolicyTests.BuildTempPolicyFixture(out aInventory: TRemoveWithSymbolInventory);
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithTempPolicyFixture\RemoveWithTempPolicyFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, aInventory, lError),
    'Expected temp policy fixture inventory build to succeed: ' + lError);
end;

procedure TRemoveWithTempPolicyTests.AssertPolicy(const aInventory: TRemoveWithSymbolInventory;
  const aSelectorText: string; const aStrategy: TRemoveWithTempStrategy; const aReceiverType, aQualifierText,
  aReason: string);
var
  lDecision: TRemoveWithTempDecision;
begin
  Assert.IsTrue(PlanRemoveWithTempPolicy(aInventory, 'TTempPolicyScope.Run', aSelectorText, lDecision),
    'Expected temp policy to inspect selector: ' + aSelectorText);
  Assert.AreEqual(RemoveWithTempStrategyToText(aStrategy), RemoveWithTempStrategyToText(lDecision.fStrategy),
    'Unexpected temp strategy for selector: ' + aSelectorText);
  Assert.AreEqual(aReceiverType, lDecision.fReceiverType, 'Unexpected receiver type for selector: ' + aSelectorText);
  Assert.AreEqual(aQualifierText, lDecision.fQualifierText, 'Unexpected qualifier for selector: ' + aSelectorText);
  Assert.AreEqual(aReason, lDecision.fReason, 'Unexpected reason for selector: ' + aSelectorText);
end;

procedure TRemoveWithTempPolicyTests.ChoosesDirectReferenceRecordPointerAndSkipStrategies;
var
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildTempPolicyFixture(lInventory);

  AssertPolicy(lInventory, 'lRecord', TRemoveWithTempStrategy.rwtsRecordPointerTemp, 'TTempPolicyRecord',
    'lWithTempPolicyRecordPtr2^', 'record-pointer-preserves-alias');
  AssertPolicy(lInventory, 'lRecordPtr^', TRemoveWithTempStrategy.rwtsDirectQualification, 'TTempPolicyRecord',
    'lRecordPtr^', 'already-pointer-qualified');
  AssertPolicy(lInventory, 'lRecords[lIndex]', TRemoveWithTempStrategy.rwtsRecordPointerTemp, 'TTempPolicyRecord',
    'lWithTempPolicyRecordPtr2^', 'record-pointer-preserves-alias');
  AssertPolicy(lInventory, 'lObject', TRemoveWithTempStrategy.rwtsReferenceTemp, 'TTempPolicyClass',
    'lWithTempPolicyClass', 'reference-temp-preserves-evaluation');
  AssertPolicy(lInventory, 'lObjects[lIndex]', TRemoveWithTempStrategy.rwtsReferenceTemp, 'TTempPolicyClass',
    'lWithTempPolicyClass', 'reference-temp-preserves-evaluation');
  AssertPolicy(lInventory, 'lScope.RecordProp', TRemoveWithTempStrategy.rwtsSkip, '', '', 'property-selector');
  AssertPolicy(lInventory, 'MakeRecord()', TRemoveWithTempStrategy.rwtsSkip, '', '', 'call-selector');
  AssertPolicy(lInventory, 'TTempPolicyRecord(lRecord)', TRemoveWithTempStrategy.rwtsSkip, '', '', 'cast-selector');
end;

procedure TRemoveWithTempPolicyTests.GeneratesCollisionFreeTempDeclarations;
var
  lDecision: TRemoveWithTempDecision;
  lInventory: TRemoveWithSymbolInventory;
begin
  BuildTempPolicyFixture(lInventory);

  Assert.IsTrue(PlanRemoveWithTempPolicy(lInventory, 'TTempPolicyScope.Run', 'lRecord', lDecision),
    'Expected record selector to produce a temp decision.');
  Assert.AreEqual('lWithTempPolicyRecordPtr2', lDecision.fTempName, 'Expected local temp collision avoidance.');
  Assert.AreEqual('lWithTempPolicyRecordPtr2: ^TTempPolicyRecord;', lDecision.fDeclarationText,
    'Expected legal method-level pointer declaration.');
  Assert.AreEqual('lWithTempPolicyRecordPtr2 := @lRecord;', lDecision.fInitializationText,
    'Expected address initialization for record temp.');

  Assert.IsTrue(PlanRemoveWithTempPolicy(lInventory, 'TTempPolicyScope.Run', 'lObjects[lIndex]', lDecision),
    'Expected object selector to produce a temp decision.');
  Assert.AreEqual('lWithTempPolicyClass: TTempPolicyClass;', lDecision.fDeclarationText,
    'Expected legal method-level object reference declaration.');
  Assert.AreEqual('lWithTempPolicyClass := lObjects[lIndex];', lDecision.fInitializationText,
    'Expected single-evaluation initialization for indexed object temp.');
end;

procedure TRemoveWithTempPolicyTests.ReservesGeneratedNamesAcrossSequentialPlans;
var
  lDecision: TRemoveWithTempDecision;
  lInventory: TRemoveWithSymbolInventory;
  lReservedNames: TRemoveWithReservedTempNames;
begin
  BuildTempPolicyFixture(lInventory);
  lReservedNames := Default(TRemoveWithReservedTempNames);

  Assert.IsTrue(PlanRemoveWithTempPolicy(lInventory, 'TTempPolicyScope.Run', 'lRecord', lReservedNames, lDecision),
    'Expected first record selector to produce a temp decision.');
  Assert.AreEqual('lWithTempPolicyRecordPtr2', lDecision.fTempName, 'Expected first record temp name.');

  Assert.IsTrue(PlanRemoveWithTempPolicy(lInventory, 'TTempPolicyScope.Run', 'lRecords[lIndex]', lReservedNames,
    lDecision), 'Expected second record selector to produce a temp decision.');
  Assert.AreEqual('lWithTempPolicyRecordPtr3', lDecision.fTempName, 'Expected second record temp name.');

  Assert.IsTrue(PlanRemoveWithTempPolicy(lInventory, 'TTempPolicyScope.Run', 'lObject', lReservedNames, lDecision),
    'Expected first object selector to produce a temp decision.');
  Assert.AreEqual('lWithTempPolicyClass', lDecision.fTempName, 'Expected first class temp name.');

  Assert.IsTrue(PlanRemoveWithTempPolicy(lInventory, 'TTempPolicyScope.Run', 'lObjects[lIndex]', lReservedNames,
    lDecision), 'Expected second object selector to produce a temp decision.');
  Assert.AreEqual('lWithTempPolicyClass1', lDecision.fTempName, 'Expected second class temp name.');
end;

end.
