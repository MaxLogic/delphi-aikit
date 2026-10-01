unit Test.Lsp.Protocol;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspProtocolTests = class
  public
    [Test]
    [TestCase('Local URI', '0')]
    [TestCase('Host URI with literal plus', '1')]
    [TestCase('Drive authority URI', '2')]
    [TestCase('UNC LocationLink', '3')]
    procedure DefinitionCoordinatesAndUris(aVariant: Integer);
    [Test]
    [TestCase('Definition', '0')]
    [TestCase('Hover', '1')]
    procedure RequestUsesZeroBasedPosition(aVariant: Integer);
    [Test]
    procedure SymbolsRequestHasNoPosition;
    [Test]
    [TestCase('Text', '0')]
    [TestCase('Empty', '1')]
    [TestCase('DelphiLSP 23 markdown without range', '2')]
    procedure HoverPreservesTextAndRange(aVariant: Integer);
    [Test]
    [TestCase('All', '0')]
    [TestCase('Query and limit', '1')]
    [TestCase('No matches', '2')]
    procedure SymbolsFlattenThenFilter(aVariant: Integer);
    [Test]
    procedure SymbolsUseSelectionRangeAcrossNesting;
    [Test]
    [TestCase('Definition null', '0')]
    [TestCase('Definition empty array', '1')]
    [TestCase('Symbols null', '2')]
    [TestCase('Symbols empty array', '3')]
    [TestCase('Hover null', '4')]
    [TestCase('Hover empty string contents', '5')]
    [TestCase('Hover empty contents array', '6')]
    procedure EmptyResultShapesStayValid(aVariant: Integer);
    [Test]
    [TestCase('Definition object without location', '0')]
    [TestCase('Definition string', '1')]
    [TestCase('Definition item without range', '2')]
    [TestCase('Symbols string', '3')]
    [TestCase('Symbols single object', '4')]
    [TestCase('Symbols item number', '5')]
    [TestCase('Hover number', '6')]
    [TestCase('Hover without contents', '7')]
    [TestCase('Hover contents number', '8')]
    procedure MalformedResultIsFailure(aVariant: Integer);
    [Test]
    [TestCase('Initialize', '0')]
    [TestCase('Probe initialize', '1')]
    [TestCase('Definition request', '2')]
    procedure ServerErrorKeepsStageCodeAndMessage(aVariant: Integer);
    [Test]
    procedure NativeTransportRejectsMissingExecutable;
    [Test]
    procedure NativeTransportBoundsUnresponsiveInput;
    [Test]
    [TestCase('Destructor', '0')]
    [TestCase('Explicit cleanup', '1')]
    [TestCase('Request timeout', '2')]
    procedure NativeTransportDestructorStopsDescendants(aVariant: Integer);
    [Test]
    [TestCase('Valid', '0')]
    [TestCase('Mismatched ID', '1')]
    [TestCase('Missing result', '2')]
    [TestCase('Server error', '3')]
    [TestCase('Wrong version', '4')]
    [TestCase('Ambiguous response', '5')]
    procedure ResponseValidation(aVariant: Integer);
    [Test]
    procedure NativeTransportControlledStop;
    [Test]
    [TestCase('Missing Content-Length', '0')]
    [TestCase('Oversized Content-Length', '1')]
    [TestCase('Invalid JSON body', '2')]
    [TestCase('Truncated body', '3')]
    [TestCase('Slow trickle past deadline', '4')]
    [TestCase('Overlong header line', '5')]
    [TestCase('Too many header lines', '6')]
    [TestCase('Server error response', '7')]
    procedure NativeTransportRejectsMalformedFrames(aVariant: Integer);
    [Test]
    procedure NativeTransportBoundsInheritedStdoutAfterExit;
    [Test]
    [TestCase('Request', '0')]
    [TestCase('Notification', '1')]
    procedure NativeTransportBoundsUndrainedStdinWrite(aVariant: Integer);
    [Test]
    procedure NativeTransportWritesLargeRequestWhole;
    [Test]
    [TestCase('Explicit stop', '0')]
    [TestCase('Failure path', '1')]
    [TestCase('Request timeout', '2')]
    procedure NativeTransportReportsCleanupFailure(aVariant: Integer);
    [Test]
    procedure StopProcessTreeWithoutProcessIsNoOp;
  end;

implementation

uses
  System.Diagnostics, System.Generics.Collections, System.IOUtils, System.JSON, System.Rtti, System.SysUtils,
  Winapi.Windows,
  Dak.Lsp.Context, Dak.Lsp.Protocol, Dak.Lsp.Transport, Dak.Types,
  Test.Support;

function ClientHandle(aClient: TLspJsonRpcClient; const aFieldName: string): THandle;
var
  lContext: TRttiContext;
  lField: TRttiField;
begin
  lContext := TRttiContext.Create;
  lField := lContext.GetType(TLspJsonRpcClient).GetField(aFieldName);
  Assert.IsNotNull(lField, 'Transport field not found: ' + aFieldName);
  Result := lField.GetValue(aClient).AsType<THandle>;
end;

procedure SetClientHandle(aClient: TLspJsonRpcClient; const aFieldName: string; aValue: THandle);
var
  lContext: TRttiContext;
  lField: TRttiField;
begin
  lContext := TRttiContext.Create;
  lField := lContext.GetType(TLspJsonRpcClient).GetField(aFieldName);
  Assert.IsNotNull(lField, 'Transport field not found: ' + aFieldName);
  lField.SetValue(aClient, TValue.From<THandle>(aValue));
