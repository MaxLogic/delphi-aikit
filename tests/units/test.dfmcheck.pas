unit Test.DfmCheck;

interface

uses
  DUnitX.TestFramework,
  System.Classes, System.IOUtils, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  Dak.DfmCheck, Dak.Types,
  Test.Support;

type
  TMockValidatorMode = (vmHappy, vmHappyParentBin, vmBroken, vmBrokenEventSignature, vmBuildFailGeneratedUnit);

  TMockDfmCheckRunner = class(TInterfacedObject, IDfmCheckProcessRunner)
  private
    fGeneratedDproj: string;
    fConfig: string;
    fMsBuildArguments: string;
    fMode: TMockValidatorMode;
    fPlatform: string;
    fRunCount: Integer;
    function ReadFirstArg(const aArguments: string): string;
  public
    constructor Create(const aMode: TMockValidatorMode; const aConfig: string; const aPlatform: string);
    function Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
      const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
    property MsBuildArguments: string read fMsBuildArguments;
  end;

  [TestFixture]
  TDfmCheckTests = class
  private
    procedure WriteInjectStubs(const aInjectDir: string);
    procedure CreateFixtureProject(out aProjectDproj: string);
    function JoinOutput(const aLines: TStrings): string;
  public
    [Test]
    procedure ResolveProjectPathMapsDprToSiblingDproj;
    [Test]
    procedure BuildExpectedPathsIsDeterministic;
    [Test]
    procedure PatchDprIsIdempotentAndPreservesSyntax;
    [Test]
    procedure PatchDprInjectsAtMainBeginNotNestedBegin;
    [Test]
    procedure MapExitCodePropagatesToolAndCategoryCodes;
    [Test]
    procedure PipelineHappyPathWithMockRunner;
    [Test]
    procedure PipelineBrokenDfmPropagatesValidatorExitAndFailText;
    [Test]
    procedure PipelineBrokenEventSignaturePropagatesValidatorExitAndFailText;
    [Test]
    procedure PipelineBuildFailureInGeneratedUnitIsClassifiedAsGeneratorIncompatibility;
    [Test]
    procedure PipelineFindsValidatorExeInParentBin;
    [Test]
    procedure PipelineCleansGeneratedArtifactsByDefault;
    [Test]
    procedure IntegrationWrongEventSignatureProducesDfmFailure;
  end;

implementation

constructor TMockDfmCheckRunner.Create(const aMode: TMockValidatorMode; const aConfig: string; const aPlatform: string);
begin
  inherited Create;
  fMode := aMode;
  fConfig := aConfig;
  fPlatform := aPlatform;
  fRunCount := 0;
end;

function TMockDfmCheckRunner.ReadFirstArg(const aArguments: string): string;
var
  lArgs: string;
  lPos: Integer;
begin
  lArgs := Trim(aArguments);
  if lArgs = '' then
    Exit('');
  if lArgs[1] = '"' then
  begin
    lPos := PosEx('"', lArgs, 2);
    if lPos > 1 then
      Exit(Copy(lArgs, 2, lPos - 2));
  end;
  lPos := Pos(' ', lArgs);
  if lPos > 0 then
    Result := Copy(lArgs, 1, lPos - 1)
  else
    Result := lArgs;
end;

function TMockDfmCheckRunner.Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
  const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
var
  lDprojPath: string;
  lValidatorExePath: string;
  lValidatorDir: string;
