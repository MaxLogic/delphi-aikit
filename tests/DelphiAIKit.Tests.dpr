program DelphiAIKit_Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.Classes, System.IOUtils, System.StrUtils, System.SysUtils,
  FireDAC.Phys.SQLiteWrapper.Stat,
  DUnitX.FilterBuilder,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  Dak.Analysis.Workspace in '..\src\Dak.Analysis.Workspace.pas',
  Dak.Analysis.WorkspaceCommand in '..\src\Dak.Analysis.WorkspaceCommand.pas',
  Dak.Analysis.Doctor in '..\src\Dak.Analysis.Doctor.pas',
  Dak.Analysis.Findings in '..\src\Dak.Analysis.Findings.pas',
  Dak.Analysis.FixInsightImport in '..\src\Dak.Analysis.FixInsightImport.pas',
  Dak.PascalAnalyzer.Help in '..\src\Dak.PascalAnalyzer.Help.pas',
  Test.NativeAnalysisWorkspace in 'units\test.nativeanalysisworkspace.pas',
  Test.NativeAnalysisWorkspace.Provenance in 'units\test.nativeanalysisworkspace.provenance.pas',
  Test.NativeAnalysisWorkspace.Command in 'units\test.nativeanalysisworkspace.command.pas',
  Test.NativeAnalysisDoctor in 'units\test.nativeanalysisdoctor.pas',
  Test.NativeAnalysisDoctor.PalHelp in 'units\test.nativeanalysisdoctor.palhelp.pas',
  Test.NativeAnalysisDoctor.Settings in 'units\test.nativeanalysisdoctor.settings.pas',
  Test.NativeAnalysisDoctor.Remaining in 'units\test.nativeanalysisdoctor.remaining.pas',
  Test.NativeAnalysisDoctor.Contracts in 'units\test.nativeanalysisdoctor.contracts.pas',
  Test.NativeAnalysisDoctor.Paths in 'units\test.nativeanalysisdoctor.paths.pas',
  Dak.Analysis.Text in '..\src\Dak.Analysis.Text.pas',
  Dak.Analysis.Projections in '..\src\Dak.Analysis.Projections.pas',
  Dak.Analysis.UnicodeText in '..\src\Dak.Analysis.UnicodeText.pas',
  Dak.Analysis.NumericText in '..\src\Dak.Analysis.NumericText.pas',
  Dak.Analysis.JsonText in '..\src\Dak.Analysis.JsonText.pas',
  Dak.Analysis.ReportBundle in '..\src\Dak.Analysis.ReportBundle.pas',
  Dak.Analysis.ReportWriters in '..\src\Dak.Analysis.ReportWriters.pas',
  Dak.Analysis.ReportPolicy in '..\src\Dak.Analysis.ReportPolicy.pas',
  Dak.Analysis.ReportReplay in '..\src\Dak.Analysis.ReportReplay.pas',
  Dak.Analysis.ReportVerify in '..\src\Dak.Analysis.ReportVerify.pas',
  Dak.Analysis.ReportCommand in '..\src\Dak.Analysis.ReportCommand.pas',
  Dak.Analysis.WorkflowFinish in '..\src\Dak.Analysis.WorkflowFinish.pas',
  Test.NativeAnalysisReports.Replay in 'units\test.nativeanalysisreports.replay.pas',
  Test.NativeAnalysisReports.Verify in 'units\test.nativeanalysisreports.verify.pas',
  Test.NativeAnalysisPolicy in 'units\test.nativeanalysispolicy.pas',
  Test.NativeAnalysisProject in 'units\test.nativeanalysisproject.pas',
  Test.NativeAnalysisUnit in 'units\test.nativeanalysisunit.pas',
  Test.AnalyzeEnvironment in 'units\test.analyzeenvironment.pas',
  Dak.Analysis.OwnershipContext in '..\src\Dak.Analysis.OwnershipContext.pas',
  Dak.Analysis.ProjectSources in '..\src\Dak.Analysis.ProjectSources.pas',
  Dak.Analysis.SourceResolution in '..\src\Dak.Analysis.SourceResolution.pas',
  Dak.Analysis.Ownership in '..\src\Dak.Analysis.Ownership.pas',
  Test.NativeAnalysisReports.Ownership in 'units\test.nativeanalysisreports.ownership.pas',
  Test.NativeAnalysisReports.Projections in 'units\test.nativeanalysisreports.projections.pas',
  Test.NativeAnalysisReports.Unicode in 'units\test.nativeanalysisreports.unicode.pas',
  Test.NativeAnalysisReports.Numeric in 'units\test.nativeanalysisreports.numeric.pas',
  Test.NativeAnalysisReports.JsonText in 'units\test.nativeanalysisreports.jsontext.pas',
  Test.NativeAnalysisReports.Import in 'units\test.nativeanalysisreports.import.pas',
  Test.NativeAnalysisReports.Import.FixInsight in 'units\test.nativeanalysisreports.import.fixinsight.pas',
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
  Test.ExternalToolProcess in 'units\test.externaltoolprocess.pas',
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
  lIsFixInsight: Boolean;
  lOutputPath: string;
  lReportedFile: string;
  lValue: string;
