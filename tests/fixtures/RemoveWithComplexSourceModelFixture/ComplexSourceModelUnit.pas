unit ComplexSourceModelUnit;

interface

type
  TComplexMarkerAttribute = class(TCustomAttribute)
  end;

  [ComplexMarker]
  TComplexAttributedRecord = record
    Name: string;
  end;

  TComplexConditionalRecord = record
{$IFDEF DAK_COMPLEX_DISABLED}
    Ghost: string;
{$ENDIF}
    Name: string;
  end;

  TComplexMultilineRecord = record
    FirstName,
    LastName: string;
  end;

  TComplexGenericRecord<T> = record
    Value: T;
  end;

  TComplexOuterRecord = record
  type
    TNested = record
      NestedName: string;
    end;
  public
    Name: string;
  end;

  TComplexSafeRecord = record
    SafeName: string;
  end;

  TComplexSourceModelScope = class
  public
    class procedure Run;
  end;

implementation

class procedure TComplexSourceModelScope.Run;
var
  lAttributed: TComplexAttributedRecord;
  lConditional: TComplexConditionalRecord;
  lGeneric: TComplexGenericRecord<string>;
  lMultiline: TComplexMultilineRecord;
  lOuter: TComplexOuterRecord;
  lSafe: TComplexSafeRecord;
  Ghost: string;
begin
  Ghost := 'local';

  with lAttributed do
  begin
    Name := 'attributed';
  end;

  with lConditional do
  begin
    Ghost := 'still local';
    Name := Ghost;
  end;

  with lMultiline do
  begin
    FirstName := 'first';
    LastName := FirstName;
  end;

  with lGeneric do
  begin
    Value := 'generic';
  end;

  with lOuter do
  begin
    Name := 'outer';
  end;

  with lSafe do
  begin
    SafeName := 'safe';
  end;
end;

end.
