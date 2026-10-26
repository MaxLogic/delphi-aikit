unit Test.RootMemberAbsence;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TRootMemberAbsenceTests = class
  public
    [TestCase('win32 component G', 'win32,dcc32.exe,component,G,True')]
    [TestCase('win32 component lCondition', 'win32,dcc32.exe,component,lCondition,True')]
    [TestCase('win32 component FTag', 'win32,dcc32.exe,component,FTag,True')]
    [TestCase('win32 component Tag', 'win32,dcc32.exe,component,Tag,False')]
    [TestCase('win32 component Name', 'win32,dcc32.exe,component,Name,False')]
    [TestCase('win32 component Owner', 'win32,dcc32.exe,component,Owner,False')]
    [TestCase('win32 component ClassName', 'win32,dcc32.exe,component,ClassName,False')]
    [TestCase('win32 component DestroyComponents', 'win32,dcc32.exe,component,DestroyComponents,False')]
    [TestCase('win32 component Loaded', 'win32,dcc32.exe,component,Loaded,False')]
    [TestCase('win32 component FComponentStyle', 'win32,dcc32.exe,component,FComponentStyle,False')]
    [TestCase('win32 component TComponentAsyncResult', 'win32,dcc32.exe,component,TComponentAsyncResult,False')]
    [TestCase('win32 interfaced G', 'win32,dcc32.exe,interfaced,G,True')]
    [TestCase('win32 interfaced FieldName', 'win32,dcc32.exe,interfaced,FieldName,True')]
    [TestCase('win32 interfaced Caption', 'win32,dcc32.exe,interfaced,Caption,True')]
    [TestCase('win32 interfaced GetRefCount', 'win32,dcc32.exe,interfaced,GetRefCount,True')]
    [TestCase('win32 interfaced RefCount', 'win32,dcc32.exe,interfaced,RefCount,False')]
    [TestCase('win32 interfaced FRefCount', 'win32,dcc32.exe,interfaced,FRefCount,False')]
    [TestCase('win32 interfaced QueryInterface', 'win32,dcc32.exe,interfaced,QueryInterface,False')]
    [TestCase('win32 interfaced ClassName', 'win32,dcc32.exe,interfaced,ClassName,False')]
    [TestCase('win32 interface G', 'win32,dcc32.exe,interface,G,True')]
    [TestCase('win32 interface ClassName', 'win32,dcc32.exe,interface,ClassName,True')]
    [TestCase('win32 interface QueryInterface', 'win32,dcc32.exe,interface,QueryInterface,False')]
    [TestCase('win32 interface _AddRef', 'win32,dcc32.exe,interface,_AddRef,False')]
    [TestCase('win32 object G', 'win32,dcc32.exe,object,G,True')]
    [TestCase('win32 object ClassName', 'win32,dcc32.exe,object,ClassName,False')]
    [TestCase('win32 explicit-object ClassName', 'win32,dcc32.exe,explicit-object,ClassName,False')]
    [TestCase('win32 exception Message', 'win32,dcc32.exe,exception,Message,False')]
    [TestCase('win32 stringlist Count', 'win32,dcc32.exe,stringlist,Count,False')]
    [TestCase('win32 form Caption', 'win32,dcc32.exe,form,Caption,False')]
    [TestCase('win32 attribute FValue', 'win32,dcc32.exe,attribute,FValue,False')]
    [TestCase('win64 component G', 'win64,dcc64.exe,component,G,True')]
    [TestCase('win64 component lCondition', 'win64,dcc64.exe,component,lCondition,True')]
    [TestCase('win64 component FTag', 'win64,dcc64.exe,component,FTag,True')]
    [TestCase('win64 component Tag', 'win64,dcc64.exe,component,Tag,False')]
    [TestCase('win64 component Name', 'win64,dcc64.exe,component,Name,False')]
    [TestCase('win64 component Owner', 'win64,dcc64.exe,component,Owner,False')]
    [TestCase('win64 component ClassName', 'win64,dcc64.exe,component,ClassName,False')]
    [TestCase('win64 component DestroyComponents', 'win64,dcc64.exe,component,DestroyComponents,False')]
    [TestCase('win64 component Loaded', 'win64,dcc64.exe,component,Loaded,False')]
    [TestCase('win64 component FComponentStyle', 'win64,dcc64.exe,component,FComponentStyle,False')]
    [TestCase('win64 component TComponentAsyncResult', 'win64,dcc64.exe,component,TComponentAsyncResult,False')]
    [TestCase('win64 interfaced G', 'win64,dcc64.exe,interfaced,G,True')]
    [TestCase('win64 interfaced FieldName', 'win64,dcc64.exe,interfaced,FieldName,True')]
    [TestCase('win64 interfaced Caption', 'win64,dcc64.exe,interfaced,Caption,True')]
    [TestCase('win64 interfaced GetRefCount', 'win64,dcc64.exe,interfaced,GetRefCount,True')]
    [TestCase('win64 interfaced RefCount', 'win64,dcc64.exe,interfaced,RefCount,False')]
    [TestCase('win64 interfaced FRefCount', 'win64,dcc64.exe,interfaced,FRefCount,False')]
    [TestCase('win64 interfaced QueryInterface', 'win64,dcc64.exe,interfaced,QueryInterface,False')]
    [TestCase('win64 interfaced ClassName', 'win64,dcc64.exe,interfaced,ClassName,False')]
    [TestCase('win64 interface G', 'win64,dcc64.exe,interface,G,True')]
    [TestCase('win64 interface ClassName', 'win64,dcc64.exe,interface,ClassName,True')]
    [TestCase('win64 interface QueryInterface', 'win64,dcc64.exe,interface,QueryInterface,False')]
    [TestCase('win64 interface _AddRef', 'win64,dcc64.exe,interface,_AddRef,False')]
    [TestCase('win64 object G', 'win64,dcc64.exe,object,G,True')]
    [TestCase('win64 object ClassName', 'win64,dcc64.exe,object,ClassName,False')]
    [TestCase('win64 explicit-object ClassName', 'win64,dcc64.exe,explicit-object,ClassName,False')]
    [TestCase('win64 exception Message', 'win64,dcc64.exe,exception,Message,False')]
    [TestCase('win64 stringlist Count', 'win64,dcc64.exe,stringlist,Count,False')]
    [TestCase('win64 form Caption', 'win64,dcc64.exe,form,Caption,False')]
    [TestCase('win64 attribute FValue', 'win64,dcc64.exe,attribute,FValue,False')]
    [TestCase('win64 stringlist Create', 'win64,dcc64.exe,stringlist,Create,False')]
    [TestCase('win64 component Create', 'win64,dcc64.exe,component,Create,False')]
    [TestCase('win64 class-unit helper', 'win64,dcc64.exe,skia,ToSkImage,False')]
    [Category('DAK418')]
    procedure NamedRootWitnessProtectsVisibleMembers(const aPlatform, aCompilerName, aShape, aName: string;
      const aAbsent: Boolean);

    [TestCase('win32 helper', 'win32,dcc32.exe,helper')]
    [TestCase('win64 helper', 'win64,dcc64.exe,helper')]
    [TestCase('win32 lookup', 'win32,dcc32.exe,lookup')]
    [TestCase('win64 lookup', 'win64,dcc64.exe,lookup')]
    [TestCase('win32 guard', 'win32,dcc32.exe,guard')]
    [TestCase('win64 guard', 'win64,dcc64.exe,guard')]
    [TestCase('win32 selection', 'win32,dcc32.exe,selection')]
    [TestCase('win64 selection', 'win64,dcc64.exe,selection')]
    [TestCase('win64 site helper precedence', 'win64,dcc64.exe,precedence')]
    [TestCase('captured DBX method', 'win64,dcc64.exe,captured')]
    [TestCase('captured DBX method repeated', 'win64,dcc64.exe,captured-repeat')]
    [TestCase('capture absent control', 'win64,dcc64.exe,capture-control')]
    [TestCase('namespace long short', 'win64,dcc64.exe,alias-long-short')]
    [TestCase('namespace short long', 'win64,dcc64.exe,alias-short-long')]
    [TestCase('win32 memo', 'win32,dcc32.exe,memo')]
    [TestCase('win64 memo', 'win64,dcc64.exe,memo')]
    [Category('DAK418')]
    procedure NamedRootBoundaries(const aPlatform, aCompilerName, aShape: string);
    [TestCase('Captured private getter property', 'win64,dcc64.exe,captured-property')]
    [TestCase('Site private getter property', 'win64,dcc64.exe,site-property')]
    [TestCase('Scope long short identity', 'win64,dcc64.exe,scope-long-short')]
    [TestCase('Scope short long identity', 'win64,dcc64.exe,scope-short-long')]
    [Category('DS742Fix5Native')]
    procedure NamedRootScopeRegressions(const aPlatform, aCompilerName, aShape: string);
    [TestCase('Declaration then site', 'False')]
    [TestCase('Site then declaration', 'True')]
    [Category('DS742Fix6Native')]
    procedure NamedRootMemoKeepsDeclarationAndSiteScopes(const aSiteFirst: Boolean);

    [Test]
    [TestCase('Win32 Halt0', 'win32,dcc32.exe,halt')]
    [TestCase('Win64 Halt0', 'win64,dcc64.exe,halt')]
    [TestCase('Win32 early exit', 'win32,dcc32.exe,exit')]
    [TestCase('Win64 early exit', 'win64,dcc64.exe,exit')]
    [TestCase('Write failure', 'win64,dcc64.exe,write-failure')]
    [TestCase('Flush failure', 'win64,dcc64.exe,flush-failure')]
    [TestCase('Large dependencies', 'win64,dcc64.exe,large-dependencies')]
    [TestCase('Large runtime', 'win64,dcc64.exe,large-runtime')]
    procedure ConsumerRefusesIncompleteOrFailedWitness(const aPlatform, aCompilerName, aMode: string);
    [Test]
    procedure ProviderCleanupPreservesUnknownFiles;
    [TestCase('win32 halt', 'win32,dcc32.exe,halt')]
    [TestCase('win32 exit', 'win32,dcc32.exe,exit')]
    [TestCase('win32 write-failure', 'win32,dcc32.exe,write-failure')]
    [TestCase('win32 flush-failure', 'win32,dcc32.exe,flush-failure')]
    [TestCase('win32 large-dependencies', 'win32,dcc32.exe,large-dependencies')]
    [TestCase('win32 large-runtime', 'win32,dcc32.exe,large-runtime')]
    [TestCase('win64 halt', 'win64,dcc64.exe,halt')]
    [TestCase('win64 exit', 'win64,dcc64.exe,exit')]
    [TestCase('win64 write-failure', 'win64,dcc64.exe,write-failure')]
    [TestCase('win64 flush-failure', 'win64,dcc64.exe,flush-failure')]
    [TestCase('win64 large-dependencies', 'win64,dcc64.exe,large-dependencies')]
    [TestCase('win64 large-runtime', 'win64,dcc64.exe,large-runtime')]
    [Category('DAK418')]
    procedure NamedConsumerRefusesIncompleteWitness(const aPlatform, aCompilerName, aMode: string);
    [TestCase('Win32', 'win32,dcc32.exe')]
    [TestCase('Win64', 'win64,dcc64.exe')]
    [Category('DAK418')]
    procedure NamedRootClosureDriftInvalidatesEvidence(const aPlatform, aCompilerName: string);
    [Test]
    [TestCase('Win32', 'win32,dcc32.exe')]
    [TestCase('Win64', 'win64,dcc64.exe')]
    procedure NativeWitnessDistinguishesExactNames(const aPlatform, aCompilerName: string);
    [Test]
    procedure MissingToolchainAndInvalidCompilerRemainUnavailable;
    [Test]
    procedure LockedInputsPreventDriftAndNewProviderRejectsCorruptSdk;
    [Test]
    procedure UnavailableScratchRetainsOptionalRefusal;
    [Test]
    procedure RetargetedSdkParentInvalidatesMemoizedEvidence;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  maxLogic.ioutils,
  Dak.RootMemberAbsence, DelphiSemantics.RootMemberAbsence,
  Test.Support;

