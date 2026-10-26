unit Test.NativeAnalysisWorkspace;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisWorkspaceTests = class
  public
    [Test]
    procedure UnmanagedIdentityPreservesCompleteReferenceContract;
    [Test]
    procedure UnmanagedIdentityPreservesUnicodeOrderAndBinaryContents;
    [Test]
    procedure UnmanagedIdentityResolvesActualRootSpelling;
    [TestCase('MissingRoot', 'False')]
    [TestCase('FileRoot', 'True')]
    procedure UnmanagedIdentityRejectsInvalidRoot(aUseFile: Boolean);
    [Test]
    procedure UnmanagedIdentityAcceptsEmptyDirectory;
    [Test]
    procedure UnmanagedIdentityRejectsUnreadableSubtree;
    [TestCase('Directory', 'False')]
    [TestCase('LinkedWorktree', 'True')]
    procedure GitIdentityPreservesCompleteReferenceContract(aUseWorktree: Boolean);
    [TestCase('MissingGit', 'True')]
    [TestCase('UnreadableMetadata', 'False')]
    procedure GitUnavailableMetadataRetainsTruthfulFallback(aMissingTool: Boolean);
    [TestCase('Healthy', 'False')]
    [TestCase('BrokenMarker', 'True')]
    procedure GitIdentityIncludesInitializedSubmoduleSources(aBrokenMarker: Boolean);
    [TestCase('CleanNested', '0')]
    [TestCase('ModifiedChild', '1')]
    [TestCase('UninitializedChild', '2')]
    [TestCase('InactivePopulatedChild', '3')]
    procedure GitIdentityPreservesExactRecursiveSubmodulePaths(aScenario: Integer);
    [Test]
    procedure GitWithoutSubmodulesAvoidsRecursiveToolStartup;
    [Test]
    procedure GitAlternateIndexCannotMasqueradeAsWorkspaceIdentity;
    [Test]
    procedure SvnCleanWorkspacePreservesReferenceContract;
    [Test]
    procedure SvnUnversionedRootPreservesIndependentFailures;
    [TestCase('Changed', '1')]
    [TestCase('MixedRevision', '2')]
    [TestCase('External', '3')]
    [TestCase('MissingSvnversion', '4')]
    [TestCase('MissingExplicitSvn', '5')]
    [TestCase('MissingTrackedFile', '6')]
    [TestCase('ScheduledDeletion', '7')]
    [TestCase('ScheduledAddition', '8')]
    [TestCase('SparseCheckout', '9')]
    [TestCase('RelativeExplicitSvn', '10')]
    [TestCase('UnresolvableTrackedLink', '11')]
    procedure SvnWorkspacePreservesPartialAndChangedReferenceCases(aScenario: Integer);
  end;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  Winapi.AccCtrl, Winapi.AclAPI, Winapi.Windows,
  AutoFree,
  Dak.Analysis.Workspace, Dak.Settings,
  Test.Support;

procedure AssertInventoryFails(const aRoot, aDiagnosticPath: string);
var
  g: TGarbos;
  lFailed: Boolean;
  lIdentity: TJSONObject;
  lWorkspace: TWorkspaceSettings;
begin
  lWorkspace := Default(TWorkspaceSettings);
  lWorkspace.fRoot := aRoot;
  lWorkspace.fVcs := 'none';
  lFailed := False;
  try
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace), g);
  except
    on E: EInOutError do
    begin
      lFailed := True;
      Assert.IsTrue(Pos(aDiagnosticPath, E.Message) > 0, E.Message);
    end;
  end;
  Assert.IsTrue(lFailed, 'Incomplete source inventory must fail with the affected path.');
end;

procedure TNativeAnalysisWorkspaceTests.UnmanagedIdentityRejectsInvalidRoot(aUseFile: Boolean);
var
  lParent: string;
  lRoot: string;
begin
  lParent := UniqueTempPath('native-analysis-invalid-root');
  TDirectory.CreateDirectory(lParent);
  lRoot := TPath.Combine(lParent, 'selected');
  try
    if aUseFile then
      TFile.WriteAllText(lRoot, 'not a directory', TEncoding.ASCII);
    AssertInventoryFails(lRoot, lRoot);
  finally
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.UnmanagedIdentityAcceptsEmptyDirectory;
var
  g: TGarbos;
  lIdentity: TJSONObject;
  lRoot: string;
  lSources: TJSONObject;
  lWorkspace: TWorkspaceSettings;
begin
  lRoot := UniqueTempPath('native-analysis-empty-root');
  TDirectory.CreateDirectory(lRoot);
  try
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'none';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace), g);
    Assert.AreEqual('available', lIdentity.GetValue<TJSONObject>('capabilities').GetValue<string>('inventory'));
    RequireJsonObjectKey(lIdentity, 'source_inputs', lSources);
    Assert.AreEqual(0, lSources.GetValue<Integer>('file_count'));
    Assert.AreEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      lSources.GetValue<string>('sha256'));
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.UnmanagedIdentityRejectsUnreadableSubtree;
const
  // Windows SDK winnt.h values absent from Delphi 12's Winapi.Windows declarations.
  cProtectedDacl: DWORD = $80000000;
  cUnprotectedDacl: DWORD = $20000000;
  cAclRevision = 2;
var
  lControl: SECURITY_DESCRIPTOR_CONTROL;
  lDenied: string;
  lDescriptor: PSecurityDescriptor;
  lEmptyAcl: TACL;
  lHandle: THandle;
  lOriginalAcl: PACL;
  lRestoreFlags: SECURITY_INFORMATION;
  lRevision: DWORD;
  lRoot: string;
  lSearch: TSearchRec;
  lStatus: Integer;
begin
  lRoot := UniqueTempPath('native-analysis-denied-subtree');
  lDenied := TPath.Combine(lRoot, 'denied');
  TDirectory.CreateDirectory(lDenied);
  try
    TFile.WriteAllText(TPath.Combine(lRoot, 'Main.pas'), 'unit Main;', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(lDenied, 'Hidden.pas'), 'unit Hidden;', TEncoding.ASCII);
    // Keep an already authorized handle so the original ACL can always be restored.
    lHandle := CreateFile(PChar(lDenied), READ_CONTROL or WRITE_DAC,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS, 0);
    Assert.IsTrue(lHandle <> INVALID_HANDLE_VALUE, SysErrorMessage(GetLastError));
    try
      lDescriptor := nil;
      lOriginalAcl := nil;
      Assert.AreEqual<DWORD>(ERROR_SUCCESS, GetSecurityInfo(lHandle, SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION, nil, nil, @lOriginalAcl, nil, @lDescriptor));
      try
        Assert.IsTrue(GetSecurityDescriptorControl(lDescriptor, lControl, lRevision));
        lRestoreFlags := DACL_SECURITY_INFORMATION;
        if (lControl and SE_DACL_PROTECTED) <> 0 then
          lRestoreFlags := lRestoreFlags or cProtectedDacl
        else
          lRestoreFlags := lRestoreFlags or cUnprotectedDacl;
        Assert.IsTrue(InitializeAcl(lEmptyAcl, SizeOf(lEmptyAcl), cAclRevision));
        Assert.AreEqual<DWORD>(ERROR_SUCCESS, SetSecurityInfo(lHandle, SE_FILE_OBJECT,
          DACL_SECURITY_INFORMATION or cProtectedDacl, nil, nil, @lEmptyAcl, nil));
        try
          lStatus := FindFirst(TPath.Combine(lDenied, '*'), faAnyFile, lSearch);
          if lStatus = 0 then
            System.SysUtils.FindClose(lSearch);
          Assert.AreEqual<Integer>(ERROR_ACCESS_DENIED, lStatus, 'The real fixture must deny enumeration.');
          AssertInventoryFails(lRoot, lDenied);
        finally
          Assert.AreEqual<DWORD>(ERROR_SUCCESS, SetSecurityInfo(lHandle, SE_FILE_OBJECT,
            lRestoreFlags, nil, nil, lOriginalAcl, nil), 'Restore only this fixture directory ACL.');
        end;
      finally
        LocalFree(HLOCAL(lDescriptor));
      end;
    finally
      CloseHandle(lHandle);
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

