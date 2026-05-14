unit Test.DelphiSemanticsIntegration;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDelphiSemanticsIntegrationTests = class
  public
    [Test]
    procedure DAKCanReferenceDelphiSemanticsApiFacade;
  end;

implementation

uses
  DelphiSemantics.Api, DelphiSemantics.Version;

procedure TDelphiSemanticsIntegrationTests.DAKCanReferenceDelphiSemanticsApiFacade;
var
  lOptions: TDelphiSemanticApiOptions;
begin
  lOptions := Default(TDelphiSemanticApiOptions);
  Assert.AreEqual('0.1.0', DelphiSemanticsVersionText);
  Assert.AreEqual('', lOptions.Cache.SqliteCacheFileName);
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiSemanticsIntegrationTests);

end.
