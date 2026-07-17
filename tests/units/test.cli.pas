unit Test.Cli;

interface

uses
  System.Generics.Collections,
  System.IniFiles,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  maxLogic.CmdLineParams,
  Dak.Cli, Dak.CommandOutput, Dak.Messages, Dak.Settings, Dak.Types,
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
    procedure ResolveCommandRejectsFixInsightTimeout;
    [Test]
    procedure AnalyzeUnitCommandRejectsUnsupportedLinuxAbsolutePath;
    [Test]
    procedure AnalyzeProjectCommandRejectsUnsupportedProjectExtension;
    [Test]
    procedure AnalyzeUnitCommandRejectsProjectAndUnitConflict;
    [Test]
    procedure AnalyzeUnitParsesProjectContext;
    [Test]
    procedure AnalyzeProjectRejectsProjectContext;
    [Test]
    procedure AnalyzeHelpIncludesProjectContext;
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
    procedure BuildCommandParsesCompilerOverlays;
    [Test]
    procedure BuildCommandRejectsCompilerOverlaysForWebCore;
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
    procedure AnalyzeChildToolLogsAreIsolatedFromRunLog;
    [Test]
    procedure AnalyzeCommandParsesAnalyzerTimeouts;
    [Test]
    procedure AnalyzeCommandRejectsInvalidAnalyzerTimeout;
    [Test]
    procedure LoadSettingsWithoutRepoMarkerUsesOnlyProjectLocalDakIni;
    [Test]
    procedure LoadSettingsReadsAnalyzerTimeouts;
    [Test]
    procedure DakIniLoadingIsCentralized;
    [Test]
    procedure LoadDakSettingsMergesTypedSections;
    [Test]
    procedure CommandOutputWritingIsCentralized;
    [Test]
    procedure CommandOutputContinuesFileWriteWhenStdoutPipeCloses;
    [Test]
    procedure LoadDefaultDelphiVersionUsesProjectLocalDakIni;
    [Test]
    procedure CommandMetadataHasSingleTokenRegistry;
    [Test]
    procedure CommandMetadataParsesAdvertisedTokens;
    [Test]
    procedure CommandMetadataCoversAllCommandKinds;
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
    procedure RemoveWithCommandParsesScanUnitTarget;
    [Test]
    procedure RemoveWithCommandParsesPlanDirTarget;
    [Test]
    procedure RemoveWithCommandParsesApplyAllTarget;
    [Test]
    procedure RemoveWithCommandParsesDiagnosticsFlag;
    [Test]
    procedure RemoveWithCommandRejectsMissingTarget;
    [Test]
    procedure RemoveWithCommandRejectsMultipleTargets;
    [Test]
    procedure RemoveWithCommandRejectsInvalidMode;
    [Test]
    procedure RemoveWithCommandRejectsInvalidFormat;
    [Test]
    procedure RemoveWithHelpDocumentsModesAndTargets;
    [Test]
    procedure RefactorSlashSwitchesDoNotBecomeBoolValues;
    [Test]
    procedure SemanticCacheSwitchesSupportOptOutAndRejectConflict;
    [Test]
    procedure DeadCodeProfileParsingUsesDakAdapter;
    [Test]
    procedure RefactorCommandsRejectPartialPositionTargetsPrecisely;
    [Test]
    procedure LspCommandParsesOperationsAndRequiredArgs;
    [Test]
    procedure LspCommandParsesProjectAndOperationFields;
    [Test]
    procedure LspProbeCommandParsesModesAndShowInitOptions;
    [Test]
    procedure LspCommandRejectsMissingOperationArguments;
    [Test]
    procedure LspHelpListsSupportedOperationsOnly;
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start resolver process.');
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start resolver process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported Linux path to be rejected. See: ' + lRunLog);
  Assert.IsFalse(FileExists(lOutPath), 'Did not expect resolve output file when project path is invalid: ' + lOutPath);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := ReadUtf8TextFile(lRunLog);
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start resolver process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported project extension to be rejected. See: ' + lRunLog);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := ReadUtf8TextFile(lRunLog);
  Assert.IsTrue(Pos('Unsupported project input', lLogText) > 0,
    'Expected unsupported project extension error message. See: ' + lRunLog);
end;

procedure TCliTests.ResolveCommandRejectsFixInsightTimeout;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('resolve --project C:\repo\Sample.dproj --delphi 23.0 --fi-timeout-sec 17');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected resolve to reject analyzer execution timeout.');
  Assert.IsTrue(Pos('Unknown argument', lError) > 0, 'Expected unknown argument error. Actual: ' + lError);
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported Linux unit path to be rejected. See: ' + lRunLog);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := ReadUtf8TextFile(lRunLog);
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported project extension to be rejected. See: ' + lRunLog);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := ReadUtf8TextFile(lRunLog);
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

procedure TCliTests.AnalyzeUnitParsesProjectContext;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('analyze --unit C:\repo\Unit1.pas --project-context C:\repo\Sample.dproj --delphi 23.0 ' +
    '--platform Win64 --config Debug');

  Assert.IsTrue(TryParseOptions(lOptions, lError), lError);
  Assert.AreEqual(TCommandKind.ckAnalyzeUnit, lOptions.fCommand);
  Assert.AreEqual('C:\repo\Sample.dproj', lOptions.fProjectContextPath);
  Assert.IsTrue(lOptions.fHasProjectContextPath);
end;

procedure TCliTests.AnalyzeProjectRejectsProjectContext;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('analyze --project C:\repo\Sample.dproj --project-context C:\repo\Other.dproj --delphi 23.0');

  Assert.IsFalse(TryParseOptions(lOptions, lError));
  Assert.IsTrue(lError.Contains('--project-context is only supported with unit analysis'), lError);
end;

procedure TCliTests.AnalyzeHelpIncludesProjectContext;
begin
  Assert.IsTrue(SUsageAnalyze.Contains('--project-context "<dproj>"'));
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