end;

// Opens a published "<pid> <creation FILETIME>" identity by handle and proves
// by creation time that the PID was not reused.
function OpenPublishedIdentity(const aPath: string): THandle;
const
  cProcessQueryLimitedInformation = $1000;
var
  lCreated, lExited, lKernel, lUser: TFileTime;
  lFields: TArray<string>;
  lTimer: TStopwatch;
begin
  lTimer := TStopwatch.StartNew;
  while not TFile.Exists(aPath) and (lTimer.ElapsedMilliseconds < 5000) do
    Sleep(10);
  Assert.IsTrue(TFile.Exists(aPath), 'The child must publish its descendant: ' + aPath);
  lFields := TFile.ReadAllText(aPath).Trim.Split([' ']);
  Assert.AreEqual<Integer>(2, Length(lFields), 'Identity file must hold a PID and a creation time: ' + aPath);
  Result := OpenProcess(SYNCHRONIZE or PROCESS_TERMINATE or cProcessQueryLimitedInformation, False,
    StrToUInt(lFields[0]));
  Assert.IsTrue(Result <> 0, 'The published process must still run when opened: ' + SysErrorMessage(GetLastError));
  if not GetProcessTimes(Result, lCreated, lExited, lKernel, lUser) or
    (((UInt64(lCreated.dwHighDateTime) shl 32) or lCreated.dwLowDateTime) <> StrToUInt64(lFields[1])) then
  begin
    CloseHandle(Result);
    Assert.Fail('PID ' + lFields[0] + ' no longer identifies the published process');
  end;
end;

function WriteFrameFile(const aFrame: string): string;
begin
  Result := UniqueTempPath('lsp-frame') + '.bin';
  TFile.WriteAllText(Result, aFrame, TEncoding.ASCII);
end;

procedure TLspProtocolTests.ResponseValidation(aVariant: Integer);
const
  cInputs: array[0..5] of string = (
    '{"jsonrpc":"2.0","id":2,"result":null}',
    '{"jsonrpc":"2.0","id":1,"result":null}',
    '{"jsonrpc":"2.0","id":2}',
    '{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Method not found"}}',
    '{"jsonrpc":"1.0","id":2,"result":null}',
    '{"jsonrpc":"2.0","id":2,"result":null,"error":null}');
var
  lResponse: TJSONObject;
  lError: string;
begin
  lResponse := TJSONObject.ParseJSONValue(cInputs[aVariant]) as TJSONObject;
  try
    Assert.AreEqual(aVariant = 0, ValidateLspResponse(lResponse, 2, lError), lError);
    if aVariant <> 0 then
      Assert.IsNotEmpty(lError);
    if aVariant = 3 then
      Assert.IsTrue(lError.Contains('Method not found'), lError);
  finally
    lResponse.Free;
  end;
end;

procedure TLspProtocolTests.ServerErrorKeepsStageCodeAndMessage(aVariant: Integer);
const
  cStages: array[0..2] of string = ('initialize', 'probe initialize contextFile', 'definition request');
var
  lDetail: string;
  lResponse: TJSONObject;
  lText: string;
begin
  lResponse := TJSONObject.ParseJSONValue(
    '{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Method not found"}}') as TJSONObject;
  try
    // SendRequest rejects error responses through this validator; the runner
    // then names its stage with BuildLspStageError.
    Assert.IsFalse(ValidateLspResponse(lResponse, 2, lDetail));
    lText := BuildLspStageError(cStages[aVariant], lDetail);
    Assert.IsTrue(lText.StartsWith('DelphiLSP ' + cStages[aVariant] + ' failed'), lText);
    Assert.IsTrue(lText.Contains('-32601'), lText);
    Assert.IsTrue(lText.Contains('Method not found'), lText);
  finally
    lResponse.Free;
  end;
end;

procedure TLspProtocolTests.NativeTransportControlledStop;
var
  lClient: TLspJsonRpcClient;
  lExitCode: Cardinal;
  lGuard: IInterface;
  lError: string;
  lProcess: THandle;
begin
  lGuard := SetScopedEnvironmentVariable('DAK_TEST_IDLE_CHILD', '1');
  Assert.IsNotNull(lGuard);
  lClient := TLspJsonRpcClient.Create;
  try
    Assert.IsTrue(lClient.Start(ParamStr(0), '', RepoRoot, UniqueTempPath('lsp-stop-stderr'), '', lError), lError);
    lProcess := ClientHandle(lClient, 'fProcessHandle');
    Assert.AreEqual<Cardinal>(WAIT_TIMEOUT, WaitForSingleObject(lProcess, 0), 'Idle child must run before cleanup');
    Assert.IsTrue(lClient.StopProcessTree(lError), lError);
    // A no-op stop would leave the ten-second idle child running, and a natural
    // exit would report code 0; only job termination yields this state.
    Assert.AreEqual<Cardinal>(WAIT_OBJECT_0, WaitForSingleObject(lProcess, 1000),
      'Controlled stop must end the owned child');
    Assert.IsTrue(GetExitCodeProcess(lProcess, lExitCode), SysErrorMessage(GetLastError));
    Assert.AreEqual<Cardinal>(ERROR_PROCESS_ABORTED, lExitCode, 'Child must end through controlled termination');
    // Cleanup remains safe if destruction follows an explicit successful stop.
    Assert.IsTrue(lClient.StopProcessTree(lError), lError);
  finally
    lClient.Free;
  end;
end;

