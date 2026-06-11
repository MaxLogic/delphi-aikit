unit Test.RemoveWith;

interface

uses
  System.IOUtils, System.JSON, System.StrUtils, System.SysUtils,
  DUnitX.TestFramework,
  Dak.RemoveWith.Discovery, Dak.RemoveWith.Expressions, Dak.RemoveWith.Model, Dak.RemoveWith.Planner,
  Dak.RemoveWith.Output, Dak.RemoveWith.Resolver, Dak.RemoveWith.SymbolMap, Dak.RemoveWith.Symbols,
  Dak.RemoveWith.TempPolicy, Dak.RemoveWith.Transaction, Dak.Types, DelphiSemantics.Api,
  DelphiSemantics.Api.RemoveWith, DelphiSemantics.Model, DelphiSemantics.WithBinding,
  Test.Support;

type
  TRemoveWithTestBase = class
  protected
    function RunRemoveWith(const aMode, aFormat, aLogName: string; out aExitCode: Cardinal): string;
    procedure AssertJsonHasKey(const aObject: TJSONObject; const aName: string);
    procedure AssertJsonMissingKey(const aObject: TJSONObject; const aName: string);
    procedure AssertJsonObjectKey(const aObject: TJSONObject; const aName: string; out aChild: TJSONObject);
    procedure AssertJsonArrayKey(const aObject: TJSONObject; const aName: string; out aChild: TJSONArray);
    procedure AssertJsonStringKey(const aObject: TJSONObject; const aName: string);
    procedure AssertJsonNumberKey(const aObject: TJSONObject; const aName: string);
    procedure AssertJsonBoolKey(const aObject: TJSONObject; const aName: string);
  end;

  [TestFixture]
  TRemoveWithCommandTests = class(TRemoveWithTestBase)
  private
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath,
      aFixtureDir: string);
    function RunSemanticCacheFixture(const aDprojPath, aCacheFileName, aLogName: string;
      out aExitCode: Cardinal): string;
  public
    [Test]
    procedure ScanModeWritesJsonShellWithoutEditingSource;
    [Test]
    procedure LegacySymbolParserIsNotCompiled;
    [Test]
    procedure RtlSourceSymbolsUseDelphiSemanticsProfile;
    [Test]
    procedure SymbolInventoryUsesDuplicateKeyIndexes;
    [Test]
    procedure ResolverUsesOwnerTypeIndex;
    [Test]
    procedure PlannerUsesOwnerTypeIndexForVisibleSelectors;
    [Test]
    procedure PlannerUsesClassificationIndex;
    [Test]
    procedure FactSetLookupsUseDelphiSemanticIndex;
    [Test]
    procedure SemanticPlanUsesSnapshotPlannerFromExistingFacts;
    [Test]
    procedure SemanticPlanChecksCompatibilityContextFingerprint;
    [Test]
    procedure DakSemanticLookupsStayDelphiSemanticOwned;
    [Test]
    procedure SemanticResolverIndexesStatementsByRange;
    [Test]
    procedure SemanticResolverBatchesSemanticClassifications;
    [Test]
    procedure ResolverIndexesLexicalParentRoutines;
    [Test]
    procedure ResolverIndexesStatementContainment;
    [Test]
    procedure ResolverIndexesSemanticBindingsByStatementRange;
    [Test]
    procedure ResolverCachesInactiveDirectiveRangesPerFile;
    [Test]
    procedure RtlSourceModelsSkipWithBinderInventoryBuild;
    [Test]
    procedure SemanticDtoParityHarnessReportsMissingFinalStatements;
    [Test]
    procedure SemanticDtoMatchesFocusedRewriteCases;
    [Test]
    procedure SemanticDtoMatchesNestedRewriteOrdering;
    [Test]
    procedure SemanticDtoMatchesInterfaceReferenceTemps;
    [Test]
    procedure SemanticDtoMatchesLocalRoutineDeclarationInsertion;
    [Test]
    procedure SemanticDtoMatchesTempPolicyFixture;
    [Test]
    procedure SemanticCacheOptionReusesAndInvalidatesUnitModels;
  end;

  [TestFixture]
  TRemoveWithReportTests = class(TRemoveWithTestBase)
  public
    [Test]
    procedure ScanJsonReportUsesStableBaseSchema;
    [Test]
    procedure PlanJsonReportUsesStableBaseSchema;
    [Test]
    procedure PlanJsonReportKeepsLegacySkippedReasonAndAddsSemanticReason;
    [Test]
    procedure PlanJsonReportIncludesPlannerPhaseMetrics;
    [Test]
    procedure PlanJsonReportIncludesSemanticDtoParity;
    [Test]
    procedure UnitPlanJsonReportScopesSemanticDtoParity;
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
    [Test]
    procedure ProjectIndexerUsesTargetPlatformDefines;
    [Test]
    procedure ResolverRunsDoNotShareOperationState;
    [Test]
    procedure PlannerRunsDoNotShareOperationState;
    [Test]
    procedure RemoveWithOperationsDoNotShareSelectorTempOrSymbolState;
  end;

  [TestFixture]
  TRemoveWithProjectModelTests = class(TRemoveWithTestBase)
  public
    [Test]
    procedure SharedProjectModelFeedsDiscoveryAndSymbolInventory;
  end;

  [TestFixture]
  TRemoveWithSymbolMapBridgeTests = class(TRemoveWithTestBase)
  private
    function UniqueTempPath(const aPrefix: string): string;
  public
    [Test]
    procedure PreparesOnceAndLooksUpCompilerProjectAndMemberSymbols;
  end;

  [TestFixture]
  TRemoveWithUnitModelExtractorTests = class(TRemoveWithTestBase)
  private
    function BuildUnitModelFixture: TRemoveWithProjectModel;
    function FindUnitModel(const aModel: TRemoveWithProjectModel; const aUnitName: string;
      out aUnitModel: TRemoveWithUnitModel): Boolean;
    function HasUse(const aUnitModel: TRemoveWithUnitModel; const aName: string): Boolean;
    function HasType(const aUnitModel: TRemoveWithUnitModel; const aName: string;
      const aKind: TRemoveWithModelTypeKind): Boolean;
    function HasMember(const aUnitModel: TRemoveWithUnitModel; const aOwnerType, aName: string;
      const aKind: TRemoveWithModelMemberKind): Boolean;
    function FindMember(const aUnitModel: TRemoveWithUnitModel; const aOwnerType, aName: string;
      const aKind: TRemoveWithModelMemberKind; out aMember: TRemoveWithModelMemberInfo): Boolean;
    function HasRoutineSymbol(const aUnitModel: TRemoveWithUnitModel; const aRoutineName, aName: string;
      const aKind: TRemoveWithModelRoutineSymbolKind): Boolean;
    function HasIdentifierReference(const aUnitModel: TRemoveWithUnitModel; const aRoutineName,
      aName: string): Boolean;
    function HasWithSelector(const aUnitModel: TRemoveWithUnitModel; const aRoutineName, aSelectorText: string;
      const aSelectorCount: Integer): Boolean;
    function MaxWithDepth(const aUnitModel: TRemoveWithUnitModel): Integer;
  public
    [Test]
    procedure AstExtractorCapturesUnitDeclarationsScopesAndWithStatements;
  end;

  [TestFixture]
  TRemoveWithSemanticBinderTests = class(TRemoveWithTestBase)
  private
    procedure BuildResolverFixture(out aInventory: TRemoveWithFactSet;
      out aScanResult: TRemoveWithScanResult);
    function CommandExePath: string;
    function FindClassification(const aResult: TRemoveWithResolverResult; const aStatementId,
      aIdentifier: string; const aStatus: TRemoveWithIdentifierStatus;
      out aClassification: TRemoveWithIdentifierClassification): Boolean;
    function RunFixtureJson(const aFixtureName, aProjectName, aLogName: string;
      out aExitCode: Cardinal): TJSONObject;
    procedure AssertClassification(const aResult: TRemoveWithResolverResult; const aStatementId,
      aIdentifier: string; const aStatus: TRemoveWithIdentifierStatus; const aReceiverText,
      aReason: string);
    procedure AssertJsonClassification(const aClassifications: TJSONArray; const aStatementId,
      aIdentifier, aStatus, aResolutionKind, aMemberKind: string);
    procedure AssertJsonSourceClassification(const aClassifications: TJSONArray; const aStatementId,
      aIdentifier, aStatus, aResolutionKind, aSourceOwnerType: string);
  public
    [Test]
    procedure BindsReceiverStackBeforeOuterScopes;
    [Test]
    procedure BindsRoutineCurrentClassAndGlobalScopes;
    [Test]
    procedure BindsHelpersInheritanceInterfacesAndOverloads;
    [Test]
    procedure PlanReportUsesSemanticProjectionForSafeSingleSelectorStatements;
    [Test]
    procedure ReportsResolvedReceiverMissingMemberPrecisely;
    [Test]
    procedure ResolverUsesSemanticBindingScopedDeclarationGate;
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
    procedure BuildSymbolFixture(out aInventory: TRemoveWithFactSet);
    function RunVerboseSymbolInventoryLog(out aExitCode: Cardinal): string;
    function CountSymbols(const aInventory: TRemoveWithFactSet; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string): Integer;
    function DescribeSymbols(const aInventory: TRemoveWithFactSet; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string): string;
    function FindSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean;
    procedure AssertSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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
    [Test]
    procedure InventoryBuildUsesProjectModelInsteadOfLineScanner;
  end;

  [TestFixture]
  TRemoveWithExpressionTypeTests = class(TRemoveWithTestBase)
  private
    procedure BuildExpressionFixture(out aInventory: TRemoveWithFactSet);
    procedure AssertSelectorInRoutine(const aInventory: TRemoveWithFactSet; const aRoutineName,
      aSelectorText: string; const aStatus: TRemoveWithSelectorTypeStatus; const aTypeName, aReason: string;
      const aAddressable: Boolean);
    procedure AssertSelector(const aInventory: TRemoveWithFactSet; const aSelectorText: string;
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
    procedure BuildSourceModelFixture(out aInventory: TRemoveWithFactSet);
    function DescribeSymbols(const aInventory: TRemoveWithFactSet): string;
    function CountSymbols(const aInventory: TRemoveWithFactSet; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string): Integer;
    function FindSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean;
    procedure AssertSelector(const aInventory: TRemoveWithFactSet; const aSelectorText,
      aTypeName: string);
    procedure AssertSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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
    procedure BuildAncestorHelperFixture(out aInventory: TRemoveWithFactSet);
    function FindSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean;
    procedure AssertSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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
    procedure BuildAncestorHelperFixture(out aInventory: TRemoveWithFactSet);
    function FindSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
      const aKind: TRemoveWithSymbolKind; const aOwnerType, aSourceOwnerType: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean;
    procedure AssertSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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
    procedure BuildResolverFixture(out aInventory: TRemoveWithFactSet;
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
    procedure ClassifiesCompilerRoutineCallsInsideResolvedReceiverStack;
    [Test]
    procedure ResolvesDependentSelectorBeforeLocalShadow;
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
    procedure BuildIndexedPropertyFixture(out aInventory: TRemoveWithFactSet);
    function CommandExePath: string;
    function FindSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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
    procedure DefaultIndexedPointerPropertyDereferencesToAddressableRecord;
    [Test]
    procedure PlanReportDistinguishesIndexedVariablesAndUnsafeIndexedProperties;
  end;

  [TestFixture]
  TRemoveWithTempPolicyTests = class(TRemoveWithTestBase)
  private
    procedure BuildTempPolicyFixture(out aInventory: TRemoveWithFactSet);
    procedure AssertPolicy(const aInventory: TRemoveWithFactSet; const aSelectorText: string;
      const aStrategy: TRemoveWithTempStrategy; const aReceiverType, aQualifierText, aReason: string);
  public
    [Test]
    procedure ChoosesDirectReferenceRecordPointerAndSkipStrategies;
    [Test]
    procedure UnitLevelPureIndexedRecordSelectorUsesDirectQualification;
    [Test]
    procedure GeneratesCollisionFreeTempDeclarations;
    [Test]
    procedure ReservesGeneratedNamesAcrossSequentialPlans;
  end;

  [TestFixture]
  TRemoveWithPlannerTests = class(TRemoveWithTestBase)
  private
    procedure BuildPlannerFixture(out aInventory: TRemoveWithFactSet; out aScanResult: TRemoveWithScanResult;
      out aResolverResult: TRemoveWithResolverResult; out aPlanResult: TRemoveWithPlanResult);
    function CommandExePath: string;
    function FindPlannedStatement(const aPlanResult: TRemoveWithPlanResult; const aStatementId: string;
      out aStatement: TRemoveWithPlannedStatement): Boolean;
  public
    [Test]
    procedure PlansSafeRecordAndClassRewritesAndSkipsUnsafeSelectors;
    [Test]
    procedure SemanticFinalDtoPrimaryPlanDoesNotRequireDakResolverClassifications;
    [Test]
    procedure SemanticFinalDtoPrimaryPlanFailsWhenStatementIdCannotMap;
    [Test]
    procedure SemanticFinalDtoPrimaryPlanFailsWhenActiveConditionalStatementCannotMap;
    [Test]
    procedure PlanCliUsesCompactHighVolumeReportContract;
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
    procedure ControlledSingleStatementBeforeElseRewritesSafely;
    [Test]
    procedure MultipleSelectorsRewriteWithCompilerPrecedence;
    [Test]
    procedure NestedWithBodiesRewriteByScopeStack;
    [Test]
    procedure ControlledNestedWithStatementsRewriteInnerSafely;
    [Test]
    procedure AnonymousNestedMultiSelectorRewrites;
    [Test]
    procedure NestedSingleStatementWithRewritesBottomUp;
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
    function ByteSequenceExists(const aBytes, aNeedle: TBytes): Boolean;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName, aUnitName: string; out aDprojPath,
      aUnitPath: string);
    function FindSingleManifest(const aProjectDir, aProjectName: string): string;
    function RunApplyFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
    function RunBuildFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
  public
    [Test]
    procedure ApplyModeBacksUpManifestsEditsAndBuildsFixture;
    [Test]
    procedure ApplyModeStopsBeforeEditingWhenPreflightBuildFails;
    [Test]
    procedure ApplyModePreservesAnsiEncodedSource;
    [Test]
    procedure ApplyModeRollsBackExactBytesWhenBuildVerificationFails;
    [Test]
    procedure BuildVerificationUsesProjectScopedMutexAndTypedDiagnostics;
    [Test]
    procedure ApplyModeTextReportsTransactionStatus;
  end;

  [TestFixture]
  TRemoveWithApplyCompileGateTests = class(TRemoveWithTestBase)
  private
    procedure AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName, aUnitName: string; out aDprojPath,
      aUnitPath: string);
    procedure BuildPlanForFixture(const aDprojPath: string; out aOptions: TAppOptions;
      out aPlanResult: TRemoveWithPlanResult; out aApplyContext: TRemoveWithPlanApplyContext);
  public
    [Test]
    procedure ApplyRefusesWhenPlannedSourceFingerprintIsStale;
    [Test]
    procedure ApplyRefusesPlannedEditsWhenContextFingerprintIsMissing;
    [Test]
    procedure LegacyApplyOverloadRefusesPlannedEditsWithoutContext;
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
    function RunBuildFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure ApplyRewritesSafeScopedDeclarationBodies;
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
  TRemoveWithIntrinsicSymbolTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertClassification(const aClassifications: TJSONArray; const aIdentifier, aStatus,
      aResolutionKind, aReason: string);
    procedure AssertClassificationSymbolMap(const aClassifications: TJSONArray; const aIdentifier, aKind,
      aSourceKind: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanPreservesModeledIntrinsicsAndBlocksUnknownCalls;
  end;

  [TestFixture]
  TRemoveWithControlCharacterLiteralTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertNoClassification(const aClassifications: TJSONArray; const aIdentifier: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanIgnoresControlCharacterLiteralsAndKeepsPointerSyntax;
  end;

  [TestFixture]
  TRemoveWithImplementationGlobalTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertClassification(const aClassifications: TJSONArray; const aIdentifier, aStatus,
      aResolutionKind, aReason: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanResolvesGlobalsDeclaredAfterImplementationRoutines;
  end;

  [TestFixture]
  TRemoveWithNestedRoutineScopeTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertClassification(const aClassifications: TJSONArray; const aIdentifier, aStatus,
      aResolutionKind, aReason: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanResolvesOuterRoutineSymbolsCapturedByNestedRoutine;
  end;

  [TestFixture]
  TRemoveWithEnumConstTypeAliasTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertClassification(const aClassifications: TJSONArray; const aIdentifier, aStatus,
      aResolutionKind, aReason: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanResolvesEnumConstantsTypedConstantsAndAliases;
  end;

  [TestFixture]
  TRemoveWithConditionalDirectiveTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure AssertNoClassification(const aClassifications: TJSONArray; const aIdentifier: string);
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanIgnoresInactiveConditionalBranches;
  end;

  [TestFixture]
  TRemoveWithUnresolvedReasonReportTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanReportsDetailedUnresolvedReasonBuckets;
  end;

  [TestFixture]
  TRemoveWithSymbolMapParityReportTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure PlanReportsLookupSourceCountsAndFallbackAccounting;
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
  TRemoveWithBoundRewriteTests = class(TRemoveWithTestBase)
  private
    function CommandExePath: string;
    procedure CopyFixtureToTemp(const aFixtureName, aTempName: string; out aDprojPath, aFixtureDir: string);
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    function RunApplyFixture(const aDprojPath, aLogName: string; out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure ApplyUsesBoundReferencesAndLeavesNonReferencesUnqualified;
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
    procedure ApplyRewritesScopedDeclarationFixture;
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
    function RunRemoveWithPlan(const aDprojPath, aTargetDir, aLogName: string; out aExitCode: Cardinal): TJSONObject;
    function RunRemoveWithScan(const aDprojPath, aTargetDir, aLogName: string; out aExitCode: Cardinal): TJSONObject;
    function CountSkippedReason(const aSkipped: TJSONArray; const aReason: string): Integer;
    procedure AssertSkippedReasonBetween(const aSkipped: TJSONArray; const aReason: string; const aMin,
      aMax: Integer);
    procedure SnapshotSourceFiles(const aRootDir: string; out aPaths: TArray<string>;
      out aBytes: TArray<TBytes>);
  public
    [Test]
    procedure PlanCloneOfMaxTdbWhenFixtureExistsReportsTelemetryAndPerformance;
    [Test]
    procedure ScanCloneOfMaxTdbWhenFixtureExists;
    [Test]
    procedure SymbolInventoryResolvesMaxTdbGlobalPointerArrayWhenFixtureExists;
  end;

implementation

uses
  System.Threading,
  DelphiAST, DelphiAST.Classes, DelphiAST.Consts, DelphiAST.ProjectIndexer;

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
  Assert.AreEqual(cAstParallelIterations, Integer(Length(aCounts)), aMessage + ' Iteration count mismatch.');
  for i := 0 to High(aCounts) do
    Assert.AreEqual(aExpected, aCounts[i], aMessage + ' Iteration ' + i.ToString + ' mismatch.');
end;

function JsonMetricValueFromLog(const aLogText, aName: string): Integer;
var
  lEndIndex: Integer;
  lNeedle: string;
  lStartIndex: Integer;
begin
  lNeedle := '"' + aName + '":';
  lStartIndex := Pos(lNeedle, aLogText);
  if lStartIndex = 0 then
    Exit(-1);

  Inc(lStartIndex, Length(lNeedle));
  while (lStartIndex <= Length(aLogText)) and (aLogText[lStartIndex] = ' ') do
    Inc(lStartIndex);

  lEndIndex := lStartIndex;
  while (lEndIndex <= Length(aLogText)) and CharInSet(aLogText[lEndIndex], ['0'..'9']) do
    Inc(lEndIndex);
  if lEndIndex = lStartIndex then
    Exit(-1);

  Result := StrToIntDef(Copy(aLogText, lStartIndex, lEndIndex - lStartIndex), -1);
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

procedure TRemoveWithTestBase.AssertJsonMissingKey(const aObject: TJSONObject; const aName: string);
begin
  Assert.IsNull(aObject.Values[aName], 'Expected JSON key to be absent: ' + aName);
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

procedure TRemoveWithCommandTests.LegacySymbolParserIsNotCompiled;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Symbols.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsFalse(ContainsText(lSourceText, 'DAK_LEGACY_REMOVEWITH_SYMBOL_PARSER'),
    'Legacy RemoveWith symbol parser block must be removed from DAK source.');
  Assert.IsFalse(ContainsText(lSourceText, 'ParseUnitGlobals'),
    'Legacy RemoveWith unit-global parser must be removed from DAK source.');
end;

procedure TRemoveWithCommandTests.RtlSourceSymbolsUseDelphiSemanticsProfile;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Symbols.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'TDelphiSemanticCompilerProfileBuilder.ProfileForTargetFromRtlSourceRoot'),
    'RemoveWith RTL source enrichment must route through DelphiSemantics compiler profiles.');
  Assert.IsFalse(ContainsText(lSourceText, 'AppendLightweightRtlSourceSymbols'),
    'RemoveWith must not keep a duplicate lightweight RTL source parser in DAK.');
  Assert.IsFalse(ContainsText(lSourceText, 'AddRtlSourceTypeSymbol'),
    'RemoveWith must not keep duplicate DAK RTL source type extraction helpers.');
end;

procedure TRemoveWithCommandTests.SymbolInventoryUsesDuplicateKeyIndexes;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Symbols.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'fLogicalSymbolKeys'),
    'Symbol inventory must use a keyed logical duplicate index for large semantic inventories.');
  Assert.IsTrue(ContainsText(lSourceText, 'fSymbolKeys'),
    'Symbol inventory must use a keyed duplicate index for large semantic inventories.');
  Assert.IsFalse(ContainsText(lSourceText,
    'for lSymbol in aInventory.fSymbols do' + sLineBreak + '  begin' + sLineBreak +
    '    if SameLogicalNonRoutineSymbol'),
    'Symbol inventory must not linearly scan every existing symbol before keyed duplicate checks.');
end;

procedure TRemoveWithCommandTests.ResolverUsesOwnerTypeIndex;
var
  lResolverSourceFileName: string;
  lResolverSourceText: string;
  lSymbolSourceFileName: string;
  lSymbolSourceText: string;
begin
  lResolverSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Resolver.pas');
  lResolverSourceText := TFile.ReadAllText(lResolverSourceFileName, TEncoding.UTF8);
  lSymbolSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Symbols.pas');
  lSymbolSourceText := TFile.ReadAllText(lSymbolSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSymbolSourceText,
    'fDelphiSemanticLookupIndex.FindSymbolsByOwnerType'),
    'Remove-with owner-type lookup must use the DelphiSemantics-owned index.');
  Assert.IsFalse(ContainsText(lResolverSourceText, 'GResolverSymbolsByOwnerType'),
    'Remove-with resolver must not keep a DAK-owned owner-type semantic index.');
end;

procedure TRemoveWithCommandTests.PlannerUsesOwnerTypeIndexForVisibleSelectors;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Planner.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'FindRemoveWithFactSetSymbolsByOwnerType(aInventory, lOwnerType, lSymbols)'),
    'Remove-with planner must use the DelphiSemantics-owned owner-type index for visible selector member lookups.');
  Assert.IsFalse(ContainsText(lSourceText,
    'for lSymbol in aInventory.fSymbols do' + sLineBreak + '      begin' + sLineBreak +
    '        if SameText(CanonicalSourceTypeName(aInventory, lSymbol.fOwnerType), lOwnerType)'),
    'Visible selector lookup must not scan every symbol for each identifier.');
end;

procedure TRemoveWithCommandTests.PlannerUsesClassificationIndex;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Planner.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'fClassificationsByStatement'),
    'Remove-with planner must index resolver classifications by statement id.');
  Assert.IsFalse(ContainsText(lSourceText,
    'for lClassification in aResolverResult.fClassifications do'),
    'Planner hot paths must not rescan every classification for each statement.');
end;

procedure TRemoveWithCommandTests.FactSetLookupsUseDelphiSemanticIndex;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Symbols.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'fDelphiSemanticLookupIndex.FindMembersByOwnerAndName'),
    'Remove-with member lookup must query DelphiSemantics-owned lookup indexes.');
  Assert.IsTrue(ContainsText(lSourceText, 'fDelphiSemanticLookupIndex.FindRoutineSymbol'),
    'Remove-with scope lookup must query DelphiSemantics-owned lookup indexes.');
  Assert.IsTrue(ContainsText(lSourceText, 'fDelphiSemanticLookupIndex.PointerTargetType'),
    'Remove-with pointer lookup must query DelphiSemantics-owned lookup indexes.');
  Assert.IsTrue(ContainsText(lSourceText, 'fDelphiSemanticLookupIndex.FindDeclarationOrTypeAliasByName'),
    'Remove-with declaration/type lookup must query DelphiSemantics-owned lookup indexes.');
  Assert.IsTrue(ContainsText(lSourceText, 'fDelphiSemanticLookupIndex.FindUnitOrGlobalByName'),
    'Remove-with unit/global lookup must query DelphiSemantics-owned lookup indexes.');
  Assert.IsTrue(ContainsText(lSourceText, 'fDelphiSemanticLookupIndex.FindUnitOrGlobalByPrefix'),
    'Remove-with qualified unit-prefix lookup must query DelphiSemantics-owned lookup indexes.');
  Assert.IsFalse(ContainsText(lSourceText, 'BuildRemoveWithFactSetLookupCache'),
    'DAK must not build a command-owned semantic fact lookup cache.');
  Assert.IsFalse(ContainsText(lSourceText, 'TDelphiSemanticRemoveWithLookupIndex.Build'),
    'DAK must not rebuild DelphiSemantics lookup indexes from DAK-owned symbols.');
end;

procedure TRemoveWithCommandTests.SemanticPlanUsesSnapshotPlannerFromExistingFacts;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Symbols.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'TDelphiSemanticRemoveWithApi.PlanRemoveWithSnapshot(lFacts)'),
    'DAK must build remove-with plans through the DelphiSemantics snapshot planner using existing facts.');
  Assert.IsFalse(ContainsText(lSourceText, 'TDelphiSemanticRemoveWithApi.PlanRemoveWith(lFacts)'),
    'DAK must not build remove-with plans through the legacy project-facts overload.');
  Assert.IsFalse(ContainsText(lSourceText, 'TDelphiSemanticRemoveWithApi.PlanRemoveWith(lOptions)'),
    'DAK must not open a second project session only to build the typed remove-with plan.');
end;

procedure TRemoveWithCommandTests.SemanticPlanChecksCompatibilityContextFingerprint;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Symbols.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText,
    'aInventory.fDelphiSemanticRemoveWithPlan.ContextFingerprint'),
    'DAK must compare compatibility facts and typed plan context fingerprints.');
  Assert.IsTrue(ContainsText(lSourceText, 'context fingerprint mismatch'),
    'DAK must fail loudly when compatibility facts and typed plan contexts drift.');
end;

procedure TRemoveWithCommandTests.DakSemanticLookupsStayDelphiSemanticOwned;
var
  lExpressionSourceFileName: string;
  lExpressionSourceText: string;
  lPlannerSourceFileName: string;
  lPlannerSourceText: string;
  lResolverSourceFileName: string;
  lResolverSourceText: string;
  lTempPolicySourceFileName: string;
  lTempPolicySourceText: string;
