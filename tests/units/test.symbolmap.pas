unit Test.SymbolMap;

interface

uses
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  System.Variants,
  DUnitX.TestFramework,
  maxLogic.CmdLineParams,
  Dak.Cli, Dak.SymbolMap.Context, Dak.Types,
  Test.Support;

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
  FireDAC.Phys.SQLite,
  Dak.SymbolMap.Cache, Dak.SymbolMap.Indexer;

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
  TDUnitX.RegisterTestFixture(TSymbolMapCliTests);

end.
