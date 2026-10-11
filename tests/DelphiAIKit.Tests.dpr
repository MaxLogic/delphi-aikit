program DelphiAIKit_Tests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.Classes, System.IOUtils, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  FireDAC.Phys.SQLiteWrapper.Stat,
  DUnitX.FilterBuilder,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.XML.NUnit,
  DUnitX.TestFramework,
  Dak.Build.Enrichment in '..\src\Dak.Build.Enrichment.pas',
  Dak.Build.NativeContext in '..\src\Dak.Build.NativeContext.pas',
  Dak.NativeInputLocks in '..\src\Dak.NativeInputLocks.pas',
  Dak.RootMemberAbsence in '..\src\Dak.RootMemberAbsence.pas',
  Test.RootMemberAbsenceContext in 'units\test.rootmemberabsencecontext.pas',
  Dak.ExternalToolProcess in '..\src\Dak.ExternalToolProcess.pas',
  Dak.Lsp.Protocol in '..\src\Dak.Lsp.Protocol.pas',
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
  Test.NativeAnalysisReports.Controls in 'units\test.nativeanalysisreports.controls.pas',
  Test.NativeAnalysisReports.OwnershipControls in 'units\test.nativeanalysisreports.ownershipcontrols.pas',
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
  Test.CrashReporting in 'units\test.crashreporting.pas',
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
  Test.Lsp.Protocol in 'units\test.lsp.protocol.pas',
  Test.MsBuild in 'units\\test.msbuild.pas',
  Test.PalFindingNormalize in 'units\\test.palfindingnormalize.pas',
  Test.ReportPostProcess in 'units\\test.reportpostprocess.pas',
  Test.PascalAnalyzer in 'units\\test.pascalanalyzer.pas',
  Test.Refactor in 'units\\test.refactor.pas',
  Test.RootMemberAbsence in 'units\test.rootmemberabsence.pas',
  Dak.Consistency.Command in '..\src\Dak.Consistency.Command.pas',
  Dak.Signature.Command in '..\src\Dak.Signature.Command.pas',
  Dak.Consistency.Dfm in '..\src\Dak.Consistency.Dfm.pas',
  Dak.Refactor.ApplyCommand in '..\src\Dak.Refactor.ApplyCommand.pas',
  Dak.Refactor.Artifact in '..\src\Dak.Refactor.Artifact.pas',
  Dak.Refactor.Preflight in '..\src\Dak.Refactor.Preflight.pas',
  Test.Refactor.Preflight in 'units\test.refactor.preflight.pas',
  Dak.Refactor.Transaction in '..\src\Dak.Refactor.Transaction.pas',
  Test.Refactor.Transaction in 'units\test.refactor.transaction.pas',
  Test.Consistency in 'units\test.consistency.pas',
  Test.SignatureCommand in 'units\test.signaturecommand.pas',
  Test.Refactor.ApplyCli in 'units\test.refactor.applycli.pas',
  Test.Refactor.ProprietaryRename in 'units\\test.refactor.proprietaryrename.pas',
  Test.RemoveWith in 'units\\test.removewith.pas',
  Test.RemoveWith.LongPath in 'units\test.removewith.longpath.pas',
  Test.DakWorkingPaths in 'units\test.dakworkingpaths.pas',
  Test.SymbolMap in 'units\\test.symbolmap.pas',
  Test.Utils in 'units\\test.utils.pas',
  Test.SourceContext in 'units\\test.sourcecontext.pas',
  ToolsAPIRepl in '..\\lib\\DFMCheck\\Source\\Console\\ToolsAPIRepl.pas';

const
  cMaxTdbProofCategory = 'MaxTdbProof';

procedure RunPalHelpFixture;
var
  lMode: string;
