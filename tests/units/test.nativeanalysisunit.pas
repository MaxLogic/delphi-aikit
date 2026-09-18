unit Test.NativeAnalysisUnit;

interface

uses
  System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  Test.Support;

type
  // analyze-unit.py's main(): the unit workflow runs Pascal Analyzer on one unit, standalone or in a
  // project context, then finalizes the report exactly as the project workflow does. These drive the
  // real executable with the DUnitX executable standing in for PALCMD.
  [TestFixture]
  TNativeAnalysisUnitTests = class
  private
    fRoot: string;
    fProjectDir: string;
    fProjectPath: string;
    fUnitPath: string;
    fOutRoot: string;
    fRunLog: string;
    fExtraArgs: string;
    procedure BuildFixture(const aUnitDirectory, aUnitName: string);
    function RunUnit(const aPalExit: Integer; aWithContext: Boolean; out aProcessExit: Cardinal): string;
    function ReadSummary: TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StandaloneUnitFinalizesTheReport;
    [Test]
    procedure ProjectContextUnitFinalizesUnderTheUnitTitle;
    [Test]
    procedure AnalyzerFailureKeepsItsOwnExitCode;
    [Test]
    procedure WithoutASummaryTheRunIsARejectedResult;
    [Test]
    procedure MissingUnitIsInvalidProjectInput;
    [Test]
    procedure UnicodeAndSpacedPathsFinalize;
    [Test]
    procedure ProjectSelectorResolvesTheContextWorkspace;
    [Test]
    procedure AnalyzersRunInTheWorkspaceRootWhateverTheCallerDirectory;
    [Test]
    procedure FailedRunInACommittedWorkspaceKeepsBaselineAndCapturedProvenance;
    [Test]
    procedure RelocatedPalOutputFromDakIniKeepsNormalizedFindingsInTheReport;
  end;

implementation

uses
  Dak.Analysis.ReportBundle;

function RunGit(const aRepo, aArguments: string): string;
var
  lExitCode: Cardinal;
  lGit, lLog: string;
begin
  lGit := FileSearch('git.exe', GetEnvironmentVariable('PATH'));
  Assert.IsTrue(lGit <> '', 'git.exe must be on PATH for this test');
  lLog := TPath.Combine(TPath.GetTempPath, 'dak-unit-git-' + TGUID.NewGuid.ToString + '.log');
  try
    Assert.IsTrue(RunCommandProcess(lGit, aArguments, aRepo, lLog, lExitCode), 'git must run: ' + aArguments);
    Result := TFile.ReadAllText(lLog);
    Assert.AreEqual<Cardinal>(0, lExitCode, 'git ' + aArguments + ': ' + Result);
  finally
    if TFile.Exists(lLog) then
      TFile.Delete(lLog);
  end;
end;

// test_valid_failed_summary_is_postprocessed_without_masking_dak_exit: a failed analyzer run in a
// committed workspace is still finalized, keeps its exit code and the accepted baseline, and records
// the provenance captured before the run wrote its untracked output.
procedure TNativeAnalysisUnitTests.FailedRunInACommittedWorkspaceKeepsBaselineAndCapturedProvenance;
var
  lBaseline: string;
  lBaselineBytes, lAfter: TBytes;
  lCounts, lSummary, lTarget: TJSONObject;
  lExit: Cardinal;
  lLog: string;
  lScope: IInterface;
