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
    [Test] procedure RunGlobalVarsJsonOutputRejectsNonDeclarationsAndReportsProvenance;
    [Test] procedure RunGlobalVarsJsonOutputKeepsSymbolLocationAndUsageShape;
    [Test] procedure RunGlobalVarsJsonOutputSupportsUnusedOnlyFilter;
    [Test] procedure RunGlobalVarsJsonOutputSupportsUnitAndNameFilter;
    [Test] procedure RunGlobalVarsJsonOutputSupportsAccessFilters;
    [Test] procedure RunGlobalVarsTextOutputCreatesProjectCache;
    [Test] procedure RunGlobalVarsUsesDelphiSemanticsGlobalAnalyzer;
    [Test] procedure RunGlobalVarsLegacyExtractorIsNotCompiled;
    [Test] procedure RunGlobalVarsUsesSemanticCacheIdentity;
    [Test] procedure RunGlobalVarsCacheInvalidatesSameStampSameSizeContentChange;
    [Test] procedure GlobalVarsCachePreservesUnicodeTextValues;
    [Test] procedure RunGlobalVarsCommandPreservesUnicodePathsThroughCacheReuse;
    [Test] procedure RunGlobalVarsCacheUsesWideTextAccessors;
    [Test] procedure RunGlobalVarsCacheUsesBusyRetryPolicy;
    [Test] procedure RunGlobalVarsCacheHitLoadsFilteredSlice;
    [Test] procedure RunGlobalVarsCommandFiltersCacheHitProjection;
    [Test] procedure RunGlobalVarsSkillDocumentsDecisionGradeContract;
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  System.Variants,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  Dak.GlobalVars,
  Dak.GlobalVars.Cache,
  Dak.GlobalVars.Model,
  Dak.Semantics.Session,
  Dak.Types,
  MaxLogic.ioUtils,
  Test.Support;

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

function GlobalVarsUnicodeText: string;
begin
  Result := 'Za' + #$017C + #$00F3 + #$0142 + #$0107 + '-' + #$6F22 + #$5B57;
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
  lCacheOwners: TStringList;
  lCacheSymbolIds: TStringList;
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

  lContent := ReadUtf8TextFile(lOutputFileName);
  lJson := ParseJsonObject(lContent);
  lFoundNames := TStringList.Create;
  lCacheOwners := TStringList.Create;
  lCacheSymbolIds := TStringList.Create;
  try
    Assert.IsNotNull(lJson);
    lSummary := lJson.GetValue<TJSONObject>('summary');
    Assert.IsNotNull(lSummary);
    Assert.AreEqual(6, lSummary.GetValue<Integer>('total'));
    Assert.AreEqual(5, lSummary.GetValue<Integer>('used'));
    Assert.AreEqual(1, lSummary.GetValue<Integer>('unused'));
    Assert.AreEqual(0, lSummary.GetValue<Integer>('ambiguities'));
    Assert.AreEqual(6, lSummary.GetValue<Integer>('emitted'));
    Assert.AreEqual(0, lSummary.GetValue<Integer>('emittedAmbiguities'));
    Assert.AreEqual('all', lSummary.GetValue<string>('filter'));
    Assert.IsNotEmpty(lSummary.GetValue<string>('contextMode'),
      'Expected global-vars JSON to report project-analysis context mode.');
    lSymbols := lJson.GetValue<TJSONArray>('symbols');
    Assert.IsNotNull(lSymbols);
    Assert.AreEqual(6, lSymbols.Count);
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
        lUsedBy := lItem.GetValue<TJSONArray>('usedBy');
        Assert.IsNotNull(lUsedBy);
        Assert.IsTrue(lUsedBy.Count > 0,
          'Each same-named class variable must retain its own usage.');
        lCacheOwners.Add(lItem.GetValue<string>('owner'));
        lCacheSymbolIds.Add(lItem.GetValue<string>('symbolId'));
      end;
      if SameText(lItem.GetValue<string>('name'), 'GUnusedValue') then
      begin
        lUsedBy := lItem.GetValue<TJSONArray>('usedBy');
        Assert.IsNotNull(lUsedBy);
        Assert.AreEqual(0, lUsedBy.Count);
      end;
    end;
    Assert.AreEqual(2, lCacheOwners.Count);
    Assert.AreEqual(2, lCacheSymbolIds.Count);
    Assert.AreNotEqual(lCacheOwners[0], lCacheOwners[1]);
    Assert.AreNotEqual(lCacheSymbolIds[0], lCacheSymbolIds[1]);
    lFoundNames.Sort;
    Assert.AreEqual('GCounter', lFoundNames[0]);
    Assert.AreEqual('GThreadCounter', lFoundNames[1]);
    Assert.AreEqual('GTypedValue', lFoundNames[2]);
    Assert.AreEqual('GUnusedValue', lFoundNames[3]);
    Assert.AreEqual('sCache', lFoundNames[4]);
    Assert.AreEqual('sCache', lFoundNames[5]);
  finally
    lCacheSymbolIds.Free;
    lCacheOwners.Free;
    lFoundNames.Free;
    lJson.Free;
  end;
end;

procedure TGlobalVarsTests.
  RunGlobalVarsJsonOutputRejectsNonDeclarationsAndReportsProvenance;
var
  lCompilerContext: TJSONObject;
  lDelphiSemantics: TJSONObject;
  lGlobalVars: TJSONObject;
  lItem: TJSONObject;
  lItemValue: TJSONValue;
  lJson: TJSONObject;
  lNames: TStringList;
  lOptions: TAppOptions;
  lOutputFileName: string;
  lProvenance: TJSONObject;
  lSymbols: TJSONArray;
