unit Test.RemoveWith;

interface

uses
  System.IOUtils, System.SysUtils,
  DUnitX.TestFramework,
  Test.Support;

type
  [TestFixture]
  TRemoveWithCommandTests = class
  public
    [Test]
    procedure ScanModeWritesJsonShellWithoutEditingSource;
  end;

implementation

procedure TRemoveWithCommandTests.ScanModeWritesJsonShellWithoutEditingSource;
var
  lArgs: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
  lSourceAfter: string;
  lSourceBefore: string;
  lUnitPath: string;
begin
  EnsureResolverBuilt;

  lDprojPath := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\LspProjectFixture.dproj');
  lUnitPath := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\Unit1.pas');
  lLogPath := TPath.Combine(TempRoot, 'remove-with-scan-shell.json');
  lSourceBefore := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);

  lArgs := 'remove-with --project ' + QuoteArg(lDprojPath) + ' --unit ' + QuoteArg(lUnitPath) +
    ' --mode scan --format json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start remove-with process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected remove-with scan shell to succeed. See: ' + lLogPath);

  lLogText := '';
  if FileExists(lLogPath) then
    lLogText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);

  Assert.IsTrue(Pos('"operation":"remove-with"', lLogText) > 0,
    'Expected operation in remove-with JSON output. See: ' + lLogPath);
  Assert.IsTrue(Pos('"mode":"scan"', lLogText) > 0, 'Expected scan mode in remove-with JSON output.');
  Assert.IsTrue(Pos('"workspace"', lLogText) > 0, 'Expected workspace object in remove-with JSON output.');
  Assert.IsTrue(Pos('remove-with', lLogText) > 0, 'Expected remove-with workspace path in JSON output.');
  Assert.IsTrue(Pos('"warnings":[]', lLogText) > 0, 'Expected empty warning array in shell output.');

  lSourceAfter := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  Assert.AreEqual(lSourceBefore, lSourceAfter, 'Scan mode must not modify the target unit.');
end;

end.
