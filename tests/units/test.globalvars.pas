unit Test.GlobalVars;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TGlobalVarsTests = class
  private
    function FixtureProjectPath: string;
    function DakRoot: string;
    procedure DeleteDakRoot;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure RunGlobalVarsJsonOutputIncludesSupportedKinds;
    [Test] procedure RunGlobalVarsJsonOutputKeepsSymbolLocationAndUsageShape;
    [Test] procedure RunGlobalVarsJsonOutputSupportsUnusedOnlyFilter;
    [Test] procedure RunGlobalVarsJsonOutputSupportsUnitAndNameFilter;
    [Test] procedure RunGlobalVarsJsonOutputSupportsAccessFilters;
    [Test] procedure RunGlobalVarsTextOutputCreatesProjectCache;
    [Test] procedure RunGlobalVarsUsesDelphiSemanticsGlobalAnalyzer;
    [Test] procedure RunGlobalVarsLegacyExtractorIsNotCompiled;
    [Test] procedure RunGlobalVarsUsesSemanticCacheIdentity;
    [Test] procedure RunGlobalVarsCacheInvalidatesSameStampSameSizeContentChange;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  System.Variants,
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  Dak.GlobalVars,
  Dak.Types,
  MaxLogic.ioUtils;

function TGlobalVarsTests.FixtureProjectPath: string;
begin
  Result := TPath.GetFullPath(CombinePath([TPath.GetDirectoryName(ParamStr(0)), 'fixtures',
    'GlobalVarsFixture.dproj']));
end;

function TGlobalVarsTests.DakRoot: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(FixtureProjectPath), '.dak');
end;

procedure TGlobalVarsTests.DeleteDakRoot;
begin
  if TDirectory.Exists(DakRoot) then
  begin
    TDirectory.Delete(DakRoot, True);
  end;
end;

procedure TGlobalVarsTests.Setup;
begin
  DeleteDakRoot;
end;

procedure TGlobalVarsTests.TearDown;
begin
  DeleteDakRoot;
end;

procedure OpenSqliteCache(const aCacheFileName: string; out aDriverLink: TFDPhysSQLiteDriverLink;
  out aConnection: TFDConnection);
begin
  aDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  aConnection := TFDConnection.Create(nil);
  aConnection.LoginPrompt := False;
  aConnection.Params.Values['DriverID'] := 'SQLite';
  aConnection.Params.Values['Database'] := aCacheFileName;
  aConnection.Params.Values['LockingMode'] := 'Normal';
  aConnection.Params.Values['OpenMode'] := 'CreateUTF8';
  aConnection.Connected := True;
end;

function ReadCacheSchemaVersion(const aCacheFileName: string): string;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  OpenSqliteCache(aCacheFileName, lDriverLink, lConnection);
  try
    Result := VarToStr(lConnection.ExecSQLScalar(
      'select value_text from meta where key_name = ?', ['schema_version']));
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

procedure WriteCacheSchemaVersion(const aCacheFileName, aSchemaVersion: string);
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  OpenSqliteCache(aCacheFileName, lDriverLink, lConnection);
  try
    lConnection.ExecSQL('update meta set value_text = ? where key_name = ?',
      [aSchemaVersion, 'schema_version']);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function ReadGlobalVarsSourceText: string;
var
  lBuilder: TStringBuilder;
  lFileName: string;
  lFiles: TArray<string>;
begin
  lBuilder := TStringBuilder.Create;
  try
    lFiles := TDirectory.GetFiles(TPath.GetFullPath(CombinePath([
      TPath.GetDirectoryName(ParamStr(0)), '..', 'src'])), 'dak.globalvars*.pas');
    for lFileName in lFiles do
    begin
      lBuilder.AppendLine(TFile.ReadAllText(lFileName, TEncoding.UTF8));
    end;
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

procedure TGlobalVarsTests.RunGlobalVarsJsonOutputIncludesSupportedKinds;
var
  lOptions: TAppOptions;
  lOutputFileName: string;
  lContent: string;
  lJson: TJSONObject;
  lSummary: TJSONObject;
  lSymbols: TJSONArray;
  lItemValue: TJSONValue;
  lItem: TJSONObject;
  lUsedBy: TJSONArray;
  lFoundNames: TStringList;
