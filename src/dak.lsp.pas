unit Dak.Lsp;

interface

uses
  Dak.Types;

function RunLspCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.SysUtils,
  Dak.ExitCodes;

function RunLspCommand(const aOptions: TAppOptions): Integer;
begin
  WriteLn(ErrOutput, 'lsp command is not implemented yet.');
  Result := cExitToolFailure;
end;

end.
