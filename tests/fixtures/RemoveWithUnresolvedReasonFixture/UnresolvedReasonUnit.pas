unit UnresolvedReasonUnit;

interface

type
  TUnresolvedReasonRecord = record
    Count: Integer;
  end;

  TUnresolvedReasonScope = class
  public
    class procedure Run;
  end;

implementation

class procedure TUnresolvedReasonScope.Run;
var
  lItem: TUnresolvedReasonRecord;
begin
  with lItem do
  begin
    Count := UnknownProjectRoutine(Count);
  end;
end;

end.
