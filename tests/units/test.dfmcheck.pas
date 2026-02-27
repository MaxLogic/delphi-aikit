unit Test.DfmCheck;

interface

uses
  DUnitX.TestFramework,
  System.Classes, System.IOUtils, System.SysUtils,
  Winapi.Windows,
  Dak.DfmCheck, Dak.Types,
  Test.Support;

type
  TMockValidatorMode = (vmHappy, vmBroken);

  TMockDfmCheckRunner = class(TInterfacedObject, IDfmCheckProcessRunner)
  private
    fMode: TMockValidatorMode;
    fProjectDproj: string;
    fConfig: string;
    fPlatform: string;
    fRunCount: Integer;
    fGeneratedDir: string;
    fGeneratedDproj: string;
    fGeneratedDpr: string;
  public
    constructor Create(const aMode: TMockValidatorMode; const aProjectDproj: string; const aConfig: string;
      const aPlatform: string);
    function Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
      const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
    property GeneratedDpr: string read fGeneratedDpr;
  end;

  [TestFixture]
  TDfmCheckTests = class
  private
    procedure WriteInjectStubs(const aInjectDir: string);
    procedure CreateFixtureProject(out aProjectDproj: string; out aDfmCheckExePath: string);
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

constructor TMockDfmCheckRunner.Create(const aMode: TMockValidatorMode; const aProjectDproj: string;
  const aConfig: string; const aPlatform: string);
begin
  inherited Create;
  fMode := aMode;
  fProjectDproj := aProjectDproj;
  fConfig := aConfig;
  fPlatform := aPlatform;
  fRunCount := 0;
end;

function TMockDfmCheckRunner.Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
  const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
var
  lProjectDir: string;
  lProjectName: string;
  lValidatorDir: string;
  lValidatorExePath: string;
begin
  Result := True;
  aError := '';
  aExitCode := 0;
  Inc(fRunCount);

  if fRunCount = 1 then
  begin
    lProjectName := TPath.GetFileNameWithoutExtension(fProjectDproj);
    lProjectDir := ExtractFilePath(fProjectDproj);
    fGeneratedDir := TPath.Combine(lProjectDir, lProjectName + '_DfmCheck');
    fGeneratedDproj := TPath.Combine(fGeneratedDir, lProjectName + '_DfmCheck.dproj');
    fGeneratedDpr := TPath.Combine(fGeneratedDir, lProjectName + '_DfmCheck.dpr');
    TDirectory.CreateDirectory(fGeneratedDir);
    TFile.WriteAllText(fGeneratedDproj, '<Project/>', TEncoding.UTF8);
    TFile.WriteAllText(fGeneratedDpr,
      'program ' + lProjectName + '_DfmCheck;' + #13#10 +
      #13#10 +
      'uses' + #13#10 +
      '  System.SysUtils;' + #13#10 +
      #13#10 +
      'begin' + #13#10 +
      'end.' + #13#10, TEncoding.UTF8);
    Exit(True);
  end;

  if fRunCount = 2 then
  begin
    lValidatorDir := TPath.Combine(TPath.Combine(fGeneratedDir, fPlatform), fConfig);
    TDirectory.CreateDirectory(lValidatorDir);
    lValidatorExePath := TPath.Combine(lValidatorDir, TPath.GetFileNameWithoutExtension(fGeneratedDproj) + '.exe');
    TFile.WriteAllText(lValidatorExePath, 'mock', TEncoding.ASCII);
    Exit(True);
  end;

  if fRunCount = 3 then
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

procedure TDfmCheckTests.CreateFixtureProject(out aProjectDproj: string; out aDfmCheckExePath: string);
var
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'dfm-check-fixture');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  aProjectDproj := TPath.Combine(lRoot, 'Sample.dproj');
  TFile.WriteAllText(aProjectDproj, '<Project/>', TEncoding.UTF8);
  TFile.WriteAllText(TPath.ChangeExtension(aProjectDproj, '.dpr'),
    'program Sample;' + #13#10 + 'begin' + #13#10 + 'end.' + #13#10, TEncoding.UTF8);

  aDfmCheckExePath := TPath.Combine(lRoot, 'DFMCheck.exe');
  TFile.WriteAllText(aDfmCheckExePath, 'mock', TEncoding.ASCII);
end;

function TDfmCheckTests.JoinOutput(const aLines: TStrings): string;
begin
  Result := String.Join(#13#10, aLines.ToStringArray);
end;

procedure TDfmCheckTests.ResolveProjectPathMapsDprToSiblingDproj;
var
  lDprojPath: string;
  lDfmCheckExePath: string;
  lResolvedPath: string;
  lError: string;
begin
  CreateFixtureProject(lDprojPath, lDfmCheckExePath);
  Assert.IsTrue(TryResolveDfmCheckProjectPath(TPath.ChangeExtension(lDprojPath, '.dpr'), lResolvedPath, lError),
    'Expected .dpr input to map to sibling .dproj. Error: ' + lError);
  Assert.AreEqual(lDprojPath, lResolvedPath);
end;

procedure TDfmCheckTests.BuildExpectedPathsIsDeterministic;
var
  lDprojPath: string;
  lDfmCheckExePath: string;
  lPaths: TDfmCheckPaths;
begin
  CreateFixtureProject(lDprojPath, lDfmCheckExePath);
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
  lDfmCheckExePath: string;
  lError: string;
  lInjectDir: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunner: IDfmCheckProcessRunner;
  lRunnerObj: TMockDfmCheckRunner;
  lPatchedDprText: string;
begin
  CreateFixtureProject(lDprojPath, lDfmCheckExePath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-happy');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  lOutputLines := TStringList.Create;
  try
    lRunnerObj := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, lDprojPath, 'Release', 'Win32');
    lRunner := lRunnerObj;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fDfmCheckExePath := lDfmCheckExePath;
    lOptions.fHasDfmCheckExePath := True;
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
    Assert.IsTrue(Pos('[dfm-check] Running DFMCheck...', lOutputText) > 0, 'Missing DFMCheck stage log.');
    Assert.IsTrue(Pos('[dfm-check] Building generated DfmCheck project via MSBuild...', lOutputText) > 0,
      'Missing MSBuild stage log.');
    Assert.IsTrue(Pos('[dfm-check] Running validator exe...', lOutputText) > 0, 'Missing validator stage log.');
    Assert.IsTrue(Pos('OK   MAINFORM', lOutputText) > 0, 'Expected OK resource output from validator stage.');
    Assert.IsFalse(Pos('NON_DFM', lOutputText) > 0, 'Non-DFM resources should not be emitted in validator output.');

    lPatchedDprText := TFile.ReadAllText(lRunnerObj.GeneratedDpr);
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
  lDfmCheckExePath: string;
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
  CreateFixtureProject(lDprojPath, lDfmCheckExePath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-broken');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  lOutputLines := TStringList.Create;
  try
    lRunner := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBroken, lDprojPath, 'Release', 'Win32');
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fDfmCheckExePath := lDfmCheckExePath;
    lOptions.fHasDfmCheckExePath := True;
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
