unit Test.Utils;

interface

uses
  DUnitX.TestFramework,
  System.IOUtils, System.SysUtils,
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
    procedure ResolveDprojPathUsesSiblingDprojForDpr;
    [Test]
    procedure ResolveConfiguredExePathExpandsEnvAndAppendsExe;
  end;

implementation

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
  lResolvedPath: string;
  lTempDir: string;
begin
  lTempDir := TPath.Combine(TempRoot, 'env-tools');
  ForceDirectories(lTempDir);
  Assert.IsTrue(SetEnvironmentVariable(PChar(CVarName), PChar(lTempDir)),
    'Failed to set temporary environment variable.');
  try
    lResolvedPath := ResolveExePathFromConfiguredValue('%' + CVarName + '%', 'FixInsightCL.exe');
    lExpectedPath := TPath.Combine(lTempDir, 'FixInsightCL.exe');
    Assert.AreEqual(lExpectedPath, lResolvedPath, 'Expected environment-backed tool path to resolve.');
  finally
    SetEnvironmentVariable(PChar(CVarName), nil);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUtilsTests);

end.
