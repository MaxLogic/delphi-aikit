unit Test.Support;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  Dak.FixInsight,
  Dak.PascalAnalyzerRunner;

function RepoRoot: string;
function TempRoot: string;
procedure EnsureTempClean;
procedure EnsureResolverBuilt;
function ResolverExePath: string;
function IsPawelMachine: Boolean;
procedure RequireFixInsightOrSkip(out aExePath: string);
procedure RequirePalCmdOrSkip(out aExePath: string);
function RunProcess(const aExe, aArgs, aWorkDir, aOutputFile: string; out aExitCode: Cardinal): Boolean;
function QuoteArg(const aValue: string): string;

implementation

var
  GRepoRoot: string;
  GTempRoot: string;
  GTempCleaned: Boolean = False;
  GResolverBuilt: Boolean = False;
  GResolverExe: string = '';

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
begin
  if GTempRoot = '' then
    GTempRoot := TPath.Combine(RepoRoot, 'tests\temp');
  Result := GTempRoot;
end;

procedure EnsureTempClean;
var
  lTemp: string;
begin
  if GTempCleaned then
    Exit;
  lTemp := TempRoot;
  if TDirectory.Exists(lTemp) then
    TDirectory.Delete(lTemp, True);
  TDirectory.CreateDirectory(lTemp);
  GTempCleaned := True;
end;

function CmdExePath: string;
begin
  Result := GetEnvironmentVariable('ComSpec');
  if Result = '' then
    Result := 'C:\Windows\System32\cmd.exe';
end;

function RunProcess(const aExe, aArgs, aWorkDir, aOutputFile: string; out aExitCode: Cardinal): Boolean;
var
  lSi: TStartupInfo;
  lPi: TProcessInformation;
  lWait: Cardinal;
  lLastError: Cardinal;
  lCmdLine: string;
  lOutHandle: THandle;
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
    lOutHandle := CreateFile(PChar(aOutputFile), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL, 0);
    if lOutHandle = INVALID_HANDLE_VALUE then
      raise Exception.Create('Failed to create output file: ' + aOutputFile);
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

procedure EnsureResolverBuilt;
var
  lBinExe: string;
  lExit: Cardinal;
  lBat: string;
  lArgs: string;
  lCmdArgs: string;
  lLogText: string;
  lLog: string;
  lTestOutputDir: string;
begin
  if GResolverBuilt then
    Exit;

  EnsureTempClean;
  lBat := TPath.Combine(RepoRoot, 'build-delphi.bat');
  lBinExe := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
  lTestOutputDir := Trim(GetEnvironmentVariable('DAK_TEST_OUTPUT_DIR'));
  lArgs := QuoteArg(TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dproj')) +
    ' -config Release -platform Win32 -ver 23';
  if lTestOutputDir <> '' then
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

initialization
  EnsureTempClean;

end.
