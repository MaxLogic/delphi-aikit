unit Test.DakWorkingPaths;

interface

uses
  DUnitX.TestFramework;

type
  // DAK-385: DAK's transient working paths below .dak\<ProjectName>\ must stay short enough for deep project
  // locations. Each working area's run directory is created by the product's own creation routine in a scratch
  // project and measured, with its deepest files, against the depth of the kept build log
  // (build\run-<GUID>\stderr.log, DAK-379), whose documented layout stays unchanged.
  [TestFixture]
  [Category('Slow')]
  TDakWorkingPathTests = class
  private
    function KeptBuildLogDepth: Integer;
    function RelativeDepth(const aDakProjectRoot, aPath, aProjectName: string): Integer;
    procedure AssertWithinBudget(const aArea, aDakProjectRoot, aProjectName: string; const aPaths: array of string);
    procedure CreateDeepProject(const aPrefix: string; const aWithForm: Boolean;
      out aRoot, aProjectDir, aDproj: string);
    procedure CreateDeepFormProject(const aPrefix, aProjectName, aExtraUnitName: string;
      const aRegisterUnitLength: Integer; out aRoot, aProjectDir, aDproj: string);
    procedure AssertDeepRefusal(const aProjectName, aDproj, aProjectDir, aDeepFileName: string);
  public
    [Test]
    procedure RunDirectoriesAreExclusiveWithShortTokens;
    [Test]
    procedure RunDirectoryFailureNamesTheParent;
    [Test]
    procedure RemoveWithWorkspaceStaysWithinBuildLogDepth;
    [Test]
    procedure DfmCheckRunWorkspaceStaysWithinBuildLogDepth;
    [Test]
    procedure RefactorTransactionWorkspaceStaysWithinBuildLogDepth;
    [Test]
    procedure SignatureWorkspaceStaysWithinBuildLogDepth;
    [Test]
    procedure DfmCheckRefusesATooDeepProjectBeforeAnyWork;
    [Test]
    procedure DfmCheckWithNothingToValidateSucceedsInADeepProject;
    [Test]
    procedure RenameAndDeadCodeRunsNeverShareAWorkspace;
    [Test]
    procedure RenameWorkspaceStaysWithinBuildLogDepth;
    [Test]
    procedure DeadCodeWorkspaceStaysWithinBuildLogDepth;
    [Test]
    procedure DfmCheckRefusesWhenTheRuntimeGuardCopyIsTooDeep;
    [Test]
    procedure DfmCheckRootKeepsTheLiteralLayoutForAnAbsoluteProject;
    [Test]
    procedure RefactorTransactionRootKeepsTheLiteralLayoutForAnAbsoluteProject;
    [Test]
    procedure RefactorTransactionRootIsAbsoluteForARelativeProject;
    [Test]
    procedure SignatureRunDirectoryKeepsTheLiteralLayoutForAnAbsoluteProject;
    [Test]
    procedure DfmCheckRefusesWhenAProjectUnitDcuIsTooDeep;
  end;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  maxLogic.ioutils,
  Dak.Build.Runner, Dak.DfmCheck, Dak.Paths, Dak.Refactor, Dak.Refactor.Transaction, Dak.RemoveWith.Transaction,
  Dak.Signature.Command, Dak.Types,
  Test.Support;

const
  cProjectName = 'Proj';

type
  // Records whether the pipeline started any external process.
  TRecordingDfmCheckRunner = class(TInterfacedObject, IDfmCheckProcessRunner)
  private
    fCalls: Integer;
  public
    function Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
      const aEnvironmentBlock: string; const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal;
      out aError: string): Boolean;
    property Calls: Integer read fCalls;
  end;

function TRecordingDfmCheckRunner.Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
  const aEnvironmentBlock: string; const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal;
  out aError: string): Boolean;
begin
  Inc(fCalls);
  aExitCode := 1;
  aError := 'no process may start';
  Result := False;
end;

