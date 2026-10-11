unit Test.RootMemberAbsenceContext;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TNativePublicationTests = class
  public
    [Test]
    procedure UsedProofDriftRefusesPlanCapture;
    [Test]
    [TestCase('Consumption count', 'consumption')]
    [TestCase('Capture count', 'capture')]
    [TestCase('Successful residue', 'residue')]
    procedure NativeBoundaryRevalidatesOnce(const aMode: string);
    [Test]
    procedure ProvenanceExceptionBecomesRefusal;
    [Test]
    procedure OwnerCreationFailureRetainsDiagnostic;
    [Test]
    [TestCase('XML', 'xml')]
    [TestCase('Property export', 'property')]
    [TestCase('Path export', 'paths')]
    procedure OversizedNativeTransportRefuses(const aMode: string);
    [Test]
    [TestCase('Directory limit', 'count')]
    [TestCase('Artifact byte limit', 'size')]
    procedure FailedContextArtifactsStayBounded(const aMode: string);
  end;

  [TestFixture]
  TRootMemberAbsenceContextTests = class
  public
    [Test]
    procedure StandardFixtureMatchesNativePathsAndReleaseRoot;
    [Test]
    procedure ExplicitDebugDcusSelectTheNativeDebugRoot;
    [Test]
    procedure IdenticalNativeInputsHaveStableFingerprints;
    [Test]
    [TestCase('System alias', 'alias')]
    [TestCase('Additional switches', 'switches')]
    [TestCase('Inherited unit override', 'override')]
    [TestCase('Custom target', 'target')]
    [TestCase('Referenced source directory', 'source-directory')]
    [TestCase('Single quoted custom import', 'single-import')]
    [TestCase('Namespace qualified custom target', 'namespace-target')]
    [TestCase('Commented explicit root selection', 'commented-root')]
    [TestCase('DPR source directory', 'dpr-source-directory')]
    [TestCase('Included source selection', 'included-source')]
    [TestCase('Pre-build root mutation', 'pre-build')]
    [TestCase('Post-build root mutation', 'post-build')]
    [TestCase('Conditional root entry', 'conditional-root')]
    [TestCase('Conditional uses terminator', 'conditional-semicolon')]
    [TestCase('Escaped root identifier', 'escaped-root')]
    procedure UnsupportedContextRetainsRefusal(const aCaseName: string);
    [Test]
    procedure NewlyAppearingOverrideInvalidatesRetainedContext;
    [Test]
    procedure ExistsConditionInvalidatesRetainedProfile;
    [Test]
    [TestCase('Native defines', 'DCC_Define,DAK_ACTIVE_HELPER')]
    [TestCase('Ordered include paths', 'DCC_IncludePath,include-after;include-before')]
    procedure ExistsConditionInvalidatesSourceProfile(const aPropertyName, aValue: string);
    [Test]
    procedure CapturedSourceProfileRetainsEvaluatedValues;
    [Test]
    [TestCase('Main source', 'main')]
    [TestCase('Referenced source', 'referenced')]
    procedure MutableSourceWritesInvalidateRetainedContext(const aCaseName: string);
    [Test]
    [TestCase('UTF8 source', 'utf8')]
    [TestCase('UTF16 source', 'utf16')]
    procedure SourceSnapshotReturnsExactEditableBytes(const aEncodingName: string);
    [Test]
    [TestCase('First snapshot', 'first-snapshot')]
    [TestCase('Changed observation', 'changed-observation')]
    procedure RequestOwnerSourceMismatchIsDrift(const aMode: string);
  end;

implementation

uses
  System.Classes, System.IOUtils, System.RegularExpressions, System.StrUtils, System.SysUtils,
  maxLogic.ioutils,
  DelphiSemantics.Cache, DelphiSemantics.CompilerProfile, DelphiSemantics.ProjectContext,
  DelphiSemantics.RootMemberAbsence, DelphiSemantics.Source,
  Dak.Build.NativeContext, Dak.Build.Runner, Dak.Build.Types, Dak.NativeInputLocks, Dak.RemoveWith.Model, Dak.RemoveWith.Symbols,
  Dak.RootMemberAbsence, Dak.Types,
  Test.Support;

function ContextOptions(const aProjectFileName: string): TAppOptions;
begin
  Result := Default(TAppOptions);
  Result.fDprojPath := aProjectFileName;
  Result.fConfig := 'Debug';
  Result.fPlatform := 'Win32';
  Result.fDelphiVersion := '23.0';
end;

function WriteContextProject(const aProperties, aExtraTargets: string): string;
var
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-root-context');
  TDirectory.CreateDirectory(lRoot);
  TDirectory.CreateDirectory(TPath.Combine(lRoot, 'lookup'));
  Result := TPath.Combine(lRoot, 'ContextProbe.dproj');
  TFile.WriteAllText(TPath.Combine(lRoot, 'ContextProbe.dpr'),
    'program ContextProbe;' + sLineBreak + 'begin end.' + sLineBreak, TEncoding.ASCII);
  TFile.WriteAllText(Result,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>ContextProbe.dpr</MainSource><ProjectName>ContextProbe</ProjectName>' +
    '<AppType>Console</AppType><FrameworkType>None</FrameworkType>' +
    '<DCC_UnitSearchPath>lookup;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' +
    '<DCC_Namespace>System;System.Win</DCC_Namespace>' + aProperties + '</PropertyGroup>' +
    aExtraTargets + '<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" />' +
    '</Project>', TEncoding.ASCII);
