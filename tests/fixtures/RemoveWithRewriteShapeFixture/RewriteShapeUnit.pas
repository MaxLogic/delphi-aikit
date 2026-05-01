unit RewriteShapeUnit;

interface

const
  cRewriteShapeVariantHandle = 0;
  cRewriteShapeVariantPointer = 1;

type
  TRewriteShapeRecord = record
    Count: Integer;
    Name: string;
  end;

  TRewriteShapeVariant = record
    Prefix: Integer;
    case Mode: Integer of
      cRewriteShapeVariantHandle:
        (Handle: Integer);
      cRewriteShapeVariantPointer:
        (Ptr: Pointer; Offset, Size: Integer)
  end;

  PRewriteShapeRecord = ^TRewriteShapeRecord;
  PRewriteShapeVariant = ^TRewriteShapeVariant;

  TRewriteShapeScope = class
  public
    class procedure RunBlock(aRecordPtr: PRewriteShapeRecord);
    class procedure RunControlledBlock(aRecordPtr: PRewriteShapeRecord);
    class procedure RunControlled(aRecordPtr: PRewriteShapeRecord);
    class procedure RunControlledFor(aRecordPtr: PRewriteShapeRecord);
    class procedure RunControlledIf(aRecordPtr: PRewriteShapeRecord);
    class procedure RunHexLiteral(aRecordPtr: PRewriteShapeRecord);
    class procedure RunImplementationArray;
    class procedure RunLocalRoutine(var aRecord: TRewriteShapeRecord);
    class procedure RunRecordValue(var aRecord: TRewriteShapeRecord);
    class procedure RunRecordValueWithOnlyLabel(var aRecord: TRewriteShapeRecord);
    class procedure RunRecordValueWithLabel(var aRecord: TRewriteShapeRecord);
    class procedure RunSingle(aRecordPtr: PRewriteShapeRecord);
    class procedure RunSingleBeforeElse(aLeftPtr, aRightPtr: PRewriteShapeRecord);
    class procedure RunVariant(aVariantPtr: PRewriteShapeVariant);
  end;

implementation

type
  TRewriteShapeImplementationItem = record
    LocalCount: Integer;
    LocalName: string;
  end;

class procedure TRewriteShapeScope.RunBlock(aRecordPtr: PRewriteShapeRecord);
begin
  with aRecordPtr^ do
  begin
    Name := 'block';
    Count := Count + 1;
  end;
end;

class procedure TRewriteShapeScope.RunControlled(aRecordPtr: PRewriteShapeRecord);
begin
  if aRecordPtr <> nil then
    with aRecordPtr^ do
      Name := 'controlled';
end;

class procedure TRewriteShapeScope.RunControlledBlock(aRecordPtr: PRewriteShapeRecord);
begin
  if aRecordPtr <> nil then
    with aRecordPtr^ do
    begin
      Name := 'controlled-block';
      Count := Count + 3;
    end
  else
    aRecordPtr^.Name := 'else';
end;

class procedure TRewriteShapeScope.RunControlledFor(aRecordPtr: PRewriteShapeRecord);
var
  i: Integer;
begin
  for i := 1 to 1 do
    with aRecordPtr^ do
      if Count > 0 then
        Count := Count + i;
end;

class procedure TRewriteShapeScope.RunControlledIf(aRecordPtr: PRewriteShapeRecord);
begin
  if aRecordPtr <> nil then
    with aRecordPtr^ do
      if Count > 0 then
        Name := 'controlled-if';
end;

class procedure TRewriteShapeScope.RunHexLiteral(aRecordPtr: PRewriteShapeRecord);
begin
  with aRecordPtr^ do
  begin
    if (Count and $7FFF) > 0 then
      Count := Count + $FFFF;
  end;
end;

class procedure TRewriteShapeScope.RunImplementationArray;
var
  lIndex: Integer;
  lItems: array [1 .. 4] of TRewriteShapeImplementationItem;

  function LocalIndex: Integer;
  begin
    Result := lIndex;
  end;

begin
  lIndex := 1;
  with lItems[LocalIndex] do
  begin
    LocalName := 'implementation-array';
    LocalCount := LocalCount + 1;
  end;
end;

class procedure TRewriteShapeScope.RunLocalRoutine(var aRecord: TRewriteShapeRecord);

  function LocalCount(var aLocalRecord: TRewriteShapeRecord): Integer;
  begin
    with aLocalRecord do
    begin
      Name := 'local-routine';
      Count := Count + 5;
      Result := Count;
    end;
  end;

begin
  aRecord.Count := LocalCount(aRecord);
  with aRecord do
  begin
    Name := 'after-local-routine';
    Count := Count + 6;
  end;
end;

class procedure TRewriteShapeScope.RunRecordValue(var aRecord: TRewriteShapeRecord);
begin
  with aRecord do
  begin
    Name := 'record-value';
    Count := Count + 2;
  end
end;

class procedure TRewriteShapeScope.RunRecordValueWithOnlyLabel(var aRecord: TRewriteShapeRecord);
label
  Done;
begin
  with aRecord do
  begin
    Name := 'record-only-label';
    Count := Count + 7;
  end;
Done:
  aRecord.Count := aRecord.Count + 1;
end;

class procedure TRewriteShapeScope.RunRecordValueWithLabel(var aRecord: TRewriteShapeRecord);
var
  lFlag: Boolean;
label
  Done;
begin
  lFlag := False;
  with aRecord do
  begin
    Name := 'record-label';
    Count := Count + 4;
  end;
Done:
  if lFlag then
    aRecord.Count := aRecord.Count + 1;
end;

class procedure TRewriteShapeScope.RunSingle(aRecordPtr: PRewriteShapeRecord);
begin
  with aRecordPtr^ do
    Name := 'single';
end;

class procedure TRewriteShapeScope.RunSingleBeforeElse(aLeftPtr, aRightPtr: PRewriteShapeRecord);
begin
  if aLeftPtr <> nil then
  begin
    with aLeftPtr^ do
      Name := 'left'
  end else begin
    with aRightPtr^ do
      Name := 'right';
  end;
end;

class procedure TRewriteShapeScope.RunVariant(aVariantPtr: PRewriteShapeVariant);
begin
  with aVariantPtr^ do
  begin
    Mode := 1;
    Handle := Prefix + 1;
    Ptr := nil;
    if Mode = cRewriteShapeVariantPointer then
      Offset := Size;
  end;
end;

end.
