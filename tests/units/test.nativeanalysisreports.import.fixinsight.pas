unit Test.NativeAnalysisReports.Import.FixInsight;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFixInsightImportTests = class
  private
    fRoot: string;
    fReport: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MissingFileReturnsOwnedEmptyArray;
    [TestCase('Empty', 'false')]
    [TestCase('BOM only', 'true')]
    procedure EmptyReportReturnsOwnedEmptyArray(aBom: Boolean);
    [Test]
    procedure RetainsOrderDuplicatesFileSpellingAndGreedyMessage;
    [Test]
    procedure IgnoresMalformedLinesAndRequiresExactFileAnchor;
    [Test]
    procedure AcceptsEmptyFileAndEmptyMessage;
    [Test]
    procedure ReadsBomUnicodeAndPythonLineSeparators;
    [Test]
    procedure ReplacesMalformedUtf8WithoutDiscardingFinding;
    [TestCase('Overlong2', 'C080,FFFD FFFD')]
    [TestCase('Overlong3', 'E08080,FFFD FFFD FFFD')]
    [TestCase('Overlong4', 'F0808080,FFFD FFFD FFFD FFFD')]
    [TestCase('Truncated2', 'C2,FFFD')]
    [TestCase('Truncated3First', 'E2,FFFD')]
    [TestCase('Truncated3Second', 'E282,FFFD')]
    [TestCase('Truncated4First', 'F0,FFFD')]
    [TestCase('Truncated4Second', 'F09F,FFFD')]
    [TestCase('Truncated4Third', 'F09F92,FFFD')]
    [TestCase('EncodedHighSurrogate', 'EDA080,FFFD FFFD FFFD')]
    [TestCase('EncodedLowSurrogate', 'EDBFBF,FFFD FFFD FFFD')]
    [TestCase('OutOfRange', 'F4908080,FFFD FFFD FFFD FFFD')]
    [TestCase('IsolatedContinuations', '809FBF,FFFD FFFD FFFD')]
    [TestCase('InterruptedSequence', 'E228A1,FFFD 0028 FFFD')]
    [TestCase('ValidNonBmpLower', 'F0908080,D800 DC00')]
    [TestCase('ValidNonBmpUpper', 'F48FBFBF,DBFF DFFF')]
    [TestCase('ValidSequencesAfterInvalidByte', 'FFC2A2E0A080E282ACED9FBFF0908080F48FBFBF,FFFD 00A2 0800 20AC D7FF D800 DC00 DBFF DFFF')]
    procedure Utf8ReplacementMatchesPinnedPython(const aHex, aExpectedUnits: string);
    [Test]
    procedure PreservesArbitraryDecimalLocations;
    [Test]
    procedure DirectoryInputRaisesReadError;
  end;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  Dak.Analysis.FixInsightImport,
  Test.Support;

procedure TFixInsightImportTests.Setup;
begin
  fRoot := UniqueTempPath('fi-text-import');
  TDirectory.CreateDirectory(fRoot);
  fReport := TPath.Combine(fRoot, 'fixinsight.txt');
end;

procedure TFixInsightImportTests.TearDown;
begin
  DeleteTempPath(fRoot);
end;

procedure TFixInsightImportTests.MissingFileReturnsOwnedEmptyArray;
var
  lRows: TJSONArray;
begin
  lRows := LoadFixInsightFindings(fReport);
  try
    Assert.AreEqual<Integer>(0, lRows.Count);
  finally
    lRows.Free;
  end;
end;

procedure TFixInsightImportTests.EmptyReportReturnsOwnedEmptyArray(aBom: Boolean);
var
  lRows: TJSONArray;
begin
  if aBom then
    TFile.WriteAllBytes(fReport, [$EF, $BB, $BF])
  else
    TFile.WriteAllBytes(fReport, nil);
  lRows := LoadFixInsightFindings(fReport);
  try
    Assert.AreEqual(0, lRows.Count);
  finally
    lRows.Free;
  end;
end;

procedure TFixInsightImportTests.RetainsOrderDuplicatesFileSpellingAndGreedyMessage;
var
  lRows: TJSONArray;
  lRow: TJSONObject;
