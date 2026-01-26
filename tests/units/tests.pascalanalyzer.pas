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

procedure TPascalAnalyzerTests.RunPascalAnalyzer;
var
  lPalCmdExe: string;
  lOutDir: string;
  lArgs: string;
  lExit: Cardinal;
  lFiles: TArray<string>;
  lLog: string;
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
    Assert.Fail('Pascal Analyzer run failed, exit=' + lExit.ToString + '. See: ' + lLog);

  lFiles := TDirectory.GetFiles(lOutDir, '*.xml', TSearchOption.soTopDirectoryOnly);
  Assert.IsTrue(Length(lFiles) > 0, 'No XML report produced in: ' + lOutDir);
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalAnalyzerTests);

end.
