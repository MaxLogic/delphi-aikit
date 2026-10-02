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
    procedure FindUsagesAndRenameRefuseUnverifiedMembers;
    [Test]
    [TestCase('Failed syntax tree', 'True')]
    [TestCase('Verified control', 'False')]
    procedure DeadCodeBlocksUnverifiedMembers(const aFailed: Boolean);
    [Test]
    procedure RenameCommandDefaultsToDryRun;
    [Test]
    procedure RenameCommandAppliesEditsAndCreatesBackups;
    [Test]
    procedure RenameCommandRollsBackWhenBuildVerificationFails;
    [Test]
    procedure RenameCommandAcceptsSourcePositionTarget;
    [Test]
    procedure RenamePlanKeepsOverloadAndRangeBoundIdentity;
    [Test]
    procedure RenamePlansQualifiedMemberReferencesAndAppliesWithBuild;
    [Test]
    procedure RenameListsUnresolvedOverloadCallsAndRefusesApply;
    [Test]
    procedure RenameListsAstFailedConsumerReferences;
    [Test]
    procedure RenameRefusesUnprovenMemberAndPositionBindings;
    [Test]
    procedure RenameRefusesWithBodyNameFromIncludedMember;
    [Test]
    procedure RenameRefusesWithBodyNameOfClassReferenceSelector;
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
  System.Generics.Collections, System.Hash,
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

