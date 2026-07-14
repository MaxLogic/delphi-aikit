unit Test.Refactor;

interface

uses
  System.IOUtils,
  System.JSON,
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
    function CreateFixtureProjectPath(const aRoot: string): string;
    procedure CreateBuildFailureFixtureProject(const aRoot: string; out aDprojPath,
      aUnitOnePath, aUnitTwoPath: string);
  public
    [Test]
    procedure FindUsagesCommandReportsProjectScopedReferencesAsJson;
    [Test]
    procedure RenameCommandDefaultsToDryRun;
    [Test]
    procedure RenameCommandAppliesEditsAndCreatesBackups;
    [Test]
    procedure RenameCommandRollsBackWhenBuildVerificationFails;
    [Test]
    procedure RenameCommandAcceptsSourcePositionTarget;
    [Test]
    procedure RenameCommandReportsSemanticPhaseMetricsAsJson;
    [Test]
    procedure ScopedIdentifierAdapterMatchesForcedFullRename;
    [Test]
    procedure RenameGuardValidationRejectsStaleSource;
    [Test]
    procedure RenameGuardValidationUsesApplyPathMatching;
    [Test]
    procedure RenameApplyRequiresStaleEditGuardsBeforeMutation;
    [Test]
    procedure RenameSemanticCacheUsesToolchainIdentity;
    [Test]
    procedure RenameDefaultsToProjectLocalSemanticCache;
    [Test]
    procedure RenameSemanticCacheOptOutAndImplicitFallback;
    [Test]
    procedure RefactorCommandsUseDelphiSemanticsProjectSession;
    [Test]
    procedure SemanticsSessionAdapterMapsOptionsAndDiagnostics;
    [Test]
    procedure SemanticSnapshotContextRejectsFailedProjectUnit;
    [Test]
    procedure SemanticsSessionAdapterIsCentralized;
    [Test]
    procedure RefactorJsonOutputUsesStructuredBuilders;
    [Test]
    procedure ProjectDakRootPolicyIsCentralized;
    [Test]
    procedure ProprietaryRenameDogfoodHasMaxTdbProofCategory;
    [Test]
    procedure DefaultRunnerExcludesMaxTdbProofOnlyWithoutExplicitFilters;
  end;

implementation

uses
  System.Hash,
  DelphiSemantics.Refactor,
  DelphiSemantics.ProjectContext,
  Dak.Refactor.RenameGuards,
  Dak.Semantics.Session, Dak.SourceText;

type
  TIdentifierAdapterPlanResult = record
    Metrics: TDakSemanticSymbolQueryMetrics;
    Plan: TDelphiSemanticRenamePlan;
  end;

function BuildIdentifierAdapterPlan(const aOptions: TDelphiSemanticOptions):
  TIdentifierAdapterPlanResult;
var
  lContext: IDakSemanticSymbolQueryContext;
  lError: string;
begin
  Assert.IsTrue(OpenSemanticSymbolQueryContextForIdentifier(aOptions,
    'SharedValue', lContext, Result.Metrics, lError, True), lError);
  Result.Plan := lContext.PlanRename('SharedValue', 'RenamedValue');
end;

procedure AssertRenamePlansEqual(const aExpected,
  aActual: TDelphiSemanticRenamePlan);
var
  i: Integer;
begin
  Assert.AreEqual(aExpected.Status, aActual.Status);
  Assert.AreEqual(aExpected.Diagnostic, aActual.Diagnostic);
  Assert.AreEqual(aExpected.ContextFingerprint, aActual.ContextFingerprint);
  Assert.AreEqual(Integer(Length(aExpected.Edits)),
    Integer(Length(aActual.Edits)));
  for i := 0 to High(aExpected.Edits) do
  begin
    Assert.AreEqual(aExpected.Edits[i].FileName, aActual.Edits[i].FileName);
    Assert.AreEqual(aExpected.Edits[i].Role, aActual.Edits[i].Role);
    Assert.AreEqual(aExpected.Edits[i].ExpectedFileHash,
      aActual.Edits[i].ExpectedFileHash);
    Assert.AreEqual(aExpected.Edits[i].ExpectedSourceText,
      aActual.Edits[i].ExpectedSourceText);
    Assert.AreEqual(aExpected.Edits[i].StartLine, aActual.Edits[i].StartLine);
    Assert.AreEqual(aExpected.Edits[i].StartColumn,
      aActual.Edits[i].StartColumn);
    Assert.AreEqual(aExpected.Edits[i].EndLine, aActual.Edits[i].EndLine);
    Assert.AreEqual(aExpected.Edits[i].EndColumn, aActual.Edits[i].EndColumn);
    Assert.AreEqual(aExpected.Edits[i].NewText, aActual.Edits[i].NewText);
  end;
end;

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
    '    <ProjectGuid>{F01F1010-6CB0-41EE-B12E-9563EB1E5155}</ProjectGuid>' + sLineBreak +
    '    <MainSource>RefactorFixture.dpr</MainSource>' + sLineBreak +
    '    <Base>True</Base>' + sLineBreak +
    '    <Config Condition="''$(Config)''==''''">Release</Config>' + sLineBreak +
    '    <ProjectName Condition="''$(ProjectName)''==''''">RefactorFixture</ProjectName>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '    <AppType>Console</AppType>' + sLineBreak +
    '    <FrameworkType>None</FrameworkType>' + sLineBreak +
    '    <ProjectVersion>20.2</ProjectVersion>' + sLineBreak +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>' + sLineBreak +
    '    <DCC_DcuOutput>$(DCC_ExeOutput)</DCC_DcuOutput>' + sLineBreak +
    '    <DCC_UnitSearchPath>.;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + sLineBreak +
    '    <DCC_Namespace>System;System.Win;$(DCC_Namespace)</DCC_Namespace>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <DelphiCompile Include="$(MainSource)">' + sLineBreak +
    '      <MainSource>MainSource</MainSource>' + sLineBreak +
    '    </DelphiCompile>' + sLineBreak +
    '    <DCCReference Include="UnitOne.pas"/>' + sLineBreak +
    '    <DCCReference Include="UnitTwo.pas"/>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '  <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')"/>' + sLineBreak +
    '</Project>' + sLineBreak,
    TEncoding.UTF8);
