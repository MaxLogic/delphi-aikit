unit Test.Support;

interface

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  System.SyncObjs,
  Winapi.Windows,
  DUnitX.TestFramework,
  maxLogic.ioutils,
  Dak.FixInsight,
  Dak.Lsp.Context,
  Dak.Lsp.Runner,
  Dak.PascalAnalyzerRunner,
  Dak.Types;

function RepoRoot: string;
function TempRoot: string;
procedure EnsureTempClean;
procedure EnsureResolverBuilt;
function ResolverExePath: string;
function IsPawelMachine: Boolean;
procedure RequireFixInsightOrSkip(out aExePath: string);
procedure RequirePalCmdOrSkip(out aExePath: string);
procedure RequireRealDelphiLsp23OrSkip(out aExePath: string);
function RunProcess(const aExe, aArgs, aWorkDir, aOutputFile: string; out aExitCode: Cardinal): Boolean;
function RunProcessWithTimeout(const aExe, aArgs, aWorkDir, aOutputFile: string;
  const aTimeoutMs: Cardinal; out aExitCode: Cardinal): Boolean;
function StartSlowPingProcess(out aProcess: THandle; out aThread: THandle; out aError: string): Boolean;
function QuoteArg(const aValue: string): string;
function SetScopedEnvironmentVariable(const aName, aValue: string): IInterface;
function SetScopedEnvironmentVariables(const aNameValuePairs: array of string): IInterface;
function ClearScopedEnvironmentVariable(const aName: string): IInterface;

implementation

type
  TScopedEnvironmentVariable = class(TInterfacedObject)
  private
    fHadPreviousValue: Boolean;
    fName: string;
    fPreviousValue: string;
  public
    constructor Create(const aName, aValue: string; aClearValue: Boolean);
    destructor Destroy; override;
  end;

  TScopedEnvironmentVariables = class(TInterfacedObject)
  private
    fHadPreviousValues: TArray<Boolean>;
    fNames: TArray<string>;
    fPreviousValues: TArray<string>;
  public
    constructor Create(const aNameValuePairs: array of string);
    destructor Destroy; override;
  end;

var
  GRepoRoot: string;
  GTempRoot: string;
  GTempCleaned: Boolean = False;
  GResolverBuilt: Boolean = False;
  GResolverExe: string = '';
  GEnvironmentLock: TCriticalSection;

function TryReadEnvironmentVariable(const aName: string; out aValue: string): Boolean;
var
  lSize: DWORD;
begin
  aValue := '';
  SetLastError(ERROR_SUCCESS);
  lSize := Winapi.Windows.GetEnvironmentVariable(PChar(aName), nil, 0);
  Result := lSize > 0;
  if not Result then
    Exit;
  SetLength(aValue, lSize - 1);
  if lSize > 1 then
    Winapi.Windows.GetEnvironmentVariable(PChar(aName), PChar(aValue), lSize);
end;

procedure SetEnvironmentVariableOrRaise(const aName, aValue: string);
begin
  if not Winapi.Windows.SetEnvironmentVariable(PChar(aName), PChar(aValue)) then
    RaiseLastOSError;
end;

procedure ClearEnvironmentVariableOrRaise(const aName: string);
begin
  if not Winapi.Windows.SetEnvironmentVariable(PChar(aName), nil) then
    RaiseLastOSError;
end;

constructor TScopedEnvironmentVariable.Create(const aName, aValue: string; aClearValue: Boolean);
begin
  inherited Create;
  GEnvironmentLock.Enter;
  try
    fName := aName;
    fHadPreviousValue := TryReadEnvironmentVariable(aName, fPreviousValue);
    if aClearValue then
      ClearEnvironmentVariableOrRaise(aName)
    else
      SetEnvironmentVariableOrRaise(aName, aValue);
  except
    GEnvironmentLock.Leave;
    raise;
  end;
end;

destructor TScopedEnvironmentVariable.Destroy;
begin
  if fHadPreviousValue then
    SetEnvironmentVariableOrRaise(fName, fPreviousValue)
  else
    ClearEnvironmentVariableOrRaise(fName);
  GEnvironmentLock.Leave;
  inherited Destroy;
end;

function SetScopedEnvironmentVariable(const aName, aValue: string): IInterface;
begin
  Result := TScopedEnvironmentVariable.Create(aName, aValue, False);
end;

constructor TScopedEnvironmentVariables.Create(const aNameValuePairs: array of string);
var
  i: Integer;
  lIndex: Integer;
