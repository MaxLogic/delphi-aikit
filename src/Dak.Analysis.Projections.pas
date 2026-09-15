unit Dak.Analysis.Projections;

{
ClassPattern and MaskPattern adapt CPython 3.13 Lib/fnmatch.py translation.
Copyright (c) 2001-2024 Python Software Foundation; All Rights Reserved.
Changes: Delphi translation, explicit PCRE start/end anchors, caller-owned
compiled patterns, Windows-independent slash normalization. License follows.
PYTHON SOFTWARE FOUNDATION LICENSE VERSION 2
--------------------------------------------

1. This LICENSE AGREEMENT is between the Python Software Foundation
("PSF"), and the Individual or Organization ("Licensee") accessing and
otherwise using this software ("Python") in source or binary form and
its associated documentation.

2. Subject to the terms and conditions of this License Agreement, PSF hereby
grants Licensee a nonexclusive, royalty-free, world-wide license to reproduce,
analyze, test, perform and/or display publicly, prepare derivative works,
distribute, and otherwise use Python alone or in any derivative version,
provided, however, that PSF's License Agreement and PSF's notice of copyright,
i.e., "Copyright (c) 2001-2024 Python Software Foundation; All Rights Reserved"
are retained in Python alone or in any derivative version prepared by Licensee.

3. In the event Licensee prepares a derivative work that is based on
or incorporates Python or any part thereof, and wants to make
the derivative work available to others as provided herein, then
Licensee hereby agrees to include in any such work a brief summary of
the changes made to Python.

4. PSF is making Python available to Licensee on an "AS IS"
basis.  PSF MAKES NO REPRESENTATIONS OR WARRANTIES, EXPRESS OR
IMPLIED.  BY WAY OF EXAMPLE, BUT NOT LIMITATION, PSF MAKES NO AND
DISCLAIMS ANY REPRESENTATION OR WARRANTY OF MERCHANTABILITY OR FITNESS
FOR ANY PARTICULAR PURPOSE OR THAT THE USE OF PYTHON WILL NOT
INFRINGE ANY THIRD PARTY RIGHTS.

5. PSF SHALL NOT BE LIABLE TO LICENSEE OR ANY OTHER USERS OF PYTHON
FOR ANY INCIDENTAL, SPECIAL, OR CONSEQUENTIAL DAMAGES OR LOSS AS
A RESULT OF MODIFYING, DISTRIBUTING, OR OTHERWISE USING PYTHON,
OR ANY DERIVATIVE THEREOF, EVEN IF ADVISED OF THE POSSIBILITY THEREOF.

6. This License Agreement will automatically terminate upon a material
breach of its terms and conditions.

7. Nothing in this License Agreement shall be deemed to create any
relationship of agency, partnership, or joint venture between PSF and
Licensee.  This License Agreement does not grant permission to use PSF
trademarks or trade name in a trademark sense to endorse or promote
products or services of Licensee, or any third party.

8. By copying, installing or otherwise using Python, Licensee
agrees to be bound by the terms and conditions of this License
Agreement.
}


interface

uses
  System.JSON;

// Arrays remain caller-owned. Nil denotes an absent report, unlike a present empty array.
procedure ApplyAnalysisReportProjections(aFixInsight, aPal: TJSONArray; aPolicy: TJSONObject;
  const aPathMasks: TArray<string>; const aPalVersion, aPalReportRoot: string; aPalRequested: Boolean);

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.Hash, System.IOUtils, System.RegularExpressions, System.SysUtils, System.Variants,
  Xml.omnixmldom, Xml.XMLDoc, Xml.xmldom, Xml.XMLIntf,
  AutoFree,
  Dak.Analysis.NumericText, Dak.Analysis.UnicodeText;

type
  TStringMap = TDictionary<string, string>;
  TCodeMap = TObjectDictionary<string, TList<string>>;

const
  cAliasReports: array[0..2] of string = ('Warnings', 'Strong Warnings', 'Optimization');
  cAliasSections: array[0..2] of string = ('Set before passed as out parameter',
    'Possible bad typecast (for objects: consider using "as")', 'Parameter is "var", can be changed to "out"');
  cAliasCodes: array[0..2] of string = ('WARN54', 'STWA6', 'OPTI8');
  cMetricPhrases: array[0..9] of string = ('method length', 'routine length', 'parameter count',
    'nesting depth', 'cyclomatic complexity', 'too many parameters', 'too many statements',
    'deeply nested', 'long methods', 'long routines');

