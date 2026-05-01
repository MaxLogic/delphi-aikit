unit Test.SymbolMap;

interface

uses
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  DUnitX.TestFramework,
  maxLogic.CmdLineParams,
  Dak.Cli, Dak.Types,
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
  Winapi.Windows,
  Dak.SymbolMap.Context;

function TSymbolMapContextTests.FixtureProjectPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\LspProjectFixture.dproj');
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
  SetParams('symbol-map index --project c:\temp\sample.dproj --cache-root c:\cache --format text');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected symbol-map index to parse. Error: ' + lError);
  Assert.AreEqual(TSymbolMapOperation.smoIndex, lOptions.fSymbolMapOperation);
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
  TDUnitX.RegisterTestFixture(TSymbolMapCliTests);

end.
