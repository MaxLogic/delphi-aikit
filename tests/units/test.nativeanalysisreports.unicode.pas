unit Test.NativeAnalysisReports.Unicode;

interface

uses
  DUnitX.TestFramework;

type
  // Pinned Unicode 15.1 / Python 3.13.15 oracle proof for Dak.Analysis.UnicodeText.
  // Expected values come from the retained fixture receipts, never from the candidate tables.
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisUnicodeTests = class
  public
    [Test]
    procedure ExhaustiveOracleMatchesEveryCodePoint;
    [Test]
    procedure ContextualSigmaStreamsMatchPinnedHashes;
    [Test]
    procedure TargetedRowsMatchExactCodeUnits;
    [Test]
    procedure InvalidArgumentsRaiseOrReturnFalse;
    [Test]
    procedure LongIgnorableRunsAroundSigma;
  end;

implementation

uses
  System.Classes, System.Hash, System.IOUtils, System.JSON, System.SysUtils, System.ZLib,
  AutoFree,
  Dak.Analysis.UnicodeText,
  Test.Support;

const
  cFixtureFolder = 'tests\fixtures\native-analysis-unicode';
  cCodePointCount = $110000;
  cCompressedBytes = 3922656;
  cCompressedSha256 = '180cda2655afd52fb02aa81e64b7ff59c1300e9b561f51a6f35abe5ea00bf637';
  cSingletonBytes = 12255720;
  cSingletonSha256 = '5dc6a6185068604df6d6acb48f61b7ff7c7ed3ef1ced5e011c01486e29fe8ce6';
  cRowsSha256 = '6a0bc76f5ca6c21c7c03647ac5b1bb4b54a849aa431557a94a5a5d35d72b1431';
  cContextSha256: array[0..2] of string = (
    'ff806e385534d10d3a6b924b50a30eeec8502758710a40d32f29631ea88b1adb',
    '3f8a8e9a14dc1e756d20657ec1d00f9e2a960858d4f40b2d46e32d706ceb4438',
    'b6956f97f2751b554259db76a107551e19fe22842a455c8c895cfdd517c2caea');
  cContextNames: array[0..2] of string = ('A+c+SIGMA', 'A+SIGMA+c', 'A+SIGMA+c+A');
  cOracleMagic = 'DAKU1511';
  cMaxReportedMismatches = 10;
  cSigma = #$03A3;
  cFinalSigma = #$03C2;
  cSmallSigma = #$03C3;
  cCombiningAcute = #$0301;

function Sha256Hex(const aBytes: TBytes): string;
var
  lHash: THashSHA2;
begin
  lHash := THashSHA2.Create;
  if Length(aBytes) > 0 then
    lHash.Update(aBytes[0], Length(aBytes));
  Result := lHash.HashAsString.ToLowerInvariant;
end;

function FixturePath(const aName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(RepoRoot, cFixtureFolder), aName);
end;

// UTF-16 construction independent of the helper under test.
function IndependentUtf16(aCodePoint: Cardinal): string;
begin
  if aCodePoint <= $FFFF then
    Result := Char(aCodePoint)
  else
    Result := Char($D800 + ((aCodePoint - $10000) shr 10)) + Char($DC00 + ((aCodePoint - $10000) and $3FF));
end;

function CodeUnitsText(const aText: string): string;
var
  c: Char;
begin
  Result := '';
  for c in aText do
    Result := Result + IntToHex(Ord(c), 4) + ' ';
  Result := Result.TrimRight;
end;

function LoadSingletonOracle: TBytes;
var
  g: TGarbos;
  lCompressed: TBytes;
  lInput, lOutput: TBytesStream;
begin
  lCompressed := TFile.ReadAllBytes(FixturePath('unicode-oracle-15.1.bin.zlib'));
  Assert.AreEqual(cCompressedBytes, Integer(Length(lCompressed)), 'compressed oracle byte length');
  Assert.AreEqual(cCompressedSha256, Sha256Hex(lCompressed), 'compressed oracle SHA256');
  GC(lInput, TBytesStream.Create(lCompressed), g);
  GC(lOutput, TBytesStream.Create, g);
  ZDecompressStream(lInput, lOutput);
  Result := Copy(lOutput.Bytes, 0, lOutput.Size);
  Assert.AreEqual(cSingletonBytes, Integer(Length(Result)), 'singleton oracle byte length');
  Assert.AreEqual(cSingletonSha256, Sha256Hex(Result), 'singleton oracle SHA256');
end;

type
  TOracleReader = record
    Bytes: TBytes;
    Position: Integer;
    function ReadByte: Byte;
    function ReadCardinal: Cardinal;
    procedure Require(aCount: Integer);
  end;

