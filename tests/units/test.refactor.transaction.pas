unit Test.Refactor.Transaction;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DelphiSemantics.Refactor.Plan,
  Dak.Refactor.Transaction, Dak.Types;

type
  [TestFixture]
  [Category('RefactoringLightTransaction,Slow')]
  TRefactorTransactionTests = class
  private
    fRoot: string;
    fBase: string;
    fOptions: TAppOptions;
    fSources: TArray<TSemanticPlanSource>;
    function Plan(const aReplacement: string = '2'): TSemanticRefactoringPlan;
    procedure AssertOriginals;
    procedure CreateFixture(const aRoot: string);
    procedure UseLongRoot;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SuccessfulBuildsAndJournal;
    [Test] procedure ShortRootKeepsLogicalPathsUnprefixed;
    [Test] procedure LongRootPublishesLockJournalAndStaging;
    [Test] procedure LongRootAcquireLockCreatesTransactionDirectory;
    [Test] procedure LongRootRecoveryRestoresOriginalBytes;
    [Test] procedure HeldLockReportsBusy;
    [Test] procedure UnopenableLockPathReportsLockFailedWithOsError;
    [Test] procedure BaselineFailureWritesNothing;
    [Test] procedure PostBuildFailureRestoresBothFiles;
    [Test] procedure StaleSecondSourceWritesNothing;
    [Test] procedure SecondWriteFailureRestoresFirst;
    [Test] procedure RollbackPreservesIndependentChange;
    [Test] procedure InterruptedJournalRequiresExplicitRecovery;
    [Test] procedure RecoveryPreservesConflictAndRestoresOtherFile;
    [Test] procedure RollbackDoesNotRestoreAFileNeverWrittenByDak;
    [Test] procedure RecoveryRetryDoesNotReacquireRestoredFiles;
    [Test] procedure CorruptSecondBackupBlocksAllRecoveryWrites;
    [Test] procedure NonObjectJournalIsRefused;
    [Test] procedure WriteIntentDoesNotProveOwnershipOfProposedBytes;
    [TestCase('UnknownFileState', 'writing,unknown')]
    [TestCase('InconsistentPrepared', 'prepared,written')]
    [Test] procedure InvalidJournalStatesBlockAllRecoveryWrites(const aState, aFileState: string);
    [Test] procedure InterruptedRestoreIntentCannotReacquireOwnership;
    [Test] procedure JournalFailurePreventsUnrecordedRestoration;
    [TestCase('PreparedBoundary', '1000,2097152,prepared,ok')]
    [TestCase('FileLimit', '1001,10,prepared,transaction.too-many-files')]
    [TestCase('PreparationHeadroom', '1,2097153,prepared,transaction.journal-too-large')]
    [TestCase('RecoveryBoundary', '1000,4194304,rolling-back,ok')]
    [TestCase('ReaderLimit', '1,4194305,rolling-back,transaction.journal-too-large')]
    [Test] procedure JournalBudgetReservesRecoveryHeadroom(const aFiles: Integer;
      const aBytes: Int64; const aState, aExpected: string);
  end;

implementation

uses
  System.Classes, System.Hash, System.IOUtils, System.JSON,
  Winapi.Windows,
  AutoFree, maxLogic.ioutils,
  Dak.Utils,
  Test.Support;

function HashBytes(const aBytes: TBytes): string;
var
  lHash: THashSHA2;
begin
  lHash := THashSHA2.Create;
  lHash.Update(aBytes);
  Result := lHash.HashAsString;
end;

procedure TRefactorTransactionTests.Setup;
begin
  fBase := CombinePath([RepoRoot, 'projects', '.dak', 'DelphiAIKit',
    'refactoring-light-transaction', 'fixtures', TGUID.NewGuid.ToString]);
  TDirectory.CreateDirectory(fBase);
  CreateFixture(fBase);
end;

// DAK-398: the same owned project, relocated beneath a directory chain well past MAX_PATH.
procedure TRefactorTransactionTests.UseLongRoot;
var
  lPath: string;