end;

procedure TRefactorCommandTests.CreateBuildFailureFixtureProject(const aRoot: string;
  out aDprojPath, aUnitOnePath, aUnitTwoPath: string);
var
  lDprojText: string;
begin
  CreateFixtureProject(aRoot, aDprojPath, aUnitOnePath, aUnitTwoPath);
  lDprojText := TFile.ReadAllText(aDprojPath, TEncoding.UTF8);
  lDprojText := StringReplace(lDprojText, '</Project>',
    '  <Target Name="FailAfterRenameRewrite" BeforeTargets="_PasCoreCompile">' + sLineBreak +
    '    <Exec Command="findstr /C:&quot;RenamedValue := 2&quot; UnitTwo.pas &gt;nul" IgnoreExitCode="true">' + sLineBreak +
    '      <Output TaskParameter="ExitCode" PropertyName="RenameVerificationExitCode"/>' + sLineBreak +
    '    </Exec>' + sLineBreak +
    '    <Error Condition="''$(RenameVerificationExitCode)''==''0''" Text="Intentional rename verification failure after rename rewrites UnitTwo.pas."/>' + sLineBreak +
    '  </Target>' + sLineBreak +
    '</Project>', []);
  TFile.WriteAllText(aDprojPath, lDprojText, TEncoding.UTF8);
end;

procedure TRefactorCommandTests.FindUsagesCommandReportsProjectScopedReferencesAsJson;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lHasUnitTwoUsage: Boolean;
  lJson: TJSONObject;
  lLogPath: string;
  lLogText: string;
  lPhaseMetrics: TJSONObject;
  lRoot: string;
  lUnitOnePath: string;
  lUnitTwoPath: string;
  lUsage: TJSONObject;
  lUsages: TJSONArray;
  i: Integer;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-find-usages');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'refactor-find-usages.log');

  Assert.IsTrue(RunResolverProcess(
    'find-usages --project ' + QuoteArg(lDprojPath) + ' --symbol SharedValue --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start find-usages command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected find-usages to succeed. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  lJson := ParseJsonObject(lLogText, lLogPath);
  try
    Assert.AreEqual('resolved', lJson.GetValue<string>('status', ''),
      'Expected resolved JSON status. See: ' + lLogPath);
    Assert.AreEqual('SharedValue', lJson.GetValue<string>('symbol', ''),
      'Expected queried symbol in JSON. See: ' + lLogPath);
    Assert.IsNotNull(lJson.Values['referenceReconciliationFallbackCount'],
      'Expected reference reconciliation fallback metric in JSON. See: ' + lLogPath);
    Assert.IsTrue(lJson.Values['semanticPhaseMetrics'] is TJSONObject,
      'Expected semantic phase metrics in JSON. See: ' + lLogPath);
    lPhaseMetrics := lJson.Values['semanticPhaseMetrics'] as TJSONObject;
    Assert.AreEqual(2, lPhaseMetrics.GetValue<Integer>(
      'identifierFullModelCount', -1));
    Assert.AreEqual(1, lPhaseMetrics.GetValue<Integer>(
      'identifierLeanModelCount', -1));
    Assert.IsFalse(lPhaseMetrics.GetValue<Boolean>('identifierScopeFailOpen',
      True));
    Assert.AreEqual(3, lJson.GetValue<Integer>('count', -1),
      'Expected declaration plus two references. See: ' + lLogPath);
    Assert.IsTrue(lJson.Values['usages'] is TJSONArray, 'Expected usages array. See: ' + lLogPath);
    lUsages := lJson.Values['usages'] as TJSONArray;
    lHasUnitTwoUsage := False;
    for i := 0 to lUsages.Count - 1 do
    begin
      lUsage := lUsages.Items[i] as TJSONObject;
      if SameText(lUsage.GetValue<string>('unit', ''), 'UnitTwo') and
        ContainsText(lUsage.GetValue<string>('file', ''), 'UnitTwo.pas') then
        lHasUnitTwoUsage := True;
    end;
    Assert.IsTrue(lHasUnitTwoUsage, 'Expected cross-unit usage in JSON. See: ' + lLogPath);
  finally
    lJson.Free;
  end;
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

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format text',
    RepoRoot, lLogPath, lExitCode), 'Failed to start rename command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected dry-run rename to succeed. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
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

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --apply --format json' +
    ' --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lLogPath, lExitCode), 'Failed to start rename apply command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected apply rename to succeed. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos('"apply":true', lLogText) > 0, 'Expected JSON apply flag. See: ' + lLogPath);
  Assert.IsTrue(Pos('"status":"applied"', lLogText) > 0, 'Expected applied status. See: ' + lLogPath);
  Assert.IsTrue(Pos('"verification":{"status":"passed"', lLogText) > 0,
    'Expected post-apply build verification to pass. See: ' + lLogPath);
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