begin
  lResolverSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Resolver.pas');
  lResolverSourceText := TFile.ReadAllText(lResolverSourceFileName, TEncoding.UTF8);
  lExpressionSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Expressions.pas');
  lExpressionSourceText := TFile.ReadAllText(lExpressionSourceFileName, TEncoding.UTF8);
  lPlannerSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Planner.pas');
  lPlannerSourceText := TFile.ReadAllText(lPlannerSourceFileName, TEncoding.UTF8);
  lTempPolicySourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.TempPolicy.pas');
  lTempPolicySourceText := TFile.ReadAllText(lTempPolicySourceFileName, TEncoding.UTF8);

  Assert.IsFalse(ContainsText(lResolverSourceText, 'GResolverSymbolNameIndex'),
    'Resolver semantic name lookup must stay in DelphiSemantics, not DAK-owned indexes.');
  Assert.IsFalse(ContainsText(lResolverSourceText, 'GResolverSymbolsByOwnerType'),
    'Resolver owner-type lookup must stay in DelphiSemantics, not DAK-owned indexes.');
  Assert.IsFalse(ContainsText(lExpressionSourceText, 'GExpressionSymbolNameIndex'),
    'Expression semantic name lookup must stay in DelphiSemantics, not DAK-owned indexes.');
  Assert.IsFalse(ContainsText(lPlannerSourceText, 'GPlannerSymbolsByName'),
    'Planner semantic name lookup must stay in DelphiSemantics, not DAK-owned indexes.');
  Assert.IsFalse(ContainsText(lPlannerSourceText, 'GPlannerSymbolsByOwnerType'),
    'Planner owner-type lookup must stay in DelphiSemantics, not DAK-owned indexes.');
  Assert.IsFalse(ContainsText(lPlannerSourceText, 'BeginPlannerSymbolCache'),
    'Planner must not rebuild semantic symbol indexes in DAK.');
  Assert.IsFalse(ContainsText(lTempPolicySourceText, 'GTempPolicySymbolNameIndex'),
    'Temp-policy semantic name lookup must stay in DelphiSemantics, not DAK-owned indexes.');
  Assert.IsFalse(ContainsText(lTempPolicySourceText, 'EnsureTempPolicySymbolNameIndex'),
    'Temp-policy must not rebuild semantic symbol indexes in DAK.');
end;

procedure TRemoveWithCommandTests.SemanticResolverIndexesStatementsByRange;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Resolver.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'BuildSemanticStatementIndex'),
    'Semantic resolver must index scanned statements by file/range instead of nested scans.');
  Assert.IsFalse(ContainsText(lSourceText,
    'for lStatement in aScanResult.fWithStatements do' + sLineBreak +
    '        if SameText(TPath.GetFullPath(lStatement.fFilePath)'),
    'Semantic resolver must not rescan every statement for every semantic binding.');
end;

procedure TRemoveWithCommandTests.SemanticResolverBatchesSemanticClassifications;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Resolver.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'TList<TRemoveWithIdentifierClassification>'),
    'Semantic resolver must batch high-volume semantic classifications.');
  Assert.IsFalse(ContainsText(lSourceText,
    'SetLength(aResult.fClassifications, lIndex + 1);' + sLineBreak +
    '  aResult.fClassifications[lIndex] := lClassification;'),
    'Semantic resolver must not resize the classification array for every semantic reference.');
end;

procedure TRemoveWithCommandTests.ResolverIndexesLexicalParentRoutines;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Resolver.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'fParentRoutineByName'),
    'Resolver must cache lexical parent routine names instead of scanning all symbols per scope lookup.');
  Assert.IsFalse(ContainsText(lSourceText,
    'for lSymbol in aInventory.fSymbols do' + sLineBreak +
    '  begin' + sLineBreak +
    '    if (lSymbol.fKind <> TRemoveWithSymbolKind.rwskRoutine)'),
    'Lexical parent lookup must not rescan the full symbol set per lookup.');
end;

procedure TRemoveWithCommandTests.ResolverIndexesStatementContainment;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Resolver.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'fContainingStatementsById'),
    'Resolver must index containing with statements by statement id.');
  Assert.IsTrue(ContainsText(lSourceText, 'fNestedStatementsById'),
    'Resolver must index nested with statements by statement id.');
end;

procedure TRemoveWithCommandTests.ResolverIndexesSemanticBindingsByStatementRange;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Resolver.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'fSemanticBindingsByStatementRange'),
    'Fallback resolver must index DelphiSemantics bindings by file/start range.');
  Assert.IsTrue(ContainsText(lSourceText,
    'fSemanticBindingsByStatementRange.TryGetValue'),
    'Fallback resolver must use the binding range index instead of rescanning all semantic bindings.');
end;

procedure TRemoveWithCommandTests.ResolverCachesInactiveDirectiveRangesPerFile;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Resolver.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText,
    'lInactiveRanges := RemoveWithInactiveDirectiveRanges(lSource, aInventory.fParserDefines)'),
    'Resolver must compute inactive directive ranges once per loaded source file.');
  Assert.IsFalse(ContainsText(lSourceText,
    'RemoveWithInactiveDirectiveRanges(aSource, aInventory.fParserDefines)'),
    'Resolver must not rescan inactive directive ranges for every with statement.');
end;

procedure TRemoveWithCommandTests.RtlSourceModelsSkipWithBinderInventoryBuild;
var
  lMarker: string;
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Symbols.pas');
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);
  lMarker := 'procedure AppendDelphiSemanticRtlSourceModels';

  Assert.IsTrue(ContainsText(lSourceText, 'AppendRtlSourceModelSymbols'),
    'RTL source models must be translated directly into RemoveWith symbols.');
  Assert.IsFalse(ContainsText(Copy(lSourceText, Pos(lMarker, lSourceText), 3000),
    'TDelphiSemanticWithBinder.BuildInventory(lSemanticModel)'),
    'RTL source models must not run the full with-binder inventory builder.');
end;

function SemanticParityRange(const aRange: TRemoveWithRange): TDelphiSemanticRemoveWithSourceRange;
begin
  Result.StartLine := aRange.fStartLine;
  Result.StartColumn := aRange.fStartColumn;
  Result.EndLine := aRange.fEndLine;
  Result.EndColumn := aRange.fEndColumn;
end;

function SemanticParityEdit(const aEdit: TRemoveWithPlannedTextEdit):
  TDelphiSemanticRemoveWithPlanParityEdit;
begin
  Result := Default(TDelphiSemanticRemoveWithPlanParityEdit);
  Result.Kind := aEdit.fKind;
  Result.FileName := aEdit.fFilePath;
  Result.StatementId := aEdit.fStatementId;
  Result.Range := SemanticParityRange(aEdit.fRange);
  Result.ReplacementText := aEdit.fReplacementText;
end;

function SemanticParityStatement(const aStatement: TRemoveWithPlannedStatement):
  TDelphiSemanticRemoveWithPlanParityStatement;
var
  i: Integer;
begin
  Result := Default(TDelphiSemanticRemoveWithPlanParityStatement);
  Result.StatementId := aStatement.fStatementId;
  Result.FileName := aStatement.fFilePath;
  Result.Status := aStatement.fStatus;
  Result.Reason := aStatement.fReason;
  Result.UnsupportedIdentifierRole := aStatement.fUnsupportedIdentifierRole;
  Result.ReplacementText := aStatement.fReplacementText;
  SetLength(Result.Edits, Length(aStatement.fEdits));
  for i := 0 to High(aStatement.fEdits) do
    Result.Edits[i] := SemanticParityEdit(aStatement.fEdits[i]);
end;

function SemanticParityStatements(const aPlanResult: TRemoveWithPlanResult):
  TArray<TDelphiSemanticRemoveWithPlanParityStatement>;
var
  lIndex: Integer;
  lStatement: TRemoveWithPlannedStatement;
begin
  SetLength(Result, 0);
  for lStatement in aPlanResult.fStatements do
  begin
    lIndex := Length(Result);
    SetLength(Result, lIndex + 1);
    Result[lIndex] := SemanticParityStatement(lStatement);
  end;
end;

procedure AssertSemanticDtoMatchesFixture(const aFixtureName: string);
var
  lError: string;
  lExpectedStatements: TArray<TDelphiSemanticRemoveWithPlanParityStatement>;
  lInventory: TRemoveWithFactSet;
  lOptions: TAppOptions;
  lPlanResult: TRemoveWithPlanResult;
  lProjectModel: TRemoveWithProjectModel;
  lReport: TDelphiSemanticRemoveWithPlanParityReport;
  lResolverResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
begin
  lProjectModel := nil;
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    TPath.Combine('tests\fixtures\' + aFixtureName, aFixtureName + '.dproj'));
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lOptions.fRemoveWithAll := True;

  try
    Assert.IsTrue(BuildRemoveWithProjectModel(lOptions, lOptions.fDprojPath, lProjectModel,
      lError), 'Expected fixture project model to build: ' + aFixtureName + ' error=' + lError);
    Assert.IsTrue(DiscoverRemoveWithStatements(lOptions, lProjectModel, lScanResult, lError),
      'Expected fixture discovery to succeed: ' + aFixtureName + ' error=' + lError);
    Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lProjectModel, lInventory, lError),
      'Expected fixture inventory build to succeed: ' + aFixtureName + ' error=' + lError);
    Assert.IsTrue(ResolveRemoveWithIdentifiersFromSemanticFacts(lInventory, lScanResult,
      lResolverResult, lError),
      'Expected fixture resolver to succeed: ' + aFixtureName + ' error=' + lError);
    Assert.IsTrue(PlanRemoveWithRewrites(lInventory, lScanResult, lResolverResult,
      lInventory.fDelphiSemanticRemoveWithPlan, lPlanResult, lError),
      'Expected fixture planning to succeed: ' + aFixtureName + ' error=' + lError);

    lExpectedStatements := SemanticParityStatements(lPlanResult);
    lReport := TDelphiSemanticRemoveWithPlanParity.Compare(lInventory.fDelphiSemanticRemoveWithPlan,
      lExpectedStatements);

    Assert.AreEqual(0, lReport.MismatchCount, lReport.SummaryText);
  finally
    lProjectModel.Free;
  end;
end;

procedure TRemoveWithCommandTests.SemanticDtoParityHarnessReportsMissingFinalStatements;
var
  lError: string;
  lExpectedStatements: TArray<TDelphiSemanticRemoveWithPlanParityStatement>;
  lInventory: TRemoveWithFactSet;
  lOptions: TAppOptions;
  lPlanResult: TRemoveWithPlanResult;
  lProjectModel: TRemoveWithProjectModel;
  lReport: TDelphiSemanticRemoveWithPlanParityReport;
  lResolverResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
begin
  lProjectModel := nil;
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithPlannerFixture\RemoveWithPlannerFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lOptions.fRemoveWithAll := True;

  try
    Assert.IsTrue(BuildRemoveWithProjectModel(lOptions, lOptions.fDprojPath, lProjectModel,
      lError), 'Expected planner fixture project model build to succeed: ' + lError);
    Assert.IsTrue(DiscoverRemoveWithStatements(lOptions, lProjectModel, lScanResult, lError),
      'Expected planner fixture discovery to succeed: ' + lError);
    Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lProjectModel, lInventory, lError),
      'Expected planner fixture inventory build to succeed: ' + lError);
    Assert.IsTrue(ResolveRemoveWithIdentifiersFromSemanticFacts(lInventory, lScanResult,
      lResolverResult, lError),
      'Expected planner fixture resolver to succeed: ' + lError);
    Assert.IsTrue(PlanRemoveWithRewrites(lInventory, lScanResult, lResolverResult,
      lInventory.fDelphiSemanticRemoveWithPlan, lPlanResult, lError),
      'Expected planner fixture planning to succeed: ' + lError);

    lExpectedStatements := SemanticParityStatements(lPlanResult);
    Assert.IsTrue(Length(lExpectedStatements) > 0, 'Expected at least one DAK planned statement.');
    lInventory.fDelphiSemanticRemoveWithPlan.FinalStatements := nil;
    lReport := TDelphiSemanticRemoveWithPlanParity.Compare(lInventory.fDelphiSemanticRemoveWithPlan,
      lExpectedStatements);

    Assert.IsTrue(lReport.MismatchCount >= 2, lReport.SummaryText);
    Assert.AreEqual('missing-final-statement', lReport.Mismatches[0].Kind);
    Assert.AreEqual(lExpectedStatements[0].StatementId, lReport.Mismatches[0].StatementId);
    Assert.IsTrue(ContainsText(lReport.SummaryText, lExpectedStatements[0].StatementId),
      'Expected parity report to include statement id.');
    Assert.IsTrue(ContainsText(lReport.SummaryText, ExtractFileName(lExpectedStatements[0].FileName)),
      'Expected parity report to include file.');
    Assert.IsTrue(ContainsText(lReport.SummaryText, 'status=planned'),
      'Expected parity report to include status.');
    Assert.IsTrue(ContainsText(lReport.SummaryText, 'reason='),
      'Expected parity report to include reason.');
    Assert.IsTrue(ContainsText(lReport.SummaryText, 'edit='),
      'Expected parity report to include edit kind.');
    Assert.IsTrue(ContainsText(lReport.SummaryText, 'range='),
      'Expected parity report to include edit range.');
    Assert.IsTrue(ContainsText(lReport.SummaryText, 'excerpt='),
      'Expected parity report to include replacement text excerpt.');
  finally
    lProjectModel.Free;
  end;
end;

procedure TRemoveWithCommandTests.SemanticDtoMatchesFocusedRewriteCases;
begin
  AssertSemanticDtoMatchesFixture('RemoveWithPlannerFixture');
end;

procedure TRemoveWithCommandTests.SemanticDtoMatchesNestedRewriteOrdering;
begin
  AssertSemanticDtoMatchesFixture('RemoveWithNestedRewriteFixture');
end;

procedure TRemoveWithCommandTests.SemanticDtoMatchesInterfaceReferenceTemps;
begin
  AssertSemanticDtoMatchesFixture('RemoveWithInterfaceResolverFixture');
end;

procedure TRemoveWithCommandTests.SemanticDtoMatchesLocalRoutineDeclarationInsertion;
begin
  AssertSemanticDtoMatchesFixture('RemoveWithTempAggregationFixture');
end;

procedure TRemoveWithCommandTests.SemanticDtoMatchesTempPolicyFixture;
begin
  AssertSemanticDtoMatchesFixture('RemoveWithTempPolicyFixture');
end;

procedure TRemoveWithCommandTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
  out aDprojPath, aFixtureDir: string);
var
  lSourceDir: string;
begin
  lSourceDir := TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName);
  aFixtureDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(aFixtureDir) then
    TDirectory.Delete(aFixtureDir, True);
  TDirectory.Copy(lSourceDir, aFixtureDir);
  aDprojPath := TPath.Combine(aFixtureDir, aFixtureName + '.dproj');
end;

function TRemoveWithCommandTests.RunSemanticCacheFixture(const aDprojPath, aCacheFileName,
  aLogName: string; out aExitCode: Cardinal): string;
var
  lArgs: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --all --mode plan --format json ' +
    '--verbose true --semantic-cache ' + QuoteArg(aCacheFileName);

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start remove-with semantic cache process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

procedure TRemoveWithCommandTests.SemanticCacheOptionReusesAndInvalidatesUnitModels;
var
  lCacheFileName: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lLogText: string;
  lProjectFactsSidecar: string;
  lUnitPath: string;
begin
  CopyFixtureToTemp('SymbolMapFixture', 'remove-with-semantic-cache', lDprojPath, lFixtureDir);
  lCacheFileName := TPath.Combine(TPath.Combine(lFixtureDir, '.dak'), 'semantic-cache.sqlite3');
  lProjectFactsSidecar := lCacheFileName + '.project-facts.json';

  lLogText := RunSemanticCacheFixture(lDprojPath, lCacheFileName, 'remove-with-semantic-cache-first.log',
    lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected first semantic cache run to succeed.');
  Assert.IsTrue(TFile.Exists(lCacheFileName), 'Expected remove-with to create the semantic cache file.');
  Assert.IsFalse(TFile.Exists(lProjectFactsSidecar),
    'remove-with semantic cache must not create the obsolete project-facts JSON sidecar.');
  Assert.IsTrue(ContainsText(lLogText,
    'semantic-project-facts graph=False'),
    'Expected first run to build graph-free semantic project facts through DelphiSemantics.');
  Assert.AreEqual(0, JsonMetricValueFromLog(lLogText, 'semanticCacheHits'),
    'Expected cold semantic cache run to report zero hits.');
  Assert.IsTrue(JsonMetricValueFromLog(lLogText, 'semanticCacheMisses') > 0,
    'Expected cold semantic cache run to report misses.');
  Assert.IsFalse(ContainsText(lLogText, 'projectFactsCache'),
    'Expected cold run to omit retired project-facts cache metrics.');

  lLogText := RunSemanticCacheFixture(lDprojPath, lCacheFileName, 'remove-with-semantic-cache-second.log',
    lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected second semantic cache run to succeed.');
  Assert.IsFalse(TFile.Exists(lProjectFactsSidecar),
    'unchanged semantic-cache run must not create the obsolete project-facts JSON sidecar.');
  Assert.IsTrue(ContainsText(lLogText,
    'semantic-project-facts graph=False'),
    'Expected second run to reuse the graph-free project semantic-facts path.');
  Assert.IsTrue(JsonMetricValueFromLog(lLogText, 'semanticCacheHits') > 0,
    'Expected unchanged semantic cache run to report hits.');
  Assert.AreEqual(0, JsonMetricValueFromLog(lLogText, 'semanticCacheMisses'),
    'Expected unchanged semantic cache run to avoid misses.');
  Assert.IsFalse(ContainsText(lLogText, 'projectFactsCache'),
    'Expected unchanged run to omit retired project-facts cache metrics.');

  lUnitPath := TPath.Combine(lFixtureDir, 'SymbolMapUnit.pas');
  TFile.AppendAllText(lUnitPath, sLineBreak + '// cache invalidation probe' + sLineBreak,
    TEncoding.UTF8);
  lLogText := RunSemanticCacheFixture(lDprojPath, lCacheFileName, 'remove-with-semantic-cache-third.log',
    lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected changed-source semantic cache run to succeed.');
  Assert.IsFalse(TFile.Exists(lProjectFactsSidecar),
    'changed-source semantic-cache run must not create the obsolete project-facts JSON sidecar.');
  Assert.IsTrue(ContainsText(lLogText,
    'semantic-project-facts graph=False'),
    'Expected changed-source run to rebuild graph-free project semantic facts.');
  Assert.IsTrue(JsonMetricValueFromLog(lLogText, 'semanticCacheInvalidations') > 0,
    'Expected changed-source semantic cache run to report invalidation.');
  Assert.IsTrue(JsonMetricValueFromLog(lLogText, 'semanticCacheMisses') > 0,
    'Expected changed-source semantic cache run to rebuild stale unit facts.');
  Assert.IsFalse(ContainsText(lLogText, 'projectFactsCache'),
    'Expected changed-source run to omit retired project-facts cache metrics.');
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
    Assert.AreEqual(0, lChildArray.Count,
      'Plan reports should not repeat detailed scan statements.');
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

procedure TRemoveWithReportTests.PlanJsonReportKeepsLegacySkippedReasonAndAddsSemanticReason;
var
  lJson: TJSONValue;
  lMetrics: TRemoveWithPlannerPhaseMetrics;
  lOptions: TAppOptions;
  lPlanResult: TRemoveWithPlanResult;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSkippedItem: TJSONObject;
  lTransactionResult: TRemoveWithTransactionResult;
begin
  lOptions := Default(TAppOptions);
  lOptions.fRemoveWithMode := TRemoveWithMode.rwmPlan;
  lOptions.fRemoveWithFormat := TRemoveWithFormat.rwfJson;
  lMetrics := Default(TRemoveWithPlannerPhaseMetrics);
  lTransactionResult := Default(TRemoveWithTransactionResult);
  lPlanResult := Default(TRemoveWithPlanResult);
  SetLength(lPlanResult.fStatements, 1);
  lPlanResult.fStatements[0].fStatementId := 'with-60';
  lPlanResult.fStatements[0].fFilePath := 'deklarat.pas';
  lPlanResult.fStatements[0].fStatus := 'skipped';
  lPlanResult.fStatements[0].fReason := 'member-not-found';

  lJson := TJSONObject.ParseJSONValue(BuildRemoveWithJsonReport(lOptions,
    'maxtdb.dproj', '', 'run-id', '', '', Default(TRemoveWithScanResult),
    Default(TRemoveWithResolverResult), lPlanResult, lTransactionResult,
    lMetrics));
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected remove-with JSON report.');
    lRoot := lJson as TJSONObject;
    AssertJsonArrayKey(lRoot, 'skipped', lSkipped);
    Assert.AreEqual(1, lSkipped.Count, 'Expected one skipped statement.');
    Assert.IsTrue(lSkipped.Items[0] is TJSONObject,
      'Expected skipped statement object.');
    lSkippedItem := lSkipped.Items[0] as TJSONObject;
    Assert.AreEqual('symbol-not-found',
      lSkippedItem.GetValue<string>('reason', ''),
      'Expected legacy skipped reason to stay backward compatible.');
    Assert.AreEqual('member-not-found',
      lSkippedItem.GetValue<string>('semanticReason', ''),
      'Expected semantic DTO reason to be preserved additively.');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithReportTests.PlanJsonReportIncludesPlannerPhaseMetrics;
var
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lRoot: TJSONObject;
  lMetrics: TJSONObject;
  lResolverSubphaseMetrics: TJSONObject;
  lSubphaseMetrics: TJSONObject;
begin
  lOutput := RunRemoveWith('plan', 'json', 'remove-with-report-plan-metrics.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with plan report to succeed.');

  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected remove-with output to be a JSON object.');
    lRoot := lJson as TJSONObject;

    AssertJsonObjectKey(lRoot, 'plannerPhaseMetrics', lMetrics);
    AssertJsonNumberKey(lMetrics, 'totalMs');
    AssertJsonNumberKey(lMetrics, 'projectModelMs');
    AssertJsonNumberKey(lMetrics, 'discoveryMs');
    AssertJsonNumberKey(lMetrics, 'symbolInventoryMs');
    AssertJsonObjectKey(lMetrics, 'symbolInventorySubphaseMetrics', lSubphaseMetrics);
    AssertJsonNumberKey(lMetrics, 'semanticProjectFactsMs');
    AssertJsonNumberKey(lMetrics, 'semanticCompatibilityFactsMs');
    AssertJsonNumberKey(lMetrics, 'semanticBindingMs');
    AssertJsonNumberKey(lMetrics, 'semanticPlanDtoMs');
    AssertJsonNumberKey(lMetrics, 'dakLookupIndexMs');
    AssertJsonNumberKey(lMetrics, 'dakResolverClassifyMs');
    AssertJsonNumberKey(lMetrics, 'dakPlannerRewriteMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticModelExtractionMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticInventoryBuildMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticScopeIndexBuildMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticSelectorBindingMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticReferenceBindingMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticReceiverMemberResolveMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticLexicalResolveMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticReferenceCacheHitCount');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticReferenceCacheMissCount');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticLookupIndexBuildMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticBindingIndexBuildMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'semanticInventoryExpansionMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'rtlSourceEnrichmentMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'externalUnitSymbolsMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'externalTypeSymbolsMs');
    AssertJsonNumberKey(lSubphaseMetrics, 'problemSymbolAssemblyMs');
    AssertJsonObjectKey(lMetrics, 'resolverReportSubphaseMetrics',
      lResolverSubphaseMetrics);
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'directSemanticProjectionMs');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackDecisionMs');
    AssertJsonMissingKey(lResolverSubphaseMetrics, 'legacyFallbackResolverMs');
    AssertJsonMissingKey(lResolverSubphaseMetrics, 'legacyReceiverBuildMs');
    AssertJsonMissingKey(lResolverSubphaseMetrics, 'legacyIdentifierCollectMs');
    AssertJsonMissingKey(lResolverSubphaseMetrics, 'legacyClassifyUseMs');
    AssertJsonMissingKey(lResolverSubphaseMetrics, 'legacyEnrichmentMs');
    AssertJsonMissingKey(lResolverSubphaseMetrics, 'legacyClassifyUseCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackStatementCount');
    AssertJsonMissingKey(lResolverSubphaseMetrics, 'fallbackClassificationCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'semanticReferenceCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackScopedDeclarationCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackScopeShadowCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackMultiSelectorCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackUppercaseLexicalCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackHelperReceiverCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackInheritedMemberCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackUnsupportedReferenceCount');
    AssertJsonNumberKey(lResolverSubphaseMetrics, 'fallbackStrictNonMemberCount');
    AssertJsonNumberKey(lMetrics, 'symbolMapBridgeMs');
    AssertJsonNumberKey(lMetrics, 'resolverMs');
    AssertJsonNumberKey(lMetrics, 'plannerMs');
    AssertJsonNumberKey(lMetrics, 'outputSerializationMs');
    AssertJsonNumberKey(lMetrics, 'projectUnitCount');
    AssertJsonNumberKey(lMetrics, 'withStatementCount');
    AssertJsonNumberKey(lMetrics, 'symbolCount');
    AssertJsonNumberKey(lMetrics, 'classificationCount');
    AssertJsonNumberKey(lMetrics, 'plannedEditCount');
    AssertJsonNumberKey(lMetrics, 'skippedStatementCount');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithReportTests.PlanJsonReportIncludesSemanticDtoParity;
var
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lOutput: string;
  lParity: TJSONObject;
  lRoot: TJSONObject;
begin
  lOutput := RunRemoveWith('plan', 'json', 'remove-with-report-dto-parity.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with plan report to succeed.');

  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected remove-with output to be a JSON object.');
    lRoot := lJson as TJSONObject;

    AssertJsonObjectKey(lRoot, 'semanticDtoParity', lParity);
    AssertJsonStringKey(lParity, 'status');
    Assert.AreEqual('passed', lParity.Values['status'].Value, 'Expected semantic DTO shadow parity to pass.');
    AssertJsonNumberKey(lParity, 'mismatchCount');
    Assert.AreEqual('0', lParity.Values['mismatchCount'].Value,
      'Expected semantic DTO final statements to match current DAK plan output.');
    AssertJsonStringKey(lParity, 'summaryText');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithReportTests.UnitPlanJsonReportScopesSemanticDtoParity;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lLogPath: string;
  lOutput: string;
  lParity: TJSONObject;
  lRoot: TJSONObject;
  lUnitPath: string;
begin
  EnsureResolverBuilt;
  lDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithE2EFixture\RemoveWithE2EFixture.dproj');
  lUnitPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithE2EFixture\E2ESafeUnit.pas');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-report-unit-dto-parity.json');

  Assert.IsTrue(RunProcess(ResolverExePath, 'remove-with --project ' + QuoteArg(lDprojPath) +
    ' --unit ' + QuoteArg(lUnitPath) + ' --mode plan --format json',
    TPath.GetDirectoryName(ResolverExePath), lLogPath, lExitCode),
    'Failed to start remove-with unit plan process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with unit plan report to succeed.');

  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lJson := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected remove-with output to be a JSON object.');
    lRoot := lJson as TJSONObject;

    AssertJsonObjectKey(lRoot, 'semanticDtoParity', lParity);
    AssertJsonStringKey(lParity, 'status');
    Assert.AreEqual('passed', lParity.Values['status'].Value,
      'Expected semantic DTO parity to ignore final statements outside the unit target.');
    AssertJsonNumberKey(lParity, 'mismatchCount');
    Assert.AreEqual('0', lParity.Values['mismatchCount'].Value,
      'Expected unit-scoped semantic DTO parity to match current DAK plan output.');
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

procedure TRemoveWithAstParallelSafetyTests.ProjectIndexerUsesTargetPlatformDefines;
var
  lDprPath: string;
  lDprojPath: string;
  lError: string;
  lHasHostType: Boolean;
  lHasTargetType: Boolean;
  lModel: TRemoveWithProjectModel;
  lOptions: TAppOptions;
  lRoot: string;
  lSourceDir: string;
  lTypeInfo: TRemoveWithModelTypeInfo;
  lUnitModel: TRemoveWithUnitModel;
  lUnitPath: string;
begin
  lRoot := TPath.Combine(TempRoot, 'remove-with-target-defines');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);
  lSourceDir := TPath.Combine(lRoot, 'src');
  TDirectory.CreateDirectory(lSourceDir);
  lDprPath := TPath.Combine(lRoot, 'TargetDefineProject.dpr');
  lDprojPath := TPath.Combine(lRoot, 'TargetDefineProject.dproj');
  lUnitPath := TPath.Combine(lSourceDir, 'TargetPlatformUnit.pas');

  TFile.WriteAllText(lDprPath,
    'program TargetDefineProject;' + sLineBreak +
    'uses TargetPlatformUnit;' + sLineBreak +
    'begin' + sLineBreak +
    'end.', TEncoding.UTF8);
  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>TargetDefineProject.dpr</MainSource>' + sLineBreak +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>' + sLineBreak +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>' + sLineBreak +
    '    <DCC_UnitSearchPath>src</DCC_UnitSearchPath>' + sLineBreak +
    '    <DCC_Define>PROJECT_DEFINE</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>', TEncoding.UTF8);
  TFile.WriteAllText(lUnitPath,
    'unit TargetPlatformUnit;' + sLineBreak +
    'interface' + sLineBreak +
    'type' + sLineBreak +
    '{$IFDEF LINUX}' + sLineBreak +
    '  TTargetPlatformType = class end;' + sLineBreak +
    '{$ENDIF}' + sLineBreak +
    '{$IFDEF MSWINDOWS}' + sLineBreak +
    '  THostPlatformType = class end;' + sLineBreak +
    '{$ENDIF}' + sLineBreak +
    'implementation' + sLineBreak +
    'end.', TEncoding.UTF8);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Linux64';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lOptions.fRemoveWithAll := True;

  lModel := nil;
  Assert.IsTrue(BuildRemoveWithProjectModel(lOptions, lDprojPath, lModel, lError), lError);
  try
    Assert.IsTrue(ContainsText(lModel.Context.fParserDefines, 'LINUX'), 'LINUX');
    Assert.IsTrue(ContainsText(lModel.Context.fParserDefines, 'POSIX'), 'POSIX');
    Assert.IsTrue(ContainsText(lModel.Context.fParserDefines, 'CPUX64'), 'CPUX64');
    Assert.IsFalse(ContainsText(lModel.Context.fParserDefines, 'MSWINDOWS'), 'MSWINDOWS');
    Assert.IsFalse(piUseDefinesDefinedByCompiler in lModel.Indexer.Options,
      'Project-aware DAK indexing must not add host compiler defines.');

    lHasTargetType := False;
    lHasHostType := False;
    for lUnitModel in lModel.UnitModels do
      if SameText(lUnitModel.fUnitName, 'TargetPlatformUnit') then
      begin
        for lTypeInfo in lUnitModel.fTypes do
        begin
          if SameText(lTypeInfo.fName, 'TTargetPlatformType') then
            lHasTargetType := True;
          if SameText(lTypeInfo.fName, 'THostPlatformType') then
            lHasHostType := True;
        end;
      end;

    Assert.IsTrue(lHasTargetType, 'Expected Linux64 target branch type.');
    Assert.IsFalse(lHasHostType, 'Did not expect Windows host branch type.');
  finally
    lModel.Free;
  end;