begin
  TFile.WriteAllText(fReport, 'W123 before anchor (1, 2)' + #13#10 +
    'File:  ..\MiXeD\One.pas  ' + #13#10 +
    '  C101 Method Bar (66 lines) (4, 5) suffix (484, 1)' + #13#10 +
    '  C101 Method Bar (66 lines) (4, 5) suffix (484, 1)' + #13#10 +
    'File: Two.pas' + #10 + 'O222 optimize (0, 0002)', TEncoding.UTF8);
  lRows := LoadFixInsightFindings(fReport);
  try
    Assert.AreEqual<Integer>(3, lRows.Count);
    lRow := lRows.Items[0] as TJSONObject;
    Assert.AreEqual<Integer>(6, lRow.Count);
    Assert.AreEqual('C101', lRow.GetValue<string>('code'));
    Assert.AreEqual('..\MiXeD\One.pas', lRow.GetValue<string>('file'));
    Assert.AreEqual('484', lRow.Values['line'].Value);
    Assert.AreEqual('1', lRow.Values['col'].Value);
    Assert.AreEqual('Method Bar (66 lines) (4, 5) suffix', lRow.GetValue<string>('message'));
    Assert.AreEqual('C', lRow.GetValue<string>('kind'));
    Assert.AreEqual(lRows.Items[0].ToJSON, lRows.Items[1].ToJSON);
    Assert.AreEqual('Two.pas', lRows.Items[2].GetValue<string>('file'));
    Assert.AreEqual('0', (lRows.Items[2] as TJSONObject).Values['line'].Value);
    Assert.AreEqual('2', (lRows.Items[2] as TJSONObject).Values['col'].Value);
  finally
    lRows.Free;
  end;
end;

procedure TFixInsightImportTests.IgnoresMalformedLinesAndRequiresExactFileAnchor;
var
  lRows: TJSONArray;
begin
  TFile.WriteAllText(fReport, ' File: Wrong.pas' + #10 + 'W100 ignored (1, 1)' + #10 +
    'file: Wrong.pas' + #10 + 'W100 ignored (1, 1)' + #10 + 'File: Right.pas' + #10 +
    'w100 lowercase (1, 1)' + #10 + 'WW100 two letters (1, 1)' + #10 +
    'W1000 extra digit (1, 1)' + #10 + 'W100 no location' + #10 +
    'W100 negative (-1, 1)' + #10 + 'W100 signed (1, +1)' + #10 +
    'W100 tail (1, 1) junk' + #10 + 'W100 kept (2, 3)', TEncoding.UTF8);
  lRows := LoadFixInsightFindings(fReport);
  try
    Assert.AreEqual<Integer>(1, lRows.Count);
    Assert.AreEqual('Right.pas', lRows.Items[0].GetValue<string>('file'));
    Assert.AreEqual('kept', lRows.Items[0].GetValue<string>('message'));
  finally
    lRows.Free;
  end;
end;

procedure TFixInsightImportTests.AcceptsEmptyFileAndEmptyMessage;
var
  lRows: TJSONArray;
begin
  TFile.WriteAllText(fReport, 'File: ' + #10 + 'W100  (1, 2)', TEncoding.UTF8);
  lRows := LoadFixInsightFindings(fReport);
  try
    Assert.AreEqual<Integer>(1, lRows.Count);
    Assert.AreEqual('', lRows.Items[0].GetValue<string>('file'));
    Assert.AreEqual('', lRows.Items[0].GetValue<string>('message'));
  finally
    lRows.Free;
  end;
end;

procedure TFixInsightImportTests.ReadsBomUnicodeAndPythonLineSeparators;
var
  lRows: TJSONArray;
  lText: string;
begin
  lText := #$FEFF + 'File: ' + #$17B + 'olw.pas' + #$2028 +
    #$A0 + 'W' + #$661#$662#$663 + #$A0 + 'message ' + #$17C + ' (' + #$661#$662 + ', ' + #$663 + ')' + #$85 +
    'File: Other.pas' + #11 + 'C101 next (3, 4)' + #30;
  TFile.WriteAllBytes(fReport, TEncoding.UTF8.GetBytes(lText));
  lRows := LoadFixInsightFindings(fReport);
  try
    Assert.AreEqual<Integer>(2, lRows.Count);
    Assert.AreEqual(#$17B + 'olw.pas', lRows.Items[0].GetValue<string>('file'));
    Assert.AreEqual('W' + #$661#$662#$663, lRows.Items[0].GetValue<string>('code'));
    Assert.AreEqual('12', (lRows.Items[0] as TJSONObject).Values['line'].Value);
    Assert.AreEqual('3', (lRows.Items[0] as TJSONObject).Values['col'].Value);
    Assert.AreEqual('message ' + #$17C, lRows.Items[0].GetValue<string>('message'));
    Assert.AreEqual('Other.pas', lRows.Items[1].GetValue<string>('file'));
  finally
    lRows.Free;
  end;
end;

procedure TFixInsightImportTests.ReplacesMalformedUtf8WithoutDiscardingFinding;
var
  lBytes: TBytes;
  lRows: TJSONArray;
  i: Integer;
begin
  lBytes := TEncoding.UTF8.GetBytes('File: Bad.pas' + #10 + 'W100 bad?message (1, 2)');
  for i := 0 to High(lBytes) do
    if lBytes[i] = Ord('?') then
      lBytes[i] := $FF;
  TFile.WriteAllBytes(fReport, lBytes);
  lRows := LoadFixInsightFindings(fReport);
  try
    Assert.AreEqual<Integer>(1, lRows.Count);
    Assert.AreEqual('bad' + #$FFFD + 'message', lRows.Items[0].GetValue<string>('message'));
  finally
    lRows.Free;
  end;
end;

procedure TFixInsightImportTests.Utf8ReplacementMatchesPinnedPython(const aHex, aExpectedUnits: string);
const
  cPrefix = 'File: ..\MiXeD\Utf8.pas' + #13#10 + 'W123 pre<';
  cSuffix = '>post (7, 11)' + #13#10;
var
  lBytes: TBytes;
  lExpected: string;
  lRow: TJSONObject;
  lRows: TJSONArray;
  lUnit: string;
  i: Integer;
begin
  // Expectations come from pinned Python; Windows replacement grouping differs for five cases.
  lBytes := TEncoding.ASCII.GetBytes(cPrefix + StringOfChar('?', Length(aHex) div 2) + cSuffix);
  for i := 0 to (Length(aHex) div 2) - 1 do
    lBytes[Length(cPrefix) + i] := Byte(StrToInt('$' + Copy(aHex, i * 2 + 1, 2)));
  lExpected := '';
  for lUnit in aExpectedUnits.Split([' ']) do
    lExpected := lExpected + Char(StrToInt('$' + lUnit));
  TFile.WriteAllBytes(fReport, lBytes);
  lRows := LoadFixInsightFindings(fReport);
  try
    Assert.AreEqual<Integer>(1, lRows.Count, aHex);
    lRow := lRows.Items[0] as TJSONObject;
    Assert.AreEqual<Integer>(6, lRow.Count, aHex);
    Assert.AreEqual('W123', lRow.GetValue<string>('code'), aHex);
    Assert.AreEqual('..\MiXeD\Utf8.pas', lRow.GetValue<string>('file'), aHex);
    Assert.AreEqual('7', lRow.Values['line'].Value, aHex);
    Assert.AreEqual('11', lRow.Values['col'].Value, aHex);
    Assert.AreEqual('W', lRow.GetValue<string>('kind'), aHex);
    Assert.AreEqual('pre<' + lExpected + '>post', lRow.GetValue<string>('message'), aHex);
  finally
    lRows.Free;
  end;
end;
procedure TFixInsightImportTests.PreservesArbitraryDecimalLocations;
var
  lHuge: string;
  lRows: TJSONArray;
  lRow: TJSONObject;
begin
  lHuge := StringOfChar('9', 400);
  TFile.WriteAllText(fReport, 'File: Big.pas' + #10 +
    'W100 large (000' + lHuge + ', 18446744073709551616)', TEncoding.UTF8);
  lRows := LoadFixInsightFindings(fReport);
  try
    Assert.AreEqual<Integer>(1, lRows.Count);
    lRow := lRows.Items[0] as TJSONObject;
    Assert.IsTrue(lRow.Values['line'] is TJSONNumber);
    Assert.AreEqual(lHuge, lRow.Values['line'].Value);
    Assert.AreEqual('18446744073709551616', lRow.Values['col'].Value);
    Assert.IsTrue(Pos('"line":' + lHuge, lRow.ToJSON) > 0, lRow.ToJSON);
  finally
    lRows.Free;
  end;
end;

procedure TFixInsightImportTests.DirectoryInputRaisesReadError;
var
  lRaised: Boolean;
  lRows: TJSONArray;
begin
  lRaised := False;
  lRows := nil;
  try
    try
      lRows := LoadFixInsightFindings(fRoot);
    except
      on EFileNotFoundException do
        lRaised := True;
    end;
    Assert.IsTrue(lRaised, 'Existing directory must fail reading, not masquerade as a missing file.');
  finally
    lRows.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFixInsightImportTests);

end.
