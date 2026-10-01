unit Dak.ExternalToolProcess;

interface

uses
  System.SysUtils,
  Winapi.Windows;

const
  cExternalToolDefaultTimeoutSec = 1800;
  cExternalToolTimeoutExitCode = WAIT_TIMEOUT;
  // Fail instead of asking: no critical-error, GP-fault or open-file message box.
  cUnattendedErrorMode = SEM_FAILCRITICALERRORS or SEM_NOGPFAULTERRORBOX or SEM_NOOPENFILEERRORBOX;

type
  TExternalToolProcessRunOptions = record
    fApplicationName: string;
    fExePath: string;
    fArguments: string;
    fCommandLine: string;
    fWorkDir: string;
    fEnvironmentBlock: string;
    fToolName: string;
    fStartFailureFormat: string;
    fUseCommandLineApplication: Boolean;
    fStdInHandle: THandle;
    fStdOutHandle: THandle;
    fStdErrHandle: THandle;
    fCreationFlags: Cardinal;
    fTimeoutSec: Integer;
    fUseDefaultTimeout: Boolean;
    fTimeoutExitCode: Cardinal;
  end;

procedure ApplyUnattendedErrorMode;
function TryValidateWindowsExecutable(const aPath: string; out aError: string): Boolean;
function ResolveExternalToolTimeoutSec(aTimeoutSec: Integer): Integer;
function ResolveExternalToolTimeoutMs(aTimeoutSec: Integer): Cardinal;
function TryTerminateTimedOutExternalToolProcess(const aToolName: string; aProcess: THandle; aTimeoutSec: Integer;
  aTimeoutExitCode: Cardinal; out aExitCode: Cardinal; out aError: string): Boolean; overload;
function TryTerminateTimedOutExternalToolProcess(const aToolName: string; aProcess: THandle; aTimeoutSec: Integer;
  out aExitCode: Cardinal; out aError: string): Boolean; overload;
function TryRunExternalToolProcess(const aOptions: TExternalToolProcessRunOptions;
  out aExitCode: Cardinal; out aTimedOut: Boolean; out aError: string): Boolean;
function TryWaitForExternalToolProcess(const aToolName: string; aProcess: THandle; aTimeoutSec: Integer;
  out aExitCode: Cardinal; out aError: string): Boolean;

implementation

// DAK-394: a process inherits its parent's error mode unless it sets its own. With mode 0, CreateProcess on a
// file that is not a PE image opens a modal "Unsupported 16-bit application" box in the calling process and
// does not return until someone closes it; a crash may wait on a GP-fault box too. Each executable calls this
// first at startup, so it and every child it starts fail with an error code instead, whatever launched it.
procedure ApplyUnattendedErrorMode;
begin
  SetErrorMode(GetErrorMode or cUnattendedErrorMode);
end;

// DAK-394: rejects a file that has no "MZ" DOS header or no "PE\0\0" signature where e_lfanew points, before
// CreateProcess sends it down the 16-bit application path. Batch files are run by cmd.exe and are not images.
// A file we cannot open or read is left to CreateProcess, which reports its own reason.
function TryValidateWindowsExecutable(const aPath: string; out aError: string): Boolean;
var
  lDosHeader: TImageDosHeader;
  lHandle: THandle;
  lRead: Integer;
  lSignature: Cardinal;
begin
  aError := '';
  if SameText(ExtractFileExt(aPath), '.bat') or SameText(ExtractFileExt(aPath), '.cmd') then
    Exit(True);
  lHandle := FileOpen(aPath, fmOpenRead or fmShareDenyNone);
  if lHandle = INVALID_HANDLE_VALUE then
    Exit(True);
  try
    lRead := FileRead(lHandle, lDosHeader, SizeOf(lDosHeader));
    if lRead < 0 then
      Exit(True);
    Result := (lRead = SizeOf(lDosHeader)) and (lDosHeader.e_magic = IMAGE_DOS_SIGNATURE) and
      (lDosHeader._lfanew >= 0);
    if Result then
    begin
      if FileSeek(lHandle, Int64(lDosHeader._lfanew), 0) < 0 then
        Exit(True);
      lRead := FileRead(lHandle, lSignature, SizeOf(lSignature));
      if lRead < 0 then
        Exit(True);
      Result := (lRead = SizeOf(lSignature)) and (lSignature = IMAGE_NT_SIGNATURE);
    end;
  finally
    FileClose(lHandle);
  end;
  if not Result then
    aError := aPath + ' is not a valid Windows executable';