begin
  Result := True;
  aError := '';
  aExitCode := 0;
  Inc(fRunCount);

  if fRunCount = 1 then
  begin
    if fMode = TMockValidatorMode.vmBuildFailGeneratedUnit then
    begin
      if Assigned(aOutput) then
      begin
        aOutput('Sample_DfmCheck_Register.pas(42): error E2003: Undeclared identifier: ''TMainForm''');
        aOutput('Sample_DfmCheck.dpr(88): error F2063: Could not compile used unit ''Sample_DfmCheck_Register.pas''');
      end;
      aExitCode := 1;
      Exit(True);
    end;

    fMsBuildArguments := aArguments;
    lDprojPath := ReadFirstArg(aArguments);
    if lDprojPath = '' then
    begin
      aError := 'Mock expected generated dproj as first msbuild argument.';
      Exit(False);
    end;
    fGeneratedDproj := lDprojPath;
    if fMode = TMockValidatorMode.vmHappyParentBin then
      lValidatorDir := TPath.Combine(TPath.Combine(TPath.Combine(ExtractFileDir(aWorkingDir), 'Bin'), fPlatform), fConfig)
    else
      lValidatorDir := TPath.Combine(TPath.Combine(aWorkingDir, fPlatform), fConfig);
    TDirectory.CreateDirectory(lValidatorDir);
    lValidatorExePath := TPath.Combine(lValidatorDir, TPath.GetFileNameWithoutExtension(lDprojPath) + '.exe');
    TFile.WriteAllText(lValidatorExePath, 'mock', TEncoding.ASCII);
    Exit(True);
  end;

  if fRunCount = 2 then
  begin
    if Assigned(aOutput) then
    begin
      if fMode = TMockValidatorMode.vmBroken then
      begin
        aOutput('FAIL MAINFORM -> EReadError: Property FullRowSelect does not exist');
      end
      else if fMode = TMockValidatorMode.vmBrokenEventSignature then
      begin
        aOutput('FAIL MAINFORM -> EReadError: Error reading MainForm.OnCreate: Type mismatch for method ''FormCreate''');
      end else
      begin
        aOutput('OK   MAINFORM');
      end;
    end;

    if (fMode = TMockValidatorMode.vmBroken) or (fMode = TMockValidatorMode.vmBrokenEventSignature) then
      aExitCode := 1
    else
      aExitCode := 0;
    Exit(True);
  end;

  aError := Format('Unexpected Run invocation #%d (exe=%s args=%s cwd=%s)', [fRunCount, aExePath, aArguments,
    aWorkingDir]);
  Result := False;
end;

procedure TDfmCheckTests.WriteInjectStubs(const aInjectDir: string);
begin
  TDirectory.CreateDirectory(aInjectDir);
  TFile.WriteAllText(TPath.Combine(aInjectDir, 'DfmStreamAll.pas'),
    'unit DfmStreamAll; interface implementation end.', TEncoding.UTF8);
end;

