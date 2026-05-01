unit NestedRoutineScopeUnit;

interface

type
  TNestedRoutineRecord = record
    Count: Integer;
  end;

  TNestedRoutineScope = class
  public
    class procedure Run;
  end;

implementation

class procedure TNestedRoutineScope.Run;
var
  ErrorFlag: Integer;
  i0: Integer;

  procedure Inner;
  var
    lItem: TNestedRoutineRecord;
  begin
    with lItem do
    begin
      Count := i0 + ErrorFlag;
    end;
  end;

begin
  i0 := 1;
  ErrorFlag := 2;
  Inner;
end;

end.
