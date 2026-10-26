unit Test.PalFindingNormalize;

interface

uses
  System.Classes,
  System.JSON,
  System.IOUtils,
  System.SysUtils,
  Xml.omnixmldom, Xml.xmldom,
  Winapi.Windows,
  DUnitX.TestFramework,
  Dak.Analyze.Common, Dak.PascalAnalyzer.Artifacts, Dak.Utils,
  Test.Support;

type
  [TestFixture]
  [Category('Slow')]
  TPalFindingNormalizeTests = class
  private
    procedure CopyPalFixtureToTemp(const aSourceRoot, aTempName: string; out aFixtureRoot: string);
    procedure PrepareLongXmlPair(out aShortRoot, aLongRoot: string);
  public
    [Test]
    procedure NormalizePalFindingsFromFixtures;
    [Test]
    procedure MalformedHotspotReportsPreserveFindingsAndRecordWarning;
    [Test]
    procedure ModulesXmlResolvesFindingPathsDeterministically;
    [Test]
    [TestCase('unique', 'unique,resolved,C:\Repo\DelphiAIKit.Tests.dpr')]
    [TestCase('no context', 'no-context,missing,')]
    [TestCase('different main', 'different,missing,')]
    [TestCase('conflicting main', 'conflicting,missing,')]
    [TestCase('duplicate main', 'duplicate-main,missing,')]
    [TestCase('conflicting alias', 'alias-conflict,ambiguous,')]
    [TestCase('ambiguous alias', 'ambiguous-alias,ambiguous,')]
    procedure ReportNameResolvesOnlyUniqueRecordedMain(const aCase, aExpectedStatus, aExpectedPath: string);
    [Test]
    [TestCase('Plain include', 'Shared.inc,resolved,False')]
    [TestCase('Class-qualified include', 'shared.INC\TWorker\Run,resolved,False')]
    [TestCase('Slash-qualified include', 'Shared.inc/TWorker/Run,resolved,False')]
    [TestCase('Conflicting include paths', 'Shared.inc,ambiguous,True')]
    procedure ModulesXmlResolvesIncludePaths(const aModule, aExpectedStatus: string; const aConflicting: Boolean);
    [Test]
    procedure LocInfoPreservesAnalyzerMessage;
    [Test]
    procedure LongXmlSectionCountsMatchShortXml;
    [Test]
    procedure LongXmlStatusMatchesShortXml;
    [Test]
    procedure LongXmlFindingsMatchShortXml;
    [Test]
    procedure LongXmlMalformedAndMissingKeepFailureContracts;
    [Test]
    procedure NestedLongPalReportRootDiscoveryKeepsLogicalPath;
    [Test]
    procedure MissingPalFixturesFailClosedWithoutOptOut;
    [Test]
    procedure NegativeSectionCountsDoNotReduceActionableTotals;
    [Test]
    procedure ProjectSummaryUsesNormalizedActionableCounts;
    [Test]
    procedure ProjectRunnerUsesNormalizedArtifactCounts;
    [Test]
    procedure UnitSummaryUsesNormalizedActionableCounts;
    [Test]
    procedure UnitSummaryMarksSkippedAnalyzer;
    [Test]
    procedure UnitRunnerUsesNormalizedArtifactCounts;
  end;

implementation

const
  cPalFixtureRootEnv = 'DAK_TEST_PAL_FIXTURE_ROOT';
  cAllowMissingPalFixturesEnv = 'DAK_ALLOW_MISSING_PAL_FIXTURES';

function PalFixtureRoot: string;
begin
  Result := Trim(GetEnvironmentVariable(cPalFixtureRootEnv));
  if Result = '' then
    Result := TPath.Combine(RepoRoot, 'docs\sample-pal-reports')
  else
    Result := TPath.GetFullPath(Result);
end;

procedure RequirePalFixtures(const aFixtureRoot: string);
begin
  if TDirectory.Exists(aFixtureRoot) and
    FileExists(TPath.Combine(aFixtureRoot, 'Warnings.xml')) then
    Exit;

  if SameText(Trim(GetEnvironmentVariable(cAllowMissingPalFixturesEnv)), '1') then
  begin
    Assert.Pass('PAL fixtures missing; ' + cAllowMissingPalFixturesEnv +
      '=1 allows skipping PAL fixture-backed tests.');
    Exit;
  end;

  Assert.Fail('PAL fixtures missing: ' + aFixtureRoot + '. Set ' +
    cAllowMissingPalFixturesEnv + '=1 to explicitly skip PAL fixture-backed tests.');
end;

procedure TPalFindingNormalizeTests.CopyPalFixtureToTemp(const aSourceRoot, aTempName: string;
  out aFixtureRoot: string);
var
  lFile: string;
  lTargetFile: string;
begin
  aFixtureRoot := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(aFixtureRoot) then
    TDirectory.Delete(aFixtureRoot, True);
  TDirectory.CreateDirectory(aFixtureRoot);

  for lFile in TDirectory.GetFiles(aSourceRoot, '*.xml') do
  begin
    lTargetFile := TPath.Combine(aFixtureRoot, TPath.GetFileName(lFile));
    TFile.Copy(lFile, lTargetFile);
  end;
end;

procedure TPalFindingNormalizeTests.PrepareLongXmlPair(out aShortRoot, aLongRoot: string);
const
  cWarningsXml = '<?xml version="1.0" encoding="utf-8"?>' +
    '<report><section name="Unused variables" count="1">' +
    '<loc><locmod>Sample.Unit</locmod><locline>7</locline><info>café</info></loc>' +
    '</section></report>';
  cStatusXml = '<?xml version="1.0" encoding="utf-16"?>' +
    '<report><section name="Overview"><version>2.1 é</version>' +
    '<compiler>Delphi 12 ü</compiler></section></report>';