procedure TRefactorCommandTests.RenameCommandRollsBackWhenBuildVerificationFails;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
  lRoot: string;
  lUnitOnePath: string;
  lUnitOneText: string;
  lUnitTwoPath: string;
  lUnitTwoText: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-verify-fail');
  CreateBuildFailureFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-verify-fail.log');

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --apply --format json' +
    ' --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lLogPath, lExitCode), 'Failed to start rename apply command.');
  Assert.AreNotEqual(Cardinal(0), lExitCode,
    'Expected rename apply to fail when post-edit build verification fails. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos('"status":"rolledBack"', lLogText) > 0,
    'Expected rolled-back status after verification failure. See: ' + lLogPath);
  Assert.IsTrue(Pos('"verification":{"status":"failed"', lLogText) > 0,
    'Expected failed build verification details. See: ' + lLogPath);
  Assert.IsTrue(Pos('"diagnostic":"Build verification failed', lLogText) > 0,
    'Expected deterministic build verification diagnostic. See: ' + lLogPath);

  lUnitOneText := TFile.ReadAllText(lUnitOnePath, TEncoding.UTF8);
  lUnitTwoText := TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8);
  Assert.IsTrue(Pos('SharedValue: Integer', lUnitOneText) > 0,
    'Rollback must restore the original declaration.');
  Assert.IsTrue(Pos('SharedValue := 2', lUnitTwoText) > 0,
    'Rollback must restore the original usage text.');
  Assert.AreEqual(0, Pos('RenamedValue', lUnitOneText + lUnitTwoText),
    'Rollback must remove all applied rename edits.');
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

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --file ' + QuoteArg(lUnitOnePath) + ' --line 6 --col 3' +
    ' --new-name RenamedValue --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start rename position command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected position rename dry-run to succeed. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos('"status":"planned"', lLogText) > 0, 'Expected planned status. See: ' + lLogPath);
  Assert.IsTrue(Pos('"symbol":"SharedValue"', lLogText) > 0, 'Expected resolved symbol. See: ' + lLogPath);
  Assert.IsTrue(Pos('"referenceReconciliationFallbackCount":', lLogText) > 0,
    'Expected reference reconciliation fallback metric in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"identifierFullModelCount":3', lLogText) > 0,
    'Position targets must keep full analysis. See: ' + lLogPath);
  Assert.IsTrue(Pos('"identifierLeanModelCount":0', lLogText) > 0,
    'Position targets must not use lean models. See: ' + lLogPath);
  Assert.IsTrue(Pos('"identifierScopeFailOpen":true', lLogText) > 0,
    'Position targets must report the full-analysis fallback. See: ' + lLogPath);
  Assert.IsTrue(Pos('"identifierScopeFailOpenReason":"position-target"',
    lLogText) > 0, 'Expected position-target fallback reason. See: ' + lLogPath);
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

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start rename command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected rename to succeed. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
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
  Assert.IsTrue(Pos('"identifierCandidateScanMs":', lLogText) > 0,
    'Expected identifier candidate scan timing in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"identifierFullModelCount":2', lLogText) > 0,
    'Expected both identifier-bearing units to receive full models. See: ' + lLogPath);
  Assert.IsTrue(Pos('"identifierLeanModelCount":1', lLogText) > 0,
    'Expected the project source without the identifier to use a lean model. See: ' + lLogPath);
  Assert.IsTrue(Pos('"identifierScopeFailOpen":false', lLogText) > 0,
    'Simple name targets should use scoped analysis. See: ' + lLogPath);
  Assert.IsTrue(Pos('"identifierScopeFailOpenReason":""', lLogText) > 0,
    'Scoped analysis should not report a fallback reason. See: ' + lLogPath);
  Assert.IsTrue(Pos('"projectSymbolIndexBuildMs":', lLogText) > 0,
    'Expected project symbol index timing in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"projectSymbolIndexBuildCount":', lLogText) > 0,
    'Expected project symbol index build count in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"commandPlanningMs":', lLogText) > 0,
    'Expected command planning timing in JSON. See: ' + lLogPath);
  Assert.IsTrue(Pos('"commandPlanningCount":1', lLogText) > 0,
    'Expected command planning count in JSON. See: ' + lLogPath);
end;

function TRefactorCommandTests.CreateFixtureProjectPath(
  const aRoot: string): string;
var
  lUnitOnePath: string;
  lUnitTwoPath: string;
begin
  CreateFixtureProject(aRoot, Result, lUnitOnePath, lUnitTwoPath);
end;

procedure TRefactorCommandTests.ScopedIdentifierAdapterMatchesForcedFullRename;
var
  lAutomatic: TIdentifierAdapterPlanResult;
  lDprojPath: string;
  lForced: TIdentifierAdapterPlanResult;
  lOptions: TDelphiSemanticOptions;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'refactor-identifier-scope-parity');
  lDprojPath := CreateFixtureProjectPath(lRoot);
  lOptions := BuildSemanticSessionOptions(lDprojPath, 'Debug', 'Win32',
    '23.0', '', '', '');

  lAutomatic := BuildIdentifierAdapterPlan(lOptions);
  lOptions.ForceFullIdentifierAnalysis := True;
  lForced := BuildIdentifierAdapterPlan(lOptions);

  Assert.AreEqual(2, lAutomatic.Metrics.IdentifierFullModelCount);
  Assert.AreEqual(1, lAutomatic.Metrics.IdentifierLeanModelCount);
  Assert.IsFalse(lAutomatic.Metrics.IdentifierScopeFailOpen);
  Assert.AreEqual(3, lForced.Metrics.IdentifierFullModelCount);
  Assert.AreEqual(0, lForced.Metrics.IdentifierLeanModelCount);
  Assert.IsTrue(lForced.Metrics.IdentifierScopeFailOpen);
  AssertRenamePlansEqual(lForced.Plan, lAutomatic.Plan);
end;

procedure TRefactorCommandTests.RenameGuardValidationRejectsStaleSource;
var
  lError: string;
  lPlan: TDelphiSemanticRenamePlan;
  lRoot: string;
  lSource: TDakSourceBuffer;
  lSourcePath: string;
  lText: string;
