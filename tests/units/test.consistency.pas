unit Test.Consistency;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TConsistencyTests = class
  public
    [Test]
    [Category('RefactoringLightConsistency')]
    procedure ReportsProjectGuidInventoryWithoutMutation;
    [Test]
    [Category('RefactoringLightConsistency')]
    procedure OmitsSourceProvenOrdinaryProperties;
    [Test]
    [TestCase('Inherited', 'inherit,HandleData,2')]
    [TestCase('Type beside keyword', 'same-line,HandleData,2')]
    [TestCase('HiddenComponentClass', 'hiding,HandleData,2')]
    [TestCase('Override', 'override,HandleOther,2')]
    [TestCase('Clear', 'clear,nil,1')]
    [TestCase('MissingComponent', 'missing-component,blocked,1')]
    [TestCase('WrongClass', 'wrong-class,blocked,1')]
    [TestCase('Inline', 'inline,blocked,1')]
    [TestCase('MissingAncestor', 'missing-ancestor,blocked,0')]
    [TestCase('MissingIntermediateResource', 'middle-missing,blocked,1')]
    [TestCase('ResourceFreeIntermediate', 'middle-pure,HandleData,2')]
    [TestCase('IntermediateOverride', 'middle-override,HandleMiddle,3')]
    [Category('RefactoringLightConsistency')]
    procedure ReportsInheritedDfmBindings(const aShape, aHandler: string; const aCount: Integer);
    [Test]
    [Category('RefactoringLightConsistency')]
    procedure MissingProjectReturnsVersionedBlockedReport;
    [Test]
    [TestCase('Match', 'match,OnData,match,ok')]
    [TestCase('CustomEvent', 'match,Changed,match,ok')]
    [TestCase('Missing', 'missing,OnData,missing-handler,ok')]
    [TestCase('Convention', 'convention,OnData,mismatch,ok')]
    [TestCase('SourceLess', 'external,OnData,unknown,incomplete')]
    [TestCase('AliasChain', 'alias-chain,OnData,match,ok')]
    [TestCase('DistinctAlias', 'alias-distinct,OnData,mismatch,ok')]
    [TestCase('EventAlias', 'alias-event,OnData,match,ok')]
    [TestCase('SameLineHandlers', 'same-line,Changed,match,ok')]
    [TestCase('FieldVisibilityHandlerLine', 'mixed-line,OnData,match,ok')]
    [Category('RefactoringLightConsistency')]
    procedure ReportsSourceBackedDfmBindings(const aShape, aEvent, aStatus, aOverall: string);
    [Test]
    [TestCase('MissingResource', 'missing,dfm.resource-unavailable')]
    [TestCase('NonstandardResource', 'named,dfm.resource-layout-unsupported')]
    [TestCase('IncludedResource', 'include,dfm.include-resource-coverage-unknown')]
    [TestCase('Binary', 'binary,dfm.binary-unsupported')]
    [TestCase('Inherited', 'inherited,dfm.ancestry-unavailable')]
    [Category('RefactoringLightConsistency')]
    procedure UnsupportedDfmIsExplicitlyIncomplete(const aShape, aReason: string);
    [Test]
    [TestCase('Direct VCL', 'direct,dfm.resource-ancestry-unknown')]
    [TestCase('Custom base VCL', 'custom,dfm.resource-only-unsupported')]
    [TestCase('Missing custom base', 'missing-base,dfm.resource-ancestry-unknown')]
    [TestCase('Cyclic base', 'cycle,dfm.resource-ancestry-unknown')]
    [TestCase('Forward class', 'forward,dfm.resource-ancestry-unknown')]
    [TestCase('Forward and full custom VCL class', 'forward-full,dfm.resource-ancestry-unknown')]
    [Category('RefactoringLightConsistency')]
    procedure ResourceOnlyFormIsExplicitlyIncomplete(const aShape, aReason: string);

    [Test]
    [TestCase('Implementation imported homonym', 'impl-homonym,incomplete')]
    // Characterization: implementation-local lookup remains incomplete; proving it is DS-727.
    [TestCase('Implementation without imported homonym', 'impl-no-homonym,incomplete')]
    [TestCase('Implementation imports affect implementation class', 'impl-uses,incomplete')]
    [TestCase('Implementation imports do not affect interface class', 'interface-uses,ok')]
    [Category('RefactoringLightConsistency')]
    procedure ResourceAncestryRequiresInspectedDeclaration(const aShape, aStatus: string);
    [Test]
    [TestCase('Unqualified homonym', 'unqualified')]
    [TestCase('Qualified homonym', 'qualified')]
    [TestCase('Indexed homonym last after VCL import', 'indexed-last')]
    [TestCase('Local homonym with VCL import', 'local-with-vcl')]
    [TestCase('Indexed homonym with VCL import', 'later-Vcl.Forms')]
    [TestCase('Indexed homonym with unscoped Forms import', 'later-Forms')]
    [TestCase('Indexed homonym with later unknown import', 'later-UnknownUnit')]
    [Category('RefactoringLightConsistency')]
    procedure UnrelatedTFormResourceDoesNotClaimVclForm(const aShape: string);
    [Test]
    [Category('RefactoringLightConsistency')]
    procedure ProgramResourceDoesNotHideTextDfmBindings;
  end;

implementation

uses
  System.Classes, System.Hash, System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Test.Support;

type
  TReportFixture = record
    fDirectory: string;
    fProject: string;
    fSource: string;
    fDfm: string;
    fLog: string;
    fSourceHash: string;
    fDfmHash: string;
  end;

function EvidenceDirectory: string;
var
  id: TGUID;
begin
  CreateGUID(id);
  Result := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-consistency\fixtures\' + GUIDToString(id));
  ForceDirectories(Result);
end;

procedure TConsistencyTests.ReportsProjectGuidInventoryWithoutMutation;
var
  lFixture: TReportFixture;
  lExit: Cardinal;
  lRoot: TJSONObject;
  lItems: TJSONArray;