end;

function ResolveExternalToolTimeoutSec(aTimeoutSec: Integer): Integer;
begin
  if aTimeoutSec > 0 then
    Exit(aTimeoutSec);
  Result := cExternalToolDefaultTimeoutSec;
end;

function ResolveExternalToolTimeoutMs(aTimeoutSec: Integer): Cardinal;
var
  lTimeoutSec: Integer;
begin
  lTimeoutSec := ResolveExternalToolTimeoutSec(aTimeoutSec);
  if lTimeoutSec >= Integer(INFINITE div 1000) then
    Exit(INFINITE - 1);
  Result := Cardinal(lTimeoutSec) * 1000;
end;

function TryTerminateTimedOutExternalToolProcess(const aToolName: string; aProcess: THandle; aTimeoutSec: Integer;
  aTimeoutExitCode: Cardinal; out aExitCode: Cardinal; out aError: string): Boolean; overload;
var
  lLastError: Cardinal;
  lTimeoutSec: Integer;
  lWait: Cardinal;
begin
  Result := False;
  aExitCode := aTimeoutExitCode;
  if aExitCode = 0 then
    aExitCode := cExternalToolTimeoutExitCode;
  aError := '';
  lTimeoutSec := ResolveExternalToolTimeoutSec(aTimeoutSec);

  if not TerminateProcess(aProcess, aExitCode) then
  begin
    lLastError := GetLastError;
    aError := Format('%s timed out after %d seconds; terminate failed: %s',
      [aToolName, lTimeoutSec, SysErrorMessage(lLastError)]);
    Exit(False);
  end;

  lWait := WaitForSingleObject(aProcess, 5000);
  if lWait = WAIT_OBJECT_0 then
  begin
    aError := Format('%s timed out after %d seconds.', [aToolName, lTimeoutSec]);
    Exit(True);
  end;

  if lWait = WAIT_TIMEOUT then
    aError := Format('%s timed out after %d seconds; terminate did not complete within 5 seconds.',
      [aToolName, lTimeoutSec])
  else
  begin
    lLastError := GetLastError;
    aError := Format('%s timed out after %d seconds; terminate wait failed: %s',
      [aToolName, lTimeoutSec, SysErrorMessage(lLastError)]);
  end;
end;

function TryTerminateTimedOutExternalToolProcess(const aToolName: string; aProcess: THandle; aTimeoutSec: Integer;
  out aExitCode: Cardinal; out aError: string): Boolean; overload;
begin
  Result := TryTerminateTimedOutExternalToolProcess(aToolName, aProcess, aTimeoutSec,
    cExternalToolTimeoutExitCode, aExitCode, aError);
end;

function ExternalToolQuoteArg(const aValue: string): string;
begin
  if (aValue = '') or (Pos(' ', aValue) > 0) or (Pos('"', aValue) > 0) or (Pos(';', aValue) > 0) then
    Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := aValue;
end;

function ExternalToolCommandLine(const aOptions: TExternalToolProcessRunOptions): string;
begin
  Result := aOptions.fCommandLine;
  if Result <> '' then
    Exit;

  Result := ExternalToolQuoteArg(aOptions.fExePath);
  if Trim(aOptions.fArguments) <> '' then
    Result := Result + ' ' + aOptions.fArguments;
end;

function ExternalToolName(const aOptions: TExternalToolProcessRunOptions): string;
begin
  Result := aOptions.fToolName;
  if Result <> '' then
    Exit;

  Result := ExtractFileName(aOptions.fExePath);
  if Result = '' then
    Result := 'external tool';
end;

function ExternalToolTimeoutSec(const aOptions: TExternalToolProcessRunOptions): Integer;
begin
  if aOptions.fTimeoutSec > 0 then
    Exit(aOptions.fTimeoutSec);
  if aOptions.fUseDefaultTimeout then
    Exit(ResolveExternalToolTimeoutSec(0));
  Result := 0;
end;

