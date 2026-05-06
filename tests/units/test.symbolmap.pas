unit Test.SymbolMap;

interface

uses
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  System.Variants,
  DUnitX.TestFramework,
  maxLogic.CmdLineParams,
  Dak.Cli, Dak.SymbolMap.Api, Dak.SymbolMap.Cache, Dak.SymbolMap.Context, Dak.SymbolMap.Indexer,
  Dak.SymbolMap.Query, Dak.Types, Test.Support;

type
  [TestFixture]
  TSymbolMapContextTests = class
  private
    function FixtureProjectPath: string;
  public
    [Test]
    procedure ResolvesProjectAndProjectCacheRoot;
    [Test]
    procedure CacheRootOptionOverridesCentralRoot;
    [Test]
    procedure CacheRootEnvironmentOverridesCentralRoot;
    [Test]
    procedure StatsJsonReportsCacheRoots;
  end;

  [TestFixture]
  TSymbolMapCacheTests = class
  private
    function BuildContext(const aCacheName: string; out aContext: TSymbolMapContext): string;
    procedure CopyFixtureProject(const aTargetDir: string; out aProjectPath: string);
    function MetaValue(const aDbPath, aKey: string): string;
    function TableExists(const aDbPath, aTableName: string): Boolean;
    function UniqueTempPath(const aPrefix: string): string;
    procedure WriteSchemaVersion(const aDbPath, aVersion: string);
  public
    [Test]
    procedure EnsuresCentralAndProjectCacheSchema;
    [Test]
    procedure ReusesExistingCachesIdempotently;
    [Test]
    procedure StatsCommandCreatesCachesAndReportsSchema;
    [Test]
    procedure RejectsUnsupportedSchemaWithoutApplyingV1Tables;
    [Test]
    procedure ConcurrentCentralCacheCreationIsSerialized;
  end;

  [TestFixture]
  TSymbolMapSourceUnitTests = class
  private
    function FixtureProjectPath: string;
    function FixtureUnitPath: string;
  public
    [Test]
    procedure LoadsAnsiFallbackWhenUtf8Fails;
    [Test]
    procedure LoadsAnsiFallbackForInvalidUtf8SurrogateSequence;
    [Test]
    procedure ExtractsUnitNameAndUsesSections;
    [Test]
    procedure ExtractsNamespacedUnitName;
    [Test]
    procedure IndexUnitCommandReportsOneIndexedUnit;
  end;

  [TestFixture]
  TSymbolMapTopLevelDeclarationTests = class
  private
    function FixtureProjectPath: string;
    function FixtureUnitPath: string;
    function FindSymbol(const aModel: TSymbolMapUnitModel; const aName, aKind, aSectionKind: string;
      out aSymbol: TSymbolMapSymbolModel): Boolean;
    function RunIndexUnitCommand(out aExitCode: Cardinal): TJSONObject;
  public
    [Test]
    procedure ExtractsTopLevelDeclarationsAndEnumValues;
    [Test]
    procedure IndexUnitCommandReportsTopLevelDeclarationCounts;
  end;

  [TestFixture]
  TSymbolMapMemberExtractionTests = class
  private
    function FixtureProjectPath: string;
    function FixtureUnitPath: string;
    function FindMember(const aModel: TSymbolMapUnitModel; const aOwnerName, aMemberName, aKind: string;
      out aMember: TSymbolMapMemberModel): Boolean;
    function MemberCacheCount(const aDbPath, aOwnerName, aMemberName: string): Integer;
  public
    [Test]
    procedure ExtractsMembersPropertiesAndMetadata;
    [Test]
    procedure StoresMembersInCentralCacheRows;
  end;

  [TestFixture]
  TSymbolMapCentralCacheReuseTests = class
  private
    function BuildContext(const aProjectName, aCacheRoot: string; out aContext: TSymbolMapContext): string;
    function FixtureUnitPath: string;
    function UniqueTempPath(const aPrefix: string): string;
    function UnitModelCount(const aDbPath, aUnitCacheKey: string): Integer;
  public
    [Test]
    procedure RepeatedStoreReportsHitAndKeepsSingleUnitModel;
    [Test]
    procedure SharedSourceAcrossProjectsReusesUnitCacheKey;
    [Test]
    procedure EquivalentProjectDefineTextReusesUnitCacheKey;
    [Test]
    procedure ChangedDefinesProduceDifferentUnitCacheKey;
  end;

  [TestFixture]
  TSymbolMapIntrinsicProfileTests = class
  private
    function BuildFreshResolverExe: string;
    function BuildContext(const aCacheRoot: string; out aContext: TSymbolMapContext): string;
    function CompilerProfileCount(const aDbPath, aProfileKey: string): Integer;
    procedure CorruptIntrinsicPreservingCount(const aDbPath, aProfileKey: string);
    procedure DeleteIntrinsics(const aDbPath, aProfileKey: string);
    function FixtureProjectPath: string;
    function IntrinsicCount(const aDbPath, aProfileKey: string): Integer;
    function IntrinsicExists(const aDbPath, aProfileKey, aName: string): Boolean;
    function WindowsCmdExePath: string;
    function UniqueTempPath(const aPrefix: string): string;
  public
    [Test]
    procedure SeedsCompilerProfileAndIntrinsicRows;
    [Test]
    procedure ReusesSeededCompilerProfile;
    [Test]
    procedure RepairsProfileWhenIntrinsicRowsAreMissing;
    [Test]
    procedure RepairsProfileWhenIntrinsicSeedRowsAreStale;
    [Test]
    procedure IndexCommandReportsCompilerProfileStatus;
  end;

  [TestFixture]
  TSymbolMapRtlIndexTests = class
  private
    function BuildContext(const aCacheRoot: string; out aContext: TSymbolMapContext): string;
    function CompilerProfileUnitCount(const aDbPath, aProfileKey: string): Integer;
    function FixtureProjectPath: string;
    function ProfileSourceKind(const aDbPath, aProfileKey, aUnitName: string): string;
    function UniqueTempPath(const aPrefix: string): string;
    procedure WriteRtlUnit(const aRoot, aRelativePath, aUnitName: string);
  public
    [Test]
    procedure IndexesSourceAvailableRtlUnitsIntoCompilerProfile;
    [Test]
    procedure MissingRtlRootIsNonFatalDiagnostic;
    [Test]
    procedure RepeatedRtlIndexReusesCompilerProfileUnits;
  end;

  [TestFixture]
  TSymbolMapDefinitionQueryTests = class
  private
    function BuildFreshResolverExe: string;
    function BuildContext(const aCacheRoot: string; out aContext: TSymbolMapContext): string;
    function FixtureProjectPath: string;
    procedure IndexFixtureProject(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus);
    function UniqueTempPath(const aPrefix: string): string;
    function WindowsCmdExePath: string;
    procedure WriteRtlUnit(const aRoot, aRelativePath, aUnitName: string);
  public
    [Test]
    procedure FindsProjectDefinitionByPositionAndName;
    [Test]
    procedure SearchesProjectMembersRtlSourceAndIntrinsics;
    [Test]
    procedure DescribesOwnedMembersAndIntrinsics;
    [Test]
    procedure CliFindDefinitionReturnsJsonResult;
  end;

  [TestFixture]
  TSymbolMapReferenceQueryTests = class
  private
    function BuildContext(const aCacheRoot: string; out aContext: TSymbolMapContext): string;
    function FixtureProjectPath: string;
    procedure IndexFixtureProject(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus);
    function UniqueTempPath(const aPrefix: string): string;
  public
    [Test]
    procedure FindsTokenReferencesInProjectScope;
    [Test]
    procedure LimitsTokenReferenceResults;
  end;

  [TestFixture]
  TSymbolMapApiTests = class
  private
    function BaseOptions(const aCacheRoot: string): TAppOptions;
    function FixtureProjectPath: string;
    function UniqueTempPath(const aPrefix: string): string;
  public
    [Test]
    procedure ResolvesCoreSymbolKindsWithoutShellingOut;
    [Test]
    procedure ResolvesSourcePositionAndReportsCacheStatus;
  end;

  [TestFixture]
  TSymbolMapCliTests = class
  private
    procedure SetParams(const aCmdLine: string);
  public
    [Test]
    procedure ParsesStatsCommandWithJsonFormat;
    [Test]
    procedure ParsesSupportedOperations;
    [Test]
    procedure RejectsMissingOperationArguments;
    [Test]
    procedure HelpDocumentsSymbolMapOptions;
    [Test]
    procedure StatsCommandWritesJsonShell;
  end;

implementation

uses
  System.Threading,
  Winapi.Windows,
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite;

function TSymbolMapContextTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\LspProjectFixture.dproj');
end;

function TSymbolMapCacheTests.BuildContext(const aCacheName: string; out aContext: TSymbolMapContext): string;
var
  lError: string;
  lOptions: TAppOptions;
  lProjectDir: string;
  lProjectPath: string;
