unit Test.AnalyzeEnvironment;

interface

uses
  System.IOUtils, System.SysUtils,
  DUnitX.TestFramework,
  maxLogic.CmdLineParams,
  Dak.Cli, Dak.Settings, Dak.Types,
  Test.Support;

type
  // analyze.py translated these environment variables into switches. Direct invocation of
  // `analyze --project` must honor the same contract (D2): an explicit switch wins, the environment
  // supplies what the command line left out, and settings supply the rest.
  [TestFixture]
  [Category('Fast')]
  TAnalyzeEnvironmentTests = class
  private
    fScopes: TArray<IInterface>;
    procedure IsolateEnvironment;
    procedure SetVariable(const aName, aValue: string);
    function Parse(const aCommandLine: string): TAppOptions;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure EnvironmentSuppliesMissingProjectSwitches;
    [Test]
    procedure ExplicitSwitchesWinOverEnvironment;
    [Test]
    procedure PascalAnalyzerFallsBackToDakPalAndDefaultsOn;
    [Test]
    procedure PascalAnalyzerVariableWinsOverDakPal;
    [Test]
    procedure FixInsightRuleVariablesMergeCaseInsensitively;
    [Test]
    procedure FixInsightSettingsPreferTheLongName;
    [Test]
    procedure RelativeOutputIsResolvedAgainstTheCurrentDirectory;
    [Test]
    procedure DelphiVersionIsStillRequired;
    [Test]
    procedure InvalidBooleanNamesTheVariable;
    [Test]
    procedure UnitEnvironmentSuppliesOnlyTheUnitContract;
    [Test]
    procedure UnitWithProjectContextDefaultsToWin64Release;
    [Test]
    procedure StandaloneUnitIgnoresPlatformAndConfigVariables;
    [Test]
    procedure PalIgnoreRulesFromEnvironmentRecordTheirOrigin;
    [Test]
    procedure SettingsRecordTheEnvironmentOriginWithoutTheProcessVariable;
    [Test]
    procedure PathVariablesAreNormalizedLikeTheWrapper;
  end;

implementation

const
  cProject = 'analyze --project C:\repo\Sample.dproj';
  cProjectWithDelphi = cProject + ' --delphi 23.0';
  cLegacyNames: array[0..22] of string = ('DAK_OUT', 'DAK_FIXINSIGHT', 'DAK_PASCAL_ANALYZER', 'DAK_PAL',
    'DAK_CLEAN', 'DAK_WRITE_SUMMARY', 'DAK_CONFIG', 'DAK_PLATFORM', 'DAK_DELPHI', 'DAK_FI_FORMATS',
    'DAK_RSVARS', 'DAK_ENVOPTIONS', 'DAK_EXCLUDE_PATH_MASKS', 'DAK_FI_IGNORE_RULES',
    'DAK_IGNORE_WARNING_IDS', 'DAK_PAL_IGNORE_RULES', 'FIXINSIGHT_SETTINGS', 'FI_SETTINGS', 'PA_PATH',
    'PA_ARGS', 'DAK_PAL_EXCLUDE_SEARCH_FOLDERS', 'DAK_PAL_EXCLUDE_FILES', 'DAK_PAL_IGNORE_RULES_ORIGIN');

procedure TAnalyzeEnvironmentTests.Setup;
begin
  fScopes := nil;
  IsolateEnvironment;
end;

procedure TAnalyzeEnvironmentTests.TearDown;
var
  i: Integer;
begin
  // Restore in reverse so a variable set after being cleared returns to its original value.
  for i := High(fScopes) downto 0 do
    fScopes[i] := nil;
  fScopes := nil;
end;

procedure TAnalyzeEnvironmentTests.IsolateEnvironment;
var
  lName: string;
begin
  for lName in cLegacyNames do
    fScopes := fScopes + [ClearScopedEnvironmentVariable(lName)];
end;

procedure TAnalyzeEnvironmentTests.SetVariable(const aName, aValue: string);
begin
  fScopes := fScopes + [SetScopedEnvironmentVariable(aName, aValue)];
end;

function TAnalyzeEnvironmentTests.Parse(const aCommandLine: string): TAppOptions;
var
  lError: string;
begin
  maxCmdLineParams.BuildFromString(aCommandLine);
  Assert.IsTrue(TryParseOptions(Result, lError), 'Parse failed: ' + lError);
end;

procedure TAnalyzeEnvironmentTests.EnvironmentSuppliesMissingProjectSwitches;
var
  lOptions: TAppOptions;
