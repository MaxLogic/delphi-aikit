unit ApplyUnit;

interface

type
  TApplyRecord = record
    Count: Integer;
    Name: string;
  end;

  PApplyRecord = ^TApplyRecord;

  TApplyScope = class
  public
    class procedure Run(aRecordPtr: PApplyRecord);
  end;

implementation

class procedure TApplyScope.Run(aRecordPtr: PApplyRecord);
begin
  with aRecordPtr^ do
  begin
    Name := 'applied';
    Count := Count + 1;
  end;
end;

end.
