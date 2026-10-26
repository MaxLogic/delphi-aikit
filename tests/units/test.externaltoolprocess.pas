unit Test.ExternalToolProcess;

interface

uses
  DUnitX.TestFramework;

type
  // The shared child-process runner must hand each child only its own standard handles.
  // Concurrent launches with inherited pipes otherwise leak one child's pipe end into the
  // other child, and the first reader only sees EOF when the unrelated child exits.
  [TestFixture]
  [Category('Slow')]
  TExternalToolProcessTests = class
  public
    [Test]
    procedure ConcurrentChildrenDoNotInheritEachOthersPipes;
    [Test]
    procedure CreateInheritablePipeClosesBothHandlesWhenSetupFails;
    [Test]
    procedure SecondPipeSetupFailureClosesBothPairs;
    [Test]
    [TestCase('Default child', '1')]
    [TestCase('Concurrent children', '2')]
    procedure PipeAcquisitionClosesEarlierHandlesWhenNulFails(aPipeCount: Integer);
    [Test]
    [TestCase('Plain helper', '0')]
    [TestCase('Timeout helper', '1')]
    [TestCase('PAL help', '2')]
    procedure NoninteractiveChildrenHaveNoConsole(aRoute: Integer);
    [Test]
    procedure DefaultExternalToolHasNoConsole;
    [Test]
    [TestCase('Test helper', '0')]
    [TestCase('External tool helper', '1')]
    procedure DescendantsOfHeadlessChildrenStayWindowless(aRoute: Integer);
    [Test]
    procedure TimeoutStopsDescendants;
    [Test]
    procedure NormalExitStopsDescendants;
    [Test]
    procedure StartFailureStopsDescendants;
    [Test]
    procedure ExternalToolStopsWhenOwnerIsInterrupted;
    [Test]
    procedure RunProcessRetriesTransientOutputLock;
    [Test]
    procedure ParallelTestRunsUseIndependentRoots;
    [Test]
    procedure OverlongOutputRootFailsAtStartupWithNamedLimit;
    [Test]
    procedure NativeHelperCapturesLargeOutputAndExitCode;
    [Test]
    procedure ChildRunRootSweepRemovesOnlyRootsMarkedWithThisRunsIdentity;
    [Test]
    procedure ChildRunRootSweepReportsAnUnlistableFolderInsteadOfRaising;
    [Test]
    procedure TestRunnerSuppressesErrorDialogsWhateverItsParentMode;
    [Test]
    [TestCase('Text file', '0')]
    [TestCase('DOS stub without a PE header', '1')]
    [TestCase('Truncated DOS header', '2')]
    [TestCase('PE offset past the end', '3')]
    procedure InvalidExecutableFailsWithNamedErrorBeforeLaunch(aVariant: Integer);
  end;

implementation

uses
  System.Classes, System.DateUtils, System.Diagnostics, System.IOUtils, System.RegularExpressions, System.StrUtils,
  System.SysUtils, System.Threading,
  Winapi.Windows,
  Dak.ExternalToolProcess, Dak.PascalAnalyzerRunner,
  Test.Support;

// DAK-383: a child killed before its own cleanup leaves a run root beside ours. The runner removes the roots that
// carry its identity, and only those: another run's root, an unmarked one and a non-run folder must survive.
procedure TExternalToolProcessTests.ChildRunRootSweepRemovesOnlyRootsMarkedWithThisRunsIdentity;
const
  cMarker = '.run-owner';
var
  lBase: string;
  lForeign: string;
  lKeepGuard: IInterface;
  lOtherFolder: string;
  lOwned: string;
  lUnmarked: string;

  procedure MakeRoot(const aPath, aMarkerText: string);
  begin
    TDirectory.CreateDirectory(aPath);
    if aMarkerText <> '' then
      TFile.WriteAllText(TPath.Combine(aPath, cMarker), aMarkerText, TEncoding.ASCII);
  end;

begin
  if RunOwnerIdentity = '' then
    Assert.Pass('A child run owns no roots, so there is nothing to sweep.');
  // The sweep below runs mid-run; under a caller's DAK_TEST_KEEP_TEMP=1 it must not touch the roots kept so far.
  if Trim(GetEnvironmentVariable('DAK_TEST_KEEP_TEMP')) = '1' then
    Assert.Pass('DAK_TEST_KEEP_TEMP=1 keeps every root, so the sweep is not exercised.');
  lBase := ExtractFileDir(TempRoot);
  // Impossible PIDs keep these names from colliding with any live run root.
  lOwned := TPath.Combine(lBase, 'run-4294967290-0A0A0A0A');
  lForeign := TPath.Combine(lBase, 'run-4294967291-0B0B0B0B');
  lUnmarked := TPath.Combine(lBase, 'run-4294967292-0C0C0C0C');
  lOtherFolder := TPath.Combine(lBase, 'dak383-not-a-run-root');
  try
    MakeRoot(lOwned, RunOwnerIdentity);
    MakeRoot(lForeign, '4294967295 1');
    MakeRoot(lUnmarked, '');
    MakeRoot(lOtherFolder, RunOwnerIdentity);

    lKeepGuard := SetScopedEnvironmentVariable('DAK_TEST_KEEP_TEMP', '1');
    RemoveOwnedChildRunRoots;
    Assert.IsTrue(TDirectory.Exists(lOwned), 'DAK_TEST_KEEP_TEMP=1 keeps everything');
    // Release the first guard before the second is taken: guards restore in the order they are released.
    lKeepGuard := nil;
    lKeepGuard := ClearScopedEnvironmentVariable('DAK_TEST_KEEP_TEMP');
    RemoveOwnedChildRunRoots;
    Assert.IsFalse(TDirectory.Exists(lOwned), 'A root marked with this run''s identity must be removed');
    Assert.IsTrue(TDirectory.Exists(lForeign), 'Another run''s root must stay');
    Assert.IsTrue(TDirectory.Exists(lUnmarked), 'An unmarked root must stay');
    Assert.IsTrue(TDirectory.Exists(lOtherFolder), 'A folder that is not a run root must stay');
  finally
    lKeepGuard := nil;
    for var lPath in [lOwned, lForeign, lUnmarked, lOtherFolder] do
      if TDirectory.Exists(lPath) then
        TDirectory.Delete(lPath, True);
  end;