begin
  Result := UniqueTempPath(aCacheName);
  if TDirectory.Exists(Result) then
    TDirectory.Delete(Result, True);
  lProjectDir := UniqueTempPath(aCacheName + '-project');
  CopyFixtureProject(lProjectDir, lProjectPath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lProjectPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fSymbolMapCacheRoot := Result;
  lOptions.fHasSymbolMapCacheRoot := True;
  Assert.IsTrue(TryBuildSymbolMapContext(lOptions, aContext, lError), 'Expected context to resolve. Error: ' + lError);
  if TDirectory.Exists(aContext.fProjectCacheRoot) then
    TDirectory.Delete(aContext.fProjectCacheRoot, True);
end;

procedure TSymbolMapCacheTests.CopyFixtureProject(const aTargetDir: string; out aProjectPath: string);
var
  lFixtureDir: string;
begin
  if TDirectory.Exists(aTargetDir) then
    TDirectory.Delete(aTargetDir, True);
  ForceDirectories(aTargetDir);
  lFixtureDir := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture');
  TFile.Copy(TPath.Combine(lFixtureDir, 'LspProjectFixture.dproj'),
    TPath.Combine(aTargetDir, 'LspProjectFixture.dproj'), True);
  TFile.Copy(TPath.Combine(lFixtureDir, 'LspProjectFixture.dpr'),
    TPath.Combine(aTargetDir, 'LspProjectFixture.dpr'), True);
  TFile.Copy(TPath.Combine(lFixtureDir, 'Unit1.pas'), TPath.Combine(aTargetDir, 'Unit1.pas'), True);
  aProjectPath := TPath.Combine(aTargetDir, 'LspProjectFixture.dproj');
end;

function TSymbolMapCacheTests.MetaValue(const aDbPath, aKey: string): string;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  Result := '';
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    Result := VarToStr(lConnection.ExecSQLScalar('select value_text from meta where key_name = ?', [aKey]));
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TSymbolMapCacheTests.TableExists(const aDbPath, aTableName: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    Result := lConnection.ExecSQLScalar(
      'select count(*) from sqlite_master where type = ''table'' and name = ?', [aTableName]) > 0;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TSymbolMapCacheTests.UniqueTempPath(const aPrefix: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := StringReplace(StringReplace(GUIDToString(lGuid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);
  Result := TPath.Combine(TempRoot, aPrefix + '-' + lGuidText);
end;

procedure TSymbolMapCacheTests.WriteSchemaVersion(const aDbPath, aVersion: string);
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  ForceDirectories(TPath.GetDirectoryName(aDbPath));
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    lConnection.ExecSQL('create table meta (key_name text primary key not null, value_text text not null)');
    lConnection.ExecSQL('insert into meta(key_name, value_text) values (''schema_version'', ?)', [aVersion]);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

procedure TSymbolMapCacheTests.EnsuresCentralAndProjectCacheSchema;
var
  lContext: TSymbolMapContext;
  lError: string;
  lStatus: TSymbolMapCacheStatus;
begin
  BuildContext('symbol-map-schema-create', lContext);

  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected caches to be created. Error: ' + lError);
  Assert.IsTrue(TFile.Exists(lStatus.fCentralDbPath), 'Expected central SQLite cache file.');
  Assert.IsTrue(TFile.Exists(lStatus.fProjectDbPath), 'Expected project SQLite cache file.');
  Assert.IsTrue(lStatus.fCentralCreated, 'Expected first central cache creation to be reported.');
  Assert.IsTrue(lStatus.fProjectCreated, 'Expected first project cache creation to be reported.');
  Assert.AreEqual(1, lStatus.fSchemaVersion);
  Assert.AreEqual('1', MetaValue(lStatus.fCentralDbPath, 'schema_version'));
  Assert.AreEqual('1', MetaValue(lStatus.fProjectDbPath, 'schema_version'));
end;

procedure TSymbolMapCacheTests.ReusesExistingCachesIdempotently;
var
  lContext: TSymbolMapContext;
  lError: string;
  lFirstStatus: TSymbolMapCacheStatus;
  lSecondStatus: TSymbolMapCacheStatus;
begin
  BuildContext('symbol-map-schema-reuse', lContext);

  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lFirstStatus, lError), 'Expected first cache creation. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lSecondStatus, lError), 'Expected second cache open. Error: ' + lError);
  Assert.IsFalse(lSecondStatus.fCentralCreated, 'Expected central cache reuse to be reported.');
  Assert.IsFalse(lSecondStatus.fProjectCreated, 'Expected project cache reuse to be reported.');
  Assert.AreEqual(lFirstStatus.fCentralDbPath, lSecondStatus.fCentralDbPath);
  Assert.AreEqual(lFirstStatus.fProjectDbPath, lSecondStatus.fProjectDbPath);
  Assert.AreEqual(1, lSecondStatus.fSchemaVersion);
end;

procedure TSymbolMapCacheTests.RejectsUnsupportedSchemaWithoutApplyingV1Tables;
var
  lContext: TSymbolMapContext;
  lDbPath: string;
  lError: string;
  lStatus: TSymbolMapCacheStatus;
begin
  BuildContext('symbol-map-schema-version-mismatch', lContext);
  lDbPath := TPath.Combine(lContext.fCentralCacheRoot, 'symbol-map.sqlite3');
  WriteSchemaVersion(lDbPath, '99');

  Assert.IsFalse(EnsureSymbolMapCaches(lContext, lStatus, lError),
    'Expected unsupported schema version to fail.');
  Assert.IsTrue(Pos('Unsupported Symbol Map cache schema version: 99', lError) > 0,
    'Expected actionable schema-version error. Actual: ' + lError);
  Assert.IsFalse(TableExists(lDbPath, 'source_files'), 'Expected v1 tables not to be applied to newer cache.');
end;

procedure TSymbolMapCacheTests.ConcurrentCentralCacheCreationIsSerialized;
const
  cProcessCount = 4;
var
  lArgs: TArray<string>;
  lCache: TJSONObject;
  lCacheRoot: string;
  lCreatedCount: Integer;
  lExitCodes: TArray<Cardinal>;
  lJson: TJSONObject;
  lJsonValue: TJSONValue;
  lLogPaths: TArray<string>;
  lLogText: string;
  lProjectDir: string;
  lProjectPath: string;
  lResults: TArray<Boolean>;
  lTasks: TArray<ITask>;
  i: Integer;

  function StartTask(const aIndex: Integer): ITask;
  begin
    Result := TTask.Run(
      procedure
      begin
        lResults[aIndex] := RunProcess(ResolverExePath, lArgs[aIndex], RepoRoot, lLogPaths[aIndex],
          lExitCodes[aIndex]);
      end);
  end;

begin
  EnsureResolverBuilt;
  lCacheRoot := UniqueTempPath('symbol-map-cache-concurrent');
  if TDirectory.Exists(lCacheRoot) then
    TDirectory.Delete(lCacheRoot, True);
  SetLength(lArgs, cProcessCount);
  SetLength(lExitCodes, cProcessCount);
  SetLength(lLogPaths, cProcessCount);
  SetLength(lResults, cProcessCount);
  SetLength(lTasks, cProcessCount);

  for i := 0 to cProcessCount - 1 do
  begin
    lProjectDir := UniqueTempPath('symbol-map-cache-concurrent-project-' + i.ToString);
    CopyFixtureProject(lProjectDir, lProjectPath);
    lLogPaths[i] := UniqueTempPath('symbol-map-cache-concurrent-' + i.ToString) + '.log';
    lArgs[i] := 'symbol-map stats --project ' + QuoteArg(lProjectPath) + ' --cache-root ' + QuoteArg(lCacheRoot) +
      ' --format json';
  end;

  for i := 0 to cProcessCount - 1 do
    lTasks[i] := StartTask(i);
  TTask.WaitForAll(lTasks);

  lCreatedCount := 0;
  for i := 0 to cProcessCount - 1 do
  begin
    Assert.IsTrue(lResults[i], 'Expected concurrent symbol-map process to start.');
    Assert.AreEqual(Cardinal(0), lExitCodes[i], 'Expected concurrent symbol-map process to succeed. See: ' +
      lLogPaths[i]);
    lLogText := TFile.ReadAllText(lLogPaths[i]);
    lJsonValue := TJSONObject.ParseJSONValue(lLogText);
    try
      Assert.IsTrue(lJsonValue is TJSONObject, 'Expected JSON object. Actual: ' + lLogText);
      lJson := TJSONObject(lJsonValue);
      lCache := lJson.GetValue('cache') as TJSONObject;
      Assert.AreEqual(1, lCache.GetValue<Integer>('schemaVersion'));
      Assert.IsTrue(TFile.Exists(lCache.GetValue<string>('centralDbPath')), 'Expected shared central cache file.');
      Assert.IsTrue(TFile.Exists(lCache.GetValue<string>('projectDbPath')), 'Expected project cache file.');
      if lCache.GetValue<Boolean>('centralCreated') then
        Inc(lCreatedCount);
    finally
      lJsonValue.Free;
    end;
  end;
  Assert.AreEqual(1, lCreatedCount, 'Expected exactly one central cache creator.');
  Assert.AreEqual('1', MetaValue(TPath.Combine(lCacheRoot, 'symbol-map.sqlite3'), 'schema_version'));
end;

procedure TSymbolMapCacheTests.StatsCommandCreatesCachesAndReportsSchema;
var
  lArgs: string;
  lCacheRoot: string;
  lCache: TJSONObject;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lJsonValue: TJSONValue;
  lLogPath: string;
  lLogText: string;
  lProjectDir: string;
  lProjectPath: string;
begin
  EnsureResolverBuilt;
  lCacheRoot := UniqueTempPath('symbol-map-cache-cli-schema');
  if TDirectory.Exists(lCacheRoot) then
    TDirectory.Delete(lCacheRoot, True);
  lProjectDir := UniqueTempPath('symbol-map-cache-cli-project');
  CopyFixtureProject(lProjectDir, lProjectPath);
  lLogPath := UniqueTempPath('symbol-map-cache-schema-json') + '.log';
  lArgs := 'symbol-map stats --project ' + QuoteArg(lProjectPath) + ' --cache-root ' + QuoteArg(lCacheRoot) +
    ' --format json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start symbol-map stats command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected symbol-map stats to succeed. See: ' + lLogPath);

  lLogText := TFile.ReadAllText(lLogPath);
  lJsonValue := TJSONObject.ParseJSONValue(lLogText);
  try
    Assert.IsTrue(lJsonValue is TJSONObject, 'Expected JSON object. Actual: ' + lLogText);
    lJson := TJSONObject(lJsonValue);
    lCache := lJson.GetValue('cache') as TJSONObject;
    Assert.AreEqual(1, lCache.GetValue<Integer>('schemaVersion'));
    Assert.IsTrue(lCache.GetValue<Boolean>('centralCreated'), 'Expected central cache creation in first CLI run.');
    Assert.IsTrue(lCache.GetValue<Boolean>('projectCreated'), 'Expected project cache creation in first CLI run.');
    Assert.IsTrue(TFile.Exists(lCache.GetValue<string>('centralDbPath')), 'Expected central SQLite cache file.');
    Assert.IsTrue(TFile.Exists(lCache.GetValue<string>('projectDbPath')), 'Expected project SQLite cache file.');
  finally
    lJsonValue.Free;
  end;
end;

function TSymbolMapSourceUnitTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapFixture.dproj');
end;

function TSymbolMapSourceUnitTests.FixtureUnitPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapUnit.pas');
end;

function TSymbolMapTopLevelDeclarationTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapFixture.dproj');
end;

function TSymbolMapTopLevelDeclarationTests.FixtureUnitPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapDeclarations.pas');
end;

function TSymbolMapMemberExtractionTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapFixture.dproj');
end;

function TSymbolMapMemberExtractionTests.FixtureUnitPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapMembers.pas');
end;

function TSymbolMapMemberExtractionTests.FindMember(const aModel: TSymbolMapUnitModel; const aOwnerName,
  aMemberName, aKind: string; out aMember: TSymbolMapMemberModel): Boolean;
var
  lMember: TSymbolMapMemberModel;
begin
  Result := False;
  aMember := Default(TSymbolMapMemberModel);
  for lMember in aModel.fMembers do
  begin
    if SameText(lMember.fOwnerName, aOwnerName) and SameText(lMember.fMemberName, aMemberName) and
      SameText(lMember.fKind, aKind) then
    begin
      aMember := lMember;
      Exit(True);
    end;
  end;
end;

function TSymbolMapMemberExtractionTests.MemberCacheCount(const aDbPath, aOwnerName, aMemberName: string): Integer;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    Result := lConnection.ExecSQLScalar(
      'select count(*) from members where owner_name = ? and member_name = ?', [aOwnerName, aMemberName]);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

procedure TSymbolMapMemberExtractionTests.ExtractsMembersPropertiesAndMetadata;
var
  lError: string;
  lMember: TSymbolMapMemberModel;
  lModel: TSymbolMapUnitModel;
begin
  Assert.IsTrue(TryExtractSymbolMapUnitModel(FixtureUnitPath, lModel, lError),
    'Expected member unit extraction to succeed. Error: ' + lError);

  Assert.AreEqual('SymbolMapMembers', lModel.fUnitName);
  Assert.AreEqual(22, Length(lModel.fMembers));
  Assert.IsTrue(FindMember(lModel, 'TMemberRecord', 'RecordField', 'field', lMember), 'Expected record field.');
  Assert.AreEqual('Integer', lMember.fTypeName);
  Assert.IsTrue(FindMember(lModel, 'TMemberRecord', 'Reset', 'method', lMember), 'Expected record method.');
  Assert.IsTrue(FindMember(lModel, 'TMemberClass', 'FName', 'field', lMember), 'Expected private field.');
  Assert.AreEqual('private', lMember.fVisibility);
  Assert.IsTrue(FindMember(lModel, 'TMemberClass', 'Run', 'method', lMember), 'Expected class method.');
  Assert.IsTrue(Pos('const aName: string', lMember.fSignature) > 0, 'Expected method signature.');
  Assert.IsTrue(FindMember(lModel, 'TMemberClass', 'Name', 'property', lMember), 'Expected property.');
  Assert.AreEqual('string', lMember.fTypeName);
  Assert.IsFalse(lMember.fIsIndexed, 'Expected scalar property.');
  Assert.IsTrue(FindMember(lModel, 'TMemberClass', 'Enabled', 'property', lMember),
    'Expected stored-default property.');
  Assert.IsFalse(lMember.fIsDefault, 'Stored default values are not default properties.');
  Assert.IsTrue(FindMember(lModel, 'TMemberClass', 'Items', 'property', lMember), 'Expected indexed property.');
  Assert.IsTrue(lMember.fIsIndexed, 'Expected indexed metadata.');
  Assert.IsTrue(lMember.fIsDefault, 'Expected default property metadata.');
  Assert.IsTrue(FindMember(lModel, 'TMemberClass', 'MultiItems', 'property', lMember),
    'Expected indexed property with semicolon in parameter list.');
  Assert.AreEqual('string', lMember.fTypeName);
  Assert.IsTrue(lMember.fIsIndexed, 'Expected indexed metadata with semicolon in parameter list.');
  Assert.IsFalse(lMember.fIsDefault, 'Expected no default-property metadata.');
  Assert.IsTrue(FindMember(lModel, 'TDefaultVisibilityClass', 'DefaultField', 'field', lMember),
    'Expected class member before explicit visibility.');
  Assert.AreEqual('public', lMember.fVisibility);
  Assert.IsTrue(FindMember(lModel, 'IMemberInterface', 'Touch', 'method', lMember), 'Expected interface method.');
  Assert.AreEqual('public', lMember.fVisibility);
  Assert.IsTrue(FindMember(lModel, 'TMemberRecordHelper', 'Normalize', 'method', lMember),
    'Expected helper method.');
  Assert.AreNotEqual(0, lMember.fLine, 'Expected source line.');
  Assert.AreNotEqual(0, lMember.fCol, 'Expected source column.');
end;

procedure TSymbolMapMemberExtractionTests.StoresMembersInCentralCacheRows;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lModel: TSymbolMapUnitModel;
  lOptions: TAppOptions;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := TPath.Combine(TempRoot, 'symbol-map-members-cache');
  if TDirectory.Exists(lCacheRoot) then
    TDirectory.Delete(lCacheRoot, True);
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fSymbolMapCacheRoot := lCacheRoot;
  lOptions.fHasSymbolMapCacheRoot := True;

  Assert.IsTrue(TryBuildSymbolMapContext(lOptions, lContext, lError), 'Expected context. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected cache schema. Error: ' + lError);
  Assert.IsTrue(TryExtractSymbolMapUnitModel(FixtureUnitPath, lModel, lError),
    'Expected member unit extraction. Error: ' + lError);
  Assert.IsTrue(StoreSymbolMapUnitModel(lContext, lStatus, lModel, lError),
    'Expected member cache write. Error: ' + lError);

  Assert.AreEqual(1, MemberCacheCount(lStatus.fCentralDbPath, 'TMemberClass', 'Items'),
    'Expected indexed property row in central cache.');
  Assert.AreEqual(1, MemberCacheCount(lStatus.fCentralDbPath, 'TDefaultVisibilityClass', 'DefaultField'),
    'Expected default visibility field row in central cache.');
end;

function TSymbolMapCentralCacheReuseTests.BuildContext(const aProjectName, aCacheRoot: string;
  out aContext: TSymbolMapContext): string;
var
  lDprPath: string;
  lDprojPath: string;
  lError: string;
  lOptions: TAppOptions;
  lProjectDir: string;
begin
  lProjectDir := UniqueTempPath(aProjectName);
  ForceDirectories(lProjectDir);
  lDprPath := TPath.Combine(lProjectDir, aProjectName + '.dpr');
  lDprojPath := TPath.Combine(lProjectDir, aProjectName + '.dproj');
  TFile.WriteAllText(lDprPath, 'program ' + aProjectName + ';' + sLineBreak + 'begin' + sLineBreak + 'end.',
    TEncoding.UTF8);
  TFile.WriteAllText(lDprojPath, '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>' + aProjectName + '.dpr</MainSource></PropertyGroup></Project>',
    TEncoding.UTF8);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fSymbolMapCacheRoot := aCacheRoot;
  lOptions.fHasSymbolMapCacheRoot := True;
  Assert.IsTrue(TryBuildSymbolMapContext(lOptions, aContext, lError), 'Expected context. Error: ' + lError);
  Result := lDprojPath;
end;

function TSymbolMapCentralCacheReuseTests.FixtureUnitPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapMembers.pas');
end;

function TSymbolMapCentralCacheReuseTests.UniqueTempPath(const aPrefix: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := StringReplace(StringReplace(GUIDToString(lGuid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);
  Result := TPath.Combine(TempRoot, aPrefix + '-' + lGuidText);
end;

function TSymbolMapCentralCacheReuseTests.UnitModelCount(const aDbPath, aUnitCacheKey: string): Integer;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    Result := lConnection.ExecSQLScalar(
      'select count(*) from unit_models where unit_cache_key = ?', [aUnitCacheKey]);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

procedure TSymbolMapCentralCacheReuseTests.RepeatedStoreReportsHitAndKeepsSingleUnitModel;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lFirst: TSymbolMapCacheStoreResult;
  lModel: TSymbolMapUnitModel;
  lSecond: TSymbolMapCacheStoreResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-reuse-cache');
  BuildContext('SymbolMapReuseA', lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected cache schema. Error: ' + lError);
  Assert.IsTrue(TryExtractSymbolMapUnitModel(FixtureUnitPath, lModel, lError),
    'Expected member unit extraction. Error: ' + lError);

  Assert.IsTrue(StoreSymbolMapUnitModel(lContext, lStatus, lModel, lFirst, lError),
    'Expected first store. Error: ' + lError);
  Assert.IsFalse(lFirst.fCacheHit, 'Expected first store to miss.');
  Assert.IsTrue(StoreSymbolMapUnitModel(lContext, lStatus, lModel, lSecond, lError),
    'Expected second store. Error: ' + lError);
  Assert.IsTrue(lSecond.fCacheHit, 'Expected second store to hit.');
  Assert.AreEqual(lFirst.fUnitCacheKey, lSecond.fUnitCacheKey);
  Assert.AreEqual(1, UnitModelCount(lStatus.fCentralDbPath, lFirst.fUnitCacheKey));
end;

procedure TSymbolMapCentralCacheReuseTests.SharedSourceAcrossProjectsReusesUnitCacheKey;
var
  lCacheRoot: string;
  lContextA: TSymbolMapContext;
  lContextB: TSymbolMapContext;
  lError: string;
  lFirst: TSymbolMapCacheStoreResult;
  lModel: TSymbolMapUnitModel;
  lSecond: TSymbolMapCacheStoreResult;
  lStatusA: TSymbolMapCacheStatus;
  lStatusB: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-shared-cache');
  BuildContext('SymbolMapSharedA', lCacheRoot, lContextA);
  BuildContext('SymbolMapSharedB', lCacheRoot, lContextB);
  Assert.IsTrue(EnsureSymbolMapCaches(lContextA, lStatusA, lError), 'Expected cache A. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCaches(lContextB, lStatusB, lError), 'Expected cache B. Error: ' + lError);
  Assert.IsTrue(TryExtractSymbolMapUnitModel(FixtureUnitPath, lModel, lError),
    'Expected member unit extraction. Error: ' + lError);

  Assert.IsTrue(StoreSymbolMapUnitModel(lContextA, lStatusA, lModel, lFirst, lError),
    'Expected first store. Error: ' + lError);
  Assert.IsTrue(StoreSymbolMapUnitModel(lContextB, lStatusB, lModel, lSecond, lError),
    'Expected shared store. Error: ' + lError);
  Assert.AreEqual(lFirst.fUnitCacheKey, lSecond.fUnitCacheKey);
  Assert.IsTrue(lSecond.fCacheHit, 'Expected second project to reuse the central unit model.');
end;

procedure TSymbolMapCentralCacheReuseTests.EquivalentProjectDefineTextReusesUnitCacheKey;
var
  lCacheRoot: string;
  lContextA: TSymbolMapContext;
  lContextB: TSymbolMapContext;
  lError: string;
  lFirst: TSymbolMapCacheStoreResult;
  lModel: TSymbolMapUnitModel;
  lSecond: TSymbolMapCacheStoreResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-equivalent-defines-cache');
  BuildContext('SymbolMapEquivalentDefinesA', lCacheRoot, lContextA);
  lContextA.fDefines := TArray<string>.Create('NET', 'DLL');
  lContextA.fProject.fParserDefines := 'NET;DLL';
  lContextB := lContextA;
  lContextB.fProject.fParserDefines := ' DLL ; NET ';
  Assert.IsTrue(EnsureSymbolMapCaches(lContextA, lStatus, lError), 'Expected cache schema. Error: ' + lError);
  Assert.IsTrue(TryExtractSymbolMapUnitModel(FixtureUnitPath, lModel, lError),
    'Expected member unit extraction. Error: ' + lError);

  Assert.IsTrue(StoreSymbolMapUnitModel(lContextA, lStatus, lModel, lFirst, lError),
    'Expected first store. Error: ' + lError);
  Assert.IsTrue(StoreSymbolMapUnitModel(lContextB, lStatus, lModel, lSecond, lError),
    'Expected equivalent define store. Error: ' + lError);
  Assert.AreEqual(lFirst.fUnitCacheKey, lSecond.fUnitCacheKey);
  Assert.IsTrue(lSecond.fCacheHit, 'Expected equivalent define text to reuse the central unit model.');
end;

procedure TSymbolMapCentralCacheReuseTests.ChangedDefinesProduceDifferentUnitCacheKey;
var
  lCacheRoot: string;
  lContextA: TSymbolMapContext;
  lContextB: TSymbolMapContext;
  lError: string;
  lFirst: TSymbolMapCacheStoreResult;
  lModel: TSymbolMapUnitModel;
  lSecond: TSymbolMapCacheStoreResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-define-cache');
  BuildContext('SymbolMapDefineA', lCacheRoot, lContextA);
  lContextB := lContextA;
  lContextB.fDefines := TArray<string>.Create('NET');
  Assert.IsTrue(EnsureSymbolMapCaches(lContextA, lStatus, lError), 'Expected cache schema. Error: ' + lError);
  Assert.IsTrue(TryExtractSymbolMapUnitModel(FixtureUnitPath, lModel, lError),
    'Expected member unit extraction. Error: ' + lError);

  Assert.IsTrue(StoreSymbolMapUnitModel(lContextA, lStatus, lModel, lFirst, lError),
    'Expected first store. Error: ' + lError);
  Assert.IsTrue(StoreSymbolMapUnitModel(lContextB, lStatus, lModel, lSecond, lError),
    'Expected define-specific store. Error: ' + lError);
  Assert.AreNotEqual(lFirst.fUnitCacheKey, lSecond.fUnitCacheKey);
  Assert.IsFalse(lSecond.fCacheHit, 'Expected changed defines to produce a cache miss.');
end;

function TSymbolMapIntrinsicProfileTests.BuildFreshResolverExe: string;
var
  lArgs: string;
  lBat: string;
  lCmdArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
  lOutputDir: string;
begin
  lOutputDir := UniqueTempPath('symbol-map-intrinsic-resolver');
  ForceDirectories(lOutputDir);
  lBat := TPath.Combine(RepoRoot, 'build-delphi.bat');
  lArgs := QuoteArg(TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dproj')) +
    ' -config Release -platform Win32 -ver 23 -test-output-dir ' + QuoteArg(lOutputDir);
  lCmdArgs := '/C "call ' + QuoteArg(lBat) + ' ' + lArgs + '"';
  lLogPath := UniqueTempPath('symbol-map-intrinsic-resolver-build') + '.log';
  Assert.IsTrue(RunProcess(WindowsCmdExePath, lCmdArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver build.');
  if lExitCode <> 0 then
  begin
    lLogText := '';
    if TFile.Exists(lLogPath) then
      lLogText := TFile.ReadAllText(lLogPath);
    Assert.Fail('Expected resolver build to succeed. See: ' + lLogPath + sLineBreak + lLogText);
  end;
  Result := TPath.Combine(lOutputDir, 'DelphiAIKit.exe');
  Assert.IsTrue(TFile.Exists(Result), 'Expected fresh resolver exe: ' + Result);
end;

function TSymbolMapIntrinsicProfileTests.BuildContext(const aCacheRoot: string;
  out aContext: TSymbolMapContext): string;
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23';
  lOptions.fSymbolMapCacheRoot := aCacheRoot;
  lOptions.fHasSymbolMapCacheRoot := True;
  Assert.IsTrue(TryBuildSymbolMapContext(lOptions, aContext, lError), 'Expected context. Error: ' + lError);
  Result := FixtureProjectPath;
end;

procedure TSymbolMapIntrinsicProfileTests.DeleteIntrinsics(const aDbPath, aProfileKey: string);
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    lConnection.ExecSQL('delete from compiler_intrinsics where profile_key = ?', [aProfileKey]);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TSymbolMapIntrinsicProfileTests.CompilerProfileCount(const aDbPath, aProfileKey: string): Integer;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    Result := lConnection.ExecSQLScalar('select count(*) from compiler_profiles where profile_key = ?',
      [aProfileKey]);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

procedure TSymbolMapIntrinsicProfileTests.CorruptIntrinsicPreservingCount(const aDbPath, aProfileKey: string);
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    lConnection.ExecSQL(
      'update compiler_intrinsics set name = ?, kind = ?, signature = ?, notes = ? ' +
      'where profile_key = ? and lower(name) = lower(?)',
      ['StaleIntrinsic', 'routine', 'procedure StaleIntrinsic', 'stale test row', aProfileKey, 'Abs']);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TSymbolMapIntrinsicProfileTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapFixture.dproj');
end;

function TSymbolMapIntrinsicProfileTests.WindowsCmdExePath: string;
begin
  Result := Trim(GetEnvironmentVariable('ComSpec'));
  if Result = '' then
    Result := 'C:\Windows\System32\cmd.exe';
end;

function TSymbolMapIntrinsicProfileTests.IntrinsicCount(const aDbPath, aProfileKey: string): Integer;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    Result := lConnection.ExecSQLScalar('select count(*) from compiler_intrinsics where profile_key = ?',
      [aProfileKey]);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TSymbolMapIntrinsicProfileTests.IntrinsicExists(const aDbPath, aProfileKey, aName: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    Result := lConnection.ExecSQLScalar(
      'select count(*) from compiler_intrinsics where profile_key = ? and lower(name) = lower(?)',
      [aProfileKey, aName]) > 0;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TSymbolMapIntrinsicProfileTests.UniqueTempPath(const aPrefix: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := StringReplace(StringReplace(GUIDToString(lGuid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);
  Result := TPath.Combine(TempRoot, aPrefix + '-' + lGuidText);
end;

procedure TSymbolMapIntrinsicProfileTests.SeedsCompilerProfileAndIntrinsicRows;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lProfile: TSymbolMapCompilerProfileResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-intrinsic-cache');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected cache schema. Error: ' + lError);

  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lProfile, lError),
    'Expected compiler profile seed. Error: ' + lError);

  Assert.AreEqual('23.0', lProfile.fDelphiVersion);
  Assert.AreEqual('Win32', lProfile.fPlatform);
  Assert.IsFalse(lProfile.fCacheHit, 'Expected first profile seed to miss.');
  Assert.IsTrue(lProfile.fIntrinsicCount >= 20, 'Expected seeded Delphi intrinsics.');
  Assert.AreEqual(1, CompilerProfileCount(lStatus.fCentralDbPath, lProfile.fProfileKey));
  Assert.AreEqual(lProfile.fIntrinsicCount, IntrinsicCount(lStatus.fCentralDbPath, lProfile.fProfileKey));
  Assert.IsTrue(IntrinsicExists(lStatus.fCentralDbPath, lProfile.fProfileKey, 'SizeOf'),
    'Expected SizeOf intrinsic.');
  Assert.IsTrue(IntrinsicExists(lStatus.fCentralDbPath, lProfile.fProfileKey, 'High'), 'Expected High intrinsic.');
  Assert.IsTrue(IntrinsicExists(lStatus.fCentralDbPath, lProfile.fProfileKey, 'IOResult'),
    'Expected IOResult intrinsic.');
  Assert.IsTrue(IntrinsicExists(lStatus.fCentralDbPath, lProfile.fProfileKey, 'sizeof'),
    'Expected case-insensitive intrinsic lookup support.');
end;

procedure TSymbolMapIntrinsicProfileTests.ReusesSeededCompilerProfile;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lFirst: TSymbolMapCompilerProfileResult;
  lSecond: TSymbolMapCompilerProfileResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-intrinsic-reuse-cache');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected cache schema. Error: ' + lError);

  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lFirst, lError),
    'Expected first compiler profile seed. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lSecond, lError),
    'Expected second compiler profile seed. Error: ' + lError);

  Assert.AreEqual(lFirst.fProfileKey, lSecond.fProfileKey);
  Assert.IsTrue(lSecond.fCacheHit, 'Expected second seed to reuse the compiler profile.');
  Assert.AreEqual(1, CompilerProfileCount(lStatus.fCentralDbPath, lFirst.fProfileKey));
  Assert.AreEqual(lFirst.fIntrinsicCount, IntrinsicCount(lStatus.fCentralDbPath, lFirst.fProfileKey));
end;

procedure TSymbolMapIntrinsicProfileTests.RepairsProfileWhenIntrinsicRowsAreMissing;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lFirst: TSymbolMapCompilerProfileResult;
  lSecond: TSymbolMapCompilerProfileResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-intrinsic-repair-cache');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected cache schema. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lFirst, lError),
    'Expected first compiler profile seed. Error: ' + lError);

  DeleteIntrinsics(lStatus.fCentralDbPath, lFirst.fProfileKey);

  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lSecond, lError),
    'Expected compiler profile repair. Error: ' + lError);
  Assert.AreEqual(lFirst.fProfileKey, lSecond.fProfileKey);
  Assert.IsFalse(lSecond.fCacheHit, 'Expected missing intrinsic rows to force repair.');
  Assert.AreEqual(lFirst.fIntrinsicCount, IntrinsicCount(lStatus.fCentralDbPath, lFirst.fProfileKey));
end;

procedure TSymbolMapIntrinsicProfileTests.RepairsProfileWhenIntrinsicSeedRowsAreStale;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lFirst: TSymbolMapCompilerProfileResult;
  lSecond: TSymbolMapCompilerProfileResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-intrinsic-stale-cache');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected cache schema. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lFirst, lError),
    'Expected first compiler profile seed. Error: ' + lError);

  CorruptIntrinsicPreservingCount(lStatus.fCentralDbPath, lFirst.fProfileKey);

  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lSecond, lError),
    'Expected compiler profile stale-row repair. Error: ' + lError);
  Assert.AreEqual(lFirst.fProfileKey, lSecond.fProfileKey);
  Assert.IsFalse(lSecond.fCacheHit, 'Expected stale intrinsic rows to force repair.');
  Assert.IsTrue(IntrinsicExists(lStatus.fCentralDbPath, lFirst.fProfileKey, 'Abs'), 'Expected Abs to be restored.');
  Assert.IsFalse(IntrinsicExists(lStatus.fCentralDbPath, lFirst.fProfileKey, 'StaleIntrinsic'),
    'Expected stale intrinsic row to be removed.');
  Assert.AreEqual(lFirst.fIntrinsicCount, IntrinsicCount(lStatus.fCentralDbPath, lFirst.fProfileKey));
end;

procedure TSymbolMapIntrinsicProfileTests.IndexCommandReportsCompilerProfileStatus;
var
  lArgs: string;
  lCacheRoot: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lJsonValue: TJSONValue;
  lLogPath: string;
  lLogText: string;
  lProfile: TJSONObject;
  lResolverExe: string;
begin
  lResolverExe := BuildFreshResolverExe;
  lCacheRoot := UniqueTempPath('symbol-map-intrinsic-cli-cache');
  lLogPath := UniqueTempPath('symbol-map-intrinsic-cli') + '.log';
  lArgs := 'symbol-map index --project ' + QuoteArg(FixtureProjectPath) + ' --cache-root ' +
    QuoteArg(lCacheRoot) + ' --format json --delphi 23 --verbose true';

  Assert.IsTrue(RunProcess(lResolverExe, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start symbol-map index command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected symbol-map index to succeed. See: ' + lLogPath);

  lLogText := TFile.ReadAllText(lLogPath);
  lJsonValue := TJSONObject.ParseJSONValue(lLogText);
  try
    Assert.IsTrue(lJsonValue is TJSONObject, 'Expected JSON object. Actual: ' + lLogText);
    lJson := TJSONObject(lJsonValue);
    Assert.IsTrue(lJson.GetValue('compilerProfile') is TJSONObject, 'Expected compilerProfile object.');
    lProfile := lJson.GetValue('compilerProfile') as TJSONObject;
    Assert.AreEqual('23.0', lProfile.GetValue<string>('delphiVersion'));
    Assert.AreEqual('Win32', lProfile.GetValue<string>('platform'));
    Assert.IsTrue(lProfile.GetValue<Integer>('syntheticIntrinsicCount') >= 20,
      'Expected synthetic intrinsic count.');
    Assert.IsNotEmpty(lProfile.GetValue<string>('profileKey'), 'Expected profile key.');
  finally
    lJsonValue.Free;
  end;
end;

function TSymbolMapRtlIndexTests.BuildContext(const aCacheRoot: string; out aContext: TSymbolMapContext): string;
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23';
  lOptions.fSymbolMapCacheRoot := aCacheRoot;
  lOptions.fHasSymbolMapCacheRoot := True;
  Assert.IsTrue(TryBuildSymbolMapContext(lOptions, aContext, lError), 'Expected context. Error: ' + lError);
  Result := FixtureProjectPath;
end;

function TSymbolMapRtlIndexTests.CompilerProfileUnitCount(const aDbPath, aProfileKey: string): Integer;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    Result := lConnection.ExecSQLScalar('select count(*) from compiler_profile_units where profile_key = ?',
      [aProfileKey]);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TSymbolMapRtlIndexTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapFixture.dproj');
end;

function TSymbolMapDefinitionQueryTests.BuildContext(const aCacheRoot: string; out aContext: TSymbolMapContext):
  string;
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23';
  lOptions.fSymbolMapCacheRoot := aCacheRoot;
  lOptions.fHasSymbolMapCacheRoot := True;
  Assert.IsTrue(TryBuildSymbolMapContext(lOptions, aContext, lError), 'Expected context. Error: ' + lError);
  Result := FixtureProjectPath;
end;

function TSymbolMapDefinitionQueryTests.BuildFreshResolverExe: string;
var
  lArgs: string;
  lBat: string;
  lCmdArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
  lOutputDir: string;
begin
  lOutputDir := UniqueTempPath('symbol-map-query-resolver');
  ForceDirectories(lOutputDir);
  lBat := TPath.Combine(RepoRoot, 'build-delphi.bat');
  lArgs := QuoteArg(TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dproj')) +
    ' -config Release -platform Win32 -ver 23 -test-output-dir ' + QuoteArg(lOutputDir);
  lCmdArgs := '/C "call ' + QuoteArg(lBat) + ' ' + lArgs + '"';
  lLogPath := UniqueTempPath('symbol-map-query-resolver-build') + '.log';
  Assert.IsTrue(RunProcess(WindowsCmdExePath, lCmdArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver build.');
  if lExitCode <> 0 then
  begin
    lLogText := '';
    if TFile.Exists(lLogPath) then
      lLogText := TFile.ReadAllText(lLogPath);
    Assert.Fail('Expected resolver build to succeed. See: ' + lLogPath + sLineBreak + lLogText);
  end;
  Result := TPath.Combine(lOutputDir, 'DelphiAIKit.exe');
  Assert.IsTrue(TFile.Exists(Result), 'Expected fresh resolver exe: ' + Result);
end;

function TSymbolMapDefinitionQueryTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapFixture.dproj');
end;

procedure TSymbolMapDefinitionQueryTests.IndexFixtureProject(const aContext: TSymbolMapContext;
  const aStatus: TSymbolMapCacheStatus);
var
  lError: string;
  lModel: TSymbolMapUnitModel;
  lUnitPath: string;
  lUnitPaths: TArray<string>;
begin
  lUnitPaths := [
    TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapDeclarations.pas'),
    TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapMembers.pas'),
    TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapUnit.pas')];
  for lUnitPath in lUnitPaths do
  begin
    Assert.IsTrue(TryExtractSymbolMapUnitModel(lUnitPath, lModel, lError),
      'Expected source extraction. Error: ' + lError);
    Assert.IsTrue(StoreSymbolMapUnitModel(aContext, aStatus, lModel, lError),
      'Expected unit model storage. Error: ' + lError);
  end;
end;

function TSymbolMapDefinitionQueryTests.UniqueTempPath(const aPrefix: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := StringReplace(StringReplace(GUIDToString(lGuid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);
  Result := TPath.Combine(TempRoot, aPrefix + '-' + lGuidText);
end;

function TSymbolMapDefinitionQueryTests.WindowsCmdExePath: string;
begin
  Result := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\cmd.exe');
  if not TFile.Exists(Result) then
    Result := 'cmd.exe';
end;

procedure TSymbolMapDefinitionQueryTests.WriteRtlUnit(const aRoot, aRelativePath, aUnitName: string);
var
  lPath: string;
begin
  lPath := TPath.Combine(aRoot, aRelativePath);
  ForceDirectories(TPath.GetDirectoryName(lPath));
  TFile.WriteAllText(lPath, 'unit ' + aUnitName + ';' + sLineBreak + sLineBreak + 'interface' + sLineBreak +
    'type' + sLineBreak + '  T' + StringReplace(aUnitName, '.', '', [rfReplaceAll]) + 'Fixture = record' +
    sLineBreak + '    Value: Integer;' + sLineBreak + '  end;' + sLineBreak + sLineBreak + 'implementation' +
    sLineBreak + sLineBreak + 'end.', TEncoding.UTF8);
end;

procedure TSymbolMapDefinitionQueryTests.FindsProjectDefinitionByPositionAndName;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lDefinition: TSymbolMapDefinition;
  lError: string;
  lProfile: TSymbolMapCompilerProfileResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-query-cache');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected caches. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lProfile, lError),
    'Expected compiler profile. Error: ' + lError);
  IndexFixtureProject(lContext, lStatus);

  Assert.IsTrue(FindSymbolMapDefinitionByPosition(lContext, lStatus, lProfile,
    TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapUnit.pas'), 10, 3, lDefinition, lError),
    'Expected position lookup. Error: ' + lError);

  Assert.IsTrue(lDefinition.fFound, 'Expected definition at TSymbolMapFixture declaration.');
  Assert.AreEqual('TSymbolMapFixture', lDefinition.fName);
  Assert.AreEqual('type', lDefinition.fKind);
  Assert.AreEqual('project', lDefinition.fSourceKind);
  Assert.AreEqual('exact', lDefinition.fConfidence);
  Assert.IsTrue(lDefinition.fFilePath.EndsWith('SymbolMapUnit.pas'), 'Expected fixture unit file.');

  Assert.IsTrue(FindSymbolMapDefinitionByName(lContext, lStatus, lProfile, 'TDeclarationRecord', '',
    lDefinition, lError), 'Expected name lookup. Error: ' + lError);
  Assert.AreEqual('TDeclarationRecord', lDefinition.fName);
  Assert.AreEqual('type', lDefinition.fKind);
end;

procedure TSymbolMapDefinitionQueryTests.SearchesProjectMembersRtlSourceAndIntrinsics;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lProfile: TSymbolMapCompilerProfileResult;
  lResults: TArray<TSymbolMapDefinition>;
  lRoot: string;
  lRtl: TSymbolMapRtlIndexResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-search-cache');
  lRoot := UniqueTempPath('symbol-map-search-rtl');
  WriteRtlUnit(lRoot, 'rtl\sys\System.pas', 'System');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected caches. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lProfile, lError),
    'Expected compiler profile. Error: ' + lError);
  IndexFixtureProject(lContext, lStatus);
  Assert.IsTrue(IndexSymbolMapRtlSources(lContext, lStatus, lRoot, lProfile, lRtl, lError),
    'Expected RTL source index. Error: ' + lError);

  Assert.IsTrue(SearchSymbolMapDefinitions(lContext, lStatus, lProfile, 'enabled', 20, lResults, lError),
    'Expected member search. Error: ' + lError);
  Assert.IsTrue(Length(lResults) > 0, 'Expected search results.');
  Assert.AreEqual('Enabled', lResults[0].fName);
  Assert.AreEqual('property', lResults[0].fKind);
  Assert.AreEqual('TMemberClass', lResults[0].fOwnerName);

  Assert.IsTrue(SearchSymbolMapDefinitions(lContext, lStatus, lProfile, 'TSystemFixture', 20, lResults, lError),
    'Expected RTL source search. Error: ' + lError);
  Assert.IsTrue(Length(lResults) > 0, 'Expected RTL source result.');
  Assert.AreEqual('rtl-source', lResults[0].fSourceKind);

  Assert.IsTrue(SearchSymbolMapDefinitions(lContext, lStatus, lProfile, 'sizeof', 20, lResults, lError),
    'Expected intrinsic search. Error: ' + lError);
  Assert.IsTrue(Length(lResults) > 0, 'Expected intrinsic result.');
  Assert.AreEqual('SizeOf', lResults[0].fName);
  Assert.AreEqual('compiler-intrinsic', lResults[0].fSourceKind);
end;

procedure TSymbolMapDefinitionQueryTests.DescribesOwnedMembersAndIntrinsics;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lDefinition: TSymbolMapDefinition;
  lError: string;
  lProfile: TSymbolMapCompilerProfileResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-describe-cache');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected caches. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lProfile, lError),
    'Expected compiler profile. Error: ' + lError);
  IndexFixtureProject(lContext, lStatus);

  Assert.IsTrue(DescribeSymbolMapDefinition(lContext, lStatus, lProfile, 'Name', 'TMemberClass', lDefinition,
    lError), 'Expected member describe. Error: ' + lError);
  Assert.IsTrue(lDefinition.fFound, 'Expected owned member.');
  Assert.AreEqual('Name', lDefinition.fName);
  Assert.AreEqual('property', lDefinition.fKind);
  Assert.AreEqual('TMemberClass', lDefinition.fOwnerName);

  Assert.IsTrue(DescribeSymbolMapDefinition(lContext, lStatus, lProfile, 'SizeOf', '', lDefinition, lError),
    'Expected intrinsic describe. Error: ' + lError);
  Assert.AreEqual('SizeOf', lDefinition.fName);
  Assert.AreEqual('compiler-intrinsic', lDefinition.fSourceKind);
end;

procedure TSymbolMapDefinitionQueryTests.CliFindDefinitionReturnsJsonResult;
var
  lArgs: string;
  lCacheRoot: string;
  lExitCode: Cardinal;
  lJson: TJSONValue;
  lLogPath: string;
  lLogText: string;
begin
  lCacheRoot := UniqueTempPath('symbol-map-cli-definition-cache');
  lLogPath := UniqueTempPath('symbol-map-cli-definition') + '.log';
  lArgs := 'symbol-map find-definition --project ' + QuoteArg(FixtureProjectPath) + ' --file ' +
    QuoteArg(TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapUnit.pas')) +
    ' --line 1 --col 1 --cache-root ' + QuoteArg(lCacheRoot) + ' --format json';

  Assert.IsTrue(RunProcess(BuildFreshResolverExe, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start symbol-map find-definition command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected find-definition to succeed. See: ' + lLogPath);
  lLogText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lJson := TJSONObject.ParseJSONValue(lLogText);
  try
    Assert.IsTrue(lJson is TJSONObject, 'Expected JSON object. Actual: ' + lLogText);
    Assert.AreEqual('find-definition', TJSONObject(lJson).GetValue<string>('operation'));
    Assert.AreEqual('SymbolMapUnit', TJSONObject(lJson).GetValue<string>('result.definition.name'));
    Assert.AreEqual('unit', TJSONObject(lJson).GetValue<string>('result.definition.kind'));
    Assert.AreEqual('project', TJSONObject(lJson).GetValue<string>('result.definition.sourceKind'));
  finally
    lJson.Free;
  end;
end;

function TSymbolMapReferenceQueryTests.BuildContext(const aCacheRoot: string; out aContext: TSymbolMapContext):
  string;
var
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23';
  lOptions.fSymbolMapCacheRoot := aCacheRoot;
  lOptions.fHasSymbolMapCacheRoot := True;
  Assert.IsTrue(TryBuildSymbolMapContext(lOptions, aContext, lError), 'Expected context. Error: ' + lError);
  Result := FixtureProjectPath;
end;

function TSymbolMapReferenceQueryTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapFixture.dproj');
end;

procedure TSymbolMapReferenceQueryTests.IndexFixtureProject(const aContext: TSymbolMapContext;
  const aStatus: TSymbolMapCacheStatus);
var
  lError: string;
  lModel: TSymbolMapUnitModel;
  lUnitPath: string;
  lUnitPaths: TArray<string>;
begin
  lUnitPaths := [
    TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapDeclarations.pas'),
    TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapMembers.pas'),
    TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapUnit.pas')];
  for lUnitPath in lUnitPaths do
  begin
    Assert.IsTrue(TryExtractSymbolMapUnitModel(lUnitPath, lModel, lError),
      'Expected source extraction. Error: ' + lError);
    Assert.IsTrue(StoreSymbolMapUnitModel(aContext, aStatus, lModel, lError),
      'Expected unit model storage. Error: ' + lError);
  end;
end;

function TSymbolMapReferenceQueryTests.UniqueTempPath(const aPrefix: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := StringReplace(StringReplace(GUIDToString(lGuid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);
  Result := TPath.Combine(TempRoot, aPrefix + '-' + lGuidText);
end;

procedure TSymbolMapReferenceQueryTests.FindsTokenReferencesInProjectScope;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lProfile: TSymbolMapCompilerProfileResult;
  lReferences: TArray<TSymbolMapReference>;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-reference-cache');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected caches. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lProfile, lError),
    'Expected compiler profile. Error: ' + lError);
  IndexFixtureProject(lContext, lStatus);

  Assert.IsTrue(FindSymbolMapReferences(lContext, lStatus, lProfile, 'TSymbolMapFixtureType', 10, lReferences,
    lError), 'Expected reference query. Error: ' + lError);

  Assert.IsTrue(Length(lReferences) >= 4, 'Expected several token references.');
  Assert.AreEqual('TSymbolMapFixtureType', lReferences[0].fName);
  Assert.AreEqual('project', lReferences[0].fSourceKind);
  Assert.AreEqual('token-name-match', lReferences[0].fConfidence);
  Assert.IsTrue(lReferences[0].fFilePath.EndsWith('SymbolMapUnit.pas'), 'Expected fixture source file.');
  Assert.IsTrue(lReferences[0].fLine > 0, 'Expected source line.');
end;

procedure TSymbolMapReferenceQueryTests.LimitsTokenReferenceResults;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lProfile: TSymbolMapCompilerProfileResult;
  lReferences: TArray<TSymbolMapReference>;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-reference-limit-cache');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected caches. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lProfile, lError),
    'Expected compiler profile. Error: ' + lError);
  IndexFixtureProject(lContext, lStatus);

  Assert.IsTrue(FindSymbolMapReferences(lContext, lStatus, lProfile, 'TSymbolMapFixtureType', 2, lReferences,
    lError), 'Expected limited reference query. Error: ' + lError);

  Assert.AreEqual(2, Length(lReferences));
end;

function TSymbolMapApiTests.BaseOptions(const aCacheRoot: string): TAppOptions;
begin
  Result := Default(TAppOptions);
  Result.fDprojPath := FixtureProjectPath;
  Result.fConfig := 'Release';
  Result.fPlatform := 'Win32';
  Result.fDelphiVersion := '23';
  Result.fSymbolMapCacheRoot := aCacheRoot;
  Result.fHasSymbolMapCacheRoot := True;
end;

function TSymbolMapApiTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapFixture.dproj');
end;

function TSymbolMapApiTests.UniqueTempPath(const aPrefix: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := StringReplace(StringReplace(GUIDToString(lGuid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);
  Result := TPath.Combine(TempRoot, aPrefix + '-' + lGuidText);
end;

procedure TSymbolMapApiTests.ResolvesCoreSymbolKindsWithoutShellingOut;
var
  lCacheRoot: string;
  lError: string;
  lOptions: TAppOptions;
  lResult: TSymbolMapApiLookupResult;
begin
  lCacheRoot := UniqueTempPath('symbol-map-api-cache');
  lOptions := BaseOptions(lCacheRoot);

  Assert.IsTrue(ResolveSymbolMapDefinitionByName(lOptions, 'TDeclarationRecord', '', lResult, lError),
    'Expected type lookup. Error: ' + lError);
  Assert.AreEqual('type', lResult.fDefinition.fKind);
  Assert.AreEqual('project', lResult.fDefinition.fSourceKind);

  Assert.IsTrue(ResolveSymbolMapDefinitionByName(lOptions, 'Name', 'TMemberClass', lResult, lError),
    'Expected member lookup. Error: ' + lError);
  Assert.AreEqual('property', lResult.fDefinition.fKind);
  Assert.AreEqual('TMemberClass', lResult.fDefinition.fOwnerName);

  Assert.IsTrue(ResolveSymbolMapDefinitionByName(lOptions, 'DeclarationFunction', '', lResult, lError),
    'Expected routine lookup. Error: ' + lError);
  Assert.AreEqual('routine', lResult.fDefinition.fKind);

  Assert.IsTrue(ResolveSymbolMapDefinitionByName(lOptions, 'GDeclarationGlobal', '', lResult, lError),
    'Expected global lookup. Error: ' + lError);
  Assert.AreEqual('var', lResult.fDefinition.fKind);

  Assert.IsTrue(ResolveSymbolMapDefinitionByName(lOptions, 'SizeOf', '', lResult, lError),
    'Expected intrinsic lookup. Error: ' + lError);
  Assert.AreEqual('compiler-intrinsic', lResult.fDefinition.fSourceKind);
end;

procedure TSymbolMapApiTests.ResolvesSourcePositionAndReportsCacheStatus;
var
  lCacheRoot: string;
  lError: string;
  lOptions: TAppOptions;
  lResult: TSymbolMapApiLookupResult;
begin
  lCacheRoot := UniqueTempPath('symbol-map-api-position-cache');
  lOptions := BaseOptions(lCacheRoot);

  Assert.IsTrue(ResolveSymbolMapDefinitionByPosition(lOptions,
    TPath.Combine(RepoRoot, 'tests\fixtures\SymbolMapFixture\SymbolMapUnit.pas'), 1, 1, lResult, lError),
    'Expected source-position lookup. Error: ' + lError);

  Assert.AreEqual('SymbolMapUnit', lResult.fDefinition.fName);
  Assert.AreEqual('unit', lResult.fDefinition.fKind);
  Assert.IsTrue(lResult.fStatus.fProjectIndexed, 'Expected project indexing status.');
  Assert.IsNotEmpty(lResult.fStatus.fCacheStatus.fCentralDbPath, 'Expected central cache path.');
  Assert.IsNotEmpty(lResult.fStatus.fCompilerProfile.fProfileKey, 'Expected compiler profile key.');
end;

function TSymbolMapRtlIndexTests.ProfileSourceKind(const aDbPath, aProfileKey, aUnitName: string): string;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  lDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  lConnection := TFDConnection.Create(nil);
  try
    lConnection.LoginPrompt := False;
    lConnection.Params.Values['DriverID'] := 'SQLite';
    lConnection.Params.Values['Database'] := aDbPath;
    lConnection.Connected := True;
    Result := VarToStr(lConnection.ExecSQLScalar(
      'select source_kind from compiler_profile_units where profile_key = ? and unit_name = ?',
      [aProfileKey, aUnitName]));
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TSymbolMapRtlIndexTests.UniqueTempPath(const aPrefix: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := StringReplace(StringReplace(GUIDToString(lGuid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);
  Result := TPath.Combine(TempRoot, aPrefix + '-' + lGuidText);
end;

procedure TSymbolMapRtlIndexTests.WriteRtlUnit(const aRoot, aRelativePath, aUnitName: string);
var
  lPath: string;
begin
  lPath := TPath.Combine(aRoot, aRelativePath);
  ForceDirectories(TPath.GetDirectoryName(lPath));
  TFile.WriteAllText(lPath, 'unit ' + aUnitName + ';' + sLineBreak + sLineBreak + 'interface' + sLineBreak +
    'type' + sLineBreak + '  T' + StringReplace(aUnitName, '.', '', [rfReplaceAll]) + 'Fixture = class' +
    sLineBreak + '  end;' + sLineBreak + sLineBreak + 'implementation' + sLineBreak + sLineBreak + 'end.',
    TEncoding.UTF8);
end;

procedure TSymbolMapRtlIndexTests.IndexesSourceAvailableRtlUnitsIntoCompilerProfile;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lProfile: TSymbolMapCompilerProfileResult;
  lRoot: string;
  lRtl: TSymbolMapRtlIndexResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-rtl-cache');
  lRoot := UniqueTempPath('symbol-map-rtl-root');
  WriteRtlUnit(lRoot, 'rtl\sys\System.pas', 'System');
  WriteRtlUnit(lRoot, 'rtl\sys\System.SysUtils.pas', 'System.SysUtils');
  WriteRtlUnit(lRoot, 'rtl\common\System.Types.pas', 'System.Types');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected cache schema. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lProfile, lError),
    'Expected compiler profile seed. Error: ' + lError);

  Assert.IsTrue(IndexSymbolMapRtlSources(lContext, lStatus, lRoot, lProfile, lRtl, lError),
    'Expected RTL source index. Error: ' + lError);

  Assert.AreEqual('indexed', lRtl.fStatus);
  Assert.AreEqual(3, lRtl.fUnitsIndexed);
  Assert.AreEqual(0, lRtl.fUnitCacheHits);
  Assert.AreEqual(3, lRtl.fUnitCacheMisses);
  Assert.AreEqual(0, lRtl.fDiagnosticsCount);
  Assert.AreEqual(3, CompilerProfileUnitCount(lStatus.fCentralDbPath, lProfile.fProfileKey));
  Assert.AreEqual('rtl-source', ProfileSourceKind(lStatus.fCentralDbPath, lProfile.fProfileKey, 'System'));
  Assert.AreEqual('rtl-source', ProfileSourceKind(lStatus.fCentralDbPath, lProfile.fProfileKey, 'System.Types'));
end;

procedure TSymbolMapRtlIndexTests.MissingRtlRootIsNonFatalDiagnostic;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lMissingRoot: string;
  lProfile: TSymbolMapCompilerProfileResult;
  lRtl: TSymbolMapRtlIndexResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-rtl-missing-cache');
  lMissingRoot := UniqueTempPath('symbol-map-rtl-missing-root');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected cache schema. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lProfile, lError),
    'Expected compiler profile seed. Error: ' + lError);

  Assert.IsTrue(IndexSymbolMapRtlSources(lContext, lStatus, lMissingRoot, lProfile, lRtl, lError),
    'Expected missing RTL source root to be non-fatal. Error: ' + lError);

  Assert.AreEqual('missing-source-root', lRtl.fStatus);
  Assert.AreEqual(0, lRtl.fUnitsIndexed);
  Assert.IsTrue(lRtl.fDiagnosticsCount > 0, 'Expected missing-source diagnostic.');
  Assert.AreEqual(0, CompilerProfileUnitCount(lStatus.fCentralDbPath, lProfile.fProfileKey));
end;

procedure TSymbolMapRtlIndexTests.RepeatedRtlIndexReusesCompilerProfileUnits;
var
  lCacheRoot: string;
  lContext: TSymbolMapContext;
  lError: string;
  lFirst: TSymbolMapRtlIndexResult;
  lProfile: TSymbolMapCompilerProfileResult;
  lRoot: string;
  lSecond: TSymbolMapRtlIndexResult;
  lStatus: TSymbolMapCacheStatus;
begin
  lCacheRoot := UniqueTempPath('symbol-map-rtl-reuse-cache');
  lRoot := UniqueTempPath('symbol-map-rtl-reuse-root');
  WriteRtlUnit(lRoot, 'rtl\sys\System.pas', 'System');
  BuildContext(lCacheRoot, lContext);
  Assert.IsTrue(EnsureSymbolMapCaches(lContext, lStatus, lError), 'Expected cache schema. Error: ' + lError);
  Assert.IsTrue(EnsureSymbolMapCompilerProfile(lContext, lStatus, lProfile, lError),
    'Expected compiler profile seed. Error: ' + lError);

  Assert.IsTrue(IndexSymbolMapRtlSources(lContext, lStatus, lRoot, lProfile, lFirst, lError),
    'Expected first RTL source index. Error: ' + lError);
  Assert.IsTrue(IndexSymbolMapRtlSources(lContext, lStatus, lRoot, lProfile, lSecond, lError),
    'Expected second RTL source index. Error: ' + lError);

  Assert.IsFalse(lFirst.fCacheHit, 'Expected first RTL index to miss.');
  Assert.IsTrue(lSecond.fCacheHit, 'Expected second RTL index to hit.');
  Assert.AreEqual(1, lSecond.fUnitsIndexed);
  Assert.AreEqual(1, CompilerProfileUnitCount(lStatus.fCentralDbPath, lProfile.fProfileKey));
end;

function TSymbolMapTopLevelDeclarationTests.FindSymbol(const aModel: TSymbolMapUnitModel; const aName, aKind,
  aSectionKind: string; out aSymbol: TSymbolMapSymbolModel): Boolean;
var
  lSymbol: TSymbolMapSymbolModel;
begin
  Result := False;
  aSymbol := Default(TSymbolMapSymbolModel);
  for lSymbol in aModel.fSymbols do
  begin
    if SameText(lSymbol.fName, aName) and SameText(lSymbol.fKind, aKind) and
      SameText(lSymbol.fSectionKind, aSectionKind) then
    begin
      aSymbol := lSymbol;
      Exit(True);
    end;
  end;
end;

function TSymbolMapTopLevelDeclarationTests.RunIndexUnitCommand(out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lCacheRoot: string;
  lJson: TJSONValue;
  lLogPath: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lCacheRoot := TPath.Combine(TempRoot, 'symbol-map-declarations-cache');
  if TDirectory.Exists(lCacheRoot) then
    TDirectory.Delete(lCacheRoot, True);
  lLogPath := TPath.Combine(TempRoot, 'symbol-map-declarations-index-json.log');
  lArgs := 'symbol-map index --project ' + QuoteArg(FixtureProjectPath) + ' --unit ' + QuoteArg(FixtureUnitPath) +
    ' --cache-root ' + QuoteArg(lCacheRoot) + ' --format json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start symbol-map declaration index command.');
  lLogText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lJson := TJSONObject.ParseJSONValue(lLogText);
  Assert.IsTrue(lJson is TJSONObject, 'Expected JSON object. Actual: ' + lLogText);
  Result := lJson as TJSONObject;
end;

procedure TSymbolMapTopLevelDeclarationTests.ExtractsTopLevelDeclarationsAndEnumValues;
var
  lError: string;
  lModel: TSymbolMapUnitModel;
  lSymbol: TSymbolMapSymbolModel;
begin
  Assert.IsTrue(TryExtractSymbolMapUnitModel(FixtureUnitPath, lModel, lError),
    'Expected declaration unit extraction to succeed. Error: ' + lError);

  Assert.AreEqual('SymbolMapDeclarations', lModel.fUnitName);
  Assert.IsTrue(FindSymbol(lModel, 'TDeclarationEnum', 'type', 'interface', lSymbol), 'Expected enum type.');
  Assert.AreEqual('enum', lSymbol.fTypeName);
  Assert.IsTrue(FindSymbol(lModel, 'deOne', 'enum-value', 'interface', lSymbol), 'Expected enum value.');
  Assert.AreEqual('TDeclarationEnum', lSymbol.fOwnerName);
  Assert.IsTrue(FindSymbol(lModel, 'TDeclarationAlias', 'type-alias', 'interface', lSymbol),
    'Expected alias type.');
  Assert.AreEqual('string', lSymbol.fTypeName);
  Assert.IsTrue(FindSymbol(lModel, 'TDeclarationRecord', 'type', 'interface', lSymbol), 'Expected record type.');
  Assert.AreEqual('record', lSymbol.fTypeName);
  Assert.IsTrue(FindSymbol(lModel, 'TDeclarationClass', 'type', 'interface', lSymbol), 'Expected class type.');
  Assert.AreEqual('class', lSymbol.fTypeName);
  Assert.IsTrue(FindSymbol(lModel, 'cDeclarationConst', 'const', 'interface', lSymbol), 'Expected const.');
  Assert.IsTrue(FindSymbol(lModel, 'cDeclarationTyped', 'typed-const', 'interface', lSymbol),
    'Expected typed const.');
  Assert.AreEqual('Integer', lSymbol.fTypeName);
  Assert.IsTrue(FindSymbol(lModel, 'GDeclarationGlobal', 'var', 'interface', lSymbol), 'Expected var.');
  Assert.AreEqual('Integer', lSymbol.fTypeName);
  Assert.IsTrue(FindSymbol(lModel, 'DeclarationProcedure', 'routine', 'interface', lSymbol),
    'Expected procedure.');
  Assert.IsTrue(Pos('const aName: string', lSymbol.fSignature) > 0, 'Expected procedure signature.');
  Assert.IsTrue(FindSymbol(lModel, 'DeclarationFunction', 'routine', 'interface', lSymbol),
    'Expected function.');
  Assert.AreEqual('Integer', lSymbol.fTypeName);
  Assert.IsTrue(FindSymbol(lModel, 'DeclarationMultiParam', 'routine', 'interface', lSymbol),
    'Expected multi-parameter function.');
  Assert.AreEqual('Boolean', lSymbol.fTypeName);
  Assert.IsTrue(Pos('const aName: string; const aValue: Integer', lSymbol.fSignature) > 0,
    'Expected semicolon inside parameter list to stay in signature.');
  Assert.IsTrue(FindSymbol(lModel, 'ImplementationOnlyProcedure', 'routine', 'implementation', lSymbol),
    'Expected implementation routine.');
  Assert.IsTrue(FindSymbol(lModel, 'GImplementationGlobal', 'var', 'implementation', lSymbol),
    'Expected implementation var.');
  Assert.AreEqual(TPath.GetFullPath(FixtureUnitPath), lSymbol.fFilePath);
  Assert.AreNotEqual(0, lSymbol.fLine, 'Expected line number.');
  Assert.AreNotEqual(0, lSymbol.fCol, 'Expected column number.');
  Assert.AreNotEqual(0, lSymbol.fEndLine, 'Expected end line.');
  Assert.IsFalse(FindSymbol(lModel, 'cLocalConst', 'const', 'implementation', lSymbol),
    'Local consts inside routine bodies must not be indexed as top-level declarations.');
  Assert.IsFalse(FindSymbol(lModel, 'TLocalType', 'type-alias', 'implementation', lSymbol),
    'Local types inside routine bodies must not be indexed as top-level declarations.');
  Assert.IsFalse(FindSymbol(lModel, 'lLocalValue', 'var', 'implementation', lSymbol),
    'Local vars inside routine bodies must not be indexed as top-level declarations.');
end;

procedure TSymbolMapTopLevelDeclarationTests.IndexUnitCommandReportsTopLevelDeclarationCounts;
var
  lExitCode: Cardinal;
  lIndexedUnits: TJSONArray;
  lResult: TJSONObject;
  lRoot: TJSONObject;
  lUnitObject: TJSONObject;
begin
  lRoot := RunIndexUnitCommand(lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected symbol-map index to succeed.');
    lResult := lRoot.GetValue('result') as TJSONObject;
    Assert.AreEqual(1, lResult.GetValue<Integer>('unitCount'));
    Assert.AreEqual(0, lResult.GetValue<Integer>('fatalDiagnostics'));
    Assert.AreEqual(18, lResult.GetValue<Integer>('symbolCount'));
    lIndexedUnits := lResult.GetValue('indexedUnits') as TJSONArray;
    lUnitObject := lIndexedUnits.Items[0] as TJSONObject;
    Assert.AreEqual(18, lUnitObject.GetValue<Integer>('symbolCount'));
    Assert.IsTrue(Pos('"TDeclarationAlias"', lUnitObject.GetValue('symbols').ToJSON) > 0,
      'Expected declaration symbols in JSON.');
  finally
    lRoot.Free;
  end;
end;

procedure TSymbolMapSourceUnitTests.LoadsAnsiFallbackWhenUtf8Fails;
var
  lBytes: TBytes;
  lEncoding: string;
  lError: string;
  lPath: string;
  lText: string;
begin
  lPath := TPath.Combine(TempRoot, 'symbol-map-ansi-source.pas');
  lBytes := TBytes.Create($75, $6E, $69, $74, $20, $41, $6E, $73, $69, $46, $61, $6C, $6C, $62, $61, $63,
    $6B, $3B, $0D, $0A, $69, $6E, $74, $65, $72, $66, $61, $63, $65, $0D, $0A, $2F, $2F, $20, $E4,
    $0D, $0A, $75, $73, $65, $73, $20, $53, $79, $73, $74, $65, $6D, $2E, $53, $79, $73, $55, $74,
    $69, $6C, $73, $3B, $0D, $0A, $69, $6D, $70, $6C, $65, $6D, $65, $6E, $74, $61, $74, $69, $6F,
    $6E, $0D, $0A, $65, $6E, $64, $2E);
  TFile.WriteAllBytes(lPath, lBytes);

  Assert.IsTrue(TryLoadSymbolMapSourceFile(lPath, lText, lEncoding, lError),
    'Expected source loading to succeed. Error: ' + lError);
  Assert.AreEqual('ansi', lEncoding);
  Assert.IsTrue(Pos('AnsiFallback', lText) > 0, 'Expected decoded ANSI source text.');
end;

procedure TSymbolMapSourceUnitTests.LoadsAnsiFallbackForInvalidUtf8SurrogateSequence;
var
  lBytes: TBytes;
  lEncoding: string;
  lError: string;
  lPath: string;
  lText: string;
begin
  lPath := TPath.Combine(TempRoot, 'symbol-map-invalid-utf8-source.pas');
  lBytes := TBytes.Create($75, $6E, $69, $74, $20, $42, $61, $64, $55, $74, $66, $38, $3B, $0D, $0A,
    $69, $6E, $74, $65, $72, $66, $61, $63, $65, $0D, $0A, $2F, $2F, $20, $ED, $A0, $A0, $0D, $0A,
    $69, $6D, $70, $6C, $65, $6D, $65, $6E, $74, $61, $74, $69, $6F, $6E, $0D, $0A, $65, $6E,
    $64, $2E);
  TFile.WriteAllBytes(lPath, lBytes);

  Assert.IsTrue(TryLoadSymbolMapSourceFile(lPath, lText, lEncoding, lError),
    'Expected source loading to succeed. Error: ' + lError);
  Assert.AreEqual('ansi', lEncoding);
  Assert.IsTrue(Pos('BadUtf8', lText) > 0, 'Expected decoded fallback source text.');
end;

procedure TSymbolMapSourceUnitTests.ExtractsUnitNameAndUsesSections;
var
  lError: string;
  lModel: TSymbolMapUnitModel;
begin
  Assert.IsTrue(TryExtractSymbolMapUnitModel(FixtureUnitPath, lModel, lError),
    'Expected unit model extraction to succeed. Error: ' + lError);
  Assert.AreEqual('SymbolMapUnit', lModel.fUnitName);
  Assert.AreEqual(TPath.GetFullPath(FixtureUnitPath), lModel.fFilePath);
  Assert.AreEqual('utf-8', lModel.fEncodingName);
  Assert.AreEqual(4, Length(lModel.fUses));
  Assert.AreEqual('System.SysUtils', lModel.fUses[0].fUnitName);
  Assert.AreEqual('interface', lModel.fUses[0].fSectionKind);
  Assert.AreEqual('Winapi.Windows', lModel.fUses[1].fUnitName);
  Assert.AreEqual('interface', lModel.fUses[1].fSectionKind);
  Assert.AreEqual('System.Classes', lModel.fUses[2].fUnitName);
  Assert.AreEqual('implementation', lModel.fUses[2].fSectionKind);
  Assert.AreEqual('System.Generics.Collections', lModel.fUses[3].fUnitName);
  Assert.AreEqual('implementation', lModel.fUses[3].fSectionKind);
end;

procedure TSymbolMapSourceUnitTests.ExtractsNamespacedUnitName;
var
  lError: string;
  lModel: TSymbolMapUnitModel;
  lPath: string;
begin
  lPath := TPath.Combine(TempRoot, 'symbol-map-namespaced-unit.pas');
  TFile.WriteAllText(lPath, 'unit Foo.Bar;' + sLineBreak + 'interface' + sLineBreak +
    'uses System.SysUtils;' + sLineBreak + 'implementation' + sLineBreak + 'end.', TEncoding.UTF8);

  Assert.IsTrue(TryExtractSymbolMapUnitModel(lPath, lModel, lError),
    'Expected unit model extraction to succeed. Error: ' + lError);
  Assert.AreEqual('Foo.Bar', lModel.fUnitName);
  Assert.AreEqual('System.SysUtils', lModel.fUses[0].fUnitName);
end;

procedure TSymbolMapSourceUnitTests.IndexUnitCommandReportsOneIndexedUnit;
var
  lArgs: string;
  lCacheRoot: string;
  lExitCode: Cardinal;
  lIndexedUnits: TJSONArray;
  lJson: TJSONObject;
  lJsonValue: TJSONValue;
  lLogPath: string;
  lLogText: string;
  lResult: TJSONObject;
  lUnitObject: TJSONObject;
begin
  EnsureResolverBuilt;
  lCacheRoot := TPath.Combine(TempRoot, 'symbol-map-source-cache');
  if TDirectory.Exists(lCacheRoot) then
    TDirectory.Delete(lCacheRoot, True);
  lLogPath := TPath.Combine(TempRoot, 'symbol-map-source-index-json.log');
  lArgs := 'symbol-map index --project ' + QuoteArg(FixtureProjectPath) + ' --unit ' + QuoteArg(FixtureUnitPath) +
    ' --cache-root ' + QuoteArg(lCacheRoot) + ' --format json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start symbol-map index command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected symbol-map index to succeed. See: ' + lLogPath);

  lLogText := TFile.ReadAllText(lLogPath);
  lJsonValue := TJSONObject.ParseJSONValue(lLogText);
  try
    Assert.IsTrue(lJsonValue is TJSONObject, 'Expected JSON object. Actual: ' + lLogText);
    lJson := TJSONObject(lJsonValue);
    lResult := lJson.GetValue('result') as TJSONObject;
    Assert.AreEqual(1, lResult.GetValue<Integer>('unitCount'));
    Assert.AreEqual(0, lResult.GetValue<Integer>('fatalDiagnostics'));
    lIndexedUnits := lResult.GetValue('indexedUnits') as TJSONArray;
    Assert.AreEqual(1, lIndexedUnits.Count);
    lUnitObject := lIndexedUnits.Items[0] as TJSONObject;
    Assert.AreEqual('SymbolMapUnit', lUnitObject.GetValue<string>('unitName'));
    Assert.AreEqual(2, (lUnitObject.GetValue('interfaceUses') as TJSONArray).Count);
    Assert.AreEqual(2, (lUnitObject.GetValue('implementationUses') as TJSONArray).Count);
  finally
    lJsonValue.Free;
  end;
end;

procedure TSymbolMapContextTests.ResolvesProjectAndProjectCacheRoot;
var
  lContext: TSymbolMapContext;
  lError: string;
  lOptions: TAppOptions;
  lProjectDir: string;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23';

  Assert.IsTrue(TryBuildSymbolMapContext(lOptions, lContext, lError), 'Expected context to resolve. Error: ' + lError);
  lProjectDir := TPath.GetDirectoryName(FixtureProjectPath);
  Assert.AreEqual(TPath.GetFullPath(FixtureProjectPath), lContext.fProject.fProjectPath);
  Assert.AreEqual('LspProjectFixture', lContext.fProject.fProjectName);
  Assert.AreEqual('23.0', lContext.fDelphiVersion);
  Assert.AreEqual(TPath.Combine(TPath.Combine(TPath.Combine(lProjectDir, '.dak'), 'LspProjectFixture'), 'symbol-map'),
    lContext.fProjectCacheRoot);
  Assert.IsTrue(Pos('symbol-map', LowerCase(lContext.fCentralCacheRoot)) > 0,
    'Expected default central cache root to include symbol-map. Actual: ' + lContext.fCentralCacheRoot);
end;

procedure TSymbolMapContextTests.CacheRootOptionOverridesCentralRoot;
var
  lContext: TSymbolMapContext;
  lError: string;
  lOptions: TAppOptions;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'symbol-map-cache-option');
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fSymbolMapCacheRoot := lRoot;
  lOptions.fHasSymbolMapCacheRoot := True;

  Assert.IsTrue(TryBuildSymbolMapContext(lOptions, lContext, lError), 'Expected context to resolve. Error: ' + lError);
  Assert.AreEqual(TPath.GetFullPath(lRoot), lContext.fCentralCacheRoot);
end;

procedure TSymbolMapContextTests.CacheRootEnvironmentOverridesCentralRoot;
var
  lContext: TSymbolMapContext;
  lError: string;
  lOldRoot: string;
  lOptions: TAppOptions;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'symbol-map-cache-env');
  lOldRoot := GetEnvironmentVariable('DAK_SYMBOL_MAP_CACHE_ROOT');
  SetEnvironmentVariable('DAK_SYMBOL_MAP_CACHE_ROOT', PChar(lRoot));
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := FixtureProjectPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';

    Assert.IsTrue(TryBuildSymbolMapContext(lOptions, lContext, lError), 'Expected context to resolve. Error: ' + lError);
    Assert.AreEqual(TPath.GetFullPath(lRoot), lContext.fCentralCacheRoot);
  finally
    if lOldRoot = '' then
      SetEnvironmentVariable('DAK_SYMBOL_MAP_CACHE_ROOT', nil)
    else
      SetEnvironmentVariable('DAK_SYMBOL_MAP_CACHE_ROOT', PChar(lOldRoot));
  end;
end;

procedure TSymbolMapContextTests.StatsJsonReportsCacheRoots;
var
  lArgs: string;
  lCacheRoot: string;
  lContext: TJSONObject;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lJsonValue: TJSONValue;
  lLogPath: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lCacheRoot := TPath.Combine(TempRoot, 'symbol-map-cache-cli');
  lLogPath := TPath.Combine(TempRoot, 'symbol-map-stats-context-json.log');
  lArgs := 'symbol-map stats --project ' + QuoteArg(FixtureProjectPath) + ' --cache-root ' + QuoteArg(lCacheRoot) +
    ' --format json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start symbol-map stats command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected symbol-map stats to succeed. See: ' + lLogPath);

  lLogText := TFile.ReadAllText(lLogPath);
  lJsonValue := TJSONObject.ParseJSONValue(lLogText);
  try
    Assert.IsTrue(lJsonValue is TJSONObject, 'Expected JSON object. Actual: ' + lLogText);
    lJson := TJSONObject(lJsonValue);
    Assert.AreEqual(TPath.GetFullPath(lCacheRoot), (lJson.GetValue('cache') as TJSONObject).GetValue<string>('centralRoot'));
    Assert.IsTrue(Pos('\.dak\LspProjectFixture\symbol-map',
      (lJson.GetValue('cache') as TJSONObject).GetValue<string>('projectRoot')) > 0,
      'Expected project symbol-map cache root. Actual: ' + lLogText);
    Assert.AreEqual('Release', (lJson.GetValue('project') as TJSONObject).GetValue<string>('config'));
    Assert.AreEqual('Win32', (lJson.GetValue('project') as TJSONObject).GetValue<string>('platform'));
    lContext := lJson.GetValue('context') as TJSONObject;
    Assert.IsTrue(lContext.GetValue('defines') is TJSONArray, 'Expected defines array.');
    Assert.IsTrue(lContext.GetValue('unitSearchPath') is TJSONArray, 'Expected unitSearchPath array.');
    Assert.IsTrue(lContext.GetValue('libraryPath') is TJSONArray, 'Expected libraryPath array.');
    Assert.IsTrue(lContext.GetValue('unitScopes') is TJSONArray, 'Expected unitScopes array.');
    Assert.IsTrue(lContext.GetValue('unitAliases') is TJSONArray, 'Expected unitAliases array.');
  finally
    lJsonValue.Free;
  end;
end;

procedure TSymbolMapCliTests.SetParams(const aCmdLine: string);
var
  lParams: iCmdLineParams;
begin
  lParams := maxCmdLineParams;
  lParams.BuildFromString(aCmdLine);
end;

procedure TSymbolMapCliTests.ParsesStatsCommandWithJsonFormat;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('symbol-map stats --project c:\temp\sample.dproj --format json');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected symbol-map stats to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckSymbolMap, lOptions.fCommand);
  Assert.AreEqual(TSymbolMapOperation.smoStats, lOptions.fSymbolMapOperation);
  Assert.AreEqual(TSymbolMapFormat.smfJson, lOptions.fSymbolMapFormat);
  Assert.AreEqual('c:\temp\sample.dproj', lOptions.fDprojPath);
end;

procedure TSymbolMapCliTests.ParsesSupportedOperations;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('symbol-map index --project c:\temp\sample.dproj --unit c:\temp\unit1.pas --cache-root c:\cache --format text');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected symbol-map index to parse. Error: ' + lError);
  Assert.AreEqual(TSymbolMapOperation.smoIndex, lOptions.fSymbolMapOperation);
  Assert.AreEqual('c:\temp\unit1.pas', lOptions.fSymbolMapUnitPath);
  Assert.AreEqual('c:\cache', lOptions.fSymbolMapCacheRoot);
  Assert.IsTrue(lOptions.fHasSymbolMapCacheRoot);
  Assert.AreEqual(TSymbolMapFormat.smfText, lOptions.fSymbolMapFormat);

  SetParams('symbol-map find-definition --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 12 --col 3');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected symbol-map find-definition to parse. Error: ' + lError);
  Assert.AreEqual(TSymbolMapOperation.smoFindDefinition, lOptions.fSymbolMapOperation);
  Assert.AreEqual('c:\temp\unit1.pas', lOptions.fSymbolMapFilePath);
  Assert.AreEqual(12, lOptions.fSymbolMapLine);
  Assert.AreEqual(3, lOptions.fSymbolMapCol);

  SetParams('symbol-map find-references --project c:\temp\sample.dproj --symbol TFoo --limit 5');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected symbol-map find-references to parse. Error: ' + lError);
  Assert.AreEqual(TSymbolMapOperation.smoFindReferences, lOptions.fSymbolMapOperation);
  Assert.AreEqual('TFoo', lOptions.fSymbolMapSymbol);
  Assert.AreEqual(5, lOptions.fSymbolMapLimit);
  Assert.IsTrue(lOptions.fHasSymbolMapLimit);

  SetParams('symbol-map search-symbols --project c:\temp\sample.dproj --query Foo');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected symbol-map search-symbols to parse. Error: ' + lError);
  Assert.AreEqual(TSymbolMapOperation.smoSearchSymbols, lOptions.fSymbolMapOperation);
  Assert.AreEqual('Foo', lOptions.fSymbolMapQuery);

  SetParams('symbol-map describe-symbol --project c:\temp\sample.dproj --symbol TFoo --owner TOwner');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected symbol-map describe-symbol to parse. Error: ' + lError);
  Assert.AreEqual(TSymbolMapOperation.smoDescribeSymbol, lOptions.fSymbolMapOperation);
  Assert.AreEqual('TFoo', lOptions.fSymbolMapSymbol);
  Assert.AreEqual('TOwner', lOptions.fSymbolMapOwner);
end;

procedure TSymbolMapCliTests.RejectsMissingOperationArguments;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('symbol-map --project c:\temp\sample.dproj');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing operation to be rejected.');
  Assert.IsTrue(Pos('operation', LowerCase(lError)) > 0, 'Expected operation error. Actual: ' + lError);

  SetParams('symbol-map stats');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing --project to be rejected.');
  Assert.IsTrue(Pos('--project', lError) > 0, 'Expected missing --project error. Actual: ' + lError);

  SetParams('symbol-map find-definition --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 12');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing --col to be rejected.');
  Assert.IsTrue(Pos('--col', lError) > 0, 'Expected missing --col error. Actual: ' + lError);

  SetParams('symbol-map find-definition --project c:\temp\sample.dproj --line 12 --col 3');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing --file to be rejected.');
  Assert.IsTrue(Pos('--file', lError) > 0, 'Expected missing --file error. Actual: ' + lError);

  SetParams('symbol-map find-definition --project c:\temp\sample.dproj --file c:\temp\unit1.pas --col 3');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing --line to be rejected.');
  Assert.IsTrue(Pos('--line', lError) > 0, 'Expected missing --line error. Actual: ' + lError);

  SetParams('symbol-map find-references --project c:\temp\sample.dproj');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing --symbol to be rejected.');
  Assert.IsTrue(Pos('--symbol', lError) > 0, 'Expected missing --symbol error. Actual: ' + lError);

  SetParams('symbol-map search-symbols --project c:\temp\sample.dproj');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing --query to be rejected.');
  Assert.IsTrue(Pos('--query', lError) > 0, 'Expected missing --query error. Actual: ' + lError);

  SetParams('symbol-map describe-symbol --project c:\temp\sample.dproj');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing describe-symbol --symbol to be rejected.');
  Assert.IsTrue(Pos('--symbol', lError) > 0, 'Expected missing describe-symbol error. Actual: ' + lError);

  SetParams('symbol-map stats --project c:\temp\sample.dproj --limit 5');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected --limit outside query operations to be rejected.');
  Assert.IsTrue(Pos('--limit', lError) > 0, 'Expected invalid --limit operation error. Actual: ' + lError);

  SetParams('symbol-map stats --project c:\temp\sample.dproj --unit c:\temp\unit1.pas');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected --unit outside index to be rejected.');
  Assert.IsTrue(Pos('--unit', lError) > 0, 'Expected invalid --unit operation error. Actual: ' + lError);

  SetParams('symbol-map stats --project c:\temp\sample.dproj --file c:\temp\unit1.pas');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected --file outside find-definition to be rejected.');
  Assert.IsTrue(Pos('--file', lError) > 0, 'Expected invalid --file operation error. Actual: ' + lError);

  SetParams('symbol-map stats --project c:\temp\sample.dproj --symbol TFoo');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected --symbol outside symbol operations to be rejected.');
  Assert.IsTrue(Pos('--symbol', lError) > 0, 'Expected invalid --symbol operation error. Actual: ' + lError);

  SetParams('symbol-map find-definition --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 12 --col 3 --query Foo');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected --query outside search-symbols to be rejected.');
  Assert.IsTrue(Pos('--query', lError) > 0, 'Expected invalid --query operation error. Actual: ' + lError);

  SetParams('symbol-map find-references --project c:\temp\sample.dproj --symbol TFoo --owner TOwner');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected --owner outside describe-symbol to be rejected.');
  Assert.IsTrue(Pos('--owner', lError) > 0, 'Expected invalid --owner operation error. Actual: ' + lError);
end;

procedure TSymbolMapCliTests.HelpDocumentsSymbolMapOptions;
var
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'symbol-map-help.log');

  Assert.IsTrue(RunProcess(ResolverExePath, 'symbol-map --help', RepoRoot, lLogPath, lExitCode),
    'Failed to start symbol-map help command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected symbol-map --help to succeed. See: ' + lLogPath);

  lLogText := '';
  if FileExists(lLogPath) then
    lLogText := TFile.ReadAllText(lLogPath);

  Assert.IsTrue(Pos('index', lLogText) > 0, 'Expected symbol-map help to mention index.');
  Assert.IsTrue(Pos('find-definition', lLogText) > 0, 'Expected symbol-map help to mention find-definition.');
  Assert.IsTrue(Pos('find-references', lLogText) > 0, 'Expected symbol-map help to mention find-references.');
  Assert.IsTrue(Pos('search-symbols', lLogText) > 0, 'Expected symbol-map help to mention search-symbols.');
  Assert.IsTrue(Pos('describe-symbol', lLogText) > 0, 'Expected symbol-map help to mention describe-symbol.');
  Assert.IsTrue(Pos('stats', lLogText) > 0, 'Expected symbol-map help to mention stats.');
  Assert.IsTrue(Pos('--project', lLogText) > 0, 'Expected symbol-map help to mention --project.');
  Assert.IsTrue(Pos('--unit', lLogText) > 0, 'Expected symbol-map help to mention --unit.');
  Assert.IsTrue(Pos('--file', lLogText) > 0, 'Expected symbol-map help to mention --file.');
  Assert.IsTrue(Pos('--line', lLogText) > 0, 'Expected symbol-map help to mention --line.');
  Assert.IsTrue(Pos('--col', lLogText) > 0, 'Expected symbol-map help to mention --col.');
  Assert.IsTrue(Pos('--symbol', lLogText) > 0, 'Expected symbol-map help to mention --symbol.');
  Assert.IsTrue(Pos('--query', lLogText) > 0, 'Expected symbol-map help to mention --query.');
  Assert.IsTrue(Pos('--cache-root', lLogText) > 0, 'Expected symbol-map help to mention --cache-root.');
  Assert.IsTrue(Pos('--format', lLogText) > 0, 'Expected symbol-map help to mention --format.');
end;

procedure TSymbolMapCliTests.StatsCommandWritesJsonShell;
var
  lArgs: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lJsonValue: TJSONValue;
  lLogPath: string;
  lLogText: string;
  lProjectPath: string;
begin
  EnsureResolverBuilt;
  lProjectPath := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\LspProjectFixture.dproj');
  lLogPath := TPath.Combine(TempRoot, 'symbol-map-stats-json.log');
  lArgs := 'symbol-map stats --project ' + QuoteArg(lProjectPath) + ' --format json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start symbol-map stats command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected symbol-map stats to succeed. See: ' + lLogPath);

  lLogText := '';
  if FileExists(lLogPath) then
    lLogText := TFile.ReadAllText(lLogPath);

  lJsonValue := TJSONObject.ParseJSONValue(lLogText);
  try
    Assert.IsNotNull(lJsonValue, 'Expected parseable JSON. Actual: ' + lLogText);
    Assert.IsTrue(lJsonValue is TJSONObject, 'Expected JSON object. Actual: ' + lLogText);
    lJson := TJSONObject(lJsonValue);
    Assert.AreEqual('stats', lJson.GetValue<string>('operation'));
    Assert.AreEqual('ok', lJson.GetValue<string>('status'));
    Assert.IsTrue(lJson.GetValue('project') is TJSONObject, 'Expected project object.');
    Assert.IsTrue(lJson.GetValue('cache') is TJSONObject, 'Expected cache object.');
    Assert.IsTrue(lJson.GetValue('diagnostics') is TJSONArray, 'Expected diagnostics array.');
    Assert.IsTrue(lJson.GetValue('timings') is TJSONObject, 'Expected timings object.');
  finally
    lJsonValue.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSymbolMapContextTests);
  TDUnitX.RegisterTestFixture(TSymbolMapCacheTests);
  TDUnitX.RegisterTestFixture(TSymbolMapSourceUnitTests);
  TDUnitX.RegisterTestFixture(TSymbolMapTopLevelDeclarationTests);
  TDUnitX.RegisterTestFixture(TSymbolMapMemberExtractionTests);
  TDUnitX.RegisterTestFixture(TSymbolMapCentralCacheReuseTests);
  TDUnitX.RegisterTestFixture(TSymbolMapIntrinsicProfileTests);
  TDUnitX.RegisterTestFixture(TSymbolMapRtlIndexTests);
  TDUnitX.RegisterTestFixture(TSymbolMapDefinitionQueryTests);
  TDUnitX.RegisterTestFixture(TSymbolMapReferenceQueryTests);
  TDUnitX.RegisterTestFixture(TSymbolMapApiTests);
  TDUnitX.RegisterTestFixture(TSymbolMapCliTests);

end.
