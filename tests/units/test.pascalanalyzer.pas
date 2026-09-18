unit Test.PascalAnalyzer;

interface

uses
  System.IOUtils, System.RegularExpressions, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  Dak.Analyze.Common, Dak.ExternalToolProcess, Dak.Messages,
  Dak.PascalAnalyzer.Artifacts, Dak.PascalAnalyzerRunner, Dak.Settings, Dak.Types,
  Test.Support;

type
  [TestFixture]
  TPascalAnalyzerTests = class
  public
    [Test]
    procedure Delphi13CommandUsesMappedCompilerFlags;
    [Test]
    procedure ExtraArgumentsRetainAutomationDefaults;
    [Test]
    procedure OwnedPalArgumentsAreRejected;
    [Test]
    [TestCase('Project INI', '0')]
    [TestCase('Repository INI', '1')]
    procedure LegacyArgumentsReportSourceAndAllConflicts(aRepository: Integer);
    [Test]
    procedure LongPalOutputPublishesReports;
    [Test]
    [TestCase('Short output', '0')]
    [TestCase('Long output', '1')]
    procedure ZeroExitWithoutStatusFails(aLong: Integer);
    [Test]
    procedure UnusableStagingPathFailsBeforePalStarts;
    [Test]
    procedure ExplicitPalExclusionsAreValidatedAndForwarded;
    [Test]
    procedure ProjectCommandOwnsReportName;
    [Test]
    procedure ProjectRunnerUsesExactNamedReportRoot;
    [Test]
    procedure UnitCommandUsesProjectContext;
    [Test]
    procedure ContextFreeUnitSummaryDeclaresPalIni;
    [Test]
    procedure SelectsSupportedCompilerFlag;
    [Test]
    procedure RunPascalAnalyzer;
    [Test]
    procedure PascalAnalyzerProcessWaitsAreBounded;
    [Test]
    procedure PascalAnalyzerTimeoutTerminatesChildProcess;
    [Test]
    procedure PascalAnalyzerHelpProbeTimeoutIsConfigurable;
    [Test]
    procedure InvalidPalMapJsonRootDoesNotRaise;
    [Test]
    procedure BuildPalCmdCommandLineUnsupportedPlatformReturnsError;
    [Test]
    procedure PascalAnalyzerRunnerDelegatesArtifactGeneration;
  end;

implementation

procedure TPascalAnalyzerTests.ZeroExitWithoutStatusFails(aLong: Integer);
var
  lRoot: string;
  lUnit: string;
  lOut: string;
  lLog: string;
  lStage: string;
  lMatch: TMatch;
  lArgs: string;
  lExit: Cardinal;
  lGuard: IInterface;
begin
  lRoot := UniqueTempPath('pal-no-status');
  TDirectory.CreateDirectory(lRoot);
  try
    lUnit := TPath.Combine(lRoot, 'Sample.pas');
    TFile.WriteAllText(lUnit, 'unit Sample; interface implementation end.', TEncoding.ASCII);
    lOut := TPath.Combine(lRoot, 'out');
    if aLong <> 0 then
      lOut := TPath.Combine(lRoot, StringOfChar('x', 190 - Length(lRoot)));
    // PAL's exit-0 internal failures vary by version; use the process fixture for this failure contract.
    lGuard := SetScopedEnvironmentVariable('DAK_TEST_PAL_HELP', '1');
    lArgs := 'analyze --unit ' + QuoteArg(lUnit) + ' --out ' + QuoteArg(lOut) +
      ' --delphi 23.0 --platform Win64 --fixinsight false --pascal-analyzer true --write-summary true' +
      ' --pa-path ' + QuoteArg(ParamStr(0));
    Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, TPath.Combine(lRoot, 'client.log'), lExit));
    Assert.AreEqual(Cardinal(6), lExit, 'Exit 0 without Status.xml must fail analysis.');
    lLog := TFile.ReadAllText(TPath.Combine(lOut, 'summary.md'));
    Assert.IsTrue(lLog.Contains('## Errors'), lLog);
    if aLong <> 0 then
    begin
      Assert.IsTrue(lLog.Contains('Status.xml'), lLog);
      Assert.IsTrue(lLog.Contains('Retained PAL staging directory:'), lLog);
      lLog := TFile.ReadAllText(TPath.Combine(lOut, 'run.log'));
      lMatch := TRegEx.Match(lLog, 'PAL staging: (.+?); publish to:');
      Assert.IsTrue(lMatch.Success, lLog);
      lStage := lMatch.Groups[1].Value;
      Assert.IsTrue(DirectoryExists(lStage), 'Failed staging evidence must remain available.');
    end;
  finally
    if (lStage <> '') and lStage.StartsWith(TPath.Combine(TPath.GetTempPath, 'dak-pal')) then
      DeleteTempPath(lStage);
    DeleteTempPath(lRoot);
  end;
end;

procedure TPascalAnalyzerTests.UnusableStagingPathFailsBeforePalStarts;
var
  lPa: TPascalAnalyzerDefaults;
  lError: string;
  lExit: Cardinal;
  lUnit: string;