procedure TOracleReader.Require(aCount: Integer);
begin
  if Position + aCount > Length(Bytes) then
    raise EInvalidOpException.CreateFmt('Oracle truncated at byte %d needing %d', [Position, aCount]);
end;

function TOracleReader.ReadByte: Byte;
begin
  Require(1);
  Result := Bytes[Position];
  Inc(Position);
end;

function TOracleReader.ReadCardinal: Cardinal;
begin
  Require(4);
  Result := Cardinal(Bytes[Position]) or (Cardinal(Bytes[Position + 1]) shl 8) or
    (Cardinal(Bytes[Position + 2]) shl 16) or (Cardinal(Bytes[Position + 3]) shl 24);
  Inc(Position, 4);
end;

procedure TNativeAnalysisUnicodeTests.ExhaustiveOracleMatchesEveryCodePoint;
var
  g: TGarbos;
  i: Integer;
  lReader: TOracleReader;
  lCodePoint, lCount, lScalar: Cardinal;
  lFlags: Byte;
  lInput, lExpected, lActual: string;
  lIndex, lMismatches: Integer;
  lReport: TStringBuilder;

  procedure Mismatch(const aWhat, aExpectedText, aActualText: string);
  begin
    Inc(lMismatches);
    if lMismatches <= cMaxReportedMismatches then
      lReport.AppendFormat('U+%s %s expected [%s] actual [%s]; ',
        [IntToHex(lCodePoint, 4), aWhat, aExpectedText, aActualText]);
  end;

  function ReadMapping(aMaxCount: Cardinal): string;
  var
    k: Cardinal;
  begin
    lCount := lReader.ReadByte;
    if (lCount < 1) or (lCount > aMaxCount) then
      raise EInvalidOpException.CreateFmt('U+%s invalid mapping count %d', [IntToHex(lCodePoint, 4), lCount]);
    Result := '';
    for k := 1 to lCount do
    begin
      lScalar := lReader.ReadCardinal;
      if lScalar > $10FFFF then
        raise EInvalidOpException.CreateFmt('U+%s mapping scalar %x out of range', [IntToHex(lCodePoint, 4), lScalar]);
      Result := Result + IndependentUtf16(lScalar);
    end;
  end;

  procedure CheckFlag(aBit: Integer; aActualValue: Boolean; const aName: string);
  var
    lExpectedValue: Boolean;
  begin
    lExpectedValue := (lFlags and (1 shl aBit)) <> 0;
    if lExpectedValue <> aActualValue then
      Mismatch(aName, BoolToStr(lExpectedValue, True), BoolToStr(aActualValue, True));
  end;

begin
  GC(lReport, TStringBuilder.Create, g);
  lReader.Bytes := LoadSingletonOracle;
  lReader.Position := 0;
  lReader.Require(Length(cOracleMagic));
  for i := 1 to Length(cOracleMagic) do
    Assert.AreEqual(Integer(Ord(cOracleMagic[i])), Integer(lReader.Bytes[i - 1]), 'oracle magic byte ' + IntToStr(i));
  lReader.Position := Length(cOracleMagic);
  Assert.AreEqual(Cardinal(cCodePointCount), lReader.ReadCardinal, 'oracle record count');
  lMismatches := 0;
  for lCodePoint := 0 to cCodePointCount - 1 do
  begin
    lInput := IndependentUtf16(lCodePoint);
    lActual := TUnicodeText.FromCodePoint(lCodePoint);
    if lActual <> lInput then
      Mismatch('FromCodePoint', CodeUnitsText(lInput), CodeUnitsText(lActual));
    lIndex := 1;
    lScalar := TUnicodeText.ReadCodePoint(lInput, lIndex);
    if (lScalar <> lCodePoint) or (lIndex <> Length(lInput) + 1) then
      Mismatch('ReadCodePoint', IntToHex(lCodePoint, 4) + '/' + IntToStr(Length(lInput) + 1),
        IntToHex(lScalar, 4) + '/' + IntToStr(lIndex));
    lExpected := ReadMapping(3);
    lActual := TUnicodeText.Upper(lInput);
    if lActual <> lExpected then
      Mismatch('Upper', CodeUnitsText(lExpected), CodeUnitsText(lActual));
    lExpected := ReadMapping(2);
    lActual := TUnicodeText.Lower(lInput);
    if lActual <> lExpected then
      Mismatch('Lower', CodeUnitsText(lExpected), CodeUnitsText(lActual));
    lFlags := lReader.ReadByte;
    if (lFlags and $F0) <> 0 then
      raise EInvalidOpException.CreateFmt('U+%s reserved flag bits set: %x', [IntToHex(lCodePoint, 4), lFlags]);
    CheckFlag(0, TUnicodeText.IsWhitespace(lCodePoint), 'IsWhitespace');
    CheckFlag(1, TUnicodeText.IsPrintable(lCodePoint), 'IsPrintable');
    CheckFlag(2, TUnicodeText.IsCased(lCodePoint), 'IsCased');
    CheckFlag(3, TUnicodeText.IsCaseIgnorable(lCodePoint), 'IsCaseIgnorable');
  end;
  Assert.AreEqual(Integer(Length(lReader.Bytes)), lReader.Position, 'oracle fully consumed with no trailing bytes');
  Assert.AreEqual(0, lMismatches, Format('%d mismatches across %d code points: %s',
    [lMismatches, cCodePointCount, lReport.ToString]));
