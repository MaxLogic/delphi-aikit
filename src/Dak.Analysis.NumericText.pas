unit Dak.Analysis.NumericText;

{$SCOPEDENUMS ON}

interface

type
  // Python-compatible presentation of validated JSON number tokens.
  // Floats (tokens containing '.', 'e' or 'E') are parsed to the correctly rounded binary64
  // value with exact integer arithmetic and printed as repr(float): the shortest digit string
  // that round-trips, in Python's fixed/exponent notation. Integers keep their digits.
  // No RTL floating-point conversion is used because Extended intermediates round differently.
  TNumericText = class sealed
  public
    // str(json.loads(aToken)). Raises EConvertError for a token outside the JSON number grammar.
    class function PythonText(const aToken: string): string; static;
    // bool(json.loads(aToken)) = False: integer zero, or a float that rounds to signed zero.
    class function IsZero(const aToken: string): Boolean; static;
    // Correctly rounded binary64 value of a JSON number token, including underflow to zero
    // and overflow to infinity. Raises EConvertError for an invalid token.
    class function ParseDouble(const aToken: string): Double; static;
    // repr(aValue) for a Python float.
    class function Repr(aValue: Double): string; static;
    class function IsFloatToken(const aToken: string): Boolean; static;
  end;

implementation

uses
  System.Math, System.SysUtils;

type
  // Arbitrary-precision unsigned integer, little-endian 32-bit limbs; Count limbs are in use.
  TBigNat = record
    Limbs: TArray<UInt32>;
    Count: Integer;
    procedure SetSmall(aValue: UInt32);
    procedure Trim;
    function IsZero: Boolean;
    function BitLength: Integer;
    procedure MulAdd(aMultiplier, aAddend: UInt32);
    procedure MulPow10(aPower: Integer);
    procedure ShiftLeft(aBits: Integer);
    procedure Add(const aOther: TBigNat);
    procedure Sub(const aOther: TBigNat);
    function Compare(const aOther: TBigNat): Integer;
  end;

const
  cPow10Small: array[0..9] of UInt32 = (1, 10, 100, 1000, 10000, 100000, 1000000, 10000000,
    100000000, 1000000000);
  cMantissaBits = 52;
  cMinExponent = -1074;
  cMaxExponent = 971;

procedure TBigNat.SetSmall(aValue: UInt32);
begin
  SetLength(Limbs, 4);
  Limbs[0] := aValue;
  Count := 1;
  Trim;
end;

procedure TBigNat.Trim;
begin
  while (Count > 0) and (Limbs[Count - 1] = 0) do
    Dec(Count);
end;

function TBigNat.IsZero: Boolean;
begin
  Result := Count = 0;
end;

function TBigNat.BitLength: Integer;
var
  lTop: UInt32;
begin
  if Count = 0 then
    Exit(0);
  Result := (Count - 1) * 32;
  lTop := Limbs[Count - 1];
  while lTop <> 0 do
  begin
    Inc(Result);
    lTop := lTop shr 1;
  end;
end;

procedure TBigNat.MulAdd(aMultiplier, aAddend: UInt32);
var
  i: Integer;
  lCarry, lProduct: UInt64;
begin
  lCarry := aAddend;
  for i := 0 to Count - 1 do
  begin
    lProduct := UInt64(Limbs[i]) * aMultiplier + lCarry;
    Limbs[i] := UInt32(lProduct);
    lCarry := lProduct shr 32;
  end;
  if lCarry <> 0 then
  begin
    if Count = Length(Limbs) then
      SetLength(Limbs, Length(Limbs) * 2 + 2);
    Limbs[Count] := UInt32(lCarry);
    Inc(Count);
  end;
end;

procedure TBigNat.MulPow10(aPower: Integer);
begin
  while aPower >= 9 do
  begin
    MulAdd(cPow10Small[9], 0);
    Dec(aPower, 9);
  end;
  if aPower > 0 then
    MulAdd(cPow10Small[aPower], 0);
end;

procedure TBigNat.ShiftLeft(aBits: Integer);
var
  i, lLimbShift, lBitShift: Integer;
  lNew: TArray<UInt32>;