procedure TDfmCheckTests.CreateFixtureProject(out aProjectDproj: string);
var
  lDprPath: string;
  lMainFormDfmPath: string;
  lMainFormPasPath: string;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'dfm-check-fixture');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  aProjectDproj := TPath.Combine(lRoot, 'Sample.dproj');
  lDprPath := TPath.ChangeExtension(aProjectDproj, '.dpr');
  lMainFormPasPath := TPath.Combine(lRoot, 'MainForm.pas');
  lMainFormDfmPath := TPath.Combine(lRoot, 'MainForm.dfm');

  TFile.WriteAllText(aProjectDproj,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <MainSource>Sample.dpr</MainSource>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '</Project>' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lDprPath,
    'program Sample;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  Vcl.Forms,' + #13#10 +
    '  MainForm in ''MainForm.pas'' {MainForm};' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lMainFormPasPath,
    'unit MainForm;' + #13#10 +
    #13#10 +
    'interface' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.Classes, Vcl.Forms;' + #13#10 +
    #13#10 +
    'type' + #13#10 +
    '  TMainForm = class(TForm)' + #13#10 +
    '  end;' + #13#10 +
    #13#10 +
    'implementation' + #13#10 +
    #13#10 +
    '{$R *.dfm}' + #13#10 +
    #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lMainFormDfmPath,
    'object MainForm: TMainForm' + #13#10 +
    '  Caption = ''MainForm''' + #13#10 +
    'end' + #13#10, TEncoding.UTF8);
end;

function TDfmCheckTests.JoinOutput(const aLines: TStrings): string;
begin
  Result := String.Join(#13#10, aLines.ToStringArray);
end;

procedure TDfmCheckTests.ResolveProjectPathMapsDprToSiblingDproj;
var
  lDprojPath: string;
  lResolvedPath: string;
  lError: string;
begin
  CreateFixtureProject(lDprojPath);
  Assert.IsTrue(TryResolveDfmCheckProjectPath(TPath.ChangeExtension(lDprojPath, '.dpr'), lResolvedPath, lError),
    'Expected .dpr input to map to sibling .dproj. Error: ' + lError);
  Assert.AreEqual(lDprojPath, lResolvedPath);
end;

procedure TDfmCheckTests.BuildExpectedPathsIsDeterministic;
var
  lDprojPath: string;
  lPaths: TDfmCheckPaths;
begin
  CreateFixtureProject(lDprojPath);
  lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
  Assert.AreEqual(TPath.Combine(ExtractFilePath(lDprojPath), 'Sample_DfmCheck'),
    ExcludeTrailingPathDelimiter(lPaths.fGeneratedDir));
  Assert.AreEqual(TPath.Combine(lPaths.fGeneratedDir, 'Sample_DfmCheck.dproj'), lPaths.fGeneratedDproj);
  Assert.AreEqual(TPath.Combine(lPaths.fGeneratedDir, 'Sample_DfmCheck.dpr'), lPaths.fGeneratedDpr);
end;

procedure TDfmCheckTests.PatchDprIsIdempotentAndPreservesSyntax;
var
  lInputText: string;
  lPatchedText: string;
  lPatchedTwiceText: string;
  lChanged: Boolean;
  lChangedTwice: Boolean;
  lError: string;
begin
  lInputText :=
    'program Sample_DfmCheck;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.SysUtils, Vcl.Forms;' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    '  Application.Initialize;' + #13#10 +
    'end.' + #13#10;

  Assert.IsTrue(TryPatchDfmCheckDpr(lInputText, lPatchedText, lChanged, lError), 'Patch failed: ' + lError);
  Assert.IsTrue(lChanged, 'Expected first patch call to modify the DPR.');
  Assert.IsTrue(Pos('DfmStreamAll,', lPatchedText) > 0, 'Expected DfmStreamAll to be injected into uses clause.');
  Assert.IsTrue(Pos('ExitCode := TDfmStreamAll.Run;', lPatchedText) > 0,
    'Expected ExitCode assignment to be injected before final end.');
  Assert.IsTrue(Pos('Halt(ExitCode);', lPatchedText) > 0,
    'Expected validator short-circuit halt in patched DPR.');
  Assert.IsTrue(Pos('uses', lPatchedText) > 0, 'Expected patched DPR to preserve uses keyword.');
  Assert.IsTrue(Pos(';', lPatchedText) > 0, 'Expected patched DPR to preserve uses syntax.');

  Assert.IsTrue(TryPatchDfmCheckDpr(lPatchedText, lPatchedTwiceText, lChangedTwice, lError),
    'Second patch pass failed: ' + lError);
  Assert.IsFalse(lChangedTwice, 'Expected second patch pass to be idempotent.');
  Assert.AreEqual(lPatchedText, lPatchedTwiceText);
end;

procedure TDfmCheckTests.MapExitCodePropagatesToolAndCategoryCodes;
begin
  Assert.AreEqual(3, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecInvalidInput, 0));
  Assert.AreEqual(17, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecDfmCheckFailed, 17));
  Assert.AreEqual(37, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecGeneratorIncompatible, 0));
  Assert.AreEqual(34, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecBuildFailed, 0));
  Assert.AreEqual(9, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecValidatorFailed, 9));
end;

procedure TDfmCheckTests.PatchDprInjectsAtMainBeginNotNestedBegin;
var
  lChanged: Boolean;
  lError: string;
  lIfBeginPos: Integer;
  lInputText: string;
  lInjectedPos: Integer;
  lPatchedText: string;
  lShowNegPos: Integer;
