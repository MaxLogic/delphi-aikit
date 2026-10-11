unit Test.Support;

interface

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
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
  Dak.Types,
  Dak.Utils;

type
  // Runs on the caller's thread after the child is contained and resumed, before
  // the deadline starts. It receives the child's process handle.
  TProcessStartedHook = reference to procedure(aProcess: THandle);

function RepoRoot: string;
function TempRoot: string;
function MaxTdbFixtureRoot: string;
function UniqueTempPath(const aPrefix: string): string;
function UniqueNoRepoTempPath(const aPrefix: string): string;
// The folder that holds UniqueNoRepoTempPath results, as named by the current
// DAK_TEST_OUTPUT_ROOT; names below it are <prefix>-<PID>-<token>.
function NoRepoTempBase: string;
procedure DeleteTempPath(const aPath: string);
// DAK-389: recursive delete that also removes folders beyond MAX_PATH (extended-length prefix).
// Reparse points (junctions, symlinks) are removed as links and never entered. Depth is bounded.
// Returns False with the first failure in aError; a missing path is success.
function TryDeleteTreeLongPath(const aPath: string; out aError: string): Boolean;
// DAK-383: the identity this runner exports to its descendants; empty in a child run, which owns nothing.
function RunOwnerIdentity: string;
// DAK-383: removes the run roots of this runner's dead children (see the implementation); no-op under
// DAK_TEST_KEEP_TEMP=1. The runner calls it when it finishes.
procedure RemoveOwnedChildRunRoots;
// DAK-383: the sweep over one base folder. False, with the reason in aError, when the folder cannot be enumerated;
// it never raises, so finalization cannot end in a runtime error.
function TryRemoveOwnedChildRunRootsIn(const aBase: string; out aError: string): Boolean;
procedure EnsureTempClean;
procedure EnsureResolverBuilt;
function ResolverExePath: string;
function HostDakExePath: string;
function TryResolveCandidateExe(out aExePath: string; out aError: string): Boolean;
procedure RequireFixInsightOrSkip(out aExePath: string);
procedure RequirePalCmdOrSkip(out aExePath: string);
procedure RequireRealDelphiLsp23OrSkip(out aExePath: string);
function RunProcess(const aExe, aArgs, aWorkDir, aOutputFile: string; out aExitCode: Cardinal): Boolean;
function RunProcessWithTimeout(const aExe, aArgs, aWorkDir, aOutputFile: string;
  const aTimeoutMs: Cardinal; out aExitCode: Cardinal): Boolean;
function RunProcessWithStartHook(const aExe, aArgs, aWorkDir, aOutputFile: string;
  const aTimeoutMs: Cardinal; const aOnStarted: TProcessStartedHook; out aExitCode: Cardinal): Boolean;
function RunResolverProcess(const aArgs, aWorkDir, aOutputFile: string; out aExitCode: Cardinal): Boolean;
function RunCommandProcess(const aExePath, aArgs, aWorkDir, aOutputFile: string;
  out aExitCode: Cardinal): Boolean;
function ReadUtf8TextFile(const aFileName: string): string;
function ParseJsonValue(const aText: string; const aContext: string = ''): TJSONValue;
function ParseJsonObject(const aText: string; const aContext: string = ''): TJSONObject;
procedure RequireJsonObjectKey(const aObject: TJSONObject; const aName: string; out aChild: TJSONObject);
procedure RequireJsonArrayKey(const aObject: TJSONObject; const aName: string; out aChild: TJSONArray);
procedure RequireJsonStringKey(const aObject: TJSONObject; const aName: string);
procedure RequireJsonNumberKey(const aObject: TJSONObject; const aName: string);
function StartSlowPingProcess(out aProcess: THandle; out aThread: THandle; out aError: string): Boolean;
function QuoteArg(const aValue: string): string;
function SetScopedPalCmdMapFixture(const aContent: string; out aMapPath: string): IInterface;
function SetScopedEnvironmentVariable(const aName, aValue: string): IInterface;
function SetScopedEnvironmentVariables(const aNameValuePairs: array of string): IInterface;
function ClearScopedEnvironmentVariable(const aName: string): IInterface;

