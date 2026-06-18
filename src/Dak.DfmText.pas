unit Dak.DfmText;

interface

uses
  System.Classes, System.Generics.Collections;

type
  TDfmTextComponent = class
  private
    fChildren: TObjectList<TDfmTextComponent>;
    fEvents: TStringList;
    fProperties: TStringList;
    fPropertyLines: TStringList;
    fClassName: string;
    fEndLine: Integer;
    fName: string;
    fParent: TDfmTextComponent;
    fStartLine: Integer;
  public
    constructor Create(const aName, aClassName: string; const aParent: TDfmTextComponent; aStartLine: Integer);
    destructor Destroy; override;
    function TryGetPropertyLine(const aName: string; out aLineNumber: Integer): Boolean;
    function TryGetPropertyValue(const aName: string; out aValue: string): Boolean;
    function TryGetUnquotedPropertyValue(const aName: string; out aValue: string): Boolean;
    property Children: TObjectList<TDfmTextComponent> read fChildren;
    property DfmClassName: string read fClassName;
    property EndLine: Integer read fEndLine write fEndLine;
    property Events: TStringList read fEvents;
    property Name: string read fName;
    property Parent: TDfmTextComponent read fParent;
    property Properties: TStringList read fProperties;
    property PropertyLines: TStringList read fPropertyLines;
    property StartLine: Integer read fStartLine;
  end;

  TDfmTextDocument = class
  private
    fComponents: TList<TDfmTextComponent>;
    fRoot: TDfmTextComponent;
  public
    constructor Create;
    destructor Destroy; override;
    function TryFindComponentByName(const aName: string; out aComponent: TDfmTextComponent): Boolean;
    property Components: TList<TDfmTextComponent> read fComponents;
    property Root: TDfmTextComponent read fRoot;
  end;

function TryLoadDfmTextDocument(const aDfmPath: string; out aDocument: TDfmTextDocument; out aError: string): Boolean;
function TryParseDfmComponentHeader(const aLine: string; out aName: string; out aClassName: string): Boolean;

implementation

uses
  System.IOUtils, System.RegularExpressions, System.StrUtils, System.SysUtils,
  DelphiSemantics.Source,
  Dak.Messages;

function TrimMatchingQuotes(const aValue: string): string;
begin
  Result := Trim(aValue);
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

constructor TDfmTextComponent.Create(const aName, aClassName: string; const aParent: TDfmTextComponent;
  aStartLine: Integer);
begin
  inherited Create;
  fName := aName;
  fClassName := aClassName;
  fParent := aParent;
  fStartLine := aStartLine;
  fChildren := TObjectList<TDfmTextComponent>.Create(True);
  fEvents := TStringList.Create;
  fProperties := TStringList.Create;
  fPropertyLines := TStringList.Create;
  fEvents.NameValueSeparator := '=';
  fProperties.NameValueSeparator := '=';
  fPropertyLines.NameValueSeparator := '=';
end;

destructor TDfmTextComponent.Destroy;
begin
  fPropertyLines.Free;
  fProperties.Free;
  fEvents.Free;
  fChildren.Free;
  inherited Destroy;
end;

function TDfmTextComponent.TryGetPropertyLine(const aName: string; out aLineNumber: Integer): Boolean;
begin
  aLineNumber := StrToIntDef(fPropertyLines.Values[aName], 0);
  Result := aLineNumber > 0;
end;

function TDfmTextComponent.TryGetPropertyValue(const aName: string; out aValue: string): Boolean;
var
  lIndex: Integer;
begin
  aValue := '';
  lIndex := fProperties.IndexOfName(aName);
  if lIndex < 0 then
    Exit(False);
  aValue := Trim(fProperties.ValueFromIndex[lIndex]);
  Result := aValue <> '';
end;

function TDfmTextComponent.TryGetUnquotedPropertyValue(const aName: string; out aValue: string): Boolean;
begin
  Result := TryGetPropertyValue(aName, aValue);
  if Result then
    aValue := TrimMatchingQuotes(aValue);
  Result := Result and (aValue <> '');
end;

constructor TDfmTextDocument.Create;
begin
  inherited Create;
  fComponents := TList<TDfmTextComponent>.Create;
end;

destructor TDfmTextDocument.Destroy;
begin
  fRoot.Free;
  fComponents.Free;
  inherited Destroy;
end;

function TDfmTextDocument.TryFindComponentByName(const aName: string; out aComponent: TDfmTextComponent): Boolean;
var
  lCandidate: TDfmTextComponent;
