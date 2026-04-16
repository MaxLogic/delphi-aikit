unit Dak.Cli;

interface

uses
  System.Classes, System.SysUtils,
  maxLogic.CmdLineParams,
  Dak.Messages, Dak.Types;

function TryParseOptions(out aOptions: TAppOptions; out aError: string): Boolean;
function TryGetCommand(out aCommand: TCommandKind; out aHasCommand: Boolean; out aError: string): Boolean;
procedure WriteUsage(const aCommand: TCommandKind; const aShowGlobalOnly: Boolean);
function IsHelpRequested: Boolean;

implementation

function IsHelpRequested: Boolean;
var
  lParams: iCmdLineParams;
begin
  lParams := maxCmdLineParams;
  Result := lParams.has(['help', 'h', '?']);
end;

function TryGetCommand(out aCommand: TCommandKind; out aHasCommand: Boolean; out aError: string): Boolean;
var
  lParams: iCmdLineParams;
  lList: TStringList;
  lArg: string;
  lIndex: Integer;
  lHelpRequested: Boolean;
  lSwitch: string;
  lSwitchValue: string;
  lHasSwitchValue: Boolean;
  lNextSwitch: string;
  lNextSwitchValue: string;
  lNextHasSwitchValue: Boolean;
  lSkipNextToken: Boolean;
  lPrefixes: TSwitchPrefixes;
  lParsedCommand: TCommandKind;

  function TryParseCommandToken(const aArg: string; out aParsedCommand: TCommandKind): Boolean;
  begin
    Result := True;
    if SameText(aArg, 'resolve') then
      aParsedCommand := TCommandKind.ckResolve
    else if SameText(aArg, 'analyze') or SameText(aArg, 'analyze-project') then
      aParsedCommand := TCommandKind.ckAnalyzeProject
    else if SameText(aArg, 'analyze-unit') then
      aParsedCommand := TCommandKind.ckAnalyzeUnit
    else if SameText(aArg, 'build') then
      aParsedCommand := TCommandKind.ckBuild
    else if SameText(aArg, 'dfm-check') then
      aParsedCommand := TCommandKind.ckDfmCheck
    else if SameText(aArg, 'dfm-inspect') then
      aParsedCommand := TCommandKind.ckDfmInspect
    else if SameText(aArg, 'global-vars') then
      aParsedCommand := TCommandKind.ckGlobalVars
    else if SameText(aArg, 'deps') then
      aParsedCommand := TCommandKind.ckDeps
    else if SameText(aArg, 'lsp') then
      aParsedCommand := TCommandKind.ckLsp
    else
      Result := False;
  end;

  function TrySplitSwitchToken(const aArg: string; out aSwitch: string; out aValue: string;
    out aHasValue: Boolean): Boolean;
  var
    lStart: Integer;
    lText: string;
    lPos: Integer;
  begin
    Result := False;
    aSwitch := '';
    aValue := '';
    aHasValue := False;

    if (spDoubleDash in lPrefixes) and (Length(aArg) >= 3) and (aArg[1] = '-') and (aArg[2] = '-') then
      lStart := 3
    else if (spDash in lPrefixes) and (Length(aArg) >= 2) and (aArg[1] = '-') then
      lStart := 2
    else if (spSlash in lPrefixes) and (Length(aArg) >= 2) and (aArg[1] = '/') then
      lStart := 2
    else
      Exit(False);

    lText := Trim(Copy(aArg, lStart, MaxInt));
    if lText = '' then
      Exit(False);

    lPos := Pos('=', lText);
    if lPos = 0 then
      lPos := Pos(':', lText);
    if lPos > 0 then
    begin
      aSwitch := Trim(Copy(lText, 1, lPos - 1));
      aValue := Copy(lText, lPos + 1, MaxInt);
      aHasValue := True;
    end else
      aSwitch := lText;

    Result := aSwitch <> '';
  end;

  function SwitchRequiresValue(const aSwitch: string): Boolean;
  begin
    Result :=
      SameText(aSwitch, 'project') or SameText(aSwitch, 'dproj') or
      SameText(aSwitch, 'platform') or SameText(aSwitch, 'config') or
      SameText(aSwitch, 'delphi') or SameText(aSwitch, 'rsvars') or
      SameText(aSwitch, 'dfm') or
      SameText(aSwitch, 'builder') or SameText(aSwitch, 'webcore-compiler') or
      SameText(aSwitch, 'envoptions') or SameText(aSwitch, 'log-file') or
      SameText(aSwitch, 'logfile') or SameText(aSwitch, 'format') or
      SameText(aSwitch, 'out-kind') or SameText(aSwitch, 'out-file') or
      SameText(aSwitch, 'out') or SameText(aSwitch, 'fi-output') or
      SameText(aSwitch, 'output') or SameText(aSwitch, 'fi-ignore') or
      SameText(aSwitch, 'ignore') or SameText(aSwitch, 'fi-settings') or
      SameText(aSwitch, 'settings') or SameText(aSwitch, 'exclude-path-masks') or
      SameText(aSwitch, 'ignore-warning-ids') or SameText(aSwitch, 'unit') or
      SameText(aSwitch, 'fi-formats') or SameText(aSwitch, 'pa-path') or
      SameText(aSwitch, 'pa-output') or SameText(aSwitch, 'pa-args') or
      SameText(aSwitch, 'target') or SameText(aSwitch, 'max-findings') or
      SameText(aSwitch, 'build-timeout-sec') or SameText(aSwitch, 'test-output-dir') or
      SameText(aSwitch, 'ignore-warnings') or SameText(aSwitch, 'ignore-hints') or
      SameText(aSwitch, 'top') or SameText(aSwitch, 'file') or
      SameText(aSwitch, 'line') or SameText(aSwitch, 'col') or
      SameText(aSwitch, 'query') or SameText(aSwitch, 'limit') or
      SameText(aSwitch, 'lsp-path');
  end;

  function SwitchAllowsBoolValue(const aSwitch: string): Boolean;
  begin
    Result :=
      SameText(aSwitch, 'log-tee') or SameText(aSwitch, 'verbose') or
      SameText(aSwitch, 'help') or SameText(aSwitch, 'h') or
      SameText(aSwitch, '?') or SameText(aSwitch, 'fi-silent') or
      SameText(aSwitch, 'silent') or SameText(aSwitch, 'fi-xml') or
      SameText(aSwitch, 'xml') or SameText(aSwitch, 'fi-csv') or
      SameText(aSwitch, 'csv') or SameText(aSwitch, 'fixinsight') or
      SameText(aSwitch, 'pascal-analyzer') or SameText(aSwitch, 'pal') or
      SameText(aSwitch, 'clean') or SameText(aSwitch, 'write-summary') or
      SameText(aSwitch, 'show-warnings') or SameText(aSwitch, 'show-hints') or
      SameText(aSwitch, 'ai') or SameText(aSwitch, 'json') or
      SameText(aSwitch, 'rebuild') or SameText(aSwitch, 'include-declaration');
  end;

  function IsBoolToken(const aArg: string): Boolean;
  begin
    Result :=
      SameText(aArg, 'true') or SameText(aArg, 'false') or
      SameText(aArg, 'yes') or SameText(aArg, 'no') or
      SameText(aArg, '1') or SameText(aArg, '0');
  end;
