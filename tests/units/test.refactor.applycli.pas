unit Test.Refactor.ApplyCli;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRefactorApplyCliTests = class
  private
    procedure CheckDirectCompilerApply(const aFailPostBuild: Boolean);
  public
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsUnsupportedArtifactVersion;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsIncompleteVersionOneArtifact;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsMissingArtifact;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsDuplicateHeaderKey;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsInvalidUtf8Artifact;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsMalformedNestedPlan;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsIncompleteArtifactBeforeVerifier;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsStatusEditCountMismatch;
    [Test]
    [Category('RefactoringLightApply')]
    procedure ValidShapeStillRequiresFeatureVerifier;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsMalformedScope;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsIncorrectSummaryCounts;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsMissingRequiredVerification;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectsDuplicateNestedKey;
    [Test]
    [Category('RefactoringLightApply')]
    procedure WriterRetainsEveryPlannedEdit;
    [Test]
    [Category('RefactoringLightApply')]
    procedure WriterRejectsInvalidRequestJson;
    [Test]
    [Category('RefactoringLightApply')]
    procedure ExactPlanComparisonRejectsDrift;
    [Test]
    [Category('RefactoringLightApply')]
    procedure KnownUsesOperationReplansAndRejectsForgedArtifact;
    [Test]
    [Category('RefactoringLightApply')]
    procedure UsesPlanRoundTripAppliesFreshArtifact;
    [Test]
    [Category('RefactoringLightApply')]
    procedure DirectCompilerArtifactRunsBaselineAndPostBuild;
    [Test]
    [Category('RefactoringLightApply')]
    procedure DirectCompilerPostBuildFailureRestoresOriginalBytes;
    [Test]
    [Category('RefactoringLightApply')]
    procedure RejectedUsesRequestsDoNotCreateArtifact;
    [Test]
    [Category('RefactoringLightApply')]
    procedure FailedArtifactWriteRemovesOnlyNewOutput;
    [Test]
    [Category('RefactoringLightUses')]
    [TestCase('Unique', 'AlphaOnlyValue,1')]
    [TestCase('Ambiguous', 'SharedValue,2')]
    [TestCase('Missing', 'MissingValue,0')]
    procedure ReportsExplicitImportCandidates(const aIdentifier: string; aExpected: Integer);
  end;

implementation

uses
  System.Hash, System.IOUtils, System.JSON, System.StrUtils, System.SysUtils,
  AutoFree,
  DelphiSemantics.Refactor.Plan,
  Dak.RadStudio.Locator, Dak.Refactor.ApplyCommand, Dak.Refactor.Artifact,
  Test.Support;

procedure TRefactorApplyCliTests.ReportsExplicitImportCandidates(const aIdentifier: string; aExpected: Integer);
var
  g: TGarbos;
  lDirectory, lConsumer, lProject, lRequestPath, lLog, lSource, lText, lArguments: string;
  lExit: Cardinal;
  lRequest, lReport: TJSONObject;
  lCandidates: TJSONArray;
