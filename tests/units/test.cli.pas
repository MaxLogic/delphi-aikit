unit Test.Cli;

interface

uses
  DUnitX.TestFramework,
  maxLogic.CmdLineParams,
  Dak.Cli, Dak.Types;

type
  [TestFixture]
  TCliTests = class
  public
    procedure SetParams(const aCmdLine: string);
    [Test]
    procedure ResolveAcceptsUnixStyleProjectPath;
  end;

implementation

procedure TCliTests.SetParams(const aCmdLine: string);
var
  lParams: iCmdLineParams;
begin
  lParams := maxCmdLineParams;
  lParams.BuildFromString(aCmdLine);
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

initialization
  TDUnitX.RegisterTestFixture(TCliTests);

end.