begin
  lMode := GetEnvironmentVariable('DAK_TEST_PAL_HELP');
  if lMode = '1' then
  begin
    Writeln('/CD12W32 /CD12W64 /CD13W32 /CD13W64 /NAME=projectname');
    Halt(0);
  end;
  // A complete help text as the doctor reads it: version line, syntax marker and one flag per line.
  if lMode = 'doctor' then
  begin
    Writeln('Pascal Analyzer (64-bits) version 9.21.4.0');
    Writeln('Syntax: PALCMD sourcepath [options]');
    Writeln('/CD12W32');
    Writeln('/CD12W64');
    Writeln('/CD13W32');
    Writeln('/CD13W64');
    Writeln('/NAME=projectname');
    Halt(0);
  end;
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
  lSourcePath: string;
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
    if GetEnvironmentVariable('DAK_TEST_PAL_IDENTITY') = '1' then
    begin
      lSourcePath := '';
      for i := 1 to ParamCount do
        if SameText(TPath.GetExtension(ParamStr(i)), '.dpr') then
          lSourcePath := ParamStr(i);
      if lSourcePath = '' then
        raise Exception.Create('PAL identity fixture requires a DPR argument.');
      TFile.WriteAllText(TPath.Combine(lReportRoot, 'Modules.xml'),
        '<report><section name="Modules"><module><name>Sample_Program</name><path>' +
        lSourcePath + '</path></module></section></report>', TEncoding.UTF8);
      TFile.WriteAllText(TPath.Combine(lReportRoot, 'Warnings.xml'),
        '<report><section name="Warnings"><item><id>base</id><locmod>' + lName +
        ' (7)</locmod></item><item><id>qualified</id><locmod>' + lName +
        '\TWorker\Run (8)</locmod></item></section></report>', TEncoding.UTF8);
    end;
  end;
  Halt(lExitCode);
end;

procedure RunDescendantFixture;
var
  lProcess, lThread: THandle;
  lPath, lWritePath, lError: string;
begin
  lPath := GetEnvironmentVariable('DAK_TEST_DESCENDANT_PID');
  if lPath = '' then
    Exit;
  if not StartSlowPingProcess(lProcess, lThread, lError) then
    raise Exception.Create(lError);
  try
    // File existence is the parent's readiness signal. Publish only after the
    // writer closes, so the parent cannot read a partial or exclusively open file.
    lWritePath := lPath + '.writing';
    TFile.WriteAllText(lWritePath, UIntToStr(GetProcessId(lProcess)), TEncoding.ASCII);
    TFile.Move(lWritePath, lPath);
    Sleep(10000);
  finally
    CloseHandle(lThread);
    CloseHandle(lProcess);
  end;
  Halt(0);
end;

// Publishes "<pid> <creation FILETIME>" so the parent can open the process by
// handle and prove it is the same process, not a reused PID.
procedure PublishProcessIdentity(const aPath: string; aProcess: THandle);
var
  lCreated, lExited, lKernel, lUser: TFileTime;
  lWritePath: string;
begin
  if not GetProcessTimes(aProcess, lCreated, lExited, lKernel, lUser) then
    RaiseLastOSError;
  // File existence is the parent's readiness signal. Publish only after the
  // writer closes, so the parent cannot read a partial or exclusively open file.
  lWritePath := aPath + '.writing';
  TFile.WriteAllText(lWritePath, UIntToStr(GetProcessId(aProcess)) + ' ' +
    UIntToStr((UInt64(lCreated.dwHighDateTime) shl 32) or lCreated.dwLowDateTime), TEncoding.ASCII);
  TFile.Move(lWritePath, aPath);
end;

procedure RunReadyDescendantFixture;
var
  lProcess, lThread: THandle;
  lPath, lError: string;
begin
  lPath := GetEnvironmentVariable('DAK_TEST_DESCENDANT_READY');
  if lPath = '' then
    Exit;
  if not StartSlowPingProcess(lProcess, lThread, lError) then
    raise Exception.Create(lError);
  try
    PublishProcessIdentity(lPath, lProcess);
    // "exit" leaves the descendant running for the parent's job to stop after
    // a normal exit. Otherwise the child outlives any deadline the test uses.
    if GetEnvironmentVariable('DAK_TEST_DESCENDANT_MODE') <> 'exit' then
      Sleep(60000);
  finally
    CloseHandle(lThread);
    CloseHandle(lProcess);
  end;
  Halt(0);
end;

procedure RunIdleReadyFixture;
var
  lPath: string;
begin
  lPath := GetEnvironmentVariable('DAK_TEST_IDLE_READY');
  if lPath = '' then
    Exit;
  PublishProcessIdentity(lPath, GetCurrentProcess);
  Sleep(60000);
  Halt(0);
end;

procedure RunExternalToolHostFixture;
var
  lError: string;
  lExitCode: Cardinal;
  lOptions: TExternalToolProcessRunOptions;
  lPath: string;
  lTimedOut: Boolean;