begin
  FillChar(lOptions, SizeOf(lOptions), 0);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
  lOutputFileName := TPath.Combine(TPath.GetTempPath, 'global-vars-fixture.json');
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;

  if TFile.Exists(lOutputFileName) then
  begin
    TFile.Delete(lOutputFileName);
  end;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  Assert.IsTrue(TFile.Exists(lOutputFileName));

  lContent := TFile.ReadAllText(lOutputFileName, TEncoding.UTF8);
  lJson := TJSONObject.ParseJSONValue(lContent) as TJSONObject;
  lFoundNames := TStringList.Create;
  try
    Assert.IsNotNull(lJson);
    lSummary := lJson.GetValue<TJSONObject>('summary');
    Assert.IsNotNull(lSummary);
    Assert.AreEqual(5, lSummary.GetValue<Integer>('total'));
    Assert.AreEqual(4, lSummary.GetValue<Integer>('used'));
    Assert.AreEqual(1, lSummary.GetValue<Integer>('unused'));
    Assert.AreEqual(0, lSummary.GetValue<Integer>('ambiguities'));
    Assert.AreEqual(5, lSummary.GetValue<Integer>('emitted'));
    Assert.AreEqual('all', lSummary.GetValue<string>('filter'));
    lSymbols := lJson.GetValue<TJSONArray>('symbols');
    Assert.IsNotNull(lSymbols);
    Assert.AreEqual(5, lSymbols.Count);
    Assert.AreEqual(0, lJson.GetValue<TJSONArray>('ambiguities').Count);
    for lItemValue in lSymbols do
    begin
      lItem := lItemValue as TJSONObject;
      lFoundNames.Add(lItem.GetValue<string>('name'));
      if SameText(lItem.GetValue<string>('name'), 'GCounter') then
      begin
        lUsedBy := lItem.GetValue<TJSONArray>('usedBy');
        Assert.IsNotNull(lUsedBy);
        Assert.IsTrue(lUsedBy.Count > 0);
        Assert.IsTrue(Pos('RunConsumer', lUsedBy.ToJSON) > 0, 'Expected consumer routine usage for GCounter.');
      end;
      if SameText(lItem.GetValue<string>('name'), 'GThreadCounter') then
      begin
        Assert.AreEqual('threadvar', lItem.GetValue<string>('kind'));
      end;
      if SameText(lItem.GetValue<string>('name'), 'GTypedValue') then
      begin
        Assert.AreEqual('typedconst', lItem.GetValue<string>('kind'));
      end;
      if SameText(lItem.GetValue<string>('name'), 'sCache') then
      begin
        Assert.AreEqual('classvar', lItem.GetValue<string>('kind'));
      end;
      if SameText(lItem.GetValue<string>('name'), 'GUnusedValue') then
      begin
        lUsedBy := lItem.GetValue<TJSONArray>('usedBy');
        Assert.IsNotNull(lUsedBy);
        Assert.AreEqual(0, lUsedBy.Count);
      end;
    end;
    lFoundNames.Sort;
    Assert.AreEqual('GCounter', lFoundNames[0]);
    Assert.AreEqual('GThreadCounter', lFoundNames[1]);
    Assert.AreEqual('GTypedValue', lFoundNames[2]);
    Assert.AreEqual('GUnusedValue', lFoundNames[3]);
    Assert.AreEqual('sCache', lFoundNames[4]);
  finally
    lFoundNames.Free;
    lJson.Free;
  end;
end;

procedure TGlobalVarsTests.RunGlobalVarsJsonOutputKeepsSymbolLocationAndUsageShape;
var
  lContent: string;
  lItem: TJSONObject;
  lItemValue: TJSONValue;
  lJson: TJSONObject;
  lOptions: TAppOptions;
  lOutputFileName: string;
  lUsedBy: TJSONArray;
  lUsage: TJSONObject;