begin
  lDirectory := TPath.Combine(RepoRoot, 'tests\.dak\DelphiAIKit.Tests\refactoring-light-uses\' +
    TGUID.NewGuid.ToString);
  ForceDirectories(lDirectory);
  lConsumer := TPath.Combine(lDirectory, 'UsesConsumer.pas');
  lSource := 'unit UsesConsumer;'#13#10'interface'#13#10'implementation'#13#10 +
    'function ReadValues: Integer; begin Result := ' + aIdentifier + '; end;'#13#10'end.';
  TFile.WriteAllText(lConsumer, lSource, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lDirectory, 'ProviderAlpha.pas'),
    'unit ProviderAlpha; interface const AlphaOnlyValue = 1; SharedValue = 2; implementation end.', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lDirectory, 'ProviderBeta.pas'),
    'unit ProviderBeta; interface const SharedValue = 3; implementation end.', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lDirectory, 'UsesProject.dpr'),
    'program UsesProject; uses UsesConsumer, ProviderAlpha, ProviderBeta; begin end.', TEncoding.UTF8);
  lProject := TPath.Combine(lDirectory, 'UsesProject.dproj');
  TFile.WriteAllText(lProject,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>UsesProject.dpr</MainSource></PropertyGroup>' +
    '<ItemGroup><DCCReference Include="UsesConsumer.pas"/>' +
    '<DCCReference Include="ProviderAlpha.pas"/><DCCReference Include="ProviderBeta.pas"/>' +
    '</ItemGroup></Project>', TEncoding.UTF8);
  lRequest := TJSONObject.Create;
  GC(lRequest, g);
  lRequest.AddPair('operation', 'uses.suggest-explicit-import-candidates');
  lRequest.AddPair('consumerFileName', lConsumer);
  lRequest.AddPair('identifier', aIdentifier);
  lRequestPath := TPath.Combine(lDirectory, 'request.json');
  TFile.WriteAllText(lRequestPath, lRequest.ToJSON, TEncoding.UTF8);
  lLog := TPath.Combine(lDirectory, 'report.json');
  lArguments := 'uses --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --format json --request ' + QuoteArg(lRequestPath);
  Assert.IsTrue(RunResolverProcess(lArguments, RepoRoot, lLog, lExit));
  lText := TFile.ReadAllText(lLog, TEncoding.UTF8);
  if aExpected > 0 then
    Assert.AreEqual(Cardinal(0), lExit, lText)
  else
    Assert.AreEqual(Cardinal(3), lExit, lText);
  lReport := TJSONObject.ParseJSONValue(lText) as TJSONObject;
  GC(lReport, g);
  Assert.IsNotNull(lReport);
  Assert.AreEqual(1, lReport.GetValue<Integer>('schemaVersion'));
  Assert.AreEqual('uses.suggest-explicit-import-candidates', lReport.GetValue<string>('operation'));
  Assert.IsFalse(lReport.GetValue<Boolean>('applicable'));
  Assert.AreEqual(0, lReport.GetValue<TJSONArray>('artifacts').Count);
  lCandidates := lReport.GetValue<TJSONArray>('candidateUnitNames');
  Assert.AreEqual(aExpected, lCandidates.Count);
  Assert.AreEqual(0, lReport.GetValue<TJSONObject>('summary').GetValue<Integer>('editCount'));
  if aExpected > 0 then
  begin
    Assert.AreEqual('ok', lReport.GetValue<string>('status'));
    Assert.AreEqual('ProviderAlpha', lCandidates.Items[0].Value);
    Assert.IsTrue(lReport.GetValue<TJSONObject>('scope').GetValue<Boolean>('complete'));
    Assert.IsTrue(lReport.GetValue<string>('contextFingerprint') <> '');
  end else
    Assert.AreEqual('uses.no-source-backed-candidate', lReport.GetValue<string>('reason'));
  if aExpected = 2 then
    Assert.AreEqual('ProviderBeta', lCandidates.Items[1].Value);
  Assert.AreEqual(lSource, TFile.ReadAllText(lConsumer, TEncoding.UTF8));
  // A report is not a saved edit plan, even when discovery found one provider.
  Assert.IsTrue(RunResolverProcess(lArguments + ' --plan-out ' +
    QuoteArg(TPath.Combine(lDirectory, 'forbidden-plan.json')), RepoRoot, lLog, lExit));
  Assert.AreEqual(Cardinal(3), lExit, TFile.ReadAllText(lLog, TEncoding.UTF8));
  Assert.IsFalse(TFile.Exists(TPath.Combine(lDirectory, 'forbidden-plan.json')));
  Assert.AreEqual(lSource, TFile.ReadAllText(lConsumer, TEncoding.UTF8));
end;

function CanonicalArtifactJson(const aScopeJson: string): string;
begin
  Result :=
    '{"schemaVersion":1,"operation":"unknown.test","status":"no-change",' +
    '"contextFingerprint":"context","bindingFingerprint":"binding",' +
    '"request":{"selector":"C:\\sample.pas:1:1"},"scope":' + aScopeJson + ',' +
    '"diagnostics":[],"summary":{"sourceCount":1,"editCount":0,' +
    '"diagnosticCount":0,"omittedResultCount":0},' +
    '"sources":[{"fileName":"C:\\sample.pas","contentHash":"hash",' +
    '"includeGraphHash":"include"}],"edits":[],' +
    '"verification":{"freshContextRevalidation":true,' +
    '"sameIntentFeatureReplan":true,"baselineBuild":true,' +
    '"postEditBuild":true,"focusedChecks":[]}}';
end;

function CanonicalScopeJson: string;
begin
  Result := '{"selectedConfigurations":["Debug|Win64"],' +
    '"scopeRoots":["C:\\sample.pas"],"expectedRoots":["C:\\sample.pas"],' +
    '"analyzedRoots":["C:\\sample.pas"],"requiredAnalysisKinds":["body"]}';
end;