var
  lBytes: TBytes;
  lPath: string;
  lPreamble: TBytes;
  lStream: TFileStream;

  procedure WriteXml(const aPath, aXml: string; const aEncoding: TEncoding);
  begin
    lStream := TFileStream.Create(aPath, fmCreate);
    try
      lPreamble := aEncoding.GetPreamble;
      if Length(lPreamble) > 0 then
        lStream.WriteBuffer(lPreamble[0], Length(lPreamble));
      lBytes := aEncoding.GetBytes(aXml);
      lStream.WriteBuffer(lBytes[0], Length(lBytes));
    finally
      lStream.Free;
    end;
  end;

begin
  aShortRoot := TPath.Combine(TempRoot, 'pal-short-xml');
  aLongRoot := TPath.Combine(TempRoot, 'pal-long-xml');
  TDirectory.CreateDirectory(aShortRoot);
  TDirectory.CreateDirectory(aLongRoot);
  while Length(TPath.Combine(aLongRoot, 'Warnings.xml')) <= 300 do
  begin
    aLongRoot := TPath.Combine(aLongRoot, StringOfChar('x', 70));
    TDirectory.CreateDirectory(LongPathSafe(aLongRoot));
  end;
  Assert.IsTrue(Length(TPath.Combine(aLongRoot, 'Warnings.xml')) > 300,
    'The PAL XML fixture must exercise an absolute path beyond 300 characters.');
  Assert.IsTrue(TDirectory.Exists(LongPathSafe(aLongRoot)), 'Long XML directory setup failed.');

  lPath := TPath.Combine(aShortRoot, 'Warnings.xml');
  WriteXml(lPath, cWarningsXml, TEncoding.UTF8);
  TFile.Copy(lPath, LongPathSafe(TPath.Combine(aLongRoot, 'Warnings.xml')), True);
  lPath := TPath.Combine(aShortRoot, 'Status.xml');
  WriteXml(lPath, cStatusXml, TEncoding.Unicode);
  TFile.Copy(lPath, LongPathSafe(TPath.Combine(aLongRoot, 'Status.xml')), True);
  Assert.IsTrue(TFile.Exists(LongPathSafe(TPath.Combine(aLongRoot, 'Warnings.xml'))),
    'Long Warnings.xml fixture setup failed.');
  Assert.IsTrue(TFile.Exists(LongPathSafe(TPath.Combine(aLongRoot, 'Status.xml'))),
    'Long Status.xml fixture setup failed.');
end;

procedure TPalFindingNormalizeTests.LongXmlSectionCountsMatchShortXml;
var
  lLongRoot: string;
  lShortRoot: string;
  lVendor: string;
begin
  PrepareLongXmlPair(lShortRoot, lLongRoot);
  lVendor := DefaultDOMVendor;
  try
    DefaultDOMVendor := sOmniXmlVendor;
    Assert.AreEqual(1, GetSectionCountTotal(TPath.Combine(lShortRoot, 'Warnings.xml')));
    Assert.AreEqual(1, GetSectionCountTotal(TPath.Combine(lLongRoot, 'Warnings.xml')));
  finally
    DefaultDOMVendor := lVendor;
  end;
end;

procedure TPalFindingNormalizeTests.LongXmlStatusMatchesShortXml;
var
  lLongCompiler: string;
  lLongRoot: string;
  lLongVersion: string;
  lShortCompiler: string;
  lShortRoot: string;
  lShortVersion: string;
  lVendor: string;
begin
  PrepareLongXmlPair(lShortRoot, lLongRoot);
  lVendor := DefaultDOMVendor;
  try
    DefaultDOMVendor := sOmniXmlVendor;
    ReadStatusSummary(TPath.Combine(lShortRoot, 'Status.xml'), lShortVersion, lShortCompiler);
    Assert.AreEqual('2.1 é', lShortVersion);
    Assert.AreEqual('Delphi 12 ü', lShortCompiler);
    ReadStatusSummary(TPath.Combine(lLongRoot, 'Status.xml'), lLongVersion, lLongCompiler);
    Assert.AreEqual(lShortVersion, lLongVersion);
    Assert.AreEqual(lShortCompiler, lLongCompiler);
  finally
    DefaultDOMVendor := lVendor;
  end;
end;

procedure TPalFindingNormalizeTests.LongXmlFindingsMatchShortXml;
var
  lError: string;
  lJson: TJSONObject;
  lLongCounts: TPalFindingCounts;
  lLongLines: TArray<string>;
  lLongOut: string;
  lLongRoot: string;
  lShortCounts: TPalFindingCounts;
  lShortLines: TArray<string>;
  lShortOut: string;
  lShortRoot: string;
  lVendor: string;