const
  cStudioRoot = 'C:\Program Files (x86)\Embarcadero\Studio\23.0';

procedure TRootMemberAbsenceTests.NamedRootClosureDriftInvalidatesEvidence(
  const aPlatform, aCompilerName: string);
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lNamed: IDelphiSemanticNamedRootMemberAbsence;
  lRoot: TDelphiSemanticQualifiedRootType;
  lDirectory, lFirst, lSecond, lAlias, lName, lReason: string;
  lExit: Cardinal;
begin
  lDirectory := UniqueTempPath('named-closure-drift');
  lFirst := TPath.Combine(lDirectory, 'first');
  lSecond := TPath.Combine(lDirectory, 'second');
  lAlias := TPath.Combine(lDirectory, 'sdk');
  TDirectory.CreateDirectory(lFirst);
  TDirectory.CreateDirectory(lSecond);
  // Both SDK copies belong to this test. All unchanged DCUs have the same
  // file identity across the retarget; only the named closure input changes.
  for lName in ['System.Classes.dcu', 'System.Rtti.dcu', 'System.SyncObjs.dcu', 'System.Diagnostics.dcu', 'System.TimeSpan.dcu', 'System.Generics.Collections.dcu', 'System.Generics.Defaults.dcu', 'System.Math.dcu', 'System.Hash.dcu', 'Winapi.ActiveX.dcu', 'Winapi.Messages.dcu', 'System.Variants.dcu', 'System.VarUtils.dcu', 'System.SysUtils.dcu', 'System.Internal.ExcUtils.dcu', 'System.Character.dcu', 'System.RTLConsts.dcu', 'Winapi.PsAPI.dcu', 'Winapi.SHFolder.dcu', 'Winapi.ImageHlp.dcu', 'System.SysConst.dcu', 'Winapi.Windows.dcu', 'Winapi.Windows.PkgHelper.dcu', 'System.UITypes.dcu', 'System.Types.dcu', 'System.TypInfo.dcu', 'SysInit.dcu', 'System.dcu'] do
  begin
    TFile.Copy(CombinePath([cStudioRoot, 'lib', aPlatform, 'release', lName]),
      TPath.Combine(lFirst, lName));
    if SameText(lName, 'System.Classes.dcu') then
      TFile.WriteAllText(TPath.Combine(lSecond, lName), 'changed named closure', TEncoding.ASCII)
    else
      Assert.IsTrue(CreateHardLink(PChar(TPath.Combine(lSecond, lName)),
        PChar(TPath.Combine(lFirst, lName)), nil));
  end;
  Assert.IsTrue(RunProcess(GetEnvironmentVariable('COMSPEC'),
    '/d /c mklink /J "' + lAlias + '" "' + lFirst + '"', lDirectory,
    TPath.Combine(lDirectory, 'link-first.log'), lExit));
  Assert.AreEqual<Cardinal>(0, lExit);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\' + aCompilerName), lAlias, lDirectory, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticNamedRootMemberAbsence, lNamed));
  lRoot := Default(TDelphiSemanticQualifiedRootType);
  lRoot.Kind := 'class';
  lRoot.TypeName := 'TComponent';
  lRoot.LookupUnits := ['System.Classes'];
  Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'DAK418_NoMember'));
  Assert.AreNotEqual('', lProvider.EvidenceFingerprint);
  Assert.IsTrue(MoveFile(PChar(lAlias), PChar(TPath.Combine(lDirectory, 'previous-sdk'))));
  Assert.IsTrue(RunProcess(GetEnvironmentVariable('COMSPEC'),
    '/d /c mklink /J "' + lAlias + '" "' + lSecond + '"', lDirectory,
    TPath.Combine(lDirectory, 'link-second.log'), lExit));
  Assert.AreEqual<Cardinal>(0, lExit);
  Assert.AreEqual('', lProvider.EvidenceFingerprint,
    'The base compiler, System and SysInit identities are unchanged; the named closure drifted.');
  Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'DAK418_NoMember'));
