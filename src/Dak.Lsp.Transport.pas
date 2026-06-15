unit Dak.Lsp.Transport;

interface

uses
  System.Classes, System.JSON,
  Winapi.Windows;

type
  TLspJsonRpcClient = class
  private
    fInput: THandleStream;
    fInputHandle: THandle;
    fOutput: THandleStream;
    fOutputHandle: THandle;
    fProcessHandle: THandle;
    fStdErrHandle: THandle;
    fThreadHandle: THandle;
    function ReadLine(out aLine: string; out aError: string): Boolean;
    function ReadMessage(out aBody: string; out aError: string): Boolean;
    function WaitForOutput(const aStage: string; out aError: string): Boolean;
    function WriteMessage(const aBody: string; out aError: string): Boolean;
  public
    destructor Destroy; override;
    function SendNotification(const aMethod, aParamsJson: string; out aError: string): Boolean;
    function SendRequest(aId: Integer; const aMethod, aParamsJson: string; out aResponse: TJSONObject;
      out aError: string): Boolean;
    function ShutdownAndExit(out aError: string): Boolean;
    function Start(const aExePath, aArguments, aWorkDir, aStdErrPath, aEnvironmentBlock: string;
      out aError: string): Boolean;
  end;

implementation

uses
  System.Diagnostics, System.SysUtils;

const
  cDefaultLspRequestTimeoutMs = 30000;
  cLspRequestTimeoutEnvVar = 'DAK_LSP_REQUEST_TIMEOUT_MS';

function ResolveLspRequestTimeoutMs: Cardinal;
var
  lParsed: Int64;
  lValue: string;
begin
  Result := cDefaultLspRequestTimeoutMs;
  lValue := Trim(GetEnvironmentVariable(cLspRequestTimeoutEnvVar));
  if (lValue = '') or not TryStrToInt64(lValue, lParsed) or (lParsed < 1) then
    Exit;
  if lParsed > High(Cardinal) then
    Exit(High(Cardinal));
  Result := Cardinal(lParsed);
end;

function TLspJsonRpcClient.WaitForOutput(const aStage: string; out aError: string): Boolean;
var
  lBytesAvailable: DWORD;
  lLastError: Cardinal;
  lStopwatch: TStopwatch;
  lTimeoutMs: Cardinal;
begin
  Result := False;
  aError := '';
  lStopwatch := TStopwatch.StartNew;
  lTimeoutMs := ResolveLspRequestTimeoutMs;
  while True do
  begin
    if (fProcessHandle <> 0) and (WaitForSingleObject(fProcessHandle, 0) = WAIT_OBJECT_0) then
      Exit(True);

    lBytesAvailable := 0;
    if not PeekNamedPipe(fOutputHandle, nil, 0, nil, @lBytesAvailable, nil) then
    begin
      lLastError := GetLastError;
      aError := 'Failed to read DelphiLSP response pipe while ' + aStage + ': ' + SysErrorMessage(lLastError);
      Exit(False);
    end;
    if lBytesAvailable > 0 then
      Exit(True);

    if UInt64(lStopwatch.ElapsedMilliseconds) >= lTimeoutMs then
    begin
      if fProcessHandle <> 0 then
      begin
        TerminateProcess(fProcessHandle, WAIT_TIMEOUT);
        WaitForSingleObject(fProcessHandle, 5000);
      end;
      aError := Format('DelphiLSP timed out after %d ms while %s.', [lTimeoutMs, aStage]);
      Exit(False);
    end;
    Sleep(10);
  end;
end;

