unit Dak.PascalAnalyzer.Artifacts;

interface

function TryFindPalReportRoot(const aOutputRoot: string; out aReportRoot: string; out aError: string): Boolean;
function TryGeneratePalArtifacts(const aReportRoot: string; const aOutRoot: string; out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.JSON, System.StrUtils, System.SysUtils,
  System.Types, System.Variants,
  Xml.omnixmldom, Xml.XMLDoc, Xml.XMLIntf, Xml.xmldom,
  maxLogic.StrUtils;

const
  SPalFindingsFileName = 'pal-findings.md';
  SPalFindingsJsonlFileName = 'pal-findings.jsonl';
  SPalHotspotsFileName = 'pal-hotspots.md';
  SPalWarningsFileName = 'Warnings.xml';
  SPalStrongWarningsFileName = 'Strong Warnings.xml';
  SPalOptimizationFileName = 'Optimization.xml';
  SPalExceptionFileName = 'Exception.xml';
  SPalComplexityFileName = 'Complexity.xml';
  SPalModuleTotalsFileName = 'Module Totals.xml';
  SPalStatusFileName = 'Status.xml';

type
  TPalFinding = record
    Severity: string;
    Report: string;
    Section: string;
    ModuleName: string;
    Line: Integer;
    Message: string;
    ItemId: string;
    ItemKind: string;
  end;

  TComplexityEntry = record
    Name: string;
    Dp: Integer;
    LinesOfCode: Integer;
    IsRoutine: Boolean;
  end;

  THotspotEntry = record
    Name: string;
    Score: Integer;
    LinesOfCode: Integer;
  end;

const
  SPalSeverityWarning = 'warning';
  SPalSeverityStrongWarning = 'strong-warning';
  SPalSeverityOptimization = 'optimization';
  SPalSeverityException = 'exception';
  CHotspotTopN = 20;

function NormalizeLineText(const aValue: string): string;
begin
  Result := aValue.Replace(#13, ' ', [rfReplaceAll]).Replace(#10, ' ', [rfReplaceAll]).Replace('|', '/', [rfReplaceAll]);
  Result := Trim(Result);
end;

function ChildText(const aNode: IXMLNode; const aName: string): string;
var
  lChild: IXMLNode;
begin
  Result := '';
  if aNode = nil then
    Exit;
  lChild := aNode.ChildNodes.FindNode(aName);
  if lChild = nil then
    Exit;
  Result := Trim(lChild.Text);
end;

function AttrText(const aNode: IXMLNode; const aName: string): string;
var
  lValue: Variant;
begin
  Result := '';
  if (aNode = nil) or (not aNode.HasAttribute(aName)) then
    Exit;
  lValue := aNode.Attributes[aName];
  Result := VarToStr(lValue);
end;

function TryParseLocMod(const aText: string; out aModule: string; out aLine: Integer): Boolean;
var
  lText: string;
  lPos: Integer;
  lLineText: string;
begin
  aModule := '';
  aLine := 0;
  lText := Trim(aText);
  if lText = '' then
    Exit(False);

  lPos := LastDelimiter('(', lText);
  if (lPos > 0) and lText.EndsWith(')') then
  begin
    lLineText := Trim(Copy(lText, lPos + 1, Length(lText) - lPos - 1));
    if TryStrToInt(lLineText, aLine) then
    begin
      aModule := Trim(Copy(lText, 1, lPos - 1));
      Exit(aModule <> '');
    end;
  end;

  aModule := lText;
  Result := aModule <> '';
end;

function ChooseMessage(const aItemId, aName, aKind: string): string;
begin
  if aItemId <> '' then
    Exit(aItemId);
  if aName <> '' then
    Exit(aName);
  Result := aKind;
end;

function BuildFindingKey(const aFinding: TPalFinding): string;
begin
  Result := UpperCase(aFinding.Severity + '|' + aFinding.Report + '|' + aFinding.Section + '|' +
    aFinding.ModuleName + '|' + aFinding.Line.ToString + '|' + aFinding.Message + '|' + aFinding.ItemId + '|' +
    aFinding.ItemKind);
end;

procedure AddFindingRecord(const aSeverity, aReport, aSection, aModule: string; const aLine: Integer;
  const aMessage, aItemId, aItemKind: string; aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lFinding: TPalFinding;
  lKey: string;
begin
  if aModule = '' then
    Exit;

  lFinding.Severity := NormalizeLineText(aSeverity);
  lFinding.Report := NormalizeLineText(aReport);
  lFinding.Section := NormalizeLineText(aSection);
  lFinding.ModuleName := NormalizeLineText(aModule);
  lFinding.Line := aLine;
  lFinding.Message := NormalizeLineText(aMessage);
  lFinding.ItemId := NormalizeLineText(aItemId);
  lFinding.ItemKind := NormalizeLineText(aItemKind);

  if lFinding.Message = '' then
    lFinding.Message := '-';

  lKey := BuildFindingKey(lFinding);
  if (lKey <> '') and aSeen.Add(lKey) then
    aFindings.Add(lFinding);
end;

procedure AddFindingFromLoc(const aSeverity, aReport, aSection, aName, aItemId, aItemKind: string; const aLoc: IXMLNode;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lLocMod: string;
  lLocLine: string;
  lLocKind: string;
  lModule: string;
  lLine: Integer;
  lLineFromMod: Integer;
  lMessage: string;
  lKind: string;
begin
  lLocMod := NormalizeLineText(ChildText(aLoc, 'locmod'));
  lLocLine := NormalizeLineText(ChildText(aLoc, 'locline'));
  lLocKind := NormalizeLineText(ChildText(aLoc, 'kind'));
  lLine := StrToIntDef(lLocLine, 0);
  lModule := '';

  if lLocMod <> '' then
  begin
    if TryParseLocMod(lLocMod, lModule, lLineFromMod) and (lLine = 0) then
      lLine := lLineFromMod;
  end;

  lMessage := ChooseMessage(aItemId, aName, aItemKind);
  if (lMessage = '') and (lLocKind <> '') then
    lMessage := lLocKind;

  lKind := aItemKind;
  if (lKind = '') and (lLocKind <> '') then
    lKind := lLocKind;

  AddFindingRecord(aSeverity, aReport, aSection, lModule, lLine, lMessage, aItemId, lKind, aFindings, aSeen);
end;

procedure AddFindingFromLocMod(const aSeverity, aReport, aSection, aName, aItemId, aItemKind, aLocMod: string;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lModule: string;
  lLine: Integer;
  lMessage: string;
begin
  if not TryParseLocMod(aLocMod, lModule, lLine) then
    Exit;
  lMessage := ChooseMessage(aItemId, aName, aItemKind);
  AddFindingRecord(aSeverity, aReport, aSection, lModule, lLine, lMessage, aItemId, aItemKind, aFindings, aSeen);
end;

procedure ParseItemNode(const aItem: IXMLNode; const aSeverity, aReport, aSection, aName: string;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lItemId: string;
  lItemKind: string;
  lLocMod: string;
  lNode: IXMLNode;
  lHasLoc: Boolean;
  i: Integer;
begin
  lItemId := NormalizeLineText(ChildText(aItem, 'id'));
  lItemKind := NormalizeLineText(ChildText(aItem, 'kind'));
  lLocMod := NormalizeLineText(ChildText(aItem, 'locmod'));

  lHasLoc := False;
  for i := 0 to aItem.ChildNodes.Count - 1 do
  begin
    lNode := aItem.ChildNodes[i];
    if SameText(lNode.NodeName, 'loc') then
    begin
      lHasLoc := True;
      AddFindingFromLoc(aSeverity, aReport, aSection, aName, lItemId, lItemKind, lNode, aFindings, aSeen);
    end;
  end;

  if (not lHasLoc) and (lLocMod <> '') then
    AddFindingFromLocMod(aSeverity, aReport, aSection, aName, lItemId, lItemKind, lLocMod, aFindings, aSeen);
end;

procedure ParseSectionNode(const aSection: IXMLNode; const aSeverity, aReport: string;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lSectionName: string;
  lCurrentName: string;
  lNode: IXMLNode;
  i: Integer;
begin
  lSectionName := NormalizeLineText(AttrText(aSection, 'name'));
  lCurrentName := '';

  for i := 0 to aSection.ChildNodes.Count - 1 do
  begin
    lNode := aSection.ChildNodes[i];
    if SameText(lNode.NodeName, 'name') then
      lCurrentName := NormalizeLineText(lNode.Text)
    else if SameText(lNode.NodeName, 'loc') then
      AddFindingFromLoc(aSeverity, aReport, lSectionName, lCurrentName, '', '', lNode, aFindings, aSeen)
    else if SameText(lNode.NodeName, 'item') then
      ParseItemNode(lNode, aSeverity, aReport, lSectionName, lCurrentName, aFindings, aSeen);
  end;
end;

function TryLoadXml(const aPath: string; out aDoc: IXMLDocument; out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  aDoc := nil;
  if not FileExists(aPath) then
  begin
    aError := 'PAL XML not found: ' + aPath;
    Exit(False);
  end;
  try
    DefaultDOMVendor := sOmniXmlVendor;
    aDoc := TXMLDocument.Create(nil);
    aDoc.Options := [doNodeAutoIndent];
    aDoc.LoadFromFile(aPath);
    aDoc.Active := True;
    if (aDoc.DocumentElement = nil) then
    begin
      aError := 'PAL XML has no document element: ' + aPath;
      Exit(False);
    end;
    Result := True;
  except
    on E: Exception do
    begin
      aError := 'PAL XML load failed: ' + aPath + ' (' + E.Message + ')';
      aDoc := nil;
    end;
  end;
end;

procedure ParseFindingReport(const aPath, aReportName, aSeverity: string; aFindings: TList<TPalFinding>;
  aSeen: THashSet<string>; out aParsed: Boolean; out aError: string);
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  lNode: IXMLNode;
  i: Integer;
begin
  aParsed := False;
  aError := '';
  if not FileExists(aPath) then
    Exit;
  if not TryLoadXml(aPath, lDoc, aError) then
    Exit;
  lRoot := lDoc.DocumentElement;
  for i := 0 to lRoot.ChildNodes.Count - 1 do
  begin
    lNode := lRoot.ChildNodes[i];
    if SameText(lNode.NodeName, 'section') then
      ParseSectionNode(lNode, aSeverity, aReportName, aFindings, aSeen);
  end;
  aParsed := True;
end;

procedure CollectExceptionCalls(const aNode: IXMLNode; const aSeverity, aReport, aSection: string;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lName: string;
  lLocMod: string;
  lLocLine: string;
  lModule: string;
  lParsedModule: string;
  lLine: Integer;
  lLineFromMod: Integer;
  lChild: IXMLNode;
  i: Integer;
begin
  if SameText(aNode.NodeName, 'called_by') then
  begin
    lName := NormalizeLineText(ChildText(aNode, 'name'));
    lLocMod := NormalizeLineText(ChildText(aNode, 'locmod'));
    lLocLine := NormalizeLineText(ChildText(aNode, 'locline'));
    lLine := StrToIntDef(lLocLine, 0);
    lModule := '';
    if lLocMod <> '' then
    begin
      if TryParseLocMod(lLocMod, lParsedModule, lLineFromMod) then
      begin
        lModule := lParsedModule;
        if lLine = 0 then
          lLine := lLineFromMod;
      end;
    end;
    AddFindingRecord(aSeverity, aReport, aSection, lModule, lLine, lName, '', '', aFindings, aSeen);
  end;

  for i := 0 to aNode.ChildNodes.Count - 1 do
  begin
    lChild := aNode.ChildNodes[i];
    if SameText(lChild.NodeName, 'called_by') then
      CollectExceptionCalls(lChild, aSeverity, aReport, aSection, aFindings, aSeen)
    else if SameText(lChild.NodeName, 'branch') then
      CollectExceptionCalls(lChild, aSeverity, aReport, aSection, aFindings, aSeen)
    else if SameText(lChild.NodeName, 'section') then
      CollectExceptionCalls(lChild, aSeverity, aReport, aSection, aFindings, aSeen);
  end;
end;

procedure ParseExceptionReport(const aPath, aReportName, aSeverity: string; aFindings: TList<TPalFinding>;
  aSeen: THashSet<string>; out aParsed: Boolean; out aError: string);
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  lNode: IXMLNode;
  lSectionName: string;
  i: Integer;
begin
  aParsed := False;
  aError := '';
  if not FileExists(aPath) then
    Exit;
  if not TryLoadXml(aPath, lDoc, aError) then
    Exit;
  lRoot := lDoc.DocumentElement;
  for i := 0 to lRoot.ChildNodes.Count - 1 do
  begin
    lNode := lRoot.ChildNodes[i];
    if SameText(lNode.NodeName, 'section') then
    begin
      lSectionName := NormalizeLineText(AttrText(lNode, 'name'));
      CollectExceptionCalls(lNode, aSeverity, aReportName, lSectionName, aFindings, aSeen);
    end;
  end;
  aParsed := True;
end;

function SplitComplexityName(const aRaw: string; out aName: string; out aTag: string): Boolean;
var
  lPos: Integer;
  lTag: string;
  lChar: Char;
begin
  aName := Trim(aRaw);
  aTag := '';
  Result := False;
  if aName = '' then
    Exit(False);
  lPos := LastDelimiter('(', aName);
  if (lPos > 0) and aName.EndsWith(')') then
  begin
    lTag := Trim(Copy(aName, lPos + 1, Length(aName) - lPos - 1));
    if lTag <> '' then
    begin
      for lChar in lTag do
        if not CharInSet(lChar, ['A'..'Z', 'a'..'z']) then
          Exit(False);
      aTag := lTag;
      aName := Trim(Copy(aName, 1, lPos - 1));
      Result := True;
    end;
  end;
end;

function IsAggregateName(const aName: string): Boolean;
var
  lName: string;
begin
  lName := Trim(aName);
  if lName = '' then
    Exit(True);
  if SameText(lName, 'Overall') then
    Exit(True);
  if lName.StartsWith('\') then
    Exit(True);
  if Pos('\...\', lName) > 0 then
    Exit(True);
  Result := False;
end;

function TryLoadComplexityEntries(const aPath: string; out aEntries: TArray<TComplexityEntry>; out aError: string): Boolean;
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  lSection: IXMLNode;
  lNode: IXMLNode;
  lList: TList<TComplexityEntry>;
  lEntry: TComplexityEntry;
  lName: string;
  lTag: string;
  i: Integer;
begin
  Result := False;
  aError := '';
  aEntries := nil;
  if not FileExists(aPath) then
    Exit(False);
  if not TryLoadXml(aPath, lDoc, aError) then
    Exit(False);

  lRoot := lDoc.DocumentElement;
  lSection := nil;
  for i := 0 to lRoot.ChildNodes.Count - 1 do
  begin
    lNode := lRoot.ChildNodes[i];
    if SameText(lNode.NodeName, 'section') then
    begin
      if SameText(AttrText(lNode, 'name'), 'Complexity per module/subprogram') then
      begin
        lSection := lNode;
        Break;
      end;
    end;
  end;
  if lSection = nil then
  begin
    aError := 'Complexity report section not found: ' + aPath;
    Exit(False);
  end;

  lList := TList<TComplexityEntry>.Create;
  try
    for i := 0 to lSection.ChildNodes.Count - 1 do
    begin
      lNode := lSection.ChildNodes[i];
      if not SameText(lNode.NodeName, 'module_or_subprogram') then
        Continue;
      lName := NormalizeLineText(ChildText(lNode, 'name'));
      if lName = '' then
        Continue;
      lEntry := Default(TComplexityEntry);
      lEntry.Dp := StrToIntDef(ChildText(lNode, 'dp'), 0);
      lEntry.LinesOfCode := StrToIntDef(ChildText(lNode, 'lines_of_code'), 0);
      if SplitComplexityName(lName, lEntry.Name, lTag) then
        lEntry.IsRoutine := True
      else
      begin
        lEntry.Name := lName;
        lEntry.IsRoutine := False;
      end;
      lList.Add(lEntry);
    end;
    aEntries := lList.ToArray;
    Result := True;
  finally
    lList.Free;
  end;
end;

function TryLoadModuleLines(const aPath: string; out aLines: TDictionary<string, Integer>; out aError: string): Boolean;
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  lSection: IXMLNode;
  lModule: IXMLNode;
  lItem: IXMLNode;
  lName: string;
  lKind: string;
  lTotal: Integer;
  i: Integer;
  j: Integer;
begin
  Result := False;
  aError := '';
  aLines := nil;
  if not FileExists(aPath) then
    Exit(False);
  if not TryLoadXml(aPath, lDoc, aError) then
    Exit(False);

  lRoot := lDoc.DocumentElement;
  lSection := nil;
  for i := 0 to lRoot.ChildNodes.Count - 1 do
  begin
    lModule := lRoot.ChildNodes[i];
    if SameText(lModule.NodeName, 'section') then
    begin
      lSection := lModule;
      Break;
    end;
  end;
  if lSection = nil then
  begin
    aError := 'Module Totals report section not found: ' + aPath;
    Exit(False);
  end;

  aLines := TDictionary<string, Integer>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for i := 0 to lSection.ChildNodes.Count - 1 do
    begin
      lModule := lSection.ChildNodes[i];
      if not SameText(lModule.NodeName, 'module') then
        Continue;
      lName := NormalizeLineText(ChildText(lModule, 'name'));
      if lName = '' then
        Continue;
      if IsAggregateName(lName) then
        Continue;
      lTotal := 0;
      for j := 0 to lModule.ChildNodes.Count - 1 do
      begin
        lItem := lModule.ChildNodes[j];
        if not SameText(lItem.NodeName, 'item') then
          Continue;
        lKind := NormalizeLineText(ChildText(lItem, 'kind'));
        if SameText(lKind, 'lines') then
        begin
          lTotal := StrToIntDef(ChildText(lItem, 'total'), 0);
          Break;
        end;
      end;
      if lTotal > 0 then
        aLines.AddOrSetValue(lName, lTotal);
    end;
    Result := True;
  except
    on E: Exception do
    begin
      aError := 'Module Totals parse failed: ' + aPath + ' (' + E.Message + ')';
      aLines.Free;
      aLines := nil;
      Result := False;
    end;
  end;
end;

function CompareHotspot(const aLeft, aRight: THotspotEntry): Integer;
begin
  if aLeft.Score > aRight.Score then
    Exit(-1);
  if aLeft.Score < aRight.Score then
    Exit(1);
  Result := CompareText(aLeft.Name, aRight.Name);
end;

function TakeTopHotspots(const aItems: TArray<THotspotEntry>): TArray<THotspotEntry>;
var
  lCount: Integer;
begin
  lCount := Length(aItems);
  if lCount > CHotspotTopN then
    lCount := CHotspotTopN;
  Result := Copy(aItems, 0, lCount);
end;

procedure SortHotspots(var aItems: TArray<THotspotEntry>);
begin
  TArray.Sort<THotspotEntry>(aItems, TComparer<THotspotEntry>.Construct(CompareHotspot));
end;

function WritePalFindingsMd(const aFindings: TList<TPalFinding>; const aPath: string; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lFinding: TPalFinding;
  lUtf8: TUTF8Encoding;
begin
  Result := False;
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    for lFinding in aFindings do
    begin
      lBuilder.Append(lFinding.Severity);
      lBuilder.Append(' | ');
      lBuilder.Append(lFinding.Report);
      lBuilder.Append(' | ');
      lBuilder.Append(lFinding.Section);
      lBuilder.Append(' | ');
      lBuilder.Append(lFinding.ModuleName);
      lBuilder.Append(':');
      lBuilder.Append(lFinding.Line.ToString);
      lBuilder.Append(' | ');
      lBuilder.Append(lFinding.Message);
      lBuilder.AppendLine;
    end;
    lUtf8 := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(aPath, lBuilder.ToString, lUtf8);
    finally
      lUtf8.Free;
    end;
    Result := True;
  finally
    lBuilder.Free;
  end;
end;

function WritePalFindingsJsonl(const aFindings: TList<TPalFinding>; const aPath: string; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lFinding: TPalFinding;
  lJson: TJSONObject;
  lUtf8: TUTF8Encoding;
begin
  Result := False;
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    for lFinding in aFindings do
    begin
      lJson := TJSONObject.Create;
      try
        lJson.AddPair('severity', lFinding.Severity);
        lJson.AddPair('report', lFinding.Report);
        lJson.AddPair('section', lFinding.Section);
        lJson.AddPair('module', lFinding.ModuleName);
        lJson.AddPair('line', TJSONNumber.Create(lFinding.Line));
        lJson.AddPair('message', lFinding.Message);
        if lFinding.ItemId <> '' then
          lJson.AddPair('id', lFinding.ItemId);
        if lFinding.ItemKind <> '' then
          lJson.AddPair('kind', lFinding.ItemKind);
        lBuilder.Append(lJson.ToJSON);
      finally
        lJson.Free;
      end;
      lBuilder.AppendLine;
    end;
    lUtf8 := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(aPath, lBuilder.ToString, lUtf8);
    finally
      lUtf8.Free;
    end;
    Result := True;
  finally
    lBuilder.Free;
  end;
end;

function WritePalHotspotsMd(const aRoutineHotspots, aModuleHotspots, aModuleLineHotspots: TArray<THotspotEntry>;
  const aWarnings: TArray<string>; const aPath: string; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lItem: THotspotEntry;
  lUtf8: TUTF8Encoding;
  lWarning: string;
begin
  Result := False;
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('# PAL Hotspots (top 20)');
    lBuilder.AppendLine;
    lBuilder.AppendLine('## Routines by decision points');
    if Length(aRoutineHotspots) = 0 then
      lBuilder.AppendLine('- none')
    else
      for lItem in aRoutineHotspots do
        lBuilder.AppendLine(Format('dp=%d | loc=%d | %s', [lItem.Score, lItem.LinesOfCode, lItem.Name]));

    lBuilder.AppendLine;
    lBuilder.AppendLine('## Modules by decision points');
    if Length(aModuleHotspots) = 0 then
      lBuilder.AppendLine('- none')
    else
      for lItem in aModuleHotspots do
        lBuilder.AppendLine(Format('dp=%d | loc=%d | %s', [lItem.Score, lItem.LinesOfCode, lItem.Name]));

    lBuilder.AppendLine;
    lBuilder.AppendLine('## Modules by lines');
    if Length(aModuleLineHotspots) = 0 then
      lBuilder.AppendLine('- none')
    else
      for lItem in aModuleLineHotspots do
        lBuilder.AppendLine(Format('lines=%d | %s', [lItem.Score, lItem.Name]));

    if Length(aWarnings) > 0 then
    begin
      lBuilder.AppendLine;
      lBuilder.AppendLine('## Warnings');
      for lWarning in aWarnings do
        lBuilder.AppendLine('- ' + lWarning);
    end;

    lUtf8 := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(aPath, lBuilder.ToString, lUtf8);
    finally
      lUtf8.Free;
    end;
    Result := True;
  finally
    lBuilder.Free;
  end;
end;

function TryFindPalReportRoot(const aOutputRoot: string; out aReportRoot: string; out aError: string): Boolean;
var
  lRoot: string;
  lFiles: TStringDynArray;
  lPath: string;
begin
  Result := False;
  aError := '';
  aReportRoot := '';

  lRoot := Trim(aOutputRoot);
  if lRoot = '' then
  begin
    aError := 'PAL output root is empty.';
    Exit(False);
  end;
  lRoot := TPath.GetFullPath(lRoot);
  if not DirectoryExists(lRoot) then
  begin
    aError := 'PAL output root not found: ' + lRoot;
    Exit(False);
  end;

  lPath := TPath.Combine(lRoot, SPalStatusFileName);
  if FileExists(lPath) then
  begin
    aReportRoot := ExcludeTrailingPathDelimiter(lRoot);
    Exit(True);
  end;

  lFiles := TDirectory.GetFiles(lRoot, SPalStatusFileName, TSearchOption.soAllDirectories);
  if Length(lFiles) = 0 then
  begin
    aError := 'PAL report root not found under: ' + lRoot;
    Exit(False);
  end;

  aReportRoot := ExcludeTrailingPathDelimiter(ExtractFilePath(lFiles[0]));
  Result := True;
end;

function TryGeneratePalArtifacts(const aReportRoot: string; const aOutRoot: string; out aError: string): Boolean;
var
  lReportRoot: string;
  lOutRoot: string;
  lFindings: TList<TPalFinding>;
  lSeen: THashSet<string>;
  lHasFindingsSource: Boolean;
  lHasHotspotSource: Boolean;
  lError: string;
  lWarningsPath: string;
  lStrongPath: string;
  lOptimizationPath: string;
  lExceptionPath: string;
  lComplexityPath: string;
  lModuleTotalsPath: string;
  lParsed: Boolean;
  lEntries: TArray<TComplexityEntry>;
  lModuleLines: TDictionary<string, Integer>;
  lRoutineList: TList<THotspotEntry>;
  lModuleList: TList<THotspotEntry>;
  lModuleLineList: TList<THotspotEntry>;
  lHotspotWarnings: TList<string>;
  lRoutineArr: TArray<THotspotEntry>;
  lModuleArr: TArray<THotspotEntry>;
  lModuleLineArr: TArray<THotspotEntry>;
  lEntry: TComplexityEntry;
  lHotspot: THotspotEntry;
  lName: string;
begin
  Result := False;
  aError := '';
  lReportRoot := Trim(aReportRoot);
  if lReportRoot = '' then
  begin
    aError := 'PAL report root is empty.';
    Exit(False);
  end;
  lReportRoot := TPath.GetFullPath(lReportRoot);
  if not DirectoryExists(lReportRoot) then
  begin
    aError := 'PAL report root not found: ' + lReportRoot;
    Exit(False);
  end;

  lOutRoot := Trim(aOutRoot);
  if lOutRoot = '' then
    lOutRoot := lReportRoot;
  lOutRoot := TPath.GetFullPath(lOutRoot);
  if not DirectoryExists(lOutRoot) then
    TDirectory.CreateDirectory(lOutRoot);

  lWarningsPath := TPath.Combine(lReportRoot, SPalWarningsFileName);
  lStrongPath := TPath.Combine(lReportRoot, SPalStrongWarningsFileName);
  lOptimizationPath := TPath.Combine(lReportRoot, SPalOptimizationFileName);
  lExceptionPath := TPath.Combine(lReportRoot, SPalExceptionFileName);
  lComplexityPath := TPath.Combine(lReportRoot, SPalComplexityFileName);
  lModuleTotalsPath := TPath.Combine(lReportRoot, SPalModuleTotalsFileName);

  lFindings := TList<TPalFinding>.Create;
  lSeen := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    lHasFindingsSource := False;
    lParsed := False;
    if FileExists(lWarningsPath) then
    begin
      ParseFindingReport(lWarningsPath, SPalWarningsFileName, SPalSeverityWarning, lFindings, lSeen, lParsed, lError);
      lHasFindingsSource := lParsed;
      if lError <> '' then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    lParsed := False;
    if FileExists(lStrongPath) then
    begin
      ParseFindingReport(lStrongPath, SPalStrongWarningsFileName, SPalSeverityStrongWarning, lFindings, lSeen, lParsed,
        lError);
      lHasFindingsSource := lHasFindingsSource or lParsed;
      if lError <> '' then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    lParsed := False;
    if FileExists(lOptimizationPath) then
    begin
      ParseFindingReport(lOptimizationPath, SPalOptimizationFileName, SPalSeverityOptimization, lFindings, lSeen, lParsed,
        lError);
      lHasFindingsSource := lHasFindingsSource or lParsed;
      if lError <> '' then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    lParsed := False;
    if FileExists(lExceptionPath) then
    begin
      ParseExceptionReport(lExceptionPath, SPalExceptionFileName, SPalSeverityException, lFindings, lSeen, lParsed,
        lError);
      lHasFindingsSource := lHasFindingsSource or lParsed;
      if lError <> '' then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    lHasHotspotSource := FileExists(lComplexityPath) or FileExists(lModuleTotalsPath);

    if not (lHasFindingsSource or lHasHotspotSource) then
    begin
      aError := 'No PAL XML report files found under: ' + lReportRoot;
      Exit(False);
    end;

    if lHasFindingsSource then
    begin
      if not WritePalFindingsMd(lFindings, TPath.Combine(lOutRoot, SPalFindingsFileName), lError) then
      begin
        aError := lError;
        Exit(False);
      end;
      if not WritePalFindingsJsonl(lFindings, TPath.Combine(lOutRoot, SPalFindingsJsonlFileName), lError) then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    if lHasHotspotSource then
    begin
      lRoutineList := TList<THotspotEntry>.Create;
      lModuleList := TList<THotspotEntry>.Create;
      lModuleLineList := TList<THotspotEntry>.Create;
      lHotspotWarnings := TList<string>.Create;
      try
        if not TryLoadComplexityEntries(lComplexityPath, lEntries, lError) then
        begin
          if FileExists(lComplexityPath) and (lError <> '') then
            lHotspotWarnings.Add(SPalComplexityFileName + ': ' + lError);
          lEntries := nil;
        end;
        if not TryLoadModuleLines(lModuleTotalsPath, lModuleLines, lError) then
        begin
          if FileExists(lModuleTotalsPath) and (lError <> '') then
            lHotspotWarnings.Add(SPalModuleTotalsFileName + ': ' + lError);
          lModuleLines := nil;
        end;

        for lEntry in lEntries do
        begin
          if lEntry.IsRoutine then
          begin
            if lEntry.Dp <= 0 then
              Continue;
            lHotspot := Default(THotspotEntry);
            lHotspot.Name := lEntry.Name;
            lHotspot.Score := lEntry.Dp;
            lHotspot.LinesOfCode := lEntry.LinesOfCode;
            lRoutineList.Add(lHotspot);
          end else
          begin
            lName := lEntry.Name;
            if IsAggregateName(lName) then
              Continue;
            if lEntry.Dp <= 0 then
              Continue;
            lHotspot := Default(THotspotEntry);
            lHotspot.Name := lName;
            lHotspot.Score := lEntry.Dp;
            lHotspot.LinesOfCode := lEntry.LinesOfCode;
            lModuleList.Add(lHotspot);
          end;
        end;

        if lModuleLines <> nil then
          for lName in lModuleLines.Keys do
          begin
            lHotspot := Default(THotspotEntry);
            lHotspot.Name := lName;
            lHotspot.Score := lModuleLines[lName];
            lHotspot.LinesOfCode := lHotspot.Score;
            lModuleLineList.Add(lHotspot);
          end;

        lRoutineArr := lRoutineList.ToArray;
        lModuleArr := lModuleList.ToArray;
        lModuleLineArr := lModuleLineList.ToArray;

        SortHotspots(lRoutineArr);
        SortHotspots(lModuleArr);
        SortHotspots(lModuleLineArr);

        lRoutineArr := TakeTopHotspots(lRoutineArr);
        lModuleArr := TakeTopHotspots(lModuleArr);
        lModuleLineArr := TakeTopHotspots(lModuleLineArr);

        if not WritePalHotspotsMd(lRoutineArr, lModuleArr, lModuleLineArr,
          lHotspotWarnings.ToArray, TPath.Combine(lOutRoot, SPalHotspotsFileName), lError) then
        begin
          aError := lError;
          Exit(False);
        end;
      finally
        lRoutineList.Free;
        lModuleList.Free;
        lModuleLineList.Free;
        lHotspotWarnings.Free;
        lModuleLines.Free;
      end;
    end;
  finally
    lFindings.Free;
    lSeen.Free;
  end;

  Result := True;
end;


end.