begin
  lRoot := TPath.Combine(TempRoot, 'rename-stale-source-guard');
  ForceDirectories(lRoot);
  lSourcePath := TPath.Combine(lRoot, 'GuardUnit.pas');
  lText := 'unit GuardUnit;' + sLineBreak +
    '' + sLineBreak +
    'interface' + sLineBreak +
    '' + sLineBreak +
    'var' + sLineBreak +
    '  SharedValue: Integer;' + sLineBreak +
    '' + sLineBreak +
    'implementation' + sLineBreak +
    '' + sLineBreak +
    'end.' + sLineBreak;
  TFile.WriteAllText(lSourcePath, lText, TEncoding.UTF8);

  lPlan := Default(TDelphiSemanticRenamePlan);
  lPlan.Status := 'planned';
  lPlan.ContextFingerprint := 'rename-plan-context';
  lPlan.BaselineSemanticModelVersion := 'rename-plan-model';
  SetLength(lPlan.RequiredVerification, 1);
  lPlan.RequiredVerification[0].Kind := 'source-file-hash';
  lPlan.RequiredVerification[0].Description := 'verify planned source hash';
  SetLength(lPlan.Edits, 1);
  lPlan.Edits[0].FileName := lSourcePath;
  lPlan.Edits[0].Role := 'declaration';
  lPlan.Edits[0].StartLine := 6;
  lPlan.Edits[0].StartColumn := 3;
  lPlan.Edits[0].EndLine := 6;
  lPlan.Edits[0].EndColumn := 13;
  lPlan.Edits[0].ExpectedFileHash := THashSHA2.GetHashStringFromFile(lSourcePath);
  lPlan.Edits[0].ExpectedSourceText := 'SharedValue';
  lPlan.Edits[0].NewText := 'RenamedValue';

  TFile.WriteAllText(lSourcePath, lText + '// changed after planning' + sLineBreak,
    TEncoding.UTF8);
  Assert.IsTrue(LoadDakSource(lSourcePath, lSource, lError), lError);

  Assert.IsFalse(ValidateRenamePlanGuards(lPlan, lSourcePath, lSource, lError),
    'Expected stale source to fail guard validation.');
  Assert.IsTrue(ContainsText(lError, 'stale-rename-plan'), lError);
  Assert.IsTrue(ContainsText(lError, 'source file hash changed'), lError);
  Assert.AreEqual(0, Pos('RenamedValue', TFile.ReadAllText(lSourcePath, TEncoding.UTF8)),
    'Stale guard validation must not mutate source.');
end;

procedure TRefactorCommandTests.RenameGuardValidationUsesApplyPathMatching;
var
  lCurrentDir: string;
  lError: string;
  lPlan: TDelphiSemanticRenamePlan;
  lRelativeSourcePath: string;
  lRoot: string;
  lSource: TDakSourceBuffer;
  lSourcePath: string;
  lText: string;
begin
  lCurrentDir := GetCurrentDir;
  SetCurrentDir(RepoRoot);
  try
    lRoot := TPath.Combine(TempRoot, 'rename-stale-source-relative-guard');
    ForceDirectories(lRoot);
    lSourcePath := TPath.Combine(lRoot, 'RelativeGuardUnit.pas');
    lRelativeSourcePath := ExtractRelativePath(IncludeTrailingPathDelimiter(RepoRoot),
      lSourcePath);
    lText := 'unit RelativeGuardUnit;' + sLineBreak +
      '' + sLineBreak +
      'interface' + sLineBreak +
      '' + sLineBreak +
      'var' + sLineBreak +
      '  SharedValue: Integer;' + sLineBreak +
      '' + sLineBreak +
      'implementation' + sLineBreak +
      '' + sLineBreak +
      'end.' + sLineBreak;
    TFile.WriteAllText(lSourcePath, lText, TEncoding.UTF8);

    lPlan := Default(TDelphiSemanticRenamePlan);
    lPlan.Status := 'planned';
    lPlan.ContextFingerprint := 'rename-plan-context';
    lPlan.BaselineSemanticModelVersion := 'rename-plan-model';
    SetLength(lPlan.RequiredVerification, 1);
    lPlan.RequiredVerification[0].Kind := 'source-file-hash';
    lPlan.RequiredVerification[0].Description := 'verify planned source hash';
    SetLength(lPlan.Edits, 1);
    lPlan.Edits[0].FileName := lRelativeSourcePath;
    lPlan.Edits[0].Role := 'declaration';
    lPlan.Edits[0].StartLine := 6;
    lPlan.Edits[0].StartColumn := 3;
    lPlan.Edits[0].EndLine := 6;
    lPlan.Edits[0].EndColumn := 13;
    lPlan.Edits[0].ExpectedFileHash := THashSHA2.GetHashStringFromFile(lSourcePath);
    lPlan.Edits[0].ExpectedSourceText := 'SharedValue';
    lPlan.Edits[0].NewText := 'RenamedValue';

    TFile.WriteAllText(lSourcePath, lText + '// changed after planning' + sLineBreak,
      TEncoding.UTF8);
    Assert.IsTrue(LoadDakSource(lSourcePath, lSource, lError), lError);

    Assert.IsFalse(ValidateRenamePlanGuards(lPlan, lSourcePath, lSource, lError),
      'Guard validation must use the same normalized file matching as apply mode.');
    Assert.IsTrue(ContainsText(lError, 'stale-rename-plan'), lError);
    Assert.IsTrue(ContainsText(lError, 'source file hash changed'), lError);
  finally
    SetCurrentDir(lCurrentDir);
  end;
end;