procedure TCliTests.BuildCommandParsesCompilerOverlays;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --delphi 23.0 ' +
    '--define maxProfiling --define PROFILE_EXTRA ' +
    '--unit-search-path C:\Profiler\runtime --unit-search-path "C:\Profiler Companions"');
  Assert.IsTrue(TryParseOptions(lOptions, lError),
    'Expected build compiler overlay switches to parse. Error: ' + lError);
end;

procedure TCliTests.BuildCommandRejectsCompilerOverlaysForWebCore;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('build --project C:\repo\Sample.dproj --builder webcore ' +
    '--webcore-compiler C:\tools\TMSWebCompiler.exe --define maxProfiling');
  Assert.IsFalse(TryParseOptions(lOptions, lError),
    'Expected WebCore builds to reject compiler overlays.');
  Assert.IsTrue(Pos('--define', lError) > 0,
    'Expected WebCore incompatibility error to mention --define. Actual: ' + lError);
  Assert.IsTrue(Pos('only supported for Delphi/MSBuild builds', lError) > 0,
    'Expected Delphi-only incompatibility error. Actual: ' + lError);

  SetParams('build --project C:\repo\Sample.dproj --builder webcore ' +
    '--webcore-compiler C:\tools\TMSWebCompiler.exe --unit-search-path C:\Profiler\runtime');
  Assert.IsFalse(TryParseOptions(lOptions, lError),
    'Expected WebCore builds to reject unit search path overlays.');
  Assert.IsTrue(Pos('--unit-search-path', lError) > 0,
    'Expected WebCore incompatibility error to mention --unit-search-path. Actual: ' + lError);
  Assert.IsTrue(Pos('only supported for Delphi/MSBuild builds', lError) > 0,
    'Expected Delphi-only incompatibility error. Actual: ' + lError);
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyze-unit process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected analyze-unit run to succeed. See: ' + lRunLog);

  lSummaryPath := TPath.Combine(lDakRoot, 'summary.md');
  Assert.IsTrue(FileExists(lSummaryPath), 'Expected default analyze-unit output under sibling .dak root: ' + lSummaryPath);
  Assert.IsFalse(TDirectory.Exists(lLegacyRoot), 'Did not expect legacy _analysis unit root: ' + lLegacyRoot);
end;

procedure TCliTests.AnalyzeChildToolLogsAreIsolatedFromRunLog;
var
  lCommonSource: string;
  lProjectSource: string;
  lUnitSource: string;
begin
  lCommonSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.analyze.common.pas'), TEncoding.UTF8);
  lProjectSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.analyze.projectrunner.pas'), TEncoding.UTF8);
  lUnitSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.analyze.unitrunner.pas'), TEncoding.UTF8);

  Assert.IsTrue(Pos('TryRunFixInsightLogged(fParams, lStdOutLogPath, lStdErrLogPath, fRunLog', lProjectSource) > 0,
    'Expected FixInsight project runs to pass isolated stdout/stderr logs plus run.log index path.');
  Assert.IsTrue(Pos('TryRunPalLogged(fParams, fPascalAnalyzer, lStdOutLogPath, lStdErrLogPath, fRunLog', lProjectSource) > 0,
    'Expected PAL project runs to pass isolated stdout/stderr logs plus run.log index path.');
  Assert.IsTrue(Pos('TryRunPalUnitLogged(fUnitPath, fPascalAnalyzer, lStdOutLogPath, lStdErrLogPath, fRunLog', lUnitSource) > 0,
    'Expected PAL unit runs to pass isolated stdout/stderr logs plus run.log index path.');
  Assert.IsTrue(Pos('AppendAnalyzeRunLogIndex', lCommonSource) > 0,
    'Expected analyze run.log to be written as an index of child logs.');
  Assert.IsFalse(Pos('TryRunFixInsightLogged(fParams, fRunLog', lProjectSource) > 0,
    'FixInsight project runs must not stream child output directly into shared run.log.');
  Assert.IsFalse(Pos('TryRunPalLogged(fParams, fPascalAnalyzer, fRunLog', lProjectSource) > 0,
    'PAL project runs must not stream child output directly into shared run.log.');
  Assert.IsFalse(Pos('TryRunPalUnitLogged(fUnitPath, fPascalAnalyzer, fRunLog', lUnitSource) > 0,
    'PAL unit runs must not stream child output directly into shared run.log.');
end;

procedure TCliTests.AnalyzeCommandParsesAnalyzerTimeouts;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('analyze --project C:\repo\Sample.dproj --delphi 23.0 --fi-timeout-sec 11 --pa-timeout-sec 22');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected analyzer timeout args to parse. Error: ' + lError);
  Assert.IsTrue(lOptions.fHasFixTimeoutSec, 'Expected explicit FixInsight timeout flag.');
  Assert.AreEqual(11, lOptions.fFixTimeoutSec, 'Unexpected FixInsight timeout value.');
  Assert.IsTrue(lOptions.fHasPaTimeoutSec, 'Expected explicit Pascal Analyzer timeout flag.');
  Assert.AreEqual(22, lOptions.fPaTimeoutSec, 'Unexpected Pascal Analyzer timeout value.');
end;

procedure TCliTests.AnalyzeCommandRejectsInvalidAnalyzerTimeout;
var
  lOptions: TAppOptions;
  lError: string;
begin
  SetParams('analyze --project C:\repo\Sample.dproj --delphi 23.0 --fi-timeout-sec 0');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected zero FixInsight timeout to be rejected.');
  Assert.IsTrue(Pos('--fi-timeout-sec', lError) > 0, 'Expected FixInsight timeout error. Actual: ' + lError);

  SetParams('analyze --project C:\repo\Sample.dproj --delphi 23.0 --pa-timeout-sec abc');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected non-integer Pascal Analyzer timeout to be rejected.');
  Assert.IsTrue(Pos('--pa-timeout-sec', lError) > 0, 'Expected Pascal Analyzer timeout error. Actual: ' + lError);
end;