begin
  Result := False;
  aError := '';
  aCommand := TCommandKind.ckResolve;
  aHasCommand := False;
  lParams := maxCmdLineParams;
  lList := lParams.GetParamList;
  lHelpRequested := lParams.has(['help', 'h', '?']);
  lPrefixes := lParams.SwitchPrefixes;
  lSkipNextToken := False;
  for lIndex := 0 to lList.Count - 1 do
  begin
    lArg := lList[lIndex];
    if lSkipNextToken then
    begin
      lSkipNextToken := False;
      Continue;
    end;

    if lHelpRequested and TrySplitSwitchToken(lArg, lSwitch, lSwitchValue, lHasSwitchValue) then
    begin
      if not lHasSwitchValue then
      begin
        if SwitchRequiresValue(lSwitch) then
        begin
          if (lIndex + 1 < lList.Count) and
            (not TrySplitSwitchToken(lList[lIndex + 1], lNextSwitch, lNextSwitchValue, lNextHasSwitchValue)) then
            lSkipNextToken := True;
        end
        else if SwitchAllowsBoolValue(lSwitch) and (lIndex + 1 < lList.Count) and IsBoolToken(lList[lIndex + 1]) then
          lSkipNextToken := True;
      end;
      Continue;
    end;

    if (lArg <> '') and (lArg[1] <> '-') and (lArg[1] <> '/') then
    begin
      if TryParseCommandToken(lArg, lParsedCommand) then
      begin
        if aHasCommand then
        begin
          aError := Format(SUnknownCommand, [lArg]);
          Exit(False);
        end;
        aCommand := lParsedCommand;
        aHasCommand := True;
      end else
      begin
        aError := Format(SUnknownCommand, [lArg]);
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

procedure WriteUsage(const aCommand: TCommandKind; const aShowGlobalOnly: Boolean);
begin
  if aShowGlobalOnly then
  begin
    WriteLn(ErrOutput, SUsageGlobal);
    Exit;
  end;

  case aCommand of
    TCommandKind.ckAnalyzeProject, TCommandKind.ckAnalyzeUnit:
      WriteLn(ErrOutput, SUsageAnalyze);
    TCommandKind.ckBuild:
      WriteLn(ErrOutput, SUsageBuild);
    TCommandKind.ckDfmCheck:
      WriteLn(ErrOutput, SUsageDfmCheck);
    TCommandKind.ckDfmInspect:
      WriteLn(ErrOutput, SUsageDfmInspect);
    TCommandKind.ckGlobalVars:
      WriteLn(ErrOutput, SUsageGlobalVars);
    TCommandKind.ckDeps:
      WriteLn(ErrOutput, SUsageDeps);
    TCommandKind.ckLsp:
      WriteLn(ErrOutput, SUsageLsp);
  else
    WriteLn(ErrOutput, SUsageResolve);
  end;
end;

