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
    function FindEdgeByNames(const aEdges: TJSONArray; const aFromName, aToName: string): TJSONObject;
    function FindNodeByName(const aNodes: TJSONArray; const aNodeName: string): TJSONObject;
    function RunDepsJson(const aProjectPath: string; const aLogFileName: string;
      const aExtraArgs: string = ''): TJSONObject;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure DepsJsonEmitsNodesEdgesAndProblems;
    [Test] procedure DepsJsonKeepsStableCompatibilityShape;
    [Test] procedure DepsJsonSurfacesUnresolvedUnits;
    [Test] procedure DepsJsonMarksSearchPathUnitsAsExternal;
    [Test] procedure DepsOutputAcceptsBareFileName;
    [Test] procedure DepsTextSummaryHighlightsCyclesAndUnresolvedUnits;
    [Test] procedure DepsUnitFocusLimitsNeighborhood;
    [Test] procedure DepsUnknownFocusDoesNotBorrowCycleComponentBySubstring;
    [Test] procedure DepsCyclesIgnoreUnresolvedAndExternalNodesByDefault;
    [Test] procedure DepsCyclesUseRealTraversalPaths;
    [Test] procedure DepsTextHotspotsRespectTopLimit;
    [Test] procedure DepsTextPrefersImplementationEdgesOnEqualRank;
    [Test] procedure DepsJsonIncludesCycleComponentsAndHotspots;
    [Test] procedure DepsJsonKeepsCyclesCompatibilityArray;
    [Test] procedure DepsJsonMarksCycleNodesAndEdges;
    [Test] procedure DepsJsonPrefersImplementationEdgesOnEqualRank;
    [Test] procedure DepsJsonExcludesUnresolvedUnitsFromHotspots;
    [Test] procedure DepsLinux64UsesTargetCompilerDefinesWithoutHostDefines;
    [Test] procedure DepsRunnerUsesSharedTypedSccAnalyzer;
    [Test] procedure DepsRunnerDelegatesGraphConstructionToProjectSession;
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

function TDepsTests.FindEdgeByNames(const aEdges: TJSONArray; const aFromName, aToName: string): TJSONObject;
var
  lEdge: TJSONObject;
  lEdgeValue: TJSONValue;
begin
  for lEdgeValue in aEdges do
  begin
    if not (lEdgeValue is TJSONObject) then
    begin
      Continue;
    end;
    lEdge := TJSONObject(lEdgeValue);
    if SameText(lEdge.GetValue('from').Value, aFromName) and SameText(lEdge.GetValue('to').Value, aToName) then
    begin
      Exit(lEdge);
    end;
  end;
  Result := nil;
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

function TDepsTests.RunDepsJson(const aProjectPath: string; const aLogFileName,
  aExtraArgs: string): TJSONObject;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogFileName);
  lArgs := 'deps --project ' + QuoteArg(aProjectPath) + ' --format json';
  if aExtraArgs <> '' then
    lArgs := lArgs + ' ' + aExtraArgs;

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

procedure TDepsTests.DepsJsonKeepsStableCompatibilityShape;
var
  lEdge: TJSONObject;
  lEdges: TJSONArray;
  lJson: TJSONObject;
  lNode: TJSONObject;
  lNodes: TJSONArray;
  lParserProblem: TJSONObject;
  lParserProblems: TJSONArray;
  lProjectJson: TJSONObject;
  lSummary: TJSONObject;