procedure TRefactorApplyCliTests.RejectsUnsupportedArtifactVersion;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\unsupported-version');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  TFile.WriteAllText(lArtifact, '{"schemaVersion":999}', TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.unsupported-version'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsIncompleteVersionOneArtifact;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\incomplete-v1');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  TFile.WriteAllText(lArtifact, '{"schemaVersion":1}', TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.malformed'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsMissingArtifact;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\missing');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, TGUID.NewGuid.ToString + '.json');
  Assert.IsFalse(TFile.Exists(lArtifact), 'Test fixture must start without an artifact');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.missing'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsDuplicateHeaderKey;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\duplicate-key');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  TFile.WriteAllText(lArtifact, '{"schemaVersion":1,"schemaVersion":999}', TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.malformed'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsInvalidUtf8Artifact;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\invalid-utf8');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  TFile.WriteAllBytes(lArtifact, TBytes.Create($7B, $22, $C3, $28, $22, $7D));
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.invalid-utf8'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsMalformedNestedPlan;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\malformed-nested');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  TFile.WriteAllText(lArtifact,
    '{"schemaVersion":1,"operation":"uses.remove","status":"complete",' +
    '"contextFingerprint":"context","request":{},"scope":' + CanonicalScopeJson + ',' +
    '"diagnostics":[],"summary":{},"sources":[{}],"edits":[{}],' +
    '"verification":{}}', TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.malformed'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsIncompleteArtifactBeforeVerifier;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lJson: string;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\incomplete-status');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  lJson := StringReplace(CanonicalArtifactJson(CanonicalScopeJson),
    '"status":"no-change"', '"status":"incomplete"', []);
  TFile.WriteAllText(lArtifact, lJson, TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.incomplete'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsStatusEditCountMismatch;
var
  lArtifact: string;
  lDirectory: string;
  lEdits: string;
  lExitCode: Cardinal;
  lJson: string;
  lLog: string;
  lOutput: string;
  lProject: string;
  lStatus: string;
  i: Integer;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\status-edit-mismatch');
  ForceDirectories(lDirectory);
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  for i := 0 to 1 do
  begin
    if i = 0 then
      lStatus := 'complete'
    else begin
      lStatus := 'no-change';
      lEdits := '[{"fileName":"C:\\sample.pas","startLine":1,' +
        '"startColumn":1,"endLine":1,"endColumn":2,' +
        '"expectedText":"a","replacementText":"b"}]';
    end;
    lArtifact := TPath.Combine(lDirectory, lStatus + '.json');
    lLog := TPath.Combine(lDirectory, lStatus + '.log');
    lJson := CanonicalArtifactJson(CanonicalScopeJson);
    if i = 0 then
      lJson := StringReplace(lJson, '"status":"no-change"',
        '"status":"complete"', [])
    else begin
      lJson := StringReplace(lJson, '"editCount":0', '"editCount":1', []);
      lJson := StringReplace(lJson, '"edits":[]', '"edits":' + lEdits, []);
    end;
    TFile.WriteAllText(lArtifact, lJson, TEncoding.UTF8);
    Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
      ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
      RepoRoot, lLog, lExitCode));
    Assert.AreNotEqual(Cardinal(0), lExitCode);
    lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
    Assert.IsTrue(ContainsText(lOutput, 'artifact.malformed'), lStatus + ': ' + lOutput);
  end;
end;

procedure TRefactorApplyCliTests.ValidShapeStillRequiresFeatureVerifier;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\valid-unknown-operation');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  TFile.WriteAllText(lArtifact, CanonicalArtifactJson(CanonicalScopeJson), TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'operation.verifier-unavailable'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsMalformedScope;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\malformed-scope');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  TFile.WriteAllText(lArtifact, CanonicalArtifactJson('{}'), TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.malformed'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsIncorrectSummaryCounts;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lJson: string;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\incorrect-summary');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  lJson := StringReplace(CanonicalArtifactJson(CanonicalScopeJson),
    '"sourceCount":1', '"sourceCount":2', []);
  TFile.WriteAllText(lArtifact, lJson, TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.malformed'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsMissingRequiredVerification;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lJson: string;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\missing-verification');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  lJson := StringReplace(CanonicalArtifactJson(CanonicalScopeJson),
    '"postEditBuild":true', '"postEditBuild":false', []);
  TFile.WriteAllText(lArtifact, lJson, TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.malformed'), lOutput);
end;

procedure TRefactorApplyCliTests.RejectsDuplicateNestedKey;
var
  lArtifact: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lJson: string;
  lLog: string;
  lOutput: string;
  lProject: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\duplicate-nested-key');
  ForceDirectories(lDirectory);
  lArtifact := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'command.log');
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  lJson := StringReplace(CanonicalArtifactJson(CanonicalScopeJson),
    '"selector":"C:\\sample.pas:1:1"',
    '"selector":"C:\\sample.pas:1:1","selector":"C:\\other.pas:1:1"', []);
  TFile.WriteAllText(lArtifact, lJson, TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lArtifact),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.malformed'), lOutput);
end;

procedure TRefactorApplyCliTests.WriterRetainsEveryPlannedEdit;
var
  lArtifact: TRefactoringArtifact;
  lArtifactPath: string;
  lDirectory: string;
  lEdit: TSemanticPlanEdit;
  lEdits: TJSONArray;
  lJson: string;
  lReason: string;
  lRoot: TJSONObject;
  lRoundTrip: TRefactoringArtifact;
  lSource: TRefactoringArtifactSource;
