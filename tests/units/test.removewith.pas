unit Test.RemoveWith;

interface

uses
  System.IOUtils, System.JSON, System.StrUtils, System.SysUtils,
  DUnitX.TestFramework,
  Dak.RemoveWith.Discovery, Dak.RemoveWith.Expressions, Dak.RemoveWith.Planner, Dak.RemoveWith.Resolver,
  Dak.RemoveWith.Symbols, Dak.RemoveWith.TempPolicy, Test.Support;

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
  TRemoveWithAstParallelSafetyTests = class(TRemoveWithTestBase)
  public
    [Test]
    procedure IndependentBuildersMatchSerialWithCounts;
    [Test]
    procedure ReadOnlySharedAstTraversalMatchesSerialWithCounts;
    [Test]
    procedure IndependentProjectIndexersMatchSerialWithCounts;
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
    [Test]
    procedure InventoryReadsAnsiEncodedSource;
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

  [TestFixture]
  TRemoveWithPlannerTests = class(TRemoveWithTestBase)
  private
    procedure BuildPlannerFixture(out aInventory: TRemoveWithSymbolInventory; out aScanResult: TRemoveWithScanResult;
      out aResolverResult: TRemoveWithResolverResult; out aPlanResult: TRemoveWithPlanResult);
    function CommandExePath: string;
    function FindPlannedStatement(const aPlanResult: TRemoveWithPlanResult; const aStatementId: string;
      out aStatement: TRemoveWithPlannedStatement): Boolean;
  public
    [Test]
    procedure PlansSafeRecordAndClassRewritesAndSkipsUnsafeSelectors;
    [Test]
    procedure PlanCliEmitsPlannedEditsWithoutChangingFixture;
  end;

  [TestFixture]
  TRemoveWithCliTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function RunBuildFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
    function SkippedReportContains(const aSkipped: TJSONArray; const aFileName, aReason: string): Boolean;
  public
    [Test]
    procedure ScanPlanApplyAndRollbackAcrossCopiedFixtures;
  end;

  [TestFixture]
  TRemoveWithRewriteShapeTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName, aUnitName: string; out aDprojPath,
      aUnitPath: string);
    function CountOccurrences(const aText, aNeedle: string): Integer;
    function RunApplyFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): TJSONObject;
    function RunBuildFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
  public
    [Test]
    procedure BeginEndAndSingleStatementBodiesRewriteSafely;
    [Test]
    procedure MultipleSelectorsRewriteWithCompilerPrecedence;
    [Test]
    procedure NestedWithBodiesRewriteByScopeStack;
    [Test]
    procedure ControlledNestedWithStatementsRemainSkipped;
    [Test]
    procedure NestedMultipleSelectorsRewriteOrBlockPrecisely;
    [Test]
    procedure TempPolicyRewriteEdgesApplyOrSkipSafely;
  end;

  [TestFixture]
  TRemoveWithTempAggregationTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName, aUnitName: string; out aDprojPath,
      aUnitPath: string);
    function CountDeclareTempEdits(const aPlans: TJSONArray): Integer;
    function CountOccurrences(const aText, aNeedle: string): Integer;
    function RunApplyFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): TJSONObject;
    function RunBuildFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
  public
    [Test]
    procedure ApplyAggregatesRoutineTempsAndBuilds;
  end;

  [TestFixture]
  TRemoveWithTransactionTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName, aUnitName: string; out aDprojPath,
      aUnitPath: string);
    function FindSingleManifest(const aProjectDir, aProjectName: string): string;
    function RunApplyFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
    function RunBuildFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
  public
    [Test]
    procedure ApplyModeBacksUpManifestsEditsAndBuildsFixture;
    [Test]
    procedure ApplyModeRollsBackExactBytesWhenBuildVerificationFails;
    [Test]
    procedure ApplyModeTextReportsTransactionStatus;
  end;

  [TestFixture]
  TRemoveWithApplyReportTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath: string);
    function RunApplyReport(const aDprojPath, aLogName: string; out aExitCode: Cardinal): TJSONObject;
    procedure AssertFileStatus(const aFiles: TJSONArray; const aExpectedStatus: string);
  public
    [Test]
    procedure ApplySuccessReportIncludesVerificationAndChangedFiles;
    [Test]
    procedure RollbackReportIncludesFailedVerificationAndRestoredFiles;
  end;

  [TestFixture]
  TRemoveWithNoEditAndRollbackTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
    procedure AssertTransactionFileStatus(const aFiles: TJSONArray; const aExpectedStatus: string);
  public
    [Test]
    procedure PlanModeLeavesSafeSkippedAndBlockedSourcesUnchanged;
    [Test]
    procedure ApplyModeLeavesAllSkippedAndBlockedSourcesUnchanged;
    [Test]
    procedure RollbackRestoresMixedSafeAndSkippedSourcesExactly;
  end;

  [TestFixture]
  TRemoveWithScopedDeclarationSafetyTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure ApplySkipsScopedDeclarationsAndLeavesSourceUnchanged;
  end;

  [TestFixture]
  TRemoveWithExpressionRoleRewriteTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function CountSkippedUnsupportedRole(const aSkipped: TJSONArray; const aRole: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure ApplySkipsUnsafeRolesAndRewritesSafeQualifiedCall;
  end;

  [TestFixture]
  TRemoveWithComplexSourceModelTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanSkipsComplexDeclarationsWithExplicitReasons;
  end;

  [TestFixture]
  TRemoveWithExternalRoutineTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure ApplyPreservesKnownExternalCallsAndSkipsUnknownCalls;
  end;

  [TestFixture]
  TRemoveWithCorpusSmokeTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanReportsStableCorpusCountsAndLeavesSourcesUnchanged;
  end;

  [TestFixture]
  TRemoveWithHardeningApplyTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
    procedure AssertApplySummary(const aRoot: TJSONObject; const aExpectedPlanned, aExpectedSkipped: Integer);
    procedure AssertVerificationPassed(const aRoot: TJSONObject);
    procedure AssertTransactionFileCount(const aRoot: TJSONObject; const aExpectedCount: Integer);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunApplyFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure ApplyBuildsMixedHardeningFixtures;
    [Test]
    procedure ApplyLeavesSkippedOnlyFixtureUnchanged;
  end;

  [TestFixture]
  TRemoveWithProprietaryProjectTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
    procedure AssertSnapshotUnchanged(const aPaths: TArray<string>; const aBytes: TArray<TBytes>;
      const aMessage: string);
    procedure CopyDirectoryToTemp(const aSourceDir, aTempName: string; out aCloneDir: string);
    function FindMaxTdbProject(const aFixtureDir: string): string;
    function IsIgnoredProjectArtifact(const aRelativePath: string): Boolean;
    function IsSourceSnapshotFile(const aPath: string): Boolean;
    function RunRemoveWithScan(const aDprojPath, aTargetDir, aLogName: string; out aExitCode: Cardinal): TJSONObject;
    procedure SnapshotSourceFiles(const aRootDir: string; out aPaths: TArray<string>;
      out aBytes: TArray<TBytes>);
  public
    [Test]
    procedure ScanCloneOfMaxTdbWhenFixtureExists;
    [Test]
    procedure SymbolInventoryResolvesMaxTdbGlobalPointerArrayWhenFixtureExists;
  end;

implementation

uses
  System.Threading,
  DelphiAST, DelphiAST.Classes, DelphiAST.Consts, DelphiAST.ProjectIndexer,
  Dak.Types;

const
  cAstParallelIterations = 24;
  cDiscoveryFixtureWithCount = 4;

function DiscoveryFixtureDprPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithDiscoveryFixture\RemoveWithDiscoveryFixture.dpr');
end;

function DiscoveryFixtureUnitPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithDiscoveryFixture\DiscoveryUnit.pas');
end;

function DiscoveryFixtureRoot: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithDiscoveryFixture');
end;

function CountWithNodes(const aNode: TSyntaxNode): Integer;
var
  lChild: TSyntaxNode;
begin
  Result := 0;
  if aNode = nil then
    Exit;

  if aNode.Typ = TSyntaxNodeType.ntWith then
    Inc(Result);
  for lChild in aNode.ChildNodes do
    Inc(Result, CountWithNodes(lChild));
end;

function CountWithNodesInUnitFile(const aFilePath: string): Integer;
var
  lSyntaxTree: TSyntaxNode;
begin
  lSyntaxTree := TPasSyntaxTreeBuilder.Run(aFilePath);
  try
    Result := CountWithNodes(lSyntaxTree);
  finally
    lSyntaxTree.Free;
  end;
end;

function CountWithNodesInProjectIndex(const aMainSourcePath: string): Integer;
var
  lIndexer: TProjectIndexer;
  lUnit: TProjectIndexer.TUnitInfo;
begin
  Result := 0;
  lIndexer := TProjectIndexer.Create;
  try
    lIndexer.Index(aMainSourcePath);
    for lUnit in lIndexer.ParsedUnits do
      Inc(Result, CountWithNodes(lUnit.SyntaxTree));
  finally
    lIndexer.Free;
  end;
end;

function ParallelCounts(const aIterations: Integer; const aCounter: TFunc<Integer>): TArray<Integer>;
var
  lCounts: TArray<Integer>;
begin
  SetLength(lCounts, aIterations);
  TParallel.&For(0, aIterations - 1,
    procedure(aIndex: Integer)
    begin
      lCounts[aIndex] := aCounter();
    end);
  Result := lCounts;
end;

procedure SnapshotDiscoveryFixture(out aPaths: TArray<string>; out aBytes: TArray<TBytes>);
var
  lCount: Integer;
  lFile: string;
begin
  SetLength(aPaths, 0);
  SetLength(aBytes, 0);
  lCount := 0;
  for lFile in TDirectory.GetFiles(DiscoveryFixtureRoot, '*', TSearchOption.soAllDirectories) do
  begin
    if not MatchText(TPath.GetExtension(lFile), ['.dpr', '.dproj', '.pas']) then
      Continue;

    SetLength(aPaths, lCount + 1);
    SetLength(aBytes, lCount + 1);
    aPaths[lCount] := lFile;
    aBytes[lCount] := TFile.ReadAllBytes(lFile);
    Inc(lCount);
  end;
end;

procedure AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aExpected), Length(aActual), aMessage + ' Size differs.');
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], aActual[i], aMessage + ' Byte differs at index ' + i.ToString + '.');
end;

procedure AssertDiscoveryFixtureUnchanged(const aProc: TProc);
var
  i: Integer;
  lBytes: TArray<TBytes>;
  lPaths: TArray<string>;
begin
  SnapshotDiscoveryFixture(lPaths, lBytes);
  Assert.IsTrue(Length(lPaths) > 0, 'Expected discovery fixture files to snapshot.');

  aProc();

  for i := 0 to High(lPaths) do
  begin
    Assert.IsTrue(TFile.Exists(lPaths[i]), 'Discovery fixture file disappeared: ' + lPaths[i]);
    AssertBytesEqual(lBytes[i], TFile.ReadAllBytes(lPaths[i]), 'Discovery fixture changed: ' + lPaths[i]);
  end;
end;