end;

procedure TNativeAnalysisUnicodeTests.ContextualSigmaStreamsMatchPinnedHashes;
var
  i: Integer;
  lCodePoint: Cardinal;
  lHashes: array[0..2] of THashSHA2;
  lInputs: array[0..2] of string;
  lOutput, lCharacter: string;
  lLength: Cardinal;
begin
  for i := 0 to 2 do
    lHashes[i] := THashSHA2.Create;
  for lCodePoint := 0 to cCodePointCount - 1 do
  begin
    lCharacter := IndependentUtf16(lCodePoint);
    lInputs[0] := 'A' + lCharacter + cSigma;
    lInputs[1] := 'A' + cSigma + lCharacter;
    lInputs[2] := 'A' + cSigma + lCharacter + 'A';
    for i := 0 to 2 do
    begin
      lOutput := TUnicodeText.Lower(lInputs[i]);
      // Stream format: UInt32LE UTF-16 code-unit count, then UTF-16LE bytes; no header.
      lLength := Length(lOutput);
      lHashes[i].Update(lLength, SizeOf(lLength));
      if lLength > 0 then
        lHashes[i].Update(PChar(lOutput)^, lLength * SizeOf(Char));
    end;
  end;
  for i := 0 to 2 do
    Assert.AreEqual(cContextSha256[i], lHashes[i].HashAsString.ToLowerInvariant,
      'context family ' + cContextNames[i] + ' over ' + IntToStr(cCodePointCount) + ' code points');
end;

function UnitsFromJson(aValue: TJSONValue; const aContext: string): string;
var
  lItem: TJSONValue;
  lUnit: Integer;
begin
  Assert.IsTrue(aValue is TJSONArray, aContext + ' must be a UInt16 array');
  Result := '';
  for lItem in TJSONArray(aValue) do
  begin
    lUnit := (lItem as TJSONNumber).AsInt;
    Assert.IsTrue((lUnit >= 0) and (lUnit <= $FFFF), aContext + ' unit out of range');
    Result := Result + Char(lUnit);
  end;
end;

procedure TNativeAnalysisUnicodeTests.TargetedRowsMatchExactCodeUnits;
var
  g: TGarbos;
  lBytes: TBytes;
  lRows: TJSONArray;
  lItem: TJSONValue;
  lRow: TJSONObject;
  lInput, lRebuilt, lLabel: string;
  lIndex, lRowNumber: Integer;
begin
  lBytes := TFile.ReadAllBytes(FixturePath('unicode-context-rows.json'));
  Assert.AreEqual(cRowsSha256, Sha256Hex(lBytes), 'targeted rows SHA256');
  GC(lRows, ParseJsonValue(TEncoding.UTF8.GetString(lBytes), 'unicode-context-rows.json') as TJSONArray, g);
  Assert.AreEqual(114, lRows.Count, 'targeted row count');
  lRowNumber := 0;
  for lItem in lRows do
  begin
    lRow := lItem as TJSONObject;
    lLabel := 'row ' + IntToStr(lRowNumber);
    lInput := UnitsFromJson(lRow.GetValue('input'), lLabel + ' input');
    Assert.AreEqual(CodeUnitsText(UnitsFromJson(lRow.GetValue('upper'), lLabel + ' upper')),
      CodeUnitsText(TUnicodeText.Upper(lInput)), lLabel + ' upper');
    Assert.AreEqual(CodeUnitsText(UnitsFromJson(lRow.GetValue('lower'), lLabel + ' lower')),
      CodeUnitsText(TUnicodeText.Lower(lInput)), lLabel + ' lower');
    Assert.AreEqual(CodeUnitsText(UnitsFromJson(lRow.GetValue('strip'), lLabel + ' strip')),
      CodeUnitsText(TUnicodeText.Strip(lInput)), lLabel + ' strip');
    // Reader traversal must consume every unit and reproduce the input, including lone surrogates.
    lRebuilt := '';
    lIndex := 1;
    while lIndex <= Length(lInput) do
      lRebuilt := lRebuilt + TUnicodeText.FromCodePoint(TUnicodeText.ReadCodePoint(lInput, lIndex));
    Assert.AreEqual(Integer(Length(lInput)) + 1, lIndex, lLabel + ' reader end index');
    Assert.AreEqual(CodeUnitsText(lInput), CodeUnitsText(lRebuilt), lLabel + ' reader round trip');
    Inc(lRowNumber);
  end;