begin
  lPa := Default(TPascalAnalyzerDefaults);
  lPa.fPath := 'C:\does-not-exist\palcmd.exe';
  lPa.fOutput := TPath.Combine(TempRoot, StringOfChar('x', 80));
  lUnit := TPath.Combine(TempRoot, StringOfChar('u', 200) + '.pas');
  Assert.IsFalse(TryRunPalUnitLogged(lUnit, lPa, '', '', '', lExit, lError));
  Assert.IsTrue(lError.Contains('PAL path budget exceeded:'), lError);
  Assert.IsTrue(lError.Contains('240'), lError);
  Assert.IsTrue(lError.Contains('--out'), lError);
  Assert.IsTrue(lError.Contains(lPa.fOutput), lError);
end;

procedure TPascalAnalyzerTests.LongPalOutputPublishesReports;
const
  cUnitName = 'IssueReview.LongUnitName.OptionalProviders.SelfTests';
var
  lRoot: string;
  lUnitPath: string;
  lOutput: string;
  lReport: string;
  lError: string;
  lExit: Cardinal;
  lPa: TPascalAnalyzerDefaults;
  lLog: string;
  lMatch: TMatch;
begin
  lRoot := UniqueTempPath('pal-path');
  TDirectory.CreateDirectory(lRoot);
  try
    lUnitPath := TPath.Combine(lRoot, cUnitName + '.pas');
    TFile.WriteAllText(lUnitPath, 'unit ' + cUnitName + '; interface implementation end.', TEncoding.ASCII);
    lOutput := TPath.Combine(lRoot, StringOfChar('x', 200 - Length(lRoot)));
    lPa := Default(TPascalAnalyzerDefaults);
    Assert.IsTrue(TryResolvePalCmdExe('', lPa.fPath, lError), lError);
    lPa.fArgs := '/CD12W64';
    lPa.fOutput := lOutput;
    Assert.IsTrue(TryRunPalUnitLogged(lUnitPath, lPa,
      TPath.Combine(lRoot, 'stdout.log'), TPath.Combine(lRoot, 'stderr.log'),
      TPath.Combine(lRoot, 'run.log'), lExit, lError), lError);
    Assert.AreEqual(Cardinal(0), lExit);
    lReport := PalArtifactPath(TPath.Combine(lOutput, cUnitName));
    Assert.IsTrue(FileExists(TPath.Combine(lReport, 'Status.xml')),
      'PAL exited successfully without publishing Status.xml for the long output path.');
    Assert.IsTrue(FileExists(TPath.Combine(lReport, 'Warnings.xml')));
    lLog := TFile.ReadAllText(TPath.Combine(lRoot, 'run.log'));
    lMatch := TRegEx.Match(lLog, 'PAL staging: (.+?); publish to:');
    Assert.IsTrue(lMatch.Success, lLog);
    Assert.IsFalse(DirectoryExists(lMatch.Groups[1].Value), 'Successful staging must be removed.');
    lPa.fOutput := TPath.Combine(lRoot, 'short');
    Assert.IsTrue(TryRunPalUnitLogged(lUnitPath, lPa,
      TPath.Combine(lRoot, 'short-stdout.log'), TPath.Combine(lRoot, 'short-stderr.log'),
      TPath.Combine(lRoot, 'short-run.log'), lExit, lError), lError);
    Assert.AreEqual(Cardinal(0), lExit);
    lReport := PalArtifactPath(TPath.Combine(lPa.fOutput, cUnitName));
    Assert.IsTrue(FileExists(TPath.Combine(lReport, 'Status.xml')));
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TPascalAnalyzerTests.LegacyArgumentsReportSourceAndAllConflicts(aRepository: Integer);
var
  lRoot: string;
  lProjectDir: string;
  lProject: string;
  lIni: string;
  lSettings: TDakSettings;
  lOptions: TAppOptions;
  lCmdLine: string;
  lError: string;
  lExe: string;
  lSwitch: string;
  lGuard: IInterface;
begin
  lRoot := UniqueTempPath('pal-legacy-args');
  TDirectory.CreateDirectory(lRoot);
  try
    TDirectory.CreateDirectory(TPath.Combine(lRoot, '.git'));
    lProjectDir := TPath.Combine(lRoot, 'src');
    TDirectory.CreateDirectory(lProjectDir);
    lProject := TPath.Combine(lProjectDir, 'Sample.dproj');
    if aRepository <> 0 then
      lIni := TPath.Combine(lRoot, 'dak.ini')
    else
      lIni := TPath.Combine(lProjectDir, 'dak.ini');
    TFile.WriteAllText(lProject, '<Project/>', TEncoding.ASCII);
    TFile.WriteAllText(lIni, '[PascalAnalyzer]' + sLineBreak +
      'Args=/F=X /Q /A+ /FA /T=32 /X="C:\Vendor<+>" /XF=Vendor.pas /NAME=Other /R=C:\Reports',
      TEncoding.ASCII);
    Assert.IsTrue(LoadDakSettings(nil, lProject, nil, lSettings), lSettings.fError);
    lSettings.fPascalAnalyzer.fPath := ParamStr(0);
    Assert.IsFalse(BuildPalCmdUnitCommandLine(lProject, lSettings.fPascalAnalyzer, lExe, lCmdLine, lError));
    Assert.IsTrue(lError.Contains(lIni), 'Missing effective configuration source: ' + lError);
    for lSwitch in ['/F=X', '/Q', '/A+', '/FA', '/T=32', '/X=', '/XF=', '/NAME=', '/R='] do
      Assert.IsTrue(lError.Contains(lSwitch), 'Missing conflict ' + lSwitch + ': ' + lError);
    Assert.IsTrue(lError.Contains('ExcludeSearchFolders'), lError);
    Assert.IsTrue(lError.Contains('ExcludeFiles'), lError);
    lOptions := Default(TAppOptions);
    lOptions.fHasPaArgs := True;
    lOptions.fPaArgs := '/Q /FA';
    ApplySettingsOverrides(lOptions, lSettings.fFixInsight, lSettings.fFixInsightIgnore,
      lSettings.fReportFilter, lSettings.fPascalAnalyzer);
    Assert.IsFalse(BuildPalCmdUnitCommandLine(lProject, lSettings.fPascalAnalyzer, lExe, lCmdLine, lError));
    Assert.IsTrue(lError.Contains('--pa-args'), lError);
    Assert.IsFalse(lError.Contains(lIni), 'CLI override must replace INI provenance: ' + lError);
    lGuard := SetScopedEnvironmentVariable('PA_ARGS', lOptions.fPaArgs);
    ApplySettingsOverrides(lOptions, lSettings.fFixInsight, lSettings.fFixInsightIgnore,
      lSettings.fReportFilter, lSettings.fPascalAnalyzer);
    Assert.IsFalse(BuildPalCmdUnitCommandLine(lProject, lSettings.fPascalAnalyzer, lExe, lCmdLine, lError));
    Assert.IsTrue(lError.Contains('PA_ARGS'), lError);
  finally
    DeleteTempPath(lRoot);
  end;
