unit ControlCharacterLiteralUnit;

interface

type
  TControlCharacterRecord = record
    Count: Integer;
    Text: string;
  end;

  TControlCharacterScope = class
  public
    class procedure Run;
  end;

implementation

class procedure TControlCharacterScope.Run;
var
  lKnown: TControlCharacterRecord;
  lOther: TControlCharacterRecord;
  lOtherPtr: ^TControlCharacterRecord;
begin
  lOtherPtr := @lOther;
  with lKnown do
  begin
    Text := 'row' + ^J + ^m + ^I;
    Count := lOtherPtr^.Count + Count;
  end;
end;

end.
