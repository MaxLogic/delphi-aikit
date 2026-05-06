unit SymbolMapUnit;

interface

uses
  System.SysUtils,
  Winapi.Windows;

type
  TSymbolMapFixture = class
  public
    procedure Run;
  end;

  TSymbolMapFixtureType = TSymbolMapFixture;

  TSymbolMapReferenceHolder = class
  private
    FValue: TSymbolMapFixtureType;
  public
    procedure UseValue(const aValue: TSymbolMapFixtureType);
  end;

implementation

uses
  System.Classes,
  System.Generics.Collections;

procedure TSymbolMapFixture.Run;
begin
end;

procedure TSymbolMapReferenceHolder.UseValue(const aValue: TSymbolMapFixtureType);
begin
  FValue := aValue;
  if Assigned(FValue) then
    FValue.Run;
end;

end.
