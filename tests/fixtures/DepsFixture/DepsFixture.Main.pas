unit DepsFixture.Main;

interface

uses
  System.SysUtils,
  DepsFixture.Shared,
  DepsFixtureSibling.External;

procedure RunDepsFixture;

implementation

uses
  MissingFixture.Dependency;

procedure RunDepsFixture;
begin
  if SharedValue + ExternalValue > 0 then
  begin
    Writeln(IntToStr(SharedValue));
  end;
end;

end.
