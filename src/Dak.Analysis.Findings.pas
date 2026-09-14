unit Dak.Analysis.Findings;

interface

uses
  System.JSON;

// The returned array owns complete input values, including extension fields and duplicate rows.
// Shape, ownership and policy validation belong to the report context, not this input adapter.
function LoadAnalysisJsonLines(const aPath: string): TJSONArray;

implementation

uses
  System.Character, System.Generics.Collections, System.IOUtils, System.SysUtils;

function IsLineWhitespace(aChar: Char): Boolean;
begin
  // Python str.strip includes these four information separators beyond Unicode whitespace.
  Result := aChar.IsWhiteSpace or ((aChar >= #28) and (aChar <= #31));
end;

function HasValidJsonLexemes(const aText: string; aFirst, aLast: Integer): Boolean;
var
  c: Char;
  i: Integer;
  lEscaped: Boolean;
  lQuoted: Boolean;
begin
  // Supplement two permissive RTL parser cases without duplicating structural JSON parsing.
  lQuoted := False;
  lEscaped := False;
  for i := aFirst to aLast do
  begin
    c := aText[i];
    if lQuoted then
    begin
      if c < #32 then
        Exit(False);
      if lEscaped then
        lEscaped := False
      else if c = '\' then
        lEscaped := True
      else if c = '"' then
        lQuoted := False;
    end else if c = '"' then
      lQuoted := True
    else if (c = '-') and ((i = aLast) or not CharInSet(aText[i + 1], ['0'..'9'])) then
      Exit(False);
  end;
  Result := True;
end;

function CopyJsonDictionaryValue(const aValue: TJSONValue): TJSONValue;
var
  c: Char;
  lArray: TJSONArray;
  lItem: TJSONValue;
  lLast: TJSONPair;
  lMembers: TDictionary<string, TJSONPair>;
  lObject: TJSONObject;
  lNumber: TJSONNumber;
  lPair: TJSONPair;
begin
  if aValue is TJSONObject then
  begin
    lMembers := TDictionary<string, TJSONPair>.Create;
    try
      for lPair in TJSONObject(aValue) do
        lMembers.AddOrSetValue(lPair.JsonString.Value, lPair);
      lObject := TJSONObject.Create;
      try
        // json.loads keeps the last duplicate value at the first key's insertion position.
        for lPair in TJSONObject(aValue) do
          if lMembers.TryGetValue(lPair.JsonString.Value, lLast) and (lLast <> nil) then
          begin
            // AddPair(string, value) silently ignores an empty key without taking ownership.
            lObject.AddPair(TJSONPair.Create(lPair.JsonString.Value, CopyJsonDictionaryValue(lLast.JsonValue)));
            lMembers[lPair.JsonString.Value] := nil;
          end;
        Result := lObject;
      except
        lObject.Free;
        raise;
      end;
    finally
      lMembers.Free;
    end;
  end else if aValue is TJSONArray then
  begin
    lArray := TJSONArray.Create;
    try
      for lItem in TJSONArray(aValue) do
        lArray.AddElement(CopyJsonDictionaryValue(lItem));
      Result := lArray;
    except
      lArray.Free;
      raise;
    end;
  end else if aValue is TJSONNumber then
  begin
    // TJSONNumber.Clone converts through Double; retain arbitrary JSON decimal text instead.
    lNumber := TJSONNumber.Create('');
    try
      for c in aValue.Value do
        lNumber.AddChar(c);
      Result := lNumber;
    except
      lNumber.Free;
      raise;
    end;
  end else
    Result := aValue.Clone as TJSONValue;
end;

function LoadAnalysisJsonLines(const aPath: string): TJSONArray;
var
  lBytes: TBytes;
  lEnd: Integer;
  lFirst: Integer;
  lLast: Integer;
  lLine: Integer;
  lOffset: Integer;
  lText: string;
  lValue: TJSONValue;
begin
  lBytes := TFile.ReadAllBytes(aPath);
  if (Length(lBytes) > 0) and not TEncoding.UTF8.IsBufferValid(@lBytes[0], Length(lBytes)) then
    raise EConvertError.CreateFmt('Invalid UTF-8 in %s.', [aPath]);
  // Unlike FixInsight TXT, normalized JSONL is strict UTF-8; a BOM is not silently removed.
  lText := TEncoding.UTF8.GetString(lBytes);
  lBytes := nil;
  Result := TJSONArray.Create;
  try
    lOffset := 1;
    lLine := 0;
    while lOffset <= Length(lText) do
    begin
      Inc(lLine);
      lEnd := lOffset;
      while (lEnd <= Length(lText)) and not CharInSet(lText[lEnd], [#10, #13]) do
        Inc(lEnd);
      lFirst := lOffset;
      lLast := lEnd - 1;
      while (lFirst <= lLast) and IsLineWhitespace(lText[lFirst]) do
        Inc(lFirst);
      while (lLast >= lFirst) and IsLineWhitespace(lText[lLast]) do
        Dec(lLast);
      if lFirst <= lLast then
      begin
        // The RTL JSON byte reader consumes a BOM even when parsing a decoded string.
        if lText[lFirst] = #$FEFF then
          raise EConvertError.CreateFmt('Malformed JSONL in %s at line %d: unexpected BOM.', [aPath, lLine]);
        if not HasValidJsonLexemes(lText, lFirst, lLast) then
          raise EConvertError.CreateFmt('Malformed JSONL in %s at line %d.', [aPath, lLine]);
        lValue := TJSONObject.ParseJSONValue(Copy(lText, lFirst, lLast - lFirst + 1), True);
        if lValue = nil then
          raise EConvertError.CreateFmt('Malformed JSONL in %s at line %d.', [aPath, lLine]);
        try
          Result.AddElement(CopyJsonDictionaryValue(lValue));
        finally
          lValue.Free;
        end;
      end;
      lOffset := lEnd + 1;
      if (lEnd < Length(lText)) and (lText[lEnd] = #13) and (lText[lEnd + 1] = #10) then
        Inc(lOffset);
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
