unit Dak.MacroExpander;

interface

uses
  System.Generics.Collections, System.SysUtils,
  DelphiSemantics.ProjectContext,
  Dak.Diagnostics;

type
  TMacroExpander = record
    class function Expand(const aValue: string; const aProps, aEnv: TDictionary<string, string>;
      aDiagnostics: TDiagnostics; aUnknownAsEmpty: Boolean): string; static;
  end;

implementation

function DictionaryToSemanticProperties(const aValues: TDictionary<string, string>): TArray<TDelphiSemanticProperty>;
var
  lPair: TPair<string, string>;
  lProperty: TDelphiSemanticProperty;
  lResult: TList<TDelphiSemanticProperty>;
begin
  lResult := TList<TDelphiSemanticProperty>.Create;
  try
    if aValues <> nil then
      for lPair in aValues do
      begin
        lProperty.Name := lPair.Key;
        lProperty.Value := lPair.Value;
        lResult.Add(lProperty);
      end;

    Result := lResult.ToArray;
  finally
    lResult.Free;
  end;
end;

function DiagnosticMacroName(const aMessage: string): string;
var
  lEndPos: Integer;
  lStartPos: Integer;
begin
  lStartPos := Pos('$(', aMessage);
  if lStartPos = 0 then
    Exit('');

  lEndPos := Pos(')', aMessage, lStartPos + 2);
  if lEndPos = 0 then
    Exit('');

  Result := Copy(aMessage, lStartPos + 2, lEndPos - lStartPos - 2);
end;

procedure AddSemanticDiagnostics(aDiagnostics: TDiagnostics;
  const aSemanticDiagnostics: TArray<TDelphiSemanticDiagnostic>);
var
  lDiagnostic: TDelphiSemanticDiagnostic;
  lMacroName: string;
begin
  if aDiagnostics = nil then
    Exit;

  for lDiagnostic in aSemanticDiagnostics do
  begin
    lMacroName := DiagnosticMacroName(lDiagnostic.Message);
    if SameText(lDiagnostic.Code, 'UNRESOLVED_MSBUILD_MACRO') then
      aDiagnostics.AddUnknownMacro(lMacroName)
    else if SameText(lDiagnostic.Code, 'CYCLE_MSBUILD_MACRO') then
      aDiagnostics.AddCycleMacro(lMacroName)
    else if lDiagnostic.Message <> '' then
      aDiagnostics.AddWarning(lDiagnostic.Message);
  end;
end;

class function TMacroExpander.Expand(const aValue: string; const aProps, aEnv: TDictionary<string, string>;
  aDiagnostics: TDiagnostics; aUnknownAsEmpty: Boolean): string;
var
  lSemanticDiagnostics: TArray<TDelphiSemanticDiagnostic>;
begin
  Result := TDelphiSemanticMsBuild.ExpandMacros(aValue, DictionaryToSemanticProperties(aProps),
    DictionaryToSemanticProperties(aEnv), aUnknownAsEmpty, lSemanticDiagnostics);
  AddSemanticDiagnostics(aDiagnostics, lSemanticDiagnostics);
end;

end.
