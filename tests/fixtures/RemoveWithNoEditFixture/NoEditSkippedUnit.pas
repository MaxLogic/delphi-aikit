unit NoEditSkippedUnit;

interface

type
  TNoEditChild = class
  private
    fName: string;
  public
    property Name: string read fName write fName;
  end;

  TNoEditHolder = class
  private
    fChild: TNoEditChild;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure KeepSkipped;
    property Child: TNoEditChild read fChild;
  end;

implementation

constructor TNoEditHolder.Create;
begin
  inherited Create;
  fChild := TNoEditChild.Create;
end;

destructor TNoEditHolder.Destroy;
begin
  fChild.Free;
  inherited Destroy;
end;

class procedure TNoEditHolder.KeepSkipped;
var
  lHolder: TNoEditHolder;
begin
  lHolder := TNoEditHolder.Create;
  try
    lHolder.Child.Name := 'ready';
    with lHolder.Child do
    begin
      Name := 'skipped';
    end;
  finally
    lHolder.Free;
  end;
end;

end.