end;

function PalCmdSupportsFlag(const aPalCmdExe, aFlag: string): Boolean;
var
  lHelpPath: string;
  lExit: Cardinal;
  lText: string;
begin
  Result := False;
  lHelpPath := TPath.Combine(TempRoot, 'palcmd-help.txt');
  if FileExists(lHelpPath) then
    System.SysUtils.DeleteFile(lHelpPath);
  if not RunProcess(aPalCmdExe, '', RepoRoot, lHelpPath, lExit) then
    Exit(False);
  if not FileExists(lHelpPath) then
    Exit(False);
  lText := TFile.ReadAllText(lHelpPath);
  Result := Pos(UpperCase(aFlag), UpperCase(lText)) > 0;
end;

function TailFile(const aPath: string; const aMaxLines: Integer): string;
var
  lLines: TArray<string>;
  lStart: Integer;
  lCount: Integer;
begin
  if (aPath = '') or (not FileExists(aPath)) then
    Exit('');
  lLines := TFile.ReadAllLines(aPath);
  lCount := Length(lLines);
  if (aMaxLines <= 0) or (lCount <= aMaxLines) then
    Exit(String.Join(sLineBreak, lLines));
  lStart := lCount - aMaxLines;
  Result := String.Join(sLineBreak, Copy(lLines, lStart, aMaxLines));
end;

function DefaultPalThreads: Integer;
var
  lSys: TSystemInfo;
begin
  GetSystemInfo(lSys);
  Result := lSys.dwNumberOfProcessors;
  if Result < 1 then
    Result := 1;
  if Result > 64 then
    Result := 64;
end;

procedure TPascalAnalyzerTests.ProjectRunnerUsesExactNamedReportRoot;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.analyze.projectrunner.pas'), TEncoding.UTF8);
  Assert.IsTrue(lSource.Contains(
    'lPaReportRoot := TPath.Combine(fPal.OutputRoot, TPath.GetFileNameWithoutExtension(fParams.fProjectDpr));'),
    'Project analysis must construct the exact DAK-owned PAL report folder.');
  Assert.IsFalse(lSource.Contains('TryFindPalReportRoot(fPal.OutputRoot'),
    'Project analysis must not recursively select a report below the parent output root.');
end;

procedure TPascalAnalyzerTests.UnitCommandUsesProjectContext;
var
  lCmdLine: string;
  lEnvGuard: IInterface;
  lError: string;
  lExePath: string;
  lMapGuard: IInterface;
  lMapPath: string;
  lMapSource: string;
  lPa: TPascalAnalyzerDefaults;
  lParams: TFixInsightParams;
  lRunnerSource: string;
  lUnitPath: string;
begin
  lMapSource := TPath.Combine(RepoRoot, 'bin\palcmd-map.json');
  lMapGuard := SetScopedPalCmdMapFixture(TFile.ReadAllText(lMapSource, TEncoding.UTF8), lMapPath);
  lEnvGuard := SetScopedEnvironmentVariable('DAK_TEST_PAL_HELP', '1');
  lUnitPath := TPath.Combine(RepoRoot, 'src\dak.types.pas');

  lParams := Default(TFixInsightParams);
  lParams.fProjectDpr := lUnitPath;
  lParams.fDelphiVersion := '23.0';
  lParams.fPlatform := 'Win64';
  lParams.fConfig := 'Debug';
  lParams.fDefines := ['PROJECT_CONTEXT'];
  lParams.fUnitSearchPath := [TPath.Combine(RepoRoot, 'src')];

  lPa := Default(TPascalAnalyzerDefaults);
  lPa.fPath := ParamStr(0);
  lPa.fOutput := TempRoot;

  Assert.IsTrue(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError), lError);
  Assert.IsTrue(lCmdLine.Contains(QuoteArg(lUnitPath)), 'Unit PAL command must analyze the requested unit.');
  Assert.IsTrue(lCmdLine.Contains('/CD12W64'), 'Unit PAL command must use the project compiler target.');
  Assert.IsTrue(lCmdLine.Contains('/BUILD=Debug'), 'Unit PAL command must use the project build configuration.');
  Assert.IsTrue(lCmdLine.Contains('/D=PROJECT_CONTEXT'), 'Unit PAL command must use project defines.');
  Assert.IsTrue(lCmdLine.Contains('/S='), 'Unit PAL command must use project search paths.');

  lRunnerSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.analyze.unitrunner.pas'), TEncoding.UTF8);
  Assert.IsTrue(lRunnerSource.Contains('TryRunPalLogged(lUnitParams, fPascalAnalyzer'),
    'Project-context unit analysis must use the project-grade PAL runner.');