procedure TCliTests.LoadSettingsWithoutRepoMarkerUsesOnlyProjectLocalDakIni;
var
  lBaseDir: string;
  lDprojPath: string;
  lFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  lFixOptions: TFixInsightExtraOptions;
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
  lBaseDir := UniqueNoRepoTempPath('dak-settings-norepo');
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
    DeleteTempPath(lBaseDir);
  end;
end;

procedure TCliTests.LoadSettingsReadsAnalyzerTimeouts;
var
  lBaseDir: string;
  lDprojPath: string;
  lFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  lFixOptions: TFixInsightExtraOptions;
  lIni: TIniFile;
  lPascalAnalyzer: TPascalAnalyzerDefaults;
  lProjectIniPath: string;
  lReportFilter: TReportFilterDefaults;
begin
  lBaseDir := UniqueTempPath('dak-settings-analyzer-timeout');
  TDirectory.CreateDirectory(lBaseDir);

  lDprojPath := TPath.Combine(lBaseDir, 'Sample.dproj');
  TFile.WriteAllText(lDprojPath, '<Project/>', TEncoding.UTF8);

  lProjectIniPath := TPath.Combine(lBaseDir, 'dak.ini');
  lIni := TIniFile.Create(lProjectIniPath);
  try
    lIni.WriteInteger('FixInsightCL', 'TimeoutSec', 33);
    lIni.WriteInteger('PascalAnalyzer', 'TimeoutSec', 44);
  finally
    lIni.Free;
  end;

  try
    Assert.IsTrue(LoadSettings(nil, lDprojPath, lFixOptions, lFixIgnoreDefaults, lReportFilter, lPascalAnalyzer),
      'Expected settings loader to succeed.');
    Assert.AreEqual(33, lFixOptions.fTimeoutSec, 'Unexpected FixInsight timeout from dak.ini.');
    Assert.AreEqual(44, lPascalAnalyzer.fTimeoutSec, 'Unexpected Pascal Analyzer timeout from dak.ini.');
  finally
    DeleteTempPath(lBaseDir);
  end;
end;

procedure TCliTests.DakIniLoadingIsCentralized;
var
  lBuildRunnerSource: string;
  lSettingsSource: string;
begin
  lSettingsSource := TPath.Combine(RepoRoot, 'src\Dak.Settings.pas');
  Assert.IsTrue(FileExists(lSettingsSource), 'Expected shared dak.ini loader unit: ' + lSettingsSource);

  lBuildRunnerSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.build.runner.pas'), TEncoding.UTF8);
  Assert.IsFalse(ContainsText(lBuildRunnerSource, 'TIniFile.Create'),
    'Build runner must consume the typed settings loader instead of parsing dak.ini directly.');
  Assert.IsFalse(ContainsText(lBuildRunnerSource, 'ReadString(''BuildIgnore'''),
    'BuildIgnore dak.ini parsing must be centralized in Dak.Settings.');
  Assert.IsFalse(ContainsText(lBuildRunnerSource, 'ReadString(''MadExcept'''),
    'MadExcept dak.ini parsing must be centralized in Dak.Settings.');
  Assert.IsFalse(ContainsText(lBuildRunnerSource, 'ReadString(''WebCore'''),
    'WebCore dak.ini parsing must be centralized in Dak.Settings.');
end;

procedure TCliTests.LoadDakSettingsMergesTypedSections;
var
  lBaseDir: string;
  lDprojPath: string;
  lEnvVars: TDictionary<string, string>;
  lRepoDir: string;
  lSettings: TDakSettings;
  lSubDir: string;

  procedure WriteIniText(const aPath, aText: string);
  begin
    ForceDirectories(ExtractFileDir(aPath));
    TFile.WriteAllText(aPath, aText, TEncoding.ASCII);
  end;
begin
  lBaseDir := UniqueTempPath('dak-settings-typed');
  lRepoDir := TPath.Combine(lBaseDir, 'repo');
  lSubDir := TPath.Combine(lRepoDir, 'sub');
  ForceDirectories(TPath.Combine(lRepoDir, '.git'));
  ForceDirectories(lSubDir);

  lDprojPath := TPath.Combine(lSubDir, 'Sample.dproj');
  TFile.WriteAllText(lDprojPath, '<Project/>', TEncoding.UTF8);
  WriteIniText(TPath.Combine(lRepoDir, 'dak.ini'),
    '[FixInsightCL]' + sLineBreak +
    'Ignore=bin;obj' + sLineBreak +
    'TimeoutSec=12' + sLineBreak +
    '[BuildIgnore]' + sLineBreak +
    'Warnings=W1000;W2000' + sLineBreak +
    '[ReportFilter]' + sLineBreak +
    'ExcludePathMasks=vendor\*' + sLineBreak +
    '[MadExcept]' + sLineBreak +
    'Path=$(TOOLS)\madExcept' + sLineBreak +
    '[Build]' + sLineBreak +
    'DelphiVersion=22.0' + sLineBreak);
  WriteIniText(TPath.Combine(lSubDir, 'dak.ini'),
    '[FixInsightCL]' + sLineBreak +
    'Ignore=obj;tmp' + sLineBreak +
    '[BuildIgnore]' + sLineBreak +
    'Warnings=W2000;W3000' + sLineBreak +
    'Hints=H1000' + sLineBreak +
    '[ReportFilter]' + sLineBreak +
    'ExcludePathMasks=generated\*;vendor\*' + sLineBreak +
    '[WebCore]' + sLineBreak +
    'CompilerPath=$(TOOLS)\webcore\TMSWebCompiler.exe' + sLineBreak +
    '[Build]' + sLineBreak +
    'DelphiVersion=23.0' + sLineBreak);

  lEnvVars := TDictionary<string, string>.Create;
  try
    lEnvVars.Add('TOOLS', TPath.Combine(lBaseDir, 'tools'));
    Assert.IsTrue(LoadDakSettings(nil, lDprojPath, lEnvVars, lSettings),
      'Expected shared typed settings loader to succeed.');
    Assert.AreEqual('bin;obj;tmp', lSettings.fFixInsight.fIgnore,
      'FixInsight path ignores should merge and dedupe across layers.');
    Assert.AreEqual(12, lSettings.fFixInsight.fTimeoutSec,
      'FixInsight timeout should be loaded through the shared typed settings record.');
    Assert.AreEqual('W1000;W2000;W3000', lSettings.fBuild.fIgnoreWarnings,
      'Build warning ignores should merge and dedupe through the shared loader.');
    Assert.AreEqual('H1000', lSettings.fBuild.fIgnoreHints,
      'Build hint ignores should come from the shared loader.');
    Assert.AreEqual('vendor\*;generated\*', lSettings.fReportFilter.fExcludePathMasks,
      'ReportFilter masks should merge in first-seen order.');
    Assert.AreEqual(lSettings.fReportFilter.fExcludePathMasks, lSettings.fBuild.fExcludePathMasks,
      'Build summary filtering should consume the same ReportFilter defaults.');
    Assert.AreEqual(TPath.GetFullPath(TPath.Combine(lBaseDir, 'tools\madExcept')),
      lSettings.fBuild.fMadExceptPath, 'MadExcept path should expand through the settings loader.');
    Assert.AreEqual(TPath.GetFullPath(TPath.Combine(lBaseDir, 'tools\webcore\TMSWebCompiler.exe')),
      lSettings.fBuild.fWebCoreCompilerPath, 'WebCore compiler path should expand through the settings loader.');
    Assert.AreEqual('23.0', lSettings.fDelphiVersion,
      'More local Build DelphiVersion should override repo-level defaults.');
  finally
    lEnvVars.Free;
    DeleteTempPath(lBaseDir);
  end;