end;

// DAK-378: an exception out of finalization ends the run with "Runtime error 217", so the sweep must report an
// unlistable folder and return.
procedure TExternalToolProcessTests.ChildRunRootSweepReportsAnUnlistableFolderInsteadOfRaising;
var
  lError: string;
  lMissing: string;
begin
  if RunOwnerIdentity = '' then
    Assert.Pass('A child run owns no roots, so the sweep does nothing.');
  if Trim(GetEnvironmentVariable('DAK_TEST_KEEP_TEMP')) = '1' then
    Assert.Pass('DAK_TEST_KEEP_TEMP=1 skips the sweep before it lists anything.');
  lMissing := UniqueTempPath('dak383-missing');
  Assert.IsFalse(TDirectory.Exists(lMissing), lMissing);
  Assert.IsFalse(TryRemoveOwnedChildRunRootsIn(lMissing, lError), 'An unlistable folder must be reported');
  Assert.IsTrue(lError.Contains(lMissing), lError);
end;

procedure TExternalToolProcessTests.NativeHelperCapturesLargeOutputAndExitCode;
var
  lGuard: IInterface;
  lPath: string;
  lLines: TArray<string>;
  lExit: Cardinal;
begin
  lPath := UniqueTempPath('native-large-output.log');
  lGuard := SetScopedEnvironmentVariables(['DAK_TEST_LARGE_OUTPUT_CHILD', '1']);
  Assert.IsNotNull(lGuard);
  Assert.IsTrue(RunProcessWithTimeout(ParamStr(0), '', RepoRoot, lPath, 30000, lExit),
    'The native helper must finish without blocking on either stream');
  Assert.AreEqual(Cardinal(7), lExit, 'Preserve the child exit code');
  lLines := TFile.ReadAllLines(lPath);
  Assert.AreEqual<Integer>(40000, Length(lLines), 'Capture every stdout and stderr line');
  for var i := 0 to 19999 do
  begin
    Assert.AreEqual('stdout ' + IntToStr(i) + ' ' + StringOfChar('x', 96), lLines[i * 2]);
    Assert.AreEqual('stderr ' + IntToStr(i) + ' ' + StringOfChar('y', 96), lLines[i * 2 + 1]);
  end;
end;

// Fresh directories in aBase whose names match aNamePattern (a regex on the name) and
// were created at or after aSince. The time filter keeps an older kept directory that
// carries a reused PID out of the result.
function FreshDirectories(const aBase, aNamePattern: string; const aSince: TDateTime): TArray<string>;
var
  lPattern: string;
  lSince: TDateTime;
begin
  Result := nil;
  if (aBase = '') or (not TDirectory.Exists(aBase)) then
    Exit;
  lPattern := aNamePattern;
  lSince := aSince;
  Result := TDirectory.GetDirectories(aBase, '*',
    function(const aPath: string; const aSearchRec: TSearchRec): Boolean
    begin
      // aPath is the searched directory; the candidate is aSearchRec.Name inside it.
      Result := TRegEx.IsMatch(aSearchRec.Name, lPattern) and
        (TDirectory.GetCreationTime(TPath.Combine(aPath, aSearchRec.Name)) >= lSince);
    end);
end;

// The children keep their temp output (DAK_TEST_KEEP_TEMP=1) so their run roots can be
// checked, so we remove what they left: run-<pid>-<token> run roots and the
// <prefix>-<pid>-<token> folders UniqueNoRepoTempPath gives them.
procedure DeleteChildRunArtifacts(const aRunBase, aNoRepoBase: string; aPid: Cardinal; const aSince: TDateTime);
var
  lPidText: string;
begin
  if aPid = 0 then
    Exit;
  lPidText := UIntToStr(aPid);
  for var lPath in FreshDirectories(aRunBase, '^run-' + lPidText + '-[0-9A-F]{8}$', aSince) do
    DeleteTempPath(lPath);
  for var lPath in FreshDirectories(aNoRepoBase, '^.+-' + lPidText + '-[0-9A-F]{8}$', aSince) do
    DeleteTempPath(lPath);
end;

procedure TExternalToolProcessTests.ParallelTestRunsUseIndependentRoots;
const
  cFilters: array[0..3] of string = ('Test.Utils', 'Test.Utils', 'Test.SourceContext', 'Test.SourceContext');
  cLabels: array[0..3] of string = ('Failed', 'Errored', 'Leaked', 'Ignored');
  cChildOutputExcerptLength = 2048;
var
  lTasks: TArray<ITask>;
  lBase: string;
  lChildNoRepoBase: string;
  lChildRoots: array[0..3] of string;
  lGuard: IInterface;
  lDetail: string;
  lLogDir, lLog, lText: string;
  lRoots: TArray<string>;
  lExitCodes: array[0..3] of Cardinal;
  lCompleted: array[0..3] of Boolean;
  lMatch: TMatch;
  lPids: array[0..3] of Cardinal;
  lStartTime: TDateTime;

  function StartRun(aIndex: Integer): ITask;
  begin
    Result := TTask.Run(
      procedure
      begin
        lCompleted[aIndex] := RunProcessWithStartHook(ParamStr(0), '--run:' + cFilters[aIndex], RepoRoot,
          TPath.Combine(lLogDir, IntToStr(aIndex) + '.log'), 30000,
          procedure(aProcess: THandle)
          begin
            lPids[aIndex] := GetProcessId(aProcess);
          end, lExitCodes[aIndex]);
      end);
  end;

