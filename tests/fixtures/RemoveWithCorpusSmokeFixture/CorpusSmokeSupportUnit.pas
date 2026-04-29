unit CorpusSmokeSupportUnit;

interface

type
  TCorpusMarkerAttribute = class(TCustomAttribute)
  private
    fName: string;
  public
    property Name: string read fName write fName;
  end;

  TCorpusItem = record
    Count: Integer;
    Name: string;
  end;

  TCorpusRight = record
    Common: string;
    RightOnly: string;
  end;

  [CorpusMarker(Name = 'attributed-record')]
  TCorpusAttributedRecord = record
    Name: string;
  end;

  TCorpusConditionalRecord = record
{$IFDEF DAK_CORPUS_DISABLED}
    Ghost: string;
{$ENDIF}
    Name: string;
  end;

  TCorpusQualifiedScope = class
  public
    class var DefaultName: string;
  end;

implementation

end.