begin
  lJson := RunDepsJson(FixtureProjectPath, 'deps-json-shape.log');
  try
    lProjectJson := lJson.GetValue<TJSONObject>('project');
    Assert.IsNotNull(lProjectJson);
    Assert.AreEqual('DepsFixture', lProjectJson.GetValue<string>('name'));
    Assert.IsNotEmpty(lProjectJson.GetValue<string>('path'));
    Assert.IsNotEmpty(lProjectJson.GetValue<string>('mainSource'));
    Assert.AreEqual('degraded-project-only', lProjectJson.GetValue<string>('contextMode'));

    lSummary := lJson.GetValue<TJSONObject>('summary');
    Assert.IsNotNull(lSummary);
    Assert.IsTrue(lSummary.GetValue<Integer>('nodeCount') >= 3);
    Assert.IsTrue(lSummary.GetValue<Integer>('resolvedNodeCount') >= 2);
    Assert.IsTrue(lSummary.GetValue<Integer>('edgeCount') >= 2);
    Assert.IsTrue(lSummary.GetValue<Integer>('unresolvedUnitCount') >= 1);
    Assert.IsTrue(lSummary.GetValue<Integer>('parserProblemCount') >= 1);

    lNodes := lJson.GetValue<TJSONArray>('nodes');
    lNode := FindNodeByName(lNodes, 'DepsFixture.Main');
    Assert.IsNotNull(lNode, 'Expected main fixture node.');
    Assert.AreEqual('DepsFixture.Main', lNode.GetValue<string>('name'));
    Assert.IsNotEmpty(lNode.GetValue<string>('path'));
    Assert.AreEqual('true', LowerCase(lNode.GetValue<string>('isProjectUnit')));
    Assert.AreEqual('resolved', lNode.GetValue<string>('resolution'));
    Assert.IsNotNull(lNode.GetValue('unitCycleScore'), 'Expected stable unitCycleScore field.');
    Assert.IsNotNull(lNode.GetValue('sccId'), 'Expected stable sccId field.');

    lEdges := lJson.GetValue<TJSONArray>('edges');
    lEdge := FindEdgeByNames(lEdges, 'DepsFixture.Main', 'DepsFixture.Shared');
    Assert.IsNotNull(lEdge, 'Expected main-to-shared edge.');
    Assert.AreEqual('DepsFixture.Main', lEdge.GetValue<string>('from'));
    Assert.AreEqual('DepsFixture.Shared', lEdge.GetValue<string>('to'));
    Assert.IsNotEmpty(lEdge.GetValue<string>('edgeKind'));
    Assert.IsNotNull(lEdge.GetValue('isCycleEdge'), 'Expected stable isCycleEdge field.');

    lParserProblems := lJson.GetValue<TJSONArray>('parserProblems');
    Assert.IsTrue(lParserProblems.Count > 0, 'Expected parser problem compatibility payload.');
    lParserProblem := lParserProblems.Items[0] as TJSONObject;
    Assert.IsNotEmpty(lParserProblem.GetValue<string>('unitName'));
    Assert.IsNotEmpty(lParserProblem.GetValue<string>('fileName'));
    Assert.IsNotEmpty(lParserProblem.GetValue<string>('description'));
  finally
    lJson.Free;
  end;
end;

procedure TDepsTests.DepsLinux64UsesTargetCompilerDefinesWithoutHostDefines;
var
  lDprojPath: string;
  lDprPath: string;
  lJson: TJSONObject;
  lMainPath: string;
  lNodes: TJSONArray;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'deps-target-defines');
  DeleteFolderIfExists(lRoot);
  TDirectory.CreateDirectory(lRoot);

  lDprPath := TPath.Combine(lRoot, 'TargetDeps.dpr');
  lDprojPath := TPath.Combine(lRoot, 'TargetDeps.dproj');
  lMainPath := TPath.Combine(lRoot, 'TargetDeps.Main.pas');

  TFile.WriteAllText(lDprPath,
    'program TargetDeps;' + sLineBreak +
    'uses TargetDeps.Main;' + sLineBreak +
    'begin' + sLineBreak +
    'end.', TEncoding.UTF8);
  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>TargetDeps.dpr</MainSource>' + sLineBreak +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>' + sLineBreak +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>', TEncoding.UTF8);
  TFile.WriteAllText(lMainPath,
    'unit TargetDeps.Main;' + sLineBreak +
    'interface' + sLineBreak +
    'uses' + sLineBreak +
    '  System.SysUtils' + sLineBreak +
    '{$IFDEF LINUX}' + sLineBreak +
    '  , TargetDeps.LinuxOnly' + sLineBreak +
    '{$ENDIF}' + sLineBreak +
    '{$IFDEF MSWINDOWS}' + sLineBreak +
    '  , TargetDeps.HostOnly' + sLineBreak +
    '{$ENDIF}' + sLineBreak +
    '  ;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lRoot, 'TargetDeps.LinuxOnly.pas'),
    'unit TargetDeps.LinuxOnly;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'end.', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lRoot, 'TargetDeps.HostOnly.pas'),
    'unit TargetDeps.HostOnly;' + sLineBreak +
    'interface' + sLineBreak +
    'implementation' + sLineBreak +
    'end.', TEncoding.UTF8);

  lJson := RunDepsJson(lDprojPath, 'deps-target-defines.log', '--platform Linux64');
  try
    lNodes := lJson.GetValue<TJSONArray>('nodes');
    Assert.IsNotNull(FindNodeByName(lNodes, 'TargetDeps.LinuxOnly'), 'Expected Linux64 target branch.');
    Assert.IsNull(FindNodeByName(lNodes, 'TargetDeps.HostOnly'), 'Did not expect Windows host branch.');
  finally
    lJson.Free;
  end;
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
  Assert.IsTrue(Pos('Cycle components', lOutputText) > 0, 'Expected cycle component summary in deps text output.');
  Assert.IsTrue(Pos('Top cycle units', lOutputText) > 0, 'Expected unit hotspot section in deps text output.');
  Assert.IsTrue(Pos('Top cycle edges', lOutputText) > 0, 'Expected edge hotspot section in deps text output.');
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

