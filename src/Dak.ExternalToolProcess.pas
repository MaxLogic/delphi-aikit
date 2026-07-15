unit Dak.ExternalToolProcess;

interface

uses
  System.SysUtils,
  Winapi.Windows;

const
  cExternalToolDefaultTimeoutSec = 1800;
  cExternalToolTimeoutExitCode = WAIT_TIMEOUT;

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

function TryRunExternalToolProcess(const aOptions: TExternalToolProcessRunOptions;
  out aExitCode: Cardinal; out aTimedOut: Boolean; out aError: string): Boolean;
var
  lApplicationName: string;
  lApplicationPtr: PChar;
  lCommandLine: string;
  lCreationFlags: Cardinal;
  lEnvironment: PChar;
  lEnvironmentBlock: string;
  lLastError: Cardinal;
  lProcessInfo: TProcessInformation;
  lStartupInfo: TStartupInfo;
  lToolName: string;
  lWait: Cardinal;
  lWorkDir: string;
  lWorkDirPtr: PChar;
begin
  Result := False;
  aExitCode := 0;
  aTimedOut := False;
  aError := '';

  FillChar(lStartupInfo, SizeOf(lStartupInfo), 0);
  lStartupInfo.cb := SizeOf(lStartupInfo);
  lStartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  lStartupInfo.wShowWindow := SW_HIDE;
  lStartupInfo.hStdInput := aOptions.fStdInHandle;
  if lStartupInfo.hStdInput = 0 then
    lStartupInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lStartupInfo.hStdOutput := aOptions.fStdOutHandle;
  if lStartupInfo.hStdOutput = 0 then
    lStartupInfo.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  lStartupInfo.hStdError := aOptions.fStdErrHandle;
  if lStartupInfo.hStdError = 0 then
    lStartupInfo.hStdError := GetStdHandle(STD_ERROR_HANDLE);

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

  lCreationFlags := aOptions.fCreationFlags;
  lEnvironmentBlock := aOptions.fEnvironmentBlock;
  if lEnvironmentBlock <> '' then
  begin
    lCreationFlags := lCreationFlags or CREATE_UNICODE_ENVIRONMENT;
    lEnvironment := PChar(lEnvironmentBlock);
  end else
    lEnvironment := nil;

  FillChar(lProcessInfo, SizeOf(lProcessInfo), 0);
  if not CreateProcess(lApplicationPtr, PChar(lCommandLine), nil, nil, True, lCreationFlags,
    lEnvironment, lWorkDirPtr, lStartupInfo, lProcessInfo) then
  begin
    lLastError := GetLastError;
    aError := ExternalToolStartError(aOptions, SysErrorMessage(lLastError));
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
