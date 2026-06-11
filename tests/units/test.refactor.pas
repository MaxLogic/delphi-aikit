unit Test.Refactor;

interface

uses
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  DUnitX.TestFramework,
  Test.Support;

type
  [TestFixture]
  TRefactorCommandTests = class
  private
    procedure CreateFixtureProject(const aRoot: string; out aDprojPath, aUnitOnePath,
      aUnitTwoPath: string);
  public
    [Test]
    procedure FindUsagesCommandReportsProjectScopedReferencesAsJson;
    [Test]
    procedure RenameCommandDefaultsToDryRun;
    [Test]
    procedure RenameCommandAppliesEditsAndCreatesBackups;
    [Test]
    procedure RenameCommandAcceptsSourcePositionTarget;
    [Test]
    procedure RenameCommandReportsSemanticPhaseMetricsAsJson;
    [Test]
    procedure RenameSemanticCacheUsesToolchainIdentity;
    [Test]
    procedure RefactorCommandsUseDelphiSemanticsProjectSession;
  end;

implementation

procedure TRefactorCommandTests.CreateFixtureProject(const aRoot: string; out aDprojPath,
  aUnitOnePath, aUnitTwoPath: string);
var
  lDprPath: string;
begin
  ForceDirectories(aRoot);
  aDprojPath := TPath.Combine(aRoot, 'RefactorFixture.dproj');
  lDprPath := TPath.Combine(aRoot, 'RefactorFixture.dpr');
  aUnitOnePath := TPath.Combine(aRoot, 'UnitOne.pas');
  aUnitTwoPath := TPath.Combine(aRoot, 'UnitTwo.pas');

  TFile.WriteAllText(lDprPath,
    'program RefactorFixture;' + sLineBreak +
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
    'end.' + sLineBreak,
    TEncoding.UTF8);

  TFile.WriteAllText(aDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>RefactorFixture.dpr</MainSource>' + sLineBreak +
    '    <DCC_UnitSearchPath>$(PROJECTDIR)</DCC_UnitSearchPath>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <DCCReference Include="RefactorFixture.dpr"/>' + sLineBreak +
    '    <DCCReference Include="UnitOne.pas"/>' + sLineBreak +
    '    <DCCReference Include="UnitTwo.pas"/>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '</Project>' + sLineBreak,
    TEncoding.UTF8);
end;

procedure TRefactorCommandTests.FindUsagesCommandReportsProjectScopedReferencesAsJson;
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
  lRoot := TPath.Combine(TempRoot, 'refactor-find-usages');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'refactor-find-usages.log');

  Assert.IsTrue(RunProcess(ResolverExePath,
    'find-usages --project ' + QuoteArg(lDprojPath) + ' --symbol SharedValue --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start find-usages command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected find-usages to succeed. See: ' + lLogPath);

  lLogText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('"status":"resolved"', lLogText) > 0, 'Expected resolved JSON status. See: ' + lLogPath);
  Assert.IsTrue(Pos('"symbol":"SharedValue"', lLogText) > 0, 'Expected queried symbol in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"referenceReconciliationFallbackCount":', lLogText) > 0,
    'Expected reference reconciliation fallback metric in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"count":3', lLogText) > 0, 'Expected declaration plus two references. See: ' + lLogPath);
  Assert.IsTrue(Pos('UnitTwo.pas', lLogText) > 0, 'Expected cross-unit usage in JSON. See: ' + lLogPath);
end;

procedure TRefactorCommandTests.RenameCommandDefaultsToDryRun;
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
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-dry-run');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-dry-run.log');

  Assert.IsTrue(RunProcess(ResolverExePath,
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format text',
    RepoRoot, lLogPath, lExitCode), 'Failed to start rename command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected dry-run rename to succeed. See: ' + lLogPath);

  lLogText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('rename: planned', LowerCase(lLogText)) > 0, 'Expected planned dry-run output.');
  Assert.IsTrue(Pos('apply: false', LowerCase(lLogText)) > 0, 'Expected dry-run apply flag in output.');
  Assert.IsTrue(Pos('SharedValue', TFile.ReadAllText(lUnitOnePath, TEncoding.UTF8)) > 0,
    'Dry-run must not edit declaration file.');
  Assert.IsTrue(Pos('SharedValue', TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8)) > 0,
    'Dry-run must not edit usage file.');
