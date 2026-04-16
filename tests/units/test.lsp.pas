unit Test.Lsp;

interface

uses
  DUnitX.TestFramework,
  Dak.Lsp.Context;

type
  [TestFixture]
  TLspContextTests = class
  private
    function ArrayContainsValue(const aValues: TArray<string>; const aExpected: string): Boolean;
    function CreateFixtureProject(const aScenarioName: string; const aProjectDefine: string;
      const aDefaultDelphiVersion: string = ''): string;
    function PrepareResolvedContext(const aScenarioName: string; out aContext: TLspContext): string;
    procedure WriteEnvOptionsFile(const aPath, aLibraryPath, aSearchPath, aDefineValue: string);
    procedure WriteRsVarsFile(const aPath, aBdsRoot: string);
  public
    [Test]
    procedure LspUsesDakIniDelphiVersionFallback;
    [Test]
    procedure LspUsesRsvarsAndEnvOptionsOverrides;
    [Test]
    procedure LspHardFailsWhenRealDelphiContextCannotBeBuilt;
    [Test]
    procedure LspWritesGeneratedContextUnderDakWorkspace;
    [Test]
    procedure LspDoesNotWriteContextBesideSourceProject;
    [Test]
    procedure LspReportsWorkspaceWriteFailureCleanly;
  end;

  [TestFixture]
  TLspFixtureTests = class
  private
    function CreateScriptFile(const aScenarioName, aScriptJson: string): string;
  public
    [Test]
    procedure FakeServerSupportsInitializeAndShutdown;
    [Test]
    procedure FakeServerReturnsScriptedDefinitionAndHoverPayloads;
    [Test]
    procedure FakeServerCanSimulateEmptyAndErrorResponses;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows,
  Dak.Types,
  Test.Support;

procedure WriteUtf8File(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.UTF8);
end;

procedure WriteAsciiFile(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.ASCII);
end;

var
  GFakeLspBuilt: Boolean = False;
  GFakeLspExePath: string = '';

function CmdExePath: string;
begin
  Result := GetEnvironmentVariable('ComSpec');
  if Result = '' then
    Result := 'C:\Windows\System32\cmd.exe';
end;

function FakeLspFixtureDir: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\LspFixture');
end;

function FakeLspProjectPath: string;
begin
  Result := TPath.Combine(FakeLspFixtureDir, 'FakeDelphiLsp.dproj');
end;

function FakeLspExePath: string;
begin
  Result := TPath.Combine(FakeLspFixtureDir, 'bin\FakeDelphiLsp.exe');
end;

procedure EnsureFakeLspFixtureBuilt;
var
  lArgs: string;
  lBat: string;
  lCmdArgs: string;
  lExit: Cardinal;
  lLog: string;
begin
  GFakeLspExePath := FakeLspExePath;
  if GFakeLspBuilt and FileExists(GFakeLspExePath) then
    Exit;
  if FileExists(GFakeLspExePath) then
  begin
    GFakeLspBuilt := True;
    Exit;
  end;

  lBat := TPath.Combine(RepoRoot, 'build-delphi.bat');
  lArgs := QuoteArg(FakeLspProjectPath) + ' -config Release -platform Win32 -ver 23';
  lCmdArgs := '/C "call ' + QuoteArg(lBat) + ' ' + lArgs + '"';
  lLog := TPath.Combine(TempRoot, 'build-fake-delphi-lsp.log');

  if not RunProcess(CmdExePath, lCmdArgs, RepoRoot, lLog, lExit) then
    Assert.Fail('Failed to start FakeDelphiLsp build.');
  if lExit <> 0 then
    Assert.Fail('FakeDelphiLsp build failed, exit=' + lExit.ToString + '. See: ' + lLog);
  if not FileExists(GFakeLspExePath) then
    Assert.Fail('FakeDelphiLsp.exe missing after build: ' + GFakeLspExePath);
  GFakeLspBuilt := True;
end;

