unit Test.NativeAnalysisReports.Numeric;

interface

uses
  DUnitX.TestFramework;

type
  // Pinned Python 3.13.15 oracle proof for Dak.Analysis.NumericText: exact binary64 parsing,
  // repr(float) shortest digits and str(json.loads(token)) presentation.
  [TestFixture]
  [Category('Fast')]
  TNativeAnalysisNumericTests = class
  public
    [Test]
    procedure ProbeCorpusParsesAndPrintsLikePython;
    [Test]
    procedure BoundaryCorpusMatchesPythonTextAndTruthiness;
    [Test]
    procedure InvalidTokensRaiseConvertError;
    [Test]
    procedure ReprRoundTripsThroughParse;
  end;

implementation

uses
  System.Hash, System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.Analysis.NumericText,
  Test.Support;

const
  cFixtureFolder = 'tests\fixtures\native-analysis-numeric';
  cProbeRows = 10998;
  cMaxReportedMismatches = 10;

function FixturePath(const aName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(RepoRoot, cFixtureFolder), aName);
end;

function LoadFixture(const aName, aExpectedSha256: string): TJSONValue;
var
  lBytes: TBytes;
  lHash: THashSHA2;
begin
  lBytes := TFile.ReadAllBytes(FixturePath(aName));
  lHash := THashSHA2.Create;
  lHash.Update(lBytes[0], Length(lBytes));
  Assert.AreEqual(aExpectedSha256, lHash.HashAsString.ToLowerInvariant, aName + ' SHA256');
  Result := ParseJsonValue(TEncoding.ASCII.GetString(lBytes), aName);
end;

function BitsHex(aValue: Double): string;
begin
  Result := IntToHex(PUInt64(@aValue)^, 16);
end;

function FixtureSha256(const aName: string): string;
var
  g: TGarbos;
  lReceipt: TJSONObject;
begin
  GC(lReceipt, ParseJsonObject(TFile.ReadAllText(FixturePath('receipt.json'), TEncoding.ASCII), 'receipt.json'), g);
  // Direct pair lookup: the generic path accessor would split the file name at its dot.
  Result := (lReceipt.GetValue(aName) as TJSONObject).GetValue<string>('sha256');
end;

procedure TNativeAnalysisNumericTests.ProbeCorpusParsesAndPrintsLikePython;
var
  g: TGarbos;
  lRows: TJSONArray;
  lItem: TJSONValue;
  lRow: TJSONObject;
  lToken, lExpectedBits, lExpectedRepr, lActualBits, lActualRepr, lReport: string;
  lMismatches: Integer;
  lValue: Double;
begin
  GC(lRows, LoadFixture('parse-repr-corpus.json', FixtureSha256('parse-repr-corpus.json')) as TJSONArray, g);
  Assert.AreEqual(cProbeRows, lRows.Count, 'probe corpus row count');
  lMismatches := 0;
  lReport := '';
  for lItem in lRows do
  begin
    lRow := lItem as TJSONObject;
    lToken := lRow.GetValue<string>('token');
    lExpectedBits := lRow.GetValue<string>('bits');
    lExpectedRepr := lRow.GetValue<string>('repr');
    lValue := TNumericText.ParseDouble(lToken);
    lActualBits := BitsHex(lValue);
    lActualRepr := TNumericText.Repr(lValue);
    if (lActualBits <> lExpectedBits) or (lActualRepr <> lExpectedRepr) or
      (TNumericText.PythonText(lToken) <> lExpectedRepr) then
    begin
      Inc(lMismatches);
      if lMismatches <= cMaxReportedMismatches then
        lReport := lReport + Format('[%s expected %s/%s actual %s/%s] ',
          [lToken, lExpectedBits, lExpectedRepr, lActualBits, lActualRepr]);
    end;
  end;
  Assert.AreEqual(0, lMismatches, Format('%d of %d probe tokens mismatched: %s', [lMismatches, lRows.Count, lReport]));
end;

procedure TNativeAnalysisNumericTests.BoundaryCorpusMatchesPythonTextAndTruthiness;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lItem: TJSONValue;
  lRow: TJSONObject;
  lToken, lKind: string;
  lRowCount: Integer;
begin
  GC(lDocument, LoadFixture('boundary-corpus.json', FixtureSha256('boundary-corpus.json')) as TJSONObject, g);
  lRowCount := 0;
  for lItem in lDocument.GetValue<TJSONArray>('rows') do
  begin
    lRow := lItem as TJSONObject;
    lToken := lRow.GetValue<string>('token');
    lKind := lRow.GetValue<string>('kind');
    Assert.AreEqual(lKind = 'float', TNumericText.IsFloatToken(lToken), lToken + ' float classification');
    if lKind = 'float' then
      Assert.AreEqual(lRow.GetValue<string>('bits'), BitsHex(TNumericText.ParseDouble(lToken)), lToken + ' binary64 bits');
    Assert.AreEqual(lRow.GetValue<string>('text'), TNumericText.PythonText(lToken), lToken + ' Python text');
    Assert.AreEqual(not lRow.GetValue<Boolean>('truthy'), TNumericText.IsZero(lToken), lToken + ' truthiness');
    Inc(lRowCount);
  end;
  Assert.IsTrue(lRowCount >= 100, 'boundary corpus has at least 100 rows, found ' + IntToStr(lRowCount));
end;

procedure TNativeAnalysisNumericTests.InvalidTokensRaiseConvertError;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lItem: TJSONValue;
  lToken: string;
  lRaised: Boolean;
begin
  GC(lDocument, LoadFixture('boundary-corpus.json', FixtureSha256('boundary-corpus.json')) as TJSONObject, g);
  for lItem in lDocument.GetValue<TJSONArray>('invalid_tokens') do
  begin
    lToken := lItem.Value;
    lRaised := False;
    try
      TNumericText.PythonText(lToken);
    except
      on EConvertError do
        lRaised := True;
    end;
    Assert.IsTrue(lRaised, 'EConvertError expected for token [' + lToken + ']');
  end;
end;

procedure TNativeAnalysisNumericTests.ReprRoundTripsThroughParse;
const
  cSamples: array[0..7] of string = ('0.1', '1e23', '5e-324', '1.7976931348623157e308', '-2.5', '123456.789',
    '9007199254740993', '1e-7');
var
  lToken, lRepr: string;
  lValue: Double;
begin
  for lToken in cSamples do
  begin
    lValue := TNumericText.ParseDouble(lToken);
    lRepr := TNumericText.Repr(lValue);
    Assert.AreEqual(BitsHex(lValue), BitsHex(TNumericText.ParseDouble(lRepr)), lToken + ' repr must round-trip');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisNumericTests);

end.
