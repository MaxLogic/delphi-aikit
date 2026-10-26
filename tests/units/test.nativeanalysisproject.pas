unit Test.NativeAnalysisProject;

interface

uses
  System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  Test.Support;

type
  // analyze.py's main(): the project workflow captures provenance, runs the analyzers, finalizes
  // and verifies the report, evaluates the gate and maps the result to the documented exit codes.
  // These drive the real executable against a real analyzer fixture, as Test.AnalyzeStatus does.
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisProjectTests = class
  private
    fExtraArgs: string;
    fMalformedReport: Boolean;
    fReportedFile: string;
    fRoot: string;
    fProjectDir: string;
    fProjectPath: string;
    fOutRoot: string;
    fRunLog: string;
    procedure BuildFixture;
    function RunAnalyze(const aFixInsightExit: Integer; out aProcessExit: Cardinal): string;
    function ReadSummary: TJSONObject;
    function ParseRunContextCwd: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SuccessfulRunFinalizesTheReport;
    [Test]
    procedure AnalyzerFailureKeepsItsOwnExitCode;
    [Test]
    procedure WithoutASummaryTheRunIsARejectedResult;
    [Test]
    procedure UnrequestedAnalyzersStillPublishAReport;
    [Test]
    procedure UnresolvedOwnershipFailsTheGate;
    [Test]
    procedure FinalizationFailureRecordsTheDiagnostic;
    [Test]
    procedure CleanRunPublishesAnEmptyPassingReport;
    [Test]
    procedure PlainRunNeverReplacesTheAcceptedBaseline;
    [Test]
    procedure ThirdPartyFindingsLeaveOwnedCoverageAndPalSettingsVisible;
    [Test]
    procedure CapturedProvenanceDoesNotSeeTheRunsOwnOutput;
    [Test]
    procedure RelocatedPalOutputKeepsNormalizedFindingsInTheReport;
    [Test]
    procedure PalReportNameFindingsUseRecordedMainSource;
    // Expectations pinned from workspace.resolve_workspace on the same layout (T-328 evidence).
    [TestCase('default', 'default,,none,src,auto,default')]
    [TestCase('project', 'project,project,none,src,project,command_line')]
    [TestCase('fixed', 'fixed,<fixed>,none,workspace,<fixed>,command_line')]
    [TestCase('git', 'git,git,git,workspace,git,command_line')]
    [TestCase('svn', 'svn,svn,svn,workspace,svn,command_line')]
    [TestCase('auto-svn', 'auto-svn,auto,svn,workspace,auto,command_line')]
    [TestCase('ini-project', 'ini-project,,none,src,project,<ini>')]
    procedure WorkspaceSelectorMatrixPublishesTheResolvedWorkspace(const aName, aSelector, aVcs, aRoot,
      aExpectedSelector, aExpectedSource: string);
    [TestCase('explicit', 'explicit')]
    [TestCase('closest-ini', 'closest-ini')]
    procedure OuterGitCheckoutDoesNotBecomeTheWorkspace(const aMode: string);
  end;

implementation

uses
  System.RegularExpressions,
  Dak.Analysis.ReportBundle;

function RunGit(const aRepo, aArguments: string): string;
var
  lExitCode: Cardinal;
  lGit, lLog: string;
begin
  lGit := FileSearch('git.exe', GetEnvironmentVariable('PATH'));
  Assert.IsTrue(lGit <> '', 'git.exe must be on PATH for this test');
  lLog := TPath.Combine(TPath.GetTempPath, 'dak-project-git-' + TGUID.NewGuid.ToString + '.log');
  try
    Assert.IsTrue(RunCommandProcess(lGit, aArguments, aRepo, lLog, lExitCode), 'git must run: ' + aArguments);
    Result := TFile.ReadAllText(lLog);
    Assert.AreEqual<Cardinal>(0, lExitCode, 'git ' + aArguments + ': ' + Result);
  finally
    if TFile.Exists(lLog) then
      TFile.Delete(lLog);
  end;
end;

// test_delphi_seed_matches_python_selector_matrix, finalized: every selector form publishes the
// workspace the reference resolver chose for the same layout.
procedure TNativeAnalysisProjectTests.WorkspaceSelectorMatrixPublishesTheResolvedWorkspace(const aName, aSelector,
  aVcs, aRoot, aExpectedSelector, aExpectedSource: string);
var
  lArgs, lCaseRoot, lExpectedRoot, lExpectedSelector, lExpectedSource, lLog, lOut, lProject, lProjectDir,
    lSelector, lWorkspace: string;
  lExit: Cardinal;
  lSummary, lWorkspaceJson: TJSONObject;