function RunFixtureGit(const aRoot, aArguments, aLogPath: string): string;
var
  lExitCode: Cardinal;
  lFilePart: PChar;
  lGit: string;
  lLength: Cardinal;
begin
  lFilePart := nil;
  lLength := SearchPath(nil, 'git.exe', nil, 0, nil, lFilePart);
  Assert.IsTrue(lLength > 0, 'Real Git is required for workspace provenance tests.');
  SetLength(lGit, lLength);
  lLength := SearchPath(nil, 'git.exe', nil, Length(lGit), PChar(lGit), lFilePart);
  SetLength(lGit, lLength);
  Assert.IsTrue(RunProcessWithTimeout(lGit, aArguments, aRoot, aLogPath, 30000, lExitCode));
  Result := ReadUtf8TextFile(aLogPath);
  Assert.AreEqual<Cardinal>(0, lExitCode, Result);
end;

procedure TNativeAnalysisWorkspaceTests.UnmanagedIdentityPreservesCompleteReferenceContract;
var
  g: TGarbos;
  lCapabilities: TJSONObject;
  lIdentity: TJSONObject;
  lRepeated: TJSONObject;
  lChanged: TJSONObject;
  lRoot: string;
  lSources: TJSONObject;
  lWorkspace: TWorkspaceSettings;
begin
  lRoot := UniqueTempPath('native-analysis-unmanaged');
  TDirectory.CreateDirectory(TPath.Combine(lRoot, 'src'));
  TDirectory.CreateDirectory(TPath.Combine(lRoot, '.dak'));
  try
    // Preserve these reference bytes: provenance hashes file contents without EOL conversion.
    TFile.WriteAllText(TPath.Combine(lRoot, 'src\Main.pas'), 'unit Main;' + #10, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(lRoot, 'Shared.inc'), 'CONST VALUE = 1;' + #10, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(lRoot, '.dak\ignored.pas'), 'unit Ignored;' + #10, TEncoding.ASCII);
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'none';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace), g);
    Assert.AreEqual(8, lIdentity.Count, 'Retain the complete unmanaged identity schema.');
    Assert.AreEqual('none', lIdentity.GetValue<string>('vcs'));
    Assert.AreEqual(lRoot, lIdentity.GetValue<string>('root'));
    Assert.AreEqual('not_applicable', lIdentity.GetValue<string>('status'));
    Assert.IsTrue(lIdentity.GetValue('revision') is TJSONNull);
    Assert.IsTrue(lIdentity.GetValue('dirty') is TJSONNull);
    Assert.IsTrue(lIdentity.GetValue('changed_files') is TJSONNull);
    RequireJsonObjectKey(lIdentity, 'capabilities', lCapabilities);
    Assert.AreEqual(5, lCapabilities.Count);
    Assert.AreEqual('not_applicable', lCapabilities.GetValue<string>('revision'));
    Assert.AreEqual('not_applicable', lCapabilities.GetValue<string>('status'));
    Assert.AreEqual('not_applicable', lCapabilities.GetValue<string>('changed_files'));
    Assert.AreEqual('not_applicable', lCapabilities.GetValue<string>('nested_roots'));
    Assert.AreEqual('available', lCapabilities.GetValue<string>('inventory'));
    RequireJsonObjectKey(lIdentity, 'source_inputs', lSources);
    Assert.AreEqual(3, lSources.Count);
    Assert.AreEqual(2, lSources.GetValue<Integer>('file_count'));
    Assert.AreEqual('filesystem-delphi-inputs', lSources.GetValue<string>('scope'));
    // Captured from the pinned Python implementation with the same real-file byte corpus.
    Assert.AreEqual('40afe6fcca248304a0f88a19cedecaab4b9733a10c8841dd477afea1909b0aef',
      lSources.GetValue<string>('sha256'));
    GC(lRepeated, CaptureWorkspaceIdentity(lWorkspace), g);
    Assert.AreEqual(lIdentity.ToJSON, lRepeated.ToJSON, 'Unchanged inputs retain the complete identity.');
    TFile.WriteAllText(TPath.Combine(lRoot, 'src\Main.pas'), 'unit Main; // changed' + #10, TEncoding.ASCII);
    GC(lChanged, CaptureWorkspaceIdentity(lWorkspace), g);
    Assert.AreNotEqual(lSources.GetValue<string>('sha256'),
      lChanged.GetValue<TJSONObject>('source_inputs').GetValue<string>('sha256'),
      'A fresh capture must observe changed source bytes.');
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.UnmanagedIdentityPreservesUnicodeOrderAndBinaryContents;
var
  g: TGarbos;
  i: Integer;
  lIdentity: TJSONObject;
  lPayload: TBytes;
  lRoot: string;
  lSources: TJSONObject;
  lWorkspace: TWorkspaceSettings;
begin
  lRoot := UniqueTempPath('native-analysis-unicode');
  TDirectory.CreateDirectory(lRoot);
  try
    TFile.WriteAllBytes(TPath.Combine(lRoot, 'main.PAS'), [0, 255, 13, 10]);
    TFile.WriteAllBytes(TPath.Combine(lRoot, Char($E000) + '.inc'), TEncoding.ASCII.GetBytes('bmp'));
    TFile.WriteAllBytes(TPath.Combine(lRoot, Char($D800) + Char($DC00) + '.inc'),
      TEncoding.ASCII.GetBytes('supplementary'));
    SetLength(lPayload, 1024 * 1024 + 3);
    for i := 0 to High(lPayload) do
      lPayload[i] := i mod 251;
    TFile.WriteAllBytes(TPath.Combine(lRoot, 'large.dpr'), lPayload);
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'none';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace), g);
    RequireJsonObjectKey(lIdentity, 'source_inputs', lSources);
    Assert.AreEqual(4, lSources.GetValue<Integer>('file_count'));
    // Independent pinned Python capture includes a file crossing the streaming buffer boundary.
    Assert.AreEqual('af53e42d8b355926bb311eb5576f5f27de218184248f4b275417a771bab411b4',
      lSources.GetValue<string>('sha256'));
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.UnmanagedIdentityResolvesActualRootSpelling;
var
  g: TGarbos;
  lIdentity: TJSONObject;
  lParent: string;
  lRoot: string;
  lWorkspace: TWorkspaceSettings;
