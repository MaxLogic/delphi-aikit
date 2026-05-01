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
var
  lKind: Integer;
begin
  lKind := 1;
  case lKind of
    1:
      with aRecordPtr^ do
      begin
        Name := 'blocked';
      end;
  end;
end;

end.