procedure TRefactorCommandTests.RenameApplyRequiresStaleEditGuardsBeforeMutation;
var
  lApplyPos: Integer;
  lGuardSource: string;
  lGuardPos: Integer;
  lSource: string;
  lWritePos: Integer;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.Refactor.pas'), TEncoding.UTF8);
  lGuardSource := TFile.ReadAllText(TPath.Combine(RepoRoot,
    'src\Dak.Refactor.RenameGuards.pas'), TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lGuardSource, 'stale-rename-plan'),
    'DAK apply must emit deterministic stale rename-plan diagnostics.');
  Assert.IsTrue(ContainsText(lSource, 'ValidateRenamePlanGuards'),
    'DAK apply must validate rename-plan stale guards before mutation.');

  lGuardPos := Pos('ValidateRenamePlanGuards', lSource);
  lApplyPos := Pos('ApplyEditToSource(lEdit', lSource);
  lWritePos := Pos('TFile.WriteAllBytes(lFileName', lSource);
  Assert.IsTrue((lGuardPos > 0) and (lGuardPos < lApplyPos),
    'Stale guards must be checked before edit application.');
  Assert.IsTrue((lGuardPos > 0) and (lGuardPos < lWritePos),
    'Stale guards must be checked before source files are written.');
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

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json' +
    ' --semantic-cache ' + QuoteArg(lCachePath) +
    ' --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lDebugLogPath, lExitCode), 'Failed to start debug rename command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected debug rename to succeed. See: ' + lDebugLogPath);

  lDebugLogText := ReadUtf8TextFile(lDebugLogPath);
  Assert.IsTrue(Pos('"baselineSemanticModelVersion":"project-snapshot-v1"', lDebugLogText) > 0,
    'Expected snapshot-backed rename provenance. See: ' + lDebugLogPath);
  Assert.IsTrue(Pos('"semanticCacheHits":0', lDebugLogText) > 0,
    'Expected cold debug cache run to avoid hits. See: ' + lDebugLogPath);
  Assert.IsFalse(Pos('"semanticCacheMisses":0', lDebugLogText) > 0,
    'Expected cold debug cache run to record misses. See: ' + lDebugLogPath);
  Assert.IsTrue(Pos('"projectSymbolIndexBuildCount":0', lDebugLogText) > 0,
    'Snapshot-backed rename must not build the legacy project symbol index. See: ' +
    lDebugLogPath);

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json' +
    ' --semantic-cache ' + QuoteArg(lCachePath) +
    ' --delphi 23.0 --platform Win32 --config Release',
    RepoRoot, lReleaseLogPath, lExitCode), 'Failed to start release rename command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected release rename to succeed. See: ' + lReleaseLogPath);

  lReleaseLogText := ReadUtf8TextFile(lReleaseLogPath);
  Assert.IsTrue(Pos('"baselineSemanticModelVersion":"project-snapshot-v1"', lReleaseLogText) > 0,
    'Expected snapshot-backed rename provenance. See: ' + lReleaseLogPath);
  Assert.IsTrue(Pos('"semanticCacheHits":0', lReleaseLogText) > 0,
    'Changing config must not hit entries created for another toolchain identity. See: ' + lReleaseLogPath);
  Assert.IsFalse(Pos('"semanticCacheMisses":0', lReleaseLogText) > 0,
    'Changing config should rebuild semantic unit models. See: ' + lReleaseLogPath);
  Assert.IsTrue(Pos('"semanticCacheInvalidations":0', lReleaseLogText) > 0,
    'Snapshot cache keys should isolate toolchain identities without legacy invalidation. See: ' +
    lReleaseLogPath);
  Assert.IsTrue(Pos('"projectSymbolIndexBuildCount":0', lReleaseLogText) > 0,
    'Snapshot-backed rename must not build the legacy project symbol index. See: ' +
    lReleaseLogPath);
end;

procedure TRefactorCommandTests.RenameDefaultsToProjectLocalSemanticCache;
var
  lCachePath: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lFirstLogPath: string;
  lFirstLogText: string;
  lRoot: string;
  lSecondLogPath: string;
  lSecondLogText: string;
  lUnitOnePath: string;
  lUnitTwoPath: string;
begin
  EnsureResolverBuilt;
  lRoot := UniqueTempPath('refactor-rename-default-cache');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lCachePath := TPath.Combine(TPath.Combine(TPath.Combine(lRoot, '.dak'),
    'RefactorFixture'), 'semantic-cache.sqlite3');
  lFirstLogPath := TPath.Combine(TempRoot, 'refactor-rename-default-cache-first.log');
  lSecondLogPath := TPath.Combine(TempRoot, 'refactor-rename-default-cache-second.log');

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json' +
    ' --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lFirstLogPath, lExitCode), 'Failed to start first default-cache rename.');
  Assert.AreEqual(Cardinal(0), lExitCode,
    'Expected first default-cache rename to succeed. See: ' + lFirstLogPath);
  Assert.IsTrue(TFile.Exists(lCachePath),
    'Expected rename to create the canonical project-local semantic cache: ' + lCachePath);
  lFirstLogText := ReadUtf8TextFile(lFirstLogPath);
  Assert.IsTrue(Pos('"semanticCacheHits":0', lFirstLogText) > 0,
    'Expected cold default-cache rename to report zero hits. See: ' + lFirstLogPath);
  Assert.IsFalse(Pos('"semanticCacheMisses":0', lFirstLogText) > 0,
    'Expected cold default-cache rename to report misses. See: ' + lFirstLogPath);

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json' +
    ' --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lSecondLogPath, lExitCode), 'Failed to start second default-cache rename.');
  Assert.AreEqual(Cardinal(0), lExitCode,
    'Expected second default-cache rename to succeed. See: ' + lSecondLogPath);
  lSecondLogText := ReadUtf8TextFile(lSecondLogPath);
  Assert.IsFalse(Pos('"semanticCacheHits":0', lSecondLogText) > 0,
    'Expected unchanged second rename to report cache hits. See: ' + lSecondLogPath);
  Assert.IsTrue(Pos('"semanticCacheMisses":0', lSecondLogText) > 0,
    'Expected unchanged second rename to avoid cache misses. See: ' + lSecondLogPath);
end;

procedure TRefactorCommandTests.RenameSemanticCacheOptOutAndImplicitFallback;
var
  lBlockedDakPath: string;
  lCachePath: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lExplicitLogPath: string;
  lExplicitLogText: string;
  lFallbackLogPath: string;
  lFallbackLogText: string;
  lOptOutLogPath: string;
  lRoot: string;
  lUnitOnePath: string;
  lUnitTwoPath: string;