begin
  // The children share this run's own output root, as parallel suites sharing one
  // DAK_TEST_OUTPUT_ROOT do, so each child's run root is as long as ours and fits
  // cMaxRunRootLength whenever ours does. Nesting them below our run root would not.
  lBase := ExtractFileDir(TempRoot);
  lLogDir := UniqueTempPath('par-logs');
  TDirectory.CreateDirectory(lLogDir);
  // Directory times can trail the clock slightly; one second of slack is enough to
  // exclude a stale kept root that happens to carry a reused PID.
  lStartTime := IncSecond(Now, -1);
  for var i := 0 to High(lPids) do
    lPids[i] := 0;
  try
    // DAK_TEST_KEEP_TEMP keeps each child's run root after it exits, so we can check it.
    lGuard := SetScopedEnvironmentVariables(['DAK_TEST_OUTPUT_ROOT', lBase, 'DAK_TEST_KEEP_TEMP', '1']);
    Assert.IsNotNull(lGuard);
    // Resolved under the children's environment: where their no-repo folders go.
    lChildNoRepoBase := NoRepoTempBase;
    SetLength(lTasks, Length(cFilters));
    for var i := 0 to High(cFilters) do
      lTasks[i] := StartRun(i);
    TTask.WaitForAll(lTasks);
    lGuard := nil;
    // Collect assertions on the DUnitX runner thread, after all children and
    // inherited capture handles have closed.
    for var i := 0 to High(cFilters) do
    begin
      lLog := TPath.Combine(lLogDir, IntToStr(i) + '.log');
      // The log is deleted with our run root, so failures carry the child's opening output.
      lText := '';
      if TFile.Exists(lLog) then
        lText := TFile.ReadAllText(lLog);
      lDetail := lLog + sLineBreak + Copy(lText, 1, cChildOutputExcerptLength);
      Assert.IsTrue(lCompleted[i], 'Child run must complete within its deadline: ' + lDetail);
      Assert.AreEqual(Cardinal(0), lExitCodes[i], lDetail);
      lMatch := TRegEx.Match(lText, 'Tests Found\s+:\s+(\d+)');
      Assert.IsTrue(lMatch.Success, lDetail);
      Assert.IsTrue(StrToInt(lMatch.Groups[1].Value) > 0, lDetail);
      for var lLabel in cLabels do
        Assert.IsTrue(TRegEx.IsMatch(lText, 'Tests ' + lLabel + '\s+:\s+0(?:\s|$)'), lDetail);
      // Exactly one fresh run root per child, named after that child's PID.
      lRoots := FreshDirectories(lBase, '^run-' + UIntToStr(lPids[i]) + '-[0-9A-F]{8}$', lStartTime);
      Assert.AreEqual<Integer>(1, Length(lRoots), 'Each child must own one run root: ' + lDetail);
      lChildRoots[i] := lRoots[0];
      Assert.AreNotEqual(TempRoot, lChildRoots[i], 'A child must not reuse the parent run root');
      for var j := 0 to i - 1 do
        Assert.AreNotEqual(lChildRoots[j], lChildRoots[i], 'Each child must own a distinct run root');
    end;
  finally
    // Restore DAK_TEST_KEEP_TEMP first so the caller's own setting decides.
    lGuard := nil;
    for var i := 0 to High(lPids) do
      DeleteChildRunArtifacts(lBase, lChildNoRepoBase, lPids[i], lStartTime);
  end;
end;

// DAK-378: a root the runner cannot use must stop it at startup with a named reason,
// not with "Runtime error 217" from a unit initialization, and must create nothing there.
procedure TExternalToolProcessTests.OverlongOutputRootFailsAtStartupWithNamedLimit;
var
  lBase: string;
  lExit: Cardinal;
  lGuard: IInterface;
  lLog: string;
  lPadLength: Integer;
  lRoot: string;
  lText: string;
begin
  lBase := UniqueTempPath('long-root');
  TDirectory.CreateDirectory(lBase);
  // The root alone already exceeds the run-root limit by one character (or more when
  // the base itself is that long), so the run root beneath it does too.
  lPadLength := cMaxRunRootLength - Length(lBase);
  if lPadLength < 1 then
    lPadLength := 1;
  lRoot := TPath.Combine(lBase, StringOfChar('x', lPadLength));
  Assert.IsTrue(Length(lRoot) > cMaxRunRootLength, 'The root must exceed the limit: ' + lRoot);
  lLog := TPath.Combine(lBase, 'child.log');
  lGuard := SetScopedEnvironmentVariables(['DAK_TEST_OUTPUT_ROOT', lRoot]);
  Assert.IsNotNull(lGuard);
  Assert.IsTrue(RunProcessWithTimeout(ParamStr(0), '--run:Test.Utils', RepoRoot, lLog, 60000, lExit),
    'The runner must stop within its deadline: ' + lLog);
  lGuard := nil;
  lText := TFile.ReadAllText(lLog);
  Assert.AreEqual(Cardinal(cStartupFailureExitCode), lExit, lText);
  Assert.IsTrue(lText.Contains('Test run root is too long'), lText);
  Assert.IsTrue(lText.Contains('the limit is ' + IntToStr(cMaxRunRootLength)), lText);
  Assert.IsTrue(lText.Contains('DAK_TEST_OUTPUT_ROOT="' + lRoot + '"'), lText);
  Assert.IsFalse(lText.Contains('Runtime error'), lText);
  Assert.IsFalse(TDirectory.Exists(lRoot), 'Nothing may be created at the rejected root: ' + lRoot);
