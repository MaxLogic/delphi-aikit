unit autoFree;

interface

type
  iGarbo = interface(IInterface) ['{4E8E97C2-6C5B-4C7C-9B32-9A6F3D2C0D11}'] end;

function gc(var aObj; const aNewObj: TObject): iGarbo;

implementation

type
  TGarbo = class(TInterfacedObject, iGarbo)
  strict private
    fObj: TObject;
  public
    constructor Create(const aObj: TObject);
    destructor Destroy; override;
  end;

constructor TGarbo.Create(const aObj: TObject);
begin
  inherited Create;
  fObj := aObj;
end;

destructor TGarbo.Destroy;
begin
  fObj.Free;
  inherited Destroy;
end;

function gc(var aObj; const aNewObj: TObject): iGarbo;
begin
  TObject(aObj) := aNewObj;
  Result := TGarbo.Create(aNewObj);
end;

end.