procedure TLspProtocolTests.NativeTransportDestructorStopsDescendants(aVariant: Integer);
var
  lClient: TLspJsonRpcClient;
  lGuard, lTimeoutGuard: IInterface;
  lPidPath, lError: string;
  lChild: THandle;
  lTimer: TStopwatch;
  lResponse: TJSONObject;
begin
  lPidPath := UniqueTempPath('lsp-descendant') + '.pid';
  lGuard := SetScopedEnvironmentVariable('DAK_TEST_DESCENDANT_PID', lPidPath);
  Assert.IsNotNull(lGuard);
  lTimeoutGuard := SetScopedEnvironmentVariable('DAK_LSP_REQUEST_TIMEOUT_MS', '250');
  Assert.IsNotNull(lTimeoutGuard);
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  lChild := 0;
  try
    Assert.IsTrue(lClient.Start(ParamStr(0), '', RepoRoot, lPidPath + '.log', '', lError), lError);
    lTimer := TStopwatch.StartNew;
    while not TFile.Exists(lPidPath) and (lTimer.ElapsedMilliseconds < 3000) do
      Sleep(10);
    Assert.IsTrue(TFile.Exists(lPidPath), 'Native child must launch its descendant');
    // Retain a handle before cleanup so PID reuse cannot disguise a survivor.
    lChild := OpenProcess(SYNCHRONIZE or PROCESS_TERMINATE, False,
      StrToUInt(TFile.ReadAllText(lPidPath).Trim));
    Assert.IsTrue(lChild <> 0, 'Descendant must be running before cleanup');
    case aVariant of
      0: FreeAndNil(lClient);
      1: Assert.IsTrue(lClient.StopProcessTree(lError), lError);
      2:
        begin
          Assert.IsFalse(lClient.SendRequest(1, 'initialize', '{}', lResponse, lError));
          Assert.IsTrue(lError.Contains('timed out'), lError);
        end;
    end;
    Assert.AreEqual<Cardinal>(WAIT_OBJECT_0, WaitForSingleObject(lChild, 1000),
      'Transport destruction must stop the owned process tree');
  finally
    lResponse.Free;
    lClient.Free;
    if lChild <> 0 then
    begin
      // Contain the failing RED reproduction without leaving a child behind.
      if WaitForSingleObject(lChild, 0) = WAIT_TIMEOUT then
      begin
        TerminateProcess(lChild, ERROR_PROCESS_ABORTED);
        WaitForSingleObject(lChild, 5000);
      end;
      CloseHandle(lChild);
    end;
  end;
end;

procedure TLspProtocolTests.NativeTransportRejectsMissingExecutable;
var
  lClient: TLspJsonRpcClient;
  lError: string;
begin
  lClient := TLspJsonRpcClient.Create;
  try
    Assert.IsFalse(lClient.Start(UniqueTempPath('missing-lsp') + '.exe', '', RepoRoot,
      UniqueTempPath('missing-lsp-stderr'), '', lError));
    Assert.IsTrue(lError.StartsWith('Failed to start DelphiLSP.exe:'), lError);
  finally
    lClient.Free;
  end;
end;

procedure TLspProtocolTests.NativeTransportBoundsUnresponsiveInput;
var
  lClient: TLspJsonRpcClient;
  lError: string;
  lGuard, lChildGuard: IInterface;
  lResponse: TJSONObject;
  lTimer: TStopwatch;
begin
  // A generic idle child exercises the input deadline without implementing
  // any server protocol or compiling an additional fixture executable.
  lGuard := SetScopedEnvironmentVariable('DAK_LSP_REQUEST_TIMEOUT_MS', '250');
  lChildGuard := SetScopedEnvironmentVariable('DAK_TEST_IDLE_CHILD', '1');
  Assert.IsNotNull(lGuard);
  Assert.IsNotNull(lChildGuard);
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  try
    Assert.IsTrue(lClient.Start(ParamStr(0), '', RepoRoot, UniqueTempPath('lsp-timeout-stderr'), '', lError), lError);
    lTimer := TStopwatch.StartNew;
    Assert.IsFalse(lClient.SendRequest(1, 'initialize', '{}', lResponse, lError));
    Assert.IsTrue(lError.Contains('timed out'), lError);
    Assert.IsTrue(lTimer.ElapsedMilliseconds < 5000, 'Transport deadline must remain bounded');
  finally
    lResponse.Free;
    lClient.Free;
  end;
end;

procedure TLspProtocolTests.NativeTransportRejectsMalformedFrames(aVariant: Integer);
const
  cValid = '{"jsonrpc":"2.0","id":1,"result":null}';
  cServerError = '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}';
var
  lClient: TLspJsonRpcClient;
  lDelayMs, lExit, lExpected, lFrame, lTimeoutMs, lError: string;
  lGuard: IInterface;
  lResponse: TJSONObject;
  lTimer: TStopwatch;
  i: Integer;