begin
  lArtifact := Default(TRefactoringArtifact);
  lArtifact.Operation := 'uses.remove';
  lArtifact.Status := 'complete';
  lArtifact.ContextFingerprint := 'context';
  lArtifact.BindingFingerprint := 'binding';
  lArtifact.RequestJson := '{"unit":"QuietLeaf"}';
  lArtifact.SelectedConfigurations := ['Debug|Win64'];
  lArtifact.ScopeRoots := ['C:\source.pas'];
  lArtifact.ExpectedRoots := ['C:\source.pas'];
  lArtifact.AnalyzedRoots := ['C:\source.pas'];
  lArtifact.RequiredAnalysisKinds := ['body', 'references'];
  lArtifact.Diagnostics := ['uses.proven-safe'];
  lArtifact.OmittedResultCount := 3;
  lArtifact.FocusedChecks := ['fixture.run'];
  lSource := Default(TRefactoringArtifactSource);
  lSource.FileName := 'C:\source.pas';
  lSource.ContentHash := 'hash';
  lSource.IncludeGraphHash := 'include';
  lArtifact.Sources := [lSource];
  lEdit := Default(TSemanticPlanEdit);
  lEdit.FileName := lSource.FileName;
  lEdit.StartLine := 1;
  lEdit.StartColumn := 1;
  lEdit.EndLine := 1;
  lEdit.EndColumn := 5;
  lEdit.ExpectedText := 'uses';
  lEdit.ReplacementText := '';
  SetLength(lArtifact.Edits, 2);
  lArtifact.Edits[0] := lEdit;
  lEdit.StartLine := 2;
  lEdit.EndLine := 2;
  lEdit.ExpectedText := 'Leaf';
  lEdit.ReplacementText := 'Other';
  lArtifact.Edits[1] := lEdit;

  Assert.IsTrue(TryWriteRefactoringArtifactJson(lArtifact, lJson, lReason), lReason);
  lRoot := TJSONObject.ParseJSONValue(lJson) as TJSONObject;
  try
    Assert.IsNotNull(lRoot);
    Assert.AreEqual('uses.remove', lRoot.GetValue<string>('operation'));
    Assert.AreEqual('QuietLeaf',
      (lRoot.GetValue('request') as TJSONObject).GetValue<string>('unit'));
    Assert.AreEqual(2,
      (lRoot.GetValue('summary') as TJSONObject).GetValue<Integer>('editCount'));
    Assert.AreEqual(3,
      (lRoot.GetValue('summary') as TJSONObject).GetValue<Integer>('omittedResultCount'));
    lEdits := lRoot.GetValue('edits') as TJSONArray;
    Assert.AreEqual(2, lEdits.Count);
    Assert.AreEqual('uses', (lEdits.Items[0] as TJSONObject).GetValue<string>('expectedText'));
    Assert.AreEqual('Other',
      (lEdits.Items[1] as TJSONObject).GetValue<string>('replacementText'));
  finally
    lRoot.Free;
  end;
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\writer-round-trip');
  ForceDirectories(lDirectory);
  lArtifactPath := TPath.Combine(lDirectory, 'plan.json');
  TFile.WriteAllText(lArtifactPath, lJson, TEncoding.UTF8);
  Assert.IsTrue(TryReadRefactoringArtifactHeader(lArtifactPath, lReason), lReason);
  Assert.IsTrue(TryReadRefactoringArtifact(lArtifactPath, lRoundTrip, lReason), lReason);
  Assert.AreEqual(lArtifact.Operation, lRoundTrip.Operation);
  Assert.AreEqual(lArtifact.BindingFingerprint, lRoundTrip.BindingFingerprint);
  Assert.AreEqual(2, Integer(Length(lRoundTrip.Edits)));
  Assert.AreEqual(lArtifact.Edits[1].ReplacementText, lRoundTrip.Edits[1].ReplacementText);
  Assert.AreEqual(3, lRoundTrip.OmittedResultCount);
end;

procedure TRefactorApplyCliTests.WriterRejectsInvalidRequestJson;
var
  lArtifact: TRefactoringArtifact;
  lJson: string;
  lReason: string;
begin
  lArtifact := Default(TRefactoringArtifact);
  lArtifact.RequestJson := '{"selector":';
  Assert.IsFalse(TryWriteRefactoringArtifactJson(lArtifact, lJson, lReason));
  Assert.AreEqual('artifact.malformed', lReason);
  Assert.AreEqual('', lJson);
end;

procedure TRefactorApplyCliTests.ExactPlanComparisonRejectsDrift;
var
  lEdit: TSemanticPlanEdit;
  lFresh: TRefactoringArtifact;
  lReason: string;
  lSaved: TRefactoringArtifact;
  lSource: TRefactoringArtifactSource;
