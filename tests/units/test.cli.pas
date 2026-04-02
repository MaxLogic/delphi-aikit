unit Test.Cli;

interface

uses
  DUnitX.TestFramework,
  System.IniFiles,
  System.IOUtils,
  System.SysUtils,
  maxLogic.CmdLineParams,
  Dak.Cli, Dak.FixInsightSettings, Dak.Types,
  Test.Support;

type
  [TestFixture]
  TCliTests = class
  private
    function ToWslPath(const aWindowsPath: string): string;
  public
    procedure SetParams(const aCmdLine: string);
    [Test]
    procedure ResolveAcceptsUnixStyleProjectPath;
    [Test]
    procedure ResolveCommandAcceptsUnixStyleProjectPath;
    [Test]
    procedure ResolveCommandRejectsUnsupportedLinuxAbsoluteProjectPath;
    [Test]
    procedure ResolveCommandRejectsUnsupportedProjectExtension;
    [Test]
    procedure AnalyzeUnitCommandRejectsUnsupportedLinuxAbsolutePath;
    [Test]
    procedure AnalyzeProjectCommandRejectsUnsupportedProjectExtension;
    [Test]
    procedure AnalyzeUnitCommandRejectsProjectAndUnitConflict;
    [Test]
    procedure DfmCheckCommandParsesRequiredFlagsAndDefaults;
    [Test]
    procedure DfmCheckCommandRequiresDproj;
    [Test]
    procedure DfmCheckCommandParsesSelectedDfmFilterList;
    [Test]
    procedure DfmCheckCommandParsesAllFlag;
    [Test]
    procedure DfmInspectCommandParsesRequiredFlagsAndDefaults;
    [Test]
    procedure DfmInspectCommandRequiresDfm;
    [Test]
    procedure DfmInspectCommandParsesSummaryFormat;
    [Test]
    procedure BuildCommandParsesDfmCheckFlag;
    [Test]
    procedure BuildCommandParsesDfmSelectionFlags;
    [Test]
    procedure BuildCommandDefaultsDfmCheckToFalse;
    [Test]
    procedure BuildCommandRejectsDfmCheckValue;
    [Test]
    procedure BuildCommandParsesWebCoreBuilder;
    [Test]
    procedure BuildCommandAutoDetectsWebCoreProject;
    [Test]
    procedure BuildCommandParsesWebCorePwaFlags;
    [Test]
    procedure BuildCommandParsesWebCoreBuilderCompilerWithoutDelphi;
    [Test]
    procedure BuildCommandRejectsDfmCheckForWebCoreBuilder;
    [Test]
    procedure AnalyzeProjectSummarySkipsStaleTxtWhenTxtReportWasNotRun;
    [Test]
    procedure AnalyzeProjectDefaultOutRootUsesSiblingDakFolder;
    [Test]
    procedure AnalyzeProjectDefaultOutRootUsesSiblingDprojFolderWhenMainSourceLivesElsewhere;
    [Test]
    procedure AnalyzeUnitDefaultOutRootUsesDakConvention;
    [Test]
    procedure LoadSettingsWithoutRepoMarkerUsesOnlyProjectLocalDakIni;
    [Test]
    procedure LoadDefaultDelphiVersionUsesProjectLocalDakIni;
    [Test]
    procedure HelpCommandIgnoresSwitchValueTokens;
    [Test]
    procedure HelpCommandFindsExplicitCommandAfterSwitchValues;
    [Test]
    procedure HelpCommandRejectsUnknownExplicitToken;
    [Test]
    procedure HelpCommandRejectsTrailingUnknownTokenAfterExplicitCommand;
    [Test]
    procedure HelpCommandDoesNotTreatSwitchValueAsExplicitCommand;
    [Test]
    procedure HelpCommandDoesNotConsumeSwitchTokenAsRequiredValue;
    [Test]
    procedure HelpCommandIgnoresDfmInspectSwitchValueTokens;
    [Test]
    procedure DepsCommandParsesJsonDefaults;
    [Test]
    procedure DepsCommandParsesTopLimit;
    [Test]
    procedure ParseGlobalVarsDefaults;
    [Test]
    procedure ParseGlobalVarsOptions;
    [Test]
    procedure ParseGlobalVarsUnusedOnly;
    [Test]
    procedure ParseGlobalVarsFilters;
  end;

implementation

procedure TCliTests.SetParams(const aCmdLine: string);
var
  lParams: iCmdLineParams;
begin
  lParams := maxCmdLineParams;
  lParams.BuildFromString(aCmdLine);
end;

function TCliTests.ToWslPath(const aWindowsPath: string): string;
var
  lDrive: string;
  lRest: string;
  lPath: string;
