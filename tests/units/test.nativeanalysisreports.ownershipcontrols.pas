unit Test.NativeAnalysisReports.OwnershipControls;

interface

uses
  DUnitX.TestFramework;

type
  // test_ownership_reporting.py cases the ownership fixture did not already assert: reprocessing
  // stability, VCS-neutral path ownership and one mixed-ownership output checked across every
  // published artifact, its verification and the command line.
  [TestFixture]
  TNativeAnalysisOwnershipControlTests = class
  private
    fRoot: string;
    fEnvironment: IInterface;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReprocessingPreservesSourceIdentityWithDuplicateBasenames;
    [Test]
    procedure ReprocessingKeepsWorkspaceRelativePathsOutOfProjectSubfolders;
    [TestCase('svn', 'svn')]
    [TestCase('none', 'none')]
    procedure SvnAndUnmanagedWorkspaceOwnershipIsPathBased(const aVcs: string);
    [Test]
    procedure UnmanagedWorkspaceDoesNotAttachOuterGitHistory;
    [Test]
    procedure PathSafeOwnershipIsConsistentAcrossAiArtifacts;
  end;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows,
  AutoFree,
  Dak.Analysis.JsonText, Dak.Analysis.Ownership, Dak.Analysis.OwnershipContext, Dak.Analysis.ReportBundle,
  Dak.Analysis.ReportReplay, Dak.Analysis.ReportVerify, Dak.Analysis.SourceResolution,
  Test.Support;

procedure WriteUtf8(const aPath, aText: string);
begin
  TDirectory.CreateDirectory(TPath.GetDirectoryName(aPath));
  TFile.WriteAllBytes(aPath, TEncoding.UTF8.GetBytes(aText));
end;

function ReadUtf8(const aPath: string): string;
begin
  Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(aPath));
end;