procedure AssertAllCounts(const aExpected: Integer; const aCounts: TArray<Integer>; const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(cAstParallelIterations, Length(aCounts), aMessage + ' Iteration count mismatch.');
  for i := 0 to High(aCounts) do
    Assert.AreEqual(aExpected, aCounts[i], aMessage + ' Iteration ' + i.ToString + ' mismatch.');
end;

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
    AssertJsonObjectKey(lRoot, 'summary', lChildObject);
    AssertJsonNumberKey(lChildObject, 'plannedEdits');
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
      AssertJsonBoolKey(lStatement, 'hasScopedDeclarationInBody');
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

procedure TRemoveWithAstParallelSafetyTests.IndependentBuildersMatchSerialWithCounts;
begin
  AssertDiscoveryFixtureUnchanged(
    procedure
    var
      lCounts: TArray<Integer>;
      lExpected: Integer;
    begin
      lExpected := CountWithNodesInUnitFile(DiscoveryFixtureUnitPath);
      Assert.AreEqual(cDiscoveryFixtureWithCount, lExpected, 'Expected stable serial discovery fixture count.');

      lCounts := ParallelCounts(cAstParallelIterations,
        function: Integer
        begin
          Result := CountWithNodesInUnitFile(DiscoveryFixtureUnitPath);
        end);
      AssertAllCounts(lExpected, lCounts, 'Independent parser instances must match serial parsing.');
    end);
end;

procedure TRemoveWithAstParallelSafetyTests.ReadOnlySharedAstTraversalMatchesSerialWithCounts;
begin
  AssertDiscoveryFixtureUnchanged(
    procedure
    var
      lCounts: TArray<Integer>;
      lExpected: Integer;
      lIndexer: TProjectIndexer;
      lRoots: TArray<TSyntaxNode>;
      lUnit: TProjectIndexer.TUnitInfo;
    begin
      lIndexer := TProjectIndexer.Create;
      try
        lExpected := 0;
        lIndexer.Index(DiscoveryFixtureDprPath);
        for lUnit in lIndexer.ParsedUnits do
        begin
          SetLength(lRoots, Length(lRoots) + 1);
          lRoots[High(lRoots)] := lUnit.SyntaxTree;
          Inc(lExpected, CountWithNodes(lUnit.SyntaxTree));
        end;
        Assert.AreEqual(cDiscoveryFixtureWithCount, lExpected, 'Expected stable project-index fixture count.');

        lCounts := ParallelCounts(cAstParallelIterations,
          function: Integer
          var
            lRoot: TSyntaxNode;
          begin
            Result := 0;
            for lRoot in lRoots do
              Inc(Result, CountWithNodes(lRoot));
          end);
        AssertAllCounts(lExpected, lCounts, 'Shared AST traversal must remain read-only and deterministic.');
      finally
        lIndexer.Free;
      end;
    end);
end;

procedure TRemoveWithAstParallelSafetyTests.IndependentProjectIndexersMatchSerialWithCounts;
begin
  AssertDiscoveryFixtureUnchanged(
    procedure
    var
      lCounts: TArray<Integer>;
      lExpected: Integer;
    begin
      lExpected := CountWithNodesInProjectIndex(DiscoveryFixtureDprPath);
      Assert.AreEqual(cDiscoveryFixtureWithCount, lExpected, 'Expected stable serial project-index fixture count.');

      lCounts := ParallelCounts(cAstParallelIterations,
        function: Integer
        begin
          Result := CountWithNodesInProjectIndex(DiscoveryFixtureDprPath);
        end);
      AssertAllCounts(lExpected, lCounts, 'Independent project indexers must match serial indexing.');
    end);
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

procedure TRemoveWithSymbolTests.InventoryReadsAnsiEncodedSource;
var
  i: Integer;
  lAnsiPath: string;
  lBytes: TBytes;
  lDir: string;
  lDprPath: string;
  lDprojPath: string;
  lError: string;
  lHead: TBytes;
  lInventory: TRemoveWithSymbolInventory;
  lOptions: TAppOptions;
  lSymbol: TRemoveWithSymbolInfo;
  lTail: TBytes;
begin
  lDir := TPath.Combine(TempRoot, 'remove-with-ansi-symbols');
  if TDirectory.Exists(lDir) then
    TDirectory.Delete(lDir, True);
  TDirectory.CreateDirectory(lDir);

  lDprojPath := TPath.Combine(lDir, 'RemoveWithAnsiSymbolsFixture.dproj');
  lDprPath := TPath.Combine(lDir, 'RemoveWithAnsiSymbolsFixture.dpr');
  lAnsiPath := TPath.Combine(lDir, 'AnsiSymbolUnit.pas');

  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>RemoveWithAnsiSymbolsFixture.dpr</MainSource>' + sLineBreak +
    '    <DCC_UnitSearchPath>.;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <DCCReference Include="AnsiSymbolUnit.pas"/>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '</Project>' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(lDprPath,
    'program RemoveWithAnsiSymbolsFixture;' + sLineBreak + sLineBreak +
    'uses' + sLineBreak +
    '  AnsiSymbolUnit in ''AnsiSymbolUnit.pas'';' + sLineBreak + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak, TEncoding.UTF8);

  lHead := TEncoding.ASCII.GetBytes(
    'unit AnsiSymbolUnit;' + #13#10 + #13#10 +
    'interface' + #13#10 + #13#10 +
    'type' + #13#10 +
    '  TAnsiSymbolRecord = record' + #13#10 +
    '    Name: string;' + #13#10 +
    '  end;' + #13#10 + #13#10 +
    'var' + #13#10 +
    '  AnsiGlobal: TAnsiSymbolRecord;' + #13#10 + #13#10 +
    'implementation' + #13#10 + #13#10 +
    '// Latin-1 byte follows: ');
  lTail := TEncoding.ASCII.GetBytes(#13#10 + #13#10 + 'end.' + #13#10);
  SetLength(lBytes, Length(lHead) + 1 + Length(lTail));
  for i := 0 to High(lHead) do
    lBytes[i] := lHead[i];
  lBytes[Length(lHead)] := $FC;
  for i := 0 to High(lTail) do
    lBytes[Length(lHead) + 1 + i] := lTail[i];
  TFile.WriteAllBytes(lAnsiPath, lBytes);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, lInventory, lError),
    'Expected ANSI source symbol inventory build to succeed: ' + lError);
  Assert.IsTrue(FindSymbol(lInventory, 'AnsiGlobal', TRemoveWithSymbolKind.rwskUnitGlobal, '', '', lSymbol),
    'Expected symbol inventory to parse declarations from ANSI source.');
  Assert.AreEqual('TAnsiSymbolRecord', lSymbol.fTypeName, 'Expected ANSI source declaration type.');
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
  AssertSelector(lInventory, 'GlobalRecordPtrs[0]^', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionRecord', '', True);
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
  Assert.IsTrue(Pos('"plannedEdits"', lOutput) > 0, 'Expected plannedEdits key in plan output.');
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
    AssertResolvedName(lClassifications, 'with-8', 'lStaticRecords[0]', 'TIndexedRecord');
    AssertResolvedName(lClassifications, 'with-9', 'lStaticRecordPtr^[0]', 'TIndexedRecord');
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

procedure TRemoveWithPlannerTests.BuildPlannerFixture(out aInventory: TRemoveWithSymbolInventory;
  out aScanResult: TRemoveWithScanResult; out aResolverResult: TRemoveWithResolverResult;
  out aPlanResult: TRemoveWithPlanResult);
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithPlannerFixture\RemoveWithPlannerFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lOptions.fRemoveWithAll := True;

  Assert.IsTrue(DiscoverRemoveWithStatements(lOptions, lOptions.fDprojPath, aScanResult, lError),
    'Expected planner fixture discovery to succeed: ' + lError);
  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, aInventory, lError),
    'Expected planner fixture inventory build to succeed: ' + lError);
  Assert.IsTrue(ResolveRemoveWithIdentifiers(aInventory, aScanResult, aResolverResult, lError),
    'Expected planner fixture resolver to succeed: ' + lError);
  Assert.IsTrue(PlanRemoveWithRewrites(aInventory, aScanResult, aResolverResult, aPlanResult, lError),
    'Expected planner fixture planning to succeed: ' + lError);
end;

function TRemoveWithPlannerTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

function TRemoveWithPlannerTests.FindPlannedStatement(const aPlanResult: TRemoveWithPlanResult;
  const aStatementId: string; out aStatement: TRemoveWithPlannedStatement): Boolean;
var
  lStatement: TRemoveWithPlannedStatement;
begin
  Result := False;
  aStatement := Default(TRemoveWithPlannedStatement);
  for lStatement in aPlanResult.fStatements do
  begin
    if SameText(lStatement.fStatementId, aStatementId) then
    begin
      aStatement := lStatement;
      Exit(True);
    end;
  end;
end;

procedure TRemoveWithPlannerTests.PlansSafeRecordAndClassRewritesAndSkipsUnsafeSelectors;
var
  lInventory: TRemoveWithSymbolInventory;
  lPlanResult: TRemoveWithPlanResult;
  lResolverResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
  lStatement: TRemoveWithPlannedStatement;
begin
  BuildPlannerFixture(lInventory, lScanResult, lResolverResult, lPlanResult);

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-1', lStatement), 'Expected record statement plan.');
  Assert.AreEqual('planned', lStatement.fStatus, 'Expected record statement to be planned.');
  Assert.IsTrue(Pos('lWithPlannerRecordPtr^.Name', lStatement.fReplacementText) > 0,
    'Expected record member qualification in replacement text.');
  Assert.IsTrue(Pos('lWithPlannerRecordPtr := @lRecord;', lStatement.fReplacementText) > 0,
    'Expected record temp initialization in replacement text.');
  Assert.IsTrue(Pos('lWithPlannerRecordPtr^.Count := lWithPlannerRecordPtr^.Count + 1',
    lStatement.fReplacementText) > 0, 'Expected repeated record member qualification in replacement text.');
  Assert.AreEqual(1, Length(lStatement.fTemps), 'Expected record pointer temp.');
  Assert.AreEqual('record-pointer-temp', RemoveWithTempStrategyToText(lStatement.fTemps[0].fStrategy),
    'Expected record pointer temp strategy.');
  Assert.AreEqual('declare-temp', lStatement.fEdits[0].fKind, 'Expected record temp declaration edit.');
  Assert.IsTrue(Pos('lWithPlannerRecordPtr: ^TPlannerRecord;', lStatement.fEdits[0].fReplacementText) > 0,
    'Expected record temp declaration text.');

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-2', lStatement), 'Expected object statement plan.');
  Assert.AreEqual('planned', lStatement.fStatus, 'Expected object statement to be planned.');
  Assert.IsTrue(Pos('lWithPlannerObject.Name', lStatement.fReplacementText) > 0,
    'Expected object member qualification in replacement text.');
  Assert.IsTrue(Pos('lWithPlannerObject := lObject;', lStatement.fReplacementText) > 0,
    'Expected object temp initialization in replacement text.');
  Assert.AreEqual('reference-temp', RemoveWithTempStrategyToText(lStatement.fTemps[0].fStrategy),
    'Expected object reference temp strategy.');

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-3', lStatement), 'Expected property statement result.');
  Assert.AreEqual('skipped', lStatement.fStatus, 'Expected property selector to be skipped.');
  Assert.AreEqual('property-selector', lStatement.fReason, 'Expected property selector skip reason.');

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-4', lStatement), 'Expected call statement result.');
  Assert.AreEqual('skipped', lStatement.fStatus, 'Expected call selector to be skipped.');
  Assert.AreEqual('call-selector', lStatement.fReason, 'Expected call selector skip reason.');

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-5', lStatement), 'Expected controlled statement result.');
  Assert.AreEqual('skipped', lStatement.fStatus, 'Expected controlled with to be skipped.');
  Assert.AreEqual('controlled-with-statement', lStatement.fReason, 'Expected controlled with skip reason.');

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-6', lStatement), 'Expected case-label statement result.');
  Assert.AreEqual('skipped', lStatement.fStatus, 'Expected case-label with to be skipped.');
  Assert.AreEqual('controlled-with-statement', lStatement.fReason, 'Expected case-label with skip reason.');

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-7', lStatement), 'Expected pointer statement plan.');
  Assert.AreEqual('planned', lStatement.fStatus, 'Expected pointer statement to be planned.');
  Assert.IsTrue(Pos('aRecordPtr^.Name', lStatement.fReplacementText) > 0,
    'Expected direct pointer qualification in replacement text.');
  Assert.AreEqual(0, Length(lStatement.fTemps), 'Expected no temp declaration for direct pointer qualification.');
  Assert.AreEqual(1, Length(lStatement.fEdits), 'Expected only replacement edit for direct pointer qualification.');
  Assert.AreEqual('replace-statement', lStatement.fEdits[0].fKind,
    'Expected no declaration edit for direct pointer qualification.');
end;

procedure TRemoveWithPlannerTests.PlanCliEmitsPlannedEditsWithoutChangingFixture;
var
  lArgs: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutput: string;
  lUnitPath: string;
  lUnitTextAfter: string;
  lUnitTextBefore: string;
begin
  EnsureResolverBuilt;
  lDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithPlannerFixture\RemoveWithPlannerFixture.dproj');
  lUnitPath := TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithPlannerFixture\PlannerUnit.pas');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-planner-plan.json');
  lUnitTextBefore := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode plan --format json';

  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, lExitCode),
    'Failed to start remove-with planner process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with planner plan report to succeed.');

  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('"plannedEdits"', lOutput) > 0, 'Expected planned edits in plan output.');
  Assert.IsTrue(Pos('lWithPlannerRecordPtr^.Name', lOutput) > 0, 'Expected record rewrite in plan output.');
  Assert.IsTrue(Pos('"property-selector"', lOutput) > 0, 'Expected skipped property selector in plan output.');

  lUnitTextAfter := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.AreEqual(lUnitTextBefore, lUnitTextAfter, 'Plan mode must not modify the planner fixture.');
end;

function TRemoveWithCliTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithCliTests.CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath,
  aFixtureDir: string);
