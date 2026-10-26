unit Test.NativeAnalysisDoctor.Contracts;
interface

uses
  System.JSON,
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisDoctorContractTests = class
  private
    fRoot: string;
    fProject: string;
    fConfig: string;
    fEnvironment: IInterface;
    function RunDoctor(const aOptions: string; aExpectedExit: Cardinal): TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MappedTargetAbsentFromRealHelpIsUnsupported;
    [Test]
    procedure ExplicitPalPathOverridesEnvironment;
    [TestCase('Ini', 'false')]
    [TestCase('Environment', 'true')]
    procedure AllOwnedSwitchesRetainSourceAndMigrationGuidance(aEnvironmentOverride: Boolean);
  end;

implementation

uses
  System.IOUtils, System.SysUtils,
  AutoFree,
  Dak.PascalAnalyzerRunner,
  Test.Support;

procedure TNativeAnalysisDoctorContractTests.Setup;
begin
  fRoot := UniqueTempPath('doctor-contracts');
  TDirectory.CreateDirectory(fRoot);
  fProject := TPath.Combine(fRoot, 'DoctorContract.dproj');
  fConfig := TPath.Combine(fRoot, 'dak.ini');
  TFile.WriteAllText(fProject, '<Project/>', TEncoding.ASCII);
  fEnvironment := SetScopedEnvironmentVariables(['DAK_DOCTOR_RUN', '', 'DAK_DELPHI', '',
    'DAK_PLATFORM', '', 'DAK_OUT', '', 'DAK_WORKSPACE_ROOT', '', 'PA_PATH', '', 'PA_ARGS', '',
    'DAK_PALCMD_MAP_PATH', '']);
end;

procedure TNativeAnalysisDoctorContractTests.TearDown;
begin
  fEnvironment := nil;
  DeleteTempPath(fRoot);
end;

function TNativeAnalysisDoctorContractTests.RunDoctor(const aOptions: string;
  aExpectedExit: Cardinal): TJSONObject;
var
  lExe: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
begin
  lExe := ResolverExePath;
  Assert.IsTrue(TFile.Exists(lExe), 'Expected coordinator-provided candidate: ' + lExe);
  lLog := TPath.Combine(fRoot, 'doctor.log');
  Assert.IsTrue(RunCommandProcess(lExe, 'analyze-doctor --project ' + QuoteArg(fProject) +
    ' --workspace-root ' + QuoteArg(fRoot) + ' --json ' + aOptions, fRoot, lLog, lExitCode));
  lOutput := ReadUtf8TextFile(lLog);
  Assert.AreEqual<Cardinal>(aExpectedExit, lExitCode, lOutput);
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(fRoot, '.dak')));
  Result := ParseJsonObject(lOutput, 'Doctor contracts');
end;

procedure TNativeAnalysisDoctorContractTests.MappedTargetAbsentFromRealHelpIsUnsupported;
const
  cUnlistedFlag = '/CD999W64';
var
  g: TGarbos;
  lCheck: TJSONValue;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lError: string;
  lFound: Boolean;
  lHelp: TJSONObject;
  lItem: TJSONValue;
  lMap: TJSONObject;
  lMapPath: string;
  lPalPath: string;
  lTarget: TJSONObject;
begin
  Assert.IsTrue(TryResolvePalCmdExe('', lPalPath, lError), 'Installed real PAL required: ' + lError);
  lMapPath := TPath.Combine(fRoot, 'palcmd-map.json');
  TFile.Copy(TPath.Combine(RepoRoot, 'bin\palcmd-map.json'), lMapPath);
  GC(lMap, ParseJsonObject(ReadUtf8TextFile(lMapPath), 'Copied PAL mapping'), g);
  lFound := False;
  for lItem in lMap.GetValue<TJSONArray>('delphiFlags') do
    if lItem.GetValue<string>('delphi') = '12' then
    begin
      (lItem as TJSONObject).RemovePair('win64').Free;
      (lItem as TJSONObject).AddPair('win64', cUnlistedFlag);
      lFound := True;
    end;
  Assert.IsTrue(lFound, 'Real mapping must contain Delphi 12');
  TFile.WriteAllText(lMapPath, lMap.ToJSON, TEncoding.UTF8);
  lEnvironment := SetScopedEnvironmentVariables(['DAK_PALCMD_MAP_PATH', lMapPath]);
  try
    GC(lDocument, RunDoctor('--pa-path ' + QuoteArg(lPalPath) +
      ' --delphi 23.0 --platform Win64 --run-checks true', 3), g);
    lHelp := nil;
    lTarget := nil;
    for lCheck in lDocument.GetValue<TJSONArray>('checks') do
    begin
      if lCheck.GetValue<string>('name') = 'pal_help' then
        lHelp := lCheck as TJSONObject;
      if lCheck.GetValue<string>('name') = 'pal_target' then
        lTarget := lCheck as TJSONObject;
    end;
    Assert.IsNotNull(lHelp);
    Assert.AreEqual('available', lHelp.GetValue<string>('status'));
    for lItem in lHelp.GetValue<TJSONArray>('supported_flags') do
      Assert.AreNotEqual(cUnlistedFlag, lItem.Value, 'Real PAL must not advertise the fixture mapping flag');
    Assert.IsNotNull(lTarget);
    Assert.AreEqual(cUnlistedFlag, lTarget.GetValue<string>('flag'), 'Must resolve mapping before rejecting help support');
    Assert.AreEqual('unsupported', lTarget.GetValue<string>('status'));
    Assert.IsTrue(lDocument.GetValue<TJSONArray>('diagnostics').Count > 0);
  finally
    lEnvironment := nil;
  end;
