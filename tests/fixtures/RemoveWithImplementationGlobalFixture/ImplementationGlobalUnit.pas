unit ImplementationGlobalUnit;

interface

type
  TImplementationGlobalRecord = record
    Count: Integer;
  end;

  TImplementationGlobalScope = class
  public
    class procedure Run;
  end;

implementation

procedure EarlierImplementationRoutine;
begin
end;

var
  gCounter: Integer;
  gSplitCounter:
    Integer;

const
  cAfterRoutine = 7;

class procedure TImplementationGlobalScope.Run;
var
  lItem: TImplementationGlobalRecord;
begin
  with lItem do
  begin
    Count := gCounter + gSplitCounter + cAfterRoutine;
  end;
end;

end.