begin
  lOutputFileName := TPath.Combine(TPath.GetTempPath,
    'global-vars-fixture-scope-provenance.json');
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fDelphiVersion := '23.0';
  lOptions.fPlatform := 'Win64';
  lOptions.fConfig := 'Debug';
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;
  lOptions.fGlobalVarsRefresh := TGlobalVarsRefresh.gvrForce;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  lJson := ParseJsonObject(ReadUtf8TextFile(lOutputFileName));
  lNames := TStringList.Create;
  try
    Assert.IsNotNull(lJson);
    lSymbols := lJson.GetValue<TJSONArray>('symbols');
    Assert.AreEqual(6, lSymbols.Count);
    for lItemValue in lSymbols do
    begin
      lItem := lItemValue as TJSONObject;
      lNames.Add(lItem.GetValue<string>('name'));
      Assert.IsFalse(lItem.GetValue<string>('type').StartsWith('='),
        'Assignment-shaped types must be rejected.');
      Assert.AreEqual('declaration', lItem.GetValue<string>('declarationRole'));
      Assert.IsNotEmpty(lItem.GetValue<string>('scopeKind'));
      Assert.IsNotEmpty(lItem.GetValue<string>('ownerScopeId'));
      Assert.IsNotEmpty(lItem.GetValue<string>('symbolId'));
    end;
    Assert.IsFalse(lNames.Contains('lValue'));
    Assert.IsFalse(lNames.Contains('Result'));
    Assert.IsFalse(lNames.Contains('CaseSensitive'));
    Assert.IsFalse(lNames.Contains('NameValueSeparator'));

    lProvenance := lJson.GetValue<TJSONObject>('provenance');
    Assert.IsNotNull(lProvenance);
    Assert.IsNotEmpty(lProvenance.GetValue<TJSONObject>('dak').GetValue<string>(
      'executableVersion'));
    Assert.IsNotEmpty(lProvenance.GetValue<TJSONObject>('dak').GetValue<string>(
      'executableSha256'));
    Assert.IsNotEmpty(lProvenance.GetValue<TJSONObject>('dak').GetValue<string>(
      'sourceRevision'));
    lDelphiSemantics := lProvenance.GetValue<TJSONObject>('delphiSemantics');
    Assert.AreEqual('DelphiSemantics.Model.Parser.4',
      lDelphiSemantics.GetValue<string>('parserVersion'));
    Assert.IsNotEmpty(lDelphiSemantics.GetValue<string>('modelVersion'));
    Assert.AreEqual('9', lDelphiSemantics.GetValue<string>('cacheSchemaVersion'));
    Assert.AreEqual('snapshot', lDelphiSemantics.GetValue<string>('factSource'));
    Assert.IsTrue(lDelphiSemantics.GetValue<Integer>('snapshotUnitCount') > 0);
    Assert.AreEqual(lDelphiSemantics.GetValue<Integer>('snapshotUnitCount'),
      lDelphiSemantics.GetValue<Integer>('verifiedScopeUnitCount'));
    Assert.AreEqual(0, lDelphiSemantics.GetValue<Integer>('modelFallbackUnitCount'));
    Assert.AreEqual(0, lDelphiSemantics.GetValue<Integer>('heuristicFallbackUnitCount'));
    Assert.IsTrue(lDelphiSemantics.GetValue<Integer>('rejectedDeclarationCount') >= 0);
    Assert.AreEqual(lDelphiSemantics.GetValue<Integer>('diagnosticCount'),
      lDelphiSemantics.GetValue<TJSONArray>('diagnostics').Count);
    Assert.IsNotEmpty(lDelphiSemantics.GetValue<string>('sourceRevision'));
    Assert.IsNotEmpty(lDelphiSemantics.GetValue<string>('sourceRevisionSource'));
    lCompilerContext := lProvenance.GetValue<TJSONObject>('compilerContext');
    Assert.AreEqual('23.0', lCompilerContext.GetValue<string>('delphiVersion'));
    Assert.AreEqual('Win64', lCompilerContext.GetValue<string>('platform'));
    Assert.AreEqual('Debug', lCompilerContext.GetValue<string>('configuration'));
    Assert.IsTrue(lCompilerContext.GetValue<Boolean>('decisionGrade'));
    lGlobalVars := lProvenance.GetValue<TJSONObject>('globalVars');
    Assert.AreEqual('5', lGlobalVars.GetValue<string>('cacheSchemaVersion'));
    Assert.IsTrue(lGlobalVars.GetValue<Integer>('rejectedImpossibleDeclarations') >= 0);
  finally
    lNames.Free;
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
  lContent := ReadUtf8TextFile(lOutputFileName);
  lJson := ParseJsonObject(lContent);
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
        Assert.AreEqual(20, lItem.GetValue<Integer>('line'));
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

  lContent := ReadUtf8TextFile(lOutputFileName);
  lJson := ParseJsonObject(lContent);
  try
    Assert.IsNotNull(lJson);
    lSummary := lJson.GetValue<TJSONObject>('summary');
    Assert.IsNotNull(lSummary);
    Assert.AreEqual(6, lSummary.GetValue<Integer>('total'));
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
  lContent := ReadUtf8TextFile(lOutputFileName);
  lJson := ParseJsonObject(lContent);
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
  lContent := ReadUtf8TextFile(lOutputFileName);
  lJson := ParseJsonObject(lContent);
  lNames := TStringList.Create;
  try
    lSymbols := lJson.GetValue<TJSONArray>('symbols');
    for lItemValue in lSymbols do
    begin
      lNames.Add((lItemValue as TJSONObject).GetValue<string>('name'));
    end;
    lNames.Sort;
    Assert.AreEqual(4, lNames.Count);
    Assert.AreEqual('GCounter', lNames[0]);
    Assert.AreEqual('GThreadCounter', lNames[1]);
    Assert.AreEqual('sCache', lNames[2]);
    Assert.AreEqual('sCache', lNames[3]);
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
  lText := ReadUtf8TextFile(lOutputFileName);
  Assert.IsTrue(Pos('Summary: total=6 used=5 unused=1 ambiguities=0 emitted=6 filter=all', lText) = 1);
  Assert.IsTrue(ContainsText(lText, 'GlobalVarsFixture.Globals.GCounter: Integer [var]'));
  Assert.IsTrue(ContainsText(lText, '  used by:'));
  Assert.IsTrue(ContainsText(lText, 'GlobalVarsFixture.Consumer.RunConsumer'));
  Assert.IsTrue(ContainsText(lText, 'GlobalVarsFixture.Globals.GUnusedValue: Integer [var]'));
  Assert.IsTrue(ContainsText(lText, '  used by: none'));

  lProjectDakRoot := TPath.Combine(DakRoot, 'GlobalVarsFixture');
  lCacheFileName := TPath.Combine(lProjectDakRoot, 'global-vars\cache\global-vars-cache.sqlite3');
  Assert.IsTrue(TDirectory.Exists(lProjectDakRoot));
  Assert.IsTrue(TFile.Exists(lCacheFileName));
  Assert.AreEqual('5', ReadCacheSchemaVersion(lCacheFileName));

  WriteCacheSchemaVersion(lCacheFileName, '1');
  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  Assert.AreEqual('5', ReadCacheSchemaVersion(lCacheFileName));
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

  Assert.IsTrue(ContainsText(lSourceText, 'TDakSemanticUnitCacheIdentity'),
    'GlobalVars cache keys must use the DAK adapter unit cache identity inputs.');
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
    lContent := ReadUtf8TextFile(lOutputFileName);
    Assert.IsTrue(ContainsText(lContent, 'GUnusedEntry'));
    Assert.IsFalse(ContainsText(lContent, 'GUnusedValue'));
  finally
    TFile.WriteAllText(lSourceFileName, lOriginalContent, TEncoding.UTF8);
    TFile.SetLastWriteTimeUtc(lSourceFileName, lOriginalStamp);
    if TFile.Exists(lOutputFileName) then
      TFile.Delete(lOutputFileName);
  end;
