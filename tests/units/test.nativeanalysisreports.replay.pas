unit Test.NativeAnalysisReports.Replay;

interface

uses
  DUnitX.TestFramework;

type
  // Replays the pinned report-small seed with the native finalizer and compares the T-324-owned
  // artifacts with the retained Python 3.13.15 reference bytes. Only the T-321 allowance is
  // normalized: the triage timestamp, the recorded engine identity and the policy-owned fields.
  [TestFixture]
  TNativeAnalysisReplayTests = class
  public
    [TestCase('report-small', 'report-small')]
    [TestCase('report-large', 'report-large')]
    procedure ReplayMatchesPinnedReference(const aScenario: string);
  end;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.JSON, System.RegularExpressions,
  System.SysUtils,
  AutoFree,
  Dak.Analysis.JsonText, Dak.Analysis.ReportBundle, Dak.Analysis.ReportReplay,
  Test.Support;

const
  cMigrationRoot = 'projects\.dak\DelphiAIKit\native-analysis-migration';
  // The complete published set: the report artifacts (T-324) and the six the policy stage owns
  // (T-325). These must be byte-identical to the retained Python reference.
  cExactArtifacts: array[0..9] of string = ('fixinsight\fi-findings.jsonl', 'pascal-analyzer\pal-findings.jsonl',
    'summary.md', 'static-analysis.sarif', 'static-analysis.full.sarif', 'external-summary.md', 'metrics.md',
    'baseline.md', 'delta.md', 'run.log');
  // Documents that record which engine produced the run; only that identity may differ.
  cIdentityArtifacts: array[0..2] of string = ('summary.json', 'baseline.json', 'delta.json');
  // Artifacts whose generated clock is the only allowed difference.
  cClockArtifacts: array[0..2] of string = ('triage.md', 'trend.md', 'history.jsonl');

function MigrationPath(const aRelative: string): string;
begin
  Result := TPath.Combine(TPath.Combine(RepoRoot, cMigrationRoot), aRelative);
end;

function Visible(const aText: string): string;
begin
  Result := aText.Replace(#13, '<CR>').Replace(#10, '<LF>' + sLineBreak);
end;

procedure CopyTree(const aSource, aDestination: string);
var
  lFile, lTarget: string;
begin
  for lFile in TDirectory.GetFiles(aSource, '*', TSearchOption.soAllDirectories) do
  begin
    lTarget := TPath.Combine(aDestination, lFile.Substring(Length(IncludeTrailingPathDelimiter(aSource))));
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTarget));
    TFile.Copy(lFile, lTarget);
  end;
end;

// The generated clocks: triage.md's timestamp, trend.md's update line and the history row's own timestamp.
function NormalizeClocks(const aText: string): string;
begin
  Result := TRegEx.Replace(aText, '^- Timestamp: .*$', '- Timestamp: <normalized>', [roMultiLine]);
  Result := TRegEx.Replace(Result, '^- Updated: .*$', '- Updated: <normalized>', [roMultiLine]);
  Result := TRegEx.Replace(Result, '"timestamp": "[^"]*"', '"timestamp": "<normalized>"');
end;

// Removes what identifies the engine that produced the run, wherever it appears: the DAK
// executable identity, the compatibility fingerprint that covers it, and the interpreter and
// operating-system facts of the host. Everything else must match the reference exactly.
procedure StripEngineIdentity(aValue: TJSONValue);
var
  lItem: TJSONValue;
  lName: string;
  lPair: TJSONPair;
begin
  if aValue is TJSONObject then
  begin
    for lName in ['dak', 'compatibility', 'host'] do
      if TJSONObject(aValue).GetValue(lName) <> nil then
        TJSONObject(aValue).RemovePair(lName).Free;
    for lPair in TJSONObject(aValue) do
      StripEngineIdentity(lPair.JsonValue);
  end else if aValue is TJSONArray then
    for lItem in TJSONArray(aValue) do
      StripEngineIdentity(lItem);
end;

function NormalizeEngineIdentity(const aText, aContext: string): string;
var
  g: TGarbos;
  lDocument: TJSONObject;
begin
  GC(lDocument, ParseJsonObject(aText, aContext), g);
  StripEngineIdentity(lDocument);
  Result := TPythonJson.Document(lDocument);
end;

procedure TNativeAnalysisReplayTests.ReplayMatchesPinnedReference(const aScenario: string);
var
  g: TGarbos;
  lArtifact, lOutput, lReference, lSeed: string;
  lResult: TJSONObject;
  lExpected, lActual: TBytes;
begin
  lSeed := MigrationPath('seeds\' + aScenario);
  lReference := MigrationPath('measurements\report-baseline-01\' + aScenario + '\cold-1\artifacts');
  Assert.IsTrue(TDirectory.Exists(lSeed) and TDirectory.Exists(lReference),
    'The pinned ' + aScenario + ' seed and reference must exist under ' + MigrationPath(''));
  // The seed's summary names the scratch repository, so the replay output lives beside it.
  lOutput := MigrationPath('scratch\' + aScenario + '\repo\.dak\Sample\policy');
  Assert.IsFalse(TDirectory.Exists(lOutput), 'Scratch output already exists; inspect it before rerunning: ' + lOutput);
  CopyTree(lSeed, lOutput);
  try
    GC(lResult, FinalizeAnalysisReport(lOutput, nil, -1), g);
    Assert.IsTrue(lResult.GetValue('summary_json') <> nil, 'finalization must report summary.json');
    for lArtifact in cExactArtifacts do
    begin
      lExpected := TFile.ReadAllBytes(TPath.Combine(lReference, lArtifact));
      lActual := TFile.ReadAllBytes(TPath.Combine(lOutput, lArtifact));
      Assert.AreEqual(Visible(TEncoding.UTF8.GetString(lExpected)), Visible(TEncoding.UTF8.GetString(lActual)),
        lArtifact + ' must be byte-identical to the reference');
      Assert.AreEqual(Integer(Length(lExpected)), Integer(Length(lActual)), lArtifact + ' byte length');
    end;
    for lArtifact in cClockArtifacts do
      Assert.AreEqual(Visible(NormalizeClocks(TFile.ReadAllText(TPath.Combine(lReference, lArtifact), TEncoding.UTF8))),
        Visible(NormalizeClocks(TFile.ReadAllText(TPath.Combine(lOutput, lArtifact), TEncoding.UTF8))),
        lArtifact + ' must match apart from its generated clock');
    for lArtifact in cIdentityArtifacts do
      Assert.AreEqual(
        Visible(NormalizeEngineIdentity(TFile.ReadAllText(TPath.Combine(lReference, lArtifact), TEncoding.UTF8), lArtifact)),
        Visible(NormalizeEngineIdentity(TFile.ReadAllText(TPath.Combine(lOutput, lArtifact), TEncoding.UTF8), lArtifact)),
        lArtifact + ' must match apart from the engine identity');
    Assert.IsFalse(TFile.Exists(TPath.Combine(lOutput, 'triage-changed.md')), 'no changed-file triage without DAK_SCOPE');
    Assert.IsFalse(TFile.Exists(TPath.Combine(lOutput, 'triage-snippets.md')), 'no snippets without DAK_TRIAGE_SNIPPETS');
  finally
    TDirectory.Delete(lOutput, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisReplayTests);

end.