procedure TDepsTests.DepsCyclesUseRealTraversalPaths;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'deps-cycle-real-path.log');
  lArgs := 'deps --project ' + QuoteArg(CycleProjectPath) + ' --format text';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for deps real cycle path test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected deps real cycle path run to succeed. See: ' + lLogPath);

  lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('PathCycleA -> PathCycleC -> PathCycleB -> PathCycleA', lOutputText) > 0,
    'Expected cycle output to use a real traversal path for PathCycle*.');
  Assert.IsFalse(Pos('PathCycleA -> PathCycleB -> PathCycleC -> PathCycleA', lOutputText) > 0,
    'Expected cycle output to avoid alphabetical SCC member joins that are not real paths.');
end;

procedure TDepsTests.DepsTextHotspotsRespectTopLimit;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'deps-cycle-top-limit.log');
  lArgs := 'deps --project ' + QuoteArg(CycleProjectPath) + ' --format text --top 1';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for deps top-limit text test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected deps text run with --top 1 to succeed. See: ' + lLogPath);

  lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('Top cycle units (up to 1):', lOutputText) > 0,
    'Expected unit hotspot heading to reflect the requested top limit.');
  Assert.IsTrue(Pos('Top cycle edges (up to 1):', lOutputText) > 0,
    'Expected edge hotspot heading to reflect the requested top limit.');
  Assert.IsFalse(Pos('  2. ', lOutputText) > 0,
    'Expected both hotspot sections to truncate to one ranked entry when --top 1 is used.');
end;

procedure TDepsTests.DepsTextPrefersImplementationEdgesOnEqualRank;
var
  lArgs: string;
  lExitCode: Cardinal;
  lImplementationPos: Integer;
  lInterfacePos: Integer;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'deps-cycle-edge-order.log');
  lArgs := 'deps --project ' + QuoteArg(CycleProjectPath) + ' --format text';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for deps edge-order text test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected deps text run to succeed. See: ' + lLogPath);

  lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lImplementationPos := Pos('CycleB -> CycleA [implementation]', lOutputText);
  lInterfacePos := Pos('CycleA -> CycleB [interface]', lOutputText);
  Assert.IsTrue(lImplementationPos > 0, 'Expected implementation edge hotspot to rank first for the equal-score tie.');
  Assert.IsTrue(lInterfacePos > 0, 'Expected interface edge hotspot to follow the equal-score implementation edge.');
  Assert.IsTrue(lImplementationPos < lInterfacePos,
    'Expected implementation edge hotspot to appear before the equal-rank interface edge hotspot.');
end;

procedure TDepsTests.DepsJsonIncludesCycleComponentsAndHotspots;
var
  lCycleComponents: TJSONArray;
  lEdgeHotspots: TJSONArray;
  lJson: TJSONObject;
  lUnitHotspots: TJSONArray;