end;

procedure TRemoveWithAstParallelSafetyTests.ResolverRunsDoNotShareOperationState;
var
  lError: string;
  lInventory: TRemoveWithFactSet;
  lModel: TRemoveWithProjectModel;
  lOptions: TAppOptions;
  lResolverSourceText: string;
  lFailedScanResult: TRemoveWithScanResult;
  lRecoveryResult: TRemoveWithResolverResult;
  lResult: TRemoveWithResolverResult;
  lRunCounts: TArray<Integer>;
  lScanResult: TRemoveWithScanResult;
begin
  lResolverSourceText := TFile.ReadAllText(TPath.Combine(RepoRoot,
    'src\Dak.RemoveWith.Resolver.pas'), TEncoding.UTF8);
  Assert.IsFalse(ContainsText(lResolverSourceText, 'GResolver'),
    'Resolver operation state must be owned by an explicit per-run context, not unit-global GResolver caches.');
  Assert.IsFalse(ContainsText(TFile.ReadAllText(TPath.Combine(RepoRoot,
    'src\Dak.RemoveWith.Expressions.pas'), TEncoding.UTF8), 'GExpressionCacheDepth'),
    'Selector type resolution entered by resolver must not use a shared operation depth counter.');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithDiscoveryFixture\RemoveWithDiscoveryFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lOptions.fRemoveWithAll := True;

  lModel := nil;
  Assert.IsTrue(BuildRemoveWithProjectModel(lOptions, lOptions.fDprojPath, lModel, lError), lError);
  try
    Assert.IsTrue(DiscoverRemoveWithStatements(lOptions, lModel, lScanResult, lError), lError);
    Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lModel, lInventory, lError), lError);
  finally
    lModel.Free;
  end;

  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lResult, lError), lError);
  Assert.IsTrue(Length(lResult.fClassifications) > 0, 'Expected serial resolver classifications.');

  lFailedScanResult := lScanResult;
  lFailedScanResult.fWithStatements := Copy(lScanResult.fWithStatements);
  lFailedScanResult.fWithStatements[0].fFilePath := TPath.Combine(TempRoot,
    'remove-with-missing-resolver-source.pas');
  Assert.IsFalse(ResolveRemoveWithIdentifiers(lInventory, lFailedScanResult, lRecoveryResult, lError),
    'Expected resolver to fail when the source file disappears.');
  Assert.IsTrue(ContainsText(lError, 'remove-with-missing-resolver-source.pas'),
    'Expected missing source path in resolver failure.');

  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lRecoveryResult, lError),
    'Expected resolver to recover after a failed independent run: ' + lError);
  Assert.AreEqual(Length(lResult.fClassifications), Length(lRecoveryResult.fClassifications),
    'A failed resolver run must not contaminate the next resolver context.');

  lRunCounts := ParallelCounts(cAstParallelIterations,
    function: Integer
    var
      lParallelError: string;
      lParallelResult: TRemoveWithResolverResult;
    begin
      Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lParallelResult,
        lParallelError), lParallelError);
      Result := Length(lParallelResult.fClassifications);
    end);
  AssertAllCounts(Length(lResult.fClassifications), lRunCounts,
    'Independent resolver runs must not share mutable resolver operation state.');
end;

procedure TRemoveWithAstParallelSafetyTests.PlannerRunsDoNotShareOperationState;
var
  lError: string;
  lFailedScanResult: TRemoveWithScanResult;
  lInventory: TRemoveWithFactSet;
  lOptions: TAppOptions;
  lPlanResult: TRemoveWithPlanResult;
  lPlannerSourceText: string;
  lRecoveryResult: TRemoveWithPlanResult;
  lResolverResult: TRemoveWithResolverResult;
  lRunCounts: TArray<Integer>;
  lScanResult: TRemoveWithScanResult;
begin
  lPlannerSourceText := TFile.ReadAllText(TPath.Combine(RepoRoot,
    'src\Dak.RemoveWith.Planner.pas'), TEncoding.UTF8);
  Assert.IsFalse(ContainsText(lPlannerSourceText, 'GPlanner'),
    'Planner operation state must be owned by an explicit per-run context, not unit-global GPlanner caches.');
  Assert.IsFalse(ContainsText(TFile.ReadAllText(TPath.Combine(RepoRoot,
    'src\Dak.RemoveWith.TempPolicy.pas'), TEncoding.UTF8), 'GTempPolicyCacheDepth'),
    'Temp-policy resolution entered by planner must not use a shared operation depth counter.');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithPlannerFixture\RemoveWithPlannerFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lOptions.fRemoveWithAll := True;

  Assert.IsTrue(DiscoverRemoveWithStatements(lOptions, lOptions.fDprojPath, lScanResult, lError),
    'Expected planner fixture discovery to succeed: ' + lError);
  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lInventory, lError),
    'Expected planner fixture inventory build to succeed: ' + lError);
  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lResolverResult, lError),
    'Expected planner fixture resolver to succeed: ' + lError);

  Assert.IsTrue(PlanRemoveWithRewrites(lInventory, lScanResult, lResolverResult, lPlanResult, lError), lError);
  Assert.IsTrue(Length(lPlanResult.fStatements) > 0, 'Expected serial planner statements.');

  lFailedScanResult := lScanResult;
  lFailedScanResult.fWithStatements := Copy(lScanResult.fWithStatements);
  lFailedScanResult.fWithStatements[0].fFilePath := TPath.Combine(TempRoot,
    'remove-with-missing-planner-source.pas');
  Assert.IsFalse(PlanRemoveWithRewrites(lInventory, lFailedScanResult, lResolverResult, lRecoveryResult,
    lError), 'Expected planner to fail when the source file disappears.');
  Assert.IsTrue(ContainsText(lError, 'remove-with-missing-planner-source.pas'),
    'Expected missing source path in planner failure.');

  Assert.IsTrue(PlanRemoveWithRewrites(lInventory, lScanResult, lResolverResult, lRecoveryResult, lError),
    'Expected planner to recover after a failed independent run: ' + lError);
  Assert.AreEqual(Length(lPlanResult.fStatements), Length(lRecoveryResult.fStatements),
    'A failed planner run must not contaminate the next planner context.');

  lRunCounts := ParallelCounts(cAstParallelIterations,
    function: Integer
    var
      lParallelError: string;
      lParallelResult: TRemoveWithPlanResult;
    begin
      Assert.IsTrue(PlanRemoveWithRewrites(lInventory, lScanResult, lResolverResult, lParallelResult,
        lParallelError), lParallelError);
      Result := Length(lParallelResult.fStatements);
    end);
  AssertAllCounts(Length(lPlanResult.fStatements), lRunCounts,
    'Independent planner runs must not share mutable planner operation state.');
end;

procedure TRemoveWithAstParallelSafetyTests.RemoveWithOperationsDoNotShareSelectorTempOrSymbolState;
var
  i: Integer;
  lBadCacheParentPath: string;
  lBadInventory: TRemoveWithFactSet;
  lBadOptions: TAppOptions;
  lError: string;
  lFailureObserved: Boolean;
  lInventory: TRemoveWithFactSet;
  lModel: TRemoveWithProjectModel;
  lModels: TArray<TRemoveWithProjectModel>;
  lOptions: TAppOptions;
  lRecoveryInventory: TRemoveWithFactSet;
  lRunCounts: TArray<Integer>;
  lRunErrors: TArray<string>;
  lSymbolsSourceText: string;
begin
  lSymbolsSourceText := TFile.ReadAllText(TPath.Combine(RepoRoot,
    'src\Dak.RemoveWith.Symbols.pas'), TEncoding.UTF8);
  Assert.IsFalse(ContainsText(lSymbolsSourceText, 'GRemoveWithSymbolKeys'),
    'Symbol inventory dedupe state must be owned by an explicit per-run context, not a unit-global dictionary.');
  Assert.IsFalse(ContainsText(lSymbolsSourceText, 'GRemoveWithLogicalSymbolKeys'),
    'Logical symbol inventory dedupe state must be owned by an explicit per-run context, not a unit-global dictionary.');
  Assert.IsFalse(ContainsText(lSymbolsSourceText, 'ProjectSemanticFactsLock'),
    'Remove-with semantic fact construction must not serialize DelphiSemantics calls through a broad global lock.');
  Assert.IsFalse(ContainsText(lSymbolsSourceText, 'TCriticalSection'),
    'Remove-with symbols must not keep a broad critical section around semantic API calls.');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithSymbolsFixture\RemoveWithSymbolsFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lOptions.fRemoveWithAll := True;

  lModel := nil;
  Assert.IsTrue(BuildRemoveWithProjectModel(lOptions, lOptions.fDprojPath, lModel, lError), lError);
  try
    Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lModel, lInventory, lError),
      'Expected serial symbol inventory to succeed: ' + lError);
    Assert.IsTrue(Length(lInventory.fSymbols) > 0, 'Expected serial symbol inventory symbols.');

    lBadOptions := lOptions;
    lBadCacheParentPath := TPath.Combine(TempRoot, 'remove-with-symbol-cache-parent-file.tmp');
    TFile.WriteAllText(lBadCacheParentPath, 'not a directory', TEncoding.UTF8);
    lBadOptions.fHasRemoveWithSemanticCachePath := True;
    lBadOptions.fRemoveWithSemanticCachePath := TPath.Combine(lBadCacheParentPath, 'unit-models.sqlite3');
    lFailureObserved := False;
    try
      lFailureObserved := not BuildRemoveWithFactSet(lBadOptions, lModel, lBadInventory, lError);
    except
      on E: Exception do
      begin
        lError := E.Message;
        lFailureObserved := True;
      end;
    end;
    Assert.IsTrue(lFailureObserved,
      'Expected invalid semantic cache path to fail inside symbol inventory before recovery.');
    Assert.IsNotEmpty(lError,
      'Expected invalid semantic cache path failure after symbol inventory context creation.');

    Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lModel, lRecoveryInventory, lError),
      'Expected symbol inventory to recover after an independent failure: ' + lError);
    Assert.AreEqual(Length(lInventory.fSymbols), Length(lRecoveryInventory.fSymbols),
      'A failed symbol inventory run must not contaminate the next inventory context.');

    SetLength(lModels, cAstParallelIterations);
    for i := 0 to High(lModels) do
      Assert.IsTrue(BuildRemoveWithProjectModel(lOptions, lOptions.fDprojPath, lModels[i], lError),
        'Expected parallel symbol inventory model ' + i.ToString + ' to build: ' + lError);

    SetLength(lRunCounts, cAstParallelIterations);
    SetLength(lRunErrors, cAstParallelIterations);
    TParallel.&For(0, cAstParallelIterations - 1,
      procedure(aIndex: Integer)
      var
        lParallelError: string;
        lParallelInventory: TRemoveWithFactSet;
      begin
        try
          if not BuildRemoveWithFactSet(lOptions, lModels[aIndex], lParallelInventory, lParallelError) then
          begin
            lRunErrors[aIndex] := lParallelError;
            Exit;
          end;
          lRunCounts[aIndex] := Length(lParallelInventory.fSymbols);
        except
          on E: Exception do
            lRunErrors[aIndex] := E.ClassName + ': ' + E.Message;
        end;
      end);
    for i := 0 to High(lRunErrors) do
      Assert.AreEqual('', lRunErrors[i], 'Parallel symbol inventory iteration ' + i.ToString + ' failed.');
    AssertAllCounts(Length(lInventory.fSymbols), lRunCounts,
      'Independent symbol inventory runs must not share mutable symbol operation state.');
  finally
    for i := 0 to High(lModels) do
      lModels[i].Free;
    lModel.Free;
  end;
end;

procedure TRemoveWithProjectModelTests.SharedProjectModelFeedsDiscoveryAndSymbolInventory;
var
  lError: string;
  lInventory: TRemoveWithFactSet;
  lSemanticBinding: TRemoveWithSemanticWithBinding;
  lModel: TRemoveWithProjectModel;
  lOptions: TAppOptions;
  lScanResult: TRemoveWithScanResult;
  lFoundBindingWithSelector: Boolean;
  lFoundInventoryWithSymbols: Boolean;
  lSymbol: TRemoveWithSymbolInfo;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithDiscoveryFixture\RemoveWithDiscoveryFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;

  lModel := nil;
  Assert.IsTrue(BuildRemoveWithProjectModel(lOptions, lOptions.fDprojPath, lModel, lError), lError);
  try
    Assert.AreEqual(1, lModel.IndexCount, 'Expected one project index during model bootstrap.');
    Assert.IsTrue(DiscoverRemoveWithStatements(lOptions, lModel, lScanResult, lError), lError);
    Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lModel, lInventory, lError), lError);

    Assert.AreEqual(1, lModel.IndexCount, 'Discovery and symbol inventory must reuse the already indexed model.');
    Assert.AreEqual(cDiscoveryFixtureWithCount, Integer(Length(lScanResult.fWithStatements)),
      'Expected discovery to read with statements from the shared model.');
    Assert.IsTrue(Length(lInventory.fSymbols) > 0, 'Expected symbol inventory to read units from the shared model.');
    Assert.IsNotEmpty(lInventory.fContextFingerprint,
      'Expected remove-with inventory to record the DelphiSemantics project context fingerprint.');
    Assert.AreEqual('remove-with', lInventory.fDelphiSemanticRemoveWithPlan.Operation,
      'Expected DAK to consume DelphiSemantics remove-with plan DTOs.');
    Assert.AreEqual(lInventory.fContextFingerprint,
      lInventory.fDelphiSemanticRemoveWithPlan.ContextFingerprint,
      'Expected semantic remove-with plan to share the project context fingerprint.');
    Assert.IsTrue(Length(lInventory.fDelphiSemanticRemoveWithPlan.RequiredVerification) > 0,
      'Expected semantic remove-with plan to declare verification requirements.');
    Assert.IsTrue(Length(lInventory.fDelphiSemanticWithBindingEntries) > 0,
      'Expected remove-with inventory to consume DelphiSemantics with bindings.');

    lFoundInventoryWithSymbols := False;
    for lSymbol in lInventory.fSymbols do
    begin
      if SameText(lSymbol.fUnitName, 'DiscoveryUnit') and SameText(lSymbol.fName, 'DiscoveryUnit') and
        (lSymbol.fKind = TRemoveWithSymbolKind.rwskUnitName) then
      begin
        lFoundInventoryWithSymbols := True;
        Break;
      end;
    end;
    Assert.IsTrue(lFoundInventoryWithSymbols,
      'Expected semantic project facts to expose inventory symbols for discovery fixture main unit.');

    lFoundBindingWithSelector := False;
    for lSemanticBinding in lInventory.fDelphiSemanticWithBindingEntries do
    begin
      Assert.IsNotEmpty(lSemanticBinding.fBinding.FileName,
        'Expected binding file name to come from DelphiSemantics.');
      Assert.IsNotEmpty(lSemanticBinding.fBinding.UnitName,
        'Expected binding unit name to come from DelphiSemantics.');
      Assert.IsNotEmpty(lSemanticBinding.fBinding.RoutineName,
        'Expected binding routine name to come from DelphiSemantics.');
      Assert.IsTrue(lSemanticBinding.fBinding.Line > 0, 'Expected binding line to be populated.');
      Assert.IsTrue(lSemanticBinding.fBinding.Column > 0, 'Expected binding column to be populated.');
      Assert.IsNotEmpty(lSemanticBinding.fBinding.Status, 'Expected binding status to be populated.');
      if Length(lSemanticBinding.fBinding.Selectors) > 0 then
      begin
        lFoundBindingWithSelector := True;
        Assert.IsNotEmpty(lSemanticBinding.fBinding.Selectors[0].SelectorText,
          'Expected selector text to be preserved for DAK adapters.');
      end;
    end;
    Assert.IsTrue(lFoundBindingWithSelector, 'Expected at least one semantic binding with selector payload.');
  finally
    lModel.Free;
  end;
end;

