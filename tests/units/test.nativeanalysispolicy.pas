unit Test.NativeAnalysisPolicy;

interface

uses
  System.JSON, System.SysUtils,
  DUnitX.TestFramework;

type
  // The policy controls from test_analysis_policy.py and test_failure_integrity.py, driven through
  // the native finalizer against a real Git working copy and real files on disk.
  [TestFixture]
  TNativeAnalysisPolicyTests = class
  private
    fRoot: string;
    fRepo: string;
    fExternal: string;
    fExternalSource: string;
    fMainSource: string;
    fProject: string;
    fOut: string;
    fEnvironment: IInterface;
    procedure BuildFixture;
    procedure WriteRun(const aFindingPaths: array of string); overload;
    procedure WriteRun(const aFindingPaths: array of string; const aSearchHash: string;
      const aProjectRoots, aThirdPartyRoots: array of string); overload;
    function Finalize(aExpectGatePass: Boolean): string;
    function CreateBaseline: TBytes; overload;
    function CreateBaseline(const aProjectRoots, aThirdPartyRoots: array of string): TBytes; overload;
    function FirstFixInsightRecord: TJSONObject;
    function GateReasonsContain(const aText: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [TestCase('project', 'project,src/Owned.pas,True')]
    [TestCase('repository', 'repository,extras/RepoOnly.pas,True')]
    [TestCase('third_party', 'third_party,<external>,False')]
    procedure DefaultPolicyGatesOwnedButNotThirdPartyFindings(const aOwnership, aPath: string; aExpectFail: Boolean);
    [Test]
    procedure OptionalTotalThresholdRunsAfterOwnershipSelection;
    [Test]
    procedure UnknownOwnershipFailsBeforeFirstBaselineCreation;
    [Test]
    procedure IncompatibleGatedUpdatePreservesBaselineBytes;
    [Test]
    procedure OwnershipContractChangeRejectsLegacyBaselineWithoutReplacingIt;
    [Test]
    procedure CompatibilityExcludesCandidateSourceIdentity;
    [Test]
    procedure VerifyRejectsStaleCompatibilityInAPassingGate;
    [Test]
    procedure RepeatedPublicationDoesNotDuplicateHistory;
    [Test]
    procedure AcceptedUpdateReplacesTheBaselineAndItsMarkdown;
    [Test]
    procedure FixInsightCodeCountsKeepFirstSeenOrder;
    [Test]
    procedure DurableJsonWriteNeverLeavesTheTargetMissing;
    // A baseline records the host release, so a run context that names the release differently
    // than the reference would make every migrated baseline look incompatible.
    [TestCase('windows-11', '10,0,22631,True,11')]
    [TestCase('windows-11-first-build', '10,0,22000,True,11')]
    [TestCase('windows-10', '10,0,19045,True,10')]
    [TestCase('windows-10-first-build', '6,4,0,True,10')]
    [TestCase('windows-8.1', '6,3,9600,True,8.1')]
    [TestCase('server-2022', '10,0,20348,False,2022Server')]
    [TestCase('server-2019', '10,0,17763,False,2019Server')]
    [TestCase('server-2016', '6,4,0,False,2016Server')]
    procedure HostReleaseFollowsTheReferenceWindowsTable(aMajor, aMinor, aBuild: Integer;
      aIsClient: Boolean; const aExpected: string);
    [Test]
    procedure UnitProjectContextParticipatesInCompatibility;
    [TestCase('root', 'root')]
    [TestCase('vcs', 'vcs')]
    [TestCase('status', 'status')]
    [TestCase('inventory_scope', 'inventory_scope')]
    [TestCase('capability', 'capability')]
    [TestCase('external', 'external')]
    procedure WorkspaceSemanticsParticipateInCompatibility(const aMutation: string);
    [Test]
    procedure CandidateWorkspaceIdentityStaysOutOfCompatibility;
    [Test]
    procedure PalFilterOriginParticipatesInCompatibility;
    [TestCase('absolute', 'absolute')]
    [TestCase('relative', 'relative')]
    [TestCase('basename', 'basename')]
    procedure MaintainedExternalRootGatesAllResolvedPathForms(const aForm: string);
    [Test]
    procedure MaintainedRootsPreserveVendorConflictAndOwnedBoundaries;
    [TestCase('absolute', 'absolute')]
    [TestCase('fallback', 'fallback')]
    procedure UnregisteredThirdPartyChildCannotDemoteMaintainedSource(const aForm: string);
    [Test]
    procedure ExternalVendorBoundaryChangeInvalidatesOwnershipCompatibility;
    [Test]
    procedure PolicyRootResolvesOnlyAnOtherwiseUnknownFinding;
    [Test]
    procedure OverlappingPolicyRootsRemainUnknown;
    [Test]
    procedure FailedRunWritesStatusAndPreservesBaselineBytes;
  end;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.StrUtils,
  Winapi.Windows,
  AutoFree,
  Dak.Analysis.JsonText, Dak.Analysis.Ownership, Dak.Analysis.OwnershipContext, Dak.Analysis.ReportBundle,
  Dak.Analysis.ReportReplay, Dak.Analysis.ReportVerify, Dak.Analysis.ReportWriters,
  Dak.Analysis.SourceResolution,
  Test.Support;

const
  // The engine identity the reference pins so the fingerprint does not follow this checkout.
  cCapturedProvenance =
    '{"target": {"head": "fixture", "dirty": false, "submodules": []}, ' +
    '"dak": {"head": "dak-fixture", "executable_sha256": "' +
    '8888888888888888888888888888888888888888888888888888888888888888"}}';

procedure WriteUtf8(const aPath, aText: string);
begin
  TDirectory.CreateDirectory(TPath.GetDirectoryName(aPath));
  TFile.WriteAllBytes(aPath, TEncoding.UTF8.GetBytes(aText));
end;

function ReadUtf8(const aPath: string): string;
begin
  Result := TEncoding.UTF8.GetString(TFile.ReadAllBytes(aPath));
end;

// The fixture needs a real Git working copy, so the executable is resolved from PATH once.
function GitExecutable: string;
begin
  Result := FileSearch('git.exe', GetEnvironmentVariable('PATH'));
  Assert.IsTrue(Result <> '', 'git.exe must be on PATH for the policy fixture');
end;

procedure Git(const aRepo: string; const aArguments: string);
var
  lExitCode: Cardinal;
  lLog: string;
begin
  lLog := TPath.Combine(aRepo, 'git-' + TGUID.NewGuid.ToString + '.log');
  Assert.IsTrue(RunCommandProcess(GitExecutable, aArguments, aRepo, lLog, lExitCode), 'git must run: ' + aArguments);
  Assert.AreEqual<Cardinal>(0, lExitCode, 'git ' + aArguments + ': ' + ReadUtf8(lLog));
  TFile.Delete(lLog);
end;

function Repeated(const aDigit: string): string;
begin
  Result := StringOfChar(aDigit[1], 64);
end;

function JsonQuotedPath(const aPath: string): string;
begin
  Result := aPath.Replace('\', '\\');
end;

{ TNativeAnalysisPolicyTests }

// A reader that shares deletion lets a delete-then-rename replacement destroy the accepted
// document: the delete is accepted, the rename is refused and the file disappears when the reader
// closes. The replacement must therefore be one operation that either succeeds or changes nothing.
// current_fi_counts_by_code is a plain dict filled in row order. history.jsonl writes it in that order
// and baseline.md sorts by count with a stable sort, so equal counts keep first-seen order there too.
// Found by Compare -Area Project: W501 then C101 must not become C101 then W501.
procedure TNativeAnalysisPolicyTests.FixInsightCodeCountsKeepFirstSeenOrder;
var
  g: TGarbos;
  lCodes: TJSONObject;
  lHistory: TJSONObject;
  lLines: TArray<string>;
  lMarkdown: string;
begin
  WriteRun(['src/Owned.pas', 'src/Owned.pas']);
  WriteUtf8(TPath.Combine(fOut, 'fixinsight\fi-findings.jsonl'),
    '{"tool": "FixInsight", "code": "W501", "kind": "W", "file": "src/Owned.pas", "path": "src/Owned.pas", ' +
    '"line": 1, "col": 1, "message": "first"}'#10 +
    '{"tool": "FixInsight", "code": "C101", "kind": "C", "file": "src/Owned.pas", "path": "src/Owned.pas", ' +
    '"line": 2, "col": 1, "message": "second"}'#10);
  Finalize(True);

  lLines := ReadUtf8(TPath.Combine(fOut, 'history.jsonl')).Trim.Split([#10]);
  GC(lHistory, ParseJsonObject(lLines[High(lLines)], 'history.jsonl'), g);
  lCodes := JsonObjectMember(JsonObjectMember(lHistory, 'fixinsight'), 'counts_by_code');
  Assert.AreEqual(2, lCodes.Count, 'counts_by_code');
  Assert.AreEqual('W501', lCodes.Pairs[0].JsonString.Value, 'history keeps the first-seen code first');
  Assert.AreEqual('C101', lCodes.Pairs[1].JsonString.Value);

  lMarkdown := ReadUtf8(TPath.Combine(fOut, 'baseline.md'));
  Assert.IsTrue(Pos('  - W501: 1', lMarkdown) > 0, lMarkdown);
  Assert.IsTrue(Pos('  - W501: 1', lMarkdown) < Pos('  - C101: 1', lMarkdown),
    'baseline.md keeps equal counts in first-seen order: ' + lMarkdown);
end;

procedure TNativeAnalysisPolicyTests.DurableJsonWriteNeverLeavesTheTargetMissing;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lHandle: THandle;
  lPath: string;
begin
  lPath := TPath.Combine(fOut, 'durable.json');
  TFile.WriteAllText(lPath, '{"kept": true}'#13#10);
  lHandle := CreateFile(PChar(lPath), GENERIC_READ,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  Assert.IsFalse(lHandle = INVALID_HANDLE_VALUE, 'the fixture could not open the durable document');
  try
    GC(lDocument, TJSONObject.Create.AddPair('written', TJSONBool.Create(True)), g);
    try
      WriteAnalysisJsonDocument(lPath, lDocument);
    except
      // A refused replacement is acceptable; losing the accepted document is not.
      on E: Exception do
        ;
    end;
  finally
    CloseHandle(lHandle);
  end;
  Assert.IsTrue(TFile.Exists(lPath), 'a refused replacement removed the accepted document');
end;

procedure TNativeAnalysisPolicyTests.HostReleaseFollowsTheReferenceWindowsTable(
  aMajor, aMinor, aBuild: Integer; aIsClient: Boolean; const aExpected: string);
begin
  Assert.AreEqual(aExpected, AnalysisHostRelease(aMajor, aMinor, aBuild, aIsClient));
end;

procedure TNativeAnalysisPolicyTests.Setup;
begin
  fRoot := UniqueNoRepoTempPath('native-analysis-policy');
  TDirectory.CreateDirectory(fRoot);
  // The policy stage reads its controls from the environment; every case starts from a known state.
  fEnvironment := SetScopedEnvironmentVariables(['DAK_BASELINE', '', 'DAK_GATE', '0', 'DAK_CI', '0',
    'DAK_UPDATE_BASELINE', '0', 'DAK_GATE_REQUIRE_CONTEXT_MATCH', '0', 'DAK_GATE_INCLUDE_PATHS', '',
    'DAK_GATE_EXCLUDE_PATHS', '', 'DAK_MAX_FI_TOTAL_INCREASE', '', 'DAK_MAX_PAL_WARNING_INCREASE', '',
    'DAK_MAX_NEW_FI_W', '', 'DAK_MAX_NEW_PAL_STRONG', '', 'DAK_SCOPE', '', 'DAK_TRIAGE_SNIPPETS', '',
    'DAK_TREND_N', '']);
  BuildFixture;
end;

procedure TNativeAnalysisPolicyTests.TearDown;
begin
  fEnvironment := nil;
  if TDirectory.Exists(fRoot) then
    DeleteTempPath(fRoot);
end;

procedure TNativeAnalysisPolicyTests.BuildFixture;
begin
  fRepo := TPath.Combine(fRoot, 'repo');
  fExternal := TPath.Combine(fRoot, 'external');
  TDirectory.CreateDirectory(fRepo);
  TDirectory.CreateDirectory(fExternal);
  Git(fRepo, 'init -q');
  WriteUtf8(TPath.Combine(fRepo, 'src\Owned.pas'), 'unit Owned;'#10);
  WriteUtf8(TPath.Combine(fRepo, 'extras\RepoOnly.pas'), 'unit RepoOnly;'#10);
  fProject := TPath.Combine(fRepo, 'Sample.dproj');
  WriteUtf8(fProject, '<Project><ItemGroup><DCCReference Include="src\Owned.pas"/></ItemGroup></Project>');
  fMainSource := TPath.Combine(fRepo, 'Sample.dpr');
  WriteUtf8(fMainSource, 'program Sample;'#10'uses Owned in ''src\Owned.pas'';'#10'begin'#10'end.'#10);
  WriteUtf8(TPath.Combine(fRepo, '.gitignore'), '.dak/'#10);
  Git(fRepo, 'add .');
  Git(fRepo, '-c user.name="DAK Test" -c user.email=dak@example.invalid commit -qm fixture');
  fExternalSource := TPath.Combine(fExternal, 'External.pas');
  WriteUtf8(fExternalSource, 'unit External;'#10);
  fOut := TPath.Combine(fRepo, '.dak\Sample\policy');
  TDirectory.CreateDirectory(fOut);
end;

procedure TNativeAnalysisPolicyTests.WriteRun(const aFindingPaths: array of string);
begin
  WriteRun(aFindingPaths, '', [], []);
end;

function RootsJson(const aRoots: array of string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(aRoots) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Result := Result + '"' + JsonQuotedPath(aRoots[i]) + '"';
  end;
end;

procedure TNativeAnalysisPolicyTests.WriteRun(const aFindingPaths: array of string; const aSearchHash: string;
  const aProjectRoots, aThirdPartyRoots: array of string);
var
  lFindings: TStringList;
  lPath, lSearch, lTopCodes: string;
begin
  lSearch := aSearchHash;
  if lSearch = '' then
    lSearch := Repeated('1');
  lFindings := TStringList.Create;
  try
    for lPath in aFindingPaths do
      lFindings.Add(Format('{"tool": "FixInsight", "code": "W101", "kind": "W", "file": "%s", "path": "%s", ' +
        '"line": 1, "col": 1, "message": "fixture warning"}', [JsonQuotedPath(lPath), JsonQuotedPath(lPath)]));
    lTopCodes := '';
    if lFindings.Count > 0 then
      lTopCodes := Format('  - W101: %d'#10, [lFindings.Count]);
    WriteUtf8(TPath.Combine(fOut, 'summary.md'),
      '# Static analysis'#10#10 +
      '- Timestamp: 2026-07-17T12:00:00Z'#10 +
      '- Project: `' + fMainSource + '`'#10#10 +
      '## FixInsight'#10#10 +
      Format('- Findings (by code): %d'#10, [lFindings.Count]) + lTopCodes +
      #10'## Pascal Analyzer'#10#10 +
      '- Version: 9.21.3'#10 +
      '- Compiler target: Delphi 13 (Win64)'#10 +
      '- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0'#10);
    WriteUtf8(TPath.Combine(fOut, 'fixinsight\fi-findings.jsonl'),
      String.Join(#10, lFindings.ToStringArray) + IfThen(lFindings.Count > 0, #10, ''));
  finally
    lFindings.Free;
  end;
  WriteUtf8(TPath.Combine(fOut, 'pascal-analyzer\pal-findings.jsonl'), '');
  WriteUtf8(TPath.Combine(fOut, 'run.log'),
    Format('CMD: palcmd.exe "%s" /S="%s" /CD13W64'#10, [fMainSource, TPath.Combine(fRepo, 'src')]));
  WriteUtf8(TPath.Combine(fOut, 'summary.json'),
    '{"schema_version": 2, "status": {"infrastructure": "complete", "policy": "not_evaluated"}, ' +
    '"subject": {"kind": "project", "path": "' + JsonQuotedPath(fMainSource) + '", "project_file": "' +
    JsonQuotedPath(fProject) + '"}, ' +
    '"compiler": {"delphi": "23.0", "platform": "Win64", "config": "Debug", "search_path_sha256": "' + lSearch + '"}, ' +
    '"analyzers": {"fixinsight": {"requested": true, "status": "complete", "version": "2023.12", ' +
    '"options": {"sha256": "' + Repeated('3') + '"}, "count_quality": "complete", "runs": []}, ' +
    '"pascal_analyzer": {"requested": true, "status": "complete", "version": "9.21.3", ' +
    '"options": {"sha256": "' + Repeated('4') + '"}, "count_quality": "complete", "runs": []}}, ' +
    '"inputs": {"project_sha256": "' + Repeated('5') + '", "main_source_sha256": "' + Repeated('6') + '", ' +
    '"config_manifests": [{"path": "' + JsonQuotedPath(TPath.Combine(fRepo, 'dak.ini')) + '", "sha256": "' +
    Repeated('7') + '"}]}, ' +
    '"policy": {"resolver": "Dak.Settings", "values": {"gate_ownership": ["project", "repository"], ' +
    '"project_roots": [' + RootsJson(aProjectRoots) + '], "third_party_roots": [' + RootsJson(aThirdPartyRoots) +
    ']}, "sources": ["' +
    JsonQuotedPath(TPath.Combine(fRepo, 'dak.ini')) + '"], "sha256": "' + Repeated('2') + '"}, ' +
    '"errors": [], "artifacts": {"summary_markdown": "summary.md"}}');
end;

function TNativeAnalysisPolicyTests.Finalize(aExpectGatePass: Boolean): string;
var
  g: TGarbos;
  lProvenance, lResult: TJSONObject;
begin
  GC(lProvenance, ParseJsonObject(cCapturedProvenance, 'captured provenance'), g);
  GC(lResult, FinalizeAnalysisReport(fOut, lProvenance, -1), g);
  Assert.AreEqual(aExpectGatePass, TJSONBool(lResult.GetValue('gate_pass')).AsBoolean,
    'gate_pass; delta reasons: ' + ReadUtf8(TPath.Combine(fOut, 'delta.json')));
  Result := TPythonJson.Document(lResult);
end;

function TNativeAnalysisPolicyTests.CreateBaseline: TBytes;
begin
  Result := CreateBaseline([], []);
end;

function TNativeAnalysisPolicyTests.CreateBaseline(const aProjectRoots, aThirdPartyRoots: array of string): TBytes;
begin
  WriteRun([], '', aProjectRoots, aThirdPartyRoots);
  Finalize(True);
  Result := TFile.ReadAllBytes(TPath.Combine(fOut, 'baseline.json'));
end;

// The caller owns the returned record.
function TNativeAnalysisPolicyTests.FirstFixInsightRecord: TJSONObject;
begin
  Result := ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'fixinsight\fi-findings.jsonl')).Trim.Split([#10])[0],
    'fi-findings.jsonl');
end;

function TNativeAnalysisPolicyTests.GateReasonsContain(const aText: string): Boolean;
var
  g: TGarbos;
  lDelta: TJSONObject;
  lItem: TJSONValue;
begin
  Result := False;
  GC(lDelta, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'delta.json')), 'delta.json'), g);
  for lItem in JsonArrayMember(JsonObjectMember(lDelta, 'gate'), 'reasons') do
    if lItem.Value.ToLowerInvariant.Contains(aText) then
      Result := True;
end;

function PosixPath(const aPath: string): string;
begin
  Result := aPath.Replace('\', '/');
end;

function SnapshotSha(const aSeedText: string): string;
var
  g: TGarbos;
  lSeed, lSnapshot: TJSONObject;
begin
  GC(lSeed, ParseJsonObject(aSeedText, 'seed'), g);
  GC(lSnapshot, AnalysisCompatibilitySnapshot(lSeed, BuildAnalysisPolicyBoundaries(lSeed)), g);
  Result := JsonText(lSnapshot, 'sha256');
  Assert.AreEqual(64, Length(Result), 'the snapshot publishes a SHA-256 fingerprint');
end;

// The workspace seed of test_workspace_semantics_participate_in_compatibility with one field replaced.
function WorkspaceSeed(const aMutation: string): string;
var
  lCapability, lDiagnostic, lDirty, lExternal, lFileCount, lHead, lRoot, lScope, lSha, lStatus, lVcs: string;
begin
  lRoot := 'C:\\work';
  lVcs := 'svn';
  lStatus := 'complete';
  lScope := 'svn-versioned-plus-unversioned-delphi-inputs';
  lCapability := 'available';
  lExternal := 'vendor/external';
  lDirty := 'false';
  lDiagnostic := 'fixture';
  lHead := '';
  lSha := Repeated('2');
  lFileCount := '12';
  if aMutation = 'root' then
    lRoot := 'D:\\work'
  else if aMutation = 'vcs' then
    lVcs := 'none'
  else if aMutation = 'status' then
    lStatus := 'unavailable'
  else if aMutation = 'inventory_scope' then
    lScope := 'filesystem-delphi-inputs'
  else if aMutation = 'capability' then
    lCapability := 'fallback'
  else if aMutation = 'external' then
    lExternal := 'vendor/other'
  else if aMutation = 'candidate' then
  begin
    lDirty := 'true';
    lDiagnostic := 'changed';
    lHead := '"head": "different", ';
    lSha := Repeated('3');
    lFileCount := '99';
  end else if aMutation <> '' then
    Assert.Fail('unknown mutation ' + aMutation);
  // The workspace root stays C:\work inside the target so only the named member changes.
  Result := '{"workspace": {"root": "' + lRoot + '", "vcs": "' + lVcs + '"}, "subject": {"kind": "project"}, ' +
    '"compiler": {}, "analyzers": {}, "inputs": {}, "policy": {"sha256": "' + Repeated('1') + '"}, ' +
    '"provenance": {"target": {' + lHead + '"root": "C:\\work", "vcs": "svn", "status": "' + lStatus + '", ' +
    '"dirty": ' + lDirty + ', "diagnostic": "' + lDiagnostic + '", ' +
    '"source_inputs": {"scope": "' + lScope + '", "sha256": "' + lSha + '", "file_count": ' + lFileCount + '}, ' +
    '"capabilities": {"revision": "available", "status": "available", "inventory": "' + lCapability + '"}, ' +
    '"externals": [{"path": "' + lExternal + '", "revision": "42"}]}, "dak": {}}}';
end;

procedure TNativeAnalysisPolicyTests.UnitProjectContextParticipatesInCompatibility;
const
  cSeed = '{"subject": {"kind": "unit"}, "compiler": {}, "analyzers": {}, ' +
    '"inputs": {"project_context_sha256": "%s"}, "policy": {"sha256": "%s"}, "provenance": %s}';
begin
  Assert.AreNotEqual(SnapshotSha(Format(cSeed, [Repeated('1'), Repeated('2'), cCapturedProvenance])),
    SnapshotSha(Format(cSeed, [Repeated('3'), Repeated('2'), cCapturedProvenance])),
    'a unit fingerprint follows its project context');
end;

procedure TNativeAnalysisPolicyTests.WorkspaceSemanticsParticipateInCompatibility(const aMutation: string);
begin
  Assert.AreNotEqual(SnapshotSha(WorkspaceSeed('')), SnapshotSha(WorkspaceSeed(aMutation)),
    aMutation + ' is part of the compatibility contract');
end;

// Dirty state, diagnostics, revision and inventory content describe the candidate, not the contract.
procedure TNativeAnalysisPolicyTests.CandidateWorkspaceIdentityStaysOutOfCompatibility;
begin
  Assert.AreEqual(SnapshotSha(WorkspaceSeed('')), SnapshotSha(WorkspaceSeed('candidate')));
end;

procedure TNativeAnalysisPolicyTests.PalFilterOriginParticipatesInCompatibility;
const
  cSeed = '{"policy": {"sha256": "%s", "reporting_sha256": "%s", "origins": {"pal_ignore_rules": ["%s"]}}}';
begin
  Assert.AreNotEqual(SnapshotSha(Format(cSeed, [Repeated('1'), Repeated('2'), 'command_line'])),
    SnapshotSha(Format(cSeed, [Repeated('1'), Repeated('2'), 'C:/repo/dak.ini'])),
    'where the PAL filter came from is part of the contract');
end;

// A maintained root outside the repository owns its findings in every path spelling, so the gate
// fails and the accepted baseline stays as it was, run after run.
procedure TNativeAnalysisPolicyTests.MaintainedExternalRootGatesAllResolvedPathForms(const aForm: string);
var
  g: TGarbos;
  lBaseline: TBytes;
  lPath: string;
  lRecord: TJSONObject;
  lRepeat: Integer;
begin
  lBaseline := CreateBaseline([fExternal], []);
  if aForm = 'absolute' then
    lPath := fExternalSource
  else if aForm = 'relative' then
    lPath := '../external/External.pas'
  else
    lPath := 'External.pas';
  WriteRun([lPath], '', [fExternal], []);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  for lRepeat := 1 to 2 do
  begin
    Finalize(False);
    GC(lRecord, FirstFixInsightRecord, g);
    Assert.AreEqual('project', JsonText(lRecord, 'ownership'), 'run ' + lRepeat.ToString);
    Assert.AreEqual(PosixPath(fExternal), JsonText(lRecord, 'ownership_root'), 'run ' + lRepeat.ToString);
    Assert.AreEqual(TEncoding.UTF8.GetString(lBaseline),
      TEncoding.UTF8.GetString(TFile.ReadAllBytes(TPath.Combine(fOut, 'baseline.json'))), 'run ' + lRepeat.ToString);
  end;
end;

// Registered vendors stay third-party inside maintained roots, a root named on both sides stays
// unknown, and a repository marked third-party cannot demote the project's own source. Row order
// and reprocessing change nothing.
procedure TNativeAnalysisPolicyTests.MaintainedRootsPreserveVendorConflictAndOwnedBoundaries;
type
  TExpectedRow = record
    fPath, fOwnership, fRoot: string;
  end;
var
  g: TGarbos;
  lConflict, lMaintained, lRoot: string;
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lExpected: TList<TExpectedRow>;
  lFi, lPal: TJSONArray;
  lOrder, lRepeat, i, lIndex: Integer;
  lResolver: TAnalysisSourceResolver;
  lRow: TExpectedRow;
  lSeed: TJSONObject;

  function Expected(const aPath, aOwnership, aRoot: string): TExpectedRow;
  begin
    Result.fPath := aPath;
    Result.fOwnership := aOwnership;
    Result.fRoot := aRoot;
  end;

begin
  lMaintained := TPath.Combine(fRepo, 'maintained');
  TDirectory.CreateDirectory(lMaintained);
  WriteUtf8(TPath.Combine(fRepo, '.gitmodules'), '[submodule "maintained"]'#10'path = maintained'#10);
  for lRoot in [lMaintained, fExternal] do
  begin
    Git(lRoot, 'init -q');
    WriteUtf8(TPath.Combine(lRoot, 'Library.pas'), 'unit Library;'#10);
    WriteUtf8(TPath.Combine(lRoot, 'vendor\Vendor.pas'), 'unit Vendor;'#10);
    WriteUtf8(TPath.Combine(lRoot, '.gitmodules'), '[submodule "vendor"]'#10'path = vendor'#10);
  end;
  lConflict := TPath.Combine(fExternal, 'conflict');
  WriteUtf8(TPath.Combine(lConflict, 'Conflict.pas'), 'unit Conflict;'#10);
  WriteRun([], '', [lMaintained, fExternal, lConflict], [fRepo, lConflict]);

  GC(lExpected, TList<TExpectedRow>.Create, g);
  for lRoot in [lMaintained, fExternal] do
    lExpected.Add(Expected(TPath.Combine(lRoot, 'Library.pas'), 'project', PosixPath(lRoot)));
  for lRoot in [lMaintained, fExternal] do
    lExpected.Add(Expected(TPath.Combine(lRoot, 'vendor\Vendor.pas'), 'third_party',
      PosixPath(TPath.Combine(lRoot, 'vendor'))));
  lExpected.Add(Expected(TPath.Combine(fRepo, 'src\Owned.pas'), 'project', PosixPath(fRepo)));
  lExpected.Add(Expected(TPath.Combine(lConflict, 'Conflict.pas'), 'unknown', ''));

  GC(lSeed, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'summary.json')), 'summary.json'), g);
  lContext := BuildAnalysisOwnershipContext(lSeed, fOut, fRepo, lDiagnostics);
  GC(lResolver, TAnalysisSourceResolver.Create(lContext), g);
  for lOrder := 0 to 1 do
  begin
    GC(lFi, TJSONArray.Create, g);
    GC(lPal, TJSONArray.Create, g);
    for i := 0 to lExpected.Count - 1 do
    begin
      if lOrder = 0 then
        lRow := lExpected[i]
      else
        lRow := lExpected[lExpected.Count - 1 - i];
      lFi.Add(TJSONObject.Create.AddPair('tool', 'FixInsight').AddPair('code', 'W101').AddPair('kind', 'W')
        .AddPair('file', lRow.fPath).AddPair('path', lRow.fPath).AddPair('line', TJSONNumber.Create(1))
        .AddPair('col', TJSONNumber.Create(1)).AddPair('message', 'fixture warning'));
      lPal.Add(TJSONObject.Create.AddPair('source_path', lRow.fPath));
    end;
    // The second pass reprocesses rows that already carry an annotation.
    for lRepeat := 1 to 2 do
    begin
      lResolver.AnnotateFixInsight(lFi);
      lResolver.AnnotatePal(lPal);
      for i := 0 to lExpected.Count - 1 do
      begin
        if lOrder = 0 then
          lIndex := i
        else
          lIndex := lExpected.Count - 1 - i;
        lRow := lExpected[lIndex];
        Assert.AreEqual(lRow.fOwnership, JsonText(TJSONObject(lFi.Items[i]), 'ownership'), 'FixInsight ' + lRow.fPath);
        Assert.AreEqual(lRow.fRoot, JsonText(TJSONObject(lFi.Items[i]), 'ownership_root'), 'FixInsight ' + lRow.fPath);
        Assert.AreEqual(lRow.fOwnership, JsonText(TJSONObject(lPal.Items[i]), 'ownership'), 'PAL ' + lRow.fPath);
        Assert.AreEqual(lRow.fRoot, JsonText(TJSONObject(lPal.Items[i]), 'ownership_root'), 'PAL ' + lRow.fPath);
      end;
    end;
  end;
end;

// A third-party root nested in a maintained root has no registration behind it, so its source
// cannot be demoted to vendor code: it stays unknown and fails the gate.
procedure TNativeAnalysisPolicyTests.UnregisteredThirdPartyChildCannotDemoteMaintainedSource(const aForm: string);
var
  g: TGarbos;
  lBaseline: TBytes;
  lChild, lPath, lSource: string;
  lRecord: TJSONObject;
begin
  lChild := TPath.Combine(fExternal, 'private');
  lSource := TPath.Combine(lChild, 'Private.pas');
  WriteUtf8(lSource, 'unit Private;'#10);
  lBaseline := CreateBaseline([fExternal], [lChild]);
  if aForm = 'absolute' then
    lPath := lSource
  else
    lPath := 'private/Private.pas';
  WriteRun([lPath], '', [fExternal], [lChild]);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  Finalize(False);
  GC(lRecord, FirstFixInsightRecord, g);
  Assert.AreEqual('unknown', JsonText(lRecord, 'ownership'));
  Assert.AreEqual(TEncoding.UTF8.GetString(lBaseline),
    TEncoding.UTF8.GetString(TFile.ReadAllBytes(TPath.Combine(fOut, 'baseline.json'))), 'baseline.json is unchanged');
end;

// Registering a vendor inside a maintained root changes ownership boundaries, which the accepted
// baseline did not record, so an update is refused.
procedure TNativeAnalysisPolicyTests.ExternalVendorBoundaryChangeInvalidatesOwnershipCompatibility;
var
  lBaseline: TBytes;
begin
  Git(fExternal, 'init -q');
  TDirectory.CreateDirectory(TPath.Combine(fExternal, 'vendor'));
  lBaseline := CreateBaseline([fExternal], []);
  WriteUtf8(TPath.Combine(fExternal, '.gitmodules'), '[submodule "vendor"]'#10'path = vendor'#10);
  WriteRun([], '', [fExternal], []);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));
  Finalize(False);
  Assert.AreEqual(TEncoding.UTF8.GetString(lBaseline),
    TEncoding.UTF8.GetString(TFile.ReadAllBytes(TPath.Combine(fOut, 'baseline.json'))), 'baseline.json is unchanged');
  Assert.IsTrue(GateReasonsContain('compatibility'), 'the reason names the compatibility mismatch');
end;

// A policy root only resolves a finding nothing else could place; here it makes the row third-party.
procedure TNativeAnalysisPolicyTests.PolicyRootResolvesOnlyAnOtherwiseUnknownFinding;
var
  g: TGarbos;
  lRecord: TJSONObject;
begin
  CreateBaseline([], [fExternal]);
  WriteRun(['External.pas'], '', [], [fExternal]);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  Finalize(True);
  GC(lRecord, FirstFixInsightRecord, g);
  Assert.AreEqual('third_party', JsonText(lRecord, 'ownership'));
  Assert.AreEqual(PosixPath(fExternal), JsonText(lRecord, 'ownership_root'));
end;

procedure TNativeAnalysisPolicyTests.OverlappingPolicyRootsRemainUnknown;
var
  g: TGarbos;
  lRecord: TJSONObject;
begin
  WriteRun(['External.pas'], '', [fExternal], [fExternal]);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  Finalize(False);
  GC(lRecord, FirstFixInsightRecord, g);
  Assert.AreEqual('unknown', JsonText(lRecord, 'ownership'));
  Assert.IsFalse(TFile.Exists(TPath.Combine(fOut, 'baseline.json')), 'no baseline is created');
end;

// A failed analyzer run keeps its failure status and never touches the accepted baseline, even
// when an update was requested.
procedure TNativeAnalysisPolicyTests.FailedRunWritesStatusAndPreservesBaselineBytes;
var
  g: TGarbos;
  lAnalyzers, lResult, lStatus: TJSONObject;
  lBaseline, lBaselineMarkdown, lOut: string;
  lBaselineBytes, lMarkdownBytes: TBytes;
begin
  lOut := TPath.Combine(fRoot, 'failed');
  lBaseline := TPath.Combine(lOut, 'accepted\baseline.json');
  lBaselineMarkdown := TPath.Combine(lOut, 'accepted\baseline.md');
  WriteUtf8(lBaseline, '{'#13#10'  "version": 1'#13#10'}'#13#10);
  WriteUtf8(lBaselineMarkdown, 'accepted baseline'#13#10);
  lBaselineBytes := TFile.ReadAllBytes(lBaseline);
  lMarkdownBytes := TFile.ReadAllBytes(lBaselineMarkdown);
  WriteUtf8(TPath.Combine(lOut, 'summary.md'),
    '# Static analysis'#10#10'- Timestamp: 2026-07-15T10:00:00Z'#10'- Project: `C:\work\sample.dproj`'#10#10 +
    '## FixInsight'#10#10'- Findings (by code): 2'#10#10'## Pascal Analyzer'#10#10'- Totals: unavailable'#10#10 +
    '## Errors'#10#10'- FixInsight TXT failed (exit=1).'#10'- Pascal Analyzer failed (exit=99).'#10);
  WriteUtf8(TPath.Combine(lOut, 'summary.json'),
    '{"schema_version": 2, "subject": {"kind": "project", "path": "C:\\work\\sample.dproj"}, ' +
    '"status": {"infrastructure": "failed", "policy": "not_evaluated"}, ' +
    '"analyzers": {"fixinsight": {"requested": true, "status": "failed", "count_quality": "partial"}, ' +
    '"pascal_analyzer": {"requested": true, "status": "failed", "count_quality": "unavailable"}}, ' +
    '"counts": {"fixinsight": {"quality": "partial", "total": 2}, "pascal_analyzer": {"quality": "unavailable"}}, ' +
    '"errors": ["FixInsight TXT failed (exit=1).", "Pascal Analyzer failed (exit=99)."]}');
  SetEnvironmentVariable('DAK_BASELINE', PChar(lBaseline));
  SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));

  GC(lResult, FinalizeAnalysisReport(lOut, nil, -1), g);
  Assert.AreEqual('False', JsonText(lResult, 'gate_pass'), 'gate_pass');
  Assert.AreEqual('False', JsonText(lResult, 'baseline_created'), 'baseline_created');
  Assert.AreEqual('False', JsonText(lResult, 'baseline_updated'), 'baseline_updated');

  GC(lStatus, ParseJsonObject(ReadUtf8(TPath.Combine(lOut, 'summary.json')), 'summary.json'), g);
  Assert.AreEqual('2', JsonText(lStatus, 'schema_version'), 'schema_version');
  Assert.AreEqual('failed', JsonText(JsonObjectMember(lStatus, 'status'), 'infrastructure'));
  Assert.AreEqual('not_evaluated', JsonText(JsonObjectMember(lStatus, 'status'), 'policy'));
  lAnalyzers := JsonObjectMember(lStatus, 'analyzers');
  Assert.AreEqual('partial', JsonText(JsonObjectMember(lAnalyzers, 'fixinsight'), 'count_quality'));
  Assert.AreEqual('unavailable', JsonText(JsonObjectMember(lAnalyzers, 'fixinsight'), 'version'));
  Assert.AreEqual('2', JsonText(JsonObjectMember(JsonObjectMember(lStatus, 'counts'), 'fixinsight'), 'total'));
  Assert.AreEqual('unavailable', JsonText(JsonObjectMember(lAnalyzers, 'pascal_analyzer'), 'count_quality'));
  Assert.AreEqual('unavailable', JsonText(JsonObjectMember(lAnalyzers, 'pascal_analyzer'), 'version'));
  Assert.IsNull(JsonObjectMember(JsonObjectMember(lStatus, 'counts'), 'pascal_analyzer').GetValue('total'),
    'an unavailable PAL count has no total');
  Assert.AreEqual(TEncoding.UTF8.GetString(lBaselineBytes), TEncoding.UTF8.GetString(TFile.ReadAllBytes(lBaseline)),
    'baseline.json is unchanged');
  Assert.AreEqual(TEncoding.UTF8.GetString(lMarkdownBytes),
    TEncoding.UTF8.GetString(TFile.ReadAllBytes(lBaselineMarkdown)), 'baseline.md is unchanged');
end;

// The default gate owns project and repository findings; a third-party finding is reported, not gated.
procedure TNativeAnalysisPolicyTests.DefaultPolicyGatesOwnedButNotThirdPartyFindings(const aOwnership,
  aPath: string; aExpectFail: Boolean);
var
  g: TGarbos;
  lFinding: string;
  lSummary: TJSONObject;
begin
  CreateBaseline;
  lFinding := aPath;
  if lFinding = '<external>' then
    lFinding := fExternalSource;
  WriteRun([lFinding]);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  Finalize(not aExpectFail);
  GC(lSummary, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'summary.json')), 'summary.json'), g);
  Assert.AreEqual(IfThen(aExpectFail, 'fail', 'pass'),
    JsonText(JsonObjectMember(lSummary, 'status'), 'policy'), 'status.policy');
  Assert.AreEqual('1', JsonText(JsonObjectMember(JsonObjectMember(JsonObjectMember(lSummary, 'counts'), 'raw'),
    'ownership'), aOwnership), 'the finding is counted under ' + aOwnership);
end;

// A total-increase threshold is evaluated after ownership selection, so vendor rows cannot trip it.
procedure TNativeAnalysisPolicyTests.OptionalTotalThresholdRunsAfterOwnershipSelection;
var
  g: TGarbos;
  lDelta: TJSONObject;
begin
  CreateBaseline;
  WriteRun([fExternalSource]);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  SetEnvironmentVariable('DAK_MAX_FI_TOTAL_INCREASE', PChar('0'));
  Finalize(True);
  GC(lDelta, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'delta.json')), 'delta.json'), g);
  Assert.AreEqual(0, JsonArrayMember(JsonObjectMember(lDelta, 'fixinsight'), 'top_code_deltas').Count,
    'external FixInsight rows stay out of the actionable deltas');
end;

// An unresolvable finding must fail the gate before any baseline is created.
procedure TNativeAnalysisPolicyTests.UnknownOwnershipFailsBeforeFirstBaselineCreation;
var
  g: TGarbos;
  lDelta, lSummary: TJSONObject;
  lFound: Boolean;
  lItem: TJSONValue;
begin
  WriteRun(['Missing.pas']);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  Finalize(False);
  Assert.IsFalse(TFile.Exists(TPath.Combine(fOut, 'baseline.json')), 'no baseline is created');
  GC(lDelta, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'delta.json')), 'delta.json'), g);
  lFound := False;
  for lItem in JsonArrayMember(JsonObjectMember(lDelta, 'gate'), 'reasons') do
    if lItem.Value.ToLowerInvariant.Contains('unknown ownership') then
      lFound := True;
  Assert.IsTrue(lFound, 'the reason names the unknown ownership');
  // test_enabled_gate_has_one_canonical_policy_outcome: the outcome lives in status.policy only.
  GC(lSummary, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'summary.json')), 'summary.json'), g);
  Assert.AreEqual('fail', JsonText(JsonObjectMember(lSummary, 'status'), 'policy'), 'status.policy');
  Assert.IsNull(JsonObjectMember(lSummary, 'policy').GetValue('status'), 'the policy object carries no second status');
end;

// A rejected update leaves the accepted baseline and its Markdown view byte-identical.
procedure TNativeAnalysisPolicyTests.IncompatibleGatedUpdatePreservesBaselineBytes;
var
  g: TGarbos;
  lBefore, lMarkdownBefore: TBytes;
  lDelta, lSummary: TJSONObject;
  lFound: Boolean;
  lItem: TJSONValue;
begin
  lBefore := CreateBaseline;
  lMarkdownBefore := TFile.ReadAllBytes(TPath.Combine(fOut, 'baseline.md'));
  WriteRun([], Repeated('9'), [], []);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));
  Finalize(False);
  Assert.AreEqual(TEncoding.UTF8.GetString(lBefore),
    TEncoding.UTF8.GetString(TFile.ReadAllBytes(TPath.Combine(fOut, 'baseline.json'))), 'baseline.json is unchanged');
  Assert.AreEqual(TEncoding.UTF8.GetString(lMarkdownBefore),
    TEncoding.UTF8.GetString(TFile.ReadAllBytes(TPath.Combine(fOut, 'baseline.md'))), 'baseline.md is unchanged');
  GC(lSummary, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'summary.json')), 'summary.json'), g);
  Assert.AreEqual('fail', JsonText(JsonObjectMember(lSummary, 'status'), 'policy'), 'status.policy');
  GC(lDelta, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'delta.json')), 'delta.json'), g);
  lFound := False;
  for lItem in JsonArrayMember(JsonObjectMember(lDelta, 'gate'), 'reasons') do
    if lItem.Value.ToLowerInvariant.Contains('compatibility') then
      lFound := True;
  Assert.IsTrue(lFound, 'the reason names the compatibility mismatch');
