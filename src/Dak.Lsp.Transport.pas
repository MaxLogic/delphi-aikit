unit Dak.Lsp.Transport;

interface

uses
  System.Classes, System.Diagnostics, System.JSON,
  Winapi.Windows;

type
  TLspJsonRpcClient = class
  private
    fInputHandle: THandle;
    fJobHandle: THandle;
    fOutput: THandleStream;
    fOutputHandle: THandle;
    fProcessHandle: THandle;
    fReadTimeoutMs: Cardinal;
    fReadTimer: TStopwatch;
    fStdErrHandle: THandle;
    fThreadHandle: THandle;
    function ReadAvailable(var aBuffer; aCount: Integer; const aStage: string; out aRead: Integer;
      out aError: string): Boolean;
    function ReadLine(out aLine: string; out aError: string): Boolean;
    function ReadMessage(out aBody: string; out aError: string): Boolean;
    function WriteMessage(const aBody, aStage: string; out aError: string): Boolean;
  public
    destructor Destroy; override;
    function SendNotification(const aMethod, aParamsJson: string; out aError: string): Boolean;
    function SendRequest(aId: Integer; const aMethod, aParamsJson: string; out aResponse: TJSONObject;
      out aError: string): Boolean;
    function ShutdownAndExit(out aError: string): Boolean;
    function StopAfterFailure(const aError: string): string;
    function StopProcessTree(out aError: string): Boolean;
    function Start(const aExePath, aArguments, aWorkDir, aStdErrPath, aEnvironmentBlock: string;
      out aError: string): Boolean;
  end;

function ValidateLspResponse(aResponse: TJSONObject; aId: Integer; out aError: string): Boolean;

implementation

uses
  System.SysUtils;

const
  cDefaultLspRequestTimeoutMs = 30000;
  cLspRequestTimeoutEnvVar = 'DAK_LSP_REQUEST_TIMEOUT_MS';
  cContentLengthHeader = 'Content-Length:';
  // Generous but finite frame limits: a broken server cannot make DAK
  // allocate or scan header data without bound.
  cMaxLspContentLength = 64 * 1024 * 1024;
  cMaxLspHeaderLineLength = 4096;
  cMaxLspHeaderLines = 32;
  // Error text quotes at most this much of an unparseable body.
  cMaxQuotedBodyLength = 200;

type
  // Native JOBOBJECT_BASIC_ACCOUNTING_INFORMATION layout (Windows SDK).
  TLspJobAccounting = record
    fTotalUserTime, fTotalKernelTime, fPeriodUserTime, fPeriodKernelTime: Int64;
    fPageFaults, fTotalProcesses, fActiveProcesses, fTerminatedProcesses: Cardinal;
  end;

function DescribeServerError(aErrorValue: TJSONValue): string;
var
  lErrorObject: TJSONObject;
begin
  if not (aErrorValue is TJSONObject) then
    Exit('DelphiLSP returned a malformed error: ' + aErrorValue.ToJSON);
  lErrorObject := aErrorValue as TJSONObject;
  // TJSONNumber derives from TJSONString in the RTL; a numeric message is malformed.
  if not (lErrorObject.Values['code'] is TJSONNumber) or not (lErrorObject.Values['message'] is TJSONString) or
    (lErrorObject.Values['message'] is TJSONNumber) then
    Exit('DelphiLSP returned a malformed error: ' + aErrorValue.ToJSON);
  Result := Format('DelphiLSP returned error %s: %s',
    [lErrorObject.Values['code'].Value, lErrorObject.Values['message'].Value]);
end;

function ValidateLspResponse(aResponse: TJSONObject; aId: Integer; out aError: string): Boolean;
var
  lId: TJSONValue;
  lVersion: TJSONValue;
