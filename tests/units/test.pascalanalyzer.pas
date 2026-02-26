unit Test.PascalAnalyzer;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Test.Support,
  Dak.PascalAnalyzerRunner,
  Dak.Types;

type
  [TestFixture]
  TPascalAnalyzerTests = class
  public
    [Test]
    procedure SelectsSupportedCompilerFlag;
    [Test]
    procedure RunPascalAnalyzer;
    [Test]
    procedure InvalidPalMapJsonRootDoesNotRaise;
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
  lMapSource: string;
  lMapTarget: string;
  lCopiedMap: Boolean;
begin
  RequirePalCmdOrSkip(lPalCmdExe);
  lMapSource := TPath.Combine(RepoRoot, 'bin\\palcmd-map.json');
  lMapTarget := TPath.Combine(ExtractFilePath(ParamStr(0)), 'palcmd-map.json');
  lCopiedMap := False;
  if FileExists(lMapSource) then
  begin
    TFile.Copy(lMapSource, lMapTarget, True);
    lCopiedMap := True;
  end;
  try
    lParams := Default(TFixInsightParams);
    lParams.fProjectDpr := TPath.Combine(RepoRoot, 'projects\\DelphiAIKit.dpr');
    lParams.fDelphiVersion := '23.0';
    lParams.fPlatform := 'Win32';
    lParams.fConfig := 'Release';

    lPa := Default(TPascalAnalyzerDefaults);
    lPa.fPath := lPalCmdExe;

    if not BuildPalCmdCommandLine(lParams, lPa, lExe, lCmdLine, lError) then
      Assert.Fail('BuildPalCmdCommandLine failed: ' + lError);

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
    Assert.IsTrue(PalCmdSupportsFlag(lPalCmdExe, lFlag), 'PALCMD help does not list flag: ' + lFlag);
    if PalCmdSupportsFlag(lPalCmdExe, '/CD12W32') then
      Assert.AreEqual('/CD12W32', lFlag, 'PALCMD supports Delphi 12, but a different flag was selected.');
  finally
    if lCopiedMap and FileExists(lMapTarget) then
      System.SysUtils.DeleteFile(lMapTarget);
  end;
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
  if not RunProcess(ResolverExePath, lArgs, RepoRoot, lLog, lExit) then
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

procedure TPascalAnalyzerTests.InvalidPalMapJsonRootDoesNotRaise;
var
  lMapPath: string;
  lBackupPath: string;
  lHadOriginal: Boolean;
  lParams: TFixInsightParams;
  lPa: TPascalAnalyzerDefaults;
  lExePath: string;
  lCmdLine: string;
  lError: string;
  lCmdExe: string;
  lSuccess: Boolean;
begin
  lMapPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'palcmd-map.json');
  lBackupPath := lMapPath + '.bak';
  lHadOriginal := FileExists(lMapPath);
  if lHadOriginal then
    TFile.Copy(lMapPath, lBackupPath, True);

  try
    TFile.WriteAllText(lMapPath, '[]', TEncoding.UTF8);

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
  finally
    if lHadOriginal then
      TFile.Copy(lBackupPath, lMapPath, True)
    else if FileExists(lMapPath) then
      TFile.Delete(lMapPath);

    if FileExists(lBackupPath) then
      TFile.Delete(lBackupPath);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalAnalyzerTests);

end.
