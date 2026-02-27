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
    procedure AnalyzeProjectSummarySkipsStaleTxtWhenTxtReportWasNotRun;
    [Test]
    procedure LoadSettingsWithoutRepoMarkerUsesOnlyProjectLocalDakIni;
    [Test]
    procedure HelpCommandIgnoresSwitchValueTokens;
    [Test]
    procedure HelpCommandFindsExplicitCommandAfterSwitchValues;
    [Test]
    procedure HelpCommandRejectsUnknownExplicitToken;
    [Test]
    procedure HelpCommandDoesNotTreatSwitchValueAsExplicitCommand;
    [Test]
    procedure HelpCommandDoesNotConsumeSwitchTokenAsRequiredValue;
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

initialization
  TDUnitX.RegisterTestFixture(TCliTests);

end.
