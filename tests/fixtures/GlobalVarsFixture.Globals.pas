unit GlobalVarsFixture.Globals;

interface

type
  TGlobalStore = class
  public
    class var sCache: Integer;
  end;

var
  GCounter: Integer;
  GUnusedValue: Integer;
threadvar
  GThreadCounter: Integer;
const
  GTypedValue: Integer = 7;

procedure TouchGlobals;

implementation

procedure TouchGlobals;
begin
  Inc(GCounter);
  GThreadCounter := GCounter;
  TGlobalStore.sCache := GTypedValue;
end;

end.