end;

procedure TCliTests.CommandOutputWritingIsCentralized;
var
  lCommandOutputSource: string;
  lDepsSource: string;
  lGlobalVarsSource: string;
  lRemoveWithSource: string;
  lResolveSource: string;
begin
  lCommandOutputSource := TPath.Combine(RepoRoot, 'src\Dak.CommandOutput.pas');
  Assert.IsTrue(FileExists(lCommandOutputSource), 'Expected shared command output helper: ' + lCommandOutputSource);

  lDepsSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.deps.runner.pas'), TEncoding.UTF8);
  lGlobalVarsSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.globalvars.pas'), TEncoding.UTF8);
  lRemoveWithSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.pas'), TEncoding.UTF8);
  lResolveSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.output.pas'), TEncoding.UTF8);

  Assert.IsFalse(ContainsText(lDepsSource, 'TFile.WriteAllText(aOutputPath'),
    'deps must use Dak.CommandOutput for file writes.');
  Assert.IsFalse(ContainsText(lGlobalVarsSource, 'TFile.WriteAllText(aOutputPath'),
    'global-vars must use Dak.CommandOutput for file writes.');
  Assert.IsFalse(ContainsText(lRemoveWithSource, 'TFile.WriteAllText(aOptions.fRemoveWithOutputPath'),
    'remove-with must use Dak.CommandOutput for file writes.');
  Assert.IsFalse(ContainsText(lResolveSource, 'TFile.WriteAllText(aOutPath'),
    'resolve output must use Dak.CommandOutput for file writes.');
end;

procedure TCliTests.CommandOutputContinuesFileWriteWhenStdoutPipeCloses;
var
  lError: string;
  lOriginalHandle: THandle;
  lOriginalStdoutHandle: THandle;
  lOutputPath: string;
  lOutputText: string;
  lReadHandle: THandle;
  lWriteHandle: THandle;
begin
  lOutputPath := UniqueTempPath('command-output-closed-pipe') + '.txt';
  lOutputText := StringOfChar('x', 8192);
  lReadHandle := 0;
  lWriteHandle := 0;
  Assert.IsTrue(CreatePipe(lReadHandle, lWriteHandle, nil, 0), 'Failed to create the stdout test pipe.');
  CloseHandle(lReadHandle);

  Flush(Output);
  lOriginalHandle := TTextRec(Output).Handle;
  lOriginalStdoutHandle := GetStdHandle(STD_OUTPUT_HANDLE);
  try
    Assert.IsTrue(SetStdHandle(STD_OUTPUT_HANDLE, lWriteHandle), 'Failed to redirect the Windows stdout handle.');
    TTextRec(Output).Handle := lWriteHandle;
    Assert.IsTrue(WriteCommandOutput(lOutputText, lOutputPath,
      TCommandOutputPolicy.copAlwaysStdoutAndOptionalFile, True, False, False, lError), lError);
  finally
    TTextRec(Output).Handle := lOriginalHandle;
    SetStdHandle(STD_OUTPUT_HANDLE, lOriginalStdoutHandle);
    CloseHandle(lWriteHandle);
  end;

  try
    Assert.IsTrue(TFile.Exists(lOutputPath), 'A closed stdout pipe must not block requested file output.');
    Assert.AreEqual(lOutputText, TFile.ReadAllText(lOutputPath, TEncoding.UTF8));
  finally
    if TFile.Exists(lOutputPath) then
      TFile.Delete(lOutputPath);
  end;
end;

procedure TCliTests.LoadDefaultDelphiVersionUsesProjectLocalDakIni;
var
  lBaseDir: string;
  lDefaultDelphiVersion: string;
  lDprojPath: string;
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
  lBaseDir := UniqueNoRepoTempPath('dak-settings-delphi');
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
    DeleteTempPath(lBaseDir);
  end;
end;

procedure TCliTests.CommandMetadataHasSingleTokenRegistry;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.cli.pas'));

  Assert.IsFalse(lSource.Contains('function TryParseCommandToken('),
    'TryGetCommand must use the shared command metadata registry, not a nested token parser.');
  Assert.IsFalse(lSource.Contains('function TOptionParser.TrySetCommandFromArg('),
    'TOptionParser must use the shared command metadata registry, not its own token parser.');
  Assert.IsFalse(lSource.Contains('SameText(aArg, ''resolve'')'),
    'Command token aliases must be centralized instead of repeated as SameText(aArg, ...) chains.');