function TDakWorkingPathTests.KeptBuildLogDepth: Integer;
var
  lError: string;
  lOptions: TAppOptions;
  lRoot: string;
  lRunDir: string;
begin
  lRoot := UniqueTempPath('wp-build');
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := TPath.Combine(lRoot, cProjectName + '.dproj');
    Assert.IsTrue(TryCreateBuildLogRunDir(lOptions, lRunDir, lError), lError);
    Result := RelativeDepth(DakProjectRootForProjectPath(lOptions.fDprojPath),
      TPath.Combine(lRunDir, 'stderr.log'), cProjectName);
  finally
    DeleteTempPath(lRoot);
  end;
end;

// Characters below .dak\<ProjectName>\, without the parts derived from the project name: those grow with the
// user's project, not with DAK's layout.
function TDakWorkingPathTests.RelativeDepth(const aDakProjectRoot, aPath, aProjectName: string): Integer;
var
  lRelative: string;
begin
  Assert.IsTrue(StartsText(IncludeTrailingPathDelimiter(aDakProjectRoot), aPath),
    aPath + ' must lie below ' + aDakProjectRoot);
  lRelative := Copy(aPath, Length(IncludeTrailingPathDelimiter(aDakProjectRoot)) + 1, MaxInt);
  Result := Length(StringReplace(lRelative, aProjectName, '', [rfReplaceAll, rfIgnoreCase]));
end;

procedure TDakWorkingPathTests.AssertWithinBudget(const aArea, aDakProjectRoot, aProjectName: string;
  const aPaths: array of string);
var
  lBudget: Integer;
  lDepth: Integer;
  lPath: string;
begin
  lBudget := KeptBuildLogDepth;
  for lPath in aPaths do
  begin
    lDepth := RelativeDepth(aDakProjectRoot, lPath, aProjectName);
    Assert.IsTrue(lDepth <= lBudget, Format('%s: %s is %d characters below .dak\<ProjectName>\; the kept build ' +
      'log is %d', [aArea, lPath, lDepth, lBudget]));
  end;
end;

// A project whose deepest generated dfm-check file passes the classic limit by a few characters, while the
// project itself stays creatable by this (not long-path aware) test process.
procedure TDakWorkingPathTests.CreateDeepProject(const aPrefix: string; const aWithForm: Boolean;
  out aRoot, aProjectDir, aDproj: string);
var
  lExpected: TDfmCheckPaths;
  lPadding: Integer;
  lUnitsXml: string;
  lUsesText: string;