end;

type
  EInjectedStartFailure = class(Exception);

function HeadlessChildEnvironment(aDescendant: Boolean): IInterface;
begin
  Result := SetScopedEnvironmentVariables(['DAK_TEST_HEADLESS_CHILD', '1',
    'DAK_TEST_HEADLESS_RUNNER_PID', UIntToStr(GetCurrentProcessId),
    'DAK_TEST_HEADLESS_DESCENDANT', IfThen(aDescendant, '1', '0')]);
end;

// A windowless console is still shared: a child launched with default flags under
// a headless runner has no console window, but it lists the runner as a member of
// its console. Separate membership plus SW_HIDE proves the helper's own policy.
procedure AssertHeadlessChildOutput(const aOutput: string);
begin
  Assert.IsTrue(aOutput.Contains('child stderr-marker'), aOutput);
  Assert.IsTrue(aOutput.Contains('child console=0' + sLineBreak), 'Child must have no console window: ' + aOutput);
  Assert.IsTrue(aOutput.Contains('child own-console=1'),
    'Child must own a hidden console of its own, not run detached: ' + aOutput);
  Assert.IsTrue(aOutput.Contains('child runner-console=0'),
    'Child must not share the test runner''s console: ' + aOutput);
  Assert.IsTrue(aOutput.Contains('child startup-hidden=1'), 'Launch must request SW_HIDE: ' + aOutput);
end;

procedure AssertHeadlessGrandchildOutput(const aOutput: string);
begin
  Assert.IsTrue(aOutput.Contains('child descendant-exit=7'), 'Grandchild must run to completion: ' + aOutput);
  Assert.IsTrue(aOutput.Contains('grandchild console=0' + sLineBreak),
    'A default-flag descendant must have no console window: ' + aOutput);
  Assert.IsTrue(aOutput.Contains('grandchild parent-console=1'),
    'A default-flag descendant must inherit its parent''s hidden console: ' + aOutput);
  Assert.IsTrue(aOutput.Contains('grandchild runner-console=0'),
    'A descendant must not reach the test runner''s console: ' + aOutput);
end;

procedure TExternalToolProcessTests.NoninteractiveChildrenHaveNoConsole(aRoute: Integer);
var
  lGuard: IInterface;
  lOutput, lPath, lError: string;
  lExit: Cardinal;
  lStarted, lTimedOut: Boolean;
begin
  lGuard := HeadlessChildEnvironment(False);
  Assert.IsNotNull(lGuard);
  lPath := UniqueTempPath('headless-child') + '.log';
  try
    case aRoute of
      0: lStarted := RunProcess(ParamStr(0), '', RepoRoot, lPath, lExit);
      1: lStarted := RunProcessWithTimeout(ParamStr(0), '', RepoRoot, lPath, 5000, lExit);
    else
      lStarted := TryCapturePalCmdHelp(ParamStr(0), 5, lOutput, lExit, lTimedOut, lError);
      Assert.IsFalse(lTimedOut);
    end;
    Assert.IsTrue(lStarted, lError);
    if aRoute <> 2 then
      lOutput := TFile.ReadAllText(lPath);
    Assert.AreEqual(Cardinal(7), lExit, 'Child exit code must survive capture');
    AssertHeadlessChildOutput(lOutput);
  finally
    if TFile.Exists(lPath) then
      TFile.Delete(lPath);
  end;
end;

type
  TPipePair = record
    ReadHandle: THandle;
    WriteHandle: THandle;
  end;
  TPipeSetup = reference to function(const aPipe: TPipePair): Boolean;
  TNulOpen = reference to function: THandle;
  TChildHandles = record
    fFirstPipe: TPipePair;
    fSecondPipe: TPipePair;
    fNul: THandle;
    procedure Close;
  end;

procedure TChildHandles.Close;
begin
  if fFirstPipe.WriteHandle <> 0 then
    CloseHandle(fFirstPipe.WriteHandle);
  if fFirstPipe.ReadHandle <> 0 then
    CloseHandle(fFirstPipe.ReadHandle);
  if fSecondPipe.WriteHandle <> 0 then
    CloseHandle(fSecondPipe.WriteHandle);
  if fSecondPipe.ReadHandle <> 0 then
    CloseHandle(fSecondPipe.ReadHandle);
  if fNul <> 0 then
    CloseHandle(fNul);
  fFirstPipe := Default(TPipePair);
  fSecondPipe := Default(TPipePair);
  fNul := 0;
end;

function CreateInheritablePipe(const aSetup: TPipeSetup = nil): TPipePair;
var
  lSecurity: TSecurityAttributes;
  lSetupOk: Boolean;
begin
  Result := Default(TPipePair);
  lSecurity := Default(TSecurityAttributes);
  lSecurity.nLength := SizeOf(lSecurity);
  lSecurity.bInheritHandle := True;
  if not CreatePipe(Result.ReadHandle, Result.WriteHandle, @lSecurity, 4096) then
    RaiseLastOSError;
  try
    if Assigned(aSetup) then
      lSetupOk := aSetup(Result)
    else
      lSetupOk := SetHandleInformation(Result.ReadHandle, HANDLE_FLAG_INHERIT, 0);
    if not lSetupOk then
      RaiseLastOSError;
  except
    // The raised native error is already captured before cleanup changes LastError.
    CloseHandle(Result.WriteHandle);
    CloseHandle(Result.ReadHandle);
    raise;
  end;
end;

function OpenInheritableNul(const aOpen: TNulOpen = nil): THandle;
var
  lSecurity: TSecurityAttributes;
