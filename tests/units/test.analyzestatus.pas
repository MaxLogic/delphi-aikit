unit Test.AnalyzeStatus;

interface

uses
  System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  Test.Support;

type
  [TestFixture]
  TAnalyzeStatusTests = class
  private
    function RunFixInsightFixture(const aExitCode: Integer; out aProcessExit: Cardinal): TJSONObject;
    function RunPalUnitFixture(const aExitCode: Integer; out aProcessExit: Cardinal): TJSONObject;
    function RunContextFreeUnitFixture(out aProcessExit: Cardinal): TJSONObject;
  public
    [Test]
    procedure SuccessfulAnalyzerWritesCompleteSchema2Seed;
    [Test]
    procedure FailedAnalyzerWritesPartialSchema2Seed;
    [Test]
    procedure SuccessfulProjectContextUnitWritesCompleteSchema2Seed;
    [Test]
    procedure FailedProjectContextUnitWritesUnavailableSchema2Seed;
    [Test]
    procedure ContextFreeUnitUsesContainingDirectoryWorkspace;
    [Test]
    procedure InvalidWorkspaceRootFailsBeforeAnalyzers;
  end;

implementation

function TAnalyzeStatusTests.RunFixInsightFixture(const aExitCode: Integer;
  out aProcessExit: Cardinal): TJSONObject;
var
  lArgs: string;
  lFixtureRoot: string;
  lOldExit: string;
  lOutRoot: string;
  lProjectDir: string;
  lProjectPath: string;
  lRunLog: string;
  lSummaryPath: string;
begin
  EnsureResolverBuilt;
  lFixtureRoot := UniqueNoRepoTempPath('analyze-status');
  lProjectDir := TPath.Combine(lFixtureRoot, 'project');
  TDirectory.CreateDirectory(lProjectDir);
  try
    lProjectPath := TPath.Combine(lProjectDir, 'Sample.dproj');
    TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'), lProjectPath);
    TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dpr'), TPath.Combine(lProjectDir, 'Sample.dpr'));
    TFile.WriteAllText(TPath.Combine(lProjectDir, 'dak.ini'),
      '[Workspace]' + sLineBreak +
      'Root=project' + sLineBreak +
      '[FixInsightCL]' + sLineBreak +
      'Path=' + ParamStr(0) + sLineBreak +
      '[FixInsightIgnore]' + sLineBreak +
      'Warnings=W501' + sLineBreak +
      '[PascalAnalyzerIgnore]' + sLineBreak +
      'Rules=WARN54' + sLineBreak +
      '[AnalysisPolicy]' + sLineBreak +
      'GateOwnership=repository;project' + sLineBreak +
      'GateMetrics=PAL.warnings.method-length-621eae6dfec836e8' + sLineBreak +
      'ProjectRoots=.' + sLineBreak, TEncoding.ASCII);
    lOutRoot := TPath.Combine(lFixtureRoot, '.dak\Sample');
    lRunLog := TPath.Combine(lFixtureRoot, 'analyze.log');
    lArgs := 'analyze --project ' + QuoteArg(lProjectPath) +
      ' --platform Win64 --config Debug --delphi 23.0 --workspace-root ' + QuoteArg(lFixtureRoot) +
      ' --fixinsight true --pascal-analyzer false --fi-formats txt --out ' + QuoteArg(lOutRoot);

    lOldExit := GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT');
    SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT', PChar(aExitCode.ToString));
    try
      Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, aProcessExit),
        'Failed to start analyzer process.');
    finally
      if lOldExit = '' then
        SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT', nil)
      else
        SetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT', PChar(lOldExit));
    end;

    lSummaryPath := TPath.Combine(lOutRoot, 'summary.json');
    Assert.IsTrue(TFile.Exists(lSummaryPath), 'Expected schema-2 status seed: ' + lSummaryPath);
    Result := ParseJsonObject(TFile.ReadAllText(lSummaryPath), lSummaryPath);
  finally
    DeleteTempPath(lFixtureRoot);
  end;
end;

function TAnalyzeStatusTests.RunContextFreeUnitFixture(out aProcessExit: Cardinal): TJSONObject;
var
  lArgs: string;
  lFixtureRoot: string;
  lOutRoot: string;
  lRunLog: string;
  lSummaryPath: string;
  lUnitPath: string;
