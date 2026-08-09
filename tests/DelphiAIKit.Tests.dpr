program DelphiAIKit_Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.Classes, System.IOUtils, System.StrUtils, System.SysUtils,
  FireDAC.Phys.SQLiteWrapper.Stat,
  DUnitX.FilterBuilder,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  DfmCheck_AppConsts in '..\\lib\\DFMCheck\\Source\\DfmCheck_AppConsts.pas',
  DfmCheck_DfmCheck in '..\\lib\\DFMCheck\\Source\\DfmCheck_DfmCheck.pas',
  DfmCheck_Options in '..\\lib\\DFMCheck\\Source\\DfmCheck_Options.pas',
  DfmCheck_PascalParser in '..\\lib\\DFMCheck\\Source\\DfmCheck_PascalParser.pas',
  DfmCheck_Utils in '..\\lib\\DFMCheck\\Source\\DfmCheck_Utils.pas',
  ProjectFileReader in '..\\lib\\DFMCheck\\Source\\Console\\ProjectFileReader.pas',
  Test.Support in 'units\\test.support.pas',
  Test.App in 'units\\test.app.pas',
  Test.AnalyzeStatus in 'units\\test.analyzestatus.pas',
  Test.Build in 'units\\test.build.pas',
  Test.Cli in 'units\\test.cli.pas',
  Test.DeadCodeApplyCli in 'units\\test.deadcodeapplycli.pas',
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
  Test.Refactor.ProprietaryRename in 'units\\test.refactor.proprietaryrename.pas',
  Test.RemoveWith in 'units\\test.removewith.pas',
  Test.SymbolMap in 'units\\test.symbolmap.pas',
  Test.Utils in 'units\\test.utils.pas',
  Test.SourceContext in 'units\\test.sourcecontext.pas',
  ToolsAPIRepl in '..\\lib\\DFMCheck\\Source\\Console\\ToolsAPIRepl.pas';

const
  cMaxTdbProofCategory = 'MaxTdbProof';

procedure RunPalHelpFixture;
begin
  if GetEnvironmentVariable('DAK_TEST_PAL_HELP') <> '1' then
    Exit;

  Writeln('/CD12W32 /CD12W64 /CD13W32 /CD13W64 /NAME=projectname');
  Halt(0);
end;

procedure RunFixInsightFixture;
var
  i: Integer;
  lExitCode: Integer;
  lOutputPath: string;
  lValue: string;
begin
  lValue := GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT');
  if not TryStrToInt(lValue, lExitCode) then
    Exit;

  // The installed analyzer is version-dependent, so this fixture supplies deterministic process behavior.
  lOutputPath := '';
  for i := 1 to ParamCount do
    if StartsText('--output=', ParamStr(i)) then
      lOutputPath := Copy(ParamStr(i), Length('--output=') + 1, MaxInt);
  if lOutputPath <> '' then
  begin
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lOutputPath));
    TFile.WriteAllLines(lOutputPath, ['W501 deterministic warning', 'C101 deterministic finding'],
      TEncoding.UTF8);
  end;
  Halt(lExitCode);
end;

procedure RunPalFixture;
var
  i: Integer;
  lExitCode: Integer;
  lName: string;
  lOutputRoot: string;
  lReportRoot: string;
  lValue: string;
begin
  lValue := GetEnvironmentVariable('DAK_TEST_PAL_EXIT');
  if not TryStrToInt(lValue, lExitCode) then
    Exit;

  // The installed analyzer is version-dependent, so this fixture supplies deterministic process behavior.
  lName := '';
  lOutputRoot := '';
  for i := 1 to ParamCount do
  begin
    if StartsText('/R=', ParamStr(i)) then
      lOutputRoot := Copy(ParamStr(i), Length('/R=') + 1, MaxInt)
    else if StartsText('/NAME=', ParamStr(i)) then
      lName := Copy(ParamStr(i), Length('/NAME=') + 1, MaxInt);
  end;
  if lOutputRoot = '' then
  begin
    Writeln('/CD12W32 /CD12W64 /CD13W32 /CD13W64 /NAME=projectname');
    Halt(0);
  end;
  if (lExitCode = 0) and (lName <> '') then
  begin
    lReportRoot := TPath.Combine(lOutputRoot, lName);
    TDirectory.CreateDirectory(lReportRoot);
    TFile.WriteAllText(TPath.Combine(lReportRoot, 'Status.xml'),
      '<report><section name="Overview"><version>9.21.3</version>' +
      '<compiler>Delphi 13 (Win64)</compiler></section></report>', TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(lReportRoot, 'Warnings.xml'),
      '<report><section name="Warnings"/></report>', TEncoding.UTF8);
  end;
  Halt(lExitCode);
end;

procedure ApplyDefaultCategoryExclusions;
begin
  if (TDUnitX.Options.Run.Count = 0) and
    (TDUnitX.Options.RunListFile = '') and
    (TDUnitX.Options.Include = '') and
    (TDUnitX.Options.Exclude = '') then
  begin
    TDUnitX.Options.Exclude := cMaxTdbProofCategory;
    TDUnitX.Filter := TDUnitXFilterBuilder.BuildFilter(TDUnitX.Options);
  end;
end;

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
begin
  RunPalHelpFixture;
  RunFixInsightFixture;
  RunPalFixture;
  ReportMemoryLeaksOnShutdown := True;
  try
    TDUnitX.CheckCommandLine;
    ApplyDefaultCategoryExclusions;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := True;
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