begin
  lParent := UniqueTempPath('native-analysis-root-spelling');
  lRoot := TPath.Combine(lParent, 'MixedCaseRoot');
  TDirectory.CreateDirectory(lRoot);
  try
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := TPath.Combine(lParent, 'mixedcaseroot');
    lWorkspace.fVcs := 'none';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace), g);
    Assert.IsTrue(lRoot = lIdentity.GetValue<string>('root'),
      'The reference resolves filesystem identity rather than retaining a caller spelling.');
  finally
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.GitIdentityPreservesCompleteReferenceContract(aUseWorktree: Boolean);
var
  g: TGarbos;
  lCapabilities: TJSONObject;
  lChanged: TJSONArray;
  lHead: string;
  lIdentity: TJSONObject;
  lLog: string;
  lParent: string;
  lRoot: string;
  lScratch: string;
  lSources: TJSONObject;
  lWorkspace: TWorkspaceSettings;
begin
  lParent := UniqueTempPath('native-analysis-git');
  lRoot := TPath.Combine(lParent, 'repository');
  lScratch := TPath.Combine(lParent, 'capture');
  lLog := TPath.Combine(lParent, 'setup.log');
  TDirectory.CreateDirectory(lRoot);
  TDirectory.CreateDirectory(lScratch);
  try
    RunFixtureGit(lRoot, 'init -q', lLog);
    TFile.WriteAllBytes(TPath.Combine(lRoot, 'Main.pas'), TEncoding.ASCII.GetBytes('unit Main;' + #10));
    RunFixtureGit(lRoot, 'add Main.pas', lLog);
    RunFixtureGit(lRoot, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture', lLog);
    lHead := Trim(RunFixtureGit(lRoot, 'rev-parse HEAD', lLog));
    if aUseWorktree then
    begin
      RunFixtureGit(lRoot, 'worktree add --detach -q ' + QuoteArg(TPath.Combine(lParent, 'linked')) + ' HEAD', lLog);
      lRoot := TPath.Combine(lParent, 'linked');
    end;
    TFile.WriteAllBytes(TPath.Combine(lRoot, 'Extra.pas'), TEncoding.ASCII.GetBytes('unit Extra;' + #10));
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'git';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lScratch), g);
    Assert.AreEqual(10, lIdentity.Count);
    Assert.AreEqual('git', lIdentity.GetValue<string>('vcs'));
    Assert.AreEqual(lRoot, lIdentity.GetValue<string>('root'));
    Assert.AreEqual(lHead, lIdentity.GetValue<string>('head'));
    Assert.AreEqual(lHead, lIdentity.GetValue<string>('revision'));
    Assert.IsTrue(lIdentity.GetValue<Boolean>('dirty'));
    Assert.AreEqual('complete', lIdentity.GetValue<string>('status'));
    RequireJsonArrayKey(lIdentity, 'changed_files', lChanged);
    Assert.AreEqual('["Extra.pas"]', lChanged.ToJSON);
    RequireJsonArrayKey(lIdentity, 'submodules', lChanged);
    Assert.AreEqual('[]', lChanged.ToJSON);
    RequireJsonObjectKey(lIdentity, 'capabilities', lCapabilities);
    Assert.AreEqual(5, lCapabilities.Count);
    Assert.AreEqual('available', lCapabilities.GetValue<string>('revision'));
    Assert.AreEqual('available', lCapabilities.GetValue<string>('status'));
    Assert.AreEqual('available', lCapabilities.GetValue<string>('changed_files'));
    Assert.AreEqual('available', lCapabilities.GetValue<string>('inventory'));
    Assert.AreEqual('available', lCapabilities.GetValue<string>('nested_roots'));
    RequireJsonObjectKey(lIdentity, 'source_inputs', lSources);
    Assert.AreEqual(3, lSources.Count);
    Assert.AreEqual(2, lSources.GetValue<Integer>('file_count'));
    Assert.AreEqual('git-delphi-inputs-with-recursive-submodules', lSources.GetValue<string>('scope'));
    Assert.AreEqual('cd826d938ec41b7eb727cfa9fe9b9f596cce6c6c1db7d2535fee836358f4bf56',
      lSources.GetValue<string>('sha256'));
    Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(lScratch)), 'Capture handles remove only their own scratch files.');
    Assert.AreEqual<NativeInt>(2 + Ord(aUseWorktree), Length(TDirectory.GetFiles(lRoot)),
      'Only the source files and an optional worktree marker belong in the queried workspace.');
  finally
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.GitUnavailableMetadataRetainsTruthfulFallback(aMissingTool: Boolean);
var
  g: TGarbos;
  lCapabilities: TJSONObject;
  lEnvironment: IInterface;
  lIdentity: TJSONObject;
  lParent: string;
  lRoot: string;
  lSources: TJSONObject;
  lWorkspace: TWorkspaceSettings;
begin
  lParent := UniqueTempPath('native-analysis-unavailable-git');
  lRoot := TPath.Combine(lParent, 'repository');
  TDirectory.CreateDirectory(TPath.Combine(lRoot, '.git'));
  try
    TFile.WriteAllBytes(TPath.Combine(lRoot, 'Main.pas'), TEncoding.ASCII.GetBytes('unit Main;' + #10));
    if aMissingTool then
      lEnvironment := SetScopedEnvironmentVariable('PATH', '')
    else
    begin
      // A broken inner marker must not borrow the valid enclosing repository's identity (T-330).
      RunFixtureGit(lParent, 'init -q', TPath.Combine(lParent, 'setup.log'));
      TFile.WriteAllBytes(TPath.Combine(lParent, 'Outer.pas'), TEncoding.ASCII.GetBytes('unit Outer;' + #10));
      RunFixtureGit(lParent, 'add Outer.pas', TPath.Combine(lParent, 'setup.log'));
      RunFixtureGit(lParent, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture',
        TPath.Combine(lParent, 'setup.log'));
    end;
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'git';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lParent), g);
    Assert.AreEqual(11, lIdentity.Count);
    Assert.AreEqual('git', lIdentity.GetValue<string>('vcs'));
    Assert.AreEqual(lRoot, lIdentity.GetValue<string>('root'));
    Assert.AreEqual('unavailable', lIdentity.GetValue<string>('status'));
    Assert.IsTrue(lIdentity.GetValue('head') is TJSONNull);
    Assert.IsTrue(lIdentity.GetValue('revision') is TJSONNull);
    Assert.IsTrue(lIdentity.GetValue('dirty') is TJSONNull);
    Assert.IsTrue(lIdentity.GetValue('changed_files') is TJSONNull);
    Assert.AreEqual('[]', lIdentity.GetValue<TJSONArray>('submodules').ToJSON);
    Assert.IsTrue(Pos('git', LowerCase(lIdentity.GetValue<string>('diagnostic'))) > 0);
    RequireJsonObjectKey(lIdentity, 'capabilities', lCapabilities);
    Assert.AreEqual(5, lCapabilities.Count);
    Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('revision'));
    Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('status'));
    Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('changed_files'));
    Assert.AreEqual('fallback', lCapabilities.GetValue<string>('inventory'));
    Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('nested_roots'));
    RequireJsonObjectKey(lIdentity, 'source_inputs', lSources);
    Assert.AreEqual(3, lSources.Count);
    Assert.AreEqual(1, lSources.GetValue<Integer>('file_count'));
    Assert.AreEqual('filesystem-delphi-inputs', lSources.GetValue<string>('scope'));
  finally
    lEnvironment := nil;
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.GitWithoutSubmodulesAvoidsRecursiveToolStartup;
var
  g: TGarbos;
  lEnvironment: IInterface;
  lIdentity: TJSONObject;
  lLog: string;
  lParent: string;
  lRoot: string;
  lTrace: string;
  lWorkspace: TWorkspaceSettings;
