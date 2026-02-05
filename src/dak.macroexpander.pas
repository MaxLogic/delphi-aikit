unit Dak.MacroExpander;

interface

uses
  System.Generics.Collections, System.SysUtils,
  Dak.Diagnostics;

type
  TMacroExpander = record
    class function Expand(const aValue: string; const aProps, aEnv: TDictionary<string, string>;
      aDiagnostics: TDiagnostics; aUnknownAsEmpty: Boolean): string; static;
  end;

implementation

class function TMacroExpander.Expand(const aValue: string; const aProps, aEnv: TDictionary<string, string>;
  aDiagnostics: TDiagnostics; aUnknownAsEmpty: Boolean): string;
var
  lStack: TList<string>;

  function TryGetMacroValue(const aName: string; out aValue: string): Boolean;
  begin
    if aProps.TryGetValue(aName, aValue) then
      Exit(True);
    if aEnv.TryGetValue(aName, aValue) then
      Exit(True);
    aValue := System.SysUtils.GetEnvironmentVariable(aName);
    Result := aValue <> '';
  end;

  function StackContains(const aName: string): Boolean;
  var
    lItem: string;
  begin
    for lItem in lStack do
      if SameText(lItem, aName) then
        Exit(True);
    Result := False;
  end;

  function ExpandText(const aText: string): string;
  var
    lIndex: Integer;
    lStart: Integer;
    lName: string;
    lValue: string;
    lResult: TStringBuilder;
  begin
    lResult := TStringBuilder.Create;
    try
      lIndex := 1;
      while lIndex <= Length(aText) do
      begin
        if (aText[lIndex] = '$') and (lIndex < Length(aText)) and (aText[lIndex + 1] = '(') then
        begin
          lStart := lIndex + 2;
          Inc(lIndex, 2);
          while (lIndex <= Length(aText)) and (aText[lIndex] <> ')') do
            Inc(lIndex);
          if lIndex <= Length(aText) then
          begin
            lName := Copy(aText, lStart, lIndex - lStart);
            if StackContains(lName) then
            begin
              if (aDiagnostics <> nil) and (not aUnknownAsEmpty) then
                aDiagnostics.AddCycleMacro(lName);
              if aUnknownAsEmpty then
                lValue := ''
              else
                lValue := '$(' + lName + ')';
            end else if TryGetMacroValue(lName, lValue) then
            begin
              lStack.Add(lName);
              try
                lValue := ExpandText(lValue);
              finally
                lStack.Delete(lStack.Count - 1);
              end;
            end else
            begin
              if (aDiagnostics <> nil) and (not aUnknownAsEmpty) then
                aDiagnostics.AddUnknownMacro(lName);
              if aUnknownAsEmpty then
                lValue := ''
              else
                lValue := '$(' + lName + ')';
            end;
            lResult.Append(lValue);
            Inc(lIndex);
          end else
          begin
            lResult.Append(aText[lStart - 2]);
            lResult.Append(aText[lStart - 1]);
            lResult.Append(Copy(aText, lStart, Length(aText) - lStart + 1));
            Break;
          end;
        end else
        begin
          lResult.Append(aText[lIndex]);
          Inc(lIndex);
        end;
      end;
      Result := lResult.ToString;
    finally
      lResult.Free;
    end;
  end;

begin
  lStack := TList<string>.Create;
  try
    Result := ExpandText(aValue);
  finally
    lStack.Free;
  end;
end;

end.