begin
  lFixture := Default(TReportFixture);
  lFixture.fDirectory := EvidenceDirectory;
  lFixture.fProject := TPath.Combine(lFixture.fDirectory, 'Inventory.dproj');
  lFixture.fSource := TPath.Combine(lFixture.fDirectory, 'Contracts.pas');
  TFile.WriteAllText(lFixture.fSource,
    'unit Contracts;'#13#10'interface'#13#10'type'#13#10 +
    '  IFirst = interface'#13#10'    [''{870E1EE6-EF37-47EA-8C91-2E21BA8D9472}'']'#13#10'  end;'#13#10 +
    '  ISecond = interface'#13#10'    [''{870E1EE6-EF37-47EA-8C91-2E21BA8D9472}'']'#13#10'  end;'#13#10 +
    'implementation'#13#10'end.'#13#10, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lFixture.fDirectory, 'Inventory.dpr'),
    'program Inventory;'#13#10'uses Contracts in ''Contracts.pas'';'#13#10'begin end.'#13#10,
    TEncoding.UTF8);
  TFile.WriteAllText(lFixture.fProject,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>Inventory.dpr</MainSource></PropertyGroup>' +
    '<ItemGroup><DCCReference Include="Contracts.pas"/></ItemGroup></Project>', TEncoding.UTF8);
  lFixture.fSourceHash := THashSHA2.GetHashStringFromFile(lFixture.fSource);
  lFixture.fLog := TPath.Combine(lFixture.fDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' + QuoteArg(lFixture.fProject) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json', lFixture.fDirectory, lFixture.fLog, lExit));
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lRoot);
    Assert.AreEqual(1, lRoot.GetValue<Integer>('schemaVersion'));
    Assert.AreEqual('consistency.inspect', lRoot.GetValue<string>('operation'));
    Assert.AreEqual('ok', lRoot.GetValue<string>('status'));
    Assert.AreEqual(Cardinal(0), lExit, lRoot.ToJSON);
    Assert.AreEqual(lFixture.fProject, lRoot.GetValue<string>('project'));
    Assert.AreEqual('Win64', lRoot.GetValue<string>('platform'));
    Assert.AreEqual('Debug', lRoot.GetValue<string>('config'));
    Assert.IsTrue(lRoot.GetValue<string>('contextFingerprint') <> '');
    Assert.IsTrue((lRoot.FindValue('scope.complete') as TJSONBool).AsBoolean);
    lItems := (lRoot.GetValue('guids') as TJSONArray);
    Assert.AreEqual(2, lItems.Count);
    Assert.AreEqual('duplicate', lItems.Items[0].GetValue<string>('status'));
    Assert.AreEqual('duplicate', lItems.Items[1].GetValue<string>('status'));
    Assert.AreEqual(2, lRoot.GetValue<Integer>('summary.guidCount'));
    Assert.AreEqual(0, lRoot.GetValue<Integer>('summary.omittedResultCount'));
  finally
    lRoot.Free;
  end;
  Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
end;

procedure TConsistencyTests.MissingProjectReturnsVersionedBlockedReport;
var
  lDirectory, lLog: string;
  lExit: Cardinal;
  lRoot: TJSONObject;
begin
  lDirectory := EvidenceDirectory;
  lLog := TPath.Combine(lDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' +
    QuoteArg(TPath.Combine(lDirectory, 'Missing.dproj')) +
    ' --config Debug --platform Win64 --delphi 23.0', lDirectory, lLog, lExit));
  Assert.AreNotEqual(Cardinal(0), lExit);
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lLog)) as TJSONObject;
  try
    Assert.IsNotNull(lRoot);
    Assert.AreEqual(1, lRoot.GetValue<Integer>('schemaVersion'));
    Assert.AreEqual('blocked', lRoot.GetValue<string>('status'));
    Assert.IsFalse((lRoot.FindValue('scope.complete') as TJSONBool).AsBoolean);
    Assert.IsTrue((lRoot.GetValue('diagnostics') as TJSONArray).Count > 0);
  finally
    lRoot.Free;
  end;
end;

function WriteBindingFixture(const aFixture: TReportFixture; const aShape, aEvent: string): string;
var
  lConvention, lComponent, lHandlers, lOther: string;
begin
  Result := 'HandleData';
  lConvention := '';
  lComponent := 'TWidget';
  if aShape = 'missing' then
    Result := 'MissingHandler';
  if aShape = 'convention' then
    lConvention := ' stdcall;';
  if aShape = 'external' then
    lComponent := 'TSourceLessWidget';
  lHandlers := '    procedure HandleData(aValue: TValue);' + lConvention;
  lOther := '';
  // The bound handler follows another member on the same physical line.
  if aShape = 'same-line' then
    lHandlers := '    procedure HandleOther(aValue: TValue); procedure HandleData(aValue: TValue);'
  else if aShape = 'mixed-line' then
    lHandlers := '  private FX: Integer; published procedure HandleOther(aValue: TValue);'#13#10 +
      '    procedure HandleData(aValue: TValue);';
  if (aShape = 'same-line') or (aShape = 'mixed-line') then
    lOther := 'procedure TBindingForm.HandleOther(aValue: TValue);'#13#10'begin end;'#13#10;
  TFile.WriteAllText(aFixture.fSource,
    'unit BindingForm;'#13#10'interface'#13#10'type'#13#10 +
    '  TValue = class end;'#13#10 +
    '  TDataEvent = procedure(aValue: TValue) of object;'#13#10 +
    '  TWidget = class'#13#10'  private'#13#10'    FData: TDataEvent;'#13#10'  published'#13#10 +
    '    property ' + aEvent + ': TDataEvent read FData write FData;'#13#10'  end;'#13#10 +
    '  TBindingForm = class'#13#10'  published'#13#10 + lHandlers + #13#10'  end;'#13#10 +
    'implementation'#13#10 + lOther +
    'procedure TBindingForm.HandleData(aValue: TValue);' + lConvention + #13#10'begin end;'#13#10'end.'#13#10,
    TEncoding.UTF8);
  TFile.WriteAllText(aFixture.fDfm, 'object BindingForm: TBindingForm'#13#10 +
    '  object Widget: ' + lComponent + #13#10'    ' + aEvent + ' = ' + Result + #13#10 +
    '  end'#13#10'end'#13#10, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(aFixture.fDirectory, 'Binding.dpr'),
    'program Binding;'#13#10'uses BindingForm in ''BindingForm.pas'';'#13#10'begin end.'#13#10,
    TEncoding.UTF8);
  TFile.WriteAllText(aFixture.fProject,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>Binding.dpr</MainSource></PropertyGroup>' +
    '<ItemGroup><DCCReference Include="BindingForm.pas"/></ItemGroup></Project>', TEncoding.UTF8);