var
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  aFixtureDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(aFixtureDir) then
    TDirectory.Delete(aFixtureDir, True);
  TDirectory.CreateDirectory(aFixtureDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(aFixtureDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(aFixtureDir, aFixtureName + '.dproj');
end;

function TRemoveWithCliTests.RunBuildFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
var
  lArgs: string;
  lCmdArgs: string;
  lCmdExe: string;
  lLogPath: string;
  lRsVarsPath: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lRsVarsPath := 'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat';
  if not TFile.Exists(lRsVarsPath) then
    lRsVarsPath := TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
      'Embarcadero\Studio\23.0\bin\rsvars.bat');
  lArgs := 'build --project ' + QuoteArg(aDprojPath) +
    ' --delphi 23.0 --platform Win32 --config Debug --builder delphi --rsvars ' + QuoteArg(lRsVarsPath);
  lCmdExe := GetEnvironmentVariable('ComSpec');
  if lCmdExe = '' then
    lCmdExe := 'C:\Windows\System32\cmd.exe';
  lCmdArgs := '/C set "BDS=" & set "BDSLIB=" & set "DCC_Namespace=" & set "DCC_UnitSearchPath=" & ' +
    'set "DelphiLibraryPath=" & set "EnvOptions=" & ' + QuoteArg(CommandExePath) + ' ' + lArgs;
  Assert.IsTrue(RunProcess(lCmdExe, lCmdArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start build process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

function TRemoveWithCliTests.RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode ' + aMode + ' --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with CLI process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

function TRemoveWithCliTests.SkippedReportContains(const aSkipped: TJSONArray; const aFileName,
  aReason: string): Boolean;
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  Result := False;
  for lItem in aSkipped do
  begin
    if not (lItem is TJSONObject) then
      Continue;

    lObject := lItem as TJSONObject;
    if (Pos(aFileName, lObject.GetValue<string>('file', '')) > 0) and
      SameText(lObject.GetValue<string>('reason', ''), aReason) then
      Exit(True);
  end;
end;

procedure TRemoveWithCliTests.ScanPlanApplyAndRollbackAcrossCopiedFixtures;
var
  lApplyRoot: TJSONObject;
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lExternalUnitPath: string;
  lExternalUnitTextBefore: string;
  lFixtureDir: string;
  lPlanRoot: TJSONObject;
  lRollbackDprojPath: string;
  lRollbackDir: string;
  lRollbackRoot: TJSONObject;
  lRollbackUnitBytesAfter: TBytes;
  lRollbackUnitBytesBefore: TBytes;
  lSafeUnitPath: string;
  lSafeUnitText: string;
  lScanRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSkippedUnitPath: string;
  lSkippedUnitTextAfter: string;
  lSkippedUnitTextBefore: string;
  i: Integer;
begin
  CopyFixtureToTemp('RemoveWithE2EFixture', 'remove-with-e2e', lDprojPath, lFixtureDir);
  lSafeUnitPath := TPath.Combine(lFixtureDir, 'E2ESafeUnit.pas');
  lSkippedUnitPath := TPath.Combine(lFixtureDir, 'E2ESkippedUnit.pas');
  lExternalUnitPath := TPath.Combine(lFixtureDir, 'E2EExternalUnit.pas');
  lSkippedUnitTextBefore := TFile.ReadAllText(lSkippedUnitPath, TEncoding.UTF8);
  lExternalUnitTextBefore := TFile.ReadAllText(lExternalUnitPath, TEncoding.UTF8);

  lScanRoot := RunRemoveWithFixture(lDprojPath, 'scan', 'remove-with-e2e-scan.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected e2e scan to succeed.');
    Assert.AreEqual('3', (lScanRoot.Values['summary'] as TJSONObject).Values['withStatements'].Value,
      'Expected safe, skipped, and external with statements in scan report.');
  finally
    lScanRoot.Free;
  end;

  lPlanRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-e2e-plan.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected e2e plan to succeed.');
    Assert.AreEqual(1, (lPlanRoot.Values['plannedEdits'] as TJSONArray).Count, 'Expected one safe edit plan.');
    lSkipped := lPlanRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(2, lSkipped.Count, 'Expected unsafe and external with statements to be skipped.');
    Assert.IsTrue(SkippedReportContains(lSkipped, 'E2ESkippedUnit.pas', 'controlled-with-statement'),
      'Expected skipped property-selector file and reason in plan report.');
    Assert.IsTrue(SkippedReportContains(lSkipped, 'E2EExternalUnit.pas', 'type-source-not-indexed'),
      'Expected skipped external-member file and reason in plan report.');
  finally
    lPlanRoot.Free;
  end;
  Assert.AreEqual(lSkippedUnitTextBefore, TFile.ReadAllText(lSkippedUnitPath, TEncoding.UTF8),
    'Plan mode must not edit skipped source.');
  Assert.AreEqual(lExternalUnitTextBefore, TFile.ReadAllText(lExternalUnitPath, TEncoding.UTF8),
    'Plan mode must not edit external source.');

  lApplyRoot := RunRemoveWithFixture(lDprojPath, 'apply', 'remove-with-e2e-apply.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected e2e apply to succeed.');
    Assert.AreEqual('applied', lApplyRoot.Values['status'].Value, 'Expected applied e2e status.');
  finally
    lApplyRoot.Free;
  end;
  lSafeUnitText := TFile.ReadAllText(lSafeUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with aCustomerPtr^ do', lSafeUnitText) = 0, 'Expected safe with to be removed.');
  Assert.IsTrue(Pos('aCustomerPtr^.Name := ''e2e'';', lSafeUnitText) > 0, 'Expected safe receiver qualification.');
  lSkippedUnitTextAfter := TFile.ReadAllText(lSkippedUnitPath, TEncoding.UTF8);
  Assert.AreEqual(lSkippedUnitTextBefore, lSkippedUnitTextAfter, 'Skipped unsafe unit must remain unchanged.');
  Assert.AreEqual(lExternalUnitTextBefore, TFile.ReadAllText(lExternalUnitPath, TEncoding.UTF8),
    'Skipped external unit must remain unchanged.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-e2e-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited e2e fixture to build. Output: ' + lBuildOutput);

  CopyFixtureToTemp('RemoveWithRollbackFixture', 'remove-with-e2e-rollback', lRollbackDprojPath, lRollbackDir);
  lRollbackUnitBytesBefore := TFile.ReadAllBytes(TPath.Combine(lRollbackDir, 'RollbackUnit.pas'));

  lRollbackRoot := RunRemoveWithFixture(lRollbackDprojPath, 'apply', 'remove-with-e2e-rollback.json', lExitCode);
  try
    Assert.AreNotEqual(Cardinal(0), lExitCode, 'Expected rollback fixture apply to fail verification.');
    Assert.AreEqual('rolledBack', lRollbackRoot.Values['status'].Value, 'Expected rolledBack e2e status.');
  finally
    lRollbackRoot.Free;
  end;

  lRollbackUnitBytesAfter := TFile.ReadAllBytes(TPath.Combine(lRollbackDir, 'RollbackUnit.pas'));
  Assert.AreEqual(Length(lRollbackUnitBytesBefore), Length(lRollbackUnitBytesAfter),
    'Expected rollback fixture source size to be restored.');
  for i := 0 to High(lRollbackUnitBytesBefore) do
    Assert.AreEqual(lRollbackUnitBytesBefore[i], lRollbackUnitBytesAfter[i],
      'Expected rollback fixture source bytes to be restored.');
end;

function TRemoveWithRewriteShapeTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithRewriteShapeTests.CopyFixtureToTemp(const aFixtureName, aTempName, aUnitName: string;
  out aDprojPath, aUnitPath: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aUnitPath := TPath.Combine(lDestinationDir, aUnitName);
end;

function TRemoveWithRewriteShapeTests.CountOccurrences(const aText, aNeedle: string): Integer;
var
  lOffset: Integer;
begin
  Result := 0;
  if aNeedle = '' then
    Exit;

  lOffset := Pos(aNeedle, aText);
  while lOffset > 0 do
  begin
    Inc(Result);
    lOffset := Pos(aNeedle, aText, lOffset + Length(aNeedle));
  end;
end;

function TRemoveWithRewriteShapeTests.RunApplyFixture(const aDprojPath, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode apply --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with apply process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

function TRemoveWithRewriteShapeTests.RunBuildFixture(const aDprojPath, aLogName: string;
  out aExitCode: Cardinal): string;
var
  lArgs: string;
  lCmdArgs: string;
  lCmdExe: string;
  lLogPath: string;
  lRsVarsPath: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lRsVarsPath := 'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat';
  if not TFile.Exists(lRsVarsPath) then
    lRsVarsPath := TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
      'Embarcadero\Studio\23.0\bin\rsvars.bat');
  lArgs := 'build --project ' + QuoteArg(aDprojPath) +
    ' --delphi 23.0 --platform Win32 --config Debug --builder delphi --rsvars ' + QuoteArg(lRsVarsPath);
  lCmdExe := GetEnvironmentVariable('ComSpec');
  if lCmdExe = '' then
    lCmdExe := 'C:\Windows\System32\cmd.exe';
  lCmdArgs := '/C set "BDS=" & set "BDSLIB=" & set "DCC_Namespace=" & set "DCC_UnitSearchPath=" & ' +
    'set "DelphiLibraryPath=" & set "EnvOptions=" & ' + QuoteArg(CommandExePath) + ' ' + lArgs;
  Assert.IsTrue(RunProcess(lCmdExe, lCmdArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start build process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithRewriteShapeTests.BeginEndAndSingleStatementBodiesRewriteSafely;
var
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lPlan: TJSONObject;
  lRoot: TJSONObject;
  lTemps: TJSONArray;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithRewriteShapeFixture', 'remove-with-rewrite-shapes', 'RewriteShapeUnit.pas',
    lDprojPath, lUnitPath);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-rewrite-shapes.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected rewrite-shape apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied rewrite-shape status.');
    Assert.AreEqual(2, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected block and single-statement rewrite plans.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with aRecordPtr^ do', lUnitText) = 0, 'Expected all with statements to be removed.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''block'';', lUnitText) > 0,
    'Expected begin-end body to be qualified.');
  Assert.IsTrue(Pos('aRecordPtr^.Count := aRecordPtr^.Count + 1;', lUnitText) > 0,
    'Expected repeated begin-end identifier to be qualified.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''single'';', lUnitText) > 0,
    'Expected single-statement body to be qualified.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-rewrite-shapes-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited rewrite-shape fixture to build. Output: ' +
    lBuildOutput);
end;

procedure TRemoveWithRewriteShapeTests.MultipleSelectorsRewriteWithCompilerPrecedence;
var
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lPlan: TJSONObject;
  lRoot: TJSONObject;
  lTemps: TJSONArray;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithMultipleSelectorRewriteFixture', 'remove-with-multiple-selectors',
    'MultipleSelectorUnit.pas', lDprojPath, lUnitPath);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-multiple-selectors.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected multiple-selector apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied multiple-selector status.');
    Assert.AreEqual(1, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected one multiple-selector rewrite plan.');
    lPlan := (lRoot.Values['plannedEdits'] as TJSONArray).Items[0] as TJSONObject;
    lTemps := lPlan.Values['temps'] as TJSONArray;
    Assert.AreEqual(2, lTemps.Count, 'Expected exactly two selector temps.');
    Assert.AreEqual('lPair.fLeft', (lTemps.Items[0] as TJSONObject).Values['selector'].Value,
      'Expected first temp to capture the earlier selector.');
    Assert.AreEqual('lWithMultiLeft := lPair.fLeft;',
      (lTemps.Items[0] as TJSONObject).Values['initialization'].Value,
      'Expected one initialization for the earlier selector.');
    Assert.AreEqual('lPair.fRight', (lTemps.Items[1] as TJSONObject).Values['selector'].Value,
      'Expected second temp to capture the later selector.');
    Assert.AreEqual('lWithMultiRight := lPair.fRight;',
      (lTemps.Items[1] as TJSONObject).Values['initialization'].Value,
      'Expected one initialization for the later selector.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with lPair.fLeft, lPair.fRight do', lUnitText) = 0,
    'Expected multiple-selector with statement to be removed.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, 'lWithMultiLeft := lPair.fLeft;'),
    'Expected left selector to be captured exactly once.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, 'lWithMultiRight := lPair.fRight;'),
    'Expected right selector to be captured exactly once.');
  Assert.IsTrue(Pos('lWithMultiRight.Common := ''right'';', lUnitText) > 0,
    'Expected later selector to win shared member lookup.');
  Assert.IsTrue(Pos('lWithMultiLeft.LeftOnly := ''left'';', lUnitText) > 0,
    'Expected earlier selector to qualify left-only member lookup.');
  Assert.IsTrue(Pos('lWithMultiRight.RightOnly := ''right-only'';', lUnitText) > 0,
    'Expected later selector to qualify right-only member lookup.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-multiple-selectors-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited multiple-selector fixture to build. Output: ' +
    lBuildOutput);
end;

procedure TRemoveWithRewriteShapeTests.NestedWithBodiesRewriteByScopeStack;
var
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lPlan: TJSONObject;
  lRoot: TJSONObject;
  lTemps: TJSONArray;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithNestedRewriteFixture', 'remove-with-nested-rewrite', 'NestedWithUnit.pas',
    lDprojPath, lUnitPath);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-nested-rewrite.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected nested rewrite apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied nested rewrite status.');
    Assert.AreEqual(1, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected one outer rewrite plan containing the nested rewrite.');
    lPlan := (lRoot.Values['plannedEdits'] as TJSONArray).Items[0] as TJSONObject;
    lTemps := lPlan.Values['temps'] as TJSONArray;
    Assert.AreEqual(2, lTemps.Count, 'Expected outer and inner selector temps.');
    Assert.AreEqual('lOuter', (lTemps.Items[0] as TJSONObject).Values['selector'].Value,
      'Expected first temp to capture the outer receiver.');
    Assert.AreEqual('lInner', (lTemps.Items[1] as TJSONObject).Values['selector'].Value,
      'Expected second temp to capture the inner receiver.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with lOuter do', lUnitText) = 0, 'Expected outer with statement to be removed.');
  Assert.IsTrue(Pos('with lInner do', lUnitText) = 0, 'Expected inner with statement to be removed.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, 'lWithNestedOuter := lOuter;'),
    'Expected outer selector to be captured exactly once.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, 'lWithNestedInner := lInner;'),
    'Expected inner selector to be captured exactly once.');
  Assert.IsTrue(Pos('lWithNestedOuter.Shared := lMarker;', lUnitText) > 0,
    'Expected outer body member to qualify against the outer receiver.');
  Assert.IsTrue(Pos('lWithNestedInner.Shared := lMarker;', lUnitText) > 0,
    'Expected inner receiver to win shared member lookup.');
  Assert.IsTrue(Pos('lWithNestedInner.InnerOnly := lWithNestedInner.Shared;', lUnitText) > 0,
    'Expected inner-only and repeated inner identifiers to qualify against the inner receiver.');
  Assert.IsTrue(Pos('lWithNestedOuter.OuterOnly := ''outer-from-inner'';', lUnitText) > 0,
    'Expected unresolved-in-inner member to fall back to the outer receiver.');
  Assert.IsTrue(Pos('lWithNestedOuter.OuterOnly := lMarker;', lUnitText) > 0,
    'Expected outer member after the nested body to remain in order.');
  Assert.IsTrue(Pos('lMarker := ''between'';', lUnitText) > 0,
    'Expected local statement before the nested body to remain unqualified.');
  Assert.IsTrue(Pos('lMarker := ''after-inner'';', lUnitText) > 0,
    'Expected local statement after the nested body to remain unqualified.');
  Assert.IsTrue(Pos('lMarker := ''after'';', lUnitText) > 0,
    'Expected statement after the outer with body to remain in place.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-nested-rewrite-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited nested rewrite fixture to build. Output: ' +
    lBuildOutput);
end;

procedure TRemoveWithRewriteShapeTests.ControlledNestedWithStatementsRemainSkipped;
var
  i: Integer;
  lDprojPath: string;
  lExitCode: Cardinal;
  lHasAncestorSkippedInner: Boolean;
  lHasControlledOuter: Boolean;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSkippedItem: TJSONObject;
  lUnitPath: string;
  lUnitTextAfter: string;
  lUnitTextBefore: string;
begin
  CopyFixtureToTemp('RemoveWithNestedControlledRewriteFixture', 'remove-with-nested-controlled-rewrite',
    'NestedControlledUnit.pas', lDprojPath, lUnitPath);
  lUnitTextBefore := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-nested-controlled-rewrite.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected controlled nested rewrite apply to finish without edits.');
    Assert.AreEqual(0, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected no planned edits for controlled nested with statements.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(2, lSkipped.Count, 'Expected outer and inner controlled nested with statements to be skipped.');
    lHasControlledOuter := False;
    lHasAncestorSkippedInner := False;
    for i := 0 to lSkipped.Count - 1 do
    begin
      lSkippedItem := lSkipped.Items[i] as TJSONObject;
      if (lSkippedItem.Values['statementId'].Value = 'with-1') and
        (lSkippedItem.Values['reason'].Value = 'controlled-with-statement') then
        lHasControlledOuter := True;
      if (lSkippedItem.Values['statementId'].Value = 'with-2') and
        (lSkippedItem.Values['reason'].Value = 'ancestor-with-not-planned') then
        lHasAncestorSkippedInner := True;
    end;
    Assert.IsTrue(lHasControlledOuter, 'Expected outer nested rewrite to be blocked by controlled child.');
    Assert.IsTrue(lHasAncestorSkippedInner, 'Expected inner nested rewrite to be skipped with its unplanned ancestor.');
  finally
    lRoot.Free;
  end;

  lUnitTextAfter := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.AreEqual(lUnitTextBefore, lUnitTextAfter, 'Expected controlled nested fixture source to remain unchanged.');
  Assert.IsTrue(Pos('if lCondition then', lUnitTextAfter) > 0, 'Expected controlling statement to remain.');
  Assert.IsTrue(Pos('with lInner do', lUnitTextAfter) > 0, 'Expected controlled inner with to remain.');
end;

procedure TRemoveWithRewriteShapeTests.NestedMultipleSelectorsRewriteOrBlockPrecisely;
var
  i: Integer;
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lHasAncestorSkippedAmbiguous: Boolean;
  lHasAmbiguousOuter: Boolean;
  lPlan: TJSONObject;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSkippedItem: TJSONObject;
  lTemps: TJSONArray;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithCombinedSelectorRewriteFixture', 'remove-with-combined-selectors',
    'CombinedSelectorUnit.pas', lDprojPath, lUnitPath);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-combined-selectors.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected combined selector apply to succeed for safe edits.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied combined selector status.');
    Assert.AreEqual(2, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected safe nested and unrelated safe rewrite plans.');
    lPlan := (lRoot.Values['plannedEdits'] as TJSONArray).Items[0] as TJSONObject;
    lTemps := lPlan.Values['temps'] as TJSONArray;
    Assert.AreEqual(4, lTemps.Count, 'Expected outer and inner multiple-selector temps.');
    Assert.AreEqual('lOuterLeft', (lTemps.Items[0] as TJSONObject).Values['selector'].Value,
      'Expected first outer selector temp.');
    Assert.AreEqual('lOuterRight', (lTemps.Items[1] as TJSONObject).Values['selector'].Value,
      'Expected second outer selector temp.');
    Assert.AreEqual('lInnerLeft', (lTemps.Items[2] as TJSONObject).Values['selector'].Value,
      'Expected first inner selector temp.');
    Assert.AreEqual('lInnerRight', (lTemps.Items[3] as TJSONObject).Values['selector'].Value,
      'Expected second inner selector temp.');

    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    lHasAmbiguousOuter := False;
    lHasAncestorSkippedAmbiguous := False;
    for i := 0 to lSkipped.Count - 1 do
    begin
      lSkippedItem := lSkipped.Items[i] as TJSONObject;
      if (lSkippedItem.Values['statementId'].Value = 'with-3') and
        (lSkippedItem.Values['reason'].Value = 'multiple-member-candidates') then
        lHasAmbiguousOuter := True;
      if (lSkippedItem.Values['statementId'].Value = 'with-4') and
        (lSkippedItem.Values['reason'].Value = 'ancestor-with-not-planned') then
        lHasAncestorSkippedAmbiguous := True;
    end;
    Assert.IsTrue(lHasAmbiguousOuter, 'Expected ambiguous nested multiple-selector parent to be skipped.');
    Assert.IsTrue(lHasAncestorSkippedAmbiguous, 'Expected ambiguous child to stay blocked with its parent.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.AreEqual(1, CountOccurrences(lUnitText, 'with lOuterLeft, lOuterRight do'),
    'Expected only the ambiguous outer multiple-selector with to remain.');
  Assert.IsTrue(Pos('with lInnerLeft, lInnerRight do', lUnitText) = 0,
    'Expected safe inner multiple-selector with to be removed.');
  Assert.IsTrue(Pos('lWithCombinedOuterRight.SharedOuter := ''outer-right'';', lUnitText) > 0,
    'Expected rightmost outer selector to win shared member lookup.');
  Assert.IsTrue(Pos('lWithCombinedOuterLeft.LeftOuterOnly := ''outer-left'';', lUnitText) > 0,
    'Expected left outer selector member to be qualified.');
  Assert.IsTrue(Pos('lWithCombinedInnerRight.InnerShared := ''inner-right'';', lUnitText) > 0,
    'Expected rightmost inner selector to win shared member lookup.');
  Assert.IsTrue(Pos('lWithCombinedInnerLeft.LeftInnerOnly := ''inner-left'';', lUnitText) > 0,
    'Expected left inner selector member to be qualified.');
  Assert.IsTrue(Pos('lWithCombinedInnerRight.RightInnerOnly := ''inner-right'';', lUnitText) > 0,
    'Expected right inner selector member to be qualified.');
  Assert.IsTrue(Pos('lWithCombinedOuterRight.RightOuterOnly := ''outer-fallback'';', lUnitText) > 0,
    'Expected inner body fallback to qualify against the active outer receiver.');
  Assert.IsTrue(Pos('with lAmbiguous do', lUnitText) > 0,
    'Expected ambiguous nested child to remain unchanged.');
  Assert.IsTrue(Pos('Clash();', lUnitText) > 0, 'Expected ambiguous call to remain unchanged.');
  Assert.IsTrue(Pos('with lSafeLeft, lSafeRight do', lUnitText) = 0,
    'Expected unrelated safe rewrite in same file to proceed.');
  Assert.IsTrue(Pos('lWithCombinedOuterRight.RightOuterOnly := ''safe-unrelated'';', lUnitText) > 0,
    'Expected unrelated safe rewrite to qualify the rightmost safe receiver.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-combined-selectors-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited combined selector fixture to build. Output: ' +
    lBuildOutput);
end;

procedure TRemoveWithRewriteShapeTests.TempPolicyRewriteEdgesApplyOrSkipSafely;
var
  i: Integer;
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lCallBlock: string;
  lCallSkipCount: Integer;
  lCastBlock: string;
  lCastSkipCount: Integer;
  lDprojPath: string;
  lExitCode: Cardinal;
  lPropertyBlock: string;
  lPropertyRecordBlock: string;
  lPropertySkipCount: Integer;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSkippedItem: TJSONObject;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithTempRewriteFixture', 'remove-with-temp-rewrite', 'TempRewriteUnit.pas',
    lDprojPath, lUnitPath);
  lPropertyBlock := 'with lObject.ChildObject do' + sLineBreak +
    '    begin' + sLineBreak +
    '      Name := ''property'';' + sLineBreak +
    '    end;';
  lPropertyRecordBlock := 'with lObject.RecordValue do' + sLineBreak +
    '    begin' + sLineBreak +
    '      Touch;' + sLineBreak +
    '    end;';
  lCastBlock := 'with TTempRewriteObject(lObject) do' + sLineBreak +
    '    begin' + sLineBreak +
    '      Name := ''cast'';' + sLineBreak +
    '    end;';
  lCallBlock := 'with MakeObject do' + sLineBreak +
    '    begin' + sLineBreak +
    '      Name := ''function'';' + sLineBreak +
    '      Free;' + sLineBreak +
    '    end;';

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-temp-rewrite.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected temp-policy rewrite apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied temp-policy rewrite status.');
    Assert.AreEqual(3, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected direct pointer, record pointer temp, and object temp rewrites.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    lPropertySkipCount := 0;
    lCallSkipCount := 0;
    lCastSkipCount := 0;
    for i := 0 to lSkipped.Count - 1 do
    begin
      lSkippedItem := lSkipped.Items[i] as TJSONObject;
      if lSkippedItem.Values['reason'].Value = 'property-selector' then
        Inc(lPropertySkipCount);
      if lSkippedItem.Values['reason'].Value = 'call-selector' then
        Inc(lCallSkipCount);
      if lSkippedItem.Values['reason'].Value = 'cast-selector' then
        Inc(lCastSkipCount);
    end;
    Assert.IsTrue(lPropertySkipCount >= 2, 'Expected object and record property selectors to be skipped explicitly.');
    Assert.IsTrue(lCastSkipCount >= 1, 'Expected cast selector to be skipped explicitly.');
    Assert.IsTrue(lCallSkipCount >= 1, 'Expected function selector to be skipped explicitly.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with aRecordPtr^ do', lUnitText) = 0,
    'Expected pointer-qualified record with to be removed.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''direct'';', lUnitText) > 0,
    'Expected pointer-qualified selector to stay directly qualified.');
  Assert.IsTrue(Pos('lWithTempRewriteRecordPtr := @lRecord;', lUnitText) > 0,
    'Expected addressable record selector to be captured by pointer temp.');
  Assert.IsTrue(Pos('lWithTempRewriteRecordPtr^.Name := ''record'';', lUnitText) > 0,
    'Expected record member write to use pointer temp.');
  Assert.IsTrue(Pos('lWithTempRewriteRecordPtr^.Count := lWithTempRewriteRecordPtr^.Count + 1;', lUnitText) > 0,
    'Expected repeated record member use to preserve aliasing through pointer temp.');
  Assert.IsTrue(Pos('lWithTempRewriteObject1 := lObject;', lUnitText) > 0,
    'Expected class receiver temp to avoid the existing local name.');
  Assert.IsTrue(Pos('lWithTempRewriteObject1.Name := ''object'';', lUnitText) > 0,
    'Expected class receiver member to use the collision-free reference temp.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, lPropertyBlock),
    'Expected object property selector with block to remain unchanged.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, lPropertyRecordBlock),
    'Expected non-addressable record property selector with block to remain unchanged.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, lCastBlock),
    'Expected cast selector with block to remain unchanged.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, lCallBlock),
    'Expected call selector with block to remain unchanged.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-temp-rewrite-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited temp-policy fixture to build. Output: ' +
    lBuildOutput);
end;

function TRemoveWithTempAggregationTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithTempAggregationTests.CopyFixtureToTemp(const aFixtureName, aTempName, aUnitName: string;
  out aDprojPath, aUnitPath: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aUnitPath := TPath.Combine(lDestinationDir, aUnitName);
end;

function TRemoveWithTempAggregationTests.CountDeclareTempEdits(const aPlans: TJSONArray): Integer;
var
  i: Integer;
  j: Integer;
  lEdit: TJSONObject;
  lEdits: TJSONArray;
  lPlan: TJSONObject;
begin
  Result := 0;
  for i := 0 to aPlans.Count - 1 do
  begin
    lPlan := aPlans.Items[i] as TJSONObject;
    lEdits := lPlan.Values['edits'] as TJSONArray;
    for j := 0 to lEdits.Count - 1 do
    begin
      lEdit := lEdits.Items[j] as TJSONObject;
      if lEdit.Values['kind'].Value = 'declare-temp' then
        Inc(Result);
    end;
  end;
end;

function TRemoveWithTempAggregationTests.CountOccurrences(const aText, aNeedle: string): Integer;
var
  lOffset: Integer;
begin
  Result := 0;
  if aNeedle = '' then
    Exit;

  lOffset := Pos(aNeedle, aText);
  while lOffset > 0 do
  begin
    Inc(Result);
    lOffset := Pos(aNeedle, aText, lOffset + Length(aNeedle));
  end;
end;

function TRemoveWithTempAggregationTests.RunApplyFixture(const aDprojPath, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode apply --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with apply process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

function TRemoveWithTempAggregationTests.RunBuildFixture(const aDprojPath, aLogName: string;
  out aExitCode: Cardinal): string;
var
  lArgs: string;
  lCmdArgs: string;
  lCmdExe: string;
  lLogPath: string;
  lRsVarsPath: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lRsVarsPath := 'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat';
  if not TFile.Exists(lRsVarsPath) then
    lRsVarsPath := TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
      'Embarcadero\Studio\23.0\bin\rsvars.bat');
  lArgs := 'build --project ' + QuoteArg(aDprojPath) +
    ' --delphi 23.0 --platform Win32 --config Debug --builder delphi --rsvars ' + QuoteArg(lRsVarsPath);
  lCmdExe := GetEnvironmentVariable('ComSpec');
  if lCmdExe = '' then
    lCmdExe := 'C:\Windows\System32\cmd.exe';
  lCmdArgs := '/C set "BDS=" & set "BDSLIB=" & set "DCC_Namespace=" & set "DCC_UnitSearchPath=" & ' +
    'set "DelphiLibraryPath=" & set "EnvOptions=" & ' + QuoteArg(CommandExePath) + ' ' + lArgs;
  Assert.IsTrue(RunProcess(lCmdExe, lCmdArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start build process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithTempAggregationTests.ApplyAggregatesRoutineTempsAndBuilds;
var
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lPlans: TJSONArray;
  lRoot: TJSONObject;
  lTemps: TJSONArray;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithTempAggregationFixture', 'remove-with-temp-aggregation',
    'TempAggregationUnit.pas', lDprojPath, lUnitPath);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-temp-aggregation.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected temp aggregation apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied temp aggregation status.');
    lPlans := lRoot.Values['plannedEdits'] as TJSONArray;
    Assert.AreEqual(8, lPlans.Count, 'Expected all same-routine with statements to be planned.');
    Assert.AreEqual(3, CountDeclareTempEdits(lPlans), 'Expected one declaration edit per routine.');

    lTemps := (lPlans.Items[4] as TJSONObject).Values['temps'] as TJSONArray;
    Assert.AreEqual('lWithTempAggregationRecordPtr', (lTemps.Items[0] as TJSONObject).Values['tempName'].Value,
      'Expected first record temp name.');
    Assert.AreEqual('lWithTempAggregationRecordPtr := @aFirstRecord;',
      (lTemps.Items[0] as TJSONObject).Values['initialization'].Value,
      'Expected first record temp initialization.');

    lTemps := (lPlans.Items[5] as TJSONObject).Values['temps'] as TJSONArray;
    Assert.AreEqual('lWithTempAggregationRecordPtr1', (lTemps.Items[0] as TJSONObject).Values['tempName'].Value,
      'Expected second record temp name to reserve across the routine.');
    Assert.AreEqual('lWithTempAggregationRecordPtr1 := @aSecondRecord;',
      (lTemps.Items[0] as TJSONObject).Values['initialization'].Value,
      'Expected second record temp initialization.');

    lTemps := (lPlans.Items[6] as TJSONObject).Values['temps'] as TJSONArray;
    Assert.AreEqual('lWithTempAggregationObject', (lTemps.Items[0] as TJSONObject).Values['tempName'].Value,
      'Expected first object temp name.');

    lTemps := (lPlans.Items[7] as TJSONObject).Values['temps'] as TJSONArray;
    Assert.AreEqual('lWithTempAggregationObject1', (lTemps.Items[0] as TJSONObject).Values['tempName'].Value,
      'Expected second object temp name to reserve across the routine.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.AreEqual(0, CountOccurrences(lUnitText, 'with aFirstRecord do'),
    'Expected first record with statement to be removed.');
  Assert.AreEqual(0, CountOccurrences(lUnitText, 'with aSecondRecord do'),
    'Expected second record with statement to be removed.');
  Assert.AreEqual(0, CountOccurrences(lUnitText, 'with aFirstObject do'),
    'Expected first object with statement to be removed.');
  Assert.AreEqual(0, CountOccurrences(lUnitText, 'with aSecondObject do'),
    'Expected second object with statement to be removed.');
  Assert.AreEqual(3, CountOccurrences(lUnitText, sLineBreak + 'var' + sLineBreak),
    'Expected one var section per fixture routine.');
  Assert.AreEqual(3, CountOccurrences(lUnitText, 'lWithTempAggregationRecordPtr: ^TTempAggregationRecord;'),
    'Expected first record declaration once per routine.');
  Assert.AreEqual(3, CountOccurrences(lUnitText, 'lWithTempAggregationRecordPtr1: ^TTempAggregationRecord;'),
    'Expected second record declaration once per routine.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, 'lWithTempAggregationObject: TTempAggregationObject;'),
    'Expected first object declaration once.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, 'lWithTempAggregationObject1: TTempAggregationObject;'),
    'Expected second object declaration once.');
  Assert.IsTrue(Pos('lWithTempAggregationRecordPtr^.Count := lWithTempAggregationRecordPtr^.Count + 1;',
    lUnitText) > 0, 'Expected first record body to use the pointer temp.');
  Assert.IsTrue(Pos('lWithTempAggregationRecordPtr1^.Count := lWithTempAggregationRecordPtr1^.Count + 1;',
    lUnitText) > 0, 'Expected second record body to use the pointer temp.');
  Assert.IsTrue(Pos('lWithTempAggregationObject.Count := lWithTempAggregationObject.Count + 1;',
    lUnitText) > 0, 'Expected first object body to use the reference temp.');
  Assert.IsTrue(Pos('lWithTempAggregationObject1.Count := lWithTempAggregationObject1.Count + 1;',
    lUnitText) > 0, 'Expected second object body to use the reference temp.');
  Assert.IsTrue(Pos('var' + sLineBreak +
    '  lMarker: Integer;' + sLineBreak +
    '  lWithTempAggregationRecordPtr: ^TTempAggregationRecord;' + sLineBreak +
    '  lWithTempAggregationRecordPtr1: ^TTempAggregationRecord;' + sLineBreak +
    'begin', lUnitText) > 0, 'Expected existing var section to receive aggregated declarations.');
  Assert.IsTrue(Pos('var' + sLineBreak +
    '  lWithTempAggregationRecordPtr: ^TTempAggregationRecord;' + sLineBreak +
    '  lWithTempAggregationRecordPtr1: ^TTempAggregationRecord;' + sLineBreak +
    '  procedure TouchLocal;', lUnitText) > 0,
    'Expected declarations before the local routine, not inside it.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-temp-aggregation-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited temp aggregation fixture to build. Output: ' +
    lBuildOutput);
end;

function TRemoveWithTransactionTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithTransactionTests.AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aExpected), Length(aActual), aMessage + ' Size differs.');
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], aActual[i], aMessage + ' Byte differs at index ' + i.ToString + '.');
end;

