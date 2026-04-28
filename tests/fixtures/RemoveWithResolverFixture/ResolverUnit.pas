unit ResolverUnit;

interface

uses
  System.Classes;

type
  TResolverAddress = record
    City: string;
    Shared: string;
  end;

  TResolverCustomer = record
    Address: TResolverAddress;
    Name: string;
    Shared: string;
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
  lAddress: TResolverAddress;
  lCustomer: TResolverCustomer;
  lDuplicate: TDuplicateTarget;
  lExternal: TMissingReceiver;
  lLocalOnly: string;
begin
  with lCustomer do
  begin
    Name := lLocalOnly;
    lLocalOnly := Name;
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
  end;

  with lDuplicate do
  begin
    Clash;
  end;
end;

end.
