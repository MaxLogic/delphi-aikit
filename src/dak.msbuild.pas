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
  TTokenKind = (tkText, tkIdentifier, tkEqual, tkNotEqual, tkAnd, tkOr, tkNot, tkLParen, tkRParen, tkUnknown, tkEof);

  TToken = record
    fKind: TTokenKind;
    fText: string;
  end;

  TConditionParser = class
  private
    fBaseDir: string;
    fText: string;
    fPos: Integer;
    fToken: TToken;
    function CurrentTokenStartsFunctionCall: Boolean;
    function EvaluateFunction(const aName, aArgument: string; out aValue: Boolean): Boolean;
    procedure NextToken;
    function ParseExpr(out aValue: Boolean): Boolean;
    function ParseTerm(out aValue: Boolean): Boolean;
    function ParseFactor(out aValue: Boolean): Boolean;
    function ParseComparison(out aValue: Boolean): Boolean;
    function ParseFunctionCall(out aValue: Boolean): Boolean;
    function ReadFunctionArgument(out aValue: string): Boolean;
    function ParseStringOperand(out aValue: string): Boolean;
  public
    constructor Create(const aText, aBaseDir: string);
    function TryEvaluate(out aValue: Boolean; out aError: string): Boolean;
  end;

{ TConditionParser }

constructor TConditionParser.Create(const aText, aBaseDir: string);
begin
  inherited Create;
  fText := aText;
  fBaseDir := aBaseDir;
  fPos := 1;
end;

function TConditionParser.CurrentTokenStartsFunctionCall: Boolean;
var
  lPos: Integer;
begin
  lPos := fPos;
  while (lPos <= Length(fText)) and (fText[lPos] <= ' ') do
    Inc(lPos);
  Result := (lPos <= Length(fText)) and (fText[lPos] = '(');
end;

function TConditionParser.EvaluateFunction(const aName, aArgument: string; out aValue: Boolean): Boolean;
var
  lPath: string;
begin
  Result := True;
  if SameText(aName, 'Exists') then
  begin
    lPath := aArgument;
    if (lPath <> '') and (not TPath.IsPathRooted(lPath)) then
      lPath := TPath.GetFullPath(TPath.Combine(fBaseDir, lPath));
    aValue := (lPath <> '') and (FileExists(lPath) or DirectoryExists(lPath));
  end else if SameText(aName, 'HasTrailingSlash') then
    aValue := (aArgument <> '') and CharInSet(aArgument[Length(aArgument)], ['\', '/'])
  else
    Result := False;
end;

procedure TConditionParser.NextToken;
var
  lStart: Integer;
  lCh: Char;
  lValue: TStringBuilder;
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
        lValue := TStringBuilder.Create;
        try
          while fPos <= Length(fText) do
          begin
            if fText[fPos] = '''' then
            begin
              if (fPos < Length(fText)) and (fText[fPos + 1] = '''') then
              begin
                lValue.Append('''');
                Inc(fPos, 2);
                Continue;
              end;
              Break;
            end;
            lValue.Append(fText[fPos]);
            Inc(fPos);
          end;
          if fPos > Length(fText) then
          begin
            fToken.fKind := TTokenKind.tkUnknown;
            fToken.fText := '''' + lValue.ToString;
            Exit;
          end;
          fToken.fKind := TTokenKind.tkText;
          fToken.fText := lValue.ToString;
          if fPos <= Length(fText) then
            Inc(fPos);
        finally
          lValue.Free;
        end;
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
          fToken.fKind := TTokenKind.tkNot;
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
        fToken.fKind := TTokenKind.tkIdentifier;
      fToken.fText := lWord;
    end;
  end;
end;

function TConditionParser.ParseStringOperand(out aValue: string): Boolean;
begin
  Result := False;
  if (fToken.fKind <> TTokenKind.tkText) and (fToken.fKind <> TTokenKind.tkIdentifier) then
    Exit;
  aValue := fToken.fText;
  NextToken;
  Result := True;
end;

function TConditionParser.ParseComparison(out aValue: Boolean): Boolean;
var
  lLeft: string;
  lRight: string;
  lOp: TTokenKind;
begin
  Result := False;
  if not ParseStringOperand(lLeft) then
    Exit;
  if (fToken.fKind <> TTokenKind.tkEqual) and (fToken.fKind <> TTokenKind.tkNotEqual) then
    Exit;
  lOp := fToken.fKind;
  NextToken;
  if not ParseStringOperand(lRight) then
    Exit;
  if lOp = TTokenKind.tkEqual then
    aValue := SameText(lLeft, lRight)
  else
    aValue := not SameText(lLeft, lRight);
  Result := True;
end;

function TConditionParser.ParseFunctionCall(out aValue: Boolean): Boolean;
var
  lArgument: string;
  lName: string;
begin
  Result := False;
  if fToken.fKind <> TTokenKind.tkIdentifier then
    Exit;
  lName := fToken.fText;
  NextToken;
  if fToken.fKind <> TTokenKind.tkLParen then
    Exit;
  if not ReadFunctionArgument(lArgument) then
    Exit;
  Result := EvaluateFunction(lName, lArgument, aValue);
end;

function TConditionParser.ReadFunctionArgument(out aValue: string): Boolean;
var
  lValue: TStringBuilder;
begin
  Result := False;
  aValue := '';
  lValue := TStringBuilder.Create;
  try
    while fPos <= Length(fText) do
    begin
      if fText[fPos] = ')' then
      begin
        Inc(fPos);
        aValue := Trim(lValue.ToString);
        NextToken;
        Exit(True);
      end;

      if fText[fPos] = '''' then
      begin
        Inc(fPos);
        while fPos <= Length(fText) do
        begin
          if fText[fPos] = '''' then
          begin
            if (fPos < Length(fText)) and (fText[fPos + 1] = '''') then
            begin
              lValue.Append('''');
              Inc(fPos, 2);
              Continue;
            end;
            Inc(fPos);
            Break;
          end;
          lValue.Append(fText[fPos]);
          Inc(fPos);
        end;
      end else
      begin
        lValue.Append(fText[fPos]);
        Inc(fPos);
      end;
    end;
  finally
    lValue.Free;
  end;
end;

function TConditionParser.ParseFactor(out aValue: Boolean): Boolean;
var
  lValue: Boolean;
begin
  Result := False;
  if fToken.fKind = TTokenKind.tkNot then
  begin
    NextToken;
    if not ParseFactor(lValue) then
      Exit;
    aValue := not lValue;
    Exit(True);
  end;

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

  if fToken.fKind = TTokenKind.tkIdentifier then
  begin
    if SameText(fToken.fText, 'true') then
    begin
      aValue := True;
      NextToken;
      Exit(True);
    end else if SameText(fToken.fText, 'false') then
    begin
      aValue := False;
      NextToken;
      Exit(True);
    end else if CurrentTokenStartsFunctionCall then
      Exit(ParseFunctionCall(aValue));
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
  lParser := TConditionParser.Create(lExpanded, aBaseDir);
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