begin
  aComponent := nil;
  for lCandidate in fComponents do
  begin
    if SameText(lCandidate.Name, aName) then
    begin
      aComponent := lCandidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TryParseDfmComponentHeader(const aLine: string; out aName: string; out aClassName: string): Boolean;
var
  lMatch: TMatch;
begin
  aName := '';
  aClassName := '';
  lMatch := TRegEx.Match(aLine, '^\s*(object|inherited|inline)\s+([^\s:]+)\s*:\s*([^\s\[]+)(?:\s+\[[^\]]+\])?\s*$',
    [roIgnoreCase]);
  if not lMatch.Success then
    Exit(False);
  aName := lMatch.Groups[2].Value;
  aClassName := lMatch.Groups[3].Value;
  Result := (aName <> '') and (aClassName <> '');
end;

function TryReadPropertyLine(const aLine: string; out aName: string; out aValue: string): Boolean;
var
  lMatch: TMatch;
begin
  aName := '';
  aValue := '';
  lMatch := TRegEx.Match(aLine, '^\s*([A-Za-z_][A-Za-z0-9_\.]*)\s*=\s*(.*)$');
  if not lMatch.Success then
    Exit(False);
  aName := Trim(lMatch.Groups[1].Value);
  aValue := Trim(lMatch.Groups[2].Value);
  Result := aName <> '';
end;

function CountCharsOutsideQuotedText(const aText: string; const aChar: Char): Integer;
var
  lIndex: Integer;
  lInQuotedText: Boolean;
begin
  Result := 0;
  lInQuotedText := False;
  lIndex := 1;
  while lIndex <= Length(aText) do
  begin
    if aText[lIndex] = '''' then
    begin
      if lInQuotedText and (lIndex < Length(aText)) and (aText[lIndex + 1] = '''') then
        Inc(lIndex)
      else
        lInQuotedText := not lInQuotedText;
    end else if (not lInQuotedText) and (aText[lIndex] = aChar) then
      Inc(Result);
    Inc(lIndex);
  end;
end;

function ReadFullPropertyValue(const aLines: TStrings; const aIndex: Integer; const aInitialValue: string;
  out aNextIndex: Integer): string;
var
  lDepth: Integer;
  lLine: string;
  lParts: TStringList;
  lValue: string;
