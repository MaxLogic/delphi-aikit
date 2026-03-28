unit Dak.Resolve;

interface

uses
  Dak.Types;

function RunResolveCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  Dak.Resolve.Runner;

function RunResolveCommand(const aOptions: TAppOptions): Integer;
begin
  Result := Dak.Resolve.Runner.RunResolveCommand(aOptions);
end;

end.
