unit Test.NativeAnalysisWorkspace.Provenance;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TNativeRunProvenanceTests = class
  public
    [TestCase('SeparateRepositories', '0')]
    [TestCase('SharedRepository', '1')]
    [TestCase('MissingGit', '2')]
    [TestCase('UnmanagedExecutable', '3')]
    [TestCase('MissingExecutable', '4')]
    [TestCase('UnavailableTargetWithHealthyRootMetadata', '5')]
    procedure CapturePreservesTargetAndExecutableEvidence(aScenario: Integer);
    [Test]
    procedure CaptureInsideWorkspaceDoesNotChangeReportedStatus;
    [Test]
    procedure CaptureSvnTargetDoesNotBorrowOuterGitIdentity;
    [TestCase('Empty', '0')]
    [TestCase('PaddingBoundary', '55')]
    [TestCase('BlockBoundary', '64')]
    [TestCase('BufferBoundary', '1048576')]
    [TestCase('MultipleBuffers', '1048593')]
    procedure ExecutableHashPreservesCompleteBinaryContents(aSize: Integer);
    [Test]
    procedure ExecutableHashPreservesLockedFileFailure;
  end;

implementation

uses
  System.Classes, System.Hash, System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.Analysis.Workspace, Dak.Settings,
  Test.Support;

function RunGitFixtureCommand(const aRoot, aArguments, aLog: string): string;
var
  lExitCode: Cardinal;
begin
  Assert.IsTrue(RunProcessWithTimeout('C:\Program Files\Git\cmd\git.exe', aArguments, aRoot, aLog, 30000, lExitCode));
  Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(aLog));
  Result := Trim(ReadUtf8TextFile(aLog));
end;

function CommitFixture(const aRoot, aLog: string): string;
var
  lArguments: string;
begin
  Result := '';
  for lArguments in ['init -q', 'add .',
    '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm initial', 'rev-parse HEAD'] do
    Result := RunGitFixtureCommand(aRoot, lArguments, aLog);
end;

procedure TNativeRunProvenanceTests.CapturePreservesTargetAndExecutableEvidence(aScenario: Integer);
const
  cExecutableHash = 'f16d05ec6b29248d2c61adb1e9263f78e4f7bace1b955014a2d17872cfe4064d';
var
  g: TGarbos;
  lChild: string;
  lDak: TJSONObject;
  lDakHead: string;
  lDakRoot: string;
  lEnvironment: IInterface;
  lExe: string;
  lGuid: TGUID;
  lLog: string;
  lOutside: string;
  lParent: string;
  lProvenance: TJSONObject;
  lRoot: string;
  lTarget: TJSONObject;
  lTargetHead: string;
  lWorkspace: TWorkspaceSettings;
