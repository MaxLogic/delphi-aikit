unit Test.NativeAnalysisDoctor;
interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisDoctorTests = class
  public
    [Test]
    procedure JsonPreviewWithoutTargetHasSchemaAndDoesNotCreateDakState;
    [Test]
    procedure ExplicitPreviewOverridesNonemptyLegacyRunFlag;
    [Test]
    procedure ExplicitMissingPalPathReturnsThreeInJsonEnvelope;
    [TestCase('UnknownBeforeJson', '0')]
    [TestCase('ConflictingTargets', '1')]
    [TestCase('InvalidBoolean', '2')]
    procedure ArgumentErrorsKeepJsonEnvelope(aCase: Integer);
    [TestCase('Configuration', 'false')]
    [TestCase('Environment', 'true')]
    procedure PalArgumentConflictsIdentifyTheirSource(aEnvironmentOverride: Boolean);
    [Test]
    procedure NonOwnedEnvironmentArgumentsReplaceIniConflicts;
    [TestCase('Supported', '23.0,true,false,false')]
    [TestCase('Unmapped', '999.0,false,false,false')]
    [TestCase('Environment', '999.0,false,true,false')]
    [TestCase('CommandOverridesEnvironment', '23.0,true,true,true')]
    procedure LivePalHelpChecksRequestedTarget(const aBdsVersion: string;
      aSupported, aEnvironment, aOverride: Boolean);
  end;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.PascalAnalyzerRunner,
  Test.Support;

procedure AssertDoctorEnvelope(const aDocument: TJSONObject; const aMode: string; aExitCode: Integer);
var
  lChecks: TJSONArray;
  lDiagnostics: TJSONArray;
  lSettings: TJSONObject;
begin
  RequireJsonNumberKey(aDocument, 'schema_version');
  Assert.AreEqual<Integer>(1, aDocument.GetValue<Integer>('schema_version'));
  RequireJsonStringKey(aDocument, 'mode');
  Assert.AreEqual(aMode, aDocument.GetValue<string>('mode'));
  Assert.IsNotNull(aDocument.Values['subject'], 'Expected nullable subject field');
  RequireJsonObjectKey(aDocument, 'settings', lSettings);
  RequireJsonArrayKey(aDocument, 'checks', lChecks);
  RequireJsonArrayKey(aDocument, 'diagnostics', lDiagnostics);
  RequireJsonNumberKey(aDocument, 'exit_code');
  Assert.AreEqual<Integer>(aExitCode, aDocument.GetValue<Integer>('exit_code'));
end;

procedure CreateDoctorProject(const aRoot: string; out aProjectPath: string; out aMissingPalPath: string);
var
  lConfig: string;
begin
  aProjectPath := TPath.Combine(aRoot, 'DoctorFixture.dproj');
  aMissingPalPath := TPath.Combine(aRoot, 'missing-palcmd.exe');
  TFile.WriteAllText(aProjectPath, '<Project/>', TEncoding.ASCII);
  lConfig := '[Workspace]' + sLineBreak +
    'Root=project' + sLineBreak + sLineBreak +
    '[PascalAnalyzer]' + sLineBreak +
    'Path=' + aMissingPalPath + sLineBreak;
  TFile.WriteAllText(TPath.Combine(aRoot, 'dak.ini'), lConfig, TEncoding.UTF8);
end;

function RunDoctorCommand(const aArgs, aWorkDir, aOutputFile: string; out aExitCode: Cardinal): string;
var
  lExePath: string;
begin
  lExePath := ResolverExePath;
  Assert.IsTrue(TFile.Exists(lExePath), 'Expected the coordinator-provided DAK candidate: ' + lExePath);
  Assert.IsTrue(RunCommandProcess(lExePath, aArgs, aWorkDir, aOutputFile, aExitCode),
    'Could not launch DAK candidate: ' + lExePath);
  Result := ReadUtf8TextFile(aOutputFile);
end;

