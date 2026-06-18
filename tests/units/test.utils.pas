unit Test.Utils;

interface

uses
  DUnitX.TestFramework,
  System.Classes, System.IOUtils, System.SysUtils,
  Winapi.Windows,
  Dak.Utils,
  Test.Support;

type
  [TestFixture]
  TUtilsTests = class
  public
    [Test]
    procedure NormalizeInputPathConvertsWslMount;
    [Test]
    procedure NormalizeInputPathRejectsUnsupportedLinuxAbsolutePath;
    [Test]
    procedure TempRootUsesProcessScopedRunDirectory;
    [Test]
    procedure RunnerFailsNoAssertTests;
    [Test]
    procedure ReadUtf8TextFileAllowsSharedWriterHandle;
    [Test]
    procedure ScopedEnvironmentVariableRestoresMissingAndPreviousValues;
    [Test]
    procedure ScopedEnvironmentVariablesRollbackAppliedValuesOnConstructorFailure;
    [Test]
    procedure ResolveDprojPathUsesSiblingDprojForDpr;
    [Test]
    procedure ResolveConfiguredExePathExpandsEnvAndAppendsExe;
  end;

implementation

function TestEnvironmentVariableExists(const aName: string): Boolean;
begin
  SetLastError(ERROR_SUCCESS);
  Winapi.Windows.GetEnvironmentVariable(PChar(aName), nil, 0);
  Result := GetLastError <> ERROR_ENVVAR_NOT_FOUND;
end;

procedure TUtilsTests.NormalizeInputPathConvertsWslMount;
var
  lError: string;
  lNormalizedPath: string;
begin
  Assert.IsTrue(TryNormalizeInputPath('/mnt/f/projects/MaxLogic/DelphiAiKit/tests/fixtures/Sample.dproj',
    lNormalizedPath, lError), 'Expected /mnt path to normalize. Error: ' + lError);
  Assert.AreEqual('F:\projects\MaxLogic\DelphiAiKit\tests\fixtures\Sample.dproj', lNormalizedPath,
    'Unexpected normalized Windows path.');
end;

procedure TUtilsTests.NormalizeInputPathRejectsUnsupportedLinuxAbsolutePath;
var
  lError: string;
  lNormalizedPath: string;
begin
  Assert.IsFalse(TryNormalizeInputPath('/home/pawel/Sample.dproj', lNormalizedPath, lError),
    'Expected unsupported Linux path to fail.');
  Assert.IsTrue(Pos('Unsupported Linux path format', lError) > 0, 'Unexpected error text: ' + lError);
end;

procedure TUtilsTests.TempRootUsesProcessScopedRunDirectory;
var
  lFixedRoot: string;
  lRoot: string;
begin
  lFixedRoot := TPath.GetFullPath(TPath.Combine(RepoRoot, 'tests\temp'));
  lRoot := TPath.GetFullPath(TempRoot);

  Assert.IsFalse(SameText(lRoot, lFixedRoot),
    'DAK tests must use a process-scoped temp root, not the shared repo tests\temp directory.');
  Assert.IsTrue(Pos(GetCurrentProcessId.ToString, lRoot) > 0,
    'DAK temp root should include the current process id. Actual: ' + lRoot);
end;

procedure TUtilsTests.RunnerFailsNoAssertTests;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'tests\DelphiAIKit.Tests.dpr'),
    TEncoding.UTF8);

  Assert.IsTrue(Pos('Runner.FailsOnNoAsserts := True', lSource) > 0,
    'DAK test runner must fail tests that execute without assertions.');
  Assert.IsFalse(Pos('Runner.FailsOnNoAsserts := False', lSource) > 0,
    'DAK test runner must not explicitly allow no-assert tests.');
end;

procedure TUtilsTests.ReadUtf8TextFileAllowsSharedWriterHandle;
var
  lPath: string;
  lWriter: TFileStream;
begin
  lPath := TPath.Combine(TempRoot, 'shared-writer-output.json');
  TFile.WriteAllText(lPath, '{"status":"ok"}', TEncoding.UTF8);
  lWriter := TFileStream.Create(lPath, fmOpenReadWrite or fmShareDenyNone);
  try
    Assert.AreEqual('{"status":"ok"}', ReadUtf8TextFile(lPath),
      'Output readers must tolerate inherited writer handles after child processes exit.');
  finally
    lWriter.Free;
  end;
end;

procedure TUtilsTests.ScopedEnvironmentVariableRestoresMissingAndPreviousValues;
const
  CVarName = 'DAK_TEST_SCOPED_ENV_GUARD';
var
  lGuard: IInterface;