begin
  if (aBits <= 0) or (Count = 0) then
    Exit;
  lLimbShift := aBits div 32;
  lBitShift := aBits mod 32;
  SetLength(lNew, Count + lLimbShift + 2);
  for i := 0 to Count - 1 do
  begin
    lNew[i + lLimbShift] := lNew[i + lLimbShift] or (Limbs[i] shl lBitShift);
    if lBitShift > 0 then
      lNew[i + lLimbShift + 1] := lNew[i + lLimbShift + 1] or (Limbs[i] shr (32 - lBitShift));
  end;
  Limbs := lNew;
  Count := Count + lLimbShift + 1;
  Trim;
end;

procedure TBigNat.Add(const aOther: TBigNat);
var
  i, lMax: Integer;
  lSum: UInt64;
begin
  lMax := Max(Count, aOther.Count);
  if lMax + 1 > Length(Limbs) then
    SetLength(Limbs, lMax + 2);
  for i := Count to lMax do
    Limbs[i] := 0;
  lSum := 0;
  for i := 0 to lMax - 1 do
  begin
    lSum := lSum + Limbs[i];
    if i < aOther.Count then
      lSum := lSum + aOther.Limbs[i];
    Limbs[i] := UInt32(lSum);
    lSum := lSum shr 32;
  end;
  Limbs[lMax] := UInt32(lSum);
  Count := lMax + 1;
  Trim;
end;

procedure TBigNat.Sub(const aOther: TBigNat);
var
  i: Integer;
  lBorrow, lDiff: Int64;
begin
  // Precondition: Self >= aOther.
  lBorrow := 0;
  for i := 0 to Count - 1 do
  begin
    lDiff := Int64(Limbs[i]) - lBorrow;
    if i < aOther.Count then
      lDiff := lDiff - aOther.Limbs[i];
    if lDiff < 0 then
    begin
      lDiff := lDiff + $100000000;
      lBorrow := 1;
    end else
      lBorrow := 0;
    Limbs[i] := UInt32(lDiff);
  end;
  Trim;
end;

function TBigNat.Compare(const aOther: TBigNat): Integer;
var
  i: Integer;
begin
  if Count <> aOther.Count then
    Exit(Sign(Count - aOther.Count));
  for i := Count - 1 downto 0 do
    if Limbs[i] <> aOther.Limbs[i] then
    begin
      if Limbs[i] > aOther.Limbs[i] then
        Exit(1);
      Exit(-1);
    end;
  Result := 0;
end;

function CopyShifted(const aValue: TBigNat; aBits: Integer): TBigNat;
begin
  Result.Limbs := Copy(aValue.Limbs, 0, Length(aValue.Limbs));
  Result.Count := aValue.Count;
  Result.ShiftLeft(aBits);
end;

procedure InvalidToken(const aToken: string);
begin
  raise EConvertError.CreateFmt('Invalid JSON number token: %s', [aToken]);
end;

// Splits a JSON number into sign, significant digits and decimal exponent so that
// |value| = digits * 10^aExponent. Leading and trailing zeros are removed from digits.
procedure DecomposeToken(const aToken: string; out aNegative: Boolean; out aDigits: string;
  out aExponent: Int64);
var
  i, lLength, lStart, lFractionDigits: Integer;
  lExponentNegative: Boolean;
  lExponent: Int64;
  lIntegerPart, lFractionPart: string;
begin
  lLength := Length(aToken);
  i := 1;
  aNegative := (lLength >= 1) and (aToken[1] = '-');
  if aNegative then
    Inc(i);
  lStart := i;
  while (i <= lLength) and CharInSet(aToken[i], ['0'..'9']) do
    Inc(i);
  lIntegerPart := Copy(aToken, lStart, i - lStart);
  if (lIntegerPart = '') or ((Length(lIntegerPart) > 1) and (lIntegerPart[1] = '0')) then
    InvalidToken(aToken);
  lFractionPart := '';
  if (i <= lLength) and (aToken[i] = '.') then
  begin
    Inc(i);
    lStart := i;
    while (i <= lLength) and CharInSet(aToken[i], ['0'..'9']) do
      Inc(i);
    lFractionPart := Copy(aToken, lStart, i - lStart);
    if lFractionPart = '' then
      InvalidToken(aToken);
  end;
  lExponent := 0;
  if (i <= lLength) and CharInSet(aToken[i], ['e', 'E']) then
  begin
    Inc(i);
    lExponentNegative := False;
    if (i <= lLength) and CharInSet(aToken[i], ['+', '-']) then
    begin
      lExponentNegative := aToken[i] = '-';
      Inc(i);
    end;
    lStart := i;
    while (i <= lLength) and CharInSet(aToken[i], ['0'..'9']) do
    begin
      // Saturate far beyond any binary64 range so absurd exponents cannot wrap.
      if lExponent < 1000000000000 then
        lExponent := lExponent * 10 + (Ord(aToken[i]) - Ord('0'));
      Inc(i);
    end;
    if i = lStart then
      InvalidToken(aToken);
    if lExponentNegative then
      lExponent := -lExponent;
  end;
  if i <= lLength then
    InvalidToken(aToken);
  lFractionDigits := Length(lFractionPart);
  aDigits := lIntegerPart + lFractionPart;
  aExponent := lExponent - lFractionDigits;
  i := 1;
  while (i <= Length(aDigits)) and (aDigits[i] = '0') do
    Inc(i);
  aDigits := Copy(aDigits, i, MaxInt);
  i := Length(aDigits);
  while (i >= 1) and (aDigits[i] = '0') do
  begin
    Dec(i);
    Inc(aExponent);
  end;
  SetLength(aDigits, i);
