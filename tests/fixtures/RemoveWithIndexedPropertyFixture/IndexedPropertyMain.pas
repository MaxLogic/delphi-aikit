unit IndexedPropertyMain;

interface

type
  TIndexedRecord = record
    Name: string;
  end;

  TStaticRecordArray = array[0..1] of TIndexedRecord;
  PStaticRecordArray = ^TStaticRecordArray;

  TIndexedChild = record
    Items: TArray<TIndexedRecord>;
    StaticItems: TStaticRecordArray;
  end;

  TIndexedBox = class
  private
    FItems: TArray<TIndexedRecord>;
    function GetItem(const aIndex: Integer): TIndexedRecord;
  public
    property Items[const aIndex: Integer]: TIndexedRecord read GetItem; default;
  end;

  PIndexedRecord = ^TIndexedRecord;

  TPointerIndexedBox = class
  private
    FItems: TArray<PIndexedRecord>;
    function GetItem(const aIndex: Integer): PIndexedRecord;
  public
    property Items[const aIndex: Integer]: PIndexedRecord read GetItem; default;
  end;

  TIndexedScope = class
  private
    class function MakeBox: TIndexedBox; static;
  public
    class procedure Run;
  end;

implementation

function TIndexedBox.GetItem(const aIndex: Integer): TIndexedRecord;
begin
  Result := FItems[aIndex];
end;

function TPointerIndexedBox.GetItem(const aIndex: Integer): PIndexedRecord;
begin
  Result := FItems[aIndex];
end;

class function TIndexedScope.MakeBox: TIndexedBox;
begin
  Result := TIndexedBox.Create;
end;

class procedure TIndexedScope.Run;
var
  lBox: TIndexedBox;
  lNested: TArray<TIndexedChild>;
  lPointerBox: TPointerIndexedBox;
  lPointerRecord: TIndexedRecord;
  lRecords: TArray<TIndexedRecord>;
  lStaticRecordPtr: PStaticRecordArray;
  lStaticRecords: TStaticRecordArray;
begin
  SetLength(lRecords, 1);
  SetLength(lNested, 1);
  SetLength(lNested[0].Items, 1);
  lBox := MakeBox;
  lPointerBox := TPointerIndexedBox.Create;
  SetLength(lPointerBox.FItems, 1);
  lPointerBox.FItems[0] := @lPointerRecord;
  lStaticRecordPtr := @lStaticRecords;

  with lRecords[0] do
  begin
    Name := 'array';
  end;

  with lNested[0].Items[0] do
  begin
    Name := 'field array';
  end;

  with lBox.Items[0] do
  begin
    Name := 'indexed property';
  end;

  with lBox[0] do
  begin
    Name := 'default property';
  end;

  with MakeBox()[0] do
  begin
    Name := 'call';
  end;

  with lNested[0] do
  begin
    with Items[0] do
    begin
      Name := 'relative indexed field';
    end;
  end;

  with lStaticRecords[0] do
  begin
    Name := 'static array';
  end;

  with lStaticRecordPtr^[0] do
  begin
    Name := 'pointer static array';
  end;

  with lPointerBox[0]^ do
  begin
    Name := 'default pointer property';
  end;
end;

end.