begin
  lPath := Trim(aWindowsPath);
  if (Length(lPath) >= 3) and (lPath[2] = ':') and CharInSet(lPath[1], ['A'..'Z', 'a'..'z']) then
  begin
    lDrive := LowerCase(lPath[1]);
    lRest := Copy(lPath, 3, MaxInt);
    while lRest.StartsWith('\') or lRest.StartsWith('/') do
      lRest := Copy(lRest, 2, MaxInt);
    lRest := lRest.Replace('\', '/', [rfReplaceAll]);
    if lRest = '' then
      Exit('/mnt/' + lDrive);
    Exit('/mnt/' + lDrive + '/' + lRest);
  end;
  Result := lPath.Replace('\', '/', [rfReplaceAll]);
end;

procedure TCliTests.ResolveAcceptsUnixStyleProjectPath;
var
  lOptions: TAppOptions;
  lError: string;
  lProjectPath: string;
begin
  lProjectPath := '/mnt/f/projects/MaxLogic/DelphiAiKit/tests/fixtures/Sample.dproj';
  SetParams('resolve --project ' + lProjectPath + ' --delphi 23.0');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected --project to accept Unix-style path. Error: ' + lError);
  Assert.AreEqual(lProjectPath, lOptions.fDprojPath);
end;

procedure TCliTests.ResolveCommandAcceptsUnixStyleProjectPath;
var
  lExitCode: Cardinal;
  lArgs: string;
  lProjectPath: string;
  lOutPath: string;
  lRunLog: string;
begin
  EnsureResolverBuilt;
  lProjectPath := ToWslPath(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'));
  lOutPath := TPath.Combine(TempRoot, 'resolve-linux-path.ini');
  lRunLog := TPath.Combine(TempRoot, 'resolve-linux-path.log');
  lArgs := 'resolve --project ' + lProjectPath + ' --platform Win32 --config Debug --delphi 23.0 --format ini --out-file ' +
    QuoteArg(lOutPath);

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start resolver process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected Linux-style project path to resolve successfully. See: ' + lRunLog);
  Assert.IsTrue(FileExists(lOutPath), 'Expected resolve output file to be created: ' + lOutPath);
end;

procedure TCliTests.ResolveCommandRejectsUnsupportedLinuxAbsoluteProjectPath;
var
  lExitCode: Cardinal;
  lArgs: string;
  lOutPath: string;
  lRunLog: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lOutPath := TPath.Combine(TempRoot, 'resolve-linux-invalid.ini');
  lRunLog := TPath.Combine(TempRoot, 'resolve-linux-invalid.log');
  lArgs := 'resolve --project /home/not-supported/Sample.dproj --platform Win32 --config Debug --delphi 23.0 --format ini --out-file ' +
    QuoteArg(lOutPath);

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start resolver process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported Linux path to be rejected. See: ' + lRunLog);
  Assert.IsFalse(FileExists(lOutPath), 'Did not expect resolve output file when project path is invalid: ' + lOutPath);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := TFile.ReadAllText(lRunLog);
  Assert.IsTrue(Pos('Unsupported Linux path format', lLogText) > 0,
    'Expected unsupported Linux path error message. See: ' + lRunLog);
end;

procedure TCliTests.ResolveCommandRejectsUnsupportedProjectExtension;
var
  lExitCode: Cardinal;
  lArgs: string;
  lRunLog: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lRunLog := TPath.Combine(TempRoot, 'resolve-project-ext-invalid.log');
  lArgs := 'resolve --project ' + QuoteArg(TPath.Combine(RepoRoot, 'README.md')) + ' --delphi 23.0';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start resolver process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported project extension to be rejected. See: ' + lRunLog);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := TFile.ReadAllText(lRunLog);
  Assert.IsTrue(Pos('Unsupported project input', lLogText) > 0,
    'Expected unsupported project extension error message. See: ' + lRunLog);
end;

procedure TCliTests.AnalyzeUnitCommandRejectsUnsupportedLinuxAbsolutePath;
var
  lExitCode: Cardinal;
  lArgs: string;
  lRunLog: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lRunLog := TPath.Combine(TempRoot, 'analyze-unit-linux-invalid.log');
  lArgs := 'analyze --unit /home/not-supported/Sample.pas --delphi 23.0 --pascal-analyzer false';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported Linux unit path to be rejected. See: ' + lRunLog);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := TFile.ReadAllText(lRunLog);
  Assert.IsTrue(Pos('Unsupported Linux path format', lLogText) > 0,
    'Expected unsupported Linux path error message. See: ' + lRunLog);
end;

procedure TCliTests.AnalyzeProjectCommandRejectsUnsupportedProjectExtension;
var
  lExitCode: Cardinal;
  lArgs: string;
  lRunLog: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lRunLog := TPath.Combine(TempRoot, 'analyze-project-ext-invalid.log');
  lArgs := 'analyze --project ' + QuoteArg(TPath.Combine(RepoRoot, 'README.md')) +
    ' --delphi 23.0 --fixinsight false --pascal-analyzer false';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported project extension to be rejected. See: ' + lRunLog);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := TFile.ReadAllText(lRunLog);
  Assert.IsTrue(Pos('Unsupported project input', lLogText) > 0,
    'Expected unsupported project extension error message. See: ' + lRunLog);
end;

procedure TCliTests.AnalyzeUnitCommandRejectsProjectAndUnitConflict;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('analyze-unit --project C:\repo\Sample.dproj --unit C:\repo\Unit1.pas --delphi 23.0');
  Assert.IsFalse(TryParseOptions(lOptions, lError),
    'Expected analyze-unit to reject simultaneous --project and --unit.');
  Assert.IsTrue(Pos('Use either --project or --unit', lError) > 0,
    'Expected conflict error message. Actual: ' + lError);
end;

procedure TCliTests.DfmCheckCommandParsesRequiredFlagsAndDefaults;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('dfm-check --dproj C:\repo\Sample.dproj');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected dfm-check args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckDfmCheck, lOptions.fCommand, 'Expected dfm-check command kind.');
  Assert.AreEqual('C:\repo\Sample.dproj', lOptions.fDprojPath, 'Unexpected --dproj parsing result.');
  Assert.AreEqual('Release', lOptions.fConfig, 'Expected default config for dfm-check command.');
  Assert.AreEqual('Win32', lOptions.fPlatform, 'Expected default platform for dfm-check command.');
end;

procedure TCliTests.DfmCheckCommandRequiresDproj;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('dfm-check --platform Win32');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected dfm-check parsing to fail without --dproj.');
  Assert.IsTrue(Pos('Missing value for parameter: --dproj', lError) > 0,
    'Expected missing --dproj error. Actual: ' + lError);
end;

procedure TCliTests.DfmCheckCommandParsesSelectedDfmFilterList;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('dfm-check --dproj C:\repo\Sample.dproj --dfm MainForm.dfm,Frames\DetailSubEditDocs.dfm');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected dfm-check --dfm list to parse. Error: ' + lError);
  Assert.AreEqual('MainForm.dfm,Frames\DetailSubEditDocs.dfm', lOptions.fDfmCheckFilter,
    'Unexpected parsed --dfm filter list.');
  Assert.IsFalse(lOptions.fDfmCheckAll, 'Expected --dfm list to disable explicit all mode.');
end;

procedure TCliTests.DfmCheckCommandParsesAllFlag;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('dfm-check --dproj C:\repo\Sample.dproj --all');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected dfm-check --all to parse. Error: ' + lError);
  Assert.IsTrue(lOptions.fDfmCheckAll, 'Expected --all to enable full DFM validation scope.');
  Assert.AreEqual('', lOptions.fDfmCheckFilter, 'Expected --all to clear explicit --dfm filter list.');
end;

procedure TCliTests.DfmInspectCommandParsesRequiredFlagsAndDefaults;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('dfm-inspect --dfm C:\repo\MainForm.dfm');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected dfm-inspect args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckDfmInspect, lOptions.fCommand, 'Expected dfm-inspect command kind.');
  Assert.AreEqual('C:\repo\MainForm.dfm', lOptions.fDfmInspectPath, 'Unexpected --dfm parsing result.');
  Assert.AreEqual('tree', lOptions.fDfmInspectFormat, 'Expected tree as the default dfm-inspect format.');
end;

procedure TCliTests.DfmInspectCommandRequiresDfm;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('dfm-inspect --format summary');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected dfm-inspect parsing to fail without --dfm.');
  Assert.IsTrue(Pos('Missing value for parameter: --dfm', lError) > 0,
    'Expected missing --dfm error. Actual: ' + lError);
end;

procedure TCliTests.DfmInspectCommandParsesSummaryFormat;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('dfm-inspect --dfm C:\repo\MainForm.dfm --format summary');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected dfm-inspect summary args to parse. Error: ' + lError);
  Assert.AreEqual('summary', lOptions.fDfmInspectFormat, 'Unexpected parsed dfm-inspect format.');
end;

procedure TCliTests.BuildCommandParsesDfmCheckFlag;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --delphi 23.0 --dfmcheck');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected build --dfmcheck to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckBuild, lOptions.fCommand, 'Expected build command kind.');
  Assert.IsTrue(lOptions.fBuildRunDfmCheck, 'Expected --dfmcheck to enable post-build DFM validation.');
end;

procedure TCliTests.BuildCommandParsesDfmSelectionFlags;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --delphi 23.0 --dfmcheck --dfm MainForm.dfm');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected build --dfm list to parse. Error: ' + lError);
  Assert.AreEqual('MainForm.dfm', lOptions.fDfmCheckFilter, 'Unexpected parsed build --dfm value.');
  Assert.IsFalse(lOptions.fDfmCheckAll, 'Expected build --dfm to disable explicit all mode.');

  SetParams('build --project C:\repo\Sample.dproj --delphi 23.0 --dfmcheck --all');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected build --all to parse. Error: ' + lError);
  Assert.IsTrue(lOptions.fDfmCheckAll, 'Expected build --all to enable full DFM scope.');
  Assert.AreEqual('', lOptions.fDfmCheckFilter, 'Expected build --all to clear explicit --dfm filter list.');
end;

procedure TCliTests.BuildCommandDefaultsDfmCheckToFalse;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --delphi 23.0');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected build args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckBuild, lOptions.fCommand, 'Expected build command kind.');
  Assert.IsFalse(lOptions.fBuildRunDfmCheck, 'Expected build to skip DFM validation by default.');
end;

procedure TCliTests.BuildCommandRejectsDfmCheckValue;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --delphi 23.0 --dfmcheck=false');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected --dfmcheck value syntax to be rejected.');
  Assert.IsTrue(Pos('Unknown argument: --dfmcheck=false', lError) > 0,
    'Expected unknown-argument error for valued --dfmcheck. Actual: ' + lError);
