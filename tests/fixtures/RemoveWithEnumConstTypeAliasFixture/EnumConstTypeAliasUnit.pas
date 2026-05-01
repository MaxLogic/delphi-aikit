unit EnumConstTypeAliasUnit;

interface

type
  TAliasInt = Integer;
  TOpcode = (
    P_JZ,
    P_JMP,
    _FALLS
  );

  TEnumConstTypeAliasRecord = record
    Count: Integer;
  end;

  TEnumConstTypeAliasScope = class
  public
    class procedure Run;
  end;

const
  TypedLimit: TAliasInt = 5;

implementation

class procedure TEnumConstTypeAliasScope.Run;
var
  lItem: TEnumConstTypeAliasRecord;
begin
  with lItem do
  begin
    Count := Ord(P_JZ) + Ord(P_JMP) + Ord(_FALLS) + TypedLimit + SizeOf(TAliasInt);
  end;
end;

end.
