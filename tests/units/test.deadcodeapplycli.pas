unit Test.DeadCodeApplyCli;

interface

uses
  System.IOUtils, System.JSON, System.SysUtils,
  DUnitX.TestFramework,
  Test.Support;

type
  [TestFixture]
  [Category('Slow')]
  TDeadCodeApplyCliTests = class
  private
    procedure CreateFixtureProject(const aRoot: string; const aFailWhenRoutineRemoved: Boolean;
      out aDprojPath, aUnitTwoPath: string);
  public
    [Test]
    procedure ApplyRequiresExplicitSafetyProfile;
    [Test]
    procedure AppliesLegacyStaticRemovalTransactionally;
    [Test]
    procedure ApplyAuditProfileProducesNoOpTransaction;
    [Test]
    procedure ApplyRollsBackWhenBuildVerificationFails;
    // DS-660: routines called only from the program main block or from another unit's
    // initialization or finalization block are kept; the unused routine is still removed.
    [Test]
    procedure ApplyKeepsRoutinesUsedOnlyFromEntryBlocks;
    // DS-660 review: overloads called without provable binding from the main block or another
    // unit, and a short-form body beside a nested namesake, are kept.
    [Test]
    procedure ApplyKeepsOverloadsAndShortFormBodiesUsedElsewhere;
  end;

implementation

procedure TDeadCodeApplyCliTests.CreateFixtureProject(const aRoot: string;
  const aFailWhenRoutineRemoved: Boolean; out aDprojPath, aUnitTwoPath: string);
var
  lDprojText: string;
  lDprPath: string;
  lUnitOnePath: string;