const
  cAllowFixInsightSkipEnvVar = 'DAK_ALLOW_FIXINSIGHT_SKIP';
  cAllowPalSkipEnvVar = 'DAK_ALLOW_PAL_SKIP';
  cAllowLspSkipEnvVar = 'DAK_ALLOW_LSP_SKIP';
  cMaxTdbFixtureEnvVar = 'DAK_MAXTDB_FIXTURE';
  // DAK-378: neither this runner nor the DAK, MSBuild, compiler, git and svn children
  // the suite starts is fully long-path aware, so every path a test creates below the
  // run root must fit a classic Windows path of MAX_PATH - 1 = 259 characters.
  // Deepest paths measured below the run root (DAK-385, 2026-10-01, DAK_TEST_KEEP_TEMP=1 over
  // RemoveWith, SymbolMap, NativeAnalysisDoctor, NativeAnalysisWorkspace, DfmCheck,
  // PascalAnalyzer, ExternalToolProcess, Utils, Refactor.Transaction, SignatureCommand and
  // DakWorkingPaths; 501 tests, all passed):
  //   136  sm-<8>\repository\.git\modules\deps\a child <4 non-ASCII> (topic)\modules\
  //        nested <1 non-ASCII> (leaf)\objects\<2>\<38 hex> (Test.NativeAnalysisWorkspace,
  //        a git submodule fixture; lengths count UTF-16 characters)
  //   126  symbol-map-api-membership-refresh-project-<8>\.dak\SymbolMapIntrinsicCollision\
  //        symbol-map\v2\semantic-unit-cache.sqlite3 (Test.SymbolMap; persistent cache layout)
  //   124  native-analysis-svn-clean-<8>\working-copy\external\.svn\pristine\... (workspace)
  //   122  remove-with-control-character-literals\.dak\RemoveWithControlCharacterLiteralFixture\
  //        remove-with\<8 hex>\vapp\stderr.log (Test.RemoveWith; 164 before DAK-385)
  //   122  dfm-check-repo-local-reference-source\App\.dak\Sample\dfm-check\runs\<8 hex>\
  //        generated\Win32\Release\Sample_DfmCheck.exe (Test.DfmCheck; 146 before DAK-385)
  // The longest UniqueTempPath folder is 50 characters (a 41-character prefix, a dash and
  // the token). Tests that size their own long paths on purpose (pal-path, pal-no-status,
  // RemoveWith.LongPath, DakWorkingPaths wp-deep) are excluded. Reserve = 136 + a
  // 10-character margin, which also covers a SQLite "-journal" beside the symbol-map cache.
  cRunRootFileReserve = 146;
  cMaxRunRootLength = MAX_PATH - 1 - cRunRootFileReserve;
  // Exit code of a runner that cannot prepare its run root, before any test runs.
  // Distinct from DUnitX (1), run.bat/run.sh (2), fixture child modes (3, 7)
  // and run-dunitx.ps1 (124); 78 is the conventional "configuration error" code.
  cStartupFailureExitCode = 78;

type
  TExternalToolMissingDecision = (etmdFail, etmdSkip);

function MissingExternalToolDecision(const aToolName, aAllowSkipEnvVar, aDiagnostic: string;
  out aMessage: string): TExternalToolMissingDecision;

implementation

uses
  System.RegularExpressions;

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
    fAppliedCount: Integer;
    fHadPreviousValues: TArray<Boolean>;
    fLockHeld: Boolean;
    fNames: TArray<string>;
    fPreviousValues: TArray<string>;
    procedure RestoreAppliedValues(const aAppliedCount: Integer);
  public
    constructor Create(const aNameValuePairs: array of string);
    destructor Destroy; override;
  end;

  // DAK-378: the run root cannot hold the files the suite writes beneath it.
  ETestRunRootTooLong = class(Exception);
  // DAK-378: every drawn UniqueTempPath name was already present.
  ETestTempPathExhausted = class(Exception);

const
  cOutputCreateAttempts = 20;
  cPalCmdMapPathEnvVar = 'DAK_PALCMD_MAP_PATH';
  cTestOutputRootEnvVar = 'DAK_TEST_OUTPUT_ROOT';
  // DAK-383: the top-level runner exports its own identity (PID and creation time) here, so every process it
  // starts, directly or through DAK, inherits it. A child run root records the value in cRunOwnerMarker, which
  // lets the owner remove the roots of children that were killed before their own cleanup ran.
  cRunOwnerEnvVar = 'DAK_TEST_RUN_OWNER';
  cRunOwnerMarker = '.run-owner';
  cRunRootNamePattern = '^run-\d+-[0-9A-F]{8}$';
  // DAK-378: characters of a GUID kept in run-root and UniqueTempPath names. The PID
  // already separates live runs, and each run root holds only its own process's
  // paths, so 32 random bits suffice; the full 36-character GUID spent path budget.
  // UniqueTempPath names are drawn again on a clash (at most cUniqueNameAttempts
  // times); a run root is drawn once, and EnsureTempClean replaces a stale one.
  cUniqueTokenLength = 8;
  cUniqueNameAttempts = 100;
  // A Windows PID is a DWORD: at most 10 decimal digits. The run root is checked as
  // if its PID had that many, so the verdict does not depend on the actual PID.
  cMaxPidDigits = 10;