begin
  lPath := fBase;
  while Length(lPath) < 300 do
    lPath := TPath.Combine(lPath, StringOfChar('d', 60));
  TDirectory.CreateDirectory(LongPathSafe(lPath));
  CreateFixture(lPath);
end;

procedure TRefactorTransactionTests.CreateFixture(const aRoot: string);
var
  i: Integer;
  lName: string;
begin
  fRoot := aRoot;
  fOptions := Default(TAppOptions);
  fOptions.fDprojPath := TPath.Combine(fRoot, 'Owned.dproj');
  fOptions.fPlatform := 'Win64';
  fOptions.fConfig := 'Debug';
  fOptions.fDelphiVersion := '23.0';
  // Fixture files use the physical-I/O form so a root beyond MAX_PATH is writable; logical names stay plain.
  TFile.WriteAllText(LongPathSafe(fOptions.fDprojPath),
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>Owned.dpr</MainSource><Base>True</Base>' +
    '<ProjectName>Owned</ProjectName><AppType>Console</AppType><FrameworkType>None</FrameworkType>' +
    '<DCC_ExeOutput>bin</DCC_ExeOutput><DCC_DcuOutput>bin</DCC_DcuOutput>' +
    '</PropertyGroup><ItemGroup><DelphiCompile Include="Owned.dpr"><MainSource>MainSource</MainSource>' +
    '</DelphiCompile></ItemGroup><Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"/></Project>', TEncoding.UTF8);
  TFile.WriteAllText(LongPathSafe(TPath.Combine(fRoot, 'Owned.dpr')),
    'program Owned; {$APPTYPE CONSOLE} uses First, Second; begin Writeln(First.Value + Second.Value); end.'#13#10,
    TEncoding.UTF8);
  SetLength(fSources, 2);
  for i := 0 to 1 do
  begin
    if i = 0 then
      lName := 'First'
    else
      lName := 'Second';
    fSources[i].FileName := TPath.Combine(fRoot, lName + '.pas');
    fSources[i].OriginalText := 'unit ' + lName + '; interface const Value = 1; implementation end.'#13#10;
    TFile.WriteAllBytes(LongPathSafe(fSources[i].FileName), TEncoding.UTF8.GetBytes(fSources[i].OriginalText));
    fSources[i].ContentHash := HashBytes(TFile.ReadAllBytes(LongPathSafe(fSources[i].FileName)));
    fSources[i].IncludeGraphHash := 'no-includes';
  end;
end;

procedure TRefactorTransactionTests.TearDown;
var
  lError: string;
begin
  Assert.IsTrue(TryDeleteTreeLongPath(fBase, lError), lError);
end;

function TRefactorTransactionTests.Plan(const aReplacement: string): TSemanticRefactoringPlan;
var
  lContext: TSemanticPlanContext;
  lEdits: TArray<TSemanticPlanEdit>;
  i: Integer;
begin
  lContext.ProjectIdentity := fOptions.fDprojPath;
  lContext.CompilerIdentity := 'Delphi12-Win64';
  lContext.ModelVersion := 'test';
  lContext.ConfigurationFingerprint := 'Debug';
  SetLength(lEdits, 2);
  for i := 0 to 1 do
  begin
    lEdits[i].FileName := fSources[i].FileName;
    lEdits[i].StartLine := 1;
    lEdits[i].EndLine := 1;
    lEdits[i].StartColumn := Pos('1;', fSources[i].OriginalText);
    lEdits[i].EndColumn := lEdits[i].StartColumn + 1;
    lEdits[i].ExpectedText := '1';
    lEdits[i].ReplacementText := aReplacement;
  end;
  Result := TSemanticRefactoringPlan.Create(lContext, TSemanticPlanStatus.Complete, 'fixture', fSources, lEdits);
end;

procedure TRefactorTransactionTests.AssertOriginals;
var
  lSource: TSemanticPlanSource;
begin
  for lSource in fSources do
    Assert.AreEqual(lSource.ContentHash, HashBytes(TFile.ReadAllBytes(LongPathSafe(lSource.FileName))));
end;

