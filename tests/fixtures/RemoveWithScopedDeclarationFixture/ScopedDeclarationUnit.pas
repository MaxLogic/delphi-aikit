unit ScopedDeclarationUnit;

interface

type
  TScopedDeclarationItem = record
    Count: Integer;
    Name: string;
  end;

  PScopedDeclarationItem = ^TScopedDeclarationItem;

  TScopedDeclarationScope = class
  public
    class procedure Run(aItemPtr: PScopedDeclarationItem);
  end;

implementation

uses
  System.SysUtils;

class procedure TScopedDeclarationScope.Run(aItemPtr: PScopedDeclarationItem);
begin
  with aItemPtr^ do
  begin
    var Count := 1;
    Name := IntToStr(Count);
  end;

  with aItemPtr^ do
  begin
    for var i := 0 to Count do
      Name := IntToStr(i);
  end;

  with aItemPtr^ do
  begin
    try
      Count := Count + 1;
    except
      on E: Exception do
        Name := E.Message;
    end;
  end;
end;

end.
