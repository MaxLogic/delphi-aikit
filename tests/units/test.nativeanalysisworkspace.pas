unit Test.NativeAnalysisWorkspace;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
    [Test]
    procedure GitAlternateIndexCannotMasqueradeAsWorkspaceIdentity;
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

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisWorkspaceTests);

end.
