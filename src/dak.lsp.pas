unit Dak.Lsp;

interface

uses
  Dak.Types;

function RunLspCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.SysUtils,
  Dak.ExitCodes, Dak.Lsp.Context;

function RunLspCommand(const aOptions: TAppOptions): Integer;
var
  lContext: TLspContext;
  lError: string;
begin
  lError := '';
  if not TryBuildStrictLspContext(aOptions, lContext, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitToolFailure);
  end;

  WriteLn(ErrOutput, 'lsp command is not implemented yet.');
  Result := cExitToolFailure;
end;

end.
