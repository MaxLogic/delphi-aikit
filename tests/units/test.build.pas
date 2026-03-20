unit Test.Build;

interface

uses
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  Dak.Build,
  Dak.Types,
  Test.Support;

type
  TCapturingBuildRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    fArguments: string;
    fArgumentsList: TArray<string>;
    fCallCount: Integer;
    fExePaths: TArray<string>;
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      aTimeoutSec: Integer; out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
  end;

  TFailingBuildRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    fStdOutText: string;
    fStdErrText: string;
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      aTimeoutSec: Integer; out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
  end;

  [TestFixture]
  TBuildTests = class
  public
    [Test]
    procedure BuildResolverExe;
    [Test]
    procedure BuildCommandUsesNativeRunnerForExternalRepoProjects;
    [Test]
    procedure BuildCommandAddsEnvironmentProjPropsToMsBuildArgs;
    [Test]
    procedure BuildSkipsMadExceptPatchWhenMesDisablesMadExcept;
    [Test]
    procedure BuildSkipsMadExceptPatchWhenMesDisablesLinkInCode;
    [Test]
    procedure BuildSkipsMadExceptPatchWhenUtf8BomMesDisablesMadExcept;
    [Test]
    procedure BuildStillRunsMadExceptPatchWhenMesEnablesMadExcept;
    [Test]
    procedure BuildWarnsOnInvalidDiagnosticsIniValues;
    [Test]
    procedure BuildSummaryIncludesResolvedSourceContextForErrors;
    [Test]
    procedure ParseBuildLogsAppliesIgnoreAndExcludeFilters;
  end;

implementation

function TCapturingBuildRunner.RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
  aTimeoutSec: Integer; out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
var
  lLength: Integer;
begin
  Inc(fCallCount);
  fArguments := aArguments;
  lLength := Length(fExePaths);
  SetLength(fExePaths, lLength + 1);
  fExePaths[lLength] := aExePath;
  SetLength(fArgumentsList, lLength + 1);
  fArgumentsList[lLength] := aArguments;
  ForceDirectories(ExtractFileDir(aStdOutPath));
  TFile.WriteAllText(aStdOutPath, '', TEncoding.UTF8);
  TFile.WriteAllText(aStdErrPath, '', TEncoding.UTF8);
  aExitCode := 0;
  aTimedOut := False;
  aError := '';
  Result := True;
end;

function TFailingBuildRunner.RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
  aTimeoutSec: Integer; out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
begin
  ForceDirectories(ExtractFileDir(aStdOutPath));
  TFile.WriteAllText(aStdOutPath, fStdOutText, TEncoding.UTF8);
  TFile.WriteAllText(aStdErrPath, fStdErrText, TEncoding.UTF8);
  aExitCode := 1;
  aTimedOut := False;
  aError := '';
  Result := True;
end;

procedure WriteUtf8File(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.UTF8);
end;

procedure WriteIniTextFile(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.ASCII);
end;

function DescribeCapturedProcesses(const aRunner: TCapturingBuildRunner): string;
var
  i: Integer;
  lParts: TArray<string>;
begin
  SetLength(lParts, Length(aRunner.fExePaths));
  for i := 0 to High(aRunner.fExePaths) do
    lParts[i] := Format('%d:%s | %s', [i, aRunner.fExePaths[i], aRunner.fArgumentsList[i]]);
  Result := String.Join(' || ', lParts);
end;

function CaptureConsoleOutput(const aProc: TProc): string;
var
  lBytesRead: Cardinal;
  lChunk: AnsiString;
  lOldErr: THandle;
  lOldOut: THandle;
  lReadHandle: THandle;
  lSa: TSecurityAttributes;
  lWriteHandle: THandle;
  lBuffer: array[0..4095] of AnsiChar;
