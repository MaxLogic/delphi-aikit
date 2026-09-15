unit Dak.Analysis.UnicodeText;

{$SCOPEDENUMS ON}

interface

type
  // Unicode 15.1, independent of Windows locale and installed Unicode versions.
  TUnicodeText = class sealed
  public
    class function Upper(const aText: string): string; static;
    class function Lower(const aText: string): string; static;
    class function Strip(const aText: string): string; static;
    class function IsWhitespace(aCodePoint: Cardinal): Boolean; static;
    class function IsPrintable(aCodePoint: Cardinal): Boolean; static;
    class function IsCased(aCodePoint: Cardinal): Boolean; static;
    class function IsCaseIgnorable(aCodePoint: Cardinal): Boolean; static;
    // One-based input index. Valid pairs combine; lone surrogates stay unchanged.
    class function ReadCodePoint(const aText: string; var aIndex: Integer): Cardinal; static;
    class function FromCodePoint(aCodePoint: Cardinal): string; static;
  end;

implementation

uses
  System.SysUtils;

type
  TUnicodeRange = record
    First, Last: Cardinal;
  end;

  TUnicodeSimpleRange = record
    First, Last: Cardinal;
    Delta: Integer;
    Step: Cardinal;
  end;

  TUnicodeExpansion = record
    CodePoint, PoolOffset, Count: Cardinal;
  end;

  TUnicodeCase = (Upper, Lower);

{$I Dak.Analysis.UnicodeData.inc}

function InRanges(aCodePoint: Cardinal; const aRanges: array of TUnicodeRange): Boolean;
var
  lLow, lHigh, lMiddle: Integer;
begin
  lLow := Low(aRanges);
  lHigh := High(aRanges);
  while lLow <= lHigh do
  begin
    lMiddle := lLow + (lHigh - lLow) div 2;
    if aCodePoint < aRanges[lMiddle].First then
      lHigh := lMiddle - 1
    else if aCodePoint > aRanges[lMiddle].Last then
      lLow := lMiddle + 1
    else
      Exit(True);
  end;
  Result := False;
end;

function MapSimple(aCodePoint: Cardinal; const aRanges: array of TUnicodeSimpleRange): Cardinal;
var
  lLow, lHigh, lMiddle: Integer;
begin
  lLow := Low(aRanges);
  lHigh := High(aRanges);
  while lLow <= lHigh do
  begin
    lMiddle := lLow + (lHigh - lLow) div 2;
    if aCodePoint < aRanges[lMiddle].First then
      lHigh := lMiddle - 1
    else if aCodePoint > aRanges[lMiddle].Last then
      lLow := lMiddle + 1
    else begin
      if ((aCodePoint - aRanges[lMiddle].First) mod aRanges[lMiddle].Step) = 0 then
        Exit(Cardinal(Int64(aCodePoint) + aRanges[lMiddle].Delta));
      Exit(aCodePoint);
    end;
  end;
  Result := aCodePoint;
end;

function FindExpansion(aCodePoint: Cardinal; const aExpansions: array of TUnicodeExpansion): Integer;
var
  lLow, lHigh, lMiddle: Integer;
begin
  lLow := Low(aExpansions);
  lHigh := High(aExpansions);
  while lLow <= lHigh do
  begin
    lMiddle := lLow + (lHigh - lLow) div 2;
    if aCodePoint < aExpansions[lMiddle].CodePoint then
      lHigh := lMiddle - 1
    else if aCodePoint > aExpansions[lMiddle].CodePoint then
      lLow := lMiddle + 1
    else
      Exit(lMiddle);
  end;
  Result := -1;
end;

procedure AppendCodePoint(var aText: string; var aUsed: Integer; aCodePoint: Cardinal);
var
  lCount: Integer;
  lCapacity, lNeeded: Int64;
begin
  if aCodePoint <= $FFFF then
    lCount := 1
  else
    lCount := 2;
  lNeeded := Int64(aUsed) + lCount;
  if lNeeded > Length(aText) then
  begin
    lCapacity := Int64(Length(aText)) * 2;
    if lCapacity < lNeeded then
      lCapacity := lNeeded;
    if lCapacity > MaxInt then
      lCapacity := MaxInt;
    if lCapacity < lNeeded then
      raise EOutOfMemory.Create('Unicode text exceeds the supported string length');
    SetLength(aText, Integer(lCapacity));
  end;
  Inc(aUsed);
  if lCount = 1 then
    aText[aUsed] := Char(aCodePoint)
  else begin
    aText[aUsed] := Char($D800 + ((aCodePoint - $10000) shr 10));
    Inc(aUsed);
    aText[aUsed] := Char($DC00 + ((aCodePoint - $10000) and $3FF));
  end;
end;

procedure AppendMapping(var aText: string; var aUsed: Integer; aCodePoint: Cardinal;
  const aSimple: array of TUnicodeSimpleRange; const aExpansions: array of TUnicodeExpansion);
var
  lExpansion: Integer;
  i: Cardinal;
begin
  lExpansion := FindExpansion(aCodePoint, aExpansions);
  if lExpansion >= 0 then
  begin
    for i := 0 to aExpansions[lExpansion].Count - 1 do
    begin
      AppendCodePoint(aText, aUsed, cExpansionPool[aExpansions[lExpansion].PoolOffset + i]);
    end;
  end else begin
    AppendCodePoint(aText, aUsed, MapSimple(aCodePoint, aSimple));
  end;
end;

function HasFollowingCased(const aText: string; aIndex: Integer): Boolean;
var
  lCodePoint: Cardinal;