begin
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
  lOutputFileName := TPath.Combine(TPath.GetTempPath, 'global-vars-fixture-shape.json');
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;

  if TFile.Exists(lOutputFileName) then
  begin
    TFile.Delete(lOutputFileName);
  end;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  lContent := TFile.ReadAllText(lOutputFileName, TEncoding.UTF8);
  lJson := TJSONObject.ParseJSONValue(lContent) as TJSONObject;
  try
    Assert.IsNotNull(lJson);
    for lItemValue in lJson.GetValue<TJSONArray>('symbols') do
    begin
      lItem := lItemValue as TJSONObject;
      if SameText(lItem.GetValue<string>('name'), 'GCounter') then
      begin
        Assert.AreEqual('GlobalVarsFixture.Globals', lItem.GetValue<string>('declaringUnit'));
        Assert.IsTrue(EndsText('GlobalVarsFixture.Globals.pas', lItem.GetValue<string>('fileName')));
        Assert.AreEqual('Integer', lItem.GetValue<string>('type'));
        Assert.AreEqual('var', lItem.GetValue<string>('kind'));
        Assert.AreEqual(12, lItem.GetValue<Integer>('line'));
        Assert.AreEqual(3, lItem.GetValue<Integer>('column'));
        lUsedBy := lItem.GetValue<TJSONArray>('usedBy');
        Assert.IsNotNull(lUsedBy);
        Assert.IsTrue(lUsedBy.Count > 0, 'Expected usage payloads for GCounter.');
        lUsage := lUsedBy.Items[0] as TJSONObject;
        Assert.IsNotEmpty(lUsage.GetValue<string>('unit'));
        Assert.IsNotEmpty(lUsage.GetValue<string>('routine'));
        Assert.IsTrue(EndsText('.pas', lUsage.GetValue<string>('file')));
        Assert.IsTrue(lUsage.GetValue<Integer>('line') > 0);
        Assert.IsTrue(lUsage.GetValue<Integer>('column') > 0);
        Assert.IsTrue(MatchText(lUsage.GetValue<string>('access'), ['read', 'write', 'readwrite']),
          'Expected stable usage access classification.');
        Exit;
      end;
    end;
    Assert.Fail('Expected GCounter symbol payload.');
  finally
    lJson.Free;
  end;
end;

procedure TGlobalVarsTests.RunGlobalVarsJsonOutputSupportsUnusedOnlyFilter;
var
  lOptions: TAppOptions;
  lOutputFileName: string;
  lContent: string;
  lJson: TJSONObject;
  lSummary: TJSONObject;
  lSymbols: TJSONArray;
  lItem: TJSONObject;
begin
  FillChar(lOptions, SizeOf(lOptions), 0);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
  lOptions.fGlobalVarsUnusedOnly := True;
  lOutputFileName := TPath.Combine(TPath.GetTempPath, 'global-vars-fixture-unused.json');
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;

  if TFile.Exists(lOutputFileName) then
  begin
    TFile.Delete(lOutputFileName);
  end;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  Assert.IsTrue(TFile.Exists(lOutputFileName));

  lContent := TFile.ReadAllText(lOutputFileName, TEncoding.UTF8);
  lJson := TJSONObject.ParseJSONValue(lContent) as TJSONObject;
  try
    Assert.IsNotNull(lJson);
    lSummary := lJson.GetValue<TJSONObject>('summary');
    Assert.IsNotNull(lSummary);
    Assert.AreEqual(5, lSummary.GetValue<Integer>('total'));
    Assert.AreEqual(1, lSummary.GetValue<Integer>('unused'));
    Assert.AreEqual(0, lSummary.GetValue<Integer>('ambiguities'));
    Assert.AreEqual(1, lSummary.GetValue<Integer>('emitted'));
    Assert.AreEqual('unused-only', lSummary.GetValue<string>('filter'));
    lSymbols := lJson.GetValue<TJSONArray>('symbols');
    Assert.IsNotNull(lSymbols);
    Assert.AreEqual(1, lSymbols.Count);
    lItem := lSymbols.Items[0] as TJSONObject;
    Assert.AreEqual('GUnusedValue', lItem.GetValue<string>('name'));
  finally
    lJson.Free;
  end;
end;

procedure TGlobalVarsTests.RunGlobalVarsJsonOutputSupportsUnitAndNameFilter;
var
  lOptions: TAppOptions;
  lOutputFileName: string;
  lContent: string;
  lJson: TJSONObject;
  lSymbols: TJSONArray;
  lItem: TJSONObject;
