unit Test.NativeAnalysisDoctor.Remaining;

interface

uses
  System.JSON,
  DUnitX.TestFramework;

type
  [TestFixture]
  TNativeAnalysisDoctorRemainingTests = class
  private
    fRoot: string;
    fProject: string;
    fConfig: string;
    fEnvironment: IInterface;
    function RunDoctor(const aOptions: string; aExpectedExit: Cardinal = 0): string;
    function LiveChecks(const aExtraIni: string): TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure HumanPreviewShowsEffectiveValuesTargetAndSource;
    [Test]
    procedure JsonEnvironmentPreservesRawLegacyValues;
    [Test]
    procedure MissingConfiguredFixInsightIsOptionalWithWorkingPal;
    [Test]
    procedure CompilerWithoutRequestedTargetIsNotRequested;
    [Test]
    procedure MissingCompilerConfigurationIsOptionalWithSupportedPal;
    [TestCase('InstalledConfiguration', '23.0,available,0')]
    [TestCase('MissingConfiguration', '999.0,unavailable,3')]
    procedure RequestedCompilerConfiguration(const aVersion, aStatus: string; aExpectedExit: Cardinal);
    [TestCase('DefaultDoctorTimeout', '0,15')]
    [TestCase('ExplicitTimeout', '1,1')]
    procedure PalHelpReportsEffectiveDoctorTimeout(aConfigured, aExpected: Integer);
  end;

implementation

uses
  System.IOUtils, System.SysUtils,
  AutoFree,
  Dak.PascalAnalyzerRunner,
  Test.Support;

function RequireCheck(const aDocument: TJSONObject; const aName: string): TJSONObject;
var
  lCheck: TJSONValue;
  lChecks: TJSONArray;
begin
  Result := nil;
  RequireJsonArrayKey(aDocument, 'checks', lChecks);
  for lCheck in lChecks do
    if lCheck.GetValue<string>('name') = aName then
      Exit(lCheck as TJSONObject);
  Assert.Fail('Expected doctor check: ' + aName);
end;

procedure TNativeAnalysisDoctorRemainingTests.Setup;
begin
  fRoot := UniqueTempPath('doctor-remaining');
  TDirectory.CreateDirectory(fRoot);
  fProject := TPath.Combine(fRoot, 'DoctorRemaining.dproj');
  fConfig := TPath.Combine(fRoot, 'dak.ini');
  TFile.WriteAllText(fProject, '<Project/>', TEncoding.ASCII);
  fEnvironment := SetScopedEnvironmentVariables([
    'DAK_DOCTOR_RUN', '', 'DAK_DELPHI', '', 'DAK_PLATFORM', '', 'DAK_CONFIG', '',
    'DAK_GATE', '', 'DAK_CI', '', 'DAK_OUT', '', 'DAK_WORKSPACE_ROOT', '',
    'DAK_FIXINSIGHT', '', 'DAK_PASCAL_ANALYZER', '', 'DAK_PAL', '', 'PA_PATH', '', 'PA_ARGS', '']);
end;

procedure TNativeAnalysisDoctorRemainingTests.TearDown;
begin
  fEnvironment := nil;
  DeleteTempPath(fRoot);
end;

function TNativeAnalysisDoctorRemainingTests.RunDoctor(const aOptions: string; aExpectedExit: Cardinal): string;
var
  lExePath: string;
  lExitCode: Cardinal;
  lLog: string;
begin
  lExePath := ResolverExePath;
  Assert.IsTrue(TFile.Exists(lExePath), 'Expected coordinator-provided DAK candidate: ' + lExePath);
  lLog := TPath.Combine(fRoot, 'doctor.log');
  Assert.IsTrue(RunCommandProcess(lExePath, 'analyze-doctor --project ' + QuoteArg(fProject) +
    ' --workspace-root ' + QuoteArg(fRoot) + ' ' + aOptions, fRoot, lLog, lExitCode));
  Result := ReadUtf8TextFile(lLog);
  Assert.AreEqual<Cardinal>(aExpectedExit, lExitCode, Result);
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(fRoot, '.dak')), 'Doctor must not create analysis state');
end;

function TNativeAnalysisDoctorRemainingTests.LiveChecks(const aExtraIni: string): TJSONObject;
var
  lError: string;
  lMissingFi: string;
  lPalPath: string;
begin
  Assert.IsTrue(TryResolvePalCmdExe('', lPalPath, lError), 'Installed real PAL is required: ' + lError);
  lMissingFi := TPath.Combine(fRoot, 'missing-FixInsightCL.exe');
  Assert.IsFalse(TFile.Exists(lMissingFi));
  TFile.WriteAllText(fConfig, '[FixInsightCL]' + sLineBreak + 'Path=' + lMissingFi + sLineBreak +
    '[PascalAnalyzer]' + sLineBreak + 'Path=' + lPalPath + sLineBreak + aExtraIni, TEncoding.UTF8);
  Result := ParseJsonObject(RunDoctor('--run-checks true --json'), 'Live doctor remaining checks');