end;

procedure TNativeAnalysisUnicodeTests.InvalidArgumentsRaiseOrReturnFalse;
var
  lIndex: Integer;
begin
  Assert.WillRaise(
    procedure
    var
      lPosition: Integer;
    begin
      lPosition := 0;
      TUnicodeText.ReadCodePoint('abc', lPosition);
    end, EArgumentOutOfRangeException, 'index below one');
  Assert.WillRaise(
    procedure
    var
      lPosition: Integer;
    begin
      lPosition := 4;
      TUnicodeText.ReadCodePoint('abc', lPosition);
    end, EArgumentOutOfRangeException, 'index beyond input');
  Assert.WillRaise(
    procedure
    var
      lPosition: Integer;
    begin
      lPosition := 1;
      TUnicodeText.ReadCodePoint('', lPosition);
    end, EArgumentOutOfRangeException, 'empty input');
  Assert.WillRaise(
    procedure
    begin
      TUnicodeText.FromCodePoint($110000);
    end, EArgumentOutOfRangeException, 'code point above U+10FFFF');
  Assert.WillRaise(
    procedure
    begin
      TUnicodeText.FromCodePoint($FFFFFFFF);
    end, EArgumentOutOfRangeException, 'code point $FFFFFFFF');
  Assert.AreEqual(CodeUnitsText(#$D800), CodeUnitsText(TUnicodeText.FromCodePoint($D800)), 'lone high surrogate accepted');
  Assert.AreEqual(CodeUnitsText(#$DBFF#$DFFF), CodeUnitsText(TUnicodeText.FromCodePoint($10FFFF)), 'largest code point');
  Assert.IsFalse(TUnicodeText.IsWhitespace($110000), 'IsWhitespace beyond range');
  Assert.IsFalse(TUnicodeText.IsPrintable($110000), 'IsPrintable beyond range');
  Assert.IsFalse(TUnicodeText.IsCased($110000), 'IsCased beyond range');
  Assert.IsFalse(TUnicodeText.IsCaseIgnorable($110000), 'IsCaseIgnorable beyond range');
  Assert.IsFalse(TUnicodeText.IsWhitespace($FFFFFFFF), 'IsWhitespace $FFFFFFFF');
  Assert.IsFalse(TUnicodeText.IsPrintable($FFFFFFFF), 'IsPrintable $FFFFFFFF');
  Assert.IsFalse(TUnicodeText.IsCased($FFFFFFFF), 'IsCased $FFFFFFFF');
  Assert.IsFalse(TUnicodeText.IsCaseIgnorable($FFFFFFFF), 'IsCaseIgnorable $FFFFFFFF');
  // A lone high surrogate before a non-low unit is consumed alone.
  lIndex := 1;
  Assert.AreEqual(Cardinal($D800), TUnicodeText.ReadCodePoint(#$D800'a', lIndex), 'lone surrogate value');
  Assert.AreEqual(2, lIndex, 'lone surrogate advances one unit');
end;

procedure TNativeAnalysisUnicodeTests.LongIgnorableRunsAroundSigma;
const
  cLengths: array[0..3] of Integer = (1, 16, 1000, 20000);
var
  i: Integer;
  lRun, lLabel: string;
begin
  for i := 0 to High(cLengths) do
  begin
    lRun := StringOfChar(cCombiningAcute, cLengths[i]);
    lLabel := Format('ignorable run of %d', [cLengths[i]]);
    Assert.AreEqual('a' + lRun + cFinalSigma, TUnicodeText.Lower('A' + lRun + cSigma), lLabel + ': cased before, end after');
    Assert.AreEqual('a' + cFinalSigma + lRun, TUnicodeText.Lower('A' + cSigma + lRun), lLabel + ': trailing ignorables only');
    Assert.AreEqual('a' + cSmallSigma + lRun + 'b', TUnicodeText.Lower('A' + cSigma + lRun + 'B'), lLabel + ': cased after run');
    Assert.AreEqual('a' + cFinalSigma + lRun + '1', TUnicodeText.Lower('A' + cSigma + lRun + '1'), lLabel + ': uncased after run');
    Assert.AreEqual(lRun + cSmallSigma, TUnicodeText.Lower(lRun + cSigma), lLabel + ': no cased before');
    Assert.AreEqual('a' + lRun + cSmallSigma + lRun + cFinalSigma,
      TUnicodeText.Lower('A' + lRun + cSigma + lRun + cSigma), lLabel + ': sigma followed by sigma');
    Assert.AreEqual('A' + lRun + cSigma, TUnicodeText.Upper('a' + lRun + cSmallSigma), lLabel + ': upper keeps run');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisUnicodeTests);

end.
