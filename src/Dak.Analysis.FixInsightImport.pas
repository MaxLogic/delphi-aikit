unit Dak.Analysis.FixInsightImport;

interface

uses
  System.JSON;

// Caller owns the array and its raw finding objects.
function LoadFixInsightFindings(const aPath: string): TJSONArray;
// write_fixinsight_normalized: turn the analyzer's own fixinsight.txt into the normalized
// fi-findings.jsonl and fi-findings.md the report stage reads. An empty report writes nothing,
// exactly as the reference leaves the directory alone.
procedure WriteFixInsightNormalized(const aFixInsightDir, aRepoRoot: string;
  const aBaseDirs: TArray<string>);

implementation

uses
  System.Character, System.Classes, System.IOUtils, System.RegularExpressions, System.SysUtils,
  Dak.Analysis.ReportBundle, Dak.Analysis.ReportWriters, Dak.Analysis.SourceResolution, Dak.Analysis.Text;

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

procedure WriteFixInsightNormalized(const aFixInsightDir, aRepoRoot: string;
  const aBaseDirs: TArray<string>);
var
  lFindings: TJSONArray;
  lItem: TJSONValue;
  lLines: TStringList;
  lLocation: string;
  lRaw: TJSONObject;
  lRecord: TJSONObject;
  lRecords: TJSONArray;
  lTextPath: string;
begin
  lTextPath := TPath.Combine(aFixInsightDir, 'fixinsight.txt');
  lFindings := LoadFixInsightFindings(lTextPath);
  try
    if lFindings.Count = 0 then
      Exit;
    lRecords := TJSONArray.Create;
    try
      lLines := TStringList.Create;
      try
        lLines.LineBreak := #10;
        for lItem in lFindings do
        begin
          lRaw := TJSONObject(lItem);
          // The member order is the reference's, because the JSONL rows are compared byte for byte.
          lRecord := TJSONObject.Create
            .AddPair('tool', 'FixInsight')
            .AddPair('code', JsonText(lRaw, 'code'))
            .AddPair('kind', JsonText(lRaw, 'kind'))
            .AddPair('file', AnalysisPosixNormPath(JsonText(lRaw, 'file').Replace('\', '/')))
            .AddPair('path', AnalysisNormalizedPathValue(JsonText(lRaw, 'file'), aRepoRoot, aBaseDirs));
          lRecord.AddPair('line', JsonCloneValue(lRaw.GetValue('line')));
          lRecord.AddPair('col', JsonCloneValue(lRaw.GetValue('col')));
          lRecord.AddPair('message', JsonText(lRaw, 'message'));
          lRecords.AddElement(lRecord);
          lLocation := JsonText(lRecord, 'path');
          if lLocation = '' then
            lLocation := JsonText(lRecord, 'file');
          if lLocation = '' then
            lLocation := '?';
          lLines.Add(Format('%s | %s:%s:%s | %s', [JsonText(lRecord, 'code'), lLocation,
            JsonText(lRecord, 'line'), JsonText(lRecord, 'col'), JsonText(lRecord, 'message')]));
        end;
        WriteAnalysisJsonLines(TPath.Combine(aFixInsightDir, 'fi-findings.jsonl'), lRecords);
        WriteAnalysisText(TPath.Combine(aFixInsightDir, 'fi-findings.md'),
          string.Join(#10, lLines.ToStringArray) + #10);
      finally
        lLines.Free;
      end;
    finally
      lRecords.Free;
    end;
  finally
    lFindings.Free;
  end;
end;

end.