end;

procedure TCliTests.BuildCommandParsesWebCoreBuilder;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --builder webcore --webcore-compiler C:\tools\TMSWebCompiler.exe');
  Assert.IsTrue(TryParseOptions(lOptions, lError),
    'Expected explicit WebCore build args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckBuild, lOptions.fCommand, 'Expected build command kind.');
  Assert.AreEqual(Integer(TBuildBackend.bbWebCore), Integer(lOptions.fBuildBackend),
    'Expected --builder webcore to select the WebCore backend.');
  Assert.IsTrue(lOptions.fHasWebCoreCompilerPath, 'Expected --webcore-compiler to be tracked as explicit input.');
  Assert.AreEqual('C:\tools\TMSWebCompiler.exe', lOptions.fWebCoreCompilerPath,
    'Unexpected parsed WebCore compiler path.');
end;

procedure TCliTests.BuildCommandAutoDetectsWebCoreProject;
var
  lDprojPath: string;
  lFixtureRoot: string;
  lOptions: TAppOptions;
  lError: string;
begin
  EnsureTempClean;
  lFixtureRoot := TPath.Combine(TempRoot, 'cli-webcore-auto-detect');
  ForceDirectories(lFixtureRoot);
  lDprojPath := TPath.Combine(lFixtureRoot, 'WebCoreAuto.dproj');
  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>WebCoreAuto.dpr</MainSource>' + sLineBreak +
    '    <TMSWebProject>2</TMSWebProject>' + sLineBreak +
    '    <TMSWebHTMLFile>index.html</TMSWebHTMLFile>' + sLineBreak +
    '    <DCC_UsePackage>TMSWEBCorePkgDXE15;$(DCC_UsePackage)</DCC_UsePackage>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak,
    TEncoding.UTF8);

  SetParams('build --project ' + QuoteArg(lDprojPath) + ' --config Debug --webcore-compiler C:\tools\TMSWebCompiler.exe');
  Assert.IsTrue(TryParseOptions(lOptions, lError),
    'Expected WebCore auto-detect build args to parse without --delphi. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckBuild, lOptions.fCommand, 'Expected build command kind.');
end;

procedure TCliTests.BuildCommandParsesWebCorePwaFlags;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --builder webcore --pwa');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected --pwa to parse. Error: ' + lError);
  Assert.IsTrue(lOptions.fHasWebCorePwaEnabled, 'Expected --pwa to be tracked as explicit input.');
  Assert.IsTrue(lOptions.fWebCorePwaEnabled, 'Expected --pwa to enable PWA mode.');

  SetParams('build --project C:\repo\Sample.dproj --builder webcore --no-pwa');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected --no-pwa to parse. Error: ' + lError);
  Assert.IsTrue(lOptions.fHasWebCorePwaEnabled, 'Expected --no-pwa to be tracked as explicit input.');
  Assert.IsFalse(lOptions.fWebCorePwaEnabled, 'Expected --no-pwa to disable PWA mode.');