procedure TRefactorTransactionTests.SuccessfulBuildsAndJournal;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult), lResult.Error);
  Assert.AreEqual('applied', lResult.Status);
  Assert.IsTrue(TFile.Exists(lResult.BaselineLog));
  Assert.IsTrue(TFile.Exists(lResult.VerificationLog));
  Assert.IsTrue(TFile.Exists(lResult.JournalPath));
  Assert.AreEqual<NativeInt>(2, Length(lResult.Files));
  Assert.AreEqual('written', lResult.Files[0].Status);
  Assert.AreEqual('written', lResult.Files[1].Status);
  Assert.AreEqual(lResult.Files[0].ProposedHash, HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
end;

// DAK-398 helpers: physical access through the long-path form, logical paths everywhere else.
function ReadLongText(const aPath: string): string;
begin
  Result := TFile.ReadAllText(LongPathSafe(aPath), TEncoding.UTF8);
end;

function LongFileHash(const aPath: string): string;
begin
  Result := HashBytes(TFile.ReadAllBytes(LongPathSafe(aPath)));
end;

function JournalValue(const aJournalPath, aName: string): string;
var
  g: TGarbos;
  lJson: TJSONObject;
begin
  g := Default(TGarbos);
  GC(lJson, TJSONObject.ParseJSONValue(ReadLongText(aJournalPath)) as TJSONObject, g);
  Result := lJson.GetValue<string>(aName);
end;

procedure SetLongJournalStates(const aPath, aState, aFileState: string);
var
  g: TGarbos;
  lJson, lFile: TJSONObject;
  lItem: TJSONValue;
begin
  g := Default(TGarbos);
  GC(lJson, TJSONObject.ParseJSONValue(ReadLongText(aPath)) as TJSONObject, g);
  lJson.RemovePair('status').Free;
  lJson.AddPair('status', aState);
  for lItem in lJson.GetValue<TJSONArray>('files') do
  begin
    lFile := lItem as TJSONObject;
    lFile.RemovePair('status').Free;
    lFile.AddPair('status', aFileState);
  end;
  TFile.WriteAllText(LongPathSafe(aPath), lJson.ToJSON, TEncoding.UTF8);
end;

procedure TRefactorTransactionTests.ShortRootKeepsLogicalPathsUnprefixed;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult), lResult.Error);
  Assert.IsFalse(lResult.JournalPath.StartsWith('\\?\'));
  Assert.IsTrue(lResult.JournalPath.StartsWith(TransactionRoot(fOptions.fDprojPath) + '\'));
  Assert.AreEqual(fOptions.fDprojPath, JournalValue(lResult.JournalPath, 'project'));
  Assert.AreEqual(fRoot, JournalValue(lResult.JournalPath, 'workspace'));
end;

// The baseline build cannot run beyond MAX_PATH (MSBuild and the Delphi compiler are not long-path aware, DAK-385),
// so the apply stops at 'baseline-failed'. Everything the transaction itself owns must still land.
procedure TRefactorTransactionTests.LongRootPublishesLockJournalAndStaging;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
  lDirectory: string;
  i: Integer;
begin
  g := Default(TGarbos);
  UseLongRoot;
  Assert.IsTrue(Length(fOptions.fDprojPath) >= 300);
  GC(lPlan, Plan, g);
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult));
  Assert.AreEqual('baseline-failed', lResult.Status, lResult.Error);
  Assert.IsFalse(lResult.JournalPath.StartsWith('\\?\'));
  Assert.IsTrue(lResult.JournalPath.StartsWith(TransactionRoot(fOptions.fDprojPath) + '\'));
  Assert.IsTrue(Length(lResult.JournalPath) > 300);
  Assert.IsTrue(TFile.Exists(LongPathSafe(TPath.Combine(TransactionRoot(fOptions.fDprojPath), 'transaction.lock'))));
  Assert.IsTrue(TFile.Exists(LongPathSafe(lResult.JournalPath)));
  Assert.AreEqual('baseline-failed', JournalValue(lResult.JournalPath, 'status'));
  Assert.AreEqual(fOptions.fDprojPath, JournalValue(lResult.JournalPath, 'project'));
  Assert.AreEqual(fRoot, JournalValue(lResult.JournalPath, 'workspace'));
  lDirectory := ExtractFileDir(lResult.JournalPath);
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(LongPathSafe(lDirectory), '*.tmp')));
  for i := 0 to 1 do
  begin
    Assert.AreEqual(fSources[i].ContentHash, LongFileHash(TPath.Combine(lDirectory, IntToStr(i) + '.original')));
    Assert.AreEqual(lResult.Files[i].ProposedHash, LongFileHash(TPath.Combine(lDirectory, IntToStr(i) + '.proposed')));
  end;
  AssertOriginals;
  // The lock was released: a second transaction reaches the same stage instead of 'transaction.busy'.
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult));
  Assert.AreNotEqual('transaction.busy', lResult.Error);
end;

procedure TRefactorTransactionTests.LongRootAcquireLockCreatesTransactionDirectory;
var
  lResult: TRefactoringTransactionResult;
  lTransactionRoot, lMissingJournal: string;
begin
  UseLongRoot;
  lTransactionRoot := TransactionRoot(fOptions.fDprojPath);
  lMissingJournal := TPath.Combine(TPath.Combine(lTransactionRoot, 'missing'), 'journal.json');
  Assert.IsTrue(Length(lTransactionRoot) > 260);
  Assert.IsFalse(TDirectory.Exists(LongPathSafe(lTransactionRoot)));
  // No journal exists, so recovery stops after AcquireLock has created the directory and taken the lock.
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lMissingJournal, lResult));
  Assert.AreEqual('blocked', lResult.Status);
  Assert.AreNotEqual('transaction.busy', lResult.Error);
  Assert.IsTrue(TDirectory.Exists(LongPathSafe(lTransactionRoot)), lResult.Error);
  Assert.IsTrue(TFile.Exists(LongPathSafe(TPath.Combine(lTransactionRoot, 'transaction.lock'))), lResult.Error);
  // Released on exit: a second acquisition does not report a busy lock.
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lMissingJournal, lResult));
  Assert.AreNotEqual('transaction.busy', lResult.Error);