end;

procedure TRootMemberAbsenceTests.NamedRootScopeRegressions(
  const aPlatform, aCompilerName, aShape: string);
begin
  NamedRootBoundaries(aPlatform, aCompilerName, aShape);
end;

procedure TRootMemberAbsenceTests.NamedRootBoundaries(
  const aPlatform, aCompilerName, aShape: string);
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lNamed: IDelphiSemanticNamedRootMemberAbsence;
  lLookup: TDakNativeRootLookup;
  lRoot: TDelphiSemanticQualifiedRootType;
  lReason, lWork, lSdk, lShadow: string;
begin
  lWork := UniqueTempPath('named-boundary-' + aShape);
  TDirectory.CreateDirectory(lWork);
  lSdk := CombinePath([cStudioRoot, 'lib', aPlatform, 'release']);
  lLookup := Default(TDakNativeRootLookup);
  lLookup.fUnitScopeNames := ['System', 'System.Win', 'Winapi', 'Vcl'];
  if MatchText(aShape, ['alias-long-short', 'alias-short-long', 'scope-long-short', 'scope-short-long']) then
    lLookup.fUnitScopeNames := ['FireDAC'] + lLookup.fUnitScopeNames;
  if aShape = 'selection' then
  begin
    lShadow := TPath.Combine(lWork, 'shadow');
    TDirectory.CreateDirectory(lShadow);
    TFile.WriteAllText(TPath.Combine(lShadow, 'Classes.pas'),
      'unit Classes; interface implementation end.', TEncoding.ASCII);
    lLookup.fUnitPaths := [lShadow, lSdk];
    lLookup.fSdkLibRoot := TPath.Combine(cStudioRoot, 'lib');
  end;
  lProvider := TryCreateNativeRootMemberAbsence(TPath.Combine(cStudioRoot, 'bin\' + aCompilerName),
    lSdk, lWork, lLookup, CreateNativeWitnessIO, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticNamedRootMemberAbsence, lNamed));
  lRoot := Default(TDelphiSemanticQualifiedRootType);
  lRoot.Kind := 'class';
  lRoot.TypeName := 'TListColumn';
  lRoot.LookupUnits := ['Vcl.ComCtrls'];
  if MatchText(aShape, ['captured-property', 'site-property']) then
  begin
    lRoot.TypeName := 'TFDCustomConnection';
    lRoot.LookupUnits := ['FireDAC.Comp.Client', 'FireDAC.ADO.Migrate'];
    if aShape = 'captured-property' then
      Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'ConnectionTimeout'),
        'The private-getter helper property is not captured by the descendant.');
    if aShape = 'site-property' then
    begin
      lRoot.LookupUnits := ['FireDAC.Comp.Client'];
      Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.ADO.Migrate'], 'ProbeMissing742'), 'The same site context must prove genuine absence.');
      Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.ADO.Migrate'], 'ConnectionTimeout'), 'The site helper property is visible.');
    end;
  end else if MatchText(aShape, ['scope-long-short', 'scope-short-long']) then
  begin
    lRoot.TypeName := 'TFDConnection';
    lRoot.LookupUnits := ['FireDAC.Comp.Client'];
    if aShape = 'scope-long-short' then
    begin
      Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.ADO.Migrate', 'FireDAC.DBX.Migrate', 'ADO.Migrate'], 'ProbeMissing742'));
      Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.ADO.Migrate', 'FireDAC.DBX.Migrate', 'ADO.Migrate'], 'ConnectionTimeout'));
    end else begin
      Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['ADO.Migrate', 'FireDAC.DBX.Migrate', 'FireDAC.ADO.Migrate'], 'ProbeMissing742'));
      Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['ADO.Migrate', 'FireDAC.DBX.Migrate', 'FireDAC.ADO.Migrate'], 'ConnectionTimeout'));
    end;
  end else if MatchText(aShape, ['captured', 'captured-repeat', 'capture-control']) then
  begin
    lRoot.TypeName := 'TFDCustomConnection';
    lRoot.LookupUnits := ['FireDAC.Comp.Client', 'FireDAC.DBX.Migrate'];
    if aShape = 'capture-control' then
      lRoot.LookupUnits := ['FireDAC.Comp.Client', 'FireDAC.ADO.Migrate'];
    Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot,
      ['FireDAC.ADO.Migrate'], 'ProbeMissing742'), 'Genuine absence must remain provable.');
    if aShape = 'captured-repeat' then
      Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.DBX.Migrate', 'FireDAC.ADO.Migrate'], 'GetLoginUsername'))
    else
      Assert.AreEqual(aShape = 'capture-control', lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.ADO.Migrate'], 'GetLoginUsername'));
  end else if MatchText(aShape, ['alias-long-short', 'alias-short-long']) then
  begin
    lRoot.TypeName := 'TFDConnection';
    if aShape = 'alias-long-short' then
    begin
      lRoot.LookupUnits := ['FireDAC.Comp.Client', 'FireDAC.ADO.Migrate'];
      Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.DBX.Migrate', 'ADO.Migrate'], 'ProbeMissing742'));
      Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.DBX.Migrate', 'ADO.Migrate'], 'ConnectionTimeout'));
    end else begin
      lRoot.LookupUnits := ['FireDAC.Comp.Client', 'ADO.Migrate'];
      Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.DBX.Migrate', 'FireDAC.ADO.Migrate'], 'ProbeMissing742'));
      Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot,
        ['FireDAC.DBX.Migrate', 'FireDAC.ADO.Migrate'], 'ConnectionTimeout'));
    end;
  end else if aShape = 'precedence' then
  begin
    lRoot.TypeName := 'TFDConnection';
    lRoot.LookupUnits := ['FireDAC.Comp.Client', 'FireDAC.ADO.Migrate'];
    Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot,
      ['FireDAC.DBX.Migrate', 'FireDAC.ADO.Migrate'], 'ProbeMissing742'),
      'The competing-helper context must support a real absence query.');
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot,
      ['FireDAC.DBX.Migrate', 'FireDAC.ADO.Migrate'], 'ConnectionTimeout'),
      'The site ADO helper must win over the DBX helper even when ADO is repeated.');
  end else if MatchText(aShape, ['helper', 'memo']) then
  begin
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'OrderTag'),
      'Class lookup units must retain helpers from the declaring context.');
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, ['Vcl.ComCtrls'], 'OrderTag'),
      'The site helper is a visible member.');
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'ordertag'));
    Assert.AreEqual<Integer>(0, Length(TDirectory.GetDirectories(lWork, 'run-*', TSearchOption.soAllDirectories)),
      'Named probes must be cleaned immediately, including memo hits.');
    TFile.WriteAllText(TPath.Combine(lWork, 'unknown.txt'), 'keep', TEncoding.ASCII);
    lNamed := nil;
    lProvider := nil;
    Assert.AreEqual('keep', TFile.ReadAllText(TPath.Combine(lWork, 'unknown.txt')));
  end else if aShape = 'lookup' then
  begin
    lRoot.TypeName := 'TBitmap';
    lRoot.LookupUnits := ['Winapi.Windows', 'Vcl.Graphics'];
    Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'G'), lRoot.TypeName);
    lRoot.LookupUnits := ['Vcl.Graphics', 'Winapi.Windows'];
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'G'),
      'The last uses entry selects a record, which cannot be a class root.');
    lRoot.TypeName := 'Classes.TComponent';
    lRoot.LookupUnits := ['Classes'];
    Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'G'), lRoot.TypeName);
    lRoot.TypeName := 'TComponent';
    lRoot.LookupUnits := nil;
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'G'));
    lRoot.Kind := 'interface';
    lRoot.TypeName := 'IUnknown';
    lRoot.LookupUnits := ['System.Classes'];
    Assert.IsTrue(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'G'), lRoot.TypeName);
  end else if aShape = 'selection' then
  begin
    lRoot.TypeName := 'Classes.TComponent';
    lRoot.LookupUnits := ['Classes'];
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'G'));
    Assert.AreEqual<Integer>(0, Length(TDirectory.GetDirectories(lWork, 'run-*', TSearchOption.soAllDirectories)));
    lRoot.TypeName := 'System.TObject';
    lRoot.LookupUnits := nil;
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, ['Foreign.UnitName'], 'G'));
  end else begin
    for var lTypeName in ['TObject^', '&TObject', 'TObject;Halt(0)'] do
    begin
      lRoot.TypeName := lTypeName;
      Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'G'));
    end;
    lRoot.TypeName := 'System.TObject';
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, ['Bad;Unit'], 'G'));
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'G.X'));
    lRoot.Kind := 'record';
    Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'G'));
    Assert.AreEqual<Integer>(0, Length(TDirectory.GetDirectories(lWork, 'run-*', TSearchOption.soAllDirectories)));
  end;