begin
  lSaved := Default(TRefactoringArtifact);
  lSaved.Operation := 'uses.remove';
  lSaved.Status := 'complete';
  lSaved.ContextFingerprint := 'context';
  lSaved.BindingFingerprint := 'binding';
  lSaved.RequestJson := '{"unit":"QuietLeaf"}';
  lSaved.SelectedConfigurations := ['Debug|Win64'];
  lSaved.ScopeRoots := ['C:\source.pas'];
  lSaved.ExpectedRoots := ['C:\source.pas'];
  lSaved.AnalyzedRoots := ['C:\source.pas'];
  lSaved.RequiredAnalysisKinds := ['body'];
  lSaved.FocusedChecks := ['fixture.run'];
  lSource := Default(TRefactoringArtifactSource);
  lSource.FileName := 'C:\source.pas';
  lSource.ContentHash := 'hash';
  lSource.IncludeGraphHash := 'include';
  lSaved.Sources := [lSource];
  lEdit := Default(TSemanticPlanEdit);
  lEdit.FileName := lSource.FileName;
  lEdit.StartLine := 1;
  lEdit.StartColumn := 1;
  lEdit.EndLine := 1;
  lEdit.EndColumn := 5;
  lEdit.ExpectedText := 'uses';
  lEdit.ReplacementText := '';
  lSaved.Edits := [lEdit];
  lFresh := lSaved;

  Assert.IsTrue(RefactoringArtifactsMatch(lSaved, lFresh, lReason), lReason);
  lFresh.Edits := Copy(lSaved.Edits);
  lFresh.Edits[0].ReplacementText := 'unit';
  Assert.IsFalse(RefactoringArtifactsMatch(lSaved, lFresh, lReason));
  Assert.AreEqual('artifact.plan-mismatch', lReason);

  lFresh := lSaved;
  lFresh.ContextFingerprint := 'stale';
  Assert.IsFalse(RefactoringArtifactsMatch(lSaved, lFresh, lReason));
  Assert.AreEqual('artifact.stale-context', lReason);

  lFresh := lSaved;
  lFresh.RequestJson := '{"unit":"DifferentLeaf"}';
  Assert.IsFalse(RefactoringArtifactsMatch(lSaved, lFresh, lReason));
  Assert.AreEqual('artifact.intent-mismatch', lReason);
end;

procedure TRefactorApplyCliTests.KnownUsesOperationReplansAndRejectsForgedArtifact;
var
  lArtifact: TRefactoringArtifact;
  lConsumerFile: string;
  lDirectory: string;
  lEdit: TSemanticPlanEdit;
  lExitCode: Cardinal;
  lJson: string;
  lLog: string;
  lOutput: string;
  lPlanPath: string;
  lProject: string;
  lReason: string;
  lRequest: TJSONObject;
  lSource: TRefactoringArtifactSource;
  lText: string;
begin
  lDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\forged-uses');
  ForceDirectories(lDirectory);
  lConsumerFile := TPath.Combine(lDirectory, 'UsesConsumer.pas');
  lText := 'unit UsesConsumer;'#13#10'interface'#13#10'implementation'#13#10 +
    'uses QuietLeaf;'#13#10'end.'#13#10;
  TFile.WriteAllText(lConsumerFile, lText, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lDirectory, 'QuietLeaf.pas'),
    'unit QuietLeaf;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10,
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lDirectory, 'UsesProject.dpr'),
    'program UsesProject;'#13#10'uses UsesConsumer in ''UsesConsumer.pas'', ' +
    'QuietLeaf in ''QuietLeaf.pas'';'#13#10'begin end.'#13#10, TEncoding.UTF8);
  lProject := TPath.Combine(lDirectory, 'UsesProject.dproj');
  TFile.WriteAllText(lProject,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>UsesProject.dpr</MainSource></PropertyGroup>' +
    '<ItemGroup><DCCReference Include="UsesConsumer.pas"/>' +
    '<DCCReference Include="QuietLeaf.pas"/></ItemGroup></Project>', TEncoding.UTF8);

  lArtifact := Default(TRefactoringArtifact);
  lArtifact.Operation := 'uses.remove-implementation-import';
  lArtifact.Status := 'complete';
  lArtifact.ContextFingerprint := 'forged-context';
  lArtifact.BindingFingerprint := 'forged-binding';
  lRequest := TJSONObject.Create;
  try
    lRequest.AddPair('consumerFileName', lConsumerFile);
    lRequest.AddPair('unitName', 'QuietLeaf');
    lArtifact.RequestJson := lRequest.ToJSON;
  finally
    lRequest.Free;
  end;
  lArtifact.SelectedConfigurations := ['Debug|Win64'];
  lArtifact.ScopeRoots := [lConsumerFile];
  lArtifact.ExpectedRoots := [lConsumerFile];
  lArtifact.AnalyzedRoots := [lConsumerFile];
  lArtifact.RequiredAnalysisKinds := ['body', 'references'];
  lSource := Default(TRefactoringArtifactSource);
  lSource.FileName := lConsumerFile;
  lSource.ContentHash := 'forged-source';
  lSource.IncludeGraphHash := 'forged-includes';
  lArtifact.Sources := [lSource];
  lEdit := Default(TSemanticPlanEdit);
  lEdit.FileName := lConsumerFile;
  lEdit.StartLine := 4;
  lEdit.StartColumn := 1;
  lEdit.EndLine := 4;
  lEdit.EndColumn := 16;
  lEdit.ExpectedText := 'uses QuietLeaf;';
  lArtifact.Edits := [lEdit];
  Assert.IsTrue(TryWriteRefactoringArtifactJson(lArtifact, lJson, lReason), lReason);
  lPlanPath := TPath.Combine(lDirectory, 'forged-plan.json');
  TFile.WriteAllText(lPlanPath, lJson, TEncoding.UTF8);
  lLog := TPath.Combine(lDirectory, 'command.log');
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lPlanPath),
    RepoRoot, lLog, lExitCode));
  Assert.AreNotEqual(Cardinal(0), lExitCode);
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lOutput, 'artifact.stale-context'), lOutput);
  Assert.AreEqual(lText, TFile.ReadAllText(lConsumerFile, TEncoding.UTF8));
