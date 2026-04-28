unit NestedWithUnit;

interface

type
  TNestedInner = class
  private
    fInnerOnly: string;
    fShared: string;
  public
    property InnerOnly: string read fInnerOnly write fInnerOnly;
    property Shared: string read fShared write fShared;
  end;

  TNestedOuter = class
  private
    fOuterOnly: string;
    fShared: string;
  public
    property OuterOnly: string read fOuterOnly write fOuterOnly;
    property Shared: string read fShared write fShared;
  end;

  TNestedScope = class
  public
    class procedure Run;
  end;

implementation

class procedure TNestedScope.Run;
var
  lInner: TNestedInner;
  lMarker: string;
  lOuter: TNestedOuter;
begin
  lOuter := TNestedOuter.Create;
  lInner := TNestedInner.Create;
  try
    lMarker := 'before';
    with lOuter do
    begin
      Shared := lMarker;
      lMarker := 'between';
      with lInner do
      begin
        Shared := lMarker;
        InnerOnly := Shared;
        OuterOnly := 'outer-from-inner';
      end;
      lMarker := 'after-inner';
      OuterOnly := lMarker;
    end;
    lMarker := 'after';
  finally
    lInner.Free;
    lOuter.Free;
  end;
end;

end.