begin
  SetVariable('DAK_OUT', 'C:\reports\Sample');
  SetVariable('DAK_FIXINSIGHT', 'false');
  SetVariable('DAK_PASCAL_ANALYZER', 'false');
  SetVariable('DAK_CLEAN', 'false');
  SetVariable('DAK_WRITE_SUMMARY', 'false');
  SetVariable('DAK_CONFIG', 'Debug');
  SetVariable('DAK_PLATFORM', 'Win64');
  SetVariable('DAK_DELPHI', '37');
  SetVariable('DAK_FI_FORMATS', 'xml');
  SetVariable('DAK_RSVARS', 'C:\bds\rsvars.bat');
  SetVariable('DAK_ENVOPTIONS', 'C:\bds\EnvOptions.proj');
  SetVariable('DAK_EXCLUDE_PATH_MASKS', '*\generated\*');
  SetVariable('DAK_PAL_IGNORE_RULES', 'WARN54');
  SetVariable('FI_SETTINGS', 'C:\fi\settings.ficfg');
  SetVariable('PA_PATH', 'C:\pal\palcmd.exe');
  SetVariable('PA_ARGS', '/I="C:\pal\PAL.INI"');
  SetVariable('DAK_PAL_EXCLUDE_SEARCH_FOLDERS', 'C:\vendor');
  SetVariable('DAK_PAL_EXCLUDE_FILES', 'Big.pas');

  // No --delphi: DAK_DELPHI supplies it.
  lOptions := Parse(cProject);

  Assert.AreEqual(TCommandKind.ckAnalyzeProject, lOptions.fCommand);
  Assert.IsTrue(lOptions.fHasAnalyzeOutPath, 'DAK_OUT is an output path');
  Assert.AreEqual('C:\reports\Sample', lOptions.fAnalyzeOutPath);
  Assert.IsFalse(lOptions.fAnalyzeFixInsight, 'DAK_FIXINSIGHT');
  Assert.IsFalse(lOptions.fAnalyzePal, 'DAK_PASCAL_ANALYZER');
  Assert.IsFalse(lOptions.fAnalyzeClean, 'DAK_CLEAN');
  Assert.IsFalse(lOptions.fAnalyzeWriteSummary, 'DAK_WRITE_SUMMARY');
  Assert.AreEqual('Debug', lOptions.fConfig);
  Assert.AreEqual('Win64', lOptions.fPlatform);
  Assert.AreEqual('37.0', lOptions.fDelphiVersion, 'DAK_DELPHI is normalized like --delphi');
  Assert.IsTrue(lOptions.fAnalyzeFiFormats = [TReportFormat.rfXml], 'DAK_FI_FORMATS');
  Assert.IsTrue(lOptions.fHasRsVarsPath);
  Assert.AreEqual('C:\bds\rsvars.bat', lOptions.fRsVarsPath);
  Assert.IsTrue(lOptions.fHasEnvOptionsPath);
  Assert.AreEqual('C:\bds\EnvOptions.proj', lOptions.fEnvOptionsPath);
  Assert.IsTrue(lOptions.fHasExcludePathMasks);
  Assert.AreEqual('*\generated\*', lOptions.fExcludePathMasks);
  Assert.IsTrue(lOptions.fHasPalIgnoreRules);
  Assert.AreEqual('WARN54', lOptions.fPalIgnoreRules);
  Assert.IsTrue(lOptions.fHasFixSettings);
  Assert.AreEqual('C:\fi\settings.ficfg', lOptions.fFixSettings);
  Assert.IsTrue(lOptions.fHasPaPath);
  Assert.AreEqual('C:\pal\palcmd.exe', lOptions.fPaPath);
  Assert.IsTrue(lOptions.fHasPaArgs);
  Assert.AreEqual('/I="C:\pal\PAL.INI"', lOptions.fPaArgs);
  Assert.IsTrue(lOptions.fHasPaExcludeSearchFolders);
  Assert.AreEqual('C:\vendor', lOptions.fPaExcludeSearchFolders);
  Assert.IsTrue(lOptions.fHasPaExcludeFiles);
  Assert.AreEqual('Big.pas', lOptions.fPaExcludeFiles);
end;

procedure TAnalyzeEnvironmentTests.ExplicitSwitchesWinOverEnvironment;
var
  lOptions: TAppOptions;