end;

procedure TRefactorTransactionTests.LongRootRecoveryRestoresOriginalBytes;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lApplied, lResult: TRefactoringTransactionResult;
  lDirectory: string;
  i: Integer;
begin
  g := Default(TGarbos);
  UseLongRoot;
  GC(lPlan, Plan, g);
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lApplied));
  Assert.AreEqual('baseline-failed', lApplied.Status, lApplied.Error);
  lDirectory := ExtractFileDir(lApplied.JournalPath);
  // Model an interruption after both sources were written with the staged proposed bytes.
  for i := 0 to 1 do
    TFile.WriteAllBytes(LongPathSafe(fSources[i].FileName),
      TFile.ReadAllBytes(LongPathSafe(TPath.Combine(lDirectory, IntToStr(i) + '.proposed'))));
  Assert.AreNotEqual(fSources[0].ContentHash, LongFileHash(fSources[0].FileName));
  SetLongJournalStates(lApplied.JournalPath, 'writing', 'written');
  // The pending journal beyond MAX_PATH is found and reported with its logical path.
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult));
  Assert.AreEqual('recovery-required', lResult.Status);
  Assert.AreEqual(lApplied.JournalPath, lResult.JournalPath);
  Assert.IsTrue(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lResult), lResult.Error);
  Assert.AreEqual('rolled-back', lResult.Status);
  Assert.AreEqual('restored', lResult.Files[0].Status);
  Assert.AreEqual('restored', lResult.Files[1].Status);
  AssertOriginals;
  Assert.AreEqual('rolled-back', JournalValue(lApplied.JournalPath, 'status'));
  Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(LongPathSafe(lDirectory), '*.tmp')));
end;

procedure TRefactorTransactionTests.HeldLockReportsBusy;
var
  lResult: TRefactoringTransactionResult;
  lMissingJournal, lLockPath: string;
  lHeld: THandle;