begin
  EnsureResolverBuilt;
  lFixtureRoot := UniqueNoRepoTempPath('analyze-unit-no-context');
  TDirectory.CreateDirectory(lFixtureRoot);
  try
    lUnitPath := TPath.Combine(lFixtureRoot, 'UnitOne.pas');
    TFile.WriteAllText(lUnitPath, 'unit UnitOne;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    lOutRoot := TPath.Combine(lFixtureRoot, '.dak\UnitOne');
    lRunLog := TPath.Combine(lFixtureRoot, 'analyze-unit.log');
    lArgs := 'analyze-unit --unit ' + QuoteArg(lUnitPath) +
      ' --platform Win64 --config Debug --delphi 23.0 --pascal-analyzer false --out ' + QuoteArg(lOutRoot);

    Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, aProcessExit),
      'Failed to start context-free unit analysis.');
    lSummaryPath := TPath.Combine(lOutRoot, 'summary.json');
    Assert.IsTrue(TFile.Exists(lSummaryPath), 'Expected unit schema-2 status seed: ' + lSummaryPath);
    Result := ParseJsonObject(TFile.ReadAllText(lSummaryPath), lSummaryPath);
  finally
    DeleteTempPath(lFixtureRoot);
  end;
end;

function TAnalyzeStatusTests.RunPalUnitFixture(const aExitCode: Integer;
  out aProcessExit: Cardinal): TJSONObject;
var
  lArgs: string;
  lFixtureRoot: string;
  lOldExit: string;
  lOldOrigin: string;
  lOldPalRules: string;
  lOutRoot: string;
  lProjectDir: string;
  lProjectInputPath: string;
  lProjectPath: string;
  lRunLog: string;
  lSummaryPath: string;
  lUnitDir: string;
  lUnitPath: string;
begin
  EnsureResolverBuilt;
  lFixtureRoot := UniqueNoRepoTempPath('analyze-unit-status');
  lProjectDir := TPath.Combine(lFixtureRoot, 'project');
  lUnitDir := TPath.Combine(lProjectDir, 'units');
  TDirectory.CreateDirectory(lUnitDir);
  try
    lProjectPath := TPath.Combine(lProjectDir, 'Sample.dproj');
    TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'), lProjectPath);
    lProjectInputPath := TPath.Combine(lProjectDir, 'Sample.dpr');
    TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dpr'), lProjectInputPath);
    lUnitPath := TPath.Combine(lUnitDir, 'UnitOne.pas');
    TFile.WriteAllText(lUnitPath, 'unit UnitOne;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);
    lOutRoot := TPath.Combine(lFixtureRoot, '.dak\UnitOne');
    lRunLog := TPath.Combine(lFixtureRoot, 'analyze-unit.log');
    lArgs := 'analyze-unit --unit ' + QuoteArg(lUnitPath) + ' --project-context ' + QuoteArg(lProjectInputPath) +
      ' --workspace-root project --platform Win64 --config Debug --delphi 23.0 --pa-path ' + QuoteArg(ParamStr(0)) +
      ' --pa-exclude-search-folders ' + QuoteArg(lProjectDir + '\Vendor<+>') +
      ' --pa-exclude-files System.pas;Vendor.pas --pal-ignore-rules STWA6' +
      ' --exclude-path-masks *Vendor.pas --pascal-analyzer true --out ' + QuoteArg(lOutRoot);

    lOldExit := GetEnvironmentVariable('DAK_TEST_PAL_EXIT');
    lOldOrigin := GetEnvironmentVariable('DAK_PAL_IGNORE_RULES_ORIGIN');
    lOldPalRules := GetEnvironmentVariable('DAK_PAL_IGNORE_RULES');
    SetEnvironmentVariable('DAK_TEST_PAL_EXIT', PChar(aExitCode.ToString));
    SetEnvironmentVariable('DAK_PAL_IGNORE_RULES', PChar('STWA6'));
    SetEnvironmentVariable('DAK_PAL_IGNORE_RULES_ORIGIN',
      PChar('environment:DAK_PAL_IGNORE_RULES'));
    try
      Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lRunLog, aProcessExit),
        'Failed to start unit analyzer process.');
    finally
      if lOldExit = '' then
        SetEnvironmentVariable('DAK_TEST_PAL_EXIT', nil)
      else
        SetEnvironmentVariable('DAK_TEST_PAL_EXIT', PChar(lOldExit));
      if lOldPalRules = '' then
        SetEnvironmentVariable('DAK_PAL_IGNORE_RULES', nil)
      else
        SetEnvironmentVariable('DAK_PAL_IGNORE_RULES', PChar(lOldPalRules));
      if lOldOrigin = '' then
        SetEnvironmentVariable('DAK_PAL_IGNORE_RULES_ORIGIN', nil)
      else
        SetEnvironmentVariable('DAK_PAL_IGNORE_RULES_ORIGIN', PChar(lOldOrigin));
    end;

    lSummaryPath := TPath.Combine(lOutRoot, 'summary.json');
    Assert.IsTrue(TFile.Exists(lSummaryPath), 'Expected unit schema-2 status seed: ' + lSummaryPath);
    Result := ParseJsonObject(TFile.ReadAllText(lSummaryPath), lSummaryPath);
  finally
    DeleteTempPath(lFixtureRoot);
  end;