begin
  lPath := GetEnvironmentVariable('DAK_TEST_TOOL_HOST_READY');
  if lPath = '' then
    Exit;
  // Stands in for DAK running PALCMD or FixInsightCL through the production
  // helper with default flags. The tool is an idle copy of this executable.
  SetEnvironmentVariable('DAK_TEST_TOOL_HOST_READY', nil);
  SetEnvironmentVariable('DAK_TEST_IDLE_READY', PChar(lPath));
  lOptions := Default(TExternalToolProcessRunOptions);
  lOptions.fExePath := ParamStr(0);
  lOptions.fTimeoutSec := 60;
  if not TryRunExternalToolProcess(lOptions, lExitCode, lTimedOut, lError) then
  begin
    Writeln(ErrOutput, lError);
    Halt(3);
  end;
  Halt(0);
end;

procedure LaunchHeadlessGrandchild;
var
  lCmdLine: string;
  lExitCode: Cardinal;
  lPi: TProcessInformation;
  lSi: TStartupInfo;
begin
  // Default creation flags, no SW_HIDE: the grandchild inherits whatever
  // console its headless parent has, which is what third-party tools do.
  SetEnvironmentVariable('DAK_TEST_HEADLESS_DESCENDANT', nil);
  SetEnvironmentVariable('DAK_TEST_HEADLESS_ROLE', 'grandchild');
  SetEnvironmentVariable('DAK_TEST_HEADLESS_PARENT_PID', PChar(UIntToStr(GetCurrentProcessId)));
  lSi := Default(TStartupInfo);
  lSi.cb := SizeOf(lSi);
  lSi.dwFlags := STARTF_USESTDHANDLES;
  lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lSi.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  lSi.hStdError := GetStdHandle(STD_ERROR_HANDLE);
  lPi := Default(TProcessInformation);
  lCmdLine := '"' + ParamStr(0) + '"';
  UniqueString(lCmdLine);
  if not CreateProcess(PChar(ParamStr(0)), PChar(lCmdLine), nil, nil, True, 0, nil, nil, lSi, lPi) then
  begin
    Writeln('child descendant-start-error=', GetLastError);
    Exit;
  end;
  try
    if WaitForSingleObject(lPi.hProcess, 10000) <> WAIT_OBJECT_0 then
    begin
      TerminateProcess(lPi.hProcess, ERROR_TIMEOUT);
      Writeln('child descendant-timeout=1');
    end else if GetExitCodeProcess(lPi.hProcess, lExitCode) then
      Writeln('child descendant-exit=', lExitCode)
    else
      Writeln('child descendant-exit-error=', GetLastError);
  finally
    CloseHandle(lPi.hThread);
    CloseHandle(lPi.hProcess);
  end;
end;

procedure RunHeadlessChildFixture;
var
  lCount: DWORD;
  lOwn, lParent, lRunner: Boolean;
  lParentPid, lRunnerPid: Cardinal;
  lPids: array[0..63] of DWORD;
  lRole: string;
  lSi: TStartupInfo;
  i: Integer;
begin
  if GetEnvironmentVariable('DAK_TEST_HEADLESS_CHILD') <> '1' then
    Exit;
  lRole := GetEnvironmentVariable('DAK_TEST_HEADLESS_ROLE');
  if lRole = '' then
    lRole := 'child';
  lRunnerPid := StrToUIntDef(GetEnvironmentVariable('DAK_TEST_HEADLESS_RUNNER_PID'), 0);
  lParentPid := StrToUIntDef(GetEnvironmentVariable('DAK_TEST_HEADLESS_PARENT_PID'), 0);
  // Console membership is the direct signal: a child that shares the test
  // runner's console lists the runner here even when that console is windowless.
  lCount := GetConsoleProcessList(@lPids[0], Length(lPids));
  lOwn := False;
  lParent := False;
  lRunner := False;
  if lCount <= DWORD(Length(lPids)) then
  begin
    for i := 0 to Integer(lCount) - 1 do
    begin
      lOwn := lOwn or (lPids[i] = GetCurrentProcessId);
      lParent := lParent or ((lParentPid <> 0) and (lPids[i] = lParentPid));
      lRunner := lRunner or ((lRunnerPid <> 0) and (lPids[i] = lRunnerPid));
    end;
  end;
  GetStartupInfo(lSi);
  Writeln(lRole, ' console=', NativeUInt(GetConsoleWindow));
  Writeln(lRole, ' console-processes=', lCount);
  Writeln(lRole, ' own-console=', Ord(lOwn));
  Writeln(lRole, ' runner-console=', Ord(lRunner));
  if lParentPid <> 0 then
    Writeln(lRole, ' parent-console=', Ord(lParent));
  Writeln(lRole, ' startup-hidden=',
    Ord(((lSi.dwFlags and STARTF_USESHOWWINDOW) <> 0) and (lSi.wShowWindow = SW_HIDE)));
  Flush(Output);
  if GetEnvironmentVariable('DAK_TEST_HEADLESS_DESCENDANT') = '1' then
    LaunchHeadlessGrandchild;
  Writeln(ErrOutput, lRole, ' stderr-marker');
  Halt(7);