begin
  lParent := UniqueTempPath('native-analysis-no-gitlinks');
  lRoot := TPath.Combine(lParent, 'repository');
  lLog := TPath.Combine(lParent, 'setup.log');
  lTrace := TPath.Combine(lParent, 'git-trace.jsonl');
  TDirectory.CreateDirectory(lRoot);
  try
    RunFixtureGit(lRoot, 'init -q', lLog);
    TFile.WriteAllText(TPath.Combine(lRoot, 'Main.pas'), 'unit Main;', TEncoding.ASCII);
    RunFixtureGit(lRoot, 'add Main.pas', lLog);
    RunFixtureGit(lRoot, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture', lLog);
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'git';
    lEnvironment := SetScopedEnvironmentVariable('GIT_TRACE2_EVENT', lTrace);
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lParent), g);
    lEnvironment := nil;
    Assert.AreEqual('complete', lIdentity.GetValue<string>('status'), lIdentity.ToJSON);
    Assert.AreEqual(1, lIdentity.GetValue<TJSONObject>('source_inputs').GetValue<Integer>('file_count'));
    Assert.IsFalse(lIdentity.GetValue<Boolean>('dirty'));
    Assert.IsTrue(TFile.Exists(lTrace), 'The installed Git must record actual command execution.');
    Assert.IsFalse(Pos('"submodule"', ReadUtf8TextFile(lTrace)) > 0,
      'A workspace without gitlinks must avoid recursive submodule tool startup.');
  finally
    lEnvironment := nil;
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.GitIdentityIncludesInitializedSubmoduleSources(aBrokenMarker: Boolean);
var
  g: TGarbos;
  lChild: string;
  lChildHead: string;
  lIdentity: TJSONObject;
  lLog: string;
  lModule: TJSONObject;
  lModules: TJSONArray;
  lParent: string;
  lRoot: string;
  lScratch: string;
  lSources: TJSONObject;
  lWorkspace: TWorkspaceSettings;
