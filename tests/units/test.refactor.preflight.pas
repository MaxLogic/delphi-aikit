unit Test.Refactor.Preflight;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DelphiSemantics.Refactor.Plan;

type
  [TestFixture]
  [Category('RefactoringLightPreflight,Fast')]
  TRefactorPreflightTests = class
  private
    fRoot: string;
    function Source(const aName, aText: string): TSemanticPlanSource;
    function Edit(const aSource: TSemanticPlanSource): TSemanticPlanEdit;
    function Plan(const aSources: TArray<TSemanticPlanSource>;
      const aEdits: TArray<TSemanticPlanEdit>;
      const aStatus: TSemanticPlanStatus = TSemanticPlanStatus.Complete): TSemanticRefactoringPlan;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure PreservesBomUnicodeAndMixedNewlines;
    [Test] procedure StaleSecondFileReturnsNoFilesAndWritesNothing;
    [TestCase('Outside', 'outside,preflight.out-of-scope')]
    [TestCase('ReadOnly', 'readonly,preflight.read-only')]
    [TestCase('Alias', 'alias,preflight.path-alias')]
    [TestCase('Utf16', 'utf16,preflight.unsupported-encoding')]
    [TestCase('InvalidUtf8', 'invalid,preflight.unsupported-encoding')]
    [TestCase('ReplacementSurrogate', 'surrogate,preflight.lossy-replacement')]
    [Test] procedure RejectsUnsafeInputs(const aMode, aExpected: string);
    [Test] procedure NoChangeReturnsEmptyWriteSet;
    [Test] procedure IncompletePlanIsRejected;
    [Test] procedure MaterializesInsertionDeletionAndAdjacentEdits;
    [Test] procedure IdenticalReplacementReturnsEmptyWriteSet;
    [Test] procedure HardLinkIsRejected;
    [TestCase('ColumnPastLine', 'column,plan.invalid-range')]
    [TestCase('CrLfSplit', 'crlf,plan.invalid-range')]
    [TestCase('SurrogateSplit', 'surrogate,plan.invalid-range')]
    [TestCase('Overlap', 'overlap,plan.overlapping-edits')]
    [TestCase('DuplicateInsert', 'insert,plan.overlapping-edits')]
    [Test] procedure InvalidRangesCannotReachPreflight(const aMode, aExpected: string);
  end;

implementation

uses
  System.Hash, System.IOUtils,
  Winapi.Windows,
  AutoFree, maxLogic.ioutils,
  Dak.Refactor.Preflight, Test.Support;

function HashBytes(const aBytes: TBytes): string;
var
  lHash: THashSHA2;
begin
  lHash := THashSHA2.Create;
  lHash.Update(aBytes);
  Result := lHash.HashAsString;
end;

procedure TRefactorPreflightTests.Setup;
begin
  fRoot := CombinePath([RepoRoot, 'projects', '.dak', 'DelphiAIKit',
    'refactoring-light-preflight', 'fixtures', TGUID.NewGuid.ToString]);
  TDirectory.CreateDirectory(fRoot);
end;

procedure TRefactorPreflightTests.TearDown;
begin
  TDirectory.Delete(fRoot, True);
end;

function TRefactorPreflightTests.Source(const aName, aText: string): TSemanticPlanSource;
begin
  Result := Default(TSemanticPlanSource);
  Result.FileName := TPath.Combine(fRoot, aName);
  Result.OriginalText := aText;
  TFile.WriteAllBytes(Result.FileName, TEncoding.UTF8.GetBytes(aText));
  Result.ContentHash := HashBytes(TFile.ReadAllBytes(Result.FileName));
  Result.IncludeGraphHash := 'no-includes';
end;

function TRefactorPreflightTests.Edit(const aSource: TSemanticPlanSource): TSemanticPlanEdit;
begin
  Result := Default(TSemanticPlanEdit);
  Result.FileName := aSource.FileName;
  Result.StartLine := 1;
  Result.StartColumn := 1;
  Result.EndLine := 1;
  Result.EndColumn := 2;
  Result.ExpectedText := Copy(aSource.OriginalText, 1, 1);
  Result.ReplacementText := 'Z';
end;

