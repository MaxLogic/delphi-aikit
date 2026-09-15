unit Test.ExternalToolProcess;

interface

uses
  DUnitX.TestFramework;

type
  // The shared child-process runner must hand each child only its own standard handles.
  // Concurrent launches with inherited pipes otherwise leak one child's pipe end into the
  // other child, and the first reader only sees EOF when the unrelated child exits.
  [TestFixture]
  TExternalToolProcessTests = class
  public
    [Test]
    procedure ConcurrentChildrenDoNotInheritEachOthersPipes;
  end;

implementation

uses
  System.Classes, System.Diagnostics, System.SysUtils,
  Winapi.Windows,
  Dak.ExternalToolProcess;

type
  TPipePair = record
    ReadHandle: THandle;
    WriteHandle: THandle;
  end;

function CreateInheritablePipe: TPipePair;
var
  lSecurity: TSecurityAttributes;
begin
  lSecurity := Default(TSecurityAttributes);
  lSecurity.nLength := SizeOf(lSecurity);
  lSecurity.bInheritHandle := True;
  if not CreatePipe(Result.ReadHandle, Result.WriteHandle, @lSecurity, 4096) then
    RaiseLastOSError;
  if not SetHandleInformation(Result.ReadHandle, HANDLE_FLAG_INHERIT, 0) then
    RaiseLastOSError;
end;

function OpenInheritableNul: THandle;
var
  lSecurity: TSecurityAttributes;
begin
  lSecurity := Default(TSecurityAttributes);
  lSecurity.nLength := SizeOf(lSecurity);
  lSecurity.bInheritHandle := True;
  Result := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @lSecurity,
    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if Result = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
end;

function RunOptions(const aArguments: string; aInput, aOutput, aError: THandle): TExternalToolProcessRunOptions;
begin
  Result := Default(TExternalToolProcessRunOptions);
  Result.fExePath := GetEnvironmentVariable('ComSpec');
  Result.fArguments := aArguments;
  Result.fStdInHandle := aInput;
  Result.fStdOutHandle := aOutput;
  Result.fStdErrHandle := aError;
  Result.fCreationFlags := CREATE_NO_WINDOW;
  Result.fTimeoutSec := 30;
end;

// Reads the pipe until EOF, which requires every inherited write handle to be closed.
function ReadUntilEof(aRead: THandle): string;
var
  lBuffer: array[0..1023] of AnsiChar;
  lCount: DWORD;
  lBytes: TBytes;
begin
  SetLength(lBytes, 0);
  while ReadFile(aRead, lBuffer, SizeOf(lBuffer), lCount, nil) and (lCount > 0) do
  begin
    SetLength(lBytes, Length(lBytes) + Integer(lCount));
    Move(lBuffer, lBytes[Length(lBytes) - Integer(lCount)], lCount);
  end;
  Result := TEncoding.ANSI.GetString(lBytes);
end;

procedure TExternalToolProcessTests.ConcurrentChildrenDoNotInheritEachOthersPipes;
var
  lSlowPipe, lFastPipe: TPipePair;
  lNul: THandle;
  lSlowThread: TThread;
  lSlowExit, lFastExit: Cardinal;
  lSlowTimedOut, lFastTimedOut, lSlowOk, lFastOk: Boolean;
  lSlowError, lFastError, lFastOutput: string;
  lWatch: TStopwatch;
  lFastMilliseconds: Int64;
begin
  lSlowPipe := CreateInheritablePipe;
  lFastPipe := CreateInheritablePipe;
  lNul := OpenInheritableNul;
  try
    lSlowOk := False;
    lSlowExit := 0;
    lSlowTimedOut := False;
    // A slow child keeps running while the fast child is launched and read.
    lSlowThread := TThread.CreateAnonymousThread(
      procedure
      begin
        lSlowOk := TryRunExternalToolProcess(RunOptions('/c ping -n 4 127.0.0.1 >nul', lNul,
          lSlowPipe.WriteHandle, lSlowPipe.WriteHandle), lSlowExit, lSlowTimedOut, lSlowError);
      end);
    lSlowThread.FreeOnTerminate := False;
    lSlowThread.Start;
    Sleep(300);
    lWatch := TStopwatch.StartNew;
    lFastOk := TryRunExternalToolProcess(RunOptions('/c echo fast', lNul, lFastPipe.WriteHandle,
      lFastPipe.WriteHandle), lFastExit, lFastTimedOut, lFastError);
    // Close our own copy so EOF depends only on children that inherited the write end.
    CloseHandle(lFastPipe.WriteHandle);
    lFastPipe.WriteHandle := 0;
    lFastOutput := ReadUntilEof(lFastPipe.ReadHandle);
    lFastMilliseconds := lWatch.ElapsedMilliseconds;
    lSlowThread.WaitFor;
    lSlowThread.Free;
    Assert.IsTrue(lFastOk, 'fast child must start: ' + lFastError);
    Assert.AreEqual(Cardinal(0), lFastExit, 'fast child exit code');
    Assert.IsTrue(lFastOutput.Trim.EndsWith('fast'), 'fast child output was [' + lFastOutput + ']');
    Assert.IsTrue(lSlowOk, 'slow child must complete: ' + lSlowError);
    Assert.IsTrue(lFastMilliseconds < 1500,
      Format('fast child pipe reached EOF after %d ms; a leaked pipe end waits for the slow child (about 3000 ms)',
      [lFastMilliseconds]));
  finally
    if lFastPipe.WriteHandle <> 0 then
      CloseHandle(lFastPipe.WriteHandle);
    CloseHandle(lFastPipe.ReadHandle);
    CloseHandle(lSlowPipe.WriteHandle);
    CloseHandle(lSlowPipe.ReadHandle);
    CloseHandle(lNul);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExternalToolProcessTests);

end.