begin
  Result := False;
  aError := 'Invalid or mismatched DelphiLSP JSON-RPC response.';
  if aResponse = nil then
    Exit;
  lId := aResponse.Values['id'];
  lVersion := aResponse.Values['jsonrpc'];
  if not (lVersion is TJSONString) or (lVersion.Value <> '2.0') or
    not (lId is TJSONNumber) or (lId.Value <> IntToStr(aId)) then
    Exit;
  if (aResponse.Values['result'] = nil) = (aResponse.Values['error'] = nil) then
    Exit;
  if aResponse.Values['error'] <> nil then
  begin
    // The single rejection path for server errors: the caller adds its stage.
    aError := DescribeServerError(aResponse.Values['error']);
    Exit;
  end;
  aError := '';
  Result := True;
end;

function TLspJsonRpcClient.StopProcessTree(out aError: string): Boolean;
var
  lAccounting: TLspJobAccounting;
  lLastError: Cardinal;
  lTimer: TStopwatch;
begin
  Result := False;
  aError := '';
  // Without a job nothing was started, so no owned process tree exists.
  if fJobHandle = 0 then
    Exit(True);
  if not TerminateJobObject(fJobHandle, ERROR_PROCESS_ABORTED) then
  begin
    lLastError := GetLastError;
    aError := 'Failed to terminate the owned DelphiLSP process tree: ' + SysErrorMessage(lLastError);
    Exit;
  end;
  lTimer := TStopwatch.StartNew;
  repeat
    if not QueryInformationJobObject(fJobHandle, JobObjectBasicAccountingInformation,
      @lAccounting, SizeOf(lAccounting), nil) then
    begin
      lLastError := GetLastError;
      aError := 'Failed to verify DelphiLSP process-tree cleanup: ' + SysErrorMessage(lLastError);
      Exit;
    end;
    if lAccounting.fActiveProcesses = 0 then
      Exit(True);
    Sleep(10);
  until lTimer.ElapsedMilliseconds >= 5000;
  aError := 'Timed out verifying DelphiLSP process-tree cleanup.';
end;

function TLspJsonRpcClient.StopAfterFailure(const aError: string): string;
var
  lCleanupError: string;
begin
  Result := aError;
  // A failed cleanup belongs to the reported failure, never only to a debug
  // channel. The same cleanup error is not appended twice.
  if not StopProcessTree(lCleanupError) and not aError.Contains(lCleanupError) then
    Result := aError + ' Cleanup also failed: ' + lCleanupError;
end;

function ResolveLspRequestTimeoutMs: Cardinal;
var
  lParsed: Cardinal;
  lValue: string;
begin
  Result := cDefaultLspRequestTimeoutMs;
  lValue := Trim(GetEnvironmentVariable(cLspRequestTimeoutEnvVar));
  if (lValue = '') or not TryStrToUInt(lValue, lParsed) or (lParsed < 1) then
    Exit;
  Result := lParsed;
end;

function TLspJsonRpcClient.ReadAvailable(var aBuffer; aCount: Integer; const aStage: string; out aRead: Integer;
  out aError: string): Boolean;
var
  lAvailable: DWORD;
  lCount: Integer;
  lLastError: Cardinal;
begin
  Result := False;
  aRead := 0;
  aError := '';
  while True do
  begin
    // Read only what the pipe already holds. DelphiLSP agents inherit the
    // stdout write end, so the server's exit does not close the pipe, and a
    // blocking read would ignore the request deadline.
    lAvailable := 0;
    if not PeekNamedPipe(fOutputHandle, nil, 0, nil, @lAvailable, nil) then
    begin
      lLastError := GetLastError;
      if lLastError = ERROR_BROKEN_PIPE then
        aError := 'Unexpected end of stream from DelphiLSP while ' + aStage + '.'
      else
        aError := 'Failed to read DelphiLSP response pipe while ' + aStage + ': ' + SysErrorMessage(lLastError);
      Exit(False);
    end;
    if lAvailable > 0 then
    begin
      lCount := aCount;
      if Cardinal(lCount) > lAvailable then
        lCount := Integer(lAvailable);
      aRead := fOutput.Read(aBuffer, lCount);
      if aRead <= 0 then
      begin
        aError := 'Unexpected end of stream from DelphiLSP while ' + aStage + '.';
        Exit(False);
      end;
      Exit(True);
    end;

    // One absolute deadline per request: a slow trickle cannot extend it.
    if UInt64(fReadTimer.ElapsedMilliseconds) >= fReadTimeoutMs then
    begin
      aError := StopAfterFailure(Format('DelphiLSP timed out after %d ms while %s.', [fReadTimeoutMs, aStage]));
      Exit(False);
    end;
    Sleep(10);
  end;
