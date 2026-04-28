unit SourceModelGoldenUnit;

interface

type
  TGoldenChild = record
    Name: string;
  end;

  TGoldenRecord = record
    RecordName: string;
    Child: TGoldenChild;
    procedure Touch;
    property RecordTitle: string read RecordName write RecordName;
  end;

  PGoldenRecord = ^TGoldenRecord;

  TGoldenClass = class
  private
    FClassRecord: TGoldenRecord;
  public
    const
      ClassLimit: Integer = 7;
    class var
      SharedCount: Integer;
    procedure Touch;
    property ClassRecord: TGoldenRecord read FClassRecord write FClassRecord;
  end;

  TGoldenScope = class
  private
    FScopeRecord: TGoldenRecord;
  public
    class procedure Run;
  end;

implementation

procedure TGoldenRecord.Touch;
begin
end;

procedure TGoldenClass.Touch;
begin
  Inc(SharedCount);
end;

class procedure TGoldenScope.Run;
var
  lObject: TGoldenClass;
  lRecord: TGoldenRecord;
  lRecordPtr: PGoldenRecord;
  lRecords: TArray<TGoldenRecord>;
begin
  lRecord.RecordName := '';
  lRecord.Child.Name := lRecord.RecordName;
  lRecordPtr := @lRecord;
  SetLength(lRecords, 1);
  lRecords[0] := lRecordPtr^;
  FScopeRecord := lRecords[0];
  lObject := TGoldenClass.Create;
  try
    lObject.FClassRecord := FScopeRecord;
  finally
    lObject.Free;
  end;
end;

end.