end;

procedure TRootMemberAbsenceContextTests.StandardFixtureMatchesNativePathsAndReleaseRoot;
var
  i: Integer;
  lContext: IDakNativeCompilerContext;
  lExitCode: Integer;
  lExpectedPaths: TArray<string>;
  lLine: string;
  lNativePaths: TArray<string>;
  lOptions: TAppOptions;
  lPath: string;
  lProjectDirectory: string;
  lReason: string;
begin
  lProjectDirectory := CombinePath([RepoRoot, 'tests', 'fixtures',
    'RemoveWithMultipleSelectorRewriteFixture']);
  lOptions := ContextOptions(TPath.Combine(lProjectDirectory,
    'RemoveWithMultipleSelectorRewriteFixture.dproj'));
  // Remove only the generated response file so path parity cannot use a retained artifact.
  TFile.Delete(CombinePath([lProjectDirectory, 'bin', 'RemoveWithMultipleSelectorRewriteFixture.cmds']));
  lOptions.fBuildTarget := 'Rebuild';
  Assert.IsTrue(TryRunBuildInternal(lOptions, lExitCode, lReason), lReason);
  Assert.AreEqual(0, lExitCode, lReason);
  Assert.IsTrue(TryReadNativeCompilerContext(lOptions, lContext, lReason), lReason);
  Assert.AreEqual('release', TPath.GetFileName(lContext.RootLibraryDirectory));
  for lLine in TFile.ReadAllLines(CombinePath([lProjectDirectory, 'bin',
    'RemoveWithMultipleSelectorRewriteFixture.cmds'])) do
    if StartsText('-U"', lLine) then
    begin
      lPath := Copy(lLine, 4, Length(lLine) - 4);
      if not TPath.IsPathRooted(lPath) then
        lPath := TPath.Combine(lProjectDirectory, lPath);
      lExpectedPaths := lExpectedPaths + [TPath.GetFullPath(lPath)];
    end;
  lNativePaths := lContext.UnitSearchPaths;
  Assert.IsTrue(Length(lExpectedPaths) > 1, 'Native build response paths are required');
  Assert.AreEqual(Integer(Length(lExpectedPaths)), Integer(Length(lNativePaths)));
  for i := 0 to High(lExpectedPaths) do
    Assert.AreEqual(lExpectedPaths[i], lNativePaths[i], IntToStr(i));
  Assert.IsTrue(lContext.EvidenceFingerprint <> '');
end;

procedure TRootMemberAbsenceContextTests.ExplicitDebugDcusSelectTheNativeDebugRoot;
var
  lContext: IDakNativeCompilerContext;
  lOptions: TAppOptions;
  lReason: string;
begin
  lOptions := ContextOptions(WriteContextProject('<DCC_DebugDCUs>true</DCC_DebugDCUs>', ''));
  Assert.IsTrue(TryReadNativeCompilerContext(lOptions, lContext, lReason), lReason);
  Assert.AreEqual('debug', TPath.GetFileName(lContext.RootLibraryDirectory));
  Assert.IsTrue(lContext.InputsAreCurrent);
end;

procedure TRootMemberAbsenceContextTests.UnsupportedContextRetainsRefusal(const aCaseName: string);
var
  lContext: IDakNativeCompilerContext;
  lOptions: TAppOptions;
  lProjectFileName: string;
  lProperties: string;
  lReason: string;
  lTargets: string;