begin
  lSecurity := Default(TSecurityAttributes);
  lSecurity.nLength := SizeOf(lSecurity);
  lSecurity.bInheritHandle := True;
  if Assigned(aOpen) then
    Result := aOpen()
  else
    Result := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @lSecurity,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if Result = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
end;

function AcquireChildHandles(aPipeCount: Integer; const aSetup: TPipeSetup = nil;
  const aOpenNul: TNulOpen = nil): TChildHandles;
begin
  Result := Default(TChildHandles);
  try
    Result.fFirstPipe := CreateInheritablePipe(aSetup);
    if aPipeCount = 2 then
      Result.fSecondPipe := CreateInheritablePipe(aSetup);
    Result.fNul := OpenInheritableNul(aOpenNul);
  except
    Result.Close;
    raise;
  end;
end;

procedure AssertClosedPipe(const aPipe: TPipePair);
var
  lReadFlags, lWriteFlags: DWORD;
  lReadOpen, lWriteOpen: Boolean;
  lReadError, lWriteError: DWORD;
begin
  if GetHandleInformation(aPipe.ReadHandle, lReadFlags) then
    lReadOpen := True
  else
    lReadOpen := False;
  lReadError := GetLastError;
  if GetHandleInformation(aPipe.WriteHandle, lWriteFlags) then
    lWriteOpen := True
  else
    lWriteOpen := False;
  lWriteError := GetLastError;
  Assert.IsFalse(lReadOpen, 'read end remained open');
  Assert.IsFalse(lWriteOpen, 'write end remained open');
  Assert.AreEqual<DWORD>(ERROR_INVALID_HANDLE, lReadError);
  Assert.AreEqual<DWORD>(ERROR_INVALID_HANDLE, lWriteError);
end;

procedure TExternalToolProcessTests.CreateInheritablePipeClosesBothHandlesWhenSetupFails;
var
  lSeen: TPipePair;
begin
  lSeen := Default(TPipePair);
  try
    CreateInheritablePipe(
      function(const aPipe: TPipePair): Boolean
      begin
        lSeen := aPipe;
        SetLastError(ERROR_ACCESS_DENIED);
        Result := False;
      end);
    Assert.Fail('SetHandleInformation failure must propagate');
  except
    on E: EOSError do
      Assert.AreEqual<Integer>(ERROR_ACCESS_DENIED, E.ErrorCode);
  end;
  Assert.IsTrue(lSeen.ReadHandle <> 0, 'CreatePipe must succeed before the injected failure');
  Assert.IsTrue(lSeen.WriteHandle <> 0, 'CreatePipe must return both pipe ends');
  AssertClosedPipe(lSeen);
end;

procedure TExternalToolProcessTests.SecondPipeSetupFailureClosesBothPairs;
var
  lSeen: array[0..1] of TPipePair;
  lSeenCount: Integer;
  lSecondSetupAttempted: Boolean;
begin
  lSeenCount := 0;
  lSecondSetupAttempted := False;
  try
    AcquireChildHandles(2,
      function(const aPipe: TPipePair): Boolean
      begin
        lSeen[lSeenCount] := aPipe;
        Inc(lSeenCount);
        if lSeenCount = 2 then
        begin
          lSecondSetupAttempted := True;
          SetLastError(ERROR_ACCESS_DENIED);
          Result := False;
        end else
          Result := SetHandleInformation(aPipe.ReadHandle, HANDLE_FLAG_INHERIT, 0);
      end);
    Assert.Fail('second pipe setup failure must propagate');
  except
    on E: EOSError do
      Assert.AreEqual<Integer>(ERROR_ACCESS_DENIED, E.ErrorCode);
  end;
  Assert.IsTrue(lSecondSetupAttempted, 'the second pipe setup must be reached');
  Assert.AreEqual<Integer>(2, lSeenCount, 'both CreatePipe calls must succeed');
  AssertClosedPipe(lSeen[0]);
  AssertClosedPipe(lSeen[1]);
end;

procedure TExternalToolProcessTests.PipeAcquisitionClosesEarlierHandlesWhenNulFails(aPipeCount: Integer);
var
  lSeen: array[0..1] of TPipePair;
  lSeenCount: Integer;
  lNulAttempted: Boolean;
begin
  lSeenCount := 0;
  lNulAttempted := False;
  try
    AcquireChildHandles(aPipeCount,
      function(const aPipe: TPipePair): Boolean
      begin
        lSeen[lSeenCount] := aPipe;
        Inc(lSeenCount);
        Result := SetHandleInformation(aPipe.ReadHandle, HANDLE_FLAG_INHERIT, 0);
      end,
      function: THandle
      begin
        lNulAttempted := True;
        SetLastError(ERROR_ACCESS_DENIED);
        Result := INVALID_HANDLE_VALUE;
      end);
    Assert.Fail('NUL acquisition failure must propagate');
  except
    on E: EOSError do
      Assert.AreEqual<Integer>(ERROR_ACCESS_DENIED, E.ErrorCode);
  end;
  Assert.IsTrue(lNulAttempted, 'the injected NUL acquisition must be reached');
  Assert.AreEqual<Integer>(aPipeCount, lSeenCount, 'all earlier pipes must be created');
  AssertClosedPipe(lSeen[0]);
  if aPipeCount = 2 then
    AssertClosedPipe(lSeen[1]);
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
  lHandles: TChildHandles;
  lSlowThread: TThread;
  lSlowExit, lFastExit: Cardinal;
  lSlowTimedOut, lFastTimedOut, lSlowOk, lFastOk: Boolean;
  lSlowError, lFastError, lFastOutput: string;
  lWatch: TStopwatch;
  lFastMilliseconds: Int64;