begin
  lJson := RunDepsJson(CycleProjectPath, 'deps-json-hotspots.log');
  try
    lCycleComponents := lJson.GetValue('cycleComponents') as TJSONArray;
    lUnitHotspots := lJson.GetValue('unitHotspots') as TJSONArray;
    lEdgeHotspots := lJson.GetValue('edgeHotspots') as TJSONArray;
    Assert.IsNotNull(lCycleComponents, 'Expected cycleComponents array.');
    Assert.IsTrue(lCycleComponents.Count >= 2, 'Expected at least two cycle components.');
    Assert.IsNotNull(lUnitHotspots, 'Expected unitHotspots array.');
    Assert.IsTrue(lUnitHotspots.Count >= 4, 'Expected hotspot entries for cycle units.');
    Assert.IsNotNull(lEdgeHotspots, 'Expected edgeHotspots array.');
    Assert.IsTrue(lEdgeHotspots.Count >= 4, 'Expected hotspot entries for cycle-bearing edges.');
  finally
    lJson.Free;
  end;
end;

procedure TDepsTests.DepsJsonKeepsCyclesCompatibilityArray;
var
  lCycles: TJSONArray;
  lJson: TJSONObject;
begin
  lJson := RunDepsJson(CycleProjectPath, 'deps-json-cycles-compat.log');
  try
    lCycles := lJson.GetValue('cycles') as TJSONArray;
    Assert.IsNotNull(lCycles, 'Expected compatibility cycles array.');
    Assert.IsTrue(Pos('PathCycleA -> PathCycleC -> PathCycleB -> PathCycleA', lCycles.ToJSON) > 0,
      'Expected cycles compatibility array to keep the real traversal path.');
  finally
    lJson.Free;
  end;
end;

procedure TDepsTests.DepsJsonMarksCycleNodesAndEdges;
var
  lEdge: TJSONObject;
  lEdges: TJSONArray;
  lJson: TJSONObject;
  lNode: TJSONObject;
  lNodes: TJSONArray;
begin
  lJson := RunDepsJson(CycleProjectPath, 'deps-json-node-edge-marks.log');
  try
    lNodes := lJson.GetValue('nodes') as TJSONArray;
    lEdges := lJson.GetValue('edges') as TJSONArray;
    Assert.IsNotNull(lNodes);
    Assert.IsNotNull(lEdges);

    lNode := FindNodeByName(lNodes, 'PathCycleA');
    Assert.IsNotNull(lNode, 'Expected PathCycleA node.');
    Assert.AreEqual('2', lNode.GetValue('unitCycleScore').Value,
      'Expected PathCycleA to report its internal SCC degree.');
    Assert.IsNotNull(lNode.GetValue('sccId'), 'Expected PathCycleA to report an SCC id.');

    lEdge := FindEdgeByNames(lEdges, 'PathCycleA', 'PathCycleC');
    Assert.IsNotNull(lEdge, 'Expected PathCycleA -> PathCycleC edge.');
    Assert.AreEqual('true', LowerCase(lEdge.GetValue('isCycleEdge').Value),
      'Expected PathCycleA -> PathCycleC to be marked as cycle-bearing.');

    lEdge := FindEdgeByNames(lEdges, 'CycleConsumer', 'CycleA');
    Assert.IsNotNull(lEdge, 'Expected CycleConsumer -> CycleA edge.');
    Assert.AreEqual('false', LowerCase(lEdge.GetValue('isCycleEdge').Value),
      'Expected CycleConsumer -> CycleA to remain outside cycle-bearing edges.');
  finally
    lJson.Free;
  end;
end;

procedure TDepsTests.DepsJsonPrefersImplementationEdgesOnEqualRank;
var
  lEdgeHotspots: TJSONArray;
  lFirstEdge: TJSONObject;
  lJson: TJSONObject;
  lSecondEdge: TJSONObject;