begin
  inherited Create;
  if (Length(aNameValuePairs) mod 2) <> 0 then
    raise Exception.Create('Scoped environment pairs must contain name/value entries.');
  GEnvironmentLock.Enter;
  try
    SetLength(fNames, Length(aNameValuePairs) div 2);
    SetLength(fPreviousValues, Length(fNames));
    SetLength(fHadPreviousValues, Length(fNames));
    lIndex := 0;
    i := 0;
    while i < Length(aNameValuePairs) do
    begin
      fNames[lIndex] := aNameValuePairs[i];
      fHadPreviousValues[lIndex] := TryReadEnvironmentVariable(fNames[lIndex], fPreviousValues[lIndex]);
      SetEnvironmentVariableOrRaise(fNames[lIndex], aNameValuePairs[i + 1]);
      Inc(lIndex);
      Inc(i, 2);
    end;
  except
    GEnvironmentLock.Leave;
    raise;
  end;
end;

destructor TScopedEnvironmentVariables.Destroy;
var
  i: Integer;
begin
  for i := High(fNames) downto 0 do
  begin
    if fHadPreviousValues[i] then
      SetEnvironmentVariableOrRaise(fNames[i], fPreviousValues[i])
    else
      ClearEnvironmentVariableOrRaise(fNames[i]);
  end;
  GEnvironmentLock.Leave;
  inherited Destroy;
end;

function SetScopedEnvironmentVariables(const aNameValuePairs: array of string): IInterface;
begin
  Result := TScopedEnvironmentVariables.Create(aNameValuePairs);
end;

function ClearScopedEnvironmentVariable(const aName: string): IInterface;
begin
  Result := TScopedEnvironmentVariable.Create(aName, '', True);
end;

