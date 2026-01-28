unit Tests.PalFindingNormalize;

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  System.IOUtils,
  System.SysUtils,
  Tests.Support,
  Dcr.PascalAnalyzerRunner;

type
  [TestFixture]
  TPalFindingNormalizeTests = class
  public
    [Test]
    procedure NormalizePalFindingsFromFixtures;
  end;

implementation

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
  lFixtureRoot := TPath.Combine(RepoRoot, 'docs\sample-pal-reports');
  if not TDirectory.Exists(lFixtureRoot) then
  begin
    Assert.Pass('PAL fixtures missing; skipping.');
    Exit;
  end;
  if not FileExists(TPath.Combine(lFixtureRoot, 'Warnings.xml')) then
  begin
    Assert.Pass('PAL fixtures missing; skipping.');
    Exit;
  end;

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
    if lLines[i].Contains('Dcr.FixInsightRunner:106') then
      lFound := True;
  Assert.IsTrue(lFound, 'Expected Dcr.FixInsightRunner:106 in pal-findings.md');

  lJsonPath := TPath.Combine(lOutDir, 'pal-findings.jsonl');
  Assert.IsTrue(FileExists(lJsonPath), 'pal-findings.jsonl missing: ' + lJsonPath);
  lJsonLines := TFile.ReadAllLines(lJsonPath);
  Assert.IsTrue(Length(lJsonLines) > 0, 'pal-findings.jsonl is empty.');

  lJson := TJSONObject.ParseJSONValue(lJsonLines[0]) as TJSONObject;
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
end;

initialization
  TDUnitX.RegisterTestFixture(TPalFindingNormalizeTests);

end.
