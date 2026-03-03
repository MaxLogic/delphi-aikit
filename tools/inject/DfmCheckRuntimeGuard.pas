unit DfmCheckRuntimeGuard;

interface

implementation

uses
  System.SysUtils,
  Winapi.Windows;

var
  GPreviousExceptProc: Pointer;

procedure WriteFatalLine(const aText: string);
var
  lBytesWritten: Cardinal;
  lLine: UTF8String;
  lStdErr: THandle;
begin
  lLine := UTF8String(aText + sLineBreak);
  lStdErr := GetStdHandle(STD_ERROR_HANDLE);
  if (lStdErr <> 0) and (lStdErr <> INVALID_HANDLE_VALUE) then
    WriteFile(lStdErr, Pointer(lLine)^, Length(lLine), lBytesWritten, nil)
  else
    Writeln(ErrOutput, aText);
end;

procedure DfmCheckExceptHandler(aObj: TObject; aAddr: Pointer);
var
  lMessage: string;
begin
  if aObj is Exception then
    lMessage := Exception(aObj).ClassName + ': ' + Exception(aObj).Message
  else if aObj <> nil then
    lMessage := aObj.ClassName
  else
    lMessage := 'Unknown exception';
  if aAddr <> nil then
    lMessage := lMessage + Format(' at %p', [aAddr]);

  WriteFatalLine('FATAL INIT -> ' + lMessage);
  Halt(255);
end;

initialization
  NoErrMsg := True;
  SetErrorMode(SEM_FAILCRITICALERRORS or SEM_NOGPFAULTERRORBOX or SEM_NOOPENFILEERRORBOX);
  GPreviousExceptProc := ExceptProc;
  ExceptProc := @DfmCheckExceptHandler;

finalization
  ExceptProc := GPreviousExceptProc;

end.