type
  TOptionParser = record
  private
    fParams: iCmdLineParams;
    fList: TStringList;
    fIndex: Integer;
    fOptions: TAppOptions;
    fError: string;
    procedure InitDefaults;
    function TryParseOutKind(const aText: string; out aKind: TOutputKind): Boolean;
    function TryParseFiFormats(const aText: string; out aFormats: TReportFormatSet): Boolean;
    function TryParseBool(const aText: string; out aValue: Boolean): Boolean;
    function TryParseSourceContextMode(const aText: string; out aMode: TSourceContextMode): Boolean;
    function TrySplitSwitch(const aParam: string; const aPrefixes: TSwitchPrefixes; out aSwitch: string;
      out aValue: string; out aHasValue: Boolean): Boolean;
    function IsKnownSwitchName(const aSwitch: string): Boolean;
    function IsSwitchParam(const aParam: string): Boolean;
    function TakeValue(const aRequiresValue: Boolean; const aAllowsValue: Boolean; const aInlineValue: string;
      const aHasInlineValue: Boolean; out aOutValue: string; const aArgName: string;
      const aAllowSwitchValue: Boolean = False): Boolean;
    function TrySetCommandFromArg(const aArg: string): Boolean;
    function TryParseCommand: Boolean;
    function TryParseArgs: Boolean;
    function TryParseSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function TryParseGlobalSwitch(const aSwitch: string; const aInlineValue: string; const aHasInlineValue: Boolean;
      out aHandled: Boolean): Boolean;
    function TryParseResolveOutputSwitch(const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
    function TryParseResolveFixInsightSwitch(const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
    function TryParseResolveSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function TryParseAnalyzeTargetSwitch(const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
    function TryParseAnalyzeFixInsightSwitch(const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
    function TryParseAnalyzePalSwitch(const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
    function TryParseGlobalVarsSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function TryParseDepsSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function TryParseLspOperation(const aArg: string): Boolean;
    function TryParseLspSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function TryParseAnalyzeSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function TryParseBuildSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function TryParseDfmCheckSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function TryParseDfmInspectSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function ValidateOptions: Boolean;
  public
    class function Create: TOptionParser; static;
    function Execute(out aOptions: TAppOptions; out aError: string): Boolean;
  end;

class function TOptionParser.Create: TOptionParser;
begin
  Result := Default(TOptionParser);
  Result.fParams := maxCmdLineParams;
  Result.fList := Result.fParams.GetParamList;
  Result.fIndex := 0;
  Result.fError := '';
  Result.InitDefaults;
end;

procedure TOptionParser.InitDefaults;
begin
  fOptions := Default(TAppOptions);
  fOptions.fCommand := TCommandKind.ckResolve;
  fOptions.fPlatform := 'Win32';
  fOptions.fConfig := 'Release';
  fOptions.fOutKind := TOutputKind.okIni;
  fOptions.fAnalyzeFiFormats := [TReportFormat.rfText];
  fOptions.fAnalyzeFixInsight := True;
  fOptions.fAnalyzePal := False;
  fOptions.fAnalyzeClean := True;
  fOptions.fAnalyzeWriteSummary := True;
  fOptions.fBuildJson := False;
  fOptions.fBuildBackend := TBuildBackend.bbAuto;
  fOptions.fBuildTarget := 'Build';
  fOptions.fBuildMaxFindings := 5;
  fOptions.fBuildTimeoutSec := 0;
  fOptions.fSourceContextMode := TSourceContextMode.scmAuto;
  fOptions.fSourceContextLines := 2;
  fOptions.fDfmInspectFormat := 'tree';
  fOptions.fDepsFormat := TDepsFormat.dfJson;
  fOptions.fDepsTopLimit := 20;
  fOptions.fLspFormat := TLspFormat.lfJson;
  fOptions.fLspIncludeDeclaration := True;
  fOptions.fLspLimit := 50;
  fOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfText;
  fOptions.fGlobalVarsRefresh := TGlobalVarsRefresh.gvrAuto;
  fOptions.fGlobalVarsUnusedOnly := False;
  fOptions.fGlobalVarsReadsOnly := False;
  fOptions.fGlobalVarsWritesOnly := False;
end;

function TOptionParser.TryParseOutKind(const aText: string; out aKind: TOutputKind): Boolean;
begin
  if SameText(aText, 'ini') then
    aKind := TOutputKind.okIni
  else if SameText(aText, 'xml') then
    aKind := TOutputKind.okXml
  else if SameText(aText, 'bat') then
    aKind := TOutputKind.okBat
  else
    Exit(False);
  Result := True;
end;

function TOptionParser.TryParseFiFormats(const aText: string; out aFormats: TReportFormatSet): Boolean;
var
  lValue: string;
  lParts: TArray<string>;
  lPart: string;
  lItem: string;
begin
  aFormats := [];
  lValue := Trim(aText);
  if lValue = '' then
  begin
    aFormats := [TReportFormat.rfText];
    Exit(True);
  end;

  if SameText(lValue, 'all') then
  begin
    aFormats := [TReportFormat.rfText, TReportFormat.rfXml, TReportFormat.rfCsv];
    Exit(True);
  end;

  lParts := lValue.Split([',', ';', ' ']);
  for lPart in lParts do
  begin
    lItem := Trim(lPart);
    if lItem = '' then
      Continue;
    if SameText(lItem, 'txt') then
      Include(aFormats, TReportFormat.rfText)
    else if SameText(lItem, 'xml') then
      Include(aFormats, TReportFormat.rfXml)
    else if SameText(lItem, 'csv') then
      Include(aFormats, TReportFormat.rfCsv)
    else
      Exit(False);
  end;

  Result := aFormats <> [];
end;

function TOptionParser.TryParseBool(const aText: string; out aValue: Boolean): Boolean;
begin
  if (aText = '') then
  begin
    aValue := True;
    Exit(True);
  end;
  if SameText(aText, 'true') or SameText(aText, '1') or SameText(aText, 'yes') then
    aValue := True
  else if SameText(aText, 'false') or SameText(aText, '0') or SameText(aText, 'no') then
    aValue := False
  else
    Exit(False);
  Result := True;
end;

function TOptionParser.TryParseSourceContextMode(const aText: string; out aMode: TSourceContextMode): Boolean;
begin
  if SameText(aText, 'auto') then
    aMode := TSourceContextMode.scmAuto
  else if SameText(aText, 'off') then
    aMode := TSourceContextMode.scmOff
  else if SameText(aText, 'on') then
    aMode := TSourceContextMode.scmOn
  else
    Exit(False);
  Result := True;
end;

function TOptionParser.TrySplitSwitch(const aParam: string; const aPrefixes: TSwitchPrefixes; out aSwitch: string;
  out aValue: string; out aHasValue: Boolean): Boolean;
var
  lStart: Integer;
  lText: string;
  lPos: Integer;
begin
  Result := False;
  aSwitch := '';
  aValue := '';
  aHasValue := False;

  if (spDoubleDash in aPrefixes) and (Length(aParam) >= 3) and (aParam[1] = '-') and (aParam[2] = '-') then
    lStart := 3
  else if (spDash in aPrefixes) and (Length(aParam) >= 2) and (aParam[1] = '-') then
    lStart := 2
  else if (spSlash in aPrefixes) and (Length(aParam) >= 2) and (aParam[1] = '/') then
    lStart := 2
  else
    Exit(False);

  lText := Copy(aParam, lStart, MaxInt);
  lText := Trim(lText);
  if lText = '' then
    Exit(False);

  lPos := Pos('=', lText);
  if lPos = 0 then
    lPos := Pos(':', lText);
  if lPos > 0 then
  begin
    aSwitch := Trim(Copy(lText, 1, lPos - 1));
    aValue := Copy(lText, lPos + 1, MaxInt);
    aHasValue := True;
  end
  else
    aSwitch := lText;

  Result := aSwitch <> '';
end;

function TOptionParser.IsKnownSwitchName(const aSwitch: string): Boolean;
begin
  Result :=
    SameText(aSwitch, 'project') or SameText(aSwitch, 'dproj') or
    SameText(aSwitch, 'platform') or SameText(aSwitch, 'config') or
    SameText(aSwitch, 'delphi') or SameText(aSwitch, 'rsvars') or
    SameText(aSwitch, 'envoptions') or SameText(aSwitch, 'log-file') or
    SameText(aSwitch, 'logfile') or SameText(aSwitch, 'log-tee') or
    SameText(aSwitch, 'verbose') or SameText(aSwitch, 'source-context') or
    SameText(aSwitch, 'source-context-lines') or SameText(aSwitch, 'help') or
    SameText(aSwitch, 'h') or SameText(aSwitch, '?') or
    SameText(aSwitch, 'format') or SameText(aSwitch, 'out-kind') or
    SameText(aSwitch, 'out-file') or SameText(aSwitch, 'out') or
    SameText(aSwitch, 'fi-output') or SameText(aSwitch, 'output') or
    SameText(aSwitch, 'fi-ignore') or SameText(aSwitch, 'ignore') or
    SameText(aSwitch, 'fi-settings') or SameText(aSwitch, 'settings') or
    SameText(aSwitch, 'fi-silent') or SameText(aSwitch, 'silent') or
    SameText(aSwitch, 'fi-xml') or SameText(aSwitch, 'xml') or
    SameText(aSwitch, 'fi-csv') or SameText(aSwitch, 'csv') or
    SameText(aSwitch, 'exclude-path-masks') or SameText(aSwitch, 'ignore-warning-ids') or
    SameText(aSwitch, 'unit') or SameText(aSwitch, 'fi-formats') or
    SameText(aSwitch, 'fixinsight') or SameText(aSwitch, 'pascal-analyzer') or
    SameText(aSwitch, 'pal') or SameText(aSwitch, 'clean') or
    SameText(aSwitch, 'write-summary') or SameText(aSwitch, 'pa-path') or
    SameText(aSwitch, 'pa-output') or SameText(aSwitch, 'pa-args') or
    SameText(aSwitch, 'show-warnings') or SameText(aSwitch, 'show-hints') or
    SameText(aSwitch, 'ai') or SameText(aSwitch, 'json') or
    SameText(aSwitch, 'target') or SameText(aSwitch, 'rebuild') or
    SameText(aSwitch, 'max-findings') or SameText(aSwitch, 'build-timeout-sec') or
    SameText(aSwitch, 'test-output-dir') or
    SameText(aSwitch, 'builder') or SameText(aSwitch, 'webcore-compiler') or
    SameText(aSwitch, 'pwa') or SameText(aSwitch, 'no-pwa') or
    SameText(aSwitch, 'dfmcheck') or SameText(aSwitch, 'dfm-check') or
    SameText(aSwitch, 'dfm') or SameText(aSwitch, 'all') or
    SameText(aSwitch, 'ignore-warnings') or
    SameText(aSwitch, 'ignore-hints') or
    SameText(aSwitch, 'cache') or SameText(aSwitch, 'refresh') or
    SameText(aSwitch, 'unused-only') or SameText(aSwitch, 'name') or
    SameText(aSwitch, 'reads-only') or SameText(aSwitch, 'writes-only') or
    SameText(aSwitch, 'file') or SameText(aSwitch, 'line') or
    SameText(aSwitch, 'col') or SameText(aSwitch, 'query') or
    SameText(aSwitch, 'limit') or SameText(aSwitch, 'include-declaration') or
    SameText(aSwitch, 'lsp-path');
end;

function TOptionParser.IsSwitchParam(const aParam: string): Boolean;
var
  lSwitch: string;
  lValue: string;
  lHasValue: Boolean;
begin
  Result := TrySplitSwitch(aParam, fParams.SwitchPrefixes, lSwitch, lValue, lHasValue);
  if (not Result) or (aParam = '') then
    Exit;
  if aParam[1] = '/' then
    Result := IsKnownSwitchName(lSwitch);
end;

function TOptionParser.TakeValue(const aRequiresValue: Boolean; const aAllowsValue: Boolean; const aInlineValue: string;
  const aHasInlineValue: Boolean; out aOutValue: string; const aArgName: string;
  const aAllowSwitchValue: Boolean = False): Boolean;
begin
  aOutValue := '';
  if aHasInlineValue then
    aOutValue := aInlineValue
  else if aRequiresValue or aAllowsValue then
  begin
    if (fIndex + 1 < fList.Count) and (aAllowSwitchValue or (not IsSwitchParam(fList[fIndex + 1]))) then
    begin
      Inc(fIndex);
      aOutValue := fList[fIndex];
    end;
  end;

  if aRequiresValue and (aOutValue = '') then
  begin
    fError := Format(SArgMissingValue, [aArgName]);
    Exit(False);
  end;

  Result := True;
end;

function TOptionParser.TrySetCommandFromArg(const aArg: string): Boolean;
begin
  if SameText(aArg, 'resolve') then
    fOptions.fCommand := TCommandKind.ckResolve
  else if SameText(aArg, 'analyze') or SameText(aArg, 'analyze-project') then
    fOptions.fCommand := TCommandKind.ckAnalyzeProject
  else if SameText(aArg, 'analyze-unit') then
    fOptions.fCommand := TCommandKind.ckAnalyzeUnit
  else if SameText(aArg, 'build') then
    fOptions.fCommand := TCommandKind.ckBuild
  else if SameText(aArg, 'dfm-check') then
    fOptions.fCommand := TCommandKind.ckDfmCheck
  else if SameText(aArg, 'dfm-inspect') then
    fOptions.fCommand := TCommandKind.ckDfmInspect
  else if SameText(aArg, 'global-vars') then
    fOptions.fCommand := TCommandKind.ckGlobalVars
  else if SameText(aArg, 'deps') then
    fOptions.fCommand := TCommandKind.ckDeps
  else if SameText(aArg, 'lsp') then
    fOptions.fCommand := TCommandKind.ckLsp
  else
  begin
    fError := Format(SUnknownCommand, [aArg]);
    Exit(False);
  end;
  Result := True;
end;

function TOptionParser.TryParseCommand: Boolean;
var
  lArg: string;
  lSwitch: string;
  lInlineValue: string;
  lHasInlineValue: Boolean;
begin
  Result := True;
  if fList.Count = 0 then
    Exit(True);

  lArg := fList[0];
  if not TrySplitSwitch(lArg, fParams.SwitchPrefixes, lSwitch, lInlineValue, lHasInlineValue) then
  begin
    if not TrySetCommandFromArg(lArg) then
      Exit(False);
    fIndex := 1;
  end;
end;

function TOptionParser.TryParseArgs: Boolean;
var
  lArg: string;
  lSwitch: string;
  lInlineValue: string;
  lHasInlineValue: Boolean;
begin
  while fIndex < fList.Count do
  begin
    lArg := fList[fIndex];
    if not TrySplitSwitch(lArg, fParams.SwitchPrefixes, lSwitch, lInlineValue, lHasInlineValue) then
    begin
      if (fOptions.fCommand = TCommandKind.ckLsp) and (fOptions.fLspOperation = TLspOperation.loNone) then
      begin
        if not TryParseLspOperation(lArg) then
          Exit(False);
        Inc(fIndex);
        Continue;
      end;
      fError := Format(SUnknownArg, [lArg]);
      Exit(False);
    end;
    if not TryParseSwitch(lArg, lSwitch, lInlineValue, lHasInlineValue) then
      Exit(False);
    Inc(fIndex);
  end;
  Result := True;
end;

function TOptionParser.TryParseSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean): Boolean;
var
  lHandled: Boolean;
begin
  if not TryParseGlobalSwitch(aSwitch, aInlineValue, aHasInlineValue, lHandled) then
    Exit(False);
  if lHandled then
    Exit(True);

  if fOptions.fCommand = TCommandKind.ckResolve then
    Exit(TryParseResolveSwitch(aArg, aSwitch, aInlineValue, aHasInlineValue));

  if fOptions.fCommand = TCommandKind.ckBuild then
    Exit(TryParseBuildSwitch(aArg, aSwitch, aInlineValue, aHasInlineValue));

  if fOptions.fCommand = TCommandKind.ckDfmCheck then
    Exit(TryParseDfmCheckSwitch(aArg, aSwitch, aInlineValue, aHasInlineValue));

  if fOptions.fCommand = TCommandKind.ckDfmInspect then
    Exit(TryParseDfmInspectSwitch(aArg, aSwitch, aInlineValue, aHasInlineValue));

  if fOptions.fCommand = TCommandKind.ckGlobalVars then
    Exit(TryParseGlobalVarsSwitch(aArg, aSwitch, aInlineValue, aHasInlineValue));

  if fOptions.fCommand = TCommandKind.ckDeps then
    Exit(TryParseDepsSwitch(aArg, aSwitch, aInlineValue, aHasInlineValue));

  if fOptions.fCommand = TCommandKind.ckLsp then
    Exit(TryParseLspSwitch(aArg, aSwitch, aInlineValue, aHasInlineValue));

  Result := TryParseAnalyzeSwitch(aArg, aSwitch, aInlineValue, aHasInlineValue);
end;

function TOptionParser.TryParseGlobalSwitch(const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
var
  lValue: string;
begin
  aHandled := True;
  if SameText(aSwitch, 'project') or SameText(aSwitch, 'dproj') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--project') then
      Exit(False);
    fOptions.fDprojPath := lValue;
  end else if SameText(aSwitch, 'platform') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--platform') then
      Exit(False);
    fOptions.fPlatform := lValue;
  end else if SameText(aSwitch, 'config') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--config') then
      Exit(False);
    fOptions.fConfig := lValue;
  end else if SameText(aSwitch, 'delphi') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--delphi') then
      Exit(False);
    if Pos('.', lValue) = 0 then
      lValue := lValue + '.0';
    fOptions.fDelphiVersion := lValue;
  end else if SameText(aSwitch, 'rsvars') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--rsvars') then
      Exit(False);
    fOptions.fRsVarsPath := lValue;
    fOptions.fHasRsVarsPath := True;
  end else if SameText(aSwitch, 'envoptions') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--envoptions') then
      Exit(False);
    fOptions.fEnvOptionsPath := lValue;
    fOptions.fHasEnvOptionsPath := True;
  end else if SameText(aSwitch, 'log-file') or SameText(aSwitch, 'logfile') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--log-file') then
      Exit(False);
    fOptions.fLogFile := lValue;
    fOptions.fHasLogFile := True;
  end else if SameText(aSwitch, 'log-tee') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--log-tee') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fLogTee) then
    begin
      fError := Format(SInvalidBoolValue, ['--log-tee', lValue]);
      Exit(False);
    end;
    fOptions.fHasLogTee := True;
  end else if SameText(aSwitch, 'verbose') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--verbose') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fVerbose) then
    begin
      fError := Format(SInvalidBoolValue, ['--verbose', lValue]);
      Exit(False);
    end;
  end else if SameText(aSwitch, 'source-context') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--source-context') then
      Exit(False);
    if not TryParseSourceContextMode(lValue, fOptions.fSourceContextMode) then
    begin
      fError := Format(SInvalidSourceContext, [lValue]);
      Exit(False);
    end;
    fOptions.fHasSourceContextMode := True;
  end else if SameText(aSwitch, 'source-context-lines') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--source-context-lines') then
      Exit(False);
    fOptions.fSourceContextLines := StrToIntDef(lValue, -1);
    if fOptions.fSourceContextLines < 0 then
    begin
      fError := Format(SInvalidSourceContextLines, [lValue]);
      Exit(False);
    end;
    fOptions.fHasSourceContextLines := True;
  end else if SameText(aSwitch, 'help') or SameText(aSwitch, 'h') or SameText(aSwitch, '?') then
    aHandled := True // handled by IsHelpRequested
  else
    aHandled := False;

  Result := True;
end;

function TOptionParser.TryParseResolveOutputSwitch(const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
var
  lValue: string;
begin
  aHandled := True;
  if SameText(aSwitch, 'format') or SameText(aSwitch, 'out-kind') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--format') then
      Exit(False);
    if not TryParseOutKind(lValue, fOptions.fOutKind) then
    begin
      fError := Format(SInvalidOutKind, [lValue]);
      Exit(False);
    end;
    fOptions.fHasOutKind := True;
  end else if SameText(aSwitch, 'out-file') or SameText(aSwitch, 'out') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--out-file') then
      Exit(False);
    fOptions.fOutPath := lValue;
    fOptions.fHasOutPath := True;
  end
  else
    aHandled := False;

  Result := True;
end;

function TOptionParser.TryParseResolveFixInsightSwitch(const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
var
  lValue: string;
begin
  aHandled := True;
  if SameText(aSwitch, 'fi-output') or SameText(aSwitch, 'output') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--fi-output') then
      Exit(False);
    fOptions.fFixOutput := lValue;
    fOptions.fHasFixOutput := True;
  end else if SameText(aSwitch, 'fi-ignore') or SameText(aSwitch, 'ignore') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--fi-ignore') then
      Exit(False);
    fOptions.fFixIgnore := lValue;
    fOptions.fHasFixIgnore := True;
  end else if SameText(aSwitch, 'fi-settings') or SameText(aSwitch, 'settings') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--fi-settings') then
      Exit(False);
    fOptions.fFixSettings := lValue;
    fOptions.fHasFixSettings := True;
  end else if SameText(aSwitch, 'fi-silent') or SameText(aSwitch, 'silent') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--fi-silent') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fFixSilent) then
    begin
      fError := Format(SInvalidBoolValue, ['--fi-silent', lValue]);
      Exit(False);
    end;
    fOptions.fHasFixSilent := True;
  end else if SameText(aSwitch, 'fi-xml') or SameText(aSwitch, 'xml') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--fi-xml') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fFixXml) then
    begin
      fError := Format(SInvalidBoolValue, ['--fi-xml', lValue]);
      Exit(False);
    end;
    fOptions.fHasFixXml := True;
  end else if SameText(aSwitch, 'fi-csv') or SameText(aSwitch, 'csv') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--fi-csv') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fFixCsv) then
    begin
      fError := Format(SInvalidBoolValue, ['--fi-csv', lValue]);
      Exit(False);
    end;
    fOptions.fHasFixCsv := True;
  end else if SameText(aSwitch, 'exclude-path-masks') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--exclude-path-masks') then
      Exit(False);
    fOptions.fExcludePathMasks := lValue;
    fOptions.fHasExcludePathMasks := True;
  end else if SameText(aSwitch, 'ignore-warning-ids') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--ignore-warning-ids') then
      Exit(False);
    fOptions.fIgnoreWarningIds := lValue;
    fOptions.fHasIgnoreWarningIds := True;
  end
  else
    aHandled := False;

  Result := True;
end;

function TOptionParser.TryParseResolveSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean): Boolean;
var
  lHandled: Boolean;
begin
  if not TryParseResolveOutputSwitch(aSwitch, aInlineValue, aHasInlineValue, lHandled) then
    Exit(False);
  if lHandled then
    Exit(True);
  if not TryParseResolveFixInsightSwitch(aSwitch, aInlineValue, aHasInlineValue, lHandled) then
    Exit(False);
  if lHandled then
    Exit(True);

  fError := Format(SUnknownArg, [aArg]);
  Result := False;
end;

function TOptionParser.TryParseAnalyzeTargetSwitch(const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
var
  lValue: string;
begin
  aHandled := True;
  if SameText(aSwitch, 'unit') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--unit') then
      Exit(False);
    fOptions.fUnitPath := lValue;
  end else if SameText(aSwitch, 'out') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--out') then
      Exit(False);
    fOptions.fAnalyzeOutPath := lValue;
    fOptions.fHasAnalyzeOutPath := True;
  end else if SameText(aSwitch, 'fi-formats') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--fi-formats') then
      Exit(False);
    if not TryParseFiFormats(lValue, fOptions.fAnalyzeFiFormats) then
    begin
      fError := Format(SInvalidFiFormats, [lValue]);
      Exit(False);
    end;
  end else if SameText(aSwitch, 'fixinsight') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--fixinsight') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fAnalyzeFixInsight) then
    begin
      fError := Format(SInvalidBoolValue, ['--fixinsight', lValue]);
      Exit(False);
    end;
  end else if SameText(aSwitch, 'pascal-analyzer') or SameText(aSwitch, 'pal') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--pascal-analyzer') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fAnalyzePal) then
    begin
      fError := Format(SInvalidBoolValue, ['--pascal-analyzer', lValue]);
      Exit(False);
    end;
  end else if SameText(aSwitch, 'clean') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--clean') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fAnalyzeClean) then
    begin
      fError := Format(SInvalidBoolValue, ['--clean', lValue]);
      Exit(False);
    end;
  end else if SameText(aSwitch, 'write-summary') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--write-summary') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fAnalyzeWriteSummary) then
    begin
      fError := Format(SInvalidBoolValue, ['--write-summary', lValue]);
      Exit(False);
    end;
  end
  else
    aHandled := False;

  Result := True;
end;

function TOptionParser.TryParseAnalyzeFixInsightSwitch(const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
var
  lValue: string;
begin
  aHandled := True;
  if SameText(aSwitch, 'fi-settings') or SameText(aSwitch, 'settings') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--fi-settings') then
      Exit(False);
    fOptions.fFixSettings := lValue;
    fOptions.fHasFixSettings := True;
  end else if SameText(aSwitch, 'fi-ignore') or SameText(aSwitch, 'ignore') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--fi-ignore') then
      Exit(False);
    fOptions.fFixIgnore := lValue;
    fOptions.fHasFixIgnore := True;
  end else if SameText(aSwitch, 'fi-silent') or SameText(aSwitch, 'silent') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--fi-silent') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fFixSilent) then
    begin
      fError := Format(SInvalidBoolValue, ['--fi-silent', lValue]);
      Exit(False);
    end;
    fOptions.fHasFixSilent := True;
  end else if SameText(aSwitch, 'exclude-path-masks') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--exclude-path-masks') then
      Exit(False);
    fOptions.fExcludePathMasks := lValue;
    fOptions.fHasExcludePathMasks := True;
  end else if SameText(aSwitch, 'ignore-warning-ids') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--ignore-warning-ids') then
      Exit(False);
    fOptions.fIgnoreWarningIds := lValue;
    fOptions.fHasIgnoreWarningIds := True;
  end
  else
    aHandled := False;

  Result := True;
end;

function TOptionParser.TryParseAnalyzePalSwitch(const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean; out aHandled: Boolean): Boolean;
var
  lValue: string;
begin
  aHandled := True;
  if SameText(aSwitch, 'pa-path') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--pa-path') then
      Exit(False);
    fOptions.fPaPath := lValue;
    fOptions.fHasPaPath := True;
  end else if SameText(aSwitch, 'pa-output') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--pa-output') then
      Exit(False);
    fOptions.fPaOutput := lValue;
    fOptions.fHasPaOutput := True;
  end else if SameText(aSwitch, 'pa-args') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--pa-args', True) then
      Exit(False);
    fOptions.fPaArgs := lValue;
    fOptions.fHasPaArgs := True;
  end
  else
    aHandled := False;

  Result := True;
end;

function TOptionParser.TryParseGlobalVarsSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean): Boolean;
var
  lValue: string;
begin
  if SameText(aSwitch, 'format') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--format') then
      Exit(False);
    if SameText(lValue, 'json') then
    begin
      fOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfJson;
    end else if SameText(lValue, 'text') then
    begin
      fOptions.fGlobalVarsFormat := TGlobalVarsFormat.gvfText;
    end else
    begin
      fError := Format(SGlobalVarsInvalidFormat, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'output') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--output') then
      Exit(False);
    fOptions.fGlobalVarsOutputPath := lValue;
    fOptions.fHasGlobalVarsOutputPath := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'cache') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--cache') then
      Exit(False);
    fOptions.fGlobalVarsCachePath := lValue;
    fOptions.fHasGlobalVarsCachePath := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'unit') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--unit') then
      Exit(False);
    fOptions.fGlobalVarsUnitFilter := lValue;
    fOptions.fHasGlobalVarsUnitFilter := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'name') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--name') then
      Exit(False);
    fOptions.fGlobalVarsNameFilter := lValue;
    fOptions.fHasGlobalVarsNameFilter := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'refresh') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--refresh') then
      Exit(False);
    if SameText(lValue, 'force') then
    begin
      fOptions.fGlobalVarsRefresh := TGlobalVarsRefresh.gvrForce;
    end else if SameText(lValue, 'auto') then
    begin
      fOptions.fGlobalVarsRefresh := TGlobalVarsRefresh.gvrAuto;
    end else
    begin
      fError := Format(SGlobalVarsInvalidRefresh, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'unused-only') then
  begin
    if aHasInlineValue then
    begin
      fError := Format(SUnknownArg, [aArg]);
      Exit(False);
    end;
    fOptions.fGlobalVarsUnusedOnly := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'reads-only') then
  begin
    if aHasInlineValue then
    begin
      fError := Format(SUnknownArg, [aArg]);
      Exit(False);
    end;
    fOptions.fGlobalVarsReadsOnly := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'writes-only') then
  begin
    if aHasInlineValue then
    begin
      fError := Format(SUnknownArg, [aArg]);
      Exit(False);
    end;
    fOptions.fGlobalVarsWritesOnly := True;
    Exit(True);
  end;

  fError := Format(SUnknownArg, [aArg]);
  Result := False;
end;

function TOptionParser.TryParseDepsSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean): Boolean;
var
  lValue: string;
