unit Test.Build;

interface

uses
  DUnitX.TestFramework,
  System.IOUtils,
  System.SysUtils,
  System.StrUtils,
  Test.Support;

type
  [TestFixture]
  TBuildTests = class
  public
    [Test]
    procedure BuildResolverExe;
    [Test]
    procedure BuildBatUsesToolRootForHelperScripts;
  end;

implementation

procedure WriteUtf8File(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.UTF8);
end;

procedure TBuildTests.BuildResolverExe;
begin
  EnsureResolverBuilt;
  Assert.IsTrue(FileExists(ResolverExePath), 'Resolver exe not found: ' + ResolverExePath);
end;

procedure TBuildTests.BuildBatUsesToolRootForHelperScripts;
var
  lBat: string;
  lCmd: string;
  lDprPath: string;
  lDprojPath: string;
  lExit: Cardinal;
  lExternalRoot: string;
  lLog: string;
  lLogText: string;
begin
  EnsureTempClean;
  lExternalRoot := TPath.Combine(TempRoot, 'external-build-root');
  if TDirectory.Exists(lExternalRoot) then
    TDirectory.Delete(lExternalRoot, True);
  ForceDirectories(TPath.Combine(lExternalRoot, '.git'));

  lDprojPath := TPath.Combine(lExternalRoot, 'ExternalBuildCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lLog := TPath.Combine(lExternalRoot, 'build.log');

  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>ExternalBuildCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_Define>madExcept</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program ExternalBuildCheck;' + sLineBreak +
    'begin' + sLineBreak +
    '  this does not compile' + sLineBreak +
    'end.' + sLineBreak);
  WriteUtf8File(TPath.ChangeExtension(lDprojPath, '.mes'), 'stub' + sLineBreak);

  lBat := TPath.Combine(RepoRoot, 'build-delphi.bat');
  lCmd := GetEnvironmentVariable('ComSpec');
  if lCmd = '' then
    lCmd := 'C:\Windows\System32\cmd.exe';

  Assert.IsTrue(
    RunProcess(
      lCmd,
      '/C "call ' + QuoteArg(lBat) + ' ' + QuoteArg(lDprojPath) + ' -config Debug -platform Win32 -ver 23 -ai"',
      RepoRoot,
      lLog,
      lExit
    ),
    'Failed to start build-delphi.bat.'
  );

  lLogText := '';
  if FileExists(lLog) then
    lLogText := TFile.ReadAllText(lLog, TEncoding.UTF8);

  Assert.IsFalse(
    ContainsText(lLogText, 'madExcept probe script not found'),
    'build-delphi.bat resolved the madExcept probe under the external repo instead of the tool root. Log: ' + lLog
  );
  Assert.IsFalse(
    ContainsText(lLogText, 'madExcept tool resolver script not found'),
    'build-delphi.bat resolved the madExcept tool resolver under the external repo instead of the tool root. Log: ' + lLog
  );
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildTests);

end.