begin
  EnsureResolverBuilt;
  lRoot := UniqueTempPath('refactor-rename-cache-policy');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lCachePath := TPath.Combine(TPath.Combine(TPath.Combine(lRoot, '.dak'),
    'RefactorFixture'), 'semantic-cache.sqlite3');
  lOptOutLogPath := TPath.Combine(TempRoot, 'refactor-rename-cache-opt-out.log');

  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json --no-semantic-cache' +
    ' --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lOptOutLogPath, lExitCode), 'Failed to start opt-out rename.');
  Assert.AreEqual(Cardinal(0), lExitCode,
    'Expected --no-semantic-cache rename to succeed. See: ' + lOptOutLogPath);
  Assert.IsFalse(TFile.Exists(lCachePath),
    '--no-semantic-cache must not create the default persistent cache.');

  lBlockedDakPath := TPath.Combine(lRoot, '.dak');
  TFile.WriteAllText(lBlockedDakPath, 'blocks cache directory creation', TEncoding.UTF8);
  lFallbackLogPath := TPath.Combine(TempRoot, 'refactor-rename-cache-fallback.log');
  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json' +
    ' --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lFallbackLogPath, lExitCode), 'Failed to start implicit-fallback rename.');
  Assert.AreEqual(Cardinal(0), lExitCode,
    'Implicit cache failure must continue uncached. See: ' + lFallbackLogPath);
  lFallbackLogText := ReadUtf8TextFile(lFallbackLogPath);
  Assert.IsTrue(ContainsText(lFallbackLogText, 'semantic cache unavailable'),
    'Expected actionable implicit-cache diagnostic. Actual: ' + lFallbackLogText);
  Assert.IsTrue(ContainsText(lFallbackLogText, 'continuing without persistence'),
    'Expected fallback diagnostic to explain uncached continuation.');
  Assert.IsTrue(ContainsText(lFallbackLogText, '--no-semantic-cache'),
    'Expected fallback diagnostic to document the opt-out switch. Actual: ' +
    lFallbackLogText);

  lExplicitLogPath := TPath.Combine(TempRoot, 'refactor-rename-cache-explicit-failure.log');
  Assert.IsTrue(RunResolverProcess(
    'rename --project ' + QuoteArg(lDprojPath) +
    ' --symbol SharedValue --new-name RenamedValue --format json --semantic-cache ' +
    QuoteArg(TPath.Combine(lBlockedDakPath, 'explicit.sqlite3')) +
    ' --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lExplicitLogPath, lExitCode), 'Failed to start explicit-cache rename.');
  Assert.AreNotEqual(Cardinal(0), lExitCode,
    'An explicitly requested unusable cache must remain a strict failure.');
  lExplicitLogText := ReadUtf8TextFile(lExplicitLogPath);
  Assert.IsFalse(ContainsText(lExplicitLogText, 'continuing without persistence'),
    'Explicit cache failures must not silently retry uncached.');
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
  Assert.IsTrue(ContainsText(lSource, 'OpenSemanticSymbolQueryContext'),
    'DAK refactor commands should build DelphiSemantics query contexts through the shared adapter.');
end;

procedure TRefactorCommandTests.SemanticsSessionAdapterMapsOptionsAndDiagnostics;
var
  lCachePath: string;
  lDiagnostics: TArray<TDelphiSemanticDiagnostic>;
  lOptions: TDelphiSemanticOptions;
begin
  lCachePath := TPath.Combine(TPath.GetTempPath, 'dak-semantic-session.sqlite3');
  lOptions := BuildSemanticSessionOptions('project.dproj', 'Debug', 'Win64', '23',
    'rsvars.bat', 'env.options', lCachePath);

  Assert.AreEqual('project.dproj', lOptions.ProjectPath);
  Assert.AreEqual('Debug', lOptions.Configuration);
  Assert.AreEqual('Win64', lOptions.Platform);
  Assert.AreEqual('23', lOptions.DelphiVersion);
  Assert.AreEqual('rsvars.bat', lOptions.RsVarsPath);
  Assert.AreEqual('env.options', lOptions.EnvOptionsPath);
  Assert.AreEqual(TPath.GetFullPath(lCachePath), lOptions.SqliteCacheFileName);

  SetLength(lDiagnostics, 1);
  lDiagnostics[0].Code := 'E001';
  lDiagnostics[0].Message := 'Cannot load project';
  lDiagnostics[0].FileName := 'UnitOne.pas';
  lDiagnostics[0].Line := 42;

  Assert.AreEqual('E001: Cannot load project (UnitOne.pas)',
    SemanticSessionDiagnosticsText(lDiagnostics));
  Assert.AreEqual('E001: Cannot load project (UnitOne.pas) line 42',
    SemanticSessionDiagnosticsText(lDiagnostics, True));
end;

procedure TRefactorCommandTests.SemanticSnapshotContextRejectsFailedProjectUnit;
var
  lContext: IDakSemanticSymbolQueryContext;
  lDprojPath: string;
  lError: string;
  lMetrics: TDakSemanticSymbolQueryMetrics;
  lMissingPath: string;
  lOptions: TDelphiSemanticOptions;
  lRoot: string;
  lUnitOnePath: string;
  lUnitTwoPath: string;
begin
  lRoot := TPath.Combine(TempRoot, 'refactor-snapshot-failed-unit');
  CreateFixtureProject(lRoot, lDprojPath, lUnitOnePath, lUnitTwoPath);
  lMissingPath := TPath.Combine(lRoot, 'MissingUnit.pas');
  lOptions := BuildSemanticSessionOptions(lDprojPath, 'Debug', 'Win32', '23.0', '', '',
    TPath.Combine(lRoot, 'semantic-cache.sqlite3'));
  lOptions.AdditionalSourceFileNames := TArray<string>.Create(lMissingPath);

  Assert.IsFalse(OpenSemanticSymbolQueryContext(lOptions, lContext, lMetrics, lError, True),
    'Expected semantic context validation to fail for missing project units.');
  Assert.IsTrue(lContext = nil, 'Failed context opens must not return a query context.');
  Assert.IsTrue(ContainsText(lError, 'Failed to build semantic model for project unit'),
    'Expected failed semantic model diagnostic: ' + lError);
  Assert.IsTrue(ContainsText(lError, 'MissingUnit.pas'),
    'Expected missing unit file in diagnostic: ' + lError);
  Assert.IsTrue(ContainsText(lError, 'SOURCE_FILE_NOT_FOUND'),
    'Expected source-loader diagnostic in semantic error: ' + lError);
end;

procedure TRefactorCommandTests.SemanticsSessionAdapterIsCentralized;
var
  lCommandSource: string;
  lHelperSource: string;
  lPath: string;
begin
  lHelperSource := TFile.ReadAllText(TPath.Combine(RepoRoot,
    'src\Dak.Semantics.Session.pas'), TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lHelperSource, 'TDelphiSemanticProjectSession.Open'),
    'The shared adapter should own the raw DelphiSemantics session open call.');
  Assert.IsTrue(ContainsText(lHelperSource, 'SemanticSessionDiagnosticsText'),
    'The shared adapter should own Semantics diagnostic formatting.');
  Assert.IsTrue(ContainsText(lHelperSource, 'OpenSemanticSymbolQueryContext'),
    'The shared adapter should own session-backed query context setup.');
  Assert.IsTrue(ContainsText(lHelperSource, 'BuildSnapshotSymbolQueryContext'),
    'The shared adapter should build owned snapshot-backed Semantics query contexts.');
  Assert.IsFalse(ContainsText(lHelperSource, 'lSessionResult.Session.BuildSymbolQueryContext'),
    'The shared adapter must not use the legacy model-only query context builder.');
  Assert.IsTrue(ContainsText(lHelperSource, 'GetVisibleUnitScopes'),
    'The shared adapter should validate and count snapshot-backed visible scopes.');

  for lPath in ['src\Dak.Refactor.pas', 'src\Dak.SymbolMap.Query.pas',
    'src\Dak.GlobalVars.Semantics.pas', 'src\dak.deps.runner.pas'] do
  begin
    lCommandSource := TFile.ReadAllText(TPath.Combine(RepoRoot, lPath), TEncoding.UTF8);
    Assert.IsTrue(ContainsText(lCommandSource, 'Dak.Semantics.Session'),
      lPath + ' should use the shared Semantics session adapter.');
    Assert.IsTrue(ContainsText(lCommandSource, 'BuildSemanticSessionOptions'),
      lPath + ' should build Semantics options through the shared adapter.');
    Assert.IsFalse(ContainsText(lCommandSource, 'TDelphiSemanticProjectSession.Open'),
      lPath + ' must not call the raw Semantics session opener directly.');
    Assert.IsFalse(ContainsText(lCommandSource, 'function SessionDiagnosticsText'),
      lPath + ' must not duplicate Semantics diagnostic formatting.');
    Assert.IsFalse(ContainsText(lCommandSource, 'TDelphiSemanticProjectSessionResult'),
      lPath + ' must not expose raw Semantics project-session records.');
    Assert.IsFalse(ContainsText(lCommandSource, 'TDelphiSemanticSymbolQueryContext'),
      lPath + ' must not expose raw Semantics query-context records.');
    Assert.IsFalse(ContainsText(lCommandSource, 'TDelphiSemanticCacheMetrics'),
      lPath + ' must not expose raw Semantics cache metrics.');
    Assert.IsFalse(ContainsText(lCommandSource, 'DelphiSemantics.ProjectSession'),
      lPath + ' must not use Semantics project-session internals directly.');
    Assert.IsFalse(ContainsText(lCommandSource, 'DelphiSemantics.Query'),
      lPath + ' must not use Semantics query internals directly.');
    if ContainsText(lPath, 'Refactor') or ContainsText(lPath, 'SymbolMap.Query') then
    begin
      Assert.IsTrue(ContainsText(lCommandSource, 'OpenSemanticSymbolQueryContext'),
        lPath + ' should build query contexts through the shared adapter.');
      Assert.IsFalse(ContainsText(lCommandSource, 'BuildSymbolQueryContext'),
        lPath + ' must not duplicate Semantics query-context setup.');
    end else begin
      Assert.IsTrue(ContainsText(lCommandSource, 'OpenSemanticProjectSession'),
        lPath + ' should open Semantics sessions through the shared adapter.');
    end;
  end;
end;

procedure TRefactorCommandTests.RefactorJsonOutputUsesStructuredBuilders;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.Refactor.pas'),
    TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSource, 'System.JSON'),
    'Refactor and dead-code JSON output should use structured System.JSON builders.');
  Assert.IsFalse(ContainsText(lSource, 'function JsonEscape'),
    'Refactor must not keep a local string-escaping JSON helper.');
  Assert.IsFalse(ContainsText(lSource, 'JsonEscape('),
    'Refactor JSON output should not call local escape-based string builders.');
  Assert.IsFalse(ContainsText(lSource, 'Result := ''{"'),
    'Refactor JSON objects should be built structurally, not by concatenating object literals.');