begin
  lProperties := '';
  lTargets := '';
  if aCaseName = 'alias' then
    lProperties := '<DCC_UnitAlias>System=Replacement;</DCC_UnitAlias>'
  else if aCaseName = 'switches' then
    lProperties := '<DCC_AdditionalSwitches>-A System=Replacement</DCC_AdditionalSwitches>'
  else if aCaseName = 'pre-build' then
    lProperties := '<PreBuildEvent>echo root context changed</PreBuildEvent>'
  else if aCaseName = 'post-build' then
    lProperties := '<PostBuildEvent>echo root context changed</PostBuildEvent>'
  else if aCaseName = 'target' then
    lTargets := '<Target Name="CustomRootSelection" BeforeTargets="Build" />'
  else if aCaseName = 'namespace-target' then
    lTargets := '<msb:Target xmlns:msb="http://schemas.microsoft.com/developer/msbuild/2003" ' +
      'Name="CustomRootSelection" BeforeTargets="Build" />'
  else if aCaseName = 'single-import' then
    lTargets := '<Import Project=''custom.targets'' />'
  else if aCaseName = 'source-directory' then
    lTargets := '<ItemGroup><DCCReference Include="other\DeclaredUnit.pas" /></ItemGroup>';
  lProjectFileName := WriteContextProject(lProperties, lTargets);
  if aCaseName = 'single-import' then
    TFile.WriteAllText(TPath.Combine(TPath.GetDirectoryName(lProjectFileName), 'custom.targets'),
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
      '<PropertyGroup><DAKHiddenProperty>true</DAKHiddenProperty></PropertyGroup></Project>', TEncoding.ASCII);
  if aCaseName = 'commented-root' then
  begin
    TFile.WriteAllText(TPath.ChangeExtension(lProjectFileName, '.dpr'),
      'program ContextProbe; uses System {source comment} in ''RootReplacement.pas''; begin end.', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(TPath.GetDirectoryName(lProjectFileName), 'RootReplacement.pas'),
      'unit System; interface implementation end.', TEncoding.ASCII);
  end;
  if MatchText(aCaseName, ['conditional-root', 'conditional-semicolon', 'escaped-root']) then
  begin
    if aCaseName = 'conditional-root' then
      lProperties := 'uses {$IFDEF TEST} OtherUnit {$ELSE} System {$ENDIF} in ''RootReplacement.pas'';'
    else if aCaseName = 'conditional-semicolon' then
      lProperties := 'uses {$IFDEF TEST} OtherUnit; {$ELSE} System in ''RootReplacement.pas''; {$ENDIF}'
    else
      lProperties := 'uses &System in ''RootReplacement.pas'';';
    TFile.WriteAllText(TPath.ChangeExtension(lProjectFileName, '.dpr'),
      'program ContextProbe; ' + lProperties + ' begin end.', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(TPath.GetDirectoryName(lProjectFileName), 'RootReplacement.pas'),
      'unit System; interface implementation end.', TEncoding.ASCII);
  end;
  if aCaseName = 'included-source' then
  begin
    TFile.WriteAllText(TPath.ChangeExtension(lProjectFileName, '.dpr'),
      'program ContextProbe; {$I Sources.inc} begin end.', TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(TPath.GetDirectoryName(lProjectFileName), 'Sources.inc'),
      'uses System in ''RootReplacement.pas'';', TEncoding.ASCII);
  end;
  if aCaseName = 'override' then
    TFile.WriteAllText(CombinePath([TPath.GetDirectoryName(lProjectFileName), 'lookup', 'System.pas']),
      'unit System; interface implementation end.', TEncoding.ASCII);
  if (aCaseName = 'source-directory') or (aCaseName = 'dpr-source-directory') then
  begin
    TDirectory.CreateDirectory(TPath.Combine(TPath.GetDirectoryName(lProjectFileName), 'other'));
    TFile.WriteAllText(CombinePath([TPath.GetDirectoryName(lProjectFileName), 'other', 'DeclaredUnit.pas']),
      'unit DeclaredUnit; interface implementation end.', TEncoding.ASCII);
    TFile.WriteAllText(CombinePath([TPath.GetDirectoryName(lProjectFileName), 'other', 'System.pas']),
      'unit System; interface implementation end.', TEncoding.ASCII);
    if aCaseName = 'dpr-source-directory' then
      TFile.WriteAllText(TPath.ChangeExtension(lProjectFileName, '.dpr'),
        'program ContextProbe; uses DeclaredUnit in ''other\DeclaredUnit.pas''; begin end.', TEncoding.ASCII);
  end;
  lOptions := ContextOptions(lProjectFileName);
  Assert.IsFalse(TryReadNativeCompilerContext(lOptions, lContext, lReason));
  Assert.IsTrue(lContext = nil);
  Assert.IsTrue(lReason <> '');
end;

procedure TRootMemberAbsenceContextTests.NewlyAppearingOverrideInvalidatesRetainedContext;
var
  lContext: IDakNativeCompilerContext;
  lOptions: TAppOptions;
  lReason: string;
begin
  lOptions := ContextOptions(WriteContextProject('', ''));
  Assert.IsTrue(TryReadNativeCompilerContext(lOptions, lContext, lReason), lReason);
  Assert.IsTrue(lContext.EvidenceFingerprint <> '');
  TFile.WriteAllText(CombinePath([TPath.GetDirectoryName(lOptions.fDprojPath), 'lookup', 'System.pas']),
    'unit System; interface implementation end.', TEncoding.ASCII);
  Assert.IsFalse(lContext.InputsAreCurrent);
  Assert.AreEqual('', lContext.EvidenceFingerprint);
end;

procedure TRootMemberAbsenceContextTests.IdenticalNativeInputsHaveStableFingerprints;
var
  lFirst: IDakNativeCompilerContext;
  lOptions: TAppOptions;
  lReason: string;
  lSecond: IDakNativeCompilerContext;
begin
  lOptions := ContextOptions(WriteContextProject('', ''));
  Assert.IsTrue(TryReadNativeCompilerContext(lOptions, lFirst, lReason), lReason);
  Assert.IsTrue(TryReadNativeCompilerContext(lOptions, lSecond, lReason), lReason);
  Assert.IsTrue(lFirst.EvidenceFingerprint <> '', 'First identity must be available');
  Assert.IsTrue(lSecond.EvidenceFingerprint <> '', 'Second identity must be available');
  Assert.AreEqual(lFirst.EvidenceFingerprint, lSecond.EvidenceFingerprint);
end;

procedure TRootMemberAbsenceContextTests.ExistsConditionInvalidatesRetainedProfile;
var
  lContext: IDakNativeCompilerContext;
  lOptions: TAppOptions;
  lReason: string;