begin
  if SameText(aSwitch, 'format') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--format') then
      Exit(False);
    if SameText(lValue, 'json') then
    begin
      fOptions.fDepsFormat := TDepsFormat.dfJson;
    end else if SameText(lValue, 'text') then
    begin
      fOptions.fDepsFormat := TDepsFormat.dfText;
    end else
    begin
      fError := Format(SDepsInvalidFormat, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'output') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--output') then
      Exit(False);
    fOptions.fDepsOutputPath := lValue;
    fOptions.fHasDepsOutputPath := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'unit') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--unit') then
      Exit(False);
    fOptions.fDepsUnitName := lValue;
    fOptions.fHasDepsUnitName := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'top') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--top') then
      Exit(False);
    fOptions.fDepsTopLimit := StrToIntDef(lValue, -1);
    if fOptions.fDepsTopLimit < 0 then
    begin
      fError := Format(SDepsInvalidTopLimit, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  fError := Format(SUnknownArg, [aArg]);
  Result := False;
end;

function TOptionParser.TryParseLspOperation(const aArg: string): Boolean;
begin
  if SameText(aArg, 'definition') then
    fOptions.fLspOperation := TLspOperation.loDefinition
  else if SameText(aArg, 'references') then
    fOptions.fLspOperation := TLspOperation.loReferences
  else if SameText(aArg, 'hover') then
    fOptions.fLspOperation := TLspOperation.loHover
  else if SameText(aArg, 'symbols') then
    fOptions.fLspOperation := TLspOperation.loSymbols
  else
  begin
    fError := Format(SLspInvalidOperation, [aArg]);
    Exit(False);
  end;
  Result := True;
end;

function TOptionParser.TryParseLspSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean): Boolean;
var
  lBoolValue: Boolean;
  lValue: string;