end;

procedure TCliTests.BuildCommandParsesWebCoreBuilderCompilerWithoutDelphi;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --builder webcore --webcore-compiler C:\tools\TMSWebCompiler.exe');
  Assert.IsTrue(TryParseOptions(lOptions, lError),
    'Expected explicit WebCore build args to parse without --delphi. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckBuild, lOptions.fCommand, 'Expected build command kind.');
  Assert.AreEqual(Integer(TBuildBackend.bbWebCore), Integer(lOptions.fBuildBackend),
    'Expected --builder webcore to select the WebCore backend.');
  Assert.IsTrue(lOptions.fHasWebCoreCompilerPath, 'Expected --webcore-compiler to be tracked as explicit input.');
  Assert.AreEqual('C:\tools\TMSWebCompiler.exe', lOptions.fWebCoreCompilerPath,
    'Unexpected parsed WebCore compiler path.');
end;

procedure TCliTests.BuildCommandRejectsDfmCheckForWebCoreBuilder;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --builder webcore --webcore-compiler C:\tools\TMSWebCompiler.exe --dfmcheck');
  Assert.IsFalse(TryParseOptions(lOptions, lError),
    'Expected WebCore builds to reject --dfmcheck.');
  Assert.IsTrue(Pos('--dfmcheck', lError) > 0,
    'Expected WebCore incompatibility error to mention --dfmcheck. Actual: ' + lError);
end;

procedure TCliTests.AnalyzeProjectSummarySkipsStaleTxtWhenTxtReportWasNotRun;
var
  lExitCode: Cardinal;
  lArgs: string;
  lOutRoot: string;
  lFixDir: string;
  lTxtPath: string;
  lSummaryPath: string;
  lRunLog: string;
  lSummaryText: string;
begin
  EnsureResolverBuilt;

  lOutRoot := TPath.Combine(TempRoot, 'analyze-stale-summary');
  lFixDir := TPath.Combine(lOutRoot, 'fixinsight');
  TDirectory.CreateDirectory(lFixDir);
  lTxtPath := TPath.Combine(lFixDir, 'fixinsight.txt');
  TFile.WriteAllLines(lTxtPath, ['W501 stale finding should not be counted'], TEncoding.UTF8);

  lRunLog := TPath.Combine(TempRoot, 'analyze-stale-summary.log');
  lArgs := 'analyze --project ' + QuoteArg(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj')) +
    ' --platform Win32 --config Debug --delphi 23.0 --fixinsight false --pascal-analyzer false --clean false --out ' +
    QuoteArg(lOutRoot);

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected analyze run to succeed. See: ' + lRunLog);

  lSummaryPath := TPath.Combine(lOutRoot, 'summary.md');
  Assert.IsTrue(FileExists(lSummaryPath), 'Expected summary file to be generated: ' + lSummaryPath);
  lSummaryText := TFile.ReadAllText(lSummaryPath);

  Assert.IsTrue(Pos('- Findings (by code): (TXT not generated)', lSummaryText) > 0,
    'Expected summary to ignore stale TXT findings when TXT report was not run. Summary: ' + lSummaryPath);
  Assert.IsFalse(Pos('- Top codes:', lSummaryText) > 0,
    'Expected summary to skip top code output when TXT report was not run. Summary: ' + lSummaryPath);
end;

procedure TCliTests.AnalyzeProjectDefaultOutRootUsesSiblingDakFolder;
var
  lArgs: string;
  lDakRoot: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lLegacyRoot: string;
  lRunLog: string;
  lSummaryPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  lDakRoot := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(lDprojPath), '.dak'), 'Sample');
  lLegacyRoot := TPath.Combine(RepoRoot, '_analysis\Sample');
  if TDirectory.Exists(lDakRoot) then
    TDirectory.Delete(lDakRoot, True);
  if TDirectory.Exists(lLegacyRoot) then
    TDirectory.Delete(lLegacyRoot, True);

  lRunLog := TPath.Combine(TempRoot, 'analyze-default-out-project.log');
  lArgs := 'analyze --project ' + QuoteArg(lDprojPath) +
    ' --platform Win32 --config Debug --delphi 23.0 --fixinsight false --pascal-analyzer false';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected analyze run to succeed. See: ' + lRunLog);

  lSummaryPath := TPath.Combine(lDakRoot, 'summary.md');
  Assert.IsTrue(FileExists(lSummaryPath), 'Expected default analyze output under sibling .dak root: ' + lSummaryPath);
  Assert.IsFalse(TDirectory.Exists(lLegacyRoot), 'Did not expect legacy _analysis output root: ' + lLegacyRoot);