end;

procedure TCliTests.CommandMetadataParsesAdvertisedTokens;
type
  TExpectedCommandToken = record
    fToken: string;
    fCommand: TCommandKind;
  end;
const
  cTokens: array[0..14] of TExpectedCommandToken = (
    (fToken: 'resolve'; fCommand: TCommandKind.ckResolve),
    (fToken: 'analyze'; fCommand: TCommandKind.ckAnalyzeProject),
    (fToken: 'analyze-project'; fCommand: TCommandKind.ckAnalyzeProject),
    (fToken: 'analyze-unit'; fCommand: TCommandKind.ckAnalyzeUnit),
    (fToken: 'build'; fCommand: TCommandKind.ckBuild),
    (fToken: 'dfm-check'; fCommand: TCommandKind.ckDfmCheck),
    (fToken: 'dfm-inspect'; fCommand: TCommandKind.ckDfmInspect),
    (fToken: 'global-vars'; fCommand: TCommandKind.ckGlobalVars),
    (fToken: 'deps'; fCommand: TCommandKind.ckDeps),
    (fToken: 'lsp'; fCommand: TCommandKind.ckLsp),
    (fToken: 'remove-with'; fCommand: TCommandKind.ckRemoveWith),
    (fToken: 'symbol-map'; fCommand: TCommandKind.ckSymbolMap),
    (fToken: 'find-usages'; fCommand: TCommandKind.ckFindUsages),
    (fToken: 'rename'; fCommand: TCommandKind.ckRename),
    (fToken: 'dead-code'; fCommand: TCommandKind.ckDeadCode)
  );
var
  lCommand: TCommandKind;
  lError: string;
  lHasCommand: Boolean;
  lToken: TExpectedCommandToken;
begin
  for lToken in cTokens do
  begin
    SetParams('--help ' + lToken.fToken);
    Assert.IsTrue(TryGetCommand(lCommand, lHasCommand, lError),
      'Expected help command detection for token "' + lToken.fToken + '". Error: ' + lError);
    Assert.IsTrue(lHasCommand, 'Expected explicit command detection for token "' + lToken.fToken + '".');
    Assert.AreEqual(lToken.fCommand, lCommand, 'Unexpected command kind for token "' + lToken.fToken + '".');
    Assert.AreEqual('', lError, 'Expected no command-detection error for token "' + lToken.fToken + '".');
  end;
end;

procedure TCliTests.CommandMetadataCoversAllCommandKinds;
var
  lCommand: TCommandKind;
begin
  for lCommand := Low(TCommandKind) to High(TCommandKind) do
    Assert.IsTrue(CommandRoutesAs(lCommand, lCommand), 'Expected descriptor for command ordinal ' +
      IntToStr(Ord(lCommand)) + '.');

  Assert.IsTrue(CommandRoutesAs(TCommandKind.ckAnalyzeUnit, TCommandKind.ckAnalyzeProject),
    'Expected analyze-unit to dispatch through the analyze route.');
  Assert.IsFalse(CommandRoutesAs(TCommandKind.ckAnalyzeUnit, TCommandKind.ckResolve),
    'Did not expect analyze-unit to dispatch through the resolve route.');
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

procedure TCliTests.RemoveWithCommandParsesScanUnitTarget;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('remove-with --project c:\temp\sample.dproj --unit c:\temp\unit1.pas --mode scan --format json');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected remove-with scan args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckRemoveWith, lOptions.fCommand);
  Assert.AreEqual(TRemoveWithMode.rwmScan, lOptions.fRemoveWithMode);
  Assert.AreEqual(TRemoveWithFormat.rwfJson, lOptions.fRemoveWithFormat);
  Assert.AreEqual(TRemoveWithTargetKind.rwtUnit, lOptions.fRemoveWithTargetKind);
  Assert.AreEqual('c:\temp\unit1.pas', lOptions.fRemoveWithUnitPath);
end;

procedure TCliTests.RemoveWithCommandParsesPlanDirTarget;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('remove-with --project c:\temp\sample.dproj --dir c:\temp\src --mode plan --format text');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected remove-with plan args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckRemoveWith, lOptions.fCommand);
  Assert.AreEqual(TRemoveWithMode.rwmPlan, lOptions.fRemoveWithMode);
  Assert.AreEqual(TRemoveWithFormat.rwfText, lOptions.fRemoveWithFormat);
  Assert.AreEqual(TRemoveWithTargetKind.rwtDir, lOptions.fRemoveWithTargetKind);
  Assert.AreEqual('c:\temp\src', lOptions.fRemoveWithDirPath);
end;

procedure TCliTests.RemoveWithCommandParsesApplyAllTarget;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('remove-with --project c:\temp\sample.dproj --all --mode apply');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected remove-with apply args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckRemoveWith, lOptions.fCommand);
  Assert.AreEqual(TRemoveWithMode.rwmApply, lOptions.fRemoveWithMode);
  Assert.AreEqual(TRemoveWithFormat.rwfJson, lOptions.fRemoveWithFormat);
  Assert.AreEqual(TRemoveWithTargetKind.rwtAll, lOptions.fRemoveWithTargetKind);
  Assert.IsTrue(lOptions.fRemoveWithAll);
end;

