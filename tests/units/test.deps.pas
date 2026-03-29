unit Test.Deps;

interface

uses
  DUnitX.TestFramework,
  System.JSON;

type
  [TestFixture]
  TDepsTests = class
  private
    function FixtureProjectPath: string;
    function FixtureDakRoot: string;
    function CycleProjectPath: string;
    function CycleDakRoot: string;
    procedure DeleteFolderIfExists(const aFolderPath: string);
    function FindNodeByName(const aNodes: TJSONArray; const aNodeName: string): TJSONObject;
    function RunDepsJson(const aProjectPath: string; const aLogFileName: string): TJSONObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure DepsJsonEmitsNodesEdgesAndProblems;
    [Test] procedure DepsJsonSurfacesUnresolvedUnits;
    [Test] procedure DepsJsonMarksSearchPathUnitsAsExternal;
    [Test] procedure DepsOutputAcceptsBareFileName;
    [Test] procedure DepsTextSummaryHighlightsCyclesAndUnresolvedUnits;
    [Test] procedure DepsUnitFocusLimitsNeighborhood;
    [Test] procedure DepsUnknownFocusDoesNotBorrowCycleComponentBySubstring;
    [Test] procedure DepsCyclesIgnoreUnresolvedAndExternalNodesByDefault;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Test.Support;

function TDepsTests.FixtureProjectPath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(RepoRoot, 'tests\fixtures\DepsFixture\DepsFixture.dproj'));
end;

function TDepsTests.FixtureDakRoot: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(FixtureProjectPath), '.dak');
end;

function TDepsTests.CycleProjectPath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(RepoRoot, 'tests\fixtures\DepsCycleFixture\DepsCycleFixture.dproj'));
end;

function TDepsTests.CycleDakRoot: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(CycleProjectPath), '.dak');
end;

procedure TDepsTests.DeleteFolderIfExists(const aFolderPath: string);
begin
  if TDirectory.Exists(aFolderPath) then
  begin
    TDirectory.Delete(aFolderPath, True);
  end;
end;

function TDepsTests.FindNodeByName(const aNodes: TJSONArray; const aNodeName: string): TJSONObject;
var
  lNodeValue: TJSONValue;
  lNode: TJSONObject;
begin
  for lNodeValue in aNodes do
  begin
    if not (lNodeValue is TJSONObject) then
    begin
      Continue;
    end;
    lNode := TJSONObject(lNodeValue);
    if SameText(lNode.GetValue('name').Value, aNodeName) then
    begin
      Exit(lNode);
    end;
  end;
  Result := nil;
end;

function TDepsTests.RunDepsJson(const aProjectPath: string; const aLogFileName: string): TJSONObject;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogFileName);
  lArgs := 'deps --project ' + QuoteArg(aProjectPath) + ' --format json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for deps JSON test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected deps JSON run to succeed. See: ' + lLogPath);
  Assert.IsTrue(TFile.Exists(lLogPath), 'Expected deps JSON log file. See: ' + lLogPath);

  lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Result := TJSONObject.ParseJSONValue(lOutputText) as TJSONObject;
  Assert.IsNotNull(Result, 'Expected deps JSON stdout. Output: ' + lOutputText);
end;

procedure TDepsTests.Setup;
begin
  DeleteFolderIfExists(FixtureDakRoot);
  DeleteFolderIfExists(CycleDakRoot);
end;

procedure TDepsTests.TearDown;
begin
  DeleteFolderIfExists(FixtureDakRoot);
  DeleteFolderIfExists(CycleDakRoot);
end;

procedure TDepsTests.DepsJsonEmitsNodesEdgesAndProblems;
var
  lJson: TJSONObject;
  lProjectJson: TJSONObject;
  lNodes: TJSONArray;
  lEdges: TJSONArray;
  lParserProblems: TJSONArray;
  lOutputPath: string;
begin
  lJson := RunDepsJson(FixtureProjectPath, 'deps-json.log');
  try
    lProjectJson := lJson.GetValue('project') as TJSONObject;
    lNodes := lJson.GetValue('nodes') as TJSONArray;
    lEdges := lJson.GetValue('edges') as TJSONArray;
    lParserProblems := lJson.GetValue('parserProblems') as TJSONArray;
    Assert.IsNotNull(lProjectJson);
    Assert.AreEqual('DepsFixture', lProjectJson.GetValue('name').Value);
    Assert.IsNotNull(lNodes);
    Assert.IsTrue(lNodes.Count >= 3, 'Expected at least three nodes.');
    Assert.IsNotNull(lEdges);
    Assert.IsTrue(lEdges.Count >= 2, 'Expected at least two edges.');
    Assert.IsNotNull(lParserProblems);
    Assert.IsTrue(lParserProblems.Count >= 1, 'Expected parser problems from broken fixture unit.');
  finally
    lJson.Free;
  end;

  lOutputPath := TPath.Combine(TPath.GetDirectoryName(FixtureProjectPath), '.dak\DepsFixture\deps\deps.json');
  Assert.IsTrue(TFile.Exists(lOutputPath), 'Expected default deps output file under sibling .dak folder.');