end;

procedure RunStdoutFrameFixture;
var
  lBytes: TBytes;
  lDelayMs: Integer;
  lPath: string;
  lStdOut: THandle;
  lWritten: DWORD;
  i: Integer;
begin
  lPath := GetEnvironmentVariable('DAK_TEST_STDOUT_FRAME');
  if lPath = '' then
    Exit;
  // Protocol-agnostic byte emitter for transport framing tests: it never reads
  // stdin and never answers a request; it only replays the given bytes.
  lBytes := TFile.ReadAllBytes(lPath);
  lDelayMs := StrToIntDef(GetEnvironmentVariable('DAK_TEST_STDOUT_DELAY_MS'), 0);
  lStdOut := GetStdHandle(STD_OUTPUT_HANDLE);
  if lDelayMs > 0 then
  begin
    for i := 0 to High(lBytes) do
    begin
      if not WriteFile(lStdOut, lBytes[i], 1, lWritten, nil) then
        Halt(3);
      Sleep(lDelayMs);
    end;
  end else if Length(lBytes) > 0 then
  begin
    if not WriteFile(lStdOut, lBytes[0], Length(lBytes), lWritten, nil) then
      Halt(3);
  end;
  if GetEnvironmentVariable('DAK_TEST_STDOUT_EXIT') <> '1' then
    Sleep(10000);
  Halt(0);
end;

procedure RunInheritedStdoutHolderFixture;
var
  lCmdLine: string;
  lPi: TProcessInformation;
  lSi: TStartupInfo;