begin
  SetVariable('DAK_OUT', 'C:\from-env');
  SetVariable('DAK_FIXINSIGHT', 'false');
  SetVariable('DAK_PASCAL_ANALYZER', 'true');
  SetVariable('DAK_CONFIG', 'Debug');
  SetVariable('DAK_PLATFORM', 'Win32');
  SetVariable('DAK_DELPHI', '37.0');
  SetVariable('DAK_FI_FORMATS', 'xml');
  SetVariable('DAK_FI_IGNORE_RULES', 'W501');
  SetVariable('DAK_PAL_IGNORE_RULES', 'WARN54');
  SetVariable('PA_ARGS', '/X');

  lOptions := Parse(cProjectWithDelphi + ' --out C:\from-switch --fixinsight true ' +
    '--pal false --config Release --platform Win64 --fi-formats csv --ignore-warning-ids C101 ' +
    '--pal-ignore-rules WARN7 --pa-args /Y');

  Assert.AreEqual('23.0', lOptions.fDelphiVersion, '--delphi wins');
  Assert.AreEqual('C:\from-switch', lOptions.fAnalyzeOutPath);
  Assert.IsTrue(lOptions.fAnalyzeFixInsight, '--fixinsight wins');
  Assert.IsFalse(lOptions.fAnalyzePal, '--pal (alias) wins');
  Assert.AreEqual('Release', lOptions.fConfig);
  Assert.AreEqual('Win64', lOptions.fPlatform);
  Assert.IsTrue(lOptions.fAnalyzeFiFormats = [TReportFormat.rfCsv], '--fi-formats wins');
  Assert.AreEqual('C101', lOptions.fIgnoreWarningIds);
  Assert.AreEqual('WARN7', lOptions.fPalIgnoreRules);
  Assert.AreEqual('', lOptions.fPalIgnoreRulesOrigin,
    'Rules from the command line do not carry the environment origin.');
  Assert.AreEqual('/Y', lOptions.fPaArgs);
end;

procedure TAnalyzeEnvironmentTests.PascalAnalyzerFallsBackToDakPalAndDefaultsOn;
var
  lOptions: TAppOptions;
begin
  // analyze.py passes --pascal-analyzer true when neither variable is set.
  lOptions := Parse(cProjectWithDelphi);
  Assert.IsTrue(lOptions.fAnalyzePal, 'Project analysis runs Pascal Analyzer by default.');

  SetVariable('DAK_PAL', 'false');
  lOptions := Parse(cProjectWithDelphi);
  Assert.IsFalse(lOptions.fAnalyzePal, 'DAK_PAL is the fallback name.');
end;

procedure TAnalyzeEnvironmentTests.PascalAnalyzerVariableWinsOverDakPal;
var
  lOptions: TAppOptions;
begin
  SetVariable('DAK_PAL', 'false');
  SetVariable('DAK_PASCAL_ANALYZER', 'true');
  lOptions := Parse(cProjectWithDelphi);
  Assert.IsTrue(lOptions.fAnalyzePal);
end;

procedure TAnalyzeEnvironmentTests.FixInsightRuleVariablesMergeCaseInsensitively;
var
  lOptions: TAppOptions;
begin
  // _merge_rule_lists: first spelling wins, order preserved, empty items dropped.
  SetVariable('DAK_FI_IGNORE_RULES', 'W501; w502;;');
  SetVariable('DAK_IGNORE_WARNING_IDS', 'W502;W503');
  lOptions := Parse(cProjectWithDelphi);
  Assert.IsTrue(lOptions.fHasIgnoreWarningIds);
  Assert.AreEqual('W501;w502;W503', lOptions.fIgnoreWarningIds);
end;

procedure TAnalyzeEnvironmentTests.FixInsightSettingsPreferTheLongName;
var
  lOptions: TAppOptions;
begin
  SetVariable('FIXINSIGHT_SETTINGS', 'C:\long.ficfg');
  SetVariable('FI_SETTINGS', 'C:\short.ficfg');
  lOptions := Parse(cProjectWithDelphi);
  Assert.AreEqual('C:\long.ficfg', lOptions.fFixSettings);
end;

procedure TAnalyzeEnvironmentTests.RelativeOutputIsResolvedAgainstTheCurrentDirectory;
var
  lOptions: TAppOptions;
begin
  SetVariable('DAK_OUT', 'reports\Sample');
  lOptions := Parse(cProjectWithDelphi);
  Assert.AreEqual(TPath.Combine(GetCurrentDir, 'reports\Sample'), lOptions.fAnalyzeOutPath);
end;

// analyze.py defaulted the version to 23.0; DAK does not guess a compiler, so a version missing
// from both --delphi and DAK_DELPHI stays an error.
procedure TAnalyzeEnvironmentTests.DelphiVersionIsStillRequired;
var
  lError: string;
  lOptions: TAppOptions;