begin
  lInputText :=
    'program Sample_DfmCheck;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.SysUtils, Vcl.Forms;' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    '  ShowNeg(mWait);' + #13#10 +
    '  if PrimeInitialization.PerformInitialization then' + #13#10 +
    '  begin' + #13#10 +
    '    Application.CreateForm(TMainForm, MainForm);' + #13#10 +
    '  end;' + #13#10 +
    '  Application.Run;' + #13#10 +
    'end.' + #13#10;

  Assert.IsTrue(TryPatchDfmCheckDpr(lInputText, lPatchedText, lChanged, lError), 'Patch failed: ' + lError);
  Assert.IsTrue(lChanged, 'Expected nested-begin DPR to be patched.');

  lInjectedPos := Pos('ExitCode := TDfmStreamAll.Run;', lPatchedText);
  Assert.IsTrue(lInjectedPos > 0, 'Expected validator injection in patched DPR.');
  lShowNegPos := Pos('ShowNeg(mWait);', lPatchedText);
  Assert.IsTrue(lShowNegPos > 0, 'Expected ShowNeg call in patched DPR.');
  Assert.IsTrue(lInjectedPos < lShowNegPos,
    'Expected validator injection before splash/login initialization statements.');
  lIfBeginPos := Pos('if PrimeInitialization.PerformInitialization then' + #13#10 + '  begin', lPatchedText);
  Assert.IsTrue(lIfBeginPos > 0, 'Expected nested IF begin block to remain unchanged.');
  Assert.IsTrue(lInjectedPos < lIfBeginPos, 'Expected validator injection at main begin, not nested begin.');
end;

procedure TDfmCheckTests.PipelineHappyPathWithMockRunner;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPaths: TDfmCheckPaths;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lGeneratedDprojText: string;
  lPatchedDprText: string;
  lGeneratedUnitText: string;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-happy');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected happy mock pipeline to return success.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for happy path.');
    Assert.AreEqual('', lError, 'Did not expect an error message in happy path.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('[dfm-check] Generating DFMCheck project...', lOutputText) > 0,
      'Missing DFMCheck generation stage log.');
    Assert.IsTrue(Pos('[dfm-check] Building generated DfmCheck project via MSBuild...', lOutputText) > 0,
      'Missing MSBuild stage log.');
    Assert.IsTrue(Pos('[dfm-check] Running validator exe...', lOutputText) > 0, 'Missing validator stage log.');
    Assert.IsTrue(Pos('OK   MAINFORM', lOutputText) > 0, 'Expected OK resource output from validator stage.');
    Assert.IsFalse(Pos('NON_DFM', lOutputText) > 0, 'Non-DFM resources should not be emitted in validator output.');
    Assert.IsTrue(Pos('/p:DCC_ForceExecute=true', lRunnerImpl.MsBuildArguments) > 0,
      'Expected forced response-file mode in MSBuild arguments.');
    Assert.IsTrue(Pos('/p:DCC_ExeOutput=', lRunnerImpl.MsBuildArguments) > 0,
      'Expected isolated exe output override in MSBuild arguments.');
    Assert.IsTrue(Pos('/p:DCC_DcuOutput=', lRunnerImpl.MsBuildArguments) > 0,
      'Expected isolated DCU output override in MSBuild arguments.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lPatchedDprText := TFile.ReadAllText(lPaths.fGeneratedDpr);
    Assert.IsTrue(Pos('DfmStreamAll,', lPatchedDprText) > 0, 'Expected DfmStreamAll in patched DPR.');
    Assert.IsTrue(Pos('ExitCode := TDfmStreamAll.Run;', lPatchedDprText) > 0,
      'Expected ExitCode assignment in patched DPR.');
    Assert.IsTrue(Pos('Halt(ExitCode);', lPatchedDprText) > 0, 'Expected validator short-circuit halt in DPR.');
    Assert.IsFalse(Pos('Application.Initialize;', lPatchedDprText) > 0,
      'Generated checker DPR should not execute application startup.');

    lGeneratedDprojText := TFile.ReadAllText(lPaths.fGeneratedDproj);
    Assert.IsTrue(Pos('<DCC_Define>DFMCheck</DCC_Define>', lGeneratedDprojText) > 0,
      'Generated checker DPROJ should define DFMCheck symbol.');

    lGeneratedUnitText := TFile.ReadAllText(TPath.Combine(lPaths.fProjectDir, 'Sample_DfmCheck_Register.pas'));
    Assert.IsTrue(Pos('unit Sample_DfmCheck_Register;', lGeneratedUnitText) > 0,
      'Expected generated register unit for streaming class registration.');
    Assert.IsTrue(Pos('uses', lGeneratedUnitText) > 0, 'Expected generated register unit to keep form-unit linkage.');
    Assert.IsTrue(Pos('MainForm', lGeneratedUnitText) > 0, 'Expected generated register unit to keep MainForm in uses.');
    Assert.IsTrue(Pos('{$IF Declared(TMainForm)} RegisterClass(TMainForm); {$IFEND}', lGeneratedUnitText) > 0,
      'Expected generated register unit to register root form class for streaming.');
    Assert.IsFalse(Pos('.ClassName;', lGeneratedUnitText) > 0,
      'Generated register unit should not include compile-time ClassName checks.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBrokenDfmPropagatesValidatorExitAndFailText;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-broken');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBroken, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(1, lResult, 'Expected validator non-zero exit to be propagated.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Expected validator failures to propagate exit code without remapping category.');
    Assert.AreEqual('', lError, 'Did not expect orchestration error text for validator-stream failure.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('FAIL MAINFORM -> EReadError: Property FullRowSelect does not exist', lOutputText) > 0,
      'Expected broken DFM FAIL line with streaming exception text.');
    Assert.IsTrue(Pos('/p:DCC_ForceExecute=true', lRunnerImpl.MsBuildArguments) > 0,
      'Expected forced response-file mode in MSBuild arguments.');
    Assert.IsTrue(Pos('/p:DCC_ExeOutput=', lRunnerImpl.MsBuildArguments) > 0,
      'Expected isolated exe output override in MSBuild arguments.');
    Assert.IsTrue(Pos('/p:DCC_DcuOutput=', lRunnerImpl.MsBuildArguments) > 0,
      'Expected isolated DCU output override in MSBuild arguments.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBrokenEventSignaturePropagatesValidatorExitAndFailText;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-broken-event');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBrokenEventSignature, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(1, lResult, 'Expected validator non-zero exit to be propagated for wrong event signature.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Expected event-signature streaming failures to propagate exit code without remapping category.');
    Assert.AreEqual('', lError, 'Did not expect orchestration error text for event-signature stream failure.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('FAIL MAINFORM -> EReadError:', lOutputText) > 0,
      'Expected FAIL line for event-signature stream failure.');
    Assert.IsTrue(Pos('OnCreate', lOutputText) > 0,
      'Expected streaming exception text to include the failing event property.');
    Assert.IsTrue(Pos('FormCreate', lOutputText) > 0,
      'Expected streaming exception text to include the event handler method name.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBuildFailureInGeneratedUnitIsClassifiedAsGeneratorIncompatibility;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-buildfail');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBuildFailGeneratedUnit, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(1, lResult, 'Expected non-zero build exit code to be propagated.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecGeneratorIncompatible, lCategory,
      'Expected generated checker unit compile failure to map to generator incompatibility.');
    Assert.IsTrue(Pos('generator incompatibility', LowerCase(lError)) > 0,
      'Expected incompatibility diagnostic in error message.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('Sample_DfmCheck_Register.pas(42): error E2003', lOutputText) > 0,
      'Expected generated checker unit compile error in build output.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineFindsValidatorExeInParentBin;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-parent-bin');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappyParentBin, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected happy pipeline to find validator exe in parent Bin layout.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for parent Bin layout.');
    Assert.AreEqual('', lError, 'Did not expect an error message for parent Bin layout.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('OK   MAINFORM', lOutputText) > 0, 'Expected validator run output in parent Bin layout.');
    Assert.IsFalse(Pos('Could not find built _DfmCheck.exe', lOutputText) > 0,
      'Did not expect validator-not-found output in parent Bin layout.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineCleansGeneratedArtifactsByDefault;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lPaths: TDfmCheckPaths;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-cleanup');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', nil);
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected cleanup happy path to return success.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for cleanup happy path.');
    Assert.AreEqual('', lError, 'Did not expect an error message in cleanup happy path.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsFalse(FileExists(lPaths.fGeneratedDpr), 'Expected generated DPR to be cleaned up by default.');
    Assert.IsFalse(FileExists(lPaths.fGeneratedDproj), 'Expected generated DPROJ to be cleaned up by default.');
    Assert.IsFalse(FileExists(TPath.Combine(lPaths.fProjectDir, 'Sample_DfmCheck_Register.pas')),
      'Expected generated register unit to be cleaned up by default.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.IntegrationWrongEventSignatureProducesDfmFailure;
var
  lArgs: string;
  lDfmPath: string;
  lDprPath: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lMainFormPasPath: string;
  lOutputText: string;
  lProjectDir: string;
  lResolverPath: string;
  lRsVarsPath: string;
  lDelphiVersion: string;
begin
  if not SameText(Trim(GetEnvironmentVariable('DAK_DFMCHECK_INTEGRATION')), '1') then
    Assert.Pass('DAK_DFMCHECK_INTEGRATION is not set; skipping dfm-check integration test.');

  lRsVarsPath := Trim(GetEnvironmentVariable('DAK_DFMCHECK_RSVARS'));
  if lRsVarsPath = '' then
    lRsVarsPath := Trim(GetEnvironmentVariable('DAK_RSVARS_BAT'));
  if lRsVarsPath = '' then
    Assert.Pass('DAK_DFMCHECK_RSVARS is not set; skipping dfm-check integration test.');
  if not FileExists(lRsVarsPath) then
    Assert.Pass('Configured rsvars.bat path does not exist: ' + lRsVarsPath);

  EnsureResolverBuilt;
  lResolverPath := ResolverExePath;
  if not FileExists(lResolverPath) then
    Assert.Fail('Resolver exe not found for integration test: ' + lResolverPath);

  lDelphiVersion := Trim(GetEnvironmentVariable('DAK_DFMCHECK_DELPHI'));
  if lDelphiVersion = '' then
    lDelphiVersion := '23.0';

  lProjectDir := TPath.Combine(TempRoot, 'dfm-check-wrong-event-signature');
  if TDirectory.Exists(lProjectDir) then
    TDirectory.Delete(lProjectDir, True);
  TDirectory.CreateDirectory(lProjectDir);

  lDprojPath := TPath.Combine(lProjectDir, 'WrongEventSample.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lMainFormPasPath := TPath.Combine(lProjectDir, 'MainForm.pas');
  lDfmPath := TPath.Combine(lProjectDir, 'MainForm.dfm');
  lLogPath := TPath.Combine(lProjectDir, 'dfm-check.log');

  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <MainSource>WrongEventSample.dpr</MainSource>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '</Project>' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lDprPath,
    'program WrongEventSample;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  Vcl.Forms,' + #13#10 +
    '  MainForm in ''MainForm.pas'' {MainForm};' + #13#10 +
    #13#10 +
    '{$R *.res}' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    '  Application.Initialize;' + #13#10 +
    '  Application.CreateForm(TMainForm, MainForm);' + #13#10 +
    '  Application.Run;' + #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lMainFormPasPath,
    'unit MainForm;' + #13#10 +
    #13#10 +
    'interface' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.Classes, Vcl.Forms;' + #13#10 +
    #13#10 +
    'type' + #13#10 +
    '  TMainForm = class(TForm)' + #13#10 +
    '    procedure FormCreate(Sender: TObject; badParam: Integer);' + #13#10 +
    '  end;' + #13#10 +
    #13#10 +
    'var' + #13#10 +
    '  MainForm: TMainForm;' + #13#10 +
    #13#10 +
    'implementation' + #13#10 +
    #13#10 +
    '{$R *.dfm}' + #13#10 +
    #13#10 +
    'procedure TMainForm.FormCreate(Sender: TObject; badParam: Integer);' + #13#10 +
    'begin' + #13#10 +
    'end;' + #13#10 +
    #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lDfmPath,
    'object MainForm: TMainForm' + #13#10 +
    '  OnCreate = FormCreate' + #13#10 +
    'end' + #13#10, TEncoding.UTF8);

  lArgs := 'dfm-check --dproj ' + QuoteArg(lDprojPath) +
    ' --delphi ' + lDelphiVersion +
    ' --config Release --platform Win32 --rsvars ' + QuoteArg(lRsVarsPath);
  Assert.IsTrue(RunProcess(lResolverPath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for dfm-check integration test.');

  if FileExists(lLogPath) then
    lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8)
  else
    lOutputText := '';

  Assert.IsTrue(lExitCode <> 0, 'Expected wrong event signature to produce non-zero dfm-check exit code.');
  Assert.IsTrue(Pos('FAIL ', lOutputText) > 0, 'Expected FAIL line in dfm-check output.');
  Assert.IsTrue((Pos('OnCreate', lOutputText) > 0) or (Pos('FormCreate', lOutputText) > 0),
    'Expected dfm-check output to mention failing event property/handler.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmCheckTests);

end.