var
  GRepoRoot: string;
  GTempRoot: string;
  GTempCleaned: Boolean = False;
  // DAK-383: this process's identity when it is the top-level runner; empty in a child run.
  GRunOwner: string = '';
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
  fLockHeld := True;
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
      Inc(fAppliedCount);
      Inc(lIndex);
      Inc(i, 2);
    end;
  except
    try
      RestoreAppliedValues(fAppliedCount);
      fAppliedCount := 0;
    finally
      GEnvironmentLock.Leave;
      fLockHeld := False;
    end;
    raise;
  end;
end;

procedure TScopedEnvironmentVariables.RestoreAppliedValues(const aAppliedCount: Integer);
var
  i: Integer;
begin
  for i := aAppliedCount - 1 downto 0 do
  begin
    if fHadPreviousValues[i] then
      SetEnvironmentVariableOrRaise(fNames[i], fPreviousValues[i])
    else
      ClearEnvironmentVariableOrRaise(fNames[i]);
  end;
end;

destructor TScopedEnvironmentVariables.Destroy;
begin
  if fLockHeld then
  begin
    try
      RestoreAppliedValues(fAppliedCount);
      fAppliedCount := 0;
    finally
      GEnvironmentLock.Leave;
      fLockHeld := False;
    end;
  end;
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

function SetScopedPalCmdMapFixture(const aContent: string; out aMapPath: string): IInterface;
var
  lMapDir: string;
begin
  lMapDir := UniqueTempPath('palcmd-map');
  TDirectory.CreateDirectory(lMapDir);
  aMapPath := TPath.Combine(lMapDir, 'palcmd-map.json');
  TFile.WriteAllText(aMapPath, aContent, TEncoding.UTF8);
  Result := SetScopedEnvironmentVariable(cPalCmdMapPathEnvVar, aMapPath);
end;

function NewRunTempRoot(const aBaseRoot: string): string;
var
  lGuid: TGUID;
  lGuidText: string;
begin
  CreateGUID(lGuid);
  lGuidText := Copy(GUIDToString(lGuid), 2, cUniqueTokenLength);
  Result := TPath.Combine(aBaseRoot, 'run-' + GetCurrentProcessId.ToString + '-' + lGuidText);
end;

function TryValidateRunRoot(const aRunRoot: string; out aError: string): Boolean;
var
  lCheckedLength: Integer;
  lEnvRoot: string;
begin
  aError := '';
  // Count the widest PID, so a parent and the children it starts under the same
  // output root get the same verdict whatever their PIDs are.
  lCheckedLength := Length(aRunRoot) - Length(GetCurrentProcessId.ToString) + cMaxPidDigits;
  if lCheckedLength <= cMaxRunRootLength then
    Exit(True);
  lEnvRoot := Trim(GetEnvironmentVariable(cTestOutputRootEnvVar));
  if lEnvRoot = '' then
    lEnvRoot := '(not set; the root is under the repository)';
  aError := Format('Test run root is too long: "%s" counts as %d characters with a %d-digit PID; ' +
    'the limit is %d (Windows MAX_PATH %d less 1, less %d reserved for test files beneath it). ' +
    '%s="%s". Choose a shorter %s.',
    [aRunRoot, lCheckedLength, cMaxPidDigits, cMaxRunRootLength, MAX_PATH, cRunRootFileReserve,
    cTestOutputRootEnvVar, lEnvRoot, cTestOutputRootEnvVar]);
  Result := False;
end;

function PathHasRepoMarker(const aPath: string): Boolean;
var
  lDir: string;
  lParent: string;
begin
  lDir := ExcludeTrailingPathDelimiter(TPath.GetFullPath(aPath));
  while lDir <> '' do
  begin
    if DirectoryExists(TPath.Combine(lDir, '.git')) or FileExists(TPath.Combine(lDir, '.git')) or
      DirectoryExists(TPath.Combine(lDir, '.svn')) then
      Exit(True);
    lParent := ExcludeTrailingPathDelimiter(ExtractFilePath(lDir));
    if (lParent = '') or SameText(lParent, lDir) then
      Break;
    lDir := lParent;
  end;
  Result := False;
end;

function UniqueTempPathUnderRoot(const aBaseRoot, aPrefix: string): string;
var
  lGuid: TGUID;
