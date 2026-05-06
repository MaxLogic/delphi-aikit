unit SymbolMapMembers;

interface

type
  TMemberRecord = record
    RecordField: Integer;
    procedure Reset;
    property DisplayName: Integer read RecordField;
  end;

  TMemberClass = class
  private
    FName: string;
    FItems: TArray<string>;
    FEnabled: Boolean;
    function GetItem(const aIndex: Integer): string;
    function GetNamedItem(const aName: string; const aIndex: Integer): string;
  public
    ClassField: Integer;
    procedure Run(const aName: string); virtual;
    function Count: Integer;
    property Name: string read FName write FName;
    property Enabled: Boolean read FEnabled write FEnabled default True;
    property Items[const aIndex: Integer]: string read GetItem; default;
    property MultiItems[const aName: string; const aIndex: Integer]: string read GetNamedItem;
  end;

  TDefaultVisibilityClass = class
    DefaultField: Integer;
    property DefaultProperty: Integer read DefaultField;
  end;

  IMemberInterface = interface
    procedure Touch;
    function GetCaption: string;
    property Caption: string read GetCaption;
  end;

  TMemberRecordHelper = record helper for TMemberRecord
    procedure Normalize;
    property HelperValue: Integer read RecordField;
  end;

implementation

procedure TMemberRecord.Reset;
begin
end;

function TMemberClass.GetItem(const aIndex: Integer): string;
begin
  Result := FItems[aIndex];
end;

function TMemberClass.GetNamedItem(const aName: string; const aIndex: Integer): string;
begin
  Result := aName + FItems[aIndex];
end;

procedure TMemberClass.Run(const aName: string);
begin
  FName := aName;
end;

function TMemberClass.Count: Integer;
begin
  Result := Length(FItems);
end;

procedure TMemberRecordHelper.Normalize;
begin
end;

end.
