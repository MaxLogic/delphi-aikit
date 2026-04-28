unit GlobalScopeMain;

interface

type
  TEmptyScopeRecord = record
    Marker: string;
    ShadowName: string;
  end;

  TGlobalScope = class
  private
    CurrentOnly: string;
  public
    class var
      ClassShared: string;
    class procedure Run(const aParamOnly: string);
  end;

const
  UnitConstOnly: string = 'const';

var
  ShadowName: string;
  UnitGlobalOnly: string;

implementation

uses
  System.Classes,
  GlobalScopeSupport, MissingGlobalScopeSupport;

var
  ImplGlobalOnly: string;

class procedure TGlobalScope.Run(const aParamOnly: string);
var
  lEmpty: TEmptyScopeRecord;
  lExternalList: TStringList;
  lLocalOnly: string;
  ShadowName: string;
begin
  with lEmpty do
  begin
    Marker := lLocalOnly + aParamOnly + CurrentOnly + UnitGlobalOnly + ImplGlobalOnly + UnitConstOnly + ClassShared;
  end;

  with lEmpty do
  begin
    ShadowName := '';
  end;

  with lEmpty do
  begin
    GlobalScopeSupport.SupportGlobal := UnitGlobalOnly;
  end;

  with lEmpty do
  begin
    MissingGlobalScopeSupport.ExternalValue := UnitGlobalOnly;
  end;

  with lEmpty do
  begin
    TStringList.ClassName;
  end;
end;

end.
