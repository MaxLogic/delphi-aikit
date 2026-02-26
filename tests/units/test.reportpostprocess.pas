unit Test.ReportPostProcess;

interface

uses
  DUnitX.TestFramework,
  System.IOUtils,
  System.SysUtils,
  Dak.ReportPostProcess, Dak.Types,
  Test.Support;

type
  [TestFixture]
  TReportPostProcessTests = class
  public
    [Test]
    procedure CsvIgnoreRuleIdsHandlesSemicolonsInMessage;
  end;

implementation

procedure TReportPostProcessTests.CsvIgnoreRuleIdsHandlesSemicolonsInMessage;
var
  lRoot: string;
  lReportPath: string;
  lLines: TArray<string>;
  lError: string;
begin
  lRoot := TPath.Combine(TempRoot, 'report-postprocess');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  lReportPath := TPath.Combine(lRoot, 'fixinsight.csv');
  lLines := [
    '"C:\repo\src\Unit1.pas",42,1,W501,alpha;beta;gamma;delta;epsilon;zeta'
  ];
  TFile.WriteAllLines(lReportPath, lLines, TEncoding.UTF8);

  Assert.IsTrue(TryPostProcessFixInsightReport(lReportPath, TReportFormat.rfCsv, '', 'W501', lError),
    'CSV post-process failed: ' + lError);

  lLines := TFile.ReadAllLines(lReportPath, TEncoding.UTF8);
  Assert.AreEqual(0, Length(lLines), 'Expected ignored warning row to be removed from CSV output.');
end;

initialization
  TDUnitX.RegisterTestFixture(TReportPostProcessTests);

end.
