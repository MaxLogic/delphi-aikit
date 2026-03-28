unit Dak.Analyze;

interface

uses
  Dak.Types;

function RunAnalyzeCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  Dak.Analyze.ProjectRunner, Dak.Analyze.UnitRunner;

function RunAnalyzeCommand(const aOptions: TAppOptions): Integer;
begin
  if aOptions.fCommand = TCommandKind.ckAnalyzeProject then
    Result := RunAnalyzeProject(aOptions)
  else if aOptions.fCommand = TCommandKind.ckAnalyzeUnit then
    Result := RunAnalyzeUnit(aOptions)
  else
    Result := 2;
end;
end.