function TRemoveWithSymbolMapBridgeTests.UniqueTempPath(const aPrefix: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := StringReplace(StringReplace(GUIDToString(lGuid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);
  Result := TPath.Combine(TempRoot, aPrefix + '-' + lGuidText);
end;

procedure TRemoveWithSymbolMapBridgeTests.PreparesOnceAndLooksUpCompilerProjectAndMemberSymbols;
var
  lBridge: TRemoveWithSymbolMapBridge;
  lError: string;
  lLookup: TRemoveWithSymbolMapLookup;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fSymbolMapCacheRoot := UniqueTempPath('remove-with-symbol-map-bridge-cache');
  lOptions.fHasSymbolMapCacheRoot := True;

  Assert.IsTrue(PrepareRemoveWithSymbolMapBridge(lOptions, lBridge, lError),
    'Expected bridge prepare. Error: ' + lError);
  try
    Assert.IsTrue(lBridge.fPrepared, 'Expected prepared bridge.');
    Assert.AreEqual(1, lBridge.fPrepareCount, 'Expected one Symbol Map prepare/open for the bridge.');
    Assert.IsTrue(lBridge.fStatus.fProjectIndexed, 'Expected project units to be indexed once for bridge lookups.');

    Assert.IsTrue(FindRemoveWithSymbolMapDefinition(lBridge, 'SizeOf', '', lLookup, lError),
      'Expected intrinsic lookup. Error: ' + lError);
    Assert.IsTrue(lLookup.fFound, 'Expected SizeOf to be found.');
    Assert.AreEqual('routine', lLookup.fKind);
    Assert.AreEqual('compiler-intrinsic', lLookup.fSourceKind);
    Assert.AreEqual('exact', lLookup.fConfidence);

    Assert.IsTrue(FindRemoveWithSymbolMapDefinition(lBridge, 'GDeclarationGlobal', '', lLookup, lError),
      'Expected project global lookup. Error: ' + lError);
    Assert.IsTrue(lLookup.fFound, 'Expected global to be found.');
    Assert.AreEqual('var', lLookup.fKind);
    Assert.AreEqual('project', lLookup.fSourceKind);

    Assert.IsTrue(FindRemoveWithSymbolMapDefinition(lBridge, 'TDeclarationRecord', '', lLookup, lError),
      'Expected type lookup. Error: ' + lError);
    Assert.IsTrue(lLookup.fFound, 'Expected type to be found.');
    Assert.AreEqual('type', lLookup.fKind);
    Assert.AreEqual('project', lLookup.fSourceKind);

    Assert.IsTrue(FindRemoveWithSymbolMapDefinition(lBridge, 'Name', 'TMemberClass', lLookup, lError),
      'Expected member lookup. Error: ' + lError);
    Assert.IsTrue(lLookup.fFound, 'Expected member to be found.');
    Assert.AreEqual('property', lLookup.fKind);
    Assert.AreEqual('TMemberClass', lLookup.fOwnerName);
    Assert.AreEqual(1, lBridge.fPrepareCount, 'Lookups must not refresh or reopen Symbol Map.');
  finally
    FinalizeRemoveWithSymbolMapBridge(lBridge);
  end;
end;

function TRemoveWithUnitModelExtractorTests.BuildUnitModelFixture: TRemoveWithProjectModel;
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithUnitModelFixture\RemoveWithUnitModelFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  Result := nil;
  Assert.IsTrue(BuildRemoveWithProjectModel(lOptions, lOptions.fDprojPath, Result, lError), lError);
end;

function TRemoveWithUnitModelExtractorTests.FindUnitModel(const aModel: TRemoveWithProjectModel;
  const aUnitName: string; out aUnitModel: TRemoveWithUnitModel): Boolean;
var
  lUnitModel: TRemoveWithUnitModel;
begin
  Result := False;
  aUnitModel := Default(TRemoveWithUnitModel);
  for lUnitModel in aModel.UnitModels do
  begin
    if SameText(lUnitModel.fUnitName, aUnitName) then
    begin
      aUnitModel := lUnitModel;
      Exit(True);
    end;
  end;
end;

function TRemoveWithUnitModelExtractorTests.HasUse(const aUnitModel: TRemoveWithUnitModel;
  const aName: string): Boolean;
var
  lName: string;
begin
  Result := False;
  for lName in aUnitModel.fUses do
  begin
    if SameText(lName, aName) then
      Exit(True);
  end;
end;

function TRemoveWithUnitModelExtractorTests.HasType(const aUnitModel: TRemoveWithUnitModel; const aName: string;
  const aKind: TRemoveWithModelTypeKind): Boolean;
var
  lTypeInfo: TRemoveWithModelTypeInfo;
begin
  Result := False;
  for lTypeInfo in aUnitModel.fTypes do
  begin
    if SameText(lTypeInfo.fName, aName) and (lTypeInfo.fKind = aKind) then
      Exit(True);
  end;
end;

function TRemoveWithUnitModelExtractorTests.HasMember(const aUnitModel: TRemoveWithUnitModel;
  const aOwnerType, aName: string; const aKind: TRemoveWithModelMemberKind): Boolean;
var
  lMember: TRemoveWithModelMemberInfo;
begin
  Result := FindMember(aUnitModel, aOwnerType, aName, aKind, lMember);
end;

function TRemoveWithUnitModelExtractorTests.FindMember(const aUnitModel: TRemoveWithUnitModel;
  const aOwnerType, aName: string; const aKind: TRemoveWithModelMemberKind;
  out aMember: TRemoveWithModelMemberInfo): Boolean;
var
  lMember: TRemoveWithModelMemberInfo;
begin
  Result := False;
  aMember := Default(TRemoveWithModelMemberInfo);
  for lMember in aUnitModel.fMembers do
  begin
    if SameText(lMember.fOwnerType, aOwnerType) and SameText(lMember.fName, aName) and
      (lMember.fKind = aKind) then
    begin
      aMember := lMember;
      Exit(True);
    end;
  end;
end;

function TRemoveWithUnitModelExtractorTests.HasRoutineSymbol(const aUnitModel: TRemoveWithUnitModel;
  const aRoutineName, aName: string; const aKind: TRemoveWithModelRoutineSymbolKind): Boolean;
var
  lSymbol: TRemoveWithModelRoutineSymbolInfo;
begin
  Result := False;
  for lSymbol in aUnitModel.fRoutineSymbols do
  begin
    if SameText(lSymbol.fRoutineName, aRoutineName) and SameText(lSymbol.fName, aName) and
      (lSymbol.fKind = aKind) then
      Exit(True);
  end;
end;

function TRemoveWithUnitModelExtractorTests.HasIdentifierReference(const aUnitModel: TRemoveWithUnitModel;
  const aRoutineName, aName: string): Boolean;
var
  lReference: TRemoveWithModelIdentifierReference;
begin
  Result := False;
  for lReference in aUnitModel.fIdentifierReferences do
  begin
    if SameText(lReference.fRoutineName, aRoutineName) and SameText(lReference.fName, aName) then
      Exit(True);
  end;
end;

function TRemoveWithUnitModelExtractorTests.HasWithSelector(const aUnitModel: TRemoveWithUnitModel;
  const aRoutineName, aSelectorText: string; const aSelectorCount: Integer): Boolean;
var
  lStatement: TRemoveWithModelWithStatementInfo;
begin
  Result := False;
  for lStatement in aUnitModel.fWithStatements do
  begin
    if SameText(lStatement.fRoutineName, aRoutineName) and SameText(lStatement.fSelectorText, aSelectorText) and
      (lStatement.fSelectorCount = aSelectorCount) then
      Exit(True);
  end;
end;

function TRemoveWithUnitModelExtractorTests.MaxWithDepth(const aUnitModel: TRemoveWithUnitModel): Integer;
var
  lStatement: TRemoveWithModelWithStatementInfo;
begin
  Result := 0;
  for lStatement in aUnitModel.fWithStatements do
  begin
    if lStatement.fNestingDepth > Result then
      Result := lStatement.fNestingDepth;
  end;
end;

procedure TRemoveWithUnitModelExtractorTests.AstExtractorCapturesUnitDeclarationsScopesAndWithStatements;
var
  lMember: TRemoveWithModelMemberInfo;
  lModel: TRemoveWithProjectModel;
  lUnitModel: TRemoveWithUnitModel;
begin
  lModel := BuildUnitModelFixture;
  try
    Assert.IsTrue(FindUnitModel(lModel, 'UnitModelMain', lUnitModel), 'Expected UnitModelMain model.');
    Assert.IsTrue(HasUse(lUnitModel, 'System.SysUtils'), 'Expected uses clause extraction.');

    Assert.IsTrue(HasType(lUnitModel, 'IUnitModelFace', TRemoveWithModelTypeKind.rwmtInterface),
      'Expected interface type.');
    Assert.IsTrue(HasType(lUnitModel, 'TUnitModelAlias', TRemoveWithModelTypeKind.rwmtAlias),
      'Expected alias type.');
    Assert.IsTrue(HasType(lUnitModel, 'TUnitModelMultilineRecord', TRemoveWithModelTypeKind.rwmtRecord),
      'Expected multiline record type.');
    Assert.IsTrue(HasType(lUnitModel, 'TUnitModelRecord', TRemoveWithModelTypeKind.rwmtRecord),
      'Expected record type.');
    Assert.IsTrue(HasType(lUnitModel, 'PUnitModelRecord', TRemoveWithModelTypeKind.rwmtAlias),
      'Expected pointer alias type.');
    Assert.IsTrue(HasType(lUnitModel, 'TUnitModelClass', TRemoveWithModelTypeKind.rwmtClass),
      'Expected class type.');
    Assert.IsTrue(HasType(lUnitModel, 'TUnitModelRecordHelper', TRemoveWithModelTypeKind.rwmtHelper),
      'Expected record helper type.');

    Assert.IsTrue(HasMember(lUnitModel, 'TUnitModelRecord', 'FieldName', TRemoveWithModelMemberKind.rwmmField),
      'Expected record field.');
    Assert.IsTrue(HasMember(lUnitModel, 'TUnitModelRecord', 'Caption', TRemoveWithModelMemberKind.rwmmProperty),
      'Expected record property.');
    Assert.IsTrue(HasMember(lUnitModel, 'TUnitModelClass', 'DefaultSize', TRemoveWithModelMemberKind.rwmmConstant),
      'Expected class constant.');
    Assert.IsTrue(HasMember(lUnitModel, 'TUnitModelClass', 'Shared', TRemoveWithModelMemberKind.rwmmClassVar),
      'Expected class var.');
    Assert.IsTrue(HasMember(lUnitModel, 'TUnitModelClass', 'Items', TRemoveWithModelMemberKind.rwmmProperty),
      'Expected indexed property.');
    Assert.IsTrue(FindMember(lUnitModel, 'TUnitModelClass', 'Items', TRemoveWithModelMemberKind.rwmmProperty,
      lMember), 'Expected indexed default Items property.');
    Assert.IsTrue(lMember.fIsIndexed, 'Expected Items to be marked indexed.');
    Assert.IsTrue(lMember.fIsDefault, 'Expected Items to be marked default.');
    Assert.AreEqual(1, lMember.fIndexParameterCount, 'Expected Items index parameter count.');
    Assert.IsTrue(HasMember(lUnitModel, 'TUnitModelRecordHelper', 'HelperText',
      TRemoveWithModelMemberKind.rwmmMethod));

    Assert.IsTrue(HasRoutineSymbol(lUnitModel, 'TUnitModelScope.Run', 'aParam',
      TRemoveWithModelRoutineSymbolKind.rwmrsParameter));
    Assert.IsTrue(HasRoutineSymbol(lUnitModel, 'TUnitModelScope.Run', 'lRecord',
      TRemoveWithModelRoutineSymbolKind.rwmrsLocal));
    Assert.IsTrue(HasRoutineSymbol(lUnitModel, 'TUnitModelScope.Run', 'lInline',
      TRemoveWithModelRoutineSymbolKind.rwmrsInlineLocal));

    Assert.AreEqual(4, Integer(Length(lUnitModel.fWithStatements)), 'Expected multiple and nested with statements.');
    Assert.AreEqual(2, MaxWithDepth(lUnitModel), 'Expected three-level nested with depth.');
    Assert.IsTrue(HasWithSelector(lUnitModel, 'TUnitModelScope.Run', 'lRecord, lClass', 2),
      'Expected multi-line selector text/count extraction.');
    Assert.IsTrue(Length(lUnitModel.fIdentifierReferences) > 0, 'Expected identifier references from routine bodies.');
    Assert.IsTrue(HasIdentifierReference(lUnitModel, 'TUnitModelScope.Run', 'FieldName'),
      'Expected FieldName identifier reference.');
  finally
    lModel.Free;
  end;
end;

function TRemoveWithSemanticBinderTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithSemanticBinderTests.BuildResolverFixture(out aInventory: TRemoveWithFactSet;
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
    'Expected resolver fixture inventory build to succeed: ' + lError);
  Assert.IsTrue(DiscoverRemoveWithStatements(lOptions, lOptions.fDprojPath, aScanResult, lError),
    'Expected resolver fixture discovery to succeed: ' + lError);
end;

function TRemoveWithSemanticBinderTests.RunFixtureJson(const aFixtureName, aProjectName,
  aLogName: string; out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lDprojPath := TPath.Combine(TPath.Combine(TPath.Combine(RepoRoot, 'tests\fixtures'), aFixtureName),
    aProjectName + '.dproj');
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode plan --format json';

  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start semantic binder fixture process.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

function TRemoveWithSemanticBinderTests.FindClassification(const aResult: TRemoveWithResolverResult;
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

procedure TRemoveWithSemanticBinderTests.AssertClassification(const aResult: TRemoveWithResolverResult;
  const aStatementId, aIdentifier: string; const aStatus: TRemoveWithIdentifierStatus; const aReceiverText,
  aReason: string);
var
  lClassification: TRemoveWithIdentifierClassification;
begin
  Assert.IsTrue(FindClassification(aResult, aStatementId, aIdentifier, aStatus, lClassification),
    'Expected semantic binder classification ' + aStatementId + ':' + aIdentifier + ':' +
    RemoveWithIdentifierStatusToText(aStatus));
  Assert.AreEqual(aReceiverText, lClassification.fReceiverText, 'Unexpected receiver for ' + aIdentifier);
  Assert.AreEqual(aReason, lClassification.fReason, 'Unexpected reason for ' + aIdentifier);
  Assert.AreNotEqual(0, lClassification.fLine, 'Expected source line for ' + aIdentifier);
  Assert.AreNotEqual(0, lClassification.fColumn, 'Expected source column for ' + aIdentifier);
end;

procedure TRemoveWithSemanticBinderTests.AssertJsonClassification(const aClassifications: TJSONArray;
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
  Assert.Fail('Expected semantic binder JSON classification ' + aStatementId + ':' + aIdentifier + ':' +
    aStatus + ':' + aResolutionKind + ':' + aMemberKind);
end;

procedure TRemoveWithSemanticBinderTests.AssertJsonSourceClassification(const aClassifications: TJSONArray;
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
  Assert.Fail('Expected semantic binder source classification ' + aStatementId + ':' + aIdentifier + ':' +
    aStatus + ':' + aResolutionKind + ':' + aSourceOwnerType);
end;

procedure TRemoveWithSemanticBinderTests.BindsReceiverStackBeforeOuterScopes;
var
  lError: string;
  lInventory: TRemoveWithFactSet;
  lResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
begin
  BuildResolverFixture(lInventory, lScanResult);

  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lResult, lError),
    'Expected resolver to succeed: ' + lError);

  AssertClassification(lResult, 'with-1', 'Name', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
  AssertClassification(lResult, 'with-1', 'Pick', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
  AssertClassification(lResult, 'with-1', 'lLocalOnly', TRemoveWithIdentifierStatus.rwisUnchanged, '',
    'routine-scope');
  AssertClassification(lResult, 'with-2', 'Shared', TRemoveWithIdentifierStatus.rwisResolved, 'lAddress', '');
  AssertClassification(lResult, 'with-2', 'Name', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
  AssertClassification(lResult, 'with-4', 'City', TRemoveWithIdentifierStatus.rwisResolved, 'Address', '');
  AssertClassification(lResult, 'with-6', 'City', TRemoveWithIdentifierStatus.rwisUnsupported, 'AddressProp',
    'property-selector');
end;

procedure TRemoveWithSemanticBinderTests.BindsRoutineCurrentClassAndGlobalScopes;
var
  lClassifications: TJSONArray;
  lExitCode: Cardinal;
  lRoot: TJSONObject;
  lResolver: TJSONObject;
begin
  lRoot := RunFixtureJson('RemoveWithGlobalScopeFixture', 'RemoveWithGlobalScopeFixture',
    'remove-with-semantic-binder-global-scope.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected global scope binder fixture to succeed.');
    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);

    AssertJsonClassification(lClassifications, 'with-1', 'Marker', 'resolved', 'direct', 'field');
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
  finally
    lRoot.Free;
  end;
end;

procedure TRemoveWithSemanticBinderTests.BindsHelpersInheritanceInterfacesAndOverloads;
var
  lClassifications: TJSONArray;
  lExitCode: Cardinal;
  lRoot: TJSONObject;
  lResolver: TJSONObject;
begin
  lRoot := RunFixtureJson('RemoveWithHelperPrecedenceFixture', 'RemoveWithHelperPrecedenceFixture',
    'remove-with-semantic-binder-helper.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected helper binder fixture to succeed.');
    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    AssertJsonSourceClassification(lClassifications, 'with-2', 'Normalize', 'resolved', 'helper',
      'THelperOnlyRecordHelper');
    AssertJsonSourceClassification(lClassifications, 'with-2', 'HelperValue', 'resolved', 'helper',
      'THelperOnlyRecordHelper');
    AssertJsonClassification(lClassifications, 'with-3', 'Clash', 'resolved', 'direct', 'method');
  finally
    lRoot.Free;
  end;

  lRoot := RunFixtureJson('RemoveWithInheritedOverrideFixture', 'RemoveWithInheritedOverrideFixture',
    'remove-with-semantic-binder-inherited.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected inherited binder fixture to succeed.');
    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
  finally
    lRoot.Free;
  end;

  lRoot := RunFixtureJson('RemoveWithInterfaceResolverFixture', 'RemoveWithInterfaceResolverFixture',
    'remove-with-semantic-binder-interface.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected interface binder fixture to succeed.');
    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    AssertJsonSourceClassification(lClassifications, 'with-1', 'ChildTouch', 'resolved', 'direct', '');
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
  finally
    lRoot.Free;
  end;
end;

procedure TRemoveWithSemanticBinderTests.PlanReportUsesSemanticProjectionForSafeSingleSelectorStatements;
var
  lClassifications: TJSONArray;
  lExitCode: Cardinal;
  lMetrics: TJSONObject;
  lResolver: TJSONObject;
  lResolverSubphaseMetrics: TJSONObject;
  lRoot: TJSONObject;
  lSummary: TJSONObject;
begin
  lRoot := RunFixtureJson('RemoveWithE2EFixture', 'RemoveWithE2EFixture',
    'remove-with-semantic-report-projection.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected resolver fixture plan to succeed.');
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    AssertJsonObjectKey(lRoot, 'plannerPhaseMetrics', lMetrics);
    AssertJsonObjectKey(lMetrics, 'resolverReportSubphaseMetrics',
      lResolverSubphaseMetrics);

    AssertJsonClassification(lClassifications, 'with-2', 'Name', 'resolved', 'direct',
      'field');
    Assert.IsTrue(lResolverSubphaseMetrics.GetValue<Integer>('semanticReferenceCount') > 0,
      'Expected plan report to project safe semantic references directly.');
    Assert.IsTrue(lResolverSubphaseMetrics.GetValue<Integer>('fallbackStatementCount') <
      lSummary.GetValue<Integer>('withStatements'),
      'Expected plan report fallback to be limited to statements that need legacy analysis.');
  finally
    lRoot.Free;
  end;
end;

procedure TRemoveWithSemanticBinderTests.ReportsResolvedReceiverMissingMemberPrecisely;
var
  lError: string;
  lInventory: TRemoveWithFactSet;
  lResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
begin
  BuildResolverFixture(lInventory, lScanResult);

  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lResult, lError),
    'Expected resolver to succeed: ' + lError);

  AssertClassification(lResult, 'with-9', 'MissingMember', TRemoveWithIdentifierStatus.rwisUnresolved, 'lCustomer',
    'receiver-member-not-found');
  AssertClassification(lResult, 'with-9', 'UnknownProcedure', TRemoveWithIdentifierStatus.rwisUnresolved, '',
    'symbol-not-found');
end;

procedure TRemoveWithSemanticBinderTests.ResolverUsesSemanticBindingScopedDeclarationGate;
var
  lBinding: TDelphiSemanticWithBinding;
  lDirectResult: TRemoveWithResolverResult;
  lError: string;
  lEntry: TRemoveWithSemanticWithBinding;
  lFoundScopedBinding: Boolean;
  lDirectInventory: TRemoveWithFactSet;
  lInventory: TRemoveWithFactSet;
  lMismatchedInventory: TRemoveWithFactSet;
  lMismatchedResult: TRemoveWithResolverResult;
  lOptions: TAppOptions;
  lResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
  lScopedColumn: Integer;
  lScopedLine: Integer;
  lStatement: TRemoveWithStatementInfo;
  lStatementIndex: Integer;
  i: Integer;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithScopedDeclarationFixture\RemoveWithScopedDeclarationFixture.dproj');
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lOptions.fRemoveWithAll := True;

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lInventory, lError),
    'Expected scoped-declaration fixture inventory build to succeed: ' + lError);
  Assert.IsTrue(DiscoverRemoveWithStatements(lOptions, lOptions.fDprojPath, lScanResult, lError),
    'Expected scoped-declaration fixture discovery to succeed: ' + lError);

  lFoundScopedBinding := False;
  lScopedColumn := 0;
  lScopedLine := 0;
  for lEntry in lInventory.fDelphiSemanticWithBindingEntries do
  begin
    lBinding := lEntry.fBinding;
    if lBinding.HasScopedDeclaration then
    begin
      lFoundScopedBinding := True;
      Assert.IsTrue(SameText(TPath.GetFullPath(lEntry.fFilePath),
        TPath.GetFullPath(TPath.Combine(RepoRoot,
        'tests\fixtures\RemoveWithScopedDeclarationFixture\ScopedDeclarationUnit.pas'))),
        'Expected semantic binding entry file path.');
      lScopedColumn := lBinding.Column;
      lScopedLine := lBinding.Line;
      Break;
    end;
  end;
  Assert.IsTrue(lFoundScopedBinding, 'Expected DelphiSemantics to report scoped declarations.');

  for i := 0 to High(lScanResult.fWithStatements) do
  begin
    lScanResult.fWithStatements[i].fHasScopedDeclarationInBody := False;
    lScanResult.fWithStatements[i].fHasUnsupportedIdentifierRoleInBody := False;
  end;
  lStatementIndex := -1;
  for i := 0 to High(lScanResult.fWithStatements) do
  begin
    if (lScanResult.fWithStatements[i].fLine = lScopedLine) and
      (lScanResult.fWithStatements[i].fColumn = lScopedColumn) then
    begin
      lStatementIndex := i;
      Break;
    end;
  end;
  Assert.AreNotEqual(-1, lStatementIndex, 'Expected discovery statement for semantic binding line.');
  lStatement := lScanResult.fWithStatements[lStatementIndex];
  SetLength(lScanResult.fWithStatements, 1);
  lScanResult.fWithStatements[0] := lStatement;

  lMismatchedInventory := lInventory;
  lMismatchedInventory.fDelphiSemanticWithBindingEntries :=
    Copy(lInventory.fDelphiSemanticWithBindingEntries);
  for i := 0 to High(lMismatchedInventory.fDelphiSemanticWithBindingEntries) do
    lMismatchedInventory.fDelphiSemanticWithBindingEntries[i].fFilePath :=
      TPath.Combine(RepoRoot, 'tests\fixtures\RemoveWithResolverFixture\ResolverUnit.pas');
  Assert.IsTrue(ResolveRemoveWithIdentifiers(lMismatchedInventory, lScanResult, lResult, lError),
    'Expected resolver to finish with mismatched semantic binding file: ' + lError);
  Assert.IsTrue(Length(lResult.fClassifications) > 0,
    'Semantic with-binding safety data must not block a statement from a different file.');
  lMismatchedResult := lResult;

  lDirectInventory := lInventory;
  lDirectInventory.fDelphiSemanticWithBindingEntries := nil;
  Assert.IsTrue(ResolveRemoveWithIdentifiers(lDirectInventory, lScanResult, lResult, lError),
    'Expected resolver to finish with direct DelphiSemantics binding metadata: ' + lError);
  Assert.IsTrue(Length(lResult.fClassifications) > 0,
    'Direct DelphiSemantics with-binding metadata must still classify safe scoped-declaration bodies.');
  lDirectResult := lResult;
  Assert.AreEqual(Length(lDirectResult.fClassifications), Length(lMismatchedResult.fClassifications),
    'Mismatched semantic binding entries must behave like absent semantic entries.');

  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lResult, lError),
    'Expected resolver to finish with semantic scoped-declaration metadata: ' + lError);
  Assert.IsTrue(Length(lResult.fClassifications) > 0,
    'Semantic with-binding safety data must classify safe scoped-declaration bodies even when legacy scan flags are absent.');
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
    Assert.AreEqual(1, Integer(Length(lExeFiles)), 'Expected one built precedence fixture exe under: ' + lOutputDir);
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

procedure TRemoveWithSymbolTests.BuildSymbolFixture(out aInventory: TRemoveWithFactSet);
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
    'Expected symbol inventory build to succeed: ' + lError);
  Assert.IsTrue(Length(aInventory.fSymbols) > 0, 'Expected symbol inventory to contain fixture declarations.');
end;

function TRemoveWithSymbolTests.RunVerboseSymbolInventoryLog(out aExitCode: Cardinal): string;
var
  lArgs: string;
  lDprojPath: string;
  lLogPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithSymbolsFixture\RemoveWithSymbolsFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-symbol-model-inventory.log');

  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --all --mode plan --format json --verbose true';
  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start remove-with process.');

  Result := '';
  if TFile.Exists(lLogPath) then
    Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

function TRemoveWithSymbolTests.CountSymbols(const aInventory: TRemoveWithFactSet; const aName: string;
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

function TRemoveWithSymbolTests.DescribeSymbols(const aInventory: TRemoveWithFactSet; const aName: string;
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

function TRemoveWithSymbolTests.FindSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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

procedure TRemoveWithSymbolTests.AssertSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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
  lInventory: TRemoveWithFactSet;
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
  lInventory: TRemoveWithFactSet;
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
  lInventory: TRemoveWithFactSet;
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
  lInventory: TRemoveWithFactSet;
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lInventory, lError),
    'Expected ANSI source symbol inventory build to succeed: ' + lError);
  Assert.IsTrue(FindSymbol(lInventory, 'AnsiGlobal', TRemoveWithSymbolKind.rwskUnitGlobal, '', '', lSymbol),
    'Expected symbol inventory to parse declarations from ANSI source.');
  Assert.AreEqual('TAnsiSymbolRecord', lSymbol.fTypeName, 'Expected ANSI source declaration type.');
end;

procedure TRemoveWithSymbolTests.InventoryBuildUsesProjectModelInsteadOfLineScanner;
var
  lExitCode: Cardinal;
  lLogText: string;
begin
  lLogText := RunVerboseSymbolInventoryLog(lExitCode);

  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected verbose remove-with plan to succeed.');
  Assert.Contains(lLogText, '[remove-with:symbols] model-unit start',
    'Expected symbol inventory to build from the AST-backed project model.');
  Assert.IsFalse(ContainsText(lLogText, '[remove-with:symbols] parse-unit start'),
    'Line-scanner inventory must not run in the remove-with semantic path.');
end;

procedure TRemoveWithExpressionTypeTests.BuildExpressionFixture(out aInventory: TRemoveWithFactSet);
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
    'Expected expression fixture inventory build to succeed: ' + lError);
end;

procedure TRemoveWithExpressionTypeTests.AssertSelector(const aInventory: TRemoveWithFactSet;
  const aSelectorText: string; const aStatus: TRemoveWithSelectorTypeStatus; const aTypeName, aReason: string;
  const aAddressable: Boolean);
begin
  AssertSelectorInRoutine(aInventory, 'TExpressionScope.Run', aSelectorText, aStatus, aTypeName, aReason,
    aAddressable);
end;

procedure TRemoveWithExpressionTypeTests.AssertSelectorInRoutine(const aInventory: TRemoveWithFactSet;
  const aRoutineName, aSelectorText: string; const aStatus: TRemoveWithSelectorTypeStatus; const aTypeName,
  aReason: string; const aAddressable: Boolean);
var
  lInfo: TRemoveWithSelectorTypeInfo;
