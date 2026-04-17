unit Test.Build;

interface

uses
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  Dak.Build,
  Dak.Registry,
  Dak.Types,
  Test.Support;

type
  TCapturingBuildRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    fArguments: string;
    fArgumentsList: TArray<string>;
    fCallCount: Integer;
    fExePaths: TArray<string>;
    fFilesToCreateOnCall: TDictionary<Integer, string>;
    destructor Destroy; override;
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
    procedure BuildResolvesMadExceptOutputPathFromCfgDependentOnOptset;
    [Test]
    procedure BuildProjectPropertiesOverrideCfgDependentOnOptsetOutputPath;
    [Test]
    procedure BuildReportsSpecificErrorWhenResolvedMadExceptOutputIsMissing;
    [Test]
    procedure BuildIgnoresMissingCfgDependentOnOptsetWhenProjectOutputExists;
    [Test]
    procedure BuildWarnsOnInvalidDiagnosticsIniValues;
    [Test]
    procedure BuildWarnsWhenWin64NamespacesOmitWinapi;
    [Test]
    procedure BuildSummaryIncludesResolvedSourceContextForErrors;
    [Test]
    procedure BuildWebCoreCompilerResolutionPrefersCliOverDakIni;
    [Test]
    procedure BuildWebCoreCompilerResolutionUsesDakIniWhenCliMissing;
    [Test]
    procedure BuildWebCoreCompilerResolutionUsesEnvVarWhenDakIniMissing;
    [Test]
    procedure BuildWebCoreCompilerResolutionUsesPathWhenConfigMissing;
    [Test]
    procedure BuildWebCoreCompilerResolutionDoesNotProbeFixedPaths;
    [Test]
    procedure BuildWebCoreMissingCompilerReportsSupportedSources;
    [Test]
    procedure BuildWebCoreUsesCompilerFromCli;
    [Test]
    procedure BuildWebCoreRunsDebugPatchHook;
    [Test]
    procedure BuildWebCoreSkipsPatchHookOutsideDebug;
    [Test]
    procedure BuildWebCoreNoPwaOmitsPwaArgument;
    [Test]
    procedure BuildWebCoreAiBuildEmitsSuccessSummary;
    [Test]
    procedure BuildWebCorePlainBuildEmitsOutputPath;
    [Test]
    procedure BuildWebCoreJsonBuildEmitsSummary;
    [Test]
    procedure BuildAutoFallsBackToDelphiWhenWebCoreProbeNeedsEnvironment;
    [Test]
    procedure IdeConfigFallsBackToEnvOptionsWin64Alias;
    [Test]
    procedure ParseBuildLogsAppliesIgnoreAndExcludeFilters;
  end;

implementation

destructor TCapturingBuildRunner.Destroy;
begin
  if Assigned(fFilesToCreateOnCall) then
    fFilesToCreateOnCall.Free;
  inherited;
end;

function TCapturingBuildRunner.RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
  aTimeoutSec: Integer; out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
var
  lFileToCreate: string;
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
  if Assigned(fFilesToCreateOnCall) and fFilesToCreateOnCall.TryGetValue(lLength, lFileToCreate) then
  begin
    ForceDirectories(ExtractFileDir(lFileToCreate));
    TFile.WriteAllText(lFileToCreate, '', TEncoding.UTF8);
  end;
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

procedure PrepareMadExceptBuildFixtureWithOptset(const aRootDir, aMesText, aOptsetText,
  aProjectPropertyXml: string; out aDprojPath, aRsVarsPath, aPatchExePath: string);
var
  lDprPath: string;
  lFakeBdsRoot: string;
  lOptsetPath: string;