begin
  aRoot := UniqueTempPath(aPrefix);
  lExpected := BuildExpectedDfmCheckPaths(TPath.Combine(aRoot, cProjectName + '.dproj'));
  AssignOwnedRunPaths(lExpected, StringOfChar('0', cDakRunTokenLength));
  lPadding := cClassicPathLimit + 5 - Length(lExpected.fGeneratedRegisterUnit) - 1;
  Assert.IsTrue(lPadding > 0, 'the run root is already too deep for this test');
  aProjectDir := TPath.Combine(aRoot, StringOfChar('d', lPadding));
  Assert.IsTrue(Length(aProjectDir) < 240, 'the project directory must stay creatable: ' + aProjectDir);
  aDproj := TPath.Combine(aProjectDir, cProjectName + '.dproj');
  TDirectory.CreateDirectory(aProjectDir);

  lUnitsXml := '';
  lUsesText := '';
  if aWithForm then
  begin
    lUnitsXml := '<ItemGroup><DCCReference Include="MainForm.pas"/></ItemGroup>';
    lUsesText := ' uses Vcl.Forms, MainForm in ''MainForm.pas'' {MainForm};';
    TFile.WriteAllText(TPath.Combine(aProjectDir, 'MainForm.pas'),
      'unit MainForm;'#13#10'interface'#13#10'uses System.Classes, Vcl.Forms;'#13#10 +
      'type'#13#10'  TMainForm = class(TForm)'#13#10'  end;'#13#10 +
      'implementation'#13#10'{$R *.dfm}'#13#10'end.'#13#10, TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(aProjectDir, 'MainForm.dfm'),
      'object MainForm: TMainForm'#13#10'  Caption = ''MainForm'''#13#10'end'#13#10, TEncoding.UTF8);
  end;
  TFile.WriteAllText(aDproj, '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>' + cProjectName + '.dpr</MainSource></PropertyGroup>' + lUnitsXml +
    '</Project>', TEncoding.UTF8);
  TFile.WriteAllText(TPath.ChangeExtension(aDproj, '.dpr'),
    'program ' + cProjectName + ';' + lUsesText + ' begin end.', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(aProjectDir, 'dak.ini'), '[Build]'#13#10'DelphiVersion=23.0'#13#10,
    TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(aProjectDir, 'rsvars.bat'), '@echo off'#13#10, TEncoding.ASCII);
end;

procedure TDakWorkingPathTests.RunDirectoriesAreExclusiveWithShortTokens;
var
  lError: string;
  lFirst: string;
  lParent: string;
  lSecond: string;
  lToken: string;
  lTokens: TArray<string>;
begin
  lParent := TPath.Combine(UniqueTempPath('wp-runs'), 'runs');
  try
    Assert.IsTrue(TryCreateDakRunDirectory(lParent, lFirst, lError), lError);
    Assert.IsTrue(TryCreateDakRunDirectory(lParent, lSecond, lError), lError);
    Assert.AreNotEqual(lFirst, lSecond, 'each run gets its own directory');
    Assert.IsTrue(TDirectory.Exists(lFirst) and TDirectory.Exists(lSecond), 'both run directories exist');
    lTokens := [ExtractFileName(lFirst), ExtractFileName(lSecond)];
    for lToken in lTokens do
    begin
      Assert.AreEqual(cDakRunTokenLength, Length(lToken), lToken);
      for var c in lToken do
        Assert.IsTrue(CharInSet(c, ['0'..'9', 'a'..'f']), 'lowercase hex token: ' + lToken);
    end;
  finally
    DeleteTempPath(ExtractFileDir(lParent));
  end;
end;

procedure TDakWorkingPathTests.RunDirectoryFailureNamesTheParent;
var
  lError: string;
  lParent: string;
  lRoot: string;
  lRunDir: string;
begin
  lRoot := UniqueTempPath('wp-blocked');
  // A file where the parent directory belongs makes creation impossible.
  lParent := TPath.Combine(lRoot, 'runs');
  TDirectory.CreateDirectory(lRoot);
  try
    TFile.WriteAllText(lParent, 'not a directory');
    Assert.IsFalse(TryCreateDakRunDirectory(lParent, lRunDir, lError), 'creation must fail');
    Assert.AreEqual('', lRunDir);
    Assert.IsTrue(lError.Contains('DAK working directory could not be created under ' + lParent), lError);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TDakWorkingPathTests.RemoveWithWorkspaceStaysWithinBuildLogDepth;
var
  lDproj: string;
  lError: string;
  lRoot: string;
  lRunDir: string;
begin
  lRoot := UniqueTempPath('wp-remove-with');
  lDproj := TPath.Combine(lRoot, cProjectName + '.dproj');
  try
    Assert.IsTrue(TryCreateRemoveWithWorkspace(lDproj, lRunDir, lError), lError);
    Assert.IsTrue(TDirectory.Exists(lRunDir), lRunDir);
    AssertWithinBudget('remove-with', DakProjectRootForProjectPath(lDproj), cProjectName, [
      CombinePath([lRunDir, cRemoveWithPreflightDirName, 'stderr.log']),
      CombinePath([lRunDir, cRemoveWithApplyDirName, 'stderr.log']),
      CombinePath([lRunDir, cRemoveWithBackupDirName, AtomicTempFileName]),
      CombinePath([lRunDir, cRemoveWithBackupDirName, '9999.bak']),
      CombinePath([lRunDir, AtomicTempFileName])]);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TDakWorkingPathTests.DfmCheckRunWorkspaceStaysWithinBuildLogDepth;
var
  lDproj: string;
  lError: string;
  lPaths: TDfmCheckPaths;
  lRoot: string;
  lRunLock: THandle;
begin
  lRoot := UniqueTempPath('wp-dfm-check');
  lDproj := TPath.Combine(lRoot, cProjectName + '.dproj');
  lRunLock := INVALID_HANDLE_VALUE;
  try
    lPaths := BuildExpectedDfmCheckPaths(lDproj);
    Assert.IsTrue(TryCreateDfmCheckRunWorkspace(lPaths, lRunLock, lError), lError);
    Assert.IsTrue(TDirectory.Exists(lPaths.fRunDir), lPaths.fRunDir);
    AssertWithinBudget('dfm-check', DakProjectRootForProjectPath(lDproj), cProjectName, [
      lPaths.fGeneratedRegisterUnit,
      lPaths.fGeneratedDproj + '.local',
      TPath.Combine(lPaths.fGeneratedDir, '_DfmCheckValidator.log'),
      TPath.Combine(lPaths.fRunDir, cDfmCheckRunLockFileName),
      CombinePath([lPaths.fRunDir, 'bin', cProjectName + '_DfmCheck.exe'])]);
  finally
    ReleaseDfmCheckRunLock(lRunLock);
    DeleteTempPath(lRoot);
  end;
end;

procedure TDakWorkingPathTests.RefactorTransactionWorkspaceStaysWithinBuildLogDepth;
var
  lDproj: string;
  lError: string;
  lRoot: string;
  lRunDir: string;
begin
  lRoot := UniqueTempPath('wp-transaction');
  lDproj := TPath.Combine(lRoot, cProjectName + '.dproj');
  try
    Assert.IsTrue(TryCreateTransactionDirectory(lDproj, lRunDir, lError), lError);
    Assert.IsTrue(TDirectory.Exists(lRunDir), lRunDir);
    AssertWithinBudget('refactor transaction', DakProjectRootForProjectPath(lDproj), cProjectName, [
      CombinePath([lRunDir, 'verification', 'stderr.log']),
      CombinePath([lRunDir, 'baseline', 'stderr.log']),
      AtomicArtifactTempPath(TPath.Combine(lRunDir, 'journal.json')),
      // The journal holds at most 1000 files, so a staged name has at most three index digits.
      AtomicArtifactTempPath(TPath.Combine(lRunDir, '999.original')),
      AtomicArtifactTempPath(TPath.Combine(lRunDir, '999.proposed'))]);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TDakWorkingPathTests.SignatureWorkspaceStaysWithinBuildLogDepth;
var
  lDproj: string;
  lError: string;
  lRoot: string;
  lRunDir: string;
begin
  lRoot := UniqueTempPath('wp-signature');
  lDproj := TPath.Combine(lRoot, cProjectName + '.dproj');
  try
    Assert.IsTrue(TryCreateSignatureRunDirectory(lDproj, lRunDir, lError), lError);
    Assert.IsTrue(TDirectory.Exists(lRunDir), lRunDir);
    AssertWithinBudget('signature', DakProjectRootForProjectPath(lDproj), cProjectName, [
      TPath.Combine(lRunDir, 'stderr.log')]);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TDakWorkingPathTests.DfmCheckRefusesATooDeepProjectBeforeAnyWork;
var
  lCategory: TDfmCheckErrorCategory;
  lDproj: string;
  lError: string;
  lOptions: TAppOptions;
  lProjectDir: string;
  lResult: Integer;
  lRoot: string;
  lRunner: TRecordingDfmCheckRunner;
  lRunnerRef: IDfmCheckProcessRunner;
begin
  CreateDeepProject('wp-deep', True, lRoot, lProjectDir, lDproj);
  try
    lRunner := TRecordingDfmCheckRunner.Create;
    lRunnerRef := lRunner;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDproj;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win64';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(lProjectDir, 'rsvars.bat');
    lResult := RunDfmCheckPipeline(lOptions, lRunnerRef, nil, lCategory, lError);

    Assert.AreEqual(TDfmCheckErrorCategory.ecInvalidInput, lCategory, lError);
    Assert.AreEqual(MapDfmCheckExitCode(TDfmCheckErrorCategory.ecInvalidInput, 0), lResult, lError);
    Assert.IsTrue(lError.Contains('dfm-check path too long'), lError);
    Assert.IsTrue(lError.Contains('accept at most ' + IntToStr(cClassicPathLimit)), lError);
    Assert.AreEqual(0, lRunner.Calls, 'no process may start');
    Assert.IsFalse(TDirectory.Exists(CombinePath([lProjectDir, '.dak', cProjectName, 'dfm-check', 'runs'])),
      'no run workspace may be created before the check');
  finally
    DeleteTempPath(lRoot);
  end;
end;

// The review of DAK-385 found the check refusing a deep project before the cache short-circuit, turning a
// successful "nothing to validate" run into exit 3.
procedure TDakWorkingPathTests.DfmCheckWithNothingToValidateSucceedsInADeepProject;
var
  lCategory: TDfmCheckErrorCategory;
  lDproj: string;
  lError: string;
  lOptions: TAppOptions;
  lProjectDir: string;
  lResult: Integer;
  lRoot: string;
  lRunner: TRecordingDfmCheckRunner;
  lRunnerRef: IDfmCheckProcessRunner;
begin
  CreateDeepProject('wp-deep-formless', False, lRoot, lProjectDir, lDproj);
  try
    lRunner := TRecordingDfmCheckRunner.Create;
    lRunnerRef := lRunner;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDproj;
    lOptions.fDelphiVersion := '23.0';
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win64';
    lOptions.fDfmCheckAll := True;
    lResult := RunDfmCheckPipeline(lOptions, lRunnerRef, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, lError);
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, lError);
    Assert.AreEqual(0, lRunner.Calls, 'no process may start');
    Assert.IsFalse(TDirectory.Exists(CombinePath([lProjectDir, '.dak', cProjectName, 'dfm-check', 'runs'])),
      'no run workspace may be created');
  finally
    DeleteTempPath(lRoot);
  end;
end;

// DAK-386: a project with one form, and optionally one more unit, placed so that the generated register unit
// path is exactly aRegisterUnitLength characters long.
procedure TDakWorkingPathTests.CreateDeepFormProject(const aPrefix, aProjectName, aExtraUnitName: string;
  const aRegisterUnitLength: Integer; out aRoot, aProjectDir, aDproj: string);
var
  lExpected: TDfmCheckPaths;
  lPadding: Integer;
  lUnitsXml: string;
  lUsesText: string;
begin
  aRoot := UniqueTempPath(aPrefix);
  lExpected := BuildExpectedDfmCheckPaths(TPath.Combine(aRoot, aProjectName + '.dproj'));
  AssignOwnedRunPaths(lExpected, StringOfChar('0', cDakRunTokenLength));
  lPadding := aRegisterUnitLength - Length(lExpected.fGeneratedRegisterUnit) - 1;
  Assert.IsTrue(lPadding > 0, 'the run root is already too deep for this test');
  aProjectDir := TPath.Combine(aRoot, StringOfChar('d', lPadding));
  aDproj := TPath.Combine(aProjectDir, aProjectName + '.dproj');
  TDirectory.CreateDirectory(aProjectDir);

  lUnitsXml := '<DCCReference Include="MainForm.pas"/>';
  lUsesText := ' uses Vcl.Forms, MainForm in ''MainForm.pas'' {MainForm}';
  TFile.WriteAllText(TPath.Combine(aProjectDir, 'MainForm.pas'),
    'unit MainForm;'#13#10'interface'#13#10'uses System.Classes, Vcl.Forms;'#13#10 +
    'type'#13#10'  TMainForm = class(TForm)'#13#10'  end;'#13#10 +
    'implementation'#13#10'{$R *.dfm}'#13#10'end.'#13#10, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(aProjectDir, 'MainForm.dfm'),
    'object MainForm: TMainForm'#13#10'  Caption = ''MainForm'''#13#10'end'#13#10, TEncoding.UTF8);
  if aExtraUnitName <> '' then
  begin
    Assert.IsTrue(Length(TPath.Combine(aProjectDir, aExtraUnitName + '.pas')) < 240, 'the unit must stay creatable');
    lUnitsXml := lUnitsXml + '<DCCReference Include="' + aExtraUnitName + '.pas"/>';
    lUsesText := lUsesText + ', ' + aExtraUnitName + ' in ''' + aExtraUnitName + '.pas''';
    TFile.WriteAllText(TPath.Combine(aProjectDir, aExtraUnitName + '.pas'),
      'unit ' + aExtraUnitName + ';'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10, TEncoding.UTF8);
  end;
  TFile.WriteAllText(aDproj, '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>' + aProjectName + '.dpr</MainSource></PropertyGroup><ItemGroup>' + lUnitsXml +
    '</ItemGroup></Project>', TEncoding.UTF8);
  TFile.WriteAllText(TPath.ChangeExtension(aDproj, '.dpr'),
    'program ' + aProjectName + ';' + lUsesText + '; begin end.', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(aProjectDir, 'dak.ini'), '[Build]'#13#10'DelphiVersion=23.0'#13#10,
    TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(aProjectDir, 'rsvars.bat'), '@echo off'#13#10, TEncoding.ASCII);
end;

// DAK-386: the refusal names the file that does not fit, shows the run directory as a placeholder rather than a
// token that looks like a real directory, and comes before any process or run workspace.
procedure TDakWorkingPathTests.AssertDeepRefusal(const aProjectName, aDproj, aProjectDir, aDeepFileName: string);
var
  lCategory: TDfmCheckErrorCategory;
  lError: string;
  lOptions: TAppOptions;
  lResult: Integer;
  lRunner: TRecordingDfmCheckRunner;
  lRunnerRef: IDfmCheckProcessRunner;
begin
  lRunner := TRecordingDfmCheckRunner.Create;
  lRunnerRef := lRunner;
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := aDproj;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win64';
  lOptions.fDfmCheckFilter := 'MainForm.dfm';
  lOptions.fHasRsVarsPath := True;
  lOptions.fRsVarsPath := TPath.Combine(aProjectDir, 'rsvars.bat');
  lResult := RunDfmCheckPipeline(lOptions, lRunnerRef, nil, lCategory, lError);

  Assert.AreEqual(TDfmCheckErrorCategory.ecInvalidInput, lCategory, lError);
  Assert.AreEqual(MapDfmCheckExitCode(TDfmCheckErrorCategory.ecInvalidInput, 0), lResult, lError);
  Assert.IsTrue(lError.Contains('dfm-check path too long'), lError);
  Assert.IsTrue(lError.Contains('\' + aDeepFileName + ' is '), 'the refusal names the deepest file: ' + lError);
  Assert.IsTrue(lError.Contains('\runs\<run-id>\'), 'the run directory is shown as a placeholder: ' + lError);
  Assert.IsFalse(lError.Contains(StringOfChar('0', cDakRunTokenLength)), 'no token that looks real: ' + lError);
  Assert.AreEqual(0, lRunner.Calls, 'no process may start');
  Assert.IsFalse(TDirectory.Exists(CombinePath([aProjectDir, '.dak', aProjectName, 'dfm-check', 'runs'])),
    'no run workspace may be created before the check');
end;

// DAK-386: the 17-digit millisecond names gave runs started in the same millisecond one directory, so their
// backups and manifests overwrote each other. Back-to-back starts land in the same millisecond almost always.
procedure TDakWorkingPathTests.RenameAndDeadCodeRunsNeverShareAWorkspace;
const
  cRunsPerArea = 25;
var
  lDproj: string;
  lError: string;
  lRoot: string;
  lRunDir: string;
  lSeen: THashSet<string>;
begin
  lRoot := UniqueTempPath('wp-refactor-runs');
  lDproj := TPath.Combine(lRoot, cProjectName + '.dproj');
  lSeen := THashSet<string>.Create;
  try
    for var i := 1 to cRunsPerArea do
    begin
      Assert.IsTrue(TryCreateRenameWorkspace(lDproj, lRunDir, lError), lError);
      Assert.IsTrue(lSeen.Add(LowerCase(lRunDir)), 'two rename runs got ' + lRunDir);
      Assert.IsTrue(TDirectory.Exists(lRunDir), lRunDir);
      Assert.IsTrue(StartsText(IncludeTrailingPathDelimiter(DakProjectPath(DakProjectRootForProjectPath(lDproj),
        ['rename'])), lRunDir), lRunDir);
    end;
    for var i := 1 to cRunsPerArea do
    begin
      Assert.IsTrue(TryCreateDeadCodeWorkspace(lDproj, lRunDir, lError), lError);
      Assert.IsTrue(lSeen.Add(LowerCase(lRunDir)), 'two dead-code runs got ' + lRunDir);
      Assert.IsTrue(TDirectory.Exists(lRunDir), lRunDir);
      Assert.IsTrue(StartsText(IncludeTrailingPathDelimiter(DakProjectPath(DakProjectRootForProjectPath(lDproj),
        ['dead-code'])), lRunDir), lRunDir);
    end;
    Assert.AreEqual(Integer(2 * cRunsPerArea), Integer(lSeen.Count));
  finally
    lSeen.Free;
    DeleteTempPath(lRoot);
  end;
end;

// Backups are named <index>-<source file name>.bak. The source file name is the user's, like the project name,
// so the measurement uses the project name for it.
procedure TDakWorkingPathTests.RenameWorkspaceStaysWithinBuildLogDepth;
var
  lDproj: string;
  lError: string;
  lRoot: string;
  lRunDir: string;
begin
  lRoot := UniqueTempPath('wp-rename');
  lDproj := TPath.Combine(lRoot, cProjectName + '.dproj');
  try
    Assert.IsTrue(TryCreateRenameWorkspace(lDproj, lRunDir, lError), lError);
    AssertWithinBudget('rename', DakProjectRootForProjectPath(lDproj), cProjectName, [
      CombinePath([lRunDir, 'build-verification', 'stdout.log']),
      CombinePath([lRunDir, 'build-verification', 'stderr.log']),
      CombinePath([lRunDir, 'backup', '9999-' + cProjectName + '.pas.bak']),
      TPath.Combine(lRunDir, 'manifest.json')]);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TDakWorkingPathTests.DeadCodeWorkspaceStaysWithinBuildLogDepth;
var
  lDproj: string;
  lError: string;
  lRoot: string;
  lRunDir: string;
begin
  lRoot := UniqueTempPath('wp-dead-code');
  lDproj := TPath.Combine(lRoot, cProjectName + '.dproj');
  try
    Assert.IsTrue(TryCreateDeadCodeWorkspace(lDproj, lRunDir, lError), lError);
    AssertWithinBudget('dead-code', DakProjectRootForProjectPath(lDproj), cProjectName, [
      CombinePath([lRunDir, 'build-verification', 'stdout.log']),
      CombinePath([lRunDir, 'build-verification', 'stderr.log']),
      CombinePath([lRunDir, 'backup', '9999-' + cProjectName + '.pas.bak']),
      TPath.Combine(lRunDir, 'manifest.json')]);
  finally
    DeleteTempPath(lRoot);
  end;
end;

// DAK-385 review: for a one-character project name the copied DfmCheckRuntimeGuard.pas is the deepest generated
// file. The register unit fits the limit exactly; the guard copy next to it does not.
procedure TDakWorkingPathTests.DfmCheckRefusesWhenTheRuntimeGuardCopyIsTooDeep;
var
  lDproj: string;
  lProjectDir: string;
  lRoot: string;
begin
  CreateDeepFormProject('wp-deep-guard', 'P', '', cClassicPathLimit, lRoot, lProjectDir, lDproj);
  try
    AssertDeepRefusal('P', lDproj, lProjectDir, 'DfmCheckRuntimeGuard.pas');
  finally
    DeleteTempPath(lRoot);
  end;
end;

// DAK-385 review: the compiler writes each project unit's DCU to runs\<run>\dcu\. A unit name much longer than the
// project name makes that the deepest file although every generated file fits.
procedure TDakWorkingPathTests.DfmCheckRefusesWhenAProjectUnitDcuIsTooDeep;
var
  lDproj: string;
  lProjectDir: string;
  lRoot: string;
  lUnitName: string;
begin
  lUnitName := 'LongUnit' + StringOfChar('x', 32);
  CreateDeepFormProject('wp-deep-dcu', cProjectName, lUnitName, cClassicPathLimit - 4, lRoot, lProjectDir, lDproj);
  try
    AssertDeepRefusal(cProjectName, lDproj, lProjectDir, lUnitName + '.dcu');
  finally
    DeleteTempPath(lRoot);
  end;
end;

// DAK-388: the .dak roots below were hand-combined strings; they now go through Dak.Paths. For an absolute project
// path the result must stay byte-identical to the documented layout, which these tests spell out literally.
procedure TDakWorkingPathTests.DfmCheckRootKeepsTheLiteralLayoutForAnAbsoluteProject;
var
  lDproj: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('wp-dfm-root');
  lDproj := lRoot + '\' + cProjectName + '.dproj';
  Assert.AreEqual(lRoot + '\.dak\' + cProjectName + '\dfm-check', BuildExpectedDfmCheckPaths(lDproj).fDakRootDir);
end;

procedure TDakWorkingPathTests.RefactorTransactionRootKeepsTheLiteralLayoutForAnAbsoluteProject;
var
  lRoot: string;
begin
  lRoot := UniqueTempPath('wp-tx-root');
  Assert.AreEqual(lRoot + '\.dak\' + cProjectName + '\refactor-transactions',
    TransactionRoot(lRoot + '\' + cProjectName + '.dproj'));
end;

// A relative project path used to give a relative root. It now resolves to the root of the full project path,
// which is what RecoverRefactoringTransaction compares a journal against, so existing transactions stay reachable.
procedure TDakWorkingPathTests.RefactorTransactionRootIsAbsoluteForARelativeProject;
var
  lRelative: string;
  lRoot: string;
begin
  lRelative := 'wp-relative-sub\' + cProjectName + '.dproj';
  lRoot := TransactionRoot(lRelative);
  Assert.IsTrue(TPath.IsPathRooted(lRoot), lRoot);
  Assert.AreEqual(TransactionRoot(TPath.GetFullPath(lRelative)), lRoot);
  Assert.AreEqual(ExtractFilePath(ExpandFileName(lRelative)) + '.dak\' + cProjectName + '\refactor-transactions',
    lRoot);
end;

procedure TDakWorkingPathTests.SignatureRunDirectoryKeepsTheLiteralLayoutForAnAbsoluteProject;
var
  lDproj: string;
  lError: string;
  lRoot: string;
  lRunDir: string;
begin
  lRoot := UniqueTempPath('wp-sig-root');
  lDproj := lRoot + '\' + cProjectName + '.dproj';
  try
    Assert.IsTrue(TryCreateSignatureRunDirectory(lDproj, lRunDir, lError), lError);
    Assert.AreEqual(lRoot + '\.dak\' + cProjectName + '\signature', ExtractFileDir(lRunDir));
  finally
    DeleteTempPath(lRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDakWorkingPathTests);

end.