type
  TLspJsonRpcClient = class
  private
    fInput: THandleStream;
    fOutput: THandleStream;
    fProcessHandle: THandle;
    fThreadHandle: THandle;
    function ReadLine(out aLine: string; out aError: string): Boolean;
    function ReadMessage(out aBody: string; out aError: string): Boolean;
    function WriteMessage(const aBody: string; out aError: string): Boolean;
  public
    destructor Destroy; override;
    function Start(const aExePath, aArguments, aWorkDir: string; out aError: string): Boolean;
    function SendNotification(const aMethod, aParamsJson: string; out aError: string): Boolean;
    function SendRequest(aId: Integer; const aMethod, aParamsJson: string; out aResponse: TJSONObject;
      out aError: string): Boolean;
    function ShutdownAndExit(out aError: string): Boolean;
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
      lCount := fOutput.Read(lByte, 1);
      if lCount <> 1 then
      begin
        aError := 'Unexpected end of stream while reading LSP header.';
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
    aError := 'Missing Content-Length header in LSP response.';
    Exit(False);
  end;
  SetLength(lBodyBytes, lContentLength);
  lOffset := 0;
  while lOffset < lContentLength do
  begin
    lRead := fOutput.Read(lBodyBytes[lOffset], lContentLength - lOffset);
    if lRead <= 0 then
    begin
      aError := 'Unexpected end of stream while reading LSP body.';
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
      aError := 'Failed to write LSP message: ' + E.Message;
    end;
  end;
end;

destructor TLspJsonRpcClient.Destroy;
begin
  fInput.Free;
  fOutput.Free;
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

function TLspJsonRpcClient.Start(const aExePath, aArguments, aWorkDir: string; out aError: string): Boolean;
var
  lChildStdInRead: THandle;
  lChildStdInWrite: THandle;
  lChildStdOutRead: THandle;
  lChildStdOutWrite: THandle;
  lCmdLine: string;
  lLastError: Cardinal;
  lPi: TProcessInformation;
  lSa: TSecurityAttributes;
  lSi: TStartupInfo;
