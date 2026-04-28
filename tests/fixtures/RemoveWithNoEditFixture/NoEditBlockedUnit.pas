unit NoEditBlockedUnit;

interface

type
  TNoEditBlockedRecord = record
    Name: string;
  end;

  PNoEditBlockedRecord = ^TNoEditBlockedRecord;

  TNoEditBlockedScope = class
  public
    class procedure KeepBlocked(aRecordPtr: PNoEditBlockedRecord);
  end;

implementation

class procedure TNoEditBlockedScope.KeepBlocked(aRecordPtr: PNoEditBlockedRecord);
begin
  if aRecordPtr <> nil then
    with aRecordPtr^ do
    begin
      Name := 'blocked';
    end;
end;

end.