begin
  lHandles := AcquireChildHandles(2);
  try
    lSlowOk := False;
    lSlowExit := 0;
    lSlowTimedOut := False;
    // A slow child keeps running while the fast child is launched and read.
    lSlowThread := TThread.CreateAnonymousThread(
      procedure
      begin
        lSlowOk := TryRunExternalToolProcess(RunOptions('/c ping -n 4 127.0.0.1 >nul', lHandles.fNul,
          lHandles.fFirstPipe.WriteHandle, lHandles.fFirstPipe.WriteHandle), lSlowExit, lSlowTimedOut, lSlowError);
      end);
    lSlowThread.FreeOnTerminate := False;
    lSlowThread.Start;
    Sleep(300);
    lWatch := TStopwatch.StartNew;
    lFastOk := TryRunExternalToolProcess(RunOptions('/c echo fast', lHandles.fNul, lHandles.fSecondPipe.WriteHandle,
      lHandles.fSecondPipe.WriteHandle), lFastExit, lFastTimedOut, lFastError);
    // Close our own copy so EOF depends only on children that inherited the write end.
    CloseHandle(lHandles.fSecondPipe.WriteHandle);
    lHandles.fSecondPipe.WriteHandle := 0;
    lFastOutput := ReadUntilEof(lHandles.fSecondPipe.ReadHandle);
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
    lHandles.Close;
  end;
end;

// Runs the headless child fixture through the production helper with the default
// flags FixInsight and PAL callers use, and returns everything it wrote.
function RunDefaultExternalToolChild(out aExit: Cardinal): string;
var
  lHandles: TChildHandles;
  lOptions: TExternalToolProcessRunOptions;
  lStarted, lTimedOut: Boolean;
  lError: string;
begin
  lHandles := AcquireChildHandles(1);
  try
    lOptions := RunOptions('', lHandles.fNul, lHandles.fFirstPipe.WriteHandle,
      lHandles.fFirstPipe.WriteHandle);
    lOptions.fExePath := ParamStr(0);
    lOptions.fCreationFlags := 0;
    lStarted := TryRunExternalToolProcess(lOptions, aExit, lTimedOut, lError);
    CloseHandle(lHandles.fFirstPipe.WriteHandle);
    lHandles.fFirstPipe.WriteHandle := 0;
    Result := ReadUntilEof(lHandles.fFirstPipe.ReadHandle);
    Assert.IsTrue(lStarted, lError);
    Assert.IsFalse(lTimedOut);
  finally
    lHandles.Close;
  end;
end;

procedure TExternalToolProcessTests.DescendantsOfHeadlessChildrenStayWindowless(aRoute: Integer);
var
  lGuard: IInterface;
  lOutput, lPath: string;
  lExit: Cardinal;
begin
  lGuard := HeadlessChildEnvironment(True);
  Assert.IsNotNull(lGuard);
  lPath := UniqueTempPath('headless-descendant') + '.log';
  try
    if aRoute = 0 then
    begin
      Assert.IsTrue(RunProcessWithTimeout(ParamStr(0), '', RepoRoot, lPath, 30000, lExit));
      lOutput := TFile.ReadAllText(lPath);
    end else
      lOutput := RunDefaultExternalToolChild(lExit);
    Assert.AreEqual(Cardinal(7), lExit, lOutput);
    AssertHeadlessChildOutput(lOutput);
    AssertHeadlessGrandchildOutput(lOutput);
  finally
    if TFile.Exists(lPath) then
      TFile.Delete(lPath);
  end;
end;

procedure TExternalToolProcessTests.DefaultExternalToolHasNoConsole;
var
  lGuard: IInterface;
  lExit: Cardinal;
  lOutput: string;
begin
  lGuard := HeadlessChildEnvironment(False);
  Assert.IsNotNull(lGuard);
  // FixInsight and PAL callers use default flags, without caller-side console policy.
  lOutput := RunDefaultExternalToolChild(lExit);
  Assert.AreEqual(Cardinal(7), lExit, lOutput);
  AssertHeadlessChildOutput(lOutput);
end;

const
  cProcessQueryLimitedInformation = $1000; // PROCESS_QUERY_LIMITED_INFORMATION
  cReadyTimeoutMs = 30000;
  cStopBudgetMs = 5000;

// Waits for a published identity file while its publisher's owner still runs.
// The owner may exit right after publishing, so existence is checked once more.
function WaitForReadyFile(const aPath: string; aOwner: THandle): Boolean;
var
  lWatch: TStopwatch;
begin
  lWatch := TStopwatch.StartNew;
  while not TFile.Exists(aPath) do
  begin
    if WaitForSingleObject(aOwner, 20) <> WAIT_TIMEOUT then
      Exit(TFile.Exists(aPath));
    if lWatch.ElapsedMilliseconds >= cReadyTimeoutMs then
      Exit(False);
  end;
  Result := True;
end;

// Opens the published process by handle while it is known to be alive, and
// proves by creation time that the PID was not reused.
function OpenPublishedProcess(const aPath: string; aOwner: THandle): THandle;
var
  lCreated, lExited, lKernel, lUser: TFileTime;
  lFields: TArray<string>;
  lLastError: Cardinal;
  lPid: Cardinal;
  lPublished: UInt64;
