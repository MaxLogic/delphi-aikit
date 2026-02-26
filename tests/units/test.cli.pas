unit Test.Cli;

interface

uses
  DUnitX.TestFramework,
  System.IOUtils,
  System.SysUtils,
  maxLogic.CmdLineParams,
  Dak.Cli, Dak.Types,
  Test.Support;

type
  [TestFixture]
  TCliTests = class
  private
    function ToWslPath(const aWindowsPath: string): string;
  public
    procedure SetParams(const aCmdLine: string);
    [Test]
    procedure ResolveAcceptsUnixStyleProjectPath;
    [Test]
    procedure ResolveCommandAcceptsUnixStyleProjectPath;
    [Test]
    procedure ResolveCommandRejectsUnsupportedLinuxAbsoluteProjectPath;
    [Test]
    procedure AnalyzeUnitCommandRejectsUnsupportedLinuxAbsolutePath;
  end;

implementation

procedure TCliTests.SetParams(const aCmdLine: string);
var
  lParams: iCmdLineParams;
begin
  lParams := maxCmdLineParams;
  lParams.BuildFromString(aCmdLine);
end;

function TCliTests.ToWslPath(const aWindowsPath: string): string;
var
  lDrive: string;
  lRest: string;
  lPath: string;
begin
  lPath := Trim(aWindowsPath);
  if (Length(lPath) >= 3) and (lPath[2] = ':') and CharInSet(lPath[1], ['A'..'Z', 'a'..'z']) then
  begin
    lDrive := LowerCase(lPath[1]);
    lRest := Copy(lPath, 3, MaxInt);
    while lRest.StartsWith('\') or lRest.StartsWith('/') do
      lRest := Copy(lRest, 2, MaxInt);
    lRest := lRest.Replace('\', '/', [rfReplaceAll]);
    if lRest = '' then
      Exit('/mnt/' + lDrive);
    Exit('/mnt/' + lDrive + '/' + lRest);
  end;
  Result := lPath.Replace('\', '/', [rfReplaceAll]);
end;

procedure TCliTests.ResolveAcceptsUnixStyleProjectPath;
var
  lOptions: TAppOptions;
  lError: string;
  lProjectPath: string;
begin
  lProjectPath := '/mnt/f/projects/MaxLogic/DelphiAiKit/tests/fixtures/Sample.dproj';
  SetParams('resolve --project ' + lProjectPath + ' --delphi 23.0');
  Assert.IsTrue(TryParseOptions(lOptions, lError), 'Expected --project to accept Unix-style path. Error: ' + lError);
  Assert.AreEqual(lProjectPath, lOptions.fDprojPath);
end;

procedure TCliTests.ResolveCommandAcceptsUnixStyleProjectPath;
var
  lExitCode: Cardinal;
  lArgs: string;
  lProjectPath: string;
  lOutPath: string;
  lRunLog: string;
begin
  EnsureResolverBuilt;
  lProjectPath := ToWslPath(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'));
  lOutPath := TPath.Combine(TempRoot, 'resolve-linux-path.ini');
  lRunLog := TPath.Combine(TempRoot, 'resolve-linux-path.log');
  lArgs := 'resolve --project ' + lProjectPath + ' --platform Win32 --config Debug --delphi 23.0 --format ini --out-file ' +
    QuoteArg(lOutPath);

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start resolver process.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected Linux-style project path to resolve successfully. See: ' + lRunLog);
  Assert.IsTrue(FileExists(lOutPath), 'Expected resolve output file to be created: ' + lOutPath);
end;

procedure TCliTests.ResolveCommandRejectsUnsupportedLinuxAbsoluteProjectPath;
var
  lExitCode: Cardinal;
  lArgs: string;
  lOutPath: string;
  lRunLog: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lOutPath := TPath.Combine(TempRoot, 'resolve-linux-invalid.ini');
  lRunLog := TPath.Combine(TempRoot, 'resolve-linux-invalid.log');
  lArgs := 'resolve --project /home/not-supported/Sample.dproj --platform Win32 --config Debug --delphi 23.0 --format ini --out-file ' +
    QuoteArg(lOutPath);

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start resolver process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported Linux path to be rejected. See: ' + lRunLog);
  Assert.IsFalse(FileExists(lOutPath), 'Did not expect resolve output file when project path is invalid: ' + lOutPath);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := TFile.ReadAllText(lRunLog);
  Assert.IsTrue(Pos('Unsupported Linux path format', lLogText) > 0,
    'Expected unsupported Linux path error message. See: ' + lRunLog);
end;

procedure TCliTests.AnalyzeUnitCommandRejectsUnsupportedLinuxAbsolutePath;
var
  lExitCode: Cardinal;
  lArgs: string;
  lRunLog: string;
  lLogText: string;
begin
  EnsureResolverBuilt;
  lRunLog := TPath.Combine(TempRoot, 'analyze-unit-linux-invalid.log');
  lArgs := 'analyze --unit /home/not-supported/Sample.pas --delphi 23.0 --pascal-analyzer false';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lRunLog, lExitCode), 'Failed to start analyzer process.');
  Assert.AreEqual(Cardinal(3), lExitCode, 'Expected unsupported Linux unit path to be rejected. See: ' + lRunLog);

  lLogText := '';
  if FileExists(lRunLog) then
    lLogText := TFile.ReadAllText(lRunLog);
  Assert.IsTrue(Pos('Unsupported Linux path format', lLogText) > 0,
    'Expected unsupported Linux path error message. See: ' + lRunLog);
end;

initialization
  TDUnitX.RegisterTestFixture(TCliTests);

end.