procedure TRemoveWithTransactionTests.CopyFixtureToTemp(const aFixtureName, aTempName, aUnitName: string;
  out aDprojPath, aUnitPath: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aUnitPath := TPath.Combine(lDestinationDir, aUnitName);
end;

function TRemoveWithTransactionTests.FindSingleManifest(const aProjectDir, aProjectName: string): string;
var
  lFiles: TArray<string>;
  lRoot: string;
begin
  lRoot := TPath.Combine(TPath.Combine(TPath.Combine(aProjectDir, '.dak'), aProjectName), 'remove-with');
  lFiles := TDirectory.GetFiles(lRoot, 'manifest.json', TSearchOption.soAllDirectories);
  Assert.AreEqual(1, Length(lFiles), 'Expected exactly one transaction manifest under ' + lRoot + '.');
  Result := lFiles[0];
end;

function TRemoveWithTransactionTests.RunApplyFixture(const aDprojPath, aLogName: string;
  out aExitCode: Cardinal): string;
var
  lArgs: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode apply --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with apply process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

function TRemoveWithTransactionTests.RunBuildFixture(const aDprojPath, aLogName: string;
  out aExitCode: Cardinal): string;
var
  lArgs: string;
  lCmdArgs: string;
  lCmdExe: string;
  lLogPath: string;
  lRsVarsPath: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lRsVarsPath := 'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat';
  if not TFile.Exists(lRsVarsPath) then
    lRsVarsPath := TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
      'Embarcadero\Studio\23.0\bin\rsvars.bat');
  lArgs := 'build --project ' + QuoteArg(aDprojPath) +
    ' --delphi 23.0 --platform Win32 --config Debug --builder delphi --rsvars ' + QuoteArg(lRsVarsPath);
  lCmdExe := GetEnvironmentVariable('ComSpec');
  if lCmdExe = '' then
    lCmdExe := 'C:\Windows\System32\cmd.exe';
  lCmdArgs := '/C set "BDS=" & set "BDSLIB=" & set "DCC_Namespace=" & set "DCC_UnitSearchPath=" & ' +
    'set "DelphiLibraryPath=" & set "EnvOptions=" & ' + QuoteArg(CommandExePath) + ' ' + lArgs;
  Assert.IsTrue(RunProcess(lCmdExe, lCmdArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start build process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithTransactionTests.ApplyModeBacksUpManifestsEditsAndBuildsFixture;
var
  lBackupPath: string;
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFiles: TJSONArray;
  lManifest: TJSONObject;
  lManifestPath: string;
  lManifestValue: TJSONValue;
  lOriginalBytes: TBytes;
  lOutput: string;
  lOutputValue: TJSONValue;
  lProjectDir: string;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithApplyFixture', 'remove-with-apply-transaction', 'ApplyUnit.pas', lDprojPath,
    lUnitPath);
  lOriginalBytes := TFile.ReadAllBytes(lUnitPath);

  lOutput := RunApplyFixture(lDprojPath, 'remove-with-apply-transaction.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected apply mode to succeed. Output: ' + lOutput);
  lOutputValue := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lOutputValue is TJSONObject, 'Expected apply output to be a single JSON object. Output: ' +
      lOutput);
    Assert.AreEqual('applied', (lOutputValue as TJSONObject).Values['status'].Value,
      'Expected applied status in apply output.');
  finally
    lOutputValue.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with aRecordPtr^ do', lUnitText) = 0, 'Expected with statement to be removed.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''applied'';', lUnitText) > 0, 'Expected direct pointer qualification.');

  lProjectDir := TPath.GetDirectoryName(lDprojPath);
  lManifestPath := FindSingleManifest(lProjectDir, 'RemoveWithApplyFixture');
  lManifestValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(lManifestPath, TEncoding.UTF8));
  try
    Assert.IsTrue(lManifestValue is TJSONObject, 'Expected manifest JSON object.');
    lManifest := lManifestValue as TJSONObject;
    Assert.AreEqual('applied', lManifest.Values['status'].Value, 'Expected applied manifest status.');
    Assert.IsTrue(lManifest.Values['files'] is TJSONArray, 'Expected manifest files array.');
    lFiles := lManifest.Values['files'] as TJSONArray;
    Assert.AreEqual(1, lFiles.Count, 'Expected one backed up file.');
    Assert.AreEqual('crlf', (lFiles.Items[0] as TJSONObject).Values['lineEnding'].Value,
      'Expected CRLF manifest line-ending fact.');
    Assert.AreEqual('utf-8', (lFiles.Items[0] as TJSONObject).Values['encoding'].Value,
      'Expected UTF-8 manifest encoding fact.');
    lBackupPath := (lFiles.Items[0] as TJSONObject).Values['backupPath'].Value;
    Assert.IsTrue(FileExists(lBackupPath), 'Expected backup file to exist.');
    AssertBytesEqual(lOriginalBytes, TFile.ReadAllBytes(lBackupPath), 'Backup must preserve exact original bytes.');
  finally
    lManifestValue.Free;
  end;

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-apply-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited apply fixture to build. Output: ' + lBuildOutput);
end;

