unit Dak.ExternalToolProcess;

interface

uses
  System.SysUtils,
  Winapi.Windows;

const
  cExternalToolDefaultTimeoutSec = 1800;
  cExternalToolTimeoutExitCode = WAIT_TIMEOUT;

function ResolveExternalToolTimeoutSec(aTimeoutSec: Integer): Integer;
function ResolveExternalToolTimeoutMs(aTimeoutSec: Integer): Cardinal;
function TryTerminateTimedOutExternalToolProcess(const aToolName: string; aProcess: THandle; aTimeoutSec: Integer;
  out aExitCode: Cardinal; out aError: string): Boolean;
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
  lMilliseconds: UInt64;
begin
  lMilliseconds := UInt64(ResolveExternalToolTimeoutSec(aTimeoutSec)) * 1000;
  if lMilliseconds >= INFINITE then
    Exit(INFINITE - 1);
  Result := Cardinal(lMilliseconds);
end;

function TryTerminateTimedOutExternalToolProcess(const aToolName: string; aProcess: THandle; aTimeoutSec: Integer;
  out aExitCode: Cardinal; out aError: string): Boolean;
var
  lLastError: Cardinal;
  lTimeoutSec: Integer;
  lWait: Cardinal;
begin
  Result := False;
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
