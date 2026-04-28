unit InterfaceResolverUnit;

interface

type
  IBaseContact = interface
    function GetBaseName: string;
    procedure BaseTouch;
    property BaseName: string read GetBaseName;
  end;

  IChildContact = interface(IBaseContact)
    function GetChildName: string;
    procedure ChildTouch;
    property ChildName: string read GetChildName;
  end;

  TConcreteContact = class(TInterfacedObject, IChildContact)
  private
    FBaseName: string;
    FChildName: string;
  public
    function GetBaseName: string;
    function GetChildName: string;
    procedure BaseTouch;
    procedure ChildTouch;
    procedure ConcreteOnly;
    property BaseName: string read GetBaseName;
    property ChildName: string read GetChildName;
  end;

  TInterfaceResolverScope = class
  public
    class procedure Run;
  end;

implementation

function TConcreteContact.GetBaseName: string;
begin
  Result := FBaseName;
end;

function TConcreteContact.GetChildName: string;
begin
  Result := FChildName;
end;

procedure TConcreteContact.BaseTouch;
begin
end;

procedure TConcreteContact.ChildTouch;
begin
end;

procedure TConcreteContact.ConcreteOnly;
begin
end;

class procedure TInterfaceResolverScope.Run;
var
  lConcrete: TConcreteContact;
  lInterface: IChildContact;
  lSink: string;
begin
  with lInterface do
  begin
    BaseTouch;
    ChildTouch;
    lSink := BaseName;
    lSink := ChildName;
    ConcreteOnly;
  end;

  with lConcrete do
  begin
    ConcreteOnly;
    ChildTouch;
  end;
end;

end.