begin
  Assert.IsTrue(ResolveRemoveWithSelectorType(aInventory, aRoutineName, aSelectorText, lInfo),
    'Expected selector resolver to handle: ' + aRoutineName + ' / ' + aSelectorText);
  Assert.AreEqual(RemoveWithSelectorTypeStatusToText(aStatus), RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Unexpected selector status for: ' + aSelectorText);
  Assert.AreEqual(aTypeName, lInfo.fTypeName, 'Unexpected selector type for: ' + aSelectorText);
  Assert.AreEqual(aReason, lInfo.fReason, 'Unexpected selector reason for: ' + aSelectorText);
  Assert.AreEqual(aAddressable, lInfo.fAddressable, 'Unexpected addressability for: ' + aSelectorText);
end;

procedure TRemoveWithExpressionTypeTests.ResolvesSupportedSelectorShapes;
var
  lInventory: TRemoveWithFactSet;
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
  AssertSelector(lInventory, 'PExpressionRecord(@lLocalRecord)^', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionRecord', '', True);
  AssertSelector(lInventory, 'lRecordPtr^', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '',
    True);
  AssertSelector(lInventory, 'lRecords[0]', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '',
    True);
  AssertSelector(lInventory, 'lRecords[Length(lRecords) - 1]', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionRecord', '', True);
  AssertSelector(lInventory, 'GlobalRecordPtrs[0]^', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionRecord', '', True);
  AssertSelector(lInventory, 'lAnonymous.Value', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionChild', '',
    True);
  AssertSelector(lInventory, 'lAliasRecord', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionRecordAlias', '', True);
  AssertSelector(lInventory, 'lAliasRecord.Child', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionChild', '', True);
  AssertSelector(lInventory, 'lImplementationAlias', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionImplementationAlias', '', True);
  AssertSelector(lInventory, 'lImplementationAlias.Child', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionChild', '', True);
  AssertSelector(lInventory, 'lSearchRec', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TSearchRec', '',
    True);
  AssertSelector(lInventory, 'lSearchRec.Name', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TFileName', '',
    True);
  AssertSelector(lInventory, 'lSearchAlias', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionSearchRecAlias', '', True);
  AssertSelector(lInventory, 'lSearchAlias.Attr', TRemoveWithSelectorTypeStatus.rwstsResolved, 'Integer', '',
    True);
  AssertSelectorInRoutine(lInventory, 'ResolveParentSelector', 'lParentPtr^',
    TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionRecord', '', True);
  AssertSelector(lInventory, 'lNested.Struktur', TRemoveWithSelectorTypeStatus.rwstsResolved,
    'TExpressionNestedRecord.Struktur', '', True);
  AssertSelector(lInventory, 'lLocalRecord.Child', TRemoveWithSelectorTypeStatus.rwstsResolved, 'TExpressionChild',
    '', True);
  AssertSelector(lInventory, 'lLocalRecord.Child.Name', TRemoveWithSelectorTypeStatus.rwstsResolved, 'string', '',
    True);
end;

procedure TRemoveWithExpressionTypeTests.ClassifiesUnsupportedAndExternalSelectors;
var
  lInventory: TRemoveWithFactSet;
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

procedure TRemoveWithSourceModelGoldenTests.BuildSourceModelFixture(out aInventory: TRemoveWithFactSet);
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
    'Expected source-model golden fixture inventory build to succeed: ' + lError);
end;

function TRemoveWithSourceModelGoldenTests.FindSymbol(const aInventory: TRemoveWithFactSet;
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

function TRemoveWithSourceModelGoldenTests.DescribeSymbols(const aInventory: TRemoveWithFactSet): string;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := '';
  for lSymbol in aInventory.fSymbols do
    Result := Result + Format('%s:%s:%s:%s; ', [lSymbol.fName, RemoveWithSymbolKindToText(lSymbol.fKind),
      lSymbol.fOwnerType, lSymbol.fTypeName]);
end;

function TRemoveWithSourceModelGoldenTests.CountSymbols(const aInventory: TRemoveWithFactSet;
  const aName: string; const aKind: TRemoveWithSymbolKind; const aOwnerType, aRoutineName: string): Integer;
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

procedure TRemoveWithSourceModelGoldenTests.AssertSelector(const aInventory: TRemoveWithFactSet;
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

procedure TRemoveWithSourceModelGoldenTests.AssertSymbol(const aInventory: TRemoveWithFactSet;
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
  lInventory: TRemoveWithFactSet;
  lSymbol: TRemoveWithSymbolInfo;
begin
  BuildSourceModelFixture(lInventory);

  AssertSymbol(lInventory, 'TGoldenChild', TRemoveWithSymbolKind.rwskTypeMember, '', '', '', 'TGoldenChild = record');
  AssertSymbol(lInventory, 'TGoldenVariant', TRemoveWithSymbolKind.rwskTypeMember, '', '', '',
    'TGoldenVariant = record');
  AssertSymbol(lInventory, 'TGoldenDefaultList', TRemoveWithSymbolKind.rwskTypeMember, '', '', '',
    'TGoldenDefaultList = class');
  AssertSymbol(lInventory, 'TGoldenRecord', TRemoveWithSymbolKind.rwskTypeMember, '', '', '', 'TGoldenRecord = record');
  AssertSymbol(lInventory, 'Mode', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '', 'Integer',
    'case Mode: Integer of');
  AssertSymbol(lInventory, 'MultiA', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '', 'Integer',
    'MultiA,');
  AssertSymbol(lInventory, 'MultiB', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '', 'Integer',
    'MultiB: Integer;');
  Assert.AreEqual(1, CountSymbols(lInventory, 'MultiB', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', ''),
    'Expected multiline continuation fields to be indexed once.');
  AssertSymbol(lInventory, 'RealValue', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '', 'Double',
    '(RealValue, ExtraReal: Double;');
  AssertSymbol(lInventory, 'ExtraReal', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '', 'Double',
    '(RealValue, ExtraReal: Double;');
  AssertSymbol(lInventory, 'HasReal', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '', 'Boolean',
    'HasReal: Boolean);');
  AssertSymbol(lInventory, 'TextValue', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '', 'string',
    '(TextValue: string; Offset, Size: Integer)');
  AssertSymbol(lInventory, 'Offset', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '', 'Integer',
    '(TextValue: string; Offset, Size: Integer)');
  AssertSymbol(lInventory, 'Size', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '', 'Integer',
    '(TextValue: string; Offset, Size: Integer)');
  Assert.IsFalse(FindSymbol(lInventory, 'cGoldenVariantReal', TRemoveWithSymbolKind.rwskField, 'TGoldenVariant', '',
    lSymbol), 'Expected variant arm labels not to be indexed as fields.');
  AssertSymbol(lInventory, 'RecordName', TRemoveWithSymbolKind.rwskField, 'TGoldenRecord', '', 'string',
    'RecordName: string;');
  AssertSymbol(lInventory, 'Child', TRemoveWithSymbolKind.rwskField, 'TGoldenRecord', '', 'TGoldenChild',
    'Child: TGoldenChild;');
  AssertSymbol(lInventory, 'RecordTitle', TRemoveWithSymbolKind.rwskProperty, 'TGoldenRecord', '', 'string',
    'property RecordTitle: string read RecordName write RecordName;');
  AssertSymbol(lInventory, 'Touch', TRemoveWithSymbolKind.rwskMethod, 'TGoldenRecord', '', '', 'procedure Touch;');
  AssertSymbol(lInventory, 'Name', TRemoveWithSymbolKind.rwskField, 'TGoldenChild', '', 'string', 'Name: string;');
  AssertSymbol(lInventory, 'Items', TRemoveWithSymbolKind.rwskProperty, 'TGoldenDefaultList', '', 'PGoldenRecord',
    'property Items[aIndex: Integer]: PGoldenRecord read GetItem; default;');
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
  lInfo: TRemoveWithSelectorTypeInfo;
  lInventory: TRemoveWithFactSet;
begin
  BuildSourceModelFixture(lInventory);

  AssertSymbol(lInventory, 'lObject', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'TGoldenClass', 'lObject: TGoldenClass;');
  AssertSymbol(lInventory, 'lDefaultList', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'TGoldenDefaultList', 'lDefaultList: TGoldenDefaultList;');
  AssertSymbol(lInventory, 'lRecord', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'TGoldenRecord', 'lRecord: TGoldenRecord;');
  AssertSymbol(lInventory, 'lRecordPtr', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'PGoldenRecord', 'lRecordPtr: PGoldenRecord;');
  AssertSymbol(lInventory, 'lRecords', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'TArray<TGoldenRecord>', 'lRecords: TArray<TGoldenRecord>;');
  AssertSymbol(lInventory, 'lStaticRecordPtrs', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'array[1..2] of PGoldenRecord', 'lStaticRecordPtrs: array[1..2] of PGoldenRecord;');
  AssertSymbol(lInventory, 'lStaticRecords', TRemoveWithSymbolKind.rwskLocalVariable, '', 'TGoldenScope.Run',
    'array [1 .. 2] of TGoldenRecord', 'lStaticRecords: array [1 .. 2] of TGoldenRecord;');

  AssertSelector(lInventory, 'lRecord', 'TGoldenRecord');
  AssertSelector(lInventory, 'lObject', 'TGoldenClass');
  AssertSelector(lInventory, 'lRecordPtr^', 'TGoldenRecord');
  AssertSelector(lInventory, 'lRecords[0]', 'TGoldenRecord');
  AssertSelector(lInventory, 'lStaticRecords[1]', 'TGoldenRecord');
  AssertSelector(lInventory, 'lStaticRecordPtrs[1]^', 'TGoldenRecord');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TGoldenScope.Run', 'lDefaultList[0]^', lInfo),
    'Expected selector resolver to handle default property selector.');
  Assert.AreEqual(RemoveWithSelectorTypeStatusToText(TRemoveWithSelectorTypeStatus.rwstsResolved),
    RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected dereferenced default pointer property selector to resolve.');
  Assert.AreEqual('TGoldenRecord', lInfo.fTypeName, 'Expected default property pointer target type.');
  AssertSelector(lInventory, 'lRecord.Child', 'TGoldenChild');
  AssertSelector(lInventory, 'lRecord.Child.Name', 'string');
  AssertSelector(lInventory, 'lObject.FClassRecord.Child', 'TGoldenChild');
end;

procedure TRemoveWithAncestorTests.BuildAncestorHelperFixture(out aInventory: TRemoveWithFactSet);
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
    'Expected ancestor/helper fixture inventory build to succeed: ' + lError);
end;

function TRemoveWithAncestorTests.FindSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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

procedure TRemoveWithAncestorTests.AssertSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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
  lInventory: TRemoveWithFactSet;
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
  lInventory: TRemoveWithFactSet;
  lSymbol: TRemoveWithSymbolInfo;
begin
  BuildAncestorHelperFixture(lInventory);

  Assert.IsFalse(FindSymbol(lInventory, 'Count', TRemoveWithSymbolKind.rwskProperty, 'TExternalDerivedList',
    'TStringList', lSymbol), 'Expected external ancestor members to stay unresolved.');
  Assert.IsTrue(FindSymbol(lInventory, 'TStringList', TRemoveWithSymbolKind.rwskExternal, '', '', lSymbol),
    'Expected source-unavailable ancestor type to be reported as external.');
end;

procedure TRemoveWithHelperTests.BuildAncestorHelperFixture(out aInventory: TRemoveWithFactSet);
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
    'Expected ancestor/helper fixture inventory build to succeed: ' + lError);
end;

function TRemoveWithHelperTests.FindSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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

procedure TRemoveWithHelperTests.AssertSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
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
  lInventory: TRemoveWithFactSet;
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
  lInventory: TRemoveWithFactSet;
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

procedure TRemoveWithResolverTests.BuildResolverFixture(out aInventory: TRemoveWithFactSet;
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
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
  lInventory: TRemoveWithFactSet;
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
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TResolverScope.Run', 'lMap[1]', lInfo),
    'Expected generic map alias selector to be inspected.');
  Assert.AreEqual(RemoveWithSelectorTypeStatusToText(TRemoveWithSelectorTypeStatus.rwstsUnresolved),
    RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected non-array generic aliases not to resolve as array elements.');
  Assert.AreNotEqual('string, Integer', lInfo.fTypeName, 'Generic map arguments must not be treated as an element.');

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

procedure TRemoveWithResolverTests.ClassifiesCompilerRoutineCallsInsideResolvedReceiverStack;
var
  lError: string;
  lInventory: TRemoveWithFactSet;
  lResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
begin
  BuildResolverFixture(lInventory, lScanResult);

  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lResult, lError),
    'Expected resolver to succeed: ' + lError);

  AssertClassification(lResult, 'with-1', 'Abs', TRemoveWithIdentifierStatus.rwisUnchanged, '',
    'external-routine-call');
  AssertClassification(lResult, 'with-1', 'Succ', TRemoveWithIdentifierStatus.rwisUnchanged, '',
    'external-routine-call');
  AssertClassification(lResult, 'with-1', 'Round', TRemoveWithIdentifierStatus.rwisUnchanged, '',
    'external-routine-call');
  AssertClassification(lResult, 'with-1', 'Pred', TRemoveWithIdentifierStatus.rwisUnchanged, '',
    'external-routine-call');
  AssertClassification(lResult, 'with-1', 'Str', TRemoveWithIdentifierStatus.rwisUnchanged, '',
    'external-routine-call');
  AssertClassification(lResult, 'with-1', 'Push', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
  AssertClassification(lResult, 'with-1', 'Size', TRemoveWithIdentifierStatus.rwisResolved, 'lCustomer', '');
end;

procedure TRemoveWithResolverTests.ResolvesDependentSelectorBeforeLocalShadow;
var
  lError: string;
  lInventory: TRemoveWithFactSet;
  lResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
begin
  BuildResolverFixture(lInventory, lScanResult);

  Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lResult, lError),
    'Expected resolver to succeed: ' + lError);

  AssertClassification(lResult, 'with-11', 'B_Nr', TRemoveWithIdentifierStatus.rwisResolved, 'b', '');
  AssertClassification(lResult, 'with-11', 'B_von', TRemoveWithIdentifierStatus.rwisResolved, 'b', '');
  AssertClassification(lResult, 'with-11', 'lLocalOnly', TRemoveWithIdentifierStatus.rwisUnchanged, '',
    'routine-scope');
end;

procedure TRemoveWithResolverTests.ReportsExternalUnsupportedUnresolvedAndAmbiguousCases;
var
  lError: string;
  lInventory: TRemoveWithFactSet;
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
  AssertClassification(lResult, 'with-9', 'MissingMember', TRemoveWithIdentifierStatus.rwisUnresolved, 'lCustomer',
    'receiver-member-not-found');
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

    AssertJsonClassification(lClassifications, 'with-1', 'DerivedField', 'resolved', 'direct', '');
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
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

    AssertJsonClassification(lClassifications, 'with-1', 'ChildTouch', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-2', 'ConcreteOnly', 'resolved', 'direct', '');
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
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
    AssertJsonClassification(lClassifications, 'with-3', 'Clash', 'resolved', 'direct', '');
    AssertJsonClassification(lClassifications, 'with-4', 'HelperValue', 'resolved', 'helper',
      'THelperOnlyRecordHelper');
    AssertJsonClassification(lClassifications, 'with-5', 'ClearData', 'resolved', 'helper',
      'TClassHelperTargetHelper');
    AssertJsonClassification(lClassifications, 'with-5', 'HelperData', 'resolved', 'helper',
      'TClassHelperTargetHelper');
    AssertJsonClassification(lClassifications, 'with-6', 'ExternalHelper', 'unresolved', 'none', '');
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
    AssertJsonClassification(lClassifications, 'with-2', 'ShadowName', 'resolved', 'direct', 'field');
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
  finally
    lJson.Free;
  end;
end;

function TRemoveWithIndexedPropertyTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithIndexedPropertyTests.BuildIndexedPropertyFixture(out aInventory: TRemoveWithFactSet);
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
    'Expected indexed property fixture inventory build to succeed: ' + lError);
end;

function TRemoveWithIndexedPropertyTests.FindSymbol(const aInventory: TRemoveWithFactSet;
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
  lInventory: TRemoveWithFactSet;
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

procedure TRemoveWithIndexedPropertyTests.DefaultIndexedPointerPropertyDereferencesToAddressableRecord;
var
  lInfo: TRemoveWithSelectorTypeInfo;
  lInventory: TRemoveWithFactSet;
begin
  BuildIndexedPropertyFixture(lInventory);

  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TIndexedScope.Run', 'lPointerBox[0]^', lInfo),
    'Expected selector resolver to handle default indexed pointer property selector.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected default indexed pointer property dereference to resolve.');
  Assert.AreEqual('TIndexedRecord', lInfo.fTypeName);
  Assert.IsTrue(lInfo.fAddressable, 'Expected dereferenced pointer property target to be addressable.');
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

    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
  finally
    lJson.Free;
  end;
end;

procedure TRemoveWithTempPolicyTests.BuildTempPolicyFixture(out aInventory: TRemoveWithFactSet);
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
    'Expected temp policy fixture inventory build to succeed: ' + lError);
end;

procedure TRemoveWithTempPolicyTests.AssertPolicy(const aInventory: TRemoveWithFactSet;
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
  lInventory: TRemoveWithFactSet;
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

procedure TRemoveWithTempPolicyTests.UnitLevelPureIndexedRecordSelectorUsesDirectQualification;
var
  lDecision: TRemoveWithTempDecision;
  lInventory: TRemoveWithFactSet;
begin
  BuildTempPolicyFixture(lInventory);

  Assert.IsTrue(PlanRemoveWithTempPolicy(lInventory, '', 'GRecords[0]', lDecision),
    'Expected unit-level indexed record selector policy to resolve.');
  Assert.AreEqual(RemoveWithTempStrategyToText(TRemoveWithTempStrategy.rwtsDirectQualification),
    RemoveWithTempStrategyToText(lDecision.fStrategy), 'Expected direct qualification without a routine var section.');
  Assert.AreEqual('GRecords[0]', lDecision.fQualifierText, 'Expected pure indexed selector qualifier.');
  Assert.AreEqual('', lDecision.fDeclarationText, 'Expected no temp declaration for unit-level pure selector.');
  Assert.AreEqual('unit-level-pure-selector', lDecision.fReason,
    'Expected explicit reason for conservative unit-level direct qualification.');
end;

procedure TRemoveWithTempPolicyTests.GeneratesCollisionFreeTempDeclarations;
var
  lDecision: TRemoveWithTempDecision;
  lInventory: TRemoveWithFactSet;
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
  lInventory: TRemoveWithFactSet;
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

procedure TRemoveWithPlannerTests.BuildPlannerFixture(out aInventory: TRemoveWithFactSet;
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
  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, aInventory, lError),
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
  lInventory: TRemoveWithFactSet;
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
  Assert.AreEqual(1, Integer(Length(lStatement.fTemps)), 'Expected record pointer temp.');
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
  Assert.AreEqual('planned', lStatement.fStatus, 'Expected if-controlled with to be planned.');
  Assert.IsTrue(Pos('lWithPlannerRecordPtr^.Name', lStatement.fReplacementText) > 0,
    'Expected controlled record member qualification in replacement text.');

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-6', lStatement), 'Expected case-label statement result.');
  Assert.AreEqual('planned', lStatement.fStatus, 'Expected case-label with to be planned.');
  Assert.IsTrue(Pos('^.Name := ''case controlled''', lStatement.fReplacementText) > 0,
    'Expected case-label record member qualification in replacement text.');

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-7', lStatement), 'Expected pointer statement plan.');
  Assert.AreEqual('planned', lStatement.fStatus, 'Expected pointer statement to be planned.');
  Assert.IsTrue(Pos('aRecordPtr^.Name', lStatement.fReplacementText) > 0,
    'Expected direct pointer qualification in replacement text.');
  Assert.AreEqual(0, Integer(Length(lStatement.fTemps)), 'Expected no temp declaration for direct pointer qualification.');
  Assert.AreEqual(1, Integer(Length(lStatement.fEdits)), 'Expected only replacement edit for direct pointer qualification.');
  Assert.AreEqual('replace-statement', lStatement.fEdits[0].fKind,
    'Expected no declaration edit for direct pointer qualification.');
end;

procedure TRemoveWithPlannerTests.SemanticFinalDtoPrimaryPlanDoesNotRequireDakResolverClassifications;
var
  lEmptyResolverResult: TRemoveWithResolverResult;
  lError: string;
  lInventory: TRemoveWithFactSet;
  lLegacyPlanResult: TRemoveWithPlanResult;
  lPlanResult: TRemoveWithPlanResult;
  lResolverResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
  lStatement: TRemoveWithPlannedStatement;
begin
  BuildPlannerFixture(lInventory, lScanResult, lResolverResult, lLegacyPlanResult);
  lEmptyResolverResult := Default(TRemoveWithResolverResult);

  Assert.IsTrue(PlanRemoveWithRewrites(lInventory, lScanResult, lEmptyResolverResult,
    lInventory.fDelphiSemanticRemoveWithPlan, lPlanResult, lError),
    'Expected DTO-primary planner to consume final semantic statements without DAK resolver classifications: ' +
    lError);

  Assert.IsTrue(FindPlannedStatement(lPlanResult, 'with-1', lStatement),
    'Expected DTO-primary result for record statement.');
  Assert.AreEqual('planned', lStatement.fStatus, 'Expected semantic final DTO status.');
  Assert.IsTrue(Pos('lWithPlannerRecordPtr^.Name', lStatement.fReplacementText) > 0,
    'Expected semantic final DTO replacement text.');
  Assert.AreEqual(2, Integer(Length(lStatement.fEdits)), 'Expected semantic final DTO edit list.');
  Assert.AreEqual('declare-temp', lStatement.fEdits[0].fKind,
    'Expected semantic final DTO declaration edit.');
  Assert.AreEqual('replace-statement', lStatement.fEdits[1].fKind,
    'Expected semantic final DTO replacement edit.');
  Assert.AreEqual(1, Integer(Length(lStatement.fTemps)), 'Expected semantic final DTO temp metadata.');
  Assert.AreEqual('record-pointer-temp', RemoveWithTempStrategyToText(lStatement.fTemps[0].fStrategy),
    'Expected semantic final DTO temp strategy.');
end;

procedure TRemoveWithPlannerTests.SemanticFinalDtoPrimaryPlanFailsWhenStatementIdCannotMap;
var
  lEmptyResolverResult: TRemoveWithResolverResult;
  lError: string;
  lInventory: TRemoveWithFactSet;
  lLegacyPlanResult: TRemoveWithPlanResult;
  lPlanResult: TRemoveWithPlanResult;
  lResolverResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
  lSemanticPlan: TDelphiSemanticRemoveWithPlan;
begin
  BuildPlannerFixture(lInventory, lScanResult, lResolverResult, lLegacyPlanResult);
  lEmptyResolverResult := Default(TRemoveWithResolverResult);
  lSemanticPlan := lInventory.fDelphiSemanticRemoveWithPlan;
  Assert.IsTrue(Length(lSemanticPlan.FinalStatements) > 0,
    'Expected fixture semantic final DTO statements.');
  lSemanticPlan.FinalStatements[0].Range.StartColumn := 999;

  Assert.IsFalse(PlanRemoveWithRewrites(lInventory, lScanResult,
    lEmptyResolverResult, lSemanticPlan, lPlanResult, lError),
    'Expected DTO-primary planner to fail when a scanned semantic final statement cannot map to a DAK statement id.');
  Assert.IsTrue(ContainsText(lError, 'statement id'),
    'Expected statement-id mapping error, got: ' + lError);
end;

procedure TRemoveWithPlannerTests.SemanticFinalDtoPrimaryPlanFailsWhenActiveConditionalStatementCannotMap;
var
  lEmptyResolverResult: TRemoveWithResolverResult;
  lError: string;
  lFileIndex: Integer;
  lInventory: TRemoveWithFactSet;
  lLegacyPlanResult: TRemoveWithPlanResult;
  lPlanResult: TRemoveWithPlanResult;
  lResolverResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
  lSemanticPlan: TDelphiSemanticRemoveWithPlan;
  lSourcePath: string;
begin
  BuildPlannerFixture(lInventory, lScanResult, lResolverResult, lLegacyPlanResult);
  lEmptyResolverResult := Default(TRemoveWithResolverResult);
  lInventory.fParserDefines := 'ACTIVE_REMOVE_WITH';
  lSourcePath := TPath.Combine(TempRoot, 'remove-with-active-conditional-map.pas');
  TFile.WriteAllText(lSourcePath,
    'unit ActiveConditionalMap;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'procedure Run;' + sLineBreak +
    'begin' + sLineBreak +
    '  {$IFDEF ACTIVE_REMOVE_WITH}' + sLineBreak +
    '  with lRecord do Name := ''x'';' + sLineBreak +
    '  {$ENDIF}' + sLineBreak +
    'end;' + sLineBreak +
    'end.', TEncoding.UTF8);

  lSemanticPlan := Default(TDelphiSemanticRemoveWithPlan);
  lSemanticPlan.Operation := 'remove-with';
  SetLength(lSemanticPlan.FinalStatements, 1);
  lSemanticPlan.FinalStatements[0].FileName := lSourcePath;
  lSemanticPlan.FinalStatements[0].Status := 'planned';
  lSemanticPlan.FinalStatements[0].Range.StartLine := 7;
  lSemanticPlan.FinalStatements[0].Range.StartColumn := 3;
  lSemanticPlan.FinalStatements[0].Range.EndLine := 7;
  lSemanticPlan.FinalStatements[0].Range.EndColumn := 31;

  lFileIndex := Length(lScanResult.fFiles);
  SetLength(lScanResult.fFiles, lFileIndex + 1);
  lScanResult.fFiles[lFileIndex].fPath := lSourcePath;
  lScanResult.fFiles[lFileIndex].fScanned := True;
  lScanResult.fFiles[lFileIndex].fWithStatementCount := 0;

  Assert.IsFalse(PlanRemoveWithRewrites(lInventory, lScanResult,
    lEmptyResolverResult, lSemanticPlan, lPlanResult, lError),
    'Expected active conditional semantic final statement to fail when it cannot map to a DAK statement id.');
  Assert.IsTrue(ContainsText(lError, 'statement id'),
    'Expected statement-id mapping error, got: ' + lError);
end;

procedure TRemoveWithPlannerTests.PlanCliUsesCompactHighVolumeReportContract;
const
  cWithCount = 105;
var
  i: Integer;
  lArgs: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lMetrics: TJSONObject;
  lOutput: string;
  lPlannedEdits: TJSONArray;
  lResolver: TJSONObject;
  lResolverClassifications: TJSONArray;
  lRoot: TJSONObject;
  lRootValue: TJSONValue;
  lSkipped: TJSONArray;
  lSourceDir: string;
  lSummary: TJSONObject;
  lTestDir: string;
  lUnitPath: string;
  lUnitText: string;
  lWithStatements: TJSONArray;
begin
  EnsureResolverBuilt;
  lTestDir := TPath.Combine(TempRoot, 'remove-with-compact-high-volume');
  if TDirectory.Exists(lTestDir) then
    TDirectory.Delete(lTestDir, True);
  TDirectory.CreateDirectory(lTestDir);
  lSourceDir := TPath.Combine(lTestDir, 'src');
  TDirectory.CreateDirectory(lSourceDir);
  lDprojPath := TPath.Combine(lTestDir, 'CompactHighVolume.dproj');
  lUnitPath := TPath.Combine(lSourceDir, 'CompactHighVolumeUnit.pas');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-compact-high-volume-plan.json');

  TFile.WriteAllText(TPath.Combine(lTestDir, 'CompactHighVolume.dpr'),
    'program CompactHighVolume;' + sLineBreak +
    'uses CompactHighVolumeUnit;' + sLineBreak +
    'begin' + sLineBreak +
    'end.', TEncoding.UTF8);
  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>CompactHighVolume.dpr</MainSource>' + sLineBreak +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>' + sLineBreak +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>' + sLineBreak +
    '    <DCC_UnitSearchPath>src</DCC_UnitSearchPath>' + sLineBreak +
    '    <DCCReference Include="src\CompactHighVolumeUnit.pas"/>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>', TEncoding.UTF8);

  lUnitText := 'unit CompactHighVolumeUnit;' + sLineBreak +
    'interface' + sLineBreak +
    'type' + sLineBreak +
    '  TCompactRecord = record' + sLineBreak +
    '    Name: string;' + sLineBreak +
    '  end;' + sLineBreak +
    'implementation' + sLineBreak +
    'procedure Run;' + sLineBreak +
    'var' + sLineBreak +
    '  lItem: TCompactRecord;' + sLineBreak +
    'begin' + sLineBreak;
  for i := 1 to cWithCount do
    lUnitText := lUnitText + '  with lItem do Name := ''item' + i.ToString +
      ''';' + sLineBreak;
  lUnitText := lUnitText + 'end;' + sLineBreak + 'end.';
  TFile.WriteAllText(lUnitPath, lUnitText, TEncoding.UTF8);

  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) +
    ' --all --mode plan --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath),
    lLogPath, lExitCode), 'Failed to start compact high-volume remove-with process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected compact high-volume plan to succeed.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lRootValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lRootValue is TJSONObject, 'Expected parseable remove-with JSON. Output: ' + lOutput);
  lRoot := lRootValue as TJSONObject;
  try
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    AssertJsonArrayKey(lRoot, 'withStatements', lWithStatements);
    AssertJsonArrayKey(lRoot, 'plannedEdits', lPlannedEdits);
    AssertJsonArrayKey(lRoot, 'skipped', lSkipped);
    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lResolverClassifications);
    AssertJsonObjectKey(lRoot, 'plannerPhaseMetrics', lMetrics);

    Assert.IsTrue((lSummary.Values['withStatements'] as TJSONNumber).AsInt > 100,
      'Expected generated fixture to exercise the compact high-volume branch.');
    Assert.AreEqual(0, lWithStatements.Count,
      'Plan JSON should keep the withStatements key but omit detailed scan rows.');
    Assert.AreEqual((lSummary.Values['plannedEdits'] as TJSONNumber).AsInt +
      (lSummary.Values['skipped'] as TJSONNumber).AsInt,
      lResolverClassifications.Count,
      'Compact high-volume plan reports should use the shared semantic projection contract.');
    Assert.AreEqual(0, (lMetrics.Values['classificationCount'] as TJSONNumber).AsInt,
      'Compact high-volume plan metrics should report zero DAK resolver classifications.');
    Assert.AreEqual(0, (lMetrics.Values['semanticCompatibilityFactsMs'] as TJSONNumber).AsInt,
      'Compact high-volume plan should skip DAK compatibility projection.');
    Assert.AreEqual((lSummary.Values['withStatements'] as TJSONNumber).AsInt,
      (lSummary.Values['plannedEdits'] as TJSONNumber).AsInt +
      (lSummary.Values['skipped'] as TJSONNumber).AsInt,
      'High-volume statement accounting must match planned plus skipped counts.');
    Assert.AreEqual((lSummary.Values['plannedEdits'] as TJSONNumber).AsInt,
      lPlannedEdits.Count, 'Planned edit report count must match summary.');
    Assert.AreEqual((lSummary.Values['skipped'] as TJSONNumber).AsInt,
      lSkipped.Count, 'Skipped report count must match summary.');
    Assert.AreEqual((lSummary.Values['plannedEdits'] as TJSONNumber).AsInt,
      (lMetrics.Values['plannedEditCount'] as TJSONNumber).AsInt,
      'Planned edit metric must match summary.');
    Assert.AreEqual((lSummary.Values['skipped'] as TJSONNumber).AsInt,
      (lMetrics.Values['skippedStatementCount'] as TJSONNumber).AsInt,
      'Skipped statement metric must match summary.');
  finally
    lRoot.Free;
  end;
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
  lStdOutLogPath: string;
  lVerification: TJSONObject;
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
    lVerification := lRollbackRoot.Values['verification'] as TJSONObject;
    lStdOutLogPath := lVerification.GetValue<string>('stdoutLog', '');
    Assert.IsTrue(TFile.Exists(lStdOutLogPath), 'Expected failed verification to preserve stdout build log.');
    Assert.Contains(TFile.ReadAllText(lStdOutLogPath, TEncoding.UTF8),
      'Intentional rollback fixture failure after remove-with rewrites RollbackUnit.pas',
      'Expected preserved build log to contain the actionable compiler/build diagnostic.');
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
    Assert.AreEqual(22, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected block, controlled, controlled-block, value-record, single-statement, and variant-record rewrite plans.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with aRecordPtr^ do', lUnitText) = 0, 'Expected all with statements to be removed.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''block'';', lUnitText) > 0,
    'Expected begin-end body to be qualified.');
  Assert.IsTrue(Pos('aRecordPtr^.Count := aRecordPtr^.Count + 1;', lUnitText) > 0,
    'Expected repeated begin-end identifier to be qualified.');
  Assert.IsTrue(Pos('if aRecordPtr <> nil then' + sLineBreak + '    begin', lUnitText) > 0,
    'Expected controlled with to be wrapped in a begin-end block.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''controlled'';', lUnitText) > 0,
    'Expected controlled with body to be qualified.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''controlled-block'';', lUnitText) > 0,
    'Expected controlled begin-end body to be qualified.');
  Assert.IsTrue(Pos('aRecordPtr^.Count := aRecordPtr^.Count + 3;', lUnitText) > 0,
    'Expected controlled begin-end repeated identifier to be qualified.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''controlled-if'';', lUnitText) > 0,
    'Expected controlled if-body with to be qualified.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''controlled-inner-if''', lUnitText) > 0,
    'Expected controlled with body if-branch to be qualified.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''controlled-inner-else'';', lUnitText) > 0,
    'Expected controlled with body else-branch to stay attached to the inner if.');
  Assert.IsTrue(Pos('if aRecordPtr^.Count > 0 then' + sLineBreak +
    '        aRecordPtr^.Name := ''controlled-inner-if''' + sLineBreak +
    '      else' + sLineBreak + '        aRecordPtr^.Name := ''controlled-inner-else'';', lUnitText) > 0,
    'Expected controlled with body else-branch not to be lifted out of the inner if.');
  Assert.IsTrue(Pos('aRecordPtr^.Count := aRecordPtr^.Count + i;', lUnitText) > 0,
    'Expected controlled for-body with to be qualified.');
  Assert.IsTrue(Pos('if (aRecordPtr^.Count and $7FFF) > 0 then', lUnitText) > 0,
    'Expected hex literals not to block identifier resolution.');
  Assert.IsTrue(Pos('aRecordPtr^.Count := aRecordPtr^.Count + $FFFF;', lUnitText) > 0,
    'Expected hex literal assignment to be qualified.');
  Assert.IsTrue(Pos('lWithRewriteShapeImplementationItemPtr^.LocalName := ''implementation-array'';', lUnitText) > 0,
    'Expected implementation-section record array selector body to be qualified.');
  Assert.IsTrue(Pos('lWithRewriteShapeImplementationItemPtr^.LocalCount := ' +
    'lWithRewriteShapeImplementationItemPtr^.LocalCount + 1;', lUnitText) > 0,
    'Expected implementation-section record array repeated identifiers to be qualified.');
  Assert.IsTrue(Pos('lWithRewriteShapeImplementationItemPtr := @lItems[LocalIndex];', lUnitText) > 0,
    'Expected implementation-section record array selector to survive nested local routine declarations.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''after-label'';', lUnitText) > 0,
    'Expected with after plain label to be treated as standalone.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr := @aRecord;', lUnitText) > 0,
    'Expected record value selector to be captured before the body.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr^.Name := ''record-value'';', lUnitText) > 0,
    'Expected record value body to be qualified.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr^.Count := lWithRewriteShapeRecordPtr^.Count + 2;', lUnitText) > 0,
    'Expected repeated record value body identifier to be qualified.');
  Assert.IsTrue(Pos('class procedure TRewriteShapeScope.RunRecordValueWithOnlyLabel(var aRecord: ' +
    'TRewriteShapeRecord);' + sLineBreak + 'var' + sLineBreak +
    '  lWithRewriteShapeRecordPtr: ^TRewriteShapeRecord;' + sLineBreak + 'label', lUnitText) > 0,
    'Expected new temp var section before a label-only routine declaration section.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr^.Name := ''record-only-label'';', lUnitText) > 0,
    'Expected label-only record value body to be qualified.');
  Assert.IsTrue(Pos('function LocalCount(var aLocalRecord: TRewriteShapeRecord): Integer;' + sLineBreak + 'var' +
    sLineBreak + '  lWithRewriteShapeRecordPtr: ^TRewriteShapeRecord;', lUnitText) > 0,
    'Expected local routine temp declaration inside the local routine.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr^.Name := ''local-routine'';', lUnitText) > 0,
    'Expected local routine with body to be qualified.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr^.Name := ''after-local-routine'';', lUnitText) > 0,
    'Expected outer routine with after a local routine to be qualified.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr^.Count := lWithRewriteShapeRecordPtr^.Count + 6;', lUnitText) > 0,
    'Expected outer routine with after a local routine to qualify repeated identifiers.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr^.Name := ''record-label'';', lUnitText) > 0,
    'Expected labeled record value body to be qualified.');
  Assert.IsTrue(Pos('lFlag: Boolean;' + sLineBreak + '  lWithRewriteShapeRecordPtr: ^TRewriteShapeRecord;' +
    sLineBreak + 'label', lUnitText) > 0, 'Expected record temp declaration before label section.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''single'';', lUnitText) > 0,
    'Expected single-statement body to be qualified.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr := @aRecord;', lUnitText) > 0,
    'Expected controlled block value selector before else to initialize a temp.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr^.Name := ''controlled-block-value-before-else'';', lUnitText) > 0,
    'Expected controlled block value selector before else to initialize a temp and qualify the body.');
  Assert.IsTrue(Pos('lWithRewriteShapeRecordPtr^.Count := lWithRewriteShapeRecordPtr^.Count + 11;', lUnitText) > 0,
    'Expected controlled block value repeated identifiers to be qualified.');
  Assert.IsTrue(Pos('endelse', LowerCase(lUnitText)) = 0,
    'Expected wrapper end and original else to remain separate tokens.');
  Assert.IsTrue(Pos('with aLeftPtr^ do', lUnitText) = 0,
    'Expected single-statement range before else to be wrapped and rewritten safely.');
  Assert.IsTrue(Pos('aLeftPtr^.Name := ''left''', lUnitText) > 0,
    'Expected left branch body before else to be qualified.');
  Assert.IsTrue(Pos('with aRightPtr^ do', lUnitText) = 0,
    'Expected safe descendant of unsafe single-statement range before else to be rewritten independently.');
  Assert.IsTrue(Pos('aRightPtr^.Name := ''right'';', lUnitText) > 0,
    'Expected safe descendant body before else to be qualified.');
  Assert.IsTrue(Pos('aVariantPtr^.Mode := 1;', lUnitText) > 0,
    'Expected variant tag field to be qualified.');
  Assert.IsTrue(Pos('aVariantPtr^.Handle := aVariantPtr^.Prefix + 1;', lUnitText) > 0,
    'Expected variant record fields to be qualified.');
  Assert.IsTrue(Pos('aVariantPtr^.Ptr := nil;', lUnitText) > 0,
    'Expected second variant record field to be qualified.');
  Assert.IsTrue(Pos('if aVariantPtr^.Mode = cRewriteShapeVariantPointer then', lUnitText) > 0,
    'Expected variant arm label constants to remain unqualified.');
  Assert.IsTrue(Pos('aVariantPtr^.Offset := aVariantPtr^.Size;', lUnitText) > 0,
    'Expected compound variant record fields to be qualified.');
  Assert.IsTrue(Pos('aVariantPtr^.cRewriteShapeVariantPointer', lUnitText) = 0,
    'Expected variant labels not to be treated as fields.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-rewrite-shapes-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited rewrite-shape fixture to build. Output: ' +
    lBuildOutput);