procedure TNativeAnalysisDoctorTests.JsonPreviewWithoutTargetHasSchemaAndDoesNotCreateDakState;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-analysis-doctor-preview');
  TDirectory.CreateDirectory(lRoot);
  try
    lLog := TPath.Combine(lRoot, 'doctor.log');
    lEnvironment := SetScopedEnvironmentVariables([
      'DAK_DOCTOR_RUN', '',
      'PA_PATH', '',
      'PA_ARGS', ''
    ]);
    lOutput := RunDoctorCommand('analyze-doctor --json', lRoot, lLog, lExitCode);
    Assert.AreEqual<Cardinal>(0, lExitCode, lOutput);
    GC(lDocument, ParseJsonObject(lOutput, 'analyze-doctor preview'), g);
    AssertDoctorEnvelope(lDocument, 'preview', 0);
    Assert.IsTrue(lDocument.Values['subject'] is TJSONNull, 'A targetless doctor run has a null subject');
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(lRoot, '.dak')),
      'Doctor preview must not create project analysis state');
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisDoctorTests.ExplicitPreviewOverridesNonemptyLegacyRunFlag;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lExitCode: Cardinal;
  lLog: string;
  lMissingPalPath: string;
  lOutput: string;
  lProjectPath: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-analysis-doctor-preview-override');
  TDirectory.CreateDirectory(lRoot);
  try
    CreateDoctorProject(lRoot, lProjectPath, lMissingPalPath);
    Assert.IsFalse(TFile.Exists(lMissingPalPath));
    lLog := TPath.Combine(lRoot, 'doctor.log');
    lEnvironment := SetScopedEnvironmentVariables([
      'DAK_DOCTOR_RUN', 'false',
      'PA_PATH', '',
      'PA_ARGS', ''
    ]);
    lOutput := RunDoctorCommand('analyze-doctor --project ' + QuoteArg(lProjectPath) +
      ' --run-checks false --json', lRoot, lLog, lExitCode);
    Assert.AreEqual<Cardinal>(0, lExitCode, lOutput);
    GC(lDocument, ParseJsonObject(lOutput, 'explicit preview overrides DAK_DOCTOR_RUN'), g);
    AssertDoctorEnvelope(lDocument, 'preview', 0);
    Assert.IsFalse(lDocument.Values['subject'] is TJSONNull, 'The project target should be present in the envelope');
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(lRoot, '.dak')),
      'Preview must not create project analysis state');
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisDoctorTests.ExplicitMissingPalPathReturnsThreeInJsonEnvelope;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lExitCode: Cardinal;
  lLog: string;
  lMissingPalPath: string;
  lOutput: string;
  lProjectPath: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-analysis-doctor-missing-pal');
  TDirectory.CreateDirectory(lRoot);
  try
    CreateDoctorProject(lRoot, lProjectPath, lMissingPalPath);
    Assert.IsFalse(TFile.Exists(lMissingPalPath));
    lLog := TPath.Combine(lRoot, 'doctor.log');
    lEnvironment := SetScopedEnvironmentVariables([
      'DAK_DOCTOR_RUN', '',
      'PA_PATH', '',
      'PA_ARGS', ''
    ]);
    lOutput := RunDoctorCommand('analyze-doctor --project ' + QuoteArg(lProjectPath) +
      ' --run-checks true --json', lRoot, lLog, lExitCode);
    Assert.AreEqual<Cardinal>(3, lExitCode, lOutput);
    GC(lDocument, ParseJsonObject(lOutput, 'explicit missing PAL path'), g);
    AssertDoctorEnvelope(lDocument, 'checks', 3);
    Assert.IsFalse(lDocument.Values['subject'] is TJSONNull, 'The project target should be present in the envelope');
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(lRoot, '.dak')),
      'Doctor checks must not create project analysis state');
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisDoctorTests.ArgumentErrorsKeepJsonEnvelope(aCase: Integer);
var
  g: TGarbos;
  lArguments: string;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lExitCode: Cardinal;
  lOutput: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('doctor-argument-errors');
  TDirectory.CreateDirectory(lRoot);
  try
    lEnvironment := SetScopedEnvironmentVariables(['DAK_DOCTOR_RUN', '', 'PA_ARGS', '']);
    case aCase of
      0: lArguments := 'analyze-doctor --unknown value --json';
      1: lArguments := 'analyze-doctor --project missing.dproj --unit missing.pas --json';
      2: lArguments := 'analyze-doctor --run-checks invalid --json';
    end;
    lOutput := RunDoctorCommand(lArguments, lRoot, TPath.Combine(lRoot, 'doctor.log'), lExitCode);
    Assert.AreEqual<Cardinal>(2, lExitCode, lOutput);
    GC(lDocument, ParseJsonObject(lOutput, 'Doctor argument error envelope'), g);
    AssertDoctorEnvelope(lDocument, 'preview', 2);
    Assert.IsTrue(lDocument.GetValue<TJSONArray>('diagnostics').Count > 0);
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(lRoot, '.dak')));
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisDoctorTests.PalArgumentConflictsIdentifyTheirSource(aEnvironmentOverride: Boolean);
var
  g: TGarbos;
  lConfigPath: string;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lExitCode: Cardinal;
  lMissingPalPath: string;
  lOutput: string;
  lProject: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('doctor-argument-origin');
  TDirectory.CreateDirectory(lRoot);
  try
    CreateDoctorProject(lRoot, lProject, lMissingPalPath);
    lConfigPath := TPath.Combine(lRoot, 'dak.ini');
    TFile.AppendAllText(lConfigPath, 'Args=/Q' + sLineBreak, TEncoding.UTF8);
    if aEnvironmentOverride then
      lEnvironment := SetScopedEnvironmentVariables(['DAK_DOCTOR_RUN', '', 'PA_ARGS', '/R=reports'])
    else
      lEnvironment := SetScopedEnvironmentVariables(['DAK_DOCTOR_RUN', '', 'PA_ARGS', '']);
    lOutput := RunDoctorCommand('analyze-doctor --project ' + QuoteArg(lProject) + ' --json',
      lRoot, TPath.Combine(lRoot, 'doctor.log'), lExitCode);
    Assert.AreEqual<Cardinal>(2, lExitCode, lOutput);
    GC(lDocument, ParseJsonObject(lOutput, 'PAL conflict provenance'), g);
    AssertDoctorEnvelope(lDocument, 'preview', 2);
    lOutput := lDocument.GetValue<TJSONArray>('diagnostics').ToJSON;
    if aEnvironmentOverride then
    begin
      Assert.IsTrue(Pos('PA_ARGS', lOutput) > 0, lOutput);
      Assert.IsTrue(Pos('/R=reports', lOutput) > 0, lOutput);
      Assert.AreEqual(0, Pos('/Q', lOutput), 'The environment replaces the INI Args value.');
    end else
    begin
      Assert.IsTrue(Pos('dak.ini', lOutput) > 0, lOutput);
      Assert.IsTrue(Pos('/Q', lOutput) > 0, lOutput);
    end;
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisDoctorTests.NonOwnedEnvironmentArgumentsReplaceIniConflicts;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lExitCode: Cardinal;
  lMissingPalPath: string;
  lOutput: string;
  lProject: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('doctor-allowed-arguments');
  TDirectory.CreateDirectory(lRoot);
  try
    CreateDoctorProject(lRoot, lProject, lMissingPalPath);
    TFile.AppendAllText(TPath.Combine(lRoot, 'dak.ini'), 'Args=/Q' + sLineBreak, TEncoding.UTF8);
    lEnvironment := SetScopedEnvironmentVariables(['DAK_DOCTOR_RUN', '', 'PA_ARGS', '/CD12W64']);
    lOutput := RunDoctorCommand('analyze-doctor --project ' + QuoteArg(lProject) + ' --json',
      lRoot, TPath.Combine(lRoot, 'doctor.log'), lExitCode);
    Assert.AreEqual<Cardinal>(0, lExitCode, lOutput);
    GC(lDocument, ParseJsonObject(lOutput, 'Allowed environment replaces conflicting INI'), g);
    AssertDoctorEnvelope(lDocument, 'preview', 0);
    Assert.AreEqual(0, lDocument.GetValue<TJSONArray>('diagnostics').Count);
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisDoctorTests.LivePalHelpChecksRequestedTarget(const aBdsVersion: string;
  aSupported, aEnvironment, aOverride: Boolean);