end;

procedure TNativeAnalysisDoctorContractTests.ExplicitPalPathOverridesEnvironment;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lOrigins: TJSONObject;
  lSettings: TJSONObject;
begin
  TFile.WriteAllText(fConfig, '[PascalAnalyzer]' + sLineBreak + 'Path=ini-pal.exe', TEncoding.ASCII);
  lEnvironment := SetScopedEnvironmentVariables(['PA_PATH', 'environment-pal.exe']);
  try
    GC(lDocument, RunDoctor('--pa-path command-pal.exe --run-checks false', 0), g);
    RequireJsonObjectKey(lDocument, 'settings', lSettings);
    Assert.AreEqual('command-pal.exe', lSettings.GetValue<string>('resolved.pascal_analyzer.path'));
    RequireJsonObjectKey(lSettings, 'origins', lOrigins);
    Assert.AreEqual<Integer>(1, (lOrigins.Values['PascalAnalyzer.Path'] as TJSONArray).Count);
    Assert.AreEqual('--pa-path',
      (lOrigins.Values['PascalAnalyzer.Path'] as TJSONArray).Items[0].Value);
  finally
    lEnvironment := nil;
  end;
end;

procedure TNativeAnalysisDoctorContractTests.AllOwnedSwitchesRetainSourceAndMigrationGuidance(
  aEnvironmentOverride: Boolean);
const
  cSwitches: array[0..13] of string = ('/F=X', '/R=reports', '/NAME=Other', '/T=32', '/X=Vendor',
    '/XF=Vendor.pas', '/A+', '/A-', '/FA', '/F+', '/FR', '/FM', '/F-', '/Q');
var
  g: TGarbos;
  lArguments: string;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lMessage: string;
  lSwitch: string;
begin
  lArguments := String.Join(' ', cSwitches);
  if aEnvironmentOverride then
  begin
    TFile.WriteAllText(fConfig, '[PascalAnalyzer]' + sLineBreak + 'Args=/CD12W64', TEncoding.ASCII);
    lEnvironment := SetScopedEnvironmentVariables(['PA_ARGS', lArguments]);
  end else begin
    TFile.WriteAllText(fConfig, '[PascalAnalyzer]' + sLineBreak + 'Args=' + lArguments, TEncoding.ASCII);
  end;
  try
    GC(lDocument, RunDoctor('--run-checks false', 2), g);
    lMessage := lDocument.GetValue<TJSONArray>('diagnostics').Items[0].Value;
    for lSwitch in cSwitches do
      Assert.IsTrue(Pos(lSwitch, lMessage) > 0, 'Missing conflict ' + lSwitch + ': ' + lMessage);
    if aEnvironmentOverride then
      Assert.IsTrue(Pos('PA_ARGS environment variable', lMessage) > 0, lMessage)
    else
      Assert.IsTrue(Pos('[PascalAnalyzer] Args in ' + fConfig, lMessage) > 0, lMessage);
    Assert.IsTrue(Pos('ExcludeSearchFolders', lMessage) > 0, lMessage);
    Assert.IsTrue(Pos('--pa-exclude-search-folders', lMessage) > 0, lMessage);
    Assert.IsTrue(Pos('ExcludeFiles', lMessage) > 0, lMessage);
    Assert.IsTrue(Pos('--pa-exclude-files', lMessage) > 0, lMessage);
  finally
    lEnvironment := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisDoctorContractTests);
end.