begin
  while aIndex <= Length(aText) do
  begin
    lCodePoint := TUnicodeText.ReadCodePoint(aText, aIndex);
    if not TUnicodeText.IsCaseIgnorable(lCodePoint) then
      Exit(TUnicodeText.IsCased(lCodePoint));
  end;
  Result := False;
end;

function ConvertCase(const aText: string; aCase: TUnicodeCase): string;
var
  lIndex, lUsed: Integer;
  lCodePoint, lMapped: Cardinal;
  lPreviousCased: Boolean;
begin
  SetLength(Result, Length(aText));
  lIndex := 1;
  lUsed := 0;
  lPreviousCased := False;
  while lIndex <= Length(aText) do
  begin
    lCodePoint := TUnicodeText.ReadCodePoint(aText, lIndex);
    if lCodePoint < $80 then
    begin
      lMapped := lCodePoint;
      if (aCase = TUnicodeCase.Upper) and (lCodePoint >= Ord('a')) and (lCodePoint <= Ord('z')) then
        Dec(lMapped, 32)
      else if (aCase = TUnicodeCase.Lower) and (lCodePoint >= Ord('A')) and (lCodePoint <= Ord('Z')) then
        Inc(lMapped, 32);
      AppendCodePoint(Result, lUsed, lMapped);
    end else if aCase = TUnicodeCase.Upper then
    begin
      AppendMapping(Result, lUsed, lCodePoint, cUpperSimple, cUpperExpansions);
    end else if (lCodePoint = $03A3) and lPreviousCased and not HasFollowingCased(aText, lIndex) then
    begin
      // Inspect original input, never transformed output. Sigma is nonignorable,
      // so separate lookaheads cannot repeatedly traverse the same ignorable run.
      AppendCodePoint(Result, lUsed, $03C2);
    end else begin
      AppendMapping(Result, lUsed, lCodePoint, cLowerSimple, cLowerExpansions);
    end;
    if aCase = TUnicodeCase.Lower then
    begin
      // Some code points are both Cased and Case_Ignorable; ignore them first.
      if not TUnicodeText.IsCaseIgnorable(lCodePoint) then
        lPreviousCased := TUnicodeText.IsCased(lCodePoint);
    end;
  end;
  SetLength(Result, lUsed);
end;

class function TUnicodeText.Upper(const aText: string): string;
begin
  Result := ConvertCase(aText, TUnicodeCase.Upper);
end;

class function TUnicodeText.Lower(const aText: string): string;
begin
  Result := ConvertCase(aText, TUnicodeCase.Lower);
end;

class function TUnicodeText.Strip(const aText: string): string;
var
  lIndex, lFirst, lLast, lStart: Integer;
  lCodePoint: Cardinal;
begin
  lIndex := 1;
  lFirst := 0;
  lLast := 0;
  while lIndex <= Length(aText) do
  begin
    lStart := lIndex;
    lCodePoint := ReadCodePoint(aText, lIndex);
    if not IsWhitespace(lCodePoint) then
    begin
      if lFirst = 0 then
        lFirst := lStart;
      lLast := lIndex - 1;
    end;
  end;
  if lFirst = 0 then
    Exit('');
  Result := Copy(aText, lFirst, lLast - lFirst + 1);
end;

class function TUnicodeText.IsWhitespace(aCodePoint: Cardinal): Boolean;
begin
  if aCodePoint < $80 then
    Exit(((aCodePoint >= 9) and (aCodePoint <= 13)) or ((aCodePoint >= 28) and (aCodePoint <= 32)));
  Result := InRanges(aCodePoint, cWhitespace);
end;

class function TUnicodeText.IsPrintable(aCodePoint: Cardinal): Boolean;
begin
  if aCodePoint < $80 then
    Exit((aCodePoint >= 32) and (aCodePoint <= 126));
  Result := (aCodePoint <= $10FFFF) and not InRanges(aCodePoint, cNonPrintable);
end;

class function TUnicodeText.IsCased(aCodePoint: Cardinal): Boolean;
begin
  if aCodePoint < $80 then
    Exit(((aCodePoint >= Ord('A')) and (aCodePoint <= Ord('Z'))) or
      ((aCodePoint >= Ord('a')) and (aCodePoint <= Ord('z'))));
  Result := InRanges(aCodePoint, cCased);
end;

class function TUnicodeText.IsCaseIgnorable(aCodePoint: Cardinal): Boolean;
begin
  Result := InRanges(aCodePoint, cCaseIgnorable);
end;

class function TUnicodeText.ReadCodePoint(const aText: string; var aIndex: Integer): Cardinal;
var
  lFollowing: Cardinal;
begin
  if (aIndex < 1) or (aIndex > Length(aText)) then
    raise EArgumentOutOfRangeException.Create('Unicode text index is outside the input');
  Result := Ord(aText[aIndex]);
  Inc(aIndex);
  if (Result >= $D800) and (Result <= $DBFF) and (aIndex <= Length(aText)) then
  begin
    lFollowing := Ord(aText[aIndex]);
    if (lFollowing >= $DC00) and (lFollowing <= $DFFF) then
    begin
      Result := $10000 + ((Result - $D800) shl 10) + (lFollowing - $DC00);
      Inc(aIndex);
    end;
  end;
end;

class function TUnicodeText.FromCodePoint(aCodePoint: Cardinal): string;
var
  lUsed: Integer;
begin
  if aCodePoint > $10FFFF then
    raise EArgumentOutOfRangeException.Create('Unicode code point exceeds U+10FFFF');
  Result := '';
  lUsed := 0;
  AppendCodePoint(Result, lUsed, aCodePoint);
end;

initialization
  Assert(SizeOf(TUnicodeRange) = 8);
  Assert(SizeOf(TUnicodeSimpleRange) = 16);
  Assert(SizeOf(TUnicodeExpansion) = 12);

end.
