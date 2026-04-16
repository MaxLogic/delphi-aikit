unit Dak.Lsp;

interface

uses
  Dak.Types;

function RunLspCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.SysUtils,
  Dak.ExitCodes, Dak.Lsp.Context, Dak.Lsp.Runner;

function RunLspCommand(const aOptions: TAppOptions): Integer;
var
  lContext: TLspContext;
  lError: string;
  lResult: TLspRunnerResult;
begin
  lError := '';
  if not TryBuildStrictLspContext(aOptions, lContext, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitToolFailure);
  end;

  if not TryRunLspRequest(aOptions, lContext, lResult, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitToolFailure);
  end;

  if aOptions.fLspFormat = TLspFormat.lfText then
    WriteLn(lResult.fTextResponse)
  else
    WriteLn(lResult.fResponseText);
  Result := cExitSuccess;
end;

end.