function TLspJsonRpcClient.ReadLine(out aLine: string; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lByte: Byte;
  lCount: Integer;
begin
  Result := False;
  aLine := '';
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    while True do
    begin
      if not WaitForOutput('reading response header', aError) then
        Exit(False);
      lCount := fOutput.Read(lByte, 1);
      if lCount <> 1 then
      begin
        aError := 'Unexpected end of stream while reading DelphiLSP response header.';
        Exit(False);
      end;
      if lByte = Ord(#10) then
        Break;
      if lByte <> Ord(#13) then
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
  lContentLength: Integer;
  lLine: string;
  lOffset: Integer;
  lRead: Integer;
begin
  Result := False;
  aBody := '';
  aError := '';
  lContentLength := -1;
  while True do
  begin
    if not ReadLine(lLine, aError) then
      Exit(False);
    if lLine = '' then
      Break;
    if SameText(Copy(lLine, 1, Length('Content-Length:')), 'Content-Length:') then
      lContentLength := StrToIntDef(Trim(Copy(lLine, Length('Content-Length:') + 1, MaxInt)), -1);
  end;
  if lContentLength < 0 then
  begin
    aError := 'Missing Content-Length header in DelphiLSP response.';
    Exit(False);
  end;
  SetLength(lBodyBytes, lContentLength);
  lOffset := 0;
  while lOffset < lContentLength do
  begin
    if not WaitForOutput('reading response body', aError) then
      Exit(False);
    lRead := fOutput.Read(lBodyBytes[lOffset], lContentLength - lOffset);
    if lRead <= 0 then
    begin
      aError := 'Unexpected end of stream while reading DelphiLSP response body.';
      Exit(False);
    end;
    Inc(lOffset, lRead);
  end;
  aBody := TEncoding.UTF8.GetString(lBodyBytes);
  Result := True;
end;

function TLspJsonRpcClient.WriteMessage(const aBody: string; out aError: string): Boolean;
var
  lBodyBytes: TBytes;
  lHeaderBytes: TBytes;
  lHeaderText: string;
begin
  Result := False;
  aError := '';
  lBodyBytes := TEncoding.UTF8.GetBytes(aBody);
  lHeaderText := 'Content-Length: ' + IntToStr(Length(lBodyBytes)) + #13#10#13#10;
  lHeaderBytes := TEncoding.ASCII.GetBytes(lHeaderText);
  try
    if Length(lHeaderBytes) > 0 then
      fInput.WriteBuffer(lHeaderBytes[0], Length(lHeaderBytes));
    if Length(lBodyBytes) > 0 then
      fInput.WriteBuffer(lBodyBytes[0], Length(lBodyBytes));
    Result := True;
  except
    on E: Exception do
    begin
      aError := 'Failed to write DelphiLSP message: ' + E.Message;
    end;
  end;
end;

destructor TLspJsonRpcClient.Destroy;
begin
  fInput.Free;
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
  Result := WriteMessage(lBody, aError);
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
  if not WriteMessage(lBody, aError) then
    Exit(False);
  if not ReadMessage(lResponseText, aError) then
    Exit(False);
  lJsonValue := TJSONObject.ParseJSONValue(lResponseText);
  if not (lJsonValue is TJSONObject) then
  begin
    lJsonValue.Free;
    aError := 'Invalid DelphiLSP JSON-RPC response: ' + lResponseText;
    Exit(False);
  end;
  aResponse := lJsonValue as TJSONObject;
  Result := True;
end;

function TLspJsonRpcClient.ShutdownAndExit(out aError: string): Boolean;
var
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
  lLastError: Cardinal;
  lPi: TProcessInformation;
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
      lCreationFlags := CREATE_NO_WINDOW or CREATE_UNICODE_ENVIRONMENT;
      lEnvironment := PChar(aEnvironmentBlock);
    end else
    begin
      lCreationFlags := CREATE_NO_WINDOW;
      lEnvironment := nil;
    end;

    if not CreateProcess(PChar(aExePath), PChar(lCmdLine), nil, nil, True, lCreationFlags, lEnvironment,
      PChar(aWorkDir), lSi, lPi) then
    begin
      lLastError := GetLastError;
      aError := 'Failed to start DelphiLSP.exe: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;

    CloseHandle(lChildStdInRead);
    lChildStdInRead := 0;
    CloseHandle(lChildStdOutWrite);
    lChildStdOutWrite := 0;

    fInput := THandleStream.Create(lChildStdInWrite);
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
