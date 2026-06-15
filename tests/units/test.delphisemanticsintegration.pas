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
    [Test]
    procedure SharedSemanticApiOptionsMapsCommonProjectFields;
  end;

implementation

uses
  System.Generics.Collections,
  DelphiSemantics.Api, DelphiSemantics.Version,
  Dak.Semantics.Session, Dak.Types;

procedure TDelphiSemanticsIntegrationTests.DAKCanReferenceDelphiSemanticsApiFacade;
var
  lOptions: TDelphiSemanticApiOptions;
begin
  lOptions := Default(TDelphiSemanticApiOptions);
  Assert.AreEqual('0.1.1', DelphiSemanticsVersionText);
  Assert.AreEqual('', lOptions.Cache.SqliteCacheFileName);
end;

procedure TDelphiSemanticsIntegrationTests.SharedSemanticApiOptionsMapsCommonProjectFields;
var
  lEnvVars: TDictionary<string, string>;
  lOptions: TAppOptions;
  lSearchPaths: TArray<string>;
  lSemanticOptions: TDelphiSemanticApiOptions;
begin
  lEnvVars := TDictionary<string, string>.Create;
  try
    lEnvVars.Add('BDS', 'C:\Delphi');
    lOptions := Default(TAppOptions);
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win64';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fDprojPath := 'C:\Project\App.dproj';
    lOptions.fRsVarsPath := 'C:\rsvars.bat';
    lOptions.fEnvOptionsPath := 'C:\EnvOptions.proj';
    lSearchPaths := ['C:\Project\Source'];

    lSemanticOptions := BuildSemanticApiOptions(lOptions, lEnvVars,
      lSearchPaths);

    Assert.AreEqual('Debug', lSemanticOptions.Configuration);
    Assert.AreEqual('Win64', lSemanticOptions.Platform);
    Assert.AreEqual('23.0', lSemanticOptions.DelphiVersion);
    Assert.AreEqual('C:\Project\App.dproj', lSemanticOptions.ProjectFileName);
    Assert.AreEqual('C:\rsvars.bat', lSemanticOptions.RsVarsPath);
    Assert.AreEqual('C:\EnvOptions.proj', lSemanticOptions.EnvOptionsPath);
    Assert.AreEqual(1, Integer(Length(lSemanticOptions.EnvironmentVariables)));
    Assert.AreEqual('BDS', lSemanticOptions.EnvironmentVariables[0].Name);
    Assert.AreEqual('C:\Delphi', lSemanticOptions.EnvironmentVariables[0].Value);
    Assert.AreEqual(1, Integer(Length(lSemanticOptions.SearchPaths)));
    Assert.AreEqual('C:\Project\Source', lSemanticOptions.SearchPaths[0]);
    Assert.AreEqual('23.0', lSemanticOptions.Cache.DelphiVersion);
    Assert.AreEqual('Debug', lSemanticOptions.Cache.Configuration);
    Assert.AreEqual('Win64', lSemanticOptions.Cache.Platform);
  finally
    lEnvVars.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiSemanticsIntegrationTests);

end.
