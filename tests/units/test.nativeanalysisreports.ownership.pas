unit Test.NativeAnalysisReports.Ownership;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisOwnershipTests = class
  public
    [Test]
    procedure OwnedSourceCannotBeDemotedByPathPolicy;
    [Test]
    procedure ConflictingRootsRemainUnknown;
    [Test]
    procedure RegisteredVendorInsideMaintainedLibraryRemainsThirdParty;
    [Test]
    procedure WorkspaceBoundaryAndProjectMembershipRemainDistinct;
    [Test]
    procedure SourceResolutionUsesOrderedRootsAndRejectsAmbiguousBasenames;
    [Test]
    procedure PalAnnotationPreservesSourceIdentityAcrossReprocessing;
    [Test]
    procedure FixInsightDisplayDoesNotChangeExternalOwnership;
    [Test]
    procedure ContextInventoryExcludesToolStateAndKeepsDelphiInputs;
    [Test]
    procedure ContextInventoryIncludesDirectoryJunctionSources;
    [TestCase('Direct', 'direct')]
    [TestCase('Two hops', 'two')]
    procedure ContextInventoryReportsJunctionCycle(const aMode: string);
    [Test]
    procedure GitContextInventoryKeepsTrackedAndUntrackedButNotIgnoredOrMissing;
    [Test]
    procedure ProjectInventoryReadsRawReferencesWithoutEvaluatingConditions;
    [TestCase('Truncated', '<Project>')]
    [TestCase('Bad close', '<Project></Other>')]
    procedure MalformedProjectRetainsSubjectPathsAndEvidence(const aXml: string);
    [Test]
    procedure SavedContextConnectsProjectInventoryAndPolicyRoots;
    [TestCase('Git submodules', 'submodules')]
    [TestCase('SVN externals', 'externals')]
    procedure SavedNestedRootsOverrideProjectMembership(const aField: string);
    [TestCase('CRLF', 'crlf')]
    [TestCase('CR', 'cr')]
    [TestCase('LF', 'lf')]
    procedure GitmodulesSuppliesNestedRootsWithoutSavedProvenance(const aLineEnding: string);
    [Test]
    procedure MaintainedRootFindsOnlyDeeperVendorsFromAncestor;
    [Test]
    procedure PalSearchRootsUseLastCommandAndPreserveOrder;
    [TestCase('Linked project', 'project')]
    [TestCase('Linked subject', 'subject')]
    procedure LinkedContextKeepsLexicalDirectoryAndPhysicalIdentities(const aMode: string);
    [TestCase('Original', 'complete-rows.json')]
    [TestCase('Policy project case null', 'extended-rows.json')]
    procedure CompleteRowsMatchPinnedPythonReference(const aFixture: string);
  end;

implementation

uses
  System.IOUtils, System.JSON, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  Dak.Analysis.Ownership, Dak.Analysis.OwnershipContext, Dak.Analysis.ProjectSources,
  Dak.Analysis.SourceResolution, Dak.Analysis.Workspace,
  Test.Support;

procedure TNativeAnalysisOwnershipTests.LinkedContextKeepsLexicalDirectoryAndPhysicalIdentities(const aMode: string);
var
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lExitCode: Cardinal;
  lExternal: string;
  lExpectedOwnership: string;
  lLink: string;
  lLocal: string;
  lLog: string;
  lPath: string;
  lResolver: TAnalysisSourceResolver;
  lRoot: string;
  lRows: TJSONArray;
  lSeed: TJSONObject;
  lSubject: TJSONObject;
  lTarget: string;
  lWorkspace: string;
begin
  lRoot := UniqueTempPath('ownership-linked-context');
  lWorkspace := TPath.Combine(lRoot, 'repo');
  lLocal := TPath.Combine(lWorkspace, 'project');
  lExternal := TPath.Combine(lRoot, 'external');
  lLog := TPath.Combine(lRoot, 'link.log');
  TDirectory.CreateDirectory(lLocal);
  TDirectory.CreateDirectory(lExternal);
  if aMode = 'project' then
  begin
    lLink := TPath.Combine(lLocal, 'Linked.dproj');
    lTarget := TPath.Combine(lExternal, 'Real.dproj');
    lExpectedOwnership := 'project';
  end else begin
    lLink := TPath.Combine(lLocal, 'Linked.pas');
    lTarget := TPath.Combine(lExternal, 'Real.pas');
    lExpectedOwnership := 'repository';
  end;
  try
    TFile.WriteAllText(TPath.Combine(lLocal, 'Unit.pas'), 'unit LocalUnit;');
    TFile.WriteAllText(TPath.Combine(lExternal, 'Unit.pas'), 'unit ExternalUnit;');
    if aMode = 'project' then
      TFile.WriteAllText(lTarget,
        '<Project><ItemGroup><DCCReference Include="Unit.pas"/></ItemGroup></Project>')
    else
      TFile.WriteAllText(lTarget, 'unit RealSubject;');
    Assert.IsTrue(RunProcessWithTimeout(GetEnvironmentVariable('COMSPEC'),
      '/d /c mklink ' + QuoteArg(lLink) + ' ' + QuoteArg(lTarget),
      lRoot, lLog, 30000, lExitCode));
    Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(lLog));
    lSeed := TJSONObject.Create;
    try
      lSubject := TJSONObject.Create.AddPair('path', lLink);
      lSeed.AddPair('subject', lSubject);
      if aMode = 'project' then
        lSubject.AddPair('project_file', lLink);
      lSeed.AddPair('workspace', TJSONObject.Create
        .AddPair('root', lWorkspace).AddPair('vcs', 'none'));
      lContext := BuildAnalysisOwnershipContext(lSeed, lRoot, '', lDiagnostics);
      Assert.AreEqual<NativeInt>(0, Length(lDiagnostics), string.Join('; ', lDiagnostics));
      Assert.AreEqual(lLocal, lContext.fProjectDirectory);
      Assert.AreEqual(lLink, lSubject.GetValue<string>('path'));
      if aMode = 'project' then
        Assert.AreEqual<NativeInt>(2, Length(lContext.fProjectFiles))
      else
        Assert.AreEqual<NativeInt>(1, Length(lContext.fProjectFiles));
      Assert.IsTrue(System.StrUtils.MatchText(ResolveFilesystemPath(lTarget), lContext.fProjectFiles));
      for lPath in lContext.fProjectFiles do
        Assert.IsFalse(SameText(lPath, ResolveFilesystemPath(TPath.Combine(lExternal, 'Unit.pas'))));
      if aMode = 'project' then
        Assert.IsTrue(System.StrUtils.MatchText(
          ResolveFilesystemPath(TPath.Combine(lLocal, 'Unit.pas')), lContext.fProjectFiles));
      lResolver := TAnalysisSourceResolver.Create(lContext);
      try
        Assert.AreEqual(ResolveFilesystemPath(TPath.Combine(lLocal, 'Unit.pas')),
          lResolver.Resolve('Unit.pas'));
        lRows := TJSONArray.Create;
        try
          lRows.Add(TJSONObject.Create.AddPair('path', 'Unit.pas'));
          lResolver.AnnotatePal(lRows);
          Assert.AreEqual('Unit.pas', TJSONObject(lRows.Items[0]).GetValue<string>('source_path'));
          Assert.AreEqual('project/Unit.pas', TJSONObject(lRows.Items[0]).GetValue<string>('path'));
          Assert.AreEqual(lExpectedOwnership, TJSONObject(lRows.Items[0]).GetValue<string>('ownership'));
        finally
          lRows.Free;
        end;
      finally
        lResolver.Free;
      end;
    finally
      lSeed.Free;
    end;
  finally
    if TFile.Exists(lLink) then
    begin
      Assert.IsTrue(Winapi.Windows.DeleteFile(PChar(lLink)));
      Assert.IsTrue(TFile.Exists(lTarget), 'Unlink must retain the physical target');
    end;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.CompleteRowsMatchPinnedPythonReference(const aFixture: string);
