unit TempRewriteUnit;

interface

type
  TTempRewriteRecord = record
    Count: Integer;
    Name: string;
    procedure Touch;
  end;

  PTempRewriteRecord = ^TTempRewriteRecord;

  TTempRewriteObject = class
  private
    fChildObject: TTempRewriteObject;
    fName: string;
    fRecordValue: TTempRewriteRecord;
  public
    constructor Create;
    destructor Destroy; override;
    property ChildObject: TTempRewriteObject read fChildObject;
    property Name: string read fName write fName;
    property RecordValue: TTempRewriteRecord read fRecordValue;
  end;

  TTempRewriteScope = class
  public
    class function MakeObject: TTempRewriteObject;
    class procedure Run(aRecordPtr: PTempRewriteRecord);
  end;

implementation

procedure TTempRewriteRecord.Touch;
begin
end;

constructor TTempRewriteObject.Create;
begin
  inherited Create;
  fChildObject := nil;
end;

destructor TTempRewriteObject.Destroy;
begin
  fChildObject.Free;
  inherited Destroy;
end;

class function TTempRewriteScope.MakeObject: TTempRewriteObject;
begin
  Result := TTempRewriteObject.Create;
end;

class procedure TTempRewriteScope.Run(aRecordPtr: PTempRewriteRecord);
var
  lObject: TTempRewriteObject;
  lRecord: TTempRewriteRecord;
  lWithTempRewriteObject: TTempRewriteObject;
begin
  lObject := TTempRewriteObject.Create;
  lObject.fChildObject := TTempRewriteObject.Create;
  lWithTempRewriteObject := nil;
  try
    aRecordPtr^.Count := 0;
    with aRecordPtr^ do
    begin
      Name := 'direct';
    end;

    with lRecord do
    begin
      Name := 'record';
      Count := Count + 1;
    end;

    with lObject do
    begin
      Name := 'object';
    end;

    with lObject.ChildObject do
    begin
      Name := 'property';
    end;

    with lObject.RecordValue do
    begin
      Touch;
    end;

    with TTempRewriteObject(lObject) do
    begin
      Name := 'cast';
    end;

    with MakeObject do
    begin
      Name := 'function';
      Free;
    end;
  finally
    lObject.Free;
  end;
end;

end.