begin
  // A short token can repeat; draw again when the name is already present so a kept
  // or concurrent sibling is never reused. The bound turns a broken GUID source or an
  // unreadable base into a named failure instead of an endless loop.
  for var lAttempt := 1 to cUniqueNameAttempts do
  begin
    CreateGUID(lGuid);
    Result := TPath.Combine(aBaseRoot, aPrefix + '-' + Copy(GUIDToString(lGuid), 2, cUniqueTokenLength));
    if not (TDirectory.Exists(Result) or TFile.Exists(Result)) then
      Exit;
  end;
  raise ETestTempPathExhausted.CreateFmt('No unused temp path "%s-<token>" under "%s" after %d attempts.',
    [aPrefix, aBaseRoot, cUniqueNameAttempts]);
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

function MaxTdbFixtureRoot: string;
begin
  Result := Trim(GetEnvironmentVariable(cMaxTdbFixtureEnvVar));
end;

function TempRoot: string;
var
  lEnvRoot: string;
begin
  if GTempRoot = '' then
  begin
    lEnvRoot := Trim(GetEnvironmentVariable(cTestOutputRootEnvVar));
    if lEnvRoot <> '' then
      GTempRoot := NewRunTempRoot(TPath.GetFullPath(lEnvRoot))
    else
      GTempRoot := NewRunTempRoot(TPath.Combine(RepoRoot, 'tests\temp'));
  end;
  Result := GTempRoot;
end;

function UniqueTempPath(const aPrefix: string): string;
begin
  Result := UniqueTempPathUnderRoot(TempRoot, aPrefix);
end;

function NoRepoTempBase: string;
var
  lEnvRoot: string;
begin
  lEnvRoot := Trim(GetEnvironmentVariable(cTestOutputRootEnvVar));
  if lEnvRoot <> '' then
    Result := TPath.GetFullPath(lEnvRoot)
  else
    Result := TPath.Combine(TPath.GetTempPath, 'DelphiAIKit-tests-no-repo');

  if PathHasRepoMarker(Result) then
    Result := TPath.Combine(TPath.GetTempPath, 'DelphiAIKit-tests-no-repo');
end;

function UniqueNoRepoTempPath(const aPrefix: string): string;
begin
  Result := UniqueTempPathUnderRoot(NoRepoTempBase, aPrefix + '-' + GetCurrentProcessId.ToString);
end;

const
  cMaxDeleteDepth = 512;

procedure NoteDeleteFailure(var aError: string; const aPath, aWhat: string);
begin
  if aError = '' then
    aError := 'could not ' + aWhat + ' ' + aPath + ': ' + SysErrorMessage(GetLastError);
end;

// Removes one directory entry without following it: a reparse point is deleted as a link.
procedure DeleteEntryOrTree(const aPath: string; aAttributes: DWORD; aDepth: Integer; var aError: string);
var
  lData: TWin32FindData;
  lFind: THandle;
  lName: string;