begin
  ForceDirectories(aRoot);
  aDprojPath := TPath.Combine(aRoot, 'DeadCodeApplyFixture.dproj');
  lDprPath := TPath.Combine(aRoot, 'DeadCodeApplyFixture.dpr');
  lUnitOnePath := TPath.Combine(aRoot, 'UnitOne.pas');
  aUnitTwoPath := TPath.Combine(aRoot, 'UnitTwo.pas');

  TFile.WriteAllText(lDprPath,
    'program DeadCodeApplyFixture;' + sLineBreak +
    '' + sLineBreak +
    'uses' + sLineBreak +
    '  UnitOne,' + sLineBreak +
    '  UnitTwo;' + sLineBreak +
    '' + sLineBreak +
    'begin' + sLineBreak +
    '  TouchSharedValue;' + sLineBreak +
    'end.' + sLineBreak,
    TEncoding.UTF8);

  TFile.WriteAllText(lUnitOnePath,
    'unit UnitOne;' + sLineBreak +
    '' + sLineBreak +
    'interface' + sLineBreak +
    '' + sLineBreak +
    'var' + sLineBreak +
    '  SharedValue: Integer;' + sLineBreak +
    '' + sLineBreak +
    'procedure TouchSharedValue;' + sLineBreak +
    '' + sLineBreak +
    'implementation' + sLineBreak +
    '' + sLineBreak +
    'procedure TouchSharedValue;' + sLineBreak +
    'begin' + sLineBreak +
    '  SharedValue := 1;' + sLineBreak +
    'end;' + sLineBreak +
    '' + sLineBreak +
    'end.' + sLineBreak,
    TEncoding.UTF8);

  TFile.WriteAllText(aUnitTwoPath,
    'unit UnitTwo;' + sLineBreak +
    '' + sLineBreak +
    'interface' + sLineBreak +
    '' + sLineBreak +
    'implementation' + sLineBreak +
    '' + sLineBreak +
    'uses' + sLineBreak +
    '  UnitOne;' + sLineBreak +
    '' + sLineBreak +
    'procedure UseSharedValue;' + sLineBreak +
    'begin' + sLineBreak +
    '  SharedValue := 2;' + sLineBreak +
    'end;' + sLineBreak +
    '' + sLineBreak +
    'procedure UnusedLocalRoutine;' + sLineBreak +
    'begin' + sLineBreak +
    'end;' + sLineBreak +
    '' + sLineBreak +
    'end.' + sLineBreak,
    TEncoding.UTF8);

  lDprojText :=
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <ProjectGuid>{AA8E07E3-EB7C-4E43-A824-67D863BF1014}</ProjectGuid>' + sLineBreak +
    '    <MainSource>DeadCodeApplyFixture.dpr</MainSource>' + sLineBreak +
    '    <Base>True</Base>' + sLineBreak +
    '    <Config Condition="''$(Config)''==''''">Release</Config>' + sLineBreak +
    '    <ProjectName Condition="''$(ProjectName)''==''''">DeadCodeApplyFixture</ProjectName>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '    <AppType>Console</AppType>' + sLineBreak +
    '    <FrameworkType>None</FrameworkType>' + sLineBreak +
    '    <ProjectVersion>20.2</ProjectVersion>' + sLineBreak +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>' + sLineBreak +
    '    <DCC_DcuOutput>$(DCC_ExeOutput)</DCC_DcuOutput>' + sLineBreak +
    '    <DCC_UnitSearchPath>.;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + sLineBreak +
    '    <DCC_Namespace>System;System.Win;$(DCC_Namespace)</DCC_Namespace>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <DelphiCompile Include="$(MainSource)">' + sLineBreak +
    '      <MainSource>MainSource</MainSource>' + sLineBreak +
    '    </DelphiCompile>' + sLineBreak +
    '    <DCCReference Include="UnitOne.pas"/>' + sLineBreak +
    '    <DCCReference Include="UnitTwo.pas"/>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak;
  if aFailWhenRoutineRemoved then
    lDprojText := lDprojText +
      '  <Target Name="FailAfterDeadCodeRemoval" BeforeTargets="_PasCoreCompile">' + sLineBreak +
      '    <Exec Command="findstr /C:&quot;UnusedLocalRoutine&quot; UnitTwo.pas &gt;nul" IgnoreExitCode="true">' + sLineBreak +
      '      <Output TaskParameter="ExitCode" PropertyName="DeadCodeVerificationExitCode"/>' + sLineBreak +
      '    </Exec>' + sLineBreak +
      '    <Error Condition="''$(DeadCodeVerificationExitCode)''!=''0''" Text="Intentional dead-code verification failure after removal rewrites UnitTwo.pas."/>' + sLineBreak +
      '  </Target>' + sLineBreak;
  lDprojText := lDprojText +
    '  <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" Condition="Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')"/>' + sLineBreak +
    '</Project>' + sLineBreak;
  TFile.WriteAllText(aDprojPath, lDprojText, TEncoding.UTF8);
end;

