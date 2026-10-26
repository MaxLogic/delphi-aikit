unit Test.Lsp;

interface

uses
  System.JSON,
  DUnitX.TestFramework,
  Dak.Lsp.Context, Dak.Types;

type
  [TestFixture]
  [Category('Slow')]
  TLspContextTests = class
  protected
    function ArrayContainsValue(const aValues: TArray<string>; const aExpected: string): Boolean;
    function CreateFixtureProject(const aScenarioName: string; const aProjectDefine: string;
      const aDefaultDelphiVersion: string = ''): string;
    function PrepareResolvedContext(const aScenarioName: string; out aContext: TLspContext): string;
    procedure WriteEnvOptionsFile(const aPath, aLibraryPath, aSearchPath, aDefineValue: string);
    procedure WriteRsVarsFile(const aPath, aBdsRoot: string);
  public
    [Test]
    procedure LspUsesDakIniDelphiVersionFallback;
    [Test]
    procedure LspDiscoveryPrefersExplicitPathThenResolvedInstall;
    [Test]
    procedure LspUsesRsvarsAndEnvOptionsOverrides;
    [Test]
    procedure LspHardFailsWhenRealDelphiContextCannotBeBuilt;
    [Test]
    procedure LspWritesGeneratedContextUnderDakWorkspace;
    [Test]
    procedure LspDoesNotWriteContextBesideSourceProject;
    [Test]
    procedure LspReportsWorkspaceWriteFailureCleanly;
    [Test]
    procedure LspWritesProbeSettingsFileWithFileUris;
    [Test]
    [TestCase('Win32', '0')]
    [TestCase('Win64', '1')]
    procedure LspCompilerDllResolvesExactPlatformDll(aVariant: Integer);
    [Test]
    procedure LspLegacySettingsWritersOmitDllName;
  end;

  // Runner orchestration tests that need no LSP server: pure wire builders, owned
  // file preparation, and failures surfaced through TryRunLspRequest by native
  // test child modes that never implement the protocol.
  [TestFixture]
  [Category('Slow')]
  TLspRunnerTests = class
  private
    function PrepareContext(const aScenarioName: string; out aContext: TLspContext): string;
  public
    [Test]
    procedure LspRequestPreparationReplacesStaleContextFile;
    [Test]
    procedure LspRequestWireSequenceUsesCanonicalSettings;
    [Test]
    [TestCase('Missing executable', '0')]
    [TestCase('Invalid executable', '1')]
    [TestCase('Missing compiler DLL still starts the server', '2')]
    procedure LspRunnerReportsExecutableFailures(aVariant: Integer);
    [Test]
    [TestCase('Text file', '0')]
    [TestCase('DOS stub without a PE header', '1')]
    procedure LspRunnerNamesInvalidExecutableBeforeLaunch(aVariant: Integer);
    [Test]
    [TestCase('Initialize error response', '0')]
    [TestCase('Probe initialize error response', '1')]
    [TestCase('Unresponsive initialize', '2')]
    procedure LspRunnerReportsStageForServerFailures(aVariant: Integer);
    [Test]
    [TestCase('Resolved', '0')]
    [TestCase('Unsupported platform', '1')]
    [TestCase('Missing DLL', '2')]
    [TestCase('Ambiguous DLL', '3')]
    procedure LspCompilerDllWarningNamesReasonWithoutRefusing(aVariant: Integer);
  end;

  [TestFixture]
  [Category('Slow')]
  TLspArchitectureTests = class
  public
    [Test]
    procedure LspTransportImplementationLivesOutsideRunner;
  end;

  [TestFixture]
  [Category('Slow')]
  TRealLspAcceptanceTests = class
  private
    function FixtureDprojPath: string;
    function FixtureUnit1Path: string;
    function RunLspCommand(const aScenarioName, aArgs: string; out aJson: TJSONObject): Cardinal;
  public
    [Test]
    procedure RealDelphi23DefinitionMatchesFixtureGoldenAnswer;
    [Test]
    procedure RealDelphi23SymbolsMatchFixtureGoldenAnswer;
    [Test]
    procedure RealDelphi23ProbePreservesBothHandshakeModes;
    [Test]
    procedure RealDelphi23HoverMatchesFixtureGoldenAnswer;
    [Test]
    procedure RealDelphi23UnsupportedPlatformWarnsAndStillAnswers;
  end;

implementation

uses
  System.Classes, System.Diagnostics, System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  Winapi.TlHelp32, Winapi.Windows,
  DelphiSemantics.Lsp,
  Dak.Lsp.Protocol, Dak.Lsp.Runner,
  Test.Support;

var
  GRealLspAcceptanceLock: TObject;

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

function FilePathToUri(const aPath: string): string;
begin
  Result := TDelphiSemanticLspBoundary.FilePathToUri(aPath);
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

function TLspContextTests.PrepareResolvedContext(const aScenarioName: string; out aContext: TLspContext): string;
var
  lBdsRoot: string;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lEnvSearchDir: string;
  lError: string;
  lLibraryDir: string;
  lOptions: TAppOptions;
  lRsVarsPath: string;
begin
  lDprojPath := CreateFixtureProject(aScenarioName, 'PROJECT_DEFINE', '99.9');
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
  Assert.IsTrue(TryBuildStrictLspContext(lOptions, aContext, lError),
    'Expected strict lsp context to resolve. Error: ' + lError);
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

procedure TLspContextTests.LspWritesGeneratedContextUnderDakWorkspace;
var
  lContext: TLspContext;
  lDprojPath: string;
  lError: string;
  lText: string;
  lWorkspaceRoot: string;