// UProv compiles, but the syntax tree builder rejects the one-character deprecation message.
// Its members then come from an unverified line scan, so find-usages and rename must refuse.
procedure TRefactorCommandTests.FindUsagesAndRenameRefuseUnverifiedMembers;
var
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lLogPath: string;
  lProjectPath: string;
  lRoot: string;
  lSourceHash: string;
  lUnitPath: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-unverified-members');
  ForceDirectories(lRoot);
  lUnitPath := TPath.Combine(lRoot, 'UProv.pas');
  lProjectPath := TPath.Combine(lRoot, 'Prov.dproj');
  TFile.WriteAllText(lUnitPath, 'unit UProv;'#13#10'interface'#13#10'type'#13#10 +
    '  TA = class'#13#10'  public'#13#10'    FCounter: Integer;'#13#10 +
    '    procedure Y; deprecated ''z'';'#13#10'  end;'#13#10'implementation'#13#10 +
    'procedure TA.Y;'#13#10'begin'#13#10'  FCounter := 1;'#13#10'end;'#13#10'end.'#13#10,
    TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lRoot, 'Prov.dpr'),
    'program Prov;'#13#10'uses UProv in ''UProv.pas'';'#13#10'begin end.'#13#10, TEncoding.ASCII);
  TFile.WriteAllText(lProjectPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup>' +
    '<MainSource>Prov.dpr</MainSource></PropertyGroup><ItemGroup>' +
    '<DCCReference Include="UProv.pas"/></ItemGroup></Project>', TEncoding.ASCII);
  lSourceHash := THashSHA2.GetHashStringFromFile(lUnitPath);

  lLogPath := TPath.Combine(TempRoot, 'refactor-unverified-find-usages.log');
  Assert.IsTrue(RunResolverProcess('find-usages --project ' + QuoteArg(lProjectPath) +
    ' --file ' + QuoteArg(lUnitPath) + ' --line 6 --col 5 --format json --no-semantic-cache',
    RepoRoot, lLogPath, lExitCode), 'Failed to start find-usages command.');
  Assert.AreNotEqual(Cardinal(0), lExitCode, 'Unverified members must not resolve. See: ' + lLogPath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
  try
    Assert.AreEqual('unknown', lJson.GetValue<string>('status', ''), lLogPath);
    Assert.IsTrue(ContainsText(lJson.GetValue<string>('diagnostic', ''), 'ast-failed'), lLogPath);
    Assert.AreEqual(0, lJson.GetValue<Integer>('count', -1), lLogPath);
  finally
    lJson.Free;
  end;

  lLogPath := TPath.Combine(TempRoot, 'refactor-unverified-rename.log');
  Assert.IsTrue(RunResolverProcess('rename --project ' + QuoteArg(lProjectPath) +
    ' --file ' + QuoteArg(lUnitPath) + ' --line 6 --col 5 --new-name FTally --format json' +
    ' --no-semantic-cache', RepoRoot, lLogPath, lExitCode), 'Failed to start rename command.');
  Assert.AreNotEqual(Cardinal(0), lExitCode, 'Unverified members must not be renamed. See: ' + lLogPath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
  try
    Assert.AreEqual('blocked', lJson.GetValue<string>('status', ''), lLogPath);
    Assert.IsTrue(ContainsText(lJson.GetValue<string>('diagnostic', ''), 'ast-failed'), lLogPath);
    Assert.AreEqual(0, lJson.GetValue<Integer>('editCount', -1), lLogPath);
  finally
    lJson.Free;
  end;
  Assert.AreEqual(lSourceHash, THashSHA2.GetHashStringFromFile(lUnitPath));
end;

// FUnused is private and unreferenced. In the ast-failed unit it is only an unverified fallback
// member, so no profile may report it as definitely unused.
procedure TRefactorCommandTests.DeadCodeBlocksUnverifiedMembers(const aFailed: Boolean);
var
  lCandidate: TJSONObject;
  lCandidates: TJSONArray;
  lDeprecation: string;
  lExitCode: Cardinal;
  lFound: Boolean;
  lJson: TJSONObject;
  lLogPath: string;
  lProfile: string;
  lProjectPath: string;
  lRoot: string;
  lSourceHash: string;
  lUnitPath: string;
  i: Integer;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-unverified-dead-code-' + BoolToStr(aFailed, True));
  ForceDirectories(lRoot);
  lUnitPath := TPath.Combine(lRoot, 'UProv.pas');
  lProjectPath := TPath.Combine(lRoot, 'Prov.dproj');
  lDeprecation := '';
  if aFailed then
    lDeprecation := ' deprecated ''z'';';
  TFile.WriteAllText(lUnitPath, 'unit UProv;'#13#10'interface'#13#10'type'#13#10 +
    '  TA = class'#13#10'  private'#13#10'    FUnused: Integer;'#13#10'  public'#13#10 +
    '    FCounter: Integer;'#13#10'    procedure Y;' + lDeprecation + #13#10'  end;'#13#10 +
    'implementation'#13#10'procedure TA.Y;'#13#10'begin'#13#10'  FCounter := 1;'#13#10 +
    'end;'#13#10'end.'#13#10, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lRoot, 'Prov.dpr'),
    'program Prov;'#13#10'uses UProv in ''UProv.pas'';'#13#10'begin end.'#13#10, TEncoding.ASCII);
  TFile.WriteAllText(lProjectPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><PropertyGroup>' +
    '<MainSource>Prov.dpr</MainSource></PropertyGroup><ItemGroup>' +
    '<DCCReference Include="UProv.pas"/></ItemGroup></Project>', TEncoding.ASCII);
  lSourceHash := THashSHA2.GetHashStringFromFile(lUnitPath);

  for lProfile in TArray<string>.Create('legacy-static', 'conservative') do
  begin
    lLogPath := TPath.Combine(TempRoot, 'refactor-unverified-dead-code-' +
      BoolToStr(aFailed, True) + '-' + lProfile + '.log');
    Assert.IsTrue(RunResolverProcess('dead-code --project ' + QuoteArg(lProjectPath) +
      ' --profile ' + lProfile + ' --format json --no-semantic-cache', RepoRoot, lLogPath,
      lExitCode), 'Failed to start dead-code command.');
    lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
    try
      Assert.IsTrue(lJson.Values['candidates'] is TJSONArray, lLogPath);
      lCandidates := lJson.Values['candidates'] as TJSONArray;
      lFound := False;
      for i := 0 to lCandidates.Count - 1 do
      begin
        lCandidate := lCandidates.Items[i] as TJSONObject;
        if not SameText(lCandidate.GetValue<string>('unit', ''), 'UProv') then
          Continue;
        if aFailed then
          Assert.AreNotEqual('definitely-unused', lCandidate.GetValue<string>('status', ''),
            'An ast-failed unit must not yield definitely-unused candidates. See: ' + lLogPath);
        if not SameText(lCandidate.GetValue<string>('name', ''), 'FUnused') then
          Continue;
        lFound := True;
        if aFailed then
        begin
          Assert.AreEqual('blocked', lCandidate.GetValue<string>('status', ''), lLogPath);
          Assert.AreEqual('unverified-scope-facts',
            lCandidate.GetValue<string>('reason', ''), lLogPath);
        end else
          Assert.AreEqual('definitely-unused', lCandidate.GetValue<string>('status', ''),
            'The verified control still reports. See: ' + lLogPath);
      end;
      Assert.IsTrue(lFound, 'Expected the FUnused candidate. See: ' + lLogPath);
    finally
      lJson.Free;
    end;
  end;
  Assert.AreEqual(lSourceHash, THashSHA2.GetHashStringFromFile(lUnitPath));
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
  // DS-652: the plan itself names the project build that apply runs.
  Assert.IsTrue(Pos('"kind":"project-build"', lLogText) > 0,
    'Expected project-build in requiredVerification. See: ' + lLogPath);
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

procedure CreateOverloadRangeFixtureProject(const aRoot: string; out aDprojPath,
  aUnitPath: string);
begin
  ForceDirectories(aRoot);
  aDprojPath := TPath.Combine(aRoot, 'OverloadRangeFixture.dproj');
  aUnitPath := TPath.Combine(aRoot, 'OverloadRange.pas');
  TFile.WriteAllText(aDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup><MainSource>OverloadRangeFixture.dpr</MainSource></PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(aRoot, 'OverloadRangeFixture.dpr'),
    'program OverloadRangeFixture;' + sLineBreak + 'uses' + sLineBreak +
    '  OverloadRange in ''OverloadRange.pas'';' + sLineBreak + 'begin' + sLineBreak + '  Run(1);' + sLineBreak +
    'end.' + sLineBreak, TEncoding.UTF8);
  // Line layout: cMax 7, subrange 10, Add overloads 12/13 and 20/25, calls 42/43,
  // case label with a second cMax use on 47.
  TFile.WriteAllText(aUnitPath,
    'unit OverloadRange;' + sLineBreak + '' + sLineBreak + 'interface' + sLineBreak +
    '' + sLineBreak + 'const' + sLineBreak + '  cMin = 1;' + sLineBreak +
    '  cMax = 5;' + sLineBreak + '' + sLineBreak + 'type' + sLineBreak +
    '  TR = cMin..cMax;' + sLineBreak + '' + sLineBreak +
    'procedure Add(const A: array of Integer); overload;' + sLineBreak +
    'procedure Add(const A: array of string); overload;' + sLineBreak +
    'procedure Put(const A: Integer); overload;' + sLineBreak +
    'procedure Put(const A: string); overload;' + sLineBreak +
    'procedure Run(X: Integer);' + sLineBreak + '' + sLineBreak +
    'implementation' + sLineBreak + '' + sLineBreak +
    'procedure Add(const A: array of Integer);' + sLineBreak + 'begin' + sLineBreak +
    '  WriteLn(Length(A));' + sLineBreak + 'end;' + sLineBreak + '' + sLineBreak +
    'procedure Add(const A: array of string);' + sLineBreak + 'begin' + sLineBreak +
    '  WriteLn(Length(A));' + sLineBreak + 'end;' + sLineBreak + '' + sLineBreak +
    'procedure Put(const A: Integer);' + sLineBreak + 'begin' + sLineBreak +
    '  WriteLn(A);' + sLineBreak + 'end;' + sLineBreak + '' + sLineBreak +
    'procedure Put(const A: string);' + sLineBreak + 'begin' + sLineBreak +
    '  WriteLn(A);' + sLineBreak + 'end;' + sLineBreak + '' + sLineBreak +
    'procedure Run(X: Integer);' + sLineBreak + 'begin' + sLineBreak +
    '  Add([1, 2]);' + sLineBreak + '  Add([''x'']);' + sLineBreak +
    '  Put(1);' + sLineBreak + '  Put(''x'');' + sLineBreak +
    '  case X of' + sLineBreak + '    cMin..cMax: WriteLn(cMax);' + sLineBreak +
    '  end;' + sLineBreak + 'end;' + sLineBreak + '' + sLineBreak + 'end.' + sLineBreak,
    TEncoding.UTF8);
end;

// DAK-392: a plan with unprovable same-name calls is 'incomplete' and exits non-zero.
function PlanFixtureRename(const aDprojPath, aUnitPath: string; const aLine,
  aColumn: Integer; const aNewName, aExpectedStatus: string): string;
var
  lExitCode: Cardinal;
  lLogPath: string;
begin
  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-overload-range-' + aNewName + '.log');
  Assert.IsTrue(RunResolverProcess('rename --project ' + QuoteArg(aDprojPath) +
    ' --platform Win64 --file ' + QuoteArg(aUnitPath) +
    Format(' --line %d --col %d', [aLine, aColumn]) + ' --new-name ' + aNewName +
    ' --format json', RepoRoot, lLogPath, lExitCode), 'Failed to start rename command.');
  Result := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos('"status":"' + aExpectedStatus + '"', Result) > 0,
    'Expected ' + aExpectedStatus + ' status. See: ' + lLogPath);
  if SameText(aExpectedStatus, 'planned') then
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected rename dry-run to succeed. See: ' + lLogPath)
  else
    Assert.AreNotEqual(Cardinal(0), lExitCode, 'An incomplete plan must not exit 0. See: ' +
      lLogPath);
end;

function PlanHasEditAt(const aPlan: string; const aLine, aColumn: Integer): Boolean;
begin
  Result := Pos(Format('"startLine":%d,"startColumn":%d,', [aLine, aColumn]), aPlan) > 0;
end;

procedure TRefactorCommandTests.RenamePlanKeepsOverloadAndRangeBoundIdentity;
var
  lDprojPath: string;
  lPlan: string;
  lUnitPath: string;
begin
  CreateOverloadRangeFixtureProject(TPath.Combine(TempRoot, 'refactor-rename-overload-range'),
    lDprojPath, lUnitPath);

  // Without argument types a call may stay unresolved, but never belongs to the other overload.
  // DAK-392: the unresolved calls make both plans incomplete.
  lPlan := PlanFixtureRename(lDprojPath, lUnitPath, 12, 11, 'AddInts', 'incomplete');
  Assert.IsTrue(PlanHasEditAt(lPlan, 12, 11) and PlanHasEditAt(lPlan, 20, 11),
    'Integer overload declarations: ' + lPlan);
  Assert.IsFalse(PlanHasEditAt(lPlan, 13, 11) or PlanHasEditAt(lPlan, 25, 11) or
    PlanHasEditAt(lPlan, 43, 3), 'Integer rename must not touch the string overload: ' + lPlan);
  lPlan := PlanFixtureRename(lDprojPath, lUnitPath, 13, 11, 'AddStrs', 'incomplete');
  Assert.IsTrue(PlanHasEditAt(lPlan, 13, 11) and PlanHasEditAt(lPlan, 25, 11),
    'String overload declarations: ' + lPlan);
  Assert.IsFalse(PlanHasEditAt(lPlan, 12, 11) or PlanHasEditAt(lPlan, 20, 11) or
    PlanHasEditAt(lPlan, 42, 3), 'String rename must not touch the Integer overload: ' + lPlan);

  // Range separators are not member access: every bound use of cMax is renamed.
  lPlan := PlanFixtureRename(lDprojPath, lUnitPath, 7, 3, 'cTop', 'planned');
  Assert.IsTrue(PlanHasEditAt(lPlan, 7, 3) and PlanHasEditAt(lPlan, 10, 14) and
    PlanHasEditAt(lPlan, 47, 11) and PlanHasEditAt(lPlan, 47, 25),
    'Every cMax use must be planned: ' + lPlan);
  Assert.IsTrue(Pos('cMax', TFile.ReadAllText(lUnitPath, TEncoding.UTF8)) > 0,
    'Dry-run rename must not edit the fixture.');
end;

const
  // Line 8 col 5 declares FCounter.
  cMemberProviderSource =
    'unit UProv;'#13#10#13#10'interface'#13#10#13#10'type'#13#10'  TA = class'#13#10 +
    '  public'#13#10'    FCounter: Integer;'#13#10'    procedure Bump;'#13#10'  end;'#13#10#13#10 +
    'implementation'#13#10#13#10'procedure TA.Bump;'#13#10'begin'#13#10 +
    '  Self.FCounter := Self.FCounter + 1;'#13#10'  FCounter := FCounter + 1;'#13#10'end;'#13#10 +
    #13#10'end.'#13#10;

function WriteMemberRenameProject(const aRoot, aProgramText: string;
  const aUnitNames, aUnitTexts: array of string): string;
var
  i: Integer;
  lReferences: string;
begin
  ForceDirectories(aRoot);
  TFile.WriteAllText(TPath.Combine(aRoot, 'Ren.dpr'), aProgramText, TEncoding.ASCII);
  lReferences := '';
  for i := 0 to High(aUnitNames) do
  begin
    TFile.WriteAllText(TPath.Combine(aRoot, aUnitNames[i]), aUnitTexts[i], TEncoding.ASCII);
    lReferences := lReferences + '    <DCCReference Include="' + aUnitNames[i] + '"/>'#13#10;
  end;
  Result := TPath.Combine(aRoot, 'Ren.dproj');
  TFile.WriteAllText(Result,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <PropertyGroup>'#13#10 +
    '    <ProjectGuid>{5D1B7C40-2E7A-4C1B-9B21-1E6F3B0A7C11}</ProjectGuid>'#13#10 +
    '    <MainSource>Ren.dpr</MainSource>'#13#10'    <Base>True</Base>'#13#10 +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>'#13#10 +
    '    <ProjectName Condition="''$(ProjectName)''==''''">Ren</ProjectName>'#13#10 +
    '    <TargetedPlatforms>3</TargetedPlatforms>'#13#10'    <AppType>Console</AppType>'#13#10 +
    '    <FrameworkType>None</FrameworkType>'#13#10'    <ProjectVersion>20.2</ProjectVersion>'#13#10 +
    '    <Platform Condition="''$(Platform)''==''''">Win64</Platform>'#13#10 +
    '  </PropertyGroup>'#13#10'  <PropertyGroup Condition="''$(Base)''!=''''">'#13#10 +
    '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>'#13#10 +
    '    <DCC_DcuOutput>$(DCC_ExeOutput)</DCC_DcuOutput>'#13#10 +
    '    <DCC_UnitSearchPath>.;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>'#13#10 +
    '    <DCC_Namespace>System;System.Win;$(DCC_Namespace)</DCC_Namespace>'#13#10 +
    '  </PropertyGroup>'#13#10'  <ItemGroup>'#13#10 +
    '    <DelphiCompile Include="$(MainSource)">'#13#10 +
    '      <MainSource>MainSource</MainSource>'#13#10'    </DelphiCompile>'#13#10 + lReferences +
    '  </ItemGroup>'#13#10 +
    '  <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" ' +
    'Condition="Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')"/>'#13#10 + '</Project>'#13#10,
    TEncoding.ASCII);
end;

function IsWordCharAt(const aText: string; const aIndex: Integer): Boolean;
begin
  Result := (aIndex >= 1) and (aIndex <= Length(aText)) and
    CharInSet(aText[aIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// Every whole-word occurrence of aName in the fixture files, as file:line:column. The fixtures
// keep aName out of comments and string literals.
function WordOccurrenceKeys(const aRoot: string; const aFileNames: array of string;
  const aName: string): string;
var
  lColumn: Integer;
  lFileName: string;
  lKeys: TArray<string>;
  lLine: Integer;
  lText: string;
  i: Integer;
begin
  lKeys := [];
  for lFileName in aFileNames do
  begin
    lText := TFile.ReadAllText(TPath.Combine(aRoot, lFileName));
    lLine := 1;
    lColumn := 1;
    for i := 1 to Length(lText) do
    begin
      if SameText(Copy(lText, i, Length(aName)), aName) and not IsWordCharAt(lText, i - 1) and
        not IsWordCharAt(lText, i + Length(aName)) then
        lKeys := lKeys + [Format('%s:%d:%d', [LowerCase(lFileName), lLine, lColumn])];
      if lText[i] = #10 then
      begin
        Inc(lLine);
        lColumn := 1;
      end else if lText[i] <> #13 then
        Inc(lColumn);
    end;
  end;
  TArray.Sort<string>(lKeys);
  Result := string.Join(' ', lKeys);
end;

function JsonPositionKeys(const aRoot: TJSONObject; const aArrayName, aFileKey, aLineKey,
  aColumnKey: string): string;
var
  lArray: TJSONArray;
  lItem: TJSONObject;
  lKeys: TArray<string>;
  i: Integer;
begin
  RequireJsonArrayKey(aRoot, aArrayName, lArray);
  lKeys := [];
  for i := 0 to lArray.Count - 1 do
  begin
    lItem := lArray.Items[i] as TJSONObject;
    lKeys := lKeys + [Format('%s:%d:%d', [LowerCase(ExtractFileName(
      lItem.GetValue<string>(aFileKey, ''))), lItem.GetValue<Integer>(aLineKey, 0),
      lItem.GetValue<Integer>(aColumnKey, 0)])];
  end;
  TArray.Sort<string>(lKeys);
  Result := string.Join(' ', lKeys);
end;

// DS-652: a.Member, Self.Member, an inherited member, with a do Member and a program main-block
// reference are all planned; apply then builds the Win64 project.
procedure TRefactorCommandTests.RenamePlansQualifiedMemberReferencesAndAppliesWithBuild;
const
  cFiles: array[0..2] of string = ('UProv.pas', 'UCons.pas', 'Ren.dpr');
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lExpected: string;
  lFileName: string;
  lJson: TJSONObject;
  lLogPath: string;
  lRoot: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-qualified-members');
  lDprojPath := WriteMemberRenameProject(lRoot,
    'program Ren;'#13#10#13#10'{$APPTYPE CONSOLE}'#13#10#13#10'uses'#13#10 +
    '  UProv in ''UProv.pas'','#13#10'  UCons in ''UCons.pas'';'#13#10#13#10'var'#13#10 +
    '  GObj: TA;'#13#10#13#10'begin'#13#10'  GObj := TA.Create;'#13#10'  try'#13#10 +
    '    GObj.FCounter := 7;'#13#10'    Run;'#13#10'    WriteLn(GObj.FCounter);'#13#10 +
    '  finally'#13#10'    GObj.Free;'#13#10'  end;'#13#10'end.'#13#10,
    ['UProv.pas', 'UCons.pas'], [cMemberProviderSource,
    'unit UCons;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  UProv;'#13#10#13#10 +
    'type'#13#10'  TB = class(TA)'#13#10'  public'#13#10'    procedure Touch;'#13#10 +
    '  end;'#13#10#13#10'procedure Run;'#13#10#13#10'implementation'#13#10#13#10 +
    'procedure TB.Touch;'#13#10'begin'#13#10'  Self.FCounter := Self.FCounter + 3;'#13#10 +
    '  FCounter := FCounter + 1;'#13#10'end;'#13#10#13#10'procedure Run;'#13#10'var'#13#10 +
    '  a: TA;'#13#10'  b: TB;'#13#10'begin'#13#10'  a := TA.Create;'#13#10 +
    '  b := TB.Create;'#13#10'  try'#13#10'    a.FCounter := 5;'#13#10'    a.Bump;'#13#10 +
    '    with a do'#13#10'      FCounter := FCounter + 10;'#13#10'    b.Touch;'#13#10 +
    '    WriteLn(a.FCounter, '' '', b.FCounter);'#13#10'  finally'#13#10'    b.Free;'#13#10 +
    '    a.Free;'#13#10'  end;'#13#10'end;'#13#10#13#10'end.'#13#10]);
  lExpected := WordOccurrenceKeys(lRoot, cFiles, 'FCounter');
  Assert.AreEqual(16, Integer(Length(lExpected.Split([' ']))),
    'Fixture occurrence count: ' + lExpected);

  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-qualified-members-dry-run.log');
  Assert.IsTrue(RunResolverProcess('rename --project ' + QuoteArg(lDprojPath) +
    ' --platform Win64 --file ' + QuoteArg(TPath.Combine(lRoot, 'UProv.pas')) +
    ' --line 8 --col 5 --new-name FTally --format json --no-semantic-cache', RepoRoot,
    lLogPath, lExitCode), 'Failed to start rename command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected a complete plan. See: ' + lLogPath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
  try
    Assert.AreEqual('planned', lJson.GetValue<string>('status', ''), lLogPath);
    Assert.AreEqual(lExpected, JsonPositionKeys(lJson, 'edits', 'file', 'startLine',
      'startColumn'), lLogPath);
    Assert.AreEqual(0, lJson.GetValue<Integer>('unresolvedCount', -1), lLogPath);
  finally
    lJson.Free;
  end;

  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-qualified-members-apply.log');
  Assert.IsTrue(RunResolverProcess('rename --project ' + QuoteArg(lDprojPath) +
    ' --file ' + QuoteArg(TPath.Combine(lRoot, 'UProv.pas')) +
    ' --line 8 --col 5 --new-name FTally --apply --format json --no-semantic-cache' +
    ' --delphi 23.0 --platform Win64 --config Debug', RepoRoot, lLogPath, lExitCode),
    'Failed to start rename apply command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected apply with build to pass. See: ' + lLogPath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
  try
    Assert.AreEqual('applied', lJson.GetValue<string>('status', ''), lLogPath);
    Assert.AreEqual('passed', lJson.GetValue<string>('verification.status', ''), lLogPath);
  finally
    lJson.Free;
  end;
  for lFileName in cFiles do
    Assert.AreEqual('', WordOccurrenceKeys(lRoot, [lFileName], 'FCounter'),
      'Apply must leave no old name in ' + lFileName);
  Assert.AreEqual(16, Integer(Length(WordOccurrenceKeys(lRoot, cFiles, 'FTally').Split([' ']))),
    'Every planned site carries the new name.');
end;

// DAK-392: the open-array calls on lines 42 and 43 cannot be bound to an Add overload, so the
// dry-run lists them and apply refuses without touching the source.
procedure TRefactorCommandTests.RenameListsUnresolvedOverloadCallsAndRefusesApply;
var
  lApplied: TJSONArray;
  lDprojPath: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lLogPath: string;
  lSourceHash: string;
  lUnitPath: string;
  lUnresolved: TJSONArray;
  i: Integer;
begin
  EnsureResolverBuilt;
  CreateOverloadRangeFixtureProject(TPath.Combine(TempRoot, 'refactor-rename-unresolved-overload'),
    lDprojPath, lUnitPath);
  lSourceHash := THashSHA2.GetHashStringFromFile(lUnitPath);

  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-unresolved-overload-dry-run.log');
  Assert.IsTrue(RunResolverProcess('rename --project ' + QuoteArg(lDprojPath) +
    ' --platform Win64 --file ' + QuoteArg(lUnitPath) + ' --line 12 --col 11' +
    ' --new-name AddInts --format json --no-semantic-cache', RepoRoot, lLogPath, lExitCode),
    'Failed to start rename command.');
  Assert.AreNotEqual(Cardinal(0), lExitCode, 'An incomplete plan must not exit 0. See: ' + lLogPath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
  try
    Assert.AreEqual('incomplete', lJson.GetValue<string>('status', ''), lLogPath);
    Assert.AreEqual(2, lJson.GetValue<Integer>('unresolvedCount', -1), lLogPath);
    Assert.AreEqual('overloadrange.pas:42:3 overloadrange.pas:43:3',
      JsonPositionKeys(lJson, 'unresolved', 'file', 'line', 'column'), lLogPath);
    RequireJsonArrayKey(lJson, 'unresolved', lUnresolved);
    for i := 0 to lUnresolved.Count - 1 do
    begin
      Assert.AreEqual('unresolved-reference',
        (lUnresolved.Items[i] as TJSONObject).GetValue<string>('reason', ''), lLogPath);
      Assert.AreEqual('unresolved',
        (lUnresolved.Items[i] as TJSONObject).GetValue<string>('role', ''), lLogPath);
    end;
    Assert.AreEqual('overloadrange.pas:12:11 overloadrange.pas:20:11',
      JsonPositionKeys(lJson, 'edits', 'file', 'startLine', 'startColumn'), lLogPath);
  finally
    lJson.Free;
  end;

  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-unresolved-overload-apply.log');
  Assert.IsTrue(RunResolverProcess('rename --project ' + QuoteArg(lDprojPath) +
    ' --platform Win64 --file ' + QuoteArg(lUnitPath) + ' --line 12 --col 11' +
    ' --new-name AddInts --apply --format json --no-semantic-cache', RepoRoot, lLogPath,
    lExitCode), 'Failed to start rename apply command.');
  Assert.AreNotEqual(Cardinal(0), lExitCode, 'Apply must refuse. See: ' + lLogPath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
  try
    Assert.AreEqual('incomplete', lJson.GetValue<string>('status', ''), lLogPath);
    Assert.IsTrue(StartsText('Rename apply refused:', lJson.GetValue<string>('diagnostic', '')),
      lLogPath);
    Assert.AreEqual('not-run', lJson.GetValue<string>('verification.status', ''), lLogPath);
    RequireJsonArrayKey(lJson, 'appliedFiles', lApplied);
    Assert.AreEqual(0, lApplied.Count, 'A refused apply writes no backup. See: ' + lLogPath);
  finally
    lJson.Free;
  end;
  Assert.AreEqual(lSourceHash, THashSHA2.GetHashStringFromFile(lUnitPath),
    'A refused apply must not change the source.');
end;

function RunMemberRenameJson(const aDprojPath, aFilePath: string; const aLine, aColumn: Integer;
  const aNewName, aExtraArgs, aLogName: string; out aExitCode: Cardinal): TJSONObject;
var
  lLogPath: string;
begin
  lLogPath := TPath.Combine(TempRoot, aLogName);
  Assert.IsTrue(RunResolverProcess('rename --project ' + QuoteArg(aDprojPath) +
    ' --platform Win64 --file ' + QuoteArg(aFilePath) + Format(' --line %d --col %d',
    [aLine, aColumn]) + ' --new-name ' + aNewName + ' --format json --no-semantic-cache' +
    aExtraArgs, RepoRoot, lLogPath, aExitCode), 'Failed to start rename command.');
  Result := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
end;

// DS-652 review shapes. TA.Limit is a class constant the model does not record, so the with-body
// Limit (UC2 21:14) may be TA.Limit; TComponent may declare Name, so WriteLn(Name) in TK.Go
// (UA2 28:11) may be TComponent.Name; whitespace in Run (UC2 22:1) names no symbol.
procedure TRefactorCommandTests.RenameRefusesUnprovenMemberAndPositionBindings;
var
  lConsPath: string;
  lConsHash: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lProvPath: string;
  lProvHash: string;
  lRoot: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-unproven-members');
  lDprojPath := WriteMemberRenameProject(lRoot,
    'program Ren;'#13#10'{$APPTYPE CONSOLE}'#13#10'uses'#13#10'  UA2 in ''UA2.pas'','#13#10 +
    '  UC2 in ''UC2.pas'';'#13#10'begin'#13#10'  Run;'#13#10'end.'#13#10, ['UA2.pas', 'UC2.pas'],
    ['unit UA2;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  System.Classes;'#13#10#13#10 +
    'type'#13#10'  TA = class'#13#10'  public const'#13#10'    Limit = 5;'#13#10'  public'#13#10 +
    '    Count: Integer;'#13#10'  end;'#13#10#13#10'  TK = class(TComponent)'#13#10 +
    '  public'#13#10'    procedure Go;'#13#10'  end;'#13#10#13#10'var'#13#10 +
    '  Name: string = ''global'';'#13#10#13#10'implementation'#13#10#13#10'procedure TK.Go;'#13#10 +
    'begin'#13#10'  WriteLn(Name);'#13#10'end;'#13#10#13#10'end.'#13#10,
    'unit UC2;'#13#10#13#10'interface'#13#10#13#10'procedure Run;'#13#10#13#10 +
    'implementation'#13#10#13#10'uses'#13#10'  System.Classes, UA2;'#13#10#13#10 +
    'procedure Run;'#13#10'var'#13#10'  a: TA;'#13#10'  Limit: Integer;'#13#10'  k: TK;'#13#10 +
    'begin'#13#10'  Limit := 100;'#13#10'  a := TA.Create;'#13#10'  with a do'#13#10 +
    '    Count := Limit;'#13#10'  WriteLn(a.Count);'#13#10'  k := TK.Create(nil);'#13#10 +
    '  k.Name := ''comp'';'#13#10'  k.Go;'#13#10'  with k do'#13#10'    WriteLn(Name);'#13#10 +
    'end;'#13#10#13#10'end.'#13#10]);
  lProvPath := TPath.Combine(lRoot, 'UA2.pas');
  lConsPath := TPath.Combine(lRoot, 'UC2.pas');
  lProvHash := THashSHA2.GetHashStringFromFile(lProvPath);
  lConsHash := THashSHA2.GetHashStringFromFile(lConsPath);

  lJson := RunMemberRenameJson(lDprojPath, lConsPath, 15, 3, 'LimX', ' --apply --delphi 23.0' +
    ' --config Debug', 'refactor-rename-unproven-limit.log', lExitCode);
  try
    Assert.AreNotEqual(Cardinal(0), lExitCode, lJson.ToJSON);
    Assert.AreEqual('incomplete', lJson.GetValue<string>('status', ''), lJson.ToJSON);
    Assert.AreEqual('uc2.pas:15:3 uc2.pas:18:3', JsonPositionKeys(lJson, 'edits', 'file',
      'startLine', 'startColumn'), lJson.ToJSON);
    Assert.AreEqual('uc2.pas:21:14', JsonPositionKeys(lJson, 'unresolved', 'file', 'line',
      'column'), lJson.ToJSON);
  finally
    lJson.Free;
  end;

  lJson := RunMemberRenameJson(lDprojPath, lProvPath, 22, 3, 'GName', ' --apply --delphi 23.0' +
    ' --config Debug', 'refactor-rename-unproven-name.log', lExitCode);
  try
    Assert.AreNotEqual(Cardinal(0), lExitCode, lJson.ToJSON);
    Assert.AreEqual('incomplete', lJson.GetValue<string>('status', ''), lJson.ToJSON);
    Assert.AreEqual('ua2.pas:22:3', JsonPositionKeys(lJson, 'edits', 'file', 'startLine',
      'startColumn'), lJson.ToJSON);
    Assert.IsTrue(ContainsText(JsonPositionKeys(lJson, 'unresolved', 'file', 'line', 'column'),
      'ua2.pas:28:11'), lJson.ToJSON);
  finally
    lJson.Free;
  end;

  lJson := RunMemberRenameJson(lDprojPath, lConsPath, 22, 1, 'Zz', '',
    'refactor-rename-unproven-whitespace.log', lExitCode);
  try
    Assert.AreNotEqual(Cardinal(0), lExitCode, lJson.ToJSON);
    Assert.AreEqual('blocked', lJson.GetValue<string>('status', ''), lJson.ToJSON);
    Assert.AreEqual(0, lJson.GetValue<Integer>('editCount', -1), lJson.ToJSON);
  finally
    lJson.Free;
  end;

  Assert.AreEqual(lProvHash, THashSHA2.GetHashStringFromFile(lProvPath), 'Refused apply edited UA2.');
  Assert.AreEqual(lConsHash, THashSHA2.GetHashStringFromFile(lConsPath), 'Refused apply edited UC2.');
end;

// DS-652 review round 2: ti.inc adds "public const ILimit = 7;" to TI. dcc64 binds the with-body
// ILimit (UC3 20:14) to TI.ILimit, so renaming the local must be refused, not applied.
procedure TRefactorCommandTests.RenameRefusesWithBodyNameFromIncludedMember;
var
  lConsHash: string;
  lConsPath: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lRoot: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-included-member');
  lDprojPath := WriteMemberRenameProject(lRoot,
    'program Ren;'#13#10'{$APPTYPE CONSOLE}'#13#10'uses'#13#10'  UA3 in ''UA3.pas'','#13#10 +
    '  UC3 in ''UC3.pas'';'#13#10'begin'#13#10'  Run;'#13#10'end.'#13#10, ['UA3.pas', 'UC3.pas'],
    ['unit UA3;'#13#10#13#10'interface'#13#10#13#10'type'#13#10'  TI = class'#13#10 +
    '  public'#13#10'    Count: Integer;'#13#10'{$I ti.inc}'#13#10'  end;'#13#10#13#10 +
    'implementation'#13#10#13#10'end.'#13#10,
    'unit UC3;'#13#10#13#10'interface'#13#10#13#10'procedure Run;'#13#10#13#10 +
    'implementation'#13#10#13#10'uses'#13#10'  UA3;'#13#10#13#10'procedure Run;'#13#10 +
    'var'#13#10'  i: TI;'#13#10'  ILimit: Integer;'#13#10'begin'#13#10'  ILimit := 200;'#13#10 +
    '  i := TI.Create;'#13#10'  with i do'#13#10'    Count := ILimit;'#13#10 +
    '  WriteLn(i.Count);'#13#10'end;'#13#10#13#10'end.'#13#10]);
  TFile.WriteAllText(TPath.Combine(lRoot, 'ti.inc'), '  public const'#13#10'    ILimit = 7;'#13#10,
    TEncoding.ASCII);
  lConsPath := TPath.Combine(lRoot, 'UC3.pas');
  lConsHash := THashSHA2.GetHashStringFromFile(lConsPath);

  lJson := RunMemberRenameJson(lDprojPath, lConsPath, 15, 3, 'LimX', ' --apply --delphi 23.0' +
    ' --config Debug', 'refactor-rename-included-member.log', lExitCode);
  try
    Assert.AreNotEqual(Cardinal(0), lExitCode, lJson.ToJSON);
    Assert.AreEqual('incomplete', lJson.GetValue<string>('status', ''), lJson.ToJSON);
    Assert.AreEqual('uc3.pas:15:3 uc3.pas:17:3', JsonPositionKeys(lJson, 'edits', 'file',
      'startLine', 'startColumn'), lJson.ToJSON);
    Assert.AreEqual('uc3.pas:20:14', JsonPositionKeys(lJson, 'unresolved', 'file', 'line',
      'column'), lJson.ToJSON);
  finally
    lJson.Free;
  end;
  Assert.AreEqual(lConsHash, THashSHA2.GetHashStringFromFile(lConsPath), 'Refused apply edited UC3.');
end;

// DS-652 review round 4 (rn652k shape): "with c do X := CVar" over c: TAClass (class of TA) binds
// CVar (UC4 38:10) to TA.CVar, so renaming the local CVar (declared 23:19, targeted at its use
// 27:3) must be refused.
procedure TRefactorCommandTests.RenameRefusesWithBodyNameOfClassReferenceSelector;
var
  lConsHash: string;
  lConsPath: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lRoot: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-class-reference');
  lDprojPath := WriteMemberRenameProject(lRoot,
    'program Ren;'#13#10'{$APPTYPE CONSOLE}'#13#10'uses'#13#10'  UA4 in ''UA4.pas'','#13#10 +
    '  UC4 in ''UC4.pas'';'#13#10'begin'#13#10'  Run;'#13#10'end.'#13#10, ['UA4.pas', 'UC4.pas'],
    ['unit UA4;'#13#10#13#10'interface'#13#10#13#10'type'#13#10'  TBase = class'#13#10 +
    '  public'#13#10'{$I base.inc}'#13#10'  end;'#13#10#13#10'  TR = record'#13#10 +
    '    A: Integer;'#13#10'{$I rec.inc}'#13#10'    B: Integer;'#13#10'  end;'#13#10#13#10 +
    '  TA = class'#13#10'  public'#13#10'    class var CVar: Integer;'#13#10'  end;'#13#10#13#10 +
    '  TAClass = class of TA;'#13#10#13#10'implementation'#13#10#13#10'end.'#13#10,
    'unit UC4;'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  UA4;'#13#10#13#10'type'#13#10 +
    '  TDer = class(TBase)'#13#10'  public'#13#10'    Count: Integer;'#13#10'  end;'#13#10#13#10 +
    'procedure Run;'#13#10#13#10'implementation'#13#10#13#10'procedure Run;'#13#10'var'#13#10 +
    '  d: TDer;'#13#10'  r: TR;'#13#10'  c: TAClass;'#13#10 +
    '  BLimit, RLimit, CVar, X: Integer;'#13#10'begin'#13#10'  BLimit := 100;'#13#10 +
    '  RLimit := 200;'#13#10'  CVar := 300;'#13#10'  TA.CVar := 3;'#13#10 +
    '  d := TDer.Create;'#13#10'  d.BLimit := 1;'#13#10'  r.RLimit := 2;'#13#10'  c := TA;'#13#10 +
    '  with d do'#13#10'    Count := BLimit;'#13#10'  with r do'#13#10'    A := RLimit;'#13#10 +
    '  with c do'#13#10'    X := CVar;'#13#10'  WriteLn(d.Count, '' '', r.A, '' '', X);'#13#10 +
    'end;'#13#10#13#10'end.'#13#10]);
  TFile.WriteAllText(TPath.Combine(lRoot, 'base.inc'), '    BLimit: Integer;'#13#10,
    TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lRoot, 'rec.inc'), '    RLimit: Integer;'#13#10,
    TEncoding.ASCII);
  lConsPath := TPath.Combine(lRoot, 'UC4.pas');
  lConsHash := THashSHA2.GetHashStringFromFile(lConsPath);

  lJson := RunMemberRenameJson(lDprojPath, lConsPath, 27, 3, 'CTally', ' --apply --delphi 23.0' +
    ' --config Debug', 'refactor-rename-class-reference.log', lExitCode);
  try
    Assert.AreNotEqual(Cardinal(0), lExitCode, lJson.ToJSON);
    Assert.AreEqual('incomplete', lJson.GetValue<string>('status', ''), lJson.ToJSON);
    Assert.AreEqual('uc4.pas:23:19 uc4.pas:27:3', JsonPositionKeys(lJson, 'edits', 'file',
      'startLine', 'startColumn'), lJson.ToJSON);
    Assert.AreEqual('uc4.pas:38:10', JsonPositionKeys(lJson, 'unresolved', 'file', 'line',
      'column'), lJson.ToJSON);
  finally
    lJson.Free;
  end;
  Assert.AreEqual(lConsHash, THashSHA2.GetHashStringFromFile(lConsPath), 'Refused apply edited UC4.');
end;

// DS-652: UBad compiles, but its syntax tree fails (one-character deprecation message), so its
// a.FCounter cannot be proven either way.
procedure TRefactorCommandTests.RenameListsAstFailedConsumerReferences;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lLogPath: string;
  lRoot: string;
  lUnresolved: TJSONArray;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'refactor-rename-ast-failed-consumer');
  lDprojPath := WriteMemberRenameProject(lRoot,
    'program Ren;'#13#10'uses'#13#10'  UProv in ''UProv.pas'','#13#10 +
    '  UBad in ''UBad.pas'';'#13#10'begin'#13#10'end.'#13#10, ['UProv.pas', 'UBad.pas'],
    [cMemberProviderSource,
    'unit UBad;'#13#10'interface'#13#10'uses'#13#10'  UProv;'#13#10'type'#13#10 +
    '  TBad = class'#13#10'  public'#13#10'    procedure Y; deprecated ''z'';'#13#10 +
    '  end;'#13#10'procedure UseIt(a: TA);'#13#10'implementation'#13#10 +
    'procedure TBad.Y;'#13#10'begin'#13#10'end;'#13#10'procedure UseIt(a: TA);'#13#10 +
    'begin'#13#10'  a.FCounter := 9;'#13#10'end;'#13#10'end.'#13#10]);

  lLogPath := TPath.Combine(TempRoot, 'refactor-rename-ast-failed-consumer.log');
  Assert.IsTrue(RunResolverProcess('rename --project ' + QuoteArg(lDprojPath) +
    ' --platform Win64 --file ' + QuoteArg(TPath.Combine(lRoot, 'UProv.pas')) +
    ' --line 8 --col 5 --new-name FTally --format json --no-semantic-cache', RepoRoot,
    lLogPath, lExitCode), 'Failed to start rename command.');
  Assert.AreNotEqual(Cardinal(0), lExitCode, 'An incomplete plan must not exit 0. See: ' + lLogPath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
  try
    Assert.AreEqual('incomplete', lJson.GetValue<string>('status', ''), lLogPath);
    Assert.AreEqual('ubad.pas:17:5', JsonPositionKeys(lJson, 'unresolved', 'file', 'line',
      'column'), lLogPath);
    RequireJsonArrayKey(lJson, 'unresolved', lUnresolved);
    Assert.AreEqual('unverified-unit',
      (lUnresolved.Items[0] as TJSONObject).GetValue<string>('reason', ''), lLogPath);
    Assert.AreEqual(WordOccurrenceKeys(lRoot, ['UProv.pas'], 'FCounter'),
      JsonPositionKeys(lJson, 'edits', 'file', 'startLine', 'startColumn'), lLogPath);
  finally
    lJson.Free;
  end;
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
    'src\dak.deps.runner.pas', 'src\Dak.Refactor.pas', 'src\Dak.RemoveWith.Transaction.pas',
    'src\dak.dfmcheck.pas', 'src\Dak.Refactor.Transaction.pas', 'src\Dak.Signature.Command.pas'] do
  begin
    lCommandSource := TFile.ReadAllText(TPath.Combine(RepoRoot, lPath), TEncoding.UTF8);
    Assert.IsTrue(ContainsText(lCommandSource, 'Dak.Paths'),
      lPath + ' should use the shared project-local path helper.');
    Assert.IsFalse(ContainsText(lCommandSource, 'TPath.Combine(TPath.Combine') and
      ContainsText(lCommandSource, '''.dak'''),
      lPath + ' must not construct project-local .dak roots with nested TPath.Combine calls.');
  end;

  // DAK-385 moved remove-with's workspace construction to Dak.RemoveWith.Transaction (TryCreateRemoveWithWorkspace);
  // the command unit must not build .dak paths itself.
  lCommandSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.pas'), TEncoding.UTF8);
  Assert.IsFalse(ContainsText(lCommandSource, '''.dak'),
    'src\Dak.RemoveWith.pas must not construct project-local .dak paths; use Dak.RemoveWith.Transaction.');

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