var
  i: Integer;
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lDocument: TJSONObject;
  lExpected: TJSONArray;
  lFiles: TJSONObject;
  lPair: TJSONPair;
  lKind: string;
  lPath: string;
  lResolver: TAnalysisSourceResolver;
  lRoot: string;
  lRows: TJSONArray;
  lText: string;
begin
  lRoot := UniqueTempPath('ownership-reference-rows');
  for lPath in ['repo\project', 'repo\other', 'external', 'output'] do
    TDirectory.CreateDirectory(TPath.Combine(lRoot, lPath));
  try
    for lPath in ['repo\project\Main.pas', 'repo\project\Dupe.pas',
      'repo\other\Dupe.pas', 'external\Main.pas'] do
      TFile.WriteAllText(TPath.Combine(lRoot, lPath), 'unit Fixture;');
    lText := TFile.ReadAllText(TPath.Combine(RepoRoot,
      'tests\fixtures\native-analysis-ownership\' + aFixture), TEncoding.UTF8);
    lText := lText.Replace('@ROOT_WIN@', lRoot.Replace('\', '\\'))
      .Replace('@ROOT_POSIX@', lRoot.Replace('\', '/'));
    lDocument := ParseJsonObject(lText);
    try
      lFiles := lDocument.GetValue<TJSONObject>('files', nil);
      if lFiles <> nil then
        for lPair in lFiles do
        begin
          lPath := TPath.Combine(lRoot, lPair.JsonString.Value);
          TDirectory.CreateDirectory(TPath.GetDirectoryName(lPath));
          TFile.WriteAllText(lPath, lPair.JsonValue.Value, TEncoding.UTF8);
        end;
      lContext := BuildAnalysisOwnershipContext(lDocument.GetValue<TJSONObject>('seed'),
        TPath.Combine(lRoot, 'output'), '', lDiagnostics);
      Assert.AreEqual<NativeInt>(0, Length(lDiagnostics), string.Join('; ', lDiagnostics));
      lResolver := TAnalysisSourceResolver.Create(lContext);
      try
        for lKind in ['fi', 'pal'] do
        begin
          lRows := lDocument.GetValue<TJSONObject>('input').GetValue<TJSONArray>(lKind);
          lExpected := lDocument.GetValue<TJSONObject>('expected').GetValue<TJSONArray>(lKind);
          for i := 1 to 3 do
          begin
            if lKind = 'fi' then
              lResolver.AnnotateFixInsight(lRows)
            else
              lResolver.AnnotatePal(lRows);
            Assert.AreEqual(lExpected.ToJSON, lRows.ToJSON, lKind + ' complete ordered rows');
          end;
        end;
      finally
        lResolver.Free;
      end;
    finally
      lDocument.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.PalSearchRootsUseLastCommandAndPreserveOrder;
var
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lRoot: string;
  lSeed: TJSONObject;
  lText: string;
begin
  lRoot := UniqueTempPath('ownership-pal-search');
  TDirectory.CreateDirectory(TPath.Combine(lRoot, 'first path'));
  TDirectory.CreateDirectory(TPath.Combine(lRoot, 'relative'));
  TDirectory.CreateDirectory(TPath.Combine(lRoot, 'last'));
  lSeed := TJSONObject.Create;
  try
    lSeed.AddPair('subject', TJSONObject.Create.AddPair('path', TPath.Combine(lRoot, 'Main.pas')));
    lText := 'CMD: palcmd.exe /S=obsolete'#13#10 +
      'CMD: PALCMD.EXE /S="' + TPath.Combine(lRoot, 'first path') +
      ';missing;relative;' + TPath.Combine(lRoot, 'first path') + '" /S=last'#13#10 +
      'CMD: FixInsightCL.exe /S=ignored'#13#10;
    TFile.WriteAllText(TPath.Combine(lRoot, 'run.log'), lText, TEncoding.UTF8);
    lContext := BuildAnalysisOwnershipContext(lSeed, lRoot, '', lDiagnostics);
    Assert.AreEqual<NativeInt>(0, Length(lDiagnostics));
    Assert.AreEqual<NativeInt>(3, Length(lContext.fSearchRoots));
    Assert.AreEqual(TPath.Combine(lRoot, 'first path'), lContext.fSearchRoots[0]);
    Assert.AreEqual(TPath.Combine(lRoot, 'relative'), lContext.fSearchRoots[1]);
    Assert.AreEqual(TPath.Combine(lRoot, 'last'), lContext.fSearchRoots[2]);
    Assert.AreEqual(lText, TFile.ReadAllText(TPath.Combine(lRoot, 'run.log'), TEncoding.UTF8));
    TFile.WriteAllText(TPath.Combine(lRoot, 'run.log'), lText + 'CMD: palcmd.exe /Q'#13#10);
    lContext := BuildAnalysisOwnershipContext(lSeed, lRoot, '', lDiagnostics);
    Assert.AreEqual<NativeInt>(0, Length(lDiagnostics), string.Join('; ', lDiagnostics));
    Assert.AreEqual<NativeInt>(0, Length(lContext.fSearchRoots), 'Last PAL command supersedes prior search roots');
    TFile.WriteAllText(TPath.Combine(lRoot, 'run.log'),
      'CMD: palcmd.exe /s=relative'#13#10'cmd: palcmd.exe /S=last'#13#10);
    lContext := BuildAnalysisOwnershipContext(lSeed, lRoot, '', lDiagnostics);
    Assert.AreEqual<NativeInt>(0, Length(lDiagnostics), string.Join('; ', lDiagnostics));
    Assert.AreEqual<NativeInt>(0, Length(lContext.fSearchRoots), 'Prefix and search switch remain case-sensitive');
  finally
    lSeed.Free;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.OwnedSourceCannotBeDemotedByPathPolicy;
var
  lContext: TAnalysisOwnershipContext;
  lResult: TAnalysisSourceOwnership;
  lRoot: string;
begin
  lRoot := UniqueTempPath('ownership-owned');
  TDirectory.CreateDirectory(lRoot);
  try
    lContext := Default(TAnalysisOwnershipContext);
    lContext.fWorkspaceRoot := lRoot;
    lContext.fProjectDirectory := lRoot;
    lContext.fProjectFiles := [TPath.Combine(lRoot, 'Main.pas')];
    TFile.WriteAllText(lContext.fProjectFiles[0], 'unit Main;');
    SetLength(lContext.fPolicyRoots, 1);
    lContext.fPolicyRoots[0].fOwnership := 'third_party';
    lContext.fPolicyRoots[0].fPath := lRoot;
    lResult := ClassifyAnalysisSource(lContext.fProjectFiles[0], lContext);
    Assert.AreEqual('project', lResult.fOwnership);
    Assert.AreEqual(lRoot, lResult.fRoot);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.ConflictingRootsRemainUnknown;
var
  lContext: TAnalysisOwnershipContext;
  lResult: TAnalysisSourceOwnership;
  lRoot: string;
begin
  lRoot := UniqueTempPath('ownership-conflict');
  TDirectory.CreateDirectory(lRoot);
  try
    lContext := Default(TAnalysisOwnershipContext);
    SetLength(lContext.fPolicyRoots, 2);
    lContext.fPolicyRoots[0].fOwnership := 'project';
    lContext.fPolicyRoots[0].fPath := lRoot;
    lContext.fPolicyRoots[1].fOwnership := 'third_party';
    lContext.fPolicyRoots[1].fPath := lRoot;
    TFile.WriteAllText(TPath.Combine(lRoot, 'Library.pas'), 'unit Library;');
    lResult := ClassifyAnalysisSource(TPath.Combine(lRoot, 'Library.pas'), lContext);
    Assert.AreEqual('unknown', lResult.fOwnership);
    Assert.AreEqual('', lResult.fRoot);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.RegisteredVendorInsideMaintainedLibraryRemainsThirdParty;
var
  lContext: TAnalysisOwnershipContext;
  lResult: TAnalysisSourceOwnership;
  lRoot: string;
  lVendor: string;
begin
  lRoot := UniqueTempPath('ownership-nested');
  lVendor := TPath.Combine(lRoot, 'vendor');
  TDirectory.CreateDirectory(lVendor);
  try
    lContext := Default(TAnalysisOwnershipContext);
    lContext.fNestedRoots := [lVendor];
    SetLength(lContext.fPolicyRoots, 1);
    lContext.fPolicyRoots[0].fOwnership := 'project';
    lContext.fPolicyRoots[0].fPath := lRoot;
    TFile.WriteAllText(TPath.Combine(lVendor, 'Vendor.pas'), 'unit Vendor;');
    lResult := ClassifyAnalysisSource(TPath.Combine(lVendor, 'Vendor.pas'), lContext);
    Assert.AreEqual('third_party', lResult.fOwnership);
    Assert.AreEqual(lVendor, lResult.fRoot);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.WorkspaceBoundaryAndProjectMembershipRemainDistinct;
var
  lContext: TAnalysisOwnershipContext;
  lResult: TAnalysisSourceOwnership;
  lRoot: string;
begin
  lRoot := UniqueTempPath('ownership-boundary');
  TDirectory.CreateDirectory(lRoot);
  try
    lContext := Default(TAnalysisOwnershipContext);
    lContext.fWorkspaceRoot := TPath.Combine(lRoot, 'repo');
    TDirectory.CreateDirectory(lContext.fWorkspaceRoot);
    TFile.WriteAllText(TPath.Combine(lContext.fWorkspaceRoot, 'Extra.pas'), 'unit Extra;');
    lResult := ClassifyAnalysisSource(TPath.Combine(lContext.fWorkspaceRoot, 'Extra.pas'), lContext);
    Assert.AreEqual('repository', lResult.fOwnership);
    Assert.AreEqual(lContext.fWorkspaceRoot, lResult.fRoot);
    TDirectory.CreateDirectory(TPath.Combine(lRoot, 'repo-other'));
    TFile.WriteAllText(TPath.Combine(lRoot, 'repo-other\Extra.pas'), 'unit Extra;');
    lResult := ClassifyAnalysisSource(TPath.Combine(lRoot, 'repo-other\Extra.pas'), lContext);
    Assert.AreEqual('third_party', lResult.fOwnership);
    Assert.AreEqual(TPath.Combine(lRoot, 'repo-other'), lResult.fRoot);
    lResult := ClassifyAnalysisSource('', lContext);
    Assert.AreEqual('unknown', lResult.fOwnership);
    Assert.AreEqual('', lResult.fRoot);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.SourceResolutionUsesOrderedRootsAndRejectsAmbiguousBasenames;
var
  lContext: TAnalysisOwnershipContext;
  lResolver: TAnalysisSourceResolver;
  lRoot: string;
  lProject: string;
  lExtra: string;
begin
  lRoot := UniqueTempPath('ownership-resolution');
  lProject := TPath.Combine(lRoot, 'project');
  lExtra := TPath.Combine(lRoot, 'extra');
  TDirectory.CreateDirectory(lProject);
  TDirectory.CreateDirectory(lExtra);
  try
    TFile.WriteAllText(TPath.Combine(lProject, 'Same.pas'), 'unit Same;');
    TFile.WriteAllText(TPath.Combine(lExtra, 'Same.pas'), 'unit Same;');
    TFile.WriteAllText(TPath.Combine(lExtra, 'Unique.pas'), 'unit Unique;');
    lContext := Default(TAnalysisOwnershipContext);
    lContext.fWorkspaceRoot := lRoot;
    lContext.fWorkspaceFiles := [TPath.Combine(lProject, 'Same.pas'),
      TPath.Combine(lExtra, 'Same.pas'), TPath.Combine(lExtra, 'Unique.pas')];
    lResolver := TAnalysisSourceResolver.Create(lContext);
    try
      Assert.AreEqual(TPath.Combine(lExtra, 'Unique.pas'), lResolver.Resolve('Unique.pas'));
      Assert.AreEqual('', lResolver.Resolve('Same.pas'));
      Assert.AreEqual(TPath.Combine(lExtra, 'Same.pas'), lResolver.Resolve('extra/Same.pas'));
      Assert.AreEqual('', lResolver.Resolve(TPath.Combine(lRoot, 'missing.pas')));
    finally
      lResolver.Free;
    end;
    lContext.fProjectDirectory := lProject;
    lResolver := TAnalysisSourceResolver.Create(lContext);
    try
      Assert.AreEqual(TPath.Combine(lProject, 'Same.pas'), lResolver.Resolve('Same.pas'));
      Assert.AreEqual(TPath.Combine(lExtra, 'Same.pas'),
        lResolver.Resolve(TPath.Combine(lExtra, 'Same.pas')));
    finally
      lResolver.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.PalAnnotationPreservesSourceIdentityAcrossReprocessing;
var
  i: Integer;
  lContext: TAnalysisOwnershipContext;
  lResolver: TAnalysisSourceResolver;
  lRoot: string;
  lLocal: string;
  lExternal: string;
  lRows: TJSONArray;
  lFirst: string;
begin
  lRoot := UniqueTempPath('ownership-pal-replay');
  lLocal := TPath.Combine(lRoot, 'repo\Same.pas');
  lExternal := TPath.Combine(lRoot, 'library\Same.pas');
  TDirectory.CreateDirectory(TPath.GetDirectoryName(lLocal));
  TDirectory.CreateDirectory(TPath.GetDirectoryName(lExternal));
  try
    TFile.WriteAllText(lLocal, 'unit Same;');
    TFile.WriteAllText(lExternal, 'unit Same;');
    lContext := Default(TAnalysisOwnershipContext);
    lContext.fWorkspaceRoot := TPath.GetDirectoryName(lLocal);
    lContext.fWorkspaceFiles := [lLocal];
    lResolver := TAnalysisSourceResolver.Create(lContext);
    lRows := TJSONArray.Create;
    try
      lRows.AddElement(TJSONObject.Create.AddPair('path', lExternal).AddPair('extension', 'keep'));
      lRows.AddElement(TJSONObject.Create.AddPair('path', lLocal));
      lFirst := '';
      for i := 1 to 3 do
      begin
        lResolver.AnnotatePal(lRows);
        Assert.AreEqual(lExternal.Replace('\', '/'), lRows[0].GetValue<string>('path'));
        Assert.AreEqual(lExternal, lRows[0].GetValue<string>('source_path'));
        Assert.AreEqual('third_party', lRows[0].GetValue<string>('ownership'));
        Assert.AreEqual('keep', lRows[0].GetValue<string>('extension'));
        Assert.AreEqual('Same.pas', lRows[1].GetValue<string>('path'));
        Assert.AreEqual('repository', lRows[1].GetValue<string>('ownership'));
        if i = 1 then
          lFirst := lRows.ToJSON
        else
          Assert.AreEqual(lFirst, lRows.ToJSON, 'Complete ordered rows must remain stable');
      end;
    finally
      lRows.Free;
      lResolver.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.FixInsightDisplayDoesNotChangeExternalOwnership;
var
  lContext: TAnalysisOwnershipContext;
  lResolver: TAnalysisSourceResolver;
  lRoot: string;
  lLocal: string;
  lExternal: string;
  lRows: TJSONArray;
  lBefore: string;
begin
  lRoot := UniqueTempPath('ownership-fi-display');
  lLocal := TPath.Combine(lRoot, 'repo\project\Main.pas');
  lExternal := TPath.Combine(lRoot, 'external\Main.pas');
  TDirectory.CreateDirectory(TPath.GetDirectoryName(lLocal));
  TDirectory.CreateDirectory(TPath.GetDirectoryName(lExternal));
  try
    TFile.WriteAllText(lLocal, 'unit Main;');
    TFile.WriteAllText(lExternal, 'unit Main;');
    TDirectory.CreateDirectory(TPath.Combine(lRoot, 'repo\other'));
    TFile.WriteAllText(TPath.Combine(lRoot, 'repo\project\Dupe.pas'), 'unit Dupe;');
    TFile.WriteAllText(TPath.Combine(lRoot, 'repo\other\Dupe.pas'), 'unit Dupe;');
    TFile.WriteAllText(TPath.Combine(lRoot, 'external\Dupe.pas'), 'unit Dupe;');
    lContext := Default(TAnalysisOwnershipContext);
    lContext.fWorkspaceRoot := TPath.Combine(lRoot, 'repo');
    lContext.fProjectDirectory := TPath.GetDirectoryName(lLocal);
    lContext.fWorkspaceFiles := [lLocal, TPath.Combine(lRoot, 'repo\project\Dupe.pas'),
      TPath.Combine(lRoot, 'repo\other\Dupe.pas')];
    lResolver := TAnalysisSourceResolver.Create(lContext);
    lRows := TJSONArray.Create;
    try
      lRows.AddElement(TJSONObject.Create.AddPair('file', lExternal));
      lRows.AddElement(TJSONObject.Create.AddPair('file', 'missing.pas'));
      lRows.AddElement(TJSONObject.Create.AddPair('file', TPath.Combine(lRoot, 'external\Dupe.pas')));
      lRows.AddElement(TJSONObject.Create.AddPair('file', '../missing.pas'));
      lRows.AddElement(TJSONObject.Create.AddPair('file', './a/../missing.pas'));
      lRows.AddElement(TJSONObject.Create.AddPair('file', ''));
      lRows.AddElement(TJSONObject.Create.AddPair('file', lLocal));
      lResolver.AnnotateFixInsight(lRows);
      Assert.IsNotNull(lRows[0].FindValue('path'), 'FI annotation must produce the display path');
      Assert.AreEqual('project/Main.pas', lRows[0].GetValue<string>('path'));
      Assert.AreEqual(lExternal, lRows[0].GetValue<string>('file'));
      Assert.AreEqual('third_party', lRows[0].GetValue<string>('ownership'));
      Assert.AreEqual('project/missing.pas', lRows[1].GetValue<string>('path'));
      Assert.AreEqual('unknown', lRows[1].GetValue<string>('ownership'));
      Assert.IsTrue(lRows[1].GetValue<TJSONValue>('ownership_root') is TJSONNull);
      // Characterized against all seven retained Python display inputs; no new behavior claimed.
      Assert.AreEqual(TPath.Combine(lRoot, 'external/Dupe.pas').Replace('\', '/'),
        lRows[2].GetValue<string>('path'));
      Assert.AreEqual('missing.pas', lRows[3].GetValue<string>('path'));
      Assert.AreEqual('project/missing.pas', lRows[4].GetValue<string>('path'));
      Assert.AreEqual('', lRows[5].GetValue<string>('path'));
      Assert.AreEqual('project/Main.pas', lRows[6].GetValue<string>('path'));
      Assert.AreEqual(7, lRows.Count);
      lBefore := lRows.ToJSON;
      lResolver.AnnotateFixInsight(lRows);
      Assert.AreEqual(lBefore, lRows.ToJSON);
    finally
      lRows.Free;
      lResolver.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.ContextInventoryExcludesToolStateAndKeepsDelphiInputs;
var
  lRoot: string;
  lFiles: TArray<string>;
  lPath: string;
begin
  lRoot := UniqueTempPath('ownership-context-inventory');
  TDirectory.CreateDirectory(lRoot);
  try
    for lPath in ['src', '.dak', '.git', '.svn'] do
      TDirectory.CreateDirectory(TPath.Combine(lRoot, lPath));
    for lPath in ['Main.dpr', 'src\UnitA.pas', 'src\Options.inc', 'src\Library.dpk',
      '.dak\Ignored.pas', '.git\Ignored.pas', '.svn\Ignored.pas', 'src\notes.txt'] do
      TFile.WriteAllText(TPath.Combine(lRoot, lPath), 'fixture');
    lFiles := CollectAnalysisSourcePaths(lRoot, 'none', '');
    Assert.AreEqual<NativeInt>(4, Length(lFiles));
    for lPath in lFiles do
    begin
      Assert.IsTrue(TFile.Exists(lPath));
      Assert.IsFalse(lPath.Contains('\.dak\') or lPath.Contains('\.git\') or
        lPath.Contains('\.svn\') or lPath.EndsWith('.txt'), lPath);
    end;
    lFiles := CollectAnalysisSourcePaths(lRoot, 'svn', '');
    Assert.AreEqual<NativeInt>(4, Length(lFiles), 'SVN ownership uses filesystem inventory');
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.ContextInventoryIncludesDirectoryJunctionSources;
var
  lAlias: string;
  lExitCode: Cardinal;
  lFiles: TArray<string>;
  lJunction: string;
  lLog: string;
  lRoot: string;
  lTarget: string;
  lSymlink: string;
  lWorkspace: string;
begin
  lRoot := UniqueTempPath('ownership-junction');
  lWorkspace := TPath.Combine(lRoot, 'workspace');
  lTarget := TPath.Combine(lRoot, 'target');
  lJunction := TPath.Combine(lWorkspace, 'vendor');
  lAlias := TPath.Combine(lWorkspace, 'vendor-alias');
  lSymlink := TPath.Combine(lWorkspace, 'symbolic-vendor');
  lLog := TPath.Combine(lRoot, 'junction.log');
  TDirectory.CreateDirectory(lWorkspace);
  TDirectory.CreateDirectory(lTarget);
  try
    TFile.WriteAllText(TPath.Combine(lTarget, 'Unique.pas'), 'unit Unique;');
    Assert.IsTrue(RunProcessWithTimeout(GetEnvironmentVariable('COMSPEC'),
      '/d /c mklink /J ' + QuoteArg(lJunction) + ' ' + QuoteArg(lTarget),
      lRoot, lLog, 30000, lExitCode));
    Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(lLog));
    Assert.IsTrue(RunProcessWithTimeout(GetEnvironmentVariable('COMSPEC'),
      '/d /c mklink /D ' + QuoteArg(lSymlink) + ' ' + QuoteArg(lTarget),
      lRoot, lLog, 30000, lExitCode));
    Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(lLog));
    lFiles := CollectAnalysisSourcePaths(lWorkspace, 'none', '');
    Assert.AreEqual<NativeInt>(1, Length(lFiles));
    Assert.AreEqual(ResolveFilesystemPath(TPath.Combine(lTarget, 'Unique.pas')), lFiles[0]);
    Assert.IsTrue(RunProcessWithTimeout(GetEnvironmentVariable('COMSPEC'),
      '/d /c mklink /J ' + QuoteArg(lAlias) + ' ' + QuoteArg(lTarget),
      lRoot, lLog, 30000, lExitCode));
    Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(lLog));
    lFiles := CollectAnalysisSourcePaths(lWorkspace, 'none', '');
    Assert.AreEqual<NativeInt>(2, Length(lFiles), 'Independent aliases retain reference entries');
    Assert.AreEqual(lFiles[0], lFiles[1]);
  finally
    // Remove the junction itself before the fixture helper visits directories.
    if TDirectory.Exists(lJunction) then
      Assert.IsTrue(Winapi.Windows.RemoveDirectory(PChar(lJunction)));
    if TDirectory.Exists(lSymlink) then
      Assert.IsTrue(Winapi.Windows.RemoveDirectory(PChar(lSymlink)));
    if TDirectory.Exists(lAlias) then
      Assert.IsTrue(Winapi.Windows.RemoveDirectory(PChar(lAlias)));
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.ContextInventoryReportsJunctionCycle(const aMode: string);
var
  lExitCode: Cardinal;
  lJunction: string;
  lLog: string;
  lRoot: string;
  lMessage: string;
  lTarget: string;
  lScanRoot: string;
  lReturnLink: string;
begin
  lRoot := UniqueTempPath('ownership-junction-cycle');
  lJunction := TPath.Combine(lRoot, 'back');
  lLog := TPath.Combine(lRoot, 'junction.log');
  lScanRoot := lRoot;
  lTarget := lRoot;
  lReturnLink := '';
  if aMode = 'two' then
  begin
    lScanRoot := TPath.Combine(lRoot, 'workspace');
    lTarget := TPath.Combine(lRoot, 'outside');
    lJunction := TPath.Combine(lScanRoot, 'outward');
    lReturnLink := TPath.Combine(lTarget, 'return');
  end;
  TDirectory.CreateDirectory(lScanRoot);
  TDirectory.CreateDirectory(lTarget);
  try
    Assert.IsTrue(RunProcessWithTimeout(GetEnvironmentVariable('COMSPEC'),
      '/d /c mklink /J ' + QuoteArg(lJunction) + ' ' + QuoteArg(lTarget),
      lRoot, lLog, 30000, lExitCode));
    Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(lLog));
    if lReturnLink <> '' then
    begin
      Assert.IsTrue(RunProcessWithTimeout(GetEnvironmentVariable('COMSPEC'),
        '/d /c mklink /J ' + QuoteArg(lReturnLink) + ' ' + QuoteArg(lScanRoot),
        lRoot, lLog, 30000, lExitCode));
      Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(lLog));
    end;
    lMessage := '';
    try
      CollectAnalysisSourcePaths(lScanRoot, 'none', '');
    except
      on E: EInOutError do
        lMessage := E.Message;
    end;
    Assert.IsTrue(lMessage.Contains('directory junction cycle'), lMessage);
    Assert.IsTrue(lMessage.Contains(lJunction), lMessage);
  finally
    if TDirectory.Exists(lJunction) then
      Assert.IsTrue(Winapi.Windows.RemoveDirectory(PChar(lJunction)));
    if (lReturnLink <> '') and TDirectory.Exists(lReturnLink) then
      Assert.IsTrue(Winapi.Windows.RemoveDirectory(PChar(lReturnLink)));
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.GitContextInventoryKeepsTrackedAndUntrackedButNotIgnoredOrMissing;
var
  lArguments: string;
  lExitCode: Cardinal;
  lFiles: TArray<string>;
  lLog: string;
  lRoot: string;
  lScratch: string;
begin
  lRoot := UniqueTempPath('ownership-context-git');
  lScratch := TPath.Combine(lRoot, '.dak');
  TDirectory.CreateDirectory(lScratch);
  lLog := TPath.Combine(lRoot, 'git-fixture.log');
  try
    TFile.WriteAllText(TPath.Combine(lRoot, '.gitignore'), '*.ignored.pas'#13#10'.dak/'#13#10);
    TFile.WriteAllText(TPath.Combine(lRoot, 'Tracked.pas'), 'unit Tracked;');
    TFile.WriteAllText(TPath.Combine(lRoot, 'Missing.pas'), 'unit Missing;');
    TFile.WriteAllText(TPath.Combine(lScratch, 'empty-excludes'), '');
    for lArguments in ['init -q', 'config core.excludesFile ' +
      QuoteArg(TPath.Combine(lScratch, 'empty-excludes')), 'add Tracked.pas Missing.pas'] do
    begin
      Assert.IsTrue(RunProcessWithTimeout('C:\Program Files\Git\cmd\git.exe',
        lArguments, lRoot, lLog, 30000, lExitCode));
      Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(lLog));
    end;
    TFile.Delete(TPath.Combine(lRoot, 'Missing.pas'));
    TFile.WriteAllText(TPath.Combine(lRoot, 'Untracked.pas'), 'unit Untracked;');
    TFile.WriteAllText(TPath.Combine(lRoot, 'Skip.ignored.pas'), 'unit Ignored;');
    lFiles := CollectAnalysisSourcePaths(lRoot, 'git', lScratch);
    Assert.AreEqual<NativeInt>(2, Length(lFiles));
    Assert.AreEqual(TPath.Combine(lRoot, 'Tracked.pas'), lFiles[0]);
    Assert.AreEqual(TPath.Combine(lRoot, 'Untracked.pas'), lFiles[1]);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.ProjectInventoryReadsRawReferencesWithoutEvaluatingConditions;
var
  lDiagnostic: string;
  lFiles: TArray<string>;
  lPath: string;
  lProject: string;
  lRoot: string;
  lSubject: string;
begin
  lRoot := UniqueTempPath('ownership-project-xml');
  TDirectory.CreateDirectory(lRoot);
  lProject := TPath.Combine(lRoot, 'Sample.dproj');
  lSubject := TPath.Combine(lRoot, 'Sample.dpr');
  try
    for lPath in ['Sample.dpr', 'Always.pas', 'Inactive.pas', 'A&B.pas'] do
      TFile.WriteAllText(TPath.Combine(lRoot, lPath), 'fixture');
    TFile.WriteAllText(lProject, '<ms:Project xmlns:ms="urn:test"><ms:ItemGroup>' +
      '<ms:DCCReference Include="Always.pas"/><ms:DCCReference Include="Always.pas"/>' +
      '<ms:DCCReference Include="Inactive.pas" Condition="false"/>' +
      '<ms:DCCReference Include="A&amp;B.pas"/><ms:DCCReference Include="Missing.pas"/>' +
      '</ms:ItemGroup></ms:Project>');
    lFiles := CollectAnalysisProjectSources(lSubject, lProject, lDiagnostic);
    Assert.AreEqual('', lDiagnostic);
    Assert.AreEqual<NativeInt>(5, Length(lFiles));
    Assert.AreEqual(TPath.Combine(lRoot, 'A&B.pas'), lFiles[0]);
    Assert.AreEqual(TPath.Combine(lRoot, 'Always.pas'), lFiles[1]);
    Assert.AreEqual(TPath.Combine(lRoot, 'Inactive.pas'), lFiles[2]);
    Assert.AreEqual(lSubject, lFiles[3]);
    Assert.AreEqual(lProject, lFiles[4]);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.MalformedProjectRetainsSubjectPathsAndEvidence(const aXml: string);
var
  lDiagnostic: string;
  lFiles: TArray<string>;
  lProject: string;
  lRoot: string;
  lSubject: string;
begin
  lRoot := UniqueTempPath('ownership-project-malformed');
  TDirectory.CreateDirectory(lRoot);
  lProject := TPath.Combine(lRoot, 'Sample.dproj');
  lSubject := TPath.Combine(lRoot, 'Sample.dpr');
  try
    TFile.WriteAllText(lSubject, 'program Sample;');
    TFile.WriteAllText(lProject, aXml);
    lFiles := CollectAnalysisProjectSources(lSubject, lProject, lDiagnostic);
    Assert.IsTrue(lDiagnostic <> '', 'Malformed XML must remain diagnosable');
    Assert.AreEqual<NativeInt>(2, Length(lFiles));
    Assert.AreEqual(lSubject, lFiles[0]);
    Assert.AreEqual(lProject, lFiles[1]);
    Assert.AreEqual(aXml, TFile.ReadAllText(lProject));
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.SavedContextConnectsProjectInventoryAndPolicyRoots;
var
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lLibrary: string;
  lProject: string;
  lResolver: TAnalysisSourceResolver;
  lRoot: string;
  lRows: TJSONArray;
  lSeed: TJSONObject;
  lWorkspace: string;
begin
  lRoot := UniqueTempPath('ownership-saved-context');
  lWorkspace := TPath.Combine(lRoot, 'repo');
  lLibrary := TPath.Combine(lRoot, 'maintained');
  lProject := TPath.Combine(lWorkspace, 'Sample.dproj');
  TDirectory.CreateDirectory(lWorkspace);
  TDirectory.CreateDirectory(lLibrary);
  try
    TFile.WriteAllText(TPath.Combine(lWorkspace, 'Main.pas'), 'unit Main;');
    TFile.WriteAllText(TPath.Combine(lLibrary, 'Library.pas'), 'unit Library;');
    TFile.WriteAllText(lProject, '<Project><DCCReference Include="Main.pas"/></Project>');
    lSeed := TJSONObject.Create;
    try
      lSeed.AddPair('subject', TJSONObject.Create.AddPair('project_file', lProject));
      lSeed.AddPair('workspace', TJSONObject.Create.AddPair('root', lWorkspace).AddPair('vcs', 'none'));
      lSeed.AddPair('policy', TJSONObject.Create.AddPair('values', TJSONObject.Create
        .AddPair('project_roots', TJSONArray.Create.Add(lLibrary))
        .AddPair('third_party_roots', TJSONArray.Create)));
      lContext := BuildAnalysisOwnershipContext(lSeed, TPath.Combine(lRoot, 'output'), '', lDiagnostics);
      Assert.AreEqual(lWorkspace, lContext.fWorkspaceRoot);
      Assert.AreEqual(lWorkspace, lContext.fProjectDirectory);
      Assert.AreEqual<NativeInt>(0, Length(lDiagnostics));
      Assert.AreEqual<NativeInt>(1, Length(lContext.fPolicyRoots));
      lResolver := TAnalysisSourceResolver.Create(lContext);
      lRows := TJSONArray.Create;
      try
        lRows.AddElement(TJSONObject.Create.AddPair('path', 'Main.pas'));
        lRows.AddElement(TJSONObject.Create.AddPair('path', TPath.Combine(lLibrary, 'Library.pas')));
        lResolver.AnnotatePal(lRows);
        Assert.AreEqual('project', lRows[0].GetValue<string>('ownership'));
        Assert.AreEqual('project', lRows[1].GetValue<string>('ownership'));
        Assert.AreEqual(lLibrary.Replace('\', '/'), lRows[1].GetValue<string>('ownership_root'));
      finally
        lRows.Free;
        lResolver.Free;
      end;
    finally
      lSeed.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.SavedNestedRootsOverrideProjectMembership(const aField: string);
var
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lNested: TJSONArray;
  lOwnership: TAnalysisSourceOwnership;
  lProject: string;
  lRoot: string;
  lSeed: TJSONObject;
  lVendor: string;
begin
  lRoot := UniqueTempPath('ownership-nested-context');
  lVendor := TPath.Combine(lRoot, 'vendor');
  lProject := TPath.Combine(lRoot, 'Sample.dproj');
  TDirectory.CreateDirectory(lVendor);
  try
    TFile.WriteAllText(TPath.Combine(lVendor, 'Vendor.pas'), 'unit Vendor;');
    TFile.WriteAllText(lProject, '<Project><DCCReference Include="vendor\Vendor.pas"/></Project>');
    lSeed := TJSONObject.Create;
    try
      lSeed.AddPair('subject', TJSONObject.Create.AddPair('project_file', lProject));
      lSeed.AddPair('workspace', TJSONObject.Create.AddPair('root', lRoot).AddPair('vcs', 'none'));
      lNested := TJSONArray.Create;
      lNested.AddElement(TJSONObject.Create.AddPair('path', 'vendor'));
      lNested.AddElement(TJSONObject.Create.AddPair('path', 'vendor'));
      lSeed.AddPair('provenance', TJSONObject.Create.AddPair('target',
        TJSONObject.Create.AddPair(aField, lNested)));
      lContext := BuildAnalysisOwnershipContext(lSeed, TPath.Combine(lRoot, 'output'), '', lDiagnostics);
      Assert.AreEqual<NativeInt>(1, Length(lContext.fNestedRoots));
      Assert.AreEqual(lVendor, lContext.fNestedRoots[0]);
      lOwnership := ClassifyAnalysisSource(TPath.Combine(lVendor, 'Vendor.pas'), lContext);
      Assert.AreEqual('third_party', lOwnership.fOwnership);
      Assert.AreEqual(lVendor, lOwnership.fRoot);
    finally
      lSeed.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.GitmodulesSuppliesNestedRootsWithoutSavedProvenance(const aLineEnding: string);
var
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lExitCode: Cardinal;
  lLog: string;
  lNewline: string;
  lRoot: string;
  lSeed: TJSONObject;
  lVendor: string;
begin
  lNewline := #13#10;
  if aLineEnding = 'cr' then
    lNewline := #13
  else if aLineEnding = 'lf' then
    lNewline := #10;
  lRoot := UniqueTempPath('ownership-gitmodules-context');
  lVendor := TPath.Combine(lRoot, 'vendor');
  lLog := TPath.Combine(lRoot, 'git-fixture.log');
  TDirectory.CreateDirectory(lVendor);
  TDirectory.CreateDirectory(TPath.Combine(lRoot, '.dak'));
  try
    Assert.IsTrue(RunProcessWithTimeout('C:\Program Files\Git\cmd\git.exe',
      'init -q', lRoot, lLog, 30000, lExitCode));
    Assert.AreEqual<Cardinal>(0, lExitCode, ReadUtf8TextFile(lLog));
    TFile.WriteAllText(TPath.Combine(lVendor, 'Vendor.pas'), 'unit Vendor;');
    TFile.WriteAllText(TPath.Combine(lRoot, '.gitmodules'),
      '[submodule "vendor"]' + lNewline + '  path = vendor' + lNewline + '  path = vendor' + lNewline);
    lSeed := TJSONObject.Create;
    try
      lSeed.AddPair('workspace', TJSONObject.Create.AddPair('root', lRoot).AddPair('vcs', 'git'));
      lContext := BuildAnalysisOwnershipContext(lSeed, TPath.Combine(lRoot, '.dak'), '', lDiagnostics);
      Assert.AreEqual<NativeInt>(0, Length(lDiagnostics), string.Join('; ', lDiagnostics));
      Assert.AreEqual<NativeInt>(1, Length(lContext.fNestedRoots));
      Assert.AreEqual(lVendor, lContext.fNestedRoots[0]);
      Assert.AreEqual('third_party', ClassifyAnalysisSource(
        TPath.Combine(lVendor, 'Vendor.pas'), lContext).fOwnership);
    finally
      lSeed.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisOwnershipTests.MaintainedRootFindsOnlyDeeperVendorsFromAncestor;
var
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lLibrary: string;
  lParent: string;
  lRoot: string;
  lSeed: TJSONObject;
  lVendor: string;
begin
  lRoot := UniqueTempPath('ownership-maintained-boundary');
  lParent := TPath.Combine(lRoot, 'maintained');
  lLibrary := TPath.Combine(lParent, 'src');
  lVendor := TPath.Combine(lLibrary, 'vendor');
  TDirectory.CreateDirectory(lVendor);
  TDirectory.CreateDirectory(TPath.Combine(lParent, 'other'));
  try
    TFile.WriteAllText(TPath.Combine(lLibrary, 'Owned.pas'), 'unit Owned;');
    TFile.WriteAllText(TPath.Combine(lVendor, 'Vendor.pas'), 'unit Vendor;');
    TFile.WriteAllText(TPath.Combine(lParent, '.gitmodules'),
      '[submodule "library"]'#13#10' path = src'#13#10 +
      '[submodule "vendor"]'#13#10' path = src/vendor'#13#10 +
      '[submodule "other"]'#13#10' path = other'#13#10);
    lSeed := TJSONObject.Create;
    try
      lSeed.AddPair('workspace', TJSONObject.Create.AddPair('root', TJSONNull.Create).AddPair('vcs', 'none'));
      lSeed.AddPair('policy', TJSONObject.Create.AddPair('values', TJSONObject.Create
        .AddPair('project_roots', TJSONArray.Create.Add(lLibrary))
        .AddPair('third_party_roots', TJSONArray.Create)));
      lContext := BuildAnalysisOwnershipContext(lSeed, TPath.Combine(lRoot, 'output'), '', lDiagnostics);
      Assert.AreEqual<NativeInt>(1, Length(lContext.fNestedRoots));
      Assert.AreEqual(lVendor, lContext.fNestedRoots[0]);
      Assert.AreEqual('project', ClassifyAnalysisSource(TPath.Combine(lLibrary, 'Owned.pas'), lContext).fOwnership);
      Assert.AreEqual('third_party', ClassifyAnalysisSource(TPath.Combine(lVendor, 'Vendor.pas'), lContext).fOwnership);
    finally
      lSeed.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisOwnershipTests);
end.
