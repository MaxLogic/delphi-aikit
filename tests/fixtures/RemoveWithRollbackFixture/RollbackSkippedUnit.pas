unit RollbackSkippedUnit;

interface

type
  TRollbackSkippedChild = class
  private
    fName: string;
  public
    property Name: string read fName write fName;
  end;

  TRollbackSkippedHolder = class
  private
    fChild: TRollbackSkippedChild;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure KeepSkipped;
    property Child: TRollbackSkippedChild read fChild;
  end;

implementation

constructor TRollbackSkippedHolder.Create;
begin
  inherited Create;
  fChild := TRollbackSkippedChild.Create;
end;

destructor TRollbackSkippedHolder.Destroy;
begin
  fChild.Free;
  inherited Destroy;
end;

class procedure TRollbackSkippedHolder.KeepSkipped;
var
  lHolder: TRollbackSkippedHolder;
begin
  lHolder := TRollbackSkippedHolder.Create;
  try
    lHolder.Child.Name := 'ready';
    with lHolder.Child do
    begin
      Name := 'skipped rollback';
    end;
  finally
    lHolder.Free;
  end;
end;

end.