end;

procedure TPascalAnalyzerTests.ContextFreeUnitSummaryDeclaresPalIni;
var
  lPal: TPalSummary;
  lSummary: string;
begin
  lPal := Default(TPalSummary);
  lPal.Context := rsAnalyzeUnitPalIniContext;

  lSummary := BuildUnitSummary('Sample', 'C:\repo\Sample.pas', 'C:\repo\.dak\_unit\Sample', lPal, []);

  Assert.IsTrue(lSummary.Contains('PAL.INI supplied compiler context'));
  Assert.IsTrue(lSummary.Contains('not project-equivalent proof'));
end;

procedure TPascalAnalyzerTests.ProjectCommandOwnsReportName;
var
  lCmdLine: string;
  lEnvGuard: IInterface;
  lError: string;
  lExePath: string;
  lMapGuard: IInterface;
  lMapPath: string;
  lMapSource: string;
  lPa: TPascalAnalyzerDefaults;
  lParams: TFixInsightParams;
begin
  lMapSource := TPath.Combine(RepoRoot, 'bin\palcmd-map.json');
  lMapGuard := SetScopedPalCmdMapFixture(TFile.ReadAllText(lMapSource, TEncoding.UTF8), lMapPath);
  lEnvGuard := SetScopedEnvironmentVariable('DAK_TEST_PAL_HELP', '1');

  lParams := Default(TFixInsightParams);
  lParams.fProjectDpr := TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dpr');
  lParams.fDelphiVersion := '23.0';
  lParams.fPlatform := 'Win64';
  lParams.fConfig := 'Release';

  lPa := Default(TPascalAnalyzerDefaults);
  lPa.fPath := ParamStr(0);
  lPa.fOutput := TempRoot;

  Assert.IsTrue(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError), lError);
  Assert.IsTrue(lCmdLine.Contains('/NAME=DelphiAIKit'), 'Project PAL command must own the exact report name.');
end;

procedure TPascalAnalyzerTests.OwnedPalArgumentsAreRejected;
var
  lCmdLine: string;
  lEnvGuard: IInterface;
  lError: string;
  lExePath: string;
  lMapGuard: IInterface;
  lMapPath: string;
  lMapSource: string;
  lPa: TPascalAnalyzerDefaults;
  lParams: TFixInsightParams;
  lSwitch: string;
begin
  lMapSource := TPath.Combine(RepoRoot, 'bin\palcmd-map.json');
  lMapGuard := SetScopedPalCmdMapFixture(TFile.ReadAllText(lMapSource, TEncoding.UTF8), lMapPath);
  lEnvGuard := SetScopedEnvironmentVariable('DAK_TEST_PAL_HELP', '1');

  lParams := Default(TFixInsightParams);
  lParams.fProjectDpr := TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dpr');
  lParams.fDelphiVersion := '23.0';
  lParams.fPlatform := 'Win64';
  lParams.fConfig := 'Release';

  for lSwitch in ['/F=T', '/f=x', '/A-', '/FA', '/F+', '/FR', '/FM', '/F-', '/Q',
    '/R="C:\Some Path"', '/NAME=Other', '/T=1'] do
  begin
    lPa := Default(TPascalAnalyzerDefaults);
    lPa.fPath := ParamStr(0);
    lPa.fArgs := lSwitch;

    Assert.IsFalse(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError),
      'Expected DAK-owned PAL argument to be rejected: ' + lSwitch);
    Assert.IsTrue(lError.Contains('conflicts with DAK-owned automation'),
      'Expected a clear ownership diagnostic for ' + lSwitch + '. Actual: ' + lError);
  end;
end;

procedure TPascalAnalyzerTests.ExplicitPalExclusionsAreValidatedAndForwarded;
var
  lCmdLine: string;
  lEnvGuard: IInterface;
  lError: string;
  lExePath: string;
  lMapGuard: IInterface;
  lMapPath: string;
  lMapSource: string;
  lPa: TPascalAnalyzerDefaults;
  lParams: TFixInsightParams;