begin
  SetEnvironmentVariable(PChar(CVarName), nil);
  lGuard := SetScopedEnvironmentVariable(CVarName, 'first-value');
  Assert.AreEqual('first-value', GetEnvironmentVariable(CVarName));
  lGuard := nil;
  Assert.AreEqual('', GetEnvironmentVariable(CVarName), 'Expected missing variable to be restored as missing.');
  Assert.IsFalse(TestEnvironmentVariableExists(CVarName), 'Expected missing variable to stay missing.');

  SetEnvironmentVariable(PChar(CVarName), PChar(''));
  try
    lGuard := SetScopedEnvironmentVariable(CVarName, 'empty-previous-value');
    Assert.AreEqual('empty-previous-value', GetEnvironmentVariable(CVarName));
    lGuard := nil;
    Assert.AreEqual('', GetEnvironmentVariable(CVarName), 'Expected empty previous value to be restored.');
    Assert.IsTrue(TestEnvironmentVariableExists(CVarName), 'Expected empty previous value to remain defined.');
  finally
    SetEnvironmentVariable(PChar(CVarName), nil);
  end;

  SetEnvironmentVariable(PChar(CVarName), PChar('previous-value'));
  try
    lGuard := SetScopedEnvironmentVariable(CVarName, 'second-value');
    Assert.AreEqual('second-value', GetEnvironmentVariable(CVarName));
    lGuard := nil;
    Assert.AreEqual('previous-value', GetEnvironmentVariable(CVarName),
      'Expected previous variable value to be restored.');
  finally
    SetEnvironmentVariable(PChar(CVarName), nil);
  end;
end;

procedure TUtilsTests.ScopedEnvironmentVariablesRollbackAppliedValuesOnConstructorFailure;
const
  CEmptyName = 'DAK_TEST_SCOPED_ENV_BATCH_EMPTY';
  CInvalidName = 'DAK_TEST_SCOPED_ENV_BATCH_INVALID=NAME';
  CMissingName = 'DAK_TEST_SCOPED_ENV_BATCH_MISSING';
  CPreviousName = 'DAK_TEST_SCOPED_ENV_BATCH_PREVIOUS';
var
  lGuard: IInterface;
  lRaised: Boolean;
begin
  SetEnvironmentVariable(PChar(CMissingName), nil);
  SetEnvironmentVariable(PChar(CEmptyName), PChar(''));
  SetEnvironmentVariable(PChar(CPreviousName), PChar('previous-value'));
  try
    lRaised := False;
    try
      lGuard := SetScopedEnvironmentVariables([
        CMissingName, 'new-missing-value',
        CEmptyName, 'new-empty-value',
        CPreviousName, 'new-previous-value',
        CInvalidName, 'failure-value']);
      lGuard := nil;
    except
      on E: EOSError do
        lRaised := True;
      on E: Exception do
        Assert.Fail('Expected EOSError for injected environment failure but got ' + E.ClassName + ': ' + E.Message);
    end;

    Assert.IsTrue(lRaised, 'Expected invalid environment variable name to force constructor failure.');
    Assert.AreEqual('', GetEnvironmentVariable(CMissingName), 'Expected missing value to be restored after rollback.');
    Assert.IsFalse(TestEnvironmentVariableExists(CMissingName),
      'Expected missing variable to stay missing after rollback.');
    Assert.AreEqual('', GetEnvironmentVariable(CEmptyName), 'Expected empty value to be restored after rollback.');
    Assert.IsTrue(TestEnvironmentVariableExists(CEmptyName),
      'Expected empty variable to stay defined after rollback.');
    Assert.AreEqual('previous-value', GetEnvironmentVariable(CPreviousName),
      'Expected previous value to be restored after rollback.');
  finally
    SetEnvironmentVariable(PChar(CMissingName), nil);
    SetEnvironmentVariable(PChar(CEmptyName), nil);
    SetEnvironmentVariable(PChar(CPreviousName), nil);
  end;
end;

procedure TUtilsTests.ResolveDprojPathUsesSiblingDprojForDpr;
var
  lError: string;
  lResolvedPath: string;
begin
  Assert.IsTrue(TryResolveDprojPath(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dpr'), lResolvedPath, lError),
    'Expected sibling .dproj resolution. Error: ' + lError);
  Assert.AreEqual(TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj'), lResolvedPath,
    'Unexpected resolved project path.');
end;

procedure TUtilsTests.ResolveConfiguredExePathExpandsEnvAndAppendsExe;
const
  CVarName = 'DAK_TEST_FIXINSIGHT_DIR';
var
  lExpectedPath: string;
  lGuard: IInterface;
  lResolvedPath: string;
  lTempDir: string;
begin
  lTempDir := TPath.Combine(TempRoot, 'env-tools');
  ForceDirectories(lTempDir);
  lGuard := SetScopedEnvironmentVariable(CVarName, lTempDir);
  lResolvedPath := ResolveExePathFromConfiguredValue('%' + CVarName + '%', 'FixInsightCL.exe');
  lExpectedPath := TPath.Combine(lTempDir, 'FixInsightCL.exe');
  Assert.AreEqual(lExpectedPath, lResolvedPath, 'Expected environment-backed tool path to resolve.');
  lGuard := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TUtilsTests);

end.
