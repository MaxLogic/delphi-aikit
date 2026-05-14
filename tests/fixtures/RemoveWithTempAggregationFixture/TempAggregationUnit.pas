unit TempAggregationUnit;

interface

type
  TTempAggregationRecord = record
    Count: Integer;
    Name: string;
  end;

  TTempAggregationObject = class
  public
    Count: Integer;
    Name: string;
  end;

  TTempAggregationScope = class
  public
    class procedure ExistingVarSection(aFirstRecord, aSecondRecord: TTempAggregationRecord);
    class procedure ExistingVarSectionWithBeginComment(aFirstRecord: TTempAggregationRecord);
    class procedure LocalRoutineBeforeBegin(aFirstRecord, aSecondRecord: TTempAggregationRecord);
    class procedure Run(aFirstRecord, aSecondRecord: TTempAggregationRecord; aFirstObject,
      aSecondObject: TTempAggregationObject);
  end;

implementation

class procedure TTempAggregationScope.ExistingVarSection(aFirstRecord, aSecondRecord: TTempAggregationRecord);
var
  lMarker: Integer;
begin
  lMarker := 0;
  with aFirstRecord do
  begin
    Count := lMarker + Count;
  end;

  with aSecondRecord do
  begin
    Count := lMarker + Count;
  end;
end;

class procedure TTempAggregationScope.ExistingVarSectionWithBeginComment(aFirstRecord: TTempAggregationRecord);
var
  lMarker: Integer;
begin {comment after begin must still terminate the var section}
  lMarker := 1;
  with aFirstRecord do
  begin
    Count := lMarker + Count;
  end;
end;

class procedure TTempAggregationScope.LocalRoutineBeforeBegin(aFirstRecord, aSecondRecord: TTempAggregationRecord);
  procedure TouchLocal;
  begin
  end;
begin
  TouchLocal;
  with aFirstRecord do
  begin
    Count := Count + 1;
  end;

  with aSecondRecord do
  begin
    Count := Count + 1;
  end;
end;

class procedure TTempAggregationScope.Run(aFirstRecord, aSecondRecord: TTempAggregationRecord; aFirstObject,
  aSecondObject: TTempAggregationObject);
begin
  with aFirstRecord do
  begin
    Name := 'first record';
    Count := Count + 1;
  end;

  with aSecondRecord do
  begin
    Name := 'second record';
    Count := Count + 1;
  end;

  with aFirstObject do
  begin
    Name := 'first object';
    Count := Count + 1;
  end;

  with aSecondObject do
  begin
    Name := 'second object';
    Count := Count + 1;
  end;
end;

end.