end;

procedure TAnalyzeStatusTests.SuccessfulAnalyzerWritesCompleteSchema2Seed;
var
  lAnalyzer: TJSONObject;
  lConfigFound: Boolean;
  lConfigManifests: TJSONArray;
  lJson: TJSONObject;
  lPalRuleOrigins: TJSONArray;
  lPolicySources: TJSONArray;
  lProcessExit: Cardinal;
  lSourcePath: string;
  i: Integer;
begin
  lJson := RunFixInsightFixture(0, lProcessExit);
  try
    Assert.AreEqual(Cardinal(0), lProcessExit, lJson.ToJSON);
    Assert.AreEqual(2, lJson.GetValue<Integer>('schema_version'));
    Assert.AreEqual('complete', lJson.GetValue<string>('status.infrastructure'));
    Assert.AreEqual('not_evaluated', lJson.GetValue<string>('status.policy'));
    Assert.AreEqual('.dpr', LowerCase(TPath.GetExtension(lJson.GetValue<string>('subject.path'))));
    Assert.AreEqual('.dproj', LowerCase(TPath.GetExtension(lJson.GetValue<string>('subject.project_file'))));
    Assert.IsNotNull(lJson.GetValue('workspace'), 'Expected resolved workspace seed data.');
    Assert.AreEqual(TPath.GetDirectoryName(TPath.GetDirectoryName(
      lJson.GetValue<string>('subject.project_file'))), lJson.GetValue<string>('workspace.root'));
    Assert.AreEqual(lJson.GetValue<string>('workspace.root'), lJson.GetValue<string>('workspace.selector'));
    Assert.AreEqual('none', lJson.GetValue<string>('workspace.vcs'));
    Assert.AreEqual('command_line', lJson.GetValue<string>('workspace.source'));
    lAnalyzer := lJson.GetValue<TJSONObject>('analyzers.fixinsight');
    Assert.IsTrue(lAnalyzer.GetValue<Boolean>('requested'));
    Assert.AreEqual('complete', lAnalyzer.GetValue<string>('status'));
    Assert.AreEqual('complete', lAnalyzer.GetValue<string>('count_quality'));
    Assert.IsNotEmpty(lAnalyzer.GetValue<string>('executable'));
    Assert.AreEqual(64, Length(lAnalyzer.GetValue<string>('options.sha256')));
    Assert.IsTrue(lAnalyzer.GetValue<Int64>('runs[0].duration_ms') >= 0);
    Assert.AreEqual('complete', lAnalyzer.GetValue<string>('runs[0].parse_status'));
    Assert.AreEqual('fixinsight/fixinsight.txt',
      lAnalyzer.GetValue<string>('runs[0].artifacts.report'));
    Assert.AreEqual(2, lJson.GetValue<Integer>('counts.fixinsight.total'));
    Assert.AreEqual(64, Length(lJson.GetValue<string>('compiler.search_path_sha256')));
    Assert.AreEqual(64, Length(lJson.GetValue<string>('inputs.project_sha256')));
    Assert.AreEqual(64, Length(lJson.GetValue<string>('inputs.main_source_sha256')));
    Assert.IsNotNull(lJson.GetValue<TJSONObject>('policy.values'),
      'The schema-2 seed must carry the resolved AnalysisPolicy values.');
    Assert.AreEqual('project', lJson.GetValue<string>('policy.values.gate_ownership[0]'));
    Assert.AreEqual('repository', lJson.GetValue<string>('policy.values.gate_ownership[1]'));
    Assert.AreEqual('PAL.warnings.method-length-621eae6dfec836e8',
      lJson.GetValue<string>('policy.values.gate_metrics[0]'));
    Assert.AreEqual('W501', lJson.GetValue<string>('policy.values.fixinsight_ignore[0]'));
    Assert.AreEqual('WARN54', lJson.GetValue<string>('policy.values.pal_ignore_rules[0]'));
    Assert.AreEqual(TPath.GetFullPath(TPath.GetDirectoryName(
      lJson.GetValue<string>('subject.project_file'))),
      lJson.GetValue<string>('policy.values.project_roots[0]'));
    Assert.AreEqual(64, Length(lJson.GetValue<string>('policy.sha256')));
    lPolicySources := lJson.GetValue<TJSONArray>('policy.sources');
    Assert.AreEqual(1, lPolicySources.Count);
    lSourcePath := TPath.Combine(TPath.GetDirectoryName(
      lJson.GetValue<string>('subject.project_file')), 'dak.ini');
    Assert.AreEqual(lSourcePath, lPolicySources.Items[0].Value);
    lPalRuleOrigins := lJson.GetValue<TJSONArray>('policy.origins.pal_ignore_rules');
    Assert.AreEqual(1, lPalRuleOrigins.Count);
    Assert.AreEqual(lSourcePath, lPalRuleOrigins.Items[0].Value);
    lConfigManifests := lJson.GetValue<TJSONArray>('inputs.config_manifests');
    lConfigFound := False;
    for i := 0 to lConfigManifests.Count - 1 do
      if SameText(lSourcePath, lConfigManifests.Items[i].GetValue<string>('path')) then
      begin
        Assert.AreEqual(64, Length(lConfigManifests.Items[i].GetValue<string>('sha256')));
        lConfigFound := True;
        Break;
      end;
    Assert.IsTrue(lConfigFound, 'Expected the policy-contributing dak.ini in config_manifests.');
  finally
    lJson.Free;
  end;