begin
  lOptions := ContextOptions(WriteContextProject(
    '<DCC_DebugDCUs Condition="Exists(''select-debug.flag'')">true</DCC_DebugDCUs>', ''));
  Assert.IsTrue(TryReadNativeCompilerContext(lOptions, lContext, lReason), lReason);
  Assert.AreEqual('release', TPath.GetFileName(lContext.RootLibraryDirectory));
  TFile.WriteAllText(TPath.Combine(TPath.GetDirectoryName(lOptions.fDprojPath),
    'select-debug.flag'), 'Enable the native debug RTL profile', TEncoding.ASCII);
  Assert.IsFalse(lContext.InputsAreCurrent, 'Unchanged /pp text cannot certify unchanged evaluated properties.');
  Assert.AreEqual('', lContext.EvidenceFingerprint);
end;

procedure TRootMemberAbsenceContextTests.ExistsConditionInvalidatesSourceProfile(
  const aPropertyName, aValue: string);
var
  lContext: IDakNativeCompilerContext;
  lOptions: TAppOptions;
  lReason: string;
begin
  lOptions := ContextOptions(WriteContextProject('<' + aPropertyName +
    ' Condition="Exists(''select-source-profile.flag'')">' + aValue + '</' + aPropertyName + '>', ''));
  Assert.IsTrue(TryReadNativeCompilerContext(lOptions, lContext, lReason), lReason);
  Assert.IsTrue(lContext.InputsAreCurrent);
  TFile.WriteAllText(TPath.Combine(TPath.GetDirectoryName(lOptions.fDprojPath),
    'select-source-profile.flag'), 'Activate a different source profile', TEncoding.ASCII);
  Assert.IsFalse(lContext.InputsAreCurrent,
    'Evaluated defines and ordered include paths are part of our retained native source profile.');
  Assert.AreEqual('', lContext.EvidenceFingerprint);
end;

procedure TRootMemberAbsenceContextTests.CapturedSourceProfileRetainsEvaluatedValues;
var
  lContext: IDakNativeCompilerContext;
  lOptions: TAppOptions;
  lProfile: TDakNativeCompilerSourceProfile;
  lReason: string;
begin
  lOptions := ContextOptions(WriteContextProject(
    '<DCC_Define>DAK_CAPTURED</DCC_Define>' +
    '<DCC_IncludePath>include-first;include-second</DCC_IncludePath>', ''));
  Assert.IsTrue(TryReadNativeCompilerContext(lOptions, lContext, lReason), lReason);
  lProfile := lContext.SourceProfile;
  Assert.AreEqual('Debug', lProfile.fConfiguration);
  Assert.AreEqual('Win32', lProfile.fPlatform);
  Assert.IsTrue(ContainsText(lProfile.fDefines, 'DAK_CAPTURED'));
  Assert.IsTrue(ContainsText(lProfile.fIncludePaths, 'include-first'));
  Assert.IsTrue(Pos('include-first', lProfile.fIncludePaths) <
    Pos('include-second', lProfile.fIncludePaths), 'Our native include order is retained.');
  Assert.IsTrue(ContainsText(lProfile.fUnitScopeNames, 'System.Win'));
end;

procedure TRootMemberAbsenceContextTests.MutableSourceWritesInvalidateRetainedContext(const aCaseName: string);
var
  lContext: IDakNativeCompilerContext;
  lFileName: string;
  lOptions: TAppOptions;
  lReason: string;
  lRoot: string;
  lStream: TFileStream;
begin
  lOptions := ContextOptions(WriteContextProject('', ''));
  lRoot := TPath.GetDirectoryName(lOptions.fDprojPath);
  TFile.WriteAllText(TPath.Combine(lRoot, 'EditableUnit.pas'),
    'unit EditableUnit; interface implementation end.', TEncoding.ASCII);
  TFile.WriteAllText(TPath.ChangeExtension(lOptions.fDprojPath, '.dpr'),
    'program ContextProbe; uses EditableUnit in ''EditableUnit.pas''; begin end.', TEncoding.ASCII);
  Assert.IsTrue(TryReadNativeCompilerContext(lOptions, lContext, lReason), lReason);
  Assert.IsTrue(lContext.EvidenceFingerprint <> '');
  if aCaseName = 'main' then
    lFileName := TPath.ChangeExtension(lOptions.fDprojPath, '.dpr')
  else
    lFileName := TPath.Combine(lRoot, 'EditableUnit.pas');
  lStream := nil;
  try
    try
      lStream := TFileStream.Create(lFileName, fmOpenReadWrite or fmShareDenyWrite);
    except
      on E: Exception do
        Assert.Fail('A retained root context must allow its source-owner write: ' + E.Message);
    end;
  finally
    lStream.Free;
  end;
  Assert.IsTrue(lContext.InputsAreCurrent);
  TFile.AppendAllText(lFileName, ' ', TEncoding.ASCII);
  Assert.IsFalse(lContext.InputsAreCurrent);
  Assert.AreEqual('', lContext.EvidenceFingerprint);
end;

procedure TRootMemberAbsenceContextTests.SourceSnapshotReturnsExactEditableBytes(
  const aEncodingName: string);
var
  lCaptured: TBytes;
  lEncoding: TEncoding;
  lExpected: TBytes;
  lFileName: string;
  lFingerprint: TStringBuilder;
  lLocks: TDakNativeInputLocks;
