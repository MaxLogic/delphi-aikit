unit Dak.DfmInspect;

interface

uses
  Dak.Types;

function RunDfmInspectCommand(const aOptions: TAppOptions): Integer;
function TryInspectDfmFile(const aDfmPath, aFormat: string; out aOutput: string; out aError: string): Boolean;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.RegularExpressions, System.StrUtils,
  System.SysUtils,
  Dak.Messages, Dak.Utils;

type
  TDfmInspectComponent = class
  private
    fChildren: TObjectList<TDfmInspectComponent>;
    fEvents: TStringList;
    fProperties: TStringList;
    fClassName: string;
    fName: string;
  public
    constructor Create(const aName, aClassName: string);
    destructor Destroy; override;
    property Children: TObjectList<TDfmInspectComponent> read fChildren;
    property ClassName: string read fClassName;
    property Events: TStringList read fEvents;
    property Name: string read fName;
    property Properties: TStringList read fProperties;
  end;

constructor TDfmInspectComponent.Create(const aName, aClassName: string);
begin
  inherited Create;
  fName := aName;
  fClassName := aClassName;
  fChildren := TObjectList<TDfmInspectComponent>.Create(True);
  fEvents := TStringList.Create;
  fProperties := TStringList.Create;
  fEvents.NameValueSeparator := '=';
  fProperties.NameValueSeparator := '=';
end;

destructor TDfmInspectComponent.Destroy;
begin
  fProperties.Free;
  fEvents.Free;
  fChildren.Free;
  inherited Destroy;
end;

function TryParseComponentHeader(const aLine: string; out aName: string; out aClassName: string): Boolean;
var
  lMatch: TMatch;
begin
  aName := '';
  aClassName := '';
  lMatch := TRegEx.Match(aLine, '^\s*(object|inherited|inline)\s+([^\s:]+)\s*:\s*([^\s]+)\s*$', [roIgnoreCase]);
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

function TryResolveDfmInspectPath(const aInputPath: string; out aResolvedPath: string; out aError: string): Boolean;
begin
  Result := TryResolveAbsolutePath(aInputPath, aResolvedPath, aError);
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

function TryParseComponent(const aLines: TStrings; var aIndex: Integer; out aComponent: TDfmInspectComponent;
  out aError: string): Boolean;
var
  lClassName: string;
  lName: string;
  lNextIndex: Integer;
  lPropertyName: string;
  lPropertyValue: string;
  lTrimmedLine: string;
  lChild: TDfmInspectComponent;
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
  if not TryParseComponentHeader(lTrimmedLine, lName, lClassName) then
  begin
    aError := 'Expected DFM object header at line ' + IntToStr(aIndex + 1) + '.';
    Exit(False);
  end;

  aComponent := TDfmInspectComponent.Create(lName, lClassName);
  Inc(aIndex);
  while aIndex < aLines.Count do
  begin
    lTrimmedLine := Trim(aLines[aIndex]);
    if SameText(lTrimmedLine, 'end') then
    begin
      Inc(aIndex);
      Exit(True);
    end;

    if TryParseComponentHeader(lTrimmedLine, lName, lClassName) then
    begin
      if not TryParseComponent(aLines, aIndex, lChild, aError) then
        Exit(False);
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
      aIndex := lNextIndex;
      Continue;
    end;

    Inc(aIndex);
  end;

  aError := 'Unexpected end of DFM object block.';
  FreeAndNil(aComponent);
end;

function TryLoadRootComponent(const aDfmPath: string; out aRoot: TDfmInspectComponent; out aError: string): Boolean;
var
  lIndex: Integer;
  lLines: TStringList;
begin
  Result := False;
  aRoot := nil;
  aError := '';
  if not FileExists(aDfmPath) then
  begin
    aError := Format(SFileNotFound, [aDfmPath]);
    Exit(False);
  end;

  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aDfmPath);
    lIndex := 0;
    while (lIndex < lLines.Count) and (Trim(lLines[lIndex]) = '') do
      Inc(lIndex);
    if lIndex >= lLines.Count then
    begin
      aError := 'DFM file is empty: ' + aDfmPath;
      Exit(False);
    end;
    Result := TryParseComponent(lLines, lIndex, aRoot, aError);
  finally
    lLines.Free;
  end;
end;

procedure AppendTreeLines(const aComponent: TDfmInspectComponent; const aLines: TStrings; const aIndent: Integer);
const
  cImportantProps: array[0..9] of string = (
    'Caption', 'Text', 'Left', 'Top', 'Width', 'Height', 'ClientWidth', 'ClientHeight', 'Align', 'TabOrder');
var
  lEventName: string;
  lIndentText: string;
  lIndex: Integer;
  lPropertyName: string;