begin
  PrepareLongXmlPair(lShortRoot, lLongRoot);
  lShortOut := TPath.Combine(TempRoot, 'pal-short-xml-out');
  lLongOut := TPath.Combine(TempRoot, 'pal-long-xml-out');
  TDirectory.CreateDirectory(lShortOut);
  TDirectory.CreateDirectory(lLongOut);
  lVendor := DefaultDOMVendor;
  try
    Assert.IsTrue(TryGeneratePalArtifactsWithCounts(lShortRoot, lShortOut, lShortCounts, lError), lError);
    Assert.AreEqual(1, lShortCounts.Total);
    lShortLines := TFile.ReadAllLines(TPath.Combine(lShortOut, 'pal-findings.jsonl'));
    Assert.AreEqual<NativeInt>(NativeInt(1), Length(lShortLines));
    lJson := ParseJsonObject(lShortLines[0]);
    try
      Assert.IsTrue(lJson <> nil, 'Short PAL finding JSON is invalid.');
      Assert.AreEqual('café', lJson.GetValue<string>('message'));
    finally
      lJson.Free;
    end;
    Assert.IsTrue(TryGeneratePalArtifactsWithCounts(lLongRoot, lLongOut, lLongCounts, lError), lError);
    Assert.AreEqual(lShortCounts.Total, lLongCounts.Total);
    lLongLines := TFile.ReadAllLines(TPath.Combine(lLongOut, 'pal-findings.jsonl'));
    Assert.AreEqual<NativeInt>(Length(lShortLines), Length(lLongLines));
    Assert.AreEqual(lShortLines[0], lLongLines[0]);
  finally
    DefaultDOMVendor := lVendor;
  end;
end;

procedure TPalFindingNormalizeTests.LongXmlMalformedAndMissingKeepFailureContracts;
var
  lCompiler: string;
  lCounts: TPalFindingCounts;
  lError: string;
  lLongRoot: string;
  lMissingPath: string;
  lOutRoot: string;
  lRaised: Boolean;
  lShortError: string;
  lShortRoot: string;
  lVendor: string;
  lVersion: string;
begin
  PrepareLongXmlPair(lShortRoot, lLongRoot);
  lMissingPath := TPath.Combine(lLongRoot, 'Missing.xml');
  Assert.AreEqual(0, GetSectionCountTotal(lMissingPath));
  ReadStatusSummary(lMissingPath, lVersion, lCompiler);
  Assert.AreEqual('', lVersion);
  Assert.AreEqual('', lCompiler);

  TFile.WriteAllText(TPath.Combine(lShortRoot, 'Warnings.xml'),
    '<?xml version="1.0" encoding="utf-8"?><report><section>', TEncoding.UTF8);
  TFile.Copy(TPath.Combine(lShortRoot, 'Warnings.xml'),
    LongPathSafe(TPath.Combine(lLongRoot, 'Warnings.xml')), True);
  lVendor := DefaultDOMVendor;
  try
    DefaultDOMVendor := sOmniXmlVendor;
    lRaised := False;
    try
      GetSectionCountTotal(TPath.Combine(lShortRoot, 'Warnings.xml'));
    except
      on E: Exception do
        lRaised := True;
    end;
    Assert.IsTrue(lRaised, 'Malformed short XML must raise from the common reader.');
    lRaised := False;
    try
      GetSectionCountTotal(TPath.Combine(lLongRoot, 'Warnings.xml'));
    except
      on E: Exception do
        lRaised := True;
    end;
    Assert.IsTrue(lRaised, 'Malformed long XML must raise from the common reader.');

    lOutRoot := TPath.Combine(TempRoot, 'pal-malformed-long-xml-out');
    TDirectory.CreateDirectory(lOutRoot);
    Assert.IsFalse(TryGeneratePalArtifactsWithCounts(lShortRoot, lOutRoot, lCounts, lShortError));
    Assert.IsTrue(lShortError.StartsWith('PAL XML load failed: ' +
      TPath.Combine(lShortRoot, 'Warnings.xml')), lShortError);
    Assert.IsFalse(TryGeneratePalArtifactsWithCounts(lLongRoot, lOutRoot, lCounts, lError));
    Assert.IsTrue(lError.StartsWith('PAL XML load failed: ' +
      TPath.Combine(lLongRoot, 'Warnings.xml')), lError);
  finally
    DefaultDOMVendor := lVendor;
  end;
end;

procedure TPalFindingNormalizeTests.NestedLongPalReportRootDiscoveryKeepsLogicalPath;
var
  lCounts: TPalFindingCounts;
  lError: string;
  lLongNested: string;
  lLongReportRoot: string;
  lLongRoot: string;
  lOutRoot: string;
  lShortNested: string;
  lShortReportRoot: string;
  lShortRoot: string;
  lVendor: string;
