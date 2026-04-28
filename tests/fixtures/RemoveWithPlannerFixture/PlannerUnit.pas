unit PlannerUnit;

interface

type
  TPlannerRecord = record
    Count: Integer;
    Name: string;
  end;

  PPlannerRecord = ^TPlannerRecord;

  TPlannerObject = class
  public
    Name: string;
  end;

  TPlannerScope = class
  private
    FRecord: TPlannerRecord;
    function GetRecord: TPlannerRecord;
    class function MakeRecord: TPlannerRecord; static;
  public
    property RecordProp: TPlannerRecord read GetRecord;
    class procedure Run;
    class procedure RunControlled;
    class procedure RunPointer(aRecordPtr: PPlannerRecord);
  end;

implementation

function TPlannerScope.GetRecord: TPlannerRecord;
begin
  Result := FRecord;
end;

class function TPlannerScope.MakeRecord: TPlannerRecord;
begin
  Result := Default(TPlannerRecord);
end;

class procedure TPlannerScope.Run;
var
  lObject: TPlannerObject;
  lRecord: TPlannerRecord;
  lScope: TPlannerScope;
begin
  lObject := TPlannerObject.Create;
  lScope := TPlannerScope.Create;

  with lRecord do
  begin
    Name := 'record';
    Count := Count + 1;
  end;

  with lObject do
  begin
    Name := 'object';
  end;

  with lScope.RecordProp do
  begin
    Name := 'property';
  end;

  with MakeRecord() do
  begin
    Name := 'call';
  end;
end;

class procedure TPlannerScope.RunControlled;
var
  lKind: Integer;
  lOk: Boolean;
  lRecord: TPlannerRecord;
begin
  lKind := 1;
  lOk := True;
  if lOk then
    // Comments must not hide the controlling then token from the planner.
    with lRecord do
    begin
      Name := 'controlled';
    end;

  case lKind of
    1:
      with lRecord do
      begin
        Name := 'case controlled';
      end;
  end;
end;

class procedure TPlannerScope.RunPointer(aRecordPtr: PPlannerRecord);
begin
  with aRecordPtr^ do
  begin
    Name := 'pointer';
  end;
end;

end.
