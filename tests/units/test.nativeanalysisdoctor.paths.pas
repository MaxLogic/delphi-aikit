unit Test.NativeAnalysisDoctor.Paths;
interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisDoctorPathTests = class
  public
    [TestCase('Executable', 'false')]
    [TestCase('Directory', 'true')]
    procedure ResolverExpandsWindowsEnvironment(aDirectory: Boolean);
    [Test]
    procedure RelativeOverrideUsesOwningExecutableDirectory;
    [Test]
    procedure LiveDelphi13ReportsResolvedPathArchitectureAndCapabilities;
  end;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.PascalAnalyzerRunner,
  Test.Support;

procedure TNativeAnalysisDoctorPathTests.ResolverExpandsWindowsEnvironment(aDirectory: Boolean);
var
  lEnvironment: IInterface;
  lError: string;
  lExpected: string;
  lInput: string;
  lResolved: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('pal-path environment');
  TDirectory.CreateDirectory(lRoot);
  try
    lExpected := TPath.Combine(lRoot, 'PALCMD.exe');
    // Existence-only resolver fixture; this file is never executed as a vendor process.
    TFile.WriteAllText(lExpected, 'resolver existence fixture', TEncoding.ASCII);
    lEnvironment := SetScopedEnvironmentVariables(['DAK_TEST_PAL_PATH_ROOT', lRoot]);
    lInput := '%DAK_TEST_PAL_PATH_ROOT%';
    if not aDirectory then
      lInput := lInput + '\PALCMD.exe';
    Assert.IsTrue(TryResolvePalCmdExe(lInput, lResolved, lError), lError);
    Assert.AreEqual(lExpected, lResolved);
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisDoctorPathTests.RelativeOverrideUsesOwningExecutableDirectory;
var
  lError: string;
  lExeDir: string;
  lExpected: string;
  lOriginalDir: string;
  lRelative: string;
  lResolved: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('pal-relative-base');
  TDirectory.CreateDirectory(lRoot);
  lOriginalDir := GetCurrentDir;
  try
    lExpected := TPath.Combine(lRoot, 'PALCMD.exe');
    // Existence-only resolver fixture; no process launch uses this file.
    TFile.WriteAllText(lExpected, 'resolver existence fixture', TEncoding.ASCII);
    lExeDir := ExtractFilePath(ParamStr(0));
    lRelative := ExtractRelativePath(lExeDir, lExpected);
    Assert.IsFalse(TPath.IsPathRooted(lRelative), 'Fixture must remain relative to the owning test executable');
    Assert.IsTrue(SetCurrentDir(lRoot));
    Assert.IsFalse(SameText(TPath.GetFullPath(lRelative), TPath.GetFullPath(lExpected)),
      'Caller CWD must differ from the executable-directory interpretation');
    Assert.IsTrue(TryResolvePalCmdExe(lRelative, lResolved, lError), lError);
    Assert.AreEqual(TPath.GetFullPath(lExpected), TPath.GetFullPath(lResolved));
  finally
    Assert.IsTrue(SetCurrentDir(lOriginalDir));
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisDoctorPathTests.LiveDelphi13ReportsResolvedPathArchitectureAndCapabilities;
var
  g: TGarbos;
  lCheck: TJSONValue;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lError: string;
  lExe: string;
  lExitCode: Cardinal;
  lFlag: TJSONValue;
  lHasDelphi12: Boolean;
  lHasDelphi13: Boolean;
  lHelp: TJSONObject;
  lLog: string;
  lOutput: string;
  lPalPath: string;
  lPathCheck: TJSONObject;
  lProject: string;
  lRoot: string;
  lTarget: TJSONObject;
begin
  lRoot := UniqueTempPath('doctor-delphi13-live');
  TDirectory.CreateDirectory(lRoot);
  try
    lEnvironment := SetScopedEnvironmentVariables(['PA_PATH', '', 'PA_ARGS', '', 'DAK_DELPHI', '',
      'DAK_PLATFORM', '', 'DAK_OUT', '', 'DAK_DOCTOR_RUN', '', 'DAK_PALCMD_MAP_PATH', '']);
    Assert.IsTrue(TryResolvePalCmdExe('', lPalPath, lError), 'Installed real PAL is required: ' + lError);
    lProject := TPath.Combine(lRoot, 'DoctorDelphi13.dproj');
    TFile.WriteAllText(lProject, '<Project/>', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(lRoot, 'dak.ini'), '[PascalAnalyzer]' + sLineBreak +
      'Path=' + lPalPath, TEncoding.UTF8);
    lExe := ResolverExePath;
    Assert.IsTrue(TFile.Exists(lExe), 'Expected coordinator-provided candidate: ' + lExe);
    lLog := TPath.Combine(lRoot, 'doctor.log');
    Assert.IsTrue(RunCommandProcess(lExe, 'analyze-doctor --project ' + QuoteArg(lProject) +
      ' --workspace-root ' + QuoteArg(lRoot) + ' --delphi 37.0 --platform Win64 --run-checks true --json',
      lRoot, lLog, lExitCode));
    lOutput := ReadUtf8TextFile(lLog);
    Assert.AreEqual<Cardinal>(0, lExitCode, lOutput);
    GC(lDocument, ParseJsonObject(lOutput, 'Live Delphi 13 doctor capabilities'), g);
    lPathCheck := nil;
    lHelp := nil;
    lTarget := nil;
    for lCheck in lDocument.GetValue<TJSONArray>('checks') do
    begin
      if lCheck.GetValue<string>('name') = 'pal_path' then
        lPathCheck := lCheck as TJSONObject;
      if lCheck.GetValue<string>('name') = 'pal_help' then
        lHelp := lCheck as TJSONObject;
      if lCheck.GetValue<string>('name') = 'pal_target' then
        lTarget := lCheck as TJSONObject;
    end;
    Assert.IsNotNull(lPathCheck);
    Assert.AreEqual(lPalPath, lPathCheck.GetValue<string>('path'));
    Assert.IsNotNull(lHelp);
    Assert.AreEqual('available', lHelp.GetValue<string>('status'));
    Assert.AreEqual('64-bit', lHelp.GetValue<string>('architecture'));
    lHasDelphi12 := False;
    lHasDelphi13 := False;
    for lFlag in lHelp.GetValue<TJSONArray>('supported_flags') do
    begin
      lHasDelphi12 := lHasDelphi12 or (lFlag.Value = '/CD12W64');
      lHasDelphi13 := lHasDelphi13 or (lFlag.Value = '/CD13W64');
    end;
    Assert.IsTrue(lHasDelphi12, 'Real PAL must advertise Delphi 12 Win64');
    Assert.IsTrue(lHasDelphi13, 'Real PAL must advertise Delphi 13 Win64');
    Assert.IsNotNull(lTarget);
    Assert.AreEqual('37.0', lTarget.GetValue<string>('bds_version'));
    Assert.AreEqual('13', lTarget.GetValue<string>('delphi'));
    Assert.AreEqual('Win64', lTarget.GetValue<string>('platform'));
    Assert.AreEqual('/CD13W64', lTarget.GetValue<string>('flag'));
    Assert.AreEqual('supported', lTarget.GetValue<string>('status'));
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(lRoot, '.dak')));
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisDoctorPathTests);
end.