begin
  PrepareLongXmlPair(lShortRoot, lLongRoot);
  lShortNested := TPath.Combine(lShortRoot, 'report');
  lLongNested := TPath.Combine(lLongRoot, 'report');
  TDirectory.CreateDirectory(lShortNested);
  TDirectory.CreateDirectory(LongPathSafe(lLongNested));
  TFile.Copy(TPath.Combine(lShortRoot, 'Status.xml'),
    TPath.Combine(lShortNested, 'Status.xml'));
  TFile.Copy(TPath.Combine(lShortRoot, 'Warnings.xml'),
    TPath.Combine(lShortNested, 'Warnings.xml'));
  TFile.Copy(LongPathSafe(TPath.Combine(lLongRoot, 'Status.xml')),
    LongPathSafe(TPath.Combine(lLongNested, 'Status.xml')));
  TFile.Copy(LongPathSafe(TPath.Combine(lLongRoot, 'Warnings.xml')),
    LongPathSafe(TPath.Combine(lLongNested, 'Warnings.xml')));
  TFile.Delete(TPath.Combine(lShortRoot, 'Status.xml'));
  TFile.Delete(LongPathSafe(TPath.Combine(lLongRoot, 'Status.xml')));

  Assert.IsFalse(TFile.Exists(TPath.Combine(lShortRoot, 'Status.xml')),
    'Short root Status.xml must be absent to require nested discovery.');
  Assert.IsFalse(TFile.Exists(LongPathSafe(TPath.Combine(lLongRoot, 'Status.xml'))),
    'Long root Status.xml must be absent to require nested discovery.');
  Assert.IsTrue(Length(TPath.Combine(lLongNested, 'Status.xml')) > 300,
    'Nested PAL Status.xml must exceed 300 characters.');
  Assert.IsTrue(TFile.Exists(LongPathSafe(TPath.Combine(lLongNested, 'Status.xml'))),
    'Nested long Status.xml setup failed.');
  Assert.IsTrue(TFile.Exists(LongPathSafe(TPath.Combine(lLongNested, 'Warnings.xml'))),
    'Nested long Warnings.xml setup failed.');

  Assert.IsTrue(TryFindPalReportRoot(lShortRoot, lShortReportRoot, lError), lError);
  Assert.AreEqual(lShortNested, lShortReportRoot);
  Assert.IsTrue(TryFindPalReportRoot(lLongRoot, lLongReportRoot, lError), lError);
  Assert.AreEqual(lLongNested, lLongReportRoot);

  lOutRoot := TPath.Combine(TempRoot, 'pal-nested-long-xml-out');
  TDirectory.CreateDirectory(lOutRoot);
  lVendor := DefaultDOMVendor;
  try
    Assert.IsTrue(TryGeneratePalArtifactsWithCounts(lLongReportRoot, lOutRoot, lCounts, lError), lError);
    Assert.AreEqual(1, lCounts.Total);
  finally
    DefaultDOMVendor := lVendor;
  end;
end;

procedure TPalFindingNormalizeTests.NormalizePalFindingsFromFixtures;
var
  lFixtureRoot: string;
  lCounts: TPalFindingCounts;
  lOutDir: string;
  lError: string;
  lFindingsPath: string;
  lHotspotsPath: string;
  lJsonPath: string;
  lLines: TArray<string>;
  lJsonLines: TArray<string>;
  lJson: TJSONObject;
  lRawExceptionAfter: string;
  lRawExceptionBefore: string;
  lFound: Boolean;
  i: Integer;
begin
  lFixtureRoot := PalFixtureRoot;
  RequirePalFixtures(lFixtureRoot);

  lOutDir := TPath.Combine(TempRoot, 'pal-findings');
  if TDirectory.Exists(lOutDir) then
    TDirectory.Delete(lOutDir, True);
  TDirectory.CreateDirectory(lOutDir);
  lRawExceptionBefore := TFile.ReadAllText(TPath.Combine(lFixtureRoot, 'Exception.xml'), TEncoding.UTF8);

  if not TryGeneratePalArtifactsWithCounts(lFixtureRoot, lOutDir, lCounts, lError) then
    Assert.Fail('PAL findings generation failed: ' + lError);
  Assert.AreEqual(4, lCounts.Warnings);
  Assert.AreEqual(1, lCounts.StrongWarnings);
  Assert.AreEqual(1, lCounts.Optimizations);
  Assert.AreEqual(6, lCounts.Total);

  lFindingsPath := TPath.Combine(lOutDir, 'pal-findings.md');
  Assert.IsTrue(FileExists(lFindingsPath), 'pal-findings.md missing: ' + lFindingsPath);
  lLines := TFile.ReadAllLines(lFindingsPath);
  Assert.IsTrue(Length(lLines) > 0, 'pal-findings.md is empty.');

  lFound := False;
  for i := 0 to High(lLines) do
    if lLines[i].Contains('Dak.FixInsightRunner:106') then
      lFound := True;
  Assert.IsTrue(lFound, 'Expected Dak.FixInsightRunner:106 in pal-findings.md');

  lJsonPath := TPath.Combine(lOutDir, 'pal-findings.jsonl');
  Assert.IsTrue(FileExists(lJsonPath), 'pal-findings.jsonl missing: ' + lJsonPath);
  lJsonLines := TFile.ReadAllLines(lJsonPath);
  Assert.IsTrue(Length(lJsonLines) > 0, 'pal-findings.jsonl is empty.');
  Assert.AreEqual(lCounts.Total, Integer(Length(lJsonLines)),
    'Normalized count total must match the JSONL row count.');
  for i := 0 to High(lJsonLines) do
  begin
    Assert.IsFalse(lJsonLines[i].Contains('"report":"Exception.xml"'),
      'Exception call-tree rows are diagnostic propagation data, not actionable findings.');
    Assert.IsFalse(lJsonLines[i].Contains('"severity":"exception"'),
      'Exception call-tree severity must not enter actionable findings.');
  end;

  lRawExceptionAfter := TFile.ReadAllText(TPath.Combine(lFixtureRoot, 'Exception.xml'), TEncoding.UTF8);
  Assert.AreEqual(lRawExceptionBefore, lRawExceptionAfter, 'Raw Exception.xml must remain byte-for-byte untouched.');

  lJson := ParseJsonObject(lJsonLines[0]);
  try
    Assert.IsTrue(lJson <> nil, 'First JSON line is invalid.');
    Assert.IsTrue(lJson.GetValue('severity') <> nil, 'JSON missing severity.');
    Assert.IsTrue(lJson.GetValue('report') <> nil, 'JSON missing report.');
    Assert.IsTrue(lJson.GetValue('section') <> nil, 'JSON missing section.');
    Assert.IsTrue(lJson.GetValue('module') <> nil, 'JSON missing module.');
    Assert.IsTrue(lJson.GetValue('line') <> nil, 'JSON missing line.');
  finally
    lJson.Free;
  end;

  lHotspotsPath := TPath.Combine(lOutDir, 'pal-hotspots.md');
  Assert.IsTrue(FileExists(lHotspotsPath), 'pal-hotspots.md missing: ' + lHotspotsPath);
  lLines := TFile.ReadAllLines(lHotspotsPath);
  lFound := False;
  for i := 0 to High(lLines) do
    if lLines[i].Contains('TryParseOptions') then
      lFound := True;
  Assert.IsTrue(lFound, 'Expected TryParseOptions in pal-hotspots.md');

  lFound := False;
  for i := 0 to High(lLines) do
    if lLines[i].Contains('## Modules by decision points') then
      lFound := True;
  Assert.IsTrue(lFound, 'Expected module decision-point totals in pal-hotspots.md');

  lFound := False;
  for i := 0 to High(lLines) do
    if lLines[i].Contains('## Modules by lines') then
      lFound := True;
  Assert.IsTrue(lFound, 'Expected module line totals in pal-hotspots.md');