begin
  lFileName := TPath.Combine(UniqueTempPath('native-source-snapshot'), 'Source.dpr');
  TDirectory.CreateDirectory(TPath.GetDirectoryName(lFileName));
  if aEncodingName = 'utf16' then
    lEncoding := TEncoding.Unicode
  else
    lEncoding := TEncoding.UTF8;
  TFile.WriteAllText(lFileName, 'program Source; begin end.', lEncoding);
  lExpected := TFile.ReadAllBytes(lFileName);
  lFingerprint := TStringBuilder.Create;
  lLocks := TDakNativeInputLocks.Create;
  try
    lCaptured := lLocks.SnapshotBytes(lFileName, lFingerprint);
    Assert.AreEqual(Length(lExpected), Length(lCaptured));
    Assert.IsTrue(CompareMem(@lExpected[0], @lCaptured[0], Length(lExpected)));
    Assert.IsTrue(lLocks.InputsAreCurrent);
    TFile.WriteAllText(lFileName, 'program ChangedSource; begin end.', lEncoding);
    Assert.IsFalse(lLocks.InputsAreCurrent);
    Assert.IsTrue(CompareMem(@lExpected[0], @lCaptured[0], Length(lExpected)),
      'Captured bytes must remain the exact input that was fingerprinted.');
  finally
    lLocks.Free;
    lFingerprint.Free;
  end;
end;

procedure TRootMemberAbsenceContextTests.RequestOwnerSourceMismatchIsDrift(const aMode: string);
var
  lGuard: IDakRemoveWithPlanInputGuard;
  lObservation: TDelphiSemanticModelObservation;
  lOptions: TAppOptions;
  lOwner: IDelphiSemanticModelObservationOwner;
  lProfileOwner: IDelphiSemanticProjectProfileValidator;
  lProject: TDelphiSemanticProjectInfo;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason, lFileName: string;
  lSource: TDelphiSemanticSourceLoadResult;
begin
  lOptions := ContextOptions(WriteContextProject('', ''));
  lFileName := TPath.Combine(TPath.GetDirectoryName(lOptions.fDprojPath), 'Observed.pas');
  TFile.WriteAllText(lFileName, 'unit Observed; interface implementation end.', TEncoding.ASCII);
  lProvider := TryCreateNativeRootRequestOwner(lOptions, lGuard, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticProjectProfileValidator, lProfileOwner));
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticModelObservationOwner, lOwner));
  lProject := Default(TDelphiSemanticProjectInfo);
  lProject.Platform := 'Win32';
  lProject.Configuration := 'Debug';
  lProject.Defines := TDelphiSemanticCompilerProfileBuilder.DefinesForPlatform('Win32');
  lProject.ContextFingerprint := 'ds717-source-drift-control';
  Assert.IsTrue(lProfileOwner.ValidateProjectProfile(lProject, lReason), lReason);
  lSource := TDelphiSemanticSourceLoader.LoadFile(lFileName);
  Assert.IsTrue(lSource.Success);
  lObservation := Default(TDelphiSemanticModelObservation);
  lObservation.ProjectContextFingerprint := lProject.ContextFingerprint;
  lObservation.ModelFileName := lFileName;
  lObservation.SourceObservations := lSource.SourceObservations;
  if aMode = 'changed-observation' then
    Assert.IsTrue(lOwner.ValidateModelSources(lObservation, lReason), lReason);
  TFile.WriteAllText(lFileName, 'unit Observed; interface const Changed = 1; implementation end.',
    TEncoding.ASCII);
  if aMode = 'changed-observation' then
  begin
    lSource := TDelphiSemanticSourceLoader.LoadFile(lFileName);
    Assert.IsTrue(lSource.Success);
    lObservation.SourceObservations := lSource.SourceObservations;
  end;
  Assert.IsFalse(lOwner.ValidateModelSources(lObservation, lReason));
  Assert.AreEqual('native-request-inputs-changed', lReason,
    'Source drift must never enter the unsupported-profile fallback.');
end;

type
  TThrowingProvenanceGuard = class(TInterfacedObject, IDakRemoveWithPlanInputGuard,
    IDakRemoveWithNativeProofProvenance, IDakRemoveWithNativeProofUsage)
  public
    function ProofFingerprint: string;
    function ProofWasUsed: Boolean;
    function ValidateInputs(const aExpectedFingerprint: string; out aReason: string): Boolean;
    function ProvenanceJson: string;
  end;

function TThrowingProvenanceGuard.ProofFingerprint: string;
begin
  Result := 'used-proof';
end;

function TThrowingProvenanceGuard.ProofWasUsed: Boolean;
begin
  Result := True;
end;

function TThrowingProvenanceGuard.ValidateInputs(const aExpectedFingerprint: string;
  out aReason: string): Boolean;
begin
  aReason := '';
  Result := aExpectedFingerprint = 'used-proof';
end;

function TThrowingProvenanceGuard.ProvenanceJson: string;
begin
  raise EInvalidOpException.Create('deliberate provenance failure');
end;

procedure TNativePublicationTests.ProvenanceExceptionBecomesRefusal;
var
  lGuard: IDakRemoveWithPlanInputGuard;
  lFingerprint, lProvenance, lReason: string;
  lAccepted: Boolean;
