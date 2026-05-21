program DelphiAIKit_Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  DfmCheck_AppConsts in '..\\lib\\DFMCheck\\Source\\DfmCheck_AppConsts.pas',
  DfmCheck_DfmCheck in '..\\lib\\DFMCheck\\Source\\DfmCheck_DfmCheck.pas',
  DfmCheck_Options in '..\\lib\\DFMCheck\\Source\\DfmCheck_Options.pas',
  DfmCheck_PascalParser in '..\\lib\\DFMCheck\\Source\\DfmCheck_PascalParser.pas',
  DfmCheck_Utils in '..\\lib\\DFMCheck\\Source\\DfmCheck_Utils.pas',
  ProjectFileReader in '..\\lib\\DFMCheck\\Source\\Console\\ProjectFileReader.pas',
  Test.Support in 'units\\test.support.pas',
  Test.App in 'units\\test.app.pas',
  Test.Build in 'units\\test.build.pas',
  Test.Cli in 'units\\test.cli.pas',
  Test.DeadCodeCli in 'units\\test.deadcodecli.pas',
  Test.DelphiSemanticsIntegration in 'units\\test.delphisemanticsintegration.pas',
  Test.Deps in 'units\\test.deps.pas',
  Test.DfmInspect in 'units\\test.dfminspect.pas',
  Test.DfmCheck in 'units\\test.dfmcheck.pas',
  Test.Diagnostics in 'units\\test.diagnostics.pas',
  Test.FixInsight in 'units\\test.fixinsight.pas',
  Test.GlobalVars in 'units\\test.globalvars.pas',
  Test.Lsp in 'units\\test.lsp.pas',
  Test.MsBuild in 'units\\test.msbuild.pas',
  Test.PalFindingNormalize in 'units\\test.palfindingnormalize.pas',
  Test.ReportPostProcess in 'units\\test.reportpostprocess.pas',
  Test.PascalAnalyzer in 'units\\test.pascalanalyzer.pas',
  Test.Refactor in 'units\\test.refactor.pas',
  Test.RemoveWith in 'units\\test.removewith.pas',
  Test.SymbolMap in 'units\\test.symbolmap.pas',
  Test.Utils in 'units\\test.utils.pas',
  Test.SourceContext in 'units\\test.sourcecontext.pas',
  ToolsAPIRepl in '..\\lib\\DFMCheck\\Source\\Console\\ToolsAPIRepl.pas';

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
    // Keep DAK RemoveWith tests single-process/sequential. Parallel executions
    // contend for shared test output/temp files and caused runtime 217 failures.

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
