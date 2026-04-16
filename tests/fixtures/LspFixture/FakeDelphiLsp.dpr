program FakeDelphiLsp;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  FakeDelphiLspMain in 'FakeDelphiLspMain.pas';

begin
  ReportMemoryLeaksOnShutdown := True;
  try
    System.ExitCode := RunFakeDelphiLsp;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName + ': ' + E.Message);
      System.ExitCode := 1;
    end;
  end;
end.
