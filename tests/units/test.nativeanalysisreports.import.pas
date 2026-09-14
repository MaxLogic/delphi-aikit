unit Test.NativeAnalysisReports.Import;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TNativeAnalysisJsonLinesTests = class
  public
    [Test]
    procedure CompleteValuesAndDuplicateRowsRemainOrdered;
    [Test]
    procedure DuplicateKeysUseLastValueAndFirstPosition;
    [Test]
    procedure EmptyKeysRetainTheirOwnedNestedValues;
    [Test]
    procedure UnicodeWhitespaceDoesNotSplitStringValues;
    [TestCase('Trailing text', '{"a":1} trailing')]
    [TestCase('Incomplete object', '{"a":')]
    [TestCase('Trailing comma', '{"a":1,}', '|')]
    [TestCase('Raw tab', '{"a":"raw'#9'text"}')]
    [TestCase('Raw NUL', '{"a":"raw'#0'text"}')]
    [TestCase('Missing mantissa', '{"a":-e1}')]
    procedure MalformedInputReportsPhysicalLine(const aMalformed: string);
    [Test]
    procedure BomAndInvalidUtf8AreNotSilentlyAccepted;
    [Test]
    procedure EmptyFileHasNoRows;
    [TestCase('NaN', 'NaN')]
    [TestCase('Positive infinity', 'Infinity')]
    [TestCase('Negative infinity', '-Infinity')]
    procedure RejectsNonfiniteExtensionWithoutChangingEvidence(const aLiteral: string);
    [Test]
    procedure QuotedConstantsAndHugeDecimalRemainData;
  end;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.Analysis.Findings,
  Test.Support;

procedure TNativeAnalysisJsonLinesTests.CompleteValuesAndDuplicateRowsRemainOrdered;
const
  cRow = '{"tool":"PAL","extension":{"array":[1,true,null,"quoted\\value"],"n":123456789012345678901234567890}}';
var
  g: TGarbos;
  lBefore: TBytes;
  lPath: string;
  lRoot: string;
  lRows: TJSONArray;
begin
  lRoot := UniqueTempPath('jsonl-complete');
  TDirectory.CreateDirectory(lRoot);
  try
    lPath := TPath.Combine(lRoot, 'findings.jsonl');
    TFile.WriteAllText(lPath, cRow + #13#10 + cRow + #10 + '[null,false]' + #10 + '"scalar"', TEncoding.ASCII);
    lBefore := TFile.ReadAllBytes(lPath);
    GC(lRows, LoadAnalysisJsonLines(lPath), g);
    Assert.AreEqual(4, lRows.Count);
    Assert.AreEqual(cRow, lRows[0].ToJSON);
    Assert.AreEqual(cRow, lRows[1].ToJSON);
    Assert.IsFalse(lRows[0] = lRows[1], 'Duplicate rows must have independent ownership');
    Assert.AreEqual('[null,false]', lRows[2].ToJSON);
    Assert.AreEqual('"scalar"', lRows[3].ToJSON);
    Assert.AreEqual(TEncoding.ASCII.GetString(lBefore), TFile.ReadAllText(lPath, TEncoding.ASCII));
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisJsonLinesTests.DuplicateKeysUseLastValueAndFirstPosition;
var
  g: TGarbos;
  lPath: string;
  lRoot: string;
  lRows: TJSONArray;
begin
  lRoot := UniqueTempPath('jsonl-keys');
  TDirectory.CreateDirectory(lRoot);
  try
    lPath := TPath.Combine(lRoot, 'findings.jsonl');
    TFile.WriteAllText(lPath, '{"a":0,"b":[{"x":1,"x":2}],"a":3,"A":4}', TEncoding.ASCII);
    GC(lRows, LoadAnalysisJsonLines(lPath), g);
    Assert.AreEqual('{"a":3,"b":[{"x":2}],"A":4}', lRows[0].ToJSON);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisJsonLinesTests.UnicodeWhitespaceDoesNotSplitStringValues;
var
  g: TGarbos;
  lPath: string;
  lRoot: string;
  lRows: TJSONArray;
  lText: string;
begin
  lRoot := UniqueTempPath('jsonl-whitespace');
  TDirectory.CreateDirectory(lRoot);
  try
    lPath := TPath.Combine(lRoot, 'findings.jsonl');
    lText := #$00A0 + '{"value":"' + #$017C + #$2028 + #$6F22 + '"}' + #$001C + #13 + 'false';
    TFile.WriteAllBytes(lPath, TEncoding.UTF8.GetBytes(lText));
    GC(lRows, LoadAnalysisJsonLines(lPath), g);
    Assert.AreEqual(2, lRows.Count);
    Assert.AreEqual(string(#$017C + #$2028 + #$6F22), lRows[0].GetValue<string>('value'));
    Assert.AreEqual('false', lRows[1].ToJSON);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisJsonLinesTests.EmptyKeysRetainTheirOwnedNestedValues;
var
  g: TGarbos;
  lPath: string;
  lRoot: string;
  lRows: TJSONArray;
begin
  lRoot := UniqueTempPath('jsonl-empty-keys');
  TDirectory.CreateDirectory(lRoot);
  try
    lPath := TPath.Combine(lRoot, 'findings.jsonl');
    TFile.WriteAllText(lPath, '{"":0,"a":3,"":{"x":2}}', TEncoding.ASCII);
    GC(lRows, LoadAnalysisJsonLines(lPath), g);
    Assert.AreEqual('{"":{"x":2},"a":3}', lRows[0].ToJSON);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisJsonLinesTests.MalformedInputReportsPhysicalLine(const aMalformed: string);
var
  lPath: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('jsonl-malformed');
  TDirectory.CreateDirectory(lRoot);
  try
    lPath := TPath.Combine(lRoot, 'findings.jsonl');
    TFile.WriteAllText(lPath, '{}'#13#10#13' '#10 + aMalformed, TEncoding.ASCII);
    try
      LoadAnalysisJsonLines(lPath).Free;
      Assert.Fail('Malformed line must fail');
    except
      on e: EConvertError do
      begin
        Assert.IsTrue(e.Message.Contains(lPath), e.Message);
        Assert.IsTrue(e.Message.Contains('line 4'), e.Message);
      end;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisJsonLinesTests.BomAndInvalidUtf8AreNotSilentlyAccepted;
var
  lPath: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('jsonl-invalid-encoding');
  TDirectory.CreateDirectory(lRoot);
  try
    lPath := TPath.Combine(lRoot, 'findings.jsonl');
    TFile.WriteAllBytes(lPath, [$EF, $BB, $BF, $7B, $7D]);
    Assert.WillRaise(procedure begin LoadAnalysisJsonLines(lPath).Free; end, EConvertError);
    TFile.WriteAllBytes(lPath, [$7B, $22, $78, $22, $3A, $22, $FF, $22, $7D]);
    Assert.WillRaise(procedure begin LoadAnalysisJsonLines(lPath).Free; end, EConvertError);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisJsonLinesTests.EmptyFileHasNoRows;
var
  g: TGarbos;
  lPath: string;
  lRoot: string;
  lRows: TJSONArray;
begin
  lRoot := UniqueTempPath('jsonl-empty');
  TDirectory.CreateDirectory(lRoot);
  try
    lPath := TPath.Combine(lRoot, 'findings.jsonl');
    TFile.WriteAllText(lPath, '', TEncoding.ASCII);
    GC(lRows, LoadAnalysisJsonLines(lPath), g);
    Assert.AreEqual(0, lRows.Count);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisJsonLinesTests.RejectsNonfiniteExtensionWithoutChangingEvidence(const aLiteral: string);
var
  lPath: string;
  lRoot: string;
  lText: string;
begin
  lRoot := UniqueTempPath('jsonl-nonfinite');
  TDirectory.CreateDirectory(lRoot);
  try
    lPath := TPath.Combine(lRoot, 'findings.jsonl');
    lText := '{}'#13#10#13#10'{"extension":{"value":' + aLiteral + '}}';
    TFile.WriteAllText(lPath, lText, TEncoding.ASCII);
    try
      LoadAnalysisJsonLines(lPath).Free;
      Assert.Fail('T-336: invalid numeric literal must reject the report');
    except
      on e: EConvertError do
      begin
        Assert.IsTrue(e.Message.Contains(lPath), e.Message);
        Assert.IsTrue(e.Message.Contains('line 3'), e.Message);
      end;
    end;
    Assert.AreEqual(lText, TFile.ReadAllText(lPath, TEncoding.ASCII));
    Assert.AreEqual<NativeInt>(1, Length(TDirectory.GetFiles(lRoot)), 'No output may replace rejected evidence');
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisJsonLinesTests.QuotedConstantsAndHugeDecimalRemainData;
var
  g: TGarbos;
  lPath: string;
  lRoot: string;
  lRows: TJSONArray;
  lText: string;
begin
  lRoot := UniqueTempPath('jsonl-nonfinite-controls');
  TDirectory.CreateDirectory(lRoot);
  try
    lPath := TPath.Combine(lRoot, 'findings.jsonl');
    lText := '{"words":["NaN","Infinity","-Infinity"],"integer":' + StringOfChar('9', 400) + '}';
    TFile.WriteAllText(lPath, lText, TEncoding.ASCII);
    GC(lRows, LoadAnalysisJsonLines(lPath), g);
    Assert.AreEqual(1, lRows.Count);
    Assert.AreEqual(lText, lRows[0].ToJSON);
  finally
    DeleteTempPath(lRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisJsonLinesTests);
end.