begin
  lDprojPath := PrepareResolvedContext('lsp-dak-workspace', lContext);
  lWorkspaceRoot := TPath.Combine(TPath.Combine(ExtractFilePath(lDprojPath), '.dak'), 'LspFixture');

  Assert.AreEqual<string>(TPath.Combine(TPath.Combine(lWorkspaceRoot, 'lsp'), 'context.delphilsp.json'),
    lContext.fContextFilePath, 'Expected generated LSP context file to live under the sibling .dak workspace.');
  Assert.IsFalse(FileExists(lContext.fContextFilePath),
    'Did not expect normal LSP context preparation to write the compatibility context file.');
  lError := '';
  Assert.IsTrue(TryWriteLspContextFile(lContext, lError),
    'Expected explicit compatibility context file writer to succeed. Error: ' + lError);
  Assert.IsTrue(FileExists(lContext.fContextFilePath),
    'Expected explicit compatibility context file writer to create the file.');
  Assert.AreEqual<string>(TPath.Combine(TPath.Combine(lWorkspaceRoot, 'lsp'), 'logs'), lContext.fLogsDir,
    'Expected logs directory to stay under the same owned workspace.');
  Assert.IsTrue(TDirectory.Exists(lContext.fLogsDir),
    'Expected logs directory to be created under the owned workspace.');

  lText := TFile.ReadAllText(lContext.fContextFilePath, TEncoding.UTF8);
  Assert.IsTrue(Pos('context.delphilsp.json', lText) > 0,
    'Expected generated context metadata to mention the owned context file path.');
  Assert.IsTrue(Pos('"project"', lText) > 0,
    'Expected generated context metadata to include the project block.');
end;

procedure TLspContextTests.LspDoesNotWriteContextBesideSourceProject;
var
  lContext: TLspContext;
  lDprojPath: string;
  lSidecarPath: string;
begin
  lDprojPath := PrepareResolvedContext('lsp-no-sidecar', lContext);
  lSidecarPath := TPath.Combine(ExtractFilePath(lDprojPath), 'context.delphilsp.json');

  Assert.IsFalse(FileExists(lSidecarPath),
    'Did not expect an LSP context sidecar beside the source project.');
  Assert.IsFalse(FileExists(lContext.fContextFilePath),
    'Did not expect normal context preparation to write the compatibility context file.');
end;

procedure TLspContextTests.LspReportsWorkspaceWriteFailureCleanly;
var
  lContext: TLspContext;
  lDakFilePath: string;
  lDprojPath: string;
  lError: string;
  lOptions: TAppOptions;