begin
  lMissingJournal := TPath.Combine(TPath.Combine(TransactionRoot(fOptions.fDprojPath), 'missing'), 'journal.json');
  // The first call creates the lock file; its failure is expected (no journal) and not busy.
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lMissingJournal, lResult));
  Assert.AreNotEqual('transaction.busy', lResult.Error);
  lLockPath := TPath.Combine(TransactionRoot(fOptions.fDprojPath), 'transaction.lock');
  lHeld := CreateFile(PChar(LongPathSafe(lLockPath)), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  Assert.AreNotEqual(INVALID_HANDLE_VALUE, lHeld);
  try
    Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lMissingJournal, lResult));
    Assert.AreEqual('transaction.busy', lResult.Error);
    Assert.AreEqual('blocked', lResult.Status);
  finally
    CloseHandle(lHeld);
  end;
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lMissingJournal, lResult));
  Assert.AreNotEqual('transaction.busy', lResult.Error);
end;

procedure TRefactorTransactionTests.UnopenableLockPathReportsLockFailedWithOsError;
var
  lResult: TRefactoringTransactionResult;
  lCode: Integer;
begin
  // A directory where the lock file belongs cannot be opened as a file: a defect, not a held lock.
  TDirectory.CreateDirectory(TPath.Combine(TransactionRoot(fOptions.fDprojPath), 'transaction.lock'));
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot,
    TPath.Combine(TPath.Combine(TransactionRoot(fOptions.fDprojPath), 'missing'), 'journal.json'), lResult));
  Assert.AreEqual('blocked', lResult.Status);
  Assert.IsTrue(lResult.Error.StartsWith('transaction.lock-failed: error '), lResult.Error);
  lCode := StrToIntDef(Copy(lResult.Error, Length('transaction.lock-failed: error ') + 1,
    Pos(':', lResult.Error, Length('transaction.lock-failed: error ') + 1) -
    Length('transaction.lock-failed: error ') - 1), 0);
  Assert.IsTrue(lCode > 0, lResult.Error);
  Assert.AreNotEqual(Integer(ERROR_SHARING_VIOLATION), lCode);
end;

procedure TRefactorTransactionTests.BaselineFailureWritesNothing;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  TFile.WriteAllText(TPath.Combine(fRoot, 'Owned.dpr'), 'invalid Delphi', TEncoding.UTF8);
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult));
  Assert.AreEqual('baseline-failed', lResult.Status);
  Assert.IsTrue(TFile.Exists(lResult.BaselineLog));
  AssertOriginals;
end;

procedure TRefactorTransactionTests.PostBuildFailureRestoresBothFiles;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan('MissingIdentifier'), g);
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult));
  Assert.AreEqual('rolled-back', lResult.Status);
  Assert.IsTrue(lResult.Error.StartsWith('post-build-failed'));
  Assert.IsTrue(TFile.Exists(lResult.VerificationLog));
  AssertOriginals;
end;

procedure TRefactorTransactionTests.StaleSecondSourceWritesNothing;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  TFile.AppendAllText(fSources[1].FileName, '// independent', TEncoding.UTF8);
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult));
  Assert.AreEqual('blocked', lResult.Status);
  Assert.AreEqual('preflight.stale-source', lResult.Error);
  Assert.AreEqual(fSources[0].ContentHash, HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
end;

procedure TRefactorTransactionTests.SecondWriteFailureRestoresFirst;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
  lLock: TFileStream;
begin
  g := Default(TGarbos);
  lLock := nil;
  GC(lPlan, Plan, g);
  try
    Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult,
      procedure(const aPhase: string; const aIndex: Integer)
      begin
        if (aPhase = 'written') and (aIndex = 0) then
          lLock := TFileStream.Create(fSources[1].FileName, fmOpenRead or fmShareDenyWrite);
      end));
    Assert.AreEqual('rolled-back', lResult.Status);
    Assert.AreEqual('restored', lResult.Files[0].Status);
    AssertOriginals;
  finally
    lLock.Free;
  end;
end;

