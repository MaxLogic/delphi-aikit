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
  aOptions.fPlatform := 'Win32';
  aOptions.fConfig := 'Release';
  aOptions.fOutKind := TOutputKind.okIni;

  lParams := maxCmdLineParams;
  lList := lParams.GetParamList;
  lIndex := 0;
  while lIndex < lList.Count do
  begin
    lArg := lList[lIndex];
    if not TrySplitSwitch(lArg, lParams.SwitchPrefixes, lSwitch, lInlineValue, lHasInlineValue) then
    begin
      aError := Format(SUnknownArg, [lArg]);
      Exit(False);
    end;

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
    end else if SameText(lSwitch, 'run-fixinsight') then
    begin
      if not TakeValue(False, True, lInlineValue, lHasInlineValue, lValue, '--run-fixinsight') then
        Exit(False);
      if not TryParseBool(lValue, aOptions.fRunFixInsight) then
      begin
        aError := Format(SInvalidBoolValue, ['--run-fixinsight', lValue]);
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
    Inc(lIndex);
  end;

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

  Result := True;
end;

end.