procedure TRemoveWithTransactionTests.ApplyModeRollsBackExactBytesWhenBuildVerificationFails;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lManifest: TJSONObject;
  lManifestPath: string;
  lManifestValue: TJSONValue;
  lOriginalBytes: TBytes;
  lOutput: string;
  lOutputValue: TJSONValue;
  lProjectDir: string;
  lUnitPath: string;
begin
  CopyFixtureToTemp('RemoveWithRollbackFixture', 'remove-with-rollback-transaction', 'RollbackUnit.pas',
    lDprojPath, lUnitPath);
  lOriginalBytes := TFile.ReadAllBytes(lUnitPath);

  lOutput := RunApplyFixture(lDprojPath, 'remove-with-rollback-transaction.json', lExitCode);
  Assert.AreNotEqual(Cardinal(0), lExitCode, 'Expected apply mode to fail after build verification.');
  lOutputValue := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lOutputValue is TJSONObject, 'Expected rollback output to be a single JSON object. Output: ' +
      lOutput);
    Assert.AreEqual('rolledBack', (lOutputValue as TJSONObject).Values['status'].Value,
      'Expected rollback status in failed apply output.');
  finally
    lOutputValue.Free;
  end;
  AssertBytesEqual(lOriginalBytes, TFile.ReadAllBytes(lUnitPath), 'Rollback must restore exact original bytes.');

  lProjectDir := TPath.GetDirectoryName(lDprojPath);
  lManifestPath := FindSingleManifest(lProjectDir, 'RemoveWithRollbackFixture');
  lManifestValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(lManifestPath, TEncoding.UTF8));
  try
    Assert.IsTrue(lManifestValue is TJSONObject, 'Expected rollback manifest JSON object.');
    lManifest := lManifestValue as TJSONObject;
    Assert.AreEqual('rolledBack', lManifest.Values['status'].Value, 'Expected rolledBack manifest status.');
    Assert.IsTrue(lManifest.Values['files'] is TJSONArray, 'Expected rollback manifest files array.');
    Assert.AreEqual(1, (lManifest.Values['files'] as TJSONArray).Count, 'Expected one restored file.');
  finally
    lManifestValue.Free;
  end;
end;

procedure TRemoveWithTransactionTests.ApplyModeTextReportsTransactionStatus;
var
  lArgs: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutput: string;
  lUnitPath: string;
begin
  CopyFixtureToTemp('RemoveWithApplyFixture', 'remove-with-apply-text-transaction', 'ApplyUnit.pas', lDprojPath,
    lUnitPath);
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'remove-with-apply-transaction.txt');
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode apply --format text';

  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, lExitCode),
    'Failed to start remove-with apply text process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);

  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected text apply mode to succeed. Output: ' + lOutput);
  Assert.IsTrue(Pos('status=applied', lOutput) > 0, 'Expected text output to report applied status.');
  Assert.IsTrue(Pos('appliedEdits=1', lOutput) > 0, 'Expected text output to report applied edit count.');
  Assert.IsTrue(Pos('verification=passed', lOutput) > 0, 'Expected text output to report verification status.');
end;

function TRemoveWithApplyReportTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithApplyReportTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
  out aDprojPath: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
end;

function TRemoveWithApplyReportTests.RunApplyReport(const aDprojPath, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode apply --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with apply report process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable apply report JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRemoveWithApplyReportTests.AssertFileStatus(const aFiles: TJSONArray; const aExpectedStatus: string);
var
  lFileObject: TJSONObject;
begin
  Assert.AreEqual(1, aFiles.Count, 'Expected one transaction file.');
  Assert.IsTrue(aFiles.Items[0] is TJSONObject, 'Expected transaction file object.');
  lFileObject := aFiles.Items[0] as TJSONObject;
  Assert.AreEqual(aExpectedStatus, lFileObject.Values['status'].Value, 'Expected transaction file status.');
  AssertJsonStringKey(lFileObject, 'path');
  AssertJsonStringKey(lFileObject, 'backupPath');
  AssertJsonStringKey(lFileObject, 'hash');
  AssertJsonNumberKey(lFileObject, 'size');
  AssertJsonStringKey(lFileObject, 'lineEnding');
  AssertJsonStringKey(lFileObject, 'encoding');
end;

procedure TRemoveWithApplyReportTests.ApplySuccessReportIncludesVerificationAndChangedFiles;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFiles: TJSONArray;
  lGates: TJSONArray;
  lRoot: TJSONObject;
  lTransaction: TJSONObject;
  lVerification: TJSONObject;
begin
  CopyFixtureToTemp('RemoveWithApplyFixture', 'remove-with-apply-report', lDprojPath);
  lRoot := RunApplyReport(lDprojPath, 'remove-with-apply-report.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected apply report fixture to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied root status.');
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('passed', lVerification.Values['status'].Value, 'Expected passed verification status.');
    AssertJsonArrayKey(lVerification, 'gates', lGates);
    Assert.AreEqual(1, lGates.Count, 'Expected one verification gate.');
    Assert.AreEqual('build', (lGates.Items[0] as TJSONObject).Values['name'].Value, 'Expected build gate.');
    Assert.AreEqual('passed', (lGates.Items[0] as TJSONObject).Values['status'].Value,
      'Expected passed build gate.');

    AssertJsonObjectKey(lRoot, 'transaction', lTransaction);
    AssertJsonStringKey(lTransaction, 'manifestPath');
    AssertJsonArrayKey(lTransaction, 'files', lFiles);
    AssertFileStatus(lFiles, 'changed');
  finally
    lRoot.Free;
  end;
end;

procedure TRemoveWithApplyReportTests.RollbackReportIncludesFailedVerificationAndRestoredFiles;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFiles: TJSONArray;
  lGates: TJSONArray;
  lRoot: TJSONObject;
  lTransaction: TJSONObject;
  lVerification: TJSONObject;
begin
  CopyFixtureToTemp('RemoveWithRollbackFixture', 'remove-with-rollback-report', lDprojPath);
  lRoot := RunApplyReport(lDprojPath, 'remove-with-rollback-report.json', lExitCode);
  try
    Assert.AreNotEqual(Cardinal(0), lExitCode, 'Expected rollback report fixture to fail verification.');
    Assert.AreEqual('rolledBack', lRoot.Values['status'].Value, 'Expected rolledBack root status.');
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('failed', lVerification.Values['status'].Value, 'Expected failed verification status.');
    AssertJsonArrayKey(lVerification, 'gates', lGates);
    Assert.AreEqual(1, lGates.Count, 'Expected one verification gate.');
    Assert.AreEqual('build', (lGates.Items[0] as TJSONObject).Values['name'].Value, 'Expected build gate.');
    Assert.AreEqual('failed', (lGates.Items[0] as TJSONObject).Values['status'].Value,
      'Expected failed build gate.');

    AssertJsonObjectKey(lRoot, 'transaction', lTransaction);
    AssertJsonStringKey(lTransaction, 'manifestPath');
    AssertJsonArrayKey(lTransaction, 'files', lFiles);
    AssertFileStatus(lFiles, 'restored');
  finally
    lRoot.Free;
  end;
end;

function TRemoveWithNoEditAndRollbackTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithNoEditAndRollbackTests.AssertBytesEqual(const aExpected, aActual: TBytes;
  const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aExpected), Length(aActual), aMessage + ' Size differs.');
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], aActual[i], aMessage + ' Byte differs at index ' + i.ToString + '.');
end;

procedure TRemoveWithNoEditAndRollbackTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
  out aDprojPath, aFixtureDir: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aFixtureDir := lDestinationDir;
end;

function TRemoveWithNoEditAndRollbackTests.RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode ' + aMode + ' --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRemoveWithNoEditAndRollbackTests.AssertTransactionFileStatus(const aFiles: TJSONArray;
  const aExpectedStatus: string);
var
  lFileObject: TJSONObject;
begin
  Assert.AreEqual(1, aFiles.Count, 'Expected one transaction file.');
  Assert.IsTrue(aFiles.Items[0] is TJSONObject, 'Expected transaction file object.');
  lFileObject := aFiles.Items[0] as TJSONObject;
  Assert.AreEqual(aExpectedStatus, lFileObject.Values['status'].Value, 'Expected transaction file status.');
  AssertJsonStringKey(lFileObject, 'path');
  AssertJsonStringKey(lFileObject, 'backupPath');
  AssertJsonStringKey(lFileObject, 'hash');
end;

procedure TRemoveWithNoEditAndRollbackTests.PlanModeLeavesSafeSkippedAndBlockedSourcesUnchanged;
var
  lBlockedBefore: TBytes;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSafeBefore: TBytes;
  lSafeUnitPath: string;
  lSkippedBefore: TBytes;
  lSkippedUnitPath: string;
  lBlockedUnitPath: string;
begin
  CopyFixtureToTemp('RemoveWithApplyFixture', 'remove-with-noedit-plan-safe', lDprojPath, lFixtureDir);
  lSafeUnitPath := TPath.Combine(lFixtureDir, 'ApplyUnit.pas');
  lSafeBefore := TFile.ReadAllBytes(lSafeUnitPath);
  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-noedit-plan-safe.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected plan mode on safe fixture to succeed.');
    Assert.AreEqual('ok', lRoot.Values['status'].Value, 'Expected non-apply plan status.');
    Assert.AreEqual(1, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected safe fixture to produce a plan without applying it.');
  finally
    lRoot.Free;
  end;
  AssertBytesEqual(lSafeBefore, TFile.ReadAllBytes(lSafeUnitPath), 'Plan mode must not edit safe source.');

  CopyFixtureToTemp('RemoveWithNoEditFixture', 'remove-with-noedit-plan-skipped', lDprojPath, lFixtureDir);
  lSkippedUnitPath := TPath.Combine(lFixtureDir, 'NoEditSkippedUnit.pas');
  lBlockedUnitPath := TPath.Combine(lFixtureDir, 'NoEditBlockedUnit.pas');
  lSkippedBefore := TFile.ReadAllBytes(lSkippedUnitPath);
  lBlockedBefore := TFile.ReadAllBytes(lBlockedUnitPath);
  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-noedit-plan-skipped.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected plan mode on skipped fixture to succeed.');
    Assert.AreEqual(0, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected skipped and blocked fixture to produce no safe edit.');
    Assert.AreEqual(2, (lRoot.Values['skipped'] as TJSONArray).Count,
      'Expected property selector and controlled statement skips.');
  finally
    lRoot.Free;
  end;
  AssertBytesEqual(lSkippedBefore, TFile.ReadAllBytes(lSkippedUnitPath),
    'Plan mode must not edit skipped source.');
  AssertBytesEqual(lBlockedBefore, TFile.ReadAllBytes(lBlockedUnitPath),
    'Plan mode must not edit blocked source.');
end;

procedure TRemoveWithNoEditAndRollbackTests.ApplyModeLeavesAllSkippedAndBlockedSourcesUnchanged;
var
  lBlockedBefore: TBytes;
  lBlockedUnitPath: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFiles: TJSONArray;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSkippedBefore: TBytes;
  lSkippedUnitPath: string;
  lTransaction: TJSONObject;
  lVerification: TJSONObject;
begin
  CopyFixtureToTemp('RemoveWithNoEditFixture', 'remove-with-noedit-apply', lDprojPath, lFixtureDir);
  lSkippedUnitPath := TPath.Combine(lFixtureDir, 'NoEditSkippedUnit.pas');
  lBlockedUnitPath := TPath.Combine(lFixtureDir, 'NoEditBlockedUnit.pas');
  lSkippedBefore := TFile.ReadAllBytes(lSkippedUnitPath);
  lBlockedBefore := TFile.ReadAllBytes(lBlockedUnitPath);

  lRoot := RunRemoveWithFixture(lDprojPath, 'apply', 'remove-with-noedit-apply.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected no-edit apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected no-edit apply status.');
    Assert.AreEqual(0, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected no safe edits for skipped and blocked fixture.');
    Assert.AreEqual(2, (lRoot.Values['skipped'] as TJSONArray).Count,
      'Expected skipped and blocked reports.');
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('not-run', lVerification.Values['status'].Value,
      'Expected no build verification when there are no edits.');
    AssertJsonObjectKey(lRoot, 'transaction', lTransaction);
    AssertJsonArrayKey(lTransaction, 'files', lFiles);
    Assert.AreEqual(0, lFiles.Count, 'Expected no transaction files when nothing is edited.');
  finally
    lRoot.Free;
  end;

  AssertBytesEqual(lSkippedBefore, TFile.ReadAllBytes(lSkippedUnitPath),
    'Apply mode must not edit skipped source.');
  AssertBytesEqual(lBlockedBefore, TFile.ReadAllBytes(lBlockedUnitPath),
    'Apply mode must not edit blocked source.');
end;

procedure TRemoveWithNoEditAndRollbackTests.RollbackRestoresMixedSafeAndSkippedSourcesExactly;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFiles: TJSONArray;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSafeBefore: TBytes;
  lSafeUnitPath: string;
  lSkippedBefore: TBytes;
  lSkippedUnitPath: string;
  lTransaction: TJSONObject;
  lVerification: TJSONObject;
begin
  CopyFixtureToTemp('RemoveWithRollbackFixture', 'remove-with-noedit-rollback', lDprojPath, lFixtureDir);
  lSafeUnitPath := TPath.Combine(lFixtureDir, 'RollbackUnit.pas');
  lSkippedUnitPath := TPath.Combine(lFixtureDir, 'RollbackSkippedUnit.pas');
  lSafeBefore := TFile.ReadAllBytes(lSafeUnitPath);
  lSkippedBefore := TFile.ReadAllBytes(lSkippedUnitPath);

  lRoot := RunRemoveWithFixture(lDprojPath, 'apply', 'remove-with-noedit-rollback.json', lExitCode);
  try
    Assert.AreNotEqual(Cardinal(0), lExitCode, 'Expected mixed rollback fixture to fail verification.');
    Assert.AreEqual('rolledBack', lRoot.Values['status'].Value, 'Expected rolledBack root status.');
    Assert.AreEqual(1, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected one safe edit before rollback.');
    Assert.AreEqual(1, (lRoot.Values['skipped'] as TJSONArray).Count,
      'Expected one unsafe selector to remain skipped.');
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('failed', lVerification.Values['status'].Value, 'Expected failed build verification.');
    AssertJsonObjectKey(lRoot, 'transaction', lTransaction);
    AssertJsonArrayKey(lTransaction, 'files', lFiles);
    AssertTransactionFileStatus(lFiles, 'restored');
  finally
    lRoot.Free;
  end;

  AssertBytesEqual(lSafeBefore, TFile.ReadAllBytes(lSafeUnitPath),
    'Rollback must restore edited source exactly.');
  AssertBytesEqual(lSkippedBefore, TFile.ReadAllBytes(lSkippedUnitPath),
    'Rollback must leave skipped source unchanged.');
end;

function TRemoveWithScopedDeclarationSafetyTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithScopedDeclarationSafetyTests.AssertBytesEqual(const aExpected, aActual: TBytes;
  const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aExpected), Length(aActual), aMessage + ' Size differs.');
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], aActual[i], aMessage + ' Byte differs at index ' + i.ToString + '.');
end;

procedure TRemoveWithScopedDeclarationSafetyTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
  out aDprojPath, aFixtureDir: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aFixtureDir := lDestinationDir;
end;

function TRemoveWithScopedDeclarationSafetyTests.CountSkippedReason(const aSkipped: TJSONArray;
  const aReason: string): Integer;
var
  i: Integer;
  lSkippedItem: TJSONObject;
begin
  Result := 0;
  for i := 0 to aSkipped.Count - 1 do
  begin
    lSkippedItem := aSkipped.Items[i] as TJSONObject;
    if lSkippedItem.Values['reason'].Value = aReason then
      Inc(Result);
  end;
end;

function TRemoveWithScopedDeclarationSafetyTests.RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode ' + aMode + ' --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRemoveWithScopedDeclarationSafetyTests.ApplySkipsScopedDeclarationsAndLeavesSourceUnchanged;
var
  lBefore: TBytes;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lTransaction: TJSONObject;
  lUnitPath: string;
begin
  CopyFixtureToTemp('RemoveWithScopedDeclarationFixture', 'remove-with-scoped-declarations', lDprojPath,
    lFixtureDir);
  lUnitPath := TPath.Combine(lFixtureDir, 'ScopedDeclarationUnit.pas');
  lBefore := TFile.ReadAllBytes(lUnitPath);

  lRoot := RunRemoveWithFixture(lDprojPath, 'apply', 'remove-with-scoped-declarations.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected scoped-declaration apply to finish without edits.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied root status.');
    Assert.AreEqual(0, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected no planned edits for scoped declaration bodies.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(3, lSkipped.Count, 'Expected all scoped declaration with statements to be skipped.');
    Assert.AreEqual(3, CountSkippedReason(lSkipped, 'scoped-declaration-in-with-body'),
      'Expected explicit scoped declaration skip reasons.');
    AssertJsonObjectKey(lRoot, 'transaction', lTransaction);
    Assert.AreEqual(0, (lTransaction.Values['files'] as TJSONArray).Count,
      'Expected no transaction files when all statements are skipped.');
  finally
    lRoot.Free;
  end;

  AssertBytesEqual(lBefore, TFile.ReadAllBytes(lUnitPath), 'Apply must leave scoped declaration fixture unchanged.');
end;

function TRemoveWithExpressionRoleRewriteTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithExpressionRoleRewriteTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
  out aDprojPath, aFixtureDir: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aFixtureDir := lDestinationDir;
end;

function TRemoveWithExpressionRoleRewriteTests.CountSkippedReason(const aSkipped: TJSONArray;
  const aReason: string): Integer;
var
  i: Integer;
  lSkippedItem: TJSONObject;
begin
  Result := 0;
  for i := 0 to aSkipped.Count - 1 do
  begin
    lSkippedItem := aSkipped.Items[i] as TJSONObject;
    if lSkippedItem.Values['reason'].Value = aReason then
      Inc(Result);
  end;
end;

function TRemoveWithExpressionRoleRewriteTests.CountSkippedUnsupportedRole(const aSkipped: TJSONArray;
  const aRole: string): Integer;
var
  i: Integer;
  lSkippedItem: TJSONObject;
begin
  Result := 0;
  for i := 0 to aSkipped.Count - 1 do
  begin
    lSkippedItem := aSkipped.Items[i] as TJSONObject;
    if lSkippedItem.Values['unsupportedIdentifierRole'].Value = aRole then
      Inc(Result);
  end;
end;

function TRemoveWithExpressionRoleRewriteTests.RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode ' + aMode + ' --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRemoveWithExpressionRoleRewriteTests.ApplySkipsUnsafeRolesAndRewritesSafeQualifiedCall;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lUnitPath: string;
  lUnitText: string;
  lVerification: TJSONObject;
begin
  CopyFixtureToTemp('RemoveWithExpressionRoleFixture', 'remove-with-expression-roles', lDprojPath, lFixtureDir);
  lUnitPath := TPath.Combine(lFixtureDir, 'ExpressionRoleUnit.pas');

  lRoot := RunRemoveWithFixture(lDprojPath, 'apply', 'remove-with-expression-roles.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected expression-role apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied root status.');
    Assert.AreEqual(1, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected one safe expression rewrite in a source-unit-qualified call.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(4, lSkipped.Count, 'Expected unsafe expression-role with statements to be skipped.');
    Assert.AreEqual(3, CountSkippedReason(lSkipped, 'unsupported-identifier-role'),
      'Expected explicit unsupported identifier role skip reasons.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'scoped-declaration-in-with-body'),
      'Expected declaration-like bodies to keep the scoped-declaration skip reason.');
    Assert.AreEqual(1, CountSkippedUnsupportedRole(lSkipped, 'label'),
      'Expected label role detail in skipped report.');
    Assert.AreEqual(1, CountSkippedUnsupportedRole(lSkipped, 'case-label'),
      'Expected case-label role detail in skipped report.');
    Assert.AreEqual(1, CountSkippedUnsupportedRole(lSkipped, 'type-qualifier'),
      'Expected type-qualifier role detail in skipped report.');
    Assert.AreEqual(1, CountSkippedUnsupportedRole(lSkipped, 'variable-declaration'),
      'Expected declaration-like role detail in skipped report.');
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('passed', lVerification.Values['status'].Value,
      'Expected edited expression-role fixture to build after apply.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('ExpressionRoleSupportUnit.TouchName(aItemPtr^.Name);', lUnitText) > 0,
    'Expected the safe member argument to be qualified.');
  Assert.IsTrue(Pos('aItemPtr^.ExpressionRoleSupportUnit', lUnitText) = 0,
    'Expected the source-unit qualifier to remain unchanged.');
  Assert.IsTrue(Pos('TExpressionRoleScope.DefaultName', lUnitText) > 0,
    'Expected skipped type-qualified body to remain unchanged.');
end;

function TRemoveWithComplexSourceModelTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithComplexSourceModelTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
  out aDprojPath, aFixtureDir: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aFixtureDir := lDestinationDir;
end;

function TRemoveWithComplexSourceModelTests.CountSkippedReason(const aSkipped: TJSONArray;
  const aReason: string): Integer;
var
  i: Integer;
  lSkippedItem: TJSONObject;
begin
  Result := 0;
  for i := 0 to aSkipped.Count - 1 do
  begin
    lSkippedItem := aSkipped.Items[i] as TJSONObject;
    if lSkippedItem.Values['reason'].Value = aReason then
      Inc(Result);
  end;
end;

function TRemoveWithComplexSourceModelTests.RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode ' + aMode + ' --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRemoveWithComplexSourceModelTests.PlanSkipsComplexDeclarationsWithExplicitReasons;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lPlannedEdits: TJSONArray;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
begin
  CopyFixtureToTemp('RemoveWithComplexSourceModelFixture', 'remove-with-complex-source-model', lDprojPath,
    lFixtureDir);

  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-complex-source-model-plan.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected complex source-model plan to succeed.');
    Assert.AreEqual('ok', lRoot.Values['status'].Value, 'Expected ok root status.');
    lPlannedEdits := lRoot.Values['plannedEdits'] as TJSONArray;
    Assert.AreEqual(1, lPlannedEdits.Count, 'Expected only the simple safe record to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(5, lSkipped.Count, 'Expected each complex source-model statement to be skipped.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-attribute'),
      'Expected attributed type declaration to be reported explicitly.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-conditional-region'),
      'Expected conditional type declaration to be reported explicitly.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-multiline-declaration'),
      'Expected multiline member declaration to be reported explicitly.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-generic-declaration'),
      'Expected generic type declaration to be reported explicitly.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-nested-type'),
      'Expected nested type declaration to be reported explicitly.');
  finally
    lRoot.Free;
  end;