end;

procedure TAnalyzeStatusTests.FailedAnalyzerWritesPartialSchema2Seed;
var
  lAnalyzer: TJSONObject;
  lJson: TJSONObject;
  lProcessExit: Cardinal;
begin
  lJson := RunFixInsightFixture(7, lProcessExit);
  try
    Assert.AreEqual(Cardinal(7), lProcessExit, lJson.ToJSON);
    Assert.AreEqual(2, lJson.GetValue<Integer>('schema_version'));
    Assert.IsNotNull(lJson.GetValue('workspace'), 'Failed analysis must retain resolved workspace seed data.');
    Assert.AreEqual('failed', lJson.GetValue<string>('status.infrastructure'));
    Assert.AreEqual('not_evaluated', lJson.GetValue<string>('status.policy'));
    lAnalyzer := lJson.GetValue<TJSONObject>('analyzers.fixinsight');
    Assert.AreEqual('failed', lAnalyzer.GetValue<string>('status'));
    Assert.AreEqual('partial', lAnalyzer.GetValue<string>('count_quality'));
    Assert.AreEqual(7, lAnalyzer.GetValue<Integer>('runs[0].exit_code'));
    Assert.AreEqual(2, lJson.GetValue<Integer>('counts.fixinsight.total'));
  finally
    lJson.Free;
  end;
end;

procedure TAnalyzeStatusTests.SuccessfulProjectContextUnitWritesCompleteSchema2Seed;
var
  lAnalyzer: TJSONObject;
  lJson: TJSONObject;
  lPalRuleOrigins: TJSONArray;
  lProcessExit: Cardinal;
