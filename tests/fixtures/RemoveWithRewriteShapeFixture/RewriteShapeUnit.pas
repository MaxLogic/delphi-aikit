unit RewriteShapeUnit;

interface

uses
  System.SysUtils;

const
  cRewriteShapeVariantHandle = 0;
  cRewriteShapeVariantPointer = 1;

type
  TRewriteShapeRecord = record
    Count: Integer;
    Name: string;
  end;

  TRewriteShapeNestedOuter = record
    OuterOnly: string;
  end;

  TRewriteShapeNestedInner = record
    InnerOnly: string;
  end;

  TRewriteShapeAnonymousOuter = record
    OuterOnly: string;
    Struktur: packed record
      InnerOnly: string;
    end;
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
    class procedure RunControlledBlockValueBeforeElse(var aRecord: TRewriteShapeRecord;
      aRecordPtr: PRewriteShapeRecord);
    class procedure RunControlled(aRecordPtr: PRewriteShapeRecord);
    class procedure RunControlledFor(aRecordPtr: PRewriteShapeRecord);
    class procedure RunControlledIf(aRecordPtr: PRewriteShapeRecord);
    class procedure RunControlledIfElseBody(aRecordPtr: PRewriteShapeRecord);
    class procedure RunHexLiteral(aRecordPtr: PRewriteShapeRecord);
    class procedure RunImplementationArray;
    class procedure RunAfterLabel(aRecordPtr: PRewriteShapeRecord);
    class procedure RunLocalRoutine(var aRecord: TRewriteShapeRecord);
    class procedure RunRecordValue(var aRecord: TRewriteShapeRecord);
    class procedure RunRecordValueWithOnlyLabel(var aRecord: TRewriteShapeRecord);
    class procedure RunRecordValueWithLabel(var aRecord: TRewriteShapeRecord);
    class procedure RunSingle(aRecordPtr: PRewriteShapeRecord);
    class procedure RunSingleBeforeElse(aLeftPtr, aRightPtr: PRewriteShapeRecord);
    class procedure RunControlledSingleBeforeElse(aLeftPtr, aRightPtr: PRewriteShapeRecord);
    class procedure RunAnonymousNestedSelector(var aOuter: TRewriteShapeAnonymousOuter);
    class procedure RunSingleNestedFor(var aOuter: TRewriteShapeNestedOuter;
      var aInner: TRewriteShapeNestedInner);
    class procedure RunSingleNested(var aOuter: TRewriteShapeNestedOuter; var aInner: TRewriteShapeNestedInner);
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

class procedure TRewriteShapeScope.RunControlledBlockValueBeforeElse(var aRecord: TRewriteShapeRecord;
  aRecordPtr: PRewriteShapeRecord);
begin
  if aRecordPtr <> nil then
    with aRecord do
    begin
      Name := 'controlled-block-value-before-else';
      Count := Count + 11;
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

class procedure TRewriteShapeScope.RunControlledIfElseBody(aRecordPtr: PRewriteShapeRecord);
begin
  if aRecordPtr <> nil then
    with aRecordPtr^ do
      if Count > 0 then
        Name := 'controlled-inner-if'
      else
        Name := 'controlled-inner-else';
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

class procedure TRewriteShapeScope.RunAfterLabel(aRecordPtr: PRewriteShapeRecord);
label
  Restore;
begin
Restore:
  with aRecordPtr^ do
  begin
    Name := 'after-label';
    Count := Count + 9;
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

class procedure TRewriteShapeScope.RunControlledSingleBeforeElse(aLeftPtr, aRightPtr: PRewriteShapeRecord);
begin
  if aLeftPtr <> nil then
    with aLeftPtr^ do
      Name := 'controlled-left-before-else'
  else
    with aRightPtr^ do
      Name := 'controlled-right-before-else';
end;

class procedure TRewriteShapeScope.RunAnonymousNestedSelector(var aOuter: TRewriteShapeAnonymousOuter);
begin
  with aOuter, Struktur do
  begin
    InnerOnly := OuterOnly;
  end;
end;

class procedure TRewriteShapeScope.RunSingleNestedFor(var aOuter: TRewriteShapeNestedOuter;
  var aInner: TRewriteShapeNestedInner);
var
  i: Integer;
begin
  with aOuter do
    for i := 1 to 1 do
      with aInner do
        InnerOnly := OuterOnly + IntToStr(i);
end;

class procedure TRewriteShapeScope.RunSingleNested(var aOuter: TRewriteShapeNestedOuter;
  var aInner: TRewriteShapeNestedInner);
begin
  with aOuter do
    with aInner do
      InnerOnly := OuterOnly;
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
