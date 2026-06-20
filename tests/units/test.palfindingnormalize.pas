unit Test.PalFindingNormalize;

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  System.IOUtils,
  System.SysUtils,
  Winapi.Windows,
  Test.Support,
  Dak.PascalAnalyzer.Artifacts;

type
  [TestFixture]
  TPalFindingNormalizeTests = class
  private
    procedure CopyPalFixtureToTemp(const aSourceRoot, aTempName: string; out aFixtureRoot: string);
  public
    [Test]
    procedure NormalizePalFindingsFromFixtures;
    [Test]
    procedure MalformedHotspotReportsPreserveFindingsAndRecordWarning;
    [Test]
    procedure MissingPalFixturesFailClosedWithoutOptOut;
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

procedure TPalFindingNormalizeTests.NormalizePalFindingsFromFixtures;
var
  lFixtureRoot: string;
  lOutDir: string;
  lError: string;
  lFindingsPath: string;
  lHotspotsPath: string;
  lJsonPath: string;
  lLines: TArray<string>;
  lJsonLines: TArray<string>;
  lJson: TJSONObject;
  lFound: Boolean;
  i: Integer;
begin
  lFixtureRoot := PalFixtureRoot;
  RequirePalFixtures(lFixtureRoot);

  lOutDir := TPath.Combine(TempRoot, 'pal-findings');
  if TDirectory.Exists(lOutDir) then
    TDirectory.Delete(lOutDir, True);
  TDirectory.CreateDirectory(lOutDir);

  if not TryGeneratePalArtifacts(lFixtureRoot, lOutDir, lError) then
    Assert.Fail('PAL findings generation failed: ' + lError);

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

initialization
  TDUnitX.RegisterTestFixture(TPalFindingNormalizeTests);

end.