function ExternalToolTimeoutMs(const aOptions: TExternalToolProcessRunOptions): Cardinal;
var
  lTimeoutSec: Integer;
begin
  lTimeoutSec := ExternalToolTimeoutSec(aOptions);
  if lTimeoutSec <= 0 then
    Exit(INFINITE);

  if lTimeoutSec >= Integer(INFINITE div 1000) then
    Exit(INFINITE - 1);
  Result := Cardinal(lTimeoutSec) * 1000;
end;

function ExternalToolStartError(const aOptions: TExternalToolProcessRunOptions;
  const aSystemError: string): string;
begin
  if aOptions.fStartFailureFormat <> '' then
    Exit(Format(aOptions.fStartFailureFormat, [aSystemError]));
  Result := aSystemError;
end;

type
  // STARTUPINFOEX: the startup record followed by the attribute list that limits inheritance.
  TStartupInfoEx = record
    StartupInfo: TStartupInfo;
    lpAttributeList: PProcThreadAttributeList;
  end;

const
  cProcThreadAttributeHandleList = $00020002; // PROC_THREAD_ATTRIBUTE_HANDLE_LIST

// The RTL overloads take the two reserved pointers by reference; the API requires NULL.
function UpdateProcThreadAttributeNullable(aAttributeList: PProcThreadAttributeList; aFlags: DWORD;
  aAttribute: NativeUInt; aValue: Pointer; aSize: NativeUInt; aPreviousValue, aReturnSize: Pointer): BOOL;
  stdcall; external kernel32 name 'UpdateProcThreadAttribute';

// Lists the inheritable standard handles so the child receives only those. Without the
// list a concurrent launch inherits every inheritable handle, including another child's
// pipe ends, and that reader only sees EOF when the unrelated child exits.
function CollectInheritableHandles(const aStartupInfo: TStartupInfo;
  var aHandles: array of THandle): Integer;

  procedure AddHandle(aHandle: THandle);
  var
    i: Integer;
    lFlags: DWORD;
  begin
    if (aHandle = 0) or (aHandle = INVALID_HANDLE_VALUE) then
      Exit;
    if not GetHandleInformation(aHandle, lFlags) or ((lFlags and HANDLE_FLAG_INHERIT) = 0) then
      Exit;
    for i := 0 to Result - 1 do
      if aHandles[i] = aHandle then
        Exit;
    aHandles[Result] := aHandle;
    Inc(Result);
  end;

begin
  Result := 0;
  AddHandle(aStartupInfo.hStdInput);
  AddHandle(aStartupInfo.hStdOutput);
  AddHandle(aStartupInfo.hStdError);
end;

// A console tool no longer shares DAK's console, so Ctrl+C or closing the console
// reaches only DAK. The job ties the tool's lifetime to DAK: when DAK exits for
// any reason, the system closes its last job handle and stops the whole tree.
function TryAssignToKillOnCloseJob(aProcess: THandle; out aJob: THandle; out aLastError: Cardinal): Boolean;
var
  lLimits: TJobObjectExtendedLimitInformation;
begin
  aLastError := ERROR_SUCCESS;
  aJob := CreateJobObject(nil, nil);
  if aJob = 0 then
  begin
    aLastError := GetLastError;
    Exit(False);
  end;
  lLimits := Default(TJobObjectExtendedLimitInformation);
  lLimits.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if SetInformationJobObject(aJob, JobObjectExtendedLimitInformation, @lLimits, SizeOf(lLimits)) and
    AssignProcessToJobObject(aJob, aProcess) then
    Exit(True);
  aLastError := GetLastError;
  CloseHandle(aJob);
  aJob := 0;
  Result := False;
end;

function TryRunExternalToolProcess(const aOptions: TExternalToolProcessRunOptions;
  out aExitCode: Cardinal; out aTimedOut: Boolean; out aError: string): Boolean;
var
  lApplicationName: string;
  lApplicationPtr: PChar;
  lAttributeBuffer: TBytes;
  lAttributeSize: NativeUInt;
  lCommandLine: string;
  lCreated: Boolean;
  lCreationFlags: Cardinal;
  lEnvironment: PChar;
  lEnvironmentBlock: string;
  lHandleCount: Integer;
  lHandles: array[0..2] of THandle;
  lJob: THandle;
  lLastError: Cardinal;
  lProcessInfo: TProcessInformation;
  lResume: Boolean;
  lStarted: Boolean;
  lStartupInfo: TStartupInfoEx;
  lToolName: string;
  lValidationError: string;
  lWait: Cardinal;
  lWorkDir: string;
  lWorkDirPtr: PChar;