end;

function DigitsToBigNat(const aDigits: string): TBigNat;
var
  i, lChunk: Integer;
begin
  Result.SetSmall(0);
  i := 1;
  while i <= Length(aDigits) do
  begin
    lChunk := Min(9, Length(aDigits) - i + 1);
    Result.MulAdd(cPow10Small[lChunk], StrToInt(Copy(aDigits, i, lChunk)));
    Inc(i, lChunk);
  end;
end;

function MakeDouble(aNegative: Boolean; aBiasedExponent: Integer; aMantissa: UInt64): Double;
var
  lBits: UInt64;
begin
  lBits := (UInt64(aBiasedExponent) shl cMantissaBits) or aMantissa;
  if aNegative then
    lBits := lBits or (UInt64(1) shl 63);
  Result := PDouble(@lBits)^;
end;

function Infinity(aNegative: Boolean): Double;
begin
  Result := MakeDouble(aNegative, $7FF, 0);
end;

class function TNumericText.ParseDouble(const aToken: string): Double;
var
  lNegative: Boolean;
  lDigits: string;
  lExponent, lLeadingExponent: Int64;
  lNumerator, lDenominator, lScaledNumerator, lScaledDenominator, lTerm: TBigNat;
  lBinaryExponent, i: Integer;
  lMantissa: UInt64;
  lRemainderCompare: Integer;
begin
  DecomposeToken(aToken, lNegative, lDigits, lExponent);
  if lDigits = '' then
    Exit(MakeDouble(lNegative, 0, 0));
  // Decimal exponent of the leading digit: the value lies in [10^p, 10^(p+1)).
  lLeadingExponent := lExponent + Length(lDigits) - 1;
  if lLeadingExponent >= 309 then
    Exit(Infinity(lNegative));
  if lLeadingExponent <= -325 then
    Exit(MakeDouble(lNegative, 0, 0));
  lNumerator := DigitsToBigNat(lDigits);
  lDenominator.SetSmall(1);
  if lExponent >= 0 then
    lNumerator.MulPow10(Integer(lExponent))
  else
    lDenominator.MulPow10(Integer(-lExponent));
  // Choose the binary exponent so that the quotient has 53 significant bits, then divide exactly.
  lBinaryExponent := lNumerator.BitLength - lDenominator.BitLength - 53;
  if lBinaryExponent < cMinExponent then
    lBinaryExponent := cMinExponent;
  repeat
    lScaledNumerator := CopyShifted(lNumerator, Max(-lBinaryExponent, 0));
    lScaledDenominator := CopyShifted(lDenominator, Max(lBinaryExponent, 0));
    lMantissa := 0;
    for i := 53 downto 0 do
    begin
      lTerm := CopyShifted(lScaledDenominator, i);
      if lScaledNumerator.Compare(lTerm) >= 0 then
      begin
        lScaledNumerator.Sub(lTerm);
        lMantissa := lMantissa or (UInt64(1) shl i);
      end;
    end;
    if lMantissa >= (UInt64(1) shl 53) then
      Inc(lBinaryExponent)
    else if (lMantissa < (UInt64(1) shl cMantissaBits)) and (lBinaryExponent > cMinExponent) then
      Dec(lBinaryExponent)
    else
      Break;
  until False;
  // Round to nearest, ties to even, using the exact remainder.
  lScaledNumerator.ShiftLeft(1);
  lRemainderCompare := lScaledNumerator.Compare(lScaledDenominator);
  if (lRemainderCompare > 0) or ((lRemainderCompare = 0) and ((lMantissa and 1) = 1)) then
  begin
    Inc(lMantissa);
    if lMantissa = (UInt64(1) shl 53) then
    begin
      lMantissa := UInt64(1) shl cMantissaBits;
      Inc(lBinaryExponent);
    end;
  end;
  if lBinaryExponent > cMaxExponent then
    Exit(Infinity(lNegative));
  if lMantissa >= (UInt64(1) shl cMantissaBits) then
    Result := MakeDouble(lNegative, lBinaryExponent + cMantissaBits + 1023, lMantissa and ((UInt64(1) shl cMantissaBits) - 1))
  else
    Result := MakeDouble(lNegative, 0, lMantissa);