begin
  maxCmdLineParams.BuildFromString(cProject);
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'No Delphi version from either source.');
  Assert.Contains(lError, '--delphi');
end;

procedure TAnalyzeEnvironmentTests.InvalidBooleanNamesTheVariable;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetVariable('DAK_CLEAN', 'sometimes');
  maxCmdLineParams.BuildFromString(cProjectWithDelphi);
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'An invalid boolean must be rejected.');
  Assert.Contains(lError, 'DAK_CLEAN');
  Assert.Contains(lError, 'sometimes');
end;

// analyze-unit.py forwards a narrower set than analyze.py: no rsvars, envoptions, FixInsight formats,
// report path masks or FixInsight settings, because a unit run never starts FixInsight.
procedure TAnalyzeEnvironmentTests.UnitEnvironmentSuppliesOnlyTheUnitContract;
var
  lOptions: TAppOptions;
begin
  SetVariable('DAK_DELPHI', '37');
  SetVariable('DAK_OUT', 'C:\reports\Unit1');
  SetVariable('DAK_PAL', 'false');
  SetVariable('DAK_CLEAN', 'false');
  SetVariable('DAK_WRITE_SUMMARY', 'false');
  SetVariable('PA_PATH', 'C:/pal//palcmd.exe');
  SetVariable('PA_ARGS', '/Q');
  SetVariable('DAK_PAL_EXCLUDE_SEARCH_FOLDERS', 'C:\vendor');
  SetVariable('DAK_PAL_EXCLUDE_FILES', 'Big.pas');
  SetVariable('DAK_FI_IGNORE_RULES', 'W501');
  SetVariable('DAK_IGNORE_WARNING_IDS', 'w501;W502');
  SetVariable('DAK_PAL_IGNORE_RULES', 'WARN54');
  // Not part of the unit contract:
  SetVariable('DAK_RSVARS', 'C:\bds\rsvars.bat');
  SetVariable('DAK_ENVOPTIONS', 'C:\bds\EnvOptions.proj');
  SetVariable('DAK_FI_FORMATS', 'xml');
  SetVariable('DAK_EXCLUDE_PATH_MASKS', '*\generated\*');
  SetVariable('FI_SETTINGS', 'C:\fi\settings.ficfg');

  for lOptions in [Parse('analyze-unit --unit C:\repo\Unit1.pas'), Parse('analyze --unit C:\repo\Unit1.pas')] do
  begin
    Assert.AreEqual(TCommandKind.ckAnalyzeUnit, lOptions.fCommand);
    Assert.AreEqual('37.0', lOptions.fDelphiVersion);
    Assert.AreEqual('C:\reports\Unit1', lOptions.fAnalyzeOutPath);
    Assert.IsFalse(lOptions.fAnalyzePal, 'DAK_PAL');
    Assert.IsFalse(lOptions.fAnalyzeClean, 'DAK_CLEAN');
    Assert.IsFalse(lOptions.fAnalyzeWriteSummary, 'DAK_WRITE_SUMMARY');
    Assert.AreEqual('C:\pal\palcmd.exe', lOptions.fPaPath);
    Assert.AreEqual('/Q', lOptions.fPaArgs);
    Assert.AreEqual('C:\vendor', lOptions.fPaExcludeSearchFolders);
    Assert.AreEqual('Big.pas', lOptions.fPaExcludeFiles);
    Assert.AreEqual('W501;W502', lOptions.fIgnoreWarningIds);
    Assert.AreEqual('WARN54', lOptions.fPalIgnoreRules);
    Assert.AreEqual('environment:DAK_PAL_IGNORE_RULES', lOptions.fPalIgnoreRulesOrigin);
    Assert.IsFalse(lOptions.fHasRsVarsPath, 'DAK_RSVARS is not forwarded for a unit');
    Assert.IsFalse(lOptions.fHasEnvOptionsPath, 'DAK_ENVOPTIONS is not forwarded for a unit');
    Assert.IsTrue(lOptions.fAnalyzeFiFormats = [TReportFormat.rfText], 'DAK_FI_FORMATS is not forwarded for a unit');
    Assert.IsFalse(lOptions.fHasExcludePathMasks, 'DAK_EXCLUDE_PATH_MASKS is not forwarded for a unit');
    Assert.IsFalse(lOptions.fHasFixSettings, 'FI_SETTINGS is not forwarded for a unit');
  end;
end;

// With a project context the wrapper always passed --platform and --config, defaulting to Win64 and
// Release rather than DAK's own Win32 default.
procedure TAnalyzeEnvironmentTests.UnitWithProjectContextDefaultsToWin64Release;
var
  lOptions: TAppOptions;