end;

procedure TRemoveWithRewriteShapeTests.ControlledSingleStatementBeforeElseRewritesSafely;
var
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lRoot: TJSONObject;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithRewriteShapeFixture', 'remove-with-controlled-single-before-else',
    'RewriteShapeUnit.pas', lDprojPath, lUnitPath);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-controlled-single-before-else.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected controlled single-before-else apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value,
      'Expected applied controlled single-before-else status.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with aLeftPtr^ do', lUnitText) = 0,
    'Expected controlled left branch with before else to be removed.');
  Assert.IsTrue(Pos('with aRightPtr^ do', lUnitText) = 0,
    'Expected controlled right branch with before else to be removed.');
  Assert.IsTrue(Pos('if aLeftPtr <> nil then' + sLineBreak + '    begin', lUnitText) > 0,
    'Expected controlled then-branch replacement to preserve the if/else shape.');
  Assert.IsTrue(Pos('aLeftPtr^.Name := ''controlled-left-before-else''', lUnitText) > 0,
    'Expected controlled left branch body before else to be qualified.');
  Assert.IsTrue(Pos('end' + sLineBreak + '  else', lUnitText) > 0,
    'Expected else to remain outside the inserted begin-end block.');
  Assert.IsTrue(Pos('aRightPtr^.Name := ''controlled-right-before-else'';', lUnitText) > 0,
    'Expected controlled right branch body to be qualified.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-controlled-single-before-else-build.log',
    lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode,
    'Expected edited controlled single-before-else fixture to build. Output: ' + lBuildOutput);
end;

procedure TRemoveWithRewriteShapeTests.MultipleSelectorsRewriteWithCompilerPrecedence;
var
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDependentPlan: TJSONObject;
  lDependentTemps: TJSONArray;
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
    Assert.AreEqual(2, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected independent and dependent multiple-selector rewrite plans.');
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
    lDependentPlan := (lRoot.Values['plannedEdits'] as TJSONArray).Items[1] as TJSONObject;
    lDependentTemps := lDependentPlan.Values['temps'] as TJSONArray;
    Assert.AreEqual(2, lDependentTemps.Count, 'Expected dependent selector temps.');
    Assert.AreEqual('lWithMultiIndexRecordPtr := @lIndex;',
      (lDependentTemps.Items[0] as TJSONObject).Values['initialization'].Value,
      'Expected one initialization for the earlier record selector.');
    Assert.AreEqual('lWithMultiRight := lItems[lWithMultiIndexRecordPtr^.Index];',
      (lDependentTemps.Items[1] as TJSONObject).Values['initialization'].Value,
      'Expected later selector initialization to qualify the earlier selector member.');
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
  Assert.IsTrue(Pos('lWithMultiRight.Code1 := ''right-code'';', lUnitText) > 0,
    'Expected digit-suffixed member lookup to be qualified.');
  Assert.IsTrue(Pos('lWithMultiLeft.LeftOnly := ''left'';', lUnitText) > 0,
    'Expected earlier selector to qualify left-only member lookup.');
  Assert.IsTrue(Pos('lWithMultiRight.RightOnly := ''right-only'';', lUnitText) > 0,
    'Expected later selector to qualify right-only member lookup.');
  Assert.IsTrue(Pos('with lIndex, lItems[Index] do', lUnitText) = 0,
    'Expected dependent selector with statement to be removed.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, 'lWithMultiIndexRecordPtr := @lIndex;'),
    'Expected dependent record selector to be captured exactly once.');
  Assert.AreEqual(1, CountOccurrences(lUnitText, 'lWithMultiRight := lItems[lWithMultiIndexRecordPtr^.Index];'),
    'Expected dependent class selector to be captured with qualified index exactly once.');
  Assert.IsTrue(Pos('lWithMultiRight.RightOnly := ''dependent'';', lUnitText) > 0,
    'Expected dependent selector body to qualify against the later selector.');

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

procedure TRemoveWithRewriteShapeTests.ControlledNestedWithStatementsRewriteInnerSafely;
var
  i: Integer;
  lDprojPath: string;
  lExitCode: Cardinal;
  lHasControlledOuter: Boolean;
  lPlan: TJSONObject;
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
    Assert.AreEqual(1, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected safe controlled nested with statement to be planned.');
    lPlan := (lRoot.Values['plannedEdits'] as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('with-1', lPlan.Values['statementId'].Value,
      'Expected the outer controlled nested with to be planned with its inner child.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, lSkipped.Count, 'Expected controlled nested with statements to be planned.');
    lHasControlledOuter := False;
    for i := 0 to lSkipped.Count - 1 do
    begin
      lSkippedItem := lSkipped.Items[i] as TJSONObject;
      if (lSkippedItem.Values['statementId'].Value = 'with-1') and
        (lSkippedItem.Values['reason'].Value = 'controlled-with-statement') then
        lHasControlledOuter := True;
    end;
    Assert.IsFalse(lHasControlledOuter, 'Expected outer nested rewrite to be planned.');
  finally
    lRoot.Free;
  end;

  lUnitTextAfter := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.AreNotEqual(lUnitTextBefore, lUnitTextAfter, 'Expected controlled nested fixture source to change.');
  Assert.IsTrue(Pos('if lCondition then', lUnitTextAfter) > 0, 'Expected controlling statement to remain.');
  Assert.IsTrue(Pos('with lOuter do', lUnitTextAfter) = 0, 'Expected outer with to be removed.');
  Assert.IsTrue(Pos('with lInner do', lUnitTextAfter) = 0, 'Expected controlled inner with to be removed.');
  Assert.IsTrue(Pos('lWithNestedControlledInner := lInner;', lUnitTextAfter) > 0,
    'Expected inner selector to be captured.');
  Assert.IsTrue(Pos('lWithNestedControlledInner.Shared := ''controlled'';', lUnitTextAfter) > 0,
    'Expected inner controlled body to be qualified.');
end;

procedure TRemoveWithRewriteShapeTests.AnonymousNestedMultiSelectorRewrites;
var
  i: Integer;
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSkippedItem: TJSONObject;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithRewriteShapeFixture', 'remove-with-anonymous-nested-selector',
    'RewriteShapeUnit.pas', lDprojPath, lUnitPath);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-anonymous-nested-selector.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected anonymous nested selector apply to succeed.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    for i := 0 to lSkipped.Count - 1 do
    begin
      lSkippedItem := lSkipped.Items[i] as TJSONObject;
      Assert.AreNotEqual('', lSkippedItem.Values['reason'].Value, 'Skipped with statements must report a reason.');
    end;
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with aOuter, Struktur do', lUnitText) = 0,
    'Expected anonymous nested multi-selector with statement to be removed.');
  Assert.IsTrue(Pos('lWithRewriteShapeAnonymousOuterPtr^.Struktur.InnerOnly := ' +
    'lWithRewriteShapeAnonymousOuterPtr^.OuterOnly;', lUnitText) > 0,
    'Expected anonymous nested body to qualify inner and outer receivers.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-anonymous-nested-selector-build.log',
    lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited anonymous nested selector fixture to build. Output: ' +
    lBuildOutput);
end;

procedure TRemoveWithRewriteShapeTests.NestedSingleStatementWithRewritesBottomUp;
var
  i: Integer;
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSkippedItem: TJSONObject;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithRewriteShapeFixture', 'remove-with-single-nested-rewrite', 'RewriteShapeUnit.pas',
    lDprojPath, lUnitPath);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-single-nested-rewrite.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected nested single-statement apply to succeed.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    for i := 0 to lSkipped.Count - 1 do
    begin
      lSkippedItem := lSkipped.Items[i] as TJSONObject;
      if SameText(lSkippedItem.Values['statementId'].Value, 'with-16') or
        SameText(lSkippedItem.Values['statementId'].Value, 'with-17') then
      begin
        Assert.AreNotEqual('single-statement-range-overlaps-nested-with', lSkippedItem.Values['reason'].Value,
          'Expected outer single-statement nested with to be planned bottom-up.');
        Assert.AreNotEqual('ancestor-single-statement-range-overlaps-nested-with', lSkippedItem.Values['reason'].Value,
          'Expected nested single-statement child not to be blocked by its ancestor.');
      end;
    end;
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with aOuter do', lUnitText) = 0, 'Expected outer single-statement with to be removed.');
  Assert.IsTrue(Pos('with aInner do', lUnitText) = 0, 'Expected inner single-statement with to be removed.');
  Assert.IsTrue(Pos('lWithRewriteShapeNestedInnerPtr^.InnerOnly := ' +
    'lWithRewriteShapeNestedOuterPtr^.OuterOnly;', lUnitText) > 0,
    'Expected inner body to qualify both inner and outer receivers.');
  Assert.IsTrue(Pos('for i := 1 to 1 do', lUnitText) > 0,
    'Expected for-controlled body to remain.');
  Assert.IsTrue(Pos('lWithRewriteShapeNestedInnerPtr^.InnerOnly := ' +
    'lWithRewriteShapeNestedOuterPtr^.OuterOnly + IntToStr(i);', lUnitText) > 0,
    'Expected nested with inside a for-controlled single body to be rewritten.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-single-nested-rewrite-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited nested single-statement fixture to build. Output: ' +
    lBuildOutput);
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
    Assert.AreEqual(3, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected safe nested, safe child under blocked parent, and unrelated safe rewrite plans.');
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
      if (lSkippedItem.Values['statementId'].Value = 'with-5') and
        (lSkippedItem.Values['reason'].Value = 'multiple-member-candidates') then
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
  Assert.IsTrue(Pos('with lSafeRight do', lUnitText) = 0,
    'Expected safe nested child under blocked parent to be removed.');
  Assert.IsTrue(Pos('lWithCombinedOuterRight.RightOuterOnly := ''safe-under-blocked-parent'';', lUnitText) > 0,
    'Expected safe nested child under blocked parent to be qualified.');
  Assert.IsTrue(Pos('with lSafeLeft, lSafeRight do', lUnitText) = 0,
    'Expected unrelated safe rewrite in same file to proceed.');
  Assert.IsTrue(Pos('lWithCombinedOuterRight1.RightOuterOnly := ''safe-unrelated'';', lUnitText) > 0,
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
  lNormalizedText: string;
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
    Assert.AreEqual(9, lPlans.Count, 'Expected all same-routine with statements to be planned.');
    Assert.AreEqual(4, CountDeclareTempEdits(lPlans), 'Expected one declaration edit per routine.');

    lTemps := (lPlans.Items[5] as TJSONObject).Values['temps'] as TJSONArray;
    Assert.AreEqual('lWithTempAggregationRecordPtr', (lTemps.Items[0] as TJSONObject).Values['tempName'].Value,
      'Expected first record temp name.');
    Assert.AreEqual('lWithTempAggregationRecordPtr := @aFirstRecord;',
      (lTemps.Items[0] as TJSONObject).Values['initialization'].Value,
      'Expected first record temp initialization.');

    lTemps := (lPlans.Items[6] as TJSONObject).Values['temps'] as TJSONArray;
    Assert.AreEqual('lWithTempAggregationRecordPtr1', (lTemps.Items[0] as TJSONObject).Values['tempName'].Value,
      'Expected second record temp name to reserve across the routine.');
    Assert.AreEqual('lWithTempAggregationRecordPtr1 := @aSecondRecord;',
      (lTemps.Items[0] as TJSONObject).Values['initialization'].Value,
      'Expected second record temp initialization.');

    lTemps := (lPlans.Items[7] as TJSONObject).Values['temps'] as TJSONArray;
    Assert.AreEqual('lWithTempAggregationObject', (lTemps.Items[0] as TJSONObject).Values['tempName'].Value,
      'Expected first object temp name.');

    lTemps := (lPlans.Items[8] as TJSONObject).Values['temps'] as TJSONArray;
    Assert.AreEqual('lWithTempAggregationObject1', (lTemps.Items[0] as TJSONObject).Values['tempName'].Value,
      'Expected second object temp name to reserve across the routine.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  lNormalizedText := StringReplace(lUnitText, #13#10, #10, [rfReplaceAll]);
  Assert.AreEqual(0, CountOccurrences(lUnitText, 'with aFirstRecord do'),
    'Expected first record with statement to be removed.');
  Assert.AreEqual(0, CountOccurrences(lUnitText, 'with aSecondRecord do'),
    'Expected second record with statement to be removed.');
  Assert.AreEqual(0, CountOccurrences(lUnitText, 'with aFirstObject do'),
    'Expected first object with statement to be removed.');
  Assert.AreEqual(0, CountOccurrences(lUnitText, 'with aSecondObject do'),
    'Expected second object with statement to be removed.');
  Assert.IsTrue(CountOccurrences(lUnitText, 'var') >= 4, 'Expected one var section per fixture routine.');
  Assert.AreEqual(4, CountOccurrences(lUnitText, 'lWithTempAggregationRecordPtr: ^TTempAggregationRecord;'),
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
  Assert.IsTrue(Pos('var' + #10 +
    '  lMarker: Integer;' + #10 +
    '  lWithTempAggregationRecordPtr: ^TTempAggregationRecord;' + #10 +
    'begin {comment after begin must still terminate the var section}', lNormalizedText) > 0,
    'Expected begin-with-comment to receive declarations before the executable body.');
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

function TRemoveWithTransactionTests.ByteSequenceExists(const aBytes, aNeedle: TBytes): Boolean;
var
  i: Integer;
  j: Integer;
  lMatched: Boolean;
begin
  Result := False;
  if Length(aNeedle) = 0 then
    Exit(True);
  if Length(aNeedle) > Length(aBytes) then
    Exit(False);

  for i := 0 to Length(aBytes) - Length(aNeedle) do
  begin
    lMatched := True;
    for j := 0 to High(aNeedle) do
    begin
      if aBytes[i + j] <> aNeedle[j] then
      begin
        lMatched := False;
        Break;
      end;
    end;
    if lMatched then
      Exit(True);
  end;
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
  Assert.AreEqual(1, Integer(Length(lFiles)), 'Expected exactly one transaction manifest under ' + lRoot + '.');
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

procedure TRemoveWithTransactionTests.ApplyModeStopsBeforeEditingWhenPreflightBuildFails;
var
  lDprojPath: string;
  lDprPath: string;
  lDprText: string;
  lExitCode: Cardinal;
  lOutput: string;
  lOutputValue: TJSONValue;
  lRoot: TJSONObject;
  lSummary: TJSONObject;
  lTransaction: TJSONObject;
  lUnitOriginalBytes: TBytes;
  lUnitPath: string;
begin
  CopyFixtureToTemp('RemoveWithApplyFixture', 'remove-with-apply-preflight-fails', 'ApplyUnit.pas',
    lDprojPath, lUnitPath);
  lUnitOriginalBytes := TFile.ReadAllBytes(lUnitPath);

  lDprPath := TPath.Combine(TPath.GetDirectoryName(lDprojPath), 'RemoveWithApplyFixture.dpr');
  lDprText := TFile.ReadAllText(lDprPath, TEncoding.UTF8);
  lDprText := StringReplace(lDprText, 'uses' + sLineBreak + '  ApplyUnit in ''ApplyUnit.pas'';',
    'uses' + sLineBreak + '  MissingPreflightUnit in ''MissingPreflightUnit.pas'',' + sLineBreak +
    '  ApplyUnit in ''ApplyUnit.pas'';', []);
  TFile.WriteAllText(lDprPath, lDprText, TEncoding.UTF8);

  lOutput := RunApplyFixture(lDprojPath, 'remove-with-apply-preflight-fails.json', lExitCode);
  Assert.AreNotEqual(Cardinal(0), lExitCode, 'Expected apply mode to fail before edits. Output: ' + lOutput);
  AssertBytesEqual(lUnitOriginalBytes, TFile.ReadAllBytes(lUnitPath),
    'Preflight failure must not change the planned source file.');

  lOutputValue := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lOutputValue is TJSONObject, 'Expected preflight output to be a single JSON object. Output: ' +
      lOutput);
    lRoot := lOutputValue as TJSONObject;
    Assert.AreEqual('preflight-build-failed', lRoot.Values['status'].Value,
      'Expected explicit preflight failure root status.');
    AssertJsonObjectKey(lRoot, 'transaction', lTransaction);
    Assert.AreEqual('preflight-build-failed', lTransaction.Values['status'].Value,
      'Expected explicit preflight failure transaction status.');
    Assert.AreEqual(0, (lTransaction.Values['files'] as TJSONArray).Count,
      'Expected no transaction files because no edits were attempted.');
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    Assert.AreEqual(0, (lSummary.Values['appliedEdits'] as TJSONNumber).AsInt,
      'Expected no applied edits on preflight failure.');
    Assert.AreEqual(0, (lSummary.Values['rolledBack'] as TJSONNumber).AsInt,
      'Expected no rollback because no file was changed.');
  finally
    lOutputValue.Free;
  end;
end;

procedure TRemoveWithTransactionTests.ApplyModePreservesAnsiEncodedSource;
var
  lAnsiBytes: TBytes;
  lAppliedBytes: TBytes;
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFiles: TJSONArray;
  lManifest: TJSONObject;
  lManifestPath: string;
  lManifestValue: TJSONValue;
  lMarker: string;
  lMarkerBytes: TBytes;
  lOutput: string;
  lOutputValue: TJSONValue;
  lProjectDir: string;
  lText: string;
  lUnitPath: string;
  lUtf8MarkerBytes: TBytes;
begin
  CopyFixtureToTemp('RemoveWithApplyFixture', 'remove-with-apply-ansi-transaction', 'ApplyUnit.pas',
    lDprojPath, lUnitPath);

  lMarker := WideChar($00E4);
  lText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  lText := StringReplace(lText, 'unit ApplyUnit;', 'unit ApplyUnit;' + sLineBreak +
    '// ansi marker: ' + lMarker, []);
  lMarkerBytes := TEncoding.Default.GetBytes(lMarker);
  lUtf8MarkerBytes := TEncoding.UTF8.GetBytes(lMarker);
  lAnsiBytes := TEncoding.Default.GetBytes(lText);
  TFile.WriteAllBytes(lUnitPath, lAnsiBytes);
  Assert.IsTrue(ByteSequenceExists(lAnsiBytes, lMarkerBytes), 'Expected fixture to contain local ANSI bytes.');

  lOutput := RunApplyFixture(lDprojPath, 'remove-with-apply-ansi-transaction.json', lExitCode);
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected ANSI apply mode to succeed. Output: ' + lOutput);
  lOutputValue := TJSONObject.ParseJSONValue(lOutput);
  try
    Assert.IsTrue(lOutputValue is TJSONObject, 'Expected apply output to be a single JSON object. Output: ' +
      lOutput);
    Assert.AreEqual('applied', (lOutputValue as TJSONObject).Values['status'].Value,
      'Expected applied status in ANSI apply output.');
  finally
    lOutputValue.Free;
  end;

  lAppliedBytes := TFile.ReadAllBytes(lUnitPath);
  Assert.IsTrue(ByteSequenceExists(lAppliedBytes, lMarkerBytes),
    'Expected ANSI marker bytes to remain in the edited file.');
  if not ByteSequenceExists(lMarkerBytes, lUtf8MarkerBytes) then
    Assert.IsFalse(ByteSequenceExists(lAppliedBytes, lUtf8MarkerBytes),
      'Expected edited ANSI file not to be rewritten as UTF-8.');

  lText := TFile.ReadAllText(lUnitPath, TEncoding.Default);
  Assert.IsTrue(Pos('with aRecordPtr^ do', lText) = 0, 'Expected with statement to be removed from ANSI file.');
  Assert.IsTrue(Pos('aRecordPtr^.Name := ''applied'';', lText) > 0,
    'Expected ANSI file to contain direct pointer qualification.');
  Assert.IsTrue(Pos('// ansi marker: ' + lMarker, lText) > 0, 'Expected ANSI marker comment to remain.');

  lProjectDir := TPath.GetDirectoryName(lDprojPath);
  lManifestPath := FindSingleManifest(lProjectDir, 'RemoveWithApplyFixture');
  lManifestValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(lManifestPath, TEncoding.UTF8));
  try
    Assert.IsTrue(lManifestValue is TJSONObject, 'Expected ANSI manifest JSON object.');
    lManifest := lManifestValue as TJSONObject;
    lFiles := lManifest.Values['files'] as TJSONArray;
    Assert.AreEqual(1, lFiles.Count, 'Expected one backed up ANSI file.');
    Assert.AreEqual('ansi', (lFiles.Items[0] as TJSONObject).Values['encoding'].Value,
      'Expected manifest to report ANSI encoding.');
  finally
    lManifestValue.Free;
  end;

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-apply-ansi-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited ANSI apply fixture to build. Output: ' +
    lBuildOutput);
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

procedure TRemoveWithTransactionTests.BuildVerificationUsesProjectScopedMutexAndTypedDiagnostics;
var
  lBuildRunnerSource: string;
  lTransactionSource: string;
begin
  lTransactionSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Transaction.pas'),
    TEncoding.UTF8);
  lBuildRunnerSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.Build.Runner.pas'),
    TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lTransactionSource, 'BuildVerificationMutexName('),
    'Expected build verification locking to derive a mutex from the project identity.');
  Assert.IsFalse(ContainsText(lTransactionSource, 'Local\DakRemoveWithBuildVerification'''),
    'Expected no fixed global remove-with build verification mutex.');
  Assert.IsFalse(ContainsText(lTransactionSource, 'WaitForSingleObject(lMutex, Winapi.Windows.INFINITE)'),
    'Expected remove-with build verification to avoid an indefinite global wait.');
  Assert.IsFalse(ContainsText(lTransactionSource, 'SetEnvironmentVariable('),
    'Expected remove-with build verification not to mutate process environment state.');
  Assert.IsTrue(ContainsText(lBuildRunnerSource, 'fBuildDiagnosticsDir'),
    'Expected build diagnostics to be a typed option instead of a process-wide environment mutation.');
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

procedure TRemoveWithApplyCompileGateTests.AssertBytesEqual(const aExpected, aActual: TBytes;
  const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aExpected), Length(aActual), aMessage + ' Size differs.');
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], aActual[i], aMessage + ' Byte differs at index ' + i.ToString + '.');
end;