end;

function TRemoveWithExternalRoutineTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithExternalRoutineTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
  out aDprojPath, aFixtureDir: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aFixtureDir := lDestinationDir;
end;

function TRemoveWithExternalRoutineTests.CountSkippedReason(const aSkipped: TJSONArray;
  const aReason: string): Integer;
var
  i: Integer;
  lSkippedItem: TJSONObject;
begin
  Result := 0;
  for i := 0 to aSkipped.Count - 1 do
  begin
    lSkippedItem := aSkipped.Items[i] as TJSONObject;
    if lSkippedItem.Values['reason'].Value = aReason then
      Inc(Result);
  end;
end;

function TRemoveWithExternalRoutineTests.RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode ' + aMode + ' --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRemoveWithExternalRoutineTests.ApplyPreservesKnownExternalCallsAndSkipsUnknownCalls;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lUnitPath: string;
  lUnitText: string;
  lVerification: TJSONObject;
begin
  CopyFixtureToTemp('RemoveWithExternalRoutineFixture', 'remove-with-external-routines', lDprojPath, lFixtureDir);
  lUnitPath := TPath.Combine(lFixtureDir, 'ExternalRoutineUnit.pas');

  lRoot := RunRemoveWithFixture(lDprojPath, 'apply', 'remove-with-external-routines.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected external-routine apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied external-routine status.');
    Assert.AreEqual(1, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected the known-routine with body to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(1, lSkipped.Count, 'Expected the unknown external call body to be skipped.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected unknown external calls to keep blocking the rewrite.');
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('passed', lVerification.Values['status'].Value,
      'Expected edited external-routine fixture to build after apply.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with lKnown do', lUnitText) = 0, 'Expected known-routine with to be removed.');
  Assert.IsTrue(Pos('with lUnknown do', lUnitText) > 0, 'Expected unknown-routine with to remain.');
  Assert.IsTrue(Pos('FillChar(lWithExternalRoutineRecordPtr^.Target, SizeOf(lWithExternalRoutineRecordPtr^.Target), 0);',
    lUnitText) > 0, 'Expected FillChar and SizeOf calls to remain routine calls.');
  Assert.IsTrue(Pos('Move(lWithExternalRoutineRecordPtr^.Source, lWithExternalRoutineRecordPtr^.Target, ' +
    'SizeOf(lWithExternalRoutineRecordPtr^.Target));', lUnitText) > 0,
    'Expected Move call to remain a routine call.');
  Assert.IsTrue(Pos('lWithExternalRoutineRecordPtr^.Exit', lUnitText) = 0,
    'Expected Exit statement not to be receiver-qualified.');
  Assert.IsTrue(Pos('Inc(lWithExternalRoutineRecordPtr^.Count);', lUnitText) > 0,
    'Expected Inc call to remain a routine call while its member argument is qualified.');
  Assert.IsTrue(Pos('Dec(lWithExternalRoutineRecordPtr^.Count);', lUnitText) > 0,
    'Expected Dec call to remain a routine call while its member argument is qualified.');
  Assert.IsTrue(Pos('Assigned(lWithExternalRoutineRecordPtr^.Ref)', lUnitText) > 0,
    'Expected Assigned call to remain a routine call.');
  Assert.IsTrue(Pos('Length(lWithExternalRoutineRecordPtr^.Items)', lUnitText) > 0,
    'Expected Length call to remain a routine call.');
  Assert.IsTrue(Pos('SetLength(lWithExternalRoutineRecordPtr^.Items, lWithExternalRoutineRecordPtr^.Count + 1);',
    lUnitText) > 0, 'Expected SetLength call to remain a routine call.');
  Assert.IsTrue(Pos('Low(lWithExternalRoutineRecordPtr^.Items)', lUnitText) > 0,
    'Expected Low call to remain a routine call.');
  Assert.IsTrue(Pos('High(lWithExternalRoutineRecordPtr^.Items)', lUnitText) > 0,
    'Expected High call to remain a routine call.');
  Assert.IsTrue(Pos('Include(lWithExternalRoutineRecordPtr^.Flags, lWithExternalRoutineRecordPtr^.Flag);',
    lUnitText) > 0, 'Expected Include call to remain a routine call.');
  Assert.IsTrue(Pos('Exclude(lWithExternalRoutineRecordPtr^.Flags, lWithExternalRoutineRecordPtr^.Flag);',
    lUnitText) > 0, 'Expected Exclude call to remain a routine call.');
  Assert.IsTrue(Pos('lWithExternalRoutineRecordPtr^.Inc', lUnitText) = 0,
    'Expected known routine names not to be receiver-qualified.');
end;

function TRemoveWithCorpusSmokeTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithCorpusSmokeTests.AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aExpected), Length(aActual), aMessage + ' Size differs.');
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], aActual[i], aMessage + ' Byte differs at index ' + i.ToString + '.');
end;

procedure TRemoveWithCorpusSmokeTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
  out aDprojPath, aFixtureDir: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aFixtureDir := lDestinationDir;
end;

function TRemoveWithCorpusSmokeTests.CountSkippedReason(const aSkipped: TJSONArray;
  const aReason: string): Integer;
var
  i: Integer;
  lSkippedItem: TJSONObject;
begin
  Result := 0;
  for i := 0 to aSkipped.Count - 1 do
  begin
    lSkippedItem := aSkipped.Items[i] as TJSONObject;
    if lSkippedItem.Values['reason'].Value = aReason then
      Inc(Result);
  end;
end;

function TRemoveWithCorpusSmokeTests.RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode ' + aMode + ' --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRemoveWithCorpusSmokeTests.PlanReportsStableCorpusCountsAndLeavesSourcesUnchanged;
var
  lDprBefore: TBytes;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lMainBefore: TBytes;
  lMainPath: string;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSummary: TJSONObject;
  lSupportBefore: TBytes;
  lSupportPath: string;
  lWithStatements: TJSONArray;
begin
  CopyFixtureToTemp('RemoveWithCorpusSmokeFixture', 'remove-with-corpus-smoke', lDprojPath, lFixtureDir);
  lMainPath := TPath.Combine(lFixtureDir, 'CorpusSmokeMainUnit.pas');
  lSupportPath := TPath.Combine(lFixtureDir, 'CorpusSmokeSupportUnit.pas');
  lDprBefore := TFile.ReadAllBytes(TPath.Combine(lFixtureDir, 'RemoveWithCorpusSmokeFixture.dpr'));
  lMainBefore := TFile.ReadAllBytes(lMainPath);
  lSupportBefore := TFile.ReadAllBytes(lSupportPath);

  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-corpus-smoke-plan.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected corpus plan to succeed.');
    Assert.AreEqual('ok', lRoot.Values['status'].Value, 'Expected ok root status.');
    lWithStatements := lRoot.Values['withStatements'] as TJSONArray;
    Assert.AreEqual(5, lWithStatements.Count, 'Expected stable corpus with-statement count.');
    Assert.AreEqual(1, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected only the safe multi-selector statement to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(4, lSkipped.Count, 'Expected risky corpus statements to be skipped.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-attribute'),
      'Expected attributed declaration skip.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-conditional-region'),
      'Expected conditional declaration skip.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-identifier-role'),
      'Expected type-qualified body skip.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'symbol-not-found'), 'Expected unknown call skip.');
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    Assert.AreEqual(3, (lSummary.Values['filesScanned'] as TJSONNumber).AsInt,
      'Expected the multi-unit corpus project to scan all project files.');
    Assert.AreEqual(5, (lSummary.Values['withStatements'] as TJSONNumber).AsInt,
      'Expected stable summary statement count.');
    Assert.AreEqual(1, (lSummary.Values['plannedEdits'] as TJSONNumber).AsInt,
      'Expected stable summary plan count.');
    Assert.AreEqual(4, (lSummary.Values['skipped'] as TJSONNumber).AsInt,
      'Expected stable summary skip count.');
  finally
    lRoot.Free;
  end;

  AssertBytesEqual(lDprBefore, TFile.ReadAllBytes(TPath.Combine(lFixtureDir, 'RemoveWithCorpusSmokeFixture.dpr')),
    'Plan mode must leave corpus DPR unchanged.');
  AssertBytesEqual(lMainBefore, TFile.ReadAllBytes(lMainPath), 'Plan mode must leave corpus main unit unchanged.');
  AssertBytesEqual(lSupportBefore, TFile.ReadAllBytes(lSupportPath),
    'Plan mode must leave corpus support unit unchanged.');
end;

function TRemoveWithHardeningApplyTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithHardeningApplyTests.AssertBytesEqual(const aExpected, aActual: TBytes;
  const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aExpected), Length(aActual), aMessage + ' Size differs.');
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], aActual[i], aMessage + ' Byte differs at index ' + i.ToString + '.');
end;

procedure TRemoveWithHardeningApplyTests.AssertApplySummary(const aRoot: TJSONObject;
  const aExpectedPlanned, aExpectedSkipped: Integer);
begin
  Assert.AreEqual('applied', aRoot.Values['status'].Value, 'Expected applied root status.');
  Assert.AreEqual(aExpectedPlanned, (aRoot.Values['plannedEdits'] as TJSONArray).Count,
    'Expected planned edit count.');
  Assert.AreEqual(aExpectedSkipped, (aRoot.Values['skipped'] as TJSONArray).Count, 'Expected skipped count.');
end;

procedure TRemoveWithHardeningApplyTests.AssertVerificationPassed(const aRoot: TJSONObject);
var
  lGates: TJSONArray;
  lVerification: TJSONObject;
begin
  AssertJsonObjectKey(aRoot, 'verification', lVerification);
  Assert.AreEqual('passed', lVerification.Values['status'].Value, 'Expected build verification to pass.');
  AssertJsonArrayKey(lVerification, 'gates', lGates);
  Assert.AreEqual(1, lGates.Count, 'Expected one build verification gate.');
  Assert.AreEqual('build', (lGates.Items[0] as TJSONObject).Values['name'].Value, 'Expected build gate.');
  Assert.AreEqual('passed', (lGates.Items[0] as TJSONObject).Values['status'].Value,
    'Expected passed build gate.');
  Assert.AreEqual('', (lGates.Items[0] as TJSONObject).Values['error'].Value, 'Expected empty build gate error.');
end;

procedure TRemoveWithHardeningApplyTests.AssertTransactionFileCount(const aRoot: TJSONObject;
  const aExpectedCount: Integer);
var
  lFiles: TJSONArray;
  lFileObject: TJSONObject;
  lTransaction: TJSONObject;
begin
  AssertJsonObjectKey(aRoot, 'transaction', lTransaction);
  Assert.AreEqual('applied', lTransaction.Values['status'].Value, 'Expected applied transaction status.');
  Assert.IsTrue(TFile.Exists(lTransaction.Values['manifestPath'].Value), 'Expected transaction manifest to exist.');
  AssertJsonArrayKey(lTransaction, 'files', lFiles);
  Assert.AreEqual(aExpectedCount, lFiles.Count, 'Expected transaction file count.');
  if aExpectedCount = 0 then
    Exit;

  lFileObject := lFiles.Items[0] as TJSONObject;
  Assert.AreEqual('changed', lFileObject.Values['status'].Value, 'Expected changed transaction file.');
  AssertJsonStringKey(lFileObject, 'path');
  AssertJsonStringKey(lFileObject, 'backupPath');
  Assert.IsTrue(TFile.Exists(lFileObject.Values['backupPath'].Value), 'Expected transaction backup file to exist.');
  AssertJsonStringKey(lFileObject, 'hash');
  AssertJsonNumberKey(lFileObject, 'size');
  AssertJsonStringKey(lFileObject, 'lineEnding');
  AssertJsonStringKey(lFileObject, 'encoding');
end;

procedure TRemoveWithHardeningApplyTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
  out aDprojPath, aFixtureDir: string);
