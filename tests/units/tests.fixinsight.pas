unit Tests.FixInsight;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  Tests.Support;

type
  [TestFixture]
  TFixInsightTests = class
  private
    procedure RunFixInsightOutputs(const aSuffix, aMasks, aIds: string;
      out aTxt, aXml, aCsv: string);
    procedure RunOne(const aFmt, aOutFile, aMasks, aIds: string);
    procedure ExtractIdsAndFile(const aText: string; out aId1, aId2, aFileName: string);
  public
    [Test]
    procedure FixInsightFiltering;
  end;

implementation

procedure TFixInsightTests.RunOne(const aFmt, aOutFile, aMasks, aIds: string);
var
  lArgs: string;
  lExit: Cardinal;
  lLog: string;
begin
  lArgs := '--dproj ' + QuoteArg(TPath.Combine(RepoRoot, 'projects\\DelphiConfigResolver.dproj')) +
    ' --platform Win32 --config Release --delphi 23.0 --run-fixinsight --output ' + QuoteArg(aOutFile);

  if SameText(aFmt, 'xml') then
    lArgs := lArgs + ' --xml true'
  else if SameText(aFmt, 'csv') then
    lArgs := lArgs + ' --csv true';

  if aMasks <> '' then
    lArgs := lArgs + ' --exclude-path-masks ' + QuoteArg(aMasks);
  if aIds <> '' then
    lArgs := lArgs + ' --ignore-warning-ids ' + QuoteArg(aIds);

  lLog := TPath.ChangeExtension(aOutFile, '.' + aFmt + '.log');
  if not RunProcess(ResolverExePath, lArgs, RepoRoot, lLog, lExit) then
    Assert.Fail('Failed to start FixInsight run: ' + lLog);
  if lExit <> 0 then
    Assert.Fail('FixInsight run failed, exit=' + lExit.ToString + '. See: ' + lLog);
  Assert.IsTrue(FileExists(aOutFile), 'Missing FixInsight output: ' + aOutFile);
end;

procedure TFixInsightTests.RunFixInsightOutputs(const aSuffix, aMasks, aIds: string;
  out aTxt, aXml, aCsv: string);
var
  lBase: string;
begin
  lBase := TPath.Combine(TempRoot, 'fixinsight-' + aSuffix);
  aTxt := lBase + '.txt';
  aXml := lBase + '.xml';
  aCsv := lBase + '.csv';

  RunOne('txt', aTxt, aMasks, aIds);
  RunOne('xml', aXml, aMasks, aIds);
  RunOne('csv', aCsv, aMasks, aIds);
end;

procedure TFixInsightTests.ExtractIdsAndFile(const aText: string; out aId1, aId2, aFileName: string);
var
  lLines: TStringList;
  lLine: string;
  lMatch: TMatch;
  lFilePath: string;
  lId: string;
  function IsNewId(const aValue: string): Boolean;
  begin
    Result := (aValue <> '') and (not SameText(aValue, aId1)) and (not SameText(aValue, aId2));
  end;
begin
  aId1 := '';
  aId2 := '';
  aFileName := '';
  lFilePath := '';
  lLines := TStringList.Create;
  try
    lLines.Text := aText;
    for lLine in lLines do
    begin
      if StartsText('File:', lLine) and (lFilePath = '') then
      begin
        lFilePath := Trim(Copy(lLine, Length('File:') + 1, MaxInt));
        if lFilePath <> '' then
          aFileName := TPath.GetFileName(lFilePath);
      end;

      lMatch := TRegEx.Match(lLine, '^\s*([A-Z]\d{3})\b');
      if lMatch.Success then
      begin
        lId := lMatch.Groups[1].Value;
        if (aId1 = '') then
          aId1 := lId
        else if (aId2 = '') and IsNewId(lId) then
          aId2 := lId;
      end;
    end;
  finally
    lLines.Free;
  end;

  if (aId1 <> '') and (aId2 = '') then
    aId2 := aId1;
end;

procedure TFixInsightTests.FixInsightFiltering;
var
  lFixInsightExe: string;
  lBaseTxt, lBaseXml, lBaseCsv: string;
  lExclTxt, lExclXml, lExclCsv: string;
  lIdsTxt, lIdsXml, lIdsCsv: string;
  lText: string;
  lId1, lId2, lFileName: string;
  lMask: string;
  lIds: string;
begin
  EnsureResolverBuilt;
  RequireFixInsightOrSkip(lFixInsightExe);

  RunFixInsightOutputs('base', '', '', lBaseTxt, lBaseXml, lBaseCsv);
  lText := TFile.ReadAllText(lBaseTxt);
  ExtractIdsAndFile(lText, lId1, lId2, lFileName);

  Assert.IsTrue(lId1 <> '', 'No FixInsight warning IDs found in baseline output.');
  Assert.IsTrue(lFileName <> '', 'No FixInsight file entries found in baseline output.');

  lMask := '*' + lFileName;
  RunFixInsightOutputs('exclude', lMask, '', lExclTxt, lExclXml, lExclCsv);

  Assert.IsFalse(ContainsText(TFile.ReadAllText(lExclTxt), lFileName), 'Exclude mask did not filter text output.');
  Assert.IsFalse(ContainsText(TFile.ReadAllText(lExclXml), lFileName), 'Exclude mask did not filter XML output.');
  Assert.IsFalse(ContainsText(TFile.ReadAllText(lExclCsv), lFileName), 'Exclude mask did not filter CSV output.');

  lIds := lId1 + ';' + lId2;
  RunFixInsightOutputs('ignore-ids', '', lIds, lIdsTxt, lIdsXml, lIdsCsv);

  Assert.IsFalse(ContainsText(TFile.ReadAllText(lIdsTxt), lId1), 'Warning IDs not filtered from text output.');
  Assert.IsFalse(ContainsText(TFile.ReadAllText(lIdsTxt), lId2), 'Warning IDs not filtered from text output.');
  Assert.IsFalse(ContainsText(TFile.ReadAllText(lIdsXml), lId1), 'Warning IDs not filtered from XML output.');
  Assert.IsFalse(ContainsText(TFile.ReadAllText(lIdsXml), lId2), 'Warning IDs not filtered from XML output.');
  Assert.IsFalse(ContainsText(TFile.ReadAllText(lIdsCsv), ',' + lId1 + ','), 'Warning IDs not filtered from CSV output.');
  Assert.IsFalse(ContainsText(TFile.ReadAllText(lIdsCsv), ',' + lId2 + ','), 'Warning IDs not filtered from CSV output.');
end;

initialization
  TDUnitX.RegisterTestFixture(TFixInsightTests);

end.