end;

procedure TRefactorApplyCliTests.UsesPlanRoundTripAppliesFreshArtifact;
var
  lArtifact: TRefactoringArtifact;
  lConsumer: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lPlan: string;
  lProject: string;
  lReason: string;
  lRequest: TJSONObject;
  lRequestPath: string;
  lText: string;
begin
  lDirectory := TPath.Combine(RepoRoot, 'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\roundtrip-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  ForceDirectories(lDirectory);
  lConsumer := TPath.Combine(lDirectory, 'UsesConsumer.pas');
  lText := 'unit UsesConsumer;'#13#10'interface'#13#10'implementation'#13#10 +
    'uses QuietLeaf;'#13#10'end.'#13#10;
  TFile.WriteAllText(lConsumer, lText, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lDirectory, 'QuietLeaf.pas'),
    'unit QuietLeaf;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lDirectory, 'UsesProject.dpr'),
    'program UsesProject; {$APPTYPE CONSOLE} uses UsesConsumer, QuietLeaf; begin end.'#13#10,
    TEncoding.UTF8);
  lProject := TPath.Combine(lDirectory, 'UsesProject.dproj');
  TFile.WriteAllText(lProject,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>UsesProject.dpr</MainSource><Config>Debug</Config>' +
    '<Platform>Win64</Platform><AppType>Console</AppType><FrameworkType>None</FrameworkType>' +
    '<DCC_ExeOutput>bin</DCC_ExeOutput><DCC_DcuOutput>bin</DCC_DcuOutput></PropertyGroup>' +
    '<ItemGroup><DelphiCompile Include="UsesProject.dpr"><MainSource>MainSource</MainSource>' +
    '</DelphiCompile><DCCReference Include="UsesConsumer.pas"/>' +
    '<DCCReference Include="QuietLeaf.pas"/></ItemGroup>' +
    '<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"/></Project>', TEncoding.UTF8);
  lRequest := TJSONObject.Create;
  try
    lRequest.AddPair('operation', 'uses.remove-implementation-import');
    lRequest.AddPair('consumerFileName', lConsumer);
    lRequest.AddPair('unitName', 'QuietLeaf');
    lRequestPath := TPath.Combine(lDirectory, 'request.json');
    TFile.WriteAllText(lRequestPath, lRequest.ToJSON, TEncoding.UTF8);
  finally
    lRequest.Free;
  end;
  lPlan := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'plan.log');
  Assert.IsTrue(RunResolverProcess('uses --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --format json --request ' + QuoteArg(lRequestPath) +
    ' --plan-out ' + QuoteArg(lPlan), RepoRoot, lLog, lExitCode));
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.AreEqual(Cardinal(0), lExitCode, lOutput);
  Assert.IsTrue(TryReadRefactoringArtifact(lPlan, lArtifact, lReason), lReason);
  Assert.AreEqual('complete', lArtifact.Status);
  Assert.AreEqual<NativeInt>(1, Length(lArtifact.Edits));
  Assert.AreEqual(lText, TFile.ReadAllText(lConsumer, TEncoding.UTF8));
  lLog := TPath.Combine(lDirectory, 'apply.log');
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lPlan),
    RepoRoot, lLog, lExitCode));
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  Assert.AreEqual(Cardinal(0), lExitCode, lOutput);
  Assert.IsTrue(ContainsText(lOutput, '"status":"applied"'), lOutput);
  Assert.IsFalse(ContainsText(TFile.ReadAllText(lConsumer, TEncoding.UTF8), 'uses QuietLeaf;'));
end;

procedure TRefactorApplyCliTests.CheckDirectCompilerApply(const aFailPostBuild: Boolean);
var
  lArtifact: TRefactoringArtifact;
  lBdsRoot: string;
  lConsumer: string;
  lDirectory: string;
  lExitCode: Cardinal;
  lJournal: TJSONObject;
  lJournalPath: string;
  lLog: string;
  lOriginalHash: string;
  lOutput: string;
  lPlan: string;
  lProject: string;
  lReason: string;
  lRequest: TJSONObject;
  lRequestPath: string;
  lResult: TJSONObject;
  lText: string;
  lVerificationTarget: string;