procedure TDeadCodeApplyCliTests.ApplyAuditProfileProducesNoOpTransaction;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFiles: TJSONArray;
  lJson: TJSONObject;
  lLogPath: string;
  lLogText: string;
  lManifestPath: string;
  lRoot: string;
  lUnitTwoBefore: string;
  lUnitTwoPath: string;
  lVerification: TJSONObject;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'dead-code-apply-noop');
  CreateFixtureProject(lRoot, False, lDprojPath, lUnitTwoPath);
  lUnitTwoBefore := TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8);
  lLogPath := TPath.Combine(TempRoot, 'dead-code-apply-noop.json');

  Assert.IsTrue(RunResolverProcess(
    'dead-code --project ' + QuoteArg(lDprojPath) +
    ' --profile audit --apply --format json --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lLogPath, lExitCode), 'Failed to start dead-code apply command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected no-op apply to succeed. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  lJson := ParseJsonObject(lLogText, lLogPath);
  try
    Assert.AreEqual('noop', lJson.GetValue<string>('status', ''),
      'Expected no-op status. See: ' + lLogPath);
    Assert.AreEqual(0, lJson.GetValue<Integer>('editCount', -1),
      'Expected no planned edits. See: ' + lLogPath);
    RequireJsonArrayKey(lJson, 'files', lFiles);
    Assert.AreEqual(0, lFiles.Count, 'No-op apply must not report changed files.');
    RequireJsonObjectKey(lJson, 'verification', lVerification);
    Assert.AreEqual('not-run', lVerification.GetValue<string>('status', ''),
      'No-op apply should not run build verification.');
    lManifestPath := lJson.GetValue<string>('manifest', '');
    Assert.IsTrue(TFile.Exists(lManifestPath), 'Expected no-op manifest: ' + lManifestPath);
    Assert.IsTrue(Pos('"status":"noop"', ReadUtf8TextFile(lManifestPath)) > 0,
      'Expected no-op status in manifest.');
  finally
    lJson.Free;
  end;
  Assert.AreEqual(lUnitTwoBefore, TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8),
    'No-op apply must not mutate source files.');
end;

procedure TDeadCodeApplyCliTests.AppliesLegacyStaticRemovalTransactionally;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lFile: TJSONObject;
  lFiles: TJSONArray;
  lJson: TJSONObject;
  lLogPath: string;
  lLogText: string;
  lManifestPath: string;
  lRoot: string;
  lUnitTwoText: string;
  lUnitTwoPath: string;
  lVerification: TJSONObject;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'dead-code-apply-success');
  CreateFixtureProject(lRoot, False, lDprojPath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'dead-code-apply-success.json');

  Assert.IsTrue(RunResolverProcess(
    'dead-code --project ' + QuoteArg(lDprojPath) +
    ' --profile legacy-static --apply --format json --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lLogPath, lExitCode), 'Failed to start dead-code apply command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected apply to succeed. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  lJson := ParseJsonObject(lLogText, lLogPath);
  try
    Assert.AreEqual('applied', lJson.GetValue<string>('status', ''),
      'Expected applied status. See: ' + lLogPath);
    Assert.IsTrue(lJson.GetValue<Boolean>('apply', False), 'Expected JSON apply flag.');
    Assert.AreEqual('legacy-static', lJson.GetValue<string>('profile', ''),
      'Expected selected profile. See: ' + lLogPath);
    Assert.IsTrue(lJson.GetValue<Integer>('editCount', 0) > 0,
      'Expected at least one planned removal edit. See: ' + lLogPath);
    RequireJsonObjectKey(lJson, 'verification', lVerification);
    Assert.AreEqual('passed', lVerification.GetValue<string>('status', ''),
      'Expected build verification to pass. See: ' + lLogPath);
    RequireJsonArrayKey(lJson, 'files', lFiles);
    Assert.IsTrue(lFiles.Count > 0, 'Expected changed file entry. See: ' + lLogPath);
    lFile := lFiles.Items[0] as TJSONObject;
    RequireJsonStringKey(lFile, 'backup');
    Assert.IsTrue(TFile.Exists(lFile.GetValue<string>('backup', '')),
      'Expected backup file to exist.');
    lManifestPath := lJson.GetValue<string>('manifest', '');
    Assert.IsTrue(TFile.Exists(lManifestPath), 'Expected apply manifest: ' + lManifestPath);
    Assert.IsTrue(Pos('"status":"applied"', ReadUtf8TextFile(lManifestPath)) > 0,
      'Expected applied status in manifest.');
  finally
    lJson.Free;
  end;

  lUnitTwoText := TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8);
  Assert.AreEqual(0, Pos('procedure UnusedLocalRoutine;', lUnitTwoText),
    'Expected unused routine declaration to be removed.');
  Assert.IsTrue(Pos('procedure UseSharedValue;', lUnitTwoText) > 0,
    'Apply must keep unsupported non-empty routines.');
end;

procedure TDeadCodeApplyCliTests.ApplyRequiresExplicitSafetyProfile;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lLogText: string;
  lRoot: string;
  lUnitTwoPath: string;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'dead-code-apply-missing-profile');
  CreateFixtureProject(lRoot, False, lDprojPath, lUnitTwoPath);
  lLogPath := TPath.Combine(TempRoot, 'dead-code-apply-missing-profile.log');

  Assert.IsTrue(RunResolverProcess(
    'dead-code --project ' + QuoteArg(lDprojPath) + ' --apply --format json',
    RepoRoot, lLogPath, lExitCode), 'Failed to start dead-code apply command.');
  Assert.AreNotEqual(Cardinal(0), lExitCode,
    'Apply must reject commands without an explicit safety profile. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos('dead-code apply requires explicit --profile', lLogText) > 0,
    'Expected explicit safety profile diagnostic. See: ' + lLogPath);
  Assert.IsTrue(Pos('procedure UnusedLocalRoutine;', TFile.ReadAllText(lUnitTwoPath,
    TEncoding.UTF8)) > 0, 'Rejected apply must not mutate source files.');
