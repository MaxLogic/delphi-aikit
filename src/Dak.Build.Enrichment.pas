unit Dak.Build.Enrichment;

interface

uses
  Dak.Types;

function EnrichmentOperationName(aOperation: TLspOperation): string;
function SelectEnrichmentOperation(const aMessage, aToken, aEnclosingSymbol: string; out aOperation: TLspOperation): Boolean;
function BuildSemanticHintText(const aOperation: TLspOperation; const aResponseText: string; out aHintText: string): Boolean;

implementation

uses
  System.Classes, System.JSON, System.StrUtils, System.SysUtils;

function EnrichmentOperationName(aOperation: TLspOperation): string;
begin
  case aOperation of
    TLspOperation.loDefinition:
      Result := 'definition';
    TLspOperation.loHover:
      Result := 'hover';
    TLspOperation.loSymbols:
      Result := 'symbols';
  else
    Result := 'unknown';
  end;
end;

function SelectEnrichmentOperation(const aMessage, aToken, aEnclosingSymbol: string; out aOperation: TLspOperation): Boolean;
begin
  Result := False;
  aOperation := TLspOperation.loNone;
  if aToken = '' then
  begin
    if aEnclosingSymbol <> '' then
    begin
      aOperation := TLspOperation.loSymbols;
      Exit(True);
    end;
    Exit(False);
  end;

  if ContainsText(aMessage, 'Undeclared identifier') or
    ContainsText(aMessage, 'Identifier not found') or
    ContainsText(aMessage, 'Undeclared field') or
    ContainsText(aMessage, 'Undeclared method') or
    ContainsText(aMessage, 'Undeclared member') then
  begin
    aOperation := TLspOperation.loDefinition;
    Exit(True);
  end;

  if ContainsText(aMessage, 'Incompatible types') or
    ContainsText(aMessage, 'Type mismatch') or
    ContainsText(aMessage, 'Cannot convert') or
    ContainsText(aMessage, 'Not enough actual parameters') or
    ContainsText(aMessage, 'No overloaded method') then
  begin
    aOperation := TLspOperation.loHover;
    Exit(True);
  end;

  aOperation := TLspOperation.loHover;
  Result := True;
end;

function BuildSemanticHintText(const aOperation: TLspOperation; const aResponseText: string; out aHintText: string): Boolean;
var
  lItem: TJSONObject;
  lJson: TJSONObject;
  lJsonValue: TJSONValue;
  lLocationArray: TJSONArray;
  lResultObject: TJSONObject;
  lSymbolsArray: TJSONArray;
  lSummary: TStringBuilder;
begin
  Result := False;
  aHintText := '';
  lJsonValue := TJSONValue.ParseJSONValue(aResponseText);
  if not (lJsonValue is TJSONObject) then
  begin
    lJsonValue.Free;
    Exit(False);
  end;
  lJson := lJsonValue as TJSONObject;
  try
    if not (lJson.Values['result'] is TJSONObject) then
      Exit(False);
    lResultObject := lJson.Values['result'] as TJSONObject;
    case aOperation of
      TLspOperation.loDefinition:
        begin
          lLocationArray := lResultObject.GetValue<TJSONArray>('locations');
          if (lLocationArray = nil) or (lLocationArray.Count = 0) then
            Exit(False);
          if not (lLocationArray.Items[0] is TJSONObject) then
            Exit(False);
          lItem := lLocationArray.Items[0] as TJSONObject;
          aHintText := Format('semantic hint: %s -> %s(%d,%d)', [EnrichmentOperationName(aOperation),
            lItem.GetValue<string>('file', ''),
            lItem.GetValue<Integer>('line', 0),
            lItem.GetValue<Integer>('col', 0)]);
          Exit(aHintText <> '');
        end;
      TLspOperation.loHover:
        begin
          aHintText := Trim(lResultObject.GetValue<string>('contentsText', ''));
          if aHintText = '' then
            Exit(False);
          aHintText := 'semantic hint: hover -> ' + aHintText;
          Exit(True);
        end;
      TLspOperation.loSymbols:
        begin
          lSymbolsArray := lResultObject.GetValue<TJSONArray>('symbols');
          if (lSymbolsArray = nil) or (lSymbolsArray.Count = 0) then
            Exit(False);
          lSummary := TStringBuilder.Create;
          try
            for var i := 0 to lSymbolsArray.Count - 1 do
            begin
              if i > 2 then
                Break;
              if not (lSymbolsArray.Items[i] is TJSONObject) then
                Continue;
              lItem := lSymbolsArray.Items[i] as TJSONObject;
              if lSummary.Length > 0 then
                lSummary.Append(', ');
              lSummary.Append(lItem.GetValue<string>('name', ''));
            end;
            aHintText := Trim(lSummary.ToString);
          finally
            lSummary.Free;
          end;
          if aHintText = '' then
            Exit(False);
          aHintText := 'semantic hint: symbols -> ' + aHintText;
          Exit(True);
        end;
    end;
  finally
    lJson.Free;
  end;
end;

end.