end;

procedure TRootMemberAbsenceTests.NamedRootWitnessProtectsVisibleMembers(
  const aPlatform, aCompilerName, aShape, aName: string; const aAbsent: Boolean);
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lNamed: IDelphiSemanticNamedRootMemberAbsence;
  lReason: string;
  lRoot: TDelphiSemanticQualifiedRootType;
begin
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\' + aCompilerName),
    CombinePath([cStudioRoot, 'lib', aPlatform, 'release']),
    UniqueTempPath('named-root-' + aShape + '-' + aName), lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticNamedRootMemberAbsence, lNamed),
    'The native provider must offer the optional named-root witness.');
  lRoot := Default(TDelphiSemanticQualifiedRootType);
  lRoot.Kind := 'class';
  lRoot.TypeName := 'System.TObject';
  if aShape = 'component' then
  begin
    lRoot.TypeName := 'TComponent';
    lRoot.LookupUnits := ['System.Classes'];
  end else if aShape = 'interfaced' then
    lRoot.TypeName := 'System.TInterfacedObject'
  else if aShape = 'explicit-object' then
    lRoot.TypeName := 'TObject'
  else if aShape = 'exception' then
  begin
    lRoot.TypeName := 'Exception';
    lRoot.LookupUnits := ['System.SysUtils'];
  end else if aShape = 'stringlist' then
  begin
    lRoot.TypeName := 'TStringList';
    lRoot.LookupUnits := ['System.Classes'];
  end else if aShape = 'form' then
  begin
    lRoot.TypeName := 'TForm';
    lRoot.LookupUnits := ['Vcl.Forms'];
  end else if aShape = 'skia' then
  begin
    lRoot.TypeName := 'TBitmap';
    lRoot.LookupUnits := ['Vcl.Graphics', 'Vcl.Skia'];
  end else if aShape = 'attribute' then
  begin
    lRoot.TypeName := 'TDefaultAttributeBase';
    lRoot.LookupUnits := ['System.Classes'];
  end else if aShape = 'interface' then
  begin
    lRoot.Kind := 'interface';
    lRoot.TypeName := 'System.IInterface';
  end;
  Assert.AreEqual(aAbsent, lNamed.IsNamedRootMemberAbsent(lRoot, [], aName),
    aShape + '.' + aName);
  Assert.AreNotEqual('', lProvider.EvidenceFingerprint);