begin
  if GetEnvironmentVariable('DAK_TEST_STDOUT_HOLDER') <> '1' then
    Exit;
  // Leave an idle descendant holding the inherited stdout write end, then exit:
  // the reader must not treat the creator's exit as the end of the pipe.
  SetEnvironmentVariable('DAK_TEST_STDOUT_HOLDER', nil);
  SetEnvironmentVariable('DAK_TEST_IDLE_CHILD', '1');
  lSi := Default(TStartupInfo);
  lSi.cb := SizeOf(lSi);
  lSi.dwFlags := STARTF_USESTDHANDLES;
  lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lSi.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  lSi.hStdError := GetStdHandle(STD_ERROR_HANDLE);
  lPi := Default(TProcessInformation);
  lCmdLine := '"' + ParamStr(0) + '"';
  UniqueString(lCmdLine);
  if not CreateProcess(PChar(ParamStr(0)), PChar(lCmdLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, lSi, lPi) then
    Halt(3);
  CloseHandle(lPi.hThread);
  CloseHandle(lPi.hProcess);
  Halt(0);
end;

procedure RunUndrainedStdinHolderFixture;
var
  lCmdLine: string;
  lPath: string;
  lPi: TProcessInformation;
  lSi: TStartupInfo;
begin
  lPath := GetEnvironmentVariable('DAK_TEST_STDIN_HOLDER');
  if lPath = '' then
    Exit;
  // Leave an idle descendant holding the inherited stdin read end, then exit.
  // Nobody ever reads stdin, as with DelphiLSP agents that inherit it; the
  // descendant publishes its identity for the parent's survivor check.
  SetEnvironmentVariable('DAK_TEST_STDIN_HOLDER', nil);
  SetEnvironmentVariable('DAK_TEST_IDLE_READY', PChar(lPath));
  lSi := Default(TStartupInfo);
  lSi.cb := SizeOf(lSi);
  lSi.dwFlags := STARTF_USESTDHANDLES;
  lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lSi.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  lSi.hStdError := GetStdHandle(STD_ERROR_HANDLE);
  lPi := Default(TProcessInformation);
  lCmdLine := '"' + ParamStr(0) + '"';
  UniqueString(lCmdLine);
  if not CreateProcess(PChar(ParamStr(0)), PChar(lCmdLine), nil, nil, True, CREATE_NO_WINDOW, nil, nil, lSi, lPi) then
    Halt(3);
  CloseHandle(lPi.hThread);
  CloseHandle(lPi.hProcess);
  Halt(0);
end;

procedure RunStdinDrainFixture;
const
  cChunkBytes = 65536;
var
  lBodyLength, lHeaderEnd, lTotal: Integer;
  lBuffer, lReply: TBytes;
  lHeader, lResponse: string;
  lRead, lWritten: DWORD;
begin
  if GetEnvironmentVariable('DAK_TEST_STDIN_DRAIN') <> '1' then
    Exit;
  // Reads one complete request frame from stdin and answers with the number of
  // body bytes received, so the parent can prove a multi-chunk write is whole.
  SetLength(lBuffer, cChunkBytes);
  lTotal := 0;
  lHeaderEnd := 0;
  lBodyLength := -1;
  while (lBodyLength < 0) or (lTotal < lHeaderEnd + lBodyLength) do
  begin
    if Length(lBuffer) - lTotal < cChunkBytes then
      SetLength(lBuffer, Length(lBuffer) * 2);
    if not ReadFile(GetStdHandle(STD_INPUT_HANDLE), lBuffer[lTotal], cChunkBytes, lRead, nil) or (lRead = 0) then
      Halt(3);
    Inc(lTotal, Integer(lRead));
    if lBodyLength < 0 then
    begin
      lHeader := TEncoding.ASCII.GetString(lBuffer, 0, lTotal);
      lHeaderEnd := Pos(#13#10#13#10, lHeader);
      if lHeaderEnd > 0 then
      begin
        lBodyLength := StrToInt(Trim(Copy(lHeader, Length('Content-Length:') + 1,
          Pos(#13#10, lHeader) - Length('Content-Length:') - 1)));
        lHeaderEnd := lHeaderEnd + 3;
      end;
    end;
  end;
  lResponse := '{"jsonrpc":"2.0","id":1,"result":' + IntToStr(lTotal - lHeaderEnd) + '}';
  lReply := TEncoding.ASCII.GetBytes('Content-Length: ' + IntToStr(Length(lResponse)) + #13#10#13#10 + lResponse);
  if not WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), lReply[0], Length(lReply), lWritten, nil) then
    Halt(3);
  Sleep(10000);
  Halt(0);
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
  // DAK-394: first, so no test, fixture child or tool they start can block on an OS message box.
  ApplyUnattendedErrorMode;
  // Reports the error mode the runner runs with, after its own startup has set it.
  if GetEnvironmentVariable('DAK_TEST_REPORT_ERROR_MODE') = '1' then
    Halt(Integer(GetErrorMode));
  if GetEnvironmentVariable('DAK_TEST_LARGE_OUTPUT_CHILD') = '1' then
  begin
    for var i := 0 to 19999 do
    begin
      Writeln('stdout ', i, ' ', StringOfChar('x', 96));
      Flush(Output);
      Writeln(ErrOutput, 'stderr ', i, ' ', StringOfChar('y', 96));
      Flush(ErrOutput);
    end;
    Halt(7);
  end;
  RunStdoutFrameFixture;
  RunInheritedStdoutHolderFixture;
  RunUndrainedStdinHolderFixture;
  RunStdinDrainFixture;
  if GetEnvironmentVariable('DAK_TEST_IDLE_CHILD') = '1' then
  begin
    Sleep(10000);
    Halt(0);
  end;
  RunHeadlessChildFixture;
  RunIdleReadyFixture;
  RunExternalToolHostFixture;
  RunReadyDescendantFixture;
  RunDescendantFixture;
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
    // --xmlfile:<path> writes an NUnit report with one entry per executed test, which the migration
    // coverage check reads to prove every mapped native case ran and passed.
    if TDUnitX.Options.XMLOutputFile <> '' then
      Runner.AddLogger(TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile));

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
