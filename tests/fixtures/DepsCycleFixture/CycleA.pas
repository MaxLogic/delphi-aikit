unit CycleA;

interface

uses
  System.SysUtils,
  CycleB;

procedure TouchCycleA;

implementation

uses
  MissingCycle.Dependency;

procedure TouchCycleA;
begin
  TouchCycleB;
end;

end.