end;

procedure TGlobalVarsTests.GlobalVarsCachePreservesUnicodeTextValues;
var
  lAmbiguity: TGlobalVarAmbiguity;
  lAmbiguities: TList<TGlobalVarAmbiguity>;
  lCacheFileName: string;
  lFilter: TGlobalVarsCacheLoadFilter;
  lIdentities: TArray<TDakSemanticUnitCacheIdentity>;
  lAmbiguityFileName: string;
  lLoadedAmbiguities: TList<TGlobalVarAmbiguity>;
  lLoadedProject: TProjectInfo;
  lLoadedSymbols: TObjectList<TGlobalVarSymbol>;
  lProject: TProjectInfo;
  lProjectPath: string;
  lRef: TGlobalVarRef;
  lRefFileName: string;
  lSymbol: TGlobalVarSymbol;
  lSymbolFileName: string;
  lSymbols: TObjectList<TGlobalVarSymbol>;
  lSummary: TGlobalVarsSummary;
  lUnicodeText: string;
begin
  lUnicodeText := GlobalVarsUnicodeText;
  lCacheFileName := TPath.Combine(DakRoot, 'unicode-cache\global-vars-cache.sqlite3');
  lProjectPath := TPath.Combine(DakRoot, 'Projekt-' + lUnicodeText + '.dproj');

  SetLength(lIdentities, 1);
  lIdentities[0].UnitCacheKey := 'unit-' + lUnicodeText;
  lIdentities[0].FileHash := 'file-' + lUnicodeText;
  lIdentities[0].ContextHash := 'context-' + lUnicodeText;
  lIdentities[0].IncludeGraphHash := 'include-' + lUnicodeText;
  lIdentities[0].DefinesHash := 'defines-' + lUnicodeText;
  lIdentities[0].SearchPathHash := 'search-' + lUnicodeText;
  lIdentities[0].ExtractionOptionsHash := 'options-' + lUnicodeText;
  lIdentities[0].CompilerProfileName := 'profile-' + lUnicodeText;
  lIdentities[0].DelphiVersion := '23.0-' + lUnicodeText;
  lIdentities[0].Configuration := 'Debug-' + lUnicodeText;
  lIdentities[0].Platform := 'Win64-' + lUnicodeText;
  lIdentities[0].ParserVersion := 'parser-' + lUnicodeText;
  lIdentities[0].ModelVersion := 'model-' + lUnicodeText;
  lIdentities[0].SchemaVersion := 'schema-' + lUnicodeText;

  lSymbols := TObjectList<TGlobalVarSymbol>.Create(True);
  lAmbiguities := TList<TGlobalVarAmbiguity>.Create;
  lProject := Default(TProjectInfo);
  lProject.SemanticFactSource := 'snapshot';
  lProject.SemanticSnapshotUnitCount := 3;
  lProject.SemanticVerifiedScopeUnitCount := 2;
  lProject.SemanticModelFallbackUnitCount := 1;
  lProject.SemanticRejectedDeclarationCount := 7;
  lProject.SemanticSourceRevision := 'semantic-revision-' + lUnicodeText;
  lProject.SemanticSourceRevisionSource := 'test';
  SetLength(lProject.SemanticDiagnostics, 1);
  lProject.SemanticDiagnostics[0].Code := 'SCOPE_MODEL_FAILED';
  lProject.SemanticDiagnostics[0].Message := 'diagnostic-' + lUnicodeText;
  lProject.SemanticDiagnostics[0].FileName := 'diagnostic-' + lUnicodeText + '.pas';
  lProject.SemanticDiagnostics[0].Line := 42;
  try
    lSymbol := TGlobalVarSymbol.Create;
    lSymbol.UnitName := 'Projekt.' + lUnicodeText;
    lSymbolFileName := TPath.Combine(DakRoot, 'Source-' + lUnicodeText + '.pas');
    lSymbol.FileName := lSymbolFileName;
    lSymbol.Name := 'G' + lUnicodeText;
    lSymbol.TypeName := 'T' + lUnicodeText;
    lSymbol.Line := 12;
    lSymbol.Column := 3;
    lSymbol.Kind := gvkClassVar;
    lRef.UnitName := 'Consumer.' + lUnicodeText;
    lRef.RoutineName := 'Use' + lUnicodeText;
    lRef.RoutineScopeId := 'scope-' + lUnicodeText;
    lRefFileName := TPath.Combine(DakRoot, 'Consumer-' + lUnicodeText + '.pas');
    lRef.FileName := lRefFileName;
    lRef.Line := 24;
    lRef.Column := 7;
    lRef.Access := akReadWrite;
    lSymbol.UsedBy.Add(lRef);
    lSymbols.Add(lSymbol);

    lAmbiguity.Name := 'Ambiguous' + lUnicodeText;
    lAmbiguity.UnitName := 'Ambiguous.Unit.' + lUnicodeText;
    lAmbiguity.RoutineName := 'Resolve' + lUnicodeText;
    lAmbiguityFileName := TPath.Combine(DakRoot, 'Ambiguous-' + lUnicodeText + '.pas');
    lAmbiguity.FileName := lAmbiguityFileName;
    lAmbiguity.Line := 31;
    lAmbiguity.Column := 9;
    lAmbiguity.Access := akWrite;
    lAmbiguity.Candidates := 'First.' + lUnicodeText + '|Second.' + lUnicodeText;
    lAmbiguities.Add(lAmbiguity);

    SaveCachedSymbols(lCacheFileName, lProjectPath, 'identity-' + lUnicodeText, lIdentities,
      lProject, lSymbols, lAmbiguities);
  finally
    lAmbiguities.Free;
    lSymbols.Free;
  end;

  lFilter := Default(TGlobalVarsCacheLoadFilter);
  lLoadedProject := Default(TProjectInfo);
  Assert.IsTrue(TryLoadCachedSymbols(lCacheFileName, lProjectPath, 'identity-' + lUnicodeText,
    lFilter, lLoadedProject, lLoadedSymbols, lLoadedAmbiguities, lSummary));
  try
    Assert.AreEqual<Integer>(1, lLoadedSymbols.Count);
    Assert.AreEqual('Projekt.' + lUnicodeText, lLoadedSymbols[0].UnitName);
    Assert.AreEqual(lSymbolFileName, lLoadedSymbols[0].FileName);
    Assert.AreEqual('G' + lUnicodeText, lLoadedSymbols[0].Name);
    Assert.AreEqual('T' + lUnicodeText, lLoadedSymbols[0].TypeName);
    Assert.AreEqual<Integer>(1, lLoadedSymbols[0].UsedBy.Count);
    Assert.AreEqual('Use' + lUnicodeText, lLoadedSymbols[0].UsedBy[0].RoutineName);
    Assert.AreEqual('scope-' + lUnicodeText,
      lLoadedSymbols[0].UsedBy[0].RoutineScopeId);
    Assert.AreEqual('Consumer.' + lUnicodeText, lLoadedSymbols[0].UsedBy[0].UnitName);
    Assert.AreEqual(lRefFileName, lLoadedSymbols[0].UsedBy[0].FileName);
    Assert.AreEqual(Integer(akReadWrite), Integer(lLoadedSymbols[0].UsedBy[0].Access));
    Assert.AreEqual<Integer>(1, lLoadedAmbiguities.Count);
    Assert.AreEqual('Ambiguous' + lUnicodeText, lLoadedAmbiguities[0].Name);
    Assert.AreEqual('Resolve' + lUnicodeText, lLoadedAmbiguities[0].RoutineName);
    Assert.AreEqual(lAmbiguityFileName, lLoadedAmbiguities[0].FileName);
    Assert.AreEqual('First.' + lUnicodeText + '|Second.' + lUnicodeText,
      lLoadedAmbiguities[0].Candidates);
    Assert.AreEqual('snapshot', lLoadedProject.SemanticFactSource);
    Assert.AreEqual<Integer>(3, lLoadedProject.SemanticSnapshotUnitCount);
    Assert.AreEqual<Integer>(2, lLoadedProject.SemanticVerifiedScopeUnitCount);
    Assert.AreEqual<Integer>(1, lLoadedProject.SemanticModelFallbackUnitCount);
    Assert.AreEqual<Integer>(7, lLoadedProject.SemanticRejectedDeclarationCount);
    Assert.AreEqual('semantic-revision-' + lUnicodeText,
      lLoadedProject.SemanticSourceRevision);
    Assert.AreEqual<Integer>(1, Length(lLoadedProject.SemanticDiagnostics));
    Assert.AreEqual('SCOPE_MODEL_FAILED',
      lLoadedProject.SemanticDiagnostics[0].Code);
    Assert.AreEqual('diagnostic-' + lUnicodeText,
      lLoadedProject.SemanticDiagnostics[0].Message);
  finally
    lLoadedAmbiguities.Free;
    lLoadedSymbols.Free;
  end;
