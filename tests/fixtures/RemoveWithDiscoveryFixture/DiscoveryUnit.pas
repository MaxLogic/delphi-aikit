unit DiscoveryUnit;

interface

type
  TDiscoveryRecord = record
    Count: Integer;
    Name: string;
    procedure Save;
  end;

  TDiscoveryFixture = class
  public
    class procedure Run;
  end;

implementation

procedure TDiscoveryRecord.Save;
begin
end;

class procedure TDiscoveryFixture.Run;
var
  lLeft: TDiscoveryRecord;
  lRight: TDiscoveryRecord;
begin
  with lLeft do
  begin
    Name := 'single';
    Save;
  end;

  with lLeft,
    lRight do
  begin
    Count := 2;
  end;

  with lLeft do
  begin
    with lRight do
    begin
      Name := 'nested';
    end;
  end;
end;

end.