begin
  lMapSource := TPath.Combine(RepoRoot, 'bin\palcmd-map.json');
  lMapGuard := SetScopedPalCmdMapFixture(TFile.ReadAllText(lMapSource, TEncoding.UTF8), lMapPath);
  lEnvGuard := SetScopedEnvironmentVariable('DAK_TEST_PAL_HELP', '1');

  lParams := Default(TFixInsightParams);
  lParams.fProjectDpr := TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dpr');
  lParams.fDelphiVersion := '23.0';
  lParams.fPlatform := 'Win64';
  lParams.fConfig := 'Release';

  lPa := Default(TPascalAnalyzerDefaults);
  lPa.fPath := ParamStr(0);
  Assert.IsTrue(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError), lError);
  Assert.IsFalse(lCmdLine.Contains('/X='), 'DAK must not derive PAL /X from ownership or search paths.');
  Assert.IsFalse(lCmdLine.Contains('/XF='), 'DAK must not derive PAL /XF from ownership or search paths.');

  lPa.fExcludeSearchFolders := 'C:\Program Files (x86)\Vendor<+>;F:\Vendor<+>';
  lPa.fExcludeFiles := 'System.pas;Vendor.pas';
  Assert.IsTrue(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError), lError);
  Assert.IsTrue(lCmdLine.Contains('/X="C:\Program Files (x86)\Vendor<+>;F:\Vendor<+>"'), lCmdLine);
  Assert.IsTrue(lCmdLine.Contains('/XF=System.pas;Vendor.pas'), lCmdLine);

  Assert.IsTrue(BuildPalCmdUnitCommandLine(lParams.fProjectDpr, lPa, lExePath, lCmdLine, lError), lError);
  Assert.IsTrue(lCmdLine.Contains('/X="C:\Program Files (x86)\Vendor<+>;F:\Vendor<+>"'), lCmdLine);
  Assert.IsTrue(lCmdLine.Contains('/XF=System.pas;Vendor.pas'), lCmdLine);

  lPa.fExcludeSearchFolders := 'relative\Vendor<+>';
  Assert.IsFalse(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError),
    'PAL /X folders must be absolute.');
  Assert.IsTrue(lError.Contains('absolute'), lError);

  lPa.fExcludeSearchFolders := '';
  lPa.fExcludeFiles := 'System.pas;;Vendor.pas';
  Assert.IsFalse(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError),
    'PAL /XF lists must reject empty items.');
  Assert.IsTrue(lError.Contains('empty item'), lError);

  lPa := Default(TPascalAnalyzerDefaults);
  lPa.fPath := ParamStr(0);
  lPa.fArgs := '/X=C:\Vendor';
  Assert.IsFalse(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError),
    'Generic PAL arguments must not bypass the explicit /X contract.');
  lPa.fArgs := '/XF=System.pas';
  Assert.IsFalse(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError),
    'Generic PAL arguments must not bypass the explicit /XF contract.');
end;

procedure TPascalAnalyzerTests.ExtraArgumentsRetainAutomationDefaults;
var
  lCmdLine: string;
  lEnvGuard: IInterface;
  lError: string;
  lExePath: string;
  lMapGuard: IInterface;
  lMapPath: string;
  lMapSource: string;
  lPa: TPascalAnalyzerDefaults;
  lParams: TFixInsightParams;
begin
  lMapSource := TPath.Combine(RepoRoot, 'bin\palcmd-map.json');
  lMapGuard := SetScopedPalCmdMapFixture(TFile.ReadAllText(lMapSource, TEncoding.UTF8), lMapPath);
  lEnvGuard := SetScopedEnvironmentVariable('DAK_TEST_PAL_HELP', '1');

  lParams := Default(TFixInsightParams);
  lParams.fProjectDpr := TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dpr');
  lParams.fDelphiVersion := '23.0';
  lParams.fPlatform := 'Win64';
  lParams.fConfig := 'Release';

  lPa := Default(TPascalAnalyzerDefaults);
  lPa.fPath := ParamStr(0);
  lPa.fArgs := '/CUSTOM-SWITCH';

  Assert.IsTrue(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError), lError);
  Assert.IsTrue(lCmdLine.Contains('/F=X'), 'DAK-owned XML output must remain enabled.');
  Assert.IsTrue(lCmdLine.Contains('/Q'), 'DAK-owned quiet mode must remain enabled.');
  Assert.IsTrue(lCmdLine.Contains('/A+'), 'DAK-owned source/form parsing must remain enabled.');
  Assert.IsTrue(lCmdLine.Contains('/FA'), 'DAK-owned all-file parsing must remain enabled.');
  Assert.IsTrue(lCmdLine.Contains('/T=' + DefaultPalThreads.ToString), 'DAK-owned default thread count must remain enabled.');
  Assert.IsTrue(lCmdLine.Contains('/CUSTOM-SWITCH'), 'Non-conflicting extra arguments must be preserved.');
end;

procedure TPascalAnalyzerTests.Delphi13CommandUsesMappedCompilerFlags;
var
  lCmdLine: string;
  lEnvGuard: IInterface;
  lError: string;
  lExePath: string;
  lExpected: string;
  lMapGuard: IInterface;
  lMapPath: string;
  lMapSource: string;
  lPa: TPascalAnalyzerDefaults;
  lParams: TFixInsightParams;
  lPlatform: string;