end;

procedure TGlobalVarsTests.RunGlobalVarsCommandPreservesUnicodePathsThroughCacheReuse;
var
  lCacheFileName: string;
  lConnection: TFDConnection;
  lDestinationFileName: string;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lFileName: string;
  lFirstContent: string;
  lFixtureRoot: string;
  lFoundUnicodePath: Boolean;
  lItem: TJSONObject;
  lItemValue: TJSONValue;
  lJson: TJSONObject;
  lOptions: TAppOptions;
  lOutputFileName: string;
  lProjectRoot: string;
  lQuery: TFDQuery;
  lSecondContent: string;
  lSentinelFileName: string;
  lUnicodeText: string;
begin
  lUnicodeText := GlobalVarsUnicodeText;
  lFixtureRoot := TPath.GetDirectoryName(FixtureProjectPath);
  lProjectRoot := TPath.Combine(DakRoot, 'Projekt-' + lUnicodeText);
  TDirectory.CreateDirectory(lProjectRoot);
  for lFileName in TDirectory.GetFiles(lFixtureRoot) do
  begin
    lDestinationFileName := TPath.Combine(lProjectRoot, TPath.GetFileName(lFileName));
    TFile.Copy(lFileName, lDestinationFileName, True);
  end;

  lOutputFileName := TPath.Combine(DakRoot, 'global-vars-unicode-paths.json');
  lCacheFileName := TPath.Combine(lProjectRoot, '.dak\GlobalVarsFixture\global-vars\cache\' +
    'global-vars-cache.sqlite3');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(lProjectRoot, 'GlobalVarsFixture.dproj');
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  lFirstContent := ReadUtf8TextFile(lOutputFileName);
  lJson := ParseJsonObject(lFirstContent);
  try
    Assert.IsNotNull(lJson);
    lFoundUnicodePath := False;
    for lItemValue in lJson.GetValue<TJSONArray>('symbols') do
    begin
      lItem := lItemValue as TJSONObject;
      if ContainsText(lItem.GetValue<string>('fileName'), lUnicodeText) then
      begin
        lFoundUnicodePath := True;
        Break;
      end;
    end;
    Assert.IsTrue(lFoundUnicodePath,
      'Fresh global-vars extraction should preserve the non-ASCII project/source path.');
  finally
    lJson.Free;
  end;
  Assert.IsTrue(TFile.Exists(lCacheFileName), 'Expected command-level projection cache.');

  lSentinelFileName := TPath.Combine(lProjectRoot, 'Cached-' + lUnicodeText + '.pas');
  OpenSqliteCache(lCacheFileName, lDriverLink, lConnection);
  lQuery := TFDQuery.Create(nil);
  try
    lQuery.Connection := lConnection;
    lQuery.SQL.Text := 'update symbols set file_name = ?';
    lQuery.Params[0].DataType := ftWideString;
    lQuery.Params[0].AsWideString := lSentinelFileName;
    lQuery.ExecSQL;
  finally
    lQuery.Free;
    lConnection.Free;
    lDriverLink.Free;
  end;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  lSecondContent := ReadUtf8TextFile(lOutputFileName);
  lJson := ParseJsonObject(lSecondContent);
  try
    Assert.IsNotNull(lJson);
    lFoundUnicodePath := False;
    for lItemValue in lJson.GetValue<TJSONArray>('symbols') do
    begin
      lItem := lItemValue as TJSONObject;
      if SameText(lItem.GetValue<string>('fileName'), lSentinelFileName) then
      begin
        lFoundUnicodePath := True;
        Break;
      end;
    end;
    Assert.IsTrue(lFoundUnicodePath,
      'Second command run should reuse the cached non-ASCII path payload.');
  finally
    lJson.Free;
  end;