begin
  lJson := RunDepsJson(CycleProjectPath, 'deps-json-edge-order.log');
  try
    lEdgeHotspots := lJson.GetValue('edgeHotspots') as TJSONArray;
    Assert.IsNotNull(lEdgeHotspots, 'Expected edgeHotspots array.');
    Assert.IsTrue(lEdgeHotspots.Count >= 2, 'Expected at least two cycle edge hotspots.');

    lFirstEdge := lEdgeHotspots.Items[0] as TJSONObject;
    lSecondEdge := lEdgeHotspots.Items[1] as TJSONObject;
    Assert.IsNotNull(lFirstEdge, 'Expected first edge hotspot object.');
    Assert.IsNotNull(lSecondEdge, 'Expected second edge hotspot object.');

    Assert.AreEqual('CycleB', lFirstEdge.GetValue('from').Value,
      'Expected equal-rank implementation edge to sort ahead of interface edges.');
    Assert.AreEqual('CycleA', lFirstEdge.GetValue('to').Value,
      'Expected first hotspot to be CycleB -> CycleA.');
    Assert.AreEqual('implementation', lFirstEdge.GetValue('edgeKind').Value,
      'Expected equal-rank implementation edge to sort first.');
    Assert.AreEqual('CycleA', lSecondEdge.GetValue('from').Value,
      'Expected interface edge to follow the implementation tie-break winner.');
    Assert.AreEqual('CycleB', lSecondEdge.GetValue('to').Value,
      'Expected second hotspot to be CycleA -> CycleB.');
    Assert.AreEqual('interface', lSecondEdge.GetValue('edgeKind').Value,
      'Expected interface edge to sort after the equal-rank implementation edge.');
  finally
    lJson.Free;
  end;
end;

procedure TDepsTests.DepsJsonExcludesUnresolvedUnitsFromHotspots;
var
  lEdgeHotspots: TJSONArray;
  lJson: TJSONObject;
  lUnitHotspots: TJSONArray;
begin
  lJson := RunDepsJson(CycleProjectPath, 'deps-json-hotspot-filter.log');
  try
    lUnitHotspots := lJson.GetValue('unitHotspots') as TJSONArray;
    lEdgeHotspots := lJson.GetValue('edgeHotspots') as TJSONArray;
    Assert.IsNotNull(lUnitHotspots);
    Assert.IsNotNull(lEdgeHotspots);
    Assert.IsFalse(Pos('MissingCycle.Dependency', lUnitHotspots.ToJSON) > 0,
      'Expected unresolved units to stay out of unitHotspots.');
    Assert.IsFalse(Pos('MissingCycle.Dependency', lEdgeHotspots.ToJSON) > 0,
      'Expected unresolved units to stay out of edgeHotspots.');
    Assert.IsFalse(Pos('System.SysUtils', lUnitHotspots.ToJSON) > 0,
      'Expected unresolved framework units to stay out of unitHotspots.');
  finally
    lJson.Free;
  end;
end;

procedure TDepsTests.DepsRunnerUsesSharedTypedSccAnalyzer;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.deps.runner.pas'),
    TEncoding.UTF8);

  Assert.IsTrue(Pos('TDelphiSemanticTypedSccAnalyzer', lSource) > 0,
    'deps runner should use the shared DelphiSemantics typed SCC analyzer.');
  Assert.IsFalse(Pos('AddReachableNodes', lSource) > 0,
    'deps runner should not own reachability-based SCC sweeps.');
  Assert.IsFalse(Pos('BuildRepresentativeCycle', lSource) > 0,
    'deps runner should not own representative cycle path assembly.');
end;

procedure TDepsTests.DepsRunnerDelegatesGraphConstructionToProjectSession;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.deps.runner.pas'),
    TEncoding.UTF8);

  Assert.IsTrue(Pos('OpenSemanticProjectSession', lSource) > 0,
    'deps runner should open DelphiSemantics project sessions through the shared adapter.');
  Assert.IsTrue(Pos('BuildDependencyGraph', lSource) > 0,
    'deps runner should request dependency graph facts from the project session.');
  Assert.IsFalse(Pos('CreateProjectAnalysisIndexer', lSource) > 0,
    'deps runner should not own project indexer construction.');
  Assert.IsFalse(Pos('TProjectIndexer', lSource) > 0,
    'deps runner should not own a parallel project indexer loop.');
  Assert.IsFalse(Pos('TDelphiSemanticUnitModelExtractor.ExtractFromFile', lSource) > 0,
    'deps runner should not extract semantic unit models file-by-file.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDepsTests);

end.