procedure TCliTests.RemoveWithCommandParsesDiagnosticsFlag;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('remove-with --project c:\temp\sample.dproj --all --mode plan --diagnostics true');
  Assert.IsTrue(TryParseOptions(lOptions, lError),
    'Expected remove-with diagnostics args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckRemoveWith, lOptions.fCommand);
  Assert.IsTrue(lOptions.fRemoveWithDiagnostics, 'Expected remove-with diagnostics flag.');
end;

procedure TCliTests.RemoveWithCommandRejectsMissingTarget;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('remove-with --project c:\temp\sample.dproj --mode scan');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected remove-with to require a target filter.');
  Assert.IsTrue(Pos('--unit, --dir, or --all', lError) > 0,
    'Expected remove-with target validation error. Actual: ' + lError);
end;

procedure TCliTests.RemoveWithCommandRejectsMultipleTargets;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('remove-with --project c:\temp\sample.dproj --unit c:\temp\unit1.pas --all');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected remove-with to reject multiple target filters.');
  Assert.IsTrue(Pos('--unit, --dir, or --all', lError) > 0,
    'Expected remove-with target validation error. Actual: ' + lError);
end;

procedure TCliTests.RemoveWithCommandRejectsInvalidMode;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('remove-with --project c:\temp\sample.dproj --all --mode rewrite');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected remove-with to reject invalid modes.');
  Assert.IsTrue(Pos('rewrite', lError) > 0, 'Expected invalid mode value in error. Actual: ' + lError);
end;

procedure TCliTests.RemoveWithCommandRejectsInvalidFormat;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('remove-with --project c:\temp\sample.dproj --all --format xml');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected remove-with to reject invalid formats.');
  Assert.IsTrue(Pos('xml', lError) > 0, 'Expected invalid format value in error. Actual: ' + lError);
end;

procedure TCliTests.RemoveWithHelpDocumentsModesAndTargets;
var
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'remove-with-help.log');

  Assert.IsTrue(RunResolverProcess('remove-with --help', RepoRoot, lLogPath, lExitCode),
    'Failed to start remove-with help command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with --help to succeed. See: ' + lLogPath);

  lLogText := '';
  if FileExists(lLogPath) then
    lLogText := ReadUtf8TextFile(lLogPath);

  Assert.IsTrue(Pos('scan', lLogText) > 0, 'Expected remove-with help to mention scan mode.');
  Assert.IsTrue(Pos('plan', lLogText) > 0, 'Expected remove-with help to mention plan mode.');
  Assert.IsTrue(Pos('apply', lLogText) > 0, 'Expected remove-with help to mention apply mode.');
  Assert.IsTrue(Pos('--unit', lLogText) > 0, 'Expected remove-with help to mention --unit.');
  Assert.IsTrue(Pos('--dir', lLogText) > 0, 'Expected remove-with help to mention --dir.');
  Assert.IsTrue(Pos('--all', lLogText) > 0, 'Expected remove-with help to mention --all.');
  Assert.IsTrue(Pos('rollback', LowerCase(lLogText)) > 0, 'Expected remove-with help to mention rollback.');
  Assert.IsTrue(Pos('safe', LowerCase(lLogText)) > 0, 'Expected remove-with help to mention safety defaults.');
  Assert.IsTrue(Pos('default: plan', LowerCase(lLogText)) > 0,
    'Expected remove-with help to document the non-mutating default mode.');
end;