var
  lDestinationDir: string;
  lFile: string;
  lRelativePath: string;
  lSourceDir: string;
  lTargetFile: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  lDestinationDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(lDestinationDir) then
    TDirectory.Delete(lDestinationDir, True);
  TDirectory.CreateDirectory(lDestinationDir);

  for lFile in TDirectory.GetFiles(lSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(lSourceDir) + 2, MaxInt);
    lTargetFile := TPath.Combine(lDestinationDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;

  aDprojPath := TPath.Combine(lDestinationDir, aFixtureName + '.dproj');
  aFixtureDir := lDestinationDir;
end;

function TRemoveWithHardeningApplyTests.CountSkippedReason(const aSkipped: TJSONArray;
  const aReason: string): Integer;
var
  i: Integer;
  lSkippedItem: TJSONObject;
begin
  Result := 0;
  for i := 0 to aSkipped.Count - 1 do
  begin
    lSkippedItem := aSkipped.Items[i] as TJSONObject;
    if lSkippedItem.Values['reason'].Value = aReason then
      Inc(Result);
  end;
end;

function TRemoveWithHardeningApplyTests.RunApplyFixture(const aDprojPath, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode apply --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with apply process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRemoveWithHardeningApplyTests.ApplyBuildsMixedHardeningFixtures;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
begin
  CopyFixtureToTemp('RemoveWithTempAggregationFixture', 'remove-with-hardening-temp-aggregation', lDprojPath,
    lFixtureDir);
  lRoot := RunApplyFixture(lDprojPath, 'remove-with-hardening-temp-aggregation.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected temp aggregation hardening apply to succeed.');
    AssertApplySummary(lRoot, 8, 0);
    AssertVerificationPassed(lRoot);
    AssertTransactionFileCount(lRoot, 1);
  finally
    lRoot.Free;
  end;

  CopyFixtureToTemp('RemoveWithExpressionRoleFixture', 'remove-with-hardening-expression-roles', lDprojPath,
    lFixtureDir);
  lRoot := RunApplyFixture(lDprojPath, 'remove-with-hardening-expression-roles.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected expression-role hardening apply to succeed.');
    AssertApplySummary(lRoot, 1, 4);
    AssertVerificationPassed(lRoot);
    AssertTransactionFileCount(lRoot, 1);
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(3, CountSkippedReason(lSkipped, 'unsupported-identifier-role'),
      'Expected expression-role unsupported skips.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'scoped-declaration-in-with-body'),
      'Expected expression-role scoped declaration skip.');
  finally
    lRoot.Free;
  end;

  CopyFixtureToTemp('RemoveWithComplexSourceModelFixture', 'remove-with-hardening-complex-source', lDprojPath,
    lFixtureDir);
  lRoot := RunApplyFixture(lDprojPath, 'remove-with-hardening-complex-source.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected complex source-model hardening apply to succeed.');
    AssertApplySummary(lRoot, 1, 5);
    AssertVerificationPassed(lRoot);
    AssertTransactionFileCount(lRoot, 1);
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-attribute'),
      'Expected attributed source-model skip.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-conditional-region'),
      'Expected conditional source-model skip.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-multiline-declaration'),
      'Expected multiline source-model skip.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-generic-declaration'),
      'Expected generic source-model skip.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-nested-type'),
      'Expected nested type source-model skip.');
  finally
    lRoot.Free;
  end;

  CopyFixtureToTemp('RemoveWithExternalRoutineFixture', 'remove-with-hardening-external-routines', lDprojPath,
    lFixtureDir);
  lRoot := RunApplyFixture(lDprojPath, 'remove-with-hardening-external-routines.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected external-routine hardening apply to succeed.');
    AssertApplySummary(lRoot, 1, 1);
    AssertVerificationPassed(lRoot);
    AssertTransactionFileCount(lRoot, 1);
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'symbol-not-found'), 'Expected unknown external call skip.');
  finally
    lRoot.Free;
  end;
end;

procedure TRemoveWithHardeningApplyTests.ApplyLeavesSkippedOnlyFixtureUnchanged;
var
  lDprBefore: TBytes;
  lBefore: TBytes;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lVerification: TJSONObject;
  lUnitPath: string;
begin
  CopyFixtureToTemp('RemoveWithScopedDeclarationFixture', 'remove-with-hardening-scoped-declarations',
    lDprojPath, lFixtureDir);
  lUnitPath := TPath.Combine(lFixtureDir, 'ScopedDeclarationUnit.pas');
  lDprBefore := TFile.ReadAllBytes(TPath.Combine(lFixtureDir, 'RemoveWithScopedDeclarationFixture.dpr'));
  lBefore := TFile.ReadAllBytes(lUnitPath);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-hardening-scoped-declarations.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected scoped declaration hardening apply to succeed.');
    AssertApplySummary(lRoot, 0, 3);
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('not-run', lVerification.Values['status'].Value,
      'Expected no build verification when no edits are planned.');
    Assert.AreEqual(0, (lVerification.Values['gates'] as TJSONArray).Count,
      'Expected no verification gates when no edits are planned.');
    AssertTransactionFileCount(lRoot, 0);
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(3, CountSkippedReason(lSkipped, 'scoped-declaration-in-with-body'),
      'Expected every scoped-declaration body to be skipped explicitly.');
  finally
    lRoot.Free;
  end;

  AssertBytesEqual(lDprBefore, TFile.ReadAllBytes(TPath.Combine(lFixtureDir, 'RemoveWithScopedDeclarationFixture.dpr')),
    'Skipped-only scoped declaration DPR must remain byte-for-byte unchanged.');
  AssertBytesEqual(lBefore, TFile.ReadAllBytes(lUnitPath),
    'Skipped-only scoped declaration fixture must remain byte-for-byte unchanged.');
end;

function TRemoveWithProprietaryProjectTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithProprietaryProjectTests.AssertBytesEqual(const aExpected, aActual: TBytes;
  const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aExpected), Length(aActual), aMessage + ' Size differs.');
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], aActual[i], aMessage + ' Byte differs at index ' + i.ToString + '.');
end;

procedure TRemoveWithProprietaryProjectTests.AssertSnapshotUnchanged(const aPaths: TArray<string>;
  const aBytes: TArray<TBytes>; const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aPaths), Length(aBytes), aMessage + ' Snapshot shape differs.');
  for i := 0 to High(aPaths) do
  begin
    Assert.IsTrue(TFile.Exists(aPaths[i]), aMessage + ' Snapshot file disappeared: ' + aPaths[i]);
    AssertBytesEqual(aBytes[i], TFile.ReadAllBytes(aPaths[i]), aMessage + ' File changed: ' + aPaths[i]);
  end;
end;

procedure TRemoveWithProprietaryProjectTests.CopyDirectoryToTemp(const aSourceDir, aTempName: string;
  out aCloneDir: string);
var
  lFile: string;
  lRelativePath: string;
  lTargetFile: string;
begin
  aCloneDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(aCloneDir) then
    TDirectory.Delete(aCloneDir, True);
  TDirectory.CreateDirectory(aCloneDir);

  for lFile in TDirectory.GetFiles(aSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(aSourceDir) + 2, MaxInt);
    if IsIgnoredProjectArtifact(lRelativePath) then
      Continue;

    lTargetFile := TPath.Combine(aCloneDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;
end;

function TRemoveWithProprietaryProjectTests.FindMaxTdbProject(const aFixtureDir: string): string;
var
  lProjectFile: string;
  lProjectFiles: TArray<string>;
  lPreferredPath: string;
begin
  lPreferredPath := TPath.Combine(TPath.Combine(aFixtureDir, 'src'), 'maxtdb.dproj');
  if TFile.Exists(lPreferredPath) then
    Exit(lPreferredPath);

  lProjectFiles := TDirectory.GetFiles(aFixtureDir, '*.dproj', TSearchOption.soAllDirectories);
  Assert.IsTrue(Length(lProjectFiles) > 0, 'Expected at least one maxTdb project file in: ' + aFixtureDir);
  for lProjectFile in lProjectFiles do
  begin
    if SameText(TPath.GetFileName(lProjectFile), 'maxtdb.dproj') then
      Exit(lProjectFile);
  end;
  Result := lProjectFiles[0];
end;

function TRemoveWithProprietaryProjectTests.IsIgnoredProjectArtifact(const aRelativePath: string): Boolean;
var
  lPath: string;
begin
  lPath := LowerCase(StringReplace(aRelativePath, '/', '\', [rfReplaceAll]));
  Result := StartsText('.dak\', lPath) or ContainsText(lPath, '\.dak\') or StartsText('.git\', lPath) or
    ContainsText(lPath, '\.git\') or StartsText('__history\', lPath) or ContainsText(lPath, '\__history\');
end;

function TRemoveWithProprietaryProjectTests.IsSourceSnapshotFile(const aPath: string): Boolean;
var
  lExt: string;
begin
  lExt := LowerCase(TPath.GetExtension(aPath));
  Result := (lExt = '.pas') or (lExt = '.dpr') or (lExt = '.dpk') or (lExt = '.inc') or (lExt = '.dfm') or
    (lExt = '.fmx') or (lExt = '.dproj') or (lExt = '.deployproj');
end;

function TRemoveWithProprietaryProjectTests.RunRemoveWithScan(const aDprojPath, aTargetDir, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --dir ' + QuoteArg(aTargetDir) +
    ' --mode scan --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with maxTdb scan process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable maxTdb remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRemoveWithProprietaryProjectTests.SnapshotSourceFiles(const aRootDir: string;
  out aPaths: TArray<string>; out aBytes: TArray<TBytes>);
var
  lCount: Integer;
  lFile: string;
  lRelativePath: string;
begin
  SetLength(aPaths, 0);
  SetLength(aBytes, 0);
  lCount := 0;
  for lFile in TDirectory.GetFiles(aRootDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(aRootDir) + 2, MaxInt);
    if IsIgnoredProjectArtifact(lRelativePath) or not IsSourceSnapshotFile(lFile) then
      Continue;

    SetLength(aPaths, lCount + 1);
    SetLength(aBytes, lCount + 1);
    aPaths[lCount] := lFile;
    aBytes[lCount] := TFile.ReadAllBytes(lFile);
    Inc(lCount);
  end;
end;

procedure TRemoveWithProprietaryProjectTests.ScanCloneOfMaxTdbWhenFixtureExists;
var
  lCloneBytes: TArray<TBytes>;
  lCloneDir: string;
  lClonePaths: TArray<string>;
  lDprojPath: string;
  lExitCode: Cardinal;
  lOriginalBytes: TArray<TBytes>;
  lOriginalPaths: TArray<string>;
  lRoot: TJSONObject;
  lSourceDir: string;
  lSummary: TJSONObject;
  lTargetDir: string;
  lWithStatements: TJSONArray;
begin
  lSourceDir := TPath.Combine(RepoRoot, 'tests\fixtures\test-projects\maxTdb');
  if not TDirectory.Exists(lSourceDir) then
  begin
    Assert.Pass('Optional proprietary maxTdb fixture is absent; no maxTdb remove-with check was run.');
    Exit;
  end;

  SnapshotSourceFiles(lSourceDir, lOriginalPaths, lOriginalBytes);
  Assert.IsTrue(Length(lOriginalPaths) > 0, 'Expected maxTdb source files to snapshot.');

  CopyDirectoryToTemp(lSourceDir, 'remove-with-maxtdb-clone', lCloneDir);
  lDprojPath := FindMaxTdbProject(lCloneDir);
  lTargetDir := TPath.Combine(lCloneDir, 'src');
  SnapshotSourceFiles(lCloneDir, lClonePaths, lCloneBytes);

  lRoot := RunRemoveWithScan(lDprojPath, lTargetDir, 'remove-with-maxtdb-scan.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected maxTdb scan mode to succeed.');
    Assert.AreEqual('ok', lRoot.Values['status'].Value, 'Expected ok maxTdb scan status.');
    Assert.AreEqual('scan', lRoot.Values['mode'].Value, 'Expected maxTdb dry-run scan mode.');
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    Assert.IsTrue((lSummary.Values['filesScanned'] as TJSONNumber).AsInt > 0,
      'Expected maxTdb scan to scan project files.');
    Assert.IsTrue((lSummary.Values['withStatements'] as TJSONNumber).AsInt > 0,
      'Expected maxTdb scan to discover with statements.');
    AssertJsonArrayKey(lRoot, 'withStatements', lWithStatements);
    Assert.IsTrue(lWithStatements.Count > 0, 'Expected concrete maxTdb with statement records.');
  finally
    lRoot.Free;
  end;

  AssertSnapshotUnchanged(lOriginalPaths, lOriginalBytes,
    'Original proprietary maxTdb fixture must never be edited.');
  AssertSnapshotUnchanged(lClonePaths, lCloneBytes, 'Scan mode must leave cloned maxTdb sources unchanged.');
end;

procedure TRemoveWithProprietaryProjectTests.SymbolInventoryResolvesMaxTdbGlobalPointerArrayWhenFixtureExists;
var
  lCloneDir: string;
  lDprojPath: string;
  lError: string;
  lInfo: TRemoveWithSelectorTypeInfo;
  lInventory: TRemoveWithSymbolInventory;
  lOptions: TAppOptions;
  lSourceDir: string;
  lSymbol: TRemoveWithSymbolInfo;
  lFoundDatFile: Boolean;
  lFoundDatFilePtr: Boolean;
  lFoundDf: Boolean;
begin
  lSourceDir := TPath.Combine(RepoRoot, 'tests\fixtures\test-projects\maxTdb');
  if not TDirectory.Exists(lSourceDir) then
  begin
    Assert.Pass('Optional proprietary maxTdb fixture is absent; no maxTdb symbol inventory check was run.');
    Exit;
  end;

  CopyDirectoryToTemp(lSourceDir, 'remove-with-maxtdb-symbols-clone', lCloneDir);
  lDprojPath := FindMaxTdbProject(lCloneDir);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Assert.IsTrue(BuildRemoveWithSymbolInventory(lOptions, lInventory, lError),
    'Expected maxTdb symbol inventory build to succeed: ' + lError);

  lFoundDatFile := False;
  lFoundDatFilePtr := False;
  lFoundDf := False;
  for lSymbol in lInventory.fSymbols do
  begin
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and SameText(lSymbol.fName, 'DatFile') then
      lFoundDatFile := True;
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and SameText(lSymbol.fName, 'DatFilePtr') and
      SameText(lSymbol.fTypeName, '^DatFile') then
      lFoundDatFilePtr := True;
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskUnitGlobal) and SameText(lSymbol.fName, 'DF') and
      SameText(lSymbol.fTypeName, 'array[1..cMaxFilesAllowed + 1] of DatFilePtr') then
      lFoundDf := True;
  end;

  Assert.IsTrue(lFoundDatFile, 'Expected maxTdb DatFile record type to be indexed.');
  Assert.IsTrue(lFoundDatFilePtr, 'Expected maxTdb DatFilePtr alias to be indexed.');
  Assert.IsTrue(lFoundDf, 'Expected maxTdb DF global pointer array to be indexed.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, '', 'DF[d]^', lInfo),
    'Expected maxTdb DF selector resolver to run.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected maxTdb DF selector status. Type=' + lInfo.fTypeName + ' Reason=' + lInfo.fReason);
  Assert.AreEqual('DatFile', lInfo.fTypeName, 'Expected maxTdb DF selector receiver type.');
end;

end.
