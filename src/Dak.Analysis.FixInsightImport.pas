unit Dak.Analysis.FixInsightImport;

interface

uses
  System.JSON;

// Caller owns the array and its raw finding objects.
function LoadFixInsightFindings(const aPath: string): TJSONArray;

implementation

uses
  System.Character, System.IOUtils, System.RegularExpressions, System.SysUtils,
  Dak.Analysis.Text;

const
  cPythonSpace = '[\x09-\x0D\x1C-\x20\x85\xA0\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}]';

function TrimPythonSpace(const aValue: string): string;
var
  lFirst: Integer;
  lLast: Integer;
begin
  lFirst := 1;
  lLast := Length(aValue);
  while (lFirst <= lLast) and
    (aValue[lFirst].IsWhiteSpace or CharInSet(aValue[lFirst], [#28..#31])) do
    Inc(lFirst);
  while (lLast >= lFirst) and
    (aValue[lLast].IsWhiteSpace or CharInSet(aValue[lLast], [#28..#31])) do
    Dec(lLast);
  Result := Copy(aValue, lFirst, lLast - lFirst + 1);
end;

function DecimalJsonNumber(const aDigits: string): TJSONNumber;
var
  c: Char;
  i: Integer;
  lStarted: Boolean;
begin
  // The regex validated decimal Unicode digits. Avoid the string constructor's Double conversion.
  Result := TJSONNumber.Create('');
  try
    i := 1;
    lStarted := False;
    while i <= Length(aDigits) do
    begin
      c := Char(Ord('0') + Round(Char.GetNumericValue(aDigits, i - 1)));
      if (c <> '0') or lStarted then
      begin
        Result.AddChar(c);
        lStarted := True;
      end;
      if aDigits[i].IsHighSurrogate then
        Inc(i);
      Inc(i);
    end;
    if not lStarted then
      Result.AddChar('0');
  except
    Result.Free;
    raise;
  end;
end;

function LoadFixInsightFindings(const aPath: string): TJSONArray;
var
  lCurrentFile: string;
  lFinding: TJSONObject;
  lHasFile: Boolean;
  lLine: string;
  lMatch: TMatch;
  lPattern: TRegEx;
  lText: string;
begin
  Result := TJSONArray.Create;
  try
    if not TFile.Exists(aPath) and not TDirectory.Exists(aPath) then
      Exit;
    lText := ReadAnalysisText(aPath);
    lPattern := TRegEx.Create('^' + cPythonSpace + '*([A-Z]\p{Nd}{3})' + cPythonSpace +
      '+(.*)' + cPythonSpace + '+\((\p{Nd}+),' + cPythonSpace + '*(\p{Nd}+)\)' + cPythonSpace + '*$', []);
    lHasFile := False;
    lCurrentFile := '';
    // Python splitlines also recognizes vertical/form feeds, separators and NEL.
    for lLine in lText.Split([#10, #13, #11, #12, #28, #29, #30, #$85, #$2028, #$2029]) do
    begin
      if TrimPythonSpace(lLine) = '' then
        Continue;
      if lLine.StartsWith('File:') then
      begin
        lCurrentFile := TrimPythonSpace(Copy(lLine, 6, MaxInt));
        lHasFile := True;
        Continue;
      end;
      if not lHasFile then
        Continue;
      lMatch := lPattern.Match(lLine);
      if not lMatch.Success then
        Continue;
      lFinding := TJSONObject.Create;
      try
        lFinding.AddPair('code', lMatch.Groups[1].Value);
        lFinding.AddPair('file', lCurrentFile);
        lFinding.AddPair('line', DecimalJsonNumber(lMatch.Groups[3].Value));
        lFinding.AddPair('col', DecimalJsonNumber(lMatch.Groups[4].Value));
        lFinding.AddPair('message', TrimPythonSpace(lMatch.Groups[2].Value));
        lFinding.AddPair('kind', Copy(lMatch.Groups[1].Value, 1, 1));
        Result.AddElement(lFinding);
        lFinding := nil;
      finally
        lFinding.Free;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
