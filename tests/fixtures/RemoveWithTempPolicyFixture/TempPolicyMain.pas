unit TempPolicyMain;

interface

type
  TTempPolicyRecord = record
    Name: string;
  end;

  TTempPolicyClass = class
  public
    Name: string;
  end;

  TTempPolicyScope = class
  private
    FRecordProp: TTempPolicyRecord;
    function GetRecordProp: TTempPolicyRecord;
    class function MakeRecord: TTempPolicyRecord; static;
  public
    property RecordProp: TTempPolicyRecord read GetRecordProp;
    class procedure Run;
  end;

  PTempPolicyRecord = ^TTempPolicyRecord;

implementation

function TTempPolicyScope.GetRecordProp: TTempPolicyRecord;
begin
  Result := FRecordProp;
end;

class function TTempPolicyScope.MakeRecord: TTempPolicyRecord;
begin
  Result := Default(TTempPolicyRecord);
end;

class procedure TTempPolicyScope.Run;
var
  lIndex: Integer;
  lObject: TTempPolicyClass;
  lObjects: TArray<TTempPolicyClass>;
  lRecord: TTempPolicyRecord;
  lRecordPtr: PTempPolicyRecord;
  lRecords: TArray<TTempPolicyRecord>;
  lScope: TTempPolicyScope;
  lWithTempPolicyRecordPtr: ^TTempPolicyRecord;
  lWithTempPolicyRecordPtr1: ^TTempPolicyRecord;
begin
  lIndex := 0;
  lObject := TTempPolicyClass.Create;
  SetLength(lObjects, 1);
  lObjects[0] := lObject;
  SetLength(lRecords, 1);
  lRecordPtr := @lRecord;
  lScope := TTempPolicyScope.Create;
  lWithTempPolicyRecordPtr := @lRecord;
  lWithTempPolicyRecordPtr1 := @lRecord;

  with lRecord do
  begin
    Name := 'record';
  end;

  with lRecordPtr^ do
  begin
    Name := 'pointer';
  end;

  with lRecords[lIndex] do
  begin
    Name := 'indexed';
    Inc(lIndex);
  end;

  with lObject do
  begin
    Name := 'object';
  end;

  with lObjects[lIndex] do
  begin
    Name := 'indexed object';
  end;

  with lScope.RecordProp do
  begin
    Name := 'property';
  end;

  with MakeRecord() do
  begin
    Name := 'call';
  end;

  with TTempPolicyRecord(lRecord) do
  begin
    Name := 'cast';
  end;
end;

end.