begin
  lCaseRoot := TPath.Combine(fRoot, aName);
  lWorkspace := TPath.Combine(lCaseRoot, 'workspace');
  lProjectDir := TPath.Combine(lWorkspace, 'src');
  TDirectory.CreateDirectory(lProjectDir);
  lProject := TPath.Combine(lProjectDir, 'Sample.dproj');
  TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'), lProject);
  TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dpr'), TPath.Combine(lProjectDir, 'Sample.dpr'));
  if aName = 'git' then
    TFile.WriteAllText(TPath.Combine(lWorkspace, '.git'), 'gitdir: elsewhere'#10, TEncoding.ASCII);
  if (aName = 'svn') or (aName = 'auto-svn') then
  begin
    TDirectory.CreateDirectory(TPath.Combine(lWorkspace, '.svn'));
    TDirectory.CreateDirectory(TPath.Combine(lCaseRoot, '.git'));
  end;
  if aName = 'ini-project' then
    TFile.WriteAllText(TPath.Combine(lProjectDir, 'dak.ini'), '[workspace]'#10'root=project'#10, TEncoding.ASCII);
  lSelector := aSelector.Replace('<fixed>', lWorkspace);
  lOut := TPath.Combine(lCaseRoot, 'out');
  lArgs := 'analyze --project ' + QuoteArg(lProject) + ' --delphi 23.0 --platform Win64 --config Debug' +
    ' --fixinsight false --pascal-analyzer false --out ' + QuoteArg(lOut);
  if lSelector <> '' then
    lArgs := lArgs + ' --workspace-root ' + QuoteArg(lSelector);
  lLog := TPath.Combine(fRoot, aName + '.log');
  Assert.IsTrue(RunResolverProcess(lArgs, lCaseRoot, lLog, lExit), 'analysis must start');
  // The git case's marker points nowhere: finalization cannot read the revision and fails with
  // exit 4, as the reference postprocessor raised on the same Git failure. The seed it patches
  // still records the resolved workspace, which is what the reference matrix compared.
  if aName = 'git' then
    Assert.AreEqual(Cardinal(4), lExit, TFile.ReadAllText(lLog))
  else
    Assert.AreEqual(Cardinal(0), lExit, TFile.ReadAllText(lLog));

  if aRoot = 'src' then
    lExpectedRoot := lProjectDir
  else
    lExpectedRoot := lWorkspace;
  lExpectedSelector := aExpectedSelector.Replace('<fixed>', lWorkspace);
  lExpectedSource := aExpectedSource.Replace('<ini>', TPath.Combine(lProjectDir, 'dak.ini'));
  lSummary := ParseJsonObject(TFile.ReadAllText(TPath.Combine(lOut, 'summary.json')), 'summary.json');
  try
    lWorkspaceJson := JsonObjectMember(lSummary, 'workspace');
    Assert.IsTrue(SameText(lExpectedRoot, JsonText(lWorkspaceJson, 'root')), 'root: ' + lWorkspaceJson.ToJSON);
    Assert.IsTrue(SameText(lExpectedSelector, JsonText(lWorkspaceJson, 'selector')), 'selector: ' + lWorkspaceJson.ToJSON);
    Assert.AreEqual(aVcs, JsonText(lWorkspaceJson, 'vcs'), 'vcs');
    Assert.IsTrue(SameText(lExpectedSource, JsonText(lWorkspaceJson, 'source')), 'source: ' + lWorkspaceJson.ToJSON);
  finally
    lSummary.Free;
  end;
end;

// A workspace nested in an unrelated outer Git checkout stays the workspace for project and unit
// analysis, whether "." is given on the command line or by the closest dak.ini.
procedure TNativeAnalysisProjectTests.OuterGitCheckoutDoesNotBecomeTheWorkspace(const aMode: string);
var
  lArgs, lLog, lOut, lProject, lSelector, lSourceDir, lUnit, lWorkspace: string;
  lExit: Cardinal;
  i: Integer;
  lScope: IInterface;
  lSummary: TJSONObject;
begin
  lWorkspace := TPath.Combine(fRoot, 'outer\workspace');
  lSourceDir := TPath.Combine(lWorkspace, 'src');
  TDirectory.CreateDirectory(TPath.Combine(fRoot, 'outer\.git'));
  TDirectory.CreateDirectory(lSourceDir);
  lSelector := '';
  if aMode = 'explicit' then
    lSelector := ' --workspace-root .'
  else
    TFile.WriteAllText(TPath.Combine(lWorkspace, 'dak.ini'), '[Workspace]'#10'Root=.'#10, TEncoding.ASCII);
  lProject := TPath.Combine(lSourceDir, 'Sample.dproj');
  TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'), lProject);
  TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dpr'), TPath.Combine(lSourceDir, 'Sample.dpr'));
  lUnit := TPath.Combine(lSourceDir, 'Sample.pas');
  TFile.WriteAllText(lUnit, 'unit Sample; interface implementation end.', TEncoding.ASCII);
  for i := 0 to 1 do
  begin
    if i = 0 then
    begin
      lOut := TPath.Combine(fRoot, 'outer\project-out');
      lArgs := 'analyze --project ' + QuoteArg(lProject) + ' --delphi 23.0 --platform Win64 --config Debug' +
        ' --fixinsight false --pascal-analyzer false';
    end else begin
      lOut := TPath.Combine(fRoot, 'outer\unit-out');
      // The unit route needs an analyzer, so the DUnitX executable stands in for PALCMD.
      lArgs := 'analyze-unit --unit ' + QuoteArg(lUnit) + ' --delphi 23.0 --pascal-analyzer true --pa-path ' +
        QuoteArg(ParamStr(0));
    end;
    lArgs := lArgs + ' --out ' + QuoteArg(lOut) + lSelector;
    lLog := TPath.Combine(fRoot, aMode + '-' + i.ToString + '.log');
    lScope := SetScopedEnvironmentVariable('DAK_TEST_PAL_EXIT', '0');
    Assert.IsTrue(RunResolverProcess(lArgs, lWorkspace, lLog, lExit), 'analysis must start');
    lScope := nil;
    Assert.AreEqual(Cardinal(0), lExit, TFile.ReadAllText(lLog));
    lSummary := ParseJsonObject(TFile.ReadAllText(TPath.Combine(lOut, 'summary.json')), 'summary.json');
    try
      Assert.IsTrue(SameText(lWorkspace, JsonText(JsonObjectMember(lSummary, 'workspace'), 'root')),
        lArgs + ': ' + JsonObjectMember(lSummary, 'workspace').ToJSON);
    finally
      lSummary.Free;
    end;
  end;
end;

// analyze.py captured provenance before DAK started, so a committed workspace was clean even though
// the run then wrote untracked output into it.
procedure TNativeAnalysisProjectTests.CapturedProvenanceDoesNotSeeTheRunsOwnOutput;
var
  lExit: Cardinal;
  lLog: string;
  lSummary, lTarget: TJSONObject;
  lGitScope: IInterface;
begin
  lGitScope := SetScopedGitConfiguration(fRoot);
  TFile.WriteAllText(TPath.Combine(fRoot, '.gitignore'), 'analyze.log'#10, TEncoding.ASCII);
  RunGit(fRoot, 'init -q');
  RunGit(fRoot, 'add .');
  RunGit(fRoot, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture');
  lLog := RunAnalyze(0, lExit);
  Assert.IsFalse(RunGit(fRoot, 'status --porcelain').Trim.IsEmpty, 'the run left untracked output behind');
  lSummary := ReadSummary;
  try
    lTarget := JsonObjectMember(JsonObjectMember(lSummary, 'provenance'), 'target');
    Assert.AreEqual('False', JsonText(lTarget, 'dirty'), 'captured before the run wrote anything: ' + lTarget.ToJSON);
    Assert.AreEqual(40, Length(JsonText(lTarget, 'head')), lTarget.ToJSON);
  finally
    lSummary.Free;
  end;
end;

procedure TNativeAnalysisProjectTests.Setup;
begin
  EnsureResolverBuilt;
  // The fixture instance can be reused across tests, so every per-test switch starts cleared.
  fExtraArgs := '';
  fMalformedReport := False;
  fReportedFile := '';
  fRoot := UniqueNoRepoTempPath('native-analysis-project');
  BuildFixture;
end;

procedure TNativeAnalysisProjectTests.TearDown;
begin
  DeleteTempPath(fRoot);
end;

procedure TNativeAnalysisProjectTests.BuildFixture;
begin
  fProjectDir := TPath.Combine(fRoot, 'project');
  TDirectory.CreateDirectory(fProjectDir);
  fProjectPath := TPath.Combine(fProjectDir, 'Sample.dproj');
  TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'), fProjectPath);
  TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dpr'), TPath.Combine(fProjectDir, 'Sample.dpr'));
  TFile.WriteAllText(TPath.Combine(fProjectDir, 'dak.ini'),
    '[Workspace]' + sLineBreak +
    'Root=project' + sLineBreak +
    '[FixInsightCL]' + sLineBreak +
    'Path=' + ParamStr(0) + sLineBreak +
    '[AnalysisPolicy]' + sLineBreak +
    'GateOwnership=repository;project' + sLineBreak +
    'ProjectRoots=.' + sLineBreak, TEncoding.ASCII);
  fOutRoot := TPath.Combine(fRoot, '.dak\Sample');
  fRunLog := TPath.Combine(fRoot, 'analyze.log');
end;

function TNativeAnalysisProjectTests.RunAnalyze(const aFixInsightExit: Integer;
  out aProcessExit: Cardinal): string;
var
  lArgs: string;
  lOldExit: string;
  lOldFile: string;
begin
  lArgs := 'analyze --project ' + QuoteArg(fProjectPath) +
    ' --platform Win64 --config Debug --delphi 23.0 --workspace-root ' + QuoteArg(fRoot) +
    ' --fixinsight true --pascal-analyzer false --fi-formats txt --out ' + QuoteArg(fOutRoot) +
    fExtraArgs;
  lOldExit := GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT');
  lOldFile := GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_FILE');
  SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT', PChar(aFixInsightExit.ToString));
  if fReportedFile <> '' then
    SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_FILE', PChar(fReportedFile));
  if fMalformedReport then
    SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_MALFORMED', '1');
  try
    Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, fRunLog, aProcessExit),
      'Failed to start the project analysis process.');
  finally
    SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_MALFORMED', nil);
    if lOldExit = '' then
      SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT', nil)
    else
      SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT', PChar(lOldExit));
    if lOldFile = '' then
      SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_FILE', nil)
    else
      SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_FILE', PChar(lOldFile));
  end;
  Result := TFile.ReadAllText(fRunLog);
end;

function TNativeAnalysisProjectTests.ReadSummary: TJSONObject;
var
  lPath: string;
begin
  lPath := TPath.Combine(fOutRoot, 'summary.json');
  Assert.IsTrue(TFile.Exists(lPath), 'Expected a published summary: ' + lPath);
  Result := ParseJsonObject(TFile.ReadAllText(lPath), lPath);
end;

function TNativeAnalysisProjectTests.ParseRunContextCwd: string;
var
  lBaseline: TJSONObject;
begin
  lBaseline := ParseJsonObject(TFile.ReadAllText(TPath.Combine(fOutRoot, 'baseline.json')), 'baseline.json');
  try
    Result := lBaseline.GetValue<string>('run_context.host.analysis_cwd');
  finally
    lBaseline.Free;
  end;
end;

procedure TNativeAnalysisProjectTests.SuccessfulRunFinalizesTheReport;
var
  lExit: Cardinal;
  lLog: string;
  lSummary: TJSONObject;
begin
  lLog := RunAnalyze(0, lExit);
  Assert.AreEqual(Cardinal(0), lExit, 'A passing project run exits zero. Run log: ' + lLog);
  lSummary := ReadSummary;
  try
    Assert.AreEqual('complete', JsonText(JsonObjectMember(lSummary, 'status'), 'finalization'),
      'The project workflow must finalize the report, not stop at the status seed.');
    Assert.AreEqual(3, StrToIntDef(JsonText(lSummary, 'schema_version'), 0),
      'A finalized report publishes schema version 3.');
    Assert.IsTrue(TFile.Exists(TPath.Combine(fOutRoot, 'triage.md')),
      'The finalized report publishes triage.md.');
    // analyze.py started DAK with cwd=workspace.root; RunAnalyze starts it from the repository root.
    Assert.AreEqual(ExcludeTrailingPathDelimiter(lSummary.GetValue<string>('workspace.root')),
      ExcludeTrailingPathDelimiter(ParseRunContextCwd), 'The analyzers run in the workspace root.');
    // summary_json["artifacts"].update(...) only adds artifacts that exist; Pascal Analyzer was not
    // requested, so it has no entry, not an empty one. Found by Compare -Area Project.
    Assert.IsNull(JsonObjectMember(lSummary, 'artifacts').GetValue('pascal_analyzer_jsonl'),
      'An unpublished artifact has no entry: ' + JsonObjectMember(lSummary, 'artifacts').ToJSON);
    Assert.AreEqual('fixinsight/fi-findings.jsonl',
      JsonText(JsonObjectMember(lSummary, 'artifacts'), 'fixinsight_jsonl'));
  finally
    lSummary.Free;
  end;
end;

// A failing analyzer is the run's own answer: the workflow must not replace it with a gate verdict
// or with its own success.
procedure TNativeAnalysisProjectTests.AnalyzerFailureKeepsItsOwnExitCode;
var
  lExit: Cardinal;
  lSummary: TJSONObject;
begin
  RunAnalyze(7, lExit);
  Assert.AreEqual(Cardinal(7), lExit, 'The analyzer exit code is the run result.');
  lSummary := ReadSummary;
  try
    // run_postprocess still runs after a failed analyzer. Like the reference (postprocess.py
    // publishes status_summary with schema_version 2) it keeps the seed schema and marks the
    // infrastructure failure, with a refusing delta beside it.
    Assert.AreEqual(2, StrToIntDef(JsonText(lSummary, 'schema_version'), 0),
      'An infrastructure failure publishes the schema-2 status summary, as the reference does.');
    Assert.IsTrue(TFile.Exists(TPath.Combine(fOutRoot, 'delta.md')),
      'An infrastructure failure still publishes the refusing delta.');
    Assert.IsFalse(TFile.Exists(TPath.Combine(fOutRoot, 'postprocessor-error.txt')),
      'An analyzer failure is not a postprocessor failure.');
    Assert.AreEqual('failed', JsonText(JsonObjectMember(lSummary, 'status'), 'infrastructure'),
      'A failed analyzer must never read as complete infrastructure.');
  finally
    lSummary.Free;
  end;
end;

// analyze.py returns 3 when the run published no summary to process.
procedure TNativeAnalysisProjectTests.WithoutASummaryTheRunIsARejectedResult;
var
  lExit: Cardinal;
  lLog: string;
begin
  fExtraArgs := ' --write-summary false';
  lLog := RunAnalyze(0, lExit);
  Assert.AreEqual(Cardinal(3), lExit, 'A run with no summary is a rejected result.');
  Assert.IsTrue(lLog.Contains('Summary not found: '), lLog);
  Assert.IsFalse(TFile.Exists(TPath.Combine(fOutRoot, 'summary.md')),
    'The fixture must not have published a summary.');
end;

// Requesting no analyzer is not a failure: the report is published with empty findings.
procedure TNativeAnalysisProjectTests.UnrequestedAnalyzersStillPublishAReport;
var
  lExit: Cardinal;
  lSummary: TJSONObject;
begin
  fExtraArgs := ' --fixinsight false';
  RunAnalyze(0, lExit);
  Assert.AreEqual(Cardinal(0), lExit, 'A run with no analyzer requested still succeeds.');
  lSummary := ReadSummary;
  try
    Assert.AreEqual('complete', JsonText(JsonObjectMember(lSummary, 'status'), 'finalization'),
      'The report is finalized even with nothing to analyze.');
    Assert.AreEqual(0, lSummary.GetValue<Integer>('counts.raw.total'),
      'No requested analyzer means no findings.');
  finally
    lSummary.Free;
  end;
end;

// Ownership is fail-closed: a finding the workspace cannot place fails a gated run before any
// baseline is created.
procedure TNativeAnalysisProjectTests.UnresolvedOwnershipFailsTheGate;
var
  lExit: Cardinal;
  lOldGate: string;
  lSummary: TJSONObject;
begin
  fReportedFile := 'Z:\nowhere\Absent.pas';
  lOldGate := GetEnvironmentVariable('DAK_GATE');
  SetEnvironmentVariable('DAK_GATE', '1');
  try
    RunAnalyze(0, lExit);
  finally
    if lOldGate = '' then
      SetEnvironmentVariable('DAK_GATE', nil)
    else
      SetEnvironmentVariable('DAK_GATE', PChar(lOldGate));
  end;
  lSummary := ReadSummary;
  try
    Assert.AreEqual(Cardinal(3), lExit, 'A failed gate is a rejected result. Published status: ' +
      JsonObjectMember(lSummary, 'status').ToJSON + ' counts: ' +
      JsonObjectMember(JsonObjectMember(lSummary, 'counts'), 'raw').ToJSON);
    Assert.AreEqual('fail', JsonText(JsonObjectMember(lSummary, 'status'), 'policy'),
      'The published status must record the refused policy.');
    Assert.IsFalse(TFile.Exists(TPath.Combine(fOutRoot, 'baseline.json')),
      'A refused run must not create a baseline.');
  finally
    lSummary.Free;
  end;
end;

// _record_postprocessor_failure: a finalization failure after a successful analyzer is exit 4,
// leaves the traceback beside the report and marks the published summary as incomplete.
procedure TNativeAnalysisProjectTests.FinalizationFailureRecordsTheDiagnostic;
var
  lError: string;
  lErrors: TJSONArray;
  lExit: Cardinal;
  lItem: TJSONValue;
  lLog: string;
  lStatus: TJSONObject;
  lSummary: TJSONObject;
begin
  fMalformedReport := True;
  lLog := RunAnalyze(0, lExit);
  Assert.AreEqual(Cardinal(4), lExit, 'Finalization failure over a successful analyzer is exit 4. Log: ' + lLog);
  Assert.IsTrue(lLog.Contains('Post-processing failed after successful analyzer: '), lLog);
  Assert.IsTrue(TFile.Exists(TPath.Combine(fOutRoot, 'postprocessor-error.txt')),
    'The diagnostic must be left beside the report.');
  // The diagnostic names the exception class and its message, as the reference traceback tail did.
  Assert.IsTrue(TRegEx.IsMatch(TFile.ReadAllText(TPath.Combine(fOutRoot, 'postprocessor-error.txt')), '^E\w+: \S'),
    TFile.ReadAllText(TPath.Combine(fOutRoot, 'postprocessor-error.txt')));
  lSummary := ReadSummary;
  try
    lStatus := JsonObjectMember(lSummary, 'status');
    Assert.AreEqual('complete', JsonText(lStatus, 'infrastructure'), 'the analyzers themselves completed');
    Assert.AreEqual('failed', JsonText(lStatus, 'postprocessor'), 'status.postprocessor');
    Assert.AreEqual('incomplete', JsonText(lStatus, 'finalization'), 'status.finalization');
    Assert.AreEqual('postprocessor-error.txt',
      JsonText(JsonObjectMember(lSummary, 'artifacts'), 'postprocessor_diagnostic'),
      'artifacts.postprocessor_diagnostic');
    lErrors := JsonArrayMember(lSummary, 'errors');
    Assert.IsNotNull(lErrors, 'The summary must list the failure.');
    lError := '';
    for lItem in lErrors do
      if lItem.Value.StartsWith('Postprocessor failed: ') then
        lError := lItem.Value;
    Assert.IsNotEmpty(lError, 'errors must name the postprocessor failure: ' + lErrors.ToJSON);
  finally
    lSummary.Free;
  end;
end;

// A clean analyzer run is a finished report with nothing in it, not a missing one.
procedure TNativeAnalysisProjectTests.CleanRunPublishesAnEmptyPassingReport;
var
  lClean: IInterface;
  lExit: Cardinal;
  lLog: string;
  lSummary: TJSONObject;
begin
  lClean := SetScopedEnvironmentVariable('DAK_TEST_FIXINSIGHT_CLEAN', '1');
  lLog := RunAnalyze(0, lExit);
  Assert.AreEqual(Cardinal(0), lExit, 'A clean run passes. Log: ' + lLog);
  lSummary := ReadSummary;
  try
    Assert.AreEqual('complete', JsonText(JsonObjectMember(lSummary, 'status'), 'finalization'));
    Assert.AreEqual(0, lSummary.GetValue<Integer>('counts.raw.total'), 'No findings.');
    Assert.IsTrue(TFile.Exists(TPath.Combine(fOutRoot, 'fixinsight\fi-findings.jsonl')),
      'A requested, complete analyzer owns an empty findings file.');
    Assert.AreEqual(Int64(0), TFile.GetSize(TPath.Combine(fOutRoot, 'fixinsight\fi-findings.jsonl')));
  finally
    lSummary.Free;
  end;
end;

// A plain run compares against the accepted baseline; only an explicit update may replace it.
procedure TNativeAnalysisProjectTests.PlainRunNeverReplacesTheAcceptedBaseline;
var
  lAccepted: TBytes;
  lCurrent: TBytes;
  lClean: IInterface;
  lDelta: TJSONObject;
  lExit: Cardinal;
  lPath: string;
begin
  RunAnalyze(0, lExit);
  Assert.AreEqual(Cardinal(0), lExit, 'The first run creates the baseline.');
  lPath := TPath.Combine(fOutRoot, 'baseline.json');
  Assert.IsTrue(TFile.Exists(lPath), 'The first run publishes a baseline.');
  lAccepted := TFile.ReadAllBytes(lPath);

  // Different results on the second run: the findings disappear.
  lClean := SetScopedEnvironmentVariable('DAK_TEST_FIXINSIGHT_CLEAN', '1');
  RunAnalyze(0, lExit);
  lClean := nil;
  Assert.AreEqual(Cardinal(0), lExit, 'An ungated second run passes.');
  lCurrent := TFile.ReadAllBytes(lPath);
  // Compare contents: = on two dynamic arrays compares their references.
  Assert.IsTrue((Length(lCurrent) = Length(lAccepted)) and
    ((Length(lAccepted) = 0) or CompareMem(@lCurrent[0], @lAccepted[0], Length(lAccepted))),
    'A plain run must leave the accepted baseline byte-identical.');
  lDelta := ParseJsonObject(TFile.ReadAllText(TPath.Combine(fOutRoot, 'delta.json')), 'delta.json');
  try
    // A creating run marks baseline.created; a comparing run reports the counts that changed.
    Assert.IsNull(JsonObjectMember(lDelta, 'baseline').GetValue('created'),
      'The second run compares against the existing baseline.');
    Assert.AreEqual(-2, lDelta.GetValue<Integer>('fixinsight.total_delta'),
      'The comparison sees both owned findings gone.');
  finally
    lDelta.Free;
  end;
end;

// Routine third-party handling keeps vendor rows out of owned coverage without hiding the owned
// findings, and the effective Pascal Analyzer exclusions stay visible in the published report.
procedure TNativeAnalysisProjectTests.ThirdPartyFindingsLeaveOwnedCoverageAndPalSettingsVisible;
var
  lExit: Cardinal;
  lExternal: string;
  lLog: string;
  lPal: TJSONObject;
  lScopes: IInterface;
  lSummary: TJSONObject;
begin
  // Outside the workspace root: inside it, both engines treat any folder as repository code.
  lExternal := fRoot + '-vendor';
  TDirectory.CreateDirectory(lExternal);
  try
  TFile.WriteAllText(TPath.Combine(lExternal, 'Vendor.pas'), 'unit Vendor;' + sLineBreak, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(fProjectDir, 'dak.ini'),
    '[Workspace]' + sLineBreak +
    'Root=project' + sLineBreak +
    '[FixInsightCL]' + sLineBreak +
    'Path=' + ParamStr(0) + sLineBreak +
    '[AnalysisPolicy]' + sLineBreak +
    'GateOwnership=repository;project' + sLineBreak +
    'ProjectRoots=.' + sLineBreak +
    'ThirdPartyRoots=' + lExternal + sLineBreak, TEncoding.ASCII);
  fExtraArgs := ' --pascal-analyzer true --pa-path ' + QuoteArg(ParamStr(0)) +
    ' --pa-exclude-search-folders ' + QuoteArg(lExternal) + ' --pa-exclude-files Vendor.pas';
  lScopes := SetScopedEnvironmentVariables(['DAK_TEST_FIXINSIGHT_THIRD_PARTY', TPath.Combine(lExternal, 'Vendor.pas'),
    'DAK_TEST_PAL_EXIT', '0', 'DAK_GATE', '1']);
  lLog := RunAnalyze(0, lExit);
  lScopes := nil;
  Assert.AreEqual(Cardinal(0), lExit, 'A vendor finding does not fail the owned gate. Log: ' + lLog);
  lSummary := ReadSummary;
  try
    Assert.AreEqual(2, lSummary.GetValue<Integer>('counts.raw.ownership.project'), 'owned rows');
    Assert.AreEqual(1, lSummary.GetValue<Integer>('counts.raw.ownership.third_party'), 'vendor rows');
    Assert.AreEqual(0, lSummary.GetValue<Integer>('counts.raw.ownership.unknown'), 'nothing unplaced');
    Assert.AreEqual(2, lSummary.GetValue<Integer>('counts.actionable.fixinsight.total'),
      'Every owned finding stays actionable.');
    Assert.AreEqual(1, lSummary.GetValue<Integer>('counts.external.fixinsight.total'),
      'The vendor finding is reported as external, not dropped.');
    lPal := lSummary.GetValue<TJSONObject>('analyzers.pascal_analyzer');
    Assert.AreEqual('complete', JsonText(lPal, 'status'), 'Pascal Analyzer ran.');
    Assert.AreEqual(lExternal, JsonText(JsonObjectMember(lPal, 'options'), 'exclude_search_folders'),
      'The effective search-folder exclusion is visible.');
    Assert.AreEqual('Vendor.pas', JsonText(JsonObjectMember(lPal, 'options'), 'exclude_files'),
      'The effective file exclusion is visible.');
  finally
    lSummary.Free;
  end;
  finally
    DeleteTempPath(lExternal);
  end;
end;

// T-343 contract: --pa-output moves only the raw Pascal Analyzer XML reports. The normalized rows
// publish under the report's pascal-analyzer folder, where finalization, replay and verify read them.
procedure TNativeAnalysisProjectTests.PalReportNameFindingsUseRecordedMainSource;
var
  lExit: Cardinal;
  lJson: TJSONObject;
  lLines: TArray<string>;
  lLog: string;
  lScope: IInterface;
  lSummary: TJSONObject;
  i: Integer;
begin
  TFile.Move(TPath.Combine(fProjectDir, 'Sample.dpr'),
    TPath.Combine(fProjectDir, 'Sample.Project.dpr'));
  TFile.WriteAllText(fProjectPath,
    TFile.ReadAllText(fProjectPath).Replace('<MainSource>Sample.dpr</MainSource>',
      '<MainSource>Sample.Project.dpr</MainSource>'), TEncoding.UTF8);
  fReportedFile := 'Sample.Project.dpr';
  fExtraArgs := ' --pascal-analyzer true --pa-path ' + QuoteArg(ParamStr(0));
  lScope := SetScopedEnvironmentVariables(['DAK_TEST_PAL_EXIT', '0', 'DAK_TEST_PAL_IDENTITY', '1']);
  lLog := RunAnalyze(0, lExit);
  lScope := nil;
  Assert.AreEqual(Cardinal(0), lExit, 'The report-name findings remain owned. Log: ' + lLog);
  lSummary := ReadSummary;
  try
    Assert.AreEqual(0, lSummary.GetValue<Integer>('counts.raw.ownership.unknown'));
    Assert.AreEqual(4, lSummary.GetValue<Integer>('counts.raw.ownership.project'));
  finally
    lSummary.Free;
  end;
  lLines := TFile.ReadAllLines(TPath.Combine(fOutRoot, 'pascal-analyzer\pal-findings.jsonl'));
  Assert.AreEqual(2, Integer(Length(lLines)));
  for i := 0 to High(lLines) do
  begin
    lJson := ParseJsonObject(lLines[i]);
    try
      if i = 0 then
        Assert.AreEqual('Sample.Project', lJson.GetValue<string>('module'))
      else
        Assert.AreEqual('Sample.Project\TWorker\Run', lJson.GetValue<string>('module'));
      Assert.AreEqual('resolved', lJson.GetValue<string>('path_status'));
      Assert.AreEqual('project', lJson.GetValue<string>('ownership'));
      Assert.IsTrue(SameText(TPath.Combine(fProjectDir, 'Sample.Project.dpr'),
        lJson.GetValue<string>('source_path')), lJson.ToJSON);
    finally
      lJson.Free;
    end;
  end;
end;

procedure TNativeAnalysisProjectTests.RelocatedPalOutputKeepsNormalizedFindingsInTheReport;
var
  lExit: Cardinal;
  lLog: string;
  lPalDir: string;
  lRelocated: string;
  lScope: IInterface;
  lSummary: TJSONObject;
begin
  lRelocated := TPath.Combine(fRoot, 'pa-relocated');
  lPalDir := TPath.Combine(fOutRoot, 'pascal-analyzer');
  fExtraArgs := ' --pascal-analyzer true --pa-path ' + QuoteArg(ParamStr(0)) + ' --pa-output ' + QuoteArg(lRelocated);
  lScope := SetScopedEnvironmentVariable('DAK_TEST_PAL_EXIT', '0');
  lLog := RunAnalyze(0, lExit);
  lScope := nil;
  Assert.AreEqual(Cardinal(0), lExit, 'A relocated PAL output still finalizes the report. Log: ' + lLog);
  Assert.IsTrue(TFile.Exists(TPath.Combine(lRelocated, 'Sample\Status.xml')),
    'The raw PAL reports go to the relocated root.');
  Assert.IsTrue(TFile.Exists(TPath.Combine(lPalDir, 'pal-findings.jsonl')), 'normalized rows in the report');
  Assert.IsTrue(TFile.Exists(TPath.Combine(lPalDir, 'pal-findings.md')), 'findings summary in the report');
  Assert.IsFalse(TFile.Exists(TPath.Combine(lRelocated, 'pal-findings.jsonl')),
    'Nothing normalized is left beside the raw reports.');
  lSummary := ReadSummary;
  try
    Assert.AreEqual('complete', JsonText(JsonObjectMember(lSummary, 'status'), 'finalization'));
    Assert.AreEqual('pascal-analyzer/pal-findings.jsonl',
      JsonText(JsonObjectMember(lSummary, 'artifacts'), 'pascal_analyzer_jsonl'));
  finally
    lSummary.Free;
  end;
end;

end.