end;

procedure TCliTests.AnalyzeProjectDefaultOutRootUsesSiblingDprojFolderWhenMainSourceLivesElsewhere;
var
  lArgs: string;
  lDakRoot: string;
  lDprPath: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lProjectDir: string;
  lRunLog: string;
  lSplitRoot: string;
  lSrcDir: string;
  lSummaryPath: string;
begin
  EnsureResolverBuilt;

  lSplitRoot := TPath.Combine(TempRoot, 'analyze-split-layout');
  if TDirectory.Exists(lSplitRoot) then
    TDirectory.Delete(lSplitRoot, True);
  lProjectDir := TPath.Combine(lSplitRoot, 'project');
  lSrcDir := TPath.Combine(lProjectDir, 'src');
  TDirectory.CreateDirectory(lSrcDir);

  lDprojPath := TPath.Combine(lProjectDir, 'SplitLayout.dproj');
  lDprPath := TPath.Combine(lSrcDir, 'SplitLayout.dpr');
  TFile.WriteAllText(lDprPath, 'program SplitLayout;' + sLineBreak + 'begin' + sLineBreak + 'end.');
  TFile.WriteAllText(TPath.Combine(lProjectDir, 'SplitLayout.optset'),
    TFile.ReadAllText(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.optset')));
  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>src\SplitLayout.dpr</MainSource>' + sLineBreak +
    '    <CfgDependentOn>SplitLayout.optset</CfgDependentOn>' + sLineBreak +
    '    <DCC_Define>BASE;$(DCC_Define)</DCC_Define>' + sLineBreak +
    '    <DCC_UnitSearchPath>.\src;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + sLineBreak +
    '    <DCC_Namespace>System;Vcl;$(DCC_Namespace)</DCC_Namespace>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);

  lDakRoot := TPath.Combine(TPath.Combine(lProjectDir, '.dak'), 'SplitLayout');
  lRunLog := TPath.Combine(TempRoot, 'analyze-split-layout.log');
  lArgs := 'analyze --project ' + QuoteArg(lDprojPath) +
    ' --platform Win32 --config Debug --delphi 23.0 --fixinsight false --pascal-analyzer false';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected split-layout analyze run to succeed. See: ' + lRunLog);

  lSummaryPath := TPath.Combine(lDakRoot, 'summary.md');
  Assert.IsTrue(FileExists(lSummaryPath),
    'Expected default analyze output next to the .dproj even when MainSource lives elsewhere: ' + lSummaryPath);
end;

procedure TCliTests.AnalyzeUnitDefaultOutRootUsesDakConvention;
var
  lArgs: string;
  lDakRoot: string;
  lExitCode: Cardinal;
  lLegacyRoot: string;
  lRunLog: string;
  lSummaryPath: string;
  lUnitPath: string;
  lUnitName: string;
begin
  EnsureResolverBuilt;

  lUnitPath := TPath.Combine(RepoRoot, 'tests\fixtures\GlobalVarsFixture.Globals.pas');
  lUnitName := TPath.GetFileNameWithoutExtension(lUnitPath);
  lDakRoot := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(lUnitPath), '.dak'), TPath.Combine('_unit', lUnitName));
  lLegacyRoot := TPath.Combine(RepoRoot, TPath.Combine('_analysis\_unit', lUnitName));
  if TDirectory.Exists(lDakRoot) then
    TDirectory.Delete(lDakRoot, True);
  if TDirectory.Exists(lLegacyRoot) then
    TDirectory.Delete(lLegacyRoot, True);

  lRunLog := TPath.Combine(TempRoot, 'analyze-default-out-unit.log');
  lArgs := 'analyze --unit ' + QuoteArg(lUnitPath) + ' --delphi 23.0 --pascal-analyzer false';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyze-unit process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected analyze-unit run to succeed. See: ' + lRunLog);

  lSummaryPath := TPath.Combine(lDakRoot, 'summary.md');
  Assert.IsTrue(FileExists(lSummaryPath), 'Expected default analyze-unit output under sibling .dak root: ' + lSummaryPath);
  Assert.IsFalse(TDirectory.Exists(lLegacyRoot), 'Did not expect legacy _analysis unit root: ' + lLegacyRoot);