end;

procedure TRefactorCommandTests.ProjectDakRootPolicyIsCentralized;
var
  lCommandSource: string;
  lHelperPath: string;
  lHelperSource: string;
  lPath: string;
begin
  lHelperPath := TPath.Combine(RepoRoot, 'src\Dak.Paths.pas');
  Assert.IsTrue(TFile.Exists(lHelperPath),
    'Project-local .dak path construction should live in a shared Dak.Paths helper.');

  lHelperSource := TFile.ReadAllText(lHelperPath, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lHelperSource, 'function DakProjectRoot'),
    'Dak.Paths should expose the project-local .dak root helper.');
  Assert.IsTrue(ContainsText(lHelperSource, 'function DakProjectPath'),
    'Dak.Paths should expose a command subpath helper.');
  Assert.IsTrue(ContainsText(lHelperSource, 'function ExplicitPathOrDefault'),
    'Dak.Paths should keep explicit user-provided output paths distinct from default paths.');
  Assert.IsTrue(ContainsText(lHelperSource, 'if aExplicitPath <> '''' then'),
    'Explicit user-provided paths must win over default project-local paths.');

  for lPath in ['src\dak.analyze.common.pas', 'src\Dak.Project.Semantics.pas',
    'src\dak.lsp.context.pas', 'src\Dak.SymbolMap.Context.pas',
    'src\dak.deps.runner.pas', 'src\Dak.Refactor.pas', 'src\Dak.RemoveWith.pas'] do
  begin
    lCommandSource := TFile.ReadAllText(TPath.Combine(RepoRoot, lPath), TEncoding.UTF8);
    Assert.IsTrue(ContainsText(lCommandSource, 'Dak.Paths'),
      lPath + ' should use the shared project-local path helper.');
    Assert.IsFalse(ContainsText(lCommandSource, 'TPath.Combine(TPath.Combine') and
      ContainsText(lCommandSource, '''.dak'''),
      lPath + ' must not construct project-local .dak roots with nested TPath.Combine calls.');
  end;

  lCommandSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.deps.runner.pas'), TEncoding.UTF8);
  Assert.IsFalse(ContainsText(lCommandSource, 'function TDepsGraphBuilder.DefaultOutputPath'),
    'Deps default output path resolution should live only in the command runner.');
end;

procedure TRefactorCommandTests.ProprietaryRenameDogfoodHasMaxTdbProofCategory;
var
  lNormalizedSource: string;
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot,
    'tests\units\test.refactor.proprietaryrename.pas'), TEncoding.UTF8);
  lNormalizedSource := StringReplace(lSource, #13#10, #10, [rfReplaceAll]);
  lNormalizedSource := StringReplace(lNormalizedSource, #13, #10, [rfReplaceAll]);

  Assert.IsTrue(ContainsText(lNormalizedSource,
    '[TestFixture]' + #10 +
    '  [Category(''MaxTdbProof'')]' + #10 +
    '  TRefactorProprietaryRenameTests = class'),
    'Proprietary maxTdb rename dogfood must be categorized as MaxTdbProof.');
end;

procedure TRefactorCommandTests.DefaultRunnerExcludesMaxTdbProofOnlyWithoutExplicitFilters;
var
  lApplyExclusionPos: Integer;
  lCreateRunnerPos: Integer;
  lCheckCommandLinePos: Integer;
  lNormalizedSource: string;
  lNormalizedRemoveWithSource: string;
  lRemoveWithSource: string;
  lRunnerSource: string;
begin
  lRemoveWithSource := TFile.ReadAllText(TPath.Combine(RepoRoot,
    'tests\units\test.removewith.pas'), TEncoding.UTF8);
  lNormalizedRemoveWithSource := StringReplace(lRemoveWithSource, #13#10, #10,
    [rfReplaceAll]);
  lNormalizedRemoveWithSource := StringReplace(lNormalizedRemoveWithSource, #13,
    #10, [rfReplaceAll]);
  Assert.IsTrue(ContainsText(lNormalizedRemoveWithSource,
    '[TestFixture]' + #10 +
    '  [Category(''MaxTdbProof'')]' + #10 +
    '  TRemoveWithProprietaryProjectTests = class(TRemoveWithTestBase)'),
    'Proprietary maxTdb remove-with dogfood must be categorized as MaxTdbProof.');

  lRunnerSource := TFile.ReadAllText(TPath.Combine(RepoRoot,
    'tests\DelphiAIKit.Tests.dpr'), TEncoding.UTF8);
  lNormalizedSource := StringReplace(lRunnerSource, #13#10, #10, [rfReplaceAll]);
  lNormalizedSource := StringReplace(lNormalizedSource, #13, #10, [rfReplaceAll]);

  Assert.IsTrue(ContainsText(lRunnerSource, 'DUnitX.FilterBuilder'),
    'The DAK test runner should use DUnitX filtering for default MaxTdbProof exclusion.');
  Assert.IsTrue(ContainsText(lRunnerSource, 'cMaxTdbProofCategory = ''MaxTdbProof'';'),
    'The MaxTdbProof category name should be centralized in the test runner.');
  Assert.IsTrue(ContainsText(lNormalizedSource,
    '(TDUnitX.Options.Run.Count = 0) and' + #10 +
    '    (TDUnitX.Options.RunListFile = '''') and' + #10 +
    '    (TDUnitX.Options.Include = '''') and' + #10 +
    '    (TDUnitX.Options.Exclude = '''')'),
    'Default exclusion must apply only when no run/runlist/category filter is explicit.');
  Assert.IsTrue(ContainsText(lRunnerSource,
    'TDUnitX.Options.Exclude := cMaxTdbProofCategory'),
    'The default runner should exclude MaxTdbProof through DUnitX category filtering.');
  Assert.IsTrue(ContainsText(lRunnerSource,
    'TDUnitX.Filter := TDUnitXFilterBuilder.BuildFilter(TDUnitX.Options)'),
    'The runner must rebuild the DUnitX filter after injecting the default exclusion.');

  lCheckCommandLinePos := Pos('TDUnitX.CheckCommandLine', lRunnerSource);
  lApplyExclusionPos := PosEx('ApplyDefaultCategoryExclusions;', lRunnerSource,
    lCheckCommandLinePos);
  lCreateRunnerPos := Pos('TDUnitX.CreateRunner', lRunnerSource);
  Assert.IsTrue((lCheckCommandLinePos > 0) and (lApplyExclusionPos > lCheckCommandLinePos) and
    (lApplyExclusionPos < lCreateRunnerPos),
    'Default category exclusion must run after command-line parsing and before runner creation.');
end;

initialization
  TDUnitX.RegisterTestFixture(TRefactorCommandTests);

end.
