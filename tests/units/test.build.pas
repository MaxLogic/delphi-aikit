unit Test.Build;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  Test.Support;

type
  [TestFixture]
  TBuildTests = class
  public
    [Test]
    procedure BuildResolverExe;
  end;

implementation

procedure TBuildTests.BuildResolverExe;
begin
  EnsureResolverBuilt;
  Assert.IsTrue(FileExists(ResolverExePath), 'Resolver exe not found: ' + ResolverExePath);
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildTests);

end.