begin
  Result := False;
  aError := '';
  lChildStdInRead := 0;
  lChildStdInWrite := 0;
  lChildStdOutRead := 0;
  lChildStdOutWrite := 0;

  FillChar(lSa, SizeOf(lSa), 0);
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;

  if not CreatePipe(lChildStdOutRead, lChildStdOutWrite, @lSa, 0) then
  begin
    aError := 'Failed to create fake LSP stdout pipe.';
    Exit(False);
  end;
  if not CreatePipe(lChildStdInRead, lChildStdInWrite, @lSa, 0) then
  begin
    aError := 'Failed to create fake LSP stdin pipe.';
    CloseHandle(lChildStdOutRead);
    CloseHandle(lChildStdOutWrite);
    Exit(False);
  end;

  try
    SetHandleInformation(lChildStdOutRead, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(lChildStdInWrite, HANDLE_FLAG_INHERIT, 0);

    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES;
    lSi.hStdInput := lChildStdInRead;
    lSi.hStdOutput := lChildStdOutWrite;
    lSi.hStdError := GetStdHandle(STD_ERROR_HANDLE);

    FillChar(lPi, SizeOf(lPi), 0);
    lCmdLine := QuoteArg(aExePath);
    if aArguments <> '' then
      lCmdLine := lCmdLine + ' ' + aArguments;
    UniqueString(lCmdLine);

    if not CreateProcess(PChar(aExePath), PChar(lCmdLine), nil, nil, True, CREATE_NO_WINDOW, nil, PChar(aWorkDir), lSi, lPi) then
    begin
      lLastError := GetLastError;
      aError := 'Failed to start fake LSP server: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;

    CloseHandle(lChildStdInRead);
    lChildStdInRead := 0;
    CloseHandle(lChildStdOutWrite);
    lChildStdOutWrite := 0;

    fInput := THandleStream.Create(lChildStdInWrite);
    fOutput := THandleStream.Create(lChildStdOutRead);
    fProcessHandle := lPi.hProcess;
    fThreadHandle := lPi.hThread;
    Result := True;
  finally
    if lChildStdInRead <> 0 then
      CloseHandle(lChildStdInRead);
    if lChildStdOutWrite <> 0 then
      CloseHandle(lChildStdOutWrite);
    if (not Result) then
    begin
      if lChildStdInWrite <> 0 then
        CloseHandle(lChildStdInWrite);
      if lChildStdOutRead <> 0 then
        CloseHandle(lChildStdOutRead);
    end;
  end;
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
  lParamsJson: string;
  lResponseText: string;
  lValue: TJSONValue;
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
  lValue := TJSONObject.ParseJSONValue(lResponseText);
  if not (lValue is TJSONObject) then
  begin
    lValue.Free;
    aError := 'Invalid JSON-RPC response: ' + lResponseText;
    Exit(False);
  end;
  aResponse := lValue as TJSONObject;
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
    aError := 'Fake LSP server did not exit cleanly.';
    Exit(False);
  end;
  Result := True;
end;

function TLspContextTests.ArrayContainsValue(const aValues: TArray<string>; const aExpected: string): Boolean;
var
  lValue: string;
begin
  Result := False;
  for lValue in aValues do
  begin
    if SameText(lValue, aExpected) then
      Exit(True);
  end;
end;

function TLspContextTests.CreateFixtureProject(const aScenarioName: string; const aProjectDefine: string;
  const aDefaultDelphiVersion: string = ''): string;
var
  lDprojPath: string;
  lRoot: string;
begin
  EnsureTempClean;
  lRoot := TPath.Combine(TempRoot, aScenarioName);
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  lDprojPath := TPath.Combine(lRoot, 'LspFixture.dproj');
  WriteUtf8File(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>LspFixture.dpr</MainSource>' + sLineBreak +
    '    <DCC_Define>' + aProjectDefine + ';$(DCC_Define)</DCC_Define>' + sLineBreak +
    '    <DCC_UnitSearchPath>src;$(BDS)\Source;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <DCCReference Include="Unit1.pas"/>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(TPath.ChangeExtension(lDprojPath, '.dpr'),
    'program LspFixture;' + sLineBreak +
    sLineBreak +
    'uses' + sLineBreak +
    '  Unit1 in ''Unit1.pas'';' + sLineBreak +
    sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);
  WriteUtf8File(TPath.Combine(lRoot, 'Unit1.pas'),
    'unit Unit1;' + sLineBreak +
    sLineBreak +
    'interface' + sLineBreak +
    sLineBreak +
    'procedure TouchUnit1;' + sLineBreak +
    sLineBreak +
    'implementation' + sLineBreak +
    sLineBreak +
    'procedure TouchUnit1;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'end.' + sLineBreak);
  TDirectory.CreateDirectory(TPath.Combine(lRoot, 'src'));

  if aDefaultDelphiVersion <> '' then
  begin
    WriteAsciiFile(TPath.Combine(lRoot, 'dak.ini'),
      '[Build]' + sLineBreak +
      'DelphiVersion=' + aDefaultDelphiVersion + sLineBreak);
  end;

  Result := lDprojPath;
end;

function TLspContextTests.PrepareResolvedContext(const aScenarioName: string; out aContext: TLspContext): string;
var
  lBdsRoot: string;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lEnvSearchDir: string;
  lError: string;
  lLibraryDir: string;
  lOptions: TAppOptions;
  lRsVarsPath: string;
begin
  lDprojPath := CreateFixtureProject(aScenarioName, 'PROJECT_DEFINE', '99.9');
  lBdsRoot := TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds');
  lLibraryDir := TPath.Combine(ExtractFilePath(lDprojPath), 'IdeLibrary');
  lEnvSearchDir := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvSearch');
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'Source'));
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'lib'));
  TDirectory.CreateDirectory(lLibraryDir);
  TDirectory.CreateDirectory(lEnvSearchDir);
  lRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
  lEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj');
  WriteRsVarsFile(lRsVarsPath, lBdsRoot);
  WriteEnvOptionsFile(lEnvOptionsPath, lLibraryDir, lEnvSearchDir, 'ENV_DEFINE');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fPlatform := 'Win32';
  lOptions.fConfig := 'Debug';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;
  lOptions.fEnvOptionsPath := lEnvOptionsPath;
  lOptions.fHasEnvOptionsPath := True;

  lError := '';
  Assert.IsTrue(TryBuildStrictLspContext(lOptions, aContext, lError),
    'Expected strict lsp context to resolve. Error: ' + lError);
  Result := lDprojPath;