begin
  Assert.IsTrue(WaitForReadyFile(aPath, aOwner), 'The child must publish its descendant: ' + aPath);
  lFields := TFile.ReadAllText(aPath).Trim.Split([' ']);
  Assert.AreEqual<Integer>(2, Length(lFields), 'Identity file must hold a PID and a creation time: ' + aPath);
  lPid := StrToUInt(lFields[0]);
  lPublished := StrToUInt64(lFields[1]);
  Result := OpenProcess(SYNCHRONIZE or PROCESS_TERMINATE or cProcessQueryLimitedInformation, False, lPid);
  if Result = 0 then
  begin
    lLastError := GetLastError;
    Assert.Fail('The published process must still run when opened: ' + SysErrorMessage(lLastError));
  end;
  if not GetProcessTimes(Result, lCreated, lExited, lKernel, lUser) or
    (((UInt64(lCreated.dwHighDateTime) shl 32) or lCreated.dwLowDateTime) <> lPublished) then
  begin
    CloseHandle(Result);
    Assert.Fail('PID ' + lFields[0] + ' no longer identifies the published process');
  end;
end;

// Terminates only through the retained handle, so a reused PID is never touched.
procedure ContainAndClose(var aProcess: THandle);
begin
  if aProcess = 0 then
    Exit;
  try
    if WaitForSingleObject(aProcess, 0) = WAIT_TIMEOUT then
    begin
      TerminateProcess(aProcess, ERROR_PROCESS_ABORTED);
      WaitForSingleObject(aProcess, cStopBudgetMs);
    end;
  finally
    CloseHandle(aProcess);
    aProcess := 0;
  end;
end;

function DescendantEnvironment(const aReadyPath, aMode: string): IInterface;
begin
  Result := SetScopedEnvironmentVariables(['DAK_TEST_DESCENDANT_READY', aReadyPath,
    'DAK_TEST_DESCENDANT_MODE', aMode]);
end;

procedure TExternalToolProcessTests.TimeoutStopsDescendants;
var
  lCompleted: Boolean;
  lDescendant: THandle;
  lExit: Cardinal;
  lGuard: IInterface;
  lReadyPath: string;
begin
  lReadyPath := UniqueTempPath('descendant-timeout') + '.ready';
  lGuard := DescendantEnvironment(lReadyPath, 'wait');
  Assert.IsNotNull(lGuard);
  lDescendant := 0;
  try
    // The hook returns only after the child is ready, and the deadline starts
    // after the hook. Test-executable startup is therefore not part of it.
    lCompleted := RunProcessWithStartHook(ParamStr(0), '', RepoRoot, lReadyPath + '.log', 2000,
      procedure(aProcess: THandle)
      begin
        lDescendant := OpenPublishedProcess(lReadyPath, aProcess);
      end, lExit);
    Assert.IsFalse(lCompleted, 'The child sleeps past its deadline');
    Assert.AreEqual(Cardinal(ERROR_TIMEOUT), lExit);
    Assert.AreEqual<Cardinal>(WAIT_OBJECT_0, WaitForSingleObject(lDescendant, cStopBudgetMs),
      'A timed-out test child must not leave descendants running');
  finally
    ContainAndClose(lDescendant);
  end;
end;

procedure TExternalToolProcessTests.NormalExitStopsDescendants;
var
  lCompleted: Boolean;
  lDescendant: THandle;
  lExit: Cardinal;
  lGuard: IInterface;
  lReadyPath: string;
begin
  lReadyPath := UniqueTempPath('descendant-exit') + '.ready';
  lGuard := DescendantEnvironment(lReadyPath, 'exit');
  Assert.IsNotNull(lGuard);
  lDescendant := 0;
  try
    lCompleted := RunProcessWithStartHook(ParamStr(0), '', RepoRoot, lReadyPath + '.log', 30000,
      procedure(aProcess: THandle)
      begin
        lDescendant := OpenPublishedProcess(lReadyPath, aProcess);
      end, lExit);
    Assert.IsTrue(lCompleted, 'The child exits on its own');
    Assert.AreEqual(Cardinal(0), lExit);
    Assert.AreEqual<Cardinal>(WAIT_OBJECT_0, WaitForSingleObject(lDescendant, cStopBudgetMs),
      'A child that exits normally must not leave descendants running');
  finally
    ContainAndClose(lDescendant);
  end;
end;

procedure TExternalToolProcessTests.StartFailureStopsDescendants;
var
  lDescendant: THandle;
  lExit: Cardinal;
  lGuard: IInterface;
  lRaised: Boolean;
  lReadyPath: string;
begin
  lReadyPath := UniqueTempPath('descendant-exception') + '.ready';
  lGuard := DescendantEnvironment(lReadyPath, 'wait');
  Assert.IsNotNull(lGuard);
  lDescendant := 0;
  lRaised := False;
  try
    try
      RunProcessWithStartHook(ParamStr(0), '', RepoRoot, lReadyPath + '.log', 30000,
        procedure(aProcess: THandle)
        begin
          lDescendant := OpenPublishedProcess(lReadyPath, aProcess);
          raise EInjectedStartFailure.Create('injected failure after the child started');
        end, lExit);
    except
      on E: EInjectedStartFailure do
        lRaised := True;
    end;
    Assert.IsTrue(lRaised, 'The injected failure must leave the helper');
    Assert.IsTrue(lDescendant <> 0, 'The descendant must be opened before the failure');
    Assert.AreEqual<Cardinal>(WAIT_OBJECT_0, WaitForSingleObject(lDescendant, cStopBudgetMs),
      'A helper exception must not leave descendants running');
  finally
    ContainAndClose(lDescendant);
  end;
end;

procedure TExternalToolProcessTests.ExternalToolStopsWhenOwnerIsInterrupted;
var
  lCompleted, lOwnerStopped, lToolStopped: Boolean;
  lExit: Cardinal;
  lGuard: IInterface;
  lReadyPath: string;
  lTool: THandle;