// Python str.lower()/upper()/strip() semantics from pinned Unicode 15.1 tables,
// independent of the Windows locale and the RTL's Unicode 15.0 data.
function LowerText(const aText: string): string;
begin
  Result := TUnicodeText.Lower(aText);
end;

function UpperText(const aText: string): string;
begin
  Result := TUnicodeText.Upper(aText);
end;

function StripText(const aText: string): string;
begin
  Result := TUnicodeText.Strip(aText);
end;

function JsonTruthy(aValue: TJSONValue): Boolean;
begin
  if (aValue = nil) or (aValue is TJSONNull) then
    Exit(False);
  if aValue is TJSONBool then
    Exit(TJSONBool(aValue).AsBoolean);
  if aValue is TJSONArray then
    Exit(TJSONArray(aValue).Count <> 0);
  if aValue is TJSONObject then
    Exit(TJSONObject(aValue).Count <> 0);
  if aValue is TJSONNumber then
    // Python truthiness of the parsed number: integer zero or a float rounding to zero is False.
    Exit(not TNumericText.IsZero(aValue.Value));
  Result := aValue.Value <> '';
end;

function QuotedText(const aText: string): string;
var
  g: TGarbos;
  i: Integer;
  c: Cardinal;
  lQuote: Char;
  lBuilder: TStringBuilder;