begin
  lMapSource := TPath.Combine(RepoRoot, 'bin\palcmd-map.json');
  lMapGuard := SetScopedPalCmdMapFixture(TFile.ReadAllText(lMapSource, TEncoding.UTF8), lMapPath);
  lEnvGuard := SetScopedEnvironmentVariable('DAK_TEST_PAL_HELP', '1');

  for lPlatform in ['Win32', 'Win64'] do
  begin
    lParams := Default(TFixInsightParams);
    lParams.fProjectDpr := TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dpr');
    lParams.fDelphiVersion := '37.0';
    lParams.fPlatform := lPlatform;
    lParams.fConfig := 'Release';

    lPa := Default(TPascalAnalyzerDefaults);
    lPa.fPath := ParamStr(0);

    if SameText(lPlatform, 'Win32') then
      lExpected := '/CD13W32'
    else begin
      lExpected := '/CD13W64';
    end;

    Assert.IsTrue(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError), lError);
    Assert.IsTrue(lCmdLine.Contains(lExpected),
      Format('Expected %s for BDS 37 %s. Actual: %s', [lExpected, lPlatform, lCmdLine]));
  end;

  lParams.fDelphiVersion := '23.0';
  lParams.fPlatform := 'Win64';
  Assert.IsTrue(BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError), lError);
  Assert.IsTrue(lCmdLine.Contains('/CD12W64'), 'Existing BDS 23 mapping must remain Delphi 12 Win64.');
end;

procedure TPascalAnalyzerTests.SelectsSupportedCompilerFlag;
var
  lPalCmdExe: string;
  lParams: TFixInsightParams;
  lPa: TPascalAnalyzerDefaults;
  lExe: string;
  lCmdLine: string;
  lFlag: string;
  lError: string;
  lPos: Integer;
  lEnd: Integer;
  lMapGuard: IInterface;
  lMapSource: string;
  lMapPath: string;
  lPhase: string;
begin
  lPhase := 'resolve PALCMD';
  try
    RequirePalCmdOrSkip(lPalCmdExe);
    lMapSource := TPath.Combine(RepoRoot, 'bin\\palcmd-map.json');
    lPhase := 'prepare isolated PALCMD map';
    if FileExists(lMapSource) then
      lMapGuard := SetScopedPalCmdMapFixture(TFile.ReadAllText(lMapSource, TEncoding.UTF8), lMapPath);
    lPhase := 'build command line';
    lParams := Default(TFixInsightParams);
    lParams.fProjectDpr := TPath.Combine(RepoRoot, 'projects\\DelphiAIKit.dpr');
    lParams.fDelphiVersion := '23.0';
    lParams.fPlatform := 'Win32';
    lParams.fConfig := 'Release';

    lPa := Default(TPascalAnalyzerDefaults);
    lPa.fPath := lPalCmdExe;

    if not BuildPalCmdCommandLine(lParams, lPa, lExe, lCmdLine, lError) then
      Assert.Fail('BuildPalCmdCommandLine failed: ' + lError);

    lPhase := 'extract PALCMD flag';
    lFlag := '';
    lPos := Pos('/CD', UpperCase(lCmdLine));
    if lPos > 0 then
    begin
      lEnd := lPos;
      while (lEnd <= Length(lCmdLine)) and (lCmdLine[lEnd] > ' ') do
        Inc(lEnd);
      lFlag := Copy(lCmdLine, lPos, lEnd - lPos);
    end;

    Assert.IsTrue(lFlag <> '', 'PALCMD flag selection returned empty flag.');
    lPhase := 'verify PALCMD selected flag';
    Assert.IsTrue(PalCmdSupportsFlag(lPalCmdExe, lFlag), 'PALCMD help does not list flag: ' + lFlag);
    lPhase := 'verify Delphi 12 PALCMD flag';
    if PalCmdSupportsFlag(lPalCmdExe, '/CD12W32') then
      Assert.AreEqual('/CD12W32', lFlag, 'PALCMD supports Delphi 12, but a different flag was selected.');
  except
    on E: Exception do
      Assert.Fail(lPhase + ' failed: ' + E.Message);
  end;
  lMapGuard := nil;
end;

procedure TPascalAnalyzerTests.RunPascalAnalyzer;
var
  lPalCmdExe: string;
  lOutDir: string;
  lPaOutDir: string;
  lArgs: string;
  lExit: Cardinal;
  lFiles: TArray<string>;
  lLog: string;
  lTail: string;
begin
  EnsureResolverBuilt;
  RequirePalCmdOrSkip(lPalCmdExe);
  if not PalCmdSupportsFlag(lPalCmdExe, '/CD12W32') then
  begin
    Assert.Pass('PALCMD does not list /CD12W32; skipping integration run. Flag selection is covered by SelectsSupportedCompilerFlag.');
    Exit;
  end;

  lOutDir := TPath.Combine(TempRoot, 'pa-run');
  if not TDirectory.Exists(lOutDir) then
    TDirectory.CreateDirectory(lOutDir);

  // --pa-output relocates only the raw PAL XML reports; the finalized report reads the normalized
  // rows from its own pascal-analyzer folder (T-343).
  lPaOutDir := TPath.Combine(TempRoot, 'pa-run-xml');
  lArgs := 'analyze --project ' + QuoteArg(TPath.Combine(RepoRoot, 'projects\\DelphiAIKit.dproj')) +
    ' --platform Win32 --config Release --delphi 23.0 --fixinsight false --pascal-analyzer true' +
    ' --out ' + QuoteArg(lOutDir) +
    ' --pa-path ' + QuoteArg(lPalCmdExe) +
    ' --pa-output ' + QuoteArg(lPaOutDir);

  lLog := TPath.Combine(lOutDir, 'pascal-analyzer.log');
  if not RunResolverProcess(lArgs, RepoRoot, lLog, lExit) then
    Assert.Fail('Failed to start Pascal Analyzer run: ' + lLog);
  if lExit <> 0 then
  begin
    lTail := TailFile(lLog, 30);
    if lTail <> '' then
      lTail := sLineBreak + '--- PALCMD log tail ---' + sLineBreak + lTail;
    Assert.Fail('Pascal Analyzer run failed, exit=' + lExit.ToString + '. See: ' + lLog + lTail);
  end;

  lFiles := TDirectory.GetFiles(lPaOutDir, '*.xml', TSearchOption.soAllDirectories);
  Assert.IsTrue(Length(lFiles) > 0, 'No XML report produced under: ' + lPaOutDir);
  Assert.IsTrue(TFile.Exists(TPath.Combine(lOutDir, 'pascal-analyzer\pal-findings.jsonl')),
    'The normalized rows publish in the report.');
  Assert.IsTrue(TFile.Exists(TPath.Combine(lOutDir, 'pascal-analyzer\pal-hotspots.md')),
    'The hotspots publish in the report.');
  Assert.IsFalse(TFile.Exists(TPath.Combine(lPaOutDir, 'pal-findings.jsonl')),
    'Nothing normalized is left beside the raw reports.');
