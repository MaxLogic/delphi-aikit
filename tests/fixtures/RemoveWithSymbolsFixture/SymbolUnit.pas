unit SymbolUnit;

interface

uses
  System.Classes;

type
  { Full-line comments before type declarations must not become type names. }
  TSymbolRecord =
    record
      RecordField: string;
      procedure RecordMethod;
      property RecordProp: string read RecordField;
    end;

  TSymbolClass = class
  private
    FClassField: string;
  public
    class var SharedValue: Integer;
    const ClassConst = 42;
    procedure Touch(
      const aParamName: string;
      aCount: Integer;
      aExternal: TStringList);
    class procedure Run;
    property ClassProp: string read FClassField;
  end;

const
  UnitConst = 7;

var
  UnitGlobal: TSymbolRecord;
  ExternalGlobal: TStringList;

implementation

uses
  System.SysUtils;

const
  ImplConst: string = 'impl';

var
  ImplGlobal: Integer;

procedure TSymbolRecord.RecordMethod;
begin
end;

procedure TSymbolClass.Touch(
  const aParamName: string;
  aCount: Integer;
  aExternal: TStringList);
var
  lLocalName: string;
  lLocalRecord,
  lSecondRecord: TSymbolRecord;
  lExternalList: TStringList;
begin
  lLocalName := aParamName + IntToStr(aCount);
  lLocalRecord.RecordField := lLocalName;
  lSecondRecord.RecordField := lLocalRecord.RecordField;
  lExternalList := aExternal;
  if Assigned(lExternalList) then
    lLocalName := lExternalList.ClassName;
end;

class procedure TSymbolClass.Run;
var
  lInstance: TSymbolClass;
begin
  lInstance := TSymbolClass.Create;
  try
    lInstance.Touch('x', UnitConst + ImplGlobal, nil);
  finally
    lInstance.Free;
  end;
end;

end.
