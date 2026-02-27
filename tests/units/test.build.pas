unit Test.Build;

interface

uses
  DUnitX.TestFramework,
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  Test.Support;

type
  [TestFixture]
  TBuildTests = class
  public
    [Test]
    procedure BuildResolverExe;
    [Test]
    procedure BuildResolverExeIgnoresLockedDefaultOutput;
  end;

implementation

procedure TBuildTests.BuildResolverExe;
begin
  EnsureResolverBuilt;
  Assert.IsTrue(FileExists(ResolverExePath), 'Resolver exe not found: ' + ResolverExePath);
end;

procedure TBuildTests.BuildResolverExeIgnoresLockedDefaultOutput;
var
  lBinExePath: string;
  lLockFile: TFileStream;
begin
  lBinExePath := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
  ResetResolverBuildCache;
  TDirectory.CreateDirectory(TPath.GetDirectoryName(lBinExePath));
  if not FileExists(lBinExePath) then
    TFile.WriteAllBytes(lBinExePath, [Byte($4D), Byte($5A)]);

  lLockFile := TFileStream.Create(lBinExePath, fmOpenReadWrite or fmShareDenyWrite);
  try
    EnsureResolverBuilt;
    Assert.IsTrue(FileExists(ResolverExePath), 'Expected resolver build to succeed even when default bin output is locked.');
    Assert.IsFalse(SameText(TPath.GetFullPath(ResolverExePath), TPath.GetFullPath(lBinExePath)),
      'Expected resolver build helper to use isolated output instead of bin\DelphiAIKit.exe.');
  finally
    lLockFile.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildTests);

end.