end;

procedure TPascalAnalyzerTests.PascalAnalyzerProcessWaitsAreBounded;
var
  lPath: string;
  lText: string;
begin
  lPath := TPath.Combine(RepoRoot, 'src\dak.pascalanalyzerrunner.pas');
  lText := TFile.ReadAllText(lPath, TEncoding.UTF8);
  Assert.IsFalse(TRegEx.IsMatch(lText, 'WaitForSingleObject\s*\([^,]+,\s*INFINITE\s*\)', [roIgnoreCase]),
    'Pascal Analyzer subprocess waits must use bounded timeouts.');
end;

procedure TPascalAnalyzerTests.PascalAnalyzerTimeoutTerminatesChildProcess;
var
  lError: string;
  lExit: Cardinal;
  lProcess: THandle;
  lThread: THandle;
begin
  Assert.IsTrue(StartSlowPingProcess(lProcess, lThread, lError), lError);
  try
    Assert.IsFalse(TryWaitForExternalToolProcess('PALCMD', lProcess, 1, lExit, lError), 'Expected timeout failure.');
    Assert.AreEqual(Cardinal(cExternalToolTimeoutExitCode), lExit, 'Timeout exit code should be deterministic.');
    Assert.IsTrue(Pos('PALCMD timed out after 1 seconds.', lError) > 0,
      'Timeout diagnostic should name PALCMD. Actual: ' + lError);
    Assert.IsTrue(WaitForSingleObject(lProcess, 0) = WAIT_OBJECT_0,
      'Timeout handling should terminate the child process.');
  finally
    if (lProcess <> 0) and (WaitForSingleObject(lProcess, 0) <> WAIT_OBJECT_0) then
      TerminateProcess(lProcess, 1);
    if lThread <> 0 then
      CloseHandle(lThread);
    if lProcess <> 0 then
      CloseHandle(lProcess);
  end;
end;

procedure TPascalAnalyzerTests.PascalAnalyzerHelpProbeTimeoutIsConfigurable;
var
  lPath: string;
  lText: string;
begin
  lPath := TPath.Combine(RepoRoot, 'src\dak.pascalanalyzerrunner.pas');
  lText := TFile.ReadAllText(lPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('TryCaptureProcessOutput(const aExe, aArgs: string; aTimeoutSec: Integer', lText) > 0,
    'PALCMD help capture should accept the configured Pascal Analyzer timeout.');
  Assert.IsFalse(Pos('ResolveExternalToolTimeoutMs(0)', lText) > 0,
    'PALCMD help capture should not hard-code the built-in timeout.');
  Assert.IsFalse(Pos('ResolveExternalToolTimeoutSec(0)', lText) > 0,
    'PALCMD help diagnostics should report the configured timeout.');
  Assert.IsTrue(Pos('if lHelpTimedOut then', lText) > 0,
    'PALCMD help timeout should fail instead of falling back to version mapping.');
end;

procedure TPascalAnalyzerTests.InvalidPalMapJsonRootDoesNotRaise;
var
  lCmdLine: string;
  lCmdExe: string;
  lError: string;
  lExecutableMapExists: Boolean;
  lExecutableMapPath: string;
  lExecutableMapText: string;
  lExePath: string;
  lMapGuard: IInterface;
  lMapPath: string;
  lPa: TPascalAnalyzerDefaults;
  lParams: TFixInsightParams;
  lSuccess: Boolean;