procedure TRemoveWithApplyCompileGateTests.CopyFixtureToTemp(const aFixtureName, aTempName,
  aUnitName: string; out aDprojPath, aUnitPath: string);
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

procedure TRemoveWithApplyCompileGateTests.BuildPlanForFixture(const aDprojPath: string;
  out aOptions: TAppOptions; out aPlanResult: TRemoveWithPlanResult;
  out aApplyContext: TRemoveWithPlanApplyContext);
var
  lError: string;
  lInventory: TRemoveWithFactSet;
  lModel: TRemoveWithProjectModel;
  lResolverResult: TRemoveWithResolverResult;
  lScanResult: TRemoveWithScanResult;
  lSymbolMapBridge: TRemoveWithSymbolMapBridge;
begin
  aOptions := Default(TAppOptions);
  aOptions.fDprojPath := aDprojPath;
  aOptions.fConfig := 'Debug';
  aOptions.fPlatform := 'Win32';
  aOptions.fDelphiVersion := '23.0';
  aOptions.fRemoveWithTargetKind := TRemoveWithTargetKind.rwtAll;
  lModel := nil;
  lSymbolMapBridge := Default(TRemoveWithSymbolMapBridge);
  Assert.IsTrue(BuildRemoveWithProjectModel(aOptions, aDprojPath, lModel, lError), lError);
  try
    Assert.IsTrue(DiscoverRemoveWithStatements(aOptions, lModel, lScanResult, lError), lError);
    Assert.IsTrue(BuildRemoveWithFactSet(aOptions, lModel, lInventory, lError), lError);
    Assert.IsTrue(ResolveRemoveWithIdentifiers(lInventory, lScanResult, lSymbolMapBridge, lResolverResult,
      lError), lError);
    Assert.IsTrue(PlanRemoveWithRewrites(lInventory, lScanResult, lResolverResult, aPlanResult, lError),
      lError);
    Assert.IsTrue(BuildRemoveWithPlanApplyContext(aPlanResult, aApplyContext, lError), lError);
    Assert.AreEqual(1, Integer(Length(aApplyContext.fSourceFingerprints)),
      'Expected the DAK apply context to fingerprint the source file it will edit.');
    Assert.IsNotEmpty(aApplyContext.fContextFingerprint,
      'Expected the DAK apply context to carry a context fingerprint.');
  finally
    FinalizeRemoveWithSymbolMapBridge(lSymbolMapBridge);
    lModel.Free;
  end;
end;

procedure TRemoveWithApplyCompileGateTests.ApplyRefusesWhenPlannedSourceFingerprintIsStale;
var
  lDprojPath: string;
  lError: string;
  lApplyContext: TRemoveWithPlanApplyContext;
  lManifestValue: TJSONValue;
  lMutatedBytes: TBytes;
  lOptions: TAppOptions;
  lPlanResult: TRemoveWithPlanResult;
  lTransactionResult: TRemoveWithTransactionResult;
  lUnitPath: string;
  lWorkspaceRoot: string;
begin
  CopyFixtureToTemp('RemoveWithApplyFixture', 'remove-with-apply-stale-fingerprint', 'ApplyUnit.pas',
    lDprojPath, lUnitPath);
  BuildPlanForFixture(lDprojPath, lOptions, lPlanResult, lApplyContext);

  TFile.AppendAllText(lUnitPath, sLineBreak + '// context changed after planning' + sLineBreak,
    TEncoding.UTF8);
  lMutatedBytes := TFile.ReadAllBytes(lUnitPath);
  lWorkspaceRoot := TPath.Combine(TPath.GetDirectoryName(lDprojPath), '.dak\RemoveWithApplyFixture\remove-with\stale');

  Assert.IsFalse(ApplyRemoveWithPlanTransactionally(lOptions, lDprojPath, lWorkspaceRoot, lPlanResult,
    lApplyContext, lTransactionResult, lError), 'Expected stale source context to refuse apply mode.');
  Assert.AreEqual('context-fingerprint-mismatch', RemoveWithTransactionStatusToText(lTransactionResult.fStatus),
    'Expected explicit context fingerprint mismatch status.');
  Assert.Contains(lError, 'context-fingerprint-mismatch',
    'Expected stale context error to be reported.');
  Assert.AreEqual(0, Integer(Length(lTransactionResult.fFiles)),
    'Expected stale context preflight to refuse before backing up or editing files.');
  AssertBytesEqual(lMutatedBytes, TFile.ReadAllBytes(lUnitPath),
    'Context mismatch must preserve the changed source bytes exactly.');
  Assert.IsTrue(TFile.Exists(lTransactionResult.fManifestPath), 'Expected refusal manifest to be written.');

  lManifestValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(lTransactionResult.fManifestPath,
    TEncoding.UTF8));
  try
    Assert.IsTrue(lManifestValue is TJSONObject, 'Expected manifest JSON object.');
    Assert.AreEqual('context-fingerprint-mismatch', (lManifestValue as TJSONObject).Values['status'].Value,
      'Expected manifest to record context mismatch.');
  finally
    lManifestValue.Free;
  end;
end;

procedure TRemoveWithApplyCompileGateTests.ApplyRefusesPlannedEditsWhenContextFingerprintIsMissing;
var
  lApplyContext: TRemoveWithPlanApplyContext;
  lDprojPath: string;
  lError: string;
  lOptions: TAppOptions;
  lOriginalBytes: TBytes;
  lPlanResult: TRemoveWithPlanResult;
  lTransactionResult: TRemoveWithTransactionResult;
  lUnitPath: string;
  lWorkspaceRoot: string;
begin
  CopyFixtureToTemp('RemoveWithApplyFixture', 'remove-with-apply-missing-fingerprint', 'ApplyUnit.pas',
    lDprojPath, lUnitPath);
  BuildPlanForFixture(lDprojPath, lOptions, lPlanResult, lApplyContext);
  lApplyContext := Default(TRemoveWithPlanApplyContext);
  lOriginalBytes := TFile.ReadAllBytes(lUnitPath);
  lWorkspaceRoot := TPath.Combine(TPath.GetDirectoryName(lDprojPath),
    '.dak\RemoveWithApplyFixture\remove-with\missing-context');

  Assert.IsFalse(ApplyRemoveWithPlanTransactionally(lOptions, lDprojPath, lWorkspaceRoot, lPlanResult,
    lApplyContext, lTransactionResult, lError), 'Expected missing source context to refuse apply mode.');
  Assert.AreEqual('context-fingerprint-missing', RemoveWithTransactionStatusToText(lTransactionResult.fStatus),
    'Expected explicit missing context fingerprint status.');
  Assert.Contains(lError, 'context-fingerprint-missing', 'Expected missing context error to be reported.');
  Assert.AreEqual(0, Integer(Length(lTransactionResult.fFiles)),
    'Expected missing context preflight to refuse before backing up or editing files.');
  AssertBytesEqual(lOriginalBytes, TFile.ReadAllBytes(lUnitPath),
    'Missing context refusal must preserve source bytes exactly.');
end;

procedure TRemoveWithApplyCompileGateTests.LegacyApplyOverloadRefusesPlannedEditsWithoutContext;
var
  lApplyContext: TRemoveWithPlanApplyContext;
  lDprojPath: string;
  lError: string;
  lOptions: TAppOptions;
  lOriginalBytes: TBytes;
  lPlanResult: TRemoveWithPlanResult;
  lTransactionResult: TRemoveWithTransactionResult;
  lUnitPath: string;
  lWorkspaceRoot: string;
begin
  CopyFixtureToTemp('RemoveWithApplyFixture', 'remove-with-apply-legacy-missing-context', 'ApplyUnit.pas',
    lDprojPath, lUnitPath);
  BuildPlanForFixture(lDprojPath, lOptions, lPlanResult, lApplyContext);
  lOriginalBytes := TFile.ReadAllBytes(lUnitPath);
  lWorkspaceRoot := TPath.Combine(TPath.GetDirectoryName(lDprojPath),
    '.dak\RemoveWithApplyFixture\remove-with\legacy-missing-context');

  Assert.IsFalse(ApplyRemoveWithPlanTransactionally(lOptions, lDprojPath, lWorkspaceRoot, lPlanResult,
    lTransactionResult, lError), 'Expected legacy apply overload to fail closed for planned edits.');
  Assert.AreEqual('context-fingerprint-missing', RemoveWithTransactionStatusToText(lTransactionResult.fStatus),
    'Expected explicit missing context fingerprint status.');
  Assert.Contains(lError, 'context-fingerprint-missing', 'Expected missing context error to be reported.');
  AssertBytesEqual(lOriginalBytes, TFile.ReadAllBytes(lUnitPath),
    'Legacy overload refusal must preserve source bytes exactly.');
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
  lDiagnostics: TJSONArray;
  lDiagnosticText: string;
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
    AssertJsonArrayKey(lGates.Items[0] as TJSONObject, 'diagnostics', lDiagnostics);
    Assert.IsTrue(lDiagnostics.Count > 0, 'Expected failed build diagnostics in JSON report.');
    lDiagnosticText := lDiagnostics.ToJSON;
    Assert.Contains(lDiagnosticText, 'Intentional rollback fixture failure after remove-with rewrites RollbackUnit.pas',
      'Expected JSON diagnostics to contain the compiler/build failure message.');

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
      'Expected property selector and call-selector skips.');
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
      'Expected property selector and call-selector reports.');
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

function TRemoveWithScopedDeclarationSafetyTests.RunBuildFixture(const aDprojPath, aLogName: string;
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

procedure TRemoveWithScopedDeclarationSafetyTests.ApplyRewritesSafeScopedDeclarationBodies;
var
  lBeforeText: string;
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lUnitPath: string;
  lUnitText: string;
  lVerification: TJSONObject;
begin
  CopyFixtureToTemp('RemoveWithScopedDeclarationFixture', 'remove-with-scoped-declarations', lDprojPath,
    lFixtureDir);
  lUnitPath := TPath.Combine(lFixtureDir, 'ScopedDeclarationUnit.pas');
  lBeforeText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);

  lRoot := RunRemoveWithFixture(lDprojPath, 'apply', 'remove-with-scoped-declarations.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected scoped-declaration apply to finish.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied root status.');
    Assert.AreEqual(4, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected every scoped declaration body to be planned.');
    Assert.AreEqual(0, CountSkippedReason(lRoot.Values['skipped'] as TJSONArray,
      'scoped-declaration-in-with-body'), 'Expected no wholesale scoped-declaration skips.');
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('passed', lVerification.Values['status'].Value,
      'Expected edited scoped-declaration fixture to build after apply.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.AreNotEqual(lBeforeText, lUnitText, 'Apply must edit safe scoped declaration bodies.');
  Assert.IsTrue(Pos('var Count := 1;', lUnitText) > 0, 'Expected inline local variable declaration to stay local.');
  Assert.IsTrue(Pos('aItemPtr^.Count := aItemPtr^.Count + 1;', lUnitText) > 0,
    'Expected member uses before a same-name inline local declaration to be qualified.');
  Assert.IsTrue(Pos('aItemPtr^.Name := IntToStr(Count);', lUnitText) > 0,
    'Expected member assignment to be qualified while local Count remains unqualified.');
  Assert.IsTrue(Pos('var Name := ''local'';', lUnitText) > 0,
    'Expected same-name inline local after a member use to stay local.');
  Assert.IsTrue(Pos('Name := Name + ''x'';', lUnitText) > 0,
    'Expected same-name inline local use after a nested block to stay local.');
  Assert.IsTrue(Pos('aItemPtr^.Name := aItemPtr^.Name + ''x'';', lUnitText) = 0,
    'Expected nested blocks after a local declaration not to end the local range too early.');
  Assert.IsTrue(Pos('for var i := 0 to aItemPtr^.Count do', lUnitText) > 0,
    'Expected inline for variable to stay local while member Count is qualified.');
  Assert.IsTrue(Pos('aItemPtr^.Name := IntToStr(i);', lUnitText) > 0,
    'Expected for body member assignment to be qualified while local i remains unqualified.');
  Assert.IsTrue(Pos('aItemPtr^.Count := aItemPtr^.Count + 1;', lUnitText) > 0,
    'Expected try body member references to be qualified.');
  Assert.IsTrue(Pos('aItemPtr^.Name := E.Message;', lUnitText) > 0,
    'Expected exception body member assignment to be qualified while exception variable remains local.');

  lBuildOutput := RunBuildFixture(lDprojPath, 'remove-with-scoped-declarations-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected edited scoped-declaration fixture to build. Output: ' +
    lBuildOutput);
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
    Assert.AreEqual(5, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected label, case-label, type-qualified, declaration-like, and source-unit-qualified rewrites.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, lSkipped.Count, 'Expected safe expression-role statements to be planned.');
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'unsupported-identifier-role'),
      'Expected known type-qualified calls to remain unchanged instead of blocking the statement.');
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'scoped-declaration-in-with-body'),
      'Expected declaration-like bodies to be rewritten when local declarations can remain unchanged.');
    Assert.AreEqual(0, CountSkippedUnsupportedRole(lSkipped, 'type-qualifier'),
      'Expected known type-qualified calls to remain unchanged instead of reported as unsupported.');
    Assert.AreEqual(0, CountSkippedUnsupportedRole(lSkipped, 'variable-declaration'),
      'Expected declaration-like role to be planned instead of skipped.');
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('passed', lVerification.Values['status'].Value,
      'Expected edited expression-role fixture to build after apply.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('goto LocalLabel;', lUnitText) > 0,
    'Expected goto target to remain unqualified.');
  Assert.IsTrue(Pos('LocalLabel:', lUnitText) > 0,
    'Expected label declaration to remain unqualified.');
  Assert.IsTrue(Pos('aItemPtr^.Name := ''label'';', lUnitText) > 0,
    'Expected labeled with body to be qualified.');
  Assert.IsTrue(Pos('0:' + sLineBreak + '        aItemPtr^.Name := ''case'';', lUnitText) > 0,
    'Expected case label to remain unqualified while the case body is qualified.');
  Assert.IsTrue(Pos('aItemPtr^.Name := TExpressionRoleScope.DefaultName;', lUnitText) > 0,
    'Expected type-qualified call to stay unchanged while the receiver member is qualified.');
  Assert.IsTrue(Pos('ExpressionRoleSupportUnit.TouchName(aItemPtr^.Name);', lUnitText) > 0,
    'Expected the safe member argument to be qualified.');
  Assert.IsTrue(Pos('var Name := ''local'';', lUnitText) > 0,
    'Expected local inline variable declaration to remain unqualified.');
  Assert.IsTrue(Pos('aItemPtr^.Count := Length(Name);', lUnitText) > 0,
    'Expected declaration-like body member assignment to be qualified while local Name remains unqualified.');
  Assert.IsTrue(Pos('aItemPtr^.ExpressionRoleSupportUnit', lUnitText) = 0,
    'Expected the source-unit qualifier to remain unchanged.');
  Assert.IsTrue(Pos('aItemPtr^.TExpressionRoleScope', lUnitText) = 0,
    'Expected the type qualifier to remain unchanged.');
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
    Assert.AreEqual(2, lPlannedEdits.Count, 'Expected multiline and simple safe records to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(4, lSkipped.Count, 'Expected unsupported complex source-model statements to be skipped.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-attribute'),
      'Expected attributed type declaration to be reported explicitly.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-conditional-region'),
      'Expected conditional type declaration to be reported explicitly.');
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
    Assert.AreEqual(2, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected modeled compiler and RTL routine-call bodies to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected RTL routine-call roots to be resolved.');
    AssertJsonObjectKey(lRoot, 'verification', lVerification);
    Assert.AreEqual('passed', lVerification.Values['status'].Value,
      'Expected edited external-routine fixture to build after apply.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with lKnown do', lUnitText) = 0, 'Expected known-routine with to be removed.');
  Assert.IsTrue(Pos('with lUnknown do', lUnitText) = 0, 'Expected RTL routine-call with to be removed.');
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
  Assert.IsTrue(Pos('lWithExternalRoutineRecordPtr1^.Count := Random(lWithExternalRoutineRecordPtr1^.Count) + ' +
    'cBoost;', lUnitText) > 0, 'Expected RTL Random call to remain while its member argument is qualified.');
  Assert.IsTrue(Pos('if lWithExternalRoutineRecordPtr1^.Flag = erfOne then', lUnitText) > 0,
    'Expected enum expression member to be qualified after RTL routine resolution.');
  Assert.IsTrue(Pos('lWithExternalRoutineRecordPtr1^.Count := lWithExternalRoutineRecordPtr1^.Count + ' +
    'SizeOf(TExternalRoutineRecord);', lUnitText) > 0,
    'Expected type-name expression member to be qualified after RTL routine resolution.');
  Assert.IsTrue(Pos('lWithExternalRoutineRecordPtr1^.Random', lUnitText) = 0,
    'Expected unknown routine call root not to be receiver-qualified.');
end;

function TRemoveWithIntrinsicSymbolTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithIntrinsicSymbolTests.AssertClassification(const aClassifications: TJSONArray;
  const aIdentifier, aStatus, aResolutionKind, aReason: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) and
      SameText(lObject.GetValue<string>('status', ''), aStatus) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), aResolutionKind) and
      SameText(lObject.GetValue<string>('reason', ''), aReason) then
      Exit;
  end;
  Assert.Fail('Expected classification ' + aIdentifier + ':' + aStatus + ':' + aResolutionKind + ':' + aReason);
end;

procedure TRemoveWithIntrinsicSymbolTests.AssertClassificationSymbolMap(const aClassifications: TJSONArray;
  const aIdentifier, aKind, aSourceKind: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
  lSymbolMap: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if not SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) then
      Continue;
    AssertJsonObjectKey(lObject, 'symbolMap', lSymbolMap);
    Assert.IsTrue(lSymbolMap.GetValue<Boolean>('found', False), 'Expected Symbol Map hit for ' + aIdentifier);
    Assert.AreEqual(aKind, lSymbolMap.GetValue<string>('kind', ''), 'Unexpected Symbol Map kind for ' + aIdentifier);
    Assert.AreEqual(aSourceKind, lSymbolMap.GetValue<string>('sourceKind', ''),
      'Unexpected Symbol Map source kind for ' + aIdentifier);
    Assert.AreEqual('exact', lSymbolMap.GetValue<string>('confidence', ''),
      'Expected exact Symbol Map confidence for ' + aIdentifier);
    Exit;
  end;
  Assert.Fail('Expected Symbol Map classification for ' + aIdentifier);
end;

procedure TRemoveWithIntrinsicSymbolTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
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