end;

// A baseline recorded under an older ownership contract is refused, never silently replaced.
procedure TNativeAnalysisPolicyTests.OwnershipContractChangeRejectsLegacyBaselineWithoutReplacingIt;
var
  g: TGarbos;
  lBaseline, lContext, lDelta: TJSONObject;
  lBefore: TBytes;
  lFound: Boolean;
  lItem: TJSONValue;
  lPath: string;
begin
  CreateBaseline;
  lPath := TPath.Combine(fOut, 'baseline.json');
  GC(lBaseline, ParseJsonObject(ReadUtf8(lPath), 'baseline.json'), g);
  lContext := JsonObjectMember(JsonObjectMember(lBaseline, 'compatibility'), 'context');
  lContext.RemovePair('ownership_contract').Free;
  lContext.RemovePair('ownership_boundaries').Free;
  JsonPutText(JsonObjectMember(lBaseline, 'compatibility'), 'sha256', TPythonJson.CompactSha256(lContext));
  WriteUtf8(lPath, lBaseline.ToJSON);
  lBefore := TFile.ReadAllBytes(lPath);
  WriteRun([]);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));
  Finalize(False);
  Assert.AreEqual(TEncoding.UTF8.GetString(lBefore), TEncoding.UTF8.GetString(TFile.ReadAllBytes(lPath)),
    'the legacy baseline bytes are preserved');
  GC(lDelta, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'delta.json')), 'delta.json'), g);
  lFound := False;
  for lItem in JsonArrayMember(JsonObjectMember(lDelta, 'gate'), 'reasons') do
    if lItem.Value.ToLowerInvariant.Contains('compatibility') then
      lFound := True;
  Assert.IsTrue(lFound, 'the reason names the compatibility mismatch');