end;

procedure TCliTests.LoadSettingsWithoutRepoMarkerUsesOnlyProjectLocalDakIni;
var
  lBaseDir: string;
  lDprojPath: string;
  lFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  lFixOptions: TFixInsightExtraOptions;
  lGuid: TGUID;
  lParentDir: string;
  lParentIniPath: string;
  lPascalAnalyzer: TPascalAnalyzerDefaults;
  lProjectDir: string;
  lProjectIniPath: string;
  lReportFilter: TReportFilterDefaults;

  procedure WriteWarningsIni(const aPath: string; const aWarnings: string);
  var
    lIni: TIniFile;
  begin
    lIni := TIniFile.Create(aPath);
    try
      lIni.WriteString('FixInsightIgnore', 'Warnings', aWarnings);
    finally
      lIni.Free;
    end;
  end;
begin
  Assert.AreEqual(0, CreateGUID(lGuid), 'Failed to create a temporary GUID.');
  lBaseDir := TPath.Combine(TPath.GetTempPath, 'dak-settings-norepo-' + GUIDToString(lGuid));
  lParentDir := TPath.Combine(lBaseDir, 'parent');
  lProjectDir := TPath.Combine(lParentDir, 'project');
  TDirectory.CreateDirectory(lProjectDir);

  lDprojPath := TPath.Combine(lProjectDir, 'Sample.dproj');
  TFile.WriteAllText(lDprojPath, '<Project/>', TEncoding.UTF8);

  lParentIniPath := TPath.Combine(lParentDir, 'dak.ini');
  WriteWarningsIni(lParentIniPath, 'W777');

  lProjectIniPath := TPath.Combine(lProjectDir, 'dak.ini');
  WriteWarningsIni(lProjectIniPath, 'W888');

  try
    Assert.IsTrue(LoadSettings(nil, lDprojPath, lFixOptions, lFixIgnoreDefaults, lReportFilter, lPascalAnalyzer),
      'Expected settings loader to succeed.');
    Assert.IsTrue(Pos('W888', lFixIgnoreDefaults.fWarnings) > 0,
      'Expected project-local dak.ini warnings to be loaded.');
    Assert.IsFalse(Pos('W777', lFixIgnoreDefaults.fWarnings) > 0,
      'Did not expect parent dak.ini warnings without a repo marker.');
  finally
    if TDirectory.Exists(lBaseDir) then
      TDirectory.Delete(lBaseDir, True);
  end;
end;