end;

procedure TRootMemberAbsenceTests.NamedRootMemoKeepsDeclarationAndSiteScopes(const aSiteFirst: Boolean);
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lNamed: IDelphiSemanticNamedRootMemberAbsence;
  lRoot: TDelphiSemanticQualifiedRootType;
  lSiteUnits: TArray<string>;
  lReason: string;
  lSite: Boolean;
begin
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    CombinePath([cStudioRoot, 'lib', 'Win64', 'release']),
    UniqueTempPath('named-declaration-site-memo'), lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticNamedRootMemberAbsence, lNamed));
  lRoot := Default(TDelphiSemanticQualifiedRootType);
  lRoot.Kind := 'class';
  lRoot.TypeName := 'TFDCustomConnection';
  // Both requests share a provider lifetime and the same combined unit set.
  // Only the boundary between captured declaration and site scopes changes.
  for var i := 0 to 1 do
  begin
    lSite := (i = 0) = aSiteFirst;
    lRoot.LookupUnits := ['FireDAC.Comp.Client'];
    lSiteUnits := nil;
    if lSite then
      lSiteUnits := ['FireDAC.ADO.Migrate']
    else
      lRoot.LookupUnits := lRoot.LookupUnits + ['FireDAC.ADO.Migrate'];
    Assert.AreEqual(not lSite, lNamed.IsNamedRootMemberAbsent(lRoot, lSiteUnits, 'ConnectionTimeout'),
      'The private-getter property is visible only at the helper-bearing site.');
  end;