end;

// Editing the analyzed source does not change the compatibility context; only recorded inputs do.
procedure TNativeAnalysisPolicyTests.CompatibilityExcludesCandidateSourceIdentity;
begin
  CreateBaseline;
  WriteUtf8(fMainSource, 'program Sample;'#10'// dirty candidate'#10'begin'#10'end.'#10);
  WriteRun([]);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  Finalize(True);
end;

// Verification refuses a passing gate whose published fingerprint no longer matches the inputs.
procedure TNativeAnalysisPolicyTests.VerifyRejectsStaleCompatibilityInAPassingGate;
var
  g: TGarbos;
  lSummary: TJSONObject;
  lCounts: TJSONObject;
begin
  CreateBaseline;
  WriteRun([]);
  SetEnvironmentVariable('DAK_GATE', PChar('1'));
  Finalize(True);
  GC(lSummary, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'summary.json')), 'summary.json'), g);
  JsonPutText(JsonObjectMember(lSummary, 'compatibility'), 'sha256', StringOfChar('0', 64));
  WriteUtf8(TPath.Combine(fOut, 'summary.json'), lSummary.ToJSON);
  try
    lCounts := VerifyAnalysisReport(fOut);
    lCounts.Free;
    Assert.Fail('verification must reject the stale fingerprint');
  except
    on e: EConvertError do
      Assert.IsTrue(e.Message.ToLowerInvariant.Contains('compatibility'), e.Message);
  end;