begin
  lParent := UniqueTempPath('native-analysis-submodule');
  lRoot := TPath.Combine(lParent, 'repository');
  lChild := TPath.Combine(lParent, 'child');
  lScratch := TPath.Combine(lParent, 'capture');
  lLog := TPath.Combine(lParent, 'setup.log');
  TDirectory.CreateDirectory(lRoot);
  TDirectory.CreateDirectory(lChild);
  TDirectory.CreateDirectory(lScratch);
  try
    RunFixtureGit(lChild, 'init -q', lLog);
    TFile.WriteAllBytes(TPath.Combine(lChild, 'Child.pas'), TEncoding.ASCII.GetBytes('unit Child;' + #10));
    RunFixtureGit(lChild, 'add Child.pas', lLog);
    RunFixtureGit(lChild, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture', lLog);
    lChildHead := Trim(RunFixtureGit(lChild, 'rev-parse HEAD', lLog));
    RunFixtureGit(lRoot, 'init -q', lLog);
    RunFixtureGit(lRoot, '-c protocol.file.allow=always submodule add -q ' + QuoteArg(lChild) + ' deps/child', lLog);
    RunFixtureGit(lRoot, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qam fixture', lLog);
    TFile.WriteAllBytes(TPath.Combine(lRoot, 'deps/child/Extra.inc'), TEncoding.ASCII.GetBytes('extra'));
    if aBrokenMarker then
    begin
      // This legitimate Git setting prevents parent status from detecting the damaged child itself.
      RunFixtureGit(lRoot, 'config submodule.deps/child.ignore all', lLog);
      // Damage only this isolated submodule: an empty marker must not select its parent Git index (T-330).
      TFile.Delete(TPath.Combine(lRoot, 'deps/child/.git'));
      TDirectory.CreateDirectory(TPath.Combine(lRoot, 'deps/child/.git'));
    end;
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'git';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lScratch), g);
    if aBrokenMarker then
    begin
      Assert.AreEqual('unavailable', lIdentity.GetValue<string>('status'));
      Assert.IsTrue(lIdentity.GetValue('revision') is TJSONNull);
      Assert.IsTrue(lIdentity.GetValue('changed_files') is TJSONNull);
      Assert.AreEqual('fallback', lIdentity.GetValue<TJSONObject>('capabilities').GetValue<string>('inventory'));
      Assert.IsTrue(Pos('workspace', lIdentity.GetValue<string>('diagnostic')) > 0);
      Exit;
    end;
    Assert.AreEqual('complete', lIdentity.GetValue<string>('status'), lIdentity.ToJSON);
    Assert.IsTrue(lIdentity.GetValue<Boolean>('dirty'));
    RequireJsonArrayKey(lIdentity, 'changed_files', lModules);
    Assert.AreEqual(1, lModules.Count);
    Assert.IsTrue('deps/child' = lModules.Items[0].Value);
    RequireJsonArrayKey(lIdentity, 'submodules', lModules);
    Assert.AreEqual(1, lModules.Count);
    lModule := lModules.Items[0] as TJSONObject;
    Assert.AreEqual(3, lModule.Count);
    Assert.AreEqual('deps/child', lModule.GetValue<string>('path'));
    Assert.AreEqual(lChildHead, lModule.GetValue<string>('revision'));
    Assert.AreEqual('clean', lModule.GetValue<string>('state'), 'Git state records the revision relationship.');
    RequireJsonObjectKey(lIdentity, 'source_inputs', lSources);
    Assert.AreEqual(2, lSources.GetValue<Integer>('file_count'));
    Assert.AreEqual('git-delphi-inputs-with-recursive-submodules', lSources.GetValue<string>('scope'));
  finally
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.GitIdentityPreservesExactRecursiveSubmodulePaths(aScenario: Integer);
const
  cChildPath = 'deps/a child żółć (topic)';
  cLeafPath = 'nested β (leaf)';
  cUninitializedPath = 'deps/a child żółć (topic) (tail)';
var
  g: TGarbos;
  lChild: string;
  lChildHead: string;
  lChildRoot: string;
  lExpectedHash: string;
  lExpectedState: string;
  lIdentity: TJSONObject;
  lLeaf: string;
  lLeafHead: string;
  lLog: string;
  lModules: TJSONArray;
  lParent: string;
  lRoot: string;
  lScratch: string;
  lSeed: string;
  lSources: TJSONObject;
  lWorkspace: TWorkspaceSettings;

  procedure AssertModule(aIndex: Integer; const aPath, aRevision, aState: string);
  var
    lModule: TJSONObject;
  begin
    lModule := lModules.Items[aIndex] as TJSONObject;
    Assert.AreEqual(3, lModule.Count);
    Assert.AreEqual(aPath, lModule.GetValue<string>('path'));
    Assert.AreEqual(aRevision, lModule.GetValue<string>('revision'));
    Assert.AreEqual(aState, lModule.GetValue<string>('state'));
  end;

begin
  lParent := UniqueTempPath('sm');
  lLeaf := TPath.Combine(lParent, 'leaf');
  lChild := TPath.Combine(lParent, 'child');
  lSeed := TPath.Combine(lParent, 'seed');
  lRoot := TPath.Combine(lParent, 'repository');
  lScratch := TPath.Combine(lParent, 'capture');
  lLog := TPath.Combine(lParent, 'setup.log');
  TDirectory.CreateDirectory(lLeaf);
  TDirectory.CreateDirectory(lChild);
  TDirectory.CreateDirectory(lSeed);
  TDirectory.CreateDirectory(lScratch);
  try
    RunFixtureGit(lLeaf, 'init -q', lLog);
    TFile.WriteAllBytes(TPath.Combine(lLeaf, 'Leaf.inc'), TEncoding.ASCII.GetBytes('leaf'));
    RunFixtureGit(lLeaf, 'add Leaf.inc', lLog);
    RunFixtureGit(lLeaf, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture', lLog);
    lLeafHead := Trim(RunFixtureGit(lLeaf, 'rev-parse HEAD', lLog));

    RunFixtureGit(lChild, 'init -q', lLog);
    TFile.WriteAllBytes(TPath.Combine(lChild, 'Child.pas'), TEncoding.ASCII.GetBytes('unit Child;' + #10));
    RunFixtureGit(lChild, '-c protocol.file.allow=always submodule add -q ' + QuoteArg(lLeaf) + ' ' +
      QuoteArg(cLeafPath), lLog);
    RunFixtureGit(lChild, 'add .', lLog);
    RunFixtureGit(lChild, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture', lLog);
    lChildHead := Trim(RunFixtureGit(lChild, 'rev-parse HEAD', lLog));

    RunFixtureGit(lSeed, 'init -q', lLog);
    TFile.WriteAllBytes(TPath.Combine(lSeed, 'Main.pas'), TEncoding.ASCII.GetBytes('unit Main;' + #10));
    RunFixtureGit(lSeed, '-c protocol.file.allow=always submodule add -q ' + QuoteArg(lChild) + ' ' +
      QuoteArg(cChildPath), lLog);
    RunFixtureGit(lSeed, '-c protocol.file.allow=always submodule add -q ' + QuoteArg(lLeaf) + ' ' +
      QuoteArg(cUninitializedPath), lLog);
    RunFixtureGit(lSeed, 'add .', lLog);
    RunFixtureGit(lSeed, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture', lLog);
    // Clone without checkout recursion so uninitialized gitlinks are real Git state (T-333).
    RunFixtureGit(lParent, 'clone -q --no-hardlinks --no-recurse-submodules ' + QuoteArg(lSeed) + ' ' +
      QuoteArg(lRoot), lLog);
    lExpectedState := 'clean';
    if aScenario <> 2 then
    begin
      RunFixtureGit(lRoot, '-c protocol.file.allow=always submodule update --init --recursive -- ' +
        QuoteArg(cChildPath), lLog);
      lChildRoot := TPath.Combine(lRoot, cChildPath);
      TFile.WriteAllBytes(TPath.Combine(lChildRoot, 'Extra.inc'), TEncoding.ASCII.GetBytes('extra'));
      if aScenario = 1 then
      begin
        RunFixtureGit(lChildRoot, '-c user.name="DAK Test" -c user.email=dak@example.invalid ' +
          'commit --allow-empty -qm advance', lLog);
        lChildHead := Trim(RunFixtureGit(lChildRoot, 'rev-parse HEAD', lLog));
        lExpectedState := 'modified';
      end else if aScenario = 3 then
      begin
        // Inactive status stops recursion while the populated child still owns source inputs (T-333).
        RunFixtureGit(lRoot, 'config ' + QuoteArg('submodule.' + cChildPath + '.active') + ' false', lLog);
        lExpectedState := 'uninitialized';
      end;
    end else
      lExpectedState := 'uninitialized';

    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'git';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lScratch), g);
    Assert.AreEqual('complete', lIdentity.GetValue<string>('status'), lIdentity.ToJSON);
    RequireJsonArrayKey(lIdentity, 'submodules', lModules);
    if aScenario in [2, 3] then
    begin
      Assert.AreEqual(2, lModules.Count);
      AssertModule(0, cChildPath, lChildHead, lExpectedState);
      AssertModule(1, cUninitializedPath, lLeafHead, 'uninitialized');
      if aScenario = 2 then
        lExpectedHash := '47a1ccde1b3a5946c322e238eac3bf86bc21930a1d5a98686c132cab30f20093'
      else
        lExpectedHash := 'fe9ec688ce2446067a9b09d18b95ccaca5308bc38bdcda2cd8136d97e054ff42';
    end else begin
      Assert.AreEqual(3, lModules.Count);
      AssertModule(0, cChildPath, lChildHead, lExpectedState);
      AssertModule(1, cChildPath + '/' + cLeafPath, lLeafHead, 'clean');
      AssertModule(2, cUninitializedPath, lLeafHead, 'uninitialized');
      lExpectedHash := '0502af2741ce5fbffcb2849c0830d2f776f1a574f7d9e207bc6a180914a2b9a6';
    end;
    RequireJsonObjectKey(lIdentity, 'source_inputs', lSources);
    Assert.AreEqual(3, lSources.Count);
    if aScenario = 2 then
      Assert.AreEqual(1, lSources.GetValue<Integer>('file_count'))
    else if aScenario = 3 then
      Assert.AreEqual(3, lSources.GetValue<Integer>('file_count'))
    else
      Assert.AreEqual(4, lSources.GetValue<Integer>('file_count'));
    Assert.AreEqual('git-delphi-inputs-with-recursive-submodules', lSources.GetValue<string>('scope'));
    // Fixed SHA256 controls include exact UTF-8 relative paths, lengths and bytes for every source.
    Assert.AreEqual(lExpectedHash, lSources.GetValue<string>('sha256'));
  finally
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.SvnUnversionedRootPreservesIndependentFailures;
var
  g: TGarbos;
  lDiagnostic: string;
  lIdentity: TJSONObject;
  lRoot: string;
  lWorkspace: TWorkspaceSettings;
begin
  lRoot := UniqueTempPath('native-svn-unversioned-root');
  TDirectory.CreateDirectory(lRoot);
  try
    TFile.WriteAllText(TPath.Combine(lRoot, 'Main.pas'), 'unit Main;', TEncoding.ASCII);
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'svn';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lRoot), g);
    Assert.AreEqual('unavailable', lIdentity.GetValue<string>('status'));
    Assert.IsTrue(lIdentity.GetValue('revision') is TJSONNull);
    Assert.IsTrue(lIdentity.GetValue('changed_files') is TJSONNull);
    Assert.AreEqual('fallback', lIdentity.GetValue<TJSONObject>('capabilities').GetValue<string>('inventory'));
    Assert.AreEqual(1, lIdentity.GetValue<TJSONObject>('source_inputs').GetValue<Integer>('file_count'));
    Assert.IsTrue(lIdentity.GetValue('dirty') is TJSONNull);
    Assert.AreEqual('filesystem-delphi-inputs',
      lIdentity.GetValue<TJSONObject>('source_inputs').GetValue<string>('scope'));
    lDiagnostic := lIdentity.GetValue<string>('diagnostic');
    Assert.IsTrue(Pos('info --xml ', lDiagnostic) > 0, lDiagnostic);
    Assert.IsTrue(Pos('unexpected svnversion output:', lDiagnostic) > Pos('info --xml ', lDiagnostic), lDiagnostic);
    Assert.IsTrue(Pos('info --xml --depth infinity', lDiagnostic) >
      Pos('unexpected svnversion output:', lDiagnostic), lDiagnostic);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.GitAlternateIndexCannotMasqueradeAsWorkspaceIdentity;
var
  g: TGarbos;
  lEnvironment: IInterface;
  lIdentity: TJSONObject;
  lIndex: string;
  lLog: string;
  lParent: string;
  lRoot: string;
  lWorkspace: TWorkspaceSettings;
begin
  lParent := UniqueTempPath('native-analysis-alternate-index');
  lRoot := TPath.Combine(lParent, 'repository');
  lIndex := TPath.Combine(lParent, 'alternate-index');
  lLog := TPath.Combine(lParent, 'setup.log');
  TDirectory.CreateDirectory(lRoot);
  try
    RunFixtureGit(lRoot, 'init -q', lLog);
    TFile.WriteAllBytes(TPath.Combine(lRoot, 'Main.pas'), TEncoding.ASCII.GetBytes('unit Main;' + #10));
    RunFixtureGit(lRoot, 'add Main.pas', lLog);
    RunFixtureGit(lRoot, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture', lLog);
    lEnvironment := SetScopedEnvironmentVariable('GIT_INDEX_FILE', lIndex);
    RunFixtureGit(lRoot, 'read-tree --empty', lLog);
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'git';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lParent), g);
    Assert.AreEqual('unavailable', lIdentity.GetValue<string>('status'));
    Assert.IsTrue(lIdentity.GetValue('revision') is TJSONNull);
    Assert.IsTrue(lIdentity.GetValue('changed_files') is TJSONNull);
    Assert.IsTrue(Pos('GIT_INDEX_FILE', lIdentity.GetValue<string>('diagnostic')) > 0);
    Assert.IsTrue(lIndex = GetEnvironmentVariable('GIT_INDEX_FILE'), 'Capture must preserve the parent environment.');
    lEnvironment := nil;
    Assert.AreEqual('Main.pas', Trim(RunFixtureGit(lRoot, 'ls-files', lLog)), 'The normal index remains intact.');
  finally
    lEnvironment := nil;
    DeleteTempPath(lParent);
  end;
end;

procedure RunSvnFixtureTool(const aExe, aArguments, aWorkDir, aLogPath: string);
var
  lExitCode: Cardinal;
begin
  Assert.IsTrue(RunProcessWithTimeout(aExe, aArguments, aWorkDir, aLogPath, 30000, lExitCode));
  Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(aLogPath));
end;

procedure RunSvnReferenceCase(aScenario: Integer);
var
  g: TGarbos;
  lCapabilities: TJSONObject;
  lEnvironment: IInterface;
  lExpectedHash: string;
  lExternal: string;
  lExternalSeed: string;
  lIdentity: TJSONObject;
  lLog: string;
  lOldDir: string;
  lParent: string;
  lPathEnvironment: IInterface;
  lRepository: string;
  lRoot: string;
  lSeed: string;
  lSources: TJSONObject;
  lSvn: string;
  lTools: string;
  lUrl: string;
  lWorkspace: TWorkspaceSettings;
  lVersion: TJSONObject;


begin
  lParent := UniqueTempPath('native-analysis-svn-clean');
  lRepository := TPath.Combine(lParent, 'repository');
  lRoot := TPath.Combine(lParent, 'working-copy');
  lSeed := TPath.Combine(lParent, 'seed');
  lLog := TPath.Combine(lParent, 'setup.log');
  lSvn := 'C:\Program Files\TortoiseSVN\bin\svn.exe';
  Assert.IsTrue(TFile.Exists(lSvn), 'Real SVN is required.');
  TDirectory.CreateDirectory(lSeed);
  lOldDir := GetCurrentDir;
  try
    TFile.WriteAllBytes(TPath.Combine(lSeed, 'Main.pas'), TEncoding.ASCII.GetBytes('unit Main;' + #10));
    TFile.WriteAllBytes(TPath.Combine(lSeed, 'Shared.inc'), TEncoding.ASCII.GetBytes('CONST VALUE = 1;' + #10));
    lUrl := 'file:///' + lRepository.Replace('\', '/').Replace(' ', '%20');
    RunSvnFixtureTool(TPath.Combine(ExtractFileDir(lSvn), 'svnadmin.exe'), 'create ' + QuoteArg(lRepository), lParent, lLog);
    RunSvnFixtureTool(lSvn, 'import ' + QuoteArg(lSeed) + ' ' + QuoteArg(lUrl) + ' -m initial', lParent, lLog);
    RunSvnFixtureTool(lSvn, 'checkout ' + QuoteArg(lUrl) + ' ' + QuoteArg(lRoot), lParent, lLog);
    lExpectedHash := '788ca2f20ff2226f83649047cfcaf2b1ba34922091a99b6fbc537f05d92696a8';
    case aScenario of
      1:
      begin
        TFile.WriteAllBytes(TPath.Combine(lRoot, 'Main.pas'), TEncoding.ASCII.GetBytes('unit Main; // modified' + #10));
        RunSvnFixtureTool(lSvn, 'propset dak-test yes ' + QuoteArg(TPath.Combine(lRoot, 'Shared.inc')), lParent, lLog);
        TFile.WriteAllBytes(TPath.Combine(lRoot, 'Unversioned.pas'), TEncoding.ASCII.GetBytes('unit Unversioned;' + #10));
        lExpectedHash := 'f05be79184fcc4c6ba3bd81e84d3e653aa96c9935823395803608b3094214e61';
      end;
      2:
      begin
        TFile.WriteAllBytes(TPath.Combine(lRoot, 'New.pas'), TEncoding.ASCII.GetBytes('unit New;' + #10));
        RunSvnFixtureTool(lSvn, 'add ' + QuoteArg(TPath.Combine(lRoot, 'New.pas')), lParent, lLog);
        RunSvnFixtureTool(lSvn, 'commit ' + QuoteArg(lRoot) + ' -m "revision two"', lParent, lLog);
        lExpectedHash := '9d508a318f3491ba91ada77f84fa3f5d0e18da93380f13dc2200839e0c3972f6';
      end;
      3:
      begin
        lExternal := TPath.Combine(lParent, 'external-repository');
        lExternalSeed := TPath.Combine(lParent, 'external-seed');
        TDirectory.CreateDirectory(lExternalSeed);
        TFile.WriteAllBytes(TPath.Combine(lExternalSeed, 'Vendor.pas'), TEncoding.ASCII.GetBytes('unit Vendor;' + #10));
        RunSvnFixtureTool(TPath.Combine(ExtractFileDir(lSvn), 'svnadmin.exe'), 'create ' + QuoteArg(lExternal), lParent, lLog);
        lExternal := 'file:///' + lExternal.Replace('\', '/').Replace(' ', '%20');
        RunSvnFixtureTool(lSvn, 'import ' + QuoteArg(lExternalSeed) + ' ' + QuoteArg(lExternal) + ' -m external', lParent, lLog);
        RunSvnFixtureTool(lSvn, 'propset svn:externals ' + QuoteArg('external ' + lExternal) + ' ' + QuoteArg(lRoot), lParent, lLog);
        RunSvnFixtureTool(lSvn, 'commit ' + QuoteArg(lRoot) + ' -m "register external"', lParent, lLog);
        RunSvnFixtureTool(lSvn, 'update ' + QuoteArg(lRoot), lParent, lLog);
      end;
      4:
      begin
        lTools := TPath.Combine(lParent, 'tools');
        TDirectory.Copy(ExtractFileDir(lSvn), lTools);
        // Only this isolated tool copy is changed; the installed executable remains untouched.
        TFile.Delete(TPath.Combine(lTools, 'svnversion.exe'));
        Assert.IsFalse(TFile.Exists(TPath.Combine(lTools, 'svnversion.exe')));
        lEnvironment := SetScopedEnvironmentVariable('DAK_SVN_EXE', TPath.Combine(lTools, 'svn.exe'));
        lPathEnvironment := SetScopedEnvironmentVariable('PATH', '');
      end;
      5:
        lEnvironment := SetScopedEnvironmentVariable('DAK_SVN_EXE', TPath.Combine(lParent, 'missing-svn.exe'));
      6, 7:
      begin
        if aScenario = 6 then
          TFile.Delete(TPath.Combine(lRoot, 'Main.pas'))
        else
          RunSvnFixtureTool(lSvn, 'delete ' + QuoteArg(TPath.Combine(lRoot, 'Main.pas')), lParent, lLog);
        Assert.IsFalse(TFile.Exists(TPath.Combine(lRoot, 'Main.pas')));
        lExpectedHash := '03a89dae70bad4c88f42586e01c42e6203f6628aa02fc8f1c93049b44aef640c';
      end;
      8:
      begin
        TFile.WriteAllBytes(TPath.Combine(lRoot, 'New.pas'), TEncoding.ASCII.GetBytes('unit New;' + #10));
        RunSvnFixtureTool(lSvn, 'add ' + QuoteArg(TPath.Combine(lRoot, 'New.pas')), lParent, lLog);
        lExpectedHash := '9d508a318f3491ba91ada77f84fa3f5d0e18da93380f13dc2200839e0c3972f6';
      end;
      9:
      begin
        RunSvnFixtureTool(lSvn, 'update --set-depth empty ' + QuoteArg(lRoot), lParent, lLog);
        Assert.IsFalse(TFile.Exists(TPath.Combine(lRoot, 'Main.pas')));
        Assert.IsFalse(TFile.Exists(TPath.Combine(lRoot, 'Shared.inc')));
        lExpectedHash := 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      end;
      10:
      begin
        lTools := TPath.Combine(lParent, 'tools');
        TDirectory.Copy(ExtractFileDir(lSvn), lTools);
        Assert.IsTrue(SetCurrentDir(lParent));
        Assert.IsFalse(SameFileName(GetCurrentDir, lRoot), 'Caller and SVN working directories must differ.');
        lEnvironment := SetScopedEnvironmentVariable('DAK_SVN_EXE', 'tools\svn.exe');
        lPathEnvironment := SetScopedEnvironmentVariable('PATH', '');
      end;
      11:
      begin
        TFile.Delete(TPath.Combine(lRoot, 'Main.pas'));
        RunSvnFixtureTool(TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\cmd.exe'),
          '/d /c mklink Main.pas Main.pas', lRoot, lLog);
        lExpectedHash := 'd472c021343c7fedb2806eb9b076d4e99f2342d1afe6ea4c7c56df8922206a52';
      end;
    end;
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'svn';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lParent), g);
    Assert.AreEqual('svn', lIdentity.GetValue<string>('vcs'));
    Assert.AreEqual(lRoot, lIdentity.GetValue<string>('root'));
    RequireJsonObjectKey(lIdentity, 'source_inputs', lSources);
    Assert.AreEqual(3, lSources.Count);
    Assert.AreEqual(lExpectedHash, lSources.GetValue<string>('sha256'));
    if aScenario = 11 then
      Assert.AreEqual(1, lSources.GetValue<Integer>('file_count'))
    else if aScenario = 9 then
      Assert.AreEqual(0, lSources.GetValue<Integer>('file_count'))
    else if (aScenario = 1) or (aScenario = 2) or (aScenario = 8) then
      Assert.AreEqual(3, lSources.GetValue<Integer>('file_count'))
    else
      Assert.AreEqual(2, lSources.GetValue<Integer>('file_count'));
    RequireJsonObjectKey(lIdentity, 'capabilities', lCapabilities);
    Assert.AreEqual(5, lCapabilities.Count);
    if aScenario = 11 then
    begin
      Assert.AreEqual('unavailable', lIdentity.GetValue<string>('status'));
      Assert.AreEqual('1', lIdentity.GetValue<string>('revision'));
      Assert.AreEqual(lUrl, lIdentity.GetValue<string>('url'));
      Assert.AreEqual('available', lCapabilities.GetValue<string>('revision'));
      Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('status'));
      Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('changed_files'));
      Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('nested_roots'));
      Assert.AreEqual('fallback', lCapabilities.GetValue<string>('inventory'));
      Assert.IsTrue(lIdentity.GetValue('dirty') is TJSONNull);
      Assert.IsTrue(lIdentity.GetValue('changed_files') is TJSONNull);
      Assert.AreEqual('[]', lIdentity.GetValue<TJSONArray>('externals').ToJSON);
      Assert.AreEqual('filesystem-delphi-inputs', lSources.GetValue<string>('scope'));
      Assert.IsTrue(lIdentity.GetValue<string>('diagnostic') <> '');
      Exit;
    end;
    if aScenario = 5 then
    begin
      Assert.AreEqual('unavailable', lIdentity.GetValue<string>('status'));
      Assert.IsTrue(lIdentity.GetValue('revision') is TJSONNull);
      Assert.IsTrue(lIdentity.GetValue('dirty') is TJSONNull);
      Assert.IsTrue(lIdentity.GetValue('changed_files') is TJSONNull);
      Assert.AreEqual('[]', lIdentity.GetValue<TJSONArray>('externals').ToJSON);
      Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('revision'));
      Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('status'));
      Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('changed_files'));
      Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('nested_roots'));
      Assert.AreEqual('fallback', lCapabilities.GetValue<string>('inventory'));
      Assert.AreEqual('filesystem-delphi-inputs', lSources.GetValue<string>('scope'));
      Assert.IsTrue(Pos('svn', LowerCase(lIdentity.GetValue<string>('diagnostic'))) > 0);
      Exit;
    end;
    Assert.AreEqual((aScenario = 1) or (aScenario in [6, 7, 8]), lIdentity.GetValue<Boolean>('dirty'));
    if aScenario = 1 then
      Assert.AreEqual('["Main.pas","Shared.inc","Unversioned.pas"]', lIdentity.GetValue<TJSONArray>('changed_files').ToJSON)
    else if aScenario in [6, 7] then
      Assert.AreEqual('["Main.pas"]', lIdentity.GetValue<TJSONArray>('changed_files').ToJSON)
    else if aScenario = 8 then
      Assert.AreEqual('["New.pas"]', lIdentity.GetValue<TJSONArray>('changed_files').ToJSON)
    else
      Assert.AreEqual('[]', lIdentity.GetValue<TJSONArray>('changed_files').ToJSON);
    if aScenario = 3 then
      Assert.AreEqual('[{"path":"external"}]', lIdentity.GetValue<TJSONArray>('externals').ToJSON)
    else
      Assert.AreEqual('[]', lIdentity.GetValue<TJSONArray>('externals').ToJSON);
    Assert.AreEqual(lUrl, lIdentity.GetValue<string>('url'));
    Assert.AreEqual(lUrl, lIdentity.GetValue<string>('repository_root'));
    if aScenario = 3 then
      Assert.AreEqual('2', lIdentity.GetValue<string>('root_revision'))
    else
      Assert.AreEqual('1', lIdentity.GetValue<string>('root_revision'));
    Assert.AreEqual<NativeInt>(36, Length(lIdentity.GetValue<string>('repository_uuid')));
    Assert.AreEqual('available', lCapabilities.GetValue<string>('status'));
    Assert.AreEqual('available', lCapabilities.GetValue<string>('changed_files'));
    Assert.AreEqual('available', lCapabilities.GetValue<string>('inventory'));
    Assert.AreEqual('available', lCapabilities.GetValue<string>('nested_roots'));
    Assert.AreEqual('svn-versioned-plus-unversioned-delphi-inputs', lSources.GetValue<string>('scope'));
    if aScenario = 4 then
    begin
      Assert.AreEqual('unavailable', lIdentity.GetValue<string>('status'));
      Assert.IsTrue(lIdentity.GetValue('revision') is TJSONNull);
      Assert.IsNull(lIdentity.GetValue('svnversion'));
      Assert.AreEqual('unavailable', lCapabilities.GetValue<string>('revision'));
      Assert.IsTrue(Pos('svnversion', lIdentity.GetValue<string>('diagnostic')) > 0);
    end else begin
      Assert.AreEqual('complete', lIdentity.GetValue<string>('status'));
      Assert.AreEqual('available', lCapabilities.GetValue<string>('revision'));
      RequireJsonObjectKey(lIdentity, 'svnversion', lVersion);
      Assert.AreEqual(7, lVersion.Count);
      Assert.AreEqual((aScenario = 1) or (aScenario in [6, 7, 8]), lVersion.GetValue<Boolean>('modified'));
      Assert.IsFalse(lVersion.GetValue<Boolean>('switched'));
      Assert.AreEqual(aScenario = 9, lVersion.GetValue<Boolean>('sparse'));
      Assert.AreEqual(lIdentity.GetValue<string>('revision'), lVersion.GetValue<string>('revision'));
      if aScenario = 2 then
        Assert.AreEqual('1:2', lVersion.GetValue<string>('raw'))
      else if aScenario = 3 then
        Assert.AreEqual('2', lVersion.GetValue<string>('raw'))
      else if aScenario = 9 then
        Assert.AreEqual('1P', lVersion.GetValue<string>('raw'))
      else if (aScenario = 1) or (aScenario in [6, 7, 8]) then
        Assert.AreEqual('1M', lVersion.GetValue<string>('raw'))
      else
        Assert.AreEqual('1', lVersion.GetValue<string>('raw'));
      if aScenario = 2 then
      begin
        Assert.AreEqual('1:2', lIdentity.GetValue<string>('revision'));
        Assert.AreEqual(1, lVersion.GetValue<Integer>('minimum'));
        Assert.AreEqual(2, lVersion.GetValue<Integer>('maximum'));
      end else if aScenario <> 3 then
      begin
        Assert.AreEqual('1', lIdentity.GetValue<string>('revision'));
        Assert.AreEqual(1, lVersion.GetValue<Integer>('minimum'));
        Assert.AreEqual(1, lVersion.GetValue<Integer>('maximum'));
      end;
    end;
  finally
    lPathEnvironment := nil;
    lEnvironment := nil;
    Assert.IsTrue(SetCurrentDir(lOldDir), 'Restore the caller directory before fixture deletion.');
    if (aScenario = 11) and
      (GetFileAttributes(PChar(TPath.Combine(lRoot, 'Main.pas'))) <> INVALID_FILE_ATTRIBUTES) then
      Assert.IsTrue(Winapi.Windows.DeleteFile(PChar(TPath.Combine(lRoot, 'Main.pas'))),
        'Unlink the looping fixture before RTL recursive directory cleanup.');
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeAnalysisWorkspaceTests.SvnCleanWorkspacePreservesReferenceContract;
begin
  RunSvnReferenceCase(0);
end;

procedure TNativeAnalysisWorkspaceTests.SvnWorkspacePreservesPartialAndChangedReferenceCases(aScenario: Integer);
begin
  RunSvnReferenceCase(aScenario);
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisWorkspaceTests);

end.
