unit Test.Diagnostics;

interface

uses
  DUnitX.TestFramework,
  System.IOUtils,
  System.SysUtils,
  Dak.Diagnostics,
  Test.Support;

type
  [TestFixture]
  TDiagnosticsTests = class
  public
    [Test]
    procedure ReopenLogFileReleasesPreviousHandle;
  end;

implementation

procedure TDiagnosticsTests.ReopenLogFileReleasesPreviousHandle;
var
  lDiagnostics: TDiagnostics;
  lRoot: string;
  lFirstLog: string;
  lSecondLog: string;
  lError: string;
  lDeleteOk: Boolean;
begin
  lRoot := TPath.Combine(TempRoot, 'diagnostics');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  lFirstLog := TPath.Combine(lRoot, 'first.log');
  lSecondLog := TPath.Combine(lRoot, 'second.log');

  lDiagnostics := TDiagnostics.Create;
  try
    Assert.IsTrue(lDiagnostics.TryOpenLogFile(lFirstLog, lError), 'First open failed: ' + lError);
    Assert.IsTrue(lDiagnostics.TryOpenLogFile(lSecondLog, lError), 'Second open failed: ' + lError);

    lDeleteOk := True;
    try
      TFile.Delete(lFirstLog);
    except
      on Exception do
        lDeleteOk := False;
    end;

    Assert.IsTrue(lDeleteOk, 'First log file remained locked after reopening.');
  finally
    lDiagnostics.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDiagnosticsTests);

end.