end;

procedure TDeadCodeApplyCliTests.ApplyRollsBackWhenBuildVerificationFails;
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lLogPath: string;
  lLogText: string;
  lManifestPath: string;
  lRoot: string;
  lUnitTwoBefore: string;
  lUnitTwoPath: string;
  lVerification: TJSONObject;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'dead-code-apply-rollback');
  CreateFixtureProject(lRoot, True, lDprojPath, lUnitTwoPath);
  lUnitTwoBefore := TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8);
  lLogPath := TPath.Combine(TempRoot, 'dead-code-apply-rollback.json');

  Assert.IsTrue(RunResolverProcess(
    'dead-code --project ' + QuoteArg(lDprojPath) +
    ' --profile legacy-static --apply --format json --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lLogPath, lExitCode), 'Failed to start dead-code apply command.');
  Assert.AreNotEqual(Cardinal(0), lExitCode,
    'Expected apply to fail when post-edit build verification fails. See: ' + lLogPath);

  lLogText := ReadUtf8TextFile(lLogPath);
  lJson := ParseJsonObject(lLogText, lLogPath);
  try
    Assert.AreEqual('rolledBack', lJson.GetValue<string>('status', ''),
      'Expected rollback status. See: ' + lLogPath);
    RequireJsonObjectKey(lJson, 'verification', lVerification);
    Assert.AreEqual('failed', lVerification.GetValue<string>('status', ''),
      'Expected failed build verification. See: ' + lLogPath);
    Assert.IsTrue(Pos('Build verification failed', lJson.GetValue<string>('diagnostic', '')) > 0,
      'Expected build verification diagnostic. See: ' + lLogPath);
    lManifestPath := lJson.GetValue<string>('manifest', '');
    Assert.IsTrue(TFile.Exists(lManifestPath), 'Expected rollback manifest: ' + lManifestPath);
    Assert.IsTrue(Pos('"status":"rolledBack"', ReadUtf8TextFile(lManifestPath)) > 0,
      'Expected rollback status in manifest.');
  finally
    lJson.Free;
  end;
  Assert.AreEqual(lUnitTwoBefore, TFile.ReadAllText(lUnitTwoPath, TEncoding.UTF8),
    'Rollback must restore original source text.');
end;

procedure TDeadCodeApplyCliTests.ApplyKeepsRoutinesUsedOnlyFromEntryBlocks;
var
  lDprojPath: string;
  lEntryPath: string;
  lEntryText: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lLogPath: string;
  lRoot: string;
  lVerification: TJSONObject;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'dead-code-apply-entry-blocks');
  ForceDirectories(lRoot);
  lDprojPath := TPath.Combine(lRoot, 'EntryBlocks.dproj');
  lEntryPath := TPath.Combine(lRoot, 'UEntry.pas');
  TFile.WriteAllText(TPath.Combine(lRoot, 'EntryBlocks.dpr'),
    'program EntryBlocks;' + sLineBreak + sLineBreak + 'uses' + sLineBreak +
    '  UEntry in ''UEntry.pas'',' + sLineBreak + '  UInit in ''UInit.pas'';' + sLineBreak +
    sLineBreak + 'begin' + sLineBreak + '  MainTouch;' + sLineBreak + 'end.' + sLineBreak,
    TEncoding.UTF8);
  TFile.WriteAllText(lEntryPath,
    'unit UEntry;' + sLineBreak + sLineBreak + 'interface' + sLineBreak + sLineBreak +
    'procedure MainTouch;' + sLineBreak + 'procedure InitTouch;' + sLineBreak +
    'procedure FinalTouch;' + sLineBreak + sLineBreak + 'implementation' + sLineBreak +
    sLineBreak + 'procedure MainTouch;' + sLineBreak + 'begin' + sLineBreak + 'end;' +
    sLineBreak + sLineBreak + 'procedure InitTouch;' + sLineBreak + 'begin' + sLineBreak +
    'end;' + sLineBreak + sLineBreak + 'procedure FinalTouch;' + sLineBreak + 'begin' +
    sLineBreak + 'end;' + sLineBreak + sLineBreak + 'procedure UnusedLocalRoutine;' +
    sLineBreak + 'begin' + sLineBreak + 'end;' + sLineBreak + sLineBreak + 'end.' + sLineBreak,
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lRoot, 'UInit.pas'),
    'unit UInit;' + sLineBreak + sLineBreak + 'interface' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak + 'uses' + sLineBreak + '  UEntry;' +
    sLineBreak + sLineBreak + 'initialization' + sLineBreak + '  InitTouch;' + sLineBreak +
    sLineBreak + 'finalization' + sLineBreak + '  FinalTouch;' + sLineBreak + sLineBreak +
    'end.' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <ProjectGuid>{5B0C3F6E-2D1A-4E57-9A64-660000000660}</ProjectGuid>' + sLineBreak +
    '    <MainSource>EntryBlocks.dpr</MainSource>' + sLineBreak +
    '    <Base>True</Base>' + sLineBreak +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>' + sLineBreak +
    '    <ProjectName Condition="''$(ProjectName)''==''''">EntryBlocks</ProjectName>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '    <AppType>Console</AppType>' + sLineBreak +
    '    <FrameworkType>None</FrameworkType>' + sLineBreak +
    '    <ProjectVersion>20.2</ProjectVersion>' + sLineBreak +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>' + sLineBreak +
    '    <DCC_DcuOutput>$(DCC_ExeOutput)</DCC_DcuOutput>' + sLineBreak +
    '    <DCC_UnitSearchPath>.;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + sLineBreak +
    '    <DCC_Namespace>System;System.Win;$(DCC_Namespace)</DCC_Namespace>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <DelphiCompile Include="$(MainSource)">' + sLineBreak +
    '      <MainSource>MainSource</MainSource>' + sLineBreak +
    '    </DelphiCompile>' + sLineBreak +
    '    <DCCReference Include="UEntry.pas"/>' + sLineBreak +
    '    <DCCReference Include="UInit.pas"/>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '  <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" ' +
    'Condition="Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')"/>' + sLineBreak +
    '</Project>' + sLineBreak, TEncoding.UTF8);
  lLogPath := TPath.Combine(TempRoot, 'dead-code-apply-entry-blocks.json');

  Assert.IsTrue(RunResolverProcess(
    'dead-code --project ' + QuoteArg(lDprojPath) +
    ' --profile legacy-static --apply --format json --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lLogPath, lExitCode), 'Failed to start dead-code apply command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected apply to succeed. See: ' + lLogPath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
  try
    Assert.AreEqual('applied', lJson.GetValue<string>('status', ''), lLogPath);
    Assert.AreEqual(1, lJson.GetValue<Integer>('editCount', -1),
      'Only UnusedLocalRoutine may be removed. See: ' + lLogPath);
    RequireJsonObjectKey(lJson, 'verification', lVerification);
    Assert.AreEqual('passed', lVerification.GetValue<string>('status', ''), lLogPath);
  finally
    lJson.Free;
  end;
  lEntryText := TFile.ReadAllText(lEntryPath, TEncoding.UTF8);
  Assert.AreEqual(0, Pos('procedure UnusedLocalRoutine;', lEntryText),
    'The unused routine must be removed.');
  Assert.IsTrue(Pos('procedure MainTouch;' + sLineBreak + 'begin', lEntryText) > 0,
    'The routine used by the main block must be kept.');
  Assert.IsTrue(Pos('procedure InitTouch;' + sLineBreak + 'begin', lEntryText) > 0,
    'The routine used by an initialization block must be kept.');
  Assert.IsTrue(Pos('procedure FinalTouch;' + sLineBreak + 'begin', lEntryText) > 0,
    'The routine used by a finalization block must be kept.');
end;

procedure TDeadCodeApplyCliTests.ApplyKeepsOverloadsAndShortFormBodiesUsedElsewhere;
const
  cKept: array[0..4] of string = ('procedure Ov(a: Integer);' + sLineBreak + 'begin',
    'procedure Ov(const s: string);' + sLineBreak + 'begin',
    'procedure Helper;' + sLineBreak + 'begin',
    'procedure Ov2(a: Integer; b: Integer);' + sLineBreak + 'begin',
    'procedure Ov2(const s: string);' + sLineBreak + 'begin');
var
  lDprojPath: string;
  lExitCode: Cardinal;
  lJson: TJSONObject;
  lKept: string;
  lLogPath: string;
  lRoot: string;
  lUnitPath: string;
  lUnitText: string;
  lVerification: TJSONObject;
begin
  EnsureResolverBuilt;
  lRoot := TPath.Combine(TempRoot, 'dead-code-apply-overloads');
  ForceDirectories(lRoot);
  lDprojPath := TPath.Combine(lRoot, 'Overloads.dproj');
  lUnitPath := TPath.Combine(lRoot, 'UD.pas');
  TFile.WriteAllText(TPath.Combine(lRoot, 'Overloads.dpr'),
    'program Overloads;' + sLineBreak + sLineBreak + 'uses' + sLineBreak +
    '  UD in ''UD.pas'',' + sLineBreak + '  UE in ''UE.pas'';' + sLineBreak + sLineBreak +
    'begin' + sLineBreak + '  Run;' + sLineBreak + '  Ov(1);' + sLineBreak + '  Helper(2);' +
    sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(lUnitPath,
    'unit UD;' + sLineBreak + sLineBreak + 'interface' + sLineBreak + sLineBreak +
    'procedure Ov(a: Integer); overload;' + sLineBreak +
    'procedure Ov(const s: string); overload;' + sLineBreak +
    'procedure Helper(a: Integer);' + sLineBreak +
    'procedure Ov2(a: Integer; b: Integer = 0); overload;' + sLineBreak +
    'procedure Ov2(const s: string); overload;' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    'procedure Ov(a: Integer);' + sLineBreak + 'begin' + sLineBreak + 'end;' + sLineBreak +
    sLineBreak + 'procedure Ov(const s: string);' + sLineBreak + 'begin' + sLineBreak +
    'end;' + sLineBreak + sLineBreak + 'procedure Helper;' + sLineBreak + 'begin' + sLineBreak +
    'end;' + sLineBreak + sLineBreak + 'procedure Other;' + sLineBreak + sLineBreak +
    '  procedure Helper;' + sLineBreak + '  begin' + sLineBreak + '  end;' + sLineBreak +
    sLineBreak + 'begin' + sLineBreak + 'end;' + sLineBreak + sLineBreak +
    'procedure Ov2(a: Integer; b: Integer);' + sLineBreak + 'begin' + sLineBreak + 'end;' +
    sLineBreak + sLineBreak + 'procedure Ov2(const s: string);' + sLineBreak + 'begin' +
    sLineBreak + 'end;' + sLineBreak + sLineBreak + 'end.' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lRoot, 'UE.pas'),
    'unit UE;' + sLineBreak + sLineBreak + 'interface' + sLineBreak + sLineBreak +
    'procedure Run;' + sLineBreak + sLineBreak + 'implementation' + sLineBreak + sLineBreak +
    'uses' + sLineBreak + '  UD;' + sLineBreak + sLineBreak + 'procedure Run;' + sLineBreak +
    'begin' + sLineBreak + '  Ov2(5);' + sLineBreak + 'end;' + sLineBreak + sLineBreak + 'end.' +
    sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <ProjectGuid>{5B0C3F6E-2D1A-4E57-9A64-660000000662}</ProjectGuid>' + sLineBreak +
    '    <MainSource>Overloads.dpr</MainSource>' + sLineBreak +
    '    <Base>True</Base>' + sLineBreak +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>' + sLineBreak +
    '    <ProjectName Condition="''$(ProjectName)''==''''">Overloads</ProjectName>' + sLineBreak +
    '    <TargetedPlatforms>1</TargetedPlatforms>' + sLineBreak +
    '    <AppType>Console</AppType>' + sLineBreak +
    '    <FrameworkType>None</FrameworkType>' + sLineBreak +
    '    <ProjectVersion>20.2</ProjectVersion>' + sLineBreak +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' + sLineBreak +
    '    <DCC_ExeOutput>.\bin</DCC_ExeOutput>' + sLineBreak +
    '    <DCC_DcuOutput>$(DCC_ExeOutput)</DCC_DcuOutput>' + sLineBreak +
    '    <DCC_UnitSearchPath>.;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + sLineBreak +
    '    <DCC_Namespace>System;System.Win;$(DCC_Namespace)</DCC_Namespace>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <ItemGroup>' + sLineBreak +
    '    <DelphiCompile Include="$(MainSource)">' + sLineBreak +
    '      <MainSource>MainSource</MainSource>' + sLineBreak +
    '    </DelphiCompile>' + sLineBreak +
    '    <DCCReference Include="UD.pas"/>' + sLineBreak +
    '    <DCCReference Include="UE.pas"/>' + sLineBreak +
    '  </ItemGroup>' + sLineBreak +
    '  <Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets" ' +
    'Condition="Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')"/>' + sLineBreak +
    '</Project>' + sLineBreak, TEncoding.UTF8);
  lLogPath := TPath.Combine(TempRoot, 'dead-code-apply-overloads.json');

  Assert.IsTrue(RunResolverProcess(
    'dead-code --project ' + QuoteArg(lDprojPath) +
    ' --profile legacy-static --apply --format json --delphi 23.0 --platform Win32 --config Debug',
    RepoRoot, lLogPath, lExitCode), 'Failed to start dead-code apply command.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected apply to succeed. See: ' + lLogPath);
  lJson := ParseJsonObject(ReadUtf8TextFile(lLogPath), lLogPath);
  try
    // Only the unused nested Helper in Other is removable.
    Assert.AreEqual('applied', lJson.GetValue<string>('status', ''), lLogPath);
    RequireJsonObjectKey(lJson, 'verification', lVerification);
    Assert.AreEqual('passed', lVerification.GetValue<string>('status', ''), lLogPath);
  finally
    lJson.Free;
  end;
  lUnitText := TFile.ReadAllText(lUnitPath, TEncoding.UTF8);
  for lKept in cKept do
    Assert.IsTrue(Pos(lKept, lUnitText) > 0, 'Called routine body was removed: ' + lKept);
end;

initialization
  TDUnitX.RegisterTestFixture(TDeadCodeApplyCliTests);

end.