end;

procedure TGlobalVarsTests.RunGlobalVarsCacheUsesWideTextAccessors;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.GetFullPath(CombinePath([TPath.GetDirectoryName(ParamStr(0)), '..',
    'src', 'Dak.GlobalVars.Cache.pas']));
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsFalse(ContainsText(lSourceText, '.AsString'),
    'GlobalVars cache text fields and parameters should use Unicode-safe accessors.');
  Assert.IsFalse(ContainsText(lSourceText, 'VarToStr(lConnection.ExecSQLScalar'),
    'GlobalVars cache metadata reads should use wide field accessors.');
  Assert.IsFalse(ContainsText(lSourceText, 'ExecSQL(''insert into symbols'),
    'GlobalVars cache symbol writes should use prepared wide parameters.');
  Assert.IsFalse(ContainsText(lSourceText, 'ExecSQL(''insert into refs'),
    'GlobalVars cache reference writes should use prepared wide parameters.');
  Assert.IsFalse(ContainsText(lSourceText, 'ExecSQL(''insert into ambiguities'),
    'GlobalVars cache ambiguity writes should use prepared wide parameters.');
  Assert.IsTrue(ContainsText(lSourceText, '.AsWideString'),
    'GlobalVars cache should read/write text through wide accessors.');
end;

procedure TGlobalVarsTests.RunGlobalVarsCacheUsesBusyRetryPolicy;
var
  lSourceFileName: string;
  lSourceText: string;
