unit Tests.PascalAnalyzer;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.IOUtils,
  Tests.Support;

type
  [TestFixture]
  TPascalAnalyzerTests = class
  public
    [Test]
    procedure RunPascalAnalyzer;
  end;

implementation

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

  lOutDir := TPath.Combine(TempRoot, 'pa-run');
  if not TDirectory.Exists(lOutDir) then
    TDirectory.CreateDirectory(lOutDir);

  lArgs := '--dproj ' + QuoteArg(TPath.Combine(RepoRoot, 'projects\\DelphiConfigResolver.dproj')) +
    ' --platform Win32 --config Release --delphi 23.0 --run-pascal-analyzer' +
    ' --pa-path ' + QuoteArg(lPalCmdExe) +
    ' --pa-output ' + QuoteArg(lOutDir);

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

initialization
  TDUnitX.RegisterTestFixture(TPascalAnalyzerTests);

end.
