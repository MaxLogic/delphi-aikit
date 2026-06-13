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

  TSymbolMapShadowCollision = class
  public
    procedure Run;
  end;

  TSymbolMapMemberShadowCollision = class
  private
    lShadowValue: Integer;
  public
    procedure Run;
  end;

  TSymbolMapOverloadCollision = class
  public
    procedure Select(const aValue: string); overload;
    procedure Select(const aValue: Integer); overload;
    procedure Run;
  end;

var
  lShadowValue: Integer;

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

procedure TSymbolMapShadowCollision.Run;
var
  lShadowValue: Integer;
begin
  lShadowValue := 1;
  if lShadowValue > 0 then
    lShadowValue := lShadowValue + 1;
end;

procedure TSymbolMapMemberShadowCollision.Run;
begin
  lShadowValue := 2;
end;

procedure TSymbolMapOverloadCollision.Select(const aValue: string);
begin
end;

procedure TSymbolMapOverloadCollision.Select(const aValue: Integer);
begin
end;

procedure TSymbolMapOverloadCollision.Run;
begin
  Select(42);
end;

end.