begin
  lBaseline := TPath.Combine(fRoot, 'accepted-baseline.json');
  TFile.WriteAllText(lBaseline, '{'#13#10'  "version": 1'#13#10'}'#13#10, TEncoding.ASCII);
  lBaselineBytes := TFile.ReadAllBytes(lBaseline);
  // Only the harness log is ignored; the run's own output stays visible to Git.
  TFile.WriteAllText(TPath.Combine(fRoot, '.gitignore'), 'analyze-unit.log'#10, TEncoding.ASCII);
  RunGit(fRoot, 'init -q');
  RunGit(fRoot, 'add .');
  RunGit(fRoot, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture');
  lScope := SetScopedEnvironmentVariables(['DAK_BASELINE', lBaseline, 'DAK_UPDATE_BASELINE', '1']);

  lLog := RunUnit(7, True, lExit);
  Assert.AreEqual(Cardinal(7), lExit, 'The analyzer exit code is the run result. Log: ' + lLog);
  Assert.IsTrue(TFile.Exists(TPath.Combine(fOutRoot, 'delta.json')), 'the failed run is still finalized');
  lAfter := TFile.ReadAllBytes(lBaseline);
  Assert.IsTrue((Length(lAfter) = Length(lBaselineBytes)) and CompareMem(@lAfter[0], @lBaselineBytes[0], Length(lAfter)),
    'the accepted baseline is unchanged');
  Assert.IsFalse(RunGit(fRoot, 'status --porcelain').Trim.IsEmpty, 'the run left untracked output behind');
  lSummary := ReadSummary;
  try
    Assert.AreEqual('failed', JsonText(JsonObjectMember(lSummary, 'status'), 'infrastructure'));
    Assert.AreEqual('not_evaluated', JsonText(JsonObjectMember(lSummary, 'status'), 'policy'));
    // The version kept from a failed run's summary is asserted at service level in
    // TNativeAnalysisReportControlTests.FailedSummaryKeepsItsPalVersionWithoutATotal.
    lCounts := JsonObjectMember(JsonObjectMember(lSummary, 'counts'), 'pascal_analyzer');
    Assert.IsNotNull(lCounts, lSummary.ToJSON);
    Assert.IsNull(lCounts.GetValue('total'), 'a failed PAL run publishes no total');
    lTarget := JsonObjectMember(JsonObjectMember(lSummary, 'provenance'), 'target');
    Assert.AreEqual('False', JsonText(lTarget, 'dirty'), 'provenance was captured before the output existed: ' +
      lTarget.ToJSON);
    Assert.AreEqual(40, Length(JsonText(lTarget, 'head')), lTarget.ToJSON);
  finally
    lSummary.Free;
  end;
end;

procedure TNativeAnalysisUnitTests.Setup;
begin
  EnsureResolverBuilt;
  fExtraArgs := '';
  fRoot := UniqueNoRepoTempPath('native-analysis-unit');
  BuildFixture('units', 'UnitOne');
end;

procedure TNativeAnalysisUnitTests.TearDown;
begin
  DeleteTempPath(fRoot);
end;

procedure TNativeAnalysisUnitTests.BuildFixture(const aUnitDirectory, aUnitName: string);
begin
  fProjectDir := TPath.Combine(fRoot, 'project');
  TDirectory.CreateDirectory(TPath.Combine(fProjectDir, aUnitDirectory));
  fProjectPath := TPath.Combine(fProjectDir, 'Sample.dproj');
  TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'), fProjectPath, True);
  TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dpr'), TPath.Combine(fProjectDir, 'Sample.dpr'), True);
  fUnitPath := TPath.Combine(TPath.Combine(fProjectDir, aUnitDirectory), aUnitName + '.pas');
  TFile.WriteAllText(fUnitPath, 'unit ' + aUnitName + ';' + sLineBreak + 'interface' + sLineBreak +
    'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(fProjectDir, 'dak.ini'),
    '[Workspace]' + sLineBreak +
    'Root=project' + sLineBreak +
    '[AnalysisPolicy]' + sLineBreak +
    'GateOwnership=repository;project' + sLineBreak +
    'ProjectRoots=.' + sLineBreak, TEncoding.ASCII);
  fOutRoot := TPath.Combine(fRoot, '.dak\_unit\' + aUnitName);
  fRunLog := TPath.Combine(fRoot, 'analyze-unit.log');
end;

function TNativeAnalysisUnitTests.RunUnit(const aPalExit: Integer; aWithContext: Boolean;
  out aProcessExit: Cardinal): string;
var
  lArgs: string;
  lScope: IInterface;
begin
  lArgs := 'analyze-unit --unit ' + QuoteArg(fUnitPath) + ' --delphi 23.0 --workspace-root ' + QuoteArg(fRoot) +
    ' --pascal-analyzer true --pa-path ' + QuoteArg(ParamStr(0)) + ' --out ' + QuoteArg(fOutRoot) + fExtraArgs;
  if aWithContext then
    lArgs := lArgs + ' --project-context ' + QuoteArg(fProjectPath) + ' --platform Win64 --config Debug';
  lScope := SetScopedEnvironmentVariable('DAK_TEST_PAL_EXIT', aPalExit.ToString);
  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, fRunLog, aProcessExit), 'Failed to start unit analysis.');
  lScope := nil;
  Result := TFile.ReadAllText(fRunLog);
end;

function TNativeAnalysisUnitTests.ReadSummary: TJSONObject;
var
  lPath: string;
begin
  lPath := TPath.Combine(fOutRoot, 'summary.json');
  Assert.IsTrue(TFile.Exists(lPath), 'Expected a published summary: ' + lPath);
  Result := ParseJsonObject(TFile.ReadAllText(lPath), lPath);
end;

procedure TNativeAnalysisUnitTests.StandaloneUnitFinalizesTheReport;
var
  lExit: Cardinal;
  lLog: string;
  lSummary: TJSONObject;
begin
  lLog := RunUnit(0, False, lExit);
  Assert.AreEqual(Cardinal(0), lExit, 'A passing unit run exits zero. Log: ' + lLog);
  lSummary := ReadSummary;
  try
    Assert.AreEqual('complete', JsonText(JsonObjectMember(lSummary, 'status'), 'finalization'),
      'The unit workflow must finalize the report, not stop at the status seed.');
    Assert.AreEqual(3, StrToIntDef(JsonText(lSummary, 'schema_version'), 0));
  finally
    lSummary.Free;
  end;
end;

procedure TNativeAnalysisUnitTests.ProjectContextUnitFinalizesUnderTheUnitTitle;
var
  lExit: Cardinal;
  lLog: string;
  lSummary: TJSONObject;
begin
  lLog := RunUnit(0, True, lExit);
  Assert.AreEqual(Cardinal(0), lExit, 'A passing unit run exits zero. Log: ' + lLog);
  lSummary := ReadSummary;
  try
    Assert.AreEqual('complete', JsonText(JsonObjectMember(lSummary, 'status'), 'finalization'));
  finally
    lSummary.Free;
  end;
  // run_postprocess(title=unit_path.stem)
  Assert.IsTrue(TFile.ReadAllText(TPath.Combine(fOutRoot, 'triage.md')).StartsWith('# UnitOne'),
    'The report is titled after the unit.');
end;

// A failed Pascal Analyzer run is the unit run's answer; the failure is published, never downgraded.
procedure TNativeAnalysisUnitTests.AnalyzerFailureKeepsItsOwnExitCode;
var
  lExit: Cardinal;
  lSummary: TJSONObject;
begin
  RunUnit(7, True, lExit);
  Assert.AreEqual(Cardinal(7), lExit, 'The analyzer exit code is the run result.');
  lSummary := ReadSummary;
  try
    Assert.AreEqual('failed', JsonText(JsonObjectMember(lSummary, 'status'), 'infrastructure'));
    Assert.AreEqual('failed', lSummary.GetValue<string>('analyzers.pascal_analyzer.status'));
  finally
    lSummary.Free;
  end;
end;

procedure TNativeAnalysisUnitTests.WithoutASummaryTheRunIsARejectedResult;
var
  lExit: Cardinal;
  lLog: string;
begin
  fExtraArgs := ' --write-summary false';
  lLog := RunUnit(0, False, lExit);
  Assert.AreEqual(Cardinal(3), lExit, 'A unit run with no summary is a rejected result.');
  Assert.IsTrue(lLog.Contains('Summary not found: '), lLog);
end;

// DAK's own contract for an analysis subject that does not exist is exit 3 (cExitInvalidProjectInput),
// pinned by Test.Cli for project and unit paths. analyze-unit.py checked the file itself and returned 2
// before starting DAK; that wrapper pre-check is not reproduced. Nothing is published.
procedure TNativeAnalysisUnitTests.MissingUnitIsInvalidProjectInput;
var
  lExit: Cardinal;
begin
  fUnitPath := TPath.Combine(fProjectDir, 'units\Absent.pas');
  RunUnit(0, False, lExit);
  Assert.AreEqual(Cardinal(3), lExit, 'A missing unit is invalid input.');
  Assert.IsFalse(TFile.Exists(TPath.Combine(fOutRoot, 'summary.json')), 'Nothing is published.');
end;

procedure TNativeAnalysisUnitTests.UnicodeAndSpacedPathsFinalize;
var
  lExit: Cardinal;
  lLog: string;
  lSummary: TJSONObject;
begin
  DeleteTempPath(fRoot);
  fRoot := UniqueNoRepoTempPath('native analysis unit ' + #$017C#$00F3#$0142#$0107);
  BuildFixture('units with spaces', 'Zażółć');
  lLog := RunUnit(0, True, lExit);
  Assert.AreEqual(Cardinal(0), lExit, 'Unicode and spaced paths work end to end. Log: ' + lLog);
  lSummary := ReadSummary;
  try
    Assert.AreEqual('complete', JsonText(JsonObjectMember(lSummary, 'status'), 'finalization'));
    Assert.AreEqual(fUnitPath, lSummary.GetValue<string>('subject.path'), 'The subject keeps its exact path.');
  finally
    lSummary.Free;
  end;
  Assert.IsTrue(TFile.ReadAllText(TPath.Combine(fOutRoot, 'triage.md'), TEncoding.UTF8).StartsWith('# Zażółć'),
    'The title keeps the unit name.');
end;

// With a project context the workspace is resolved for the project, not for the unit's folder.
procedure TNativeAnalysisUnitTests.ProjectSelectorResolvesTheContextWorkspace;
var
  lArgs: string;
  lExit: Cardinal;
  lScope: IInterface;
  lSummary: TJSONObject;
begin
  lArgs := 'analyze-unit --unit ' + QuoteArg(fUnitPath) + ' --project-context ' + QuoteArg(fProjectPath) +
    ' --delphi 23.0 --workspace-root project --pascal-analyzer true --pa-path ' + QuoteArg(ParamStr(0)) +
    ' --out ' + QuoteArg(fOutRoot);
  lScope := SetScopedEnvironmentVariable('DAK_TEST_PAL_EXIT', '0');
  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, fRunLog, lExit), 'Failed to start unit analysis.');
  lScope := nil;
  Assert.AreEqual(Cardinal(0), lExit, TFile.ReadAllText(fRunLog));
  lSummary := ReadSummary;
  try
    Assert.AreEqual('project', lSummary.GetValue<string>('workspace.selector'));
    Assert.AreEqual(fProjectDir, lSummary.GetValue<string>('workspace.root'),
      'The project selector resolves to the context project''s folder.');
    Assert.AreEqual(0, lSummary.GetValue<Integer>('counts.raw.ownership.unknown'));
  finally
    lSummary.Free;
  end;
end;

// analyze-unit.py started DAK with cwd=workspace.root. The recorded analysis_cwd is part of the run
// context a baseline keeps, so it must not depend on the directory the command was typed in. The
// fixture runs DAK from the repository root, not from the workspace.
procedure TNativeAnalysisUnitTests.AnalyzersRunInTheWorkspaceRootWhateverTheCallerDirectory;
var
  lBaseline: TJSONObject;
  lExit: Cardinal;
  lLog: string;
  lSummary: TJSONObject;
  lWorkspaceRoot: string;
begin
  // Standalone: the project selector resolves to the unit's own folder, which is not the caller's.
  fExtraArgs := '';
  lLog := RunUnit(0, False, lExit);
  Assert.AreEqual(Cardinal(0), lExit, lLog);
  lSummary := ReadSummary;
  try
    lWorkspaceRoot := lSummary.GetValue<string>('workspace.root');
  finally
    lSummary.Free;
  end;
  Assert.AreNotEqual(TPath.GetFullPath(RepoRoot), lWorkspaceRoot, 'The fixture must run from outside the workspace.');
  lBaseline := ParseJsonObject(TFile.ReadAllText(TPath.Combine(fOutRoot, 'baseline.json')), 'baseline.json');
  try
    Assert.AreEqual(ExcludeTrailingPathDelimiter(lWorkspaceRoot),
      ExcludeTrailingPathDelimiter(lBaseline.GetValue<string>('run_context.host.analysis_cwd')),
      'The analyzers run in the workspace root.');
  finally
    lBaseline.Free;
  end;
end;

// T-343 contract through [PascalAnalyzer].Output: only the raw Pascal Analyzer XML reports move; the
// normalized rows stay in the report's pascal-analyzer folder so the unit report finalizes.
procedure TNativeAnalysisUnitTests.RelocatedPalOutputFromDakIniKeepsNormalizedFindingsInTheReport;
var
  lExit: Cardinal;
  lLog: string;
  lPalDir: string;
  lRelocated: string;
  lSummary: TJSONObject;
begin
  lRelocated := TPath.Combine(fRoot, 'pa-relocated');
  lPalDir := TPath.Combine(fOutRoot, 'pascal-analyzer');
  TFile.AppendAllText(TPath.Combine(fProjectDir, 'dak.ini'),
    '[PascalAnalyzer]' + sLineBreak + 'Output=' + lRelocated + sLineBreak, TEncoding.ASCII);
  lLog := RunUnit(0, True, lExit);
  Assert.AreEqual(Cardinal(0), lExit, 'A relocated PAL output still finalizes the report. Log: ' + lLog);
  Assert.IsTrue(Length(TDirectory.GetFiles(lRelocated, 'Status.xml', TSearchOption.soAllDirectories)) > 0,
    'The raw PAL reports go to the relocated root.');
  Assert.IsTrue(TFile.Exists(TPath.Combine(lPalDir, 'pal-findings.jsonl')), 'normalized rows in the report');
  Assert.IsTrue(TFile.Exists(TPath.Combine(lPalDir, 'pal-findings.md')), 'findings summary in the report');
  Assert.IsFalse(TFile.Exists(TPath.Combine(lRelocated, 'pal-findings.jsonl')),
    'Nothing normalized is left beside the raw reports.');
  lSummary := ReadSummary;
  try
    Assert.AreEqual('complete', JsonText(JsonObjectMember(lSummary, 'status'), 'finalization'));
  finally
    lSummary.Free;
  end;
end;

end.