begin
  lDelayMs := '0';
  lExit := '0';
  lTimeoutMs := '3000';
  case aVariant of
    0:
      begin
        lFrame := 'X-Other: 1'#13#10#13#10 + cValid;
        lExpected := 'Missing Content-Length';
      end;
    1:
      begin
        lFrame := 'Content-Length: 1073741824'#13#10#13#10;
        lExpected := 'exceeds';
      end;
    2:
      begin
        lFrame := 'Content-Length: 5'#13#10#13#10'{abc}';
        lExpected := 'Invalid DelphiLSP JSON-RPC response';
      end;
    3:
      begin
        lFrame := 'Content-Length: 100'#13#10#13#10'{"jsonrpc"';
        lExit := '1';
        lExpected := 'Unexpected end of stream';
      end;
    4:
      begin
        // Each byte arrives well inside the per-read window; only an absolute
        // request deadline stops the trickle.
        lFrame := 'Content-Length: ' + IntToStr(Length(cValid)) + #13#10#13#10 + cValid;
        lDelayMs := '50';
        lTimeoutMs := '250';
        lExpected := 'timed out';
      end;
    5:
      begin
        lFrame := 'X-Long: ' + StringOfChar('a', 5000) + #13#10#13#10;
        lExpected := 'header line';
      end;
    6:
      begin
        lFrame := '';
        for i := 1 to 40 do
          lFrame := lFrame + 'X-Repeat: 1'#13#10;
        lFrame := lFrame + #13#10;
        lExpected := 'header lines';
      end;
  else
    lFrame := 'Content-Length: ' + IntToStr(Length(cServerError)) + #13#10#13#10 + cServerError;
    lExpected := 'Method not found';
  end;
  lGuard := SetScopedEnvironmentVariables(['DAK_TEST_STDOUT_FRAME', WriteFrameFile(lFrame),
    'DAK_TEST_STDOUT_DELAY_MS', lDelayMs, 'DAK_TEST_STDOUT_EXIT', lExit,
    'DAK_LSP_REQUEST_TIMEOUT_MS', lTimeoutMs]);
  Assert.IsNotNull(lGuard);
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  try
    Assert.IsTrue(lClient.Start(ParamStr(0), '', RepoRoot, UniqueTempPath('lsp-frame-stderr'), '', lError), lError);
    lTimer := TStopwatch.StartNew;
    Assert.IsFalse(lClient.SendRequest(1, 'initialize', '{}', lResponse, lError), 'Malformed frame must fail');
    Assert.IsNull(lResponse, 'A rejected response must not be returned');
    Assert.IsTrue(lError.Contains(lExpected), lError);
    if aVariant = 7 then
      Assert.IsTrue(lError.Contains('-32601'), lError);
    // The rejection must come from the frame check itself, not a later timeout.
    Assert.IsTrue(lTimer.ElapsedMilliseconds < 2500,
      Format('Rejection took %d ms: %s', [lTimer.ElapsedMilliseconds, lError]));
  finally
    lResponse.Free;
    lClient.Free;
  end;
end;

procedure TLspProtocolTests.NativeTransportBoundsInheritedStdoutAfterExit;
var
  lClient: TLspJsonRpcClient;
  lError: string;
  lGuard: IInterface;
  lResponse: TJSONObject;
  lTimer: TStopwatch;
begin
  // DelphiLSP agents inherit the stdout write end (checked 2026-09-30), so the
  // server's own exit does not close the pipe. The request deadline must hold.
  lGuard := SetScopedEnvironmentVariables(['DAK_TEST_STDOUT_HOLDER', '1', 'DAK_LSP_REQUEST_TIMEOUT_MS', '500']);
  Assert.IsNotNull(lGuard);
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  try
    Assert.IsTrue(lClient.Start(ParamStr(0), '', RepoRoot, UniqueTempPath('lsp-holder-stderr'), '', lError), lError);
    // Reach the hazardous state first: the direct child has exited while its
    // idle descendant still holds the pipe.
    Assert.AreEqual<Cardinal>(WAIT_OBJECT_0, WaitForSingleObject(ClientHandle(lClient, 'fProcessHandle'), 5000),
      'Holder child must exit after starting its descendant');
    lTimer := TStopwatch.StartNew;
    Assert.IsFalse(lClient.SendRequest(1, 'initialize', '{}', lResponse, lError));
    Assert.IsTrue(lError.Contains('timed out'), lError);
    Assert.IsTrue(lTimer.ElapsedMilliseconds < 5000,
      Format('Read blocked for %d ms: %s', [lTimer.ElapsedMilliseconds, lError]));
  finally
    lResponse.Free;
    lClient.Free;
  end;
end;

procedure TLspProtocolTests.NativeTransportBoundsUndrainedStdinWrite(aVariant: Integer);
const
  cTimeoutMs = 500;
  cPayloadBytes = 4 * 1024 * 1024;
  cStages: array[0..1] of string = ('writing request', 'writing notification');
var
  lClient: TLspJsonRpcClient;
  lDescendant: THandle;
  lElapsedMs: Int64;
  lError, lIdentityPath, lParams: string;
  lSent: Boolean;
  lExitCode, lFlags, lInSize, lOutSize: Cardinal;
  lGuard: IInterface;
  lResponse: TJSONObject;
  lTimer: TStopwatch;
