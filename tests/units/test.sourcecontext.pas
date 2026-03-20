unit Test.SourceContext;

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections, System.IOUtils, System.SysUtils,
  Dak.Project, Dak.SourceContext, Dak.Types,
  Test.Support;

type
  [TestFixture]
  TSourceContextTests = class
  private
    procedure CreateFixtureProject(out aDprojPath: string; out aProjectFilePath: string; out aSearchFilePath: string);
    function LoadLookup(const aDprojPath: string): TProjectSourceLookup;
  public
    [Test]
    procedure AbsolutePathSourceContextResolves;
    [Test]
    procedure ProjectRelativeSourceContextResolves;
    [Test]
    procedure ProjectRelativeSourceContextPrefersProjectLookupOverCurrentDirectoryShadow;
    [Test]
    procedure SearchPathSourceContextResolves;
    [Test]
    procedure MissingSourceContextFileReturnsFalse;
  end;

implementation

procedure WriteFixtureFile(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.UTF8);
end;

procedure TSourceContextTests.CreateFixtureProject(out aDprojPath: string; out aProjectFilePath: string;
  out aSearchFilePath: string);
var
  lRoot: string;
begin
  EnsureTempClean;
  lRoot := TPath.Combine(TempRoot, 'source-context-fixture');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  aDprojPath := TPath.Combine(lRoot, 'SourceContextFixture.dproj');
  aProjectFilePath := TPath.Combine(lRoot, 'ProjectRelativeUnit.pas');
  aSearchFilePath := TPath.Combine(TPath.Combine(lRoot, 'lib'), 'SearchHitUnit.pas');

  WriteFixtureFile(aDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <MainSource>SourceContextFixture.dpr</MainSource>' + #13#10 +
    '    <DCC_UnitSearchPath>lib</DCC_UnitSearchPath>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '  <ItemGroup>' + #13#10 +
    '    <DCCReference Include="ProjectRelativeUnit.pas"/>' + #13#10 +
    '  </ItemGroup>' + #13#10 +
    '</Project>' + #13#10);
  WriteFixtureFile(TPath.ChangeExtension(aDprojPath, '.dpr'),
    'program SourceContextFixture;' + #13#10 +
    'begin' + #13#10 +
    'end.' + #13#10);
  WriteFixtureFile(aProjectFilePath,
    'unit ProjectRelativeUnit;' + #13#10 +
    'interface' + #13#10 +
    'procedure TouchProjectRelative;' + #13#10 +
    'implementation' + #13#10 +
    'procedure TouchProjectRelative;' + #13#10 +
    'begin' + #13#10 +
    '  ProjectRelativeValue := 1;' + #13#10 +
    'end;' + #13#10 +
    'end.' + #13#10);
  WriteFixtureFile(aSearchFilePath,
    'unit SearchHitUnit;' + #13#10 +
    'interface' + #13#10 +
    'procedure TouchSearchHit;' + #13#10 +
    'implementation' + #13#10 +
    'procedure TouchSearchHit;' + #13#10 +
    'begin' + #13#10 +
    '  SearchPathValue := 1;' + #13#10 +
    'end;' + #13#10 +
    'end.' + #13#10);
end;

function TSourceContextTests.LoadLookup(const aDprojPath: string): TProjectSourceLookup;
var
  lEnvVars: TDictionary<string, string>;
  lError: string;
begin
  lEnvVars := TDictionary<string, string>.Create;
  try
    Assert.IsTrue(TryBuildProjectSourceLookup(aDprojPath, 'Debug', 'Win32', '23.0', lEnvVars, nil, Result, lError),
      'Expected source lookup to load. Error: ' + lError);
  finally
    lEnvVars.Free;
  end;
end;

procedure TSourceContextTests.AbsolutePathSourceContextResolves;
var
  lContext: TSourceContextSnippet;
  lError: string;
  lDprojPath: string;
  lLookup: TProjectSourceLookup;
  lProjectFilePath: string;
  lSearchFilePath: string;
begin
  CreateFixtureProject(lDprojPath, lProjectFilePath, lSearchFilePath);
  lLookup := LoadLookup(lDprojPath);

  Assert.IsTrue(TryResolveSourceContext(lLookup, lProjectFilePath, 7, 1, lContext, lError),
    'Expected absolute file path to resolve. Error: ' + lError);
  Assert.AreEqual(TPath.GetFullPath(lProjectFilePath), lContext.fFilePath);
  Assert.IsTrue(Pos('ProjectRelativeValue := 1;', String.Join(#13#10, lContext.fLines)) > 0,
    'Expected source context to include the target line.');
end;

procedure TSourceContextTests.ProjectRelativeSourceContextResolves;
var
  lContext: TSourceContextSnippet;
  lError: string;
  lDprojPath: string;
  lLookup: TProjectSourceLookup;
  lProjectFilePath: string;
  lSearchFilePath: string;
begin
  CreateFixtureProject(lDprojPath, lProjectFilePath, lSearchFilePath);
  lLookup := LoadLookup(lDprojPath);

  Assert.IsTrue(TryResolveSourceContext(lLookup, 'ProjectRelativeUnit.pas', 7, 1, lContext, lError),
    'Expected project-relative file token to resolve. Error: ' + lError);
  Assert.AreEqual(TPath.GetFullPath(lProjectFilePath), lContext.fFilePath);
end;

procedure TSourceContextTests.ProjectRelativeSourceContextPrefersProjectLookupOverCurrentDirectoryShadow;
var
  lContext: TSourceContextSnippet;
  lCurrentDir: string;
  lDprojPath: string;
  lError: string;
  lLookup: TProjectSourceLookup;
  lProjectFilePath: string;
  lSearchFilePath: string;
  lShadowDir: string;
  lShadowFilePath: string;
begin
  CreateFixtureProject(lDprojPath, lProjectFilePath, lSearchFilePath);
  lLookup := LoadLookup(lDprojPath);
  lShadowDir := TPath.Combine(TempRoot, 'source-context-shadow');
  if TDirectory.Exists(lShadowDir) then
    TDirectory.Delete(lShadowDir, True);
  TDirectory.CreateDirectory(lShadowDir);
  lShadowFilePath := TPath.Combine(lShadowDir, 'ProjectRelativeUnit.pas');
  WriteFixtureFile(lShadowFilePath,
    'unit ProjectRelativeUnit;' + #13#10 +
    'interface' + #13#10 +
    'implementation' + #13#10 +
    'begin' + #13#10 +
    '  ShadowValue := 1;' + #13#10 +
    'end.' + #13#10);

  lCurrentDir := GetCurrentDir;
  try
    SetCurrentDir(lShadowDir);
    Assert.IsTrue(TryResolveSourceContext(lLookup, 'ProjectRelativeUnit.pas', 7, 1, lContext, lError),
      'Expected project-relative lookup to win even with a cwd shadow file. Error: ' + lError);
  finally
    SetCurrentDir(lCurrentDir);
  end;

  Assert.AreEqual(TPath.GetFullPath(lProjectFilePath), lContext.fFilePath);
  Assert.IsTrue(Pos('ProjectRelativeValue := 1;', String.Join(#13#10, lContext.fLines)) > 0,
    'Expected project file content, not cwd shadow content.');
end;

procedure TSourceContextTests.SearchPathSourceContextResolves;
var
  lContext: TSourceContextSnippet;
  lError: string;
  lDprojPath: string;
  lLookup: TProjectSourceLookup;
  lProjectFilePath: string;
  lSearchFilePath: string;
begin
  CreateFixtureProject(lDprojPath, lProjectFilePath, lSearchFilePath);
  lLookup := LoadLookup(lDprojPath);

  Assert.IsTrue(TryResolveSourceContext(lLookup, 'SearchHitUnit.pas', 7, 1, lContext, lError),
    'Expected search-path file token to resolve. Error: ' + lError);
  Assert.AreEqual(TPath.GetFullPath(lSearchFilePath), lContext.fFilePath);
end;

procedure TSourceContextTests.MissingSourceContextFileReturnsFalse;
var
  lContext: TSourceContextSnippet;
  lError: string;
  lDprojPath: string;
  lLookup: TProjectSourceLookup;
  lProjectFilePath: string;
  lSearchFilePath: string;
begin
  CreateFixtureProject(lDprojPath, lProjectFilePath, lSearchFilePath);
  lLookup := LoadLookup(lDprojPath);

  Assert.IsFalse(TryResolveSourceContext(lLookup, 'MissingUnit.pas', 7, 1, lContext, lError),
    'Expected missing source file to stay unresolved.');
  Assert.IsTrue(Pos('Could not resolve source file', lError) > 0, 'Expected missing-file error text.');
end;

initialization
  TDUnitX.RegisterTestFixture(TSourceContextTests);

end.