end;

procedure TNativeAnalysisDoctorRemainingTests.HumanPreviewShowsEffectiveValuesTargetAndSource;
var
  lOutput: string;
begin
  TFile.WriteAllText(fConfig, '[FixInsightCL]' + sLineBreak + 'Silent=false' + sLineBreak +
    'Settings=human-preview-settings.ficfg' + sLineBreak +
    '[ReportFilter]' + sLineBreak + 'ExcludePathMasks=human-generated;human-vendor' + sLineBreak +
    '[PascalAnalyzer]' + sLineBreak + 'Path=human-missing-pal.exe' + sLineBreak +
    'Args=/CD12W64', TEncoding.UTF8);
  lOutput := RunDoctor('--run-checks false');
  Assert.IsTrue(Pos('human-preview-settings.ficfg', lOutput) > 0, lOutput);
  Assert.IsTrue(Pos('human-generated;human-vendor', lOutput) > 0, lOutput);
  Assert.IsTrue(Pos('human-missing-pal.exe', lOutput) > 0, lOutput);
  Assert.IsTrue(Pos('/CD12W64', lOutput) > 0, lOutput);
  Assert.IsTrue(Pos(fProject, lOutput) > 0, 'Human output must show target path: ' + lOutput);
  Assert.IsTrue(Pos(fConfig, lOutput) > 0, 'Human output must show settings source path: ' + lOutput);
end;

procedure TNativeAnalysisDoctorRemainingTests.JsonEnvironmentPreservesRawLegacyValues;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lRaw: TJSONObject;
  lSettings: TJSONObject;
begin
  lEnvironment := SetScopedEnvironmentVariables([
    'DAK_CONFIG', 'ReleasePreview', 'DAK_GATE', 'not-a-boolean', 'DAK_OUT', 'preview-output']);
  try
    GC(lDocument, ParseJsonObject(RunDoctor('--run-checks false --json'), 'Legacy environment preview'), g);
    RequireJsonObjectKey(lDocument, 'settings', lSettings);
    RequireJsonObjectKey(lSettings, 'environment', lRaw);
    RequireJsonStringKey(lRaw, 'DAK_CONFIG');
    RequireJsonStringKey(lRaw, 'DAK_GATE');
    RequireJsonStringKey(lRaw, 'DAK_OUT');
    Assert.AreEqual('ReleasePreview', lRaw.GetValue<string>('DAK_CONFIG'));
    Assert.AreEqual('not-a-boolean', lRaw.GetValue<string>('DAK_GATE'));
    Assert.AreEqual('preview-output', lRaw.GetValue<string>('DAK_OUT'));
    Assert.AreEqual<Integer>(0, lDocument.GetValue<Integer>('exit_code'));
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(fRoot, 'preview-output')));
  finally
    lEnvironment := nil;
  end;
end;

procedure TNativeAnalysisDoctorRemainingTests.MissingConfiguredFixInsightIsOptionalWithWorkingPal;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lFixInsight: TJSONObject;
  lPal: TJSONObject;
begin
  GC(lDocument, LiveChecks(''), g);
  lFixInsight := RequireCheck(lDocument, 'fixinsight');
  Assert.AreEqual('unavailable', lFixInsight.GetValue<string>('status'));
  lPal := RequireCheck(lDocument, 'pal_help');
  Assert.AreEqual('available', lPal.GetValue<string>('status'));
  Assert.AreEqual<Integer>(0, lPal.GetValue<Integer>('exit_code'));
  Assert.AreEqual<Integer>(0, lDocument.GetValue<Integer>('exit_code'));
end;

procedure TNativeAnalysisDoctorRemainingTests.CompilerWithoutRequestedTargetIsNotRequested;
var
  g: TGarbos;
  lCompiler: TJSONObject;
  lDocument: TJSONObject;
begin
  GC(lDocument, LiveChecks(''), g);
  lCompiler := RequireCheck(lDocument, 'compiler');
  Assert.AreEqual('not_requested', lCompiler.GetValue<string>('status'));
end;

procedure TNativeAnalysisDoctorRemainingTests.PalHelpReportsEffectiveDoctorTimeout(aConfigured, aExpected: Integer);
var
  g: TGarbos;
  lDocument: TJSONObject;
  lExtraIni: string;
  lHelp: TJSONObject;
begin
  lExtraIni := '';
  if aConfigured > 0 then
    lExtraIni := 'TimeoutSec=' + IntToStr(aConfigured) + sLineBreak;
  GC(lDocument, LiveChecks(lExtraIni), g);
  lHelp := RequireCheck(lDocument, 'pal_help');
  RequireJsonNumberKey(lHelp, 'timeout_seconds');
  Assert.AreEqual<Integer>(aExpected, lHelp.GetValue<Integer>('timeout_seconds'));
  Assert.AreEqual('available', lHelp.GetValue<string>('status'));