end;

procedure TRootMemberAbsenceTests.NativeWitnessDistinguishesExactNames(
  const aPlatform, aCompilerName: string);
var
  lCount: Integer;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-root-' + aPlatform);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\' + aCompilerName),
    TPath.Combine(cStudioRoot, 'lib\' + aPlatform + '\debug'), lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.AreNotEqual('', lProvider.EvidenceFingerprint);
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  Assert.IsTrue(lProvider.IsNameAbsent('LeftOnly'));
  Assert.IsFalse(lProvider.IsNameAbsent('ClassName'));
  Assert.IsFalse(lProvider.IsNameAbsent('Disposed'));
  Assert.IsFalse(lProvider.IsNameAbsent('GetDisposed'));
  lCount := Length(TDirectory.GetDirectories(TPath.Combine(lRoot, 'root-member-absence')));
  Assert.AreEqual(5, lCount);
  Assert.IsTrue(lProvider.IsNameAbsent('LPAIR'));
  Assert.IsFalse(lProvider.IsNameAbsent('CLASSNAME'));
  Assert.IsFalse(lProvider.IsNameAbsent(''));
  Assert.IsFalse(lProvider.IsNameAbsent('x); Halt(0)'));
  Assert.AreEqual(lCount,
    Integer(Length(TDirectory.GetDirectories(TPath.Combine(lRoot, 'root-member-absence')))),
    'Case-insensitive memoization and invalid names must not run additional probes.');
end;

procedure TRootMemberAbsenceTests.MissingToolchainAndInvalidCompilerRemainUnavailable;
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-root-unavailable');
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(lRoot, 'dcc64.exe'),
    TPath.Combine(lRoot, 'sdk'), lRoot, lReason);
  Assert.IsTrue(lProvider = nil);
  Assert.AreNotEqual('', lReason);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    TPath.Combine(lRoot, 'missing-sdk'), lRoot, lReason);
  Assert.IsTrue(lProvider = nil);
  Assert.AreNotEqual('', lReason);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(lRoot, 'unexpected.exe'),
    TPath.Combine(lRoot, 'sdk'), lRoot, lReason);
  Assert.IsTrue(lProvider = nil);
  Assert.AreEqual('unsupported-native-compiler', lReason);
end;

procedure TRootMemberAbsenceTests.LockedInputsPreventDriftAndNewProviderRejectsCorruptSdk;
var
  lBlocked: Boolean;
  lByte: Byte;
  lFingerprint: string;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
  lSdkRoot: string;
  lStream: TFileStream;