begin
  lDprojPath := CreateFixtureProject('lsp-workspace-write-failure', 'PROJECT_DEFINE', '99.9');
  lDakFilePath := TPath.Combine(TPath.Combine(TPath.Combine(ExtractFilePath(lDprojPath), '.dak'), 'LspFixture'), 'lsp');
  TDirectory.CreateDirectory(ExtractFilePath(lDakFilePath));
  WriteAsciiFile(lDakFilePath, 'blocked');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fPlatform := 'Win32';
  lOptions.fConfig := 'Debug';
  lOptions.fDelphiVersion := '99.9';
  lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'missing', 'rsvars.bat');
  lOptions.fHasRsVarsPath := True;

  WriteRsVarsFile(TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat'), TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds'));
  TDirectory.CreateDirectory(TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds', 'Source'));
  TDirectory.CreateDirectory(TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds', 'lib'));
  WriteEnvOptionsFile(TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj'),
    TPath.Combine(ExtractFilePath(lDprojPath), 'IdeLibrary'), TPath.Combine(ExtractFilePath(lDprojPath), 'EnvSearch'),
    'ENV_DEFINE');
  lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
  lOptions.fEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj');
  lOptions.fHasEnvOptionsPath := True;

  lError := '';
  Assert.IsFalse(TryBuildStrictLspContext(lOptions, lContext, lError),
    'Expected strict lsp context to fail cleanly when the owned workspace path is blocked.');
  Assert.IsTrue(Pos('Failed to write lsp context artifacts', lError) > 0,
    'Expected a clean workspace-write error. Actual: ' + lError);
end;

function CreateFakeLspBinDir(const aScenarioName: string; const aFileNames: array of string): string;
var
  lFileName: string;
begin
  Result := UniqueTempPath(aScenarioName);
  ForceDirectories(Result);
  WriteUtf8File(TPath.Combine(Result, 'DelphiLSP.exe'), 'lsp');
  for lFileName in aFileNames do
    WriteUtf8File(TPath.Combine(Result, lFileName), 'dll');
end;

procedure TLspContextTests.LspCompilerDllResolvesExactPlatformDll(aVariant: Integer);
var
  lBinDir, lDllName, lExpected, lPlatform: string;
begin
  // Mirrors the installed 23.0 bin64 layout, including the dcc64290N.dll
  // variant that must not match.
  lBinDir := CreateFakeLspBinDir('lsp-compiler-dll-' + IntToStr(aVariant),
    ['dcc32290.dll', 'dcc64290.dll', 'dcc64290N.dll', 'dcclinux64290.dll']);
  lPlatform := 'Win32';
  lExpected := 'dcc32290.dll';
  if aVariant = 1 then
  begin
    lPlatform := 'win64';
    lExpected := 'dcc64290.dll';
  end;
  Assert.AreEqual('', ResolveLspCompilerDllForRequest(TPath.Combine(lBinDir, 'DelphiLSP.exe'), lPlatform,
    lDllName));
  Assert.AreEqual(lExpected, lDllName);
end;

procedure TLspContextTests.LspLegacySettingsWritersOmitDllName;
var
  lContext: TLspContext;
  lError, lSettingsFilePath: string;
  lJson: TJSONObject;
begin
  // The public writers keep their original signatures and output.
  PrepareResolvedContext('lsp legacy settings writers', lContext);
  Assert.IsTrue(TryWriteCanonicalLspSettingsFile(lContext, lSettingsFilePath, lError), lError);
  lJson := ParseJsonObject(ReadUtf8TextFile(lSettingsFilePath), lSettingsFilePath);
  try
    Assert.IsNull(lJson.GetValue<TJSONObject>('settings').Values['dllname'], lJson.ToJSON);
  finally
    lJson.Free;
  end;
  Assert.IsTrue(TryWriteOfficialLspSettingsFile(lContext, lSettingsFilePath, lError), lError);
  lJson := ParseJsonObject(ReadUtf8TextFile(lSettingsFilePath), lSettingsFilePath);
  try
    Assert.IsNull(lJson.GetValue<TJSONObject>('settings').Values['dllname'], lJson.ToJSON);
  finally
    lJson.Free;
  end;
end;

procedure TLspContextTests.LspWritesProbeSettingsFileWithFileUris;
var
  lBrowsingPaths: TJSONArray;
  lContext: TLspContext;
  lError: string;
  lFoundUnitSearchPath: Boolean;
  lJson: TJSONObject;
  lPath: string;
  lProjectJson: string;
  lSettingsFilePath: string;
  lSettingsJson: TJSONObject;
begin
  PrepareResolvedContext('lsp probe settings json', lContext);

  lError := '';
  Assert.IsTrue(TryWriteOfficialLspSettingsFile(lContext, 'dcc32290.dll', lSettingsFilePath, lError),
    'Expected official probe settings file to be written. Error: ' + lError);
  Assert.AreEqual<string>(TPath.Combine(lContext.fDakLspRoot, 'probe.delphilsp.json'), lSettingsFilePath,
    'Expected probe settings file to live under the owned .dak workspace.');
  Assert.IsTrue(FileExists(lSettingsFilePath), 'Expected probe settings file to exist.');

  lJson := ParseJsonObject(ReadUtf8TextFile(lSettingsFilePath), lSettingsFilePath);
  try
    Assert.IsNotNull(lJson, 'Expected probe settings file to contain valid JSON.');
    lSettingsJson := lJson.GetValue<TJSONObject>('settings');
    Assert.IsNotNull(lSettingsJson, 'Expected settings block in probe settings file.');

    lProjectJson := lSettingsJson.GetValue<string>('project', '');
    Assert.AreEqual<string>(FilePathToUri(lContext.fMainSourcePath), lProjectJson,
      'Expected project path to be written as the exact main-source file URI.');
    Assert.AreEqual<string>('dcc32290.dll', lSettingsJson.GetValue<string>('dllname', ''),
      'Expected the probe settings to name the resolved compiler DLL.');

    lBrowsingPaths := lSettingsJson.GetValue<TJSONArray>('browsingPaths');
    Assert.IsNotNull(lBrowsingPaths, 'Expected browsingPaths in probe settings file.');
    Assert.IsTrue(lBrowsingPaths.Count > 0, 'Expected at least one browsing path in probe settings file.');
    Assert.IsTrue(lBrowsingPaths.Count >= Length(lContext.fParams.fUnitSearchPath),
      'Expected probe browsing paths to include the unit search path entries.');
    lFoundUnitSearchPath := False;
    for var i := 0 to lBrowsingPaths.Count - 1 do
    begin
      lPath := lBrowsingPaths.Items[i].Value;
      Assert.IsTrue(lPath.StartsWith('file:///'),
        'Expected browsing path to be expressed as a file URI. Actual: ' + lPath);
      Assert.IsTrue(Pos('\\', lPath) = 0,
        'Expected browsing path URI to use forward slashes only. Actual: ' + lPath);
      if SameText(lPath, FilePathToUri(lContext.fParams.fUnitSearchPath[0])) then
        lFoundUnitSearchPath := True;
    end;
    Assert.IsTrue(lFoundUnitSearchPath,
      'Expected probe browsing paths to include the first unit search path as a file URI.');
  finally
    lJson.Free;
  end;
end;


function BuildRunnerOptions(const aDprojPath: string): TAppOptions;
begin
  Result := Default(TAppOptions);
  Result.fDprojPath := aDprojPath;
  Result.fPlatform := 'Win32';
  Result.fConfig := 'Debug';
  Result.fLspOperation := TLspOperation.loDefinition;
  Result.fLspFormat := TLspFormat.lfJson;
  Result.fLspFilePath := TPath.Combine(ExtractFilePath(aDprojPath), 'Unit1.pas');
  Result.fLspLine := 1;
  Result.fLspCol := 1;
end;

procedure AddContextEnvironmentVar(var aContext: TLspContext; const aName, aValue: string);
var
  lBlock: string;
begin
  // The runner starts the server with the context's environment block.
  lBlock := aContext.fEnvironmentBlock;
  if lBlock = '' then
    lBlock := #0;
  aContext.fEnvironmentBlock := Copy(lBlock, 1, Length(lBlock) - 1) + aName + '=' + aValue + #0#0;
  aContext.fParams.fEnvironmentBlock := aContext.fEnvironmentBlock;
end;

function TLspRunnerTests.PrepareContext(const aScenarioName: string; out aContext: TLspContext): string;
var
  lHelper: TLspContextTests;
begin
  lHelper := TLspContextTests.Create;
  try
    Result := lHelper.PrepareResolvedContext(aScenarioName, aContext);
  finally
    lHelper.Free;
  end;
end;

procedure TLspRunnerTests.LspRequestPreparationReplacesStaleContextFile;
var
  lContext: TLspContext;
  lError: string;
  lJson: TJSONObject;
  lSettingsFilePath: string;
begin
  PrepareContext('lsp-runner-prepare', lContext);
  Assert.IsTrue(TryWriteLspContextFile(lContext, lError), lError);
  Assert.IsTrue(FileExists(lContext.fContextFilePath), 'Stale context file must exist before preparation');

  Assert.IsTrue(TryPrepareLspRequestFiles(lContext, 'dcc64290.dll', lSettingsFilePath, lError), lError);
  Assert.IsFalse(FileExists(lContext.fContextFilePath), 'Normal requests must delete the stale context file');
  Assert.AreEqual<string>(TPath.Combine(lContext.fDakLspRoot, 'settings.delphilsp.json'), lSettingsFilePath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lSettingsFilePath), lSettingsFilePath);
  try
    Assert.AreEqual<string>(FilePathToUri(lContext.fMainSourcePath),
      lJson.GetValue<TJSONObject>('settings').GetValue<string>('project'));
    Assert.AreEqual<string>('dcc64290.dll', lJson.GetValue<TJSONObject>('settings').GetValue<string>('dllname'));
  finally
    lJson.Free;
  end;
end;

procedure TLspRunnerTests.LspRequestWireSequenceUsesCanonicalSettings;
var
  lContext: TLspContext;
  lDprojPath, lError, lRequestFilePath, lSettingsFilePath: string;
  lMessages: TArray<TLspWireMessage>;
  lOptions, lParams, lSettings, lTextDocument: TJSONObject;
begin
  lDprojPath := PrepareContext('lsp-runner-wire', lContext);
  lRequestFilePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Unit1.pas');
  Assert.IsTrue(TryPrepareLspRequestFiles(lContext, 'dcc32290.dll', lSettingsFilePath, lError), lError);

  lParams := ParseJsonObject(BuildRequestInitializeParams(lContext, lSettingsFilePath), 'initialize');
  try
    Assert.AreEqual<string>(FilePathToUri(lContext.fProjectDir), lParams.GetValue<string>('rootUri'));
    lOptions := lParams.GetValue<TJSONObject>('initializationOptions');
    Assert.AreEqual<string>(lSettingsFilePath, lOptions.GetValue<string>('settingsFile'));
    Assert.AreEqual<string>(FilePathToUri(lSettingsFilePath), lOptions.GetValue<string>('settingsFileUri'));
    Assert.IsNull(lOptions.Values['contextFile'], 'Normal requests must not send the compatibility context file');
  finally
    lParams.Free;
  end;

  // The runner sends exactly this sequence after a successful initialize.
  lMessages := BuildRequestNotifications(lSettingsFilePath, lRequestFilePath);
  Assert.AreEqual(3, Integer(Length(lMessages)));
  Assert.AreEqual('initialized', lMessages[0].fMethod);
  Assert.AreEqual('{}', lMessages[0].fParams);
  Assert.AreEqual('workspace/didChangeConfiguration', lMessages[1].fMethod);
  lParams := ParseJsonObject(lMessages[1].fParams, 'didChangeConfiguration');
  try
    lSettings := lParams.GetValue<TJSONObject>('settings');
    Assert.AreEqual<string>(lSettingsFilePath, lSettings.GetValue<string>('settingsFile'));
    Assert.AreEqual<string>(FilePathToUri(lSettingsFilePath), lSettings.GetValue<string>('settingsFileUri'));
  finally
    lParams.Free;
  end;
  Assert.AreEqual('textDocument/didOpen', lMessages[2].fMethod);
  lParams := ParseJsonObject(lMessages[2].fParams, 'didOpen');
  try
    lTextDocument := lParams.GetValue<TJSONObject>('textDocument');
    Assert.AreEqual<string>(FilePathToUri(lRequestFilePath), lTextDocument.GetValue<string>('uri'));
    Assert.AreEqual('delphi', lTextDocument.GetValue<string>('languageId'));
    Assert.AreEqual<string>(TFile.ReadAllText(lRequestFilePath), lTextDocument.GetValue<string>('text'));
  finally
    lParams.Free;
  end;
end;

procedure TLspRunnerTests.LspRunnerReportsExecutableFailures(aVariant: Integer);
var
  lContext: TLspContext;
  lDprojPath, lError, lExePath: string;
  lOptions: TAppOptions;
  lResult: TLspRunnerResult;
begin
  lDprojPath := PrepareContext('lsp-runner-exe-' + IntToStr(aVariant), lContext);
  lExePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Tools\DelphiLSP.exe');
  if aVariant >= 1 then
    WriteAsciiFile(lExePath, 'not a Windows executable');
  // Variant 2 omits the compiler DLL: an unresolved DLL is only a warning, so
  // the runner still tries to start the server and reaches the start failure.
  if aVariant = 1 then
    WriteAsciiFile(TPath.Combine(ExtractFilePath(lExePath), 'dcc32290.dll'), 'dll');
  lOptions := BuildRunnerOptions(lDprojPath);
  lOptions.fLspPath := lExePath;
  lOptions.fHasLspPath := True;
  Assert.IsFalse(TryRunLspRequest(lOptions, lContext, lResult, lError));
  if aVariant = 0 then
    Assert.IsTrue(lError.StartsWith('DelphiLSP.exe not found at: ' + lExePath), lError)
  else
    Assert.IsTrue(lError.StartsWith('Failed to start DelphiLSP.exe:'), lError);
end;

// DAK-394: CreateProcess on a file without a PE image may show a modal "Unsupported 16-bit application"
// dialog. The transport reads the image signatures first, so the start fails at once with a named reason.
procedure TLspRunnerTests.LspRunnerNamesInvalidExecutableBeforeLaunch(aVariant: Integer);
var
  lBytes: TBytes;
  lContext: TLspContext;
  lDprojPath, lError, lExePath: string;
  lOptions: TAppOptions;
  lResult: TLspRunnerResult;
begin
  lDprojPath := PrepareContext('lsp-runner-invalid-image-' + IntToStr(aVariant), lContext);
  lExePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Tools\DelphiLSP.exe');
  if aVariant = 0 then
    WriteAsciiFile(lExePath, 'not a Windows executable')
  else begin
    // A DOS header whose e_lfanew points at bytes that are not "PE\0\0"; SetLength zero-fills the array.
    SetLength(lBytes, 256);
    lBytes[0] := Ord('M');
    lBytes[1] := Ord('Z');
    lBytes[$3C] := $80;
    ForceDirectories(ExtractFileDir(lExePath));
    TFile.WriteAllBytes(lExePath, lBytes);
  end;
  WriteAsciiFile(TPath.Combine(ExtractFilePath(lExePath), 'dcc32290.dll'), 'dll');
  lOptions := BuildRunnerOptions(lDprojPath);
  lOptions.fLspPath := lExePath;
  lOptions.fHasLspPath := True;
  Assert.IsFalse(TryRunLspRequest(lOptions, lContext, lResult, lError));
  Assert.AreEqual('Failed to start DelphiLSP.exe: ' + lExePath + ' is not a valid Windows executable', lError);
end;

procedure TLspRunnerTests.LspCompilerDllWarningNamesReasonWithoutRefusing(aVariant: Integer);
var
  lBinDir, lDllName, lExpectedReason, lPlatform, lWarning: string;
begin
  lPlatform := 'Win64';
  lExpectedReason := '';
  case aVariant of
    0:
      lBinDir := CreateFakeLspBinDir('lsp-dll-warning-resolved', ['dcc64290.dll', 'dcc64290N.dll']);
    1:
      begin
        lBinDir := CreateFakeLspBinDir('lsp-dll-warning-unsupported', ['dcc64290.dll']);
        lPlatform := 'Linux64';
        lExpectedReason := 'platform Linux64 is not supported';
      end;
    2:
      begin
        lBinDir := CreateFakeLspBinDir('lsp-dll-warning-missing', ['dcc32290.dll', 'dcc64290N.dll']);
        lExpectedReason := 'no dcc64NNN.dll';
      end;
  else
    lBinDir := CreateFakeLspBinDir('lsp-dll-warning-ambiguous', ['dcc64290.dll', 'dcc64370.dll']);
    lExpectedReason := 'more than one dcc64NNN.dll';
  end;
  lWarning := ResolveLspCompilerDllForRequest(TPath.Combine(lBinDir, 'DelphiLSP.exe'), lPlatform, lDllName);
  if aVariant = 0 then
  begin
    Assert.AreEqual('dcc64290.dll', lDllName);
    Assert.AreEqual('', lWarning);
  end else begin
    // Never guess: an unresolved or ambiguous DLL is omitted from the settings.
    Assert.AreEqual('', lDllName);
    Assert.IsTrue(lWarning.StartsWith('DelphiLSP compiler DLL not resolved ('), lWarning);
    Assert.IsTrue(ContainsText(lWarning, lExpectedReason), lWarning);
    Assert.IsTrue(ContainsText(lWarning, 'hover may return no content'), lWarning);
  end;
end;

procedure TLspRunnerTests.LspRunnerReportsStageForServerFailures(aVariant: Integer);
const
  cInitError = '{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"simulated init failure"}}';
var
  lContext: TLspContext;
  lDprojPath, lError, lFramePath, lLspBinDir, lName, lTimeoutMs, lValue: string;
  lGuard: IInterface;
  lOptions: TAppOptions;
  lResult: TLspRunnerResult;
  lTimer: TStopwatch;
begin
  lDprojPath := PrepareContext('lsp-runner-stage-' + IntToStr(aVariant), lContext);
  lOptions := BuildRunnerOptions(lDprojPath);
  // A copy of the test executable stands in only as a process: its child modes
  // either replay one fixed error frame or stay silent; neither reads a request.
  // The placeholder compiler DLL satisfies the pre-start DLL resolution.
  lLspBinDir := UniqueTempPath('lsp-runner-stage-bin-' + IntToStr(aVariant));
  ForceDirectories(lLspBinDir);
  lOptions.fLspPath := TPath.Combine(lLspBinDir, 'DelphiLSP.exe');
  TFile.Copy(ParamStr(0), lOptions.fLspPath);
  WriteAsciiFile(TPath.Combine(lLspBinDir, 'dcc32290.dll'), 'dll');
  lOptions.fHasLspPath := True;
  if aVariant = 1 then
  begin
    lOptions.fLspOperation := TLspOperation.loProbe;
    lOptions.fLspProbeModes := [TLspProbeMode.lpmContextFile];
  end;
  if aVariant < 2 then
  begin
    lFramePath := UniqueTempPath('lsp-runner-frame') + '.bin';
    TFile.WriteAllText(lFramePath, 'Content-Length: ' + IntToStr(Length(cInitError)) + #13#10#13#10 + cInitError,
      TEncoding.ASCII);
    lName := 'DAK_TEST_STDOUT_FRAME';
    lValue := lFramePath;
  end else begin
    lName := 'DAK_TEST_IDLE_CHILD';
    lValue := '1';
  end;
  // Variants 0 and 1 assert the server-error stage, not timing: the child test exe must finish initialization and
  // replay its frame inside the request timeout, which 250 ms does not cover on a busy machine. They return as
  // soon as the frame arrives, so 10 s costs nothing when it is met. Variant 2 tests the timeout and keeps 250 ms.
  if aVariant < 2 then
    lTimeoutMs := '10000'
  else
    lTimeoutMs := '250';
  lGuard := SetScopedEnvironmentVariables([lName, lValue, 'DAK_LSP_REQUEST_TIMEOUT_MS', lTimeoutMs]);
  Assert.IsNotNull(lGuard);
  AddContextEnvironmentVar(lContext, lName, lValue);

  lTimer := TStopwatch.StartNew;
  Assert.IsFalse(TryRunLspRequest(lOptions, lContext, lResult, lError));
  Assert.IsTrue(lTimer.ElapsedMilliseconds < 5000, Format('Runner failure took %d ms', [lTimer.ElapsedMilliseconds]));
  case aVariant of
    0:
      begin
        Assert.IsTrue(lError.StartsWith('DelphiLSP initialize failed'), lError);
        Assert.IsTrue(lError.Contains('-32001') and lError.Contains('simulated init failure'), lError);
      end;
    1:
      begin
        Assert.IsTrue(lError.StartsWith('DelphiLSP probe initialize contextFile failed'), lError);
        Assert.IsTrue(lError.Contains('-32001') and lError.Contains('simulated init failure'), lError);
      end;
  else
    Assert.IsTrue(lError.StartsWith('DelphiLSP initialize failed'), lError);
    Assert.IsTrue(lError.Contains('timed out'), lError);
  end;
end;

procedure TLspArchitectureTests.LspTransportImplementationLivesOutsideRunner;
var
  lRunnerSource: string;
  lTransportPath: string;
  lTransportSource: string;
begin
  lRunnerSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.lsp.runner.pas'), TEncoding.UTF8);
  lTransportPath := TPath.Combine(RepoRoot, 'src\Dak.Lsp.Transport.pas');
  Assert.IsTrue(FileExists(lTransportPath), 'Expected focused LSP transport unit to exist: ' + lTransportPath);
  lTransportSource := TFile.ReadAllText(lTransportPath, TEncoding.UTF8);

  Assert.IsFalse(ContainsText(lRunnerSource, 'TLspJsonRpcClient = class'),
    'LSP JSON-RPC transport class should live outside dak.lsp.runner.pas.');
  Assert.IsFalse(ContainsText(lRunnerSource, 'CreatePipe(') or ContainsText(lRunnerSource, 'CreateProcess(') or
    ContainsText(lRunnerSource, 'ReadMessage(') or ContainsText(lRunnerSource, 'WriteMessage('),
    'dak.lsp.runner.pas should keep request orchestration and output shaping, not transport implementation.');
  Assert.IsTrue(ContainsText(lTransportSource, 'TLspJsonRpcClient = class'),
    'Expected focused LSP transport unit to own TLspJsonRpcClient.');
  Assert.IsTrue(ContainsText(lTransportSource, 'CreatePipe(') and ContainsText(lTransportSource, 'CreateProcess(') and
    ContainsText(lTransportSource, 'ReadMessage(') and ContainsText(lTransportSource, 'WriteMessage('),
    'Expected focused LSP transport unit to own process startup and JSON-RPC framing.');
  Assert.IsTrue(ContainsText(lTransportSource, 'fInputHandle: THandle') and
    ContainsText(lTransportSource, 'CloseHandle(fInputHandle)') and
    ContainsText(lTransportSource, 'CloseHandle(fOutputHandle)'),
    'Expected transport to explicitly own and close pipe handles wrapped by THandleStream.');
end;

function TRealLspAcceptanceTests.FixtureDprojPath: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\LspProjectFixture.dproj');
end;

function TRealLspAcceptanceTests.FixtureUnit1Path: string;
begin
  Result := TPath.Combine(RepoRoot, 'tests\fixtures\LspProjectFixture\Unit1.pas');
end;

function JsonArrayHasString(aArray: TJSONArray; const aValue: string): Boolean;
var
  lItem: TJSONValue;
begin
  Result := False;
  if aArray = nil then
    Exit;
  for lItem in aArray do
    if (lItem is TJSONString) and (lItem.Value = aValue) then
      Exit(True);
end;

function LiveDelphiLspProcessesCreatedSince(const aStartedAt: TFileTime): string;
const
  // PROCESS_QUERY_LIMITED_INFORMATION; Winapi.Windows does not declare it.
  cProcessQueryLimitedInformation = $1000;
var
  lCreated, lExited, lKernel, lUser: TFileTime;
  lEntry: TProcessEntry32;
  lProcess: THandle;
  lSnapshot: THandle;
begin
  Result := '';
  lSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  Assert.IsTrue(lSnapshot <> INVALID_HANDLE_VALUE, 'Process snapshot failed: ' + SysErrorMessage(GetLastError));
  try
    lEntry := Default(TProcessEntry32);
    lEntry.dwSize := SizeOf(lEntry);
    if not Process32First(lSnapshot, lEntry) then
      Exit;
    repeat
      if SameText(PChar(@lEntry.szExeFile[0]), 'DelphiLSP.exe') then
      begin
        // Liveness and creation time come from the process handle, so a reused
        // PID from an older process cannot be mistaken for one of ours.
        lProcess := OpenProcess(cProcessQueryLimitedInformation or SYNCHRONIZE, False, lEntry.th32ProcessID);
        if lProcess <> 0 then
        try
          if (WaitForSingleObject(lProcess, 0) = WAIT_TIMEOUT) and
            GetProcessTimes(lProcess, lCreated, lExited, lKernel, lUser) and
            (CompareFileTime(lCreated, aStartedAt) >= 0) then
            Result := Result + ' ' + UIntToStr(lEntry.th32ProcessID);
        finally
          CloseHandle(lProcess);
        end;
      end;
    until not Process32Next(lSnapshot, lEntry);
  finally
    CloseHandle(lSnapshot);
  end;
end;

function TRealLspAcceptanceTests.RunLspCommand(const aScenarioName, aArgs: string; out aJson: TJSONObject): Cardinal;
var
  lLogPath, lLogText, lSurvivors: string;
  lStartedAt: TFileTime;
  lValue: TJSONValue;
  lWarnings: TJSONArray;
begin
  TMonitor.Enter(GRealLspAcceptanceLock);
  try
    EnsureResolverBuilt;
    lLogPath := UniqueTempPath(aScenarioName) + '.json';
    GetSystemTimeAsFileTime(lStartedAt);
    Assert.IsTrue(RunResolverProcess(aArgs, RepoRoot, lLogPath, Result), 'LSP command must start');
    // Any DelphiLSP started during the command and still alive after DAK exited
    // escaped the owned cleanup. An unrelated DelphiLSP started concurrently by
    // an IDE would also be reported; the check fails closed.
    lSurvivors := LiveDelphiLspProcessesCreatedSince(lStartedAt);
    Assert.AreEqual('', lSurvivors, 'DelphiLSP processes survived the command: PIDs' + lSurvivors);
    lLogText := ReadUtf8TextFile(lLogPath);
    lValue := TJSONValue.ParseJSONValue(lLogText);
    if not (lValue is TJSONObject) then
    begin
      lValue.Free;
      Assert.Fail('Expected JSON output for ' + aScenarioName + ': ' + lLogText + '. Log: ' + lLogPath);
    end;
    aJson := lValue as TJSONObject;
    if Result = 0 then
    begin
      Assert.AreEqual('controlled-termination', aJson.GetValue<TJSONObject>('lsp').GetValue<string>('cleanup'));
      Assert.AreEqual('unverified', aJson.GetValue<TJSONObject>('lsp').GetValue<string>('settingsAcceptance'));
      lWarnings := aJson.GetValue<TJSONArray>('warnings');
      Assert.IsTrue(JsonArrayHasString(lWarnings, cLspCleanupWarning),
        'Controlled cleanup must be reported: ' + lWarnings.ToJSON);
      Assert.IsTrue(JsonArrayHasString(lWarnings, cLspSettingsWarning),
        'Unverified settings acceptance must be reported: ' + lWarnings.ToJSON);
    end;
  finally
    TMonitor.Exit(GRealLspAcceptanceLock);
  end;
end;
procedure TRealLspAcceptanceTests.RealDelphi23ProbePreservesBothHandshakeModes;
var
  lArgs, lLspPath, lModeName, lOtherKey, lPath: string;
  lJson, lMode, lOptions: TJSONObject;
  lModes: TJSONArray;
begin
  RequireRealDelphiLsp23OrSkip(lLspPath);
  lArgs := 'lsp probe --project ' + QuoteArg(FixtureDprojPath) +
    ' --delphi 23.0 --lsp-path ' + QuoteArg(lLspPath) +
    ' --mode contextFile --mode settingsFile --show-init-options --format json';
  lJson := nil;
  try
    Assert.AreEqual<Cardinal>(0, RunLspCommand('real-lsp-probe-modes', lArgs, lJson));
    lModes := (lJson.Values['result'] as TJSONObject).GetValue<TJSONArray>('modes');
    Assert.AreEqual(2, lModes.Count);
    for var i := 0 to 1 do
    begin
      lMode := lModes.Items[i] as TJSONObject;
      lModeName := 'contextFile';
      lOtherKey := 'settingsFile';
      if i = 1 then
      begin
        lModeName := 'settingsFile';
        lOtherKey := 'contextFile';
      end;
      Assert.AreEqual(lModeName, lMode.GetValue<string>('mode'));
      lOptions := lMode.GetValue<TJSONObject>('initializationOptions');
      Assert.IsNull(lOptions.Values[lOtherKey]);
      lPath := lOptions.GetValue<string>(lModeName);
      Assert.IsTrue(FileExists(lPath), lPath);
      Assert.IsTrue(lPath.Contains('.dak'), lPath);
      if i = 1 then
      begin
        // Settings mode reports its file and the configuration notification it sent.
        Assert.AreEqual<string>(lPath, lMode.GetValue<string>('settingsFile'));
        Assert.AreEqual<string>(lPath, lMode.GetValue<TJSONObject>('configurationNotification')
          .GetValue<TJSONObject>('settings').GetValue<string>('settingsFile'));
      end else
        Assert.IsNull(lMode.Values['configurationNotification'], 'Context mode sends no configuration');
    end;
  finally
    lJson.Free;
  end;
end;

procedure TLspContextTests.LspDiscoveryPrefersExplicitPathThenResolvedInstall;
var
  lContext: TLspContext;
  lDprojPath: string;
  lError: string;
  lExePath: string;
  lExplicitExePath: string;
  lOptions: TAppOptions;
  lRootExePath: string;
  lResolvedExePath: string;
begin
  lDprojPath := PrepareResolvedContext('lsp-runner-discovery', lContext);
  lRootExePath := TPath.Combine(TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds'), 'DelphiLSP.exe');
  lResolvedExePath := TPath.Combine(TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds'), 'bin64\DelphiLSP.exe');
  lExplicitExePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Tools\DelphiLSP.exe');
  WriteUtf8File(lRootExePath, 'root');
  WriteUtf8File(lResolvedExePath, 'resolved');
  WriteUtf8File(lExplicitExePath, 'explicit');

  lOptions := BuildRunnerOptions(lDprojPath);
  lOptions.fLspPath := lExplicitExePath;
  lOptions.fHasLspPath := True;
  lError := '';
  Assert.IsTrue(TryResolveDelphiLspExe(lOptions, lContext, lExePath, lError),
    'Expected explicit lsp path to resolve. Error: ' + lError);
  Assert.AreEqual(TPath.GetFullPath(lExplicitExePath), lExePath, 'Expected explicit path to win.');

  lOptions.fLspPath := TPath.Combine(ExtractFilePath(lDprojPath), 'FakeBds');
  lOptions.fHasLspPath := True;
  lError := '';
  Assert.IsTrue(TryResolveDelphiLspExe(lOptions, lContext, lExePath, lError),
    'Expected Delphi install root passed via --lsp-path to resolve. Error: ' + lError);
  Assert.AreEqual(TPath.GetFullPath(lRootExePath), lExePath,
    'Expected install root override to resolve the first existing root candidate.');

  lOptions.fLspPath := '';
  lOptions.fHasLspPath := False;
  lError := '';
  Assert.IsTrue(TryResolveDelphiLspExe(lOptions, lContext, lExePath, lError),
    'Expected Delphi-version-derived install path to resolve. Error: ' + lError);
  Assert.AreEqual(TPath.GetFullPath(lRootExePath), lExePath,
    'Expected first existing derived install candidate to be used.');
end;

procedure TRealLspAcceptanceTests.RealDelphi23DefinitionMatchesFixtureGoldenAnswer;
var
  lJson: TJSONObject;
  lLocations: TJSONArray;
  lArgs: string;
  lLspPath: string;
  lLocation: TJSONObject;
begin
  RequireRealDelphiLsp23OrSkip(lLspPath);
  lArgs := 'lsp definition --project ' + QuoteArg(FixtureDprojPath) +
    ' --delphi 23.0 --lsp-path ' + QuoteArg(lLspPath) +
    ' --file ' + QuoteArg(FixtureUnit1Path) +
    ' --line 8 --col 21 --format json';
  lJson := nil;
  try
    Assert.AreEqual<Cardinal>(0, RunLspCommand('real-lsp-definition-golden', lArgs, lJson),
      'Expected real Delphi 23 definition golden query to succeed.');
    lLocations := (lJson.Values['result'] as TJSONObject).GetValue<TJSONArray>('locations');
    Assert.IsNotNull(lLocations, 'Expected real definition locations array.');
    Assert.AreEqual(1, lLocations.Count, 'Expected one real definition location.');
    lLocation := lLocations.Items[0] as TJSONObject;
    Assert.AreEqual<string>(FixtureUnit1Path, lLocation.GetValue<string>('file'),
      'Expected definition to stay inside the fixture unit.');
    Assert.AreEqual(13, lLocation.GetValue<Integer>('line'),
      'Expected definition to resolve to the implementation of TFixtureType.Run.');
    Assert.AreEqual(1, lLocation.GetValue<Integer>('col'),
      'Expected definition column for TFixtureType.Run implementation.');
    Assert.AreEqual(13, lLocation.GetValue<Integer>('endLine'),
      'Expected definition end line for TFixtureType.Run implementation.');
    Assert.AreEqual(1, lLocation.GetValue<Integer>('endCol'),
      'Expected definition end column for TFixtureType.Run implementation.');
  finally
    lJson.Free;
  end;
end;

procedure TRealLspAcceptanceTests.RealDelphi23SymbolsMatchFixtureGoldenAnswer;
var
  lArgs: string;
  lJson: TJSONObject;
  lLspPath: string;
  lSymbols: TJSONArray;
begin
  RequireRealDelphiLsp23OrSkip(lLspPath);
  lArgs := 'lsp symbols --project ' + QuoteArg(FixtureDprojPath) +
    ' --delphi 23.0 --lsp-path ' + QuoteArg(lLspPath) +
    ' --file ' + QuoteArg(FixtureUnit1Path) +
    ' --query Fixture --format json';
  lJson := nil;
  try
    Assert.AreEqual<Cardinal>(0, RunLspCommand('real-lsp-symbols-golden', lArgs, lJson),
      'Expected real Delphi 23 symbols golden query to succeed.');
    lSymbols := (lJson.Values['result'] as TJSONObject).GetValue<TJSONArray>('symbols');
    Assert.IsNotNull(lSymbols, 'Expected real symbols array.');
    Assert.AreEqual(2, lSymbols.Count, 'Expected two real golden symbol rows.');
    Assert.AreEqual<string>('TFixtureType', (lSymbols.Items[0] as TJSONObject).GetValue<string>('name'),
      'Expected class symbol first.');
    Assert.AreEqual(5, (lSymbols.Items[0] as TJSONObject).GetValue<Integer>('kind'),
      'Expected class symbol kind.');
    Assert.AreEqual<string>('interface', (lSymbols.Items[0] as TJSONObject).GetValue<string>('containerName'),
      'Expected class symbol container.');
    Assert.AreEqual<string>(FixtureUnit1Path, (lSymbols.Items[0] as TJSONObject).GetValue<string>('file'),
      'Expected class symbol file.');
    Assert.AreEqual(6, (lSymbols.Items[0] as TJSONObject).GetValue<Integer>('line'),
      'Expected class symbol line.');
    Assert.AreEqual(18, (lSymbols.Items[0] as TJSONObject).GetValue<Integer>('col'),
      'Expected class symbol column.');
    Assert.AreEqual<string>('TFixtureType.Run', (lSymbols.Items[1] as TJSONObject).GetValue<string>('name'),
      'Expected method symbol second.');
    Assert.AreEqual(6, (lSymbols.Items[1] as TJSONObject).GetValue<Integer>('kind'),
      'Expected method symbol kind.');
    Assert.AreEqual<string>('implementation', (lSymbols.Items[1] as TJSONObject).GetValue<string>('containerName'),
      'Expected method symbol container.');
    Assert.AreEqual<string>(FixtureUnit1Path, (lSymbols.Items[1] as TJSONObject).GetValue<string>('file'),
      'Expected method symbol file.');
    Assert.AreEqual(13, (lSymbols.Items[1] as TJSONObject).GetValue<Integer>('line'),
      'Expected method symbol line.');
    Assert.AreEqual(1, (lSymbols.Items[1] as TJSONObject).GetValue<Integer>('col'),
      'Expected method symbol column.');
  finally
    lJson.Free;
  end;
end;

procedure TRealLspAcceptanceTests.RealDelphi23HoverMatchesFixtureGoldenAnswer;
type
  THoverCase = record
    fScenario: string;
    fPlatformArgs: string;
    fLine: Integer;
    fCol: Integer;
    fExpectedSignature: string;
  end;
const
  // DelphiLSP answers hover only through the platform compiler DLL, so one case
  // runs per platform. Each position names a different symbol; a golden that
  // only checked for non-empty text could pass on the wrong declaration.
  cCases: array[0..1] of THoverCase = (
    (fScenario: 'real-lsp-hover-golden-win32'; fPlatformArgs: ''; fLine: 8; fCol: 21;
     fExpectedSignature: 'class procedure TFixtureType.Run'),
    (fScenario: 'real-lsp-hover-golden-win64'; fPlatformArgs: ' --platform Win64 --config Debug'; fLine: 13;
     fCol: 18; fExpectedSignature: 'type Unit1.TFixtureType = class(TObject)'));
var
  lArgs: string;
  lCase: THoverCase;
  lJson: TJSONObject;
  lLspPath: string;
  lResult: TJSONObject;
begin
  RequireRealDelphiLsp23OrSkip(lLspPath);
  for lCase in cCases do
  begin
    lArgs := 'lsp hover --project ' + QuoteArg(FixtureDprojPath) +
      ' --delphi 23.0 --lsp-path ' + QuoteArg(lLspPath) + lCase.fPlatformArgs +
      ' --file ' + QuoteArg(FixtureUnit1Path) +
      Format(' --line %d --col %d --format json', [lCase.fLine, lCase.fCol]);
    lJson := nil;
    try
      Assert.AreEqual<Cardinal>(0, RunLspCommand(lCase.fScenario, lArgs, lJson),
        'Expected real Delphi 23 hover golden query to succeed: ' + lCase.fScenario);
      lResult := lJson.Values['result'] as TJSONObject;
      Assert.IsNotNull(lResult, 'Expected a hover result object: ' + lCase.fScenario);
      Assert.IsFalse(lResult.GetValue<Boolean>('isEmpty', False),
        'Expected non-empty real hover: ' + lCase.fScenario + ' ' + lResult.ToJSON);
      Assert.IsTrue(ContainsText(lResult.GetValue<string>('contentsText', ''), lCase.fExpectedSignature),
        'Expected hover signature "' + lCase.fExpectedSignature + '": ' + lResult.ToJSON);
      Assert.IsTrue(ContainsText(lResult.GetValue<string>('contentsMarkdown', ''), lCase.fExpectedSignature),
        'Expected DelphiLSP markdown hover content: ' + lResult.ToJSON);
      Assert.IsFalse(ContainsText(lJson.GetValue<TJSONArray>('warnings').ToJSON, 'compiler DLL not resolved'),
        'A resolved compiler DLL must not be reported: ' + lJson.ToJSON);
    finally
      lJson.Free;
    end;
  end;
end;

procedure TRealLspAcceptanceTests.RealDelphi23UnsupportedPlatformWarnsAndStillAnswers;
var
  lArgs, lLspPath: string;
  lJson: TJSONObject;
  lLocations: TJSONArray;
  lWarnings: string;
begin
  // Linux64 has no proven compiler DLL for DelphiLSP: the query still runs
  // without "dllname", as before, and names the reason in its warnings.
  RequireRealDelphiLsp23OrSkip(lLspPath);
  lArgs := 'lsp definition --project ' + QuoteArg(FixtureDprojPath) +
    ' --delphi 23.0 --lsp-path ' + QuoteArg(lLspPath) + ' --platform Linux64 --config Debug' +
    ' --file ' + QuoteArg(FixtureUnit1Path) + ' --line 8 --col 21 --format json';
  lJson := nil;
  try
    Assert.AreEqual<Cardinal>(0, RunLspCommand('real-lsp-definition-linux64-warning', lArgs, lJson),
      'Expected an unresolved compiler DLL not to refuse the query.');
    lWarnings := lJson.GetValue<TJSONArray>('warnings').ToJSON;
    Assert.IsTrue(ContainsText(lWarnings, 'DelphiLSP compiler DLL not resolved (platform Linux64 is not supported'),
      lWarnings);
    Assert.IsTrue(ContainsText(lWarnings, 'hover may return no content'), lWarnings);
    lLocations := (lJson.Values['result'] as TJSONObject).GetValue<TJSONArray>('locations');
    Assert.AreEqual(1, lLocations.Count, 'Expected the definition answer without dllname: ' + lJson.ToJSON);
    Assert.AreEqual(13, (lLocations.Items[0] as TJSONObject).GetValue<Integer>('line'), lJson.ToJSON);
  finally
    lJson.Free;
  end;
end;

initialization
  GRealLspAcceptanceLock := TObject.Create;
  TDUnitX.RegisterTestFixture(TLspContextTests);
  TDUnitX.RegisterTestFixture(TLspRunnerTests);
  TDUnitX.RegisterTestFixture(TLspArchitectureTests);
  TDUnitX.RegisterTestFixture(TRealLspAcceptanceTests);

finalization
  GRealLspAcceptanceLock.Free;

end.
