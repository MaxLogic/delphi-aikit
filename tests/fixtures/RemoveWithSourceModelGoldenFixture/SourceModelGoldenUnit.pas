unit SourceModelGoldenUnit;

interface

const
  cGoldenVariantReal = 1;
  cGoldenVariantString = 2;

type
  TGoldenChild = record
    Name: string;
  end;

  TGoldenVariant = record
    Prefix: Integer;
    MultiA,
      MultiB: Integer;
    case Mode: Integer of
      cGoldenVariantReal: (RealValue, ExtraReal: Double;
        HasReal: Boolean);
      cGoldenVariantString: (TextValue: string; Offset, Size: Integer)
  end;

  TGoldenRecord = record
    RecordName: string;
    Child: TGoldenChild;
    procedure Touch;
    property RecordTitle: string read RecordName write RecordName;
  end;

  PGoldenRecord = ^TGoldenRecord;

  TGoldenDefaultList = class
  private
    function GetItem(aIndex: Integer): PGoldenRecord;
  public
    property Items[aIndex: Integer]: PGoldenRecord read GetItem; default;
  end;

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

function TGoldenDefaultList.GetItem(aIndex: Integer): PGoldenRecord;
begin
  Result := nil;
end;

class procedure TGoldenScope.Run;
var
  lDefaultList: TGoldenDefaultList;
  lObject: TGoldenClass;
  lRecord: TGoldenRecord;
  lRecordPtr: PGoldenRecord;
  lRecords: TArray<TGoldenRecord>;
  lStaticRecordPtrs: array[1..2] of PGoldenRecord;
  lStaticRecords: array [1 .. 2] of TGoldenRecord;
begin
  lRecord.RecordName := '';
  lRecord.Child.Name := lRecord.RecordName;
  lRecordPtr := @lRecord;
  SetLength(lRecords, 1);
  lRecords[0] := lRecordPtr^;
  lStaticRecords[1] := lRecord;
  lStaticRecordPtrs[1] := @lRecord;
  lDefaultList := nil;
  FScopeRecord := lRecords[0];
  lObject := TGoldenClass.Create;
  try
    lObject.FClassRecord := FScopeRecord;
  finally
    lObject.Free;
  end;
end;

end.