procedure TCliTests.LoadDefaultDelphiVersionUsesProjectLocalDakIni;
var
  lBaseDir: string;
  lDefaultDelphiVersion: string;
  lDprojPath: string;
  lGuid: TGUID;
  lParentDir: string;
  lParentIniPath: string;
  lProjectDir: string;
  lProjectIniPath: string;

  procedure WriteDelphiVersionIni(const aPath: string; const aDelphiVersion: string);
  var
    lIni: TIniFile;
  begin
    lIni := TIniFile.Create(aPath);
    try
      lIni.WriteString('Build', 'DelphiVersion', aDelphiVersion);
    finally
      lIni.Free;
    end;
  end;
begin
  Assert.AreEqual(0, CreateGUID(lGuid), 'Failed to create a temporary GUID.');
  lBaseDir := TPath.Combine(TPath.GetTempPath, 'dak-settings-delphi-' + GUIDToString(lGuid));
  lParentDir := TPath.Combine(lBaseDir, 'parent');
  lProjectDir := TPath.Combine(lParentDir, 'project');
  TDirectory.CreateDirectory(lProjectDir);

  lDprojPath := TPath.Combine(lProjectDir, 'Sample.dproj');
  TFile.WriteAllText(lDprojPath, '<Project/>', TEncoding.UTF8);

  lParentIniPath := TPath.Combine(lParentDir, 'dak.ini');
  WriteDelphiVersionIni(lParentIniPath, '22.0');

  lProjectIniPath := TPath.Combine(lProjectDir, 'dak.ini');
  WriteDelphiVersionIni(lProjectIniPath, '23.0');

  try
    Assert.IsTrue(LoadDefaultDelphiVersion(lDprojPath, lDefaultDelphiVersion),
      'Expected Delphi version settings loader to succeed.');
    Assert.AreEqual('23.0', lDefaultDelphiVersion,
      'Expected project-local DelphiVersion to be used without repo marker traversal.');
  finally
    if TDirectory.Exists(lBaseDir) then
      TDirectory.Delete(lBaseDir, True);
  end;
end;

procedure TCliTests.HelpCommandIgnoresSwitchValueTokens;
var
  lCommand: TCommandKind;
  lHasCommand: Boolean;
  lError: string;
begin
  SetParams('--help --project "C:\repo\Sample.dproj"');
  Assert.IsTrue(TryGetCommand(lCommand, lHasCommand, lError),
    'Expected help command detection to ignore switch values. Error: ' + lError);
  Assert.IsFalse(lHasCommand, 'Expected no explicit command when only switches and values are provided.');
  Assert.AreEqual('', lError, 'Expected empty error for global help command detection.');
end;

procedure TCliTests.HelpCommandFindsExplicitCommandAfterSwitchValues;
var
  lCommand: TCommandKind;
  lHasCommand: Boolean;
  lError: string;
begin
  SetParams('--help --project "C:\repo\Sample.dproj" analyze');
  Assert.IsTrue(TryGetCommand(lCommand, lHasCommand, lError),
    'Expected help command detection to find explicit analyze command. Error: ' + lError);
  Assert.IsTrue(lHasCommand, 'Expected explicit command detection when analyze token is present.');
  Assert.AreEqual(TCommandKind.ckAnalyzeProject, lCommand, 'Expected analyze command kind.');
end;

procedure TCliTests.HelpCommandRejectsUnknownExplicitToken;
var
  lCommand: TCommandKind;
  lHasCommand: Boolean;
  lError: string;
begin
  SetParams('foo --help');
  Assert.IsFalse(TryGetCommand(lCommand, lHasCommand, lError),
    'Expected unknown explicit token to be rejected even when --help is present.');
  Assert.IsTrue(Pos('Unknown command: foo', lError) > 0,
    'Expected unknown command error message. Actual: ' + lError);
end;

procedure TCliTests.HelpCommandRejectsTrailingUnknownTokenAfterExplicitCommand;
var
  lCommand: TCommandKind;
  lHasCommand: Boolean;
  lError: string;
begin
  SetParams('--help analyze foo');
  Assert.IsFalse(TryGetCommand(lCommand, lHasCommand, lError),
    'Expected trailing unknown token to be rejected in help command mode.');
  Assert.IsTrue(Pos('Unknown command: foo', lError) > 0,
    'Expected unknown command error message for trailing token. Actual: ' + lError);
end;

procedure TCliTests.HelpCommandDoesNotTreatSwitchValueAsExplicitCommand;
var
  lCommand: TCommandKind;
  lHasCommand: Boolean;
  lError: string;
begin
  SetParams('--help --project analyze');
  Assert.IsTrue(TryGetCommand(lCommand, lHasCommand, lError),
    'Expected help command detection to ignore switch-consumed value tokens. Error: ' + lError);
  Assert.IsFalse(lHasCommand, 'Expected no explicit command when command-like token is consumed by --project.');
  Assert.AreEqual('', lError, 'Expected empty error for help command detection.');
end;

procedure TCliTests.HelpCommandDoesNotConsumeSwitchTokenAsRequiredValue;
var
  lCommand: TCommandKind;
  lHasCommand: Boolean;
  lError: string;
