unit IndexedPropertyMain;

interface

type
  TIndexedRecord = record
    Name: string;
  end;

  TIndexedChild = record
    Items: TArray<TIndexedRecord>;
  end;

  TIndexedBox = class
  private
    FItems: TArray<TIndexedRecord>;
    function GetItem(const aIndex: Integer): TIndexedRecord;
  public
    property Items[const aIndex: Integer]: TIndexedRecord read GetItem; default;
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

class function TIndexedScope.MakeBox: TIndexedBox;
begin
  Result := TIndexedBox.Create;
end;

class procedure TIndexedScope.Run;
var
  lBox: TIndexedBox;
  lNested: TArray<TIndexedChild>;
  lRecords: TArray<TIndexedRecord>;
begin
  SetLength(lRecords, 1);
  SetLength(lNested, 1);
  SetLength(lNested[0].Items, 1);
  lBox := MakeBox;

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
end;

end.
