unit Test.NativeAnalysisReports.Verify;

interface

uses
  DUnitX.TestFramework;

type
  // verify_outputs on the replayed report-small output: the corrupted controls from the reference
  // suites (test_ownership_reporting.py and test_pal_rule_policy.py) ported one to one. Policy
  // artifacts (baseline/delta/history/trend) are T-325 controls and are not exercised here.
  [TestFixture]
  TNativeAnalysisVerifyTests = class
  private
    fOutput: string;
    fPristine: string;
    procedure AssertVerifyFails(const aFragment: string);
    function ReadJson(const aRelative: string): string;
    procedure WriteRaw(const aRelative, aText: string);
  public
    [SetupFixture]
    procedure ReplayOnce;
    [TearDownFixture]
    procedure DropReplay;
    [Setup]
    procedure RestorePristine;
    [Test]
    procedure VerifiedOutputReportsActionableOwnership;
    [Test]
    procedure CorruptTriageRowIsEvidenceMismatch;
    [Test]
    procedure CorruptSarifMessageIsEvidenceMismatch;
    [Test]
    procedure CorruptFullSarifRuleIsEvidenceMismatch;
    [Test]
    procedure EmptyOwnershipIsInvalid;
    [Test]
    procedure MissingRequestedFixInsightJsonlIsReported;
    [Test]
    procedure SummaryProjectionMismatchIsReported;
    [Test]
    procedure ActivePalIgnorePolicyMismatchIsReported;
    [Test]
    procedure VerifiedPalAliasMismatchIsReported;
    [Test]
    procedure CompatibilityFingerprintMismatchIsReported;
    [Test]
    procedure SummaryMarkdownOwnershipMismatchIsReported;
  end;

  // Synthetic streams from the reference suite (write_summary / finding_streams / write_schema2_seed)
  // driven through the native finalizer and verifier.
  [TestFixture]
  TNativeAnalysisReplayControlTests = class
  private
    fRoot: string;
    fProject: string;
    procedure WriteSummary;
    procedure WriteFindingStreams;
    procedure WriteSchema2Seed;
    procedure WriteFakeFixInsight;
    function Finalize: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SummaryJsonAndSarifMatchNormalizedFindings;
    [Test]
    procedure CorruptPalCodeIsIdentityMismatch;
    [Test]
    procedure SummaryCountMismatchIsRequiredFailure;
    [Test]
    procedure NonActionableRawFindingsStillRequireSummaryTotals;
    [Test]
    procedure UnitSummarySubjectAndPalVersionAreParsed;
    [Test]
    procedure SkippedUnitSummaryIsRecognizedAsExplicitStatus;
    [Test]
    procedure SkippedUnitIsNotReclassifiedAsRequestedCleanAnalysis;
    [Test]
    procedure MissingOptionalSnippetSourceDoesNotFail;
    [Test]
    procedure DisabledAnalyzerCountsAreZeroNotUnknown;
    [TestCase('both-empty', 'both-empty')]
    [TestCase('pal-empty', 'pal-empty')]
    [TestCase('fixinsight-empty', 'fixinsight-empty')]
    procedure MalformedPresentSummaryFailsBeforeStateMutation(const aCase: string);
    [Test]
    procedure SarifValidationFailsBeforeStateMutation;
    [Test]
    procedure RunContextCapturesFixInsightVersion;
  end;

  // analyze-report CLI contract: replay prints the finalization result, --verify prints the
  // ownership line, exit 3 reports a rejected output and exit 2 a usage error.
  [TestFixture]
  TNativeAnalysisReportCommandTests = class
  private
    fRoot: string;
    fEnvironment: IInterface;
    function RunReport(const aArguments: string; aExpectedExit: Cardinal): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReplayThenVerifyThroughTheCommandLine;
    [Test]
    procedure MissingOutIsUsageError;
    [Test]
    procedure BrokenReplayIsNotARejectedResult;
    [Test]
    procedure BaselineSwitchSelectsTheBaselineFile;
  end;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.Analysis.JsonText, Dak.Analysis.ReportBundle, Dak.Analysis.ReportReplay, Dak.Analysis.ReportVerify,
  Dak.Analysis.ReportWriters,
  Test.Support;

const
  cMigrationRoot = 'projects\.dak\DelphiAIKit\native-analysis-migration';

function MigrationPath(const aRelative: string): string;
begin
  Result := TPath.Combine(TPath.Combine(RepoRoot, cMigrationRoot), aRelative);
end;

procedure CopyTree(const aSource, aDestination: string);
var
  lFile, lTarget: string;
begin
  for lFile in TDirectory.GetFiles(aSource, '*', TSearchOption.soAllDirectories) do
  begin
    lTarget := TPath.Combine(aDestination, lFile.Substring(Length(IncludeTrailingPathDelimiter(aSource))));
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTarget));
    TFile.Copy(lFile, lTarget, True);
  end;
end;

procedure WriteUtf8(const aPath, aText: string);
begin
  TDirectory.CreateDirectory(TPath.GetDirectoryName(aPath));
  TFile.WriteAllBytes(aPath, TEncoding.UTF8.GetBytes(aText));
end;

