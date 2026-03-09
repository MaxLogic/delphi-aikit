unit GlobalVarsFixture.Consumer;

interface

procedure RunConsumer;

implementation

uses
  GlobalVarsFixture.Globals;

procedure RunConsumer;
begin
  GCounter := GCounter + 1;
  if GThreadCounter > 0 then
  begin
    TGlobalStore.sCache := GCounter + GTypedValue;
  end;
  TouchGlobals;
end;

end.
