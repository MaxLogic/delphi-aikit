unit RewriteShapeUnit;

interface

type
  TRewriteShapeRecord = record
    Count: Integer;
    Name: string;
  end;

  PRewriteShapeRecord = ^TRewriteShapeRecord;

  TRewriteShapeScope = class
  public
    class procedure RunBlock(aRecordPtr: PRewriteShapeRecord);
    class procedure RunSingle(aRecordPtr: PRewriteShapeRecord);
  end;

implementation

class procedure TRewriteShapeScope.RunBlock(aRecordPtr: PRewriteShapeRecord);
begin
  with aRecordPtr^ do
  begin
    Name := 'block';
    Count := Count + 1;
  end;
end;

class procedure TRewriteShapeScope.RunSingle(aRecordPtr: PRewriteShapeRecord);
begin
  with aRecordPtr^ do
    Name := 'single';
end;

end.
