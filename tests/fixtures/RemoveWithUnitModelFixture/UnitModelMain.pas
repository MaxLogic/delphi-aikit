unit UnitModelMain;

interface

uses
  System.Generics.Collections, System.SysUtils;

type
  IUnitModelFace = interface
    ['{3F28CC93-FDD9-4F3F-A8D7-B82A04E8F53A}']
    function GetCaption: string;
    property Caption: string read GetCaption;
  end;

  TUnitModelAlias = string;

  TUnitModelMultilineRecord =
    record
      Value: Integer;
    end;

  TUnitModelRecord = record
    FieldName: string;
    Values: TArray<Integer>;
    procedure Reset;
    property Caption: string read FieldName write FieldName;
  end;

  PUnitModelRecord = ^TUnitModelRecord;

  TUnitModelRecordPtr = ^TUnitModelRecord;

  PUnitModelAmount = Integer;

  TUnitModelRecordArray = TArray<TUnitModelRecord>;

  TUnitModelMapAlias = TDictionary<string, Integer>;

  TUnitModelClass = class(TInterfacedObject, IUnitModelFace)
  private
    FRecord: TUnitModelRecord;
    function GetCaption: string;
    function GetItem(const aIndex: Integer): Integer;
  public
    const
      DefaultSize: Integer = 4;
    class var
      Shared: Integer;
    procedure Reset; virtual;
    property Items[const aIndex: Integer]: Integer read GetItem; default;
    property RecordValue: TUnitModelRecord read FRecord write FRecord;
  end;

  TUnitModelRecordHelper = record helper for TUnitModelRecord
    function HelperText: string;
  end;

  TUnitModelScope = class
  public
    class procedure Run(const aParam: TUnitModelRecord);
  end;

implementation

procedure TUnitModelRecord.Reset;
begin
  FieldName := '';
end;

function TUnitModelClass.GetCaption: string;
begin
  Result := FRecord.FieldName;
end;

function TUnitModelClass.GetItem(const aIndex: Integer): Integer;
begin
  Result := aIndex;
end;

procedure TUnitModelClass.Reset;
begin
  FRecord.Reset;
end;

function TUnitModelRecordHelper.HelperText: string;
begin
  Result := FieldName;
end;

class procedure TUnitModelScope.Run(const aParam: TUnitModelRecord);
var
  lClass: TUnitModelClass;
  lPtr: PUnitModelRecord;
  lRecord: TUnitModelRecord;
  lRecords: TUnitModelRecordArray;
begin
  var lInline: Integer := 1;
  lRecord := aParam;
  lRecords := nil;
  lPtr := @lRecord;
  lClass := TUnitModelClass.Create;
  try
    with lRecord,
      lClass do
    begin
      FieldName := Caption;
      Reset;
    end;

    with lPtr^ do
      with lRecord do
        with lClass do
          RecordValue := lRecord;

    Shared := lInline;
  finally
    lClass.Free;
  end;
end;

end.
