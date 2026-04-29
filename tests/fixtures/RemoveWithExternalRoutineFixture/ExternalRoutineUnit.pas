unit ExternalRoutineUnit;

interface

type
  TExternalRoutineFlag = (erfOne, erfTwo);
  TExternalRoutineFlags = set of TExternalRoutineFlag;

  TExternalRoutineRecord = record
    Count: Integer;
    Flag: TExternalRoutineFlag;
    Flags: TExternalRoutineFlags;
    Items: TArray<string>;
    Name: string;
    Ref: TObject;
  end;

  TExternalRoutineScope = class
  public
    class procedure Run;
  end;

implementation

class procedure TExternalRoutineScope.Run;
var
  lKnown: TExternalRoutineRecord;
  lUnknown: TExternalRoutineRecord;
begin
  with lKnown do
  begin
    Inc(Count);
    Dec(Count);
    if Assigned(Ref) then
      Count := Length(Items);
    SetLength(Items, Count + 1);
    if Low(Items) <= High(Items) then
      Name := Items[Low(Items)];
    Include(Flags, Flag);
    Exclude(Flags, Flag);
  end;

  with lUnknown do
  begin
    Count := Random(Count);
    Name := 'blocked';
  end;
end;

end.