begin
  lQuote := '''';
  if aText.Contains('''') and not aText.Contains('"') then
    lQuote := '"';
  GC(lBuilder, TStringBuilder.Create, g);
  lBuilder.Append(lQuote);
  i := 1;
  while i <= Length(aText) do
  begin
    c := TUnicodeText.ReadCodePoint(aText, i);
    if (c = Ord(lQuote)) or (c = Ord('\')) then
      lBuilder.Append('\').Append(Char(c))
    else if c = 9 then
      lBuilder.Append('\t')
    else if c = 10 then
      lBuilder.Append('\n')
    else if c = 13 then
      lBuilder.Append('\r')
    else if not TUnicodeText.IsPrintable(c) then
    begin
      if c <= $FF then
        lBuilder.Append('\x').Append(IntToHex(c, 2).ToLowerInvariant)
      else if c <= $FFFF then
        lBuilder.Append('\u').Append(IntToHex(c, 4).ToLowerInvariant)
      else
        lBuilder.Append('\U').Append(IntToHex(c, 8).ToLowerInvariant);
    end else
      lBuilder.Append(TUnicodeText.FromCodePoint(c));
  end;
  Result := lBuilder.Append(lQuote).ToString;
end;

function ValueText(aValue: TJSONValue; aQuoteString: Boolean): string;
var
  g: TGarbos;
  i: Integer;
  lPair: TJSONPair;
  lBuilder: TStringBuilder;
begin
  if (aValue = nil) or (aValue is TJSONNull) then
    Exit('None');
  if aValue is TJSONBool then
  begin
    if TJSONBool(aValue).AsBoolean then
      Exit('True');
    Exit('False');
  end;
  if (aValue is TJSONArray) or (aValue is TJSONObject) then
  begin
    GC(lBuilder, TStringBuilder.Create, g);
    if aValue is TJSONArray then
    begin
      lBuilder.Append('[');
      for i := 0 to TJSONArray(aValue).Count - 1 do
      begin
        if i > 0 then
          lBuilder.Append(', ');
        lBuilder.Append(ValueText(TJSONArray(aValue).Items[i], True));
      end;
      lBuilder.Append(']');
    end else begin
      lBuilder.Append('{');
      for i := 0 to TJSONObject(aValue).Count - 1 do
      begin
        if i > 0 then
          lBuilder.Append(', ');
        lPair := TJSONObject(aValue).Pairs[i];
        lBuilder.Append(QuotedText(lPair.JsonString.Value)).Append(': ');
        lBuilder.Append(ValueText(lPair.JsonValue, True));
      end;
      lBuilder.Append('}');
    end;
    Exit(lBuilder.ToString);
  end;
  if aValue is TJSONNumber then
    // str(json.loads(token)): the original token stays on the row; only derived text is Python-shaped.
    Exit(TNumericText.PythonText(aValue.Value));
  if aQuoteString and (aValue is TJSONString) then
    Exit(QuotedText(aValue.Value));
  Result := aValue.Value;
end;

function FieldText(aObject: TJSONObject; const aName: string; const aFallback: string = ''): string;
var
  lValue: TJSONValue;
begin
  lValue := aObject.GetValue(aName);
  if JsonTruthy(lValue) then
    Result := ValueText(lValue, False)
  else
    Result := aFallback;
end;

procedure PutValue(aObject: TJSONObject; const aName: string; aValue: TJSONValue);
var
  lPair: TJSONPair;
begin
  lPair := aObject.Get(aName);
  if lPair <> nil then
    // The setter frees the old value while retaining the member's insertion position.
    lPair.JsonValue := aValue
  else
    aObject.AddPair(aName, aValue);
end;

procedure PutText(aObject: TJSONObject; const aName, aValue: string);
begin
  PutValue(aObject, aName, TJSONString.Create(aValue));
end;

function Slug(const aText: string): string;
var
  c: Char;
  s: string;
  lDash: Boolean;
begin
  Result := '';
  s := LowerText(StripText(aText));
  lDash := False;
  for c in s do
    if CharInSet(c, ['a'..'z', '0'..'9']) then
    begin
      Result := Result + c;
      lDash := False;
    end else if not lDash then
    begin
      Result := Result + '-';
      lDash := True;
    end;
  Result := Result.Trim(['-']);
  if Result = '' then
    Result := 'unknown'
  else
    Result := Copy(Result, 1, 64);
end;

function ReportStem(const aReport: string): string;
var
  i, j: Integer;
  s: string;
begin
  s := aReport.Replace('\', '/');
  i := LastDelimiter('/', s);
  s := Copy(s, i + 1, MaxInt);
  j := LastDelimiter('.', s);
  // posixpath.splitext preserves a basename consisting of leading dots.
  i := 1;
  while (i < j) and (s[i] = '.') do
    Inc(i);
  if (j > 0) and (i < j) then
    s := Copy(s, 1, j - 1);
  Result := s;
end;

function ReportName(aRow: TJSONObject): string;
var
  s: string;
begin
  Result := ReportStem(StripText(FieldText(aRow, 'report')));
  if Result <> '' then
    Exit;
  s := LowerText(StripText(FieldText(aRow, 'severity')));
  if s = 'warning' then
    Result := 'Warnings'
  else if s = 'strong-warning' then
    Result := 'Strong Warnings'
  else if s = 'optimization' then
    Result := 'Optimization'
  else
    Result := 'Unknown Report';
end;

function CanonicalRule(const aReport, aSection: string): string;
begin
  Result := 'PAL.' + Slug(aReport) + '.' + Slug(aSection) + '-' +
    Copy(THashSHA2.GetHashString(aReport + #0 + aSection), 1, 16);
end;

function NativeCode(const aReport, aSection, aVersion: string): string;
var
  i: Integer;
begin
  Result := '';
  if (aVersion <> '9.21.3') and (aVersion <> '9.21.3.0') then
    Exit;
  for i := Low(cAliasCodes) to High(cAliasCodes) do
    if (Slug(aReport) = Slug(cAliasReports[i])) and (aSection = cAliasSections[i]) then
      Exit(cAliasCodes[i]);
end;

function ClassPattern(const aMask: string; aFirst, aLast: Integer): string;
var
  g: TGarbos;
  i, j, k: Integer;
  lChunks: TList<string>;
  s, lChunk: string;
begin
  s := Copy(aMask, aFirst, aLast - aFirst + 1);
  if not s.Contains('-') then
    s := s.Replace('\', '\\')
  else begin
    GC(lChunks, TList<string>.Create, g);
    i := aFirst;
    k := i + 1;
    if aMask[i] = '!' then
      Inc(k);
    while k <= aLast do
    begin
      while (k <= aLast) and (aMask[k] <> '-') do
        Inc(k);
      if k > aLast then
        Break;
      lChunks.Add(Copy(aMask, i, k - i));
      i := k + 1;
      Inc(k, 3);
    end;
    lChunk := Copy(aMask, i, aLast - i + 1);
    if lChunk <> '' then
      lChunks.Add(lChunk)
    else
      lChunks[lChunks.Count - 1] := lChunks[lChunks.Count - 1] + '-';
    for k := lChunks.Count - 1 downto 1 do
    begin
      s := lChunks[k - 1];
      lChunk := lChunks[k];
      if s[Length(s)] > lChunk[1] then
      begin
        lChunks[k - 1] := Copy(s, 1, Length(s) - 1) + Copy(lChunk, 2, MaxInt);
        lChunks.Delete(k);
      end;
    end;
    s := '';
    for j := 0 to lChunks.Count - 1 do
    begin
      if j > 0 then
        s := s + '-';
      s := s + lChunks[j].Replace('\', '\\').Replace('-', '\-');
    end;
  end;
  s := s.Replace('&', '\&').Replace('~', '\~').Replace('|', '\|');
  if s = '' then
    Exit('(?!)');
  if s = '!' then
    Exit('.');
  if s[1] = '!' then
    s := '^' + Copy(s, 2, MaxInt)
  else if CharInSet(s[1], ['^', '[']) then
    s := '\' + s;
  Result := '[' + s + ']';
end;

function MaskPattern(const aMask: string): string;
var
  g: TGarbos;
  c: Char;
  i, j: Integer;
  lParts: TList<string>;
  s, lFixed: string;
begin
  GC(lParts, TList<string>.Create, g);
  s := LowerText(aMask.Replace('/', '\'));
  i := 1;
  while i <= Length(s) do
  begin
    c := s[i];
    Inc(i);
    if c = '*' then
    begin
      if (lParts.Count = 0) or (lParts.Last <> '*') then
        lParts.Add('*');
    end else if c = '?' then
      lParts.Add('.')
    else if c = '[' then
    begin
      j := i;
      if (j <= Length(s)) and (s[j] = '!') then
        Inc(j);
      if (j <= Length(s)) and (s[j] = ']') then
        Inc(j);
      while (j <= Length(s)) and (s[j] <> ']') do
        Inc(j);
      if j > Length(s) then
        lParts.Add('\[')
      else begin
        lParts.Add(ClassPattern(s, i, j - 1));
        i := j + 1;
      end;
    end else
      lParts.Add(TRegEx.Escape(c));
  end;
  Result := '\A(?s:';
  i := 0;
  while (i < lParts.Count) and (lParts[i] <> '*') do
  begin
    Result := Result + lParts[i];
    Inc(i);
  end;
  while i < lParts.Count do
  begin
    Inc(i);
    lFixed := '';
    while (i < lParts.Count) and (lParts[i] <> '*') do
    begin
      lFixed := lFixed + lParts[i];
      Inc(i);
    end;
    if i = lParts.Count then
      Result := Result + '.*' + lFixed
    else
      Result := Result + '(?>.*?' + lFixed + ')';
  end;
  // PCRE \z is the strict end-of-string anchor corresponding to Python \Z.
  Result := Result + ')\z';
end;

function IgnorePolicy(const aReason, aValue: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('disposition', 'ignored');
  Result.AddPair('reason', aReason);
  Result.AddPair('value', aValue);
end;

function PolicyObject(aRow: TJSONObject): TJSONObject;
var
  lValue: TJSONValue;
begin
  lValue := aRow.GetValue('report_policy');
  if lValue is TJSONObject then
    Result := TJSONObject(lValue)
  else
    Result := nil;
end;

procedure ApplyMasks(aRows: TJSONArray; const aMasks: TArray<string>; const aPatterns: TArray<TRegEx>);
var
  i: Integer;
  lItem: TJSONValue;
  lRow, lPolicy: TJSONObject;
  s: string;
begin
  if aRows = nil then
    Exit;
  for lItem in aRows do
  begin
    lRow := lItem as TJSONObject;
    lPolicy := PolicyObject(lRow);
    if (lPolicy <> nil) and (FieldText(lPolicy, 'reason') = 'path_mask') then
      lRow.RemovePair('report_policy').Free;
    s := StripText(FieldText(lRow, 'path', FieldText(lRow, 'file')));
    if s = '' then
      Continue;
    s := LowerText(s.Replace('/', '\'));
    for i := 0 to High(aMasks) do
      if aPatterns[i].IsMatch(s) then
      begin
        PutValue(lRow, 'report_policy', IgnorePolicy('path_mask', aMasks[i]));
        Break;
      end;
  end;
end;

function TryReadCatalogXml(const aPath: string; out aDocument: IXMLDocument): Boolean;
var
  lXml: TXMLDocument;
begin
  Result := False;
  lXml := TXMLDocument.Create(nil);
  aDocument := lXml;
  lXml.DOMVendor := GetDOMVendor(sOmniXmlVendor);
  try
    aDocument.LoadFromFile(aPath);
    Result := (aDocument.DocumentElement <> nil) and (aDocument.DocumentElement.LocalName = 'report');
  except
    // The reference ignores malformed/unreadable catalog files, retaining other valid reports.
    on EDOMParseError do Exit;
    on EXMLDocError do Exit;
    on DOMException do Exit;
    on EStreamError do Exit;
    on EInOutError do Exit;
  end;
end;

procedure LoadCatalog(const aRoot: string; aRules: TStringMap);
var
  g: TGarbos;
  i: Integer;
  lDocument: IXMLDocument;
  lFiles: TArray<string>;
  lNode: IXMLNode;
  lPending: TStack<IXMLNode>;
  lPath, lSection, lCanonical: string;
begin
  if not TDirectory.Exists(aRoot) then
    Exit;
  lFiles := TDirectory.GetFiles(aRoot, '*.xml', TSearchOption.soAllDirectories);
  TArray.Sort<string>(lFiles, TStringComparer.Ordinal);
  GC(lPending, TStack<IXMLNode>.Create, g);
  for lPath in lFiles do
  begin
    if not TryReadCatalogXml(lPath, lDocument) then
      Continue;
    lPending.Push(lDocument.DocumentElement);
    while lPending.Count > 0 do
    begin
      lNode := lPending.Pop;
      if (lNode.LocalName = 'section') and lNode.HasAttribute('name') then
      begin
        lSection := StripText(VarToStr(lNode.Attributes['name']));
        if lSection <> '' then
        begin
          lCanonical := CanonicalRule(ReportStem(StripText(TPath.GetFileName(lPath))), lSection);
          aRules.AddOrSetValue(LowerText(lCanonical), lCanonical);
        end;
      end;
      for i := lNode.ChildNodes.Count - 1 downto 0 do
        lPending.Push(lNode.ChildNodes[i]);
    end;
  end;
end;

procedure AddCode(aCodes: TCodeMap; const aCode, aCanonical: string);
var
  lRules: TList<string>;
begin
  if aCode = '' then
    Exit;
  if not aCodes.TryGetValue(aCode, lRules) then
  begin
    lRules := TList<string>.Create;
    aCodes.Add(aCode, lRules);
  end;
  if not lRules.Contains(aCanonical) then
    lRules.Add(aCanonical);
end;

function SortedText(const aValues: TArray<string>): string;
var
  lValues: TArray<string>;
begin
  lValues := Copy(aValues);
  TArray.Sort<string>(lValues, TStringComparer.Ordinal);
  Result := string.Join(', ', lValues);
  if Result = '' then
    Result := '<none>';
end;

procedure ResolveIgnoredRules(aPal: TJSONArray; aPolicy: TJSONObject; const aVersion, aRoot: string;
  aResolved: TStringMap);
var
  g: TGarbos;
  i: Integer;
  lRules: TStringMap;
  lCodes: TCodeMap;
  lMatches: TList<string>;
  lUnmatched, lAmbiguous: TList<string>;
  lItem, lRequests: TJSONValue;
  lRow: TJSONObject;
  lReport, lSection, lCanonical, lCode, lRequested, lDetails: string;
begin
  GC(lRules, TStringMap.Create(TStringComparer.Ordinal), g);
  GC(lCodes, TCodeMap.Create([TDictionaryOwnership.doOwnsValues], TStringComparer.Ordinal), g);
  GC(lUnmatched, TList<string>.Create, g);
  GC(lAmbiguous, TList<string>.Create, g);
  LoadCatalog(aRoot, lRules);
  if (aVersion = '9.21.3') or (aVersion = '9.21.3.0') then
    for i := Low(cAliasCodes) to High(cAliasCodes) do
    begin
      lCanonical := CanonicalRule(cAliasReports[i], cAliasSections[i]);
      lRules.AddOrSetValue(LowerText(lCanonical), lCanonical);
      AddCode(lCodes, cAliasCodes[i], lCanonical);
    end;
  for lItem in aPal do
  begin
    lRow := lItem as TJSONObject;
    lReport := ReportName(lRow);
    lSection := StripText(FieldText(lRow, 'section'));
    lCanonical := CanonicalRule(lReport, lSection);
    lCode := NativeCode(lReport, lSection, aVersion);
    lRules.AddOrSetValue(LowerText(lCanonical), lCanonical);
    AddCode(lCodes, lCode, lCanonical);
  end;
  lRequests := aPolicy.GetValue('pal_ignore_rules');
  if lRequests is TJSONArray then
    for lItem in TJSONArray(lRequests) do
    begin
      lRequested := StripText(ValueText(lItem, False));
      if lRules.TryGetValue(LowerText(lRequested), lCanonical) then
        aResolved.AddOrSetValue(LowerText(lCanonical), lRequested)
      else if lCodes.TryGetValue(UpperText(lRequested), lMatches) then
      begin
        if lMatches.Count = 1 then
          aResolved.AddOrSetValue(LowerText(lMatches[0]), lRequested)
        else
          lAmbiguous.Add(lRequested);
      end else
        lUnmatched.Add(lRequested);
    end;
  if (lUnmatched.Count = 0) and (lAmbiguous.Count = 0) then
    Exit;
  lDetails := '';
  if lUnmatched.Count > 0 then
    lDetails := 'unmatched: ' + string.Join(', ', lUnmatched.ToArray);
  if lAmbiguous.Count > 0 then
  begin
    if lDetails <> '' then
      lDetails := lDetails + '; ';
    lDetails := lDetails + 'ambiguous: ' + string.Join(', ', lAmbiguous.ToArray);
  end;
  raise EConvertError.Create('Invalid Pascal Analyzer ignore rule(s) (' + lDetails +
    '). Available canonical rules: ' + SortedText(lRules.Values.ToArray) +
    '. Verified native codes: ' + SortedText(lCodes.Keys.ToArray));
end;

procedure ReadPolicySet(aPolicy: TJSONObject; const aName: string; aValues: TStringMap; aCaseMode: Integer);
var
  lValue, lItem: TJSONValue;
  s: string;
begin
  lValue := aPolicy.GetValue(aName);
  if not (lValue is TJSONArray) then
    Exit;
  for lItem in TJSONArray(lValue) do
  begin
    s := ValueText(lItem, False);
    if aCaseMode <> 0 then
      s := StripText(s);
    if aCaseMode < 0 then
      s := LowerText(s)
    else if aCaseMode > 0 then
      s := UpperText(s);
    aValues.AddOrSetValue(s, '');
  end;
end;

function IsMetric(aRow: TJSONObject): Boolean;
var
  s, lPhrase: string;
begin
  s := LowerText(StripText(FieldText(aRow, 'section')));
  for lPhrase in cMetricPhrases do
    if s.Contains(lPhrase) then
      Exit(True);
  Result := False;
end;

procedure ProjectRows(aRows: TJSONArray; const aVersion: string;
  aOwnership, aMetrics, aFiIgnore, aPalIgnore: TStringMap);
var
  lItem: TJSONValue;
  lRow, lPolicy: TJSONObject;
  lCode, lReport, lSection, lRule, lNative, lReason, lMatched, lOwner, lProjection: string;
begin
  if aRows = nil then
    Exit;
  for lItem in aRows do
  begin
    lRow := lItem as TJSONObject;
    lCode := UpperText(StripText(FieldText(lRow, 'code')));
    if lCode <> '' then
      lRule := 'FI.' + lCode
    else begin
      lReport := ReportName(lRow);
      lSection := StripText(FieldText(lRow, 'section'));
      lRule := CanonicalRule(lReport, lSection);
    end;
    PutText(lRow, 'normalized_rule', lRule);
    if lCode = '' then
    begin
      lNative := NativeCode(lReport, lSection, aVersion);
      if lNative <> '' then
        PutText(lRow, 'pal_code', lNative)
      else
        lRow.RemovePair('pal_code').Free;
    end;
    lPolicy := PolicyObject(lRow);
    if lPolicy <> nil then
    begin
      lReason := FieldText(lPolicy, 'reason');
      if (lReason = 'fixinsight_ignore') or (lReason = 'pal_rule_ignore') then
      begin
        lRow.RemovePair('report_policy').Free;
        lPolicy := nil;
      end;
    end;
    if (lCode <> '') and aFiIgnore.ContainsKey(lCode) and (lPolicy = nil) then
    begin
      lPolicy := IgnorePolicy('fixinsight_ignore', lCode);
      PutValue(lRow, 'report_policy', lPolicy);
    end;
    if (lCode = '') and aPalIgnore.TryGetValue(LowerText(lRule), lMatched) and (lPolicy = nil) then
    begin
      lPolicy := IgnorePolicy('pal_rule_ignore', lRule);
      lPolicy.AddPair('matched', lMatched);
      PutValue(lRow, 'report_policy', lPolicy);
    end;
    lOwner := FieldText(lRow, 'ownership', 'unknown');
    if lOwner = 'unknown' then
      lProjection := 'unknown'
    else if (lPolicy <> nil) and (FieldText(lPolicy, 'disposition') = 'ignored') then
      lProjection := 'ignored'
    else if not aOwnership.ContainsKey(lOwner) then
      lProjection := 'external'
    else if IsMetric(lRow) and not aMetrics.ContainsKey(LowerText(lRule)) then
      lProjection := 'advisory_metrics'
    else
      lProjection := 'actionable';
    PutText(lRow, 'report_projection', lProjection);
  end;
end;

procedure ApplyAnalysisReportProjections(aFixInsight, aPal: TJSONArray; aPolicy: TJSONObject;
  const aPathMasks: TArray<string>; const aPalVersion, aPalReportRoot: string; aPalRequested: Boolean);
var
  g: TGarbos;
  i: Integer;
  lPatterns: TArray<TRegEx>;
  lOwnership, lMetrics, lFiIgnore, lPalIgnore: TStringMap;
begin
  SetLength(lPatterns, Length(aPathMasks));
  for i := 0 to High(aPathMasks) do
    lPatterns[i] := TRegEx.Create(MaskPattern(aPathMasks[i]), []);
  ApplyMasks(aFixInsight, aPathMasks, lPatterns);
  ApplyMasks(aPal, aPathMasks, lPatterns);
  GC(lOwnership, TStringMap.Create(TStringComparer.Ordinal), g);
  GC(lMetrics, TStringMap.Create(TStringComparer.Ordinal), g);
  GC(lFiIgnore, TStringMap.Create(TStringComparer.Ordinal), g);
  GC(lPalIgnore, TStringMap.Create(TStringComparer.Ordinal), g);
  ReadPolicySet(aPolicy, 'gate_ownership', lOwnership, 0);
  ReadPolicySet(aPolicy, 'gate_metrics', lMetrics, -1);
  ReadPolicySet(aPolicy, 'fixinsight_ignore', lFiIgnore, 1);
  if (aPal <> nil) and not aPalRequested then
    while aPal.Count > 0 do
      aPal.Remove(aPal.Count - 1).Free;
  if aPalRequested and (aPal <> nil) then
    ResolveIgnoredRules(aPal, aPolicy, aPalVersion, aPalReportRoot, lPalIgnore);
  ProjectRows(aFixInsight, aPalVersion, lOwnership, lMetrics, lFiIgnore, lPalIgnore);
  ProjectRows(aPal, aPalVersion, lOwnership, lMetrics, lFiIgnore, lPalIgnore);
end;

end.