begin
  lSourceFileName := TPath.GetFullPath(CombinePath([TPath.GetDirectoryName(ParamStr(0)), '..',
    'src', 'Dak.GlobalVars.Cache.pas']));
  lSourceText := TFile.ReadAllText(lSourceFileName, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSourceText, 'cGlobalVarsCacheBusyTimeoutMs'),
    'GlobalVars cache must document the SQLite busy/retry wait policy.');
  Assert.IsTrue(ContainsText(lSourceText, 'BusyTimeout'),
    'GlobalVars cache connections must wait/retry when another process holds the SQLite file.');
  Assert.IsTrue(ContainsText(lSourceText, 'StartTransaction'),
    'GlobalVars cache refresh must remain atomic while relying on SQLite lock waiting.');
end;

procedure TGlobalVarsTests.RunGlobalVarsSkillDocumentsDecisionGradeContract;
var
  lSkillPath: string;
  lSkillText: string;
begin
  lSkillPath := TPath.GetFullPath(CombinePath([TPath.GetDirectoryName(ParamStr(0)),
    '..', 'agentskills', 'dak-global-vars', 'SKILL.md']));
  lSkillText := TFile.ReadAllText(lSkillPath, TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSkillText, '--delphi'));
  Assert.IsTrue(ContainsText(lSkillText, '--platform'));
  Assert.IsTrue(ContainsText(lSkillText, '--config'));
  Assert.IsTrue(ContainsText(lSkillText, '--rsvars'));
  Assert.IsTrue(ContainsText(lSkillText, '--envoptions'));
  Assert.IsTrue(ContainsText(lSkillText, 'strict-semantic'));
  Assert.IsTrue(ContainsText(lSkillText, 'degraded-project-only'));
  Assert.IsTrue(ContainsText(lSkillText, 'decisionGrade'));
  Assert.IsTrue(ContainsText(lSkillText, 'declarationRole'));
  Assert.IsTrue(ContainsText(lSkillText, 'ownerScopeId'));
  Assert.IsTrue(ContainsText(lSkillText, 'symbolId'));
  Assert.IsTrue(ContainsText(lSkillText, 'routineScopeId'));
  Assert.IsTrue(ContainsText(lSkillText, 'verifiedScopeUnitCount'));
  Assert.IsTrue(ContainsText(lSkillText, 'rejectedDeclarationCount'));
  Assert.IsTrue(ContainsText(lSkillText, 'diagnosticCount'));
  Assert.IsTrue(ContainsText(lSkillText, 'sourceRevisionSource'));
  Assert.IsTrue(ContainsText(lSkillText, '"cacheSchemaVersion": "5"'));
  Assert.IsTrue(ContainsText(lSkillText, 'rejectedImpossibleDeclarations'));
end;

procedure TGlobalVarsTests.RunGlobalVarsCacheHitLoadsFilteredSlice;
var
  lAmbiguity: TGlobalVarAmbiguity;
  lAmbiguities: TList<TGlobalVarAmbiguity>;
  lCacheFileName: string;
  lFilter: TGlobalVarsCacheLoadFilter;
  lIdentities: TArray<TDakSemanticUnitCacheIdentity>;
  lLoadedAmbiguities: TList<TGlobalVarAmbiguity>;
  lLoadedSymbols: TObjectList<TGlobalVarSymbol>;
  lProjectPath: string;
  lRef: TGlobalVarRef;
  lSummary: TGlobalVarsSummary;
  lSymbol: TGlobalVarSymbol;
  lSymbols: TObjectList<TGlobalVarSymbol>;
