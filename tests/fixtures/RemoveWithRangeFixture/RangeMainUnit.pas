unit RangeMainUnit;

interface

type
  TRangeRecord = record
    Name: string;
    Count: Integer;
    procedure Save;
  end;

  TRangeFactory = record
    class function Make(const aName: string): TRangeRecord; static;
  end;

  TRangeMainFixture = class
  public
    class procedure Run;
  end;

implementation

procedure TRangeRecord.Save;
begin
end;

class function TRangeFactory.Make(const aName: string): TRangeRecord;
begin
  Result.Name := aName;
end;

class procedure TRangeMainFixture.Run;
var
  lFactory: TRangeFactory;
  lIndex: Integer;
  lLeft: TRangeRecord;
  lMatrix: array[0..1, 0..1] of TRangeRecord;
  lRight: TRangeRecord;
begin
  lIndex := 0;

  with lMatrix[lIndex, 0],
    lFactory.Make('a,b') do
  begin
    Name := 'comma,inside';
    Save;
  end;

  with lLeft,
    {selector comment}
    lRight do
    Save;

  with lLeft, // selector line comment, with comma
    lRight do
    Save;

  with lLeft
    {$IFDEF MSWINDOWS}
    {$ENDIF}
    do
  begin
    Count := 1;
  end;

  with lLeft do
  begin
    with lRight do
      Count := lIndex;
  end;

  with lLeft do
    if lIndex = 0 then
    begin
      Name := 'if-body';
      Save;
    end;
end;

end.