end;

// Shortest round-tripping digits (Steele-White/Burger-Dybvig free format with dtoa mode 0 tie rules).
procedure ShortestDigits(aValue: Double; out aDigits: string; out aDecimalPoint: Integer);
var
  lBits, lMantissa: UInt64;
  lBiasedExponent, lExponent, lEstimate, lDigit, lCompare: Integer;
  lEven, lUnequalGaps, lLow, lHigh: Boolean;
  lRemainder, lScale, lPlus, lMinus, lTemp: TBigNat;
  lBuilder: TStringBuilder;
begin
  lBits := PUInt64(@aValue)^;
  lBiasedExponent := Integer((lBits shr cMantissaBits) and $7FF);
  lMantissa := lBits and ((UInt64(1) shl cMantissaBits) - 1);
  if lBiasedExponent = 0 then
    lExponent := cMinExponent
  else begin
    lMantissa := lMantissa or (UInt64(1) shl cMantissaBits);
    lExponent := lBiasedExponent - 1023 - cMantissaBits;
  end;
  lEven := (lMantissa and 1) = 0;
  // A power of two above the smallest normal has a smaller gap below than above.
  lUnequalGaps := (lMantissa = (UInt64(1) shl cMantissaBits)) and (lBiasedExponent > 1);
  lRemainder.SetSmall(0);
  lRemainder.Limbs[0] := UInt32(lMantissa);
  lRemainder.Limbs[1] := UInt32(lMantissa shr 32);
  lRemainder.Count := 2;
  lRemainder.Trim;
  lScale.SetSmall(1);
  lPlus.SetSmall(1);
  lMinus.SetSmall(1);
  if lExponent >= 0 then
  begin
    lRemainder.ShiftLeft(lExponent + 1);
    lScale.ShiftLeft(1);
    lPlus.ShiftLeft(lExponent);
    lMinus.ShiftLeft(lExponent);
  end else begin
    lRemainder.ShiftLeft(1);
    lScale.ShiftLeft(1 - lExponent);
  end;
  if lUnequalGaps then
  begin
    lRemainder.ShiftLeft(1);
    lScale.ShiftLeft(1);
    lPlus.ShiftLeft(1);
  end;
  // Estimate ceil(log10(value)); never too large, and one too small is corrected below.
  lEstimate := Ceil(Log10(Abs(aValue)) - 1E-10);
  if lEstimate >= 0 then
    lScale.MulPow10(lEstimate)
  else begin
    lRemainder.MulPow10(-lEstimate);
    lPlus.MulPow10(-lEstimate);
    lMinus.MulPow10(-lEstimate);
  end;
  lTemp := lRemainder;
  lTemp.Limbs := Copy(lRemainder.Limbs, 0, Length(lRemainder.Limbs));
  lTemp.Add(lPlus);
  lCompare := lTemp.Compare(lScale);
  if (lCompare > 0) or (lEven and (lCompare = 0)) then
    Inc(lEstimate)
  else begin
    lRemainder.MulAdd(10, 0);
    lPlus.MulAdd(10, 0);
    lMinus.MulAdd(10, 0);
  end;
  aDecimalPoint := lEstimate;
  lBuilder := TStringBuilder.Create;
  try
    repeat
      lDigit := 0;
      while lRemainder.Compare(lScale) >= 0 do
      begin
        lRemainder.Sub(lScale);
        Inc(lDigit);
      end;
      lCompare := lRemainder.Compare(lMinus);
      lLow := (lCompare < 0) or (lEven and (lCompare = 0));
      lTemp.Limbs := Copy(lRemainder.Limbs, 0, Length(lRemainder.Limbs));
      lTemp.Count := lRemainder.Count;
      lTemp.Add(lPlus);
      lCompare := lTemp.Compare(lScale);
      lHigh := (lCompare > 0) or (lEven and (lCompare = 0));
      if lLow and lHigh and not lRemainder.IsZero then
      begin
        // Both neighbours are acceptable: pick the closer digit, ties to the even digit.
        lRemainder.ShiftLeft(1);
        lCompare := lRemainder.Compare(lScale);
        if (lCompare > 0) or ((lCompare = 0) and ((lDigit and 1) = 1)) then
          Inc(lDigit);
        lBuilder.Append(Chr(Ord('0') + lDigit));
        Break;
      end;
      if lLow then
      begin
        lBuilder.Append(Chr(Ord('0') + lDigit));
        Break;
      end;
      if lHigh then
      begin
        if lDigit = 9 then
        begin
          // Rounding up past 9 at the first digit means the value is the next power of ten.
          lBuilder.Append('1');
          Inc(aDecimalPoint);
        end else
          lBuilder.Append(Chr(Ord('0') + lDigit + 1));
        Break;
      end;
      lBuilder.Append(Chr(Ord('0') + lDigit));
      lRemainder.MulAdd(10, 0);
      lPlus.MulAdd(10, 0);
      lMinus.MulAdd(10, 0);
    until False;
    aDigits := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