begin
  if SameText(aSwitch, 'file') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--file') then
      Exit(False);
    fOptions.fLspFilePath := lValue;
    Exit(True);
  end;

  if SameText(aSwitch, 'line') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--line') then
      Exit(False);
    fOptions.fLspLine := StrToIntDef(lValue, -1);
    if fOptions.fLspLine < 1 then
    begin
      fError := Format(SLspInvalidPosition, ['--line', lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'col') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--col') then
      Exit(False);
    fOptions.fLspCol := StrToIntDef(lValue, -1);
    if fOptions.fLspCol < 1 then
    begin
      fError := Format(SLspInvalidPosition, ['--col', lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'query') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--query') then
      Exit(False);
    fOptions.fLspQuery := lValue;
    Exit(True);
  end;

  if SameText(aSwitch, 'limit') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--limit') then
      Exit(False);
    fOptions.fLspLimit := StrToIntDef(lValue, -1);
    fOptions.fHasLspLimit := True;
    if fOptions.fLspLimit < 1 then
    begin
      fError := Format(SLspInvalidLimit, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'format') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--format') then
      Exit(False);
    if SameText(lValue, 'json') then
      fOptions.fLspFormat := TLspFormat.lfJson
    else if SameText(lValue, 'text') then
      fOptions.fLspFormat := TLspFormat.lfText
    else
    begin
      fError := Format(SLspInvalidFormat, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'include-declaration') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--include-declaration') then
      Exit(False);
    if not TryParseBool(lValue, lBoolValue) then
    begin
      fError := Format(SInvalidBoolValue, ['--include-declaration', lValue]);
      Exit(False);
    end;
    fOptions.fLspIncludeDeclaration := lBoolValue;
    fOptions.fHasLspIncludeDeclaration := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'lsp-path') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--lsp-path') then
      Exit(False);
    fOptions.fLspPath := lValue;
    fOptions.fHasLspPath := True;
    Exit(True);
  end;

  fError := Format(SUnknownArg, [aArg]);
  Result := False;
end;

function TOptionParser.TryParseAnalyzeSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean): Boolean;
var
  lHandled: Boolean;