begin
  lJson := RunPalUnitFixture(0, lProcessExit);
  try
    Assert.AreEqual(Cardinal(0), lProcessExit, lJson.ToJSON);
    Assert.AreEqual(2, lJson.GetValue<Integer>('schema_version'));
    Assert.IsNotNull(lJson.GetValue('workspace'), 'Expected project-context unit workspace data.');
    Assert.AreEqual(TPath.GetDirectoryName(lJson.GetValue<string>('subject.project_context')),
      lJson.GetValue<string>('workspace.root'));
    Assert.AreEqual('project', lJson.GetValue<string>('workspace.selector'));
    Assert.AreEqual('none', lJson.GetValue<string>('workspace.vcs'));
    Assert.AreEqual('command_line', lJson.GetValue<string>('workspace.source'));
    Assert.AreEqual('complete', lJson.GetValue<string>('status.infrastructure'));
    lAnalyzer := lJson.GetValue<TJSONObject>('analyzers.pascal_analyzer');
    Assert.AreEqual('complete', lAnalyzer.GetValue<string>('status'));
    Assert.AreEqual('complete', lAnalyzer.GetValue<string>('count_quality'));
    Assert.AreEqual('9.21.3', lAnalyzer.GetValue<string>('version'));
    Assert.AreEqual(64, Length(lAnalyzer.GetValue<string>('options.sha256')));
    Assert.AreEqual(TPath.GetDirectoryName(
      lJson.GetValue<string>('subject.project_context')) + '\Vendor<+>',
      lAnalyzer.GetValue<string>('options.exclude_search_folders'));
    Assert.AreEqual('System.pas;Vendor.pas',
      lAnalyzer.GetValue<string>('options.exclude_files'));
    Assert.AreEqual('STWA6',
      lJson.GetValue<string>('policy.values.pal_ignore_rules[0]'));
    lPalRuleOrigins := lJson.GetValue<TJSONArray>('policy.origins.pal_ignore_rules');
    Assert.AreEqual(2, lPalRuleOrigins.Count);
    Assert.AreEqual('command_line', lPalRuleOrigins.Items[0].Value);
    Assert.AreEqual('environment:DAK_PAL_IGNORE_RULES', lPalRuleOrigins.Items[1].Value);
    Assert.AreEqual('*Vendor.pas',
      lJson.GetValue<string>('policy.values.exclude_path_masks[0]'));
    Assert.AreEqual(64, Length(lJson.GetValue<string>('policy.reporting_sha256')));
    Assert.AreEqual('.dproj', LowerCase(TPath.GetExtension(
      lJson.GetValue<string>('subject.project_context'))));
    Assert.AreEqual(64, Length(lJson.GetValue<string>('inputs.project_sha256')));
    Assert.IsNotNull(lJson.GetValue<TJSONObject>('policy.values'),
      'Project-context unit analysis must seed the same resolved policy contract.');
    Assert.AreEqual('project', lJson.GetValue<string>('policy.values.gate_ownership[0]'));
    Assert.AreEqual('repository', lJson.GetValue<string>('policy.values.gate_ownership[1]'));
    Assert.AreEqual(64, Length(lJson.GetValue<string>('policy.sha256')));
  finally
    lJson.Free;
  end;
end;

procedure TAnalyzeStatusTests.FailedProjectContextUnitWritesUnavailableSchema2Seed;
var
  lAnalyzer: TJSONObject;
  lJson: TJSONObject;
  lProcessExit: Cardinal;
begin
  lJson := RunPalUnitFixture(7, lProcessExit);
  try
    Assert.AreEqual(Cardinal(7), lProcessExit, lJson.ToJSON);
    Assert.AreEqual(2, lJson.GetValue<Integer>('schema_version'));
    Assert.IsNotNull(lJson.GetValue('workspace'), 'Failed unit analysis must retain workspace data.');
    Assert.AreEqual('failed', lJson.GetValue<string>('status.infrastructure'));
    lAnalyzer := lJson.GetValue<TJSONObject>('analyzers.pascal_analyzer');
    Assert.AreEqual('failed', lAnalyzer.GetValue<string>('status'));
    Assert.AreEqual('unavailable', lAnalyzer.GetValue<string>('count_quality'));
    Assert.AreEqual(64, Length(lAnalyzer.GetValue<string>('options.sha256')));
    Assert.IsNull(lJson.GetValue('counts.pascal_analyzer.total'));
  finally
    lJson.Free;
  end;
