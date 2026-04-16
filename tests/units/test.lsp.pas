unit Test.Lsp;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspContextTests = class
  private
    function ArrayContainsValue(const aValues: TArray<string>; const aExpected: string): Boolean;
    function CreateFixtureProject(const aScenarioName: string; const aProjectDefine: string;
      const aDefaultDelphiVersion: string = ''): string;
    procedure WriteEnvOptionsFile(const aPath, aLibraryPath, aSearchPath, aDefineValue: string);
    procedure WriteRsVarsFile(const aPath, aBdsRoot: string);
  public
    [Test]
    procedure LspUsesDakIniDelphiVersionFallback;
    [Test]
    procedure LspUsesRsvarsAndEnvOptionsOverrides;
    [Test]
    procedure LspHardFailsWhenRealDelphiContextCannotBeBuilt;
  end;

implementation

uses
  System.IOUtils, System.SysUtils,
  Dak.Lsp.Context, Dak.Types,
  Test.Support;

procedure WriteUtf8File(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.UTF8);
end;

procedure WriteAsciiFile(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.ASCII);
end;

function TLspContextTests.ArrayContainsValue(const aValues: TArray<string>; const aExpected: string): Boolean;
var
  lValue: string;
begin
  Result := False;
  for lValue in aValues do
  begin
    if SameText(lValue, aExpected) then
      Exit(True);
  end;
end;

function TLspContextTests.CreateFixtureProject(const aScenarioName: string; const aProjectDefine: string;
  const aDefaultDelphiVersion: string = ''): string;
var
  lDprojPath: string;
  lRoot: string;
begin
  EnsureTempClean;
  lRoot := TPath.Combine(TempRoot, aScenarioName);
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  lDprojPath := TPath.Combine(lRoot, 'LspFixture.dproj');
  WriteUtf8File(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>LspFixture.dpr</MainSource>' + sLineBreak +
    '    <DCC_Define>' + aProjectDefine + ';$(DCC_Define)</DCC_Define>' + sLineBreak +
    '    <DCC_UnitSearchPath>src;$(BDS)\Source;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <DCCReference Include="Unit1.pas"/>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(TPath.ChangeExtension(lDprojPath, '.dpr'),
    'program LspFixture;' + sLineBreak +
    sLineBreak +
    'uses' + sLineBreak +
    '  Unit1 in ''Unit1.pas'';' + sLineBreak +
    sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);
  WriteUtf8File(TPath.Combine(lRoot, 'Unit1.pas'),
    'unit Unit1;' + sLineBreak +
    sLineBreak +
    'interface' + sLineBreak +
    sLineBreak +
    'procedure TouchUnit1;' + sLineBreak +
    sLineBreak +
    'implementation' + sLineBreak +
    sLineBreak +
    'procedure TouchUnit1;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'end.' + sLineBreak);
  TDirectory.CreateDirectory(TPath.Combine(lRoot, 'src'));

  if aDefaultDelphiVersion <> '' then
  begin
    WriteAsciiFile(TPath.Combine(lRoot, 'dak.ini'),
      '[Build]' + sLineBreak +
      'DelphiVersion=' + aDefaultDelphiVersion + sLineBreak);
  end;

  Result := lDprojPath;
end;

procedure TLspContextTests.WriteEnvOptionsFile(const aPath, aLibraryPath, aSearchPath, aDefineValue: string);
begin
  WriteUtf8File(aPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <DelphiLibraryPath>' + aLibraryPath + '</DelphiLibraryPath>' + sLineBreak +
    '    <DCC_UnitSearchPath>' + aSearchPath + '</DCC_UnitSearchPath>' + sLineBreak +
    '    <DCC_Define>' + aDefineValue + '</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
end;

procedure TLspContextTests.WriteRsVarsFile(const aPath, aBdsRoot: string);
begin
  WriteAsciiFile(aPath,
    '@echo off' + sLineBreak +
    'set BDS=' + aBdsRoot + sLineBreak +
    'set BDSLIB=' + TPath.Combine(aBdsRoot, 'lib') + sLineBreak +
    'set DAK_TEST_RSVARS=1' + sLineBreak);
end;

procedure TLspContextTests.LspUsesDakIniDelphiVersionFallback;
var
  lBdsRoot: string;
  lContext: TLspContext;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lEnvSearchDir: string;
  lError: string;
  lLibraryDir: string;
  lOptions: TAppOptions;
  lRsVarsPath: string;
begin
  lDprojPath := CreateFixtureProject('lsp-dak-fallback', 'PROJECT_DEFINE', '99.9');
  lBdsRoot := TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds');
  lLibraryDir := TPath.Combine(ExtractFilePath(lDprojPath), 'IdeLibrary');
  lEnvSearchDir := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvSearch');
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'Source'));
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'lib'));
  TDirectory.CreateDirectory(lLibraryDir);
  TDirectory.CreateDirectory(lEnvSearchDir);
  lRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
  lEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj');
  WriteRsVarsFile(lRsVarsPath, lBdsRoot);
  WriteEnvOptionsFile(lEnvOptionsPath, lLibraryDir, lEnvSearchDir, 'ENV_DEFINE');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fPlatform := 'Win32';
  lOptions.fConfig := 'Debug';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;
  lOptions.fEnvOptionsPath := lEnvOptionsPath;
  lOptions.fHasEnvOptionsPath := True;

  lError := '';
  Assert.IsTrue(TryBuildStrictLspContext(lOptions, lContext, lError),
    'Expected strict lsp context to resolve using dak.ini DelphiVersion. Error: ' + lError);
  Assert.AreEqual('99.9', lContext.fDelphiVersion,
    'Expected DelphiVersion to fall back from project-local dak.ini.');
  Assert.IsTrue(ArrayContainsValue(lContext.fParams.fUnitSearchPath, TPath.Combine(lBdsRoot, 'Source')),
    'Expected BDS-derived search path from fake rsvars override.');