begin
  if (aAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
  begin
    SetFileAttributes(PChar(aPath), FILE_ATTRIBUTE_NORMAL);
    if not DeleteFile(PChar(aPath)) then
      NoteDeleteFailure(aError, aPath, 'delete');
    Exit;
  end;
  if (aAttributes and FILE_ATTRIBUTE_REPARSE_POINT) = 0 then
  begin
    if aDepth > cMaxDeleteDepth then
    begin
      if aError = '' then
        aError := 'folder nesting exceeds ' + cMaxDeleteDepth.ToString + ' levels below ' + aPath;
      Exit;
    end;
    lFind := FindFirstFile(PChar(aPath + '\*'), lData);
    if lFind <> INVALID_HANDLE_VALUE then
    begin
      try
        repeat
          lName := lData.cFileName;
          if (lName <> '.') and (lName <> '..') then
            DeleteEntryOrTree(aPath + '\' + lName, lData.dwFileAttributes, aDepth + 1, aError);
        until not FindNextFile(lFind, lData);
      finally
        Winapi.Windows.FindClose(lFind);
      end;
    end;
  end;
  SetFileAttributes(PChar(aPath), FILE_ATTRIBUTE_DIRECTORY);
  if not RemoveDirectory(PChar(aPath)) then
    NoteDeleteFailure(aError, aPath, 'remove');
end;

function TryDeleteTreeLongPath(const aPath: string; out aError: string): Boolean;
var
  lAttributes: DWORD;
  lPath: string;
begin
  aError := '';
  if aPath = '' then
    Exit(True);
  // A reserve above MAX_PATH always selects the extended-length form.
  lPath := ExcludeTrailingPathDelimiter(LongPathSafe(aPath, 1000));
  lAttributes := GetFileAttributes(PChar(lPath));
  if lAttributes <> INVALID_FILE_ATTRIBUTES then
    DeleteEntryOrTree(lPath, lAttributes, 0, aError);
  Result := aError = '';
end;

procedure DeleteTempPath(const aPath: string);
var
  lError: string;
begin
  if (aPath = '') or (Trim(GetEnvironmentVariable('DAK_TEST_KEEP_TEMP')) = '1') then
    Exit;
  if not TryDeleteTreeLongPath(aPath, lError) then
    raise EInOutError.Create('DelphiAIKit.Tests ' + lError);
end;

// DAK-383: PID plus creation time identifies this process even when its PID is reused later.
function CurrentProcessIdentity: string;
var
  lCreated, lExited, lKernel, lUser: TFileTime;
begin
  if not GetProcessTimes(GetCurrentProcess, lCreated, lExited, lKernel, lUser) then
    RaiseLastOSError;
  Result := UIntToStr(GetCurrentProcessId) + ' ' +
    UIntToStr((UInt64(lCreated.dwHighDateTime) shl 32) or lCreated.dwLowDateTime);
end;

// DAK-383: the first runner in a process tree owns its descendants' run roots; a child run marks its own root
// with the owner it inherited, so the owner can recognise it by identity and never touches another run's roots.
procedure RegisterRunOwner(const aRunRoot: string);
var
  lOwner: string;
begin
  lOwner := Trim(GetEnvironmentVariable(cRunOwnerEnvVar));
  if lOwner = '' then
  begin
    GRunOwner := CurrentProcessIdentity;
    if not SetEnvironmentVariable(PChar(cRunOwnerEnvVar), PChar(GRunOwner)) then
      RaiseLastOSError;
  end else
    TFile.WriteAllText(TPath.Combine(aRunRoot, cRunOwnerMarker), lOwner, TEncoding.ASCII);
end;

procedure EnsureTempClean;
var
  lError: string;
  lTemp: string;
begin
  if GTempCleaned then
    Exit;
  lTemp := TempRoot;
  if not TryValidateRunRoot(lTemp, lError) then
    raise ETestRunRootTooLong.Create(lError);
  if (Trim(GetEnvironmentVariable('DAK_TEST_KEEP_TEMP')) <> '1') and not TryDeleteTreeLongPath(lTemp, lError) then
    raise EInOutError.Create('DelphiAIKit.Tests ' + lError);
  TDirectory.CreateDirectory(lTemp);
  RegisterRunOwner(lTemp);
  GTempCleaned := True;
end;

// DAK-378: an exception raised in a unit initialization ends the process with
// "Runtime error 217" and no message. Report why the run root cannot be prepared
// and stop before any test runs.
procedure PrepareTempRootOrHalt;
begin
  try
    EnsureTempClean;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'DelphiAIKit.Tests cannot prepare its test run root: ' + E.Message);
      Halt(cStartupFailureExitCode);
    end;
  end;
end;

// DAK-383: children killed by an owned job, a deadline or TerminateProcess never reach their own cleanup and
// leave an empty run root beside ours. Only roots marked with this runner's identity are removed, so a
// concurrent run's roots, and a root kept by DAK_TEST_KEEP_TEMP=1, are never touched.
function RunOwnerIdentity: string;
begin
  Result := GRunOwner;
end;

function TryRemoveOwnedChildRunRootsIn(const aBase: string; out aError: string): Boolean;
var
  lMarker: string;
  lMarkerText: string;
  lPath: string;
  lPaths: TArray<string>;
begin
  aError := '';
  Result := True;
  if (GRunOwner = '') or (GTempRoot = '') or (Trim(GetEnvironmentVariable('DAK_TEST_KEEP_TEMP')) = '1') then
    Exit;
  try
    lPaths := TDirectory.GetDirectories(aBase);
  except
    on E: Exception do
    begin
      aError := 'DelphiAIKit.Tests could not list ' + aBase + ' to remove its child run roots: ' + E.Message;
      Exit(False);
    end;
  end;
  for lPath in lPaths do
  begin
    if SameText(lPath, GTempRoot) or not TRegEx.IsMatch(ExtractFileName(lPath), cRunRootNamePattern) then
      Continue;
    lMarker := TPath.Combine(lPath, cRunOwnerMarker);
    if not TFile.Exists(lMarker) then
      Continue;
    try
      lMarkerText := TFile.ReadAllText(lMarker, TEncoding.ASCII);
    except
      on E: EInOutError do
        // A marker another run's child is still writing is not ours: its owner cannot be this finished run.
        Continue;
    end;
    if lMarkerText <> GRunOwner then
      Continue;
    if not TryDeleteTreeLongPath(lPath, lMarkerText) then
      Writeln(ErrOutput, 'DelphiAIKit.Tests could not remove its child run root ' + lPath + ': ' + lMarkerText);
  end;
end;

procedure RemoveOwnedChildRunRoots;
var
  lError: string;
begin
  if GTempRoot = '' then
    Exit;
  if not TryRemoveOwnedChildRunRootsIn(ExtractFileDir(GTempRoot), lError) then
    Writeln(ErrOutput, lError);
end;

procedure CleanupTempRoot;
var
  lError: string;
begin
  if (Trim(GetEnvironmentVariable('DAK_TEST_KEEP_TEMP')) = '1') or (GTempRoot = '') then
    Exit;
  RemoveOwnedChildRunRoots;
  // Finalization must not raise: report what stays behind.
  if not TryDeleteTreeLongPath(GTempRoot, lError) then
    Writeln(ErrOutput, 'DelphiAIKit.Tests could not remove its run root ' + GTempRoot + ': ' + lError);
end;

function RunProcess(const aExe, aArgs, aWorkDir, aOutputFile: string; out aExitCode: Cardinal): Boolean;
begin
  // One bounded launch path for all synchronous test commands.
  Result := RunProcessWithTimeout(aExe, aArgs, aWorkDir, aOutputFile, 1800000, aExitCode);
end;

function RunProcessWithTimeout(const aExe, aArgs, aWorkDir, aOutputFile: string;
  const aTimeoutMs: Cardinal; out aExitCode: Cardinal): Boolean;
begin
  Result := RunProcessWithStartHook(aExe, aArgs, aWorkDir, aOutputFile, aTimeoutMs, nil, aExitCode);
end;

function RunProcessWithStartHook(const aExe, aArgs, aWorkDir, aOutputFile: string;
  const aTimeoutMs: Cardinal; const aOnStarted: TProcessStartedHook; out aExitCode: Cardinal): Boolean;
var
  lCmdLine: string;
  lCreateError: Cardinal;
  lLastError: Cardinal;
  lOutHandle: THandle;
  lOutputDir: string;
  lPi: TProcessInformation;
  lJob: THandle;
  lJobInfo: TJobObjectExtendedLimitInformation;
  lSa: TSecurityAttributes;
  lSi: TStartupInfo;
  lWait: Cardinal;
  lWorkDir: string;
begin
  Result := False;
  aExitCode := STILL_ACTIVE;
  lOutHandle := INVALID_HANDLE_VALUE;
  lCreateError := ERROR_SUCCESS;
  lJob := 0;
  if aOutputFile <> '' then
  begin
    lOutputDir := ExtractFileDir(aOutputFile);
    if lOutputDir <> '' then
      ForceDirectories(lOutputDir);
    FillChar(lSa, SizeOf(lSa), 0);
    lSa.nLength := SizeOf(lSa);
    lSa.bInheritHandle := True;
    // A scanner or a previous child's closing writer can hold the file briefly.
    // Retry only those transient errors, for at most cOutputCreateAttempts * 50 ms.
    for var lAttempt := 1 to cOutputCreateAttempts do
    begin
      lOutHandle := CreateFile(PChar(aOutputFile), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, 0);
      if lOutHandle <> INVALID_HANDLE_VALUE then
        Break;
      lCreateError := GetLastError;
      if (lCreateError <> ERROR_PATH_NOT_FOUND) and (lCreateError <> ERROR_FILE_NOT_FOUND) and
        (lCreateError <> ERROR_ACCESS_DENIED) and (lCreateError <> ERROR_SHARING_VIOLATION) then
        Break;
      if lAttempt < cOutputCreateAttempts then
      begin
        if lOutputDir <> '' then
          ForceDirectories(lOutputDir);
        Sleep(50);
      end;
    end;
    if lOutHandle = INVALID_HANDLE_VALUE then
      raise Exception.Create('Failed to create output file: ' + aOutputFile + ' (' +
        SysErrorMessage(lCreateError) + ')');
  end;

  try
    lJob := CreateJobObject(nil, nil);
    if lJob = 0 then
      RaiseLastOSError;
    lJobInfo := Default(TJobObjectExtendedLimitInformation);
    lJobInfo.BasicLimitInformation.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if not SetInformationJobObject(lJob, JobObjectExtendedLimitInformation, @lJobInfo, SizeOf(lJobInfo)) then
      RaiseLastOSError;
    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    lSi.wShowWindow := SW_HIDE;
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

    if not CreateProcess(PChar(aExe), PChar(lCmdLine), nil, nil, True, CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, PChar(lWorkDir), lSi, lPi) then
    begin
      lLastError := GetLastError;
      raise Exception.Create('Process start failed: ' + SysErrorMessage(lLastError));
    end;
    try
      if not AssignProcessToJobObject(lJob, lPi.hProcess) then
      begin
        lLastError := GetLastError;
        if not TerminateProcess(lPi.hProcess, ERROR_PROCESS_ABORTED) then
          RaiseLastOSError;
        raise Exception.Create('Cannot contain test child: ' + SysErrorMessage(lLastError));
      end;
      if ResumeThread(lPi.hThread) = Cardinal(-1) then
        RaiseLastOSError;
      // An exception from the hook leaves through the finally blocks below; closing
      // the job then stops the child and every descendant.
      if Assigned(aOnStarted) then
        aOnStarted(lPi.hProcess);
      lWait := WaitForSingleObject(lPi.hProcess, aTimeoutMs);
      if lWait = WAIT_TIMEOUT then
      begin
        if not TerminateJobObject(lJob, Cardinal(ERROR_TIMEOUT)) then
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
        if not GetExitCodeProcess(lPi.hProcess, aExitCode) then
        begin
          lLastError := GetLastError;
          raise Exception.Create('Timed-out process exit code failed: ' + SysErrorMessage(lLastError));
        end;
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
    if lJob <> 0 then
      CloseHandle(lJob);
    if lOutHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(lOutHandle);
  end;
end;

function RunResolverProcess(const aArgs, aWorkDir, aOutputFile: string; out aExitCode: Cardinal): Boolean;
var
  lExePath: string;
begin
  EnsureResolverBuilt;
  lExePath := ResolverExePath;
  Result := RunProcess(lExePath, aArgs, aWorkDir, aOutputFile, aExitCode);
end;

function RunCommandProcess(const aExePath, aArgs, aWorkDir, aOutputFile: string;
  out aExitCode: Cardinal): Boolean;
begin
  Result := RunProcess(aExePath, aArgs, aWorkDir, aOutputFile, aExitCode);
end;

function ReadUtf8TextFile(const aFileName: string): string;
var
  lReader: TStreamReader;
  lStream: TFileStream;
begin
  Assert.IsTrue(TFile.Exists(aFileName), 'Expected output file: ' + aFileName);
  lStream := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyNone);
  try
    lReader := TStreamReader.Create(lStream, TEncoding.UTF8, True);
    try
      Result := lReader.ReadToEnd;
    finally
      lReader.Free;
    end;
  finally
    lStream.Free;
  end;