end;

procedure ApplyAliasFixture(const aFileName, aShape: string);
var
  lSource: string;
begin
  if not aShape.StartsWith('alias-') then
    Exit;
  lSource := TFile.ReadAllText(aFileName, TEncoding.UTF8);
  if aShape = 'alias-event' then
    lSource := lSource.Replace('  TWidget = class',
      '  TEventAlias = TDataEvent;'#13#10'  TWidget = class').Replace(
      ': TDataEvent', ': TEventAlias')
  else
  begin
    var lAlias := 'TIntermediate';
    if aShape = 'alias-distinct' then
      lAlias := 'type TValue';
    lSource := lSource.Replace('  TValue = class end;',
      '  TValue = (one, two);'#13#10'  TIntermediate = TValue;'#13#10 +
      '  TAlias = ' + lAlias + ';').Replace(
      'TDataEvent = procedure(aValue: TValue)', 'TDataEvent = procedure(aValue: TAlias)').Replace(
      '(aValue:', '(var aValue:');
  end;
  TFile.WriteAllText(aFileName, lSource, TEncoding.UTF8);
end;

procedure TConsistencyTests.ReportsSourceBackedDfmBindings(const aShape, aEvent, aStatus, aOverall: string);
var
  lFixture: TReportFixture;
  lHandler: string;
  lExit: Cardinal;
  lRoot: TJSONObject;
  lEvents: TJSONArray;
begin
  lFixture := Default(TReportFixture);
  lFixture.fDirectory := EvidenceDirectory;
  lFixture.fProject := TPath.Combine(lFixture.fDirectory, 'Binding.dproj');
  lFixture.fSource := TPath.Combine(lFixture.fDirectory, 'BindingForm.pas');
  lFixture.fDfm := ChangeFileExt(lFixture.fSource, '.dfm');
  lHandler := WriteBindingFixture(lFixture, aShape, aEvent);
  ApplyAliasFixture(lFixture.fSource, aShape);
  lFixture.fSourceHash := THashSHA2.GetHashStringFromFile(lFixture.fSource);
  lFixture.fDfmHash := THashSHA2.GetHashStringFromFile(lFixture.fDfm);
  lFixture.fLog := TPath.Combine(lFixture.fDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' + QuoteArg(lFixture.fProject) +
    ' --config Debug --platform Win64 --delphi 23.0', lFixture.fDirectory, lFixture.fLog, lExit));
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lRoot);
    Assert.AreEqual(aOverall, lRoot.GetValue<string>('status'), lRoot.ToJSON);
    Assert.AreEqual(aOverall = 'ok', lExit = 0);
    lEvents := (lRoot.GetValue('events') as TJSONArray);
    Assert.AreEqual(1, lEvents.Count, lRoot.ToJSON);
    Assert.AreEqual(aStatus, lEvents.Items[0].GetValue<string>('status'));
    Assert.AreEqual(aEvent, lEvents.Items[0].GetValue<string>('event'));
    Assert.AreEqual(lHandler, lEvents.Items[0].GetValue<string>('handler'));
    Assert.AreEqual(lFixture.fDfm, lEvents.Items[0].GetValue<string>('fileName'));
    Assert.AreEqual(3, lEvents.Items[0].GetValue<Integer>('line'));
    if aStatus <> 'unknown' then
      Assert.AreEqual(lFixture.fSource, lEvents.Items[0].GetValue<string>('eventType.fileName'));
  finally
    lRoot.Free;
  end;
  Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
  Assert.AreEqual(lFixture.fDfmHash, THashSHA2.GetHashStringFromFile(lFixture.fDfm));
end;

procedure WriteInheritedFixture(const aFixture: TReportFixture; const aShape: string);
var
  lAssignment, lExtra, lTypeKeyword: string;
