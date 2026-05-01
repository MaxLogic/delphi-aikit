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
  TDUnitX.RegisterTestFixture(TSymbolMapCliTests);

end.