end;

function ParseJsonValue(const aText: string; const aContext: string): TJSONValue;
var
  lContext: string;
begin
  Result := TJSONValue.ParseJSONValue(aText);
  if Result <> nil then
    Exit;
  lContext := aContext;
  if lContext = '' then
    lContext := aText;
  Assert.Fail('Expected JSON output. Context: ' + lContext);
end;

function ParseJsonObject(const aText: string; const aContext: string): TJSONObject;
var
  lContext: string;
  lValue: TJSONValue;
begin
  Result := nil;
  lValue := ParseJsonValue(aText, aContext);
  if lValue is TJSONObject then
    Exit(TJSONObject(lValue));
  try
    lContext := aContext;
    if lContext = '' then
      lContext := aText;
    Assert.Fail('Expected JSON object. Context: ' + lContext);
  finally
    lValue.Free;
  end;
end;

procedure RequireJsonObjectKey(const aObject: TJSONObject; const aName: string; out aChild: TJSONObject);
begin
  Assert.IsNotNull(aObject.Values[aName], 'Expected JSON key: ' + aName);
  Assert.IsTrue(aObject.Values[aName] is TJSONObject, 'Expected JSON object key: ' + aName);
  aChild := aObject.Values[aName] as TJSONObject;
end;

procedure RequireJsonArrayKey(const aObject: TJSONObject; const aName: string; out aChild: TJSONArray);
begin
  Assert.IsNotNull(aObject.Values[aName], 'Expected JSON key: ' + aName);
  Assert.IsTrue(aObject.Values[aName] is TJSONArray, 'Expected JSON array key: ' + aName);
  aChild := aObject.Values[aName] as TJSONArray;
