unit RollbackUnit;

interface

type
  TRollbackRecord = record
    Name: string;
  end;

  PRollbackRecord = ^TRollbackRecord;

  TRollbackScope = class
  public
    class procedure Broken(aRecordPtr: PRollbackRecord);
  end;

implementation

class procedure TRollbackScope.Broken(aRecordPtr: PRollbackRecord);
begin
  with aRecordPtr^ do
  begin
    Name := 'rolled back';
  end;
end;

end.