begin
  lDirectory := TPath.Combine(RepoRoot, 'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\direct-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  ForceDirectories(lDirectory);
  lConsumer := TPath.Combine(lDirectory, 'UsesConsumer.pas');
  lText := 'unit UsesConsumer;'#13#10'interface'#13#10'implementation'#13#10 +
    'uses QuietLeaf;'#13#10'end.'#13#10;
  TFile.WriteAllText(lConsumer, lText, TEncoding.UTF8);
  lOriginalHash := THashSHA2.GetHashStringFromFile(lConsumer);
  TFile.WriteAllText(TPath.Combine(lDirectory, 'QuietLeaf.pas'),
    'unit QuietLeaf;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lDirectory, 'UsesProject.dpr'),
    'program UsesProject; {$APPTYPE CONSOLE} uses UsesConsumer, QuietLeaf; begin end.'#13#10,
    TEncoding.UTF8);
  lBdsRoot := ResolveBdsRoot('23.0', '', '');
  Assert.IsTrue(TFile.Exists(TPath.Combine(lBdsRoot, 'bin\dcc64.exe')),
    'The direct-compiler fixture requires installed Delphi 12 Win64.');
  lVerificationTarget := '';
  if aFailPostBuild then
    lVerificationTarget := '<Error Condition="Exists(''baseline.marker'')" ' +
      'Text="Owned post-edit verification failure"/>' +
      '<Touch Files="baseline.marker" AlwaysCreate="true"/>';
  lProject := TPath.Combine(lDirectory, 'UsesProject.dproj');
  TFile.WriteAllText(lProject,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Build">' +
    '<PropertyGroup><MainSource>UsesProject.dpr</MainSource><ProjectName>UsesProject</ProjectName>' +
    '<Config>Debug</Config><Platform>Win64</Platform><AppType>Console</AppType>' +
    '<DCC_Define>DEBUG</DCC_Define></PropertyGroup>' +
    '<ItemGroup><DCCReference Include="UsesConsumer.pas"/><DCCReference Include="QuietLeaf.pas"/></ItemGroup>' +
    '<Target Name="Build"><MakeDir Directories="bin"/>' +
    '<Exec Command="&quot;' + TPath.Combine(lBdsRoot, 'bin\dcc64.exe') +
    '&quot; -B -Q -DDEBUG -Ebin -N0bin -U&quot;' + TPath.Combine(lBdsRoot, 'lib\win64\release') +
    '&quot; UsesProject.dpr"/>' + lVerificationTarget + '</Target>' +
    '<Target Name="Rebuild" DependsOnTargets="Build"/></Project>', TEncoding.UTF8);
  lRequest := TJSONObject.Create;
  try
    lRequest.AddPair('operation', 'uses.remove-implementation-import');
    lRequest.AddPair('consumerFileName', lConsumer);
    lRequest.AddPair('unitName', 'QuietLeaf');
    lRequestPath := TPath.Combine(lDirectory, 'request.json');
    TFile.WriteAllText(lRequestPath, lRequest.ToJSON, TEncoding.UTF8);
  finally
    lRequest.Free;
  end;
  lPlan := TPath.Combine(lDirectory, 'plan.json');
  lLog := TPath.Combine(lDirectory, 'plan.log');
  Assert.IsTrue(RunResolverProcess('uses --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --format json --request ' + QuoteArg(lRequestPath) +
    ' --plan-out ' + QuoteArg(lPlan), RepoRoot, lLog, lExitCode));
  Assert.AreEqual(Cardinal(0), lExitCode, TFile.ReadAllText(lLog, TEncoding.UTF8));
  Assert.IsTrue(TryReadRefactoringArtifact(lPlan, lArtifact, lReason), lReason);
  Assert.AreEqual('complete', lArtifact.Status);
  Assert.AreEqual<NativeInt>(1, Length(lArtifact.Edits));
  Assert.AreEqual(lOriginalHash, THashSHA2.GetHashStringFromFile(lConsumer));
  lLog := TPath.Combine(lDirectory, 'apply.log');
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --apply-plan ' + QuoteArg(lPlan),
    RepoRoot, lLog, lExitCode));
  lOutput := TFile.ReadAllText(lLog, TEncoding.UTF8);
  lResult := TJSONObject.ParseJSONValue(lOutput) as TJSONObject;
  try
    Assert.IsNotNull(lResult, lOutput);
    if aFailPostBuild then
    begin
      Assert.AreNotEqual(Cardinal(0), lExitCode, lOutput);
      Assert.AreEqual('rolled-back', lResult.GetValue<string>('status'), lOutput);
      Assert.AreEqual(lOriginalHash, THashSHA2.GetHashStringFromFile(lConsumer));
    end else begin
      Assert.AreEqual(Cardinal(0), lExitCode, lOutput);
      Assert.AreEqual('applied', lResult.GetValue<string>('status'), lOutput);
      Assert.IsFalse(ContainsText(TFile.ReadAllText(lConsumer, TEncoding.UTF8), 'uses QuietLeaf;'));
    end;
    lJournalPath := lResult.GetValue<string>('journal');
  finally
    lResult.Free;
  end;
  lJournal := TJSONObject.ParseJSONValue(TFile.ReadAllText(lJournalPath, TEncoding.UTF8)) as TJSONObject;
  try
    Assert.IsNotNull(lJournal);
    Assert.Contains(TFile.ReadAllText(lJournal.GetValue<string>('baselineLog'), TEncoding.UTF8),
      'Embarcadero Delphi for Win64 compiler');
    lOutput := TFile.ReadAllText(lJournal.GetValue<string>('verificationLog'), TEncoding.UTF8);
    Assert.Contains(lOutput, 'Embarcadero Delphi for Win64 compiler');
    if aFailPostBuild then
      Assert.Contains(lOutput, 'Owned post-edit verification failure');
  finally
    lJournal.Free;
  end;