function TRefactorPreflightTests.Plan(const aSources: TArray<TSemanticPlanSource>;
  const aEdits: TArray<TSemanticPlanEdit>; const aStatus: TSemanticPlanStatus): TSemanticRefactoringPlan;
var
  lContext: TSemanticPlanContext;
begin
  lContext.ProjectIdentity := 'owned-fixture';
  lContext.CompilerIdentity := 'Delphi12-Win64';
  lContext.ModelVersion := 'test';
  lContext.ConfigurationFingerprint := 'Debug';
  Result := TSemanticRefactoringPlan.Create(lContext, aStatus, 'fixture', aSources, aEdits);
end;

procedure TRefactorPreflightTests.PreservesBomUnicodeAndMixedNewlines;
var
  g: TGarbos;
  lSource: TSemanticPlanSource;
  lEdit: TSemanticPlanEdit;
  lPlan: TSemanticRefactoringPlan;
  lFiles: TArray<TDakMaterializedFile>;
  lOriginal, lExpected: TBytes;
  lError: string;
begin
  g := Default(TGarbos);
  lSource := Source('Unicode.pas', 'A' + #$D83D#$DE00 + ' B'#13#10'C'#10'D'#13'E');
  lOriginal := [$EF, $BB, $BF];
  lOriginal := lOriginal + TEncoding.UTF8.GetBytes(lSource.OriginalText);
  TFile.WriteAllBytes(lSource.FileName, lOriginal);
  lSource.ContentHash := HashBytes(lOriginal);
  lEdit := Edit(lSource);
  lEdit.StartColumn := 2;
  lEdit.EndColumn := 4;
  lEdit.ExpectedText := #$D83D#$DE00;
  lEdit.ReplacementText := #$00E9;
  GC(lPlan, Plan([lSource], [lEdit]), g);
  Assert.IsTrue(MaterializeRefactoringPlan(lPlan, fRoot, lFiles, lError), lError);
  Assert.AreEqual<NativeInt>(1, Length(lFiles));
  lExpected := [$EF, $BB, $BF];
  lExpected := lExpected + TEncoding.UTF8.GetBytes('A' + #$00E9 + ' B'#13#10'C'#10'D'#13'E');
  Assert.AreEqual(HashBytes(lExpected), lFiles[0].ProposedHash);
  Assert.AreEqual(lSource.ContentHash, HashBytes(lFiles[0].OriginalBytes));
  Assert.AreEqual(lSource.ContentHash, HashBytes(TFile.ReadAllBytes(lSource.FileName)));
end;

procedure TRefactorPreflightTests.StaleSecondFileReturnsNoFilesAndWritesNothing;
var
  g: TGarbos;
  lFirst, lSecond: TSemanticPlanSource;
  lPlan: TSemanticRefactoringPlan;
  lFiles: TArray<TDakMaterializedFile>;
  lError, lChangedHash: string;
begin
  g := Default(TGarbos);
  lFirst := Source('First.pas', 'ABC');
  lSecond := Source('Second.pas', 'DEF');
  GC(lPlan, Plan([lFirst, lSecond], [Edit(lFirst), Edit(lSecond)]), g);
  TFile.WriteAllBytes(lSecond.FileName, TEncoding.UTF8.GetBytes('independent change'));
  lChangedHash := HashBytes(TFile.ReadAllBytes(lSecond.FileName));
  Assert.IsFalse(MaterializeRefactoringPlan(lPlan, fRoot, lFiles, lError));
  Assert.AreEqual('preflight.stale-source', lError);
  Assert.AreEqual<NativeInt>(0, Length(lFiles));
  Assert.AreEqual(lFirst.ContentHash, HashBytes(TFile.ReadAllBytes(lFirst.FileName)));
  Assert.AreEqual(lChangedHash, HashBytes(TFile.ReadAllBytes(lSecond.FileName)));
end;

procedure TRefactorPreflightTests.RejectsUnsafeInputs(const aMode, aExpected: string);
var
  g: TGarbos;
  lSource, lAlias: TSemanticPlanSource;
  lEdit: TSemanticPlanEdit;
  lPlan: TSemanticRefactoringPlan;
  lFiles: TArray<TDakMaterializedFile>;
  lBytes: TBytes;
  lError, lRoot: string;
begin
  g := Default(TGarbos);
  lSource := Source('Input.pas', 'ABC');
  lRoot := fRoot;
  lEdit := Edit(lSource);
  if aMode = 'outside' then
  begin
    lRoot := TPath.Combine(fRoot, 'Selected');
    TDirectory.CreateDirectory(lRoot);
  end;
  if aMode = 'readonly' then
    Assert.IsTrue(SetFileAttributes(PChar(lSource.FileName), FILE_ATTRIBUTE_READONLY));
  if aMode = 'utf16' then
    TFile.WriteAllBytes(lSource.FileName, [$FF, $FE, $41, 0, $42, 0, $43, 0]);
  if aMode = 'invalid' then
    TFile.WriteAllBytes(lSource.FileName, [$C0, $AF]);
  if aMode = 'surrogate' then
    lEdit.ReplacementText := #$D800;
  lBytes := TFile.ReadAllBytes(lSource.FileName);
  lSource.ContentHash := HashBytes(lBytes);
  if aMode = 'alias' then
  begin
    lAlias := lSource;
    lAlias.FileName := TPath.Combine(fRoot, '.\Input.pas');
    GC(lPlan, Plan([lSource, lAlias], [lEdit, Edit(lAlias)]), g);
  end else
    GC(lPlan, Plan([lSource], [lEdit]), g);
  try
    Assert.IsFalse(MaterializeRefactoringPlan(lPlan, lRoot, lFiles, lError));
    Assert.AreEqual(aExpected, lError);
    Assert.AreEqual<NativeInt>(0, Length(lFiles));
    Assert.AreEqual(lSource.ContentHash, HashBytes(TFile.ReadAllBytes(lSource.FileName)));
  finally
    Assert.IsTrue(SetFileAttributes(PChar(lSource.FileName), FILE_ATTRIBUTE_NORMAL));
  end;
end;

procedure TRefactorPreflightTests.NoChangeReturnsEmptyWriteSet;
var
  g: TGarbos;
  lSource: TSemanticPlanSource;
  lPlan: TSemanticRefactoringPlan;
  lFiles: TArray<TDakMaterializedFile>;
  lError: string;
begin
  g := Default(TGarbos);
  lSource := Source('Input.pas', 'ABC');
  GC(lPlan, Plan([lSource], [], TSemanticPlanStatus.NoChange), g);
  Assert.IsTrue(MaterializeRefactoringPlan(lPlan, fRoot, lFiles, lError), lError);
  Assert.AreEqual<NativeInt>(0, Length(lFiles));
end;

procedure TRefactorPreflightTests.IncompletePlanIsRejected;
var
  g: TGarbos;
  lSource: TSemanticPlanSource;
  lPlan: TSemanticRefactoringPlan;
  lFiles: TArray<TDakMaterializedFile>;
  lError: string;
begin
  g := Default(TGarbos);
  lSource := Source('Input.pas', 'ABC');
  GC(lPlan, Plan([lSource], [], TSemanticPlanStatus.Incomplete), g);
  Assert.IsFalse(MaterializeRefactoringPlan(lPlan, fRoot, lFiles, lError));
  Assert.AreEqual('preflight.incomplete-plan', lError);
  Assert.AreEqual<NativeInt>(0, Length(lFiles));
end;

procedure TRefactorPreflightTests.MaterializesInsertionDeletionAndAdjacentEdits;
var
  g: TGarbos;
  lSource: TSemanticPlanSource;
  lFirst, lSecond, lInsert: TSemanticPlanEdit;
  lPlan: TSemanticRefactoringPlan;
  lFiles: TArray<TDakMaterializedFile>;
  lError: string;
begin
  g := Default(TGarbos);
  lSource := Source('Input.pas', 'ABCD'#13#10'// keep directive {$IFDEF X}'#10);
  lFirst := Edit(lSource);
  lFirst.ReplacementText := '';
  lSecond := Edit(lSource);
  lSecond.StartColumn := 2;
  lSecond.EndColumn := 3;
  lSecond.ExpectedText := 'B';
  lSecond.ReplacementText := 'long';
  lInsert := Edit(lSource);
  lInsert.StartLine := 3;
  lInsert.EndLine := 3;
  lInsert.EndColumn := 1;
  lInsert.ExpectedText := '';
  lInsert.ReplacementText := 'end';
  GC(lPlan, Plan([lSource], [lInsert, lSecond, lFirst]), g);
  Assert.IsTrue(MaterializeRefactoringPlan(lPlan, fRoot, lFiles, lError), lError);
  Assert.AreEqual<NativeInt>(1, Length(lFiles));
  Assert.AreEqual('longCD'#13#10'// keep directive {$IFDEF X}'#10'end',
    TEncoding.UTF8.GetString(lFiles[0].ProposedBytes));
  Assert.AreEqual(lSource.ContentHash, HashBytes(TFile.ReadAllBytes(lSource.FileName)));
end;

procedure TRefactorPreflightTests.IdenticalReplacementReturnsEmptyWriteSet;
var
  g: TGarbos;
  lSource: TSemanticPlanSource;
  lEdit: TSemanticPlanEdit;
  lPlan: TSemanticRefactoringPlan;
  lFiles: TArray<TDakMaterializedFile>;
  lError: string;
begin
  g := Default(TGarbos);
  lSource := Source('Input.pas', 'ABC');
  lEdit := Edit(lSource);
  lEdit.ReplacementText := lEdit.ExpectedText;
  GC(lPlan, Plan([lSource], [lEdit]), g);
  Assert.IsTrue(MaterializeRefactoringPlan(lPlan, fRoot, lFiles, lError), lError);
  Assert.AreEqual<NativeInt>(0, Length(lFiles));
  Assert.AreEqual(lSource.ContentHash, HashBytes(TFile.ReadAllBytes(lSource.FileName)));
end;

procedure TRefactorPreflightTests.HardLinkIsRejected;
var
  g: TGarbos;
  lSource: TSemanticPlanSource;
  lPlan: TSemanticRefactoringPlan;
  lFiles: TArray<TDakMaterializedFile>;
  lError, lAlias: string;
begin
  g := Default(TGarbos);
  lSource := Source('Input.pas', 'ABC');
  lAlias := TPath.Combine(fRoot, 'HardLink.pas');
  Assert.IsTrue(CreateHardLink(PChar(lAlias), PChar(lSource.FileName), nil), SysErrorMessage(GetLastError));
  GC(lPlan, Plan([lSource], [Edit(lSource)]), g);
  Assert.IsFalse(MaterializeRefactoringPlan(lPlan, fRoot, lFiles, lError));
  Assert.AreEqual('preflight.path-alias', lError);
  Assert.AreEqual<NativeInt>(0, Length(lFiles));
  Assert.AreEqual(lSource.ContentHash, HashBytes(TFile.ReadAllBytes(lAlias)));
end;

procedure TRefactorPreflightTests.InvalidRangesCannotReachPreflight(const aMode, aExpected: string);
var
  g: TGarbos;
  lSource: TSemanticPlanSource;
  lEdit, lSecond: TSemanticPlanEdit;
  lContext: TSemanticPlanContext;
  lPlan, lValid: TSemanticRefactoringPlan;
  lEdits: TArray<TSemanticPlanEdit>;
  lError: string;
begin
  g := Default(TGarbos);
  lSource := Source('Input.pas', 'A' + #$D83D#$DE00 + #13#10'B');
  GC(lValid, Plan([lSource], [Edit(lSource)]), g);
  lContext := lValid.Context;
  lEdit := Edit(lSource);
  if aMode = 'column' then
    lEdit.EndColumn := 20;
  if aMode = 'crlf' then
    lEdit.EndColumn := 5;
  if aMode = 'surrogate' then
    lEdit.EndColumn := 3;
  lEdits := [lEdit];
  if aMode = 'overlap' then
    lEdits := [lEdit, lEdit];
  if aMode = 'insert' then
  begin
    lSecond := lEdit;
    lSecond.EndColumn := lSecond.StartColumn;
    lSecond.ExpectedText := '';
    lEdits := [lSecond, lSecond];
  end;
  Assert.IsFalse(TSemanticRefactoringPlan.TryCreate(lContext, TSemanticPlanStatus.Complete,
    'fixture', [lSource], lEdits, lPlan, lError));
  GC(lPlan, g);
  Assert.IsNull(lPlan);
  Assert.AreEqual(aExpected, lError);
  Assert.AreEqual(lSource.ContentHash, HashBytes(TFile.ReadAllBytes(lSource.FileName)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRefactorPreflightTests);

end.