end;

procedure TPalFindingNormalizeTests.MalformedHotspotReportsPreserveFindingsAndRecordWarning;
var
  lFixtureRoot: string;
  lHotspotsPath: string;
  lJsonLines: TArray<string>;
  lJsonPath: string;
  lLines: TArray<string>;
  lOutDir: string;
  lSourceRoot: string;
  lText: string;
begin
  lSourceRoot := PalFixtureRoot;
  RequirePalFixtures(lSourceRoot);
  CopyPalFixtureToTemp(lSourceRoot, 'pal-findings-malformed-hotspots', lFixtureRoot);
  TFile.WriteAllText(TPath.Combine(lFixtureRoot, 'Complexity.xml'),
    '<?xml version="1.0" encoding="utf-8"?><report><section>', TEncoding.UTF8);

  lOutDir := TPath.Combine(TempRoot, 'pal-findings-malformed-hotspots-out');
  if TDirectory.Exists(lOutDir) then
    TDirectory.Delete(lOutDir, True);
  TDirectory.CreateDirectory(lOutDir);

  if not TryGeneratePalArtifacts(lFixtureRoot, lOutDir, lText) then
    Assert.Fail('PAL findings generation failed: ' + lText);

  lJsonPath := TPath.Combine(lOutDir, 'pal-findings.jsonl');
  Assert.IsTrue(FileExists(lJsonPath), 'pal-findings.jsonl missing: ' + lJsonPath);
  lJsonLines := TFile.ReadAllLines(lJsonPath);
  Assert.IsTrue(Length(lJsonLines) > 0, 'Malformed hotspot input must preserve normalized findings output.');

  lHotspotsPath := TPath.Combine(lOutDir, 'pal-hotspots.md');
  Assert.IsTrue(FileExists(lHotspotsPath), 'pal-hotspots.md missing: ' + lHotspotsPath);
  lLines := TFile.ReadAllLines(lHotspotsPath);
  lText := String.Join(sLineBreak, lLines);
  Assert.IsTrue(lText.Contains('## Warnings'),
    'Malformed hotspot input must emit a visible warning section.');
  Assert.IsTrue(lText.Contains('Complexity.xml'),
    'Malformed hotspot warning should name the degraded PAL report.');
  Assert.IsTrue(lText.Contains('PAL XML load failed') or lText.Contains('Complexity report section not found'),
    'Malformed hotspot warning should include the parse failure reason. Actual: ' + lText);
end;

procedure TPalFindingNormalizeTests.ModulesXmlResolvesFindingPathsDeterministically;
var
  lCounts: TPalFindingCounts;
  lError: string;
  lJson: TJSONObject;
  lJsonLines: TArray<string>;
  lModule: string;
  lOutRoot: string;
  lPath: string;
  lReportRoot: string;
  lStatus: string;
  i: Integer;
begin
  lReportRoot := TPath.Combine(TempRoot, 'pal-module-paths');
  lOutRoot := TPath.Combine(TempRoot, 'pal-module-paths-out');
  TDirectory.CreateDirectory(lReportRoot);
  TDirectory.CreateDirectory(lOutRoot);
  TFile.WriteAllText(TPath.Combine(lReportRoot, 'Warnings.xml'),
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<report><section name="Module paths" count="4">' +
    '<item><id>suffix</id><locmod>sample.unit\TWorker\Run (7)</locmod></item>' +
    '<item><id>same</id><locmod>SameUnit (8)</locmod></item>' +
    '<item><id>ambiguous</id><locmod>AmbiguousUnit (9)</locmod></item>' +
    '<item><id>missing</id><locmod>MissingUnit (10)</locmod></item>' +
    '</section></report>', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lReportRoot, 'Modules.xml'),
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<report><section name="Module information" count="6">' +
    '<module><name>Sample.Unit</name><path>C:\Repo\Sample.Unit.pas</path></module>' +
    '<module><name>sameunit</name><path>C:\Repo\SameUnit.pas</path></module>' +
    '<module><name>SAMEUNIT</name><path>c:\repo\sameunit.pas</path></module>' +
    '<module><name>AmbiguousUnit</name><path>C:\Repo\A\AmbiguousUnit.pas</path></module>' +
    '<module><name>ambiguousunit</name><path>C:\Repo\B\AmbiguousUnit.pas</path></module>' +
    '<module><name>Unused</name><path>C:\Repo\Unused.pas</path></module>' +
    '</section></report>', TEncoding.UTF8);

  Assert.IsTrue(TryGeneratePalArtifactsWithCounts(lReportRoot, lOutRoot, lCounts, lError), lError);
  Assert.AreEqual(4, lCounts.Total);
  lJsonLines := TFile.ReadAllLines(TPath.Combine(lOutRoot, 'pal-findings.jsonl'));
  Assert.AreEqual(4, Integer(Length(lJsonLines)));
  for i := 0 to High(lJsonLines) do
  begin
    lJson := ParseJsonObject(lJsonLines[i]);
    try
      lModule := lJson.GetValue<string>('module');
      lPath := lJson.GetValue<string>('path', '');
      lStatus := lJson.GetValue<string>('path_status', '');
      if SameText(lModule, 'sample.unit\TWorker\Run') then
      begin
        Assert.AreEqual('C:\Repo\Sample.Unit.pas', lPath);
        Assert.AreEqual('resolved', lStatus);
      end
      else if SameText(lModule, 'SameUnit') then
      begin
        Assert.IsTrue(SameText('C:\Repo\SameUnit.pas', lPath), lPath);
        Assert.AreEqual('resolved', lStatus);
      end
      else if SameText(lModule, 'AmbiguousUnit') then
      begin
        Assert.AreEqual('', lPath);
        Assert.AreEqual('ambiguous', lStatus);
      end
      else if SameText(lModule, 'MissingUnit') then
      begin
        Assert.AreEqual('', lPath);
        Assert.AreEqual('missing', lStatus);
      end;
    finally
      lJson.Free;
    end;
  end;
