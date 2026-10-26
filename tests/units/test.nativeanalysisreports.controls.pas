unit Test.NativeAnalysisReports.Controls;

interface

uses
  DUnitX.TestFramework;

type
  // Report finalization controls from test_ai_reporting.py, test_failure_integrity.py,
  // test_pal_rule_policy.py and test_workspace_provenance.py that the replay and policy fixtures
  // did not already assert, driven through the native services on real files and Git working copies.
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisReportControlTests = class
  private
    fRoot: string;
    fEnvironment: IInterface;
    procedure CheckPalCatalogLongXml(const aLongRoot: Boolean);
    function PalCatalogProjection(const aRoot: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SummaryErrorsAreParsed;
    [Test]
    procedure StaleSeedSubjectFailsBeforeBaselineMutation;
    [Test]
    procedure MalformedSeedFailsBeforeBaselineAndHistoryMutation;
    [Test]
    procedure NonObjectBaselineSectionsFailWithoutMutation;
    [Test]
    procedure PalNotRequestedDiscardsRetainedPalEvidence;
    [Test]
    procedure PalRuleIdentityKeepsExactReportAndSectionDistinctions;
    [Test]
    procedure PalCatalogLongXmlFileKeepsRuleResolution;
    [Test]
    procedure PalCatalogLongXmlRootKeepsRuleResolution;
    [TestCase('Utf16Bom', '0,False')]
    [TestCase('Windows1252', '1,False')]
    [TestCase('Utf8Bom', '2,False')]
    [TestCase('Utf16BomLongPath', '0,True')]
    [TestCase('Windows1252LongPath', '1,True')]
    procedure PalCatalogXmlEncodingKeepsRuleResolution(aVariant: Integer; aLong: Boolean);
    [TestCase('Empty', '')]
    [TestCase('Whitespace', '   ')]
    procedure PalCatalogEmptyRootMeansNoCatalog(const aRoot: string);
    [Test]
    procedure PalRuleIdentitySurvivesSummarySarifAndFingerprint;
    [Test]
    procedure FixInsightFilterCannotSuppressPascalAnalyzerRule;
    [Test]
    procedure PalFilterStaysInBaselineAndDeltaContract;
    [Test]
    procedure ChangedFileTriageUsesExactPathBeforeUniqueModuleFallback;
    [Test]
    procedure ChangedFileTriageUsesSvnProvenanceWithoutGit;
    [Test]
    procedure ChangedFileTriageIsNotApplicableWithoutVcs;
    [Test]
    procedure GitChangedFilesKeepRenameTargetAndFullUntrackedPath;
    [Test]
    procedure Schema2ProvenanceTracksDirtySourcesAndRecursiveSubmodules;
    [Test]
    procedure MissingSvnCliKeepsFinalizationComplete;
    [Test]
    procedure FailedSummaryKeepsItsPalVersionWithoutATotal;
    [Test]
    procedure AdvisoryMetricsRequireExplicitPolicyOptIn;
  end;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows,
  AutoFree,
  Dak.Analysis.JsonText, Dak.Analysis.Projections, Dak.Analysis.ReportBundle, Dak.Analysis.ReportPolicy,
  Dak.Analysis.ReportReplay, Dak.Analysis.ReportVerify, Dak.Analysis.ReportWriters, Dak.Analysis.Workspace,
  Dak.Settings, Dak.Utils,
  Test.Support;

const
  cIgnoredRule = 'PAL.warnings.set-before-passed-as-out-parameter-1f0b5be50a52e864';
  cStrongRule = 'PAL.strong-warnings.possible-bad-typecast-for-objects-consider-using-as-2f1b8d64c282a875';
  cExpectedAliases = '{"OPTI8": "PAL.optimization.parameter-is-var-can-be-changed-to-out-8d547169dfe78c92", ' +
    '"STWA6": "' + cStrongRule + '", "WARN54": "' + cIgnoredRule + '"}';

procedure WriteUtf8(const aPath, aText: string);
begin
  TDirectory.CreateDirectory(TPath.GetDirectoryName(aPath));
  TFile.WriteAllBytes(aPath, TEncoding.UTF8.GetBytes(aText));
end;

function ReadUtf8(const aPath: string): string;
begin
  Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(aPath));
end;

