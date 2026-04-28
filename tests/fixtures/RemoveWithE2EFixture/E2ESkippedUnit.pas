unit E2ESkippedUnit;

interface

type
  TE2EChild = class
  private
    fName: string;
  public
    property Name: string read fName write fName;
  end;

  TE2EHolder = class
  private
    fChild: TE2EChild;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure KeepSkipped;
    property Child: TE2EChild read fChild;
  end;

implementation

constructor TE2EHolder.Create;
begin
  inherited Create;
  fChild := TE2EChild.Create;
end;

destructor TE2EHolder.Destroy;
begin
  fChild.Free;
  inherited Destroy;
end;

class procedure TE2EHolder.KeepSkipped;
var
  lHolder: TE2EHolder;
begin
  lHolder := TE2EHolder.Create;
  try
    with lHolder.Child do
    begin
      Name := 'skipped';
    end;
  finally
    lHolder.Free;
  end;
end;

end.
