unit GlobalVarsFixture.Globals;

interface

uses
  System.Classes;

type
  TGlobalStore = class
  public
    class var sCache: Integer;
  end;

  TGlobalPropertyStore = class(TStringList)
  public
    constructor Create;
  end;

var
  GCounter: Integer;
  GUnusedValue: Integer;
threadvar
  GThreadCounter: Integer;
const
  GTypedValue: Integer = 7;

type
  TSecondGlobalStore = class
  public
    class var sCache: Integer;
  end;

procedure TouchGlobals;
function BuildLocalValue(const aSeed: Integer): Integer;

implementation

function BuildLocalValue(const aSeed: Integer): Integer;
var
  lValue: Integer;
begin
  lValue := aSeed;
  Result := lValue;
  lValue := Result + 1;
  Result := lValue;
end;

constructor TGlobalPropertyStore.Create;
begin
  inherited Create;
  CaseSensitive := False;
  NameValueSeparator := '=';
end;

procedure TouchGlobals;
begin
  Inc(GCounter);
  GThreadCounter := GCounter;
  TGlobalStore.sCache := GTypedValue;
  TSecondGlobalStore.sCache := GCounter;
end;

end.