begin
  if not TryParseAnalyzeTargetSwitch(aSwitch, aInlineValue, aHasInlineValue, lHandled) then
    Exit(False);
  if lHandled then
    Exit(True);
  if not TryParseAnalyzeFixInsightSwitch(aSwitch, aInlineValue, aHasInlineValue, lHandled) then
    Exit(False);
  if lHandled then
    Exit(True);
  if not TryParseAnalyzePalSwitch(aSwitch, aInlineValue, aHasInlineValue, lHandled) then
    Exit(False);
  if lHandled then
    Exit(True);

  fError := Format(SUnknownArg, [aArg]);
  Result := False;
end;

function TOptionParser.TryParseBuildSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean): Boolean;
var
  lRebuild: Boolean;
  lValue: string;
  function TryParseDfmSelectionSwitch(const aSwitchName: string; const aInline: string;
    const aHasInline: Boolean): Boolean;
  begin
    if SameText(aSwitchName, 'all') then
    begin
      if aHasInline then
      begin
        fError := Format(SUnknownArg, [aArg]);
        Exit(False);
      end;
      fOptions.fDfmCheckAll := True;
      fOptions.fDfmCheckFilter := '';
      Exit(True);
    end;

    if SameText(aSwitchName, 'dfm') then
    begin
      if not TakeValue(True, False, aInline, aHasInline, lValue, '--dfm') then
        Exit(False);
      fOptions.fDfmCheckFilter := lValue;
      fOptions.fDfmCheckAll := False;
      Exit(True);
    end;

    Result := False;
  end;
