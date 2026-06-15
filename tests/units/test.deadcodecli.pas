unit Test.DeadCodeCli;

interface

uses
  System.IOUtils,
  System.SysUtils,
  DUnitX.TestFramework,
  DelphiSemantics.DeadCode,
  Test.Support;

type
  [TestFixture]
  TDeadCodeCliTests = class
  private
    procedure CreateFixtureProject(const aRoot: string; out aDprojPath, aUnitOnePath,
      aUnitTwoPath: string);
  public
    [Test]
    procedure ReportsJsonWithoutMutatingSources;
    [Test]
    procedure ReportsTextWithConservativeDefaultWithoutMutatingSources;
    [Test]
    procedure RejectsUnknownSafetyProfile;
  end;

implementation

procedure TDeadCodeCliTests.CreateFixtureProject(const aRoot: string; out aDprojPath,
  aUnitOnePath, aUnitTwoPath: string);
var
  lDprPath: string;
begin
  ForceDirectories(aRoot);
  aDprojPath := TPath.Combine(aRoot, 'DeadCodeFixture.dproj');
  lDprPath := TPath.Combine(aRoot, 'DeadCodeFixture.dpr');
  aUnitOnePath := TPath.Combine(aRoot, 'UnitOne.pas');
  aUnitTwoPath := TPath.Combine(aRoot, 'UnitTwo.pas');

  TFile.WriteAllText(lDprPath,
    'program DeadCodeFixture;' + sLineBreak +
    '' + sLineBreak +
    'uses' + sLineBreak +
    '  UnitOne,' + sLineBreak +
    '  UnitTwo;' + sLineBreak +
    '' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak,
    TEncoding.UTF8);

  TFile.WriteAllText(aUnitOnePath,
    'unit UnitOne;' + sLineBreak +
    '' + sLineBreak +
    'interface' + sLineBreak +
    '' + sLineBreak +
    'var' + sLineBreak +
    '  SharedValue: Integer;' + sLineBreak +
    '' + sLineBreak +
    'procedure TouchSharedValue;' + sLineBreak +
    '' + sLineBreak +
    'implementation' + sLineBreak +
    '' + sLineBreak +
    'procedure TouchSharedValue;' + sLineBreak +
    'begin' + sLineBreak +
    '  SharedValue := 1;' + sLineBreak +
    'end;' + sLineBreak +
    '' + sLineBreak +
    'end.' + sLineBreak,
    TEncoding.UTF8);

  TFile.WriteAllText(aUnitTwoPath,
    'unit UnitTwo;' + sLineBreak +
    '' + sLineBreak +
    'interface' + sLineBreak +
    '' + sLineBreak +
    'implementation' + sLineBreak +
    '' + sLineBreak +
    'uses' + sLineBreak +
    '  UnitOne;' + sLineBreak +
    '' + sLineBreak +
    'procedure UseSharedValue;' + sLineBreak +
    'begin' + sLineBreak +
    '  SharedValue := 2;' + sLineBreak +
    'end;' + sLineBreak +
    '' + sLineBreak +
    'procedure UnusedLocalRoutine;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    '' + sLineBreak +
    'end.' + sLineBreak,
    TEncoding.UTF8);

  TFile.WriteAllText(aDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>DeadCodeFixture.dpr</MainSource>' + sLineBreak +
    '    <DCC_UnitSearchPath>$(PROJECTDIR)</DCC_UnitSearchPath>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <DCCReference Include="DeadCodeFixture.dpr"/>' + sLineBreak +
    '    <DCCReference Include="UnitOne.pas"/>' + sLineBreak +
    '    <DCCReference Include="UnitTwo.pas"/>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '</Project>' + sLineBreak,
    TEncoding.UTF8);
end;

procedure TDeadCodeCliTests.ReportsJsonWithoutMutatingSources;
var
  lBeforeText: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
  lRoot: string;
  lUnitOnePath: string;
  lUnitTwoPath: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'dead-code-cli-report');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lBeforeText := TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8);
  lLogPath := TPath.Combine(TempRoot, 'dead-code-cli-report.json');

  Assert.IsTrue(RunResolverProcess(
    'dead-code --project ' + QuoteArg(lDprojPath) + ' --profile legacy-static --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start dead-code command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected dead-code report to succeed. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos('"status":"ok"', lLogText) > 0, 'Expected ok JSON status. See: ' + lLogPath);
  Assert.IsTrue(Pos('"profile":"legacy-static"', lLogText) > 0, 'Expected selected profile. See: ' + lLogPath);
  Assert.IsTrue(Pos('"safetyProfile":"legacy-static"', lLogText) > 0,
    'Expected candidate safety profile. See: ' + lLogPath);
  Assert.IsTrue(Pos('"name":"UnusedLocalRoutine"', lLogText) > 0,
    'Expected candidate name in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"blockers"', lLogText) > 0, 'Expected blocker list in JSON. See: ' + lLogPath);
  Assert.AreEqual(lBeforeText, TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8),
    'Report-only dead-code command must not mutate source files.');
end;

procedure TDeadCodeCliTests.RejectsUnknownSafetyProfile;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
  lRoot: string;
  lUnitOnePath: string;
  lUnitTwoPath: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'dead-code-cli-invalid-profile');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'dead-code-cli-invalid-profile.log');

  Assert.IsTrue(RunResolverProcess(
    'dead-code --project ' + QuoteArg(lDprojPath) + ' --profile typo --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start dead-code command.');
  Assert.AreNotEqual(Cardinal(0), lExitCode, 'Unknown profiles must fail. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos(Format('Invalid --profile value: typo (expected %s).',
    [TDelphiSemanticDeadCodeProfiles.AllowedNamesText]), lLogText) > 0,
    'Expected invalid profile diagnostic. See: ' + lLogPath);
end;

procedure TDeadCodeCliTests.ReportsTextWithConservativeDefaultWithoutMutatingSources;
var
  lBeforeText: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
  lRoot: string;
  lUnitOnePath: string;
  lUnitTwoPath: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'dead-code-cli-text-default');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lBeforeText := TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8);
  lLogPath := TPath.Combine(TempRoot, 'dead-code-cli-text-default.log');

  Assert.IsTrue(RunResolverProcess(
    'dead-code --project ' + QuoteArg(lDprojPath) + ' --format text',
    RepoRoot, lLogPath, lExitCode), 'Failed to start dead-code command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected dead-code report to succeed. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos('dead-code: report', lLogText) > 0, 'Expected text report header. See: ' + lLogPath);
  Assert.IsTrue(Pos('profile: ' + TDelphiSemanticDeadCodeProfiles.ToName(
    TDelphiSemanticDeadCodeProfiles.DefaultRemovalProfile), lLogText) > 0,
    'Expected conservative default profile. See: ' + lLogPath);
  Assert.IsTrue(Pos('UnusedLocalRoutine', lLogText) > 0,
    'Expected candidate name in text output. See: ' + lLogPath);
  Assert.AreEqual(lBeforeText, TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8),
    'Text dead-code report must not mutate source files.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeadCodeCliTests);

end.
