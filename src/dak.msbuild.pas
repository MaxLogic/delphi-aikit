unit Dak.MsBuild;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.RegularExpressions, System.StrUtils,
  System.SysUtils, System.Variants,
  Xml.omnixmldom, Xml.XMLDoc, Xml.XMLIntf, Xml.xmldom,
  Dak.Diagnostics, Dak.MacroExpander, Dak.Messages;

type
  TPropertySetProc = procedure(const aName, aValue: string) of object;

  TMsBuildEvaluator = class
  private
    fImportStack: TStringList;
    fProps: TDictionary<string, string>;
    fEnvVars: TDictionary<string, string>;
    fDiagnostics: TDiagnostics;
    fOnPropertySet: TPropertySetProc;
    function EvaluateFileInternal(const aFileName: string; out aError: string): Boolean;
    function NormalizeConditionFunctions(const aCondition: string; const aBaseDir: string): string;
    function ResolveImportFilePath(const aImportProject: string; const aBaseDir: string): string;
    function TryEvaluateCondition(const aCondition: string; const aBaseDir: string; out aResult: Boolean;
      out aError: string): Boolean;
    procedure ApplyProperty(const aName, aValue: string);
  public
    constructor Create(const aProps, aEnvVars: TDictionary<string, string>; aDiagnostics: TDiagnostics);
    destructor Destroy; override;
    function EvaluateFile(const aFileName: string; out aError: string): Boolean;
    property OnPropertySet: TPropertySetProc read fOnPropertySet write fOnPropertySet;
  end;

implementation

type
  TTokenKind = (tkText, tkEqual, tkNotEqual, tkAnd, tkOr, tkLParen, tkRParen, tkUnknown, tkEof);

  TToken = record
    fKind: TTokenKind;
    fText: string;
  end;

  TConditionParser = class
  private
    fText: string;
    fPos: Integer;
    fToken: TToken;
    procedure NextToken;
    function ParseExpr(out aValue: Boolean): Boolean;
    function ParseTerm(out aValue: Boolean): Boolean;
    function ParseFactor(out aValue: Boolean): Boolean;
    function ParseComparison(out aValue: Boolean): Boolean;
  public
    constructor Create(const aText: string);
    function TryEvaluate(out aValue: Boolean; out aError: string): Boolean;
  end;

{ TConditionParser }

constructor TConditionParser.Create(const aText: string);
begin
  inherited Create;
  fText := aText;
  fPos := 1;
end;

procedure TConditionParser.NextToken;
var
  lStart: Integer;
  lCh: Char;
  lWord: string;