begin
  FillChar(lOptions, SizeOf(lOptions), 0);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
  lOptions.fGlobalVarsUnitFilter := '*Globals*';
  lOptions.fHasGlobalVarsUnitFilter := True;
  lOptions.fGlobalVarsNameFilter := 'Typed';
  lOptions.fHasGlobalVarsNameFilter := True;
  lOutputFileName := TPath.Combine(TPath.GetTempPath, 'global-vars-fixture-unit-name.json');
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  lContent := TFile.ReadAllText(lOutputFileName, TEncoding.UTF8);
  lJson := TJSONObject.ParseJSONValue(lContent) as TJSONObject;
  try
    lSymbols := lJson.GetValue<TJSONArray>('symbols');
    Assert.AreEqual(1, lSymbols.Count);
    lItem := lSymbols.Items[0] as TJSONObject;
    Assert.AreEqual('GTypedValue', lItem.GetValue<string>('name'));
  finally
    lJson.Free;
  end;
end;

procedure TGlobalVarsTests.RunGlobalVarsJsonOutputSupportsAccessFilters;
var
  lOptions: TAppOptions;
  lOutputFileName: string;
  lContent: string;
  lJson: TJSONObject;
  lSymbols: TJSONArray;
  lNames: TStringList;
  lItemValue: TJSONValue;
begin
  FillChar(lOptions, SizeOf(lOptions), 0);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
  lOptions.fGlobalVarsWritesOnly := True;
  lOutputFileName := TPath.Combine(TPath.GetTempPath, 'global-vars-fixture-writes.json');
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  lContent := TFile.ReadAllText(lOutputFileName, TEncoding.UTF8);
  lJson := TJSONObject.ParseJSONValue(lContent) as TJSONObject;
  lNames := TStringList.Create;
  try
    lSymbols := lJson.GetValue<TJSONArray>('symbols');
    for lItemValue in lSymbols do
    begin
      lNames.Add((lItemValue as TJSONObject).GetValue<string>('name'));
    end;
    lNames.Sort;
    Assert.AreEqual(3, lNames.Count);
    Assert.AreEqual('GCounter', lNames[0]);
    Assert.AreEqual('GThreadCounter', lNames[1]);
    Assert.AreEqual('sCache', lNames[2]);
  finally
    lNames.Free;
    lJson.Free;
  end;
end;

procedure TGlobalVarsTests.RunGlobalVarsTextOutputCreatesProjectCache;
var
  lOptions: TAppOptions;
  lOutputFileName: string;
  lCacheFileName: string;
  lProjectDakRoot: string;
  lText: string;
begin
  FillChar(lOptions, SizeOf(lOptions), 0);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfText;
  lOutputFileName := TPath.Combine(TPath.GetTempPath, 'global-vars-fixture.txt');
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;

  if TFile.Exists(lOutputFileName) then
  begin
    TFile.Delete(lOutputFileName);
  end;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  Assert.IsTrue(TFile.Exists(lOutputFileName));
  lText := TFile.ReadAllText(lOutputFileName, TEncoding.UTF8);
  Assert.IsTrue(Pos('Summary: total=5 used=4 unused=1 ambiguities=0 emitted=5 filter=all', lText) = 1);
  Assert.IsTrue(ContainsText(lText, 'GlobalVarsFixture.Globals.GCounter: Integer [var]'));
  Assert.IsTrue(ContainsText(lText, '  used by:'));
  Assert.IsTrue(ContainsText(lText, 'GlobalVarsFixture.Consumer.RunConsumer'));
  Assert.IsTrue(ContainsText(lText, 'GlobalVarsFixture.Globals.GUnusedValue: Integer [var]'));
  Assert.IsTrue(ContainsText(lText, '  used by: none'));

  lProjectDakRoot := TPath.Combine(DakRoot, 'GlobalVarsFixture');
  lCacheFileName := TPath.Combine(lProjectDakRoot, 'global-vars\cache\global-vars-cache.sqlite3');
  Assert.IsTrue(TDirectory.Exists(lProjectDakRoot));
  Assert.IsTrue(TFile.Exists(lCacheFileName));
  Assert.AreEqual('3', ReadCacheSchemaVersion(lCacheFileName));

  WriteCacheSchemaVersion(lCacheFileName, '1');
  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  Assert.AreEqual('3', ReadCacheSchemaVersion(lCacheFileName));
