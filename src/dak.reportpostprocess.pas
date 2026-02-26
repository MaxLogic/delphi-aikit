unit Dak.ReportPostProcess;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.IOUtils,
  System.Variants,
  Xml.XMLDoc,
  Xml.XMLIntf,
  maxLogic.StrUtils,
  Dak.Types;

type
  EReportPostProcess = class(Exception);

function ParseList(const aValue: string): TArray<string>;
function BuildRuleIdSet(const aRuleIds: string): THashSet<string>;
function HasAnyReportFilters(const aExcludePathMasks: string; const aIgnoreRuleIds: string): Boolean;

function TryPostProcessFixInsightReport(const aReportPath: string; aFormat: TReportFormat;
  const aExcludePathMasks: string; const aIgnoreRuleIds: string; out aError: string): Boolean;

implementation

function ParseList(const aValue: string): TArray<string>;
var
  lRaw: TArray<string>;
  lList: TList<string>;
  lPart: string;
  lItem: string;
begin
  Result := nil;
  if aValue = '' then
    Exit;

  lRaw := aValue.Split([';']);
  lList := TList<string>.Create;
  try
    for lPart in lRaw do
    begin
      lItem := Trim(lPart);
      if lItem <> '' then
        lList.Add(lItem);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function NormalizeSlashes(const aValue: string): string;
