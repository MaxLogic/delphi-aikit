unit CorpusSmokeMainUnit;

interface

uses
  CorpusSmokeSupportUnit;

type
  TCorpusSmokeScope = class
  public
    class procedure Run;
  end;

implementation

class procedure TCorpusSmokeScope.Run;
label
  RetryLabel;
var
  lAttributed: TCorpusAttributedRecord;
  lConditional: TCorpusConditionalRecord;
  lLeft: TCorpusItem;
  lRight: TCorpusRight;
  lUnknown: TCorpusItem;
begin
RetryLabel:
  lLeft.Count := 1;

  with lLeft, lRight do
  begin
    Inc(Count);
    Common := Name;
    RightOnly := Common;
  end;

  with lAttributed do
  begin
    Name := 'attribute';
  end;

  with lConditional do
  begin
    Name := 'conditional';
  end;

  with lLeft do
  begin
    TCorpusQualifiedScope.DefaultName := Name;
  end;

  with lUnknown do
  begin
    Count := Random(Count);
    Name := 'unknown';
  end;

  if lLeft.Count < 0 then
    goto RetryLabel;
end;

end.
