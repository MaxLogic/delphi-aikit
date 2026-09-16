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
  cExactArtifacts: array[0..6] of string = ('fixinsight\fi-findings.jsonl', 'pascal-analyzer\pal-findings.jsonl',
    'summary.md', 'static-analysis.sarif', 'static-analysis.full.sarif', 'external-summary.md', 'metrics.md');

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

function NormalizeTriage(const aText: string): string;
begin
  Result := TRegEx.Replace(aText, '^- Timestamp: .*$', '- Timestamp: <normalized>', [roMultiLine]);
end;

// Removes the policy-owned members (T-325) and the recorded engine identity before comparison.
function NormalizeSummaryJson(const aText: string): string;
var
  g: TGarbos;
  lArtifacts, lDocument, lProvenance, lStatus: TJSONObject;
  lName: string;
begin
  GC(lDocument, ParseJsonObject(aText, 'summary.json'), g);
  lArtifacts := JsonObjectMember(lDocument, 'artifacts');
  if lArtifacts <> nil then
    for lName in ['baseline', 'delta', 'history', 'trend'] do
      lArtifacts.RemovePair(lName).Free;
  lStatus := JsonObjectMember(lDocument, 'status');
  if lStatus <> nil then
    lStatus.RemovePair('policy').Free;
  lProvenance := JsonObjectMember(lDocument, 'provenance');
  if lProvenance <> nil then
    lProvenance.RemovePair('dak').Free;
  lDocument.RemovePair('compatibility').Free;
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
    Assert.AreEqual(Visible(NormalizeTriage(TFile.ReadAllText(TPath.Combine(lReference, 'triage.md'), TEncoding.UTF8))),
      Visible(NormalizeTriage(TFile.ReadAllText(TPath.Combine(lOutput, 'triage.md'), TEncoding.UTF8))),
      'triage.md must match apart from its generated timestamp');
    Assert.AreEqual(Visible(NormalizeSummaryJson(TFile.ReadAllText(TPath.Combine(lReference, 'summary.json'), TEncoding.UTF8))),
      Visible(NormalizeSummaryJson(TFile.ReadAllText(TPath.Combine(lOutput, 'summary.json'), TEncoding.UTF8))),
      'summary.json must match apart from policy-owned members and the engine identity');
    Assert.IsFalse(TFile.Exists(TPath.Combine(lOutput, 'triage-changed.md')), 'no changed-file triage without DAK_SCOPE');
    Assert.IsFalse(TFile.Exists(TPath.Combine(lOutput, 'triage-snippets.md')), 'no snippets without DAK_TRIAGE_SNIPPETS');
  finally
    TDirectory.Delete(lOutput, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisReplayTests);

end.