begin
  lCacheFileName := TPath.Combine(DakRoot, 'filtered-cache\global-vars-cache.sqlite3');
  lProjectPath := TPath.Combine(DakRoot, 'FilteredGlobalVars.dproj');
  SetLength(lIdentities, 1);
  lIdentities[0].UnitCacheKey := 'filtered-unit';
  lIdentities[0].FileHash := 'filtered-file';
  lIdentities[0].ContextHash := 'filtered-context';
  lIdentities[0].IncludeGraphHash := 'filtered-include';
  lIdentities[0].DefinesHash := 'filtered-defines';
  lIdentities[0].SearchPathHash := 'filtered-search';
  lIdentities[0].ExtractionOptionsHash := 'filtered-options';
  lIdentities[0].CompilerProfileName := 'filtered-profile';
  lIdentities[0].DelphiVersion := '23.0';
  lIdentities[0].Configuration := 'Debug';
  lIdentities[0].Platform := 'Win64';
  lIdentities[0].ParserVersion := 'parser';
  lIdentities[0].ModelVersion := 'model';
  lIdentities[0].SchemaVersion := 'schema';

  lSymbols := TObjectList<TGlobalVarSymbol>.Create(True);
  lAmbiguities := TList<TGlobalVarAmbiguity>.Create;
  try
    lSymbol := TGlobalVarSymbol.Create;
    lSymbol.UnitName := 'Filtered.Globals';
    lSymbol.FileName := 'Filtered.Globals.pas';
    lSymbol.Name := 'GAlpha';
    lSymbol.TypeName := 'Integer';
    lSymbol.Line := 10;
    lSymbol.Column := 3;
    lSymbol.Kind := gvkVar;
    lRef.UnitName := 'Filtered.Consumer';
    lRef.RoutineName := 'ReadAlpha';
    lRef.FileName := 'Filtered.Consumer.pas';
    lRef.Line := 20;
    lRef.Column := 5;
    lRef.Access := akRead;
    lSymbol.UsedBy.Add(lRef);
    lRef.RoutineName := 'WriteAlpha';
    lRef.Line := 21;
    lRef.Access := akWrite;
    lSymbol.UsedBy.Add(lRef);
    lRef.RoutineName := 'ReadWriteAlpha';
    lRef.Line := 22;
    lRef.Access := akReadWrite;
    lSymbol.UsedBy.Add(lRef);
    lSymbols.Add(lSymbol);

    lSymbol := TGlobalVarSymbol.Create;
    lSymbol.UnitName := 'Other.Globals';
    lSymbol.FileName := 'Other.Globals.pas';
    lSymbol.Name := 'GBeta';
    lSymbol.TypeName := 'Integer';
    lSymbol.Line := 30;
    lSymbol.Column := 3;
    lSymbol.Kind := gvkVar;
    lSymbols.Add(lSymbol);

    lAmbiguity.Name := 'GAlpha';
    lAmbiguity.UnitName := 'Filtered.Consumer';
    lAmbiguity.RoutineName := 'ReadAlpha';
    lAmbiguity.FileName := 'Filtered.Consumer.pas';
    lAmbiguity.Line := 40;
    lAmbiguity.Column := 7;
    lAmbiguity.Access := akRead;
    lAmbiguity.Candidates := 'Filtered.Globals.GAlpha';
    lAmbiguities.Add(lAmbiguity);

    lAmbiguity.Name := 'GBeta';
    lAmbiguity.UnitName := 'Other.Consumer';
    lAmbiguity.RoutineName := 'WriteBeta';
    lAmbiguity.FileName := 'Other.Consumer.pas';
    lAmbiguity.Line := 41;
    lAmbiguity.Column := 7;
    lAmbiguity.Access := akWrite;
    lAmbiguity.Candidates := 'Other.Globals.GBeta';
    lAmbiguities.Add(lAmbiguity);

    lSymbol := TGlobalVarSymbol.Create;
    lSymbol.UnitName := 'Escaped.Percent_Unit';
    lSymbol.FileName := 'Escaped.Percent_Unit.pas';
    lSymbol.Name := 'GPercent_Value';
    lSymbol.TypeName := 'Integer';
    lSymbol.Line := 50;
    lSymbol.Column := 3;
    lSymbol.Kind := gvkVar;
    lSymbols.Add(lSymbol);

    SaveCachedSymbols(lCacheFileName, lProjectPath, 'filtered-identity', lIdentities,
      lSymbols, lAmbiguities);
  finally
    lAmbiguities.Free;
    lSymbols.Free;
  end;

  lFilter := Default(TGlobalVarsCacheLoadFilter);
  lFilter.HasUnitFilter := True;
  lFilter.UnitFilter := '*Filtered*';
  lFilter.HasNameFilter := True;
  lFilter.NameFilter := 'Alpha';
  lFilter.ReadsOnly := True;

  Assert.IsTrue(TryLoadCachedSymbols(lCacheFileName, lProjectPath, 'filtered-identity',
    lFilter, lLoadedSymbols, lLoadedAmbiguities, lSummary));
  try
    Assert.AreEqual<Integer>(3, lSummary.Total);
    Assert.AreEqual<Integer>(1, lSummary.Used);
    Assert.AreEqual<Integer>(2, lSummary.Unused);
    Assert.AreEqual<Integer>(2, lSummary.Ambiguities);
    Assert.AreEqual<Integer>(1, lLoadedSymbols.Count);
    Assert.AreEqual('GAlpha', lLoadedSymbols[0].Name);
    Assert.AreEqual<Integer>(2, lLoadedSymbols[0].UsedBy.Count);
    Assert.AreEqual('ReadAlpha', lLoadedSymbols[0].UsedBy[0].RoutineName);
    Assert.AreEqual<Integer>(Integer(akRead), Integer(lLoadedSymbols[0].UsedBy[0].Access));
    Assert.AreEqual('ReadWriteAlpha', lLoadedSymbols[0].UsedBy[1].RoutineName);
    Assert.AreEqual<Integer>(Integer(akReadWrite), Integer(lLoadedSymbols[0].UsedBy[1].Access));
    Assert.AreEqual<Integer>(1, lLoadedAmbiguities.Count);
    Assert.AreEqual('GAlpha', lLoadedAmbiguities[0].Name);
    Assert.AreEqual<Integer>(Integer(akRead), Integer(lLoadedAmbiguities[0].Access));
  finally
    lLoadedAmbiguities.Free;
    lLoadedSymbols.Free;
  end;

  lFilter := Default(TGlobalVarsCacheLoadFilter);
  lFilter.UnusedOnly := True;
  Assert.IsTrue(TryLoadCachedSymbols(lCacheFileName, lProjectPath, 'filtered-identity',
    lFilter, lLoadedSymbols, lLoadedAmbiguities, lSummary));
  try
    Assert.AreEqual<Integer>(2, lLoadedSymbols.Count);
    Assert.AreEqual('GBeta', lLoadedSymbols[0].Name);
    Assert.AreEqual<Integer>(0, lLoadedSymbols[0].UsedBy.Count);
    Assert.AreEqual('GPercent_Value', lLoadedSymbols[1].Name);
    Assert.AreEqual<Integer>(0, lLoadedSymbols[1].UsedBy.Count);
    Assert.AreEqual<Integer>(0, lLoadedAmbiguities.Count);
    Assert.AreEqual<Integer>(3, lSummary.Total);
    Assert.AreEqual<Integer>(2, lSummary.Unused);
  finally
    lLoadedAmbiguities.Free;
    lLoadedSymbols.Free;
  end;

  lFilter := Default(TGlobalVarsCacheLoadFilter);
  lFilter.WritesOnly := True;
  Assert.IsTrue(TryLoadCachedSymbols(lCacheFileName, lProjectPath, 'filtered-identity',
    lFilter, lLoadedSymbols, lLoadedAmbiguities, lSummary));
  try
    Assert.AreEqual<Integer>(1, lLoadedSymbols.Count);
    Assert.AreEqual('GAlpha', lLoadedSymbols[0].Name);
    Assert.AreEqual<Integer>(2, lLoadedSymbols[0].UsedBy.Count);
    Assert.AreEqual('WriteAlpha', lLoadedSymbols[0].UsedBy[0].RoutineName);
    Assert.AreEqual<Integer>(Integer(akWrite), Integer(lLoadedSymbols[0].UsedBy[0].Access));
    Assert.AreEqual('ReadWriteAlpha', lLoadedSymbols[0].UsedBy[1].RoutineName);
    Assert.AreEqual<Integer>(Integer(akReadWrite), Integer(lLoadedSymbols[0].UsedBy[1].Access));
    Assert.AreEqual<Integer>(1, lLoadedAmbiguities.Count);
    Assert.AreEqual('GBeta', lLoadedAmbiguities[0].Name);
    Assert.AreEqual<Integer>(Integer(akWrite), Integer(lLoadedAmbiguities[0].Access));
    Assert.AreEqual<Integer>(3, lSummary.Total);
    Assert.AreEqual<Integer>(1, lSummary.Used);
  finally
    lLoadedAmbiguities.Free;
    lLoadedSymbols.Free;
  end;

  lFilter := Default(TGlobalVarsCacheLoadFilter);
  lFilter.HasUnitFilter := True;
  lFilter.UnitFilter := 'Percent_Unit';
  lFilter.HasNameFilter := True;
  lFilter.NameFilter := 'Percent_Value';
  Assert.IsTrue(TryLoadCachedSymbols(lCacheFileName, lProjectPath, 'filtered-identity',
    lFilter, lLoadedSymbols, lLoadedAmbiguities, lSummary));
  try
    Assert.AreEqual<Integer>(1, lLoadedSymbols.Count);
    Assert.AreEqual('Escaped.Percent_Unit', lLoadedSymbols[0].UnitName);
    Assert.AreEqual('GPercent_Value', lLoadedSymbols[0].Name);
    Assert.AreEqual<Integer>(0, lLoadedAmbiguities.Count);
  finally
    lLoadedAmbiguities.Free;
    lLoadedSymbols.Free;
  end;