begin
  ForceDirectories(aRootDir);

  aDprojPath := TPath.Combine(aRootDir, 'MesGateCheck.dproj');
  lDprPath := TPath.ChangeExtension(aDprojPath, '.dpr');
  lOptsetPath := TPath.Combine(aRootDir, 'MesGateCheck.optset');
  aPatchExePath := TPath.Combine(aRootDir, 'madExceptPatch.exe');

  WriteUtf8File(aDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>MesGateCheck.dpr</MainSource>' + sLineBreak +
    '    <CfgDependentOn>MesGateCheck.optset</CfgDependentOn>' + sLineBreak +
    '    <DCC_Define>madExcept</DCC_Define>' + sLineBreak +
         aProjectPropertyXml +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lOptsetPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
         aOptsetText +
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

procedure PrepareMadExceptBuildFixtureWithMissingOptset(const aRootDir, aMesText, aProjectPropertyXml: string;
  out aDprojPath, aRsVarsPath, aPatchExePath: string);
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
    '    <CfgDependentOn>Missing.optset</CfgDependentOn>' + sLineBreak +
    '    <DCC_Define>madExcept</DCC_Define>' + sLineBreak +
         aProjectPropertyXml +
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
  lExpectedOutputPath: string;
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
  lExpectedOutputPath := TPath.Combine(lProjectRoot, 'MesGateCheck.exe');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
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

procedure TBuildTests.BuildResolvesMadExceptOutputPathFromCfgDependentOnOptset;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lExpectedOutputPath: string;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-optset-output-build');
  PrepareMadExceptBuildFixtureWithOptset(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    '    <DCC_ExeOutput>bin\$(CONFIG)\$(PLATFORM)</DCC_ExeOutput>' + sLineBreak,
    '', lDprojPath, lRsVarsPath, lPatchExePath);

  lExpectedOutputPath := TPath.Combine(lProjectRoot, 'bin\Debug\Win32\MesGateCheck.exe');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with imported optset output path. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected build to stay green when the imported optset output exists.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'Expected MSBuild followed by madExcept patch. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], 'bin\Debug\Win32\MesGateCheck.exe'),
    'Expected madExcept patch to target the imported optset output path. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildProjectPropertiesOverrideCfgDependentOnOptsetOutputPath;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lExpectedOutputPath: string;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-optset-override-output-build');
  PrepareMadExceptBuildFixtureWithOptset(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    '    <DCC_ExeOutput>optset-bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak,
    '    <DCC_ExeOutput>project-bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lExpectedOutputPath := TPath.Combine(lProjectRoot, 'project-bin\Debug\Win32\MesGateCheck.exe');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed when project output overrides imported optset output. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected project-local DCC_ExeOutput override to stay green.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'Expected MSBuild followed by madExcept patch. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], 'project-bin\Debug\Win32\MesGateCheck.exe'),
    'Expected madExcept patch to use the project-local output override. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsFalse(ContainsText(lCapturingRunner.fArgumentsList[1], 'optset-bin\Debug\Win32\MesGateCheck.exe'),
    'Expected imported optset output path to be overridden by the project file. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildReportsSpecificErrorWhenResolvedMadExceptOutputIsMissing;
