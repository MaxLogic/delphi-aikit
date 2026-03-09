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
    [Test] procedure RunGlobalVarsJsonOutputSupportsUnusedOnlyFilter;
    [Test] procedure RunGlobalVarsJsonOutputSupportsUnitAndNameFilter;
    [Test] procedure RunGlobalVarsJsonOutputSupportsAccessFilters;
    [Test] procedure RunGlobalVarsTextOutputCreatesProjectCache;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.SysUtils,
  Dak.GlobalVars,
  Dak.Types;

function TGlobalVarsTests.FixtureProjectPath: string;
begin
  Result := TPath.GetFullPath(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\fixtures\GlobalVarsFixture.dproj'));
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

  lProjectDakRoot := TPath.Combine(DakRoot, 'GlobalVarsFixture');
  lCacheFileName := TPath.Combine(lProjectDakRoot, 'global-vars\cache\global-vars-cache.sqlite3');
  Assert.IsTrue(TDirectory.Exists(lProjectDakRoot));
  Assert.IsTrue(TFile.Exists(lCacheFileName));
end;

initialization
  TDUnitX.RegisterTestFixture(TGlobalVarsTests);

end.