end;

procedure TPalFindingNormalizeTests.ReportNameResolvesOnlyUniqueRecordedMain(
  const aCase, aExpectedStatus, aExpectedPath: string);
var
  lCounts: TPalFindingCounts;
  lError: string;
  lJson: TJSONObject;
  lLines: TArray<string>;
  lMainPath: string;
  lModules: string;
  lOutRoot: string;
  lReportRoot: string;
  i: Integer;
begin
  lReportRoot := TPath.Combine(TempRoot, 'pal-report-name-' + aCase);
  lOutRoot := TPath.Combine(TempRoot, 'pal-report-name-out-' + aCase);
  TDirectory.CreateDirectory(lReportRoot);
  TDirectory.CreateDirectory(lOutRoot);
  lMainPath := 'C:\Repo\DelphiAIKit.Tests.dpr';
  lModules := '<module><name>DelphiAIKit_Tests</name><path>' + lMainPath + '</path></module>';
  if SameText(aCase, 'different') then
    lMainPath := 'C:\Repo\Other.dpr'
  else if SameText(aCase, 'conflicting') then
    lModules := lModules + '<module><name>DelphiAIKit_Tests</name>' +
      '<path>C:\Repo\Other.dpr</path></module>'
  else if SameText(aCase, 'duplicate-main') then
    lModules := lModules + '<module><name>AnotherProgram</name><path>' +
      lMainPath + '</path></module>'
  else if SameText(aCase, 'alias-conflict') then
    lModules := lModules + '<module><name>DelphiAIKit.Tests</name>' +
      '<path>C:\Repo\Other.dpr</path></module>'
  else if SameText(aCase, 'ambiguous-alias') then
    lModules := lModules + '<module><name>DelphiAIKit.Tests</name>' +
      '<path>C:\Repo\Other.dpr</path></module>' +
      '<module><name>DelphiAIKit.Tests</name><path>C:\Repo\Third.dpr</path></module>';
  TFile.WriteAllText(TPath.Combine(lReportRoot, 'Modules.xml'),
    '<report><section name="Modules">' + lModules + '</section></report>', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lReportRoot, 'Warnings.xml'),
    '<report><section name="Warnings"><item><id>base</id>' +
    '<locmod>DelphiAIKit.Tests (7)</locmod></item><item><id>qualified</id>' +
    '<locmod>DelphiAIKit.Tests\TWorker\Run (8)</locmod></item></section></report>', TEncoding.UTF8);
  if SameText(aCase, 'no-context') then
    Assert.IsTrue(TryGeneratePalArtifactsWithCounts(lReportRoot, lOutRoot, lCounts, lError), lError)
  else
    Assert.IsTrue(TryGeneratePalArtifactsForProject(lReportRoot, lOutRoot,
      'DelphiAIKit.Tests', lMainPath, lCounts, lError), lError);
  Assert.AreEqual(2, lCounts.Total);
  lLines := TFile.ReadAllLines(TPath.Combine(lOutRoot, 'pal-findings.jsonl'));
  Assert.AreEqual(2, Integer(Length(lLines)));
  for i := 0 to High(lLines) do
  begin
    lJson := ParseJsonObject(lLines[i]);
    try
      Assert.AreEqual(aExpectedStatus, lJson.GetValue<string>('path_status'));
      Assert.AreEqual(aExpectedPath, lJson.GetValue<string>('path', ''));
      if i = 0 then
        Assert.AreEqual('DelphiAIKit.Tests', lJson.GetValue<string>('module'))
      else
        Assert.AreEqual('DelphiAIKit.Tests\TWorker\Run', lJson.GetValue<string>('module'));
    finally
      lJson.Free;
    end;
  end;
end;

procedure TPalFindingNormalizeTests.ModulesXmlResolvesIncludePaths(const aModule, aExpectedStatus: string;
  const aConflicting: Boolean);
var
  lCounts: TPalFindingCounts;
  lError: string;
  lJson: TJSONObject;
  lJsonLines: TArray<string>;
  lOtherPath: string;
  lOutRoot: string;
  lReportRoot: string;
