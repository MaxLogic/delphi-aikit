unit Test.PascalAnalyzer;

interface

uses
  System.IOUtils, System.RegularExpressions, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  Dak.ExternalToolProcess,
  Dak.PascalAnalyzerRunner, Dak.Types,
  Test.Support;

type
  [TestFixture]
  TPascalAnalyzerTests = class
  public
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
  end;

implementation

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

  lArgs := 'analyze --project ' + QuoteArg(TPath.Combine(RepoRoot, 'projects\\DelphiAIKit.dproj')) +
    ' --platform Win32 --config Release --delphi 23.0 --fixinsight false --pascal-analyzer true' +
    ' --out ' + QuoteArg(lOutDir) +
    ' --pa-path ' + QuoteArg(lPalCmdExe) +
    ' --pa-output ' + QuoteArg(lOutDir) +
    ' --pa-args "/F=X /Q /A+ /FA /T=' + DefaultPalThreads.ToString + '"';

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

  lFiles := TDirectory.GetFiles(lOutDir, '*.xml', TSearchOption.soAllDirectories);
  Assert.IsTrue(Length(lFiles) > 0, 'No XML report produced under: ' + lOutDir);
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

initialization
  TDUnitX.RegisterTestFixture(TPascalAnalyzerTests);

end.