begin
  if TryParseDfmSelectionSwitch(aSwitch, aInlineValue, aHasInlineValue) then
    Exit(True);

  if SameText(aSwitch, 'show-warnings') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--show-warnings') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fBuildShowWarnings) then
    begin
      fError := Format(SInvalidBoolValue, ['--show-warnings', lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'show-hints') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--show-hints') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fBuildShowHints) then
    begin
      fError := Format(SInvalidBoolValue, ['--show-hints', lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'ai') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--ai') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fBuildAi) then
    begin
      fError := Format(SInvalidBoolValue, ['--ai', lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'json') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--json') then
      Exit(False);
    if not TryParseBool(lValue, fOptions.fBuildJson) then
    begin
      fError := Format(SInvalidBoolValue, ['--json', lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'dfmcheck') or SameText(aSwitch, 'dfm-check') then
  begin
    if aHasInlineValue then
    begin
      fError := Format(SUnknownArg, [aArg]);
      Exit(False);
    end;
    fOptions.fBuildRunDfmCheck := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'target') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--target') then
      Exit(False);
    if SameText(lValue, 'build') then
      fOptions.fBuildTarget := 'Build'
    else if SameText(lValue, 'rebuild') then
      fOptions.fBuildTarget := 'Rebuild'
    else
    begin
      fError := Format(SInvalidBuildTarget, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'builder') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--builder') then
      Exit(False);
    if SameText(lValue, 'auto') then
      fOptions.fBuildBackend := TBuildBackend.bbAuto
    else if SameText(lValue, 'delphi') then
      fOptions.fBuildBackend := TBuildBackend.bbDelphi
    else if SameText(lValue, 'webcore') then
      fOptions.fBuildBackend := TBuildBackend.bbWebCore
    else
    begin
      fError := Format(SInvalidBuildBackend, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'webcore-compiler') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--webcore-compiler') then
      Exit(False);
    fOptions.fWebCoreCompilerPath := lValue;
    fOptions.fHasWebCoreCompilerPath := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'pwa') then
  begin
    if aHasInlineValue then
    begin
      fError := Format(SUnknownArg, [aArg]);
      Exit(False);
    end;
    fOptions.fWebCorePwaEnabled := True;
    fOptions.fHasWebCorePwaEnabled := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'no-pwa') then
  begin
    if aHasInlineValue then
    begin
      fError := Format(SUnknownArg, [aArg]);
      Exit(False);
    end;
    fOptions.fWebCorePwaEnabled := False;
    fOptions.fHasWebCorePwaEnabled := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'rebuild') then
  begin
    if not TakeValue(False, True, aInlineValue, aHasInlineValue, lValue, '--rebuild') then
      Exit(False);
    if not TryParseBool(lValue, lRebuild) then
    begin
      fError := Format(SInvalidBoolValue, ['--rebuild', lValue]);
      Exit(False);
    end;
    if lRebuild then
      fOptions.fBuildTarget := 'Rebuild'
    else
      fOptions.fBuildTarget := 'Build';
    Exit(True);
  end;

  if SameText(aSwitch, 'max-findings') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--max-findings') then
      Exit(False);
    fOptions.fBuildMaxFindings := StrToIntDef(lValue, -1);
    if fOptions.fBuildMaxFindings < 1 then
    begin
      fError := Format(SInvalidMaxFindings, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'build-timeout-sec') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--build-timeout-sec') then
      Exit(False);
    fOptions.fBuildTimeoutSec := StrToIntDef(lValue, -1);
    if fOptions.fBuildTimeoutSec < 0 then
    begin
      fError := Format(SInvalidBuildTimeout, [lValue]);
      Exit(False);
    end;
    Exit(True);
  end;

  if SameText(aSwitch, 'test-output-dir') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--test-output-dir') then
      Exit(False);
    fOptions.fBuildTestOutputDir := lValue;
    fOptions.fHasBuildTestOutputDir := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'ignore-warnings') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--ignore-warnings') then
      Exit(False);
    fOptions.fBuildIgnoreWarnings := lValue;
    fOptions.fHasBuildIgnoreWarnings := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'ignore-hints') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--ignore-hints') then
      Exit(False);
    fOptions.fBuildIgnoreHints := lValue;
    fOptions.fHasBuildIgnoreHints := True;
    Exit(True);
  end;

  if SameText(aSwitch, 'exclude-path-masks') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--exclude-path-masks') then
      Exit(False);
    fOptions.fExcludePathMasks := lValue;
    fOptions.fHasExcludePathMasks := True;
    Exit(True);
  end;

  fError := Format(SUnknownArg, [aArg]);
  Result := False;
end;

function TOptionParser.TryParseDfmCheckSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean): Boolean;
var
  lValue: string;
begin
  if SameText(aSwitch, 'all') then
  begin
    if aHasInlineValue then
    begin
      fError := Format(SUnknownArg, [aArg]);
      Exit(False);
    end;
    fOptions.fDfmCheckAll := True;
    fOptions.fDfmCheckFilter := '';
    Exit(True);
  end;

  if SameText(aSwitch, 'dfm') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--dfm') then
      Exit(False);
    fOptions.fDfmCheckFilter := lValue;
    fOptions.fDfmCheckAll := False;
    Exit(True);
  end;

  fError := Format(SUnknownArg, [aArg]);
  Result := False;
end;

function TOptionParser.TryParseDfmInspectSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
  const aHasInlineValue: Boolean): Boolean;
var
  lValue: string;
