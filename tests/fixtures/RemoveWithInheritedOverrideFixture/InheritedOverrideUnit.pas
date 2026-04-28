unit InheritedOverrideUnit;

interface

uses
  System.Classes;

type
  TBaseGolden = class
  private
    FBaseProp: string;
    FHiddenProp: string;
  public
    const
      BaseLimit: Integer = 11;
    class var
      BaseCount: Integer;
    BaseField: string;
    procedure OverrideMe; virtual;
    procedure HiddenMethod;
    procedure BaseOnly;
    property BaseProp: string read FBaseProp write FBaseProp;
    property HiddenProp: string read FHiddenProp write FHiddenProp;
  end;

  TDerivedGolden = class(TBaseGolden)
  private
    FDerivedProp: string;
    FHiddenProp: string;
  public
    DerivedField: string;
    procedure OverrideMe; override;
    procedure HiddenMethod;
    procedure DerivedOnly;
    property DerivedProp: string read FDerivedProp write FDerivedProp;
    property HiddenProp: string read FHiddenProp write FHiddenProp;
  end;

  TGrandGolden = class(TDerivedGolden)
  end;

  TExternalGolden = class(TStringList)
  end;

  TInheritedOverrideScope = class
  public
    class procedure Run;
  end;

implementation

procedure TBaseGolden.OverrideMe;
begin
end;

procedure TBaseGolden.BaseOnly;
begin
end;

procedure TBaseGolden.HiddenMethod;
begin
end;

procedure TDerivedGolden.OverrideMe;
begin
end;

procedure TDerivedGolden.HiddenMethod;
begin
end;

procedure TDerivedGolden.DerivedOnly;
begin
end;

class procedure TInheritedOverrideScope.Run;
var
  lDerived: TDerivedGolden;
  lExternal: TExternalGolden;
  lGrand: TGrandGolden;
begin
  with lDerived do
  begin
    BaseField := '';
    DerivedField := '';
    DerivedProp := '';
    DerivedOnly;
    HiddenProp := '';
    HiddenMethod;
    OverrideMe;
  end;

  with lGrand do
  begin
    BaseField := '';
    BaseProp := '';
    BaseOnly;
    BaseCount := 1;
    BaseLimit;
    DerivedField := '';
    DerivedProp := '';
    DerivedOnly;
    HiddenProp := '';
    OverrideMe;
    MissingMember := '';
  end;

  with lExternal do
  begin
    Count := 1;
  end;
end;

end.