end;

procedure TLspContextTests.LspUsesRsvarsAndEnvOptionsOverrides;
var
  lBdsRoot: string;
  lContext: TLspContext;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lEnvSearchDir: string;
  lError: string;
  lLibraryDir: string;
  lOptions: TAppOptions;
  lRsVarsPath: string;
begin
  lDprojPath := CreateFixtureProject('lsp-explicit-overrides', 'PROJECT_OVERRIDE_DEFINE');
  lBdsRoot := TPath.Combine(ExtractFilePath(lDprojPath), 'OverrideBds');
  lLibraryDir := TPath.Combine(ExtractFilePath(lDprojPath), 'OverrideLibrary');
  lEnvSearchDir := TPath.Combine(ExtractFilePath(lDprojPath), 'OverrideEnvSearch');
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'Source'));
  TDirectory.CreateDirectory(TPath.Combine(lBdsRoot, 'lib'));
  TDirectory.CreateDirectory(lLibraryDir);
  TDirectory.CreateDirectory(lEnvSearchDir);
  lRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'override-rsvars.bat');
  lEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'OverrideEnvOptions.proj');
  WriteRsVarsFile(lRsVarsPath, lBdsRoot);
  WriteEnvOptionsFile(lEnvOptionsPath, lLibraryDir, lEnvSearchDir, 'ENV_OVERRIDE_DEFINE');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fPlatform := 'Win32';
  lOptions.fConfig := 'Release';
  lOptions.fDelphiVersion := '99.9';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;
  lOptions.fEnvOptionsPath := lEnvOptionsPath;
  lOptions.fHasEnvOptionsPath := True;

  lError := '';
  Assert.IsTrue(TryBuildStrictLspContext(lOptions, lContext, lError),
    'Expected strict lsp context to resolve using explicit overrides. Error: ' + lError);
  Assert.IsTrue(SameText(lLibraryDir, lContext.fLibraryPath),
    'Expected explicit EnvOptions override library path to be used.');
  Assert.IsTrue(ArrayContainsValue(lContext.fParams.fUnitSearchPath, lEnvSearchDir),
    'Expected explicit EnvOptions override search path to be part of the effective search path.');
  Assert.IsTrue(ArrayContainsValue(lContext.fParams.fUnitSearchPath, TPath.Combine(lBdsRoot, 'Source')),
    'Expected explicit rsvars override BDS root to contribute to the effective search path.');
  Assert.IsTrue(ArrayContainsValue(lContext.fParams.fDefines, 'ENV_OVERRIDE_DEFINE'),
    'Expected explicit EnvOptions override defines to flow into the evaluated project params.');
end;

procedure TLspContextTests.LspHardFailsWhenRealDelphiContextCannotBeBuilt;
var
  lContext: TLspContext;
  lDprojPath: string;
  lError: string;
  lOptions: TAppOptions;
  lRsVarsPath: string;
begin
  lDprojPath := CreateFixtureProject('lsp-hard-fail', 'PROJECT_DEFINE');
  lRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'missing', 'rsvars.bat');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fPlatform := 'Win32';
  lOptions.fConfig := 'Release';
  lOptions.fDelphiVersion := '99.9';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;

  lError := '';
  Assert.IsFalse(TryBuildStrictLspContext(lOptions, lContext, lError),
    'Expected strict lsp context to fail when the Delphi toolchain cannot be resolved.');
  Assert.IsTrue(Pos('rsvars.bat not found', lError) > 0,
    'Expected missing rsvars prerequisite in the error. Actual: ' + lError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspContextTests);

end.
