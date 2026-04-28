unit E2EExternalUnit;

interface

uses
  System.Classes;

type
  TE2EExternalScope = class
  public
    class procedure KeepExternal;
  end;

implementation

class procedure TE2EExternalScope.KeepExternal;
var
  lList: TStringList;
begin
  lList := TStringList.Create;
  try
    lList.Add('ready');
    with lList do
    begin
      Add('external');
    end;
  finally
    lList.Free;
  end;
end;

end.