function NewRunTempRoot(const aBaseRoot: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := StringReplace(StringReplace(GUIDToString(lGuid), '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]);
  Result := TPath.Combine(aBaseRoot, 'run-' + GetCurrentProcessId.ToString + '-' + lGuidText);
end;

function QuoteArg(const aValue: string): string;
begin
  if (aValue = '') or (Pos(' ', aValue) > 0) or (Pos('"', aValue) > 0) then
    Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := aValue;
end;

function FindRepoRoot: string;
var
  lDir: string;
  i: Integer;
begin
  Result := '';
  lDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  for i := 0 to 6 do
  begin
    if FileExists(TPath.Combine(lDir, 'projects\DelphiAIKit.dproj')) then
      Exit(lDir);
    lDir := ExcludeTrailingPathDelimiter(ExtractFilePath(lDir));
    if lDir = '' then
      Break;
  end;
end;

function RepoRoot: string;
begin
  if GRepoRoot = '' then
  begin
    GRepoRoot := FindRepoRoot;
    if GRepoRoot = '' then
      GRepoRoot := ExcludeTrailingPathDelimiter(GetCurrentDir);
  end;
  Result := GRepoRoot;
end;

function TempRoot: string;
var
  lEnvRoot: string;
begin
  if GTempRoot = '' then
  begin
    lEnvRoot := Trim(GetEnvironmentVariable('DAK_TEST_OUTPUT_ROOT'));
    if lEnvRoot <> '' then
      GTempRoot := NewRunTempRoot(TPath.GetFullPath(lEnvRoot))
    else
      GTempRoot := NewRunTempRoot(TPath.Combine(RepoRoot, 'tests\temp'));
  end;
  Result := GTempRoot;
end;

procedure EnsureTempClean;
var
  lTemp: string;
begin
  if GTempCleaned then
    Exit;
  lTemp := TempRoot;
  if (Trim(GetEnvironmentVariable('DAK_TEST_KEEP_TEMP')) <> '1') and TDirectory.Exists(lTemp) then
    TDirectory.Delete(lTemp, True);
  TDirectory.CreateDirectory(lTemp);
  GTempCleaned := True;
end;

procedure CleanupTempRoot;
begin
  if (Trim(GetEnvironmentVariable('DAK_TEST_KEEP_TEMP')) = '1') or (GTempRoot = '') then
    Exit;
  if TDirectory.Exists(GTempRoot) then
    TDirectory.Delete(GTempRoot, True);
end;

function CmdExePath: string;
begin
  Result := GetEnvironmentVariable('ComSpec');
  if Result = '' then
    Result := 'C:\Windows\System32\cmd.exe';
end;

function RunProcess(const aExe, aArgs, aWorkDir, aOutputFile: string; out aExitCode: Cardinal): Boolean;
var
  lAttempt: Integer;
  lSi: TStartupInfo;
  lPi: TProcessInformation;
  lWait: Cardinal;
  lCreateError: Cardinal;
  lLastError: Cardinal;
  lCmdLine: string;
  lOutHandle: THandle;
  lOutputDir: string;
  lSa: TSecurityAttributes;
  lWorkDir: string;
begin
  Result := False;
  aExitCode := 0;
  lOutHandle := INVALID_HANDLE_VALUE;

  FillChar(lSa, SizeOf(lSa), 0);
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;

  if aOutputFile <> '' then
  begin
    lOutputDir := ExtractFileDir(aOutputFile);
    if lOutputDir <> '' then
      ForceDirectories(lOutputDir);
    lCreateError := 0;
    for lAttempt := 1 to 20 do
    begin
      lOutHandle := CreateFile(PChar(aOutputFile), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, 0);
      if lOutHandle <> INVALID_HANDLE_VALUE then
        Break;
      lCreateError := GetLastError;
      if (lCreateError <> ERROR_PATH_NOT_FOUND) and (lCreateError <> ERROR_FILE_NOT_FOUND) and
        (lCreateError <> ERROR_ACCESS_DENIED) and (lCreateError <> ERROR_SHARING_VIOLATION) then
        Break;
      if lOutputDir <> '' then
        ForceDirectories(lOutputDir);
      Sleep(50);
    end;
    if lOutHandle = INVALID_HANDLE_VALUE then
      raise Exception.Create('Failed to create output file: ' + aOutputFile + ' (' +
        SysErrorMessage(lCreateError) + ')');
  end;

  try
    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES;
    lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    if lOutHandle <> INVALID_HANDLE_VALUE then
    begin
      lSi.hStdOutput := lOutHandle;
      lSi.hStdError := lOutHandle;
    end else
    begin
      lSi.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
      lSi.hStdError := GetStdHandle(STD_ERROR_HANDLE);
    end;

    FillChar(lPi, SizeOf(lPi), 0);
    lCmdLine := QuoteArg(aExe);
    if aArgs <> '' then
      lCmdLine := lCmdLine + ' ' + aArgs;
    UniqueString(lCmdLine);
    lWorkDir := aWorkDir;
    if lWorkDir = '' then
      lWorkDir := ExtractFilePath(aExe);

    if not CreateProcess(PChar(aExe), PChar(lCmdLine), nil, nil, True, 0, nil, PChar(lWorkDir), lSi, lPi) then
    begin
      lLastError := GetLastError;
      raise Exception.Create('Process start failed: ' + SysErrorMessage(lLastError));
    end;
    try
      lWait := WaitForSingleObject(lPi.hProcess, INFINITE);
      if lWait <> WAIT_OBJECT_0 then
      begin
        lLastError := GetLastError;
        raise Exception.Create('Process wait failed: ' + SysErrorMessage(lLastError));
      end;
      if not GetExitCodeProcess(lPi.hProcess, aExitCode) then
      begin
        lLastError := GetLastError;
        raise Exception.Create('Process exit code failed: ' + SysErrorMessage(lLastError));
      end;
    finally
      CloseHandle(lPi.hThread);
      CloseHandle(lPi.hProcess);
    end;

    Result := True;
  finally
    if lOutHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(lOutHandle);
  end;
end;

function RunProcessWithTimeout(const aExe, aArgs, aWorkDir, aOutputFile: string;
  const aTimeoutMs: Cardinal; out aExitCode: Cardinal): Boolean;
var
  lCmdLine: string;
  lCreateError: Cardinal;
  lLastError: Cardinal;
  lOutHandle: THandle;
  lOutputDir: string;
  lPi: TProcessInformation;
  lSa: TSecurityAttributes;
  lSi: TStartupInfo;
  lWait: Cardinal;
  lWorkDir: string;
begin
  Result := False;
  aExitCode := STILL_ACTIVE;
  lOutHandle := INVALID_HANDLE_VALUE;
  lCreateError := ERROR_SUCCESS;
  if aOutputFile <> '' then
  begin
    lOutputDir := ExtractFileDir(aOutputFile);
    if lOutputDir <> '' then
      ForceDirectories(lOutputDir);
    FillChar(lSa, SizeOf(lSa), 0);
    lSa.nLength := SizeOf(lSa);
    lSa.bInheritHandle := True;
    lOutHandle := CreateFile(PChar(aOutputFile), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL, 0);
    if lOutHandle = INVALID_HANDLE_VALUE then
    begin
      lCreateError := GetLastError;
      raise Exception.Create('Failed to create output file: ' + aOutputFile + ' (' +
        SysErrorMessage(lCreateError) + ')');
    end;
  end;

  try
    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES;
    lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    if lOutHandle <> INVALID_HANDLE_VALUE then
    begin
      lSi.hStdOutput := lOutHandle;
      lSi.hStdError := lOutHandle;
    end else
    begin
      lSi.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
      lSi.hStdError := GetStdHandle(STD_ERROR_HANDLE);
    end;

    FillChar(lPi, SizeOf(lPi), 0);
    lCmdLine := QuoteArg(aExe);
    if aArgs <> '' then
      lCmdLine := lCmdLine + ' ' + aArgs;
    UniqueString(lCmdLine);
    lWorkDir := aWorkDir;
    if lWorkDir = '' then
      lWorkDir := ExtractFilePath(aExe);

    if not CreateProcess(PChar(aExe), PChar(lCmdLine), nil, nil, True, 0, nil, PChar(lWorkDir), lSi, lPi) then
    begin
      lLastError := GetLastError;
      raise Exception.Create('Process start failed: ' + SysErrorMessage(lLastError));
    end;
    try
      lWait := WaitForSingleObject(lPi.hProcess, aTimeoutMs);
      if lWait = WAIT_TIMEOUT then
      begin
        if not TerminateProcess(lPi.hProcess, Cardinal(ERROR_TIMEOUT)) then
        begin
          lLastError := GetLastError;
          raise Exception.Create('Process termination failed: ' + SysErrorMessage(lLastError));
        end;
        lWait := WaitForSingleObject(lPi.hProcess, 5000);
        if lWait = WAIT_TIMEOUT then
          raise Exception.Create('Process did not terminate after timeout: ' + aExe);
        if lWait <> WAIT_OBJECT_0 then
        begin
          lLastError := GetLastError;
          raise Exception.Create('Process termination wait failed: ' + SysErrorMessage(lLastError));
        end;
        GetExitCodeProcess(lPi.hProcess, aExitCode);
        Exit(False);
      end;
      if lWait <> WAIT_OBJECT_0 then
      begin
        lLastError := GetLastError;
        raise Exception.Create('Process wait failed: ' + SysErrorMessage(lLastError));
      end;
      if not GetExitCodeProcess(lPi.hProcess, aExitCode) then
      begin
        lLastError := GetLastError;
        raise Exception.Create('Process exit code failed: ' + SysErrorMessage(lLastError));
      end;
    finally
      CloseHandle(lPi.hThread);
      CloseHandle(lPi.hProcess);
    end;

    Result := True;
  finally
    if lOutHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(lOutHandle);
  end;
end;

function StartSlowPingProcess(out aProcess: THandle; out aThread: THandle; out aError: string): Boolean;
var
  lCmdLine: string;
  lExe: string;
  lLastError: Cardinal;
  lPi: TProcessInformation;
  lRoot: string;
  lSi: TStartupInfo;
begin
  Result := False;
  aProcess := 0;
  aThread := 0;
  aError := '';

  lRoot := Trim(GetEnvironmentVariable('SystemRoot'));
  if lRoot <> '' then
    lExe := CombinePath([lRoot, 'System32', 'ping.exe'])
  else
    lExe := 'ping.exe';

  FillChar(lSi, SizeOf(lSi), 0);
  lSi.cb := SizeOf(lSi);
  FillChar(lPi, SizeOf(lPi), 0);

  lCmdLine := QuoteArg(lExe) + ' -n 30 127.0.0.1';
  UniqueString(lCmdLine);
  if not CreateProcess(PChar(lExe), PChar(lCmdLine), nil, nil, False, CREATE_NO_WINDOW, nil, nil, lSi, lPi) then
  begin
    lLastError := GetLastError;
    aError := 'Slow ping process start failed: ' + SysErrorMessage(lLastError);
    Exit(False);
  end;

  aProcess := lPi.hProcess;
  aThread := lPi.hThread;
  Result := True;
end;

procedure EnsureResolverBuilt;
var
  lBinExe: string;
  lExit: Cardinal;
  lBat: string;
  lArgs: string;
  lCmdArgs: string;
  lLogText: string;
  lLog: string;
  lResolverExe: string;
  lTestOutputDir: string;
begin
  if GResolverBuilt then
    Exit;

  lResolverExe := Trim(GetEnvironmentVariable('DAK_TEST_RESOLVER_EXE'));
  if lResolverExe <> '' then
  begin
    if not FileExists(lResolverExe) then
      Assert.Fail('Resolver exe from DAK_TEST_RESOLVER_EXE not found: ' + lResolverExe);
    GResolverExe := TPath.GetFullPath(lResolverExe);
    GResolverBuilt := True;
    Exit;
  end;

  lBinExe := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
  if FileExists(lBinExe) then
  begin
    GResolverExe := lBinExe;
    GResolverBuilt := True;
    Exit;
  end;

  EnsureTempClean;
  lBat := TPath.Combine(RepoRoot, 'build-delphi.bat');
  lTestOutputDir := Trim(GetEnvironmentVariable('DAK_TEST_OUTPUT_DIR'));
  if lTestOutputDir = '' then
  begin
    lTestOutputDir := TPath.Combine(TempRoot, 'resolver-build-out');
  end;
  ForceDirectories(lTestOutputDir);
  lArgs := QuoteArg(TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dproj')) +
    ' -config Release -platform Win64 -ver 23';
  lArgs := lArgs + ' -test-output-dir ' + QuoteArg(lTestOutputDir);
  lCmdArgs := '/C "call ' + QuoteArg(lBat) + ' ' + lArgs + '"';
  lLog := TPath.Combine(TempRoot, 'build-resolver.log');

  if not RunProcess(CmdExePath, lCmdArgs, RepoRoot, lLog, lExit) then
    Assert.Fail('Failed to start build-delphi.bat');
  if lExit <> 0 then
  begin
    lLogText := '';
    if FileExists(lLog) then
      lLogText := TFile.ReadAllText(lLog, TEncoding.UTF8);
    if Pos('Could not create output file', lLogText) > 0 then
      Assert.Fail('build-delphi.bat failed: output file is locked. Choose output location explicitly (set DAK_TEST_OUTPUT_DIR). See: ' +
        lLog);
    Assert.Fail('build-delphi.bat failed, exit=' + lExit.ToString + '. See: ' + lLog);
  end;

  if lTestOutputDir <> '' then
    GResolverExe := TPath.Combine(TPath.GetFullPath(lTestOutputDir), 'DelphiAIKit.exe')
  else
    GResolverExe := lBinExe;
  if not FileExists(GResolverExe) then
    Assert.Fail('Resolver exe not found after build: ' + GResolverExe);

  GResolverBuilt := True;
end;

function ResolverExePath: string;
begin
  if GResolverExe = '' then
    GResolverExe := Trim(GetEnvironmentVariable('DAK_TEST_RESOLVER_EXE'));
  if GResolverExe = '' then
    GResolverExe := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
  Result := GResolverExe;
end;

function IsPawelMachine: Boolean;
begin
  Result := SameText(GetEnvironmentVariable('pawelspc'), '1');
end;

procedure RequireFixInsightOrSkip(out aExePath: string);
begin
  if TryResolveFixInsightExe(nil, aExePath) then
    Exit;

  if IsPawelMachine then
    Assert.Fail('FixInsightCL.exe not found, but pawelspc=1 requires it.')
  else
  begin
    aExePath := '';
    Assert.Pass('FixInsightCL.exe not found; skipping FixInsight tests.');
  end;
end;

procedure RequirePalCmdOrSkip(out aExePath: string);
var
  lError: string;
begin
  if TryResolvePalCmdExe('', aExePath, lError) then
    Exit;

  if IsPawelMachine then
    Assert.Fail('PALCMD not found, but pawelspc=1 requires it. ' + lError)
  else
  begin
    aExePath := '';
    Assert.Pass('PALCMD not found; skipping Pascal Analyzer tests.');
  end;
end;

procedure RequireRealDelphiLsp23OrSkip(out aExePath: string);
var
  lContext: TLspContext;
  lError: string;
  lOptions: TAppOptions;
  lOverride: string;
begin
  aExePath := '';
  lContext := Default(TLspContext);
  lContext.fDelphiVersion := '23.0';
  lOptions := Default(TAppOptions);
  lOverride := Trim(GetEnvironmentVariable('DAK_REAL_LSP_EXE'));
  if lOverride <> '' then
  begin
    lOptions.fLspPath := lOverride;
    lOptions.fHasLspPath := True;
  end;

  if TryResolveDelphiLspExe(lOptions, lContext, aExePath, lError) then
    Exit;

  if IsPawelMachine then
    Assert.Fail('DelphiLSP.exe for Delphi 23.0 not found, but pawelspc=1 requires it. ' + lError)
  else
  begin
    aExePath := '';
    Assert.Pass('DelphiLSP.exe for Delphi 23.0 not found; skipping real LSP acceptance tests. ' + lError);
  end;
end;

initialization
  GEnvironmentLock := TCriticalSection.Create;
  EnsureTempClean;

finalization
  CleanupTempRoot;
  GEnvironmentLock.Free;

end.