begin
  lAccepted := False;
  lGuard := TThrowingProvenanceGuard.Create;
  try
    lAccepted := FinalizeNativeRootProof(lGuard, lFingerprint, lProvenance, lReason);
  except
    on E: Exception do
      Assert.Fail('Proof finalization must return a structured refusal: ' + E.Message);
  end;
  Assert.IsFalse(lAccepted);
  Assert.IsTrue(lReason.Contains('native-root-proof-finalization-failed'), lReason);
  Assert.IsTrue(lReason.Contains('deliberate provenance failure'), lReason);
  Assert.AreEqual('', lFingerprint);
  Assert.AreEqual('', lProvenance);
end;

procedure TNativePublicationTests.UsedProofDriftRefusesPlanCapture;
var
  lGuard: IDakRemoveWithPlanInputGuard;
  lObservation: TDelphiSemanticModelObservation;
  lOptions: TAppOptions;
  lOwner: IDelphiSemanticModelObservationOwner;
  lProfileOwner: IDelphiSemanticProjectProfileValidator;
  lProject: TDelphiSemanticProjectInfo;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lUsage: IDakRemoveWithNativeProofUsage;
  lReason, lFileName, lFingerprint, lProvenance: string;
  lSource: TDelphiSemanticSourceLoadResult;
begin
  lOptions := ContextOptions(WriteContextProject('', ''));
  lFileName := TPath.Combine(TPath.GetDirectoryName(lOptions.fDprojPath), 'Observed.pas');
  TFile.WriteAllText(lFileName, 'unit Observed; interface implementation end.', TEncoding.ASCII);
  lProvider := TryCreateNativeRootRequestOwner(lOptions, lGuard, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticProjectProfileValidator, lProfileOwner));
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticModelObservationOwner, lOwner));
  Assert.IsTrue(Supports(lProvider, IDakRemoveWithNativeProofUsage, lUsage));
  lProject := Default(TDelphiSemanticProjectInfo);
  lProject.Platform := 'Win32';
  lProject.Configuration := 'Debug';
  lProject.Defines := TDelphiSemanticCompilerProfileBuilder.DefinesForPlatform('Win32');
  lProject.ContextFingerprint := 'publication-drift-control';
  Assert.IsTrue(lProfileOwner.ValidateProjectProfile(lProject, lReason), lReason);
  lSource := TDelphiSemanticSourceLoader.LoadFile(lFileName);
  Assert.IsTrue(lSource.Success);
  lObservation := Default(TDelphiSemanticModelObservation);
  lObservation.ProjectContextFingerprint := lProject.ContextFingerprint;
  lObservation.ModelFileName := lFileName;
  lObservation.SourceObservations := lSource.SourceObservations;
  Assert.IsTrue(lOwner.ValidateModelSources(lObservation, lReason), lReason);
  Assert.IsTrue(lProvider.IsNameAbsent('DAK_UnownedName_414'), 'Real witness must succeed first');
  Assert.IsTrue(lUsage.ProofWasUsed);
  Assert.IsTrue(lGuard.ProofFingerprint <> '');
  TFile.AppendAllText(lFileName, sLineBreak + '// drift before plan capture', TEncoding.ASCII);
  Assert.AreEqual('', lGuard.ProofFingerprint, 'Drift invalidates the current identity');
  Assert.IsTrue(lUsage.ProofWasUsed, 'Drift must retain historical proof dependency');
  Assert.IsFalse(FinalizeNativeRootProof(lGuard, lFingerprint, lProvenance, lReason),
    'Symbols plan capture must refuse a used stale proof');
  Assert.AreEqual('native-request-inputs-changed', lReason);
  Assert.AreEqual('', lFingerprint);
  Assert.AreEqual('', lProvenance);
end;

procedure TNativePublicationTests.NativeBoundaryRevalidatesOnce(const aMode: string);
var
  lGuard: IDakRemoveWithPlanInputGuard;
  lObservation: TDelphiSemanticModelObservation;
  lOptions: TAppOptions;
  lOwner: IDelphiSemanticModelObservationOwner;
  lProfileOwner: IDelphiSemanticProjectProfileValidator;
  lProject: TDelphiSemanticProjectInfo;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lUsage: IDakRemoveWithNativeProofUsage;
  lReason, lFileName, lFingerprint, lProvenance: string;
  lSource: TDelphiSemanticSourceLoadResult;
  lMetrics: IDakNativeRootProofMetrics;
  lBefore: Integer;
  lContextRoot: string;