begin
  lValue := GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_EXIT');
  if not TryStrToInt(lValue, lExitCode) then
    Exit;
  // This executable also stands in for Pascal Analyzer. DAK always starts FixInsight with
  // --project=, so any other invocation (such as the PALCMD help probe) belongs to another fixture.
  lIsFixInsight := False;
  for i := 1 to ParamCount do
    if StartsText('--project=', ParamStr(i)) then
      lIsFixInsight := True;
  if not lIsFixInsight then
    Exit;

  // The installed analyzer is version-dependent, so this fixture supplies deterministic process behavior.
  lOutputPath := '';
  for i := 1 to ParamCount do
    if StartsText('--output=', ParamStr(i)) then
      lOutputPath := Copy(ParamStr(i), Length('--output=') + 1, MaxInt);
  if lOutputPath <> '' then
  begin
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lOutputPath));
    // The layout is FixInsight's own: a File: header, then one indented row per finding ending in
    // its (line, column). The report stage normalizes exactly this shape. The reported file can be
    // overridden so a test can produce a finding whose ownership the workspace cannot resolve.
    lReportedFile := GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_FILE');
    if lReportedFile = '' then
      lReportedFile := 'Sample.dpr';
    // DAK_TEST_FIXINSIGHT_MALFORMED adds a row the summary counter accepts but the normalizer cannot
    // place, so report finalization fails on real input instead of an injected exception.
    // DAK_TEST_FIXINSIGHT_CLEAN writes a report with no findings. DAK_TEST_FIXINSIGHT_THIRD_PARTY
    // appends a second File: block for that path, so ownership can split one run's findings.
    if GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_CLEAN') = '1' then
      TFile.WriteAllText(lOutputPath, '', TEncoding.UTF8)
    else if GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_MALFORMED') = '1' then
      TFile.WriteAllLines(lOutputPath, ['File: ' + lReportedFile,
        '  W501 deterministic warning (12, 3)', '  C101 deterministic finding (18, 5)',
        '  W502 row without a location'], TEncoding.UTF8)
    else if GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_THIRD_PARTY') <> '' then
      TFile.WriteAllLines(lOutputPath, ['File: ' + lReportedFile,
        '  W501 deterministic warning (12, 3)', '  C101 deterministic finding (18, 5)',
        'File: ' + GetEnvironmentVariable('DAK_TEST_FIXINSIGHT_THIRD_PARTY'),
        '  W503 vendor warning (7, 1)'], TEncoding.UTF8)
    else
      TFile.WriteAllLines(lOutputPath, ['File: ' + lReportedFile,
        '  W501 deterministic warning (12, 3)', '  C101 deterministic finding (18, 5)'],
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
  // A standalone unit run passes no /NAME=; PALCMD then names the report folder after the source.
  if lName = '' then
    for i := 1 to ParamCount do
      if (lName = '') and not StartsText('/', ParamStr(i)) then
        lName := TPath.GetFileNameWithoutExtension(ParamStr(i));
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