begin
  Result := aValue.Replace('/', '\', [rfReplaceAll]);
end;

function TryNormalizeRuleId(const aValue: string; out aRuleId: string): Boolean;
var
  i: Integer;
  s: string;
begin
  aRuleId := '';
  s := Trim(aValue);
  if s = '' then
    Exit(False);
  s := UpperCase(s);
  if not (s[1] in ['W', 'C', 'O']) then
    Exit(False);
  if Length(s) < 2 then
    Exit(False);
  for i := 2 to Length(s) do
    if not CharInSet(s[i], ['0'..'9']) then
      Exit(False);
  aRuleId := s;
  Result := True;
end;

function BuildRuleIdSet(const aRuleIds: string): THashSet<string>;
var
  lItem: string;
  lNorm: string;
begin
  Result := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  for lItem in ParseList(aRuleIds) do
    if TryNormalizeRuleId(lItem, lNorm) then
      Result.Add(lNorm);
end;

function HasAnyReportFilters(const aExcludePathMasks: string; const aIgnoreRuleIds: string): Boolean;
begin
  Result := (Trim(aExcludePathMasks) <> '') or (Trim(aIgnoreRuleIds) <> '');
end;

function MatchesMaskCI(const aText: string; const aMask: string): Boolean;
var
  t: string;
  m: string;
  i: Integer;
  j: Integer;
  star: Integer;
  lMark: Integer;
begin
  // Simple wildcard matcher: '*' and '?', case-insensitive.
  t := UpperCase(aText);
  m := UpperCase(aMask);

  i := 1;
  j := 1;
  star := 0;
  lMark := 0;
  while i <= Length(t) do
  begin
    if (j <= Length(m)) and ((m[j] = '?') or (m[j] = t[i])) then
    begin
      Inc(i);
      Inc(j);
      Continue;
    end;

    if (j <= Length(m)) and (m[j] = '*') then
    begin
      star := j;
      Inc(j);
      lMark := i;
      Continue;
    end;

    if star <> 0 then
    begin
      j := star + 1;
      Inc(lMark);
      i := lMark;
      Continue;
    end;

    Exit(False);
  end;

  while (j <= Length(m)) and (m[j] = '*') do
    Inc(j);

  Result := j > Length(m);
end;

function PathMatchesAnyMask(const aPath: string; const aMasks: TArray<string>): Boolean;
var
  lMask: string;
  lPath: string;
begin
  Result := False;
  if Length(aMasks) = 0 then
    Exit(False);
  lPath := NormalizeSlashes(aPath);
  for lMask in aMasks do
    if MatchesMaskCI(lPath, NormalizeSlashes(lMask)) then
      Exit(True);
end;

function TryPostProcessFixInsightText(const aReportPath: string; const aExcludeMasks: TArray<string>;
  const aIgnoreRuleSet: THashSet<string>; out aError: string): Boolean;
var
  lLines: TArray<string>;
  lOut: TList<string>;
  lCurHeader: string;
  lCurFile: string;
  lCurExcluded: Boolean;
  lCurLines: TList<string>;
  lLine: string;

  procedure FlushCurrent;
  var
    lItem: string;
  begin
    if lCurHeader = '' then
      Exit;
    if (not lCurExcluded) and (lCurLines.Count > 0) then
    begin
      lOut.Add(lCurHeader);
      for lItem in lCurLines do
        lOut.Add(lItem);
    end;
    lCurHeader := '';
    lCurFile := '';
    lCurExcluded := False;
    lCurLines.Clear;
  end;

  function TryGetRuleIdFromLine(const aLine: string; out aRuleId: string): Boolean;
  var
    lTrim: string;
    lToken: string;
    lPos: Integer;
  begin
    aRuleId := '';
    lTrim := aLine.TrimLeft;
    if lTrim = '' then
      Exit(False);
    lPos := Pos(' ', lTrim);
    if lPos = 0 then
      lToken := lTrim
    else
      lToken := Copy(lTrim, 1, lPos - 1);
    Result := TryNormalizeRuleId(lToken, aRuleId);
  end;

  function IsFileHeader(const aLine: string): Boolean;
  begin
    Result := aLine.StartsWith('File:', True);
  end;

begin
  Result := False;
  aError := '';
  try
    lLines := TFile.ReadAllLines(aReportPath, TEncoding.UTF8);
    lOut := TList<string>.Create;
    try
      lCurHeader := '';
      lCurFile := '';
      lCurExcluded := False;
      lCurLines := TList<string>.Create;
      try
        for lLine in lLines do
        begin
          if IsFileHeader(lLine) then
          begin
            FlushCurrent;
            lCurHeader := lLine;
            lCurFile := Trim(Copy(lLine, Length('File:') + 1, MaxInt));
            lCurExcluded := PathMatchesAnyMask(lCurFile, aExcludeMasks);
            Continue;
          end;

          if lCurHeader <> '' then
          begin
            if lCurExcluded then
              Continue;

            if aIgnoreRuleSet <> nil then
            begin
              var lRuleId: string;
              if TryGetRuleIdFromLine(lLine, lRuleId) and aIgnoreRuleSet.Contains(lRuleId) then
                Continue;
            end;
            lCurLines.Add(lLine);
          end else
            lOut.Add(lLine);
        end;
        FlushCurrent;

        TFile.WriteAllLines(aReportPath, lOut.ToArray, TEncoding.UTF8);
      finally
        lCurLines.Free;
      end;
      Result := True;
    finally
      lOut.Free;
    end;
  except
    on E: Exception do
    begin
      aError := E.Message;
      Exit(False);
    end;
  end;
end;

function TryDetectCsvDelimiter(const aLine: string; out aDelimiter: Char): Boolean;
var
  i: Integer;
  inQuotes: Boolean;
  commaCount: Integer;
  semiCount: Integer;
begin
  aDelimiter := ',';
  commaCount := 0;
  semiCount := 0;
  inQuotes := False;
  for i := 1 to Length(aLine) do
  begin
    if aLine[i] = '"' then
      inQuotes := not inQuotes
    else if not inQuotes then
    begin
      if aLine[i] = ',' then
        Inc(commaCount)
      else if aLine[i] = ';' then
        Inc(semiCount);
    end;
  end;

  if (commaCount = 0) and (semiCount = 0) then
    Exit(False);

  if semiCount > commaCount then
    aDelimiter := ';'
  else
    aDelimiter := ',';
  Result := True;
end;

function ParseCsvRow(const aLine: string; aDelimiter: Char): TArray<string>;
var
  lList: TList<string>;
  sb: TStringBuilder;
  i: Integer;
  inQuotes: Boolean;
begin
  lList := TList<string>.Create;
  try
    sb := TStringBuilder.Create;
    try
      inQuotes := False;
      i := 1;
      while i <= Length(aLine) do
      begin
        if aLine[i] = '"' then
        begin
          if inQuotes and (i < Length(aLine)) and (aLine[i + 1] = '"') then
          begin
            sb.Append('"');
            Inc(i, 2);
            Continue;
          end;
          inQuotes := not inQuotes;
          Inc(i);
          Continue;
        end;

        if (not inQuotes) and (aLine[i] = aDelimiter) then
        begin
          lList.Add(sb.ToString);
          sb.Clear;
          Inc(i);
          Continue;
        end;

        sb.Append(aLine[i]);
        Inc(i);
      end;
      lList.Add(sb.ToString);
    finally
      sb.Free;
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function FindColumnIndex(const aHeaders: TArray<string>; const aNeedle: array of string): Integer;
var
  i: Integer;
  lNeedle: string;
  lHeader: string;
begin
  Result := -1;
  for i := 0 to High(aHeaders) do
  begin
    lHeader := Trim(aHeaders[i]);
    for lNeedle in aNeedle do
      if SameText(lHeader, lNeedle) then
        Exit(i);
  end;
end;

function LooksLikePath(const aValue: string): Boolean;
var
  s: string;
begin
  s := aValue;
  if s = '' then
    Exit(False);
  s := NormalizeSlashes(s);
  Result :=
    (Pos(':\', s) > 0) or
    (s.Contains('\') and (s.EndsWith('.pas', True) or s.EndsWith('.dpr', True) or s.EndsWith('.dpk', True)));
end;

function TryPostProcessFixInsightCsv(const aReportPath: string; const aExcludeMasks: TArray<string>;
  const aIgnoreRuleSet: THashSet<string>; out aError: string): Boolean;
var
  lLines: TArray<string>;
  lDelim: Char;
  lAltDelim: Char;
  lIdxRule: Integer;
  lIdxFile: Integer;
  lAltIdxRule: Integer;
  lAltIdxFile: Integer;
  lOut: TList<string>;
  i: Integer;
  lRow: TArray<string>;
  lFile: string;
  lRule: string;
  lRawRule: string;
  lNormRule: string;
  lHasHeader: Boolean;
  lAltHasHeader: Boolean;
  lFirstRow: TArray<string>;
  lAltFirstRow: TArray<string>;

  function LooksLikeHeader(const aFields: TArray<string>): Boolean;
  var
    lField: string;
  begin
    Result := False;
    for lField in aFields do
      if SameText(Trim(lField), 'File') or SameText(Trim(lField), 'Filename') or SameText(Trim(lField), 'Rule') or
        SameText(Trim(lField), 'RuleId') or SameText(Trim(lField), 'RuleID') or SameText(Trim(lField), 'Line') then
        Exit(True);
  end;

  procedure DetectIndexesFromRow(const aFields: TArray<string>; var aRuleIdx: Integer; var aFileIdx: Integer);
  var
    j: Integer;
    lTmp: string;
  begin
    if (aRuleIdx >= 0) and (aFileIdx >= 0) then
      Exit;
    for j := 0 to High(aFields) do
    begin
      if (aRuleIdx < 0) and TryNormalizeRuleId(aFields[j], lTmp) then
        aRuleIdx := j;
      if (aFileIdx < 0) and LooksLikePath(aFields[j]) then
        aFileIdx := j;
    end;
  end;

  function IsUsableLayout(const aDelimiter: Char; const aHasHeader: Boolean; const aRuleIdx: Integer;
    const aFileIdx: Integer): Boolean;
  var
    lSampleIndex: Integer;
    lSampleRow: TArray<string>;
    lRuleId: string;
  begin
    Result := False;
    lSampleIndex := Ord(aHasHeader);
    if (lSampleIndex < 0) or (lSampleIndex > High(lLines)) then
      Exit(False);

    lSampleRow := ParseCsvRow(lLines[lSampleIndex], aDelimiter);
    if (aRuleIdx < 0) or (aRuleIdx > High(lSampleRow)) then
      Exit(False);
    if (aFileIdx < 0) or (aFileIdx > High(lSampleRow)) then
      Exit(False);
    if not LooksLikePath(lSampleRow[aFileIdx]) then
      Exit(False);
    Result := TryNormalizeRuleId(lSampleRow[aRuleIdx], lRuleId);
  end;
begin
  Result := False;
  aError := '';
  try
    lLines := TFile.ReadAllLines(aReportPath, TEncoding.UTF8);
    if Length(lLines) = 0 then
      Exit(True);

    if not TryDetectCsvDelimiter(lLines[0], lDelim) then
      lDelim := ',';

    lFirstRow := ParseCsvRow(lLines[0], lDelim);
    lHasHeader := LooksLikeHeader(lFirstRow);

    lIdxRule := -1;
    lIdxFile := -1;
    if lHasHeader then
    begin
      lIdxRule := FindColumnIndex(lFirstRow, ['Rule', 'RuleId', 'RuleID', 'ID', 'Id', 'Code']);
      lIdxFile := FindColumnIndex(lFirstRow, ['File', 'FileName', 'Filename', 'Unit', 'Path']);
    end else
    begin
      // FixInsightCL CSV output (2023.x) is headerless and stable:
      // "<file>",<line>,<col>,<rule>,<message>
      lIdxFile := 0;
      lIdxRule := 3;
      DetectIndexesFromRow(lFirstRow, lIdxRule, lIdxFile);
    end;

    if not IsUsableLayout(lDelim, lHasHeader, lIdxRule, lIdxFile) then
    begin
      if lDelim = ',' then
        lAltDelim := ';'
      else
        lAltDelim := ',';

      lAltFirstRow := ParseCsvRow(lLines[0], lAltDelim);
      lAltHasHeader := LooksLikeHeader(lAltFirstRow);
      lAltIdxRule := -1;
      lAltIdxFile := -1;
      if lAltHasHeader then
      begin
        lAltIdxRule := FindColumnIndex(lAltFirstRow, ['Rule', 'RuleId', 'RuleID', 'ID', 'Id', 'Code']);
        lAltIdxFile := FindColumnIndex(lAltFirstRow, ['File', 'FileName', 'Filename', 'Unit', 'Path']);
      end else
      begin
        lAltIdxFile := 0;
        lAltIdxRule := 3;
        DetectIndexesFromRow(lAltFirstRow, lAltIdxRule, lAltIdxFile);
      end;

      if IsUsableLayout(lAltDelim, lAltHasHeader, lAltIdxRule, lAltIdxFile) then
      begin
        lDelim := lAltDelim;
        lHasHeader := lAltHasHeader;
        lIdxRule := lAltIdxRule;
        lIdxFile := lAltIdxFile;
      end;
    end;

    lOut := TList<string>.Create;
    try
      if lHasHeader then
        lOut.Add(lLines[0]);

      for i := Ord(lHasHeader) to High(lLines) do
      begin
        if lLines[i] = '' then
          Continue;

        lRow := ParseCsvRow(lLines[i], lDelim);
        lFile := '';
        lRule := '';
        if (lIdxFile >= 0) and (lIdxFile <= High(lRow)) then
          lFile := lRow[lIdxFile];
        if (lIdxRule >= 0) and (lIdxRule <= High(lRow)) then
        begin
          lRawRule := lRow[lIdxRule];
          if not TryNormalizeRuleId(lRawRule, lNormRule) then
            lNormRule := lRawRule;
          lRule := lNormRule;
        end
        else
        begin
          DetectIndexesFromRow(lRow, lIdxRule, lIdxFile);
          if (lFile = '') and (lIdxFile >= 0) and (lIdxFile <= High(lRow)) then
            lFile := lRow[lIdxFile];
          if (lRule = '') and (lIdxRule >= 0) and (lIdxRule <= High(lRow)) then
          begin
            lRawRule := lRow[lIdxRule];
            if not TryNormalizeRuleId(lRawRule, lNormRule) then
              lNormRule := lRawRule;
            lRule := lNormRule;
          end;
        end;

        if (lFile <> '') and PathMatchesAnyMask(lFile, aExcludeMasks) then
          Continue;
        if (lRule <> '') and (aIgnoreRuleSet <> nil) and aIgnoreRuleSet.Contains(lRule) then
          Continue;

        // Preserve original row formatting/quoting.
        lOut.Add(lLines[i]);
      end;

      TFile.WriteAllLines(aReportPath, lOut.ToArray, TEncoding.UTF8);
    finally
      lOut.Free;
    end;

    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

function TryPostProcessFixInsightXml(const aReportPath: string; const aExcludeMasks: TArray<string>;
  const aIgnoreRuleSet: THashSet<string>; out aError: string): Boolean;
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  iFile: Integer;
  iMsg: Integer;
  lFileNode: IXMLNode;
  lMsgNode: IXMLNode;
  lFileName: string;
  lExcludeFile: Boolean;
  lRuleId: string;
  lRawRuleId: string;
  lNormRuleId: string;
begin
  Result := False;
  aError := '';
  try
    lDoc := TXMLDocument.Create(nil);
    lDoc.Options := [doNodeAutoCreate, doNodeAutoIndent];
    lDoc.LoadFromFile(aReportPath);
    lDoc.Active := True;

    lRoot := lDoc.DocumentElement;
    if lRoot <> nil then
      for iFile := lRoot.ChildNodes.Count - 1 downto 0 do
      begin
        lFileNode := lRoot.ChildNodes[iFile];
        if (lFileNode = nil) or (lFileNode.NodeType <> ntElement) or (not SameText(lFileNode.NodeName, 'file')) then
          Continue;

        lFileName := '';
        if lFileNode.HasAttribute('name') then
          lFileName := VarToStr(lFileNode.Attributes['name']);
        lExcludeFile := (lFileName <> '') and PathMatchesAnyMask(lFileName, aExcludeMasks);

        for iMsg := lFileNode.ChildNodes.Count - 1 downto 0 do
        begin
          lMsgNode := lFileNode.ChildNodes[iMsg];
          if (lMsgNode = nil) or (lMsgNode.NodeType <> ntElement) or (not SameText(lMsgNode.NodeName, 'message')) then
            Continue;

          lRuleId := '';
          if lMsgNode.HasAttribute('id') then
          begin
            lRawRuleId := VarToStr(lMsgNode.Attributes['id']);
            if TryNormalizeRuleId(lRawRuleId, lNormRuleId) then
              lRuleId := lNormRuleId
            else
              lRuleId := lRawRuleId;
          end;

          if lExcludeFile or ((lRuleId <> '') and (aIgnoreRuleSet <> nil) and aIgnoreRuleSet.Contains(lRuleId)) then
            lFileNode.ChildNodes.Remove(lMsgNode);
        end;

        if lFileNode.ChildNodes.Count = 0 then
          lRoot.ChildNodes.Remove(lFileNode);
      end;

    lDoc.SaveToFile(aReportPath);

    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

function TryPostProcessFixInsightReport(const aReportPath: string; aFormat: TReportFormat;
  const aExcludePathMasks: string; const aIgnoreRuleIds: string; out aError: string): Boolean;
var
  lExcludeMasks: TArray<string>;
  lIgnoreSet: THashSet<string>;
begin
  Result := False;
  aError := '';
  if not FileExists(aReportPath) then
  begin
    aError := 'Report not found: ' + aReportPath;
    Exit(False);
  end;

  lExcludeMasks := ParseList(aExcludePathMasks);
  lIgnoreSet := nil;
  try
    if Trim(aIgnoreRuleIds) <> '' then
      lIgnoreSet := BuildRuleIdSet(aIgnoreRuleIds);

    case aFormat of
      TReportFormat.rfText: Result := TryPostProcessFixInsightText(aReportPath, lExcludeMasks, lIgnoreSet, aError);
      TReportFormat.rfXml: Result := TryPostProcessFixInsightXml(aReportPath, lExcludeMasks, lIgnoreSet, aError);
      TReportFormat.rfCsv: Result := TryPostProcessFixInsightCsv(aReportPath, lExcludeMasks, lIgnoreSet, aError);
    else
      aError := 'Unsupported report format.';
      Exit(False);
    end;
  finally
    lIgnoreSet.Free;
  end;
end;

end.