begin
  lParent := UniqueTempPath('native-run-provenance');
  lRoot := TPath.Combine(lParent, 'target');
  lDakRoot := TPath.Combine(lParent, 'tool');
  lOutside := '';
  lLog := TPath.Combine(lParent, 'setup.log');
  TDirectory.CreateDirectory(lRoot);
  try
    if (aScenario = 1) or (aScenario = 5) then
      lDakRoot := lRoot;
    if aScenario = 3 then
    begin
      CreateGUID(lGuid);
      // The subprocess TMP/TEMP contract points to the approved outside-Git disposable fixture root.
      lOutside := TPath.Combine(TPath.GetTempPath, 'dak-provenance-' + GUIDToString(lGuid));
      lDakRoot := lOutside;
    end;
    TDirectory.CreateDirectory(lDakRoot);
    lExe := TPath.Combine(lDakRoot, 'DelphiAIKit.exe');
    TFile.WriteAllBytes(lExe, TEncoding.ASCII.GetBytes('fixture'));
    TFile.WriteAllBytes(TPath.Combine(lRoot, 'Main.pas'), TEncoding.ASCII.GetBytes('unit Main;' + #10));
    if aScenario = 2 then
    begin
      TDirectory.CreateDirectory(TPath.Combine(lRoot, '.git'));
      TDirectory.CreateDirectory(TPath.Combine(lDakRoot, '.git'));
      lEnvironment := SetScopedEnvironmentVariable('PATH', '');
    end else begin
      lTargetHead := CommitFixture(lRoot, lLog);
      if (aScenario = 1) or (aScenario = 5) then
        lDakHead := lTargetHead
      else if aScenario <> 3 then
        lDakHead := CommitFixture(lDakRoot, lLog);
    end;
    if aScenario = 5 then
    begin
      lChild := TPath.Combine(lParent, 'child-source');
      TDirectory.CreateDirectory(lChild);
      TFile.WriteAllBytes(TPath.Combine(lChild, 'Child.pas'), TEncoding.ASCII.GetBytes('unit Child;' + #10));
      CommitFixture(lChild, lLog);
      RunGitFixtureCommand(lRoot, '-c protocol.file.allow=always submodule add -q ' + QuoteArg(lChild) + ' deps/child', lLog);
      lDakHead := CommitFixture(lRoot, lLog);
      RunGitFixtureCommand(lRoot, 'config submodule.deps/child.ignore all', lLog);
      // Root metadata stays valid while T-330 rejects the damaged submodule inventory.
      lChild := TPath.Combine(lRoot, 'deps/child/.git');
      TFile.Delete(lChild);
      TDirectory.CreateDirectory(lChild);
    end;
    if aScenario = 4 then
      TFile.Delete(lExe);
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'git';
    GC(lProvenance, CaptureRunProvenance(lWorkspace, lExe, lParent), g);
    Assert.AreEqual(2, lProvenance.Count);
    RequireJsonObjectKey(lProvenance, 'target', lTarget);
    RequireJsonObjectKey(lProvenance, 'dak', lDak);
    Assert.AreEqual(lExe, lDak.GetValue<string>('executable'));
    if aScenario = 4 then
      Assert.IsTrue(lDak.GetValue('executable_sha256') is TJSONNull)
    else
      Assert.AreEqual(cExecutableHash, lDak.GetValue<string>('executable_sha256'));
    if aScenario = 5 then
      Assert.AreEqual(2, lTarget.GetValue<TJSONObject>('source_inputs').GetValue<Integer>('file_count'))
    else
      Assert.AreEqual(1, lTarget.GetValue<TJSONObject>('source_inputs').GetValue<Integer>('file_count'));
    Assert.IsNull(lDak.GetValue('source_inputs'), 'DAK identity must not carry a second source inventory.');
    if aScenario = 2 then
    begin
      Assert.AreEqual('unavailable', lTarget.GetValue<string>('status'));
      Assert.AreEqual('unavailable', lDak.GetValue<string>('status'));
      Assert.AreEqual('fallback', lTarget.GetValue<TJSONObject>('capabilities').GetValue<string>('inventory'));
      Assert.AreEqual('unavailable', lDak.GetValue<TJSONObject>('capabilities').GetValue<string>('inventory'));
      Assert.IsTrue(lDak.GetValue('revision') is TJSONNull);
    end else begin
      if aScenario = 5 then
      begin
        Assert.AreEqual('unavailable', lTarget.GetValue<string>('status'));
        Assert.IsTrue(lTarget.GetValue('revision') is TJSONNull);
      end else begin
        Assert.AreEqual('complete', lTarget.GetValue<string>('status'));
        Assert.AreEqual(lTargetHead, lTarget.GetValue<string>('revision'));
      end;
      if aScenario = 3 then
      begin
        Assert.AreEqual('none', lDak.GetValue<string>('vcs'));
        Assert.AreEqual(3, lDak.Count, 'An installed executable without repository metadata has only its file identity.');
      end else begin
        Assert.AreEqual('complete', lDak.GetValue<string>('status'));
        Assert.AreEqual(lDakHead, lDak.GetValue<string>('revision'));
        Assert.IsNull(lDak.GetValue('root'));
        Assert.IsNull(lDak.GetValue('submodules'));
        Assert.AreEqual(5, lDak.GetValue<TJSONObject>('capabilities').Count);
      end;
    end;
    if aScenario = 1 then
    begin
      lTarget.RemovePair('status').Free;
      lTarget.AddPair('status', 'changed by consumer');
      Assert.AreEqual('complete', lDak.GetValue<string>('status'), 'Target and DAK JSON have independent ownership.');
    end;
  finally
    lEnvironment := nil;
    if lOutside <> '' then
      DeleteTempPath(lOutside);
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeRunProvenanceTests.CaptureSvnTargetDoesNotBorrowOuterGitIdentity;
var
  g: TGarbos;
  lDak: TJSONObject;
  lExecutable: string;
  lHead: string;
  lLog: string;
  lParent: string;
  lProject: string;
  lProvenance: TJSONObject;
  lRoot: string;
  lSettings: TDakSettings;
  lTarget: TJSONObject;
begin
  lParent := UniqueTempPath('native-provenance-svn-boundary');
  lRoot := TPath.Combine(lParent, 'inner-svn');
  lLog := TPath.Combine(lParent, 'setup.log');
  TDirectory.CreateDirectory(lParent);
  try
    lExecutable := TPath.Combine(lParent, 'DelphiAIKit.exe');
    TFile.WriteAllText(lExecutable, 'fixture', TEncoding.ASCII);
    lHead := CommitFixture(lParent, lLog);
    // The real SVN CLI rejects this damaged marker; it must not select the healthy outer Git root.
    TDirectory.CreateDirectory(TPath.Combine(lRoot, '.svn'));
    lProject := TPath.Combine(lRoot, 'App.dproj');
    TFile.WriteAllText(lProject, '<Project/>', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(lRoot, 'Main.pas'), 'unit Main;', TEncoding.ASCII);
    Assert.IsTrue(LoadDakSettings(nil, lProject, nil, 'svn', lSettings), lSettings.fError);
    Assert.AreEqual(lRoot, lSettings.fWorkspace.fRoot);
    GC(lProvenance, CaptureRunProvenance(lSettings.fWorkspace, lExecutable, lParent), g);
    RequireJsonObjectKey(lProvenance, 'target', lTarget);
    RequireJsonObjectKey(lProvenance, 'dak', lDak);
    Assert.AreEqual('svn', lTarget.GetValue<string>('vcs'));
    Assert.AreEqual(lRoot, lTarget.GetValue<string>('root'));
    Assert.AreEqual('unavailable', lTarget.GetValue<string>('status'));
    Assert.IsTrue(lTarget.GetValue('revision') is TJSONNull);
    Assert.AreEqual('git', lDak.GetValue<string>('vcs'));
    Assert.AreEqual('complete', lDak.GetValue<string>('status'));
    Assert.AreEqual(lHead, lDak.GetValue<string>('revision'));
  finally
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeRunProvenanceTests.CaptureInsideWorkspaceDoesNotChangeReportedStatus;
var
  g: TGarbos;
  i: Integer;
  lChanged: TJSONArray;
  lExternal: TJSONObject;
  lIdentity: TJSONObject;
  lLog: string;
  lParent: string;
  lRoot: string;
  lScratch: string;
  lSnapshot: TJSONObject;
  lWorkspace: TWorkspaceSettings;
begin
  lParent := UniqueTempPath('native-provenance-scratch');
  lRoot := TPath.Combine(lParent, 'target');
  lLog := TPath.Combine(lParent, 'setup.log');
  lScratch := TPath.Combine(lRoot, '.dak/Subject');
  TDirectory.CreateDirectory(lRoot);
  try
    TFile.WriteAllBytes(TPath.Combine(lRoot, 'Main.pas'), TEncoding.ASCII.GetBytes('unit Main;' + #10));
    CommitFixture(lRoot, lLog);
    TFile.WriteAllBytes(TPath.Combine(lParent, 'empty-excludes'), nil);
    RunGitFixtureCommand(lRoot, 'config core.excludesFile ' + QuoteArg(TPath.Combine(lParent, 'empty-excludes')), lLog);
    TDirectory.CreateDirectory(lScratch);
    Assert.AreEqual('', RunGitFixtureCommand(lRoot, 'status --porcelain=v1 --untracked-files=all', lLog));
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'git';
    GC(lIdentity, CaptureWorkspaceIdentity(lWorkspace, lScratch), g);
    Assert.AreEqual('complete', lIdentity.GetValue<string>('status'));
    Assert.AreEqual('[]', lIdentity.GetValue<TJSONArray>('changed_files').ToJSON,
      'Temporary command captures must not appear as user changes.');
    Assert.IsFalse(lIdentity.GetValue<Boolean>('dirty'));
    Assert.AreEqual(1, lIdentity.GetValue<TJSONObject>('source_inputs').GetValue<Integer>('file_count'));
    Assert.AreEqual('', RunGitFixtureCommand(lRoot, 'status --porcelain=v1 --untracked-files=all', lLog));
    // More than one pipe buffer of NUL-separated Git records must survive complete capture.
    for i := 0 to 1499 do
      TFile.WriteAllBytes(TPath.Combine(lRoot, Format('Unit_%.5d_', [i]) + StringOfChar('x', 40) + '.pas'),
        TEncoding.ASCII.GetBytes('unit Source;'));
    TFile.WriteAllBytes(TPath.Combine(lScratch, 'UserNote.txt'), TEncoding.ASCII.GetBytes('keep visible'));
    GC(lSnapshot, CaptureWorkspaceIdentity(lWorkspace, lScratch), g);
    lChanged := lSnapshot.GetValue<TJSONArray>('changed_files');
    Assert.AreEqual(1501, lChanged.Count);
    Assert.AreEqual('.dak/Subject/UserNote.txt', lChanged.Items[0].Value,
      'Caller files in scratch must remain visible; only our capture must avoid modifying the workspace.');
    for i := 0 to 1499 do
      Assert.AreEqual(Format('Unit_%.5d_', [i]) + StringOfChar('x', 40) + '.pas', lChanged.Items[i + 1].Value);
    GC(lExternal, CaptureWorkspaceIdentity(lWorkspace, lParent), g);
    Assert.AreEqual(lExternal.ToJSON, lSnapshot.ToJSON,
      'Complete records must agree for internal and external scratch, including source hashes and ordering.');
  finally
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeRunProvenanceTests.ExecutableHashPreservesCompleteBinaryContents(aSize: Integer);
var
  g: TGarbos;
  i: Integer;
  lBytes: TBytes;
  lExecutable: string;
  lExpected: string;
  lIdentity: TJSONObject;
  lRoot: string;
  lWorkspace: TWorkspaceSettings;
begin
  lRoot := UniqueTempPath('native-executable-hash');
  TDirectory.CreateDirectory(lRoot);
  try
    lExecutable := TPath.Combine(lRoot, #$03BB + ' engine.exe');
    SetLength(lBytes, aSize);
    for i := 0 to High(lBytes) do
      lBytes[i] := Byte(i mod 251);
    TFile.WriteAllBytes(lExecutable, lBytes);
    lExpected := THashSHA2.GetHashStringFromFile(lExecutable);
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'none';
    GC(lIdentity, CaptureRunProvenance(lWorkspace, lExecutable, lRoot), g);
    Assert.AreEqual(lExpected, lIdentity.GetValue<TJSONObject>('dak').GetValue<string>('executable_sha256'));
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeRunProvenanceTests.ExecutableHashPreservesLockedFileFailure;
var
  g: TGarbos;
  lExecutable: string;
  lFailed: Boolean;
  lIdentity: TJSONObject;
  lLock: TFileStream;
  lRoot: string;
  lWorkspace: TWorkspaceSettings;
begin
  lRoot := UniqueTempPath('native-executable-lock');
  TDirectory.CreateDirectory(lRoot);
  try
    lExecutable := TPath.Combine(lRoot, 'engine.exe');
    TFile.WriteAllText(lExecutable, 'locked bytes');
    lWorkspace := Default(TWorkspaceSettings);
    lWorkspace.fRoot := lRoot;
    lWorkspace.fVcs := 'none';
    GC(lLock, TFileStream.Create(lExecutable, fmOpenRead or fmShareExclusive), g);
    lFailed := False;
    try
      GC(lIdentity, CaptureRunProvenance(lWorkspace, lExecutable, lRoot), g);
    except
      on e: EFOpenError do
        lFailed := True;
    end;
    Assert.IsTrue(lFailed, 'A locked executable must fail instead of publishing a partial hash.');
  finally
    g.Clear;
    DeleteTempPath(lRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeRunProvenanceTests);

end.