begin
  // Only task-owned SDK copies are mutated; the installed SDK stays read-only.
  lRoot := UniqueTempPath('native-root-input-lock');
  lSdkRoot := TPath.Combine(lRoot, 'sdk');
  TDirectory.CreateDirectory(lSdkRoot);
  TFile.Copy(TPath.Combine(cStudioRoot, 'lib\win64\debug\System.dcu'),
    TPath.Combine(lSdkRoot, 'System.dcu'));
  TFile.Copy(TPath.Combine(cStudioRoot, 'lib\win64\debug\SysInit.dcu'),
    TPath.Combine(lSdkRoot, 'SysInit.dcu'));
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    lSdkRoot, lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  lFingerprint := lProvider.EvidenceFingerprint;
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  lBlocked := False;
  lStream := nil;
  try
    try
      lStream := TFileStream.Create(TPath.Combine(lSdkRoot, 'SysInit.dcu'),
        fmOpenReadWrite or fmShareDenyNone);
    except
      on E: EFOpenError do
        lBlocked := True;
    end;
  finally
    lStream.Free;
  end;
  Assert.IsTrue(lBlocked, 'A provider must retain OS-enforced immutable inputs.');
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  lProvider := nil;
  lStream := TFileStream.Create(TPath.Combine(lSdkRoot, 'SysInit.dcu'),
    fmOpenReadWrite or fmShareDenyNone);
  try
    lStream.ReadBuffer(lByte, SizeOf(lByte));
    lByte := lByte xor $FF;
    lStream.Position := 0;
    lStream.WriteBuffer(lByte, SizeOf(lByte));
  finally
    lStream.Free;
  end;
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    lSdkRoot, lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.AreNotEqual(lFingerprint, lProvider.EvidenceFingerprint);
  Assert.IsFalse(lProvider.IsNameAbsent('lPair'),
    'A new input identity cannot reuse a prior successful name absence.');
end;

procedure TRootMemberAbsenceTests.UnavailableScratchRetainsOptionalRefusal;
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-root-blocked-scratch');
  TDirectory.CreateDirectory(lRoot);
  TFile.WriteAllText(TPath.Combine(lRoot, 'root-member-absence'),
    'Task-owned scratch conflict.', TEncoding.UTF8);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    TPath.Combine(cStudioRoot, 'lib\win64\debug'), lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsFalse(lProvider.IsNameAbsent('lPair'));
end;

procedure TRootMemberAbsenceTests.RetargetedSdkParentInvalidatesMemoizedEvidence;
var
  lExitCode: Cardinal;
  lFirstRoot: string;
  lName: string;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
  lSdkAlias: string;
  lSecondRoot: string;