end;

function TLspJsonRpcClient.ReadLine(out aLine: string; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lByte: Byte;
  lRead: Integer;
begin
  Result := False;
  aLine := '';
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    while True do
    begin
      if not ReadAvailable(lByte, 1, 'reading response header', lRead, aError) then
        Exit(False);
      if lByte = Ord(#10) then
        Break;
      if lByte = Ord(#13) then
        Continue;
      if lBuilder.Length >= cMaxLspHeaderLineLength then
      begin
        aError := Format('DelphiLSP response header line exceeds %d bytes.', [cMaxLspHeaderLineLength]);
        Exit(False);
      end;
      lBuilder.Append(Char(lByte));
    end;
    aLine := lBuilder.ToString;
    Result := True;
  finally
    lBuilder.Free;
  end;
end;

function TLspJsonRpcClient.ReadMessage(out aBody: string; out aError: string): Boolean;
var
  lBodyBytes: TBytes;
  lContentLength: Int64;
  lLine: string;
  lLineCount: Integer;
  lOffset: Integer;
  lRead: Integer;
begin
  Result := False;
  aBody := '';
  aError := '';
  lContentLength := -1;
  lLineCount := 0;
  while True do
  begin
    if not ReadLine(lLine, aError) then
      Exit(False);
    if lLine = '' then
      Break;
    Inc(lLineCount);
    if lLineCount > cMaxLspHeaderLines then
    begin
      aError := Format('DelphiLSP response has more than %d header lines.', [cMaxLspHeaderLines]);
      Exit(False);
    end;
    if not SameText(Copy(lLine, 1, Length(cContentLengthHeader)), cContentLengthHeader) then
      Continue;
    if not TryStrToInt64(Trim(Copy(lLine, Length(cContentLengthHeader) + 1, MaxInt)), lContentLength) or
      (lContentLength < 0) then
    begin
      aError := 'Invalid Content-Length header in DelphiLSP response: ' + lLine;
      Exit(False);
    end;
    if lContentLength > cMaxLspContentLength then
    begin
      aError := Format('DelphiLSP response Content-Length %d exceeds the %d-byte limit.',
        [lContentLength, cMaxLspContentLength]);
      Exit(False);
    end;
  end;
  if lContentLength < 0 then
  begin
    aError := 'Missing Content-Length header in DelphiLSP response.';
    Exit(False);
  end;
  SetLength(lBodyBytes, Integer(lContentLength)); // bounded by cMaxLspContentLength above
  lOffset := 0;
  while lOffset < lContentLength do
  begin
    if not ReadAvailable(lBodyBytes[lOffset], Integer(lContentLength) - lOffset, 'reading response body', lRead,
      aError) then
      Exit(False);
    Inc(lOffset, lRead);
  end;
  aBody := TEncoding.UTF8.GetString(lBodyBytes);
  Result := True;
end;

function TLspJsonRpcClient.WriteMessage(const aBody, aStage: string; out aError: string): Boolean;
var
  lBodyBytes: TBytes;
  lFrame: TBytes;
  lLastError: Cardinal;
  lOffset: Integer;
  lWritten: DWORD;
begin
  Result := False;
  aError := '';
  lBodyBytes := TEncoding.UTF8.GetBytes(aBody);
  lFrame := TEncoding.ASCII.GetBytes('Content-Length: ' + IntToStr(Length(lBodyBytes)) + #13#10#13#10) + lBodyBytes;
  lOffset := 0;
  while True do
  begin
    // The stdin write end is non-blocking (Start): WriteFile takes only what
    // the pipe buffer can hold and never waits for the reader. DelphiLSP agents
    // inherit the read end, so a stalled server need not break the pipe either.
    lWritten := 0;
    if not WriteFile(fInputHandle, lFrame[lOffset], DWORD(Length(lFrame) - lOffset), lWritten, nil) then
    begin
      lLastError := GetLastError;
      aError := 'Failed to write DelphiLSP message while ' + aStage + ': ' + SysErrorMessage(lLastError);
      Exit(False);
    end;
    Inc(lOffset, Integer(lWritten));
    if lOffset >= Length(lFrame) then
      Exit(True);

    // The same absolute request deadline as the response read.
    if UInt64(fReadTimer.ElapsedMilliseconds) >= fReadTimeoutMs then
    begin
      aError := StopAfterFailure(Format('DelphiLSP timed out after %d ms while %s.', [fReadTimeoutMs, aStage]));
      Exit(False);
    end;
    if lWritten = 0 then
      Sleep(10);
  end;
end;

destructor TLspJsonRpcClient.Destroy;
var
  lCleanupError: string;
begin
  // Kill-on-close also contains startup and request failures and descendants.
  if fJobHandle <> 0 then
  begin
    // Callers report cleanup failures through StopProcessTree/StopAfterFailure
    // before destruction; this is only the safety net for other paths.
    if not StopProcessTree(lCleanupError) then
      OutputDebugString(PChar(lCleanupError));
    CloseHandle(fJobHandle);
  end;
  if fInputHandle <> 0 then
    CloseHandle(fInputHandle);
  fOutput.Free;
  if fOutputHandle <> 0 then
    CloseHandle(fOutputHandle);
  if fStdErrHandle <> 0 then
    CloseHandle(fStdErrHandle);
  if fProcessHandle <> 0 then
  begin
    if WaitForSingleObject(fProcessHandle, 0) = WAIT_TIMEOUT then
      TerminateProcess(fProcessHandle, 1);
    CloseHandle(fProcessHandle);
  end;
  if fThreadHandle <> 0 then
    CloseHandle(fThreadHandle);
  inherited Destroy;
end;

function TLspJsonRpcClient.SendNotification(const aMethod, aParamsJson: string; out aError: string): Boolean;
var
  lBody: string;
  lParamsJson: string;
begin
  lParamsJson := aParamsJson;
  if Trim(lParamsJson) = '' then
    lParamsJson := '{}';
  lBody := '{"jsonrpc":"2.0","method":"' + aMethod + '","params":' + lParamsJson + '}';
  // A notification gets no response, but its write needs its own deadline.
  fReadTimeoutMs := ResolveLspRequestTimeoutMs;
  fReadTimer := TStopwatch.StartNew;
  Result := WriteMessage(lBody, 'writing notification', aError);
end;

function TLspJsonRpcClient.SendRequest(aId: Integer; const aMethod, aParamsJson: string; out aResponse: TJSONObject;
  out aError: string): Boolean;
var
  lBody: string;
  lJsonValue: TJSONValue;
  lParamsJson: string;
  lResponseText: string;
begin
  Result := False;
  aError := '';
  aResponse := nil;
  lParamsJson := aParamsJson;
  if Trim(lParamsJson) = '' then
    lParamsJson := '{}';
  lBody := '{"jsonrpc":"2.0","id":' + IntToStr(aId) + ',"method":"' + aMethod + '","params":' + lParamsJson + '}';
  fReadTimeoutMs := ResolveLspRequestTimeoutMs;
  fReadTimer := TStopwatch.StartNew;
  if not WriteMessage(lBody, 'writing request', aError) then
    Exit(False);
  if not ReadMessage(lResponseText, aError) then
    Exit(False);
  lJsonValue := TJSONObject.ParseJSONValue(lResponseText);
  if not (lJsonValue is TJSONObject) then
  begin
    lJsonValue.Free;
    aError := 'Invalid DelphiLSP JSON-RPC response: ' + Copy(lResponseText, 1, cMaxQuotedBodyLength);
    Exit(False);
  end;
  aResponse := lJsonValue as TJSONObject;
  Result := ValidateLspResponse(aResponse, aId, aError);
  if not Result then
    FreeAndNil(aResponse);
end;

function TLspJsonRpcClient.ShutdownAndExit(out aError: string): Boolean;
var
  lExitCode: Cardinal;
  lResponse: TJSONObject;
  lWait: Cardinal;
begin
  lResponse := nil;
  try
    if not SendRequest(9001, 'shutdown', '{}', lResponse, aError) then
      Exit(False);
  finally
    lResponse.Free;
  end;
  if not SendNotification('exit', '{}', aError) then
    Exit(False);
  lWait := WaitForSingleObject(fProcessHandle, 5000);
  if lWait <> WAIT_OBJECT_0 then
  begin
    aError := 'DelphiLSP did not exit cleanly.';
    Exit(False);
  end;
  if not GetExitCodeProcess(fProcessHandle, lExitCode) then
  begin
    aError := 'Failed to read DelphiLSP exit code: ' + SysErrorMessage(GetLastError);
    Exit(False);
  end;
  if lExitCode <> 0 then
  begin
    aError := Format('DelphiLSP exited with code %d.', [lExitCode]);
    Exit(False);
  end;
  Result := True;
end;

function TLspJsonRpcClient.Start(const aExePath, aArguments, aWorkDir, aStdErrPath, aEnvironmentBlock: string;
  out aError: string): Boolean;
var
  lChildStdInRead: THandle;
  lChildStdInWrite: THandle;
  lChildStdOutRead: THandle;
  lChildStdOutWrite: THandle;
  lCmdLine: string;
  lCreationFlags: Cardinal;
  lEnvironment: PChar;
  lJobLimits: TJobObjectExtendedLimitInformation;
  lLastError: Cardinal;
  lPi: TProcessInformation;
  lPipeMode: DWORD;
  lSa: TSecurityAttributes;
  lSi: TStartupInfo;
  lStdErrHandle: THandle;
  lStdErrDir: string;
begin
  Result := False;
  aError := '';
  lChildStdInRead := 0;
  lChildStdInWrite := 0;
  lChildStdOutRead := 0;
  lChildStdOutWrite := 0;
  lStdErrHandle := 0;

  // Protocol-specific process supervision: LSP owns JSON-RPC pipes and request-timeout semantics.
  FillChar(lSa, SizeOf(lSa), 0);
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;

  if not CreatePipe(lChildStdOutRead, lChildStdOutWrite, @lSa, 0) then
  begin
    aError := 'Failed to create DelphiLSP stdout pipe.';
    Exit(False);
  end;
  if not CreatePipe(lChildStdInRead, lChildStdInWrite, @lSa, 0) then
  begin
    aError := 'Failed to create DelphiLSP stdin pipe.';
    CloseHandle(lChildStdOutRead);
    CloseHandle(lChildStdOutWrite);
    Exit(False);
  end;

  try
    SetHandleInformation(lChildStdOutRead, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(lChildStdInWrite, HANDLE_FLAG_INHERIT, 0);
    // Our write end only: WriteFile then never blocks on a server that stops
    // draining stdin, and WriteMessage enforces the request deadline. An
    // anonymous pipe is a named pipe, and the mode is per end, so the child's
    // read end stays blocking.
    lPipeMode := PIPE_READMODE_BYTE or PIPE_NOWAIT;
    if not SetNamedPipeHandleState(lChildStdInWrite, lPipeMode, nil, nil) then
    begin
      aError := 'Failed to make the DelphiLSP stdin pipe non-blocking: ' + SysErrorMessage(GetLastError);
      Exit(False);
    end;

    if Trim(aStdErrPath) <> '' then
    begin
      lStdErrDir := ExtractFileDir(aStdErrPath);
      if lStdErrDir <> '' then
        ForceDirectories(lStdErrDir);
      lStdErrHandle := CreateFile(PChar(aStdErrPath), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, 0);
      if lStdErrHandle = INVALID_HANDLE_VALUE then
      begin
        lStdErrHandle := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @lSa, OPEN_EXISTING,
          FILE_ATTRIBUTE_NORMAL, 0);
        if lStdErrHandle = INVALID_HANDLE_VALUE then
          lStdErrHandle := GetStdHandle(STD_ERROR_HANDLE);
      end;
    end else
      lStdErrHandle := GetStdHandle(STD_ERROR_HANDLE);

    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES;
    lSi.hStdInput := lChildStdInRead;
    lSi.hStdOutput := lChildStdOutWrite;
    lSi.hStdError := lStdErrHandle;

    FillChar(lPi, SizeOf(lPi), 0);
    lCmdLine := '"' + aExePath + '"';
    if aArguments <> '' then
      lCmdLine := lCmdLine + ' ' + aArguments;
    UniqueString(lCmdLine);
    if aEnvironmentBlock <> '' then
    begin
      lCreationFlags := CREATE_NO_WINDOW or CREATE_SUSPENDED or CREATE_UNICODE_ENVIRONMENT;
      lEnvironment := PChar(aEnvironmentBlock);
    end else begin
      lCreationFlags := CREATE_NO_WINDOW or CREATE_SUSPENDED;
      lEnvironment := nil;
    end;

    fJobHandle := CreateJobObject(nil, nil);
    lJobLimits := Default(TJobObjectExtendedLimitInformation);
    lJobLimits.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (fJobHandle = 0) or not SetInformationJobObject(fJobHandle, JobObjectExtendedLimitInformation,
      @lJobLimits, SizeOf(lJobLimits)) then
    begin
      aError := 'Failed to isolate DelphiLSP process tree: ' + SysErrorMessage(GetLastError);
      Exit(False);
    end;
    if not CreateProcess(PChar(aExePath), PChar(lCmdLine), nil, nil, True, lCreationFlags, lEnvironment,
      PChar(aWorkDir), lSi, lPi) then
    begin
      lLastError := GetLastError;
      aError := 'Failed to start DelphiLSP.exe: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;

    // Assign before execution: no descendant can escape the owned job.
    if not AssignProcessToJobObject(fJobHandle, lPi.hProcess) or
      (ResumeThread(lPi.hThread) = DWORD(-1)) then
    begin
      lLastError := GetLastError;
      TerminateProcess(lPi.hProcess, ERROR_PROCESS_ABORTED);
      WaitForSingleObject(lPi.hProcess, 5000);
      CloseHandle(lPi.hThread);
      CloseHandle(lPi.hProcess);
      aError := 'Failed to start isolated DelphiLSP process: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;

    CloseHandle(lChildStdInRead);
    lChildStdInRead := 0;
    CloseHandle(lChildStdOutWrite);
    lChildStdOutWrite := 0;

    fOutput := THandleStream.Create(lChildStdOutRead);
    fInputHandle := lChildStdInWrite;
    fOutputHandle := lChildStdOutRead;
    fProcessHandle := lPi.hProcess;
    fThreadHandle := lPi.hThread;
    if (Trim(aStdErrPath) <> '') and (lStdErrHandle <> INVALID_HANDLE_VALUE) then
    begin
      fStdErrHandle := lStdErrHandle;
      lStdErrHandle := 0;
    end;
    Result := True;
  finally
    if lChildStdInRead <> 0 then
      CloseHandle(lChildStdInRead);
    if lChildStdOutWrite <> 0 then
      CloseHandle(lChildStdOutWrite);
    if not Result then
    begin
      if lChildStdInWrite <> 0 then
        CloseHandle(lChildStdInWrite);
      if lChildStdOutRead <> 0 then
        CloseHandle(lChildStdOutRead);
    end;
    if (lStdErrHandle <> 0) and (lStdErrHandle <> GetStdHandle(STD_ERROR_HANDLE)) and
      (lStdErrHandle <> INVALID_HANDLE_VALUE) then
      CloseHandle(lStdErrHandle);
  end;
end;

end.
