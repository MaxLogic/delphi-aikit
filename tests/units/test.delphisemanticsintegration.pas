unit Test.DelphiSemanticsIntegration;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDelphiSemanticsIntegrationTests = class
  public
    [Test]
    procedure DAKCanReferenceDelphiSemanticsVersionUnit;
  end;

implementation

uses
  DelphiSemantics.Version;

procedure TDelphiSemanticsIntegrationTests.DAKCanReferenceDelphiSemanticsVersionUnit;
begin
  Assert.AreEqual('0.1.0', DelphiSemanticsVersionText);
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiSemanticsIntegrationTests);

end.
