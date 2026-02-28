unit Test.DfmCheck;

interface

uses
  DUnitX.TestFramework,
  System.Classes, System.IOUtils, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  Dak.DfmCheck, Dak.Types,
  Test.Support;

type
  TMockValidatorMode = (vmHappy, vmBroken);

  TMockDfmCheckRunner = class(TInterfacedObject, IDfmCheckProcessRunner)
  private
    fGeneratedDproj: string;
    fConfig: string;
    fMode: TMockValidatorMode;
    fPlatform: string;
    fRunCount: Integer;
    function ReadFirstArg(const aArguments: string): string;
  public
    constructor Create(const aMode: TMockValidatorMode; const aConfig: string; const aPlatform: string);
    function Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
      const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
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
    procedure MapExitCodePropagatesToolAndCategoryCodes;
    [Test]
    procedure PipelineHappyPathWithMockRunner;
    [Test]
    procedure PipelineBrokenDfmPropagatesValidatorExitAndFailText;
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
    lDprojPath := ReadFirstArg(aArguments);
    if lDprojPath = '' then
    begin
      aError := 'Mock expected generated dproj as first msbuild argument.';
      Exit(False);
    end;
    fGeneratedDproj := lDprojPath;
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
      end else
      begin
        aOutput('OK   MAINFORM');
      end;
    end;

    if fMode = TMockValidatorMode.vmBroken then
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
  TFile.WriteAllText(TPath.Combine(aInjectDir, 'autoFree.pas'), 'unit autoFree; interface implementation end.',
    TEncoding.UTF8);
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
  Assert.AreEqual(34, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecBuildFailed, 0));
  Assert.AreEqual(9, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecValidatorFailed, 9));
end;

procedure TDfmCheckTests.PipelineHappyPathWithMockRunner;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPaths: TDfmCheckPaths;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunner: IDfmCheckProcessRunner;
  lPatchedDprText: string;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-happy');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  lOutputLines := TStringList.Create;
  try
    lRunner := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
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

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lPatchedDprText := TFile.ReadAllText(lPaths.fGeneratedDpr);
    Assert.IsTrue(Pos('DfmStreamAll,', lPatchedDprText) > 0, 'Expected DfmStreamAll in patched DPR.');
    Assert.IsTrue(Pos('ExitCode := TDfmStreamAll.Run;', lPatchedDprText) > 0,
      'Expected ExitCode assignment in patched DPR.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBrokenDfmPropagatesValidatorExitAndFailText;
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
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-broken');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  lOutputLines := TStringList.Create;
  try
    lRunner := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBroken, 'Release', 'Win32');
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
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    lOutputLines.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmCheckTests);

end.