end;

procedure TGlobalVarsTests.RunGlobalVarsCommandFiltersCacheHitProjection;
var
  lCacheFileName: string;
  lConnection: TFDConnection;
  lContent: string;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lFirstFilteredContent: string;
  lJson: TJSONObject;
  lOptions: TAppOptions;
  lOutputFileName: string;
  lProjectDakRoot: string;
  lSymbols: TJSONArray;
begin
  lOutputFileName := TPath.Combine(TPath.GetTempPath, 'global-vars-fixture-cache-filter.json');
  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := FixtureProjectPath;
  lOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
  lOptions.fGlobalVarsOutputPath := lOutputFileName;
  lOptions.fHasGlobalVarsOutputPath := True;

  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  lProjectDakRoot := TPath.Combine(DakRoot, 'GlobalVarsFixture');
  lCacheFileName := TPath.Combine(lProjectDakRoot, 'global-vars\cache\global-vars-cache.sqlite3');
  Assert.IsTrue(TFile.Exists(lCacheFileName));

  lOptions.fGlobalVarsUnitFilter := '*Globals*';
  lOptions.fHasGlobalVarsUnitFilter := True;
  lOptions.fGlobalVarsNameFilter := 'Typed';
  lOptions.fHasGlobalVarsNameFilter := True;
  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  lFirstFilteredContent := ReadUtf8TextFile(lOutputFileName);
  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));
  Assert.AreEqual(lFirstFilteredContent, ReadUtf8TextFile(lOutputFileName),
    'Fresh analysis and cache-hit filtered global-vars output should match.');

  OpenSqliteCache(lCacheFileName, lDriverLink, lConnection);
  try
    lConnection.ExecSQL('update symbols set line_no = ? where name = ?',
      ['not-an-integer', 'GCounter']);
    lConnection.ExecSQL('update symbols set name = ? where name = ?',
      ['GCachedTypedValue', 'GTypedValue']);
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;

  lOptions.fGlobalVarsNameFilter := 'CachedTyped';
  Assert.AreEqual(0, RunGlobalVarsCommand(lOptions));

  lContent := ReadUtf8TextFile(lOutputFileName);
  lJson := ParseJsonObject(lContent);
  try
    Assert.AreEqual<Integer>(6, lJson.GetValue<TJSONObject>('summary').GetValue<Integer>('total'));
    Assert.AreEqual<Integer>(1, lJson.GetValue<TJSONObject>('summary').GetValue<Integer>('emitted'));
    Assert.AreEqual<Integer>(0, lJson.GetValue<TJSONObject>('summary').GetValue<Integer>(
      'emittedAmbiguities'));
    lSymbols := lJson.GetValue<TJSONArray>('symbols');
    Assert.AreEqual<Integer>(1, lSymbols.Count);
    Assert.AreEqual('GCachedTypedValue',
      (lSymbols.Items[0] as TJSONObject).GetValue<string>('name'));
  finally
    lJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TGlobalVarsTests);

end.