end;

procedure TRefactorCommandTests.RenameCommandAppliesEditsAndCreatesBackups;
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
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-apply');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-apply.log');

  Assert.IsTrue(RunProcess(ResolverExePath,
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --apply --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start rename apply command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected apply rename to succeed. See: ' + lLogPath);

  lLogText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('"apply":true', lLogText) > 0, 'Expected JSON apply flag. See: ' + lLogPath);
  Assert.IsTrue(Pos('"status":"applied"', lLogText) > 0, 'Expected applied status. See: ' + lLogPath);
  Assert.IsTrue(Pos('"referenceReconciliationFallbackCount":', lLogText) > 0,
    'Expected reference reconciliation fallback metric in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('RenamedValue', TFile.ReadAllText(lUnitOnePath, TEncoding.UTF8)) > 0,
    'Expected declaration file to be renamed.');
  Assert.IsTrue(Pos('RenamedValue', TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8)) > 0,
    'Expected usage file to be renamed.');
  Assert.AreEqual(0, Pos('SharedValue: Integer', TFile.ReadAllText(lUnitOnePath, TEncoding.UTF8)),
    'Expected declaration file to contain no old variable declaration after apply.');
  Assert.AreEqual(0, Pos('SharedValue := 2', TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8)),
    'Expected usage file to contain no old assignment after apply.');
  Assert.IsTrue(Pos('\\.dak\\RefactorFixture\\rename\\', lLogText) > 0,
    'Expected run-scoped rename transaction backup path. See: ' + lLogPath);
  Assert.IsTrue(Pos('UnitOne.pas.bak', lLogText) > 0, 'Expected backup for declaration file.');
  Assert.IsTrue(Pos('UnitTwo.pas.bak', lLogText) > 0, 'Expected backup for usage file.');
end;

procedure TRefactorCommandTests.RenameCommandAcceptsSourcePositionTarget;
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
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-position');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-position.log');

  Assert.IsTrue(RunProcess(ResolverExePath,
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --file ' + QuoteArg(lUnitOnePath) + ' --line 6 --col 3' +
    ' --new-name RenamedValue --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start rename position command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected position rename dry-run to succeed. See: ' + lLogPath);

  lLogText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('"status":"planned"', lLogText) > 0, 'Expected planned status. See: ' + lLogPath);
  Assert.IsTrue(Pos('"symbol":"SharedValue"', lLogText) > 0, 'Expected resolved symbol. See: ' + lLogPath);
  Assert.IsTrue(Pos('"referenceReconciliationFallbackCount":', lLogText) > 0,
    'Expected reference reconciliation fallback metric in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('RenamedValue', lLogText) > 0, 'Expected planned rename text. See: ' + lLogPath);
  Assert.IsTrue(Pos('SharedValue', TFile.ReadAllText(lUnitOnePath, TEncoding.UTF8)) > 0,
    'Dry-run position rename must not edit declaration file.');
end;

procedure TRefactorCommandTests.RenameCommandReportsSemanticPhaseMetricsAsJson;
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
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-phase-metrics');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-phase-metrics.log');

  Assert.IsTrue(RunProcess(ResolverExePath,
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start rename command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected rename to succeed. See: ' + lLogPath);

  lLogText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('"semanticPhaseMetrics":{', lLogText) > 0,
    'Expected semantic phase metrics object in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"status":"planned"', lLogText) > 0,
    'Existing rename status contract must remain present. See: ' + lLogPath);
  Assert.IsTrue(Pos('"editCount":3', lLogText) > 0,
    'Existing edit count contract must remain present. See: ' + lLogPath);
  Assert.IsTrue(Pos('"projectContextMs":', lLogText) > 0,
    'Expected project context timing in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"projectUnitIndexMs":', lLogText) > 0,
    'Expected project unit index timing in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"projectUnitCount":', lLogText) > 0,
    'Expected indexed project unit count in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"unitModelExtractionMs":', lLogText) > 0,
    'Expected unit model extraction timing in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"unitModelExtractionCount":', lLogText) > 0,
    'Expected unit model extraction count in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"projectSymbolIndexBuildMs":', lLogText) > 0,
    'Expected project symbol index timing in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"projectSymbolIndexBuildCount":', lLogText) > 0,
    'Expected project symbol index build count in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"commandPlanningMs":', lLogText) > 0,
    'Expected command planning timing in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"commandPlanningCount":1', lLogText) > 0,
    'Expected command planning count in JSON. See: ' + lLogPath);
