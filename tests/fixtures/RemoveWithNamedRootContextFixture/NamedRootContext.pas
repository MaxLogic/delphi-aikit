unit NamedRootContext;

interface

uses
  System.Classes, System.SysUtils;

procedure Run;

implementation

type
  TComponentReceiver = class(TComponent)
  public
    Own: Integer;
  end;
  TInterfaceReceiver = class(TInterfacedObject)
  public
    Own: Integer;
  end;

var
  GlobalValue: Integer = 4;
  Tag: NativeInt = 90;
  Name: string = 'global-name';
  RefCount: Integer = 91;
  ClassName: string = 'global-class';

procedure PositiveComponent(const aInput: Integer);
var
  lReceiver: TComponentReceiver;
  lOutput: Integer;
begin
  lReceiver := TComponentReceiver.Create(nil);
  try
    with lReceiver do
    begin
      Own := aInput + GlobalValue;
      lOutput := Own;
    end;
    Writeln(lOutput);
  finally
    lReceiver.Free;
  end;
end;

procedure PositiveInterface(const aInput: Integer);
var
  lReceiver: TInterfaceReceiver;
  lOutput: Integer;
begin
  lReceiver := TInterfaceReceiver.Create;
  try
    with lReceiver do
    begin
      Own := aInput + GlobalValue;
      lOutput := Own;
    end;
    Writeln(lOutput);
  finally
    lReceiver.Free;
  end;
end;

procedure MemberHomonyms;
var
  lComponent: TComponentReceiver;
  lInterface: TInterfaceReceiver;
  lNumber: NativeInt;
  lText: string;
begin
  lComponent := TComponentReceiver.Create(nil);
  lInterface := TInterfaceReceiver.Create;
  try
    lComponent.Tag := 5;
    lComponent.Name := 'receiver_name';
    with lComponent do lNumber := Tag;
    Writeln(lNumber);
    with lComponent do lText := Name;
    Writeln(lText);
    with lInterface do lNumber := RefCount;
    Writeln(lNumber);
    with lInterface do lText := ClassName;
    Writeln(lText);
  finally
    lInterface.Free;
    lComponent.Free;
  end;
end;

procedure Run;
begin
  PositiveComponent(3);
  PositiveInterface(6);
  MemberHomonyms;
end;

end.