end;

procedure TRefactorApplyCliTests.DirectCompilerArtifactRunsBaselineAndPostBuild;
begin
  CheckDirectCompilerApply(False);
end;

procedure TRefactorApplyCliTests.DirectCompilerPostBuildFailureRestoresOriginalBytes;
begin
  CheckDirectCompilerApply(True);
end;

procedure TRefactorApplyCliTests.RejectedUsesRequestsDoNotCreateArtifact;
const
  cRequests: array[0..3] of string = ('{"operation":',
    '{"operation":"unknown.operation","consumerFileName":"unused.pas","unitName":"QuietLeaf"}',
    '{"operation":"uses.remove-implementation-import","consumerFileName":42,"unitName":"QuietLeaf"}',
    '{"operation":"uses.remove-implementation-import","operation":"duplicate","unitName":"QuietLeaf"}');
var
  i: Integer;
  lDirectory: string;
  lExitCode: Cardinal;
  lLog: string;
  lPlan: string;
  lProject: string;
  lRequest: string;
begin
  lDirectory := TPath.Combine(RepoRoot, 'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\refused-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  ForceDirectories(lDirectory);
  lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  lPlan := TPath.Combine(lDirectory, 'plan.json');
  lRequest := TPath.Combine(lDirectory, 'request.json');
  for i := Low(cRequests) to High(cRequests) do
  begin
    TFile.WriteAllText(lRequest, cRequests[i], TEncoding.UTF8);
    lLog := TPath.Combine(lDirectory, IntToStr(i) + '.log');
    Assert.IsTrue(RunResolverProcess('uses --project ' + QuoteArg(lProject) +
      ' --platform Win64 --config Debug --delphi 23.0 --format json --request ' + QuoteArg(lRequest) +
      ' --plan-out ' + QuoteArg(lPlan), RepoRoot, lLog, lExitCode));
    Assert.AreNotEqual(Cardinal(0), lExitCode, TFile.ReadAllText(lLog, TEncoding.UTF8));
    Assert.IsFalse(TFile.Exists(lPlan), 'A rejected request must not leave an applicable artifact.');
  end;
end;

procedure TRefactorApplyCliTests.FailedArtifactWriteRemovesOnlyNewOutput;
var
  lDirectory: string;
  lPath: string;
begin
  lDirectory := TPath.Combine(RepoRoot, 'tests\.dak\DelphiAIKit.Tests\refactoring-light-apply\write-failure-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  ForceDirectories(lDirectory);
  lPath := TPath.Combine(lDirectory, 'plan.json');
  try
    WriteNewRefactoringArtifactForTest(lPath, '{}',
      procedure
      begin
        Assert.IsTrue(TFile.Exists(lPath), 'Fault must occur after CREATE_NEW owns the output.');
        Assert.Fail('owned after-create failure');
      end);
    Assert.Fail('Injected file-write failure must surface.');
  except
    on Exception do
      Assert.Contains(Exception(ExceptObject).Message, 'owned after-create failure');
  end;
  Assert.IsFalse(TFile.Exists(lPath), 'Failed new artifact must be removed.');
  TFile.WriteAllText(lPath, 'existing output', TEncoding.UTF8);
  try
    WriteNewRefactoringArtifactForTest(lPath, '{}', nil);
    Assert.Fail('Existing output must not be overwritten.');
  except
    on EInOutError do
      Assert.Contains(Exception(ExceptObject).Message, 'artifact.output-not-new');
  end;
  Assert.AreEqual('existing output', TFile.ReadAllText(lPath, TEncoding.UTF8));
end;

initialization
  TDUnitX.RegisterTestFixture(TRefactorApplyCliTests);

end.