end;

procedure TLspContextTests.WriteEnvOptionsFile(const aPath, aLibraryPath, aSearchPath, aDefineValue: string);
begin
  WriteUtf8File(aPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <DelphiLibraryPath>' + aLibraryPath + '</DelphiLibraryPath>' + sLineBreak +
    '    <DCC_UnitSearchPath>' + aSearchPath + '</DCC_UnitSearchPath>' + sLineBreak +
    '    <DCC_Define>' + aDefineValue + '</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
end;

procedure TLspContextTests.WriteRsVarsFile(const aPath, aBdsRoot: string);
begin
  WriteAsciiFile(aPath,
    '@echo off' + sLineBreak +
    'set BDS=' + aBdsRoot + sLineBreak +
    'set BDSLIB=' + TPath.Combine(aBdsRoot, 'lib') + sLineBreak +
    'set DAK_TEST_RSVARS=1' + sLineBreak);
end;

procedure TLspContextTests.LspUsesDakIniDelphiVersionFallback;
var
  lBdsRoot: string;
  lContext: TLspContext;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lEnvSearchDir: string;
  lError: string;
  lLibraryDir: string;
  lOptions: TAppOptions;
  lRsVarsPath: string;
begin
  lDprojPath := CreateFixtureProject('lsp-dak-fallback', 'PROJECT_DEFINE', '99.9');
  lBdsRoot := TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds');
  lLibraryDir := TPath.Combine(ExtractFilePath(lDprojPath), 'IdeLibrary');
  lEnvSearchDir := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvSearch');
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'Source'));
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'lib'));
  TDirectory.CreateDirectory(lLibraryDir);
  TDirectory.CreateDirectory(lEnvSearchDir);
  lRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
  lEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj');
  WriteRsVarsFile(lRsVarsPath, lBdsRoot);
  WriteEnvOptionsFile(lEnvOptionsPath, lLibraryDir, lEnvSearchDir, 'ENV_DEFINE');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fPlatform := 'Win32';
  lOptions.fConfig := 'Debug';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;
  lOptions.fEnvOptionsPath := lEnvOptionsPath;
  lOptions.fHasEnvOptionsPath := True;

  lError := '';
  Assert.IsTrue(TryBuildStrictLspContext(lOptions, lContext, lError),
    'Expected strict lsp context to resolve using dak.ini DelphiVersion. Error: ' + lError);
  Assert.AreEqual('99.9', lContext.fDelphiVersion,
    'Expected DelphiVersion to fall back from project-local dak.ini.');
  Assert.IsTrue(ArrayContainsValue(lContext.fParams.fUnitSearchPath, TPath.Combine(lBdsRoot, 'Source')),
    'Expected BDS-derived search path from fake rsvars override.');
end;

procedure TLspContextTests.LspUsesRsvarsAndEnvOptionsOverrides;
var
  lBdsRoot: string;
  lContext: TLspContext;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lEnvSearchDir: string;
  lError: string;
  lLibraryDir: string;
  lOptions: TAppOptions;
  lRsVarsPath: string;