begin
  lReportRoot := TPath.Combine(TempRoot, 'pal-include-paths');
  lOutRoot := TPath.Combine(TempRoot, 'pal-include-paths-out');
  TDirectory.CreateDirectory(lReportRoot);
  TDirectory.CreateDirectory(lOutRoot);
  TFile.WriteAllText(TPath.Combine(lReportRoot, 'Warnings.xml'),
    '<report><section name="Unused variables" count="1"><item><id>include-variable</id>' +
    '<locmod>' + aModule + ' (12)</locmod></item></section></report>', TEncoding.UTF8);
  lOtherPath := 'c:\repo\shared.inc';
  if aConflicting then
    lOtherPath := 'C:\Other\Shared.inc';
  TFile.WriteAllText(TPath.Combine(lReportRoot, 'Modules.xml'),
    '<report><section name="Module information">' +
    '<module><name>Owner</name><path>C:\Repo\Owner.pas</path>' +
    '<includes><name>Shared.inc</name><path>C:\Repo\Shared.inc</path></includes></module>' +
    '<module><name>OtherOwner</name><path>C:\Repo\OtherOwner.pas</path>' +
    '<includes><name>SHARED.INC</name><path>' + lOtherPath + '</path></includes></module>' +
    '<module><name>LastOwner</name><path>C:\Repo\LastOwner.pas</path>' +
    '<includes><name>Shared.inc</name><path>C:\Repo\Shared.inc</path></includes></module>' +
    '</section></report>', TEncoding.UTF8);

  Assert.IsTrue(TryGeneratePalArtifactsWithCounts(lReportRoot, lOutRoot, lCounts, lError), lError);
  Assert.AreEqual(1, lCounts.Total, 'Include path resolution must preserve the finding.');
  lJsonLines := TFile.ReadAllLines(TPath.Combine(lOutRoot, 'pal-findings.jsonl'));
  Assert.AreEqual(1, Integer(Length(lJsonLines)));
  lJson := ParseJsonObject(lJsonLines[0]);
  try
    Assert.AreEqual(aExpectedStatus, lJson.GetValue<string>('path_status'));
    if aConflicting then
      Assert.AreEqual('', lJson.GetValue<string>('path', ''))
    else
      Assert.AreEqual('C:\Repo\Shared.inc', lJson.GetValue<string>('path'));
  finally
    lJson.Free;
  end;
end;

procedure TPalFindingNormalizeTests.LocInfoPreservesAnalyzerMessage;
var
  lCounts: TPalFindingCounts;
  lError: string;
  lJson: TJSONObject;
  lJsonLines: TArray<string>;
  lOutRoot: string;
  lReportRoot: string;
begin
  lReportRoot := TPath.Combine(TempRoot, 'pal-loc-info');
  lOutRoot := TPath.Combine(TempRoot, 'pal-loc-info-out');
  TDirectory.CreateDirectory(lReportRoot);
  TDirectory.CreateDirectory(lOutRoot);
  TFile.WriteAllText(TPath.Combine(lReportRoot, 'Warnings.xml'),
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<report><section name="Mismatch parameter value (32/64-bits)" count="1">' +
    '<name>aDelta</name><loc><locmod>Sample.Unit</locmod><locline>24</locline>' +
    '<info>64-bits aDelta passed as 32-bits parameter N]</info></loc>' +
    '</section></report>', TEncoding.UTF8);

  Assert.IsTrue(TryGeneratePalArtifactsWithCounts(lReportRoot, lOutRoot, lCounts, lError), lError);
  Assert.AreEqual(1, lCounts.Total);
  lJsonLines := TFile.ReadAllLines(TPath.Combine(lOutRoot, 'pal-findings.jsonl'));
  Assert.AreEqual(1, Integer(Length(lJsonLines)));
  lJson := ParseJsonObject(lJsonLines[0]);
  try
    Assert.AreEqual('64-bits aDelta passed as 32-bits parameter N]',
      lJson.GetValue<string>('message', ''));
  finally
    lJson.Free;
  end;
end;

procedure TPalFindingNormalizeTests.MissingPalFixturesFailClosedWithoutOptOut;
var
  lAllowGuard: IInterface;
  lFailed: Boolean;
  lRootGuard: IInterface;
begin
  lRootGuard := SetScopedEnvironmentVariable(cPalFixtureRootEnv, TPath.Combine(TempRoot, 'missing-pal-fixtures'));
  lAllowGuard := ClearScopedEnvironmentVariable(cAllowMissingPalFixturesEnv);
  try
    lFailed := False;
    try
      NormalizePalFindingsFromFixtures;
    except
      on E: Exception do
      begin
        lFailed := Pos('PAL fixtures missing', E.Message) > 0;
        if not lFailed then
          raise;
      end;
    end;

    Assert.IsTrue(lFailed,
      'Missing PAL fixtures must fail closed unless ' + cAllowMissingPalFixturesEnv +
      ' is explicitly set.');
  finally
    lAllowGuard := nil;
    lRootGuard := nil;
  end;
end;

procedure TPalFindingNormalizeTests.NegativeSectionCountsDoNotReduceActionableTotals;
var
  lCounts: TPalFindingCounts;
  lError: string;
  lJsonLines: TArray<string>;
  lOutRoot: string;
  lPath: string;
  lReportRoot: string;