procedure TRefactorTransactionTests.RollbackPreservesIndependentChange;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan('MissingIdentifier'), g);
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult,
    procedure(const aPhase: string; const aIndex: Integer)
    begin
      if (aPhase = 'written') and (aIndex = 1) then
        TFile.WriteAllText(fSources[0].FileName, 'independent bytes', TEncoding.UTF8);
    end));
  Assert.AreEqual('rollback-failed', lResult.Status);
  Assert.AreEqual('conflict', lResult.Files[0].Status);
  Assert.AreEqual('restored', lResult.Files[1].Status);
  Assert.AreEqual('independent bytes', TFile.ReadAllText(fSources[0].FileName, TEncoding.UTF8));
  Assert.AreEqual(fSources[1].ContentHash, HashBytes(TFile.ReadAllBytes(fSources[1].FileName)));
end;

// Model the durable state left by interruption after writes but before the
// applied marker. Recovery consumes disk evidence, not the abandoned object.
procedure MarkInterrupted(const aJournalPath: string);
var
  g: TGarbos;
  lJson: TJSONObject;
begin
  g := Default(TGarbos);
  GC(lJson, TJSONObject.ParseJSONValue(TFile.ReadAllText(aJournalPath, TEncoding.UTF8)) as TJSONObject, g);
  lJson.RemovePair('status').Free;
  lJson.AddPair('status', 'writing');
  TFile.WriteAllText(aJournalPath, lJson.ToJSON, TEncoding.UTF8);
end;

procedure TRefactorTransactionTests.InterruptedJournalRequiresExplicitRecovery;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lApplied, lResult: TRefactoringTransactionResult;
  lHash: string;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lApplied), lApplied.Error);
  MarkInterrupted(lApplied.JournalPath);
  lHash := HashBytes(TFile.ReadAllBytes(fSources[0].FileName));
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult));
  Assert.AreEqual('recovery-required', lResult.Status);
  Assert.AreEqual(lHash, HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
  Assert.IsTrue(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lResult), lResult.Error);
  Assert.AreEqual('rolled-back', lResult.Status);
  AssertOriginals;
end;

procedure TRefactorTransactionTests.RecoveryPreservesConflictAndRestoresOtherFile;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lApplied, lResult: TRefactoringTransactionResult;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lApplied), lApplied.Error);
  MarkInterrupted(lApplied.JournalPath);
  TFile.WriteAllText(fSources[0].FileName, 'independent bytes', TEncoding.UTF8);
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lResult));
  Assert.AreEqual('rollback-failed', lResult.Status);
  Assert.AreEqual('conflict', lResult.Files[0].Status);
  Assert.AreEqual('restored', lResult.Files[1].Status);
  Assert.AreEqual('independent bytes', TFile.ReadAllText(fSources[0].FileName, TEncoding.UTF8));
  Assert.AreEqual(fSources[1].ContentHash, HashBytes(TFile.ReadAllBytes(fSources[1].FileName)));
end;

procedure TRefactorTransactionTests.RollbackDoesNotRestoreAFileNeverWrittenByDak;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
  lIndependent: TBytes;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  lIndependent := TEncoding.UTF8.GetBytes(StringReplace(fSources[1].OriginalText, '1;', '2;', []));
  Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult,
    procedure(const aPhase: string; const aIndex: Integer)
    begin
      if (aPhase = 'written') and (aIndex = 0) then
        TFile.WriteAllBytes(fSources[1].FileName, lIndependent);
    end));
  Assert.AreEqual('rolled-back', lResult.Status);
  Assert.AreEqual(fSources[0].ContentHash, HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
  // Matching proposed bytes alone cannot confer ownership before DAK writes.
  Assert.AreEqual(HashBytes(lIndependent), HashBytes(TFile.ReadAllBytes(fSources[1].FileName)));
  Assert.AreEqual('not-written', lResult.Files[1].Status);
end;

procedure TRefactorTransactionTests.RecoveryRetryDoesNotReacquireRestoredFiles;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lApplied, lRecovered: TRefactoringTransactionResult;
  lIndependent: TBytes;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lApplied), lApplied.Error);
  MarkInterrupted(lApplied.JournalPath);
  lIndependent := TFile.ReadAllBytes(fSources[1].FileName);
  TFile.WriteAllText(fSources[0].FileName, 'independent first', TEncoding.UTF8);
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lRecovered));
  Assert.AreEqual('restored', lRecovered.Files[1].Status);
  TFile.WriteAllBytes(fSources[1].FileName, lIndependent);
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lRecovered));
  Assert.AreEqual('rollback-failed', lRecovered.Status);
  Assert.AreEqual(HashBytes(lIndependent), HashBytes(TFile.ReadAllBytes(fSources[1].FileName)));