var
  lCapturedOutput: string;
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExpectedMessage: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-optset-output-missing');
  PrepareMadExceptBuildFixtureWithOptset(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    '    <DCC_ExeOutput>bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak,
    '', lDprojPath, lRsVarsPath, lPatchExePath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fBuildJson := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      lError := '';
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected build command to complete and emit JSON output. Error: ' + lError);
    end);

  Assert.AreEqual(1, lExitCode, 'Expected missing resolved output path to fail the build.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'Expected madExcept patching to stop before invoking madExceptPatch.exe. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(Pos('"status":"internal_error"', lCapturedOutput) > 0,
    'Expected JSON summary to report internal_error. Output: ' + lCapturedOutput);
  lExpectedMessage := 'Resolved build output path does not exist: ' +
    StringReplace(TPath.Combine(lProjectRoot, 'bin\Debug\Win32\MesGateCheck.exe'), '\', '\\', [rfReplaceAll]);
  Assert.IsTrue(Pos(lExpectedMessage, lCapturedOutput) > 0,
    'Expected JSON summary to include the missing resolved output path. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.BuildIgnoresMissingCfgDependentOnOptsetWhenProjectOutputExists;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lExpectedOutputPath: string;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-missing-optset-output-build');
  PrepareMadExceptBuildFixtureWithMissingOptset(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    '    <DCC_ExeOutput>project-bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lExpectedOutputPath := TPath.Combine(lProjectRoot, 'project-bin\Debug\Win32\MesGateCheck.exe');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to stay non-fatal when CfgDependentOn points to a missing optset. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected missing CfgDependentOn optset to keep the build green.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'Expected MSBuild followed by madExcept patch even when the optset file is missing. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], 'project-bin\Debug\Win32\MesGateCheck.exe'),
    'Expected the fallback project output path to reach madExcept patching when the optset file is missing. Calls: ' +
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

procedure PrepareWebCoreBuildFixture(const aRootDir: string; out aDprojPath: string);
var
  lDprPath: string;
begin
  ForceDirectories(aRootDir);
  aDprojPath := TPath.Combine(aRootDir, 'WebCoreCheck.dproj');
  lDprPath := TPath.ChangeExtension(aDprojPath, '.dpr');
  WriteUtf8File(aDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>WebCoreCheck.dpr</MainSource>' + sLineBreak +
    '    <Config Condition="' + '''$(Config)''==''''">Debug</Config>' + sLineBreak +
    '    <Platform Condition="' + '''$(Platform)''==''''">Win32</Platform>' + sLineBreak +
    '    <TMSWebProject>2</TMSWebProject>' + sLineBreak +
    '    <TMSWebHTMLFile>index.html</TMSWebHTMLFile>' + sLineBreak +
    '    <TMSWebPWA>2</TMSWebPWA>' + sLineBreak +
    '    <DCC_UsePackage>TMSWEBCorePkgDXE15;$(DCC_UsePackage)</DCC_UsePackage>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program WebCoreCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);
end;

procedure PrepareWebCoreDebugHookFixture(const aRootDir: string; out aDprojPath: string);
var
  lIndexPath: string;
  lJsPath: string;
begin
  PrepareWebCoreBuildFixture(aRootDir, aDprojPath);
  WriteUtf8File(TPath.Combine(aRootDir, 'tools\patch-index-debug.ps1'),
    'param([string]$ProjectDir,[string]$Config,[string]$ProjectName)' + sLineBreak);

  lIndexPath := TPath.Combine(aRootDir, 'TMSWeb\Debug\index.html');
  lJsPath := TPath.Combine(aRootDir, 'TMSWeb\Debug\WebCoreCheck.js');
  WriteUtf8File(lIndexPath,
    '<html><body><script src="WebCoreCheck.js"></script></body></html>' + sLineBreak);
  WriteUtf8File(lJsPath, 'console.log("ok");' + sLineBreak);
end;

procedure TBuildTests.BuildWarnsWhenWin64NamespacesOmitWinapi;
var
  lAppData: string;
  lCapturedOutput: string;
  lCapturingRunner: TCapturingBuildRunner;
  lDprPath: string;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lError: string;
  lExitCode: Integer;
  lFakeBdsRoot: string;
  lFakeLibPath: string;
  lOptions: TAppOptions;
  lPrevAppData: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'build-preflight-win64-no-winapi');
  if TDirectory.Exists(lProjectRoot) then
    TDirectory.Delete(lProjectRoot, True);
  TDirectory.CreateDirectory(lProjectRoot);

  lDprojPath := TPath.Combine(lProjectRoot, 'Win64NamespaceCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>Win64NamespaceCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_ExeOutput>bin</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base_Win64)''!=''''">' + sLineBreak +
    '    <DCC_ConsoleTarget>true</DCC_ConsoleTarget>' + sLineBreak +
    '    <DCC_Namespace>System.Win;Data.Win;$(DCC_Namespace)</DCC_Namespace>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program Win64NamespaceCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(TempRoot, 'fake-bds-root-win64-warning');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  lRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(lRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');

  lFakeLibPath := TPath.Combine(lProjectRoot, 'fake-lib\win64');
  ForceDirectories(lFakeLibPath);
  lAppData := TPath.Combine(TempRoot, 'fake-appdata-win64-warning');
  lEnvOptionsPath := TPath.Combine(lAppData, 'Embarcadero\BDS\99.9\EnvOptions.proj');
  WriteUtf8File(lEnvOptionsPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Platform)''==''Win64x''">' + sLineBreak +
    '    <DelphiLibraryPath>' + lFakeLibPath + '</DelphiLibraryPath>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);

  lPrevAppData := GetEnvironmentVariable('APPDATA');
  Winapi.Windows.SetEnvironmentVariable('APPDATA', PChar(lAppData));
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win64';
    lOptions.fDelphiVersion := '99.9';
    lOptions.fRsVarsPath := lRsVarsPath;
    lOptions.fHasRsVarsPath := True;
    lOptions.fEnvOptionsPath := lEnvOptionsPath;
    lOptions.fHasEnvOptionsPath := True;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lCapturedOutput := CaptureConsoleOutput(
      procedure
      begin
        lError := '';
        Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
          'Expected build to succeed with fake toolchain. Error: ' + lError);
      end);

    Assert.AreEqual(0, lExitCode, 'Expected successful fake build.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one MSBuild launch.');
    Assert.IsTrue(Pos('does not include Winapi in the effective DCC_Namespace', lCapturedOutput) > 0,
      'Expected missing Winapi preflight warning. Output: ' + lCapturedOutput);
  finally
    lRunner := nil;
    lCapturingRunner := nil;
    if lPrevAppData <> '' then
      Winapi.Windows.SetEnvironmentVariable('APPDATA', PChar(lPrevAppData))
    else
      Winapi.Windows.SetEnvironmentVariable('APPDATA', nil);
  end;
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

procedure TBuildTests.BuildWebCoreCompilerResolutionPrefersCliOverDakIni;
var
  lCliCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lIniCompilerPath: string;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-cli-over-ini');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCliCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  lIniCompilerPath := TPath.Combine(lProjectRoot, 'ini\TMSWebCompiler.exe');
  WriteUtf8File(lCliCompilerPath, 'stub');
  WriteUtf8File(lIniCompilerPath, 'stub');
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + lIniCompilerPath + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCliCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore build to use the CLI compiler path. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one WebCore compiler launch.');
  Assert.IsTrue(SameText(lCliCompilerPath, lCapturingRunner.fExePaths[0]),
    'Expected CLI compiler path to win over dak.ini. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildWebCoreCompilerResolutionUsesDakIniWhenCliMissing;
var
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lIniCompilerPath: string;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-ini');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lIniCompilerPath := TPath.Combine(lProjectRoot, 'ini\TMSWebCompiler.exe');
  WriteUtf8File(lIniCompilerPath, 'stub');
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + lIniCompilerPath + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore build to use dak.ini compiler path. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one WebCore compiler launch.');
  Assert.IsTrue(SameText(lIniCompilerPath, lCapturingRunner.fExePaths[0]),
    'Expected dak.ini compiler path to be used when CLI is absent. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildWebCoreCompilerResolutionUsesEnvVarWhenDakIniMissing;
var
  lDprojPath: string;
  lEnvCompilerPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPrevCompilerPath: string;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-env');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lEnvCompilerPath := TPath.Combine(lProjectRoot, 'env\TMSWebCompiler.exe');
  WriteUtf8File(lEnvCompilerPath, 'stub');
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + TPath.Combine(lProjectRoot, 'missing\TMSWebCompiler.exe') + sLineBreak);

  lPrevCompilerPath := GetEnvironmentVariable('DAK_TMSWEB_COMPILER');
  Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', PChar(lEnvCompilerPath));
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fBuildBackend := TBuildBackend.bbWebCore;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected WebCore build to use DAK_TMSWEB_COMPILER. Error: ' + lError);
    Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one WebCore compiler launch.');
    Assert.IsTrue(SameText(lEnvCompilerPath, lCapturingRunner.fExePaths[0]),
      'Expected env var compiler path to be used when dak.ini is absent. Calls: ' +
      DescribeCapturedProcesses(lCapturingRunner));
  finally
    if lPrevCompilerPath <> '' then
      Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', PChar(lPrevCompilerPath))
    else
      Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', nil);
  end;
end;

procedure TBuildTests.BuildWebCoreCompilerResolutionUsesPathWhenConfigMissing;
var
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPathCompilerDir: string;
  lPathCompilerPath: string;
  lPreviousCompilerPath: string;
  lPreviousPath: string;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-path');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lPathCompilerDir := TPath.Combine(lProjectRoot, 'path-bin');
  lPathCompilerPath := TPath.Combine(lPathCompilerDir, 'TMSWebCompiler.exe');
  WriteUtf8File(lPathCompilerPath, 'stub');
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + TPath.Combine(lProjectRoot, 'missing\TMSWebCompiler.exe') + sLineBreak);

  lPreviousCompilerPath := GetEnvironmentVariable('DAK_TMSWEB_COMPILER');
  lPreviousPath := GetEnvironmentVariable('PATH');
  Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', nil);
  Winapi.Windows.SetEnvironmentVariable('PATH', PChar(lPathCompilerDir + ';' + lPreviousPath));
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fBuildBackend := TBuildBackend.bbWebCore;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected WebCore build to use TMSWebCompiler.exe from PATH. Error: ' + lError);
    Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one WebCore compiler launch.');
    Assert.IsTrue(SameText(lPathCompilerPath, lCapturingRunner.fExePaths[0]),
      'Expected PATH compiler path to be used when CLI, dak.ini, and env var are unavailable. Calls: ' +
      DescribeCapturedProcesses(lCapturingRunner));
  finally
    if lPreviousCompilerPath <> '' then
      Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', PChar(lPreviousCompilerPath))
    else
      Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', nil);
    if lPreviousPath <> '' then
      Winapi.Windows.SetEnvironmentVariable('PATH', PChar(lPreviousPath))
    else
      Winapi.Windows.SetEnvironmentVariable('PATH', nil);
  end;
end;

procedure TBuildTests.BuildWebCoreCompilerResolutionDoesNotProbeFixedPaths;
var
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPrevCompilerPath: string;
  lPrevPath: string;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-no-fixed-probe');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + TPath.Combine(lProjectRoot, 'missing\TMSWebCompiler.exe') + sLineBreak);

  lPrevCompilerPath := GetEnvironmentVariable('DAK_TMSWEB_COMPILER');
  lPrevPath := GetEnvironmentVariable('PATH');
  Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', nil);
  Winapi.Windows.SetEnvironmentVariable('PATH', PChar(lProjectRoot));
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fBuildBackend := TBuildBackend.bbWebCore;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsFalse(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected WebCore build to fail when only fixed machine paths could satisfy compiler discovery.');
    Assert.AreEqual(0, lCapturingRunner.fCallCount, 'No compiler should be launched when discovery fails.');
    Assert.IsFalse(ContainsText(lError, 'TMS-SmartSetUp'),
      'Compiler resolution must not mention hardcoded machine-specific probe paths. Error: ' + lError);
    Assert.IsFalse(ContainsText(lError, 'Program Files'),
      'Compiler resolution must not mention hardcoded install roots. Error: ' + lError);
  finally
    if lPrevCompilerPath <> '' then
      Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', PChar(lPrevCompilerPath))
    else
      Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', nil);
    if lPrevPath <> '' then
      Winapi.Windows.SetEnvironmentVariable('PATH', PChar(lPrevPath))
    else
      Winapi.Windows.SetEnvironmentVariable('PATH', nil);
  end;
end;

procedure TBuildTests.BuildWebCoreMissingCompilerReportsSupportedSources;
var
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPrevCompilerPath: string;
  lPrevPath: string;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-missing-message');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + TPath.Combine(lProjectRoot, 'missing\TMSWebCompiler.exe') + sLineBreak);

  lPrevCompilerPath := GetEnvironmentVariable('DAK_TMSWEB_COMPILER');
  lPrevPath := GetEnvironmentVariable('PATH');
  Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', nil);
  Winapi.Windows.SetEnvironmentVariable('PATH', PChar(lProjectRoot));
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fBuildBackend := TBuildBackend.bbWebCore;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsFalse(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected missing WebCore compiler resolution to fail.');
    Assert.AreEqual(0, lCapturingRunner.fCallCount, 'No compiler should be launched when discovery fails.');
    Assert.IsTrue(ContainsText(lError, '--webcore-compiler'),
      'Expected missing compiler message to mention the CLI override. Error: ' + lError);
    Assert.IsTrue(ContainsText(lError, '[WebCore]') and ContainsText(lError, 'CompilerPath'),
      'Expected missing compiler message to mention dak.ini settings. Error: ' + lError);
    Assert.IsTrue(ContainsText(lError, 'DAK_TMSWEB_COMPILER'),
      'Expected missing compiler message to mention the environment variable. Error: ' + lError);
    Assert.IsTrue(ContainsText(lError, 'PATH'),
      'Expected missing compiler message to mention PATH lookup. Error: ' + lError);
  finally
    if lPrevCompilerPath <> '' then
      Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', PChar(lPrevCompilerPath))
    else
      Winapi.Windows.SetEnvironmentVariable('DAK_TMSWEB_COMPILER', nil);
    if lPrevPath <> '' then
      Winapi.Windows.SetEnvironmentVariable('PATH', PChar(lPrevPath))
    else
      Winapi.Windows.SetEnvironmentVariable('PATH', nil);
  end;
end;

procedure TBuildTests.BuildWebCoreUsesCompilerFromCli;
var
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-auto-cli-compiler');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbAuto;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore auto build to use the CLI compiler path. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsTrue(lCapturingRunner.fCallCount >= 1, 'Expected at least one WebCore process launch.');
  Assert.IsTrue(SameText(lCompilerPath, lCapturingRunner.fExePaths[0]),
    'Expected auto-detected WebCore build to launch the CLI compiler path. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[0], '/ParseDprojFile'),
    'Expected WebCore compiler args to include /ParseDprojFile. Args: ' + lCapturingRunner.fArgumentsList[0]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[0], '/Config:Debug'),
    'Expected WebCore compiler args to include the selected config. Args: ' + lCapturingRunner.fArgumentsList[0]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[0], '/PWA'),
    'Expected WebCore builds to enable /PWA by default. Args: ' + lCapturingRunner.fArgumentsList[0]);
end;

procedure TBuildTests.BuildWebCoreRunsDebugPatchHook;
var
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-debug-hook');
  PrepareWebCoreDebugHookFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbAuto;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore build to run the debug patch hook. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'Expected compiler plus debug patch hook launches. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(ExtractFileName(lCapturingRunner.fExePaths[1]), 'powershell.exe'),
    'Expected the second launch to invoke PowerShell. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], 'patch-index-debug.ps1'),
    'Expected PowerShell args to target patch-index-debug.ps1. Args: ' + lCapturingRunner.fArgumentsList[1]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], '-ProjectDir'),
    'Expected PowerShell args to pass -ProjectDir. Args: ' + lCapturingRunner.fArgumentsList[1]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], '-Config') and
    ContainsText(lCapturingRunner.fArgumentsList[1], 'Debug'),
    'Expected PowerShell args to pass the build config. Args: ' + lCapturingRunner.fArgumentsList[1]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], '-ProjectName') and
    ContainsText(lCapturingRunner.fArgumentsList[1], 'WebCoreCheck'),
    'Expected PowerShell args to pass the project name. Args: ' + lCapturingRunner.fArgumentsList[1]);
end;

procedure TBuildTests.BuildWebCoreSkipsPatchHookOutsideDebug;
var
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-release-hook-skip');
  PrepareWebCoreDebugHookFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbAuto;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected non-Debug WebCore build to skip the patch hook cleanly. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'Expected only the WebCore compiler launch outside Debug. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildWebCoreNoPwaOmitsPwaArgument;
var
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-no-pwa');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;
  lOptions.fWebCorePwaEnabled := False;
  lOptions.fHasWebCorePwaEnabled := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore build with --no-pwa to complete successfully. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsFalse(ContainsText(lCapturingRunner.fArgumentsList[0], '/PWA'),
    'Expected explicit --no-pwa to omit /PWA from compiler args. Args: ' + lCapturingRunner.fArgumentsList[0]);
end;

procedure TBuildTests.BuildAutoFallsBackToDelphiWhenWebCoreProbeNeedsEnvironment;
var
  lDprPath: string;
  lDprojPath: string;
  lEnvImportPath: string;
  lError: string;
  lExitCode: Integer;
  lFakeBdsRoot: string;
  lOptions: TAppOptions;
  lPreviousImportPath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'auto-delphi-fallback');
  ForceDirectories(lProjectRoot);
  lDprojPath := TPath.Combine(lProjectRoot, 'AutoDelphiCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lEnvImportPath := TPath.Combine(lProjectRoot, 'env-import.props');
  WriteUtf8File(lEnvImportPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <ImportedFromEnv>1</ImportedFromEnv>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <Import Project="$(DAK_TEST_IMPORT)" />' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>AutoDelphiCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_ExeOutput>bin</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program AutoDelphiCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(lProjectRoot, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  lRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(lRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');

  lPreviousImportPath := GetEnvironmentVariable('DAK_TEST_IMPORT');
  Winapi.Windows.SetEnvironmentVariable('DAK_TEST_IMPORT', PChar(lEnvImportPath));
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fRsVarsPath := lRsVarsPath;
    lOptions.fBuildBackend := TBuildBackend.bbAuto;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected auto backend to fall back to Delphi when WebCore probing needs environment imports. Error: ' + lError);
    Assert.AreEqual(0, lExitCode, 'Expected fake Delphi build to succeed.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one MSBuild launch.');
    Assert.IsTrue(ContainsText(ExtractFileName(lCapturingRunner.fExePaths[0]), 'MSBuild.exe'),
      'Expected auto backend fallback to launch MSBuild. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  finally
    if lPreviousImportPath <> '' then
      Winapi.Windows.SetEnvironmentVariable('DAK_TEST_IMPORT', PChar(lPreviousImportPath))
    else
      Winapi.Windows.SetEnvironmentVariable('DAK_TEST_IMPORT', nil);
  end;
end;

procedure TBuildTests.BuildWebCoreAiBuildEmitsSuccessSummary;
var
  lCapturedOutput: string;
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-ai-summary');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;
  lOptions.fBuildAi := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      lError := '';
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected WebCore build to complete successfully. Error: ' + lError);
    end);

  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsTrue(Pos('SUCCESS.', lCapturedOutput) > 0,
    'Expected AI summary output for successful WebCore builds. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.BuildWebCorePlainBuildEmitsOutputPath;
var
  lCapturedOutput: string;
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-plain-summary');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      lError := '';
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected plain WebCore build summary to complete successfully. Error: ' + lError);
    end);

  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsTrue(Pos('Build succeeded:', lCapturedOutput) > 0,
    'Expected plain summary output to include the success banner. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('TMSWeb\Debug\index.html', lCapturedOutput) > 0,
    'Expected plain summary output to include the WebCore output path. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.BuildWebCoreJsonBuildEmitsSummary;
var
  lCapturedOutput: string;
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-json-summary');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;
  lOptions.fBuildJson := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      lError := '';
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected JSON WebCore build summary to complete successfully. Error: ' + lError);
    end);

  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsTrue(Pos('"status":"ok"', lCapturedOutput) > 0,
    'Expected JSON summary output to include the ok status. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('"output":"', lCapturedOutput) > 0,
    'Expected JSON summary output to include the output path. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('index.html', lCapturedOutput) > 0,
    'Expected JSON summary output to include the WebCore output file. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.IdeConfigFallsBackToEnvOptionsWin64Alias;
var
  lEnvOptionsPath: string;
  lEnvVars: TDictionary<string, string>;
  lError: string;
  lFakeLibPath: string;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lProjectRoot: string;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'ide-config-envoptions-alias');
  if TDirectory.Exists(lProjectRoot) then
    TDirectory.Delete(lProjectRoot, True);
  TDirectory.CreateDirectory(lProjectRoot);

  lFakeLibPath := TPath.Combine(lProjectRoot, 'fake-lib\win64');
  ForceDirectories(lFakeLibPath);
  lEnvOptionsPath := TPath.Combine(lProjectRoot, 'EnvOptions.proj');
  WriteUtf8File(lEnvOptionsPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Platform)''==''Win64x''">' + sLineBreak +
    '    <DelphiLibraryPath>' + lFakeLibPath + '</DelphiLibraryPath>' + sLineBreak +
    '    <DCC_Namespace>Winapi;System.Win</DCC_Namespace>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);

  lEnvVars := nil;
  try
    lError := '';
    Assert.IsTrue(TryReadIdeConfig('99.9', 'Win64', lEnvOptionsPath, lEnvVars, lLibraryPath, lLibrarySource, nil,
      lError), 'Expected EnvOptions fallback to succeed. Error: ' + lError);
    Assert.IsTrue(SameText(lLibraryPath, lFakeLibPath),
      'Expected DelphiLibraryPath from the Win64x EnvOptions block. Actual: ' + lLibraryPath);
    Assert.AreEqual(Integer(TPropertySource.psEnvOptions), Integer(lLibrarySource),
      'Expected EnvOptions to be reported as the library source.');
    Assert.IsTrue(Assigned(lEnvVars), 'Expected EnvOptions environment values to be captured.');
    Assert.IsTrue(lEnvVars.ContainsKey('DCC_Namespace'), 'Expected DCC_Namespace from EnvOptions to be captured.');
    Assert.AreEqual('Winapi;System.Win', lEnvVars['DCC_Namespace'],
      'Expected DCC_Namespace from the aliased Win64x block.');
  finally
    lEnvVars.Free;
  end;
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
