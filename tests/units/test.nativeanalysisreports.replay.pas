unit Test.NativeAnalysisReports.Replay;

interface

uses
  DUnitX.TestFramework;

type
  // Replays the pinned report-small seed with the native finalizer and compares the T-324-owned
  // artifacts with the retained Python 3.13.15 reference bytes. Only the T-321 allowance is
  // normalized: the triage timestamp, the recorded engine identity and the policy-owned fields.
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisReplayTests = class
  public
    [TestCase('report-small', 'report-small')]
    [TestCase('report-large', 'report-large')]
    procedure ReplayMatchesPinnedReference(const aScenario: string);
  end;

  [TestFixture]
  [Category('Fast')]
  TMigrationRelocationTests = class
  public
    [Test]
    procedure CanonicalRootsArePortable;
    [Test]
    procedure EmbeddedNonCanonicalRootIsUnchanged;
    [TestCase('suffix', 'suffix')]
    [TestCase('finding', 'finding')]
    [TestCase('other-root', 'other-root')]
    procedure UnapprovedDifferencesRemainVisible(const aMutation: string);
  end;

function MigrationPath(const aRelative: string): string;
function NormalizeCanonicalRoot(const aText, aRoot, aPlaceholder: string): string;

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
var
  lRoot: string;
begin
  lRoot := GetEnvironmentVariable('DAK_TEST_MIGRATION_ROOT');
  if lRoot = '' then
    lRoot := TPath.Combine(RepoRoot, cMigrationRoot);
  Result := TPath.Combine(lRoot, aRelative);
end;

function NormalizeCanonicalRoot(const aText, aRoot, aPlaceholder: string): string;
var
  lVariant: string;
begin
  Result := aText;
  if aRoot = '' then
    Exit;
  // Exact, case-sensitive root plus a path/serialization boundary; never a sibling prefix.
  for lVariant in [aRoot.Replace('\', '\\'), aRoot.Replace('\', '/'), aRoot] do
    Result := TRegEx.Replace(Result, '(?<![\w\\/:.-])' + TRegEx.Escape(lVariant) + '(?=[\\/"`]|$)', aPlaceholder);
end;

function NormalizeMigrationPaths(const aText, aScenario: string): string;
var
  lCanonicalCheckout: string;
  lCanonicalRepo: string;
  lLocalRepo: string;
begin
  lCanonicalCheckout := TFile.ReadAllText(MigrationPath('canonical-checkout.txt'), TEncoding.UTF8);
  lCanonicalRepo := TPath.Combine(lCanonicalCheckout, cMigrationRoot + '\scratch\' + aScenario + '\repo');
  lLocalRepo := MigrationPath('scratch\' + aScenario + '\repo');
  Result := NormalizeCanonicalRoot(aText, TPath.Combine(lCanonicalRepo, '.dak\Sample\policy'), '<output>');
  Result := NormalizeCanonicalRoot(Result, TPath.Combine(lLocalRepo, '.dak\Sample\policy'), '<output>');
  Result := NormalizeCanonicalRoot(Result, lCanonicalRepo, '<scratch-repo>');
  Result := NormalizeCanonicalRoot(Result, lLocalRepo, '<scratch-repo>');
  Result := NormalizeCanonicalRoot(Result, lCanonicalCheckout, '<checkout>');
  Result := NormalizeCanonicalRoot(Result, RepoRoot, '<checkout>');
end;

procedure TMigrationRelocationTests.CanonicalRootsArePortable;
begin
  Assert.AreEqual('<repo>\src\Owned.pas warning 10',
    NormalizeCanonicalRoot('F:\canonical\repo\src\Owned.pas warning 10', 'F:\canonical\repo', '<repo>'));
end;

procedure TMigrationRelocationTests.EmbeddedNonCanonicalRootIsUnchanged;
const
  cEmbedded = 'X:\archive\F:\canonical\repo\src\Owned.pas';
  cSibling = 'F:\canonical\repo-other\src\Owned.pas';
begin
  Assert.AreEqual(cEmbedded, NormalizeCanonicalRoot(cEmbedded, 'F:\canonical\repo', '<repo>'));
  Assert.AreEqual(cSibling, NormalizeCanonicalRoot(cSibling, 'F:\canonical\repo', '<repo>'));
end;

procedure TMigrationRelocationTests.UnapprovedDifferencesRemainVisible(const aMutation: string);
var
  lActual: string;
  lExpected: string;
begin
  lExpected := 'F:\canonical\repo\src\Owned.pas warning 10';
  lActual := lExpected;
  if aMutation = 'suffix' then
    lActual := lActual.Replace('Owned.pas', 'Other.pas')
  else if aMutation = 'finding' then
    lActual := lActual.Replace('warning 10', 'warning 11')
  else
    lActual := lActual.Replace('repo\', 'repo-other\');
  Assert.AreNotEqual(NormalizeCanonicalRoot(lExpected, 'F:\canonical\repo', '<repo>'),
    NormalizeCanonicalRoot(lActual, 'F:\canonical\repo', '<repo>'));
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
      Assert.AreEqual(Visible(NormalizeMigrationPaths(TEncoding.UTF8.GetString(lExpected), aScenario)),
        Visible(NormalizeMigrationPaths(TEncoding.UTF8.GetString(lActual), aScenario)),
        lArtifact + ' must be byte-identical to the reference');
      Assert.AreEqual(Length(TEncoding.UTF8.GetBytes(NormalizeMigrationPaths(TEncoding.UTF8.GetString(lExpected), aScenario))),
        Length(TEncoding.UTF8.GetBytes(NormalizeMigrationPaths(TEncoding.UTF8.GetString(lActual), aScenario))),
        lArtifact + ' normalized byte length');
    end;
    for lArtifact in cClockArtifacts do
      Assert.AreEqual(Visible(NormalizeMigrationPaths(NormalizeClocks(TFile.ReadAllText(TPath.Combine(lReference, lArtifact), TEncoding.UTF8)), aScenario)),
        Visible(NormalizeMigrationPaths(NormalizeClocks(TFile.ReadAllText(TPath.Combine(lOutput, lArtifact), TEncoding.UTF8)), aScenario)),
        lArtifact + ' must match apart from its generated clock');
    for lArtifact in cIdentityArtifacts do
      Assert.AreEqual(
        Visible(NormalizeMigrationPaths(NormalizeEngineIdentity(TFile.ReadAllText(TPath.Combine(lReference, lArtifact), TEncoding.UTF8), lArtifact), aScenario)),
        Visible(NormalizeMigrationPaths(NormalizeEngineIdentity(TFile.ReadAllText(TPath.Combine(lOutput, lArtifact), TEncoding.UTF8), lArtifact), aScenario)),
        lArtifact + ' must match apart from the engine identity');
    Assert.IsFalse(TFile.Exists(TPath.Combine(lOutput, 'triage-changed.md')), 'no changed-file triage without DAK_SCOPE');
    Assert.IsFalse(TFile.Exists(TPath.Combine(lOutput, 'triage-snippets.md')), 'no snippets without DAK_TRIAGE_SNIPPETS');
  finally
    TDirectory.Delete(lOutput, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisReplayTests);
  TDUnitX.RegisterTestFixture(TMigrationRelocationTests);

end.