begin
  lOptions := Parse('analyze-unit --unit C:\repo\Unit1.pas --project-context C:\repo\Sample.dproj --delphi 23.0');
  Assert.AreEqual('Win64', lOptions.fPlatform);
  Assert.AreEqual('Release', lOptions.fConfig);

  SetVariable('DAK_PLATFORM', 'Win32');
  SetVariable('DAK_CONFIG', 'Debug');
  lOptions := Parse('analyze-unit --unit C:\repo\Unit1.pas --project-context C:\repo\Sample.dproj --delphi 23.0');
  Assert.AreEqual('Win32', lOptions.fPlatform);
  Assert.AreEqual('Debug', lOptions.fConfig);

  lOptions := Parse('analyze-unit --unit C:\repo\Unit1.pas --project-context C:\repo\Sample.dproj --delphi 23.0 ' +
    '--platform Win64 --config Release');
  Assert.AreEqual('Win64', lOptions.fPlatform, '--platform wins');
  Assert.AreEqual('Release', lOptions.fConfig, '--config wins');
end;

procedure TAnalyzeEnvironmentTests.StandaloneUnitIgnoresPlatformAndConfigVariables;
var
  lOptions: TAppOptions;
begin
  SetVariable('DAK_PLATFORM', 'Win64');
  SetVariable('DAK_CONFIG', 'Debug');
  lOptions := Parse('analyze-unit --unit C:\repo\Unit1.pas --delphi 23.0');
  Assert.AreEqual('Win32', lOptions.fPlatform, 'A standalone unit keeps DAK''s own default.');
  Assert.AreEqual('Release', lOptions.fConfig);
end;

procedure TAnalyzeEnvironmentTests.PalIgnoreRulesFromEnvironmentRecordTheirOrigin;
var
  lOptions: TAppOptions;
begin
  SetVariable('DAK_PAL_IGNORE_RULES', 'WARN54');
  lOptions := Parse(cProjectWithDelphi);
  Assert.AreEqual('environment:DAK_PAL_IGNORE_RULES', lOptions.fPalIgnoreRulesOrigin);
end;

// D3: summary.json's policy origins come from the settings sources. Without a wrapper nothing sets
// DAK_PAL_IGNORE_RULES_ORIGIN (Setup clears it), so the origin must travel on the options.
procedure TAnalyzeEnvironmentTests.SettingsRecordTheEnvironmentOriginWithoutTheProcessVariable;
var
  lIgnore: TPascalAnalyzerIgnoreDefaults;
  lOptions: TAppOptions;
begin
  SetVariable('DAK_PAL_IGNORE_RULES', 'WARN54');
  lOptions := Parse(cProjectWithDelphi);
  lIgnore := Default(TPascalAnalyzerIgnoreDefaults);
  ApplyPascalAnalyzerIgnoreOverride(lOptions, lIgnore);
  Assert.Contains(lIgnore.fSources, 'command_line');
  Assert.Contains(lIgnore.fSources, 'environment:DAK_PAL_IGNORE_RULES');
end;

// analyze.py passed these through _to_win_arg(Path(value)), which on Windows is str(PureWindowsPath):
// forward slashes become backslashes, repeated separators and "." segments collapse, a trailing
// separator is dropped and ".." is kept. The recorded analyzer executable depends on it. Found by
// Compare -Area Project on the pinned live scenario, whose PA_PATH uses forward slashes.
procedure TAnalyzeEnvironmentTests.PathVariablesAreNormalizedLikeTheWrapper;
var
  lOptions: TAppOptions;
begin
  SetVariable('PA_PATH', 'C:/Program Files/Peganza//Pascal Analyzer 9/./palcmd.exe');
  SetVariable('DAK_RSVARS', 'C:\bds\bin\\rsvars.bat');
  SetVariable('DAK_ENVOPTIONS', './settings/../EnvOptions.proj');
  SetVariable('FI_SETTINGS', '\\server\share\fi/settings.ficfg/');
  lOptions := Parse(cProjectWithDelphi);
  Assert.AreEqual('C:\Program Files\Peganza\Pascal Analyzer 9\palcmd.exe', lOptions.fPaPath);
  Assert.AreEqual('C:\bds\bin\rsvars.bat', lOptions.fRsVarsPath);
  Assert.AreEqual('settings\..\EnvOptions.proj', lOptions.fEnvOptionsPath);
  Assert.AreEqual('\\server\share\fi\settings.ficfg', lOptions.fFixSettings);
end;

end.
