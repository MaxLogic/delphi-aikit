unit NoEditBlockedUnit;

interface

type
  TNoEditBlockedRecord = record
    Name: string;
  end;

  PNoEditBlockedRecord = ^TNoEditBlockedRecord;

  TNoEditBlockedScope = class
  public
    class function MakeRecord: TNoEditBlockedRecord; static;
    class procedure KeepBlocked(aRecordPtr: PNoEditBlockedRecord);
  end;

implementation

class function TNoEditBlockedScope.MakeRecord: TNoEditBlockedRecord;
begin
  Result.Name := 'blocked';
end;

class procedure TNoEditBlockedScope.KeepBlocked(aRecordPtr: PNoEditBlockedRecord);
var
  lKind: Integer;
begin
  lKind := 1;
  case lKind of
    1:
      with MakeRecord do
      begin
        aRecordPtr^.Name := Name;
      end;
  end;
end;

end.