begin
  lReadyPath := UniqueTempPath('tool-owner') + '.ready';
  lGuard := SetScopedEnvironmentVariable('DAK_TEST_TOOL_HOST_READY', lReadyPath);
  Assert.IsNotNull(lGuard);
  lTool := 0;
  lOwnerStopped := False;
  lToolStopped := False;
  try
    lCompleted := RunProcessWithStartHook(ParamStr(0), '', RepoRoot, lReadyPath + '.log', 30000,
      procedure(aOwner: THandle)
      begin
        lTool := OpenPublishedProcess(lReadyPath, aOwner);
        // End the owner the way an interrupted DAK ends: no cleanup code of the
        // production helper runs. Its descendants must still stop.
        if not TerminateProcess(aOwner, ERROR_PROCESS_ABORTED) then
          RaiseLastOSError;
        lOwnerStopped := WaitForSingleObject(aOwner, cStopBudgetMs) = WAIT_OBJECT_0;
        lToolStopped := WaitForSingleObject(lTool, cStopBudgetMs) = WAIT_OBJECT_0;
      end, lExit);
    Assert.IsTrue(lCompleted);
    Assert.IsTrue(lOwnerStopped, 'The owner must stop when terminated');
    Assert.AreEqual(Cardinal(ERROR_PROCESS_ABORTED), lExit);
    Assert.IsTrue(lToolStopped, 'An external tool must not outlive its interrupted DAK owner');
  finally
    ContainAndClose(lTool);
  end;
end;

procedure TExternalToolProcessTests.RunProcessRetriesTransientOutputLock;
var
  lExit: Cardinal;
  lLock: TFileStream;
  lPath: string;
  lRelease: ITask;
begin
  lPath := UniqueTempPath('locked-output') + '.log';
  ForceDirectories(ExtractFileDir(lPath));
  // Another process briefly holding the capture file (an indexer, a previous
  // child's writer) must not fail the launch.
  lLock := TFileStream.Create(lPath, fmCreate or fmShareExclusive);
  lRelease := TTask.Run(
    procedure
    begin
      Sleep(300);
      lLock.Free;
      lLock := nil;
    end);
  try
    Assert.IsTrue(RunProcessWithTimeout(GetEnvironmentVariable('ComSpec'), '/c echo retry-ok', RepoRoot, lPath,
      30000, lExit));
    Assert.AreEqual(Cardinal(0), lExit);
  finally
    // The task owns the lock's release; it only sleeps before freeing it.
    if not lRelease.Wait(10000) then
      Assert.Fail('The lock-release task did not finish');
  end;
  Assert.AreEqual('retry-ok', TFile.ReadAllText(lPath).Trim);
end;

// DAK-394: a process inherits its parent's error mode. Under a parent with mode 0, CreateProcess on a file that
// is not a PE image opens a modal "Unsupported 16-bit application" dialog and the run blocks. The child starts
// with CREATE_DEFAULT_ERROR_MODE, so only the runner's own startup can set the flags it reports as exit code.
procedure TExternalToolProcessTests.TestRunnerSuppressesErrorDialogsWhateverItsParentMode;
const
  cRequired = SEM_FAILCRITICALERRORS or SEM_NOGPFAULTERRORBOX or SEM_NOOPENFILEERRORBOX;
var
  lError: string;
  lExit: Cardinal;
  lGuard: IInterface;
  lOptions: TExternalToolProcessRunOptions;
  lTimedOut: Boolean;
begin
  lGuard := SetScopedEnvironmentVariable('DAK_TEST_REPORT_ERROR_MODE', '1');
  Assert.IsNotNull(lGuard);
  lOptions := Default(TExternalToolProcessRunOptions);
  lOptions.fExePath := ParamStr(0);
  lOptions.fCreationFlags := CREATE_DEFAULT_ERROR_MODE;
  lOptions.fTimeoutSec := 30;
  Assert.IsTrue(TryRunExternalToolProcess(lOptions, lExit, lTimedOut, lError), lError);
  Assert.AreEqual<Cardinal>(cRequired, lExit and cRequired,
    Format('Child error mode $%.4x lacks the dialog-suppressing flags $%.4x', [lExit, cRequired]));
end;

procedure TExternalToolProcessTests.InvalidExecutableFailsWithNamedErrorBeforeLaunch(aVariant: Integer);
var
  lBytes: TBytes;
  lError: string;
  lExit: Cardinal;
  lOptions: TExternalToolProcessRunOptions;
  lPath: string;
  lTimedOut: Boolean;
begin
  lPath := UniqueTempPath('invalid-image') + '.exe';
  ForceDirectories(ExtractFileDir(lPath));
  case aVariant of
    0:
      lBytes := TEncoding.ASCII.GetBytes('not a Windows executable');
    2:
      lBytes := TEncoding.ASCII.GetBytes('MZ');
  else
    // SetLength zero-fills the new array.
    SetLength(lBytes, 256);
    lBytes[0] := Ord('M');
    lBytes[1] := Ord('Z');
    // Variant 1 points e_lfanew at zero bytes; variant 3 points it past the end of the file.
    if aVariant = 1 then
      lBytes[$3C] := $80
    else
      lBytes[$3D] := $10;
  end;
  TFile.WriteAllBytes(lPath, lBytes);
  try
    lOptions := Default(TExternalToolProcessRunOptions);
    lOptions.fExePath := lPath;
    lOptions.fStartFailureFormat := 'Sample tool failed to start: %s';
    lOptions.fTimeoutSec := 30;
    Assert.IsFalse(TryRunExternalToolProcess(lOptions, lExit, lTimedOut, lError), 'An invalid image must not start');
    Assert.IsFalse(lTimedOut);
    Assert.AreEqual('Sample tool failed to start: ' + lPath + ' is not a valid Windows executable', lError);
  finally
    TFile.Delete(lPath);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExternalToolProcessTests);

end.