begin
  lRoot := UniqueTempPath('native-root-retarget');
  lFirstRoot := TPath.Combine(lRoot, 'sdk-first');
  lSecondRoot := TPath.Combine(lRoot, 'sdk-second');
  lSdkAlias := TPath.Combine(lRoot, 'sdk-alias');
  TDirectory.CreateDirectory(lFirstRoot);
  TDirectory.CreateDirectory(lSecondRoot);
  for lName in ['System.dcu', 'SysInit.dcu'] do
  begin
    TFile.Copy(CombinePath([cStudioRoot, 'lib', 'Win64', 'release', lName]),
      TPath.Combine(lFirstRoot, lName));
    TFile.Copy(CombinePath([cStudioRoot, 'lib', 'Win64', 'release', lName]),
      TPath.Combine(lSecondRoot, lName));
  end;
  Assert.IsTrue(RunProcess(GetEnvironmentVariable('COMSPEC'),
    '/d /c mklink /J "' + lSdkAlias + '" "' + lFirstRoot + '"', lRoot,
    TPath.Combine(lRoot, 'first-link.log'), lExitCode));
  Assert.AreEqual(Cardinal(0), lExitCode);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(CombinePath([cStudioRoot, 'bin', 'dcc64.exe']),
    lSdkAlias, lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  Assert.IsTrue(lProvider.EvidenceFingerprint <> '');
  // Move only our junction, preserving both task-owned target directories and locked inputs.
  Assert.IsTrue(MoveFile(PChar(lSdkAlias), PChar(TPath.Combine(lRoot, 'prior-sdk-link'))));
  Assert.IsTrue(RunProcess(GetEnvironmentVariable('COMSPEC'),
    '/d /c mklink /J "' + lSdkAlias + '" "' + lSecondRoot + '"', lRoot,
    TPath.Combine(lRoot, 'second-link.log'), lExitCode));
  Assert.AreEqual(Cardinal(0), lExitCode);
  Assert.IsFalse(lProvider.IsNameAbsent('lPair'), 'A memo hit cannot retain a different physical input.');
  Assert.IsFalse(lProvider.IsNameAbsent('LeftOnly'));
  Assert.AreEqual('', lProvider.EvidenceFingerprint);
end;

type
  TWitnessFailureIO = class(TInterfacedObject, IDakNativeWitnessIO)
  private
    fMode: string;
    fInner: IDakNativeWitnessIO;
  public
    constructor Create(const aMode: string);
    procedure WriteText(const aFileName, aText: string; const aEncoding: TEncoding);
    function ReadTextBounded(const aFileName: string; const aLimit: Integer;
      const aEncoding: TEncoding): string;
    function FlushOutput(const aHandle: NativeUInt): Boolean;
  end;

constructor TWitnessFailureIO.Create(const aMode: string);
begin
  inherited Create;
  fMode := aMode;
  fInner := CreateNativeWitnessIO;
end;

procedure TWitnessFailureIO.WriteText(const aFileName, aText: string; const aEncoding: TEncoding);
var
  lText: string;
begin
  if fMode = 'write-failure' then
    raise EWriteError.Create('deliberate witness write failure');
  lText := aText;
  if SameText(TPath.GetExtension(aFileName), '.dpr') then
  begin
    if lText.Contains('begin if ') then
    begin
      if fMode = 'halt' then
        lText := StringReplace(lText, 'begin if ', 'begin Halt(0); if ', [])
      else if fMode = 'exit' then
        lText := StringReplace(lText, 'begin if ', 'begin Exit; if ', []);
    end;
    if fMode = 'halt' then
      lText := StringReplace(lText, '  lProbe := TProbe.Create;',
        '  Halt(0);' + sLineBreak + '  lProbe := TProbe.Create;', [])
    else if fMode = 'exit' then
      lText := StringReplace(lText, '  lProbe := TProbe.Create;',
        '  Exit;' + sLineBreak + '  lProbe := TProbe.Create;', []);
  end;
  fInner.WriteText(aFileName, lText, aEncoding);
end;

function TWitnessFailureIO.ReadTextBounded(const aFileName: string; const aLimit: Integer;
  const aEncoding: TEncoding): string;
begin
  if ((fMode = 'large-dependencies') and SameText(TPath.GetExtension(aFileName), '.d')) or
    ((fMode = 'large-runtime') and SameText(TPath.GetFileName(aFileName), 'runtime.log')) then
    fInner.WriteText(aFileName, StringOfChar('x', aLimit + 1), aEncoding);
  Result := fInner.ReadTextBounded(aFileName, aLimit, aEncoding);
end;

function TWitnessFailureIO.FlushOutput(const aHandle: NativeUInt): Boolean;
begin
  Result := fInner.FlushOutput(aHandle) and (fMode <> 'flush-failure');
end;

procedure TRootMemberAbsenceTests.NamedConsumerRefusesIncompleteWitness(
  const aPlatform, aCompilerName, aMode: string);
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lNamed: IDelphiSemanticNamedRootMemberAbsence;
  lRoot: TDelphiSemanticQualifiedRootType;
  lReason, lWork: string;
begin
  lWork := UniqueTempPath('named-io-' + aMode);
  TDirectory.CreateDirectory(lWork);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\' + aCompilerName),
    CombinePath([cStudioRoot, 'lib', aPlatform, 'release']), lWork,
    TWitnessFailureIO.Create(aMode), lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(Supports(lProvider, IDelphiSemanticNamedRootMemberAbsence, lNamed));
  lRoot := Default(TDelphiSemanticQualifiedRootType);
  lRoot.Kind := 'class';
  lRoot.TypeName := 'System.TObject';
  Assert.IsFalse(lNamed.IsNamedRootMemberAbsent(lRoot, [], 'DAK418_NoMember'));
  Assert.AreEqual<Integer>(0, Length(TDirectory.GetDirectories(lWork, 'run-*',
    TSearchOption.soAllDirectories)), 'Failed named probes also clean immediately.');
end;

procedure TRootMemberAbsenceTests.ConsumerRefusesIncompleteOrFailedWitness(
  const aPlatform, aCompilerName, aMode: string);
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason, lRoot, lRunRoot, lOutput: string;
  lIO: IDakNativeWitnessIO;
begin
  lRoot := UniqueTempPath('native-consumer-' + aMode + '-' + aPlatform);
  lIO := TWitnessFailureIO.Create(aMode);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\' + aCompilerName),
    TPath.Combine(cStudioRoot, 'lib\' + aPlatform + '\release'), lRoot, lIO, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsFalse(lProvider.IsNameAbsent('lPair'));
  lRunRoot := TDirectory.GetDirectories(TPath.Combine(lRoot, 'root-member-absence'))[0];
  if (aMode = 'halt') or (aMode = 'exit') then
  begin
    Assert.IsTrue(TFile.Exists(TPath.Combine(lRunRoot, 'runtime.log')),
      'Fresh compiler and runtime must both execute the mutated witness');
    Assert.IsFalse(TFile.Exists(TPath.Combine(lRunRoot, 'runtime.log.status')),
      'Exit zero alone must still refuse');
    lOutput := TFile.ReadAllText(TPath.Combine(lRunRoot, 'runtime.log'));
    Assert.AreEqual('', lOutput);
    Assert.IsTrue(TFile.ReadAllText(TPath.Combine(lRunRoot, 'result.txt')).Contains('absent=False'));
  end else if aMode = 'flush-failure' then
    Assert.IsTrue(TFile.Exists(TPath.Combine(lRunRoot, 'compiler.log.status')))
  else
  begin
    lOutput := TFile.ReadAllText(TPath.Combine(lRunRoot, 'refusal.txt'));
    if aMode = 'write-failure' then
      Assert.IsTrue(lOutput.Contains('deliberate witness write failure'), lOutput)
    else
      Assert.IsTrue(lOutput.Contains('size limit'), lOutput);
  end;
end;

procedure TRootMemberAbsenceTests.ProviderCleanupPreservesUnknownFiles;
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason, lRoot, lRunRoot, lUnknown: string;
begin
  lRoot := UniqueTempPath('native-cleanup');
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    TPath.Combine(cStudioRoot, 'lib\win64\release'), lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  lRunRoot := TDirectory.GetDirectories(TPath.Combine(lRoot, 'root-member-absence'))[0];
  lUnknown := TPath.Combine(lRunRoot, 'unrelated.keep');
  TFile.WriteAllText(lUnknown, 'preserve these bytes', TEncoding.ASCII);
  lProvider := nil;
  Assert.AreEqual('preserve these bytes', TFile.ReadAllText(lUnknown));
  Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(lRunRoot))));
end;

initialization
  TDUnitX.RegisterTestFixture(TRootMemberAbsenceTests);

end.