begin
  Result := '';
  FillChar(lSa, SizeOf(lSa), 0);
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;
  lReadHandle := 0;
  lWriteHandle := 0;
  if not CreatePipe(lReadHandle, lWriteHandle, @lSa, 0) then
    raise Exception.Create('Failed to create capture pipe.');
  try
    lOldOut := TTextRec(Output).Handle;
    lOldErr := TTextRec(ErrOutput).Handle;
    TTextRec(Output).Handle := lWriteHandle;
    TTextRec(ErrOutput).Handle := lWriteHandle;
    try
      aProc();
      Flush(Output);
      Flush(ErrOutput);
    finally
      TTextRec(Output).Handle := lOldOut;
      TTextRec(ErrOutput).Handle := lOldErr;
    end;

    CloseHandle(lWriteHandle);
    lWriteHandle := 0;
    while ReadFile(lReadHandle, lBuffer, SizeOf(lBuffer), lBytesRead, nil) and (lBytesRead > 0) do
    begin
      SetString(lChunk, PAnsiChar(@lBuffer[0]), lBytesRead);
      Result := Result + string(lChunk);
    end;
  finally
    if lWriteHandle <> 0 then
      CloseHandle(lWriteHandle);
    if lReadHandle <> 0 then
      CloseHandle(lReadHandle);
  end;
end;

procedure PrepareMadExceptBuildFixture(const aRootDir, aMesText: string; out aDprojPath, aRsVarsPath,
  aPatchExePath: string);
var
  lDprPath: string;
  lFakeBdsRoot: string;