end;

procedure TDepsTests.DepsJsonSurfacesUnresolvedUnits;
var
  lJson: TJSONObject;
  lUnresolvedUnits: TJSONArray;
begin
  lJson := RunDepsJson(FixtureProjectPath, 'deps-json-unresolved.log');
  try
    lUnresolvedUnits := lJson.GetValue('unresolvedUnits') as TJSONArray;
    Assert.IsNotNull(lUnresolvedUnits);
    Assert.IsTrue(Pos('MissingFixture.Dependency', lUnresolvedUnits.ToJSON) > 0,
      'Expected unresolved unit list to include MissingFixture.Dependency.');
  finally
    lJson.Free;
  end;
end;

procedure TDepsTests.DepsJsonMarksSearchPathUnitsAsExternal;
var
  lJson: TJSONObject;
  lNode: TJSONObject;
  lNodes: TJSONArray;
begin
  lJson := RunDepsJson(FixtureProjectPath, 'deps-json-external.log');
  try
    lNodes := lJson.GetValue('nodes') as TJSONArray;
    Assert.IsNotNull(lNodes);
    lNode := FindNodeByName(lNodes, 'DepsFixtureSibling.External');
    Assert.IsNotNull(lNode, 'Expected resolved search-path unit in deps JSON nodes.');
    Assert.AreEqual('resolved', lNode.GetValue('resolution').Value);
    Assert.AreEqual('false', LowerCase(lNode.GetValue('isProjectUnit').Value),
      'Expected resolved search-path unit to remain external to the project directory.');
  finally
    lJson.Free;
  end;
end;

procedure TDepsTests.DepsOutputAcceptsBareFileName;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputPath: string;
  lOutputRoot: string;
begin
  EnsureResolverBuilt;
  lOutputRoot := TPath.Combine(TempRoot, 'deps-bare-output');
  DeleteFolderIfExists(lOutputRoot);
  ForceDirectories(lOutputRoot);
  lLogPath := TPath.Combine(TempRoot, 'deps-output-bare.log');
  lOutputPath := TPath.Combine(lOutputRoot, 'deps-output.json');
  lArgs := 'deps --project ' + QuoteArg(FixtureProjectPath) + ' --format json --output deps-output.json';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, lOutputRoot, lLogPath, lExitCode),
    'Failed to start resolver for bare output path test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected deps run with bare output path to succeed. See: ' + lLogPath);
  Assert.IsTrue(TFile.Exists(lOutputPath), 'Expected deps output file in the process working directory.');
end;

procedure TDepsTests.DepsTextSummaryHighlightsCyclesAndUnresolvedUnits;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'deps-cycle-text.log');
  lArgs := 'deps --project ' + QuoteArg(CycleProjectPath) + ' --format text';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for deps text summary test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected deps text run to succeed. See: ' + lLogPath);

  lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('Cycles', lOutputText) > 0, 'Expected cycle summary in deps text output.');
  Assert.IsTrue(Pos('MissingCycle.Dependency', lOutputText) > 0, 'Expected unresolved unit in deps text output.');
end;

procedure TDepsTests.DepsUnitFocusLimitsNeighborhood;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'deps-cycle-focus.log');
  lArgs := 'deps --project ' + QuoteArg(CycleProjectPath) + ' --format text --unit CycleA';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for deps focus test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected deps focus run to succeed. See: ' + lLogPath);

  lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('Focus unit: CycleA', lOutputText) > 0, 'Expected focus header for CycleA.');
  Assert.IsFalse(Pos('CycleConsumer', lOutputText) > 0, 'Expected focus output to omit unrelated project units.');
end;

procedure TDepsTests.DepsUnknownFocusDoesNotBorrowCycleComponentBySubstring;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'deps-cycle-focus-substring.log');
  lArgs := 'deps --project ' + QuoteArg(CycleProjectPath) + ' --format text --unit Cycle';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for deps focus substring test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected deps focus substring run to succeed. See: ' + lLogPath);

  lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('Focus unit: Cycle', lOutputText) > 0, 'Expected focus header for the requested unit token.');
  Assert.IsFalse(Pos('Cycle component:', lOutputText) > 0,
    'Expected unknown focus units to avoid borrowing cycle output by substring match.');
end;

procedure TDepsTests.DepsCyclesIgnoreUnresolvedAndExternalNodesByDefault;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'deps-cycle-filter.log');
  lArgs := 'deps --project ' + QuoteArg(CycleProjectPath) + ' --format text';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for deps cycle filtering test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected deps cycle filtering run to succeed. See: ' + lLogPath);

  lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('CycleA -> CycleB -> CycleA', lOutputText) > 0,
    'Expected cycle summary over resolved project units.');
  Assert.IsFalse(Pos('System.SysUtils', lOutputText) > 0,
    'Expected external units to stay out of cycle summaries by default.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDepsTests);

end.
