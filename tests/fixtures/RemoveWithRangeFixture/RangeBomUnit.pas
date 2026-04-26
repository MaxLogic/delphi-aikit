unit RangeBomUnit;

interface

type
  TRangeBomRecord = record
    Value: Integer;
  end;

  TRangeBomFixture = class
  public
    class procedure Run;
  end;

implementation

class procedure TRangeBomFixture.Run;
var
  lBom: TRangeBomRecord;
begin
  with lBom do
    Value := 1;
end;

end.