begin
  ForceDirectories(aRootDir);

  aDprojPath := TPath.Combine(aRootDir, 'MesGateCheck.dproj');
  lDprPath := TPath.ChangeExtension(aDprojPath, '.dpr');
  aPatchExePath := TPath.Combine(aRootDir, 'madExceptPatch.exe');

  WriteUtf8File(aDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>MesGateCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_Define>madExcept</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program MesGateCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);
  WriteIniTextFile(TPath.ChangeExtension(aDprojPath, '.mes'), aMesText);
  WriteIniTextFile(TPath.Combine(aRootDir, 'dak.ini'),
    '[MadExcept]' + sLineBreak +
    'Path=' + aPatchExePath + sLineBreak);
  WriteUtf8File(aPatchExePath, 'stub' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(aRootDir, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  aRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(aRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');
end;

procedure TBuildTests.BuildResolverExe;
begin
  EnsureResolverBuilt;
  Assert.IsTrue(FileExists(ResolverExePath), 'Resolver exe not found: ' + ResolverExePath);
end;

procedure TBuildTests.BuildCommandUsesNativeRunnerForExternalRepoProjects;
var
  lCmd: string;
  lDprPath: string;
  lDprojPath: string;
  lExit: Cardinal;
  lExternalRoot: string;
  lLog: string;
  lLogText: string;
begin
  EnsureTempClean;
  lExternalRoot := TPath.Combine(TempRoot, 'external-build-root');
  if TDirectory.Exists(lExternalRoot) then
    TDirectory.Delete(lExternalRoot, True);
  ForceDirectories(TPath.Combine(lExternalRoot, '.git'));

  lDprojPath := TPath.Combine(lExternalRoot, 'ExternalBuildCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lLog := TPath.Combine(lExternalRoot, 'build.log');

  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>ExternalBuildCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_Define>madExcept</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program ExternalBuildCheck;' + sLineBreak +
    'begin' + sLineBreak +
    '  this does not compile' + sLineBreak +
    'end.' + sLineBreak);
  WriteUtf8File(TPath.ChangeExtension(lDprojPath, '.mes'), 'stub' + sLineBreak);

  Assert.IsTrue(
    RunProcess(
      ResolverExePath,
      'build --project ' + QuoteArg(lDprojPath) + ' --config Debug --platform Win32 --delphi 23.0 --ai',
      RepoRoot,
      lLog,
      lExit
    ),
    'Failed to start DelphiAIKit.exe build.'
  );

  lLogText := '';
  if FileExists(lLog) then
    lLogText := TFile.ReadAllText(lLog);

  Assert.AreNotEqual(Cardinal(0), lExit, 'The synthetic project must fail to compile so we can inspect build output.');

  Assert.IsFalse(
    ContainsText(lLogText, 'madExcept probe script not found'),
    'DelphiAIKit.exe still depends on the old helper-script probe path. Log: ' + lLog
  );
  Assert.IsFalse(
    ContainsText(lLogText, 'madExcept tool resolver script not found'),
    'DelphiAIKit.exe still depends on the old helper-script resolver path. Log: ' + lLog
  );
  Assert.IsTrue(
    ContainsText(lLogText, 'FAILED.'),
    'The native runner did not report a build failure summary. Log: ' + lLog
  );
end;

procedure TBuildTests.BuildCommandAddsEnvironmentProjPropsToMsBuildArgs;
var
  lAppData: string;
  lCapturingRunner: TCapturingBuildRunner;
  lDprPath: string;
  lDprojPath: string;
  lEnvProjPath: string;
  lError: string;
  lExitCode: Integer;
  lFakeBdsRoot: string;
  lOptions: TAppOptions;
  lPrevAppData: string;
  lPrevExistingProp: string;
  lPrevExistingPropPresent: Boolean;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lRsVarsPath: string;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'env-props-build');
  ForceDirectories(lProjectRoot);

  lDprojPath := TPath.Combine(lProjectRoot, 'EnvPropsCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>EnvPropsCheck.dpr</MainSource>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program EnvPropsCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(TempRoot, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  lRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(lRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');

  lAppData := TPath.Combine(TempRoot, 'fake-appdata');
  lEnvProjPath := TPath.Combine(lAppData, 'Embarcadero\BDS\23.0\environment.proj');
  WriteUtf8File(lEnvProjPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <FrameworkDirOverride>C:\Program Files\Reference Assemblies</FrameworkDirOverride>' + sLineBreak +
    '    <FrameworkVersionOverride>v4.8</FrameworkVersionOverride>' + sLineBreak +
    '    <ExistingProp>must-not-override</ExistingProp>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);

  lPrevAppData := GetEnvironmentVariable('APPDATA');
  lPrevExistingProp := GetEnvironmentVariable('ExistingProp');
  lPrevExistingPropPresent := lPrevExistingProp <> '';
  Winapi.Windows.SetEnvironmentVariable('APPDATA', PChar(lAppData));
  Winapi.Windows.SetEnvironmentVariable('ExistingProp', 'already-set');
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fRsVarsPath := lRsVarsPath;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected native build runner to succeed with fake toolchain. Error: ' + lError);
    Assert.AreEqual(0, lExitCode, 'The fake build runner should return success.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one MSBuild launch.');
    Assert.IsTrue(ContainsText(lCapturingRunner.fArguments,
      '/p:FrameworkDirOverride="C:\Program Files\Reference Assemblies"'),
      'Expected environment.proj property to be forwarded to MSBuild arguments.');
    Assert.IsTrue(ContainsText(lCapturingRunner.fArguments, '/p:FrameworkVersionOverride=v4.8'),
      'Expected environment.proj scalar property to be forwarded to MSBuild arguments.');
    Assert.IsFalse(ContainsText(lCapturingRunner.fArguments, '/p:ExistingProp=must-not-override'),
      'Existing process environment values must win over environment.proj overrides.');
  finally
    lRunner := nil;
    lCapturingRunner := nil;
    if lPrevAppData <> '' then
      Winapi.Windows.SetEnvironmentVariable('APPDATA', PChar(lPrevAppData))
    else
      Winapi.Windows.SetEnvironmentVariable('APPDATA', nil);
    if lPrevExistingPropPresent then
      Winapi.Windows.SetEnvironmentVariable('ExistingProp', PChar(lPrevExistingProp))
    else
      Winapi.Windows.SetEnvironmentVariable('ExistingProp', nil);
  end;
end;

procedure TBuildTests.BuildSkipsMadExceptPatchWhenMesDisablesMadExcept;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-disabled-build');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with fake toolchain. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Disabled madExcept in .mes should not fail the build.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'madExcept patch should be skipped when .mes disables exception handling. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(SameText(lCapturingRunner.fExePaths[0], TPath.Combine(TPath.GetDirectoryName(lRsVarsPath), 'MSBuild.exe')),
    'Expected the first process invocation to be MSBuild. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildSkipsMadExceptPatchWhenMesDisablesLinkInCode;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-link-disabled-build');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=0' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with fake toolchain. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Disabled LinkInCode in .mes should not fail the build.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'madExcept patch should be skipped when .mes disables LinkInCode. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(SameText(lCapturingRunner.fExePaths[0], TPath.Combine(TPath.GetDirectoryName(lRsVarsPath), 'MSBuild.exe')),
    'Expected the first process invocation to be MSBuild. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildSkipsMadExceptPatchWhenUtf8BomMesDisablesMadExcept;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-bom-disabled-build');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  WriteUtf8File(TPath.ChangeExtension(lDprojPath, '.mes'),
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=1' + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with fake toolchain. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'BOM-encoded disabled .mes should not fail the build.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'madExcept patch should be skipped when a UTF-8 BOM .mes disables exception handling. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(SameText(lCapturingRunner.fExePaths[0], TPath.Combine(TPath.GetDirectoryName(lRsVarsPath), 'MSBuild.exe')),
    'Expected the first process invocation to be MSBuild. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildStillRunsMadExceptPatchWhenMesEnablesMadExcept;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-enabled-build');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with fake toolchain. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Enabled madExcept in .mes should keep the patch step green.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'madExcept patch should run when .mes still enables exception handling. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(SameText(lCapturingRunner.fExePaths[1], lPatchExePath),
    'Expected the second process invocation to be madExceptPatch.exe. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildWarnsOnInvalidDiagnosticsIniValues;
var
  lCapturedOutput: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunnerImpl: TCapturingBuildRunner;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'build-invalid-diagnostics');
  if TDirectory.Exists(lProjectRoot) then
    TDirectory.Delete(lProjectRoot, True);
  TDirectory.CreateDirectory(lProjectRoot);

  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=0' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[MadExcept]' + sLineBreak +
    'Path=' + lPatchExePath + sLineBreak +
    '[Diagnostics]' + sLineBreak +
    'SourceContext=autoo' + sLineBreak +
    'SourceContextLines=abc' + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;

  lRunnerImpl := TCapturingBuildRunner.Create;
  lRunner := lRunnerImpl;
  lError := '';
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected build run to complete. Error: ' + lError);
    end);

  Assert.AreEqual(0, lExitCode, 'Expected scripted build success for warning-only configuration issue.');
  Assert.IsTrue(Pos('Invalid dak.ini SourceContext value: autoo', lCapturedOutput) > 0,
    'Expected invalid SourceContext warning in build output. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('Invalid dak.ini SourceContextLines value: abc', lCapturedOutput) > 0,
    'Expected invalid SourceContextLines warning in build output. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.BuildSummaryIncludesResolvedSourceContextForErrors;
var
  lCapturedOutput: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lFailingRunner: TFailingBuildRunner;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lDprPath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'build-source-context');
  if TDirectory.Exists(lProjectRoot) then
    TDirectory.Delete(lProjectRoot, True);
  TDirectory.CreateDirectory(lProjectRoot);

  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=0' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>' + TPath.GetFileName(lDprPath) + '</MainSource>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[MadExcept]' + sLineBreak +
    'Path=' + lPatchExePath + sLineBreak +
    '[Diagnostics]' + sLineBreak +
    'SourceContext=on' + sLineBreak +
    'SourceContextLines=1' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program MesGateCheck;' + sLineBreak +
    sLineBreak +
    'uses' + sLineBreak +
    '  BrokenUnit;' + sLineBreak +
    sLineBreak +
    'begin' + sLineBreak +
    '  Trigger;' + sLineBreak +
    'end.' + sLineBreak);
  WriteUtf8File(TPath.Combine(lProjectRoot, 'BrokenUnit.pas'),
    'unit BrokenUnit;' + sLineBreak +
    sLineBreak +
    'interface' + sLineBreak +
    sLineBreak +
    'procedure Trigger;' + sLineBreak +
    sLineBreak +
    'implementation' + sLineBreak +
    sLineBreak +
    'procedure Trigger;' + sLineBreak +
    'begin' + sLineBreak +
    '  MissingIdentifier := 1;' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'end.' + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;
  lOptions.fBuildAi := True;

  lFailingRunner := TFailingBuildRunner.Create;
  lFailingRunner.fStdErrText :=
    TPath.Combine(lProjectRoot, 'BrokenUnit.pas') + '(11): error E2003: Undeclared identifier: ''MissingIdentifier''' +
    sLineBreak;
  lRunner := lFailingRunner;
  lError := '';
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected scripted build run to complete. Error: ' + lError);
    end);

  Assert.AreEqual(1, lExitCode, 'Expected scripted build failure exit code.');
  Assert.IsTrue(Pos('BrokenUnit.pas(11): error E2003', lCapturedOutput) > 0,
    'Expected compiler error to be reported in summary output. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('source context:', LowerCase(lCapturedOutput)) > 0,
    'Expected build output to include resolved source context. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('MissingIdentifier := 1;', lCapturedOutput) > 0,
    'Expected build output to include the failing source line. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.ParseBuildLogsAppliesIgnoreAndExcludeFilters;
var
  lErrLog: string;
  lOutLog: string;
  lOptions: TBuildSummaryOptions;
  lSummary: TBuildSummary;
begin
  EnsureResolverBuilt;
  EnsureTempClean;
  lOutLog := TPath.Combine(TempRoot, 'build-parse.out.log');
  lErrLog := TPath.Combine(TempRoot, 'build-parse.err.log');

  WriteUtf8File(lErrLog,
    'F:\repo\src\main.pas(10): error E2003: Undeclared identifier: ''Foo''' + sLineBreak +
    'F:\repo\3rdParty\skip.pas(20): error E2003: Undeclared identifier: ''Bar''' + sLineBreak);
  WriteUtf8File(lOutLog,
    'F:\repo\src\warn1.pas(30): warning W1000: Visible warning' + sLineBreak +
    'F:\repo\src\warn2.pas(31): warning W2000: Ignored warning' + sLineBreak +
    'F:\repo\src\hint1.pas(40): hint H1000: Visible hint' + sLineBreak +
    'F:\repo\src\hint2.pas(41): hint H2000: Ignored hint' + sLineBreak);

  lOptions := Default(TBuildSummaryOptions);
  lOptions.fProjectRoot := 'F:\repo';
  lOptions.fIgnoreWarnings := 'W2000';
  lOptions.fIgnoreHints := 'H2000';
  lOptions.fExcludePathMasks := '3rdParty\*';
  lOptions.fMaxFindings := 5;
  lOptions.fIncludeWarnings := True;
  lOptions.fIncludeHints := True;

  lSummary := ParseBuildLogs(lOutLog, lErrLog, lOptions);

  Assert.AreEqual(1, lSummary.fErrorCount, 'Excluded paths must not contribute to error counts.');
  Assert.AreEqual(1, lSummary.fWarningCount, 'Ignored warnings must not contribute to warning counts.');
  Assert.AreEqual(1, lSummary.fHintCount, 'Ignored hints must not contribute to hint counts.');
  Assert.AreEqual(1, Length(lSummary.fErrors), 'Only one error finding should remain after path exclusion.');
  Assert.AreEqual(1, Length(lSummary.fWarnings), 'Ignored warnings must not be returned as findings.');
  Assert.AreEqual(1, Length(lSummary.fHints), 'Ignored hints must not be returned as findings.');
  Assert.AreEqual('src\main.pas(10): error E2003: Undeclared identifier: ''Foo''', lSummary.fErrors[0]);
  Assert.AreEqual('src\warn1.pas(30): warning W1000: Visible warning', lSummary.fWarnings[0]);
  Assert.AreEqual('src\hint1.pas(40): hint H1000: Visible hint', lSummary.fHints[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildTests);

end.