begin
  lExecutableMapPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'palcmd-map.json');
  lExecutableMapExists := FileExists(lExecutableMapPath);
  if lExecutableMapExists then
    lExecutableMapText := TFile.ReadAllText(lExecutableMapPath, TEncoding.UTF8)
  else
    lExecutableMapText := '';
  lMapGuard := SetScopedPalCmdMapFixture('[]', lMapPath);

  try
    lParams := Default(TFixInsightParams);
    lParams.fProjectDpr := TPath.Combine(RepoRoot, 'projects\\DelphiAIKit.dpr');
    lParams.fDelphiVersion := '23.0';
    lParams.fPlatform := 'Win32';
    lParams.fConfig := 'Release';

    lPa := Default(TPascalAnalyzerDefaults);
    lCmdExe := GetEnvironmentVariable('ComSpec');
    if lCmdExe = '' then
      lCmdExe := 'C:\Windows\System32\cmd.exe';
    lPa.fPath := lCmdExe;

    lSuccess := BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError);
    Assert.IsFalse(lSuccess, 'Expected BuildPalCmdCommandLine to fail for invalid map root.');
    Assert.IsTrue(lError <> '', 'Expected error details for invalid map root.');
    Assert.IsTrue(Pos(TPath.GetFullPath(lMapPath), lError) > 0,
      'Expected invalid map error to reference the isolated temp map path. Actual: ' + lError);
    Assert.IsTrue(FileExists(lExecutableMapPath) = lExecutableMapExists,
      'PascalAnalyzer tests must not create or delete executable-local palcmd-map.json.');
    if lExecutableMapExists then
      Assert.AreEqual(lExecutableMapText, TFile.ReadAllText(lExecutableMapPath, TEncoding.UTF8),
        'PascalAnalyzer tests must not rewrite executable-local palcmd-map.json.');
  finally
    lMapGuard := nil;
  end;
end;

procedure TPascalAnalyzerTests.BuildPalCmdCommandLineUnsupportedPlatformReturnsError;
var
  lCmdExe: string;
  lCmdLine: string;
  lError: string;
  lExePath: string;
  lParams: TFixInsightParams;
  lPa: TPascalAnalyzerDefaults;
  lSuccess: Boolean;
begin
  lParams := Default(TFixInsightParams);
  lParams.fProjectDpr := TPath.Combine(RepoRoot, 'projects\\DelphiAIKit.dpr');
  lParams.fDelphiVersion := '23.0';
  lParams.fPlatform := 'Linux64';
  lParams.fConfig := 'Release';

  lPa := Default(TPascalAnalyzerDefaults);
  lCmdExe := GetEnvironmentVariable('ComSpec');
  if lCmdExe = '' then
    lCmdExe := 'C:\Windows\System32\cmd.exe';
  lPa.fPath := lCmdExe;

  lSuccess := BuildPalCmdCommandLine(lParams, lPa, lExePath, lCmdLine, lError);
  Assert.IsFalse(lSuccess, 'Expected unsupported platform to be rejected for PALCMD command line generation.');
  Assert.IsTrue(lError <> '', 'Expected unsupported platform failure to include a concrete error message.');
  Assert.IsTrue(Pos('Unsupported platform', lError) > 0,
    'Expected unsupported platform error details. Actual: ' + lError);
end;

procedure TPascalAnalyzerTests.PascalAnalyzerRunnerDelegatesArtifactGeneration;
var
  lArtifactsPath: string;
  lArtifactsSource: string;
  lRunnerSource: string;
begin
  lRunnerSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.pascalanalyzerrunner.pas'),
    TEncoding.UTF8);
  lArtifactsPath := TPath.Combine(RepoRoot, 'src\Dak.PascalAnalyzer.Artifacts.pas');
  Assert.IsTrue(TFile.Exists(lArtifactsPath), 'Expected PAL artifact generation to live in a focused unit.');
  lArtifactsSource := TFile.ReadAllText(lArtifactsPath, TEncoding.UTF8);

  Assert.IsFalse(lRunnerSource.Contains('TPalFinding = record'),
    'Pascal Analyzer runner must not own PAL finding DTOs.');
  Assert.IsFalse(lRunnerSource.Contains('THotspotEntry = record'),
    'Pascal Analyzer runner must not own PAL hotspot DTOs.');
  Assert.IsFalse(lRunnerSource.Contains('TryLoadComplexityEntries'),
    'Pascal Analyzer runner must not parse PAL complexity artifacts directly.');
  Assert.IsFalse(lRunnerSource.Contains('TryLoadModuleLines'),
    'Pascal Analyzer runner must not parse PAL module totals directly.');
  Assert.IsFalse(lRunnerSource.Contains('WritePalFindingsJsonl'),
    'Pascal Analyzer runner must not write PAL findings JSONL directly.');
  Assert.IsFalse(lRunnerSource.Contains('WritePalHotspotsMd'),
    'Pascal Analyzer runner must not write PAL hotspot markdown directly.');

  Assert.IsTrue(lArtifactsSource.Contains('TPalFinding = record'),
    'PAL artifact unit should own finding DTOs.');
  Assert.IsTrue(lArtifactsSource.Contains('THotspotEntry = record'),
    'PAL artifact unit should own hotspot DTOs.');
  Assert.IsTrue(lArtifactsSource.Contains('TryLoadComplexityEntries'),
    'PAL artifact unit should own complexity parsing.');
  Assert.IsTrue(lArtifactsSource.Contains('TryLoadModuleLines'),
    'PAL artifact unit should own module-line parsing.');
  Assert.IsTrue(lArtifactsSource.Contains('WritePalFindingsJsonl'),
    'PAL artifact unit should own findings JSONL writing.');
  Assert.IsTrue(lArtifactsSource.Contains('WritePalHotspotsMd'),
    'PAL artifact unit should own hotspot markdown writing.');
  Assert.IsTrue(lRunnerSource.Contains('Dak.PascalAnalyzer.Artifacts'),
    'Runner should delegate artifact generation to the focused unit.');
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalAnalyzerTests);

end.