begin
  lDprojPath := CreateFixtureProject('lsp-explicit-overrides', 'PROJECT_OVERRIDE_DEFINE');
  lBdsRoot := TPath.Combine(ExtractFilePath(lDprojPath), 'OverrideBds');
  lLibraryDir := TPath.Combine(ExtractFilePath(lDprojPath), 'OverrideLibrary');
  lEnvSearchDir := TPath.Combine(ExtractFilePath(lDprojPath), 'OverrideEnvSearch');
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'Source'));
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'lib'));
  TDirectory.CreateDirectory(lLibraryDir);
  TDirectory.CreateDirectory(lEnvSearchDir);
  lRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'override-rsvars.bat');
  lEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'OverrideEnvOptions.proj');
  WriteRsVarsFile(lRsVarsPath, lBdsRoot);
  WriteEnvOptionsFile(lEnvOptionsPath, lLibraryDir, lEnvSearchDir, 'ENV_OVERRIDE_DEFINE');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fPlatform := 'Win32';
  lOptions.fConfig := 'Release';
  lOptions.fDelphiVersion := '99.9';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;
  lOptions.fEnvOptionsPath := lEnvOptionsPath;
  lOptions.fHasEnvOptionsPath := True;

  lError := '';
  Assert.IsTrue(TryBuildStrictLspContext(lOptions, lContext, lError),
    'Expected strict lsp context to resolve using explicit overrides. Error: ' + lError);
  Assert.IsTrue(SameText(lLibraryDir, lContext.fLibraryPath),
    'Expected explicit EnvOptions override library path to be used.');
  Assert.IsTrue(ArrayContainsValue(lContext.fParams.fUnitSearchPath, lEnvSearchDir),
    'Expected explicit EnvOptions override search path to be part of the effective search path.');
  Assert.IsTrue(ArrayContainsValue(lContext.fParams.fUnitSearchPath, TPath.Combine(lBdsRoot, 'Source')),
    'Expected explicit rsvars override BDS root to contribute to the effective search path.');
  Assert.IsTrue(ArrayContainsValue(lContext.fParams.fDefines, 'ENV_OVERRIDE_DEFINE'),
    'Expected explicit EnvOptions override defines to flow into the evaluated project params.');
end;

procedure TLspContextTests.LspHardFailsWhenRealDelphiContextCannotBeBuilt;
var
  lContext: TLspContext;
  lDprojPath: string;
  lError: string;
  lOptions: TAppOptions;
  lRsVarsPath: string;
begin
  lDprojPath := CreateFixtureProject('lsp-hard-fail', 'PROJECT_DEFINE');
  lRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'missing', 'rsvars.bat');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fPlatform := 'Win32';
  lOptions.fConfig := 'Release';
  lOptions.fDelphiVersion := '99.9';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;

  lError := '';
  Assert.IsFalse(TryBuildStrictLspContext(lOptions, lContext, lError),
    'Expected strict lsp context to fail when the Delphi toolchain cannot be resolved.');
  Assert.IsTrue(Pos('rsvars.bat not found', lError) > 0,
    'Expected missing rsvars prerequisite in the error. Actual: ' + lError);
end;

procedure TLspContextTests.LspWritesGeneratedContextUnderDakWorkspace;
var
  lContext: TLspContext;
  lDprojPath: string;
  lText: string;
  lWorkspaceRoot: string;
begin
  lDprojPath := PrepareResolvedContext('lsp-dak-workspace', lContext);
  lWorkspaceRoot := TPath.Combine(TPath.Combine(ExtractFilePath(lDprojPath), '.dak'), 'LspFixture');

  Assert.AreEqual<string>(TPath.Combine(TPath.Combine(lWorkspaceRoot, 'lsp'), 'context.delphilsp.json'),
    lContext.fContextFilePath, 'Expected generated LSP context file to live under the sibling .dak workspace.');
  Assert.IsTrue(FileExists(lContext.fContextFilePath),
    'Expected generated LSP context file to be written.');
  Assert.AreEqual<string>(TPath.Combine(TPath.Combine(lWorkspaceRoot, 'lsp'), 'logs'), lContext.fLogsDir,
    'Expected logs directory to stay under the same owned workspace.');
  Assert.IsTrue(TDirectory.Exists(lContext.fLogsDir),
    'Expected logs directory to be created under the owned workspace.');

  lText := TFile.ReadAllText(lContext.fContextFilePath, TEncoding.UTF8);
  Assert.IsTrue(Pos('context.delphilsp.json', lText) > 0,
    'Expected generated context metadata to mention the owned context file path.');
  Assert.IsTrue(Pos('"project"', lText) > 0,
    'Expected generated context metadata to include the project block.');
end;

procedure TLspContextTests.LspDoesNotWriteContextBesideSourceProject;
var
  lContext: TLspContext;
  lDprojPath: string;
  lSidecarPath: string;