function Escaped(const aPath: string): string;
begin
  Result := aPath.Replace('\', '\\');
end;

function ReadJson(const aPath: string): TJSONObject;
begin
  Result := ParseJsonObject(ReadUtf8(aPath), aPath);
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
var
  lValue: TJSONValue;
begin
  lValue := Member(aObject, aPath);
  if lValue is TJSONBool then
    Exit(BoolToStr(TJSONBool(lValue).AsBoolean, True));
  Result := lValue.Value;
end;

procedure AssertJsonEquals(const aExpected: string; aActual: TJSONValue; const aMessage: string);
var
  g: TGarbos;
  lExpected: TJSONValue;
begin
  GC(lExpected, ParseJsonValue(aExpected), g);
  Assert.IsTrue(AnalysisJsonEquivalent(lExpected, aActual), aMessage + ': ' + TPythonJson.Compact(aActual));
end;

procedure AssertBytesUnchanged(const aPath: string; const aBefore: TBytes);
var
  lAfter: TBytes;
begin
  lAfter := TFile.ReadAllBytes(aPath);
  Assert.IsTrue((Length(lAfter) = Length(aBefore)) and
    ((Length(lAfter) = 0) or CompareMem(@lAfter[0], @aBefore[0], Length(lAfter))), aPath + ' is unchanged');
end;

function RuleRows(aDocument: TJSONObject; const aField: string): TJSONArray;
begin
  Result := Member(aDocument, ['pascal_analyzer', aField]) as TJSONArray;
end;

procedure RewriteJson(const aPath, aOriginal: string; aMutation: TProc<TJSONObject>);
var
  lDocument: TJSONObject;
begin
  lDocument := ParseJsonObject(aOriginal, aPath);
  try
    aMutation(lDocument);
    WriteUtf8(aPath, lDocument.ToJSON);
  finally
    lDocument.Free;
  end;
end;

function VerifyProc(const aOutRoot: string): TProc;
begin
  Result :=
    procedure
    begin
      VerifyAnalysisReport(aOutRoot).Free;
    end;
end;

// assertRaisesRegex with ordered fragments, as the reference patterns match them.
procedure AssertRaisesContaining(aProc: TProc; const aFragments: array of string);
var
  lFragment: string;
  lPosition, lNext: Integer;
begin
  try
    aProc;
    Assert.Fail('expected EConvertError containing "' + String.Join('...', aFragments) + '"');
  except
    on e: EConvertError do
    begin
      lPosition := 1;
      for lFragment in aFragments do
      begin
        lNext := Pos(lFragment, e.Message, lPosition);
        Assert.IsTrue(lNext > 0, 'expected "' + lFragment + '" in: ' + e.Message);
        lPosition := lNext + Length(lFragment);
      end;
    end;
  end;
end;

function GitExecutable: string;
begin
  Result := FileSearch('git.exe', GetEnvironmentVariable('PATH'));
  Assert.IsTrue(Result <> '', 'git.exe must be on PATH for this fixture');
end;

procedure Git(const aRepo, aArguments: string);
var
  lExitCode: Cardinal;
  lLog: string;
begin
  lLog := TPath.Combine(TPath.GetTempPath, 'dak-git-' + TGUID.NewGuid.ToString + '.log');
  try
    Assert.IsTrue(RunCommandProcess(GitExecutable, aArguments, aRepo, lLog, lExitCode), 'git must run: ' + aArguments);
    Assert.AreEqual<Cardinal>(0, lExitCode, 'git ' + aArguments + ': ' + ReadUtf8(lLog));
  finally
    if TFile.Exists(lLog) then
      TFile.Delete(lLog);
  end;
end;

procedure Commit(const aRepo, aMessage: string);
begin
  Git(aRepo, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm "' + aMessage + '"');
end;

// write_summary and finding_streams of test_ai_reporting.py.
procedure WriteReportingRun(const aOutRoot, aProject: string);
begin
  WriteUtf8(TPath.Combine(aOutRoot, 'summary.md'),
    '# Static analysis'#10#10'- Timestamp: 2026-07-16T10:00:00Z'#10'- Project: `' + aProject + '`'#10#10 +
    '## FixInsight'#10#10'- Findings (by code): 2'#10'  - W101: 1'#10'  - C102: 1'#10#10 +
    '## Pascal Analyzer'#10#10'- Version: 9.21.3'#10'- Compiler target: Delphi 13 (Win64)'#10 +
    '- Totals: warnings=1, strong_warnings=1, optimizations=1, total=3'#10);
  WriteUtf8(TPath.Combine(aOutRoot, 'fixinsight\fi-findings.jsonl'),
    '{"tool": "FixInsight", "code": "W101", "kind": "W", "path": "src/One.pas", "line": 10, "col": 2, "message": "warning"}'#10 +
    '{"tool": "FixInsight", "code": "C102", "kind": "C", "path": null, "line": 1, "col": 1, "message": "maintainability"}'#10);
  WriteUtf8(TPath.Combine(aOutRoot, 'pascal-analyzer\pal-findings.jsonl'),
    '{"severity": "warning", "section": "Warnings", "module": "One", "path": "src/One.pas", "line": 20, "message": "warning"}'#10 +
    '{"severity": "strong-warning", "section": "Strong warnings", "module": "Two", "path": "src/Two.pas", "line": 30, "message": "strong warning"}'#10 +
    '{"severity": "optimization", "section": "Optimizations", "module": "Three", "path": null, "line": 40, "message": "optimization"}'#10);
  WriteUtf8(TPath.Combine(aOutRoot, 'summary.json'),
    '{"schema_version": 2, "status": {"infrastructure": "complete", "policy": "not_evaluated"}, ' +
    '"subject": {"kind": "project", "path": "' + Escaped(aProject) + '"}, ' +
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

function PalRow(const aSeverity, aReport, aSection: string): TJSONObject;
begin
  Result := TJSONObject.Create.AddPair('severity', aSeverity).AddPair('report', aReport)
    .AddPair('section', aSection).AddPair('ownership', 'project');
end;

function PolicyObject(const aJson: string): TJSONObject;
begin
  Result := ParseJsonObject(aJson, 'policy');
end;

{ TNativeAnalysisReportControlTests }

procedure TNativeAnalysisReportControlTests.Setup;
begin
  fRoot := UniqueNoRepoTempPath('native-report-controls');
  TDirectory.CreateDirectory(fRoot);
  // Finalization reads its policy controls from the environment; each case starts from a known state.
  fEnvironment := SetScopedEnvironmentVariables(['DAK_BASELINE', '', 'DAK_GATE', '0', 'DAK_CI', '0',
    'DAK_UPDATE_BASELINE', '0', 'DAK_GATE_REQUIRE_CONTEXT_MATCH', '0', 'DAK_GATE_INCLUDE_PATHS', '',
    'DAK_GATE_EXCLUDE_PATHS', '', 'DAK_MAX_FI_TOTAL_INCREASE', '', 'DAK_MAX_PAL_WARNING_INCREASE', '',
    'DAK_MAX_NEW_FI_W', '', 'DAK_MAX_NEW_PAL_STRONG', '', 'DAK_SCOPE', '', 'DAK_TRIAGE_SNIPPETS', '',
    'DAK_TREND_N', '', 'DAK_SVN_EXE', '']);
end;

procedure TNativeAnalysisReportControlTests.TearDown;
begin
  fEnvironment := nil;
  if TDirectory.Exists(fRoot) then
    DeleteTempPath(fRoot);
end;

procedure TNativeAnalysisReportControlTests.CheckPalCatalogLongXml(const aLongRoot: Boolean);
const
  cCatalogXml = '<?xml version="1.0" encoding="utf-8"?>' +
    '<report><section name="Catalog-only café" /></report>';
var
  g: TGarbos;
  lCatalogRow, lLongPolicy, lShortPolicy: TJSONObject;
  lLongDirectory: string;
  lLongFile: string;
  lLongRoot: string;
  lRule: string;
  lShortFile: string;
  lShortRoot: string;
  lLongFi, lLongPal, lShortFi, lShortPal: TJSONArray;
begin
  lShortRoot := TPath.Combine(fRoot, 'pal-catalog-short');
  TDirectory.CreateDirectory(lShortRoot);
  lShortFile := TPath.Combine(lShortRoot, 'Bindings.xml');
  WriteUtf8(lShortFile, cCatalogXml);

  lLongRoot := TPath.Combine(fRoot, 'pal-catalog-long');
  TDirectory.CreateDirectory(lLongRoot);
  lLongDirectory := lLongRoot;
  if aLongRoot then
  begin
    while Length(lLongRoot) <= 300 do
    begin
      lLongRoot := TPath.Combine(lLongRoot, StringOfChar('x', 70));
      TDirectory.CreateDirectory(LongPathSafe(lLongRoot));
    end;
    lLongDirectory := lLongRoot;
  end else
  begin
    while Length(TPath.Combine(lLongDirectory, 'Bindings.xml')) <= 300 do
    begin
      lLongDirectory := TPath.Combine(lLongDirectory, StringOfChar('x', 70));
      TDirectory.CreateDirectory(LongPathSafe(lLongDirectory));
    end;
    Assert.IsTrue(Length(lLongRoot) < MAX_PATH, 'The catalog root must stay enumerable.');
  end;
  lLongFile := TPath.Combine(lLongDirectory, 'Bindings.xml');
  Assert.IsTrue(Length(lLongFile) > 300, 'The catalog XML filename must exceed 300 characters.');
  TFile.Copy(lShortFile, LongPathSafe(lLongFile));
  Assert.IsTrue(TFile.Exists(LongPathSafe(lLongFile)), 'Long catalog XML fixture setup failed.');
  AssertBytesUnchanged(LongPathSafe(lLongFile), TFile.ReadAllBytes(lShortFile));

  GC(lCatalogRow, PalRow('warning', 'Bindings.xml', 'Catalog-only café'), g);
  lRule := AnalysisNormalizedRuleId(lCatalogRow);
  GC(lShortPolicy, PolicyObject('{"gate_ownership": ["project"], "pal_ignore_rules": ["' +
    lRule + '"]}'), g);
  GC(lLongPolicy, PolicyObject('{"gate_ownership": ["project"], "pal_ignore_rules": ["' +
    lRule + '"]}'), g);
  GC(lShortFi, TJSONArray.Create, g);
  GC(lLongFi, TJSONArray.Create, g);
  GC(lShortPal, TJSONArray.Create, g);
  GC(lLongPal, TJSONArray.Create, g);
  lShortPal.AddElement(PalRow('warning', 'Warnings.xml', 'Unrelated rule'));
  lLongPal.AddElement(PalRow('warning', 'Warnings.xml', 'Unrelated rule'));
  ApplyAnalysisReportProjections(lShortFi, lShortPal, lShortPolicy, [], '', lShortRoot, True);
  Assert.AreEqual('actionable', JsonText(TJSONObject(lShortPal.Items[0]), 'report_projection'));
  ApplyAnalysisReportProjections(lLongFi, lLongPal, lLongPolicy, [], '', lLongRoot, True);
  Assert.AreEqual(lShortPal.ToJSON, lLongPal.ToJSON);
end;

function TNativeAnalysisReportControlTests.PalCatalogProjection(const aRoot: string): string;
var
  g: TGarbos;
  lPal, lFi: TJSONArray;
  lPolicy, lRow: TJSONObject;
begin
  GC(lRow, PalRow('warning', 'Bindings.xml', 'Catalog-only café'), g);
  GC(lPolicy, PolicyObject('{"gate_ownership": ["project"], "pal_ignore_rules": ["' +
    AnalysisNormalizedRuleId(lRow) + '"]}'), g);
  GC(lFi, TJSONArray.Create, g);
  GC(lPal, TJSONArray.Create, g);
  lPal.AddElement(PalRow('warning', 'Warnings.xml', 'Unrelated rule'));
  ApplyAnalysisReportProjections(lFi, lPal, lPolicy, [], '', aRoot, True);
  Result := lPal.ToJSON;
end;

procedure TNativeAnalysisReportControlTests.PalCatalogXmlEncodingKeepsRuleResolution(aVariant: Integer;
  aLong: Boolean);
const
  cBody = '<report><section name="Catalog-only café" /></report>';
var
  lBytes, lPreamble: TBytes;
  lDirectory, lFile, lBaseline, lRoot: string;
  lEncoding: TEncoding;
begin
  // Every variant must resolve the same non-ASCII rule as the UTF-8 baseline through the stream loader.
  lRoot := TPath.Combine(fRoot, 'pal-enc-base');
  WriteUtf8(TPath.Combine(lRoot, 'Bindings.xml'), '<?xml version="1.0" encoding="utf-8"?>' + cBody);
  lBaseline := PalCatalogProjection(lRoot);
  Assert.IsTrue(lBaseline.Contains('"actionable"'), 'Baseline projection must be real.');

  lRoot := TPath.Combine(fRoot, 'pal-enc-variant');
  lDirectory := lRoot;
  if aLong then
    while Length(TPath.Combine(lDirectory, 'Bindings.xml')) <= 300 do
    begin
      lDirectory := TPath.Combine(lDirectory, StringOfChar('x', 70));
      TDirectory.CreateDirectory(LongPathSafe(lDirectory));
    end
  else
    TDirectory.CreateDirectory(lDirectory);
  lFile := TPath.Combine(lDirectory, 'Bindings.xml');
  case aVariant of
    0: begin
      lEncoding := TEncoding.Unicode;
      lBytes := lEncoding.GetBytes('<?xml version="1.0" encoding="utf-16"?>' + cBody);
    end;
    1: begin
      lEncoding := TEncoding.GetEncoding(1252);
      try
        lBytes := lEncoding.GetBytes('<?xml version="1.0" encoding="windows-1252"?>' + cBody);
      finally
        lEncoding.Free;
      end;
      Assert.IsTrue(TArray.IndexOf<Byte>(lBytes, $E9) >= 0, 'Fixture must contain the ANSI e-acute byte.');
      lEncoding := nil;
    end;
  else
    lEncoding := TEncoding.UTF8;
    lBytes := lEncoding.GetBytes('<?xml version="1.0" encoding="utf-8"?>' + cBody);
  end;
  if (aVariant <> 1) and (lEncoding <> nil) then
  begin
    lPreamble := lEncoding.GetPreamble;
    lBytes := lPreamble + lBytes;
  end;
  TFile.WriteAllBytes(LongPathSafe(lFile), lBytes);
  if aLong then
    Assert.IsTrue(Length(lFile) > 300, 'The catalog XML filename must exceed 300 characters.');
  Assert.AreEqual(lBaseline, PalCatalogProjection(lRoot));
end;

procedure TNativeAnalysisReportControlTests.PalCatalogLongXmlFileKeepsRuleResolution;
begin
  CheckPalCatalogLongXml(False);
end;

procedure TNativeAnalysisReportControlTests.PalCatalogLongXmlRootKeepsRuleResolution;
begin
  CheckPalCatalogLongXml(True);
end;

procedure TNativeAnalysisReportControlTests.SummaryErrorsAreParsed;
var
  g: TGarbos;
  lSummary: TJSONObject;
begin
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Static analysis'#10#10'## Errors'#10#10'- FixInsight TXT failed (exit=1).'#10'- Pascal Analyzer failed (exit=99).'#10);
  GC(lSummary, ParseAnalysisSummaryMarkdown(TPath.Combine(fRoot, 'summary.md')), g);
  AssertJsonEquals('["FixInsight TXT failed (exit=1).", "Pascal Analyzer failed (exit=99)."]',
    Member(lSummary, ['errors']), 'errors');
end;

// A seed left by an earlier subject is refused before the accepted baseline can be replaced.
procedure TNativeAnalysisReportControlTests.StaleSeedSubjectFailsBeforeBaselineMutation;
var
  lBaseline, lProject: string;
  lBefore: TBytes;
begin
  lProject := TPath.Combine(fRoot, 'Current.dproj');
  WriteUtf8(lProject, '<Project />');
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Static analysis'#10#10'- Timestamp: 2026-07-15T10:00:00Z'#10'- Project: `' + lProject + '`'#10#10 +
    '## FixInsight'#10#10'- Findings (by code): 0'#10#10'## Pascal Analyzer'#10#10'- Skipped.'#10);
  WriteUtf8(TPath.Combine(fRoot, 'summary.json'),
    '{"schema_version": 2, "subject": {"kind": "project", "path": "' + Escaped(TPath.Combine(fRoot, 'Old.dproj')) +
    '"}, "status": {"infrastructure": "complete", "policy": "not_evaluated"}}');
  lBaseline := TPath.Combine(fRoot, 'accepted.json');
  WriteUtf8(lBaseline, '{'#13#10'  "version": 3'#13#10'}'#13#10);
  lBefore := TFile.ReadAllBytes(lBaseline);
  SetEnvironmentVariable('DAK_BASELINE', PChar(lBaseline));
  SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));
  AssertRaisesContaining(
    procedure
    begin
      FinalizeAnalysisReport(fRoot, nil, -1).Free;
    end, ['seed subject']);
  AssertBytesUnchanged(lBaseline, lBefore);
end;

procedure TNativeAnalysisReportControlTests.MalformedSeedFailsBeforeBaselineAndHistoryMutation;
var
  lBaseline, lHistory, lMarkdown, lProject: string;
  lBaselineBytes, lHistoryBytes, lMarkdownBytes: TBytes;
begin
  lProject := TPath.Combine(fRoot, 'Sample.dproj');
  WriteUtf8(lProject, '<Project />');
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Static analysis'#10#10'- Timestamp: 2026-07-15T10:00:00Z'#10'- Project: `' + lProject + '`'#10#10 +
    '## FixInsight'#10#10'- Findings (by code): 0'#10#10'## Pascal Analyzer'#10#10'- Skipped.'#10);
  WriteUtf8(TPath.Combine(fRoot, 'summary.json'), '{broken');
  lBaseline := TPath.Combine(fRoot, 'accepted.json');
  lMarkdown := TPath.Combine(fRoot, 'accepted.md');
  lHistory := TPath.Combine(fRoot, 'history.jsonl');
  WriteUtf8(lBaseline, '{'#13#10'  "version": 3'#13#10'}'#13#10);
  WriteUtf8(lMarkdown, 'accepted markdown'#13#10);
  WriteUtf8(lHistory, '{"accepted": true}'#13#10);
  lBaselineBytes := TFile.ReadAllBytes(lBaseline);
  lMarkdownBytes := TFile.ReadAllBytes(lMarkdown);
  lHistoryBytes := TFile.ReadAllBytes(lHistory);
  SetEnvironmentVariable('DAK_BASELINE', PChar(lBaseline));
  SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));
  AssertRaisesContaining(
    procedure
    begin
      FinalizeAnalysisReport(fRoot, nil, -1).Free;
    end, ['Invalid analysis status seed']);
  AssertBytesUnchanged(lBaseline, lBaselineBytes);
  AssertBytesUnchanged(lMarkdown, lMarkdownBytes);
  AssertBytesUnchanged(lHistory, lHistoryBytes);
end;

procedure TNativeAnalysisReportControlTests.NonObjectBaselineSectionsFailWithoutMutation;
var
  lBaseline, lHistory, lMarkdown, lOut, lProject: string;
  lBaselineBytes, lHistoryBytes, lMarkdownBytes: TBytes;
  lRow: string;
begin
  lProject := TPath.Combine(fRoot, 'Sample.dproj');
  WriteUtf8(lProject, '<Project />');
  lOut := TPath.Combine(fRoot, '.dak\Sample\baseline-shapes');
  WriteReportingRun(lOut, lProject);
  FinalizeAnalysisReport(lOut, nil, -1).Free;
  FinalizeAnalysisReport(lOut, nil, -1).Free; // A valid baseline remains accepted.
  lBaseline := TPath.Combine(lOut, 'baseline.json');
  lMarkdown := TPath.Combine(lOut, 'baseline.md');
  lHistory := TPath.Combine(lOut, 'history.jsonl');
  lMarkdownBytes := TFile.ReadAllBytes(lMarkdown);
  lHistoryBytes := TFile.ReadAllBytes(lHistory);
  SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));
  for lRow in ['1', '[]', 'null'] do
  begin
    RewriteJson(lBaseline, ReadUtf8(lBaseline),
      procedure(aBaseline: TJSONObject)
      begin
        JsonPut(Member(aBaseline, ['pascal_analyzer']) as TJSONObject, 'top_warning_sections',
          ParseJsonValue('[' + lRow + ']'));
      end);
    lBaselineBytes := TFile.ReadAllBytes(lBaseline);
    AssertRaisesContaining(
      procedure
      begin
        FinalizeAnalysisReport(lOut, nil, -1).Free;
      end, ['Invalid analysis baseline', 'top_warning_sections']);
    AssertBytesUnchanged(lBaseline, lBaselineBytes);
    AssertBytesUnchanged(lMarkdown, lMarkdownBytes);
    AssertBytesUnchanged(lHistory, lHistoryBytes);
  end;
end;

// A PAL report left from an earlier run is not evidence for a run that did not request PAL, so its
// broken content is neither parsed nor counted.
procedure TNativeAnalysisReportControlTests.PalNotRequestedDiscardsRetainedPalEvidence;
var
  g: TGarbos;
  lOut, lPalPath, lUnit: string;
  lProvenance, lResult, lSummary: TJSONObject;
begin
  lUnit := TPath.Combine(fRoot, 'Sample.pas');
  WriteUtf8(lUnit, 'unit Sample;'#10);
  lOut := TPath.Combine(fRoot, '.dak\Sample\retained-pal');
  WriteUtf8(TPath.Combine(lOut, 'summary.md'),
    '# Pascal Analyzer unit summary: Sample'#10#10'- Timestamp: 2026-07-19T12:00:00Z'#10'- Unit: `' + lUnit + '`'#10 +
    '- Skipped.'#10);
  WriteUtf8(TPath.Combine(lOut, 'fixinsight\fi-findings.jsonl'), '');
  lPalPath := TPath.Combine(lOut, 'pascal-analyzer\pal-findings.jsonl');
  WriteUtf8(lPalPath, '{"severity":"warning","report":"Warnings.xml"');
  WriteUtf8(TPath.Combine(lOut, 'summary.json'),
    '{"schema_version": 2, "status": {"infrastructure": "complete", "policy": "not_evaluated"}, ' +
    '"subject": {"kind": "unit", "path": "' + Escaped(lUnit) + '", "unit_file": "' + Escaped(lUnit) + '"}, ' +
    '"compiler": {"delphi": "23.0", "platform": "Win64", "config": "Debug", "search_path_sha256": "' +
    StringOfChar('1', 64) + '"}, ' +
    '"analyzers": {"fixinsight": {"requested": false, "status": "not_requested", "version": "", ' +
    '"options": {"sha256": "' + StringOfChar('2', 64) + '"}, "count_quality": "complete", "runs": []}, ' +
    '"pascal_analyzer": {"requested": false, "status": "not_requested", "version": "9.21.3.0", ' +
    '"options": {"sha256": "' + StringOfChar('3', 64) + '"}, "count_quality": "complete", "runs": []}}, ' +
    '"inputs": {"unit_sha256": "' + StringOfChar('4', 64) + '", "config_manifests": []}, ' +
    '"policy": {"resolver": "Dak.Settings", "values": {"gate_ownership": ["project", "repository"], ' +
    '"gate_metrics": [], "fixinsight_ignore": [], "pal_ignore_rules": ["NOT-CURRENTLY-VALIDATED"], ' +
    '"project_roots": ["' + Escaped(fRoot) + '"], "third_party_roots": [], "exclude_path_masks": []}, ' +
    '"origins": {"pal_ignore_rules": ["command_line"]}, "sources": [], "sha256": "' + StringOfChar('5', 64) +
    '", "reporting_sha256": "' + StringOfChar('6', 64) + '"}, "errors": [], ' +
    '"artifacts": {"summary_markdown": "summary.md"}}');
  WriteUtf8(TPath.Combine(lOut, 'run.log'), '');
  GC(lProvenance, ParseJsonObject('{"target": {"head": "fixture", "dirty": false, "submodules": []}, ' +
    '"dak": {"head": "dak-fixture", "executable_sha256": "' + StringOfChar('7', 64) + '"}}', 'provenance'), g);

  GC(lResult, FinalizeAnalysisReport(lOut, lProvenance, -1), g);
  Assert.AreEqual('', ReadUtf8(lPalPath).Trim, 'the retained PAL rows are discarded');
  GC(lSummary, ReadJson(TPath.Combine(lOut, 'summary.json')), g);
  Assert.AreEqual('0', MemberText(lSummary, ['counts', 'raw', 'pascal_analyzer', 'total']));
end;

procedure TNativeAnalysisReportControlTests.PalRuleIdentityKeepsExactReportAndSectionDistinctions;
const
  cPairs: array[0..4, 0..3] of string = (
    ('Warnings.xml', 'Rule (A)', 'Warnings.xml', 'Rule - A'),
    ('Warnings.xml', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA first',
     'Warnings.xml', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA second'),
    ('Report (A).xml', 'Same', 'Report - A.xml', 'Same'),
    ('Warnings.xml', 'Rule A', 'Warnings.xml', 'rule a'),
    ('Warnings.xml', '', 'Warnings.xml', 'unknown'));
var
  g: TGarbos;
  i: Integer;
  lFi, lPal: TJSONArray;
  lFirst, lPolicy, lSecond: TJSONObject;
begin
  for i := Low(cPairs) to High(cPairs) do
  begin
    GC(lFirst, PalRow('warning', cPairs[i, 0], cPairs[i, 1]), g);
    GC(lSecond, PalRow('warning', cPairs[i, 2], cPairs[i, 3]), g);
    Assert.AreNotEqual(AnalysisNormalizedRuleId(lFirst), AnalysisNormalizedRuleId(lSecond),
      cPairs[i, 0] + '/' + cPairs[i, 1] + ' against ' + cPairs[i, 2] + '/' + cPairs[i, 3]);
  end;

  // Ignoring one member of a colliding pair ignores exactly that member.
  GC(lFi, TJSONArray.Create, g);
  GC(lPal, TJSONArray.Create, g);
  lPal.AddElement(PalRow('warning', 'Warnings.xml', 'Rule (A)'));
  lPal.AddElement(PalRow('warning', 'Warnings.xml', 'Rule - A'));
  GC(lPolicy, PolicyObject('{"gate_ownership": ["project", "repository"], "pal_ignore_rules": ["' +
    AnalysisNormalizedRuleId(TJSONObject(lPal.Items[0])) + '"]}'), g);
  ApplyAnalysisReportProjections(lFi, lPal, lPolicy, [], '', TPath.Combine(fRoot, 'pascal-analyzer'), True);
  Assert.AreEqual('ignored', JsonText(TJSONObject(lPal.Items[0]), 'report_projection'));
  Assert.AreEqual('actionable', JsonText(TJSONObject(lPal.Items[1]), 'report_projection'));
end;

procedure TNativeAnalysisReportControlTests.PalCatalogEmptyRootMeansNoCatalog(const aRoot: string);
var
  g: TGarbos;
  lActual, lExpected: TJSONArray;
  lPolicy, lPolicyMissing: TJSONObject;
  lRule: string;
  lRow: TJSONObject;
begin
  GC(lRow, PalRow('warning', 'Warnings.xml', 'Plain rule'), g);
  lRule := AnalysisNormalizedRuleId(lRow);
  GC(lPolicy, PolicyObject('{"gate_ownership": ["project"], "pal_ignore_rules": ["' + lRule + '"]}'), g);
  GC(lPolicyMissing, PolicyObject('{"gate_ownership": ["project"], "pal_ignore_rules": ["' + lRule + '"]}'), g);
  GC(lActual, TJSONArray.Create, g);
  GC(lExpected, TJSONArray.Create, g);
  lActual.AddElement(PalRow('warning', 'Warnings.xml', 'Plain rule'));
  lExpected.AddElement(PalRow('warning', 'Warnings.xml', 'Plain rule'));
  // A nonexistent root is the established "no catalog" behavior; empty roots must match it.
  ApplyAnalysisReportProjections(nil, lExpected, lPolicyMissing, [], '', TPath.Combine(fRoot, 'no-such-catalog'), True);
  ApplyAnalysisReportProjections(nil, lActual, lPolicy, [], '', aRoot, True);
  Assert.AreEqual(lExpected.ToJSON, lActual.ToJSON);
  Assert.AreEqual('ignored', JsonText(TJSONObject(lActual.Items[0]), 'report_projection'));
end;

procedure TNativeAnalysisReportControlTests.PalRuleIdentitySurvivesSummarySarifAndFingerprint;
var
  g: TGarbos;
  lActionable, lChanged, lFull, lPolicy, lProjections, lSummary: TJSONObject;
  lFi, lPal, lResults: TJSONArray;
  lFound: Boolean;
  lResult, lRun: TJSONValue;
begin
  GC(lFi, TJSONArray.Create, g);
  GC(lPal, TJSONArray.Create, g);
  lPal.AddElement(PalRow('warning', 'Warnings.xml', 'Set before passed as out parameter')
    .AddPair('path', 'src/One.pas').AddPair('line', TJSONNumber.Create(10)));
  lPal.AddElement(PalRow('strong-warning', 'Strong Warnings.xml', 'Possible bad typecast (for objects: consider using "as")')
    .AddPair('path', 'src/Two.pas').AddPair('line', TJSONNumber.Create(20)));
  GC(lPolicy, PolicyObject('{"gate_ownership": ["project", "repository"], "pal_ignore_rules": ["WARN54"]}'), g);
  ApplyAnalysisReportProjections(lFi, lPal, lPolicy, [], '9.21.3.0', TPath.Combine(fRoot, 'pascal-analyzer'), True);

  GC(lSummary, ParseJsonObject('{"pal_totals": {"warnings": 1, "strong_warnings": 1, "optimizations": 0, "total": 2}}',
    'summary'), g);
  GC(lProjections, AnalysisReportProjections(lSummary, lFi, lPal), g);
  Assert.AreEqual('1', MemberText(lProjections, ['ignored', 'pascal_analyzer', 'by_rule', cIgnoredRule]));

  WriteAnalysisSarif(fRoot, lFi, lPal, False);
  WriteAnalysisSarif(fRoot, lFi, lPal, True);
  GC(lActionable, ReadJson(TPath.Combine(fRoot, 'static-analysis.sarif')), g);
  for lRun in Member(lActionable, ['runs']) as TJSONArray do
    for lResult in TJSONObject(lRun).GetValue('results') as TJSONArray do
      Assert.AreNotEqual(cIgnoredRule, JsonText(TJSONObject(lResult), 'ruleId'), 'the ignored rule is not actionable');
  GC(lFull, ReadJson(TPath.Combine(fRoot, 'static-analysis.full.sarif')), g);
  lFound := False;
  for lRun in Member(lFull, ['runs']) as TJSONArray do
  begin
    lResults := TJSONObject(lRun).GetValue('results') as TJSONArray;
    for lResult in lResults do
      if JsonText(TJSONObject(lResult), 'ruleId') = cIgnoredRule then
      begin
        lFound := True;
        Assert.AreEqual('WARN54', MemberText(TJSONObject(lResult), ['properties', 'pal_code']));
      end;
  end;
  Assert.IsTrue(lFound, 'the full SARIF keeps the ignored rule');

  GC(lChanged, TJSONObject(lPal.Items[0].Clone), g);
  JsonPutText(lChanged, 'normalized_rule', 'PAL.warnings.different-section');
  Assert.AreNotEqual(PalFingerprint(TJSONObject(lPal.Items[0])), PalFingerprint(lChanged),
    'the baseline fingerprint follows the rule identity');
end;

procedure TNativeAnalysisReportControlTests.FixInsightFilterCannotSuppressPascalAnalyzerRule;
var
  g: TGarbos;
  lFi, lPal: TJSONArray;
  lPolicy: TJSONObject;
begin
  GC(lFi, TJSONArray.Create, g);
  GC(lPal, TJSONArray.Create, g);
  lPal.AddElement(PalRow('warning', 'Warnings.xml', 'Set before passed as out parameter')
    .AddPair('path', 'src/One.pas').AddPair('line', TJSONNumber.Create(10)));
  GC(lPolicy, PolicyObject('{"gate_ownership": ["project", "repository"], "fixinsight_ignore": ["WARN54"]}'), g);
  ApplyAnalysisReportProjections(lFi, lPal, lPolicy, [], '9.21.3.0', TPath.Combine(fRoot, 'pascal-analyzer'), True);
  Assert.AreEqual('actionable', JsonText(TJSONObject(lPal.Items[0]), 'report_projection'));
  Assert.IsNull(TJSONObject(lPal.Items[0]).GetValue('report_policy'), 'no report policy applies to the PAL row');
end;

// The PAL ignore filter is carried consistently through summary, baseline and delta, and
// verification accepts only rule-count rows that agree with the baseline and the projections.
procedure TNativeAnalysisReportControlTests.PalFilterStaysInBaselineAndDeltaContract;
const
  cFields: array[0..2, 0..1] of string = (('rule_count_deltas', 'rule_counts'),
    ('raw_rule_count_deltas', 'raw_rule_counts'), ('ignored_rule_count_deltas', 'ignored_rule_counts'));
  cRemovedRule = 'PAL.warnings.removed-fixture-0123456789abcdef';
var
  g: TGarbos;
  lBaseline, lDelta, lProvenance, lResult, lSummary: TJSONObject;
  lBaselinePath, lBaselineText, lDeltaPath, lDeltaText, lOut, lProject, lSummaryPath, lSummaryText: string;
  i: Integer;
  lVerify: TProc;


begin
  lProject := TPath.Combine(fRoot, 'Sample.dproj');
  WriteUtf8(lProject, '<Project />');
  WriteUtf8(TPath.Combine(fRoot, 'One.pas'), 'unit One;');
  WriteUtf8(TPath.Combine(fRoot, 'Two.pas'), 'unit Two;');
  lOut := TPath.Combine(fRoot, '.dak\Sample\pal-rule-policy');
  lVerify := VerifyProc(lOut);
  WriteUtf8(TPath.Combine(lOut, 'summary.md'),
    '# Static analysis'#10#10'- Timestamp: 2026-07-19T12:00:00Z'#10'- Project: `' + lProject + '`'#10#10 +
    '## FixInsight'#10#10'- Findings (by code): 0'#10#10'## Pascal Analyzer'#10#10'- Version: 9.21.3.0'#10 +
    '- Compiler target: Delphi 12 (Win64)'#10'- Totals: warnings=1, strong_warnings=1, optimizations=0, total=2'#10);
  WriteUtf8(TPath.Combine(lOut, 'fixinsight\fi-findings.jsonl'), '');
  WriteUtf8(TPath.Combine(lOut, 'pascal-analyzer\pal-findings.jsonl'),
    '{"severity": "warning", "report": "Warnings.xml", "section": "Set before passed as out parameter", ' +
    '"module": "One", "path": "' + Escaped(TPath.Combine(fRoot, 'One.pas')) + '", "line": 10, "message": "value"}'#10 +
    '{"severity": "strong-warning", "report": "Strong Warnings.xml", ' +
    '"section": "Possible bad typecast (for objects: consider using \"as\")", "module": "Two", ' +
    '"path": "' + Escaped(TPath.Combine(fRoot, 'Two.pas')) + '", "line": 20, "message": "cast"}'#10);
  lSummaryPath := TPath.Combine(lOut, 'summary.json');
  WriteUtf8(lSummaryPath,
    '{"schema_version": 2, "status": {"infrastructure": "complete", "policy": "not_evaluated"}, ' +
    '"subject": {"kind": "project", "path": "' + Escaped(lProject) + '", "project_file": "' + Escaped(lProject) + '"}, ' +
    '"compiler": {"delphi": "23.0", "platform": "Win64", "config": "Debug", "search_path_sha256": "' +
    StringOfChar('1', 64) + '"}, ' +
    '"analyzers": {"fixinsight": {"requested": false, "status": "not_requested", "version": "", ' +
    '"options": {"sha256": "' + StringOfChar('2', 64) + '"}, "count_quality": "complete", "runs": []}, ' +
    '"pascal_analyzer": {"requested": true, "status": "complete", "version": "9.21.3.0", ' +
    '"options": {"sha256": "' + StringOfChar('3', 64) + '"}, "count_quality": "complete", "runs": []}}, ' +
    '"inputs": {"project_sha256": "' + StringOfChar('4', 64) + '", "main_source_sha256": "' + StringOfChar('5', 64) +
    '", "config_manifests": []}, ' +
    '"policy": {"resolver": "Dak.Settings", "values": {"gate_ownership": ["project", "repository", "third_party"], ' +
    '"gate_metrics": [], "fixinsight_ignore": [], "pal_ignore_rules": ["WARN54"], ' +
    '"project_roots": ["' + Escaped(fRoot) + '"], "third_party_roots": [], "exclude_path_masks": []}, ' +
    '"sources": ["' + Escaped(TPath.Combine(fRoot, 'dak.ini')) + '"], ' +
    '"origins": {"pal_ignore_rules": ["' + Escaped(TPath.Combine(fRoot, 'dak.ini')) + '"]}, ' +
    '"sha256": "' + StringOfChar('6', 64) + '", "reporting_sha256": "' + StringOfChar('7', 64) + '"}, ' +
    '"errors": [], "artifacts": {"summary_markdown": "summary.md"}}');
  WriteUtf8(TPath.Combine(lOut, 'run.log'), '');
  GC(lProvenance, ParseJsonObject('{"target": {"head": "fixture", "dirty": false, "submodules": []}, ' +
    '"dak": {"head": "dak-fixture", "executable_sha256": "' + StringOfChar('8', 64) + '"}}', 'provenance'), g);

  GC(lResult, FinalizeAnalysisReport(lOut, lProvenance, -1), g);
  Assert.AreEqual('True', MemberText(lResult, ['baseline_created']));
  lSummaryText := ReadUtf8(lSummaryPath);
  GC(lSummary, ParseJsonObject(lSummaryText, 'summary.json'), g);
  Assert.AreEqual('1', MemberText(lSummary, ['counts', 'ignored', 'pascal_analyzer', 'total']));
  Assert.AreEqual('1', MemberText(lSummary, ['counts', 'actionable', 'pascal_analyzer', 'strong_warnings']));
  AssertJsonEquals('["WARN54"]', Member(lSummary, ['policy', 'active', 'pal_ignore_rules']), 'active PAL filter');
  AssertJsonEquals(cExpectedAliases, Member(lSummary, ['analyzers', 'pascal_analyzer', 'verified_rule_aliases']),
    'summary aliases');

  lBaselinePath := TPath.Combine(lOut, 'baseline.json');
  lBaselineText := ReadUtf8(lBaselinePath);
  GC(lBaseline, ParseJsonObject(lBaselineText, 'baseline.json'), g);
  Assert.AreEqual(MemberText(lSummary, ['compatibility', 'sha256']), MemberText(lBaseline, ['compatibility', 'sha256']));
  Assert.AreEqual(1, (Member(lBaseline, ['pascal_analyzer', 'strong_hashes']) as TJSONArray).Count, 'strong hashes');
  Assert.AreEqual(0, (Member(lBaseline, ['pascal_analyzer', 'warning_hashes']) as TJSONArray).Count, 'warning hashes');
  AssertJsonEquals('{"' + cStrongRule + '": 1}', Member(lBaseline, ['pascal_analyzer', 'rule_counts']), 'rule_counts');
  AssertJsonEquals(cExpectedAliases, Member(lBaseline, ['pascal_analyzer', 'verified_rule_aliases']), 'baseline aliases');

  lDeltaPath := TPath.Combine(lOut, 'delta.json');
  lDeltaText := ReadUtf8(lDeltaPath);
  GC(lDelta, ParseJsonObject(lDeltaText, 'delta.json'), g);
  Assert.AreEqual('True', MemberText(lDelta, ['baseline', 'created']));
  Assert.AreEqual(cStrongRule, JsonText(TJSONObject(RuleRows(lDelta, 'rule_count_deltas').Items[0]), 'rule'));
  AssertJsonEquals('{"before": ' + cExpectedAliases + ', "after": ' + cExpectedAliases + '}',
    Member(lDelta, ['pascal_analyzer', 'verified_rule_aliases']), 'delta aliases');
  AssertJsonEquals('[{"rule": "' + cIgnoredRule + '", "before": 1, "after": 1, "delta": 0}]',
    Member(lDelta, ['pascal_analyzer', 'ignored_rule_count_deltas']), 'ignored rule deltas');
  lVerify();

  for i := Low(cFields) to High(cFields) do
  begin
    // A rule new since the baseline and a rule gone since the baseline are both consistent rows.
    RewriteJson(lBaselinePath, lBaselineText,
      procedure(aBaseline: TJSONObject)
      var
        lDeltaDocument: TJSONObject;
        lRow: TJSONObject;
        lValue: TJSONValue;
      begin
        lDeltaDocument := ParseJsonObject(lDeltaText, 'delta.json');
        try
          lRow := nil;
          for lValue in RuleRows(lDeltaDocument, cFields[i, 0]) do
            if StrToInt(JsonText(TJSONObject(lValue), 'after')) > 0 then
            begin
              lRow := TJSONObject(lValue);
              Break;
            end;
          Assert.IsNotNull(lRow, cFields[i, 0] + ' has a row with findings');
          (Member(aBaseline, ['pascal_analyzer', cFields[i, 1]]) as TJSONObject).RemovePair(JsonText(lRow, 'rule')).Free;
          JsonPut(lRow, 'before', TJSONNumber.Create(0));
          JsonPut(lRow, 'delta', TJSONNumber.Create(StrToInt(JsonText(lRow, 'after'))));
          WriteUtf8(lDeltaPath, lDeltaDocument.ToJSON);
        finally
          lDeltaDocument.Free;
        end;
      end);
    lVerify();
    RewriteJson(lBaselinePath, lBaselineText,
      procedure(aBaseline: TJSONObject)
      begin
        (Member(aBaseline, ['pascal_analyzer', cFields[i, 1]]) as TJSONObject)
          .AddPair(cRemovedRule, TJSONNumber.Create(1));
      end);
    RewriteJson(lDeltaPath, lDeltaText,
      procedure(aDelta: TJSONObject)
      begin
        RuleRows(aDelta, cFields[i, 0]).AddElement(TJSONObject.Create.AddPair('rule', cRemovedRule)
          .AddPair('before', TJSONNumber.Create(1)).AddPair('after', TJSONNumber.Create(0))
          .AddPair('delta', TJSONNumber.Create(-1)));
      end);
    lVerify();
  end;
  WriteUtf8(lBaselinePath, lBaselineText);
  WriteUtf8(lDeltaPath, lDeltaText);
  lVerify();

  TFile.Delete(lBaselinePath);
  AssertRaisesContaining(lVerify, ['baseline', 'missing']);
  WriteUtf8(lBaselinePath, lBaselineText);

  RewriteJson(lSummaryPath, lSummaryText,
    procedure(aSummary: TJSONObject)
    begin
      JsonPut(Member(aSummary, ['policy', 'active']) as TJSONObject, 'pal_ignore_rules', TJSONArray.Create);
    end);
  AssertRaisesContaining(lVerify, ['active PAL ignore policy']);
  WriteUtf8(lSummaryPath, lSummaryText);

  RewriteJson(lDeltaPath, lDeltaText,
    procedure(aDelta: TJSONObject)
    begin
      JsonPut(Member(aDelta, ['pascal_analyzer', 'verified_rule_aliases']) as TJSONObject, 'after', TJSONObject.Create);
    end);
  AssertRaisesContaining(lVerify, ['verified PAL alias']);
  RewriteJson(lDeltaPath, lDeltaText,
    procedure(aDelta: TJSONObject)
    begin
      JsonPut(Member(aDelta, ['pascal_analyzer', 'verified_rule_aliases']) as TJSONObject, 'before', TJSONObject.Create);
    end);
  AssertRaisesContaining(lVerify, ['verified PAL alias']);

  for i := Low(cFields) to High(cFields) do
  begin
    RewriteJson(lDeltaPath, lDeltaText,
      procedure(aDelta: TJSONObject)
      var
        lRow: TJSONObject;
      begin
        lRow := TJSONObject(RuleRows(aDelta, cFields[i, 0]).Items[0]);
        JsonPut(lRow, 'before', TJSONNumber.Create(StrToInt(JsonText(lRow, 'before')) + 1));
        JsonPut(lRow, 'delta', TJSONNumber.Create(StrToInt(JsonText(lRow, 'after')) - StrToInt(JsonText(lRow, 'before'))));
      end);
    AssertRaisesContaining(lVerify, [cFields[i, 0]]);
  end;
  WriteUtf8(lDeltaPath, lDeltaText);
  lVerify();
end;

// A module-only PAL row joins a changed file only through a unique basename; a path is taken as is.
procedure TNativeAnalysisReportControlTests.ChangedFileTriageUsesExactPathBeforeUniqueModuleFallback;
var
  g: TGarbos;
  lFi, lPal: TJSONArray;
  lSummary: TJSONObject;
  lTriage: string;
begin
  GC(lSummary, ParseJsonObject('{"provenance": {"target": {"vcs": "git", "root": "' + Escaped(fRoot) +
    '", "status": "complete", "changed_files": ["src/a/Shared.pas", "src/Unique.pas"]}}}', 'summary'), g);
  GC(lFi, TJSONArray.Create, g);
  GC(lPal, ParseJsonValue(
    '[{"module": "Shared", "path": "src/a/Shared.pas", "section": "W", "line": 1, "message": "exact"}, ' +
    '{"module": "Shared", "path": "src/b/Shared.pas", "section": "W", "line": 2, "message": "wrong-path"}, ' +
    '{"module": "Shared", "path": null, "section": "W", "line": 3, "message": "ambiguous"}, ' +
    '{"module": "Unique", "path": null, "section": "W", "line": 4, "message": "unique-fallback"}]') as TJSONArray, g);
  lTriage := ReadUtf8(WriteAnalysisTriageChanged(fRoot, 'Sample', lSummary, lFi, lPal,
    [TPath.Combine(fRoot, 'src\a\Shared.pas'), TPath.Combine(fRoot, 'src\b\Shared.pas'),
     TPath.Combine(fRoot, 'src\Unique.pas')]));
  Assert.IsTrue(lTriage.Contains('exact'), lTriage);
  Assert.IsTrue(lTriage.Contains('unique-fallback'), lTriage);
  Assert.IsFalse(lTriage.Contains('wrong-path'), lTriage);
  Assert.IsFalse(lTriage.Contains('ambiguous'), lTriage);
end;

procedure TNativeAnalysisReportControlTests.ChangedFileTriageUsesSvnProvenanceWithoutGit;
var
  g: TGarbos;
  lFi, lPal: TJSONArray;
  lSummary: TJSONObject;
  lTriage: string;
begin
  WriteUtf8(TPath.Combine(fRoot, 'Main.pas'), 'unit Main;'#10);
  GC(lSummary, ParseJsonObject('{"project": "' + Escaped(TPath.Combine(fRoot, 'Sample.dproj')) +
    '", "provenance": {"target": {"vcs": "svn", "root": "' + Escaped(fRoot) +
    '", "status": "complete", "changed_files": ["Main.pas"]}}}', 'summary'), g);
  GC(lFi, ParseJsonValue('[{"code": "W101", "path": "Main.pas", "line": 1, "col": 1, ' +
    '"message": "SVN changed finding"}]') as TJSONArray, g);
  GC(lPal, TJSONArray.Create, g);
  lTriage := ReadUtf8(WriteAnalysisTriageChanged(TPath.Combine(fRoot, '.dak\Sample'), 'Sample', lSummary, lFi, lPal, []));
  Assert.IsTrue(lTriage.Contains('- VCS: `svn`'), lTriage);
  Assert.IsTrue(lTriage.Contains('- Workspace root: `' + fRoot + '`'), lTriage);
  Assert.IsTrue(lTriage.Contains('SVN changed finding'), lTriage);
  Assert.IsFalse(lTriage.Contains('Git repo not found'), lTriage);
end;

procedure TNativeAnalysisReportControlTests.ChangedFileTriageIsNotApplicableWithoutVcs;
var
  g: TGarbos;
  lFi, lPal: TJSONArray;
  lSummary: TJSONObject;
  lTriage: string;
begin
  GC(lSummary, ParseJsonObject('{"provenance": {"target": {"vcs": "none", "root": "' + Escaped(fRoot) +
    '", "status": "not_applicable", "changed_files": null}}}', 'summary'), g);
  GC(lFi, TJSONArray.Create, g);
  GC(lPal, TJSONArray.Create, g);
  lTriage := ReadUtf8(WriteAnalysisTriageChanged(TPath.Combine(fRoot, '.dak\Sample'), 'Sample', lSummary, lFi, lPal, []));
  Assert.IsTrue(lTriage.Contains('No-VCS changed-file scope is not applicable.'), lTriage);
  Assert.IsFalse(lTriage.Contains('unavailable'), lTriage);
end;

procedure TNativeAnalysisReportControlTests.GitChangedFilesKeepRenameTargetAndFullUntrackedPath;
var
  g: TGarbos;
  lChanged: TStringList;
  lIdentity: TJSONObject;
  lRepo, lScratch: string;
  lValue: TJSONValue;
  lWorkspace: TWorkspaceSettings;
begin
  lRepo := TPath.Combine(fRoot, 'repo');
  // The capture scratch lives outside the repository so it cannot appear as an untracked change.
  lScratch := TPath.Combine(fRoot, 'capture');
  TDirectory.CreateDirectory(lScratch);
  WriteUtf8(TPath.Combine(lRepo, 'src\Old.pas'), 'unit Old;'#10);
  Git(lRepo, 'init -q');
  Git(lRepo, 'add .');
  Commit(lRepo, 'fixture');
  TFile.Move(TPath.Combine(lRepo, 'src\Old.pas'), TPath.Combine(lRepo, 'src\Renamed.pas'));
  Git(lRepo, 'add -A');
  WriteUtf8(TPath.Combine(lRepo, 'src\new\Added.pas'), 'unit Added;'#10);

  lWorkspace := Default(TWorkspaceSettings);
  lWorkspace.fRoot := lRepo;
  lWorkspace.fVcs := 'git';
  GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lScratch), g);
  Assert.AreEqual('complete', JsonText(lIdentity, 'status'), lIdentity.ToJSON);
  GC(lChanged, TStringList.Create, g);
  for lValue in Member(lIdentity, ['changed_files']) as TJSONArray do
    lChanged.Add(lValue.Value);
  Assert.IsTrue(lChanged.IndexOf('src/Renamed.pas') >= 0, lChanged.CommaText);
  Assert.IsTrue(lChanged.IndexOf('src/new/Added.pas') >= 0, lChanged.CommaText);
  Assert.IsTrue(lChanged.IndexOf('src/Old.pas') < 0, lChanged.CommaText);
  Assert.IsTrue(lChanged.IndexOf('src/') < 0, lChanged.CommaText);
end;

// Finalization without captured provenance records the dirty Git candidate and its recursive
// submodule revision in summary.json.
procedure TNativeAnalysisReportControlTests.Schema2ProvenanceTracksDirtySourcesAndRecursiveSubmodules;
var
  g: TGarbos;
  lLibrary, lOut, lRepo, lSource: string;
  lSubmodule, lSummary, lTarget: TJSONObject;
begin
  lLibrary := TPath.Combine(fRoot, 'library');
  lRepo := TPath.Combine(fRoot, 'repo');
  WriteUtf8(TPath.Combine(lLibrary, 'LibraryUnit.pas'), 'unit LibraryUnit;'#10);
  Git(lLibrary, 'init -q');
  Git(lLibrary, 'add .');
  Commit(lLibrary, 'library fixture');

  WriteUtf8(TPath.Combine(lRepo, 'Sample.dproj'), '<Project />');
  WriteUtf8(TPath.Combine(lRepo, 'Sample.dpr'), 'program Sample;'#10'begin'#10'end.'#10);
  lSource := TPath.Combine(lRepo, 'SampleUnit.pas');
  WriteUtf8(lSource, 'unit SampleUnit;'#10);
  WriteUtf8(TPath.Combine(lRepo, '.gitignore'), '.dak/'#10);
  Git(lRepo, 'init -q');
  Git(lRepo, 'add .');
  Commit(lRepo, 'project fixture');
  Git(lRepo, '-c protocol.file.allow=always submodule add -q "' + lLibrary + '" vendor/library');
  Git(lRepo, 'add .');
  Commit(lRepo, 'add submodule');
  WriteUtf8(lSource, 'unit SampleUnit;'#10'// dirty'#10);
  WriteUtf8(TPath.Combine(lRepo, 'NewUnit.pas'), 'unit NewUnit;'#10);

  lOut := TPath.Combine(lRepo, '.dak\Sample');
  WriteReportingRun(lOut, TPath.Combine(lRepo, 'Sample.dproj'));
  FinalizeAnalysisReport(lOut, nil, -1).Free;

  GC(lSummary, ReadJson(TPath.Combine(lOut, 'summary.json')), g);
  lTarget := Member(lSummary, ['provenance', 'target']) as TJSONObject;
  Assert.AreEqual(40, Length(JsonText(lTarget, 'head')), lTarget.ToJSON);
  Assert.AreEqual('True', MemberText(lTarget, ['dirty']));
  Assert.AreEqual('git-delphi-inputs-with-recursive-submodules', MemberText(lTarget, ['source_inputs', 'scope']));
  Assert.IsTrue(StrToInt(MemberText(lTarget, ['source_inputs', 'file_count'])) >= 4, lTarget.ToJSON);
  Assert.AreEqual(64, Length(MemberText(lTarget, ['source_inputs', 'sha256'])));
  lSubmodule := TJSONObject((Member(lTarget, ['submodules']) as TJSONArray).Items[0]);
  Assert.AreEqual('vendor/library', JsonText(lSubmodule, 'path'));
  Assert.AreEqual(40, Length(JsonText(lSubmodule, 'revision')));
end;

// An SVN workspace without a usable svn client degrades provenance truthfully; the run itself is
// still complete and reports no error.
procedure TNativeAnalysisReportControlTests.MissingSvnCliKeepsFinalizationComplete;
var
  g: TGarbos;
  lOut, lUnit: string;
  lProvenance, lSummary, lTarget: TJSONObject;
  lWorkspace: TWorkspaceSettings;
begin
  TDirectory.CreateDirectory(TPath.Combine(fRoot, '.svn'));
  lUnit := TPath.Combine(fRoot, 'Main.pas');
  WriteUtf8(lUnit, 'unit Main;'#10);
  SetEnvironmentVariable('DAK_SVN_EXE', PChar(TPath.Combine(fRoot, 'missing-svn.exe')));
  lOut := TPath.Combine(fRoot, '.dak\Main');
  lWorkspace := Default(TWorkspaceSettings);
  lWorkspace.fRoot := fRoot;
  lWorkspace.fVcs := 'svn';
  GC(lProvenance, CaptureRunProvenance(lWorkspace, ParamStr(0), lOut), g);
  lTarget := Member(lProvenance, ['target']) as TJSONObject;
  Assert.AreEqual('svn', JsonText(lTarget, 'vcs'));
  Assert.AreEqual('unavailable', JsonText(lTarget, 'status'));
  Assert.IsTrue(JsonText(lTarget, 'diagnostic').ToLowerInvariant.Contains('svn'), lTarget.ToJSON);
  Assert.AreEqual('filesystem-delphi-inputs', MemberText(lTarget, ['source_inputs', 'scope']));

  WriteUtf8(TPath.Combine(lOut, 'summary.md'),
    '# Pascal Analyzer unit summary: Main'#10#10'- Timestamp: 2026-07-19T12:00:00Z'#10'- Unit: `' + lUnit + '`'#10 +
    '- Skipped.'#10);
  WriteUtf8(TPath.Combine(lOut, 'summary.json'),
    '{"schema_version": 2, "status": {"infrastructure": "complete", "policy": "not_evaluated"}, ' +
    '"workspace": {"root": "' + Escaped(fRoot) + '", "vcs": "svn"}, ' +
    '"subject": {"kind": "unit", "path": "' + Escaped(lUnit) + '"}, "inputs": {}, "errors": []}');
  FinalizeAnalysisReport(lOut, lProvenance, -1).Free;
  GC(lSummary, ReadJson(TPath.Combine(lOut, 'summary.json')), g);
  Assert.AreEqual('complete', MemberText(lSummary, ['status', 'infrastructure']));
  Assert.AreEqual(0, (Member(lSummary, ['errors']) as TJSONArray).Count, lSummary.ToJSON);
  Assert.AreEqual('unavailable', MemberText(lSummary, ['provenance', 'target', 'status']));
end;

// The failed-analyzer seed and summary of test_valid_failed_summary_is_postprocessed_without_masking_dak_exit:
// the version the summary reports survives the failure, the unavailable count gets no total and the
// accepted baseline is not replaced although an update was requested.
procedure TNativeAnalysisReportControlTests.FailedSummaryKeepsItsPalVersionWithoutATotal;
var
  g: TGarbos;
  lBaseline, lProject: string;
  lBefore: TBytes;
  lSummary: TJSONObject;
begin
  lProject := TPath.Combine(fRoot, 'Sample.dproj');
  WriteUtf8(lProject, '<Project />');
  WriteUtf8(TPath.Combine(fRoot, 'summary.md'),
    '# Static analysis'#10#10'- Timestamp: 2026-07-15T10:00:00Z'#10'- Project: `' + lProject + '`'#10#10 +
    '## FixInsight'#10#10'- Findings (by code): (TXT not generated)'#10#10'## Pascal Analyzer'#10#10 +
    '- Version: 9.21.3'#10'- Compiler target: Delphi 13 (Win64)'#10 +
    '- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0'#10);
  WriteUtf8(TPath.Combine(fRoot, 'summary.json'),
    '{"schema_version": 2, "subject": {"kind": "project", "path": "' + Escaped(lProject) + '"}, ' +
    '"status": {"infrastructure": "failed", "policy": "not_evaluated"}, ' +
    '"analyzers": {"pascal_analyzer": {"requested": true, "status": "failed", "count_quality": "unavailable"}}, ' +
    '"counts": {"pascal_analyzer": {"quality": "unavailable"}}, "errors": ["Pascal Analyzer failed (exit=99)."]}');
  lBaseline := TPath.Combine(fRoot, 'accepted-baseline.json');
  WriteUtf8(lBaseline, '{'#13#10'  "version": 1'#13#10'}'#13#10);
  lBefore := TFile.ReadAllBytes(lBaseline);
  SetEnvironmentVariable('DAK_BASELINE', PChar(lBaseline));
  SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));

  FinalizeAnalysisReport(fRoot, nil, 7).Free;
  Assert.IsTrue(TFile.Exists(TPath.Combine(fRoot, 'delta.json')), 'the failed run is finalized');
  GC(lSummary, ReadJson(TPath.Combine(fRoot, 'summary.json')), g);
  Assert.AreEqual('failed', MemberText(lSummary, ['status', 'infrastructure']));
  Assert.AreEqual('not_evaluated', MemberText(lSummary, ['status', 'policy']));
  Assert.AreEqual('9.21.3', MemberText(lSummary, ['analyzers', 'pascal_analyzer', 'version']));
  Assert.IsNull(TJSONObject(Member(lSummary, ['counts', 'pascal_analyzer'])).GetValue('total'),
    'an unavailable PAL count has no total');
  AssertBytesUnchanged(lBaseline, lBefore);
end;

// A metric row without a report name derives its rule from the severity; it stays advisory until the
// policy opts that exact rule in, and projecting the same rows again honors the new policy.
procedure TNativeAnalysisReportControlTests.AdvisoryMetricsRequireExplicitPolicyOptIn;
var
  g: TGarbos;
  lFi, lPal: TJSONArray;
  lOptIn, lPolicy: TJSONObject;
begin
  GC(lFi, TJSONArray.Create, g);
  GC(lPal, ParseJsonValue(
    '[{"severity": "warning", "section": "Method length", "module": "Main", "path": "src/Main.pas", "line": 10, ' +
    '"message": "120 statements", "ownership": "project", "ownership_root": "' + Escaped(fRoot) + '"}, ' +
    '{"severity": "warning", "section": "Possible bad pointer usage", "module": "Main", "path": "src/Main.pas", ' +
    '"line": 20, "message": "Pointer cast", "ownership": "project", "ownership_root": "' + Escaped(fRoot) + '"}]')
    as TJSONArray, g);
  GC(lPolicy, PolicyObject('{"gate_ownership": ["project", "repository"], "gate_metrics": []}'), g);
  ApplyAnalysisReportProjections(lFi, lPal, lPolicy, [], '', TPath.Combine(fRoot, 'pascal-analyzer'), True);
  Assert.AreEqual('advisory_metrics', JsonText(TJSONObject(lPal.Items[0]), 'report_projection'));
  Assert.AreEqual('actionable', JsonText(TJSONObject(lPal.Items[1]), 'report_projection'));

  GC(lOptIn, PolicyObject('{"gate_ownership": ["project", "repository"], ' +
    '"gate_metrics": ["PAL.warnings.method-length-621eae6dfec836e8"]}'), g);
  ApplyAnalysisReportProjections(lFi, lPal, lOptIn, [], '', TPath.Combine(fRoot, 'pascal-analyzer'), True);
  Assert.AreEqual('actionable', JsonText(TJSONObject(lPal.Items[0]), 'report_projection'));
  Assert.AreEqual('actionable', JsonText(TJSONObject(lPal.Items[1]), 'report_projection'));
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisReportControlTests);

end.