end;

// Re-publishing the same outputs appends no second history row.
procedure TNativeAnalysisPolicyTests.RepeatedPublicationDoesNotDuplicateHistory;
var
  lFirst, lSecond: Integer;

  function HistoryRows: Integer;
  var
    lLine: string;
  begin
    Result := 0;
    for lLine in ReadUtf8(TPath.Combine(fOut, 'history.jsonl')).Replace(#13#10, #10).Split([#10]) do
      if Trim(lLine) <> '' then
        Inc(Result);
  end;

begin
  CreateBaseline;
  lFirst := HistoryRows;
  Assert.AreEqual(1, lFirst, 'the first run records one history row');
  Finalize(True);
  lSecond := HistoryRows;
  Assert.AreEqual(lFirst, lSecond, 'a repeated run on the same outputs adds no row');
end;

// An accepted update replaces the baseline and the Markdown view beside it.
procedure TNativeAnalysisPolicyTests.AcceptedUpdateReplacesTheBaselineAndItsMarkdown;
var
  g: TGarbos;
  lBefore: TBytes;
  lBaseline: TJSONObject;
begin
  lBefore := CreateBaseline;
  WriteRun([TPath.Combine(fRepo, 'src\Owned.pas')]);
  SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));
  Finalize(True);
  Assert.AreNotEqual(TEncoding.UTF8.GetString(lBefore),
    TEncoding.UTF8.GetString(TFile.ReadAllBytes(TPath.Combine(fOut, 'baseline.json'))), 'the baseline is replaced');
  GC(lBaseline, ParseJsonObject(ReadUtf8(TPath.Combine(fOut, 'baseline.json')), 'baseline.json'), g);
  Assert.AreEqual('1', JsonText(JsonObjectMember(lBaseline, 'fixinsight'), 'total'), 'it records this run');
  Assert.IsTrue(ReadUtf8(TPath.Combine(fOut, 'baseline.md')).Contains('- Findings: 1'),
    'the Markdown view follows the accepted baseline');
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisPolicyTests);

end.
