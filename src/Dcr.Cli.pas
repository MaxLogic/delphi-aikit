unit Dcr.Cli;

interface

uses
  System.Classes, System.SysUtils,
  maxLogic.CmdLineParams,
  Dcr.Messages, Dcr.Types;

function TryParseOptions(out aOptions: TAppOptions; out aError: string): Boolean;
procedure WriteUsage;
function IsHelpRequested: Boolean;

implementation

function IsHelpRequested: Boolean;
var
  lParams: iCmdLineParams;
begin
  lParams := maxCmdLineParams;
  Result := lParams.has(['help', 'h', '?']);
end;

procedure WriteUsage;
begin
  WriteLn(ErrOutput, SUsage);
end;

function TryParseOptions(out aOptions: TAppOptions; out aError: string): Boolean;
var
  lParams: iCmdLineParams;
  lList: TStringList;
  lIndex: Integer;
  lArg: string;
  lSwitch: string;
  lValue: string;
  lInlineValue: string;
  lHasInlineValue: Boolean;

  function TryParseOutKind(const aText: string; out aKind: TOutputKind): Boolean;
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

  function TryParseFiFormats(const aText: string; out aFormats: TReportFormatSet): Boolean;
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

  function TryParseBool(const aText: string; out aValue: Boolean): Boolean;
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

  function TrySplitSwitch(const aParam: string; const aPrefixes: TSwitchPrefixes; out aSwitch: string;
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

  function IsSwitchParam(const aParam: string): Boolean;
  var
    lDummySwitch: string;
    lDummyValue: string;
    lDummyHasValue: Boolean;
  begin
    Result := TrySplitSwitch(aParam, lParams.SwitchPrefixes, lDummySwitch, lDummyValue, lDummyHasValue);
  end;

  function TakeValue(const aRequiresValue: Boolean; const aAllowsValue: Boolean; const aInlineValue: string;
    const aHasInlineValue: Boolean; out aOutValue: string; const aArgName: string): Boolean;
  begin
    aOutValue := '';
    if aHasInlineValue then
      aOutValue := aInlineValue
    else if aRequiresValue or aAllowsValue then
    begin
      if (lIndex + 1 < lList.Count) and (not IsSwitchParam(lList[lIndex + 1])) then
      begin
        Inc(lIndex);
        aOutValue := lList[lIndex];
      end;
    end;

    if aRequiresValue and (aOutValue = '') then
    begin
      aError := Format(SArgMissingValue, [aArgName]);
      Exit(False);
    end;

    Result := True;
  end;

begin
  Result := False;
  aError := '';
  aOptions := Default(TAppOptions);
  aOptions.fCommand := TCommandKind.ckResolve;
  aOptions.fPlatform := 'Win32';
  aOptions.fConfig := 'Release';
  aOptions.fOutKind := TOutputKind.okIni;
  aOptions.fAnalyzeFiFormats := [TReportFormat.rfText];
  aOptions.fAnalyzePal := True;
  aOptions.fAnalyzeClean := True;
  aOptions.fAnalyzeWriteSummary := True;

  lParams := maxCmdLineParams;
  lList := lParams.GetParamList;
  lIndex := 0;
  if lList.Count > 0 then
  begin
    lArg := lList[0];
    if not TrySplitSwitch(lArg, lParams.SwitchPrefixes, lSwitch, lInlineValue, lHasInlineValue) then
    begin
      if SameText(lArg, 'analyze-project') then
        aOptions.fCommand := TCommandKind.ckAnalyzeProject
      else if SameText(lArg, 'analyze-unit') then
        aOptions.fCommand := TCommandKind.ckAnalyzeUnit
      else
      begin
        aError := Format(SUnknownCommand, [lArg]);
        Exit(False);
      end;
      lIndex := 1;
    end;
  end;
  while lIndex < lList.Count do
  begin
    lArg := lList[lIndex];
    if not TrySplitSwitch(lArg, lParams.SwitchPrefixes, lSwitch, lInlineValue, lHasInlineValue) then
    begin
      aError := Format(SUnknownArg, [lArg]);
      Exit(False);
    end;

    if (aOptions.fCommand = TCommandKind.ckResolve) then
    begin
      if SameText(lSwitch, 'dproj') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--dproj') then
          Exit(False);
        aOptions.fDprojPath := lValue;
      end else if SameText(lSwitch, 'platform') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--platform') then
          Exit(False);
        aOptions.fPlatform := lValue;
      end else if SameText(lSwitch, 'config') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--config') then
          Exit(False);
        aOptions.fConfig := lValue;
      end else if SameText(lSwitch, 'delphi') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--delphi') then
          Exit(False);
        if Pos('.', lValue) = 0 then
          lValue := lValue + '.0';
        aOptions.fDelphiVersion := lValue;
      end else if SameText(lSwitch, 'out-kind') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--out-kind') then
          Exit(False);
        if not TryParseOutKind(lValue, aOptions.fOutKind) then
        begin
          aError := Format(SInvalidOutKind, [lValue]);
          Exit(False);
        end;
        aOptions.fHasOutKind := True;
      end else if SameText(lSwitch, 'out') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--out') then
          Exit(False);
        aOptions.fOutPath := lValue;
        aOptions.fHasOutPath := True;
      end else if SameText(lSwitch, 'verbose') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--verbose') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fVerbose) then
        begin
          aError := Format(SInvalidBoolValue, ['--verbose', lValue]);
          Exit(False);
        end;
      end else if SameText(lSwitch, 'rsvars') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--rsvars') then
          Exit(False);
        aOptions.fRsVarsPath := lValue;
        aOptions.fHasRsVarsPath := True;
      end else if SameText(lSwitch, 'envoptions') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--envoptions') then
          Exit(False);
        aOptions.fEnvOptionsPath := lValue;
        aOptions.fHasEnvOptionsPath := True;
      end else if SameText(lSwitch, 'output') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--output') then
          Exit(False);
        aOptions.fFixOutput := lValue;
        aOptions.fHasFixOutput := True;
      end else if SameText(lSwitch, 'ignore') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--ignore') then
          Exit(False);
        aOptions.fFixIgnore := lValue;
        aOptions.fHasFixIgnore := True;
      end else if SameText(lSwitch, 'settings') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--settings') then
          Exit(False);
        aOptions.fFixSettings := lValue;
        aOptions.fHasFixSettings := True;
      end else if SameText(lSwitch, 'silent') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--silent') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fFixSilent) then
        begin
          aError := Format(SInvalidBoolValue, ['--silent', lValue]);
          Exit(False);
        end;
        aOptions.fHasFixSilent := True;
      end else if SameText(lSwitch, 'xml') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--xml') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fFixXml) then
        begin
          aError := Format(SInvalidBoolValue, ['--xml', lValue]);
          Exit(False);
        end;
        aOptions.fHasFixXml := True;
      end else if SameText(lSwitch, 'csv') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--csv') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fFixCsv) then
        begin
          aError := Format(SInvalidBoolValue, ['--csv', lValue]);
          Exit(False);
        end;
        aOptions.fHasFixCsv := True;
      end else if SameText(lSwitch, 'exclude-path-masks') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--exclude-path-masks') then
          Exit(False);
        aOptions.fExcludePathMasks := lValue;
        aOptions.fHasExcludePathMasks := True;
      end else if SameText(lSwitch, 'ignore-warning-ids') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--ignore-warning-ids') then
          Exit(False);
        aOptions.fIgnoreWarningIds := lValue;
        aOptions.fHasIgnoreWarningIds := True;
      end else if SameText(lSwitch, 'run-fixinsight') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--run-fixinsight') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fRunFixInsight) then
        begin
          aError := Format(SInvalidBoolValue, ['--run-fixinsight', lValue]);
          Exit(False);
        end;
      end else if SameText(lSwitch, 'run-pascal-analyzer') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--run-pascal-analyzer') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fRunPascalAnalyzer) then
        begin
          aError := Format(SInvalidBoolValue, ['--run-pascal-analyzer', lValue]);
          Exit(False);
        end;
      end else if SameText(lSwitch, 'pa-path') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--pa-path') then
          Exit(False);
        aOptions.fPaPath := lValue;
        aOptions.fHasPaPath := True;
      end else if SameText(lSwitch, 'pa-output') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--pa-output') then
          Exit(False);
        aOptions.fPaOutput := lValue;
        aOptions.fHasPaOutput := True;
      end else if SameText(lSwitch, 'pa-args') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--pa-args') then
          Exit(False);
        aOptions.fPaArgs := lValue;
        aOptions.fHasPaArgs := True;
      end else if SameText(lSwitch, 'logfile') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--logfile') then
          Exit(False);
        aOptions.fLogFile := lValue;
        aOptions.fHasLogFile := True;
      end else if SameText(lSwitch, 'log-tee') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--log-tee') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fLogTee) then
        begin
          aError := Format(SInvalidBoolValue, ['--log-tee', lValue]);
          Exit(False);
        end;
        aOptions.fHasLogTee := True;
      end else if SameText(lSwitch, 'help') or SameText(lSwitch, 'h') or SameText(lSwitch, '?') then
      begin
        // handled by IsHelpRequested
      end
      else
      begin
        aError := Format(SUnknownArg, [lArg]);
        Exit(False);
      end;
    end else
    begin
      if SameText(lSwitch, 'dproj') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--dproj') then
          Exit(False);
        aOptions.fDprojPath := lValue;
      end else if SameText(lSwitch, 'unit') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--unit') then
          Exit(False);
        aOptions.fUnitPath := lValue;
      end else if SameText(lSwitch, 'out') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--out') then
          Exit(False);
        aOptions.fAnalyzeOutPath := lValue;
        aOptions.fHasAnalyzeOutPath := True;
      end else if SameText(lSwitch, 'fi-formats') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--fi-formats') then
          Exit(False);
        if not TryParseFiFormats(lValue, aOptions.fAnalyzeFiFormats) then
        begin
          aError := Format(SInvalidFiFormats, [lValue]);
          Exit(False);
        end;
      end else if SameText(lSwitch, 'pal') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--pal') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fAnalyzePal) then
        begin
          aError := Format(SInvalidBoolValue, ['--pal', lValue]);
          Exit(False);
        end;
      end else if SameText(lSwitch, 'clean') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--clean') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fAnalyzeClean) then
        begin
          aError := Format(SInvalidBoolValue, ['--clean', lValue]);
          Exit(False);
        end;
      end else if SameText(lSwitch, 'write-summary') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--write-summary') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fAnalyzeWriteSummary) then
        begin
          aError := Format(SInvalidBoolValue, ['--write-summary', lValue]);
          Exit(False);
        end;
      end else if SameText(lSwitch, 'platform') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--platform') then
          Exit(False);
        aOptions.fPlatform := lValue;
      end else if SameText(lSwitch, 'config') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--config') then
          Exit(False);
        aOptions.fConfig := lValue;
      end else if SameText(lSwitch, 'delphi') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--delphi') then
          Exit(False);
        if Pos('.', lValue) = 0 then
          lValue := lValue + '.0';
        aOptions.fDelphiVersion := lValue;
      end else if SameText(lSwitch, 'rsvars') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--rsvars') then
          Exit(False);
        aOptions.fRsVarsPath := lValue;
        aOptions.fHasRsVarsPath := True;
      end else if SameText(lSwitch, 'envoptions') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--envoptions') then
          Exit(False);
        aOptions.fEnvOptionsPath := lValue;
        aOptions.fHasEnvOptionsPath := True;
      end else if SameText(lSwitch, 'settings') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--settings') then
          Exit(False);
        aOptions.fFixSettings := lValue;
        aOptions.fHasFixSettings := True;
      end else if SameText(lSwitch, 'ignore') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--ignore') then
          Exit(False);
        aOptions.fFixIgnore := lValue;
        aOptions.fHasFixIgnore := True;
      end else if SameText(lSwitch, 'silent') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--silent') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fFixSilent) then
        begin
          aError := Format(SInvalidBoolValue, ['--silent', lValue]);
          Exit(False);
        end;
        aOptions.fHasFixSilent := True;
      end else if SameText(lSwitch, 'exclude-path-masks') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--exclude-path-masks') then
          Exit(False);
        aOptions.fExcludePathMasks := lValue;
        aOptions.fHasExcludePathMasks := True;
      end else if SameText(lSwitch, 'ignore-warning-ids') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--ignore-warning-ids') then
          Exit(False);
        aOptions.fIgnoreWarningIds := lValue;
        aOptions.fHasIgnoreWarningIds := True;
      end else if SameText(lSwitch, 'pa-path') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--pa-path') then
          Exit(False);
        aOptions.fPaPath := lValue;
        aOptions.fHasPaPath := True;
      end else if SameText(lSwitch, 'pa-output') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--pa-output') then
          Exit(False);
        aOptions.fPaOutput := lValue;
        aOptions.fHasPaOutput := True;
      end else if SameText(lSwitch, 'pa-args') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--pa-args') then
          Exit(False);
        aOptions.fPaArgs := lValue;
        aOptions.fHasPaArgs := True;
      end else if SameText(lSwitch, 'logfile') then
      begin
        if not TakeValue(True, False, lInlineValue, lHasInlineValue, lValue, '--logfile') then
          Exit(False);
        aOptions.fLogFile := lValue;
        aOptions.fHasLogFile := True;
      end else if SameText(lSwitch, 'log-tee') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--log-tee') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fLogTee) then
        begin
          aError := Format(SInvalidBoolValue, ['--log-tee', lValue]);
          Exit(False);
        end;
        aOptions.fHasLogTee := True;
      end else if SameText(lSwitch, 'verbose') then
      begin
        if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--verbose') then
          Exit(False);
        if not TryParseBool(lValue, aOptions.fVerbose) then
        begin
          aError := Format(SInvalidBoolValue, ['--verbose', lValue]);
          Exit(False);
        end;
      end else if SameText(lSwitch, 'help') or SameText(lSwitch, 'h') or SameText(lSwitch, '?') then
      begin
        // handled by IsHelpRequested
      end
      else
      begin
        aError := Format(SUnknownArg, [lArg]);
        Exit(False);
      end;
    end;
    Inc(lIndex);
  end;

  if aOptions.fCommand = TCommandKind.ckResolve then
  begin
    if aOptions.fDprojPath = '' then
    begin
      aError := Format(SArgMissingValue, ['--dproj']);
      Exit(False);
    end;
    if aOptions.fDelphiVersion = '' then
    begin
      aError := Format(SArgMissingValue, ['--delphi']);
      Exit(False);
    end;
  end else if aOptions.fCommand = TCommandKind.ckAnalyzeProject then
  begin
    if aOptions.fDprojPath = '' then
    begin
      aError := Format(SArgMissingValue, ['--dproj']);
      Exit(False);
    end;
    if aOptions.fDelphiVersion = '' then
      aOptions.fDelphiVersion := '23.0';
  end else if aOptions.fCommand = TCommandKind.ckAnalyzeUnit then
  begin
    if aOptions.fUnitPath = '' then
    begin
      aError := Format(SArgMissingValue, ['--unit']);
      Exit(False);
    end;
  end;

  Result := True;
end;

end.