end;

procedure TRefactorCommandTests.RenameSemanticCacheUsesToolchainIdentity;
var
  lCachePath: string;
  lDebugLogPath: string;
  lDebugLogText: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lReleaseLogPath: string;
  lReleaseLogText: string;
  lRoot: string;
  lUnitOnePath: string;
  lUnitTwoPath: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-cache-toolchain');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lCachePath := TPath.Combine(lRoot, 'semantic-cache.sqlite3');
  lDebugLogPath := TPath.Combine(TempRoot, 'refactor-rename-cache-debug.log');
  lReleaseLogPath := TPath.Combine(TempRoot, 'refactor-rename-cache-release.log');

  Assert.IsTrue(RunProcess(ResolverExePath,
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json' +
    ' --semantic-cache ' + QuoteArg(lCachePath) +
    ' --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lDebugLogPath, lExitCode), 'Failed to start debug rename command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected debug rename to succeed. See: ' + lDebugLogPath);

  lDebugLogText := TFile.ReadAllText(lDebugLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('"semanticCacheHits":0', lDebugLogText) > 0,
    'Expected cold debug cache run to avoid hits. See: ' + lDebugLogPath);
  Assert.IsFalse(Pos('"semanticCacheMisses":0', lDebugLogText) > 0,
    'Expected cold debug cache run to record misses. See: ' + lDebugLogPath);

  Assert.IsTrue(RunProcess(ResolverExePath,
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json' +
    ' --semantic-cache ' + QuoteArg(lCachePath) +
    ' --delphi 23.0 --platform Win32 --config Release',
    RepoRoot, lReleaseLogPath, lExitCode), 'Failed to start release rename command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected release rename to succeed. See: ' + lReleaseLogPath);

  lReleaseLogText := TFile.ReadAllText(lReleaseLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('"semanticCacheHits":0', lReleaseLogText) > 0,
    'Changing config must not hit entries created for another toolchain identity. See: ' + lReleaseLogPath);
  Assert.IsFalse(Pos('"semanticCacheMisses":0', lReleaseLogText) > 0,
    'Changing config should rebuild semantic unit models. See: ' + lReleaseLogPath);
  Assert.IsFalse(Pos('"semanticCacheInvalidations":0', lReleaseLogText) > 0,
    'Changing config should invalidate same-unit cache entries with different keys. See: ' + lReleaseLogPath);
end;

procedure TRefactorCommandTests.RefactorCommandsUseDelphiSemanticsProjectSession;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.Refactor.pas'), TEncoding.UTF8);

  Assert.IsFalse(ContainsText(lSource, 'DelphiAST.ProjectIndexer'),
    'DAK refactor commands should not own project indexing.');
  Assert.IsFalse(ContainsText(lSource, 'TDelphiSemanticUnitModelExtractor'),
    'DAK refactor commands should not extract semantic unit models directly.');
  Assert.IsFalse(ContainsText(lSource, 'DelphiSemantics.Cache.Sqlite'),
    'DAK refactor commands should not own semantic cache implementation selection.');
  Assert.IsTrue(ContainsText(lSource, 'TDelphiSemanticProjectSession.Open'),
    'DAK refactor commands should open a DelphiSemantics project session.');
end;

initialization
  TDUnitX.RegisterTestFixture(TRefactorCommandTests);

end.
