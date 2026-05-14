unit ResolverUnit;

interface

uses
  System.Classes, System.Generics.Collections;

type
  TResolverAddress = record
    City: string;
    Shared: string;
  end;

  TResolverRange = record
    B_Nr: Integer;
    B_von: Double;
  end;

  TResolverMapAlias = TDictionary<string, Integer>;

  TResolverCustomer = record
    Address: TResolverAddress;
    b: TResolverRange;
    Name: string;
    Shared: string;
    Size: Integer;
    function Pick(aValue: Integer): string; overload;
    function Pick(const aValue: string): string; overload;
    property AddressProp: TResolverAddress read Address;
    procedure Save;
  end;

  TDuplicateTarget = record
    Raw: string;
  end;

  TDuplicateTargetHelperA = record helper for TDuplicateTarget
  public
    procedure Clash;
  end;

  TDuplicateTargetHelperB = record helper for TDuplicateTarget
  public
    procedure Clash;
  end;

  TResolverScope = class
  private
    FCustomer: TResolverCustomer;
    class function MakeCustomer: TResolverCustomer; static;
  public
    property CustomerProp: TResolverCustomer read FCustomer;
    class procedure Run;
  end;

implementation

procedure TResolverCustomer.Save;
begin
end;

function TResolverCustomer.Pick(aValue: Integer): string;
begin
  Result := aValue.ToString;
end;

function TResolverCustomer.Pick(const aValue: string): string;
begin
  Result := aValue;
end;

procedure TDuplicateTargetHelperA.Clash;
begin
end;

procedure TDuplicateTargetHelperB.Clash;
begin
end;

class function TResolverScope.MakeCustomer: TResolverCustomer;
begin
  Result := Default(TResolverCustomer);
end;

class procedure TResolverScope.Run;
var
  b: Byte;
  lAddress: TResolverAddress;
  lCustomer: TResolverCustomer;
  lDuplicate: TDuplicateTarget;
  lExternal: TMissingReceiver;
  lLocalOnly: string;
  lMap: TResolverMapAlias;
begin
  b := 0;

  with lCustomer do
  begin
    Name := lLocalOnly;
    lLocalOnly := Name;
    Abs(Succ(0));
    Round(1.0);
    Count := Min(Max(Count, 1), 10);
    Str(Size: 10, lLocalOnly);
    Pick(1);
    Save;
  end;

  with lCustomer, lAddress do
  begin
    Shared := City;
    Name := Shared;
  end;

  with lCustomer do
  begin
    with Address do
    begin
      City := Name;
    end;
  end;

  with lCustomer do
  begin
    with AddressProp do
    begin
      City := Name;
    end;
  end;

  with lExternal do
  begin
    Count := 1;
  end;

  with MakeCustomer() do
  begin
    Name := 'unsupported selector';
    Pick(1);
  end;

  with lCustomer do
  begin
    MissingMember := Name;
    UnknownProcedure;
  end;

  with lDuplicate do
  begin
    Clash;
  end;

  with lCustomer, b do
  begin
    B_Nr := 1;
    B_von := lLocalOnly.Length;
  end;
end;

end.
