program DelphiAIKit_Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  Test.Support in 'units\\test.support.pas',
  Test.Build in 'units\\test.build.pas',
  Test.Diagnostics in 'units\\test.diagnostics.pas',
  Test.FixInsight in 'units\\test.fixinsight.pas',
  Test.PalFindingNormalize in 'units\\test.palfindingnormalize.pas',
  Test.PascalAnalyzer in 'units\\test.pascalanalyzer.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
begin
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := False;

    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);

    Results := Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := 1
    else
      System.ExitCode := 0;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := 1;
    end;
  end;
end.