begin
  SetParams('--help --project --delphi 23.0 analyze');
  Assert.IsTrue(TryGetCommand(lCommand, lHasCommand, lError),
    'Expected help command detection to treat --delphi as a switch, not as --project value. Error: ' + lError);
  Assert.IsTrue(lHasCommand, 'Expected explicit command detection when analyze token is present.');
  Assert.AreEqual(TCommandKind.ckAnalyzeProject, lCommand, 'Expected analyze command kind.');
  Assert.AreEqual('', lError, 'Expected empty error for help command detection.');
end;

procedure TCliTests.HelpCommandIgnoresDfmInspectSwitchValueTokens;
var
  lCommand: TCommandKind;
  lHasCommand: Boolean;
  lError: string;
begin
  SetParams('dfm-inspect --dfm tests\fixtures\MainForm.dfm --help');
  Assert.IsTrue(TryGetCommand(lCommand, lHasCommand, lError),
    'Expected help command detection to ignore --dfm values. Error: ' + lError);
  Assert.IsTrue(lHasCommand, 'Expected explicit dfm-inspect command detection.');
  Assert.AreEqual(TCommandKind.ckDfmInspect, lCommand, 'Expected dfm-inspect command kind.');
  Assert.AreEqual('', lError, 'Expected empty error for dfm-inspect help command detection.');
end;

procedure TCliTests.DepsCommandParsesJsonDefaults;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('deps --project c:\temp\sample.dproj');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected deps defaults to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckDeps, lOptions.fCommand);
  Assert.AreEqual(TDepsFormat.dfJson, lOptions.fDepsFormat);
  Assert.IsFalse(lOptions.fHasDepsOutputPath);
  Assert.IsFalse(lOptions.fHasDepsUnitName);
end;

procedure TCliTests.DepsCommandParsesTopLimit;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('deps --project c:\temp\sample.dproj');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected deps defaults to parse. Error: ' + lError);
  Assert.AreEqual(20, lOptions.fDepsTopLimit, 'Expected deps --top default to stay bounded.');

  SetParams('deps --project c:\temp\sample.dproj --top 7');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected deps --top=7 to parse. Error: ' + lError);
  Assert.AreEqual(7, lOptions.fDepsTopLimit, 'Expected explicit --top value to be captured.');

  SetParams('deps --project c:\temp\sample.dproj --top 0');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected deps --top=0 to parse. Error: ' + lError);
  Assert.AreEqual(0, lOptions.fDepsTopLimit, 'Expected --top=0 to mean unlimited.');
end;

procedure TCliTests.ParseGlobalVarsDefaults;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('global-vars --project c:\temp\sample.dproj');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected global-vars defaults to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckGlobalVars, lOptions.fCommand);
  Assert.AreEqual(TGlobalVarsFormat.gvfText, lOptions.fGlobalVarsFormat);
  Assert.IsFalse(lOptions.fHasGlobalVarsOutputPath);
  Assert.AreEqual(TGlobalVarsRefresh.gvrAuto, lOptions.fGlobalVarsRefresh);
  Assert.IsFalse(lOptions.fGlobalVarsUnusedOnly);
end;

procedure TCliTests.ParseGlobalVarsOptions;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('global-vars --project c:\temp\sample.dproj --format json --output out.json --cache cache.db --refresh force');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected global-vars options to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckGlobalVars, lOptions.fCommand);
  Assert.AreEqual(TGlobalVarsFormat.gvfJson, lOptions.fGlobalVarsFormat);
  Assert.IsTrue(lOptions.fHasGlobalVarsOutputPath);
  Assert.AreEqual('out.json', lOptions.fGlobalVarsOutputPath);
  Assert.IsTrue(lOptions.fHasGlobalVarsCachePath);
  Assert.AreEqual('cache.db', lOptions.fGlobalVarsCachePath);
  Assert.AreEqual(TGlobalVarsRefresh.gvrForce, lOptions.fGlobalVarsRefresh);
end;

procedure TCliTests.ParseGlobalVarsUnusedOnly;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('global-vars --project c:\temp\sample.dproj --unused-only');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected --unused-only to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckGlobalVars, lOptions.fCommand);
  Assert.IsTrue(lOptions.fGlobalVarsUnusedOnly);
end;

procedure TCliTests.ParseGlobalVarsFilters;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('global-vars --project c:\temp\sample.dproj --unit foo* --name bar --reads-only');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected filters to parse. Error: ' + lError);
  Assert.IsTrue(lOptions.fHasGlobalVarsUnitFilter);
  Assert.AreEqual('foo*', lOptions.fGlobalVarsUnitFilter);
  Assert.IsTrue(lOptions.fHasGlobalVarsNameFilter);
  Assert.AreEqual('bar', lOptions.fGlobalVarsNameFilter);
  Assert.IsTrue(lOptions.fGlobalVarsReadsOnly);
  Assert.IsFalse(lOptions.fGlobalVarsWritesOnly);
end;

initialization
  TDUnitX.RegisterTestFixture(TCliTests);

end.