procedure TCliTests.RefactorSlashSwitchesDoNotBecomeBoolValues;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('rename --project C:\repo\Sample.dproj --symbol OldName --apply /new-name NewName');

  Assert.IsTrue(TryParseOptions(lOptions, lError),
    'Expected slash-style /new-name to remain a switch after --apply. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckRename, lOptions.fCommand, 'Expected rename command kind.');
  Assert.IsTrue(lOptions.fHasRefactorApply, 'Expected --apply to be parsed as an explicit flag.');
  Assert.IsTrue(lOptions.fRefactorApply, 'Expected bare --apply to enable apply mode.');
  Assert.AreEqual('NewName', lOptions.fRefactorNewName, 'Expected /new-name value to parse.');

  SetParams('rename --project C:\repo\Sample.dproj --symbol OldName --apply /semantic-cache C:\cache /new-name NewName');

  Assert.IsTrue(TryParseOptions(lOptions, lError),
    'Expected slash-style /semantic-cache to remain a switch after --apply. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckRename, lOptions.fCommand, 'Expected rename command kind.');
  Assert.IsTrue(lOptions.fHasRefactorApply, 'Expected --apply to be parsed as an explicit flag.');
  Assert.IsTrue(lOptions.fRefactorApply, 'Expected bare --apply to enable apply mode.');
  Assert.IsTrue(lOptions.fHasRefactorSemanticCachePath, 'Expected /semantic-cache to set the semantic cache path.');
  Assert.AreEqual('C:\cache', lOptions.fRefactorSemanticCachePath, 'Expected /semantic-cache value to parse.');
  Assert.AreEqual('NewName', lOptions.fRefactorNewName, 'Expected /new-name value to parse.');

  SetParams('dead-code --project C:\repo\Sample.dproj --verbose /profile audit');

  Assert.IsTrue(TryParseOptions(lOptions, lError),
    'Expected slash-style /profile to remain a switch after --verbose. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckDeadCode, lOptions.fCommand, 'Expected dead-code command kind.');
  Assert.IsTrue(lOptions.fVerbose, 'Expected bare --verbose to enable verbose mode.');
  Assert.AreEqual('audit', lOptions.fDeadCodeProfile, 'Expected /profile value to parse.');

  SetParams('rename --project C:\repo\Sample.dproj --symbol OldName --new-name NewName /profile audit');

  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected rename to reject dead-code-only /profile.');
  Assert.IsTrue(Pos('/profile', lError) > 0, 'Expected rejected /profile in error. Actual: ' + lError);
end;

procedure TCliTests.SemanticCacheSwitchesSupportOptOutAndRejectConflict;
var
  lArgs: string;
  lCommands: TArray<string>;
  lError: string;
  lOptions: TAppOptions;
begin
  lCommands := [
    'find-usages --project C:\repo\Sample.dproj --symbol SharedValue',
    'rename --project C:\repo\Sample.dproj --symbol SharedValue --new-name RenamedValue',
    'dead-code --project C:\repo\Sample.dproj',
    'remove-with --project C:\repo\Sample.dproj --all --mode plan'];
  for lArgs in lCommands do
  begin
    SetParams(lArgs + ' --no-semantic-cache');
    Assert.IsTrue(TryParseOptions(lOptions, lError),
      'Expected --no-semantic-cache to parse. Error: ' + lError);
    Assert.IsTrue(lOptions.fNoSemanticCache,
      'Expected --no-semantic-cache to enable opt-out. Command: ' + lArgs);
  end;

  for lArgs in lCommands do
  begin
    SetParams(lArgs +
      ' --semantic-cache C:\cache.sqlite3 --no-semantic-cache');
    Assert.IsFalse(TryParseOptions(lOptions, lError),
      'Expected explicit semantic cache and opt-out to conflict.');
    Assert.IsTrue(ContainsText(lError, '--semantic-cache'),
      'Expected conflict error to mention --semantic-cache. Actual: ' + lError);
    Assert.IsTrue(ContainsText(lError, '--no-semantic-cache'),
      'Expected conflict error to mention --no-semantic-cache. Actual: ' + lError);
  end;
end;

procedure TCliTests.DeadCodeProfileParsingUsesDakAdapter;
var
  lCliSource: string;
begin
  lCliSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.cli.pas'),
    TEncoding.UTF8);

  Assert.IsFalse(ContainsText(lCliSource, 'DelphiSemantics.DeadCode'),
    'CLI parsing must not import Semantics dead-code implementation units.');
  Assert.IsFalse(ContainsText(lCliSource, 'TDelphiSemanticDeadCode'),
    'CLI parsing must not expose Semantics dead-code profile types.');
  Assert.IsTrue(ContainsText(lCliSource, 'Dak.DeadCodeProfile'),
    'CLI parsing should use the DAK dead-code profile adapter.');
  Assert.IsTrue(ContainsText(lCliSource, 'TryNormalizeDeadCodeProfileName'),
    'CLI parsing should normalize profile names through the DAK adapter.');
  Assert.IsTrue(ContainsText(lCliSource, 'DefaultDeadCodeProfileName'),
    'CLI defaults should come through the DAK adapter.');
end;

procedure TCliTests.RefactorCommandsRejectPartialPositionTargetsPrecisely;
var
  lError: string;
  lOptions: TAppOptions;

  procedure CheckValid(const aArgs: string; const aCommand: TCommandKind);
  begin
    SetParams(aArgs);
    Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected command to parse. Error: ' + lError);
    Assert.AreEqual(aCommand, lOptions.fCommand);
  end;

  procedure CheckInvalid(const aArgs, aExpectedSwitch, aForbiddenText: string);
  begin
    SetParams(aArgs);
    Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected command to be rejected: ' + aArgs);
    Assert.IsTrue(Pos(aExpectedSwitch, lError) > 0,
      'Expected error to mention ' + aExpectedSwitch + '. Actual: ' + lError);
    if aForbiddenText <> '' then
      Assert.AreEqual(0, Pos(aForbiddenText, lError),
        'Error should not mention ' + aForbiddenText + '. Actual: ' + lError);
  end;
begin
  CheckValid('find-usages --project C:\repo\Sample.dproj --symbol SharedValue', TCommandKind.ckFindUsages);
  CheckValid('find-usages --project C:\repo\Sample.dproj --file C:\repo\Unit1.pas --line 6 --col 3',
    TCommandKind.ckFindUsages);
  CheckInvalid('find-usages --project C:\repo\Sample.dproj', 'Use either', '');
  CheckInvalid('find-usages --project C:\repo\Sample.dproj --symbol SharedValue --file C:\repo\Unit1.pas',
    'Use either', '');
  CheckInvalid('find-usages --project C:\repo\Sample.dproj --line 6 --col 3', '--file', 'Use either');
  CheckInvalid('find-usages --project C:\repo\Sample.dproj --file C:\repo\Unit1.pas --col 3', '--line',
    'Use either');
  CheckInvalid('find-usages --project C:\repo\Sample.dproj --file C:\repo\Unit1.pas --line 6', '--col',
    'Use either');

  CheckValid('rename --project C:\repo\Sample.dproj --symbol SharedValue --new-name RenamedValue',
    TCommandKind.ckRename);
  CheckValid('rename --project C:\repo\Sample.dproj --file C:\repo\Unit1.pas --line 6 --col 3 ' +
    '--new-name RenamedValue', TCommandKind.ckRename);
  CheckInvalid('rename --project C:\repo\Sample.dproj --new-name RenamedValue', '--symbol', '');
  CheckInvalid('rename --project C:\repo\Sample.dproj --symbol SharedValue --file C:\repo\Unit1.pas ' +
    '--new-name RenamedValue', 'Use either', '');
  CheckInvalid('rename --project C:\repo\Sample.dproj --line 6 --col 3 --new-name RenamedValue', '--file',
    '--symbol');
  CheckInvalid('rename --project C:\repo\Sample.dproj --file C:\repo\Unit1.pas --col 3 ' +
    '--new-name RenamedValue', '--line', '--symbol');
  CheckInvalid('rename --project C:\repo\Sample.dproj --file C:\repo\Unit1.pas --line 6 ' +
    '--new-name RenamedValue', '--col', '--symbol');
end;

procedure TCliTests.LspCommandParsesOperationsAndRequiredArgs;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('lsp definition --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 3 --col 5');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected lsp definition args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckLsp, lOptions.fCommand);
  Assert.AreEqual(TLspOperation.loDefinition, lOptions.fLspOperation);
  Assert.AreEqual('c:\temp\unit1.pas', lOptions.fLspFilePath);
  Assert.AreEqual(3, lOptions.fLspLine);
  Assert.AreEqual(5, lOptions.fLspCol);

  SetParams('lsp hover --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 11 --col 13');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected lsp hover args to parse. Error: ' + lError);
  Assert.AreEqual(TLspOperation.loHover, lOptions.fLspOperation);
  Assert.AreEqual(11, lOptions.fLspLine);
  Assert.AreEqual(13, lOptions.fLspCol);

  SetParams('lsp symbols --project c:\temp\sample.dproj --file c:\temp\unit1.pas --query Foo --limit 7');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected lsp symbols args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckLsp, lOptions.fCommand);
  Assert.AreEqual(TLspOperation.loSymbols, lOptions.fLspOperation);
  Assert.AreEqual('c:\temp\unit1.pas', lOptions.fLspFilePath);
  Assert.AreEqual('Foo', lOptions.fLspQuery);
  Assert.AreEqual(7, lOptions.fLspLimit);
