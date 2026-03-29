unit Dak.Deps;

interface

uses
  Dak.Types;

function RunDepsCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  Dak.Deps.Runner;

function RunDepsCommand(const aOptions: TAppOptions): Integer;
begin
  Result := Dak.Deps.Runner.RunDepsCommand(aOptions);
end;

end.