var
  g: TGarbos;
  lArguments: string;
  lBdsEnvironment: string;
  lCheck: TJSONValue;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lError: string;
  lExitCode: Cardinal;
  lExpectedExit: Cardinal;
  lHelp: TJSONObject;
  lMissingPalPath: string;
  lOutput: string;
  lPalPath: string;
  lPlatformEnvironment: string;
  lProject: string;
  lRoot: string;
  lTarget: TJSONObject;
begin
  Assert.IsTrue(TryResolvePalCmdExe('', lPalPath, lError),
    'This live integration requires installed PAL: ' + lError);
  lRoot := UniqueTempPath('doctor-live-pal');
  TDirectory.CreateDirectory(lRoot);
  try
    CreateDoctorProject(lRoot, lProject, lMissingPalPath);
    lBdsEnvironment := '';
    lPlatformEnvironment := '';
    if aEnvironment then
    begin
      lBdsEnvironment := '999.0';
      lPlatformEnvironment := 'Win64';
      if aOverride then
        lPlatformEnvironment := 'Unknown';
    end;
    lEnvironment := SetScopedEnvironmentVariables(['DAK_DOCTOR_RUN', '', 'PA_PATH', '', 'PA_ARGS', '',
      'DAK_DELPHI', lBdsEnvironment, 'DAK_PLATFORM', lPlatformEnvironment]);
    lArguments := 'analyze-doctor --project ' + QuoteArg(lProject) +
      ' --pa-path ' + QuoteArg(lPalPath) + ' --run-checks true --json';
    if not aEnvironment or aOverride then
      lArguments := lArguments + ' --delphi ' + aBdsVersion + ' --platform Win64';
    lOutput := RunDoctorCommand(lArguments, lRoot, TPath.Combine(lRoot, 'doctor.log'), lExitCode);
    lExpectedExit := 3;
    if aSupported then
      lExpectedExit := 0;
    Assert.AreEqual<Cardinal>(lExpectedExit, lExitCode, lOutput);
    GC(lDocument, ParseJsonObject(lOutput, 'Live PAL capability checks'), g);
    AssertDoctorEnvelope(lDocument, 'checks', lExpectedExit);
    lHelp := nil;
    lTarget := nil;
    for lCheck in lDocument.GetValue<TJSONArray>('checks') do
    begin
      if lCheck.GetValue<string>('name') = 'pal_help' then
        lHelp := lCheck as TJSONObject;
      if lCheck.GetValue<string>('name') = 'pal_target' then
        lTarget := lCheck as TJSONObject;
    end;
    Assert.IsNotNull(lHelp, 'Expected actual PAL help probe result');
    Assert.AreEqual('available', lHelp.GetValue<string>('status'));
    Assert.AreEqual<Integer>(0, lHelp.GetValue<Integer>('exit_code'));
    Assert.AreNotEqual('unknown', lHelp.GetValue<string>('version'));
    Assert.IsTrue(lHelp.GetValue<Boolean>('help_available'));
    Assert.IsTrue(lHelp.GetValue<TJSONArray>('supported_flags').Count > 0);
    Assert.IsNotNull(lTarget, 'Expected explicit requested-target result');
    Assert.AreEqual(aBdsVersion, lTarget.GetValue<string>('bds_version'));
    Assert.AreEqual('Win64', lTarget.GetValue<string>('platform'));
    if aSupported then
    begin
      Assert.AreEqual('supported', lTarget.GetValue<string>('status'));
      Assert.AreEqual('/CD12W64', lTarget.GetValue<string>('flag'));
    end else
    begin
      Assert.AreEqual('unsupported', lTarget.GetValue<string>('status'));
      Assert.IsTrue(lDocument.GetValue<TJSONArray>('diagnostics').Count > 0);
    end;
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(lRoot, '.dak')),
      'Help checks must not publish analysis state');
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisDoctorTests);

end.