end;

procedure TCliTests.LspCommandParsesProjectAndOperationFields;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('lsp hover --project c:\temp\sample.dproj --platform Win64 --config Debug --file c:\temp\unit1.pas --line 21 --col 34 --format text');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected lsp hover fields to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckLsp, lOptions.fCommand);
  Assert.AreEqual('c:\temp\sample.dproj', lOptions.fDprojPath);
  Assert.AreEqual('Win64', lOptions.fPlatform);
  Assert.AreEqual('Debug', lOptions.fConfig);
  Assert.AreEqual(TLspOperation.loHover, lOptions.fLspOperation);
  Assert.AreEqual('c:\temp\unit1.pas', lOptions.fLspFilePath);
  Assert.AreEqual(21, lOptions.fLspLine);
  Assert.AreEqual(34, lOptions.fLspCol);
  Assert.AreEqual(TLspFormat.lfText, lOptions.fLspFormat);
end;

procedure TCliTests.LspProbeCommandParsesModesAndShowInitOptions;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('lsp probe --project c:\temp\sample.dproj --mode contextFile --mode settingsFile --show-init-options --format text');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected lsp probe args to parse. Error: ' + lError);
  Assert.AreEqual(TCommandKind.ckLsp, lOptions.fCommand);
  Assert.AreEqual(TLspOperation.loProbe, lOptions.fLspOperation);
  Assert.IsTrue(TLspProbeMode.lpmContextFile in lOptions.fLspProbeModes, 'Expected contextFile probe mode.');
  Assert.IsTrue(TLspProbeMode.lpmSettingsFile in lOptions.fLspProbeModes, 'Expected settingsFile probe mode.');
  Assert.IsTrue(lOptions.fLspShowInitOptions, 'Expected show-init-options to be captured.');
  Assert.AreEqual(TLspFormat.lfText, lOptions.fLspFormat);
end;

procedure TCliTests.LspCommandRejectsMissingOperationArguments;
var
  lError: string;
  lOptions: TAppOptions;
begin
  SetParams('lsp definition --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 3');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing lsp --col to be rejected.');
  Assert.IsTrue(Pos('--col', lError) > 0, 'Expected missing --col error. Actual: ' + lError);

  SetParams('lsp hover --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 0 --col 2');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected 1-based lsp --line validation to reject 0.');
  Assert.IsTrue(Pos('--line', lError) > 0, 'Expected invalid --line error. Actual: ' + lError);

  SetParams('lsp symbols --project c:\temp\sample.dproj --query Foo');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing lsp --file for symbols to be rejected.');
  Assert.IsTrue(Pos('--file', lError) > 0, 'Expected missing --file error. Actual: ' + lError);

  SetParams('lsp symbols --project c:\temp\sample.dproj --file c:\temp\unit1.pas');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected missing lsp --query to be rejected.');
  Assert.IsTrue(Pos('--query', lError) > 0, 'Expected missing --query error. Actual: ' + lError);

  SetParams('lsp definition --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 3 --col 5 --limit 10');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected --limit outside lsp symbols to be rejected.');
  Assert.IsTrue(Pos('--limit', lError) > 0, 'Expected invalid --limit operation error. Actual: ' + lError);

  SetParams('lsp references --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 7 --col 9');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected unsupported lsp references operation to be rejected.');
  Assert.IsTrue(Pos('references', LowerCase(lError)) > 0, 'Expected unsupported references error. Actual: ' + lError);

  SetParams('lsp hover --project c:\temp\sample.dproj --file c:\temp\unit1.pas --line 3 --col 5 --include-declaration false');
  Assert.IsFalse(TryParseOptions(lOptions, lError), 'Expected unsupported --include-declaration switch to be rejected.');
  Assert.IsTrue(Pos('--include-declaration', lError) > 0, 'Expected unsupported include-declaration error. Actual: ' + lError);
end;

procedure TCliTests.LspHelpListsSupportedOperationsOnly;
var
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'lsp-help.log');

  Assert.IsTrue(RunResolverProcess('lsp --help', RepoRoot, lLogPath, lExitCode),
    'Failed to start lsp help command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected lsp --help to succeed. See: ' + lLogPath);

  lLogText := '';
  if FileExists(lLogPath) then
    lLogText := ReadUtf8TextFile(lLogPath);

  Assert.IsTrue(Pos('definition', lLogText) > 0, 'Expected lsp help to mention definition.');
  Assert.IsTrue(Pos('hover', lLogText) > 0, 'Expected lsp help to mention hover.');
  Assert.IsTrue(Pos('symbols', lLogText) > 0, 'Expected lsp help to mention symbols.');
  Assert.IsTrue(Pos('probe', lLogText) > 0, 'Expected lsp help to mention probe.');
  Assert.AreEqual(0, Pos('references', LowerCase(lLogText)), 'Expected lsp help to omit unsupported references.');
  Assert.IsTrue(Pos('symbols: --file', LowerCase(lLogText)) > 0, 'Expected lsp help to mention file-scoped symbols usage.');
  Assert.IsTrue(Pos('--rsvars', lLogText) > 0, 'Expected lsp help to mention --rsvars.');
  Assert.IsTrue(Pos('--envoptions', lLogText) > 0, 'Expected lsp help to mention --envoptions.');

  lLogPath := TPath.Combine(TempRoot, 'resolve-help-regression.log');
  Assert.IsTrue(RunResolverProcess('resolve --help', RepoRoot, lLogPath, lExitCode),
    'Failed to start resolve help regression command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected resolve --help to keep working. See: ' + lLogPath);

  lLogText := '';
  if FileExists(lLogPath) then
    lLogText := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos('DelphiAIKit.exe resolve --project', lLogText) > 0,
    'Expected existing resolve help output to remain intact.');
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