function ReadUtf8(const aPath: string): string;
begin
  Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(aPath));
end;

// json.dumps(items) per line, like the reference write_jsonl helper.
procedure WriteJsonLines(const aPath: string; aRows: TJSONArray);
var
  lItem: TJSONValue;
  lText: TStringBuilder;
begin
  lText := TStringBuilder.Create;
  try
    for lItem in aRows do
      lText.Append(TPythonJson.Line(lItem)).Append(#10);
    WriteUtf8(aPath, lText.ToString);
  finally
    lText.Free;
  end;
end;

function LoadJsonLines(const aPath: string): TJSONArray;
var
  lLine: string;
begin
  Result := TJSONArray.Create;
  for lLine in ReadUtf8(aPath).Split([#10]) do
    if Trim(lLine) <> '' then
      Result.AddElement(ParseJsonObject(lLine, aPath));
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

// First result of the first run in a SARIF document.
function FirstSarifResult(aSarif: TJSONObject): TJSONObject;
var
  lRun: TJSONObject;
begin
  lRun := (Member(aSarif, ['runs']) as TJSONArray).Items[0] as TJSONObject;
  Result := (lRun.GetValue('results') as TJSONArray).Items[0] as TJSONObject;
end;

// assertRaisesRegex: the reference messages carry details after the asserted fragment.
procedure AssertRaisesContaining(aProc: TProc; const aFragment: string);
begin
  try
    aProc;
    Assert.Fail('expected EConvertError containing "' + aFragment + '"');
  except
    on e: EConvertError do
      Assert.IsTrue(e.Message.Contains(aFragment), 'expected "' + aFragment + '" in: ' + e.Message);
  end;
end;

function SarifResultCount(aSarif: TJSONObject): Integer;
var
  lRun: TJSONValue;
begin
  Result := 0;
  for lRun in aSarif.GetValue('runs') as TJSONArray do
    Inc(Result, (TJSONObject(lRun).GetValue('results') as TJSONArray).Count);
end;

{ TNativeAnalysisVerifyTests }

procedure TNativeAnalysisVerifyTests.ReplayOnce;
var
  g: TGarbos;
  lResult: TJSONObject;
begin
  fOutput := MigrationPath('scratch\report-small\repo\.dak\Sample\policy');
  Assert.IsFalse(TDirectory.Exists(fOutput), 'Scratch output already exists; inspect it before rerunning: ' + fOutput);
  CopyTree(MigrationPath('seeds\report-small'), fOutput);
  GC(lResult, FinalizeAnalysisReport(fOutput, nil, -1), g);
  fPristine := UniqueNoRepoTempPath('native-verify-pristine');
  CopyTree(fOutput, fPristine);
end;

procedure TNativeAnalysisVerifyTests.DropReplay;
begin
  if (fOutput <> '') and TDirectory.Exists(fOutput) then
    TDirectory.Delete(fOutput, True);
  if (fPristine <> '') and TDirectory.Exists(fPristine) then
    TDirectory.Delete(fPristine, True);
end;

procedure TNativeAnalysisVerifyTests.RestorePristine;
begin
  if TDirectory.Exists(fOutput) then
    TDirectory.Delete(fOutput, True);
  CopyTree(fPristine, fOutput);
end;

procedure TNativeAnalysisVerifyTests.AssertVerifyFails(const aFragment: string);
var
  lCounts: TJSONObject;
begin
  try
    lCounts := VerifyAnalysisReport(fOutput);
    lCounts.Free;
    Assert.Fail('verification must fail with "' + aFragment + '"');
  except
    on e: EConvertError do
      Assert.IsTrue(e.Message.Contains(aFragment), 'expected "' + aFragment + '" in: ' + e.Message);
  end;
end;

function TNativeAnalysisVerifyTests.ReadJson(const aRelative: string): string;
begin
  Result := ReadUtf8(TPath.Combine(fOutput, aRelative));
end;

procedure TNativeAnalysisVerifyTests.WriteRaw(const aRelative, aText: string);
begin
  WriteUtf8(TPath.Combine(fOutput, aRelative), aText);
end;

procedure TNativeAnalysisVerifyTests.VerifiedOutputReportsActionableOwnership;
var
  g: TGarbos;
  lCounts, lSummary: TJSONObject;
begin
  GC(lCounts, VerifyAnalysisReport(fOutput), g);
  GC(lSummary, ParseJsonObject(ReadJson('summary.json'), 'summary.json'), g);
  Assert.AreEqual(TPythonJson.Compact(Member(lSummary, ['counts', 'actionable', 'ownership'])),
    TPythonJson.Compact(lCounts), 'verify returns the actionable ownership counts');
  Assert.AreEqual('project=10, repository=0, third_party=0, unknown=0', AnalysisOwnershipText(lCounts));
end;

procedure TNativeAnalysisVerifyTests.CorruptTriageRowIsEvidenceMismatch;
var
  i: Integer;
  lLines: TArray<string>;
begin
  lLines := ReadJson('triage.md').Replace(#13#10, #10).Split([#10]);
  for i := 0 to High(lLines) do
    if lLines[i].StartsWith('- [') then
    begin
      lLines[i] := lLines[i] + ' corrupt';
      Break;
    end;
  WriteRaw('triage.md', String.Join(#10, lLines).TrimRight + #10);
  AssertVerifyFails('triage.md evidence mismatch');
end;

procedure TNativeAnalysisVerifyTests.CorruptSarifMessageIsEvidenceMismatch;
var
  g: TGarbos;
  lSarif: TJSONObject;
begin
  GC(lSarif, ParseJsonObject(ReadJson('static-analysis.sarif'), 'sarif'), g);
  JsonPutText(FirstSarifResult(lSarif).GetValue('message') as TJSONObject, 'text', 'corrupt');
  WriteRaw('static-analysis.sarif', lSarif.ToJSON);
  AssertVerifyFails('static-analysis.sarif evidence mismatch');
end;

procedure TNativeAnalysisVerifyTests.CorruptFullSarifRuleIsEvidenceMismatch;
var
  g: TGarbos;
  lSarif: TJSONObject;
begin
  GC(lSarif, ParseJsonObject(ReadJson('static-analysis.full.sarif'), 'full sarif'), g);
  JsonPutText(FirstSarifResult(lSarif), 'ruleId', 'corrupt');
  WriteRaw('static-analysis.full.sarif', lSarif.ToJSON);
  AssertVerifyFails('static-analysis.full.sarif evidence mismatch');
end;

procedure TNativeAnalysisVerifyTests.EmptyOwnershipIsInvalid;
var
  g: TGarbos;
  lRows: TJSONArray;
begin
  GC(lRows, LoadJsonLines(TPath.Combine(fOutput, 'fixinsight\fi-findings.jsonl')), g);
  JsonPutText(TJSONObject(lRows[0]), 'ownership', '');
  WriteJsonLines(TPath.Combine(fOutput, 'fixinsight\fi-findings.jsonl'), lRows);
  AssertVerifyFails('invalid ownership');
end;

procedure TNativeAnalysisVerifyTests.MissingRequestedFixInsightJsonlIsReported;
begin
  TFile.Delete(TPath.Combine(fOutput, 'fixinsight\fi-findings.jsonl'));
  AssertVerifyFails('requested FixInsight JSONL is missing');
end;

procedure TNativeAnalysisVerifyTests.SummaryProjectionMismatchIsReported;
var
  g: TGarbos;
  lSummary: TJSONObject;
begin
  GC(lSummary, ParseJsonObject(ReadJson('summary.json'), 'summary.json'), g);
  JsonPut(TJSONObject(Member(lSummary, ['counts', 'actionable', 'ownership'])), 'project', TJSONNumber.Create(11));
  WriteRaw('summary.json', lSummary.ToJSON);
  AssertVerifyFails('summary.json projection mismatch');
end;

procedure TNativeAnalysisVerifyTests.ActivePalIgnorePolicyMismatchIsReported;
var
  g: TGarbos;
  lSummary: TJSONObject;
begin
  GC(lSummary, ParseJsonObject(ReadJson('summary.json'), 'summary.json'), g);
  JsonPut(TJSONObject(Member(lSummary, ['policy', 'active'])), 'pal_ignore_rules',
    TJSONArray.Create.Add('WARN54'));
  WriteRaw('summary.json', lSummary.ToJSON);
  AssertVerifyFails('active PAL ignore policy');
end;

procedure TNativeAnalysisVerifyTests.VerifiedPalAliasMismatchIsReported;
var
  g: TGarbos;
  lSummary: TJSONObject;
begin
  GC(lSummary, ParseJsonObject(ReadJson('summary.json'), 'summary.json'), g);
  JsonPut(TJSONObject(Member(lSummary, ['analyzers', 'pascal_analyzer'])), 'verified_rule_aliases',
    TJSONObject.Create);
  WriteRaw('summary.json', lSummary.ToJSON);
  AssertVerifyFails('verified PAL alias');
end;

procedure TNativeAnalysisVerifyTests.CompatibilityFingerprintMismatchIsReported;
var
  g: TGarbos;
  lSummary: TJSONObject;
begin
  GC(lSummary, ParseJsonObject(ReadJson('summary.json'), 'summary.json'), g);
  JsonPutText(TJSONObject(Member(lSummary, ['compatibility'])), 'sha256', StringOfChar('0', 64));
  WriteRaw('summary.json', lSummary.ToJSON);
  AssertVerifyFails('compatibility fingerprint mismatch');
end;

procedure TNativeAnalysisVerifyTests.SummaryMarkdownOwnershipMismatchIsReported;
begin
  WriteRaw('summary.md', ReadJson('summary.md').Replace('- project=10, repository=0',
    '- project=999, repository=0'));
  AssertVerifyFails('summary.md ownership mismatch');
end;

{ TNativeAnalysisReplayControlTests }

procedure TNativeAnalysisReplayControlTests.Setup;
begin
  fRoot := UniqueNoRepoTempPath('native-replay-control');
  TDirectory.CreateDirectory(fRoot);
  fProject := TPath.Combine(fRoot, 'Sample.dproj');
  WriteUtf8(fProject, '<Project />');
end;

procedure TNativeAnalysisReplayControlTests.TearDown;
begin
  if TDirectory.Exists(fRoot) then
    TDirectory.Delete(fRoot, True);
end;

procedure TNativeAnalysisReplayControlTests.WriteSummary;
begin
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Static analysis'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Project: `' + fProject + '`'#10#10 +
    '## FixInsight'#10#10 +
    '- Findings (by code): 2'#10 +
    '  - W101: 1'#10 +
    '  - C102: 1'#10#10 +
    '## Pascal Analyzer'#10#10 +
    '- Version: 9.21.3'#10 +
    '- Compiler target: Delphi 13 (Win64)'#10 +
    '- Totals: warnings=1, strong_warnings=1, optimizations=1, total=3'#10);
end;

procedure TNativeAnalysisReplayControlTests.WriteFindingStreams;
begin
  WriteUtf8(TPath.Combine(fRoot, 'fixinsight\fi-findings.jsonl'),
    '{"tool": "FixInsight", "code": "W101", "kind": "W", "path": "src/One.pas", "line": 10, "col": 2, "message": "warning"}'#10 +
    '{"tool": "FixInsight", "code": "C102", "kind": "C", "path": null, "line": 1, "col": 1, "message": "maintainability"}'#10);
  WriteUtf8(TPath.Combine(fRoot, 'pascal-analyzer\pal-findings.jsonl'),
    '{"severity": "warning", "section": "Warnings", "module": "One", "path": "src/One.pas", "line": 20, "message": "warning"}'#10 +
    '{"severity": "strong-warning", "section": "Strong warnings", "module": "Two", "path": "src/Two.pas", "line": 30, "message": "strong warning"}'#10 +
    '{"severity": "optimization", "section": "Optimizations", "module": "Three", "path": null, "line": 40, "message": "optimization"}'#10);
end;

// write_schema2_seed: the schema-2 status seed the analysis stage leaves for the postprocessor.
procedure WriteSchema2SeedFile(const aRoot, aProject: string);
var
  lProject: string;
begin
  lProject := aProject.Replace('\', '\\');
  WriteUtf8(TPath.Combine(aRoot, 'summary.json'),
    '{"schema_version": 2, "status": {"infrastructure": "complete", "policy": "not_evaluated"}, ' +
    '"subject": {"kind": "project", "path": "' + lProject + '"}, ' +
    '"compiler": {"platform": "Win64", "config": "Debug", "delphi": "23.0", "search_path_sha256": "search-path-seed"}, ' +
    '"analyzers": {"fixinsight": {"requested": true, "status": "complete", "executable": "FixInsightCL.exe", "count_quality": "complete"}, ' +
    '"pascal_analyzer": {"requested": true, "status": "complete", "executable": "palcmd.exe", "version": "9.21.3", "count_quality": "complete"}}, ' +
    '"inputs": {"project_sha256": "project-seed", "main_source_sha256": "main-source-seed", ' +
    '"config_manifests": [{"name": "dak.ini", "sha256": "settings-seed"}]}, ' +
    '"artifacts": {"summary_markdown": "summary.md"}, ' +
    '"policy": {"resolver": "Dak.Settings", "status": "not_evaluated", ' +
    '"values": {"gate_ownership": ["project", "repository"], "project_roots": [], "third_party_roots": []}, ' +
    '"sources": [], "sha256": "' + StringOfChar('b', 64) + '"}, "errors": []}');
end;

procedure TNativeAnalysisReplayControlTests.WriteSchema2Seed;
begin
  WriteSchema2SeedFile(fRoot, fProject);
end;

procedure TNativeAnalysisReplayControlTests.WriteFakeFixInsight;
var
  lFake: string;
begin
  lFake := TPath.Combine(fRoot, 'FixInsightCL.cmd');
  WriteUtf8(lFake, '@echo FixInsightCL Pro version 2023.12'#13#10);
  WriteUtf8(TPath.Combine(fRoot, 'run.log'), 'CMD: "' + lFake + '" --project=Sample.dpr'#10);
end;

function TNativeAnalysisReplayControlTests.Finalize: string;
var
  g: TGarbos;
  lResult: TJSONObject;
begin
  GC(lResult, FinalizeAnalysisReport(fRoot, nil, -1), g);
  Result := TPythonJson.Document(lResult);
end;

procedure TNativeAnalysisReplayControlTests.SummaryJsonAndSarifMatchNormalizedFindings;
var
  g: TGarbos;
  lCounts, lFull, lResult, lSarif, lSummary: TJSONObject;
  lTriage: string;
begin
  WriteSummary;
  WriteFindingStreams;
  WriteSchema2Seed;
  WriteFakeFixInsight;
  GC(lResult, ParseJsonObject(Finalize, 'result'), g);
  Assert.IsTrue(TJSONBool(lResult.GetValue('gate_pass')).AsBoolean, 'gate_pass');
  Assert.AreEqual(TPath.Combine(fRoot, 'summary.json'), MemberText(lResult, ['summary_json']));
  GC(lSummary, ParseJsonObject(ReadUtf8(TPath.Combine(fRoot, 'summary.json')), 'summary.json'), g);
  Assert.AreEqual('3', MemberText(lSummary, ['schema_version']));
  Assert.AreEqual('complete', MemberText(lSummary, ['status', 'infrastructure']));
  Assert.AreEqual('complete', MemberText(lSummary, ['status', 'postprocessor']));
  Assert.AreEqual('complete', MemberText(lSummary, ['status', 'finalization']));
  Assert.AreEqual('search-path-seed', MemberText(lSummary, ['compiler', 'search_path_sha256']));
  Assert.AreEqual('complete', MemberText(lSummary, ['analyzers', 'fixinsight', 'count_quality']));
  Assert.AreEqual('2023.12', MemberText(lSummary, ['analyzers', 'fixinsight', 'version']));
  Assert.AreEqual('complete', MemberText(lSummary, ['analyzers', 'pascal_analyzer', 'count_quality']));
  Assert.AreEqual('project-seed', MemberText(lSummary, ['inputs', 'project_sha256']));
  Assert.IsNull(TJSONObject(Member(lSummary, ['policy'])).GetValue('status'), 'policy.status is not published');
  Assert.AreEqual('5', MemberText(lSummary, ['counts', 'raw', 'total']));
  Assert.AreEqual('0', MemberText(lSummary, ['counts', 'actionable', 'total']));
  Assert.AreEqual('5', MemberText(lSummary, ['counts', 'unknown', 'total']));
  Assert.AreEqual('{"project":0,"repository":0,"third_party":0,"unknown":5}',
    TPythonJson.Compact(Member(lSummary, ['counts', 'raw', 'ownership'])));
  Assert.AreEqual(0, (lSummary.GetValue('errors') as TJSONArray).Count, 'errors');
  Assert.AreEqual('summary.md', MemberText(lSummary, ['artifacts', 'summary_markdown']));
  Assert.AreEqual('static-analysis.sarif', MemberText(lSummary, ['artifacts', 'sarif']));
  Assert.AreEqual('static-analysis.full.sarif', MemberText(lSummary, ['artifacts', 'full_sarif']));
  GC(lSarif, ParseJsonObject(ReadUtf8(TPath.Combine(fRoot, 'static-analysis.sarif')), 'sarif'), g);
  Assert.AreEqual(0, SarifResultCount(lSarif), 'actionable SARIF results');
  GC(lFull, ParseJsonObject(ReadUtf8(TPath.Combine(fRoot, 'static-analysis.full.sarif')), 'full sarif'), g);
  Assert.AreEqual(5, SarifResultCount(lFull), 'full SARIF results');
  lTriage := ReadUtf8(TPath.Combine(fRoot, 'triage.md'));
  Assert.IsTrue(lTriage.Contains('FixInsight findings: 0'), 'triage FixInsight line');
  Assert.IsTrue(lTriage.Contains('Pascal Analyzer findings: 0'), 'triage PAL line');
  // The published output verifies against itself.
  GC(lCounts, VerifyAnalysisReport(fRoot), g);
  Assert.AreEqual('project=0, repository=0, third_party=0, unknown=0', AnalysisOwnershipText(lCounts));
end;

procedure TNativeAnalysisReplayControlTests.CorruptPalCodeIsIdentityMismatch;
var
  g: TGarbos;
  lFi, lPal: TJSONArray;
  lPalPath: string;
begin
  WriteSummary;
  WriteFindingStreams;
  WriteSchema2Seed;
  Finalize;
  lPalPath := TPath.Combine(fRoot, 'pascal-analyzer\pal-findings.jsonl');
  GC(lPal, LoadJsonLines(lPalPath), g);
  JsonPutText(TJSONObject(lPal[0]), 'pal_code', 'STWA6');
  WriteJsonLines(lPalPath, lPal);
  GC(lFi, LoadJsonLines(TPath.Combine(fRoot, 'fixinsight\fi-findings.jsonl')), g);
  WriteAnalysisSarif(fRoot, lFi, lPal, True);
  AssertRaisesContaining(
    procedure
    begin
      VerifyAnalysisReport(fRoot).Free;
    end, 'PAL identity');
end;

procedure TNativeAnalysisReplayControlTests.SummaryCountMismatchIsRequiredFailure;
var
  g: TGarbos;
  lPal: TJSONArray;
  lPalPath: string;
begin
  WriteSummary;
  WriteFindingStreams;
  lPalPath := TPath.Combine(fRoot, 'pascal-analyzer\pal-findings.jsonl');
  GC(lPal, LoadJsonLines(lPalPath), g);
  lPal.Remove(lPal.Count - 1).Free;
  WriteJsonLines(lPalPath, lPal);
  AssertRaisesContaining(
    procedure
    begin
      Finalize;
    end, 'Pascal Analyzer count mismatch');
end;

procedure TNativeAnalysisReplayControlTests.NonActionableRawFindingsStillRequireSummaryTotals;
var
  g: TGarbos;
  lEmpty, lFi, lPal: TJSONArray;
  lSummary: TJSONObject;
begin
  GC(lSummary, TJSONObject.Create, g);
  GC(lEmpty, TJSONArray.Create, g);
  GC(lFi, ParseJsonValue('[{"kind": "W", "ownership": "third_party", "report_projection": "external"}]') as TJSONArray, g);
  GC(lPal, ParseJsonValue('[{"severity": "warning", "ownership": "third_party", "report_projection": "external"}]') as TJSONArray, g);
  AssertRaisesContaining(
    procedure
    begin
      AnalysisActionableCounts(lSummary, lFi, lEmpty).Free;
    end, 'FixInsight count mismatch: summary total is missing');
  AssertRaisesContaining(
    procedure
    begin
      AnalysisActionableCounts(lSummary, lEmpty, lPal).Free;
    end, 'Pascal Analyzer count mismatch: summary totals are missing');
end;

procedure TNativeAnalysisReplayControlTests.UnitSummarySubjectAndPalVersionAreParsed;
var
  g: TGarbos;
  lSummary: TJSONObject;
begin
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Pascal Analyzer unit summary: Sample'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Unit: `C:\repo\Sample.pas`'#10 +
    '- PAL version: 9.21.3'#10 +
    '- Compiler target: Delphi 13 (Win64)'#10 +
    '- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0'#10);
  GC(lSummary, ParseAnalysisSummaryMarkdown(TPath.Combine(fRoot, 'summary.md')), g);
  Assert.AreEqual('C:\repo\Sample.pas', MemberText(lSummary, ['unit']));
  Assert.AreEqual('9.21.3', MemberText(lSummary, ['pal_version']));
  Assert.AreEqual('0', MemberText(lSummary, ['pal_totals', 'total']));
end;

procedure TNativeAnalysisReplayControlTests.SkippedUnitSummaryIsRecognizedAsExplicitStatus;
var
  g: TGarbos;
  lSummary: TJSONObject;
begin
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Pascal Analyzer unit summary: Sample'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Unit: `C:\repo\Sample.pas`'#10 +
    '- Skipped.'#10);
  GC(lSummary, ParseAnalysisSummaryMarkdown(TPath.Combine(fRoot, 'summary.md')), g);
  ValidateAnalysisSummary(lSummary);
  Assert.AreEqual('["pascal_analyzer"]', TPythonJson.Compact(Member(lSummary, ['analyzers'])));
end;

procedure TNativeAnalysisReplayControlTests.SkippedUnitIsNotReclassifiedAsRequestedCleanAnalysis;
var
  g: TGarbos;
  lStatus: TJSONObject;
  lUnit: string;
begin
  lUnit := TPath.Combine(fRoot, 'Sample.pas');
  WriteUtf8(lUnit, 'unit Sample;'#10);
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Pascal Analyzer unit summary: Sample'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Unit: `' + lUnit + '`'#10 +
    '- Skipped.'#10);
  Finalize;
  GC(lStatus, ParseJsonObject(ReadUtf8(TPath.Combine(fRoot, 'summary.json')), 'summary.json'), g);
  Assert.IsFalse(TJSONBool(Member(lStatus, ['analyzers', 'pascal_analyzer', 'requested'])).AsBoolean, 'requested');
  Assert.AreEqual('not_requested', MemberText(lStatus, ['analyzers', 'pascal_analyzer', 'status']));
end;

procedure TNativeAnalysisReplayControlTests.MissingOptionalSnippetSourceDoesNotFail;
var
  g: TGarbos;
  lResult: TJSONObject;
  lScope: IInterface;
begin
  WriteSummary;
  WriteFindingStreams;
  lScope := SetScopedEnvironmentVariable('DAK_TRIAGE_SNIPPETS', '1');
  GC(lResult, ParseJsonObject(Finalize, 'result'), g);
  Assert.IsTrue(TJSONBool(lResult.GetValue('gate_pass')).AsBoolean, 'gate_pass');
end;

procedure TNativeAnalysisReplayControlTests.DisabledAnalyzerCountsAreZeroNotUnknown;
var
  g: TGarbos;
  lSummary: TJSONObject;
begin
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Static analysis'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Project: `' + fProject + '`'#10#10 +
    '## FixInsight'#10#10 +
    '- Findings (by code): (TXT not generated)'#10#10 +
    '## Pascal Analyzer'#10#10 +
    '- Version: 9.21.3'#10 +
    '- Compiler target: Delphi 13 (Win64)'#10 +
    '- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0'#10);
  Finalize;
  GC(lSummary, ParseJsonObject(ReadUtf8(TPath.Combine(fRoot, 'summary.json')), 'summary.json'), g);
  Assert.AreEqual('0', MemberText(lSummary, ['counts', 'actionable', 'fixinsight', 'total']));
  Assert.AreEqual('0', MemberText(lSummary, ['counts', 'unknown', 'total']));
  Assert.AreEqual('0', MemberText(lSummary, ['counts', 'raw', 'total']));
end;

procedure TNativeAnalysisReplayControlTests.MalformedPresentSummaryFailsBeforeStateMutation(const aCase: string);
var
  lSections: string;
begin
  if aCase = 'both-empty' then
    lSections := '## FixInsight'#10#10'## Pascal Analyzer'#10
  else if aCase = 'pal-empty' then
    lSections := '## FixInsight'#10#10'- Findings (by code): 0'#10#10'## Pascal Analyzer'#10
  else
    lSections := '## FixInsight'#10#10'## Pascal Analyzer'#10#10'- Skipped.'#10;
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Static analysis with truncated analyzer sections'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Project: `C:\repo\Sample.dproj`'#10#10 + lSections);
  AssertRaisesContaining(
    procedure
    begin
      Finalize;
    end, 'Invalid analysis summary');
  Assert.IsFalse(TFile.Exists(TPath.Combine(fRoot, 'baseline.json')), 'no baseline');
  Assert.IsFalse(TFile.Exists(TPath.Combine(fRoot, 'history.jsonl')), 'no history');
  Assert.IsFalse(TFile.Exists(TPath.Combine(fRoot, 'static-analysis.sarif')), 'no SARIF');
end;

procedure TNativeAnalysisReplayControlTests.SarifValidationFailsBeforeStateMutation;
begin
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Static analysis'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Project: `' + fProject + '`'#10#10 +
    '## FixInsight'#10#10 +
    '- Findings (by code): 1'#10#10 +
    '## Pascal Analyzer'#10#10 +
    '- Version: 9.21.3'#10 +
    '- Compiler target: Delphi 13 (Win64)'#10 +
    '- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0'#10);
  WriteUtf8(TPath.Combine(fRoot, 'fixinsight\fi-findings.jsonl'),
    '{"code": "", "kind": "W", "path": "src/One.pas", "message": "invalid"}'#10);
  AssertRaisesContaining(
    procedure
    begin
      Finalize;
    end, 'SARIF count mismatch');
  Assert.IsFalse(TFile.Exists(TPath.Combine(fRoot, 'baseline.json')), 'no baseline');
  Assert.IsFalse(TFile.Exists(TPath.Combine(fRoot, 'history.jsonl')), 'no history');
  Assert.IsFalse(TFile.Exists(TPath.Combine(fRoot, 'summary.json')), 'no summary.json');
end;

procedure TNativeAnalysisReplayControlTests.RunContextCapturesFixInsightVersion;
var
  g: TGarbos;
  lContext, lSummary: TJSONObject;
begin
  WriteFakeFixInsight;
  GC(lSummary, TJSONObject.Create, g);
  GC(lContext, BuildAnalysisRunContext(fRoot, lSummary), g);
  Assert.AreEqual('2023.12', MemberText(lContext, ['tools', 'fixinsight_version']));
end;

{ TNativeAnalysisReportCommandTests }

procedure TNativeAnalysisReportCommandTests.Setup;
begin
  fRoot := UniqueNoRepoTempPath('native-report-command');
  TDirectory.CreateDirectory(fRoot);
  fEnvironment := SetScopedEnvironmentVariables(['DAK_TRIAGE_SNIPPETS', '', 'DAK_SCOPE', '', 'DAK_TRIAGE_TOP', '',
    'DAK_TRIAGE_INCLUDE_PATHS', '', 'DAK_TRIAGE_EXCLUDE_PATHS', '', 'DAK_PLATFORM', '', 'DAK_CONFIG', '', 'DAK_DELPHI', '']);
end;

procedure TNativeAnalysisReportCommandTests.TearDown;
begin
  fEnvironment := nil;
  if TDirectory.Exists(fRoot) then
    TDirectory.Delete(fRoot, True);
end;

function TNativeAnalysisReportCommandTests.RunReport(const aArguments: string; aExpectedExit: Cardinal): string;
var
  lExe, lLog: string;
  lExitCode: Cardinal;
begin
  lExe := ResolverExePath;
  Assert.IsTrue(TFile.Exists(lExe), 'Expected coordinator-provided candidate: ' + lExe);
  lLog := TPath.Combine(fRoot, 'report-' + TGUID.NewGuid.ToString + '.log');
  Assert.IsTrue(RunCommandProcess(lExe, 'analyze-report ' + aArguments, fRoot, lLog, lExitCode));
  Result := ReadUtf8TextFile(lLog);
  Assert.AreEqual<Cardinal>(aExpectedExit, lExitCode, Result);
end;

procedure TNativeAnalysisReportCommandTests.ReplayThenVerifyThroughTheCommandLine;
var
  g: TGarbos;
  lOutput: string;
  lResult, lSummary: TJSONObject;
begin
  lOutput := TPath.Combine(fRoot, 'out');
  WriteUtf8(TPath.Combine(lOutput, 'Sample.dproj'), '<Project />');
  WriteUtf8(TPath.Combine(lOutput, 'summary.md'),
    '# Static analysis'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Project: `' + TPath.Combine(lOutput, 'Sample.dproj') + '`'#10#10 +
    '## FixInsight'#10#10 +
    '- Findings (by code): 1'#10 +
    '  - W101: 1'#10#10 +
    '## Pascal Analyzer'#10#10 +
    '- Version: 9.21.3'#10 +
    '- Compiler target: Delphi 13 (Win64)'#10 +
    '- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0'#10);
  WriteUtf8(TPath.Combine(lOutput, 'fixinsight\fi-findings.jsonl'),
    '{"tool": "FixInsight", "code": "W101", "kind": "W", "path": "src/One.pas", "line": 10, "col": 2, "message": "warning"}'#10);
  WriteUtf8(TPath.Combine(lOutput, 'pascal-analyzer\pal-findings.jsonl'), '');
  // Like the reference, verification needs the recorded policy context, so the analysis stage's seed is present.
  WriteSchema2SeedFile(lOutput, TPath.Combine(lOutput, 'Sample.dproj'));
  GC(lResult, ParseJsonObject(RunReport('--out ' + QuoteArg(lOutput), 0), 'replay result'), g);
  Assert.IsTrue(TJSONBool(lResult.GetValue('gate_pass')).AsBoolean, 'gate_pass');
  Assert.AreEqual(TPath.Combine(lOutput, 'summary.json'), MemberText(lResult, ['summary_json']));
  GC(lSummary, ParseJsonObject(ReadUtf8(TPath.Combine(lOutput, 'summary.json')), 'summary.json'), g);
  Assert.AreEqual('3', MemberText(lSummary, ['schema_version']));
  Assert.AreEqual('{"ownership": {"project": 0, "repository": 0, "third_party": 0, "unknown": 0}, "verified": true}',
    RunReport('--out ' + QuoteArg(lOutput) + ' --verify', 0).TrimRight);
  // A rejected output reports the reference's message on stderr with exit 3.
  JsonPut(TJSONObject(Member(lSummary, ['counts', 'actionable', 'ownership'])), 'project', TJSONNumber.Create(7));
  WriteUtf8(TPath.Combine(lOutput, 'summary.json'), lSummary.ToJSON);
  Assert.IsTrue(RunReport('--out ' + QuoteArg(lOutput) + ' --verify', 3).Contains('ERROR: summary.json projection mismatch'),
    'rejected verification message');
end;

procedure TNativeAnalysisReportCommandTests.MissingOutIsUsageError;
begin
  Assert.IsTrue(RunReport('--verify', 2).Contains('--out'), 'usage names --out');
end;

// postprocess.py's main() returns 3 only for a rejected result; a replay that raises leaves the
// exception unhandled, so the process reports a broken run instead.
procedure TNativeAnalysisReportCommandTests.BrokenReplayIsNotARejectedResult;
var
  lOutput: string;
begin
  lOutput := TPath.Combine(fRoot, 'broken');
  WriteUtf8(TPath.Combine(lOutput, 'summary.md'),
    '# Static analysis with truncated analyzer sections'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Project: `C:\repo\Sample.dproj`'#10#10 +
    '## FixInsight'#10#10'## Pascal Analyzer'#10);
  Assert.IsTrue(RunReport('--out ' + QuoteArg(lOutput), 1).Contains('Invalid analysis summary'),
    'a broken replay reports the parse failure');
  Assert.IsFalse(TFile.Exists(TPath.Combine(lOutput, 'summary.json')), 'no summary.json');
end;

// --baseline selects where the policy stage reads and writes the accepted baseline.
procedure TNativeAnalysisReportCommandTests.BaselineSwitchSelectsTheBaselineFile;
var
  lBaseline, lOutput: string;
begin
  lOutput := TPath.Combine(fRoot, 'selected');
  WriteUtf8(TPath.Combine(lOutput, 'Sample.dproj'), '<Project />');
  WriteUtf8(TPath.Combine(lOutput, 'summary.md'),
    '# Static analysis'#10#10 +
    '- Timestamp: 2026-07-16T10:00:00Z'#10 +
    '- Project: `' + TPath.Combine(lOutput, 'Sample.dproj') + '`'#10#10 +
    '## FixInsight'#10#10 +
    '- Findings (by code): 1'#10 +
    '  - W101: 1'#10#10 +
    '## Pascal Analyzer'#10#10 +
    '- Version: 9.21.3'#10 +
    '- Compiler target: Delphi 13 (Win64)'#10 +
    '- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0'#10);
  WriteUtf8(TPath.Combine(lOutput, 'fixinsight' + PathDelim + 'fi-findings.jsonl'),
    '{"tool": "FixInsight", "code": "W101", "kind": "W", "path": "src/One.pas", "line": 10, "col": 2, "message": "warning"}'#10);
  WriteUtf8(TPath.Combine(lOutput, 'pascal-analyzer\pal-findings.jsonl'), '');
  lBaseline := TPath.Combine(fRoot, 'chosen-baseline.json');
  RunReport('--out ' + QuoteArg(lOutput) + ' --baseline ' + QuoteArg(lBaseline), 0);
  Assert.IsTrue(TFile.Exists(lBaseline), 'the selected baseline file is written');
  Assert.IsFalse(TFile.Exists(TPath.Combine(lOutput, 'baseline.json')), 'the default baseline is not written');
  Assert.IsTrue(TFile.Exists(TPath.ChangeExtension(lBaseline, '.md')), 'its Markdown view sits beside it');
  Assert.IsTrue(RunReport('--out ' + QuoteArg(lOutput) + ' --baseline', 2).Contains('Missing value for parameter'),
    '--baseline without a path is a usage error');
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisVerifyTests);
  TDUnitX.RegisterTestFixture(TNativeAnalysisReplayControlTests);
  TDUnitX.RegisterTestFixture(TNativeAnalysisReportCommandTests);

end.
