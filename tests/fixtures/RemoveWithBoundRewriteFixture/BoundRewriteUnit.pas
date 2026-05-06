unit BoundRewriteUnit;

interface

type
  TBoundRewriteCast = record
    Name: string;
  end;

  TBoundRewriteRecord = record
    Count: Integer;
    Name: string;
  end;

  TBoundRewriteScope = class
  public
    class procedure Run; static;
  end;

implementation

class procedure TBoundRewriteScope.Run;
label
  BoundLabel;
var
  lCast: TBoundRewriteCast;
  lRecord: TBoundRewriteRecord;
begin
  lCast.Name := 'cast';

  with lRecord do
  begin
    goto BoundLabel;
BoundLabel:
    Name := TBoundRewriteCast(lCast).Name;
    Count := Count + 1;
  end;

  with lRecord do
  begin
    var Name := 'local';
    Count := Length(Name);
  end;
end;

end.