function TRemoveWithIntrinsicSymbolTests.CountSkippedReason(const aSkipped: TJSONArray;
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

function TRemoveWithIntrinsicSymbolTests.RunRemoveWithFixture(const aDprojPath, aMode, aLogName: string;
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

procedure TRemoveWithIntrinsicSymbolTests.PlanPreservesModeledIntrinsicsAndBlocksUnknownCalls;
var
  lClassifications: TJSONArray;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lPlannedEdits: TJSONArray;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
begin
  CopyFixtureToTemp('RemoveWithIntrinsicSymbolFixture', 'remove-with-intrinsic-symbols', lDprojPath, lFixtureDir);

  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-intrinsic-symbols.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected intrinsic-symbol plan to succeed.');
    Assert.AreEqual('ok', lRoot.Values['status'].Value, 'Expected ok root status.');
    lPlannedEdits := lRoot.Values['plannedEdits'] as TJSONArray;
    Assert.AreEqual(2, lPlannedEdits.Count, 'Expected modeled intrinsic statements to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected arbitrary unknown project routine calls to remain blocked.');

    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
  finally
    lRoot.Free;
  end;
end;

function TRemoveWithControlCharacterLiteralTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithControlCharacterLiteralTests.AssertNoClassification(const aClassifications: TJSONArray;
  const aIdentifier: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) then
      Assert.Fail('Unexpected classification for control-character literal ' + aIdentifier);
  end;
end;

procedure TRemoveWithControlCharacterLiteralTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
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

function TRemoveWithControlCharacterLiteralTests.CountSkippedReason(const aSkipped: TJSONArray;
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

function TRemoveWithControlCharacterLiteralTests.RunRemoveWithFixture(const aDprojPath, aMode,
  aLogName: string; out aExitCode: Cardinal): TJSONObject;
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

procedure TRemoveWithControlCharacterLiteralTests.PlanIgnoresControlCharacterLiteralsAndKeepsPointerSyntax;
var
  lClassifications: TJSONArray;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lPlannedEdits: TJSONArray;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithControlCharacterLiteralFixture', 'remove-with-control-character-literals',
    lDprojPath, lFixtureDir);

  lRoot := RunRemoveWithFixture(lDprojPath, 'apply', 'remove-with-control-character-literals.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected control-character literal apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied root status.');
    lPlannedEdits := lRoot.Values['plannedEdits'] as TJSONArray;
    Assert.AreEqual(1, lPlannedEdits.Count, 'Expected control-character literal statement to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected control-character literals not to be reported as missing symbols.');

    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    AssertNoClassification(lClassifications, 'J');
    AssertNoClassification(lClassifications, 'M');
    AssertNoClassification(lClassifications, 'I');
  finally
    lRoot.Free;
  end;

  lUnitPath := TPath.Combine(lFixtureDir, 'ControlCharacterLiteralUnit.pas');
  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('with lKnown do', lUnitText) = 0, 'Expected with statement to be removed.');
  Assert.IsTrue(Pos('''row'' + ^J + ^m + ^I', lUnitText) > 0,
    'Expected control-character literals to stay unchanged.');
  Assert.IsTrue(Pos('lOtherPtr^.Count + lWithControlCharacterRecordPtr^.Count', lUnitText) > 0,
    'Expected pointer dereference syntax to stay intact while receiver member is qualified.');
end;

function TRemoveWithImplementationGlobalTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithImplementationGlobalTests.AssertClassification(const aClassifications: TJSONArray;
  const aIdentifier, aStatus, aResolutionKind, aReason: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) and
      SameText(lObject.GetValue<string>('status', ''), aStatus) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), aResolutionKind) and
      SameText(lObject.GetValue<string>('reason', ''), aReason) then
      Exit;
  end;
  Assert.Fail('Expected classification ' + aIdentifier + ':' + aStatus + ':' + aResolutionKind + ':' + aReason);
end;

procedure TRemoveWithImplementationGlobalTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
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

function TRemoveWithImplementationGlobalTests.CountSkippedReason(const aSkipped: TJSONArray;
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

function TRemoveWithImplementationGlobalTests.RunRemoveWithFixture(const aDprojPath, aMode,
  aLogName: string; out aExitCode: Cardinal): TJSONObject;
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

procedure TRemoveWithImplementationGlobalTests.PlanResolvesGlobalsDeclaredAfterImplementationRoutines;
var
  lClassifications: TJSONArray;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lPlannedEdits: TJSONArray;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
begin
  CopyFixtureToTemp('RemoveWithImplementationGlobalFixture', 'remove-with-implementation-globals', lDprojPath,
    lFixtureDir);

  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-implementation-globals.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected implementation-global plan to succeed.');
    lPlannedEdits := lRoot.Values['plannedEdits'] as TJSONArray;
    Assert.AreEqual(1, lPlannedEdits.Count, 'Expected implementation globals after routines to be resolved.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected implementation globals after routines not to be missing symbols.');

    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
  finally
    lRoot.Free;
  end;
end;

function TRemoveWithNestedRoutineScopeTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithNestedRoutineScopeTests.AssertClassification(const aClassifications: TJSONArray;
  const aIdentifier, aStatus, aResolutionKind, aReason: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) and
      SameText(lObject.GetValue<string>('status', ''), aStatus) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), aResolutionKind) and
      SameText(lObject.GetValue<string>('reason', ''), aReason) then
      Exit;
  end;
  Assert.Fail('Expected classification ' + aIdentifier + ':' + aStatus + ':' + aResolutionKind + ':' + aReason);
end;

procedure TRemoveWithNestedRoutineScopeTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
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

function TRemoveWithNestedRoutineScopeTests.CountSkippedReason(const aSkipped: TJSONArray;
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

function TRemoveWithNestedRoutineScopeTests.RunRemoveWithFixture(const aDprojPath, aMode,
  aLogName: string; out aExitCode: Cardinal): TJSONObject;
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

procedure TRemoveWithNestedRoutineScopeTests.PlanResolvesOuterRoutineSymbolsCapturedByNestedRoutine;
var
  lClassifications: TJSONArray;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lPlannedEdits: TJSONArray;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
begin
  CopyFixtureToTemp('RemoveWithNestedRoutineScopeFixture', 'remove-with-nested-routine-scope', lDprojPath,
    lFixtureDir);

  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-nested-routine-scope.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected nested-routine scope plan to succeed.');
    lPlannedEdits := lRoot.Values['plannedEdits'] as TJSONArray;
    Assert.AreEqual(1, lPlannedEdits.Count, 'Expected captured outer routine locals to be resolved.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected captured outer routine locals not to be missing symbols.');

    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
  finally
    lRoot.Free;
  end;
end;

function TRemoveWithEnumConstTypeAliasTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithEnumConstTypeAliasTests.AssertClassification(const aClassifications: TJSONArray;
  const aIdentifier, aStatus, aResolutionKind, aReason: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) and
      SameText(lObject.GetValue<string>('status', ''), aStatus) and
      SameText(lObject.GetValue<string>('resolutionKind', ''), aResolutionKind) and
      SameText(lObject.GetValue<string>('reason', ''), aReason) then
      Exit;
  end;
  Assert.Fail('Expected classification ' + aIdentifier + ':' + aStatus + ':' + aResolutionKind + ':' + aReason);
end;

procedure TRemoveWithEnumConstTypeAliasTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
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

function TRemoveWithEnumConstTypeAliasTests.CountSkippedReason(const aSkipped: TJSONArray;
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

function TRemoveWithEnumConstTypeAliasTests.RunRemoveWithFixture(const aDprojPath, aMode,
  aLogName: string; out aExitCode: Cardinal): TJSONObject;
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

procedure TRemoveWithEnumConstTypeAliasTests.PlanResolvesEnumConstantsTypedConstantsAndAliases;
var
  lClassifications: TJSONArray;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lPlannedEdits: TJSONArray;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
begin
  CopyFixtureToTemp('RemoveWithEnumConstTypeAliasFixture', 'remove-with-enum-const-type-alias', lDprojPath,
    lFixtureDir);

  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-enum-const-type-alias.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected enum/const/type-alias plan to succeed.');
    lPlannedEdits := lRoot.Values['plannedEdits'] as TJSONArray;
    Assert.AreEqual(1, lPlannedEdits.Count, 'Expected enum constants, typed constants, and aliases to resolve.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected enum constants, typed constants, and aliases not to be missing symbols.');

    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    Assert.IsTrue(lClassifications.Count > 0,
      'Expected semantic report classifications without legacy fallback rows.');
  finally
    lRoot.Free;
  end;
end;

function TRemoveWithConditionalDirectiveTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithConditionalDirectiveTests.AssertNoClassification(const aClassifications: TJSONArray;
  const aIdentifier: string);
var
  lItem: TJSONValue;
  lObject: TJSONObject;
begin
  for lItem in aClassifications do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lObject := lItem as TJSONObject;
    if SameText(lObject.GetValue<string>('identifier', ''), aIdentifier) then
      Assert.Fail('Unexpected conditional-directive classification for ' + aIdentifier);
  end;
end;

procedure TRemoveWithConditionalDirectiveTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
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

function TRemoveWithConditionalDirectiveTests.CountSkippedReason(const aSkipped: TJSONArray;
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

function TRemoveWithConditionalDirectiveTests.RunRemoveWithFixture(const aDprojPath, aMode,
  aLogName: string; out aExitCode: Cardinal): TJSONObject;
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

procedure TRemoveWithConditionalDirectiveTests.PlanIgnoresInactiveConditionalBranches;
var
  lClassifications: TJSONArray;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSummary: TJSONObject;
  lWithStatements: TJSONArray;
begin
  CopyFixtureToTemp('RemoveWithConditionalDirectiveFixture', 'remove-with-conditional-directives', lDprojPath,
    lFixtureDir);

  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-conditional-directives.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected conditional-directive plan to succeed.');
    lWithStatements := lRoot.Values['withStatements'] as TJSONArray;
    Assert.AreEqual(0, lWithStatements.Count,
      'Plan reports should omit detailed with-statement rows.');
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    Assert.AreEqual(2, (lSummary.Values['withStatements'] as TJSONNumber).AsInt,
      'Expected project-defined active with statements to be included and inactive statements to be excluded.');
    Assert.AreEqual(2, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected active statements with inactive branch text to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected inactive branch identifiers not to be scanned.');
    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonArrayKey(lResolver, 'classifications', lClassifications);
    AssertNoClassification(lClassifications, 'ProgFun');
    AssertNoClassification(lClassifications, 'InlineMissingSymbol');
    AssertNoClassification(lClassifications, 'nd');
    AssertNoClassification(lClassifications, 'ND');
  finally
    lRoot.Free;
  end;
end;

function TRemoveWithUnresolvedReasonReportTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithUnresolvedReasonReportTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
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

function TRemoveWithUnresolvedReasonReportTests.RunRemoveWithFixture(const aDprojPath, aMode,
  aLogName: string; out aExitCode: Cardinal): TJSONObject;
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

procedure TRemoveWithUnresolvedReasonReportTests.PlanReportsDetailedUnresolvedReasonBuckets;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lResolver: TJSONObject;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lSkippedItem: TJSONObject;
  lUnresolvedReasons: TJSONObject;
begin
  CopyFixtureToTemp('RemoveWithUnresolvedReasonFixture', 'remove-with-unresolved-reason', lDprojPath,
    lFixtureDir);

  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-unresolved-reason.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected unresolved-reason plan to succeed.');
    AssertJsonObjectKey(lRoot, 'resolver', lResolver);
    AssertJsonObjectKey(lResolver, 'unresolvedReasons', lUnresolvedReasons);
    Assert.AreEqual(0, lUnresolvedReasons.Count,
      'Expected semantic report projection not to synthesize legacy fallback buckets.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(1, lSkipped.Count, 'Expected one skipped statement.');
    lSkippedItem := lSkipped.Items[0] as TJSONObject;
    Assert.AreEqual('true-symbol-not-found', lSkippedItem.GetValue<string>('detailedReason', ''),
      'Expected skipped statement to keep detailed blocking reason.');
  finally
    lRoot.Free;
  end;
end;

function TRemoveWithSymbolMapParityReportTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithSymbolMapParityReportTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
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

function TRemoveWithSymbolMapParityReportTests.RunRemoveWithFixture(const aDprojPath, aMode,
  aLogName: string; out aExitCode: Cardinal): TJSONObject;
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

procedure TRemoveWithSymbolMapParityReportTests.PlanReportsLookupSourceCountsAndFallbackAccounting;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSummary: TJSONObject;
  lTelemetry: TJSONObject;
begin
  CopyFixtureToTemp('RemoveWithIntrinsicSymbolFixture', 'remove-with-symbol-map-parity', lDprojPath, lFixtureDir);

  lRoot := RunRemoveWithFixture(lDprojPath, 'plan', 'remove-with-symbol-map-parity.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected parity plan to succeed.');
    AssertJsonObjectKey(lRoot, 'migrationTelemetry', lTelemetry);
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    AssertJsonNumberKey(lTelemetry, 'localModelHits');
    AssertJsonNumberKey(lTelemetry, 'symbolMapHits');
    AssertJsonNumberKey(lTelemetry, 'symbolMapMisses');
    Assert.AreEqual(0, lTelemetry.GetValue<Integer>('intrinsicAllowlistFallbacks'),
      'Expected external routine facts to come from DelphiSemantics rather than DAK fallback allowlists.');
    AssertJsonNumberKey(lTelemetry, 'trueUnknowns');
    Assert.AreEqual(lSummary.GetValue<Integer>('plannedEdits'), lTelemetry.GetValue<Integer>('plannedEdits'),
      'Expected planned telemetry to match summary.');
    Assert.AreEqual(lSummary.GetValue<Integer>('skipped'), lTelemetry.GetValue<Integer>('skippedStatements'),
      'Expected skipped telemetry to match summary.');
    Assert.IsTrue(lTelemetry.GetValue<Integer>('elapsedPlanningMs') >= 0,
      'Expected planning elapsed time telemetry.');
  finally
    lRoot.Free;
  end;
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
    Assert.AreEqual(0, lWithStatements.Count,
      'Plan reports should omit detailed with-statement rows.');
    Assert.AreEqual(3, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected multi-selector, RTL Random, and type-qualified statements to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(2, lSkipped.Count, 'Expected risky corpus statements to be skipped.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-attribute'),
      'Expected attributed declaration skip.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-conditional-region'),
      'Expected conditional declaration skip.');
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'unsupported-identifier-role'),
      'Expected type-qualified body references to remain unqualified instead of skipped.');
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected RTL Random call body to resolve.');
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    Assert.AreEqual(3, (lSummary.Values['filesScanned'] as TJSONNumber).AsInt,
      'Expected the multi-unit corpus project to scan all project files.');
    Assert.AreEqual(5, (lSummary.Values['withStatements'] as TJSONNumber).AsInt,
      'Expected stable summary statement count.');
    Assert.AreEqual(3, (lSummary.Values['plannedEdits'] as TJSONNumber).AsInt,
      'Expected stable summary plan count.');
    Assert.AreEqual(2, (lSummary.Values['skipped'] as TJSONNumber).AsInt,
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

function TRemoveWithBoundRewriteTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

procedure TRemoveWithBoundRewriteTests.CopyFixtureToTemp(const aFixtureName, aTempName: string;
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

function TRemoveWithBoundRewriteTests.CountSkippedReason(const aSkipped: TJSONArray;
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

function TRemoveWithBoundRewriteTests.RunApplyFixture(const aDprojPath, aLogName: string;
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

procedure TRemoveWithBoundRewriteTests.ApplyUsesBoundReferencesAndLeavesNonReferencesUnqualified;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lUnitPath: string;
  lUnitText: string;
begin
  CopyFixtureToTemp('RemoveWithBoundRewriteFixture', 'remove-with-bound-rewrite', lDprojPath, lFixtureDir);
  lUnitPath := TPath.Combine(lFixtureDir, 'BoundRewriteUnit.pas');

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-bound-rewrite.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected bound-rewrite apply to succeed.');
    Assert.AreEqual('applied', lRoot.Values['status'].Value, 'Expected applied root status.');
    Assert.AreEqual(4, (lRoot.Values['plannedEdits'] as TJSONArray).Count,
      'Expected the semantically bound, declaration-like, and comparison with statements to be planned.');
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'scoped-declaration-in-with-body'),
      'Expected inline declaration body to be planned when local declarations can remain unchanged.');
  finally
    lRoot.Free;
  end;

  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('var Name := ''local'';', lUnitText) > 0,
    'Expected declaration identifier to remain local.');
  Assert.IsTrue(Pos('.Count := Length(Name);', lUnitText) > 0,
    'Expected declaration body member assignment to be qualified while local Name remains unqualified.');
  Assert.IsTrue(Pos('.Child <> nil', lUnitText) > 0,
    'Expected not-equal comparison member to be qualified, not treated as a generic type name.');
  Assert.IsTrue(Pos('.Count<', lUnitText) > 0,
    'Expected compact less-than comparison left member to be qualified, not treated as a generic type name.');
  Assert.IsTrue(Pos('<' + 'lWithBoundRewriteRecordPtr', lUnitText) > 0,
    'Expected compact less-than comparison right member to be qualified.');
  Assert.IsTrue(Pos('goto BoundLabel;', lUnitText) > 0, 'Expected goto target to remain unqualified.');
  Assert.IsTrue(Pos('BoundLabel:', lUnitText) > 0, 'Expected label declaration to remain unqualified.');
  Assert.IsTrue(Pos('TBoundRewriteCast(lCast).Name', lUnitText) > 0,
    'Expected typecast target to remain unqualified.');
  Assert.IsTrue(Pos('.TBoundRewriteCast(lCast)', lUnitText) = 0,
    'Planner must not qualify type names that only look like receiver members lexically.');
  Assert.IsTrue(Pos('.Name := TBoundRewriteCast(lCast).Name;', lUnitText) > 0,
    'Expected bound receiver member assignment to be qualified.');
  Assert.IsTrue(Pos('.Count := .Count + 1;', lUnitText) = 0,
    'Expected both count references to use an explicit qualifier.');
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
    AssertApplySummary(lRoot, 9, 0);
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
    AssertApplySummary(lRoot, 5, 0);
    AssertVerificationPassed(lRoot);
    AssertTransactionFileCount(lRoot, 1);
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'unsupported-identifier-role'),
      'Expected expression-role type-qualified references to be preserved without skips.');
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'scoped-declaration-in-with-body'),
      'Expected expression-role scoped declaration body to be planned.');
  finally
    lRoot.Free;
  end;

  CopyFixtureToTemp('RemoveWithComplexSourceModelFixture', 'remove-with-hardening-complex-source', lDprojPath,
    lFixtureDir);
  lRoot := RunApplyFixture(lDprojPath, 'remove-with-hardening-complex-source.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected complex source-model hardening apply to succeed.');
    AssertApplySummary(lRoot, 2, 4);
    AssertVerificationPassed(lRoot);
    AssertTransactionFileCount(lRoot, 1);
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-attribute'),
      'Expected attributed source-model skip.');
    Assert.AreEqual(1, CountSkippedReason(lSkipped, 'unsupported-source-model-conditional-region'),
      'Expected conditional source-model skip.');
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
    AssertApplySummary(lRoot, 2, 0);
    AssertVerificationPassed(lRoot);
    AssertTransactionFileCount(lRoot, 1);
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected RTL external routine calls to resolve.');
  finally
    lRoot.Free;
  end;
end;

procedure TRemoveWithHardeningApplyTests.ApplyRewritesScopedDeclarationFixture;
var
  lDprBefore: TBytes;
  lBeforeText: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFixtureDir: string;
  lRoot: TJSONObject;
  lSkipped: TJSONArray;
  lUnitPath: string;
begin
  CopyFixtureToTemp('RemoveWithScopedDeclarationFixture', 'remove-with-hardening-scoped-declarations',
    lDprojPath, lFixtureDir);
  lUnitPath := TPath.Combine(lFixtureDir, 'ScopedDeclarationUnit.pas');
  lDprBefore := TFile.ReadAllBytes(TPath.Combine(lFixtureDir, 'RemoveWithScopedDeclarationFixture.dpr'));
  lBeforeText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);

  lRoot := RunApplyFixture(lDprojPath, 'remove-with-hardening-scoped-declarations.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected scoped declaration hardening apply to succeed.');
    AssertApplySummary(lRoot, 4, 0);
    AssertVerificationPassed(lRoot);
    AssertTransactionFileCount(lRoot, 1);
    lSkipped := lRoot.Values['skipped'] as TJSONArray;
    Assert.AreEqual(0, CountSkippedReason(lSkipped, 'scoped-declaration-in-with-body'),
      'Expected scoped-declaration bodies to be rewritten when local declarations can remain unchanged.');
  finally
    lRoot.Free;
  end;

  AssertBytesEqual(lDprBefore, TFile.ReadAllBytes(TPath.Combine(lFixtureDir, 'RemoveWithScopedDeclarationFixture.dpr')),
    'Scoped declaration DPR must remain byte-for-byte unchanged.');
  Assert.AreNotEqual(lBeforeText, TFile.ReadAllText(lUnitPath, TEncoding.UTF8),
    'Scoped declaration unit should be edited after safe rewrite.');
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

function TRemoveWithProprietaryProjectTests.RunRemoveWithPlan(const aDprojPath, aTargetDir, aLogName: string;
  out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lJsonPath: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lJsonPath := TPath.Combine(TempRoot, aLogName);
  lLogPath := TPath.ChangeExtension(lJsonPath, '.stdout.log');
  lArgs := 'remove-with --project ' + QuoteArg(aDprojPath) + ' --dir ' + QuoteArg(aTargetDir) +
    ' --mode plan --format json --output ' + QuoteArg(lJsonPath) + ' --verbose true';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start remove-with maxTdb plan process.');
  Assert.IsTrue(TFile.Exists(lJsonPath), 'Expected maxTdb plan JSON output file: ' + lJsonPath);
  lOutput := TFile.ReadAllText(lJsonPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable maxTdb remove-with JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
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

function TRemoveWithProprietaryProjectTests.CountSkippedReason(const aSkipped: TJSONArray;
  const aReason: string): Integer;
var
  i: Integer;
  lItem: TJSONObject;
begin
  Result := 0;
  for i := 0 to aSkipped.Count - 1 do
  begin
    if not (aSkipped.Items[i] is TJSONObject) then
      Continue;
    lItem := aSkipped.Items[i] as TJSONObject;
    if SameText(lItem.GetValue<string>('reason', ''), aReason) or
      SameText(lItem.GetValue<string>('detailedReason', ''), aReason) then
      Inc(Result);
  end;
end;

procedure TRemoveWithProprietaryProjectTests.AssertSkippedReasonBetween(const aSkipped: TJSONArray;
  const aReason: string; const aMin, aMax: Integer);
var
  lCount: Integer;
begin
  lCount := CountSkippedReason(aSkipped, aReason);
  Assert.IsTrue(lCount >= aMin,
    Format('Expected maxTdb skip bucket %s count >= %d, got %d.', [aReason, aMin, lCount]));
  Assert.IsTrue(lCount <= aMax,
    Format('Expected maxTdb skip bucket %s count <= %d, got %d.', [aReason, aMax, lCount]));
end;

procedure TRemoveWithProprietaryProjectTests.PlanCloneOfMaxTdbWhenFixtureExistsReportsTelemetryAndPerformance;
var
  lCloneBytes: TArray<TBytes>;
  lCloneDir: string;
  lClonePaths: TArray<string>;
  lDprojPath: string;
  lExitCode: Cardinal;
  lMismatches: TJSONArray;
  lOriginalBytes: TArray<TBytes>;
  lOriginalPaths: TArray<string>;
  lParity: TJSONObject;
  lRoot: TJSONObject;
  lSourceDir: string;
  lSkipped: TJSONArray;
  lSummary: TJSONObject;
  lTargetDir: string;
  lTelemetry: TJSONObject;
begin
  lSourceDir := TPath.Combine(RepoRoot, 'tests\fixtures\test-projects\maxTdb');
  if not TDirectory.Exists(lSourceDir) then
  begin
    Assert.Pass('Optional proprietary maxTdb fixture is absent; no maxTdb remove-with plan check was run.');
    Exit;
  end;

  SnapshotSourceFiles(lSourceDir, lOriginalPaths, lOriginalBytes);
  Assert.IsTrue(Length(lOriginalPaths) > 0, 'Expected maxTdb source files to snapshot.');

  CopyDirectoryToTemp(lSourceDir, 'remove-with-maxtdb-semantic-gate', lCloneDir);
  lDprojPath := FindMaxTdbProject(lCloneDir);
  lTargetDir := TPath.Combine(lCloneDir, 'src');
  SnapshotSourceFiles(lCloneDir, lClonePaths, lCloneBytes);

  lRoot := RunRemoveWithPlan(lDprojPath, lTargetDir, 'remove-with-maxtdb-semantic-gate.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected maxTdb plan mode to succeed.');
    Assert.AreEqual('ok', lRoot.Values['status'].Value, 'Expected ok maxTdb plan status.');
    Assert.AreEqual('plan', lRoot.Values['mode'].Value, 'Expected maxTdb plan mode.');
    AssertJsonObjectKey(lRoot, 'summary', lSummary);
    AssertJsonObjectKey(lRoot, 'migrationTelemetry', lTelemetry);
    Assert.AreEqual(667, (lSummary.Values['withStatements'] as TJSONNumber).AsInt,
      'Expected maxTdb plan to retain the current with-statement coverage baseline.');
    Assert.AreEqual(215, (lSummary.Values['plannedEdits'] as TJSONNumber).AsInt,
      'Expected maxTdb planned edits to stay at the evidence-backed semantic rewrite baseline.');
    Assert.IsTrue((lSummary.Values['skipped'] as TJSONNumber).AsInt <= 460,
      'Expected maxTdb skipped count not to regress materially.');
    AssertJsonArrayKey(lRoot, 'skipped', lSkipped);
    Assert.AreEqual((lSummary.Values['skipped'] as TJSONNumber).AsInt, lSkipped.Count,
      'Expected skipped array count to match summary.');
    AssertJsonObjectKey(lRoot, 'semanticDtoParity', lParity);
    AssertJsonArrayKey(lParity, 'mismatches', lMismatches);
    Assert.AreEqual('passed', lParity.GetValue<string>('status', ''),
      'Expected maxTdb semantic DTO parity to pass.');
    Assert.AreEqual('0', lParity.Values['mismatchCount'].Value,
      'Expected maxTdb semantic DTO parity to have no mismatches.');
    Assert.AreEqual(0, lMismatches.Count,
      'Expected maxTdb semantic DTO parity mismatch array to be empty.');
    AssertSkippedReasonBetween(lSkipped, 'scoped-declaration-in-with-body', 0, 0);
    AssertSkippedReasonBetween(lSkipped, 'unsupported-identifier-role', 0, 0);
    AssertSkippedReasonBetween(lSkipped, 'controlled-with-statement', 0, 3);
    AssertSkippedReasonBetween(lSkipped, 'temp-declaration-requires-routine-var-section', 0, 3);
    AssertSkippedReasonBetween(lSkipped, 'type-source-not-indexed', 0, 460);
    Assert.AreEqual(335, CountSkippedReason(lSkipped, 'symbol-not-found'),
      'Expected maxTdb generic symbol-not-found skips to stay at the current baseline.');
    Assert.AreEqual((lSummary.Values['plannedEdits'] as TJSONNumber).AsInt,
      lTelemetry.GetValue<Integer>('plannedEdits'), 'Expected planned telemetry to match summary.');
    Assert.AreEqual((lSummary.Values['skipped'] as TJSONNumber).AsInt,
      lTelemetry.GetValue<Integer>('skippedStatements'), 'Expected skipped telemetry to match summary.');
    AssertJsonNumberKey(lTelemetry, 'localModelHits');
    Assert.AreEqual(0, lTelemetry.GetValue<Integer>('intrinsicAllowlistFallbacks'),
      'Expected external routine facts to come from DelphiSemantics rather than DAK fallback allowlists.');
    AssertJsonNumberKey(lTelemetry, 'trueUnknowns');
    Assert.IsTrue(lTelemetry.GetValue<Integer>('elapsedPlanningMs') > 0,
      'Expected planner elapsed telemetry.');
    Assert.IsTrue(lTelemetry.GetValue<Integer>('elapsedPlanningMs') < 300000,
      'Expected planner elapsed telemetry to stay inside the documented maxTdb tolerance.');
  finally
    lRoot.Free;
  end;

  AssertSnapshotUnchanged(lOriginalPaths, lOriginalBytes,
    'Original proprietary maxTdb fixture must never be edited.');
  AssertSnapshotUnchanged(lClonePaths, lCloneBytes, 'Plan mode must leave cloned maxTdb sources unchanged.');
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
  lDecision: TRemoveWithTempDecision;
  lDprojPath: string;
  lError: string;
  lInfo: TRemoveWithSelectorTypeInfo;
  lInventory: TRemoveWithFactSet;
  lOptions: TAppOptions;
  lSourceDir: string;
  lSymbol: TRemoveWithSymbolInfo;
  lFoundBitArrayListPtr: Boolean;
  lFoundDatFile: Boolean;
  lFoundDatFilePtr: Boolean;
  lFoundDf: Boolean;
  lFoundRelFiles: Boolean;
  function DescribeMaxTdbSelectorSymbols(const aNames: array of string): string;
  var
    lName: string;
    lSymbol: TRemoveWithSymbolInfo;
  begin
    Result := '';
    for lSymbol in lInventory.fSymbols do
    begin
      for lName in aNames do
      begin
        if not SameText(lSymbol.fName, lName) then
          Continue;
        Result := Result + Format('%s kind=%s type=%s owner=%s routine=%s line=%d endLine=%d; ',
          [lSymbol.fName, RemoveWithSymbolKindToText(lSymbol.fKind), lSymbol.fTypeName, lSymbol.fOwnerType,
          lSymbol.fRoutineName, lSymbol.fLine, lSymbol.fEndLine]);
        Break;
      end;
    end;
  end;
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

  Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lInventory, lError),
    'Expected maxTdb symbol inventory build to succeed: ' + lError);

  lFoundBitArrayListPtr := False;
  lFoundDatFile := False;
  lFoundDatFilePtr := False;
  lFoundDf := False;
  lFoundRelFiles := False;
  lSymbol := Default(TRemoveWithSymbolInfo);
  for lSymbol in lInventory.fSymbols do
  begin
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and SameText(lSymbol.fName, 'TBitArrayListPtr') and
      SameText(lSymbol.fTypeName, '^TBitArrayList') then
      lFoundBitArrayListPtr := True;
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and SameText(lSymbol.fName, 'DatFile') then
      lFoundDatFile := True;
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and SameText(lSymbol.fName, 'DatFilePtr') and
      SameText(lSymbol.fTypeName, '^DatFile') then
      lFoundDatFilePtr := True;
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskUnitGlobal) and SameText(lSymbol.fName, 'DF') and
      SameText(lSymbol.fTypeName, 'array[1..cMaxFilesAllowed + 1] of DatFilePtr') then
      lFoundDf := True;
  end;

  Assert.IsTrue(lFoundBitArrayListPtr, 'Expected maxTdb TBitArrayListPtr alias to be indexed.');
  Assert.IsTrue(lFoundDatFile, 'Expected maxTdb DatFile record type to be indexed.');
  Assert.IsTrue(lFoundDatFilePtr, 'Expected maxTdb DatFilePtr alias to be indexed.');
  Assert.IsTrue(lFoundDf, 'Expected maxTdb DF global pointer array to be indexed.');
  for lSymbol in lInventory.fSymbols do
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskParameter) and SameText(lSymbol.fName, 'RelFiles') and
      SameText(lSymbol.fRoutineName, 'DoMarkBits') then
    begin
      Assert.AreEqual('', lSymbol.fTypeName, 'Expected untyped RelFiles parameter to keep an empty type.');
      lFoundRelFiles := True;
    end;
  Assert.IsTrue(lFoundRelFiles,
    'Expected maxTdb untyped RelFiles parameter to be available through semantic facts.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, '', 'DF[d]^', lInfo),
    'Expected maxTdb DF selector resolver to run.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected maxTdb DF selector status. Type=' + lInfo.fTypeName + ' Reason=' + lInfo.fReason);
  Assert.AreEqual('DatFile', lInfo.fTypeName, 'Expected maxTdb DF selector receiver type.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'SetRec', 'DF[c]^.IndFiles[AktIndex]^', lInfo),
    'Expected maxTdb IndFiles selector resolver to run.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected maxTdb IndFiles selector status. Type=' + lInfo.fTypeName + ' Reason=' + lInfo.fReason +
    ' Symbols=' + DescribeMaxTdbSelectorSymbols(['IndFiles', 'SetRec', 'DatFile']));
  Assert.AreEqual('IndexFile', lInfo.fTypeName, 'Expected maxTdb IndFiles selector receiver type.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'BitArraySum', 'BitArrayListPtr^[c]', lInfo),
    'Expected maxTdb pointer-array selector resolver to run.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected maxTdb pointer-array selector status. Type=' + lInfo.fTypeName + ' Reason=' + lInfo.fReason);
  Assert.AreEqual('TBitArray', lInfo.fTypeName, 'Expected pointer-array selector receiver type.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'NewDATFile', 'D^', lInfo),
    'Expected maxTdb parent-scope pointer selector resolver to run.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected maxTdb parent-scope pointer selector status. Type=' + lInfo.fTypeName + ' Reason=' + lInfo.fReason +
    ' Symbols=' + DescribeMaxTdbSelectorSymbols(['DBF2DAT', 'NewDATFile', 'D', 'DatFile', 'DatFilePtr']));
  Assert.AreEqual('DatFile', lInfo.fTypeName, 'Expected maxTdb parent-scope pointer selector receiver type.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'GetNumVal', 'num_rec', lInfo),
    'Expected maxTdb anonymous local record selector resolver to run.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected maxTdb anonymous local record selector status. Type=' + lInfo.fTypeName + ' Reason=' + lInfo.fReason);
  Assert.IsTrue(EndsText('.num_rec', lInfo.fTypeName), 'Expected synthetic num_rec receiver type.');
  Assert.IsTrue(PlanRemoveWithTempPolicy(lInventory, 'GetNumVal', 'num_rec', lDecision),
    'Expected maxTdb anonymous local record selector temp policy to run.');
  Assert.AreEqual(RemoveWithTempStrategyToText(TRemoveWithTempStrategy.rwtsDirectQualification),
    RemoveWithTempStrategyToText(lDecision.fStrategy), 'Expected anonymous local record to be directly qualified.');
  Assert.AreEqual('anonymous-record-direct-qualification', lDecision.fReason,
    'Expected synthetic local record receiver to avoid invalid temp declarations.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TdbLoadProgram', 'PrgSaveRec', lInfo),
    'Expected maxTdb late parent-scope record selector resolver to run.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected maxTdb late parent-scope record selector status. Type=' + lInfo.fTypeName + ' Reason=' + lInfo.fReason +
    ' Symbols=' + DescribeMaxTdbSelectorSymbols(['TPrgSaveRec', 'PrgSaveRec', 'TdbLoadProgram', 'TdbUnloadProgram']));
  Assert.AreEqual('TPrgSaveRec', lInfo.fTypeName, 'Expected maxTdb late parent-scope record selector receiver type.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TIdentManager.SetIdentToRamtext', 'f^', lInfo),
    'Expected maxTdb PRamText selector resolver to run.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected maxTdb PRamText selector status. Type=' + lInfo.fTypeName + ' Reason=' + lInfo.fReason +
    ' Symbols=' + DescribeMaxTdbSelectorSymbols(['f', 'PRamText', 'TRamText']));
  Assert.AreEqual('TRamText', lInfo.fTypeName, 'Expected maxTdb PRamText selector receiver type.');
  Assert.IsTrue(ResolveRemoveWithSelectorType(lInventory, 'TIdentManager.DelIdentFromRamtext', 'f^', lInfo),
    'Expected maxTdb PRamText selector resolver to run.');
  Assert.AreEqual('resolved', RemoveWithSelectorTypeStatusToText(lInfo.fStatus),
    'Expected maxTdb PRamText selector status. Type=' + lInfo.fTypeName + ' Reason=' + lInfo.fReason +
    ' Symbols=' + DescribeMaxTdbSelectorSymbols(['f', 'PRamText', 'TRamText']));
  Assert.AreEqual('TRamText', lInfo.fTypeName, 'Expected maxTdb PRamText selector receiver type.');
end;

end.
