program RemoveWithTempAggregationFixture;

uses
  TempAggregationUnit in 'TempAggregationUnit.pas';

var
  lFirstObject: TTempAggregationObject;
  lSecondObject: TTempAggregationObject;
  lFirstRecord: TTempAggregationRecord;
  lSecondRecord: TTempAggregationRecord;

begin
  lFirstObject := TTempAggregationObject.Create;
  try
    lSecondObject := TTempAggregationObject.Create;
    try
      TTempAggregationScope.ExistingVarSection(lFirstRecord, lSecondRecord);
      TTempAggregationScope.LocalRoutineBeforeBegin(lFirstRecord, lSecondRecord);
      TTempAggregationScope.Run(lFirstRecord, lSecondRecord, lFirstObject, lSecondObject);
    finally
      lSecondObject.Free;
    end;
  finally
    lFirstObject.Free;
  end;
end.
