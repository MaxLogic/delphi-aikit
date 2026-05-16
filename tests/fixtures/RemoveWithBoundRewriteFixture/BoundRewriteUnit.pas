unit BoundRewriteUnit;

interface

type
  TBoundRewriteCast = record
    Name: string;
  end;

  TBoundRewriteRecord = record
    Child: ^TBoundRewriteRecord;
    Count: Integer;
    Limit: Integer;
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

  with lRecord do
  begin
    if Child <> nil then
      Count := Count + 1;
  end;

  with lRecord do
  begin
    if Count<Limit then
      Count := Limit
    else if Limit>0 then
      Count := 0;
  end;
end;

end.