begin
  lReportRoot := TPath.Combine(TempRoot, 'pal-negative-section-count');
  lOutRoot := TPath.Combine(TempRoot, 'pal-negative-section-count-out');
  TDirectory.CreateDirectory(lReportRoot);
  TDirectory.CreateDirectory(lOutRoot);
  lPath := TPath.Combine(lReportRoot, 'Warnings.xml');
  TFile.WriteAllText(lPath,
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<report><section name="Actionable" count="1"><loc><locmod>Sample.Unit</locmod>' +
    '<locline>7</locline></loc></section>' +
    '<section name="Sentinel" count="-2" /></report>', TEncoding.UTF8);

  Assert.AreEqual(1, GetSectionCountTotal(lPath));
  Assert.IsTrue(TryGeneratePalArtifactsWithCounts(lReportRoot, lOutRoot, lCounts, lError), lError);
  Assert.AreEqual(1, lCounts.Warnings);
  Assert.AreEqual(1, lCounts.Total);
  lJsonLines := TFile.ReadAllLines(TPath.Combine(lOutRoot, 'pal-findings.jsonl'));
  Assert.AreEqual(1, Integer(Length(lJsonLines)));
end;

procedure TPalFindingNormalizeTests.ProjectSummaryUsesNormalizedActionableCounts;
var
  lCounts: TPalFindingCounts;
  lError: string;
  lFixtureRoot: string;
  lFixCounts: TFixInsightCounts;
  lOutRoot: string;
  lPal: TPalSummary;
  lSummary: string;
begin
  lFixtureRoot := PalFixtureRoot;
  RequirePalFixtures(lFixtureRoot);
  lOutRoot := TPath.Combine(TempRoot, 'pal-summary-normalized-counts');
  TDirectory.CreateDirectory(lOutRoot);
  Assert.IsTrue(TryGeneratePalArtifactsWithCounts(lFixtureRoot, lOutRoot, lCounts, lError), lError);

  lFixCounts := Default(TFixInsightCounts);
  lPal := Default(TPalSummary);
  lPal.Ran := True;
  lPal.Warnings := lCounts.Warnings;
  lPal.StrongWarnings := lCounts.StrongWarnings;
  lPal.Optimizations := lCounts.Optimizations;

  lSummary := BuildProjectSummary('Sample', 'C:\repo\Sample.dproj', 'C:\repo\.dak\Sample', '', '', '', False,
    False, False, 0, 0, 0, lFixCounts, lPal, []);

  Assert.IsTrue(lSummary.Contains(
    '- Totals: warnings=4, strong_warnings=1, optimizations=1, total=6'), lSummary);
  Assert.IsFalse(lSummary.Contains('exceptions='), lSummary);
end;

procedure TPalFindingNormalizeTests.ProjectRunnerUsesNormalizedArtifactCounts;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.analyze.projectrunner.pas'), TEncoding.UTF8);
  Assert.IsTrue(lSource.Contains('TryGeneratePalArtifactsForProject'),
    'Project summary counts must come from the normalized artifact list with main-source context.');
  Assert.IsTrue(lSource.Contains('AddError(''PAL findings generation failed: '' + lPalPostError, 6)'),
    'Required project PAL normalization failures must fail the command.');
  Assert.IsTrue(lSource.Contains('AddError(''PAL report root not found: '' + lPalPostError, 6)'),
    'Missing project PAL status must fail the command.');
  Assert.IsTrue(lSource.Contains(
    'AddError(''PAL post-processing failed: '' + E.ClassName + '': '' + E.Message, 6)'),
    'Project PAL extraction exceptions must fail the command.');
  Assert.IsFalse(lSource.Contains('GetSectionCountTotal('),
    'Project summary must not use raw PAL section-count metadata.');
end;

procedure TPalFindingNormalizeTests.UnitSummaryUsesNormalizedActionableCounts;
var
  lPal: TPalSummary;
  lSummary: string;
begin
  lPal := Default(TPalSummary);
  lPal.Ran := True;
  lPal.Warnings := 4;
  lPal.StrongWarnings := 1;
  lPal.Optimizations := 1;

  lSummary := BuildUnitSummary('Sample', 'C:\repo\Sample.pas', 'C:\repo\.dak\_unit\Sample', lPal, []);

  Assert.IsTrue(lSummary.Contains(
    '- Totals: warnings=4, strong_warnings=1, optimizations=1, total=6'), lSummary);
end;

procedure TPalFindingNormalizeTests.UnitSummaryMarksSkippedAnalyzer;
var
  lPal: TPalSummary;
  lSummary: string;
begin
  lPal := Default(TPalSummary);

  lSummary := BuildUnitSummary('Sample', 'C:\repo\Sample.pas', 'C:\repo\.dak\_unit\Sample', lPal, []);

  Assert.IsTrue(lSummary.Contains('- Skipped.'), lSummary);
end;

procedure TPalFindingNormalizeTests.UnitRunnerUsesNormalizedArtifactCounts;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.analyze.unitrunner.pas'), TEncoding.UTF8);
  Assert.IsTrue(lSource.Contains('TryGeneratePalArtifactsWithCounts'),
    'Unit summary counts must come from the normalized artifact list.');
  Assert.IsTrue(lSource.Contains('AddError(''PAL findings generation failed: '' + lPalPostError, 6)'),
    'Required unit PAL normalization failures must fail the command.');
  Assert.IsTrue(lSource.Contains('AddError(''PAL report root not found: '' + lPalPostError, 6)'),
    'Missing unit PAL status must fail the command.');
  Assert.IsTrue(lSource.Contains(
    'AddError(''PAL post-processing failed: '' + E.ClassName + '': '' + E.Message, 6)'),
    'Unit PAL extraction exceptions must fail the command.');
  Assert.IsFalse(lSource.Contains('GetSectionCountTotal('),
    'Unit summary must not use raw PAL section-count metadata.');
end;

initialization
  TDUnitX.RegisterTestFixture(TPalFindingNormalizeTests);

end.