function Posix(const aPath: string): string;
begin
  Result := aPath.Replace('\', '/');
end;

procedure WriteRows(const aPath: string; aRows: TJSONArray);
var
  lItem: TJSONValue;
  lText: TStringBuilder;
begin
  lText := TStringBuilder.Create;
  try
    for lItem in aRows do
      lText.Append(lItem.ToJSON).Append(#10);
    WriteUtf8(aPath, lText.ToString);
  finally
    lText.Free;
  end;
end;

function LoadRows(const aPath: string): TJSONArray;
var
  lLine: string;
begin
  Result := TJSONArray.Create;
  for lLine in ReadUtf8(aPath).Split([#10]) do
    if Trim(lLine) <> '' then
      Result.AddElement(ParseJsonObject(lLine, aPath));
end;

function Row(aRows: TJSONArray; aIndex: Integer): TJSONObject;
begin
  Result := TJSONObject(aRows.Items[aIndex]);
end;

// ownership_counts over one or two row sets, as "project=N, repository=N, third_party=N, unknown=N".
function OwnershipText(const aRowSets: array of TJSONArray): string;
var
  g: TGarbos;
  lCounts: TJSONObject;
begin
  GC(lCounts, AnalysisOwnershipCounts(aRowSets), g);
  Result := AnalysisOwnershipText(lCounts);
end;

function Member(aObject: TJSONObject; const aPath: array of string): TJSONValue;
var
  lName: string;
begin
  Result := aObject;
  for lName in aPath do
  begin
    Assert.IsTrue(Result is TJSONObject, 'expected an object before ' + lName);
    Result := TJSONObject(Result).GetValue(lName);
    Assert.IsNotNull(Result, 'missing member ' + lName);
  end;
end;

function MemberText(aObject: TJSONObject; const aPath: array of string): string;
begin
  Result := Member(aObject, aPath).Value;
end;

procedure AssertJsonEquals(const aExpected: string; aActual: TJSONValue; const aMessage: string);
var
  g: TGarbos;
  lExpected: TJSONValue;
begin
  GC(lExpected, ParseJsonValue(aExpected), g);
  Assert.IsTrue(AnalysisJsonEquivalent(lExpected, aActual), aMessage + ': ' + TPythonJson.Compact(aActual));
end;

procedure AssertVerifyFails(const aOutRoot, aFragment: string);
begin
  try
    VerifyAnalysisReport(aOutRoot).Free;
    Assert.Fail('verification must fail with "' + aFragment + '"');
  except
    on e: EConvertError do
      Assert.IsTrue(e.Message.Contains(aFragment), 'expected "' + aFragment + '" in: ' + e.Message);
  end;
end;

function RunGit(const aRepo, aArguments: string): string;
var
  lExitCode: Cardinal;
  lGit, lLog: string;
begin
  lGit := FileSearch('git.exe', GetEnvironmentVariable('PATH'));
  Assert.IsTrue(lGit <> '', 'git.exe must be on PATH for this fixture');
  lLog := TPath.Combine(TPath.GetTempPath, 'dak-ownership-git-' + TGUID.NewGuid.ToString + '.log');
  try
    Assert.IsTrue(RunCommandProcess(lGit, aArguments, aRepo, lLog, lExitCode), 'git must run: ' + aArguments);
    Result := ReadUtf8(lLog);
    Assert.AreEqual<Cardinal>(0, lExitCode, 'git ' + aArguments + ': ' + Result);
  finally
    if TFile.Exists(lLog) then
      TFile.Delete(lLog);
  end;
end;

procedure CommitAll(const aRepo, aMessage: string);
begin
  RunGit(aRepo, 'add .');
  RunGit(aRepo, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm "' + aMessage + '"');
end;

function RunVerifyCommand(const aOutRoot: string; out aOutput: string): Cardinal;
var
  lLog: string;
begin
  lLog := TPath.Combine(TPath.GetTempPath, 'dak-ownership-verify-' + TGUID.NewGuid.ToString + '.log');
  try
    Assert.IsTrue(RunCommandProcess(ResolverExePath, 'analyze-report --out ' + QuoteArg(aOutRoot) + ' --verify',
      aOutRoot, lLog, Result), 'analyze-report must start');
    aOutput := ReadUtf8TextFile(lLog);
  finally
    if TFile.Exists(lLog) then
      TFile.Delete(lLog);
  end;
end;

{ TNativeAnalysisOwnershipControlTests }

procedure TNativeAnalysisOwnershipControlTests.Setup;
begin
  EnsureResolverBuilt;
  fRoot := UniqueNoRepoTempPath('native-ownership-controls');
  TDirectory.CreateDirectory(fRoot);
  fEnvironment := SetScopedEnvironmentVariables(['DAK_BASELINE', '', 'DAK_GATE', '0', 'DAK_CI', '0',
    'DAK_UPDATE_BASELINE', '0', 'DAK_GATE_REQUIRE_CONTEXT_MATCH', '0', 'DAK_GATE_INCLUDE_PATHS', '',
    'DAK_GATE_EXCLUDE_PATHS', '', 'DAK_SCOPE', '', 'DAK_TRIAGE_SNIPPETS', '', 'DAK_TRIAGE_TOP', '',
    'DAK_TREND_N', '']);
end;

procedure TNativeAnalysisOwnershipControlTests.TearDown;
begin
  fEnvironment := nil;
  if TDirectory.Exists(fRoot) then
    DeleteTempPath(fRoot);
end;

// A local and an external unit share a basename that differs only in case; three passes keep each
// row's own source identity.
procedure TNativeAnalysisOwnershipControlTests.ReprocessingPreservesSourceIdentityWithDuplicateBasenames;
var
  g: TGarbos;
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lExternal, lFirst, lLocal, lProject, lWorkspace: string;
  lPass: Integer;
  lResolver: TAnalysisSourceResolver;
  lRows: TJSONArray;
  lSeed: TJSONObject;
begin
  lWorkspace := TPath.Combine(fRoot, 'repo');
  lLocal := TPath.Combine(lWorkspace, 'tools\inject\autoFree.pas');
  lExternal := TPath.Combine(fRoot, 'MaxLogicFoundation\AutoFree.pas');
  WriteUtf8(lLocal, 'unit AutoFree;'#10);
  WriteUtf8(lExternal, 'unit AutoFree;'#10);
  lProject := TPath.Combine(lWorkspace, 'Sample.dproj');
  WriteUtf8(lProject, '<Project/>');
  GC(lSeed, TJSONObject.Create, g);
  lSeed.AddPair('workspace', TJSONObject.Create.AddPair('root', lWorkspace).AddPair('vcs', 'none'));
  lSeed.AddPair('subject', TJSONObject.Create.AddPair('project_file', lProject));
  lSeed.AddPair('policy', TJSONObject.Create.AddPair('values', TJSONObject.Create));
  GC(lRows, TJSONArray.Create, g);
  lRows.AddElement(TJSONObject.Create.AddPair('path', lExternal).AddPair('module', 'AutoFree')
    .AddPair('line', TJSONNumber.Create(7)).AddPair('id', 'External'));
  lRows.AddElement(TJSONObject.Create.AddPair('path', lLocal).AddPair('module', 'AutoFree')
    .AddPair('line', TJSONNumber.Create(9)).AddPair('id', 'Owned'));

  lContext := BuildAnalysisOwnershipContext(lSeed, TPath.Combine(lWorkspace, '.dak\Sample'), lWorkspace, lDiagnostics);
  lFirst := '';
  for lPass := 1 to 3 do
  begin
    // Each pass is a fresh postprocessor run over the rows the previous run wrote.
    GC(lResolver, TAnalysisSourceResolver.Create(lContext), g);
    lResolver.AnnotatePal(lRows);
    Assert.AreEqual(2, lRows.Count);
    Assert.AreEqual(Posix(lExternal), JsonText(Row(lRows, 0), 'path'), 'pass ' + lPass.ToString);
    Assert.AreEqual('third_party', JsonText(Row(lRows, 0), 'ownership'), 'pass ' + lPass.ToString);
    Assert.AreEqual('tools/inject/autoFree.pas', JsonText(Row(lRows, 1), 'path'), 'pass ' + lPass.ToString);
    Assert.AreEqual('repository', JsonText(Row(lRows, 1), 'ownership'), 'pass ' + lPass.ToString);
    Assert.AreEqual('project=0, repository=1, third_party=1, unknown=0', OwnershipText([lRows]));
    if lFirst = '' then
      lFirst := lRows.ToJSON
    else
      Assert.AreEqual(lFirst, lRows.ToJSON, 'pass ' + lPass.ToString);
  end;
end;

// A project in src/ must not turn the workspace-relative "src/Owned.pas" into src/src/Owned.pas when
// the rows are processed again.
procedure TNativeAnalysisOwnershipControlTests.ReprocessingKeepsWorkspaceRelativePathsOutOfProjectSubfolders;
var
  g: TGarbos;
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lFirst, lProject, lSource: string;
  lResolver: TAnalysisSourceResolver;
  lRows: TJSONArray;
  lSeed: TJSONObject;
begin
  lSource := TPath.Combine(fRoot, 'src\Owned.pas');
  WriteUtf8(lSource, 'unit Owned;'#10);
  WriteUtf8(TPath.Combine(fRoot, 'src\src\Owned.pas'), 'unit Owned;'#10);
  lProject := TPath.Combine(fRoot, 'src\Sample.dproj');
  WriteUtf8(lProject, '<Project><ItemGroup><DCCReference Include="Owned.pas"/></ItemGroup></Project>');
  GC(lSeed, TJSONObject.Create, g);
  lSeed.AddPair('workspace', TJSONObject.Create.AddPair('root', fRoot).AddPair('vcs', 'none'));
  lSeed.AddPair('subject', TJSONObject.Create.AddPair('project_file', lProject));
  lSeed.AddPair('policy', TJSONObject.Create.AddPair('values', TJSONObject.Create));
  GC(lRows, TJSONArray.Create, g);
  lRows.AddElement(TJSONObject.Create.AddPair('path', lSource).AddPair('module', 'Owned')
    .AddPair('line', TJSONNumber.Create(1)));
  lContext := BuildAnalysisOwnershipContext(lSeed, TPath.Combine(fRoot, '.dak\Sample'), fRoot, lDiagnostics);

  GC(lResolver, TAnalysisSourceResolver.Create(lContext), g);
  lResolver.AnnotatePal(lRows);
  Assert.AreEqual('src/Owned.pas', JsonText(Row(lRows, 0), 'path'));
  Assert.AreEqual('project', JsonText(Row(lRows, 0), 'ownership'));
  lFirst := lRows.ToJSON;
  GC(lResolver, TAnalysisSourceResolver.Create(lContext), g);
  lResolver.AnnotatePal(lRows);
  Assert.AreEqual(lFirst, lRows.ToJSON, 'the second pass changes nothing');
end;

// Without Git, ownership follows the workspace boundary, project membership, registered externals
// and the inventory; an outer .git directory is not the workspace.
procedure TNativeAnalysisOwnershipControlTests.SvnAndUnmanagedWorkspaceOwnershipIsPathBased(const aVcs: string);
const
  cCases: array[0..8, 0..1] of string = (
    ('Owned.pas', 'project'),
    ('extras/RepoOnly.pas', 'repository'),
    ('RepoOnly.pas', 'repository'),
    ('notes/Owned.dfm', 'repository'),
    ('vendor/external/External.pas', 'third_party'),
    ('<outside>', 'third_party'),
    ('Dupe.pas', 'unknown'),
    ('missing/RepoOnly.pas', 'unknown'),
    ('Missing.pas', 'unknown'));
var
  g: TGarbos;
  i: Integer;
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lExternalRoot, lOutside, lProject, lProjectSource, lRaw, lResolved, lWorkspace: string;
  lOwnership: TAnalysisSourceOwnership;
  lResolver: TAnalysisSourceResolver;
  lSeed, lTarget: TJSONObject;
begin
  lWorkspace := TPath.Combine(fRoot, 'workspace');
  lExternalRoot := TPath.Combine(lWorkspace, 'vendor\external');
  lOutside := TPath.Combine(fRoot, 'outside\Outside.pas');
  TDirectory.CreateDirectory(TPath.Combine(fRoot, '.git'));
  TDirectory.CreateDirectory(lExternalRoot);
  if aVcs = 'svn' then
    TDirectory.CreateDirectory(TPath.Combine(lWorkspace, '.svn'));
  lProjectSource := TPath.Combine(lWorkspace, 'src\Owned.pas');
  WriteUtf8(lProjectSource, 'unit Owned;'#10);
  lProject := TPath.Combine(lWorkspace, 'src\Sample.dproj');
  WriteUtf8(lProject, '<Project><ItemGroup><DCCReference Include="Owned.pas"/></ItemGroup></Project>');
  WriteUtf8(TPath.Combine(lWorkspace, 'extras\RepoOnly.pas'), 'unit RepoOnly;'#10);
  WriteUtf8(TPath.Combine(lWorkspace, '.dak\ignored\RepoOnly.pas'), 'unit RepoOnly;'#10);
  WriteUtf8(TPath.Combine(lWorkspace, 'notes\Owned.dfm'), 'object Owned: TOwned'#10'end'#10);
  WriteUtf8(TPath.Combine(lWorkspace, 'a\Dupe.pas'), 'unit Dupe;'#10);
  WriteUtf8(TPath.Combine(lWorkspace, 'b\Dupe.pas'), 'unit Dupe;'#10);
  WriteUtf8(TPath.Combine(lExternalRoot, 'External.pas'), 'unit External;'#10);
  WriteUtf8(lOutside, 'unit Outside;'#10);

  GC(lSeed, TJSONObject.Create, g);
  lSeed.AddPair('workspace', TJSONObject.Create.AddPair('root', lWorkspace).AddPair('vcs', aVcs)
    .AddPair('selector', aVcs).AddPair('source', 'command_line'));
  lSeed.AddPair('subject', TJSONObject.Create.AddPair('kind', 'project').AddPair('path', lProjectSource)
    .AddPair('project_file', lProject));
  lSeed.AddPair('policy', TJSONObject.Create.AddPair('values', TJSONObject.Create));
  lTarget := TJSONObject.Create.AddPair('vcs', aVcs).AddPair('root', lWorkspace)
    .AddPair('externals', TJSONArray.Create.Add(TJSONObject.Create.AddPair('path', 'vendor/external')));
  lSeed.AddPair('provenance', TJSONObject.Create.AddPair('target', lTarget));

  lContext := BuildAnalysisOwnershipContext(lSeed, TPath.Combine(lWorkspace, '.dak\Sample\ownership'), '', lDiagnostics);
  GC(lResolver, TAnalysisSourceResolver.Create(lContext), g);
  for i := Low(cCases) to High(cCases) do
  begin
    lRaw := cCases[i, 0];
    if lRaw = '<outside>' then
      lRaw := lOutside;
    lResolved := lResolver.Resolve(lRaw);
    lOwnership := ClassifyAnalysisSource(lResolved, lContext);
    Assert.AreEqual(cCases[i, 1], lOwnership.fOwnership, aVcs + ': ' + lRaw);
    if cCases[i, 0] = 'vendor/external/External.pas' then
      Assert.IsTrue(SameText(ExcludeTrailingPathDelimiter(lExternalRoot),
        ExcludeTrailingPathDelimiter(lOwnership.fRoot.Replace('/', '\'))), 'external root: ' + lOwnership.fRoot);
  end;
end;

// An unmanaged workspace inside someone else's Git checkout publishes no Git history facts.
procedure TNativeAnalysisOwnershipControlTests.UnmanagedWorkspaceDoesNotAttachOuterGitHistory;
var
  g: TGarbos;
  lCounts, lProvenance, lResult: TJSONObject;
  lHistory, lRows: TJSONArray;
  lOut, lProject, lSource, lWorkspace: string;
begin
  RunGit(fRoot, 'init -q');
  lWorkspace := TPath.Combine(fRoot, 'workspace');
  lProject := TPath.Combine(lWorkspace, 'src\Sample.dproj');
  lSource := TPath.Combine(lWorkspace, 'src\Sample.dpr');
  WriteUtf8(lProject, '<Project />');
  WriteUtf8(lSource, 'program Sample; begin end.'#10);
  WriteUtf8(TPath.Combine(lWorkspace, 'extras\RepoOnly.pas'), 'unit RepoOnly;'#10);
  lOut := TPath.Combine(lWorkspace, '.dak\Sample\ownership');
  WriteUtf8(TPath.Combine(lOut, 'summary.md'),
    '# Static analysis'#10#10'- Timestamp: 2026-08-08T10:00:00Z'#10'- Project: `' + lSource + '`'#10#10 +
    '## FixInsight'#10#10'- Findings (by code): 1'#10'  - W101: 1'#10#10'## Pascal Analyzer'#10#10 +
    '- Version: disabled'#10'- Compiler target: Delphi 12 (Win64)'#10 +
    '- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0'#10);
  WriteUtf8(TPath.Combine(lOut, 'fixinsight\fi-findings.jsonl'),
    '{"tool": "FixInsight", "code": "W101", "kind": "W", "file": "extras/RepoOnly.pas", ' +
    '"path": "extras/RepoOnly.pas", "line": 1, "col": 1, "message": "fixture warning"}'#10);
  WriteUtf8(TPath.Combine(lOut, 'pascal-analyzer\pal-findings.jsonl'), '');
  WriteUtf8(TPath.Combine(lOut, 'summary.json'),
    '{"schema_version": 2, "status": {"infrastructure": "complete", "policy": "not_evaluated"}, ' +
    '"workspace": {"root": "' + lWorkspace.Replace('\', '\\') + '", "vcs": "none", "selector": "project", ' +
    '"source": "command_line"}, "subject": {"kind": "project", "path": "' + lSource.Replace('\', '\\') +
    '", "project_file": "' + lProject.Replace('\', '\\') + '"}, ' +
    '"compiler": {"delphi": "23.0", "platform": "Win64", "config": "Debug", "search_path_sha256": "' +
    StringOfChar('1', 64) + '"}, ' +
    '"analyzers": {"fixinsight": {"requested": true, "status": "complete", "version": "fixture", ' +
    '"options": {"sha256": "' + StringOfChar('2', 64) + '"}, "count_quality": "complete"}, ' +
    '"pascal_analyzer": {"requested": false, "status": "not_requested", "options": {"sha256": "' +
    StringOfChar('3', 64) + '"}, "count_quality": "complete"}}, ' +
    '"inputs": {"project_sha256": "' + StringOfChar('4', 64) + '"}, ' +
    '"policy": {"values": {"gate_ownership": ["project", "repository"], "project_roots": [], ' +
    '"third_party_roots": [], "exclude_path_masks": []}, "sha256": "' + StringOfChar('5', 64) +
    '", "reporting_sha256": "' + StringOfChar('6', 64) + '"}, ' +
    '"errors": [], "artifacts": {"summary_markdown": "summary.md"}}');
  SetEnvironmentVariable('DAK_BASELINE', PChar(TPath.Combine(lOut, 'baseline.json')));
  GC(lProvenance, ParseJsonObject('{"target": {"vcs": "none", "root": "' + lWorkspace.Replace('\', '\\') + '"}, ' +
    '"dak": {"head": "fixture", "executable_sha256": "' + StringOfChar('7', 64) + '"}}', 'provenance'), g);

  GC(lResult, FinalizeAnalysisReport(lOut, 'Sample', lProvenance, -1), g);
  Assert.IsTrue(TJSONBool(lResult.GetValue('gate_pass')).AsBoolean, 'gate_pass');
  GC(lRows, LoadRows(TPath.Combine(lOut, 'fixinsight\fi-findings.jsonl')), g);
  Assert.AreEqual('repository', JsonText(Row(lRows, 0), 'ownership'));
  GC(lHistory, LoadRows(TPath.Combine(lOut, 'history.jsonl')), g);
  Assert.IsNull(Row(lHistory, lHistory.Count - 1).GetValue('git'), 'no outer Git history is attached');
  GC(lCounts, VerifyAnalysisReport(lOut), g);
end;

procedure TNativeAnalysisOwnershipControlTests.PathSafeOwnershipIsConsistentAcrossAiArtifacts;
const
  cExpected = 'project=4, repository=3, third_party=0, unknown=0';
  cRawExpected = 'project=4, repository=3, third_party=6, unknown=4';
  cSources: array[0..7] of string = ('src\Main.pas', 'src\Main.inc', 'src\Dupe.pas', 'extras\RepoOnly.pas',
    'extras\Dupe.pas', 'search-a\DuplicateUnit.pas', 'search-a\GuessOnly.pas', 'search-b\DuplicateUnit.pas');
  cPalExpected: array[0..9] of string = ('project', 'project', 'repository', 'third_party', 'third_party',
    'unknown', 'unknown', 'project', 'repository', 'unknown');
var
  g: TGarbos;
  i: Integer;
  lCounts, lDelta, lFullSarif, lOwnership, lResult, lResultRow, lSarif, lSummary, lSummaryCopy: TJSONObject;
  lExternal, lFiPath, lLibrary, lMainSource, lName, lOut, lOutput, lProject, lRepo, lShadow, lStale,
    lText, lTriage, lValidDelta, lValidFi, lValidFullSarif, lValidSarif: string;
  lFi, lFiRows, lHistory, lPal, lPalRows: TJSONArray;
  lFiPaths, lFiExpected, lLines: TStringList;
  lFound: Boolean;
  lItem: TJSONValue;
  lSarifRows: TJSONArray;
  lSearch: TArray<string>;
  lTop: IInterface;

  function SarifOwnership(aDocument: TJSONObject; aRequireRoot: Boolean): TJSONArray;
  var
    lDocumentRun, lDocumentResult: TJSONValue;
    lProperties: TJSONObject;
  begin
    Result := TJSONArray.Create;
    for lDocumentRun in Member(aDocument, ['runs']) as TJSONArray do
      for lDocumentResult in TJSONObject(lDocumentRun).GetValue('results') as TJSONArray do
      begin
        lProperties := Member(TJSONObject(lDocumentResult), ['properties']) as TJSONObject;
        if aRequireRoot then
          Assert.IsNotNull(lProperties.GetValue('ownership_root'), 'actionable SARIF carries ownership_root');
        Result.AddElement(TJSONObject.Create.AddPair('ownership', JsonText(lProperties, 'ownership')));
      end;
  end;

begin
  lLibrary := TPath.Combine(fRoot, 'library');
  lRepo := TPath.Combine(fRoot, 'repo');
  lExternal := TPath.Combine(fRoot, 'external');
  lShadow := TPath.Combine(fRoot, 'shadow');
  lStale := TPath.Combine(fRoot, 'stale');

  WriteUtf8(TPath.Combine(lLibrary, 'nested\NestedUnit.pas'), 'unit NestedUnit;'#10);
  RunGit(lLibrary, 'init -q');
  CommitAll(lLibrary, 'library');

  for lName in cSources do
    WriteUtf8(TPath.Combine(lRepo, lName), 'unit ' + TPath.GetFileNameWithoutExtension(lName) + ';'#10'interface'#10 +
      'implementation'#10'end.'#10);
  lProject := TPath.Combine(lRepo, 'Sample.dproj');
  WriteUtf8(lProject, '<Project><ItemGroup><DCCReference Include="src\Main.pas"/><DCCReference Include="' +
    TPath.Combine(lExternal, 'ExternalUnit.pas') + '"/></ItemGroup></Project>');
  lMainSource := TPath.Combine(lRepo, 'Sample.dpr');
  WriteUtf8(lMainSource, 'program Sample;'#10'uses Main in ''src\Main.pas'';'#10'begin'#10'end.'#10);
  WriteUtf8(TPath.Combine(lRepo, '.gitignore'), '.dak/'#10);
  RunGit(lRepo, 'init -q');
  CommitAll(lRepo, 'project');
  RunGit(lRepo, '-c protocol.file.allow=always submodule add -q "' + lLibrary + '" vendor/library');
  CommitAll(lRepo, 'submodule');

  WriteUtf8(TPath.Combine(lExternal, 'ExternalUnit.pas'), 'unit ExternalUnit;'#10);
  WriteUtf8(TPath.Combine(lShadow, 'Main.pas'), 'unit Main;'#10);
  WriteUtf8(TPath.Combine(lShadow, 'Dupe.pas'), 'unit Dupe;'#10);
  WriteUtf8(TPath.Combine(lStale, 'Main.pas'), 'unit Main;'#10);

  lOut := TPath.Combine(lRepo, '.dak\Sample\ownership-fixture');
  WriteUtf8(TPath.Combine(lOut, 'summary.md'),
    '# Static analysis'#10#10'- Timestamp: 2026-07-17T10:00:00Z'#10'- Project: `' + lMainSource + '`'#10#10 +
    '## FixInsight'#10#10'- Findings (by code): 7'#10'  - W101: 7'#10#10'## Pascal Analyzer'#10#10 +
    '- Version: 9.21.3'#10'- Compiler target: Delphi 13 (Win64)'#10 +
    '- Totals: warnings=9, strong_warnings=1, optimizations=0, total=10'#10);
  lSearch := [TPath.Combine(lRepo, 'src'), TPath.Combine(lRepo, 'extras'), TPath.Combine(lRepo, 'vendor\library\nested'),
    lExternal, TPath.Combine(lRepo, 'search-a'), TPath.Combine(lRepo, 'search-b')];
  WriteUtf8(TPath.Combine(lOut, 'run.log'),
    'CMD: palcmd.exe "' + lMainSource + '" /S="' + lStale + '" /CD13W64'#10 +
    'CMD: palcmd.exe "' + lMainSource + '" /S="' + String.Join(';', lSearch) + '" /CD13W64'#10);
  WriteUtf8(TPath.Combine(lOut, 'summary.json'),
    '{"schema_version": 2, "status": {"infrastructure": "complete", "policy": "not_evaluated"}, ' +
    '"subject": {"kind": "project", "path": "' + lMainSource.Replace('\', '\\') + '", "project_file": "' +
    lProject.Replace('\', '\\') + '"}, ' +
    '"compiler": {"delphi": "23.0", "platform": "Win64", "config": "Debug", "search_path_sha256": "fixture"}, ' +
    '"analyzers": {"fixinsight": {"requested": true, "status": "complete", "count_quality": "complete", ' +
    '"options": {"sha256": "' + StringOfChar('1', 64) + '"}}, "pascal_analyzer": {"requested": true, ' +
    '"status": "complete", "version": "9.21.3", "count_quality": "complete", "options": {"sha256": "' +
    StringOfChar('2', 64) + '"}}}, "counts": {}, "inputs": {}, ' +
    '"policy": {"resolver": "Dak.Settings", "values": {"gate_ownership": ["project", "repository"], ' +
    '"project_roots": [], "third_party_roots": [], "exclude_path_masks": ["*ExternalUnit.pas"]}, ' +
    '"sha256": "' + StringOfChar('3', 64) + '", "reporting_sha256": "' + StringOfChar('4', 64) + '"}, ' +
    '"errors": [], "artifacts": {"summary_markdown": "summary.md"}}');

  GC(lFiPaths, TStringList.Create, g);
  GC(lFiExpected, TStringList.Create, g);
  lFiPaths.AddStrings(['src/Main.pas', 'extras/RepoOnly.pas', 'vendor/library/nested/NestedUnit.pas',
    TPath.Combine(lExternal, 'ExternalUnit.pas'), 'MissingUnit.pas', TPath.Combine(lShadow, 'Main.pas'),
    TPath.Combine(lShadow, 'Dupe.pas')]);
  lFiExpected.AddStrings(['project', 'repository', 'third_party', 'third_party', 'unknown', 'third_party',
    'third_party']);
  GC(lFiRows, TJSONArray.Create, g);
  for i := 0 to lFiPaths.Count - 1 do
    lFiRows.AddElement(TJSONObject.Create.AddPair('tool', 'FixInsight').AddPair('code', 'W101').AddPair('kind', 'W')
      .AddPair('file', lFiPaths[i]).AddPair('path', lFiPaths[i]).AddPair('line', TJSONNumber.Create(i + 1))
      .AddPair('col', TJSONNumber.Create(1)).AddPair('message', lFiExpected[i]));
  lFiPath := TPath.Combine(lOut, 'fixinsight\fi-findings.jsonl');
  WriteRows(lFiPath, lFiRows);
  GC(lPalRows, TJSONArray.Create, g);
  for i := 0 to 9 do
  begin
    lItem := TJSONObject.Create;
    lPalRows.AddElement(lItem);
    case i of
      0: TJSONObject(lItem).AddPair('module', 'Main').AddPair('path', 'src/Main.pas');
      1: TJSONObject(lItem).AddPair('module', 'Sample').AddPair('path', 'Sample.dpr');
      2: TJSONObject(lItem).AddPair('module', 'RepoOnly').AddPair('path', 'extras/RepoOnly.pas');
      3: TJSONObject(lItem).AddPair('module', 'NestedUnit').AddPair('path', 'vendor/library/nested/NestedUnit.pas');
      4: TJSONObject(lItem).AddPair('module', 'ExternalUnit').AddPair('path', TPath.Combine(lExternal, 'ExternalUnit.pas'));
      5: TJSONObject(lItem).AddPair('module', 'DuplicateUnit').AddPair('path', TJSONNull.Create);
      6: TJSONObject(lItem).AddPair('module', 'MissingModule').AddPair('path', TJSONNull.Create);
      7: TJSONObject(lItem).AddPair('module', 'Main').AddPair('path', 'SRC/main.PAS');
      8: TJSONObject(lItem).AddPair('module', 'DuplicateUnit').AddPair('path', 'search-a/DuplicateUnit.pas');
      9: TJSONObject(lItem).AddPair('module', 'GuessOnly').AddPair('path', TJSONNull.Create);
    end;
  end;
  for i := 0 to 9 do
  begin
    lText := JsonText(Row(lPalRows, i), 'module');
    // Rebuild each row in the reference member order: severity, report, section, module, path, line, message.
    lItem := TJSONObject.Create;
    if lText = 'NestedUnit' then
      TJSONObject(lItem).AddPair('severity', 'strong-warning')
    else
      TJSONObject(lItem).AddPair('severity', 'warning');
    TJSONObject(lItem).AddPair('report', 'Warnings.xml').AddPair('section', 'Warnings').AddPair('module', lText)
      .AddPair('path', Row(lPalRows, i).GetValue('path').Clone as TJSONValue)
      .AddPair('line', TJSONNumber.Create(i + 1)).AddPair('message', lText);
    lPalRows.AddElement(lItem);
  end;
  for i := 0 to 9 do
    lPalRows.Remove(0).Free;
  WriteRows(TPath.Combine(lOut, 'pascal-analyzer\pal-findings.jsonl'), lPalRows);

  lTop := SetScopedEnvironmentVariable('DAK_TRIAGE_TOP', '1');
  FinalizeAnalysisReport(lOut, 'Sample', nil, -1).Free;
  GC(lResult, FinalizeAnalysisReport(lOut, 'Sample', nil, -1), g);
  lTop := nil;
  Assert.IsTrue(TJSONBool(lResult.GetValue('gate_pass')).AsBoolean, 'gate_pass');
  lText := ReadUtf8(TPath.Combine(lOut, 'summary.md'));
  Assert.AreEqual(1, (Length(lText) - Length(lText.Replace('<!-- DAK ownership -->', ''))) div
    Length('<!-- DAK ownership -->'), 'one ownership block after two runs');

  GC(lFi, LoadRows(lFiPath), g);
  GC(lPal, LoadRows(TPath.Combine(lOut, 'pascal-analyzer\pal-findings.jsonl')), g);
  for i := 0 to lFiExpected.Count - 1 do
    Assert.AreEqual(lFiExpected[i], JsonText(Row(lFi, i), 'ownership'), 'FixInsight row ' + i.ToString);
  for i := 0 to High(cPalExpected) do
    Assert.AreEqual(cPalExpected[i], JsonText(Row(lPal, i), 'ownership'), 'PAL row ' + i.ToString);
  Assert.AreEqual('src/Main.pas', JsonText(Row(lFi, 5), 'path'));
  Assert.AreEqual(Posix(TPath.Combine(lShadow, 'Dupe.pas')), JsonText(Row(lFi, 6), 'path'));
  Assert.AreEqual('src/Main.pas', JsonText(Row(lPal, 0), 'path'));
  Assert.AreEqual('Sample.dpr', JsonText(Row(lPal, 1), 'path'));
  for i in [5, 6, 9] do
    Assert.IsTrue(Row(lPal, i).GetValue('path') is TJSONNull, 'module-only PAL row ' + i.ToString + ' keeps a null path');
  Assert.AreEqual(Posix(lRepo), JsonText(Row(lFi, 0), 'ownership_root'));
  Assert.AreEqual(Posix(lRepo), JsonText(Row(lFi, 1), 'ownership_root'));
  Assert.AreEqual(Posix(TPath.Combine(lRepo, 'vendor\library')), JsonText(Row(lFi, 2), 'ownership_root'));
  Assert.AreEqual(Posix(lExternal), JsonText(Row(lFi, 3), 'ownership_root'));
  Assert.IsTrue(Row(lFi, 4).GetValue('ownership_root') is TJSONNull, 'an unknown row has no ownership root');
  Assert.AreEqual(cRawExpected, OwnershipText([lFi, lPal]));

  GC(lSummary, ParseJsonObject(ReadUtf8(TPath.Combine(lOut, 'summary.json')), 'summary.json'), g);
  Assert.AreEqual('3', MemberText(lSummary, ['schema_version']));
  Assert.AreEqual('17', MemberText(lSummary, ['counts', 'raw', 'total']));
  AssertJsonEquals('{"fixinsight": 7, "pascal_analyzer": 10}', Member(lSummary, ['counts', 'raw', 'by_analyzer']),
    'by_analyzer');
  AssertJsonEquals('{"warning": 16, "strong_warning": 1, "optimization": 0, "maintainability": 0, "hygiene": 0, ' +
    '"other": 0}', Member(lSummary, ['counts', 'raw', 'by_severity']), 'by_severity');
  Assert.AreEqual(cRawExpected, AnalysisOwnershipText(Member(lSummary, ['counts', 'raw', 'ownership']) as TJSONObject));
  Assert.AreEqual('7', MemberText(lSummary, ['counts', 'actionable', 'total']));
  Assert.AreEqual(cExpected, AnalysisOwnershipText(Member(lSummary, ['counts', 'actionable', 'ownership']) as TJSONObject));
  Assert.AreEqual('2', MemberText(lSummary, ['counts', 'ignored', 'total']));
  Assert.AreEqual('4', MemberText(lSummary, ['counts', 'external', 'total']));
  Assert.AreEqual('4', MemberText(lSummary, ['counts', 'unknown', 'total']));
  Assert.AreEqual('0', MemberText(lSummary, ['counts', 'advisory_metrics', 'total']));
  AssertJsonEquals('["project", "repository"]', Member(lSummary, ['policy', 'active', 'gate_ownership']), 'gate ownership');
  Assert.AreEqual('static-analysis.full.sarif', MemberText(lSummary, ['artifacts', 'full_sarif']));
  GC(lDelta, ParseJsonObject(ReadUtf8(TPath.Combine(lOut, 'delta.json')), 'delta.json'), g);
  Assert.AreEqual(cExpected, AnalysisOwnershipText(Member(lDelta, ['ownership', 'after']) as TJSONObject));

  GC(lSarif, ParseJsonObject(ReadUtf8(TPath.Combine(lOut, 'static-analysis.sarif')), 'sarif'), g);
  GC(lSarifRows, SarifOwnership(lSarif, True), g);
  Assert.AreEqual(cExpected, OwnershipText([lSarifRows]));
  GC(lFullSarif, ParseJsonObject(ReadUtf8(TPath.Combine(lOut, 'static-analysis.full.sarif')), 'full sarif'), g);
  GC(lSarifRows, SarifOwnership(lFullSarif, False), g);
  Assert.AreEqual(cRawExpected, OwnershipText([lSarifRows]));

  lTriage := ReadUtf8(TPath.Combine(lOut, 'triage.md'));
  Assert.IsTrue(lTriage.Contains('Sample.dpr'), lTriage);
  for lName in ['NestedUnit', 'ExternalUnit', 'MissingModule', 'GuessOnly'] do
    Assert.IsFalse(lTriage.Contains(lName), lName + ' is not actionable: ' + lTriage);
  Assert.IsTrue(lTriage.Contains('showing top 1'), lTriage);
  lText := ReadUtf8(TPath.Combine(lOut, 'external-summary.md'));
  Assert.IsTrue(lText.Contains('third_party'), lText);
  Assert.IsTrue(lText.Contains(Posix(lShadow)), lText);
  for lName in ['summary.md', 'delta.md', 'trend.md', 'triage.md'] do
  begin
    lText := ReadUtf8(TPath.Combine(lOut, lName));
    for lOutput in ['project=4', 'repository=3', 'third_party=0', 'unknown=0'] do
      Assert.IsTrue(lText.Contains(lOutput), lName + ' names ' + lOutput);
  end;
  Assert.IsTrue(ReadUtf8(TPath.Combine(lOut, 'trend.md')).Contains('Latest raw ownership: ' + cRawExpected));
  GC(lHistory, LoadRows(TPath.Combine(lOut, 'history.jsonl')), g);
  Assert.AreEqual(cRawExpected, AnalysisOwnershipText(Member(Row(lHistory, lHistory.Count - 1),
    ['raw', 'ownership']) as TJSONObject));

  GC(lCounts, VerifyAnalysisReport(lOut), g);
  Assert.AreEqual(cExpected, AnalysisOwnershipText(lCounts));

  // Each published view is evidence: corrupting any one of them is reported by name.
  GC(lLines, TStringList.Create, g);
  lLines.LineBreak := #10;
  lLines.Text := lTriage;
  for i := 0 to lLines.Count - 1 do
    if lLines[i].StartsWith('- [') then
    begin
      lLines[i] := lLines[i] + ' corrupt';
      Break;
    end;
  WriteUtf8(TPath.Combine(lOut, 'triage.md'), lLines.Text);
  AssertVerifyFails(lOut, 'triage.md evidence mismatch');
  WriteUtf8(TPath.Combine(lOut, 'triage.md'), lTriage);

  lValidSarif := ReadUtf8(TPath.Combine(lOut, 'static-analysis.sarif'));
  lResultRow := Row(Member(Row(Member(lSarif, ['runs']) as TJSONArray, 0), ['results']) as TJSONArray, 0);
  JsonPutText(Member(lResultRow, ['message']) as TJSONObject, 'text', 'corrupt');
  WriteUtf8(TPath.Combine(lOut, 'static-analysis.sarif'), lSarif.ToJSON);
  AssertVerifyFails(lOut, 'static-analysis.sarif evidence mismatch');
  WriteUtf8(TPath.Combine(lOut, 'static-analysis.sarif'), lValidSarif);

  lValidFullSarif := ReadUtf8(TPath.Combine(lOut, 'static-analysis.full.sarif'));
  JsonPutText(Row(Member(Row(Member(lFullSarif, ['runs']) as TJSONArray, 0), ['results']) as TJSONArray, 0),
    'ruleId', 'corrupt');
  WriteUtf8(TPath.Combine(lOut, 'static-analysis.full.sarif'), lFullSarif.ToJSON);
  AssertVerifyFails(lOut, 'static-analysis.full.sarif evidence mismatch');
  WriteUtf8(TPath.Combine(lOut, 'static-analysis.full.sarif'), lValidFullSarif);
  Assert.AreEqual<Cardinal>(0, RunVerifyCommand(lOut, lOutput), lOutput);

  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  GC(lResult, FinalizeAnalysisReport(lOut, 'Sample', nil, -1), g);
  SetEnvironmentVariable('DAK_GATE', PChar('0'));
  Assert.IsFalse(TJSONBool(lResult.GetValue('gate_pass')).AsBoolean, 'the gate fails on unknown ownership');
  GC(lDelta, ParseJsonObject(ReadUtf8(TPath.Combine(lOut, 'delta.json')), 'gated delta.json'), g);
  lFound := False;
  for lItem in Member(lDelta, ['gate', 'reasons']) as TJSONArray do
    if lItem.Value.Contains('Unknown ownership findings: 4') then
      lFound := True;
  Assert.IsTrue(lFound, TPythonJson.Compact(Member(lDelta, ['gate', 'reasons'])));

  lValidFi := ReadUtf8(lFiPath);
  GC(lFi, LoadRows(lFiPath), g);
  JsonPutText(Row(lFi, 0), 'ownership', '');
  WriteRows(lFiPath, lFi);
  AssertVerifyFails(lOut, 'invalid ownership');
  Assert.AreEqual<Cardinal>(3, RunVerifyCommand(lOut, lOutput), lOutput);
  Assert.IsTrue(lOutput.Contains('invalid ownership'), lOutput);
  WriteUtf8(lFiPath, lValidFi);

  TFile.Move(lFiPath, lFiPath + '.missing');
  try
    AssertVerifyFails(lOut, 'requested FixInsight JSONL is missing');
  finally
    TFile.Move(lFiPath + '.missing', lFiPath);
  end;

  lValidDelta := ReadUtf8(TPath.Combine(lOut, 'delta.md'));
  WriteUtf8(TPath.Combine(lOut, 'delta.md'), lValidDelta.Replace('- After: ' + cExpected,
    '- After: project=999, repository=0, third_party=0, unknown=0'));
  AssertVerifyFails(lOut, 'delta.md After ownership mismatch');
  WriteUtf8(TPath.Combine(lOut, 'delta.md'), lValidDelta);

  GC(lSummaryCopy, ParseJsonObject(ReadUtf8(TPath.Combine(lOut, 'summary.json')), 'summary.json'), g);
  lOwnership := Member(lSummaryCopy, ['counts', 'actionable', 'ownership']) as TJSONObject;
  JsonPut(lOwnership, 'project', TJSONNumber.Create(StrToInt(JsonText(lOwnership, 'project')) + 1));
  WriteUtf8(TPath.Combine(lOut, 'summary.json'), lSummaryCopy.ToJSON);
  AssertVerifyFails(lOut, 'summary.json projection mismatch');
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisOwnershipControlTests);

end.
