unit Dak.DfmInspect;

interface

uses
  Dak.Types;

function RunDfmInspectCommand(const aOptions: TAppOptions): Integer;
function TryInspectDfmFile(const aDfmPath, aFormat: string; out aOutput: string; out aError: string): Boolean;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  Dak.DfmText, Dak.Utils;

function TryResolveDfmInspectPath(const aInputPath: string; out aResolvedPath: string; out aError: string): Boolean;
begin
  Result := TryResolveAbsolutePath(aInputPath, aResolvedPath, aError);
end;

procedure AppendTreeLines(const aComponent: TDfmTextComponent; const aLines: TStrings; const aIndent: Integer);
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
  aLines.Add(lIndentText + aComponent.Name + ': ' + aComponent.DfmClassName);
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

procedure CollectSummaryData(const aComponent: TDfmTextComponent; const aClassCounts: TDictionary<string, Integer>;
  const aEventLines: TStrings; var aCount: Integer);
var
  lCount: Integer;
  lEventName: string;
  lIndex: Integer;
begin
  Inc(aCount);
  if aClassCounts.TryGetValue(aComponent.DfmClassName, lCount) then
    aClassCounts[aComponent.DfmClassName] := lCount + 1
  else
    aClassCounts.Add(aComponent.DfmClassName, 1);

  for lIndex := 0 to aComponent.Events.Count - 1 do
  begin
    lEventName := aComponent.Events.Names[lIndex];
    aEventLines.Add(aComponent.Name + '.' + lEventName + ' = ' + aComponent.Events.ValueFromIndex[lIndex]);
  end;

  for lIndex := 0 to aComponent.Children.Count - 1 do
    CollectSummaryData(aComponent.Children[lIndex], aClassCounts, aEventLines, aCount);
end;

function BuildTreeOutput(const aRoot: TDfmTextComponent): string;
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

function BuildSummaryOutput(const aRoot: TDfmTextComponent): string;
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

    lLines.Add('Form: ' + aRoot.Name + ' (' + aRoot.DfmClassName + ')');
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
  lDocument: TDfmTextDocument;
  lFormat: string;
  lResolvedPath: string;
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

  if not TryLoadDfmTextDocument(lResolvedPath, lDocument, aError) then
    Exit(False);
  try
    if lFormat = 'summary' then
      aOutput := BuildSummaryOutput(lDocument.Root)
    else
      aOutput := BuildTreeOutput(lDocument.Root);
    Result := True;
  finally
    lDocument.Free;
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