begin
  lDprojPath := PrepareResolvedContext('lsp-no-sidecar', lContext);
  lSidecarPath := TPath.Combine(ExtractFilePath(lDprojPath), 'context.delphilsp.json');

  Assert.IsFalse(FileExists(lSidecarPath),
    'Did not expect an LSP context sidecar beside the source project.');
  Assert.IsTrue(FileExists(lContext.fContextFilePath),
    'Expected the owned workspace context file to exist.');
end;

procedure TLspContextTests.LspReportsWorkspaceWriteFailureCleanly;
var
  lContext: TLspContext;
  lDakFilePath: string;
  lDprojPath: string;
  lError: string;
  lOptions: TAppOptions;
begin
  lDprojPath := CreateFixtureProject('lsp-workspace-write-failure', 'PROJECT_DEFINE', '99.9');
  lDakFilePath := TPath.Combine(ExtractFilePath(lDprojPath), '.dak');
  WriteAsciiFile(lDakFilePath, 'blocked');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fPlatform := 'Win32';
  lOptions.fConfig := 'Debug';
  lOptions.fDelphiVersion := '99.9';
  lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'missing', 'rsvars.bat');
  lOptions.fHasRsVarsPath := True;

  WriteRsVarsFile(TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat'), TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds'));
  TDirectory.CreateDirectory(TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds', 'Source'));
  TDirectory.CreateDirectory(TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds', 'lib'));
  WriteEnvOptionsFile(TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj'),
    TPath.Combine(ExtractFilePath(lDprojPath), 'IdeLibrary'), TPath.Combine(ExtractFilePath(lDprojPath), 'EnvSearch'),
    'ENV_DEFINE');
  lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
  lOptions.fEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj');
  lOptions.fHasEnvOptionsPath := True;

  lError := '';
  Assert.IsFalse(TryBuildStrictLspContext(lOptions, lContext, lError),
    'Expected strict lsp context to fail cleanly when the owned workspace path is blocked.');
  Assert.IsTrue(Pos('Failed to write lsp context artifacts', lError) > 0,
    'Expected a clean workspace-write error. Actual: ' + lError);
end;


function TLspFixtureTests.CreateScriptFile(const aScenarioName, aScriptJson: string): string;
var
  lDir: string;
begin
  EnsureTempClean;
  lDir := TPath.Combine(TempRoot, 'lsp-fixture-scripts');
  TDirectory.CreateDirectory(lDir);
  Result := TPath.Combine(lDir, aScenarioName + '.json');
  WriteUtf8File(Result, aScriptJson);
end;

procedure TLspFixtureTests.FakeServerSupportsInitializeAndShutdown;
var
  lClient: TLspJsonRpcClient;
  lDefinitionArray: TJSONArray;
  lError: string;
  lResponse: TJSONObject;
  lScriptPath: string;
begin
  EnsureFakeLspFixtureBuilt;
  lScriptPath := CreateScriptFile('fixture-init',
    '{"requireOpenedDocuments":true,"initializeResult":{"capabilities":{"hoverProvider":true}},"responses":{"textDocument/definition":[{"uri":"file:///C:/repo/Unit1.pas","range":{"start":{"line":2,"character":4},"end":{"line":2,"character":10}}}]}}');
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  try
    lError := '';
    Assert.IsTrue(lClient.Start(FakeLspExePath, '--script ' + QuoteArg(lScriptPath), FakeLspFixtureDir, lError),
      'Expected fake LSP server to start. Error: ' + lError);
    Assert.IsTrue(lClient.SendRequest(1, 'initialize', '{"processId":1}', lResponse, lError),
      'Expected initialize request to succeed. Error: ' + lError);
    Assert.IsTrue(Assigned(lResponse.Values['result']), 'Expected initialize result payload.');
    Assert.IsTrue(Assigned((lResponse.Values['result'] as TJSONObject).Values['capabilities']),
      'Expected initialize result to expose capabilities.');
    lResponse.Free;
    lResponse := nil;
    Assert.IsTrue(lClient.SendNotification('textDocument/didOpen',
      '{"textDocument":{"uri":"file:///C:/repo/Unit1.pas","languageId":"delphi","version":1,"text":"unit Unit1;"}}', lError),
      'Expected didOpen notification to succeed. Error: ' + lError);
    Assert.IsTrue(lClient.SendRequest(2, 'textDocument/definition',
      '{"textDocument":{"uri":"file:///C:/repo/Unit1.pas"},"position":{"line":2,"character":4}}', lResponse, lError),
      'Expected definition request after didOpen to succeed. Error: ' + lError);
    Assert.IsTrue(lResponse.Values['result'] is TJSONArray, 'Expected definition result array after didOpen.');
    lDefinitionArray := lResponse.Values['result'] as TJSONArray;
    Assert.AreEqual(1, lDefinitionArray.Count, 'Expected one scripted definition result after didOpen.');
    lResponse.Free;
    lResponse := nil;
    Assert.IsTrue(lClient.ShutdownAndExit(lError), 'Expected fake LSP server shutdown to succeed. Error: ' + lError);
  finally
    lResponse.Free;
    lClient.Free;
  end;
end;

procedure TLspFixtureTests.FakeServerReturnsScriptedDefinitionAndHoverPayloads;
var
  lClient: TLspJsonRpcClient;
  lDefinitionArray: TJSONArray;
  lError: string;
  lHoverObject: TJSONObject;
  lResponse: TJSONObject;
  lScriptPath: string;
  lSymbolsArray: TJSONArray;
begin
  EnsureFakeLspFixtureBuilt;
  lScriptPath := CreateScriptFile('fixture-definition-hover',
    '{"requireOpenedDocuments":true,"responses":{"textDocument/definition":[{"uri":"file:///C:/repo/Unit1.pas","range":{"start":{"line":2,"character":4},"end":{"line":2,"character":10}}}],"textDocument/hover":{"contents":{"kind":"markdown","value":"TFixtureType"},"range":{"start":{"line":2,"character":4},"end":{"line":2,"character":16}}},"workspace/symbol":[{"name":"TFixtureType","kind":5,"containerName":"Unit1","location":{"uri":"file:///C:/repo/Unit1.pas","range":{"start":{"line":2,"character":4},"end":{"line":2,"character":16}}}}]}}');
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  try
    lError := '';
    Assert.IsTrue(lClient.Start(FakeLspExePath, '--script ' + QuoteArg(lScriptPath), FakeLspFixtureDir, lError),
      'Expected fake LSP server to start. Error: ' + lError);
    Assert.IsTrue(lClient.SendRequest(1, 'initialize', '{"processId":1}', lResponse, lError),
      'Expected initialize request to succeed. Error: ' + lError);
    lResponse.Free;
    lResponse := nil;
    Assert.IsTrue(lClient.SendNotification('textDocument/didOpen',
      '{"textDocument":{"uri":"file:///C:/repo/Unit1.pas","languageId":"delphi","version":1,"text":"unit Unit1;"}}', lError),
      'Expected didOpen notification to succeed. Error: ' + lError);

    Assert.IsTrue(lClient.SendRequest(2, 'textDocument/definition',
      '{"textDocument":{"uri":"file:///C:/repo/Unit1.pas"},"position":{"line":2,"character":4}}', lResponse, lError),
      'Expected definition request to succeed. Error: ' + lError);
    Assert.IsTrue(lResponse.Values['result'] is TJSONArray, 'Expected definition result array.');
    lDefinitionArray := lResponse.Values['result'] as TJSONArray;
    Assert.AreEqual(1, lDefinitionArray.Count, 'Expected one scripted definition result.');
    Assert.AreEqual<string>('file:///C:/repo/Unit1.pas',
      (lDefinitionArray.Items[0] as TJSONObject).GetValue<string>('uri'), 'Expected scripted definition uri.');
    lResponse.Free;
    lResponse := nil;

    Assert.IsTrue(lClient.SendRequest(3, 'textDocument/hover',
      '{"textDocument":{"uri":"file:///C:/repo/Unit1.pas"},"position":{"line":2,"character":4}}', lResponse, lError),
      'Expected hover request to succeed. Error: ' + lError);
    Assert.IsTrue(lResponse.Values['result'] is TJSONObject, 'Expected hover result object.');
    lHoverObject := lResponse.Values['result'] as TJSONObject;
    Assert.AreEqual<string>('TFixtureType',
      ((lHoverObject.Values['contents'] as TJSONObject).GetValue<string>('value')), 'Expected scripted hover contents.');
    lResponse.Free;
    lResponse := nil;

    Assert.IsTrue(lClient.SendRequest(4, 'workspace/symbol', '{"query":"Fixture"}', lResponse, lError),
      'Expected workspace/symbol request to succeed. Error: ' + lError);
    Assert.IsTrue(lResponse.Values['result'] is TJSONArray, 'Expected workspace/symbol result array.');
    lSymbolsArray := lResponse.Values['result'] as TJSONArray;
    Assert.AreEqual(1, lSymbolsArray.Count, 'Expected one scripted symbol result.');
    Assert.AreEqual<string>('TFixtureType',
      (lSymbolsArray.Items[0] as TJSONObject).GetValue<string>('name'), 'Expected scripted symbol name.');
    Assert.IsTrue(lClient.ShutdownAndExit(lError), 'Expected fake LSP server shutdown to succeed. Error: ' + lError);
  finally
    lResponse.Free;
    lClient.Free;
  end;
end;

procedure TLspFixtureTests.FakeServerCanSimulateEmptyAndErrorResponses;
var
  lClient: TLspJsonRpcClient;
  lError: string;
  lErrorObject: TJSONObject;
  lResponse: TJSONObject;
  lResultArray: TJSONArray;
  lScriptPath: string;
begin
  EnsureFakeLspFixtureBuilt;
  lScriptPath := CreateScriptFile('fixture-empty-error',
    '{"responses":{"textDocument/references":[]},"errors":{"workspace/symbol":{"code":-32001,"message":"simulated failure"}}}');
  lClient := TLspJsonRpcClient.Create;
  lResponse := nil;
  try
    lError := '';
    Assert.IsTrue(lClient.Start(FakeLspExePath, '--script ' + QuoteArg(lScriptPath), FakeLspFixtureDir, lError),
      'Expected fake LSP server to start. Error: ' + lError);
    Assert.IsTrue(lClient.SendRequest(1, 'initialize', '{"processId":1}', lResponse, lError),
      'Expected initialize request to succeed. Error: ' + lError);
    lResponse.Free;
    lResponse := nil;

    Assert.IsTrue(lClient.SendRequest(2, 'textDocument/references',
      '{"textDocument":{"uri":"file:///C:/repo/Unit1.pas"},"position":{"line":2,"character":4}}', lResponse, lError),
      'Expected references request to succeed. Error: ' + lError);
    Assert.IsTrue(lResponse.Values['result'] is TJSONArray, 'Expected references result array.');
    lResultArray := lResponse.Values['result'] as TJSONArray;
    Assert.AreEqual(0, lResultArray.Count, 'Expected empty scripted references result.');
    lResponse.Free;
    lResponse := nil;

    Assert.IsTrue(lClient.SendRequest(3, 'workspace/symbol', '{"query":"Foo"}', lResponse, lError),
      'Expected workspace/symbol request to return a scripted error response. Error: ' + lError);
    Assert.IsTrue(lResponse.Values['error'] is TJSONObject, 'Expected error object in scripted failure response.');
    lErrorObject := lResponse.Values['error'] as TJSONObject;
    Assert.AreEqual<string>('-32001', lErrorObject.GetValue<string>('code'), 'Expected scripted error code.');
    Assert.AreEqual<string>('simulated failure', lErrorObject.GetValue<string>('message'), 'Expected scripted error message.');
    Assert.IsTrue(lClient.ShutdownAndExit(lError), 'Expected fake LSP server shutdown to succeed. Error: ' + lError);
  finally
    lResponse.Free;
    lClient.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspContextTests);
  TDUnitX.RegisterTestFixture(TLspFixtureTests);

end.