end;

procedure RequireJsonStringKey(const aObject: TJSONObject; const aName: string);
begin
  Assert.IsNotNull(aObject.Values[aName], 'Expected JSON key: ' + aName);
  Assert.IsTrue(aObject.Values[aName] is TJSONString, 'Expected JSON string key: ' + aName);
end;

procedure RequireJsonNumberKey(const aObject: TJSONObject; const aName: string);
begin
  Assert.IsNotNull(aObject.Values[aName], 'Expected JSON key: ' + aName);
  Assert.IsTrue(aObject.Values[aName] is TJSONNumber, 'Expected JSON number key: ' + aName);
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
  lError: string;
  lResolverExe: string;
begin
  if GResolverBuilt then
    Exit;
  if not TryResolveCandidateExe(lResolverExe, lError) then
    Assert.Fail(lError);
  GResolverExe := lResolverExe;
  GResolverBuilt := True;
end;

function HostDakExePath: string;
begin
  // The known-good build host. Tests must never run it in place of the candidate.
  Result := TPath.GetFullPath(TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe'));
end;

function TryResolveCandidateExe(out aExePath: string; out aError: string): Boolean;
var
  lBinaryType: Cardinal;
  lLastError: Cardinal;
begin
  aError := '';
  aExePath := Trim(GetEnvironmentVariable('DAK_TEST_RESOLVER_EXE'));
  if aExePath = '' then
    aExePath := TPath.Combine(RepoRoot, 'bin\Debug\DelphiAIKit.exe');
  aExePath := TPath.GetFullPath(aExePath);
  if not FileExists(aExePath) then
  begin
    aError := 'Build the Win64 Debug DAK candidate before testing, or set DAK_TEST_RESOLVER_EXE: ' + aExePath;
    Exit(False);
  end;
  if not GetBinaryType(PChar(aExePath), lBinaryType) then
  begin
    lLastError := GetLastError;
    aError := 'Unreadable DAK candidate: ' + aExePath + ' (' + SysErrorMessage(lLastError) + ')';
    Exit(False);
  end;
  if lBinaryType <> SCS_64BIT_BINARY then
  begin
    aError := 'Tests require a Win64 DAK candidate: ' + aExePath;
    Exit(False);
  end;
  Result := True;
end;

function ResolverExePath: string;
begin
  // Every caller runs the validated candidate. A missing candidate fails here
  // instead of silently running the build host.
  EnsureResolverBuilt;
  Result := GResolverExe;
end;

function MissingExternalToolDecision(const aToolName, aAllowSkipEnvVar, aDiagnostic: string;
  out aMessage: string): TExternalToolMissingDecision;
var
  lDiagnostic: string;
begin
  lDiagnostic := Trim(aDiagnostic);
  if SameText(Trim(GetEnvironmentVariable(aAllowSkipEnvVar)), '1') then
  begin
    Result := TExternalToolMissingDecision.etmdSkip;
    aMessage := Format('%s not found; %s=1 explicitly allows this external-tool acceptance test to be skipped.',
      [aToolName, aAllowSkipEnvVar]);
  end else
  begin
    Result := TExternalToolMissingDecision.etmdFail;
    aMessage := Format('%s not found. Install or configure it, or set %s=1 to explicitly skip this external-tool acceptance test.',
      [aToolName, aAllowSkipEnvVar]);
  end;
  if lDiagnostic <> '' then
    aMessage := aMessage + ' ' + lDiagnostic;
end;

procedure RequireExternalToolOrSkip(const aToolName, aAllowSkipEnvVar, aDiagnostic: string;
  out aExePath: string);
var
  lDecision: TExternalToolMissingDecision;
  lMessage: string;
begin
  aExePath := '';
  lDecision := MissingExternalToolDecision(aToolName, aAllowSkipEnvVar, aDiagnostic, lMessage);
  if lDecision = TExternalToolMissingDecision.etmdSkip then
  begin
    Assert.Pass(lMessage);
    Exit;
  end;
  Assert.Fail(lMessage);
end;

procedure RequireFixInsightOrSkip(out aExePath: string);
begin
  if TryResolveFixInsightExe(nil, aExePath) then
    Exit;

  RequireExternalToolOrSkip('FixInsightCL.exe', cAllowFixInsightSkipEnvVar, '', aExePath);
end;

procedure RequirePalCmdOrSkip(out aExePath: string);
var
  lError: string;
begin
  if TryResolvePalCmdExe('', aExePath, lError) then
    Exit;

  RequireExternalToolOrSkip('PALCMD', cAllowPalSkipEnvVar, lError, aExePath);
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

  RequireExternalToolOrSkip('DelphiLSP.exe for Delphi 23.0', cAllowLspSkipEnvVar,
    lError, aExePath);
end;

initialization
  GEnvironmentLock := TCriticalSection.Create;
  PrepareTempRootOrHalt;

finalization
  CleanupTempRoot;
  GEnvironmentLock.Free;

end.