begin
  // DelphiLSP agents inherit stdin as well as stdout. Here the direct child
  // exits and leaves an idle descendant holding the stdin read end: nobody
  // drains the pipe, and it never breaks, so only the deadline ends the write.
  lIdentityPath := UniqueTempPath('lsp-stdin-holder') + '.id';
  lGuard := SetScopedEnvironmentVariables(['DAK_TEST_STDIN_HOLDER', lIdentityPath,
    'DAK_LSP_REQUEST_TIMEOUT_MS', IntToStr(cTimeoutMs)]);
  Assert.IsNotNull(lGuard);
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  lDescendant := 0;
  try
    Assert.IsTrue(lClient.Start(ParamStr(0), '', RepoRoot, UniqueTempPath('lsp-stdin-stderr'), '', lError), lError);
    lDescendant := OpenPublishedIdentity(lIdentityPath);
    // The payload must exceed the pipe buffers many times over, or the write
    // would complete into the buffer and the test would pass for the wrong reason.
    lFlags := 0;
    lOutSize := 0;
    lInSize := 0;
    Assert.IsTrue(GetNamedPipeInfo(ClientHandle(lClient, 'fInputHandle'), lFlags, @lOutSize, @lInSize, nil),
      SysErrorMessage(GetLastError));
    Assert.IsTrue(UInt64(cPayloadBytes) > 4 * (UInt64(lOutSize) + lInSize),
      Format('Payload must exceed the pipe buffers (out %d, in %d)', [lOutSize, lInSize]));
    lParams := '{"pad":"' + StringOfChar('x', cPayloadBytes) + '"}';
    lTimer := TStopwatch.StartNew;
    if aVariant = 0 then
      lSent := lClient.SendRequest(1, 'initialize', lParams, lResponse, lError)
    else
      lSent := lClient.SendNotification('textDocument/didOpen', lParams, lError);
    lElapsedMs := lTimer.ElapsedMilliseconds;
    Assert.IsFalse(lSent, 'An undrained write must not succeed');
    Assert.IsTrue(lError.Contains('timed out') and lError.Contains(cStages[aVariant]), lError);
    Assert.IsFalse(lError.Contains('Cleanup also failed'), lError);
    // The deadline itself ends the write: not an early pipe error, not a hang.
    Assert.IsTrue((lElapsedMs >= cTimeoutMs - 50) and (lElapsedMs < cTimeoutMs + 2000),
      Format('Write ended after %d ms: %s', [lElapsedMs, lError]));
    // Checked before the client is freed: the failure path, not the destructor,
    // stopped the owned tree.
    Assert.AreEqual<Cardinal>(WAIT_OBJECT_0, WaitForSingleObject(lDescendant, 1000),
      'The timed-out write must stop the owned process tree');
    Assert.IsTrue(GetExitCodeProcess(lDescendant, lExitCode), SysErrorMessage(GetLastError));
    Assert.AreEqual<Cardinal>(ERROR_PROCESS_ABORTED, lExitCode, 'The descendant must end through controlled cleanup');
  finally
    lResponse.Free;
    lClient.Free;
    if lDescendant <> 0 then
    begin
      // Contain the failing RED reproduction without leaving a descendant behind.
      if WaitForSingleObject(lDescendant, 0) = WAIT_TIMEOUT then
      begin
        TerminateProcess(lDescendant, ERROR_PROCESS_ABORTED);
        WaitForSingleObject(lDescendant, 5000);
      end;
      CloseHandle(lDescendant);
    end;
  end;
end;

procedure TLspProtocolTests.NativeTransportWritesLargeRequestWhole;
const
  cPayloadChars = 2 * 1024 * 1024;
var
  lBody, lError, lParams: string;
  lClient: TLspJsonRpcClient;
  lGuard: IInterface;
  lResponse: TJSONObject;