begin
  lIndentText := StringOfChar(' ', aIndent * 2);
  aLines.Add(lIndentText + aComponent.Name + ': ' + aComponent.ClassName);
  for lPropertyName in cImportantProps do
    if aComponent.Properties.Values[lPropertyName] <> '' then
      aLines.Add(lIndentText + '  ' + lPropertyName + ' = ' + aComponent.Properties.Values[lPropertyName]);
  for lIndex := 0 to aComponent.Events.Count - 1 do
  begin
    lEventName := aComponent.Events.Names[lIndex];
    aLines.Add(lIndentText + '  ' + lEventName + ' = ' + aComponent.Events.ValueFromIndex[lIndex]);
  end;
  for lIndex := 0 to aComponent.Children.Count - 1 do
    AppendTreeLines(aComponent.Children[lIndex], aLines, aIndent + 1);
end;

procedure CollectSummaryData(const aComponent: TDfmInspectComponent; const aClassCounts: TDictionary<string, Integer>;
  const aEventLines: TStrings; var aCount: Integer);
var
  lCount: Integer;
  lEventName: string;
  lIndex: Integer;
begin
  Inc(aCount);
  if aClassCounts.TryGetValue(aComponent.ClassName, lCount) then
    aClassCounts[aComponent.ClassName] := lCount + 1
  else
    aClassCounts.Add(aComponent.ClassName, 1);

  for lIndex := 0 to aComponent.Events.Count - 1 do
  begin
    lEventName := aComponent.Events.Names[lIndex];
    aEventLines.Add(aComponent.Name + '.' + lEventName + ' = ' + aComponent.Events.ValueFromIndex[lIndex]);
  end;

  for lIndex := 0 to aComponent.Children.Count - 1 do
    CollectSummaryData(aComponent.Children[lIndex], aClassCounts, aEventLines, aCount);
end;

function BuildTreeOutput(const aRoot: TDfmInspectComponent): string;
var
  lLines: TStringList;
begin
  lLines := TStringList.Create;
  try
    AppendTreeLines(aRoot, lLines, 0);
    Result := TrimRight(lLines.Text);
  finally
    lLines.Free;
  end;
end;

function BuildSummaryOutput(const aRoot: TDfmInspectComponent): string;
var
  lClassCount: Integer;
  lClassCounts: TDictionary<string, Integer>;
  lClassNames: TStringList;
  lEventLines: TStringList;
  lIndex: Integer;
  lLines: TStringList;
  lTotalCount: Integer;
  lClassName: string;
begin
  lClassCounts := TDictionary<string, Integer>.Create;
  lClassNames := TStringList.Create;
  lEventLines := TStringList.Create;
  lLines := TStringList.Create;
  try
    lClassNames.Sorted := True;
    lClassNames.Duplicates := TDuplicates.dupIgnore;
    lTotalCount := 0;
    CollectSummaryData(aRoot, lClassCounts, lEventLines, lTotalCount);
    for lClassName in lClassCounts.Keys do
      lClassNames.Add(lClassName);

    lLines.Add('Form: ' + aRoot.Name + ' (' + aRoot.ClassName + ')');
    lLines.Add('Components: ' + IntToStr(lTotalCount));
    lLines.Add('Classes:');
    for lIndex := 0 to lClassNames.Count - 1 do
    begin
      lClassName := lClassNames[lIndex];
      lClassCount := lClassCounts[lClassName];
      lLines.Add('  ' + lClassName + ' = ' + IntToStr(lClassCount));
    end;
    if lEventLines.Count > 0 then
    begin
      lLines.Add('Events:');
      for lIndex := 0 to lEventLines.Count - 1 do
        lLines.Add('  ' + lEventLines[lIndex]);
    end;
    Result := TrimRight(lLines.Text);
  finally
    lLines.Free;
    lEventLines.Free;
    lClassNames.Free;
    lClassCounts.Free;
  end;
end;

function TryInspectDfmFile(const aDfmPath, aFormat: string; out aOutput: string; out aError: string): Boolean;
var
  lFormat: string;
  lResolvedPath: string;
  lRoot: TDfmInspectComponent;
begin
  Result := False;
  aOutput := '';
  aError := '';
  lFormat := LowerCase(Trim(aFormat));
  if lFormat = '' then
    lFormat := 'tree';
  if (lFormat <> 'tree') and (lFormat <> 'summary') then
  begin
    aError := 'Unsupported dfm-inspect format: ' + aFormat;
    Exit(False);
  end;

  if not TryResolveDfmInspectPath(aDfmPath, lResolvedPath, aError) then
    Exit(False);

  if not TryLoadRootComponent(lResolvedPath, lRoot, aError) then
    Exit(False);
  try
    if lFormat = 'summary' then
      aOutput := BuildSummaryOutput(lRoot)
    else
      aOutput := BuildTreeOutput(lRoot);
    Result := True;
  finally
    lRoot.Free;
  end;
end;

function RunDfmInspectCommand(const aOptions: TAppOptions): Integer;
var
  lError: string;
  lOutput: string;
  lResolvedPath: string;
begin
  if not TryResolveDfmInspectPath(aOptions.fDfmInspectPath, lResolvedPath, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(3);
  end;

  if not TryInspectDfmFile(lResolvedPath, aOptions.fDfmInspectFormat, lOutput, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(3);
  end;
  if lOutput <> '' then
    WriteLn(lOutput);
  Result := 0;
end;

end.
