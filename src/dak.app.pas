unit Dak.App;

interface

uses
  Dak.Types;

type
  TDelphiAIKitApp = class
  public
    class function Run: Integer; static;
  protected
    fOptions: TAppOptions;
    class function RunApp(aApp: TDelphiAIKitApp): Integer; static;
    procedure InitializeProcess; virtual;
    function HandleHelpIfRequested(out aExitCode: Integer): Boolean; virtual;
    function TryParseOptions(out aExitCode: Integer): Boolean; virtual;
    function DispatchCommand: Integer; virtual;
    function RunLspCommand: Integer; virtual;
    function Execute: Integer; virtual;
    procedure ConfigureCrashReporting; virtual;
    procedure ApplyMadExceptSettings(const aBugReportDir: string); virtual;
    function ResolveBugReportDir: string; virtual;
  end;

implementation

uses
  System.SysUtils,
  Xml.omnixmldom, Xml.xmldom,
  MaxMadExcept,
  Dak.Analyze, Dak.Build, Dak.Cli, Dak.Deps, Dak.DfmCheck, Dak.DfmInspect, Dak.ExitCodes, Dak.GlobalVars, Dak.Lsp,
  Dak.Messages, Dak.Resolve, Dak.Utils;

class function TDelphiAIKitApp.Run: Integer;
var
  lApp: TDelphiAIKitApp;
begin
  lApp := TDelphiAIKitApp.Create;
  try
    Result := RunApp(lApp);
  finally
    lApp.Free;
  end;
end;

class function TDelphiAIKitApp.RunApp(aApp: TDelphiAIKitApp): Integer;
begin
  Result := aApp.Execute;
end;

procedure TDelphiAIKitApp.InitializeProcess;
begin
  DefaultDOMVendor := sOmniXmlVendor;
  ConfigureCrashReporting;
end;

procedure TDelphiAIKitApp.ConfigureCrashReporting;
var
  lBugReportDir: string;
begin
  lBugReportDir := ResolveBugReportDir;
  if lBugReportDir = '' then
    Exit;

  ApplyMadExceptSettings(lBugReportDir);
end;

procedure TDelphiAIKitApp.ApplyMadExceptSettings(const aBugReportDir: string);
begin
  MaxMadExcept.AdjustMadExcept(aBugReportDir);
end;

function TDelphiAIKitApp.ResolveBugReportDir: string;
begin
  Result := ExeDir;
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

function TDelphiAIKitApp.RunLspCommand: Integer;
begin
  Result := Dak.Lsp.RunLspCommand(fOptions);
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
    TCommandKind.ckDeps:
      Result := RunDepsCommand(fOptions);
    TCommandKind.ckLsp:
      Result := RunLspCommand;
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