class function TNumericText.Repr(aValue: Double): string;
var
  lBits: UInt64;
  lNegative: Boolean;
  lDigits, lExponentText: string;
  lDecimalPoint, lExponent: Integer;
begin
  lBits := PUInt64(@aValue)^;
  lNegative := (lBits shr 63) = 1;
  if (lBits and $7FFFFFFFFFFFFFFF) = 0 then
  begin
    if lNegative then
      Exit('-0.0');
    Exit('0.0');
  end;
  if ((lBits shr cMantissaBits) and $7FF) = $7FF then
  begin
    if (lBits and ((UInt64(1) shl cMantissaBits) - 1)) <> 0 then
      Exit('nan');
    if lNegative then
      Exit('-inf');
    Exit('inf');
  end;
  ShortestDigits(aValue, lDigits, lDecimalPoint);
  // Python float_repr_style 'short': exponent form outside 1e-4 <= |value| < 1e16.
  if (lDecimalPoint <= -4) or (lDecimalPoint > 16) then
  begin
    lExponent := lDecimalPoint - 1;
    lExponentText := IntToStr(Abs(lExponent));
    if Length(lExponentText) < 2 then
      lExponentText := '0' + lExponentText;
    Result := lDigits[1];
    if Length(lDigits) > 1 then
      Result := Result + '.' + Copy(lDigits, 2, MaxInt);
    if lExponent < 0 then
      Result := Result + 'e-' + lExponentText
    else
      Result := Result + 'e+' + lExponentText;
  end else if lDecimalPoint <= 0 then
    Result := '0.' + StringOfChar('0', -lDecimalPoint) + lDigits
  else if lDecimalPoint >= Length(lDigits) then
    Result := lDigits + StringOfChar('0', lDecimalPoint - Length(lDigits)) + '.0'
  else
    Result := Copy(lDigits, 1, lDecimalPoint) + '.' + Copy(lDigits, lDecimalPoint + 1, MaxInt);
  if lNegative then
    Result := '-' + Result;
end;

class function TNumericText.IsFloatToken(const aToken: string): Boolean;
var
  c: Char;
begin
  for c in aToken do
    if CharInSet(c, ['.', 'e', 'E']) then
      Exit(True);
  Result := False;
end;

class function TNumericText.PythonText(const aToken: string): string;
var
  lNegative: Boolean;
  lDigits: string;
  lExponent: Int64;
begin
  if IsFloatToken(aToken) then
    Exit(Repr(ParseDouble(aToken)));
  DecomposeToken(aToken, lNegative, lDigits, lExponent);
  if lDigits = '' then
    Exit('0');
  Result := aToken;
end;

class function TNumericText.IsZero(const aToken: string): Boolean;
var
  lNegative: Boolean;
  lDigits: string;
  lExponent: Int64;
begin
  if IsFloatToken(aToken) then
    Exit(ParseDouble(aToken) = 0);
  DecomposeToken(aToken, lNegative, lDigits, lExponent);
  Result := lDigits = '';
end;

end.
