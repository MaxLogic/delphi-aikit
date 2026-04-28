unit NestedControlledUnit;

interface

type
  TNestedControlledInner = class
  private
    fShared: string;
  public
    property Shared: string read fShared write fShared;
  end;

  TNestedControlledOuter = class
  private
    fOuterOnly: string;
  public
    property OuterOnly: string read fOuterOnly write fOuterOnly;
  end;

  TNestedControlledScope = class
  public
    class procedure Run;
  end;

implementation

class procedure TNestedControlledScope.Run;
var
  lCondition: Boolean;
  lInner: TNestedControlledInner;
  lOuter: TNestedControlledOuter;
begin
  lOuter := TNestedControlledOuter.Create;
  lInner := TNestedControlledInner.Create;
  try
    lCondition := True;
    with lOuter do
    begin
      if lCondition then
        with lInner do
          Shared := 'controlled';
      OuterOnly := 'outer';
    end;
  finally
    lInner.Free;
    lOuter.Free;
  end;
end;

end.