begin
  lValue := Trim(aInitialValue);
  aNextIndex := aIndex + 1;

  if lValue = '(' then
  begin
    lParts := TStringList.Create;
    try
      while aNextIndex < aLines.Count do
      begin
        lLine := Trim(aLines[aNextIndex]);
        if EndsText(')', lLine) then
        begin
          lLine := Trim(Copy(lLine, 1, Length(lLine) - 1));
          if lLine <> '' then
            lParts.Add(lLine);
          Break;
        end;
        if lLine <> '' then
          lParts.Add(lLine);
        Inc(aNextIndex);
      end;
      Inc(aNextIndex);
      Result := '(' + String.Join(', ', lParts.ToStringArray) + ')';
      Exit;
    finally
      lParts.Free;
    end;
  end;

  if lValue = '<' then
  begin
    lParts := TStringList.Create;
    try
      lParts.Add(lValue);
      lDepth := 1;
      while (aNextIndex < aLines.Count) and (lDepth > 0) do
      begin
        lLine := Trim(aLines[aNextIndex]);
        lParts.Add(lLine);
        lDepth := lDepth + CountCharsOutsideQuotedText(lLine, '<') - CountCharsOutsideQuotedText(lLine, '>');
        Inc(aNextIndex);
      end;
      Result := String.Join(' ', lParts.ToStringArray);
      Exit;
    finally
      lParts.Free;
    end;
  end;

  if StartsText('{', lValue) then
  begin
    if EndsText('}', lValue) then
      Exit('{...binary data...}');
    while aNextIndex < aLines.Count do
    begin
      lLine := Trim(aLines[aNextIndex]);
      Inc(aNextIndex);
      if EndsText('}', lLine) then
        Break;
    end;
    Exit('{...binary data...}');
  end;

  while EndsText('+', lValue) and (aNextIndex < aLines.Count) do
  begin
    lValue := Trim(Copy(lValue, 1, Length(lValue) - 1));
    lValue := lValue + ' ' + Trim(aLines[aNextIndex]);
    Inc(aNextIndex);
  end;

  while aNextIndex < aLines.Count do
  begin
    lLine := Trim(aLines[aNextIndex]);
    if (lLine = '') or (lLine[1] <> '''') or TRegEx.IsMatch(lLine, '^[A-Za-z_][A-Za-z0-9_\.]*\s*=') then
      Break;
    lValue := lValue + ' + ' + lLine;
    Inc(aNextIndex);
  end;

  Result := lValue;
end;

function TryParseComponent(const aLines: TStrings; var aIndex: Integer; const aParent: TDfmTextComponent;
  const aDocument: TDfmTextDocument; out aComponent: TDfmTextComponent; out aError: string): Boolean;
var
  lChild: TDfmTextComponent;
  lClassName: string;
  lName: string;
  lNextIndex: Integer;
  lPropertyName: string;
  lPropertyValue: string;
  lTrimmedLine: string;
begin
  Result := False;
  aComponent := nil;
  aError := '';
  if aIndex >= aLines.Count then
  begin
    aError := 'Unexpected end of DFM file.';
    Exit(False);
  end;

  lTrimmedLine := Trim(aLines[aIndex]);
  if not TryParseDfmComponentHeader(lTrimmedLine, lName, lClassName) then
  begin
    aError := 'Expected DFM object header at line ' + IntToStr(aIndex + 1) + '.';
    Exit(False);
  end;

  aComponent := TDfmTextComponent.Create(lName, lClassName, aParent, aIndex + 1);
  aDocument.fComponents.Add(aComponent);
  Inc(aIndex);
  while aIndex < aLines.Count do
  begin
    lTrimmedLine := Trim(aLines[aIndex]);
    if SameText(lTrimmedLine, 'end') then
    begin
      aComponent.EndLine := aIndex + 1;
      Inc(aIndex);
      Exit(True);
    end;

    if TryParseDfmComponentHeader(lTrimmedLine, lName, lClassName) then
    begin
      if not TryParseComponent(aLines, aIndex, aComponent, aDocument, lChild, aError) then
      begin
        lChild.Free;
        Exit(False);
      end;
      aComponent.Children.Add(lChild);
      Continue;
    end;

    if TryReadPropertyLine(lTrimmedLine, lPropertyName, lPropertyValue) then
    begin
      lPropertyValue := ReadFullPropertyValue(aLines, aIndex, lPropertyValue, lNextIndex);
      if StartsText('On', lPropertyName) and (Pos('.', lPropertyName) = 0) then
        aComponent.Events.Values[lPropertyName] := lPropertyValue
      else
        aComponent.Properties.Values[lPropertyName] := lPropertyValue;
      aComponent.PropertyLines.Values[lPropertyName] := IntToStr(aIndex + 1);
      aIndex := lNextIndex;
      Continue;
    end;

    Inc(aIndex);
  end;

  aError := 'Unexpected end of DFM object block.';
  FreeAndNil(aComponent);
end;

function TryLoadDfmTextDocument(const aDfmPath: string; out aDocument: TDfmTextDocument; out aError: string): Boolean;
var
  lIndex: Integer;
  lLines: TStringList;
  lRoot: TDfmTextComponent;
  lSourceLoad: TDelphiSemanticSourceLoadResult;
begin
  Result := False;
  aDocument := nil;
  aError := '';
  if not FileExists(aDfmPath) then
  begin
    aError := Format(SFileNotFound, [aDfmPath]);
    Exit(False);
  end;

  lLines := TStringList.Create;
  try
    lSourceLoad := TDelphiSemanticSourceLoader.LoadFile(aDfmPath);
    if not lSourceLoad.Success then
    begin
      if Length(lSourceLoad.Diagnostics) > 0 then
        aError := lSourceLoad.Diagnostics[0].Message
      else
        aError := 'Failed to load DFM source: ' + aDfmPath;
      Exit(False);
    end;
    lLines.Text := lSourceLoad.Source.Text;
    lIndex := 0;
    while (lIndex < lLines.Count) and (Trim(lLines[lIndex]) = '') do
      Inc(lIndex);
    if lIndex >= lLines.Count then
    begin
      aError := 'DFM file is empty: ' + aDfmPath;
      Exit(False);
    end;

    aDocument := TDfmTextDocument.Create;
    if not TryParseComponent(lLines, lIndex, nil, aDocument, lRoot, aError) then
    begin
      lRoot.Free;
      Exit(False);
    end;
    aDocument.fRoot := lRoot;
    Result := True;
  finally
    if not Result then
      FreeAndNil(aDocument);
    lLines.Free;
  end;
end;

end.