end;

procedure TAnalyzeStatusTests.ContextFreeUnitUsesContainingDirectoryWorkspace;
var
  lJson: TJSONObject;
  lProcessExit: Cardinal;
begin
  lJson := RunContextFreeUnitFixture(lProcessExit);
  try
    Assert.AreEqual(Cardinal(0), lProcessExit, lJson.ToJSON);
    Assert.AreEqual(2, lJson.GetValue<Integer>('schema_version'));
    Assert.AreEqual(TPath.GetDirectoryName(lJson.GetValue<string>('subject.path')),
      lJson.GetValue<string>('workspace.root'));
    Assert.AreEqual('auto', lJson.GetValue<string>('workspace.selector'));
    Assert.AreEqual('none', lJson.GetValue<string>('workspace.vcs'));
    Assert.AreEqual('default', lJson.GetValue<string>('workspace.source'));
  finally
    lJson.Free;
  end;
end;

procedure TAnalyzeStatusTests.InvalidWorkspaceRootFailsBeforeAnalyzers;
var
  lArgs: string;
  lExitCode: Cardinal;
  lFixtureRoot: string;
  lLogPath: string;
  lMissingRoot: string;
  lOutRoot: string;
  lProjectPath: string;
  lUnitPath: string;
begin
  EnsureResolverBuilt;
  lFixtureRoot := UniqueNoRepoTempPath('analyze-invalid-workspace');
  TDirectory.CreateDirectory(lFixtureRoot);
  try
    lMissingRoot := TPath.Combine(lFixtureRoot, 'missing');
    lProjectPath := TPath.Combine(lFixtureRoot, 'Sample.dproj');
    TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'), lProjectPath);
    TFile.Copy(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dpr'), TPath.Combine(lFixtureRoot, 'Sample.dpr'));
    lUnitPath := TPath.Combine(lFixtureRoot, 'UnitOne.pas');
    TFile.WriteAllText(lUnitPath, 'unit UnitOne;' + sLineBreak + 'interface' + sLineBreak +
      'implementation' + sLineBreak + 'end.' + sLineBreak, TEncoding.ASCII);

    lOutRoot := TPath.Combine(lFixtureRoot, 'project-out');
    lLogPath := TPath.Combine(lFixtureRoot, 'project.log');
    lArgs := 'analyze --project ' + QuoteArg(lProjectPath) + ' --delphi 23.0 --workspace-root ' +
      QuoteArg(lMissingRoot) + ' --fixinsight true --pascal-analyzer false --out ' + QuoteArg(lOutRoot);
    Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lLogPath, lExitCode));
    Assert.AreEqual(Cardinal(6), lExitCode, TFile.ReadAllText(lLogPath));
    Assert.IsTrue(TFile.ReadAllText(lLogPath).Contains('does not exist'), TFile.ReadAllText(lLogPath));
    Assert.IsFalse(TDirectory.Exists(lOutRoot), 'Project output must not be prepared after workspace validation fails.');

    lOutRoot := TPath.Combine(lFixtureRoot, 'unit-out');
    lLogPath := TPath.Combine(lFixtureRoot, 'unit.log');
    lArgs := 'analyze-unit --unit ' + QuoteArg(lUnitPath) + ' --delphi 23.0 --workspace-root ' +
      QuoteArg(lMissingRoot) + ' --pascal-analyzer true --pa-path ' + QuoteArg(ParamStr(0)) +
      ' --out ' + QuoteArg(lOutRoot);
    Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lLogPath, lExitCode));
    Assert.AreEqual(Cardinal(6), lExitCode, TFile.ReadAllText(lLogPath));
    Assert.IsTrue(TFile.ReadAllText(lLogPath).Contains('does not exist'), TFile.ReadAllText(lLogPath));
    Assert.IsFalse(TDirectory.Exists(lOutRoot), 'Unit output must not be prepared after workspace validation fails.');
  finally
    DeleteTempPath(lFixtureRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAnalyzeStatusTests);

end.