begin
  Assert.AreEqual('HandleData', WriteBindingFixture(aFixture, 'match', 'Changed'));
  lExtra := '';
  lTypeKeyword := 'type'#13#10;
  if aShape = 'same-line' then
    lTypeKeyword := 'type ';
  if aShape = 'hiding' then
    lExtra := '  TWidget = class end;'#13#10;
  TFile.WriteAllText(TPath.Combine(aFixture.fDirectory, 'ChildForm.pas'),
    'unit ChildForm;'#13#10'interface'#13#10'uses BindingForm;'#13#10 +
    lTypeKeyword + lExtra + '  TChildForm = class(TBindingForm)'#13#10'published'#13#10 +
    '  procedure HandleOther(aValue: TValue);'#13#10'end;'#13#10 +
    'implementation'#13#10'procedure TChildForm.HandleOther(aValue: TValue);'#13#10 +
    'begin end;'#13#10'end.'#13#10, TEncoding.UTF8);
  lAssignment := '';
  if aShape = 'override' then
    lAssignment := '    Changed = HandleOther'#13#10;
  if aShape = 'clear' then
    lAssignment := '    Changed = nil'#13#10;
  TFile.WriteAllText(TPath.Combine(aFixture.fDirectory, 'ChildForm.dfm'),
    'inherited ChildForm: TChildForm'#13#10'  inherited Widget: TWidget'#13#10 +
    lAssignment + '  end'#13#10'end'#13#10, TEncoding.UTF8);
  if aShape = 'missing-component' then
    TFile.WriteAllText(TPath.Combine(aFixture.fDirectory, 'ChildForm.dfm'),
      'inherited ChildForm: TChildForm'#13#10'  inherited Missing: TWidget'#13#10'  end'#13#10'end',
      TEncoding.UTF8);
  if aShape = 'wrong-class' then
    TFile.WriteAllText(TPath.Combine(aFixture.fDirectory, 'ChildForm.dfm'),
      'inherited ChildForm: TChildForm'#13#10'  inherited Widget: TWrong'#13#10'  end'#13#10'end',
      TEncoding.UTF8);
  if aShape = 'inline' then
    TFile.WriteAllText(TPath.Combine(aFixture.fDirectory, 'ChildForm.dfm'),
      'inherited ChildForm: TChildForm'#13#10'  inline Frame: TWidget'#13#10'  end'#13#10'end',
      TEncoding.UTF8);
  if aShape = 'missing-ancestor' then
    TFile.Delete(aFixture.fDfm);
  TFile.WriteAllText(TPath.Combine(aFixture.fDirectory, 'Binding.dpr'),
    'program Binding;'#13#10'uses BindingForm in ''BindingForm.pas'', ChildForm in ''ChildForm.pas'';' +
    #13#10'begin end.'#13#10, TEncoding.UTF8);
end;

procedure WriteIntermediateFixture(const aFixture: TReportFixture; const aShape: string);
var
  lSource, lChild: string;
begin
  lSource := 'unit MiddleForm;'#13#10'interface'#13#10'uses BindingForm;'#13#10 +
    'type'#13#10'  TMiddleForm = class(TBindingForm)'#13#10'  published'#13#10 +
    '    procedure HandleMiddle(aValue: TValue);'#13#10'  end;'#13#10'implementation'#13#10;
  if aShape <> 'middle-pure' then
    lSource := lSource + '{$R *.dfm}'#13#10;
  lSource := lSource + 'procedure TMiddleForm.HandleMiddle(aValue: TValue);'#13#10 +
    'begin end;'#13#10'end.'#13#10;
  TFile.WriteAllText(TPath.Combine(aFixture.fDirectory, 'MiddleForm.pas'), lSource, TEncoding.UTF8);
  lChild := TPath.Combine(aFixture.fDirectory, 'ChildForm.pas');
  lSource := TFile.ReadAllText(lChild, TEncoding.UTF8);
  lSource := StringReplace(lSource, 'uses BindingForm;', 'uses BindingForm, MiddleForm;', []);
  lSource := StringReplace(lSource, 'class(TBindingForm)', 'class(TMiddleForm)', []);
  TFile.WriteAllText(lChild, lSource, TEncoding.UTF8);
  lChild := TPath.Combine(aFixture.fDirectory, 'Binding.dpr');
  lSource := TFile.ReadAllText(lChild, TEncoding.UTF8);
  lSource := StringReplace(lSource, 'ChildForm in', 'MiddleForm in ''MiddleForm.pas'', ChildForm in', []);
  TFile.WriteAllText(lChild, lSource, TEncoding.UTF8);
  if aShape = 'middle-override' then
    TFile.WriteAllText(TPath.Combine(aFixture.fDirectory, 'MiddleForm.dfm'),
      'inherited MiddleForm: TMiddleForm'#13#10'  inherited Widget: TWidget'#13#10 +
      '    Changed = HandleMiddle'#13#10'  end'#13#10'end'#13#10, TEncoding.UTF8);
end;
function BindingFixtureHash(const aDirectory: string): string;
var
  lFiles: TStringList;
  lFileName: string;
begin
  lFiles := TStringList.Create;
  try
    for lFileName in TDirectory.GetFiles(aDirectory) do
      if SameText(ExtractFileExt(lFileName), '.pas') or SameText(ExtractFileExt(lFileName), '.dfm') or
        SameText(ExtractFileExt(lFileName), '.dpr') or SameText(ExtractFileExt(lFileName), '.dproj') or
        SameText(ExtractFileExt(lFileName), '.res') then
        lFiles.Add(lFileName + '=' + THashSHA2.GetHashStringFromFile(lFileName));
    lFiles.Sort;
    Result := lFiles.Text;
  finally
    lFiles.Free;
  end;
end;
procedure AssertIncompleteAncestry(const aReport: TJSONObject; const aExit: Cardinal);
var
  lItem: TJSONValue;
  lFound: Boolean;
begin
  Assert.AreEqual(Cardinal(3), aExit, aReport.ToJSON);
  Assert.AreEqual('incomplete', aReport.GetValue<string>('status'));
  Assert.IsFalse((aReport.FindValue('scope.complete') as TJSONBool).AsBoolean);
  lFound := False;
  for lItem in (aReport.GetValue('diagnostics') as TJSONArray) do
    if lItem.GetValue<string>('reason') = 'dfm.ancestry-unavailable' then
      lFound := True;
  Assert.IsTrue(lFound, aReport.ToJSON);
end;
procedure TConsistencyTests.ReportsInheritedDfmBindings(const aShape, aHandler: string;
  const aCount: Integer);
var
  lResourceCount: Integer;
  lFixture: TReportFixture;
  lExit: Cardinal;
  lRoot: TJSONObject;
  lItem: TJSONValue;
  lFound: Boolean;
begin
  lFixture := Default(TReportFixture);
  lFixture.fDirectory := EvidenceDirectory;
  lFixture.fProject := TPath.Combine(lFixture.fDirectory, 'Binding.dproj');
  lFixture.fSource := TPath.Combine(lFixture.fDirectory, 'BindingForm.pas');
  lFixture.fDfm := ChangeFileExt(lFixture.fSource, '.dfm');
  WriteInheritedFixture(lFixture, aShape);
  if Copy(aShape, 1, 7) = 'middle-' then
    WriteIntermediateFixture(lFixture, aShape);
  lFixture.fSourceHash := BindingFixtureHash(lFixture.fDirectory);
  lFixture.fLog := TPath.Combine(lFixture.fDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' + QuoteArg(lFixture.fProject) +
    ' --config Debug --platform Win64 --delphi 23.0', lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(lFixture.fSourceHash, BindingFixtureHash(lFixture.fDirectory));
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lRoot);
    Assert.AreEqual(aCount, (lRoot.GetValue('events') as TJSONArray).Count, lRoot.ToJSON);
    if aHandler = 'blocked' then
    begin
      AssertIncompleteAncestry(lRoot, lExit);
      if aShape = 'middle-missing' then
      begin
        lResourceCount := 0;
        for lItem in (lRoot.GetValue('diagnostics') as TJSONArray) do
          if (lItem.GetValue<string>('reason') = 'dfm.resource-unavailable') and
            SameText(lItem.GetValue<string>('fileName'),
              TPath.Combine(lFixture.fDirectory, 'MiddleForm.dfm')) then
            Inc(lResourceCount);
        Assert.AreEqual(1, lResourceCount, lRoot.ToJSON);
      end;
      Exit;
    end;
    Assert.AreEqual(Cardinal(0), lExit, lRoot.ToJSON);
    Assert.AreEqual('ok', lRoot.GetValue<string>('status'));
    lFound := False;
    for lItem in (lRoot.GetValue('events') as TJSONArray) do
      if lItem.GetValue<string>('formClass') = 'TChildForm' then
      begin
        lFound := True;
        Assert.AreEqual(aHandler, lItem.GetValue<string>('handler'));
        Assert.AreEqual('match', lItem.GetValue<string>('status'));
        Assert.AreEqual(TPath.Combine(lFixture.fDirectory, 'ChildForm.dfm'),
          lItem.GetValue<string>('formFileName'));
        if (aShape = 'inherit') or (aShape = 'hiding') or (aShape = 'middle-pure') or
          (aShape = 'same-line') then
          Assert.AreEqual(lFixture.fDfm, lItem.GetValue<string>('fileName'))
        else if aShape = 'middle-override' then
          Assert.AreEqual(TPath.Combine(lFixture.fDirectory, 'MiddleForm.dfm'),
            lItem.GetValue<string>('fileName'))
        else
          Assert.AreEqual(TPath.Combine(lFixture.fDirectory, 'ChildForm.dfm'),
            lItem.GetValue<string>('fileName'));
        Assert.AreEqual(3, lItem.GetValue<Integer>('line'));
      end;
    Assert.AreEqual(aShape <> 'clear', lFound);
  finally
    lRoot.Free;
  end;
end;
procedure TConsistencyTests.OmitsSourceProvenOrdinaryProperties;
var
  lFixture: TReportFixture;
  lSource: string;
  lExit: Cardinal;
  lRoot: TJSONObject;
begin
  lFixture := Default(TReportFixture);
  lFixture.fDirectory := EvidenceDirectory;
  lFixture.fProject := TPath.Combine(lFixture.fDirectory, 'Binding.dproj');
  lFixture.fSource := TPath.Combine(lFixture.fDirectory, 'BindingForm.pas');
  lFixture.fDfm := ChangeFileExt(lFixture.fSource, '.dfm');
  Assert.AreEqual('HandleData', WriteBindingFixture(lFixture, 'match', 'OnMode'));
  lSource := TFile.ReadAllText(lFixture.fSource, TEncoding.UTF8);
  lSource := StringReplace(lSource, '  TValue = class end;',
    '  TMode = (one, two);'#13#10'  TValue = class end;', []);
  lSource := StringReplace(lSource, 'FData: TDataEvent', 'FData: TMode', []);
  lSource := StringReplace(lSource, 'OnMode: TDataEvent', 'OnMode: TMode', []);
  TFile.WriteAllText(lFixture.fSource, lSource, TEncoding.UTF8);
  TFile.WriteAllText(lFixture.fDfm, 'object BindingForm: TBindingForm'#13#10 +
    '  object Widget: TWidget'#13#10'    OnMode = one'#13#10'  end'#13#10'end'#13#10, TEncoding.UTF8);
  lFixture.fSourceHash := BindingFixtureHash(lFixture.fDirectory);
  lFixture.fLog := TPath.Combine(lFixture.fDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' + QuoteArg(lFixture.fProject) +
    ' --config Debug --platform Win64 --delphi 23.0', lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(lFixture.fSourceHash, BindingFixtureHash(lFixture.fDirectory));
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lRoot);
    Assert.AreEqual(Cardinal(0), lExit, lRoot.ToJSON);
    Assert.AreEqual('ok', lRoot.GetValue<string>('status'));
    Assert.AreEqual(0, (lRoot.GetValue('events') as TJSONArray).Count, lRoot.ToJSON);
    Assert.AreEqual(0, lRoot.GetValue<Integer>('summary.omittedResultCount'));
  finally
    lRoot.Free;
  end;
end;
procedure WriteBinaryDfm(const aFileName: string);
var
  lInput: TStringStream;
  lOutput: TFileStream;
begin
  lInput := TStringStream.Create('object Form1: TForm1'#13#10'end'#13#10, TEncoding.ASCII);
  try
    lOutput := TFileStream.Create(aFileName, fmCreate);
    try
      ObjectTextToBinary(lInput, lOutput);
    finally
      lOutput.Free;
    end;
  finally
    lInput.Free;
  end;
end;

procedure TConsistencyTests.UnsupportedDfmIsExplicitlyIncomplete(const aShape, aReason: string);
var
  lFixture: TReportFixture;
  lResource: string;
  lExit: Cardinal;
  lRoot: TJSONObject;
  lItem: TJSONValue;
  lFound: Boolean;
begin
  lFixture := Default(TReportFixture);
  lFixture.fDirectory := EvidenceDirectory;
  lFixture.fProject := TPath.Combine(lFixture.fDirectory, 'Unsupported.dproj');
  lFixture.fSource := TPath.Combine(lFixture.fDirectory, 'Unsupported.pas');
  lFixture.fDfm := ChangeFileExt(lFixture.fSource, '.dfm');
  lResource := '*.dfm';
  if aShape = 'named' then
    lResource := 'Different.dfm';
  if aShape = 'include' then
  begin
    TFile.WriteAllText(TPath.Combine(lFixture.fDirectory, 'Resource.inc'), '{$R Different.dfm}', TEncoding.UTF8);
    TFile.WriteAllText(lFixture.fSource, 'unit Unsupported;'#13#10'interface'#13#10'implementation'#13#10 +
      '{$I Resource.inc}'#13#10'end.'#13#10, TEncoding.UTF8);
  end else
    TFile.WriteAllText(lFixture.fSource, 'unit Unsupported;'#13#10'interface'#13#10'implementation'#13#10 +
      '{$R ' + lResource + '}'#13#10'end.'#13#10, TEncoding.UTF8);
  TFile.WriteAllText(lFixture.fProject,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>Unsupported.pas</MainSource></PropertyGroup>' +
    '<ItemGroup><DCCReference Include="Unsupported.pas"/></ItemGroup></Project>', TEncoding.UTF8);
  if aShape = 'binary' then
    WriteBinaryDfm(lFixture.fDfm)
  else if aShape = 'inherited' then
    TFile.WriteAllText(lFixture.fDfm, 'inherited Form1: TForm1'#13#10'end'#13#10, TEncoding.UTF8)
  else if aShape = 'named' then
    TFile.WriteAllText(TPath.Combine(lFixture.fDirectory, lResource),
      'object Form1: TForm1'#13#10'end'#13#10, TEncoding.UTF8);
  lFixture.fLog := TPath.Combine(lFixture.fDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' + QuoteArg(lFixture.fProject) +
    ' --config Debug --platform Win64 --delphi 23.0', lFixture.fDirectory, lFixture.fLog, lExit));
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lRoot);
    Assert.AreNotEqual(Cardinal(0), lExit, lRoot.ToJSON);
    Assert.AreEqual('incomplete', lRoot.GetValue<string>('status'));
    Assert.IsFalse((lRoot.FindValue('scope.complete') as TJSONBool).AsBoolean);
    lFound := False;
    for lItem in (lRoot.GetValue('diagnostics') as TJSONArray) do
      if lItem.GetValue<string>('reason') = aReason then
        lFound := True;
    Assert.IsTrue(lFound, lRoot.ToJSON);
  finally
    lRoot.Free;
  end;
end;

procedure TConsistencyTests.ResourceOnlyFormIsExplicitlyIncomplete(const aShape, aReason: string);
var
  g: TGarbos;
  lFixture: TReportFixture;
  lSource: string;
  lDpr: string;
  lProject: string;
  lSourceHash: string;
  lExit: Cardinal;
  lRoot: TJSONObject;
  lItem: TJSONValue;
  lFound: Boolean;
begin
  lFixture := Default(TReportFixture);
  lFixture.fDirectory := EvidenceDirectory;
  lFixture.fProject := TPath.Combine(lFixture.fDirectory, 'Binding.dproj');
  lFixture.fSource := TPath.Combine(lFixture.fDirectory, 'BindingForm.pas');
  lFixture.fDfm := ChangeFileExt(lFixture.fSource, '.dfm');
  WriteBindingFixture(lFixture, 'match', 'OnData');
  lSource := TFile.ReadAllText(lFixture.fSource, TEncoding.UTF8);
  if (aShape = 'custom') or (aShape = 'forward-full') then
  begin
    TFile.WriteAllText(TPath.Combine(lFixture.fDirectory, 'BaseForm.pas'),
      'unit BaseForm;'#13#10'interface'#13#10'uses Vcl.Forms;'#13#10 +
      'type TBaseForm = class(Vcl.Forms.TForm) end;'#13#10 +
      'implementation'#13#10'end.'#13#10, TEncoding.UTF8);
    lSource := lSource.Replace('unit BindingForm;'#13#10'interface',
      'unit BindingForm;'#13#10'interface'#13#10'uses BaseForm;').Replace(
      'TBindingForm = class', 'TBindingForm = class(TBaseForm)');
    lDpr := TPath.Combine(lFixture.fDirectory, 'Binding.dpr');
    TFile.WriteAllText(lDpr, TFile.ReadAllText(lDpr, TEncoding.UTF8).Replace(
      'uses BindingForm', 'uses BaseForm in ''BaseForm.pas'', BindingForm'), TEncoding.UTF8);
    lProject := TFile.ReadAllText(lFixture.fProject, TEncoding.UTF8).Replace(
      '<DCCReference Include="BindingForm.pas"/>',
      '<DCCReference Include="BaseForm.pas"/><DCCReference Include="BindingForm.pas"/>');
    TFile.WriteAllText(lFixture.fProject, lProject, TEncoding.UTF8);
  end else if aShape = 'forward' then
    lSource := lSource.Replace('  TBindingForm = class'#13#10'  published'#13#10 +
      '    procedure HandleData(aValue: TValue);'#13#10'  end;', '  TBindingForm = class;').Replace(
      'procedure TBindingForm.HandleData(aValue: TValue);'#13#10'begin end;'#13#10, '')
  else if aShape = 'cycle' then
    lSource := lSource.Replace('TBindingForm = class', 'TBindingForm = class(TBindingForm)')
  else if aShape = 'missing-base' then
    lSource := lSource.Replace('TBindingForm = class',
      'TBindingForm = class(TMissingBase)')
  else
    lSource := lSource.Replace('unit BindingForm;'#13#10'interface',
      'unit BindingForm;'#13#10'interface'#13#10'uses Vcl.Forms;').Replace(
      'TBindingForm = class', 'TBindingForm = class(TForm)');
  lSource := lSource.Replace('implementation'#13#10,
    'implementation'#13#10'{$R Forms.res}'#13#10);
  if aShape = 'forward-full' then
    // DS HasCompleteClassDeclaration refuses the forward/full pair before ancestry; see DS-727.
    lSource := lSource.Replace('  TBindingForm = class(TBaseForm)',
      '  TBindingForm = class;'#13#10'  TBindingForm = class(TBaseForm)');
  TFile.WriteAllText(lFixture.fSource, lSource, TEncoding.UTF8);
  TFile.Delete(lFixture.fDfm);
  TFile.WriteAllBytes(TPath.Combine(lFixture.fDirectory, 'Forms.res'), [0, 0, 0, 0]);
  lSourceHash := BindingFixtureHash(lFixture.fDirectory);
  lFixture.fLog := TPath.Combine(lFixture.fDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' + QuoteArg(lFixture.fProject) +
    ' --config Debug --platform Win64 --delphi 23.0', lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(lSourceHash, BindingFixtureHash(lFixture.fDirectory));
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  GC(lRoot, g);
  Assert.IsNotNull(lRoot);
  Assert.AreEqual(Cardinal(3), lExit, lRoot.ToJSON);
  Assert.AreEqual('incomplete', lRoot.GetValue<string>('status'), lRoot.ToJSON);
  Assert.IsFalse((lRoot.FindValue('scope.complete') as TJSONBool).AsBoolean);
  Assert.AreEqual(0, (lRoot.GetValue('events') as TJSONArray).Count, lRoot.ToJSON);
  lFound := False;
  for lItem in (lRoot.GetValue('diagnostics') as TJSONArray) do
    if lItem.GetValue<string>('reason') = aReason then
    begin
      lFound := True;
      Assert.AreEqual(lFixture.fSource, lItem.GetValue<string>('fileName'));
      Assert.IsTrue(Pos('Forms.res', lItem.GetValue<string>('message')) > 0);
    end;
  Assert.IsTrue(lFound, lRoot.ToJSON);
end;

procedure TConsistencyTests.ResourceAncestryRequiresInspectedDeclaration(const aShape, aStatus: string);
var
  g: TGarbos;
  lFixture: TReportFixture;
  lSource, lWrongSource, lProject, lDpr, lSourceHash: string;
  lExit: Cardinal;
  lRoot: TJSONObject;
  lItem: TJSONValue;
  lFound: Boolean;
begin
  lFixture := Default(TReportFixture);
  lFixture.fDirectory := EvidenceDirectory;
  lFixture.fProject := TPath.Combine(lFixture.fDirectory, 'Binding.dproj');
  lFixture.fSource := TPath.Combine(lFixture.fDirectory, 'BindingForm.pas');
  lFixture.fDfm := ChangeFileExt(lFixture.fSource, '.dfm');
  WriteBindingFixture(lFixture, 'match', 'OnData');
  lWrongSource := 'unit WrongUnit;'#13#10'interface'#13#10 +
    'type TForm = class end;'#13#10;
  if aShape = 'impl-homonym' then
    lWrongSource := lWrongSource + '  TBindingForm = class end;'#13#10;
  TFile.WriteAllText(TPath.Combine(lFixture.fDirectory, 'WrongUnit.pas'),
    lWrongSource + 'implementation'#13#10'end.'#13#10, TEncoding.UTF8);
  lSource := 'unit BindingForm;'#13#10'interface'#13#10;
  if (aShape = 'impl-homonym') or (aShape = 'impl-no-homonym') then
    lSource := lSource + 'uses WrongUnit, Vcl.Forms;'#13#10 +
      'implementation'#13#10'type TBindingForm = class(Vcl.Forms.TForm) end;'#13#10
  else begin
    lSource := lSource + 'uses WrongUnit;'#13#10;
    if aShape = 'interface-uses' then
      lSource := lSource + 'type TBindingForm = class(TForm) end;'#13#10;
    lSource := lSource + 'implementation'#13#10'uses Vcl.Forms;'#13#10;
    if aShape = 'impl-uses' then
      lSource := lSource + 'type TBindingForm = class(TForm) end;'#13#10;
  end;
  TFile.WriteAllText(lFixture.fSource, lSource + '{$R Forms.res}'#13#10'end.'#13#10, TEncoding.UTF8);
  TFile.Delete(lFixture.fDfm);
  TFile.WriteAllBytes(TPath.Combine(lFixture.fDirectory, 'Forms.res'), [0, 0, 0, 0]);
  lDpr := TPath.Combine(lFixture.fDirectory, 'Binding.dpr');
  TFile.WriteAllText(lDpr, TFile.ReadAllText(lDpr, TEncoding.UTF8).Replace(
    'uses BindingForm', 'uses WrongUnit in ''WrongUnit.pas'', BindingForm'), TEncoding.UTF8);
  lProject := TFile.ReadAllText(lFixture.fProject, TEncoding.UTF8).Replace(
    '<DCCReference Include="BindingForm.pas"/>',
    '<DCCReference Include="WrongUnit.pas"/><DCCReference Include="BindingForm.pas"/>');
  TFile.WriteAllText(lFixture.fProject, lProject, TEncoding.UTF8);
  lSourceHash := BindingFixtureHash(lFixture.fDirectory);
  lFixture.fLog := TPath.Combine(lFixture.fDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' + QuoteArg(lFixture.fProject) +
    ' --config Debug --platform Win64 --delphi 23.0', lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(lSourceHash, BindingFixtureHash(lFixture.fDirectory));
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  GC(lRoot, g);
  Assert.IsNotNull(lRoot);
  Assert.AreEqual(aStatus, lRoot.GetValue<string>('status'), lRoot.ToJSON);
  Assert.AreEqual(0, (lRoot.GetValue('events') as TJSONArray).Count, lRoot.ToJSON);
  if aStatus = 'ok' then
  begin
    Assert.AreEqual(Cardinal(0), lExit, lRoot.ToJSON);
    Assert.IsTrue((lRoot.FindValue('scope.complete') as TJSONBool).AsBoolean);
    Assert.AreEqual(0, (lRoot.GetValue('diagnostics') as TJSONArray).Count, lRoot.ToJSON);
    Exit;
  end;
  Assert.AreEqual(Cardinal(3), lExit, lRoot.ToJSON);
  Assert.IsFalse((lRoot.FindValue('scope.complete') as TJSONBool).AsBoolean);
  lFound := False;
  for lItem in (lRoot.GetValue('diagnostics') as TJSONArray) do
    if lItem.GetValue<string>('reason') = 'dfm.resource-ancestry-unknown' then
    begin
      lFound := True;
      Assert.AreEqual(lFixture.fSource, lItem.GetValue<string>('fileName'));
      Assert.AreEqual('Forms.res', lItem.GetValue<string>('message'));
    end;
  Assert.IsTrue(lFound, lRoot.ToJSON);
end;

procedure TConsistencyTests.UnrelatedTFormResourceDoesNotClaimVclForm(const aShape: string);
var
  g: TGarbos;
  lFound: Boolean;
  lFixture: TReportFixture;
  lSource: string;
  lDpr: string;
  lProject: string;
  lSourceHash: string;
  lExit: Cardinal;
  lRoot: TJSONObject;
begin
  lFixture := Default(TReportFixture);
  lFixture.fDirectory := EvidenceDirectory;
  lFixture.fProject := TPath.Combine(lFixture.fDirectory, 'Binding.dproj');
  lFixture.fSource := TPath.Combine(lFixture.fDirectory, 'BindingForm.pas');
  lFixture.fDfm := ChangeFileExt(lFixture.fSource, '.dfm');
  WriteBindingFixture(lFixture, 'match', 'OnData');
  if aShape <> 'local-with-vcl' then
    TFile.WriteAllText(TPath.Combine(lFixture.fDirectory, 'WrongUnit.pas'),
      'unit WrongUnit;'#13#10'interface'#13#10 +
      'type TForm = class end;'#13#10'implementation'#13#10'end.'#13#10, TEncoding.UTF8);
  lSource := TFile.ReadAllText(lFixture.fSource, TEncoding.UTF8);
  if aShape = 'local-with-vcl' then
    lSource := lSource.Replace('unit BindingForm;'#13#10'interface',
      'unit BindingForm;'#13#10'interface'#13#10'uses Vcl.Forms;').Replace(
      '  TValue = class end;', '  TForm = class end;'#13#10'  TValue = class end;')
  else if aShape = 'indexed-last' then
    lSource := lSource.Replace('unit BindingForm;'#13#10'interface',
      'unit BindingForm;'#13#10'interface'#13#10'uses Vcl.Forms, WrongUnit;')
  else if aShape.StartsWith('later-') then
    lSource := lSource.Replace('unit BindingForm;'#13#10'interface',
      'unit BindingForm;'#13#10'interface'#13#10'uses WrongUnit, ' + Copy(aShape, 7, MaxInt) + ';')
  else
    lSource := lSource.Replace('unit BindingForm;'#13#10'interface',
      'unit BindingForm;'#13#10'interface'#13#10'uses WrongUnit;');
  if aShape = 'qualified' then
    lSource := lSource.Replace('TBindingForm = class', 'TBindingForm = class(WrongUnit.TForm)')
  else
    lSource := lSource.Replace('TBindingForm = class', 'TBindingForm = class(TForm)');
  lSource := lSource.Replace('implementation'#13#10,
    'implementation'#13#10'{$R Forms.res}'#13#10);
  TFile.WriteAllText(lFixture.fSource, lSource, TEncoding.UTF8);
  TFile.Delete(lFixture.fDfm);
  TFile.WriteAllBytes(TPath.Combine(lFixture.fDirectory, 'Forms.res'), [0, 0, 0, 0]);
  if aShape <> 'local-with-vcl' then
  begin
    lDpr := TPath.Combine(lFixture.fDirectory, 'Binding.dpr');
    TFile.WriteAllText(lDpr, TFile.ReadAllText(lDpr, TEncoding.UTF8).Replace(
      'uses BindingForm', 'uses WrongUnit in ''WrongUnit.pas'', BindingForm'), TEncoding.UTF8);
    lProject := TFile.ReadAllText(lFixture.fProject, TEncoding.UTF8).Replace(
      '<DCCReference Include="BindingForm.pas"/>',
      '<DCCReference Include="WrongUnit.pas"/><DCCReference Include="BindingForm.pas"/>');
    TFile.WriteAllText(lFixture.fProject, lProject, TEncoding.UTF8);
  end;
  lSourceHash := BindingFixtureHash(lFixture.fDirectory);
  lFixture.fLog := TPath.Combine(lFixture.fDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' + QuoteArg(lFixture.fProject) +
    ' --config Debug --platform Win64 --delphi 23.0', lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(lSourceHash, BindingFixtureHash(lFixture.fDirectory));
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  GC(lRoot, g);
  Assert.IsNotNull(lRoot);
  if aShape.StartsWith('later-') then
  begin
    Assert.AreEqual(Cardinal(3), lExit, lRoot.ToJSON);
    Assert.AreEqual('incomplete', lRoot.GetValue<string>('status'), lRoot.ToJSON);
    Assert.IsFalse((lRoot.FindValue('scope.complete') as TJSONBool).AsBoolean);
    lFound := False;
    for var lItem in (lRoot.GetValue('diagnostics') as TJSONArray) do
      if lItem.GetValue<string>('reason') = 'dfm.resource-ancestry-unknown' then
      begin
        lFound := True;
        Assert.AreEqual(lFixture.fSource, lItem.GetValue<string>('fileName'));
        Assert.AreEqual('Forms.res', lItem.GetValue<string>('message'));
      end;
    Assert.IsTrue(lFound, lRoot.ToJSON);
    Exit;
  end;
  Assert.AreEqual(Cardinal(0), lExit, lRoot.ToJSON);
  Assert.AreEqual('ok', lRoot.GetValue<string>('status'), lRoot.ToJSON);
  Assert.IsTrue((lRoot.FindValue('scope.complete') as TJSONBool).AsBoolean);
  Assert.AreEqual(0, (lRoot.GetValue('diagnostics') as TJSONArray).Count, lRoot.ToJSON);
end;

procedure TConsistencyTests.ProgramResourceDoesNotHideTextDfmBindings;
var
  g: TGarbos;
  lFixture: TReportFixture;
  lDpr: string;
  lSourceHash: string;
  lExit: Cardinal;
  lRoot: TJSONObject;
  lEvents: TJSONArray;
begin
  lFixture := Default(TReportFixture);
  lFixture.fDirectory := EvidenceDirectory;
  lFixture.fProject := TPath.Combine(lFixture.fDirectory, 'Binding.dproj');
  lFixture.fSource := TPath.Combine(lFixture.fDirectory, 'BindingForm.pas');
  lFixture.fDfm := ChangeFileExt(lFixture.fSource, '.dfm');
  WriteBindingFixture(lFixture, 'match', 'OnData');
  lDpr := TPath.Combine(lFixture.fDirectory, 'Binding.dpr');
  TFile.WriteAllText(lDpr, TFile.ReadAllText(lDpr, TEncoding.UTF8).Replace(
    'begin end.', '{$R App.res}'#13#10'begin end.'), TEncoding.UTF8);
  TFile.WriteAllBytes(TPath.Combine(lFixture.fDirectory, 'App.res'), [0, 0, 0, 0]);
  lSourceHash := BindingFixtureHash(lFixture.fDirectory);
  lFixture.fLog := TPath.Combine(lFixture.fDirectory, 'report.json');
  Assert.IsTrue(RunResolverProcess('consistency --project ' + QuoteArg(lFixture.fProject) +
    ' --config Debug --platform Win64 --delphi 23.0', lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(lSourceHash, BindingFixtureHash(lFixture.fDirectory));
  lRoot := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  GC(lRoot, g);
  Assert.IsNotNull(lRoot);
  Assert.AreEqual(Cardinal(0), lExit, lRoot.ToJSON);
  Assert.AreEqual('ok', lRoot.GetValue<string>('status'), lRoot.ToJSON);
  Assert.IsTrue((lRoot.FindValue('scope.complete') as TJSONBool).AsBoolean);
  Assert.AreEqual(0, (lRoot.GetValue('diagnostics') as TJSONArray).Count, lRoot.ToJSON);
  lEvents := lRoot.GetValue('events') as TJSONArray;
  Assert.AreEqual(1, lEvents.Count, lRoot.ToJSON);
  Assert.AreEqual('match', lEvents.Items[0].GetValue<string>('status'));
  Assert.AreEqual(lFixture.fDfm, lEvents.Items[0].GetValue<string>('fileName'));
end;

initialization
  TDUnitX.RegisterTestFixture(TConsistencyTests);

end.