end;

procedure TNativeAnalysisDoctorRemainingTests.RequestedCompilerConfiguration(
  const aVersion, aStatus: string; aExpectedExit: Cardinal);
var
  g: TGarbos;
  lCompiler: TJSONObject;
  lDocument: TJSONObject;
  lError: string;
  lPalPath: string;
begin
  Assert.IsTrue(TryResolvePalCmdExe('', lPalPath, lError), 'Installed real PAL is required: ' + lError);
  GC(lDocument, ParseJsonObject(RunDoctor('--json --run-checks true --pa-path ' + QuoteArg(lPalPath) +
    ' --delphi ' + aVersion + ' --platform Win64', aExpectedExit), 'Compiler configuration check'), g);
  lCompiler := RequireCheck(lDocument, 'compiler');
  Assert.AreEqual(aStatus, lCompiler.GetValue<string>('status'));
  Assert.AreEqual('configuration', lCompiler.GetValue<string>('kind'));
  Assert.AreEqual(aVersion, lCompiler.GetValue<string>('bds_version'));
  Assert.AreEqual('Win64', lCompiler.GetValue<string>('platform'));
  if aStatus = 'available' then
  begin
    Assert.IsTrue(lCompiler.GetValue<string>('library_path') <> '');
    Assert.IsTrue(lCompiler.GetValue<string>('source') <> '');
  end else begin
    Assert.IsTrue(lCompiler.GetValue<string>('error') <> '');
  end;
end;

procedure TNativeAnalysisDoctorRemainingTests.MissingCompilerConfigurationIsOptionalWithSupportedPal;
var
  g: TGarbos;
  lCompiler: TJSONObject;
  lConfigRoot: string;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lError: string;
  lHelp: TJSONObject;
  lItem: TJSONValue;
  lMap: TJSONObject;
  lMapPath: string;
  lMappings: TJSONArray;
  lPalPath: string;
  lTarget: TJSONObject;
begin
  Assert.IsTrue(TryResolvePalCmdExe('', lPalPath, lError), 'Installed real PAL is required: ' + lError);
  lMapPath := TPath.Combine(fRoot, 'compiler-optional-map.json');
  TFile.Copy(TPath.Combine(RepoRoot, 'bin\palcmd-map.json'), lMapPath);
  GC(lMap, ParseJsonObject(ReadUtf8TextFile(lMapPath), 'Copied PAL mapping'), g);
  RequireJsonArrayKey(lMap, 'bdsToDelphi', lMappings);
  for lItem in lMappings do
    Assert.AreNotEqual<Integer>(999, lItem.GetValue<Integer>('bdsMajor'),
      'Fixture BDS version must not already have a mapping');
  lMappings.AddElement(TJSONObject.Create
    .AddPair('bdsMajor', TJSONNumber.Create(999))
    .AddPair('delphi', '12'));
  TFile.WriteAllText(lMapPath, lMap.ToJSON, TEncoding.UTF8);

  lConfigRoot := TPath.Combine(fRoot, 'missing-ide-configuration');
  TDirectory.CreateDirectory(lConfigRoot);
  Assert.IsFalse(TFile.Exists(TPath.Combine(lConfigRoot, 'EnvOptions.proj')));
  lEnvironment := SetScopedEnvironmentVariables([
    'DAK_PALCMD_MAP_PATH', lMapPath, 'BDSUSERDIR', lConfigRoot]);
  try
    GC(lDocument, ParseJsonObject(RunDoctor('--json --run-checks true --pa-path ' +
      QuoteArg(lPalPath) + ' --delphi 999.0 --platform Win64', 0),
      'Optional missing compiler configuration'), g);
    lCompiler := RequireCheck(lDocument, 'compiler');
    Assert.AreEqual('configuration', lCompiler.GetValue<string>('kind'));
    Assert.AreEqual('999.0', lCompiler.GetValue<string>('bds_version'));
    Assert.AreEqual('unavailable', lCompiler.GetValue<string>('status'));
    Assert.IsTrue(lCompiler.GetValue<string>('error') <> '');

    lHelp := RequireCheck(lDocument, 'pal_help');
    Assert.AreEqual('available', lHelp.GetValue<string>('status'));
    Assert.AreEqual<Integer>(0, lHelp.GetValue<Integer>('exit_code'));
    lTarget := RequireCheck(lDocument, 'pal_target');
    Assert.AreEqual('12', lTarget.GetValue<string>('delphi'));
    Assert.AreEqual('/CD12W64', lTarget.GetValue<string>('flag'));
    Assert.AreEqual('supported', lTarget.GetValue<string>('status'));
    Assert.AreEqual<Integer>(0, lDocument.GetValue<Integer>('exit_code'));
  finally
    lEnvironment := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisDoctorRemainingTests);

end.