end;

procedure TRefactorTransactionTests.CorruptSecondBackupBlocksAllRecoveryWrites;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lApplied, lRecovered: TRefactoringTransactionResult;
  lFirstHash: string;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lApplied), lApplied.Error);
  MarkInterrupted(lApplied.JournalPath);
  lFirstHash := HashBytes(TFile.ReadAllBytes(fSources[0].FileName));
  TFile.WriteAllText(TPath.Combine(ExtractFileDir(lApplied.JournalPath), '1.original'), 'corrupt', TEncoding.UTF8);
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lRecovered));
  Assert.AreEqual('transaction.backup-corrupt', lRecovered.Error);
  Assert.AreEqual(lFirstHash, HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
end;

procedure TRefactorTransactionTests.NonObjectJournalIsRefused;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lApplied, lRecovered: TRefactoringTransactionResult;
  lFirstHash: string;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lApplied), lApplied.Error);
  lFirstHash := HashBytes(TFile.ReadAllBytes(fSources[0].FileName));
  TFile.WriteAllText(lApplied.JournalPath, '[]', TEncoding.UTF8);
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lRecovered));
  Assert.AreEqual('transaction.invalid-journal', lRecovered.Error);
  Assert.AreEqual(lFirstHash, HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
end;

procedure TRefactorTransactionTests.WriteIntentDoesNotProveOwnershipOfProposedBytes;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lApplied, lRecovered: TRefactoringTransactionResult;
  lJson, lFile: TJSONObject;
  lFirstHash: string;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lApplied), lApplied.Error);
  MarkInterrupted(lApplied.JournalPath);
  GC(lJson, TJSONObject.ParseJSONValue(TFile.ReadAllText(lApplied.JournalPath, TEncoding.UTF8)) as TJSONObject, g);
  lFile := lJson.GetValue<TJSONArray>('files').Items[0] as TJSONObject;
  lFile.RemovePair('status').Free;
  lFile.AddPair('status', 'write-intent');
  TFile.WriteAllText(lApplied.JournalPath, lJson.ToJSON, TEncoding.UTF8);
  // This journal also describes an independent exact-proposed write between
  // durable intent and DAK acquiring its lease. The hash cannot distinguish it.
  lFirstHash := HashBytes(TFile.ReadAllBytes(fSources[0].FileName));
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lRecovered));
  Assert.AreEqual('conflict', lRecovered.Files[0].Status);
  Assert.AreEqual('restored', lRecovered.Files[1].Status);
  Assert.AreEqual(lFirstHash, HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
end;

procedure SetJournalStates(const aPath, aState, aFileState: string);
var
  g: TGarbos;
  lJson, lFile: TJSONObject;
begin
  g := Default(TGarbos);
  GC(lJson, TJSONObject.ParseJSONValue(TFile.ReadAllText(aPath, TEncoding.UTF8)) as TJSONObject, g);
  lJson.RemovePair('status').Free;
  lJson.AddPair('status', aState);
  lFile := lJson.GetValue<TJSONArray>('files').Items[0] as TJSONObject;
  lFile.RemovePair('status').Free;
  lFile.AddPair('status', aFileState);
  TFile.WriteAllText(aPath, lJson.ToJSON, TEncoding.UTF8);
end;

procedure TRefactorTransactionTests.InvalidJournalStatesBlockAllRecoveryWrites(const aState, aFileState: string);
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lApplied, lRecovered: TRefactoringTransactionResult;
  lFirstHash, lSecondHash: string;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lApplied), lApplied.Error);
  SetJournalStates(lApplied.JournalPath, aState, aFileState);
  lFirstHash := HashBytes(TFile.ReadAllBytes(fSources[0].FileName));
  lSecondHash := HashBytes(TFile.ReadAllBytes(fSources[1].FileName));
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lRecovered));
  Assert.AreEqual('blocked', lRecovered.Status);
  Assert.AreEqual('transaction.invalid-file-state', lRecovered.Error);
  Assert.AreEqual(lFirstHash, HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
  Assert.AreEqual(lSecondHash, HashBytes(TFile.ReadAllBytes(fSources[1].FileName)));
end;

procedure TRefactorTransactionTests.InterruptedRestoreIntentCannotReacquireOwnership;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lApplied, lRecovered: TRefactoringTransactionResult;
  lFirstHash: string;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  Assert.IsTrue(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lApplied), lApplied.Error);
  // Model a crash after restore-intent and source restoration but before the
  // restored marker, followed by an independent exact-proposed edit.
  SetJournalStates(lApplied.JournalPath, 'rollback-failed', 'restore-intent');
  lFirstHash := HashBytes(TFile.ReadAllBytes(fSources[0].FileName));
  Assert.IsFalse(RecoverRefactoringTransaction(fOptions.fDprojPath, fRoot, lApplied.JournalPath, lRecovered));
  Assert.AreEqual('rollback-failed', lRecovered.Status);
  Assert.AreEqual('conflict', lRecovered.Files[0].Status);
  Assert.AreEqual('restored', lRecovered.Files[1].Status);
  Assert.AreEqual(lFirstHash, HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
end;

procedure TRefactorTransactionTests.JournalFailurePreventsUnrecordedRestoration;
var
  g: TGarbos;
  lPlan: TSemanticRefactoringPlan;
  lResult: TRefactoringTransactionResult;
  lJournal, lExpected: string;
begin
  g := Default(TGarbos);
  GC(lPlan, Plan, g);
  lJournal := '';
  try
    Assert.IsFalse(ApplyRefactoringTransaction(fOptions, lPlan, fRoot, lResult,
      procedure(const aPhase: string; const aIndex: Integer)
      begin
        if (aPhase = 'written') and (aIndex = 1) then
        begin
          lJournal := TDirectory.GetFiles(fRoot, 'journal.json', TSearchOption.soAllDirectories)[0];
          Assert.IsTrue(SetFileAttributes(PChar(lJournal), FILE_ATTRIBUTE_READONLY));
          raise EAbort.Create('stop-after-write');
        end;
      end));
    Assert.AreEqual('rollback-failed', lResult.Status);
    lExpected := StringReplace(fSources[0].OriginalText, '1;', '2;', []);
    Assert.AreEqual(HashBytes(TEncoding.UTF8.GetBytes(lExpected)), HashBytes(TFile.ReadAllBytes(fSources[0].FileName)));
    lExpected := StringReplace(fSources[1].OriginalText, '1;', '2;', []);
    Assert.AreEqual(HashBytes(TEncoding.UTF8.GetBytes(lExpected)), HashBytes(TFile.ReadAllBytes(fSources[1].FileName)));
    Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(fRoot, '*.tmp', TSearchOption.soAllDirectories)),
      'A failed journal replacement must remove its own long-path temporary files');
  finally
    if lJournal <> '' then
      Assert.IsTrue(SetFileAttributes(PChar(lJournal), FILE_ATTRIBUTE_NORMAL));
  end;
end;

procedure TRefactorTransactionTests.JournalBudgetReservesRecoveryHeadroom(const aFiles: Integer;
  const aBytes: Int64; const aState, aExpected: string);
var
  lError: string;
begin
  lError := RefactoringJournalLimitError(aFiles, aBytes, aState);
  if aExpected = 'ok' then
    Assert.AreEqual('', lError)
  else
    Assert.AreEqual(aExpected, lError);
end;

initialization
  TDUnitX.RegisterTestFixture(TRefactorTransactionTests);

end.