begin
  Result := False;
  aExitCode := 0;
  aTimedOut := False;
  aError := '';

  FillChar(lStartupInfo, SizeOf(lStartupInfo), 0);
  lStartupInfo.StartupInfo.cb := SizeOf(lStartupInfo.StartupInfo);
  lStartupInfo.StartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  lStartupInfo.StartupInfo.wShowWindow := SW_HIDE;
  lStartupInfo.StartupInfo.hStdInput := aOptions.fStdInHandle;
  if lStartupInfo.StartupInfo.hStdInput = 0 then
    lStartupInfo.StartupInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lStartupInfo.StartupInfo.hStdOutput := aOptions.fStdOutHandle;
  if lStartupInfo.StartupInfo.hStdOutput = 0 then
    lStartupInfo.StartupInfo.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  lStartupInfo.StartupInfo.hStdError := aOptions.fStdErrHandle;
  if lStartupInfo.StartupInfo.hStdError = 0 then
    lStartupInfo.StartupInfo.hStdError := GetStdHandle(STD_ERROR_HANDLE);

  lApplicationName := aOptions.fApplicationName;
  if (lApplicationName = '') and not aOptions.fUseCommandLineApplication then
    lApplicationName := aOptions.fExePath;
  if lApplicationName <> '' then
    lApplicationPtr := PChar(lApplicationName)
  else
    lApplicationPtr := nil;

  lCommandLine := ExternalToolCommandLine(aOptions);
  UniqueString(lCommandLine);
  lWorkDir := aOptions.fWorkDir;
  if lWorkDir <> '' then
    lWorkDirPtr := PChar(lWorkDir)
  else
    lWorkDirPtr := nil;

  // Redirection and SW_HIDE alone do not prevent child console allocation.
  // The tool starts suspended so it joins its job before running any code.
  lResume := (aOptions.fCreationFlags and CREATE_SUSPENDED) = 0;
  lCreationFlags := aOptions.fCreationFlags or CREATE_NO_WINDOW or CREATE_SUSPENDED;
  lEnvironmentBlock := aOptions.fEnvironmentBlock;
  if lEnvironmentBlock <> '' then
  begin
    lCreationFlags := lCreationFlags or CREATE_UNICODE_ENVIRONMENT;
    lEnvironment := PChar(lEnvironmentBlock);
  end else
    lEnvironment := nil;

  if (lApplicationPtr <> nil) and not TryValidateWindowsExecutable(lApplicationName, lValidationError) then
  begin
    aError := ExternalToolStartError(aOptions, lValidationError);
    Exit(False);
  end;

  FillChar(lProcessInfo, SizeOf(lProcessInfo), 0);
  lHandleCount := CollectInheritableHandles(lStartupInfo.StartupInfo, lHandles);
  if lHandleCount > 0 then
  begin
    lAttributeSize := 0;
    // The first call only reports the required size.
    InitializeProcThreadAttributeList(nil, 1, 0, lAttributeSize);
    SetLength(lAttributeBuffer, lAttributeSize);
    lStartupInfo.lpAttributeList := PProcThreadAttributeList(@lAttributeBuffer[0]);
    if not InitializeProcThreadAttributeList(lStartupInfo.lpAttributeList, 1, 0, lAttributeSize) then
    begin
      lLastError := GetLastError;
      aError := ExternalToolStartError(aOptions, SysErrorMessage(lLastError));
      Exit(False);
    end;
    if not UpdateProcThreadAttributeNullable(lStartupInfo.lpAttributeList, 0, cProcThreadAttributeHandleList,
      @lHandles[0], NativeUInt(lHandleCount) * SizeOf(THandle), nil, nil) then
    begin
      lLastError := GetLastError;
      DeleteProcThreadAttributeList(lStartupInfo.lpAttributeList);
      aError := ExternalToolStartError(aOptions, SysErrorMessage(lLastError));
      Exit(False);
    end;
    lStartupInfo.StartupInfo.cb := SizeOf(lStartupInfo);
    lCreationFlags := lCreationFlags or EXTENDED_STARTUPINFO_PRESENT;
  end;
  try
    lCreated := CreateProcess(lApplicationPtr, PChar(lCommandLine), nil, nil, True, lCreationFlags,
      lEnvironment, lWorkDirPtr, lStartupInfo.StartupInfo, lProcessInfo);
    lLastError := GetLastError;
  finally
    if lHandleCount > 0 then
      DeleteProcThreadAttributeList(lStartupInfo.lpAttributeList);
  end;
  if not lCreated then
  begin
    aError := ExternalToolStartError(aOptions, SysErrorMessage(lLastError));
    Exit(False);
  end;

  lStarted := TryAssignToKillOnCloseJob(lProcessInfo.hProcess, lJob, lLastError);
  if lStarted and lResume and (ResumeThread(lProcessInfo.hThread) = DWORD(-1)) then
  begin
    lLastError := GetLastError;
    lStarted := False;
  end;
  if not lStarted then
  begin
    aError := ExternalToolStartError(aOptions, SysErrorMessage(lLastError));
    // The tool never ran. Stop it explicitly, since no job may own it yet.
    if not TerminateProcess(lProcessInfo.hProcess, ERROR_PROCESS_ABORTED) then
    begin
      lLastError := GetLastError;
      aError := aError + '; the suspended process could not be stopped: ' + SysErrorMessage(lLastError);
    end;
    if lJob <> 0 then
      CloseHandle(lJob);
    CloseHandle(lProcessInfo.hThread);
    CloseHandle(lProcessInfo.hProcess);
    Exit(False);
  end;

  lToolName := ExternalToolName(aOptions);
  try
    lWait := WaitForSingleObject(lProcessInfo.hProcess, ExternalToolTimeoutMs(aOptions));
    if lWait = WAIT_TIMEOUT then
    begin
      aTimedOut := True;
      TryTerminateTimedOutExternalToolProcess(lToolName, lProcessInfo.hProcess,
        ExternalToolTimeoutSec(aOptions), aOptions.fTimeoutExitCode, aExitCode, aError);
      Exit(False);
    end;
    if lWait <> WAIT_OBJECT_0 then
    begin
      lLastError := GetLastError;
      aError := Format('%s wait failed: %s', [lToolName, SysErrorMessage(lLastError)]);
      Exit(False);
    end;
    if not GetExitCodeProcess(lProcessInfo.hProcess, aExitCode) then
    begin
      lLastError := GetLastError;
      aError := Format('%s exit code failed: %s', [lToolName, SysErrorMessage(lLastError)]);
      Exit(False);
    end;
  finally
    CloseHandle(lProcessInfo.hThread);
    CloseHandle(lProcessInfo.hProcess);
    // Stops anything the tool left running, including after a timeout.
    CloseHandle(lJob);
  end;

  Result := True;