begin
  lOptions := ContextOptions(WriteContextProject('', ''));
  lFileName := TPath.Combine(TPath.GetDirectoryName(lOptions.fDprojPath), 'Observed.pas');
  TFile.WriteAllText(lFileName, 'unit Observed; interface implementation end.', TEncoding.ASCII);
  lProvider := TryCreateNativeRootRequestOwner(lOptions, lGuard, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticProjectProfileValidator, lProfileOwner));
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticModelObservationOwner, lOwner));
  Assert.IsTrue(Supports(lProvider, IDakRemoveWithNativeProofUsage, lUsage));
  lProject := Default(TDelphiSemanticProjectInfo);
  lProject.Platform := 'Win32';
  lProject.Configuration := 'Debug';
  lProject.Defines := TDelphiSemanticCompilerProfileBuilder.DefinesForPlatform('Win32');
  lProject.ContextFingerprint := 'publication-drift-control';
  Assert.IsTrue(lProfileOwner.ValidateProjectProfile(lProject, lReason), lReason);
  lSource := TDelphiSemanticSourceLoader.LoadFile(lFileName);
  Assert.IsTrue(lSource.Success);
  lObservation := Default(TDelphiSemanticModelObservation);
  lObservation.ProjectContextFingerprint := lProject.ContextFingerprint;
  lObservation.ModelFileName := lFileName;
  lObservation.SourceObservations := lSource.SourceObservations;
  Assert.IsTrue(lOwner.ValidateModelSources(lObservation, lReason), lReason);
  Assert.IsTrue(Supports(lGuard, IDakNativeRootProofMetrics, lMetrics));
  lBefore := lMetrics.NativeRevalidationCount;
  Assert.IsTrue(lProvider.IsNameAbsent('DAK_UnownedName_414'), 'Positive witness required');
  if aMode = 'consumption' then
    Assert.AreEqual(1, lMetrics.NativeRevalidationCount - lBefore,
      'One fresh evaluation per consumption boundary, no nested fingerprint launches');
  lBefore := lMetrics.NativeRevalidationCount;
  Assert.IsTrue(FinalizeNativeRootProof(lGuard, lFingerprint, lProvenance, lReason), lReason);
  Assert.IsTrue(lFingerprint <> '');
  if aMode = 'capture' then
    Assert.AreEqual(1, lMetrics.NativeRevalidationCount - lBefore,
      'Plan capture is one fresh boundary, provenance access adds no native evaluations');
  lContextRoot := TPath.Combine(TPath.GetDirectoryName(lOptions.fDprojPath),
    '.dak\ContextProbe\native-root-context');
  lMetrics := nil;
  lUsage := nil;
  lOwner := nil;
  lProfileOwner := nil;
  lGuard := nil;
  lProvider := nil;
  if aMode = 'residue' then
    Assert.AreEqual<NativeInt>(0, Length(TDirectory.GetFiles(lContextRoot, '*',
      TSearchOption.soAllDirectories)), 'Successful context transport must be removed');
end;

type
  TNativeTransportRunner = class(TInterfacedObject, IBuildProcessRunner)
  private
    fMode: string;
    fSdkRoot: string;
  public
    fCalls: Integer;
    constructor Create(const aMode, aSdkRoot: string);
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
      out aTimedOut: Boolean; out aError: string): Boolean;
  end;

constructor TNativeTransportRunner.Create(const aMode, aSdkRoot: string);
begin
  inherited Create;
  fMode := aMode;
  fSdkRoot := aSdkRoot;
end;

