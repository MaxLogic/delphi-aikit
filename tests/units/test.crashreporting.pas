unit Test.CrashReporting;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCrashReportingTests = class
  public
    [Test]
    procedure UnattendedHelpRemovesStaleReport;
    [Test]
    procedure UnattendedUnhandledExceptionWritesFreshReport;
    [Test]
    procedure InteractiveOptOutPreservesReport;
  end;

implementation

uses
  System.IOUtils, System.SysUtils,
  Winapi.Messages, Winapi.Windows,
  Test.Support;

var
  GObservedPid: Cardinal;
  GWindowSeen: Boolean;

procedure ObserveWindow(aHook: THandle; aEvent: DWORD; aWindow: HWND;
  aObject, aChild: Longint; aEventThread, aEventTime: DWORD); stdcall;
begin
  // The hook filters by PID. The HWND may already be destroyed when this async callback runs.
  if (GObservedPid <> 0) and (aWindow <> 0) and (aObject = OBJID_WINDOW) then
    GWindowSeen := True;
end;

procedure PumpObserverMessages;
var
  lMessage: TMsg;
  i: Integer;
begin
  for i := 1 to 1024 do
  begin
    if not PeekMessage(lMessage, 0, 0, 0, PM_REMOVE) then
      Break;
    TranslateMessage(lMessage);
    DispatchMessage(lMessage);
  end;
end;

procedure WaitForObservedChild(aProcess: THandle);
const
  cChildDeadlineMs = 30000;
var
  lDeadline: UInt64;
  lNow: UInt64;
  lRemaining: Cardinal;
  lWait: Cardinal;
begin
  lDeadline := GetTickCount64 + cChildDeadlineMs;
  repeat
    lNow := GetTickCount64;
    if lNow >= lDeadline then
      raise Exception.Create('DAK subprocess exceeded 30 seconds');
    lRemaining := Cardinal(lDeadline - lNow);
    lWait := MsgWaitForMultipleObjects(1, aProcess, False, lRemaining, QS_ALLINPUT);
    if lWait = WAIT_OBJECT_0 then
    begin
      PumpObserverMessages;
      Exit;
    end;
    if lWait = WAIT_OBJECT_0 + 1 then
      PumpObserverMessages
    else if lWait = WAIT_TIMEOUT then
      raise Exception.Create('DAK subprocess exceeded 30 seconds')
    else
      RaiseLastOSError;
  until False;
end;

function PrepareCandidate(const aPrefix: string; out aReport, aOutput: string): string;
var
  lCandidate: string;
  lError: string;
  lFolder: string;
begin
  Assert.IsTrue(TryResolveCandidateExe(lCandidate, lError), lError);
  lFolder := UniqueNoRepoTempPath(aPrefix);
  TDirectory.CreateDirectory(lFolder);
  Result := TPath.Combine(lFolder, 'DelphiAIKit.exe');
  TFile.Copy(lCandidate, Result);
  aReport := TPath.Combine(lFolder, 'bugreport.txt');
  aOutput := TPath.Combine(lFolder, 'stdout.txt');
end;

procedure RunCandidate(const aExe, aOutput: string; out aExitCode, aPid: Cardinal;
  out aWindowSeen: Boolean);
var
  lAssignError: Cardinal;
  lCommandLine: string;
  lDialogHook: THandle;
  lJob: THandle;
  lJobInfo: TJobObjectExtendedLimitInformation;
  lMessage: TMsg;
  lOutput: THandle;
  lProcess: TProcessInformation;
  lProcessAssigned: Boolean;
  lSecurity: TSecurityAttributes;
  lShowHook: THandle;
  lStartup: TStartupInfo;