end;

procedure TGlobalVarsTests.RunGlobalVarsUsesDelphiSemanticsGlobalAnalyzer;
var
  lSourceText: string;
begin
  lSourceText := ReadGlobalVarsSourceText;

  Assert.IsTrue(ContainsText(lSourceText, 'BuildGlobalAnalysis'),
    'GlobalVars production analysis must call the DelphiSemantics project session.');
end;

procedure TGlobalVarsTests.RunGlobalVarsLegacyExtractorIsNotCompiled;
var
  lSourceText: string;
begin
  lSourceText := ReadGlobalVarsSourceText;

  Assert.IsFalse(ContainsText(lSourceText, 'DAK_LEGACY_GLOBALVARS_EXTRACTOR'),
    'Legacy GlobalVars extractor block must be removed from DAK source.');
  Assert.IsFalse(ContainsText(lSourceText, 'ParseGlobalVarsFromAst'),
    'Legacy GlobalVars AST extraction must be removed from DAK source.');
end;

procedure TGlobalVarsTests.RunGlobalVarsUsesSemanticCacheIdentity;
var
  lSourceText: string;
begin
  lSourceText := ReadGlobalVarsSourceText;

  Assert.IsTrue(ContainsText(lSourceText, 'TDelphiSemanticUnitCacheIdentity'),
    'GlobalVars cache keys must reuse DelphiSemantics unit cache identity inputs.');
  Assert.IsFalse(ContainsText(lSourceText, 'TDelphiSemanticUnitModelExtractor'),
    'GlobalVars command orchestration should not extract semantic unit models directly.');
  Assert.IsFalse(ContainsText(lSourceText, 'DelphiAST.ProjectIndexer'),
    'GlobalVars command orchestration should not own project indexing.');
  Assert.IsFalse(ContainsText(lSourceText, 'GetLastWriteTimeUtc'),
    'GlobalVars cache invalidation must not rely on timestamp-only file stamps.');
  Assert.IsFalse(ContainsText(lSourceText, 'GetSize'),
    'GlobalVars cache invalidation must include content identity, not file size only.');
end;

procedure TGlobalVarsTests.RunGlobalVarsCacheInvalidatesSameStampSameSizeContentChange;
var
  lContent: string;
  lModifiedContent: string;
  lOptions: TAppOptions;
  lOriginalContent: string;
  lOriginalStamp: TDateTime;
  lOutputFileName: string;
  lSourceFileName: string;
begin
  lSourceFileName := TPath.GetFullPath(CombinePath([TPath.GetDirectoryName(ParamStr(0)),
    'fixtures', 'GlobalVarsFixture.Globals.pas']));
  lOutputFileName := TPath.Combine(TPath.GetTempPath,
    'global-vars-fixture-same-stamp-size.json');
  lOriginalContent := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);
  lOriginalStamp := TFile.GetLastWriteTimeUtc(lSourceFileName);
  lModifiedContent := StringReplace(lOriginalContent, 'GUnusedValue', 'GUnusedEntry',
    [rfReplaceAll]);
  Assert.AreEqual(Length(lOriginalContent), Length(lModifiedContent));

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;

  try
    Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
    TFile.WriteAllText(lSourceFileName, lModifiedContent, TEncoding.UTF8);
    TFile.SetLastWriteTimeUtc(lSourceFileName, lOriginalStamp);

    Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
    lContent := TFile.ReadAllText(lOutputFileName, TEncoding.UTF8);
    Assert.IsTrue(ContainsText(lContent, 'GUnusedEntry'));
    Assert.IsFalse(ContainsText(lContent, 'GUnusedValue'));
  finally
    TFile.WriteAllText(lSourceFileName, lOriginalContent, TEncoding.UTF8);
    TFile.SetLastWriteTimeUtc(lSourceFileName, lOriginalStamp);
    if TFile.Exists(lOutputFileName) then
      TFile.Delete(lOutputFileName);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TGlobalVarsTests);

end.