end;

function TryWaitForExternalToolProcess(const aToolName: string; aProcess: THandle; aTimeoutSec: Integer;
  out aExitCode: Cardinal; out aError: string): Boolean;
var
  lLastError: Cardinal;
  lTimeoutSec: Integer;
  lWait: Cardinal;
begin
  Result := False;
  aExitCode := 0;
  aError := '';
  lTimeoutSec := ResolveExternalToolTimeoutSec(aTimeoutSec);

  lWait := WaitForSingleObject(aProcess, ResolveExternalToolTimeoutMs(lTimeoutSec));
  if lWait = WAIT_TIMEOUT then
  begin
    TryTerminateTimedOutExternalToolProcess(aToolName, aProcess, lTimeoutSec, aExitCode, aError);
    Exit(False);
  end;

  if lWait <> WAIT_OBJECT_0 then
  begin
    lLastError := GetLastError;
    aError := Format('%s wait failed: %s', [aToolName, SysErrorMessage(lLastError)]);
    Exit(False);
  end;

  if not GetExitCodeProcess(aProcess, aExitCode) then
  begin
    lLastError := GetLastError;
    aError := Format('%s exit code failed: %s', [aToolName, SysErrorMessage(lLastError)]);
    Exit(False);
  end;

  Result := True;
end;

end.
