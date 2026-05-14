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
type
  TNestedRoutineState = (nrsWriting, nrsSaving);
var
  ErrorFlag: Integer;
  i0: Integer;
  Mode: (nrsInlineWriting, nrsInlineSaving);
  State: TNestedRoutineState;

  procedure Inner;
  var
    lItem: TNestedRoutineRecord;
  begin
    with lItem do
    begin
      State := nrsSaving;
      Mode := nrsInlineSaving;
      if Mode = nrsInlineWriting then
        Count := Count + 2;
      if State = nrsWriting then
        Count := Count + 1;
      case State of
        nrsWriting:
          Count := Count + i0;
        nrsSaving:
          Count := Count + ErrorFlag;
      end;
      Count := i0 + ErrorFlag;
    end;
  end;

begin
  i0 := 1;
  ErrorFlag := 2;
  State := nrsWriting;
  Inner;
end;

end.