begin
  if SameText(aSwitch, 'dfm') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--dfm') then
      Exit(False);
    fOptions.fDfmInspectPath := lValue;
    Exit(True);
  end;

  if SameText(aSwitch, 'format') then
  begin
    if not TakeValue(True, False, aInlineValue, aHasInlineValue, lValue, '--format') then
      Exit(False);
    if not SameText(lValue, 'tree') and not SameText(lValue, 'summary') then
    begin
      fError := 'Unsupported dfm-inspect format: ' + lValue;
      Exit(False);
    end;
    fOptions.fDfmInspectFormat := LowerCase(lValue);
    Exit(True);
  end;

  fError := Format(SUnknownArg, [aArg]);
  Result := False;
end;

function TOptionParser.ValidateOptions: Boolean;
begin
  if (fOptions.fCommand = TCommandKind.ckAnalyzeProject) and (fOptions.fUnitPath <> '') then
  begin
    if fOptions.fDprojPath <> '' then
    begin
      fError := SAnalyzeUnitConflict;
      Exit(False);
    end;
    fOptions.fCommand := TCommandKind.ckAnalyzeUnit;
  end;

  if fOptions.fCommand = TCommandKind.ckResolve then
  begin
    if fOptions.fDprojPath = '' then
    begin
      fError := Format(SArgMissingValue, ['--project']);
      Exit(False);
    end;
    if fOptions.fDelphiVersion = '' then
    begin
      fError := Format(SArgMissingValue, ['--delphi']);
      Exit(False);
    end;
  end else if fOptions.fCommand = TCommandKind.ckAnalyzeProject then
  begin
    if fOptions.fDprojPath = '' then
    begin
      fError := Format(SArgMissingValue, ['--project']);
      Exit(False);
    end;
    if fOptions.fDelphiVersion = '' then
    begin
      fError := Format(SArgMissingValue, ['--delphi']);
      Exit(False);
    end;
  end else if fOptions.fCommand = TCommandKind.ckAnalyzeUnit then
  begin
    if fOptions.fDprojPath <> '' then
    begin
      fError := SAnalyzeUnitConflict;
      Exit(False);
    end;
    if fOptions.fUnitPath = '' then
    begin
      fError := Format(SArgMissingValue, ['--unit']);
      Exit(False);
    end;
    if fOptions.fDelphiVersion = '' then
    begin
      fError := Format(SArgMissingValue, ['--delphi']);
      Exit(False);
    end;
  end else if fOptions.fCommand = TCommandKind.ckLsp then
  begin
    if fOptions.fDprojPath = '' then
    begin
      fError := Format(SArgMissingValue, ['--project']);
      Exit(False);
    end;
    if fOptions.fLspOperation = TLspOperation.loNone then
    begin
      fError := SLspMissingOperation;
      Exit(False);
    end;
    if fOptions.fLspOperation in [TLspOperation.loDefinition, TLspOperation.loReferences, TLspOperation.loHover] then
    begin
      if fOptions.fLspFilePath = '' then
      begin
        fError := Format(SArgMissingValue, ['--file']);
        Exit(False);
      end;
      if fOptions.fLspLine < 1 then
      begin
        fError := Format(SArgMissingValue, ['--line']);
        Exit(False);
      end;
      if fOptions.fLspCol < 1 then
      begin
        fError := Format(SArgMissingValue, ['--col']);
        Exit(False);
      end;
    end else if fOptions.fLspOperation = TLspOperation.loSymbols then
    begin
      if fOptions.fLspQuery = '' then
      begin
        fError := Format(SArgMissingValue, ['--query']);
        Exit(False);
      end;
    end;
    if fOptions.fHasLspIncludeDeclaration and (fOptions.fLspOperation <> TLspOperation.loReferences) then
    begin
      fError := Format(SLspOptionOnlyForOperation, ['--include-declaration', 'references']);
      Exit(False);
    end;
    if fOptions.fHasLspLimit and (fOptions.fLspOperation <> TLspOperation.loSymbols) then
    begin
      fError := Format(SLspOptionOnlyForOperation, ['--limit', 'symbols']);
      Exit(False);
    end;
  end else if fOptions.fCommand = TCommandKind.ckBuild then
  begin
    if fOptions.fDprojPath = '' then
    begin
      fError := Format(SArgMissingValue, ['--project']);
      Exit(False);
    end;
    if (fOptions.fBuildBackend = TBuildBackend.bbWebCore) and fOptions.fBuildRunDfmCheck then
    begin
      fError := Format(SBuildOptionDelphiOnly, ['--dfmcheck']);
      Exit(False);
    end;
    if (fOptions.fBuildBackend = TBuildBackend.bbWebCore) and fOptions.fHasRsVarsPath then
    begin
      fError := Format(SBuildOptionDelphiOnly, ['--rsvars']);
      Exit(False);
    end;
    if (fOptions.fBuildBackend = TBuildBackend.bbWebCore) and fOptions.fHasEnvOptionsPath then
    begin
      fError := Format(SBuildOptionDelphiOnly, ['--envoptions']);
      Exit(False);
    end;
    if (fOptions.fBuildBackend = TBuildBackend.bbDelphi) and (fOptions.fDelphiVersion = '') then
    begin
      fError := Format(SArgMissingValue, ['--delphi']);
      Exit(False);
    end;
  end else if fOptions.fCommand = TCommandKind.ckDfmCheck then
  begin
    if fOptions.fDprojPath = '' then
    begin
      fError := Format(SArgMissingValue, ['--dproj']);
      Exit(False);
    end;
  end else if fOptions.fCommand = TCommandKind.ckDfmInspect then
  begin
    if fOptions.fDfmInspectPath = '' then
    begin
      fError := Format(SArgMissingValue, ['--dfm']);
      Exit(False);
    end;
  end else if fOptions.fCommand = TCommandKind.ckGlobalVars then
  begin
    if fOptions.fDprojPath = '' then
    begin
      fError := Format(SArgMissingValue, ['--project']);
      Exit(False);
    end;
    if fOptions.fGlobalVarsReadsOnly and fOptions.fGlobalVarsWritesOnly then
    begin
      fError := SGlobalVarsConflictingAccessFilters;
      Exit(False);
    end;
    if fOptions.fGlobalVarsUnusedOnly and (fOptions.fGlobalVarsReadsOnly or fOptions.fGlobalVarsWritesOnly) then
    begin
      fError := SGlobalVarsUnusedAccessConflict;
      Exit(False);
    end;
  end else if fOptions.fCommand = TCommandKind.ckDeps then
  begin
    if fOptions.fDprojPath = '' then
    begin
      fError := Format(SArgMissingValue, ['--project']);
      Exit(False);
    end;
  end;

  Result := True;
end;

function TOptionParser.Execute(out aOptions: TAppOptions; out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  if not TryParseCommand then
  begin
    aError := fError;
    Exit(False);
  end;
  if not TryParseArgs then
  begin
    aError := fError;
    Exit(False);
  end;
  if not ValidateOptions then
  begin
    aError := fError;
    Exit(False);
  end;

  aOptions := fOptions;
  Result := True;
end;

function TryParseOptions(out aOptions: TAppOptions; out aError: string): Boolean;
var
  lParser: TOptionParser;
begin
  lParser := TOptionParser.Create;
  Result := lParser.Execute(aOptions, aError);
end;

end.
