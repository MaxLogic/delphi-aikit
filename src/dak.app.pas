unit Dak.App;

interface

uses
  Dak.Types;

type
  TDelphiAIKitApp = class
  public
    class function Run: Integer; static;
  private
    fOptions: TAppOptions;
    procedure InitializeProcess;
    function HandleHelpIfRequested(out aExitCode: Integer): Boolean;
    function TryParseOptions(out aExitCode: Integer): Boolean;
    function DispatchCommand: Integer;
    function Execute: Integer;
  end;

implementation

uses
  System.SysUtils,
  Xml.omnixmldom, Xml.xmldom,
  Dak.Analyze, Dak.Build, Dak.Cli, Dak.DfmCheck, Dak.DfmInspect, Dak.ExitCodes, Dak.GlobalVars, Dak.Messages,
  Dak.Resolve;

class function TDelphiAIKitApp.Run: Integer;
var
  lApp: TDelphiAIKitApp;
begin
  lApp := TDelphiAIKitApp.Create;
  try
    try
      Result := lApp.Execute;
    except
      on E: Exception do
      begin
        WriteLn(ErrOutput, Format(SUnhandledException, [E.ClassName, E.Message]));
        Result := cExitUnhandledException;
      end;
    end;
  finally
    lApp.Free;
  end;
end;

procedure TDelphiAIKitApp.InitializeProcess;
begin
  DefaultDOMVendor := sOmniXmlVendor;
end;

function TDelphiAIKitApp.HandleHelpIfRequested(out aExitCode: Integer): Boolean;
var
  lError: string;
  lHasHelpCommand: Boolean;
  lHelpCommand: TCommandKind;
begin
  Result := False;
  aExitCode := cExitSuccess;
  if not IsHelpRequested then
    Exit(False);

  Result := True;
  if not TryGetCommand(lHelpCommand, lHasHelpCommand, lError) then
  begin
    WriteLn(ErrOutput, SInvalidArgs);
    if lError <> '' then
      WriteLn(ErrOutput, lError);
    WriteUsage(TCommandKind.ckResolve, True);
    aExitCode := cExitInvalidArgs;
  end else
    WriteUsage(lHelpCommand, not lHasHelpCommand);
end;

function TDelphiAIKitApp.TryParseOptions(out aExitCode: Integer): Boolean;
var
  lError: string;
begin
  Result := Dak.Cli.TryParseOptions(fOptions, lError);
  if Result then
  begin
    aExitCode := cExitSuccess;
    Exit(True);
  end;

  WriteLn(ErrOutput, SInvalidArgs);
  if lError <> '' then
    WriteLn(ErrOutput, lError);
  WriteUsage(fOptions.fCommand, False);
  aExitCode := cExitInvalidArgs;
end;

function TDelphiAIKitApp.DispatchCommand: Integer;
var
  lError: string;
begin
  case fOptions.fCommand of
    TCommandKind.ckBuild:
      begin
        if not TryRunBuild(fOptions, Result, lError) then
        begin
          WriteLn(ErrOutput, lError);
          Result := cExitToolFailure;
        end else if (Result = cExitSuccess) and fOptions.fBuildRunDfmCheck then
        begin
          WriteLn('[build] Running dfm-check validation...');
          Result := RunDfmCheckCommand(fOptions);
        end;
      end;
    TCommandKind.ckDfmCheck:
      Result := RunDfmCheckCommand(fOptions);
    TCommandKind.ckDfmInspect:
      Result := RunDfmInspectCommand(fOptions);
    TCommandKind.ckGlobalVars:
      Result := RunGlobalVarsCommand(fOptions);
    TCommandKind.ckAnalyzeProject, TCommandKind.ckAnalyzeUnit:
      Result := RunAnalyzeCommand(fOptions);
  else
    Result := RunResolveCommand(fOptions);
  end;
end;

function TDelphiAIKitApp.Execute: Integer;
begin
  InitializeProcess;
  if HandleHelpIfRequested(Result) then
    Exit(Result);
  if not TryParseOptions(Result) then
    Exit(Result);
  Result := DispatchCommand;
end;

end.