function TNativeTransportRunner.RunProcess(const aExePath, aArguments, aWorkDir,
  aStdOutPath, aStdErrPath, aEnvironmentBlock: string; aTimeoutSec: Integer;
  out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
var
  lMatch: TMatch;
  lFileName, lName, lValue, lTarget: string;
  lStream: TFileStream;
begin
  Inc(fCalls);
  Assert.AreEqual(30, aTimeoutSec);
  aExitCode := 0;
  aTimedOut := False;
  aError := '';
  Result := True;
  lMatch := TRegEx.Match(aArguments, '/pp:"([^"]+)"');
  if lMatch.Success then
  begin
    lFileName := lMatch.Groups[1].Value;
    TFile.WriteAllText(lFileName,
      '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" />', TEncoding.ASCII);
    if fMode = 'xml' then
    begin
      lStream := TFileStream.Create(lFileName, fmOpenWrite);
      try
        lStream.Size := 4 * 1024 * 1024 + 1;
      finally
        lStream.Free;
      end;
    end;
    Exit;
  end;
  lMatch := TRegEx.Match(aArguments, '/p:GlobalOptionFile="([^"]+)"');
  Assert.IsTrue(lMatch.Success, 'Snapshot target must be generated');
  lTarget := lMatch.Groups[1].Value;
  for lMatch in TRegEx.Matches(TFile.ReadAllText(lTarget), 'File="([^"]+\.txt)"') do
  begin
    lFileName := lMatch.Groups[1].Value;
    lName := TPath.GetFileNameWithoutExtension(lFileName);
    lValue := '';
    if lName = 'BDS' then
      lValue := fSdkRoot
    else if lName = 'GlobalOptionFile' then
      lValue := lTarget
    else if lName = 'MainSource' then
      lValue := 'ContextProbe.dpr'
    else if lName = 'Platform' then
      lValue := 'Win32'
    else if lName = 'Config' then
      lValue := 'Debug';
    TFile.WriteAllText(lFileName, 'DAK_CONTEXT_BEGIN' + sLineBreak + lValue +
      sLineBreak + 'DAK_CONTEXT_END' + sLineBreak, TEncoding.ASCII);
    if (fMode = 'property') and (lName = 'DCC_Define') then
    begin
      lStream := TFileStream.Create(lFileName, fmOpenWrite);
      try
        lStream.Size := 64 * 1024 + 1;
      finally
        lStream.Free;
      end;
    end;
  end;
  lMatch := TRegEx.Match(aArguments, '/p:CmdsFileOutput="([^"]+)"');
  Assert.IsTrue(lMatch.Success);
  lFileName := lMatch.Groups[1].Value;
  TFile.WriteAllText(lFileName, '-U"' + TPath.Combine(fSdkRoot, 'lib\Win32\release') + '"' +
    sLineBreak, TEncoding.ASCII);
  if fMode = 'paths' then
  begin
    lStream := TFileStream.Create(lFileName, fmOpenWrite);
    try
      lStream.Size := 1024 * 1024 + 1;
    finally
      lStream.Free;
    end;
  end;
end;

procedure TNativePublicationTests.OversizedNativeTransportRefuses(const aMode: string);
var
  lInvocation: TDakNativeCompilerInvocation;
  lContext: IDakNativeCompilerContext;
  lProbe: TNativeTransportRunner;
  lRunner: IBuildProcessRunner;
  lReason: string;
begin
  lInvocation := Default(TDakNativeCompilerInvocation);
  lInvocation.fProjectFileName := WriteContextProject('', '');
  lInvocation.fSdkRoot := 'C:\Program Files (x86)\Embarcadero\Studio\23.0';
  lInvocation.fCompilerFileName := TPath.Combine(lInvocation.fSdkRoot, 'bin\dcc32.exe');
  // The supplied runner is a transport control and launches no process.
  lInvocation.fMsBuildFileName := lInvocation.fCompilerFileName;
  lInvocation.fWorkRoot := TPath.Combine(TPath.GetDirectoryName(lInvocation.fProjectFileName),
    '.dak\ContextProbe\native-root-context');
  lProbe := TNativeTransportRunner.Create(aMode, lInvocation.fSdkRoot);
  lRunner := lProbe;
  lContext := TryCaptureNativeCompilerContext(lInvocation, lRunner, lReason);
  Assert.IsTrue(lProbe.fCalls > 0, 'The oversize transport must be produced');
  Assert.IsTrue(lContext = nil, 'Oversize native output must refuse');
  Assert.IsTrue(lReason.Contains('native-context-output-too-large'), lReason);
end;

procedure TNativePublicationTests.OwnerCreationFailureRetainsDiagnostic;
var
  lOptions: TAppOptions;
  lModel: TRemoveWithProjectModel;
  lInventory: TRemoveWithFactSet;
  lReason: string;
begin
  lOptions := ContextOptions(WriteContextProject('', ''));
  lOptions.fDelphiVersion := '';
  lModel := nil;
  Assert.IsTrue(BuildRemoveWithProjectModel(lOptions, lOptions.fDprojPath, lModel, lReason), lReason);
  try
    Assert.IsTrue(BuildRemoveWithFactSet(lOptions, lModel, lInventory, lReason), lReason);
    Assert.IsTrue(lInventory.fNativeRootProofDiagnostic.Contains('native-toolchain-not-selected'),
      'Optional owner creation failure must remain visible: ' + lInventory.fNativeRootProofDiagnostic);
  finally
    lModel.Free;
  end;
end;

procedure TNativePublicationTests.FailedContextArtifactsStayBounded(const aMode: string);
var
  i: Integer;
  lInvocation: TDakNativeCompilerInvocation;
  lContext: IDakNativeCompilerContext;
  lRunner: IBuildProcessRunner;
  lDirectories: TArray<string>;
  lFileName, lReason: string;
  lStream: TFileStream;
begin
  lInvocation := Default(TDakNativeCompilerInvocation);
  lInvocation.fProjectFileName := WriteContextProject('', '');
  lInvocation.fSdkRoot := 'C:\Program Files (x86)\Embarcadero\Studio\23.0';
  lInvocation.fCompilerFileName := TPath.Combine(lInvocation.fSdkRoot, 'bin\dcc32.exe');
  lInvocation.fMsBuildFileName := lInvocation.fCompilerFileName;
  lInvocation.fWorkRoot := TPath.Combine(TPath.GetDirectoryName(lInvocation.fProjectFileName),
    '.dak\ContextProbe\native-root-context');
  lRunner := TNativeTransportRunner.Create('xml', lInvocation.fSdkRoot);
  for i := 1 to 4 do
  begin
    lContext := TryCaptureNativeCompilerContext(lInvocation, lRunner, lReason);
    Assert.IsTrue(lContext = nil);
    Assert.IsTrue(lReason.Contains('native-context-output-too-large'), lReason);
  end;
  lDirectories := TDirectory.GetDirectories(lInvocation.fWorkRoot);
  Assert.IsTrue(Length(lDirectories) > 0, 'Failures must retain bounded diagnostic artifacts');
  if aMode = 'count' then
    Assert.IsTrue(Length(lDirectories) <= 3, 'At most three failed transport sets per project');
  if aMode = 'size' then
    for lFileName in TDirectory.GetFiles(lInvocation.fWorkRoot, '*', TSearchOption.soAllDirectories) do
    begin
      lStream := TFileStream.Create(lFileName, fmOpenRead or fmShareDenyWrite);
      try
        Assert.IsTrue(lStream.Size <= 1024 * 1024, 'Retained failure artifacts must be byte bounded');
      finally
        lStream.Free;
      end;
    end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativePublicationTests);
  TDUnitX.RegisterTestFixture(TRootMemberAbsenceContextTests);

end.
