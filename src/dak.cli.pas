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
begin
  Result := False;
  aError := '';
  aCommand := TCommandKind.ckResolve;
  aHasCommand := False;
  lParams := maxCmdLineParams;
  lList := lParams.GetParamList;
  for lIndex := 0 to lList.Count - 1 do
  begin
    lArg := lList[lIndex];
    if (lArg <> '') and (lArg[1] <> '-') and (lArg[1] <> '/') then
    begin
      aHasCommand := True;
      if SameText(lArg, 'resolve') then
        aCommand := TCommandKind.ckResolve
      else if SameText(lArg, 'analyze') or SameText(lArg, 'analyze-project') then
        aCommand := TCommandKind.ckAnalyzeProject
      else if SameText(lArg, 'analyze-unit') then
        aCommand := TCommandKind.ckAnalyzeUnit
      else if SameText(lArg, 'build') then
        aCommand := TCommandKind.ckBuild
      else
      begin
        aError := Format(SUnknownCommand, [lArg]);
        Exit(False);
      end;
      Exit(True);
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
    function TrySplitSwitch(const aParam: string; const aPrefixes: TSwitchPrefixes; out aSwitch: string;
      out aValue: string; out aHasValue: Boolean): Boolean;
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
    function TryParseAnalyzeSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
      const aHasInlineValue: Boolean): Boolean;
    function TryParseBuildSwitch(const aArg: string; const aSwitch: string; const aInlineValue: string;
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

function TOptionParser.IsSwitchParam(const aParam: string): Boolean;
var
  lDummySwitch: string;
  lDummyValue: string;
  lDummyHasValue: Boolean;
begin
  Result := TrySplitSwitch(aParam, fParams.SwitchPrefixes, lDummySwitch, lDummyValue, lDummyHasValue);
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
  lValue: string;
begin
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
  end else if fOptions.fCommand = TCommandKind.ckBuild then
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