begin
  // The non-blocking write goes out in many partial chunks to a reader that
  // drains stdin. The child answers with the body byte count it received.
  lGuard := SetScopedEnvironmentVariables(['DAK_TEST_STDIN_DRAIN', '1', 'DAK_LSP_REQUEST_TIMEOUT_MS', '20000']);
  Assert.IsNotNull(lGuard);
  // A two-byte UTF-8 character keeps the byte count distinct from the char count.
  lParams := '{"pad":"' + StringOfChar(#$017C, cPayloadChars) + '"}';
  lBody := '{"jsonrpc":"2.0","id":1,"method":"initialize","params":' + lParams + '}';
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  try
    Assert.IsTrue(lClient.Start(ParamStr(0), '', RepoRoot, UniqueTempPath('lsp-drain-stderr'), '', lError), lError);
    Assert.IsTrue(lClient.SendRequest(1, 'initialize', lParams, lResponse, lError), lError);
    Assert.AreEqual<Int64>(TEncoding.UTF8.GetByteCount(lBody), lResponse.GetValue<Int64>('result'),
      'The server must receive the whole request body');
    Assert.IsTrue(lClient.StopProcessTree(lError), lError);
  finally
    lResponse.Free;
    lClient.Free;
  end;
end;

procedure TLspProtocolTests.NativeTransportReportsCleanupFailure(aVariant: Integer);
var
  lBogus: THandle;
  lClient: TLspJsonRpcClient;
  lError, lText: string;
  lGuard: IInterface;
  lJob, lJobCopy: THandle;
  lResponse: TJSONObject;
begin
  lGuard := SetScopedEnvironmentVariables(['DAK_TEST_IDLE_CHILD', '1', 'DAK_LSP_REQUEST_TIMEOUT_MS', '250']);
  Assert.IsNotNull(lGuard);
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  lJobCopy := 0;
  try
    Assert.IsTrue(lClient.Start(ParamStr(0), '', RepoRoot, UniqueTempPath('lsp-cleanup-stderr'), '', lError), lError);
    // Fault injection: replace the owned job with a non-job handle so that job
    // termination really fails. The test keeps a duplicate, which keeps the child
    // contained, and terminates it afterwards.
    lJob := ClientHandle(lClient, 'fJobHandle');
    Assert.IsTrue(DuplicateHandle(GetCurrentProcess, lJob, GetCurrentProcess, @lJobCopy, 0, False,
      DUPLICATE_SAME_ACCESS), SysErrorMessage(GetLastError));
    lBogus := CreateEvent(nil, True, False, nil);
    Assert.IsTrue(lBogus <> 0, SysErrorMessage(GetLastError));
    SetClientHandle(lClient, 'fJobHandle', lBogus);
    CloseHandle(lJob);
    case aVariant of
      0:
        begin
          Assert.IsFalse(lClient.StopProcessTree(lText));
        end;
      1:
        lText := lClient.StopAfterFailure('DelphiLSP initialize failed: injected');
    else
      Assert.IsFalse(lClient.SendRequest(1, 'initialize', '{}', lResponse, lText));
      Assert.IsTrue(lText.Contains('timed out'), lText);
    end;
    Assert.IsTrue(lText.Contains('Failed to terminate the owned DelphiLSP process tree'), lText);
    if aVariant = 1 then
      Assert.IsTrue(lText.StartsWith('DelphiLSP initialize failed: injected'), lText);
  finally
    lResponse.Free;
    lClient.Free;
    if lJobCopy <> 0 then
    begin
      TerminateJobObject(lJobCopy, ERROR_PROCESS_ABORTED);
      CloseHandle(lJobCopy);
    end;
  end;
end;

procedure TLspProtocolTests.StopProcessTreeWithoutProcessIsNoOp;
var
  lClient: TLspJsonRpcClient;
  lError: string;
begin
  lClient := TLspJsonRpcClient.Create;
  try
    Assert.IsTrue(lClient.StopProcessTree(lError), lError);
    Assert.AreEqual('', lError);
    Assert.AreEqual('prior failure', lClient.StopAfterFailure('prior failure'));
  finally
    lClient.Free;
  end;
end;

function ConvertResponse(const aOptions: TAppOptions; const aResultJson: string): TJSONObject;
var
  lError: string;
  lResponse: TJSONObject;
  lText: string;
begin
  lResponse := TJSONObject.ParseJSONValue('{"result":' + aResultJson + '}') as TJSONObject;
  try
    Assert.IsTrue(TryBuildOperationResultText(aOptions, 'C:\repo\Unit1.pas', lResponse, lText, lError), lError);
    Result := TJSONObject.ParseJSONValue(lText) as TJSONObject;
  finally
    lResponse.Free;
  end;
end;

procedure TLspProtocolTests.DefinitionCoordinatesAndUris(aVariant: Integer);
var
  lOptions: TAppOptions;
  lResult, lLocation: TJSONObject;
  lUri, lExpected: string;
begin
  lOptions := Default(TAppOptions);
  lOptions.fLspOperation := TLspOperation.loDefinition;
  lUri := 'file:///C:/repo/Unit1.pas';
  lExpected := 'C:\repo\Unit1.pas';
  case aVariant of
    1:
      begin
        lUri := 'file://localhost/C:/repo/A+B%20Unit.pas';
        lExpected := 'C:\repo\A+B Unit.pas';
      end;
    2:
      begin
        lUri := 'file://C:/repo/Foo%2BBar.pas';
        lExpected := 'C:\repo\Foo+Bar.pas';
      end;
    3:
      begin
        lUri := 'file://fileserver/share/Foo%2BBar.pas';
        lExpected := '\\fileserver\share\Foo+Bar.pas';
      end;
  end;
  if aVariant = 3 then
    // LocationLink: targetRange wins over targetSelectionRange.
    lResult := ConvertResponse(lOptions, '[{"targetUri":"' + lUri +
      '","targetRange":{"start":{"line":12,"character":2},"end":{"line":13,"character":4}},' +
      '"targetSelectionRange":{"start":{"line":40,"character":1},"end":{"line":40,"character":3}}}]')
  else
    lResult := ConvertResponse(lOptions, '[{"uri":"' + lUri +
      '","range":{"start":{"line":12,"character":2},"end":{"line":13,"character":4}}}]');
  try
    Assert.AreEqual(1, lResult.GetValue<TJSONArray>('locations').Count);
    lLocation := lResult.GetValue<TJSONArray>('locations').Items[0] as TJSONObject;
    Assert.AreEqual(lExpected, lLocation.GetValue<string>('file'));
    Assert.AreEqual(13, lLocation.GetValue<Integer>('line'));
    Assert.AreEqual(3, lLocation.GetValue<Integer>('col'));
    Assert.AreEqual(14, lLocation.GetValue<Integer>('endLine'));
    Assert.AreEqual(5, lLocation.GetValue<Integer>('endCol'));
  finally
    lResult.Free;
  end;
end;

procedure TLspProtocolTests.RequestUsesZeroBasedPosition(aVariant: Integer);
var
  lOptions: TAppOptions;
  lParams, lPosition: TJSONObject;
begin
  lOptions := Default(TAppOptions);
  lOptions.fLspOperation := TLspOperation.loDefinition;
  if aVariant = 1 then
    lOptions.fLspOperation := TLspOperation.loHover;
  lOptions.fLspLine := 8;
  lOptions.fLspCol := 21;
  lParams := TJSONObject.ParseJSONValue(BuildRequestParams(lOptions, 'file:///C:/repo/Unit1.pas')) as TJSONObject;
  try
    lPosition := lParams.GetValue<TJSONObject>('position');
    Assert.AreEqual(7, lPosition.GetValue<Integer>('line'));
    Assert.AreEqual(20, lPosition.GetValue<Integer>('character'));
    Assert.AreEqual('file:///C:/repo/Unit1.pas', lParams.GetValue<TJSONObject>('textDocument').GetValue<string>('uri'));
  finally
    lParams.Free;
  end;
end;

procedure TLspProtocolTests.SymbolsRequestHasNoPosition;
var
  lOptions: TAppOptions;
  lParams: TJSONObject;
begin
  lOptions := Default(TAppOptions);
  lOptions.fLspOperation := TLspOperation.loSymbols;
  lParams := TJSONObject.ParseJSONValue(BuildRequestParams(lOptions, 'file:///C:/repo/Unit1.pas')) as TJSONObject;
  try
    Assert.IsNull(lParams.Values['position']);
    Assert.AreEqual('file:///C:/repo/Unit1.pas', lParams.GetValue<TJSONObject>('textDocument').GetValue<string>('uri'));
  finally
    lParams.Free;
  end;
end;

procedure TLspProtocolTests.HoverPreservesTextAndRange(aVariant: Integer);
var
  lOptions: TAppOptions;
  lResult, lRange: TJSONObject;
  lInput, lText: string;
  lContext: TLspContext;
begin
  lOptions := Default(TAppOptions);
  lOptions.fLspOperation := TLspOperation.loHover;
  lInput := 'null';
  if aVariant = 0 then
    lInput := '{"contents":{"kind":"markdown","value":"**Integer**"},' +
      '"range":{"start":{"line":4,"character":1},"end":{"line":4,"character":8}}}';
  // Raw result captured from DelphiLSP 23.0 for Unit1.pas 8:21 (2026-10-01).
  if aVariant = 2 then
    lInput := '{"contents":{"kind":"markdown","value":"[Unit1.pas:8](file:///F%3A/projects/MaxLogic/DelphiAiKit/' +
      'tests/fixtures/LspProjectFixture/Unit1.pas#8)\r\n\r\n```\r\nclass procedure TFixtureType.Run\r\n```\r\n\r\n"}}';
  lResult := ConvertResponse(lOptions, lInput);
  try
    if aVariant = 2 then
    begin
      Assert.AreEqual('[Unit1.pas:8](file:///F%3A/projects/MaxLogic/DelphiAiKit/' +
        'tests/fixtures/LspProjectFixture/Unit1.pas#8)'#13#10#13#10'```'#13#10'class procedure TFixtureType.Run' +
        #13#10'```'#13#10#13#10, lResult.GetValue<string>('contentsText'));
      Assert.AreEqual(lResult.GetValue<string>('contentsText'), lResult.GetValue<string>('contentsMarkdown'));
      Assert.IsNull(lResult.Values['isEmpty'], 'Vendor hover content is not empty');
      Assert.IsNull(lResult.Values['range'], 'DelphiLSP 23 sends no hover range');
    end else if aVariant = 0 then
    begin
      Assert.AreEqual('**Integer**', lResult.GetValue<string>('contentsText'));
      Assert.AreEqual('**Integer**', lResult.GetValue<string>('contentsMarkdown'));
      lRange := lResult.GetValue<TJSONObject>('range');
      Assert.AreEqual(5, lRange.GetValue<Integer>('line'));
      Assert.AreEqual(2, lRange.GetValue<Integer>('col'));
      lContext := Default(TLspContext);
      lText := BuildOperationText(lOptions, lContext, '', 'hover', 'C:\repo\Unit1.pas', lResult.ToJSON,
        ['DelphiLSP compiler DLL not resolved (test reason); hover may return no content.']);
      Assert.IsTrue(lText.Contains('DelphiLSP compiler DLL not resolved (test reason)'), lText);
      // Compact hover text: heading, contents and one-based range, no envelope.
      Assert.IsTrue(lText.StartsWith('Hover:'), lText);
      Assert.IsTrue(lText.Contains('**Integer**'), lText);
      Assert.IsTrue(lText.Contains('Range: 5:2-5:9'), lText);
      Assert.IsFalse(lText.Contains('contentsText'), lText);
      Assert.IsFalse(lText.Contains('operation:'), lText);
    end else begin
      Assert.AreEqual('', lResult.GetValue<string>('contentsText'));
      Assert.IsTrue(lResult.GetValue<Boolean>('isEmpty'));
      Assert.IsNull(lResult.Values['range'], 'An empty hover has no range');
    end;
  finally
    lResult.Free;
  end;
end;

procedure TLspProtocolTests.SymbolsFlattenThenFilter(aVariant: Integer);
const
  cRange = '"range":{"start":{"line":1,"character":0},"end":{"line":9,"character":0}}';
var
  lOptions: TAppOptions;
  lResult, lChild: TJSONObject;
  lSymbols: TJSONArray;
begin
  lOptions := Default(TAppOptions);
  lOptions.fLspOperation := TLspOperation.loSymbols;
  if aVariant = 1 then
  begin
    lOptions.fLspQuery := 'Run';
    lOptions.fLspLimit := 1;
  end else if aVariant = 2 then
    lOptions.fLspQuery := 'Missing';
  lResult := ConvertResponse(lOptions, '[{"name":"TExample","kind":5,' + cRange +
    ',"children":[{"name":"Run","kind":6,' + cRange + '}]}]');
  try
    lSymbols := lResult.GetValue<TJSONArray>('symbols');
    case aVariant of
      0: Assert.AreEqual(2, lSymbols.Count);
      1: Assert.AreEqual(1, lSymbols.Count);
      2: Assert.AreEqual(0, lSymbols.Count);
    end;
    if aVariant = 1 then
    begin
      lChild := lSymbols.Items[0] as TJSONObject;
      Assert.AreEqual('Run', lChild.GetValue<string>('name'));
      Assert.AreEqual('TExample', lChild.GetValue<string>('containerName'));
      Assert.AreEqual('C:\repo\Unit1.pas', lChild.GetValue<string>('file'));
    end;
  finally
    lResult.Free;
  end;
end;

procedure TLspProtocolTests.SymbolsUseSelectionRangeAcrossNesting;
var
  lOptions: TAppOptions;
  lResult, lSymbol: TJSONObject;
  lSymbols: TJSONArray;
begin
  lOptions := Default(TAppOptions);
  lOptions.fLspOperation := TLspOperation.loSymbols;
  lResult := ConvertResponse(lOptions, '[{"name":"TFixtureType","kind":5,' +
    '"range":{"start":{"line":1,"character":0},"end":{"line":20,"character":0}},' +
    '"selectionRange":{"start":{"line":2,"character":4},"end":{"line":2,"character":16}},"children":[' +
    '{"name":"CreateFixture","kind":6,"range":{"start":{"line":4,"character":2},"end":{"line":6,"character":5}},' +
    '"selectionRange":{"start":{"line":4,"character":10},"end":{"line":4,"character":23}},"children":[' +
    '{"name":"lFixtureValue","kind":13,"range":{"start":{"line":5,"character":4},"end":{"line":5,"character":20}},' +
    '"selectionRange":{"start":{"line":5,"character":8},"end":{"line":5,"character":21}}}]}]}]');
  try
    lSymbols := lResult.GetValue<TJSONArray>('symbols');
    Assert.AreEqual(3, lSymbols.Count);
    lSymbol := lSymbols.Items[0] as TJSONObject;
    Assert.AreEqual('TFixtureType', lSymbol.GetValue<string>('name'));
    Assert.AreEqual('', lSymbol.GetValue<string>('containerName'));
    Assert.AreEqual(3, lSymbol.GetValue<Integer>('line'), 'selectionRange line, not range line');
    Assert.AreEqual(5, lSymbol.GetValue<Integer>('col'), 'selectionRange column, not range column');
    lSymbol := lSymbols.Items[1] as TJSONObject;
    Assert.AreEqual('CreateFixture', lSymbol.GetValue<string>('name'));
    Assert.AreEqual('TFixtureType', lSymbol.GetValue<string>('containerName'));
    lSymbol := lSymbols.Items[2] as TJSONObject;
    Assert.AreEqual('lFixtureValue', lSymbol.GetValue<string>('name'));
    Assert.AreEqual('CreateFixture', lSymbol.GetValue<string>('containerName'));
    Assert.AreEqual(6, lSymbol.GetValue<Integer>('line'));
    Assert.AreEqual(9, lSymbol.GetValue<Integer>('col'));
  finally
    lResult.Free;
  end;
end;

procedure TLspProtocolTests.EmptyResultShapesStayValid(aVariant: Integer);
const
  cOperations: array[0..6] of TLspOperation = (TLspOperation.loDefinition, TLspOperation.loDefinition,
    TLspOperation.loSymbols, TLspOperation.loSymbols, TLspOperation.loHover, TLspOperation.loHover,
    TLspOperation.loHover);
  cInputs: array[0..6] of string = ('null', '[]', 'null', '[]', 'null', '{"contents":""}', '{"contents":[]}');
var
  lOptions: TAppOptions;
  lResult: TJSONObject;
begin
  lOptions := Default(TAppOptions);
  lOptions.fLspOperation := cOperations[aVariant];
  lResult := ConvertResponse(lOptions, cInputs[aVariant]);
  try
    case lOptions.fLspOperation of
      TLspOperation.loDefinition:
        Assert.AreEqual(0, lResult.GetValue<TJSONArray>('locations').Count);
      TLspOperation.loSymbols:
        Assert.AreEqual(0, lResult.GetValue<TJSONArray>('symbols').Count);
    else
      Assert.IsTrue(lResult.GetValue<Boolean>('isEmpty'), lResult.ToJSON);
    end;
  finally
    lResult.Free;
  end;
end;

procedure TLspProtocolTests.MalformedResultIsFailure(aVariant: Integer);
const
  cOperations: array[0..8] of TLspOperation = (TLspOperation.loDefinition, TLspOperation.loDefinition,
    TLspOperation.loDefinition, TLspOperation.loSymbols, TLspOperation.loSymbols, TLspOperation.loSymbols,
    TLspOperation.loHover, TLspOperation.loHover, TLspOperation.loHover);
  cNames: array[0..8] of string = ('definition', 'definition', 'definition', 'symbols', 'symbols', 'symbols',
    'hover', 'hover', 'hover');
  cInputs: array[0..8] of string = ('{"foo":1}', '"x"', '[{"uri":"file:///C:/repo/Unit1.pas"}]', '"x"',
    '{"name":"A"}', '[1]', '42', '{"range":null}', '{"contents":42}');
var
  lError: string;
  lOptions: TAppOptions;
  lResponse: TJSONObject;
  lText: string;
begin
  lOptions := Default(TAppOptions);
  lOptions.fLspOperation := cOperations[aVariant];
  lResponse := TJSONObject.ParseJSONValue('{"result":' + cInputs[aVariant] + '}') as TJSONObject;
  try
    Assert.IsFalse(TryBuildOperationResultText(lOptions, 'C:\repo\Unit1.pas', lResponse, lText, lError),
      'A wrong-type result must not become an empty answer: ' + lText);
    Assert.IsTrue(lError.Contains(cNames[aVariant]), lError);
    Assert.IsTrue(lError.Contains('malformed result'), lError);
  finally
    lResponse.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspProtocolTests);

end.