begin
  aPid := 0;
  aWindowSeen := False;
  lDialogHook := 0;
  lJob := 0;
  lOutput := INVALID_HANDLE_VALUE;
  lProcess := Default(TProcessInformation);
  lProcessAssigned := False;
  lShowHook := 0;
  try
    lSecurity := Default(TSecurityAttributes);
    lSecurity.nLength := SizeOf(lSecurity);
    lSecurity.bInheritHandle := True;
    lOutput := CreateFile(PChar(aOutput), GENERIC_WRITE, FILE_SHARE_READ,
      @lSecurity, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if lOutput = INVALID_HANDLE_VALUE then
      RaiseLastOSError;
    lJob := CreateJobObject(nil, nil);
    if lJob = 0 then
      RaiseLastOSError;
    lJobInfo := Default(TJobObjectExtendedLimitInformation);
    lJobInfo.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if not SetInformationJobObject(lJob, JobObjectExtendedLimitInformation,
      @lJobInfo, SizeOf(lJobInfo)) then
      RaiseLastOSError;
    lStartup := Default(TStartupInfo);
    lStartup.cb := SizeOf(lStartup);
    lStartup.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    lStartup.wShowWindow := SW_HIDE;
    lStartup.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    lStartup.hStdOutput := lOutput;
    lStartup.hStdError := lOutput;
    lCommandLine := '"' + aExe + '" --help';
    UniqueString(lCommandLine);
    if not CreateProcess(PChar(aExe), PChar(lCommandLine), nil, nil, True,
      CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, PChar(ExtractFilePath(aExe)),
      lStartup, lProcess) then
      RaiseLastOSError;
    if not AssignProcessToJobObject(lJob, lProcess.hProcess) then
    begin
      lAssignError := GetLastError;
      raise Exception.Create('Cannot contain DAK child: ' + SysErrorMessage(lAssignError));
    end;
    lProcessAssigned := True;
    aPid := lProcess.dwProcessId;
    GObservedPid := aPid;
    GWindowSeen := False;
    PeekMessage(lMessage, 0, 0, 0, PM_NOREMOVE);
    lShowHook := SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW, 0,
      ObserveWindow, aPid, 0, WINEVENT_OUTOFCONTEXT);
    if lShowHook = 0 then
      raise Exception.Create('Could not observe child window show events');
    lDialogHook := SetWinEventHook(EVENT_SYSTEM_DIALOGSTART, EVENT_SYSTEM_DIALOGSTART, 0,
      ObserveWindow, aPid, 0, WINEVENT_OUTOFCONTEXT);
    if lDialogHook = 0 then
      raise Exception.Create('Could not observe child dialog events');
    if ResumeThread(lProcess.hThread) = Cardinal(-1) then
      RaiseLastOSError;
    WaitForObservedChild(lProcess.hProcess);
    if not GetExitCodeProcess(lProcess.hProcess, aExitCode) then
      RaiseLastOSError;
    aWindowSeen := GWindowSeen;
  finally
    if lDialogHook <> 0 then
      UnhookWinEvent(lDialogHook);
    if lShowHook <> 0 then
      UnhookWinEvent(lShowHook);
    GObservedPid := 0;
    if (lProcess.hProcess <> 0) and not lProcessAssigned and
      (WaitForSingleObject(lProcess.hProcess, 0) = WAIT_TIMEOUT) then
    begin
      // A failed job assignment leaves the new child suspended outside the job.
      if not TerminateProcess(lProcess.hProcess, ERROR_PROCESS_ABORTED) then
        RaiseLastOSError;
      if WaitForSingleObject(lProcess.hProcess, 5000) <> WAIT_OBJECT_0 then
        raise Exception.Create('Unassigned child did not terminate');
    end;
    if lJob <> 0 then
      CloseHandle(lJob);
    if lProcess.hThread <> 0 then
      CloseHandle(lProcess.hThread);
    if lProcess.hProcess <> 0 then
      CloseHandle(lProcess.hProcess);
    if lOutput <> INVALID_HANDLE_VALUE then
      CloseHandle(lOutput);
  end;
end;

procedure TCrashReportingTests.UnattendedHelpRemovesStaleReport;
var
  lEnv: IInterface;
  lExe: string;
  lOutput: string;
  lPid: Cardinal;
  lReport: string;
  lResult: Cardinal;
  lWindowSeen: Boolean;
begin
  lExe := PrepareCandidate('dak396-help', lReport, lOutput);
  TFile.WriteAllText(lReport, 'DAK-396 stale marker');
  lEnv := SetScopedEnvironmentVariables(['MAXLOGIC_MADEXCEPT_AI', '1',
    'DAK_TEST_UNHANDLED_EXCEPTION', '']);
  RunCandidate(lExe, lOutput, lResult, lPid, lWindowSeen);
  Assert.AreEqual<Cardinal>(0, lResult);
  Assert.IsFalse(FileExists(lReport), 'AI startup must remove the old report');
  Assert.IsFalse(lWindowSeen, 'Child showed a window');
end;

procedure TCrashReportingTests.UnattendedUnhandledExceptionWritesFreshReport;
var
  lEnv: IInterface;
  lExe: string;
  lOutput: string;
  lPid: Cardinal;
  lReport: string;
  lResult: Cardinal;
  lText: string;
  lToken: string;
  lWindowSeen: Boolean;
begin
  lExe := PrepareCandidate('dak396-crash', lReport, lOutput);
  lToken := 'DAK396-' + IntToHex(GetTickCount64, 16);
  TFile.WriteAllText(lReport, 'DAK-396 stale marker');
  lEnv := SetScopedEnvironmentVariables(['MAXLOGIC_MADEXCEPT_AI', '1',
    'DAK_TEST_UNHANDLED_EXCEPTION', lToken]);
  RunCandidate(lExe, lOutput, lResult, lPid, lWindowSeen);
  Assert.AreEqual<Cardinal>(207, lResult, 'Uncaught madExcept exit');
  Assert.IsTrue(FileExists(lReport), 'No fresh bugreport.txt');
  lText := TFile.ReadAllText(lReport);
  Assert.IsTrue(lText.Contains(lToken), 'Exception token missing');
  Assert.IsTrue(lText.Contains('TDelphiAIKitApp.Execute'), 'DAK callstack missing');
  Assert.IsFalse(lText.Contains('DAK-396 stale marker'), 'Old report survived');
  Assert.IsFalse(lWindowSeen, 'Child showed a modal or please-wait window');
end;

procedure TCrashReportingTests.InteractiveOptOutPreservesReport;
var
  lEnv: IInterface;
  lExe: string;
  lOutput: string;
  lPid: Cardinal;
  lReport: string;
  lResult: Cardinal;
  lWindowSeen: Boolean;
begin
  lExe := PrepareCandidate('dak396-optout', lReport, lOutput);
  TFile.WriteAllText(lReport, 'DAK-396 opt-out marker');
  lEnv := SetScopedEnvironmentVariables(['MAXLOGIC_MADEXCEPT_AI', '',
    'DAK_TEST_UNHANDLED_EXCEPTION', '']);
  RunCandidate(lExe, lOutput, lResult, lPid, lWindowSeen);
  Assert.AreEqual<Cardinal>(0, lResult);
  Assert.AreEqual('DAK-396 opt-out marker', TFile.ReadAllText(lReport));
  Assert.IsFalse(lWindowSeen, 'Healthy help showed a child window');
end;

initialization
  TDUnitX.RegisterTestFixture(TCrashReportingTests);

end.