begin
  while (fPos <= Length(fText)) and (fText[fPos] <= ' ') do
    Inc(fPos);

  if fPos > Length(fText) then
  begin
    fToken.fKind := TTokenKind.tkEof;
    fToken.fText := '';
    Exit;
  end;

  lCh := fText[fPos];
  case lCh of
    '(':
      begin
        fToken.fKind := TTokenKind.tkLParen;
        fToken.fText := lCh;
        Inc(fPos);
      end;
    ')':
      begin
        fToken.fKind := TTokenKind.tkRParen;
        fToken.fText := lCh;
        Inc(fPos);
      end;
    '''':
      begin
        Inc(fPos);
        lStart := fPos;
        while (fPos <= Length(fText)) and (fText[fPos] <> '''') do
          Inc(fPos);
        if fPos > Length(fText) then
        begin
          fToken.fKind := TTokenKind.tkUnknown;
          fToken.fText := Copy(fText, lStart - 1, MaxInt);
          Exit;
        end;
        fToken.fKind := TTokenKind.tkText;
        fToken.fText := Copy(fText, lStart, fPos - lStart);
        if fPos <= Length(fText) then
          Inc(fPos);
      end;
    '=':
      begin
        if (fPos < Length(fText)) and (fText[fPos + 1] = '=') then
        begin
          fToken.fKind := TTokenKind.tkEqual;
          fToken.fText := '==';
          Inc(fPos, 2);
        end else
        begin
          fToken.fKind := TTokenKind.tkUnknown;
          fToken.fText := lCh;
          Inc(fPos);
        end;
      end;
    '!':
      begin
        if (fPos < Length(fText)) and (fText[fPos + 1] = '=') then
        begin
          fToken.fKind := TTokenKind.tkNotEqual;
          fToken.fText := '!=';
          Inc(fPos, 2);
        end else
        begin
          fToken.fKind := TTokenKind.tkUnknown;
          fToken.fText := lCh;
          Inc(fPos);
        end;
      end;
  else
    begin
      lStart := fPos;
      while (fPos <= Length(fText)) and (fText[fPos] > ' ') and (fText[fPos] <> '(') and
        (fText[fPos] <> ')') and (fText[fPos] <> '''') do
        Inc(fPos);
      lWord := Copy(fText, lStart, fPos - lStart);
      if SameText(lWord, 'and') then
        fToken.fKind := TTokenKind.tkAnd
      else if SameText(lWord, 'or') then
        fToken.fKind := TTokenKind.tkOr
      else
        fToken.fKind := TTokenKind.tkUnknown;
      fToken.fText := lWord;
    end;
  end;
end;

function TConditionParser.ParseComparison(out aValue: Boolean): Boolean;
var
  lLeft: string;
  lRight: string;
  lOp: TTokenKind;
begin
  Result := False;
  if fToken.fKind <> TTokenKind.tkText then
    Exit;
  lLeft := fToken.fText;
  NextToken;
  if (fToken.fKind <> TTokenKind.tkEqual) and (fToken.fKind <> TTokenKind.tkNotEqual) then
    Exit;
  lOp := fToken.fKind;
  NextToken;
  if fToken.fKind <> TTokenKind.tkText then
    Exit;
  lRight := fToken.fText;
  NextToken;
  if lOp = TTokenKind.tkEqual then
    aValue := SameText(lLeft, lRight)
  else
    aValue := not SameText(lLeft, lRight);
  Result := True;
end;

function TConditionParser.ParseFactor(out aValue: Boolean): Boolean;
begin
  Result := False;
  if fToken.fKind = TTokenKind.tkLParen then
  begin
    NextToken;
    if not ParseExpr(aValue) then
      Exit;
    if fToken.fKind <> TTokenKind.tkRParen then
      Exit;
    NextToken;
    Exit(True);
  end;
  Result := ParseComparison(aValue);
end;

function TConditionParser.ParseTerm(out aValue: Boolean): Boolean;
var
  lRight: Boolean;
begin
  Result := False;
  if not ParseFactor(aValue) then
    Exit;
  while fToken.fKind = TTokenKind.tkAnd do
  begin
    NextToken;
    if not ParseFactor(lRight) then
      Exit(False);
    aValue := aValue and lRight;
  end;
  Result := True;
end;

function TConditionParser.ParseExpr(out aValue: Boolean): Boolean;
var
  lRight: Boolean;
begin
  Result := False;
  if not ParseTerm(aValue) then
    Exit;
  while fToken.fKind = TTokenKind.tkOr do
  begin
    NextToken;
    if not ParseTerm(lRight) then
      Exit(False);
    aValue := aValue or lRight;
  end;
  Result := True;
end;

function TConditionParser.TryEvaluate(out aValue: Boolean; out aError: string): Boolean;
begin
  NextToken;
  if not ParseExpr(aValue) then
  begin
    aError := 'parse error';
    Exit(False);
  end;
  if fToken.fKind <> TTokenKind.tkEof then
  begin
    aError := 'trailing tokens';
    Exit(False);
  end;
  aError := '';
  Result := True;
end;

{ TMsBuildEvaluator }

constructor TMsBuildEvaluator.Create(const aProps, aEnvVars: TDictionary<string, string>; aDiagnostics: TDiagnostics);
begin
  inherited Create;
  fImportStack := TStringList.Create;
  fImportStack.CaseSensitive := False;
  fImportStack.Sorted := False;
  fImportStack.Duplicates := TDuplicates.dupIgnore;
  fProps := aProps;
  fEnvVars := aEnvVars;
  fDiagnostics := aDiagnostics;
end;

destructor TMsBuildEvaluator.Destroy;
begin
  fImportStack.Free;
  inherited;
end;

function TMsBuildEvaluator.NormalizeConditionFunctions(const aCondition: string; const aBaseDir: string): string;
var
  lEndPos: Integer;
  lPos: Integer;
  lQuotedPath: string;
  lResolvedPath: string;
  lReplacementText: string;
  lSearchPos: Integer;
  lSegmentLength: Integer;
const
  cExistsPrefix = 'exists(''';
begin
  Result := aCondition;
  lSearchPos := 1;
  repeat
    lPos := PosEx(cExistsPrefix, LowerCase(Result), lSearchPos);
    if lPos <= 0 then
      Break;

    lEndPos := PosEx(''')', Result, lPos + Length(cExistsPrefix));
    if lEndPos <= 0 then
      Break;

    lQuotedPath := Trim(Copy(Result, lPos + Length(cExistsPrefix), lEndPos - (lPos + Length(cExistsPrefix))));
    lResolvedPath := lQuotedPath;
    if (lResolvedPath <> '') and (Pos('$(', lResolvedPath) = 0) then
    begin
      if not TPath.IsPathRooted(lResolvedPath) then
        lResolvedPath := TPath.GetFullPath(TPath.Combine(aBaseDir, lResolvedPath));
      lReplacementText := BoolToStr(FileExists(lResolvedPath) or DirectoryExists(lResolvedPath), True);
    end else
      lReplacementText := BoolToStr(False, True);

    lSegmentLength := (lEndPos - lPos) + 2;
    Result := Copy(Result, 1, lPos - 1) + '''' + lReplacementText + '''==''true''' +
      Copy(Result, lPos + lSegmentLength, MaxInt);
    lSearchPos := lPos + 1;
  until False;
end;

function TMsBuildEvaluator.ResolveImportFilePath(const aImportProject: string; const aBaseDir: string): string;
var
  lExpanded: string;
begin
  Result := '';
  lExpanded := Trim(TMacroExpander.Expand(aImportProject, fProps, fEnvVars, fDiagnostics, False));
  if (lExpanded = '') or (Pos('$(', lExpanded) > 0) then
    Exit('');
  if not TPath.IsPathRooted(lExpanded) then
    lExpanded := TPath.Combine(aBaseDir, lExpanded);
  Result := TPath.GetFullPath(lExpanded);
end;

function TMsBuildEvaluator.TryEvaluateCondition(const aCondition: string; const aBaseDir: string; out aResult: Boolean;
  out aError: string): Boolean;
var
  lExpanded: string;
  lParser: TConditionParser;
begin
  aResult := True;
  aError := '';
  if Trim(aCondition) = '' then
    Exit(True);

  lExpanded := TMacroExpander.Expand(aCondition, fProps, fEnvVars, fDiagnostics, True);
  lExpanded := NormalizeConditionFunctions(lExpanded, aBaseDir);
  lParser := TConditionParser.Create(lExpanded);
  try
    Result := lParser.TryEvaluate(aResult, aError);
  finally
    lParser.Free;
  end;
  if not Result then
    aError := Format(SConditionParseError, [aCondition]);
end;

procedure TMsBuildEvaluator.ApplyProperty(const aName, aValue: string);
var
  lExpanded: string;
  lCurrentValue: string;
begin
  if not fProps.TryGetValue(aName, lCurrentValue) then
  begin
    lCurrentValue := '';
    fProps.AddOrSetValue(aName, lCurrentValue);
  end;

  lExpanded := TMacroExpander.Expand(aValue, fProps, fEnvVars, fDiagnostics, False);
  fProps.AddOrSetValue(aName, lExpanded);
  if fDiagnostics <> nil then
    fDiagnostics.AddInfo(Format(SInfoPropertySet, [aName, lExpanded]));
  if Assigned(fOnPropertySet) then
    fOnPropertySet(aName, lExpanded);
end;

function TMsBuildEvaluator.EvaluateFile(const aFileName: string; out aError: string): Boolean;
begin
  aError := '';
  Result := EvaluateFileInternal(TPath.GetFullPath(aFileName), aError);
end;

function TMsBuildEvaluator.EvaluateFileInternal(const aFileName: string; out aError: string): Boolean;
var
  lBaseDir: string;
  lChildNode: IXMLNode;
  lChildNodes: IXMLNodeList;
  lDoc: IXMLDocument;
  lGroup: IXMLNode;
  lXmlDoc: TXMLDocument;
  lImportCondition: string;
  lImportPath: string;
  lImportProject: string;
  lImportOk: Boolean;
  lNodeOk: Boolean;
  lNodePath: string;
  lImportNode: IXMLNode;
  lNodeCondition: string;
  lVendor: TDOMVendor;
  lRoot: IXMLNode;
  lProp: IXMLNode;
  lPropList: IXMLNodeList;
  i: Integer;
  j: Integer;
  lCondition: string;
  lGroupOk: Boolean;
  lPropOk: Boolean;
  lValue: string;

  function BoolToText(aValue: Boolean): string;
  begin
    if aValue then
      Result := 'true'
    else
      Result := 'false';
  end;
begin
  Result := False;
  aError := '';
  if fImportStack.IndexOf(aFileName) >= 0 then
  begin
    aError := 'Circular MSBuild import detected: ' + aFileName;
    Exit(False);
  end;

  fImportStack.Add(aFileName);
  lBaseDir := TPath.GetDirectoryName(aFileName);
  if fDiagnostics <> nil then
    fDiagnostics.AddInfo(Format(SInfoReadingFile, [aFileName]));
  try
    try
      lVendor := GetDOMVendor(sOmniXmlVendor);
    except
      on E: Exception do
      begin
        aError := Format(SXmlVendorMissing, ['OmniXML']);
        if fDiagnostics <> nil then
          fDiagnostics.AddInfo(E.Message);
        Exit(False);
      end;
    end;
    if lVendor = nil then
    begin
      aError := Format(SXmlVendorMissing, ['OmniXML']);
      Exit(False);
    end;
    lXmlDoc := TXMLDocument.Create(nil);
    lXmlDoc.DOMVendor := lVendor;
    lDoc := lXmlDoc;
    try
      lDoc.Options := [doNodeAutoIndent];
      lDoc.LoadFromFile(aFileName);
      lDoc.Active := True;
    except
      on E: Exception do
      begin
        aError := E.Message;
        Exit(False);
      end;
    end;

    lRoot := lDoc.DocumentElement;
    if lRoot = nil then
    begin
      aError := 'missing root';
      Exit(False);
    end;

    lChildNodes := lRoot.ChildNodes;
    for i := 0 to lChildNodes.Count - 1 do
    begin
      lChildNode := lChildNodes[i];
      if lChildNode.NodeType <> ntElement then
        Continue;

      if SameText(lChildNode.LocalName, 'Import') then
      begin
        lImportNode := lChildNode;
        if lImportNode.HasAttribute('Condition') then
          lImportCondition := VarToStr(lImportNode.Attributes['Condition'])
        else
          lImportCondition := '';
        if not TryEvaluateCondition(lImportCondition, lBaseDir, lImportOk, aError) then
          Exit(False);
        if (lImportCondition <> '') and (fDiagnostics <> nil) then
          fDiagnostics.AddInfo(Format(SInfoGroupCondition, [lImportCondition, BoolToText(lImportOk)]));
        if not lImportOk then
          Continue;

        if not lImportNode.HasAttribute('Project') then
          Continue;
        lImportProject := VarToStr(lImportNode.Attributes['Project']);
        lImportPath := ResolveImportFilePath(lImportProject, lBaseDir);
        if lImportPath = '' then
          Continue;
        if not FileExists(lImportPath) then
          Continue;
        if not EvaluateFileInternal(lImportPath, aError) then
          Exit(False);
        Continue;
      end;

      if SameText(lChildNode.LocalName, 'ImportGroup') then
      begin
        if lChildNode.HasAttribute('Condition') then
          lNodeCondition := VarToStr(lChildNode.Attributes['Condition'])
        else
          lNodeCondition := '';
        if not TryEvaluateCondition(lNodeCondition, lBaseDir, lNodeOk, aError) then
          Exit(False);
        if (lNodeCondition <> '') and (fDiagnostics <> nil) then
          fDiagnostics.AddInfo(Format(SInfoGroupCondition, [lNodeCondition, BoolToText(lNodeOk)]));
        if not lNodeOk then
          Continue;

        for j := 0 to lChildNode.ChildNodes.Count - 1 do
        begin
          lImportNode := lChildNode.ChildNodes[j];
          if (lImportNode.NodeType <> ntElement) or (not SameText(lImportNode.LocalName, 'Import')) then
            Continue;
          if lImportNode.HasAttribute('Condition') then
            lImportCondition := VarToStr(lImportNode.Attributes['Condition'])
          else
            lImportCondition := '';
          if not TryEvaluateCondition(lImportCondition, lBaseDir, lImportOk, aError) then
            Exit(False);
          if (lImportCondition <> '') and (fDiagnostics <> nil) then
            fDiagnostics.AddInfo(Format(SInfoGroupCondition, [lImportCondition, BoolToText(lImportOk)]));
          if not lImportOk then
            Continue;

          if not lImportNode.HasAttribute('Project') then
            Continue;
          lImportProject := VarToStr(lImportNode.Attributes['Project']);
          lNodePath := ResolveImportFilePath(lImportProject, lBaseDir);
          if lNodePath = '' then
            Continue;
          if not FileExists(lNodePath) then
            Continue;
          if not EvaluateFileInternal(lNodePath, aError) then
            Exit(False);
        end;
        Continue;
      end;

      if not SameText(lChildNode.LocalName, 'PropertyGroup') then
        Continue;

      lGroup := lChildNode;
      if lGroup.HasAttribute('Condition') then
        lCondition := VarToStr(lGroup.Attributes['Condition'])
      else
        lCondition := '';
      if not TryEvaluateCondition(lCondition, lBaseDir, lGroupOk, aError) then
        Exit(False);
      if (lCondition <> '') and (fDiagnostics <> nil) then
        fDiagnostics.AddInfo(Format(SInfoGroupCondition, [lCondition, BoolToText(lGroupOk)]));
      if not lGroupOk then
        Continue;

      lPropList := lGroup.ChildNodes;
      for j := 0 to lPropList.Count - 1 do
      begin
        lProp := lPropList[j];
        if lProp.NodeType <> ntElement then
          Continue;
        if lProp.HasAttribute('Condition') then
          lCondition := VarToStr(lProp.Attributes['Condition'])
        else
          lCondition := '';
        if not TryEvaluateCondition(lCondition, lBaseDir, lPropOk, aError) then
          Exit(False);
        if (lCondition <> '') and (fDiagnostics <> nil) then
          fDiagnostics.AddInfo(Format(SInfoPropertyCondition, [lProp.LocalName, lCondition, BoolToText(lPropOk)]));
        if not lPropOk then
          Continue;
        lValue := Trim(lProp.Text);
        if fDiagnostics <> nil then
          fDiagnostics.AddInfo(Format(SInfoPropertyRaw, [lProp.LocalName, lValue]));
        ApplyProperty(lProp.LocalName, lValue);
      end;
    end;

    Result := True;
  finally
    fImportStack.Delete(fImportStack.IndexOf(aFileName));
  end;
end;

end.
