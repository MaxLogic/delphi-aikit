unit ConditionalDirectiveUnit;

interface

type
  TConditionalDirectiveRecord = record
    Count: Integer;
  end;

  TConditionalDirectiveScope = class
  public
    class procedure Run;
  end;

implementation

class procedure TConditionalDirectiveScope.Run;
var
  lActive: TConditionalDirectiveRecord;
  lInactive: TConditionalDirectiveRecord;
begin
  with lActive do
  begin
    Count := Count + 1;
    {$IFDEF NEVER_DEFINED_REMOVE_WITH}InlineMissingSymbol := Count;
    {$ENDIF}
    {$IFDEF NEVER_DEFINED_REMOVE_WITH}
    ProgFun := Count;
    MissingInactiveSymbol := Count;
    {$ENDIF}
  end;

  {$IFDEF NEVER_DEFINED_REMOVE_WITH}
  with lInactive do
  begin
    ProgFun := Count;
    MissingInactiveSymbol := Count;
  end;
  {$ENDIF}

  {$IFDEF ACTIVE_REMOVE_WITH}
  with lActive do
  begin
    Count := Count + 2;
  end;
  {$ENDIF}
end;

end.
